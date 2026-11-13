-- modules/camera.lua - camera
-- FOV, third person, free camera
-- Returns function(ctx); ctx is built by core/ui.lua (shared UI helpers).

return function(ctx)
local locale, player, connect, Players, uiState, RunService, window, UserInputService, gui, pageScroll, tabs, panelWidths, picker, previewPanel, make, corner, colors, animate, previewRow, localize, rowSlider, settingField, closeLanguageMenu, refreshBindValue, bindField, layoutPreview, Loader =
    ctx.locale,
    ctx.player,
    ctx.connect,
    ctx.Players,
    ctx.uiState,
    ctx.RunService,
    ctx.window,
    ctx.UserInputService,
    ctx.gui,
    ctx.pageScroll,
    ctx.tabs,
    ctx.panelWidths,
    ctx.picker,
    ctx.previewPanel,
    ctx.make,
    ctx.corner,
    ctx.colors,
    ctx.animate,
    ctx.previewRow,
    ctx.localize,
    ctx.rowSlider,
    ctx.settingField,
    ctx.closeLanguageMenu,
    ctx.refreshBindValue,
    ctx.bindField,
    ctx.layoutPreview,
    ctx.Loader

-- Camera ---------------------------------------------------------------------
--
-- Three functions in one card, docked to the right of the ESP cards on the
-- visuals tab:
--   * field of view - slider, changes Camera.FieldOfView instead of pulling
--                    the camera back (first person stays first person): the
--                    middle is the game's own FOV, right widens up to the
--                    engine ceiling, left narrows (zoom) down to 1 degree.
--                    The row always shows the FOV that is really applied;
--   * third person - toggle, a preset on top of the slider (base distance +
--                    over-the-shoulder shift, own body made visible);
--   * free camera  - toggle + rebindable key (default F, same capture logic
--                    as the menu key). The character is frozen in place
--                    while the camera flies around.
--
-- Everything lives in its own xpcall closure: it adds nothing to the main
-- chunk's 200-local budget and an error here cannot break the menu or ESP.
-- The camera is written at RenderPriority.Last (ESP is bound one step later).

xpcall(function()
    local Workspace = game:GetService("Workspace")
    local ContextActionService = game:GetService("ContextActionService")
    local clamp = math.clamp
    local WHITE = Color3.new(1, 1, 1)

    -- finder for the first person arms / weapon (core/viewmodel.lua)
    local VM

    if Loader then
        local okVm, module = pcall(Loader.module, "core/viewmodel.lua")

        if okVm and type(module) == "table" then
            VM = module
        end
    end

    local THIRD_DISTANCE = 8.3    -- default: studs behind the head
    local THIRD_SHOULDER = 0.2    -- default: studs to the right
    local THIRD_LIFT = 1.7        -- default: studs up
    local VISIBLE_AT = 1.5        -- body becomes visible past this distance
    local SMOOTH = 8              -- easing speed of zoom / shoulder
    local FREE_SPEED = 40         -- studs per second
    local FREE_BOOST = 3          -- LeftShift multiplier
    local LOOK_SENSITIVITY = 0.009  -- radians per pixel of mouse travel
    local PITCH_LIMIT = math.rad(89)

    -- locale keys live here so the main locale tables stay untouched
    local extra = {
        en = {
            ["cam.panel"] = "camera",
            ["cam.fov"] = "field of view",
            ["cam.fovReset"] = "reset",
            ["cam.third"] = "third person",
            ["cam.thirdX"] = "left / right",
            ["cam.thirdY"] = "up / down",
            ["cam.thirdDist"] = "distance",
            ["cam.free"] = "free camera",
            ["cam.freeKey"] = "camera key",
        },
        ru = {
            ["cam.panel"] = "камера",
            ["cam.fov"] = "поле зрения",
            ["cam.fovReset"] = "сброс",
            ["cam.third"] = "вид от 3 лица",
            ["cam.thirdX"] = "влево / вправо",
            ["cam.thirdY"] = "вверх / вниз",
            ["cam.thirdDist"] = "дистанция",
            ["cam.free"] = "свободная камера",
            ["cam.freeKey"] = "клавиша камеры",
        },
    }

    for language, pack in pairs(extra) do
        for key, text in pairs(pack) do
            locale[language][key] = text
        end
    end

    -- State --------------------------------------------------------------------

    local cfg = {
        fov = 70, fovOn = false, third = false,   -- fov = degrees
        thirdX = THIRD_SHOULDER,   -- studs to the right (negative = left)
        thirdY = THIRD_LIFT,       -- studs up (negative = down)
        thirdDist = THIRD_DISTANCE, -- studs behind the head
    }
    local current, shoulder, lift = 0, 0, 0   -- eased values
    local lastWritten, lastBase              -- guards against re-offsetting
    local freeState
    local paintFree
    local freeKey = Enum.KeyCode.F
    local capturingFree = false

    local bodyParts = {}      -- part -> original LocalTransparencyModifier
    local bodyChar, bodyScan = nil, 0
    local viewParts = {}      -- first person arms / gun parts -> original value
    local viewScan = 0

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.IgnoreWater = true

    -- Helpers ------------------------------------------------------------------

    local function liveCharacter()
        local char = player.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")

        if char and char.Parent and root and root:IsA("BasePart") and hum
            and hum.Health > 0
            and hum:GetState() ~= Enum.HumanoidStateType.Dead then
            return char, root, hum
        end

        return nil
    end

    -- First person hides the body through LocalTransparencyModifier. While the
    -- camera is away from the head the modifier is forced to 0 and the original
    -- values are remembered, so going back to first person restores them.
    local function releaseBody()
        for part, original in pairs(bodyParts) do
            if part.Parent then
                part.LocalTransparencyModifier = original
            end
        end

        for part, original in pairs(viewParts) do
            if part.Parent then
                part.LocalTransparencyModifier = original
            end
        end

        table.clear(bodyParts)
        table.clear(viewParts)
        bodyChar = nil
    end

    -- The first person arms and gun are a model the game keeps under the
    -- camera and glues to it every frame, so they follow a camera that is
    -- pulled back and float in front of it. While the real body is shown they
    -- are made invisible (and restored together with the body).
    local function hideViewModel(now)
        local cam = Workspace.CurrentCamera

        if cam and now - viewScan > 0.25 then
            viewScan = now

            local found = VM and VM.parts(cam, now)

            if found then
                for _, item in ipairs(found) do
                    if viewParts[item] == nil then
                        viewParts[item] = item.LocalTransparencyModifier
                    end
                end
            else
                for _, child in ipairs(cam:GetChildren()) do
                    if child:IsA("Model") then
                        for _, item in ipairs(child:GetDescendants()) do
                            if item:IsA("BasePart") and viewParts[item] == nil then
                                viewParts[item] = item.LocalTransparencyModifier
                            end
                        end
                    end
                end
            end
        end

        for part in pairs(viewParts) do
            if part.Parent then
                if part.LocalTransparencyModifier ~= 1 then
                    part.LocalTransparencyModifier = 1
                end
            else
                viewParts[part] = nil
            end
        end
    end

    -- Some games keep their own visible copy of our avatar next to the real
    -- (hidden, raw) player.Character. Forcing the REAL character visible then
    -- shows a body the game never poses for the camera - it stands in its raw
    -- orientation, sideways. When such a copy exists, it is the body that gets
    -- shown instead of player.Character.
    local copyHumanoids = {}
    local copyReady = false
    local ownCopy, ownCopyAt = nil, 0

    local function noteHumanoid(item)
        if item:IsA("Humanoid") then
            local model = item.Parent

            if model and model:IsA("Model") then
                copyHumanoids[model] = item
            end
        end
    end

    local function ensureCopyScan()
        if copyReady then
            return
        end

        copyReady = true

        connect(Workspace.DescendantAdded, noteHumanoid)

        connect(Workspace.DescendantRemoving, function(item)
            if item:IsA("Humanoid") and copyHumanoids[item.Parent] == item then
                copyHumanoids[item.Parent] = nil
            end
        end)

        for _, item in ipairs(Workspace:GetDescendants()) do
            noteHumanoid(item)
        end
    end

    local function findOwnCopy(char, rootPart)
        local now = os.clock()

        if now - ownCopyAt < 0.5 then
            return ownCopy and ownCopy.Parent and ownCopy or nil
        end

        ownCopyAt = now
        ownCopy = nil
        ensureCopyScan()

        local cam = Workspace.CurrentCamera

        for model, humanoid in pairs(copyHumanoids) do
            if model ~= char
                and model.Parent
                and not model:IsDescendantOf(char)
                and not char:IsDescendantOf(model)
                and not (cam and model:IsDescendantOf(cam))
                and not Players:GetPlayerFromCharacter(model) then
                local root = humanoid.RootPart
                    or model:FindFirstChild("HumanoidRootPart")
                    or model.PrimaryPart

                if model.Name == player.Name
                    or (root and rootPart
                        and (root.Position - rootPart.Position).Magnitude < 1.25) then
                    ownCopy = model
                    break
                end
            end
        end

        return ownCopy
    end

    local function showBody(char, show, keepView)
        if not show then
            if keepView then
                -- free camera next to the body: the body stays as the game
                -- draws it, but the view model (arms + weapon glued to the
                -- camera) must not be drawn in front of a free camera
                for part, original in pairs(bodyParts) do
                    if part.Parent then
                        part.LocalTransparencyModifier = original
                    end
                end

                table.clear(bodyParts)
                bodyChar = nil
                hideViewModel(os.clock())
            elseif next(bodyParts) ~= nil or next(viewParts) ~= nil then
                releaseBody()
            end

            return
        end

        local now = os.clock()

        if bodyChar ~= char then
            -- another model is shown now (own copy <-> real character): give
            -- the previous one its original transparency back first
            for part, original in pairs(bodyParts) do
                if part.Parent then
                    part.LocalTransparencyModifier = original
                end
            end

            table.clear(bodyParts)
            bodyChar = char
            bodyScan = 0
        end

        if now - bodyScan > 1 then
            bodyScan = now

            for _, item in ipairs(char:GetDescendants()) do
                if item:IsA("BasePart") and bodyParts[item] == nil then
                    bodyParts[item] = item.LocalTransparencyModifier
                end
            end
        end

        for part in pairs(bodyParts) do
            if part.Parent and part.LocalTransparencyModifier ~= 0 then
                part.LocalTransparencyModifier = 0
            end
        end

        hideViewModel(now)
    end

    -- Walls are cover, invisible parts and other characters are not.
    local function clip(from, to, char)
        local direction = to - from

        if direction.Magnitude < 0.01 then
            return to
        end

        local filter = { char }

        for _ = 1, 4 do
            rayParams.FilterDescendantsInstances = filter

            local hit = Workspace:Raycast(from, direction, rayParams)

            if not hit then
                return to
            end

            local part = hit.Instance
            local model = part:FindFirstAncestorOfClass("Model")
            local human = model and model:FindFirstChildOfClass("Humanoid")
                and model

            if part:IsA("Terrain") then
                return from + direction.Unit * math.max(0, hit.Distance - 0.4)
            elseif human then
                filter[#filter + 1] = human
            elseif part.Transparency >= 0.9 then
                filter[#filter + 1] = part
            else
                return from + direction.Unit * math.max(0, hit.Distance - 0.4)
            end
        end

        return from
    end

    -- Field of view -------------------------------------------------------------
    --
    -- The slider is an ABSOLUTE field of view in degrees (1 - 120, the range the
    -- engine allows) and it applies at once. Nothing is derived from the game's
    -- own value any more: a game that eases the FOV from its current value used
    -- to feed our own write back as "the game's FOV" and the old relative
    -- slider drifted up to 120 and stopped responding.
    --
    -- Until the slider is touched nothing is written at all; "reset" hands the
    -- property back to the game. The write happens late (RenderPriority.Last - 1,
    -- before the aimbot and the ESP) and is repeated at once if the game
    -- overwrites it later in the same frame, so the picture, the aim and the
    -- boxes all use the same value.

    local FOV_MIN = 1
    local FOV_LIMIT = 120
    local FOV_STEP = "ShitaroFov"
    local FOV_FIXES = 3          -- re-asserts per frame, a fight guard

    local fovGame                -- the game's own FOV, tracked while we do not write
    local fovWritten             -- last value we wrote (nil: the game owns it)
    local fovBusy = false
    local fovFixes = 0
    local fovCam, fovLink

    local function writeFov(cam, value)
        fovBusy = true
        cam.FieldOfView = value
        fovBusy = false
        fovWritten = value
    end

    local function applyFov(cam)
        local value = cam.FieldOfView

        if not cfg.fovOn then
            if fovWritten then
                -- reset: give the game's value back once
                if fovGame then
                    writeFov(cam, fovGame)
                end

                fovWritten = nil
            else
                fovGame = value
            end

            return
        end

        if not fovGame then
            fovGame = value
        end

        local target = clamp(cfg.fov, FOV_MIN, FOV_LIMIT)

        if math.abs(value - target) > 0.001 then
            writeFov(cam, target)
        else
            fovWritten = target
        end
    end

    local function trackFovCam(cam)
        if cam == fovCam then
            return
        end

        if fovLink then
            fovLink:Disconnect()
            fovLink = nil
        end

        fovCam = cam

        fovLink = cam:GetPropertyChangedSignal("FieldOfView"):Connect(function()
            if fovBusy or not cfg.fovOn or uiState.closed then
                return
            end

            if fovFixes >= FOV_FIXES then
                return
            end

            local target = clamp(cfg.fov, FOV_MIN, FOV_LIMIT)

            if math.abs(cam.FieldOfView - target) > 0.001 then
                fovFixes = fovFixes + 1
                writeFov(cam, target)
            end
        end)
    end

    local function fovFrame()
        if uiState.closed then
            return
        end

        local cam = Workspace.CurrentCamera

        if not cam then
            return
        end

        fovFixes = 0
        trackFovCam(cam)
        applyFov(cam)
    end

    pcall(function()
        RunService:UnbindFromRenderStep(FOV_STEP)
    end)

    if not pcall(function()
        RunService:BindToRenderStep(
            FOV_STEP,
            Enum.RenderPriority.Last.Value - 1,
            fovFrame
        )
    end) then
        connect(RunService.RenderStepped, fovFrame)
    end

    -- hands the FOV back to the game when the cheat is shut down
    local function restoreFov()
        pcall(function()
            RunService:UnbindFromRenderStep(FOV_STEP)
        end)

        if fovLink then
            fovLink:Disconnect()
            fovLink = nil
        end

        local cam = Workspace.CurrentCamera

        if cam and fovWritten and fovGame then
            cam.FieldOfView = fovGame
        end

        fovWritten, fovCam = nil, nil
    end

    -- Third person --------------------------------------------------------------

    -- The third person camera is pinned to the CHARACTER, not to the camera's
    -- own previous position. Offsetting the previous camera made the offset and
    -- the aimbot feed each ther: the aim turned the camera, the turned camera
    -- moved the offset, the moved offset changed the aim, and the view ended up
    -- circling the player and looking straight back at him.
    local function thirdPersonPoint(anchor, look, right, distance, shoulder, up)
        return anchor - look * distance + right * shoulder
            + Vector3.new(0, up, 0)
    end

    local function applyOffset(cam, char, dt)
        local targetDistance = cfg.third and cfg.thirdDist or 0
        local targetShoulder = cfg.third and cfg.thirdX or 0
        local targetLift = cfg.third and cfg.thirdY or 0
        local k = math.min(1, dt * SMOOTH)

        current = current + (targetDistance - current) * k
        shoulder = shoulder + (targetShoulder - shoulder) * k
        lift = lift + (targetLift - lift) * k

        if math.abs(targetDistance - current) < 0.02 then
            current = targetDistance
        end

        if math.abs(targetShoulder - shoulder) < 0.02 then
            shoulder = targetShoulder
        end

        if math.abs(targetLift - lift) < 0.02 then
            lift = targetLift
        end

        if math.abs(current) < 0.001
            and math.abs(shoulder) < 0.001
            and math.abs(lift) < 0.001 then
            lastWritten, lastBase = nil, nil
            showBody(char, false)
            return
        end

        local cf = cam.CFrame
        local head = char:FindFirstChild("Head")
        local rootPart = char:FindFirstChild("HumanoidRootPart")
            or char.PrimaryPart
        local anchor = head and head.Position
            or (rootPart and rootPart.Position + Vector3.new(0, 1.5, 0))

        if not anchor then
            return
        end

        -- The offset is measured from the HEAD, along the camera's own view.
        -- The old code offset the camera's previous position instead, so every
        -- frame pushed it another six studs back and the view ran away. Anchor
        -- plus view means the camera is always exactly THIRD_DISTANCE behind
        -- the head, whichever way the view is turned.
        local desired = thirdPersonPoint(
            anchor,
            cf.LookVector,
            cf.RightVector,
            current,
            shoulder,
            lift
        )
        local final = clip(anchor, desired, char)

        lastBase = cf
        cam.CFrame = cf - cf.Position + final
        lastWritten = cam.CFrame

        showBody(
            findOwnCopy(char, rootPart) or char,
            current > VISIBLE_AT
        )
    end

    -- Body report ---------------------------------------------------------------
    -- getgenv().shitaro_body() in the executor, third person ON: copies to the
    -- clipboard how the body is oriented against the camera and whether the
    -- game keeps a copy of the avatar.

    local function yawOf(cf)
        local look = cf.LookVector

        return math.deg(math.atan2(-look.X, -look.Z))
    end

    local function yawDiff(a, b)
        return (a - b + 180) % 360 - 180
    end

    local function bodyReport()
        local cam = Workspace.CurrentCamera
        local char, root, hum = liveCharacter()
        local out = {}

        if not char or not cam then
            out[#out + 1] = "no live character"
        else
            local camYaw = yawOf(cam.CFrame)

            out[#out + 1] = string.format(
                "third=%s camYaw=%.0f autoRotate=%s",
                tostring(cfg.third), camYaw, tostring(hum.AutoRotate)
            )

            out[#out + 1] = string.format(
                "root yaw diff vs camera: %.0f", yawDiff(yawOf(root.CFrame), camYaw)
            )

            for _, name in ipairs({ "LowerTorso", "UpperTorso", "Torso", "Head" }) do
                local part = char:FindFirstChild(name)

                if part and part:IsA("BasePart") then
                    out[#out + 1] = string.format(
                        "%s yaw diff: %.0f  localTransparency=%.2f",
                        name, yawDiff(yawOf(part.CFrame), camYaw),
                        part.LocalTransparencyModifier
                    )
                end
            end

            local joint = char:FindFirstChild("RootJoint", true)

            if joint and joint:IsA("Motor6D") then
                local _, c0y = joint.C0:ToOrientation()
                local _, ty = joint.Transform:ToOrientation()

                out[#out + 1] = string.format(
                    "RootJoint C0 yaw=%.0f Transform yaw=%.0f",
                    math.deg(c0y), math.deg(ty)
                )
            end

            local copy = findOwnCopy(char, root)

            if copy then
                local copyRoot = copy:FindFirstChild("HumanoidRootPart")
                    or copy.PrimaryPart
                local sample = copy:FindFirstChildWhichIsA("BasePart", true)

                out[#out + 1] = "OWN COPY: " .. copy:GetFullName()

                if copyRoot then
                    out[#out + 1] = string.format(
                        "copy root yaw diff vs camera: %.0f",
                        yawDiff(yawOf(copyRoot.CFrame), camYaw)
                    )
                end

                if sample then
                    out[#out + 1] = string.format(
                        "copy part %s transparency=%.2f localTransparency=%.2f",
                        sample.Name, sample.Transparency,
                        sample.LocalTransparencyModifier
                    )
                end
            else
                out[#out + 1] = "no own copy found"
            end
        end

        local text = table.concat(out, "\n")

        warn("[shitaro/body]\n" .. text)
        pcall(function()
            setclipboard(text)
        end)
    end

    pcall(function()
        getgenv().shitaro_body = bodyReport
    end)

    -- Free camera --------------------------------------------------------------

    local SINK_NAME = "ShitaroFreecamSink"
    local SINK_PRIORITY = Enum.ContextActionPriority.High.Value + 500

    -- keeps the game from seeing these while the camera is free
    local SINK_INPUTS = {
        Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D,
        Enum.KeyCode.Q, Enum.KeyCode.E, Enum.KeyCode.Space,
        Enum.KeyCode.LeftShift, Enum.KeyCode.LeftControl,
        Enum.UserInputType.MouseButton1, Enum.UserInputType.MouseButton2,
        Enum.UserInputType.MouseWheel, Enum.UserInputType.MouseMovement,
    }

    local function sinkInput()
        return Enum.ContextActionResult.Sink
    end

    -- The sink above only stops games that read input through
    -- ContextActionService. Shooting also goes through plain input events,
    -- polling and remotes, so while the camera is free:
    --   * equipped Tools are put away (and the first one is equipped again
    --     when the camera comes back);
    --   * the game's weapon remotes are swallowed and "is the mouse button
    --     held" answers no (needs hookmetamethod; skipped without it).
    -- Calls made by this script itself are never touched.
    local blockGame = false
    local hookInstalled = false

    local FIRE_WORDS = {
        "shoot", "fire", "attack", "hit", "damage", "bullet", "reload",
        "melee", "swing", "weapon", "gun", "shot", "projectile", "throw",
        "grenade", "ability", "slash", "stab", "punch", "kick",
    }

    local function weaponRemote(name)
        name = name:lower()

        for _, word in ipairs(FIRE_WORDS) do
            if name:find(word, 1, true) then
                return true
            end
        end

        return false
    end

    local function installBlockHook()
        if hookInstalled or type(hookmetamethod) ~= "function"
            or type(getnamecallmethod) ~= "function" then
            return
        end

        local old
        local wrap = newcclosure or function(fn)
            return fn
        end

        hookInstalled = pcall(function()
            old = hookmetamethod(game, "__namecall", wrap(function(self, ...)
                if blockGame then
                    local method = getnamecallmethod()

                    if not (checkcaller and checkcaller()) then
                        if method == "FireServer" or method == "InvokeServer" then
                            local okName, name = pcall(function()
                                return self.Name
                            end)

                            if okName and type(name) == "string"
                                and weaponRemote(name) then
                                return nil
                            end
                        elseif method == "IsMouseButtonPressed" then
                            return false
                        end
                    end
                end

                return old(self, ...)
            end))
        end)
    end

    local function disableFree()
        local fs = freeState

        if not fs then
            return
        end

        freeState = nil
        uiState.freeCamera = false
        blockGame = false

        pcall(function()
            ContextActionService:UnbindAction(SINK_NAME)
        end)

        if fs.beat then
            fs.beat:Disconnect()
        end

        local root = fs.root

        if root and root.Parent then
            root.CFrame = fs.rootCF
            root.Anchored = fs.anchored
        end

        if fs.hum and fs.hum.Parent and fs.hum.WalkSpeed == 0 then
            fs.hum.WalkSpeed = fs.walk
        end

        local cam = Workspace.CurrentCamera

        if cam then
            cam.CameraType = fs.camType
            cam.CameraSubject = fs.subject
            cam.CFrame = fs.camCF
        end

        if not window.Visible then
            pcall(function()
                UserInputService.MouseBehavior = fs.mouse
            end)
        end

        -- bring back the weapon that was put away
        if fs.tools and fs.tools[1] and fs.hum and fs.hum.Parent then
            pcall(function()
                if fs.tools[1].Parent then
                    fs.hum:EquipTool(fs.tools[1])
                end
            end)
        end

        releaseBody()
        lastWritten, lastBase = nil, nil

        if paintFree then
            pcall(paintFree, false)
        end
    end

    local function enableFree()
        if freeState then
            return
        end

        local cam = Workspace.CurrentCamera
        local char, root, hum = liveCharacter()

        if not cam or not char then
            return
        end

        local cf = cam.CFrame
        local look = cf.LookVector

        local fs = {
            char = char,
            root = root,
            hum = hum,
            rootCF = root.CFrame,
            anchored = root.Anchored,
            walk = hum.WalkSpeed,
            camType = cam.CameraType,
            subject = cam.CameraSubject,
            camCF = cf,
            mouse = UserInputService.MouseBehavior,
            pos = cf.Position,
            yaw = math.atan2(-look.X, -look.Z),
            pitch = math.asin(clamp(look.Y, -1, 1)),
        }

        freeState = fs
        uiState.freeCamera = true
        blockGame = true
        installBlockHook()

        -- put the weapon away so it cannot be fired from the free camera
        fs.tools = {}

        pcall(function()
            for _, item in ipairs(char:GetChildren()) do
                if item:IsA("Tool") then
                    fs.tools[#fs.tools + 1] = item
                end
            end

            if #fs.tools > 0 then
                hum:UnequipTools()
            end
        end)

        pcall(function()
            ContextActionService:UnbindAction(SINK_NAME)
        end)

        pcall(function()
            ContextActionService:BindActionAtPriority(
                SINK_NAME,
                sinkInput,
                false,
                SINK_PRIORITY,
                table.unpack(SINK_INPUTS)
            )
        end)

        -- the character stays exactly where it is: no physics, no writes
        root.Anchored = true
        hum.WalkSpeed = 0
        cam.CameraType = Enum.CameraType.Scriptable
        lastWritten, lastBase = nil, nil

        -- the game rotates the character itself (AutoRotate is off), so the
        -- pose is pinned again on every physics step as well
        fs.beat = RunService.Heartbeat:Connect(function()
            if freeState == fs and root.Parent
                and root.CFrame ~= fs.rootCF then
                root.CFrame = fs.rootCF
            end
        end)
    end

    local function setFree(on)
        if on then
            enableFree()
        else
            disableFree()
        end

        if paintFree then
            paintFree(freeState ~= nil)
        end
    end

    local function isDown(key)
        return UserInputService:IsKeyDown(key)
    end

    local function stepFree(cam, dt)
        local fs = freeState
        local root = fs.root

        if root.CFrame ~= fs.rootCF then
            root.CFrame = fs.rootCF
        end

        if not root.Anchored then
            root.Anchored = true
        end

        if cam.CameraType ~= Enum.CameraType.Scriptable then
            cam.CameraType = Enum.CameraType.Scriptable
        end

        -- menu open: the pointer belongs to the menu, the camera holds still
        if not window.Visible then
            if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
                UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
            end

            local delta = UserInputService:GetMouseDelta()
            local sensitivity = LOOK_SENSITIVITY
                * UserInputService.MouseDeltaSensitivity

            fs.yaw = fs.yaw - delta.X * sensitivity
            fs.pitch = clamp(
                fs.pitch - delta.Y * sensitivity,
                -PITCH_LIMIT,
                PITCH_LIMIT
            )

            local x, y, z = 0, 0, 0

            if isDown(Enum.KeyCode.W) then z = z - 1 end
            if isDown(Enum.KeyCode.S) then z = z + 1 end
            if isDown(Enum.KeyCode.A) then x = x - 1 end
            if isDown(Enum.KeyCode.D) then x = x + 1 end
            if isDown(Enum.KeyCode.Space) or isDown(Enum.KeyCode.E) then
                y = y + 1
            end
            if isDown(Enum.KeyCode.LeftControl) or isDown(Enum.KeyCode.Q) then
                y = y - 1
            end

            local rotation = CFrame.Angles(0, fs.yaw, 0)
                * CFrame.Angles(fs.pitch, 0, 0)

            local direction = rotation:VectorToWorldSpace(Vector3.new(x, 0, z))
                + Vector3.new(0, y, 0)

            if direction.Magnitude > 0 then
                local speed = FREE_SPEED
                    * (isDown(Enum.KeyCode.LeftShift) and FREE_BOOST or 1)

                fs.pos = fs.pos + direction.Unit * speed * dt
            end
        end

        cam.CFrame = CFrame.new(fs.pos)
            * CFrame.Angles(0, fs.yaw, 0)
            * CFrame.Angles(fs.pitch, 0, 0)

        showBody(fs.char, (fs.pos - root.Position).Magnitude > 3, true)
    end

    -- Frame step ---------------------------------------------------------------

    local function step(dt)
        if uiState.closed then
            return
        end

        local cam = Workspace.CurrentCamera

        if not cam then
            return
        end

        dt = math.min(dt, 0.1)

        if VM then
            VM.sample(cam, os.clock())
        end

        local char = liveCharacter()

        if freeState then
            if char and char == freeState.char then
                stepFree(cam, dt)
                return
            end

            -- died, respawned or left: hand the camera back
            disableFree()
        end

        if not char then
            releaseBody()
            lastWritten, lastBase = nil, nil
            return
        end

        applyOffset(cam, char, dt)
    end

    local stepName = "ShitaroCamera"

    pcall(function()
        RunService:UnbindFromRenderStep(stepName)
    end)

    -- One tick after the game's camera script (200) and BEFORE the aim (Last).
    -- The third person offset therefore always works from the view the game
    -- produced, never from a view the aimbot just wrote - so the two can never
    -- move each other - and the aimbot aims from the camera position that is
    -- already offset, which is what keeps the crosshair on the target instead
    -- of a few degrees left of it (parallax of the shoulder offset).
    local bound = pcall(function()
        RunService:BindToRenderStep(
            stepName,
            Enum.RenderPriority.Camera.Value + 1,
            step
        )
    end)

    if not bound then
        connect(RunService.RenderStepped, step)
    end

    -- not registered through connect(): that list is disconnected first
    gui.Destroying:Connect(function()
        pcall(disableFree)
        pcall(releaseBody)
        pcall(restoreFov)

        pcall(function()
            getgenv().shitaro_body = nil
        end)

        pcall(function()
            RunService:UnbindFromRenderStep(stepName)
        end)

        pcall(function()
            ContextActionService:UnbindAction(SINK_NAME)
        end)
    end)

    -- Menu: card on the right of the visuals tab -------------------------------
    --
    -- A second scroll frame of its own: the ESP cards keep their layout, and
    -- layoutPreview places this card like any other (column width 330). It sits
    -- in the top right corner of the tab, where the colour-squares hint used to
    -- be, so the whole right column is the camera card.

    local camScroll = pageScroll(tabs[3].page, "CameraScroll")
    camScroll.Position = UDim2.fromOffset(430, 14)
    camScroll.Size = UDim2.new(0, 350, 1, -24)
    panelWidths[camScroll] = 330

    -- the colour editor is docked over this area: hide the card while it is open
    if picker.panel then
        camScroll.Visible = not picker.panel.Visible

        connect(picker.panel:GetPropertyChangedSignal("Visible"), function()
            camScroll.Visible = not picker.panel.Visible
        end)
    end

    local camCard = previewPanel(camScroll, "cam.panel", 1, 7)

    local function addToggle(frame, onClick)
        local track = make("Frame", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -12, 0.5, 0),
            Size = UDim2.fromOffset(26, 14),
            BackgroundColor3 = WHITE,
            BackgroundTransparency = 0.86,
            ZIndex = 2,
        }, frame)

        corner(track, UDim.new(1, 0))

        local knob = make("Frame", {
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 2, 0.5, 0),
            Size = UDim2.fromOffset(10, 10),
            BackgroundColor3 = colors.sub,
            BackgroundTransparency = 0.15,
            ZIndex = 3,
        }, track)

        corner(knob, UDim.new(1, 0))

        local hit = make("TextButton", {
            Size = UDim2.fromScale(1, 1),
            ZIndex = 5,
        }, frame)

        connect(hit.Activated, onClick)

        return function(state)
            animate(track, {
                BackgroundColor3 = state and colors.accent or WHITE,
                BackgroundTransparency = state and 0.35 or 0.86,
            })

            animate(knob, {
                Position = UDim2.new(0, state and 14 or 2, 0.5, 0),
                BackgroundColor3 = state and colors.accent or colors.sub,
            })
        end
    end

    -- 1: field of view, absolute degrees. The slider only starts writing once
    -- it is dragged; "reset" gives the property back to the game.
    local fovRow, fovLabel = previewRow(camCard, 1, "", true)
    localize(fovLabel, "cam.fov")

    local fovSlider = rowSlider(
        fovRow,
        "CameraFov",
        FOV_MIN,
        FOV_LIMIT,
        function(value)
            return tostring(math.floor(value + 0.5)) .. "°"
        end,
        function(value)
            cfg.fov = math.floor(value + 0.5)
            cfg.fovOn = true
        end
    )

    local function gameFov()
        local cam = Workspace.CurrentCamera

        return fovGame or (cam and cam.FieldOfView) or 70
    end

    fovSlider.set(gameFov(), false)

    local fovReset = make("TextButton", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0.48, -56, 0.5, 0),
        Size = UDim2.fromOffset(50, 18),
        BackgroundColor3 = WHITE,
        BackgroundTransparency = 0.93,
        TextSize = 11,
        TextColor3 = colors.sub,
        TextXAlignment = Enum.TextXAlignment.Center,
        ZIndex = 5,
    }, fovRow)

    corner(fovReset, UDim.new(0, 6))
    localize(fovReset, "cam.fovReset")

    connect(fovReset.Activated, function()
        cfg.fovOn = false
        fovSlider.set(gameFov(), false)
    end)

    -- 2: third person
    local thirdRow, thirdLabel = previewRow(camCard, 2, "", true)
    localize(thirdLabel, "cam.third")

    local paintThird

    paintThird = addToggle(thirdRow, function()
        cfg.third = not cfg.third
        paintThird(cfg.third)
    end)

    -- 3-5: where the third person camera sits (works while third person is on)
    local function thirdSlider(index, labelKey, name, minValue, maxValue, field)
        local sliderRow, sliderLabel = previewRow(camCard, index, "", true)
        localize(sliderLabel, labelKey)

        local slider = rowSlider(
            sliderRow,
            name,
            minValue,
            maxValue,
            function(value)
                return string.format("%.1f", value)
            end,
            function(value)
                cfg[field] = math.floor(value * 10 + 0.5) / 10
            end
        )

        slider.set(cfg[field], false)

        return slider
    end

    thirdSlider(3, "cam.thirdX", "ThirdX", -10, 10, "thirdX")
    thirdSlider(4, "cam.thirdY", "ThirdY", -6, 10, "thirdY")
    thirdSlider(5, "cam.thirdDist", "ThirdDist", 0, 25, "thirdDist")

    -- 6: free camera
    local freeRow, freeLabel = previewRow(camCard, 6, "", true)
    localize(freeLabel, "cam.free")

    paintFree = addToggle(freeRow, function()
        setFree(freeState == nil)
    end)

    -- 7: free camera key, same capture logic as the menu key
    local keyRow, keyLabel = previewRow(camCard, 7, "", true)
    localize(keyLabel, "cam.freeKey")

    local keyField, keyValue = settingField(keyRow)

    local function refreshKey()
        keyValue.Text = capturingFree and "..." or freeKey.Name
    end

    refreshKey()

    -- one capture at a time: starting this one cancels the menu key capture
    local function beginFreeCapture()
        closeLanguageMenu()
        ctx.setCapturingBind(false)
        refreshBindValue()
        capturingFree = true
        refreshKey()
    end

    connect(keyField.Activated, function()
        if capturingFree then
            capturingFree = false
            refreshKey()
            return
        end

        beginFreeCapture()
    end)

    connect(keyField.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton2 then
            beginFreeCapture()
        end
    end)

    -- ...and starting the menu key capture cancels this one
    local function cancelFreeCapture()
        if capturingFree then
            capturingFree = false
            refreshKey()
        end
    end

    connect(bindField.Activated, cancelFreeCapture)

    connect(bindField.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton2 then
            cancelFreeCapture()
        end
    end)

    connect(UserInputService.InputBegan, function(input)
        if input.UserInputType ~= Enum.UserInputType.Keyboard then
            return
        end

        if capturingFree then
            if input.KeyCode == ctx.getBindKey() then
                -- the menu key is taken: abort (the menu handles the press)
                capturingFree = false
                refreshKey()
            elseif input.KeyCode ~= Enum.KeyCode.Unknown then
                freeKey = input.KeyCode
                capturingFree = false
                refreshKey()
            end

            return
        end

        if ctx.isCapturingBind()
            or UserInputService:GetFocusedTextBox()
            or input.KeyCode == ctx.getBindKey() then
            return
        end

        if input.KeyCode == freeKey then
            setFree(freeState == nil)
        end
    end)

    layoutPreview()
end, function(err)
    warn("[shitaro/camera] " .. debug.traceback(tostring(err), 2))
end)
end
