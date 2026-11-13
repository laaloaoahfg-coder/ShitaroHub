-- modules/aim.lua - aimbot
-- aim tab, targeting, FOV circle
-- Returns function(ctx); ctx is built by core/ui.lua (shared UI helpers).

return function(ctx)
local locale, playerGui, make, corner, colors, player, uiState, connect, RunService, gui, panelWidths, previewScroll, window, PANEL_RESERVE, previewPanel, panelGapBefore, animate, previewRow, localize, rowSlider, layoutPreview =
    ctx.locale,
    ctx.playerGui,
    ctx.make,
    ctx.corner,
    ctx.colors,
    ctx.player,
    ctx.uiState,
    ctx.connect,
    ctx.RunService,
    ctx.gui,
    ctx.panelWidths,
    ctx.previewScroll,
    ctx.window,
    ctx.PANEL_RESERVE,
    ctx.previewPanel,
    ctx.panelGapBefore,
    ctx.animate,
    ctx.previewRow,
    ctx.localize,
    ctx.rowSlider,
    ctx.layoutPreview

-- Aimbot ---------------------------------------------------------------------
--
-- Lives in its own xpcall closure like the ESP and camera sections: it adds
-- nothing to the chunk's 200-local budget and a failure here can never break the
-- menu. The third-person offset is applied first (RenderPriority.Camera + 1),
-- the aim is written last (RenderPriority.Last) and measures its direction from
-- the offset camera position. That order fixes both third-person problems at
-- once: the offset never sees the aim (so the view cannot circle the player)
-- and the aim never guesses where the camera will be (so the crosshair is on
-- the target instead of a few degrees to the left of it).
--
-- Target point is read from the live parts every frame (head / neck / body /
-- legs), so a crouching, jumping or animating target is tracked by its current
-- pose - no cached coordinates are ever reused.

xpcall(function()
    local Workspace = game:GetService("Workspace")
    local Players = game:GetService("Players")
    local UserInputService = game:GetService("UserInputService")
    local clamp = math.clamp

    -- the ESP range slider uses metres too (1 stud = 0.28 m)
    local STUDS_TO_M = 0.28

    -- the aimbot circle is measured in pixels at this screen height and scaled
    -- to the real viewport, so the setting means the same thing on any monitor
    local AIM_REFERENCE = 1080

    -- Build-independent tuning lives here. These are screen/range limits,
    -- not projectile speeds, offsets, or game-specific hitbox assumptions.
    local LIMITS = {
        circleMin = 1, circleMax = 500,
        rangeMin = 1, rangeMax = 800,
        smoothMin = 0, smoothMax = 10,
        sightPasses = 8,
    }

    -- smoothing 1..10: how fast the camera swings, in "convergence per second"
    local SPEED_FAST = 42
    local SPEED_RATIO = 0.62
    local SPEED_FLOOR = 1.6

    local cfg = {
        enabled = false,
        visible = true,      -- needs line of sight
        ignoreBots = true,
        ignoreTeam = true,
        shootOnly = false,   -- false = aim all the time
        smooth = 0,         -- 0 = exact live-part tracking; 1..10 = smoothing
        fov = 240,           -- circle radius, pixels at AIM_REFERENCE
        range = 800,         -- metres; streamed/replicated parts are required
        part = "head",       -- head | neck | body | legs
    }

    local PARTS = {
        { "head", "aim.part.head" },
        { "neck", "aim.part.neck" },
        { "body", "aim.part.body" },
        { "legs", "aim.part.legs" },
    }

    -- locale keys live here so the main locale tables stay untouched
    local extra = {
        en = {
            ["aim.panel"] = "aimbot",
            ["aim.filters"] = "targets",
            ["aim.tuning"] = "tuning",
            ["aim.enabled"] = "aimbot",
            ["aim.visible"] = "visibility check",
            ["aim.shootOnly"] = "only while shooting",
            ["aim.part"] = "target part",
            ["aim.part.head"] = "head",
            ["aim.part.neck"] = "neck",
            ["aim.part.body"] = "body",
            ["aim.part.legs"] = "legs",
            ["aim.ignoreBots"] = "ignore bots",
            ["aim.ignoreTeam"] = "ignore teammates",
            ["aim.smooth"] = "smoothing",
            ["aim.fov"] = "aimbot circle",
            ["aim.range"] = "max distance",
        },
        ru = {
            ["aim.panel"] = "аимбот",
            ["aim.filters"] = "цели",
            ["aim.tuning"] = "настройки",
            ["aim.enabled"] = "аимбот",
            ["aim.visible"] = "проверка видимости",
            ["aim.shootOnly"] = "только при стрельбе",
            ["aim.part"] = "часть тела",
            ["aim.part.head"] = "голова",
            ["aim.part.neck"] = "шея",
            ["aim.part.body"] = "тело",
            ["aim.part.legs"] = "ноги",
            ["aim.ignoreBots"] = "игнорировать ботов",
            ["aim.ignoreTeam"] = "игнорировать тиммейтов",
            ["aim.smooth"] = "плавность",
            ["aim.fov"] = "круг аимбота",
            ["aim.range"] = "дальность",
        },
    }

    for language, pack in pairs(extra) do
        for key, text in pairs(pack) do
            locale[language][key] = text
        end
    end

    -- Overlay: the aimbot circle ---------------------------------------------

    local stale = playerGui:FindFirstChild("ShitaroAim")

    if stale then
        stale:Destroy()
    end

    local overlay = make("ScreenGui", {
        Name = "ShitaroAim",
        IgnoreGuiInset = true,
        ResetOnSpawn = false,
        ScreenInsets = Enum.ScreenInsets.None,
        ClipToDeviceSafeArea = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 9100,
    }, playerGui)

    local ring = make("Frame", {
        Name = "FovCircle",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(240, 240),
        BackgroundTransparency = 1,
        Visible = false,
    }, overlay)

    corner(ring, UDim.new(1, 0))

    make("UIStroke", {
        Color = colors.accent,
        Transparency = 0.45,
        Thickness = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, ring)

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.IgnoreWater = true

    -- Aimbot: targeting logic -------------------------------------------------

    local partCache = setmetatable({}, { __mode = "k" })
    local botModels = {}
    local botLinks = {}

    local current          -- the target we keep locked
    local candidates = {}  -- reused every frame

    -- Prone/crouch systems may use Physics, Ragdoll or PlatformStand on a
    -- LIVING character. A pose is not proof of death: use health, Dead state
    -- and explicit death flags instead.
    local function isAlive(char)
        local humanoid = char and char:FindFirstChildOfClass("Humanoid")

        if not humanoid or not humanoid.Parent or humanoid.Health <= 0
            or humanoid:GetState() == Enum.HumanoidStateType.Dead then
            return nil
        end

        if char:GetAttribute("Dead") == true
            or char:GetAttribute("IsDead") == true
            or humanoid:GetAttribute("Dead") == true
            or humanoid:GetAttribute("IsDead") == true then
            return nil
        end

        return humanoid
    end

    local function part(char, name)
        local found = char:FindFirstChild(name)
        return found and found:IsA("BasePart") and found or nil
    end

    -- Reuse the table, NOT the lookup results or world positions. Re-resolve
    -- every slot so reparenting, replacement and late streaming cannot leave
    -- us pointing at the old head/leg or at a lower leg removed mid-round.
    local function parts(char)
        local p = partCache[char]
        if not p then
            p = {}
            partCache[char] = p
        end

        p.head = part(char, "Head")
        p.upper = part(char, "UpperTorso")
        p.lower = part(char, "LowerTorso")
        p.torso = part(char, "Torso")
        p.leftLeg = part(char, "LeftUpperLeg") or part(char, "Left Leg")
        p.rightLeg = part(char, "RightUpperLeg") or part(char, "Right Leg")
        p.leftLower = part(char, "LeftLowerLeg")
        p.rightLower = part(char, "RightLowerLeg")
        p.leftFoot = part(char, "LeftFoot")
        p.rightFoot = part(char, "RightFoot")
        return p
    end

    -- Returns a point AND the real body part that owns it. Never infer a
    -- head/leg from HumanoidRootPart: that fails on jumps, prone and crouches.
    local function aimPoint(p, which, preferred)
        if which == "head" then
            return p.head and p.head.Position, p.head
        end

        if which == "neck" then
            local head = p.head
            local torso = p.upper or p.torso
            local attachment = head and head:FindFirstChild("NeckRigAttachment")

            if attachment and attachment:IsA("Attachment") then
                return attachment.WorldPosition, head
            end

            local neck = torso and torso:FindFirstChild("Neck")
            if neck and neck:IsA("Motor6D") and head then
                if neck.Part1 == head then
                    return (head.CFrame * neck.C1).Position, head
                elseif neck.Part0 == head then
                    return (head.CFrame * neck.C0).Position, head
                end
            end

            if head then
                return head.CFrame * Vector3.new(0, -head.Size.Y * 0.4, 0), head
            end
            return nil
        end

        if which == "body" then
            local body = p.upper or p.torso or p.lower
            return body and body.Position, body
        end

        if which == "legs" then
            -- Keep one real limb rather than the empty midpoint BETWEEN two
            -- legs. Preserve that limb while it exists, even during animation.
            for _, limb in pairs({ p.leftLeg, p.rightLeg, p.leftLower,
                p.rightLower, p.leftFoot, p.rightFoot }) do
                if limb == preferred then
                    return limb.Position, limb
                end
            end

            local limb = p.leftLeg or p.rightLeg or p.leftLower
                or p.rightLower or p.leftFoot or p.rightFoot
            return limb and limb.Position, limb
        end

        return nil
    end

    -- Walls block, invisible parts and characters do not.
    local function hasSight(from, to, target, localChar)
        local direction = to - from

        if direction.Magnitude < 0.01 then
            return true
        end

        -- A gun/arm parented to CurrentCamera is not a wall.
        local filter = { target }
        local camera = Workspace.CurrentCamera
        if camera then
            filter[#filter + 1] = camera
        end

        if localChar then
            filter[#filter + 1] = localChar
        end

        for _ = 1, LIMITS.sightPasses do
            rayParams.FilterDescendantsInstances = filter

            local hit = Workspace:Raycast(from, direction, rayParams)

            if not hit then
                return true
            end

            local piece = hit.Instance

            if piece:IsA("Terrain") then
                return false
            end

            local model = piece:FindFirstAncestorOfClass("Model")

            if model and model:FindFirstChildOfClass("Humanoid") then
                filter[#filter + 1] = model
            elseif piece.Transparency >= 0.9 then
                filter[#filter + 1] = piece
            else
                return false
            end
        end

        return false
    end

    -- Players:GetPlayers() allocates a table per call: keep one list.
    local roster = {}
    local rosterNames = {}

    local function refreshRoster()
        local list = Players:GetPlayers()

        for index = 1, #list do
            roster[index] = list[index]
        end

        for index = #list + 1, #roster do
            roster[index] = nil
        end

        table.clear(rosterNames)

        for index = 1, #roster do
            local other = roster[index]

            rosterNames[other.Name] = other
        end
    end

    refreshRoster()

    -- Modes with a single team for everybody (or none at all) must not lose
    -- every target to the teammate filter, so it only applies while a second
    -- side really exists.
    --
    -- The sides themselves are read by the ESP block (Roblox Team, attributes,
    -- value objects, character folders - see sideOf there) and shared through
    -- uiState, so the aimbot and the ESP can never disagree about who is a
    -- teammate. The plain Roblox-Team check below is only the fallback for the
    -- case that the ESP block failed to load.
    local sidesOn = false
    local sidesAt = -1

    local function fallbackRefreshSides(now)
        if now - sidesAt < 1 then
            return
        end

        sidesAt = now
        sidesOn = false

        local mine = player.Team

        if mine == nil then
            return
        end

        for index = 1, #roster do
            local other = roster[index]

            if other ~= player and other.Team ~= nil and other.Team ~= mine then
                sidesOn = true
                return
            end
        end
    end

    local function fallbackIsTeammate(target)
        local mine = player.Team

        return mine ~= nil and sidesOn and target.Team == mine
    end

    local function refreshSides(now)
        local shared = uiState.refreshSides

        if shared then
            shared(now)
        else
            fallbackRefreshSides(now)
        end
    end

    local function isTeammate(target)
        local shared = uiState.isTeammate

        if shared then
            return shared(target)
        end

        return fallbackIsTeammate(target)
    end

    -- Bodies that outlive the player. Two shapes are covered:
    --   * a model that carries a player's name but is not his character any
    --     more - that is the body he left behind;
    --   * a model that has not moved its root for a while - a living character
    --     animates and drifts even when it stands still, a corpse does not.
    local FROZEN_AFTER = 1.5
    local frozenAt = setmetatable({}, { __mode = "k" })

    local function isFrozenBody(model)
        local root = model.PrimaryPart
            or model:FindFirstChild("HumanoidRootPart")

        if not root then
            return false
        end

        local now = os.clock()
        local state = frozenAt[model]
        local pos = root.Position

        if not state then
            frozenAt[model] = { pos = pos, since = now }
            return false
        end

        if (pos - state.pos).Magnitude > 0.05 then
            state.pos = pos
            state.since = now
            return false
        end

        return now - state.since > FROZEN_AFTER
    end

    local function isLeftoverBody(model)
        local owner = rosterNames[model.Name]

        return owner ~= nil and owner.Character ~= model
    end

    -- Bots are only collected while they can actually be targeted.
    local function noteBot(item)
        if not item:IsA("Humanoid") then
            return
        end

        local model = item.Parent

        if model and model:IsA("Model") then
            botModels[model] = item
        end
    end

    local function stopBotScan()
        for _, link in ipairs(botLinks) do
            link:Disconnect()
        end

        table.clear(botLinks)
        table.clear(botModels)
    end

    local function startBotScan()
        if #botLinks > 0 then
            return
        end

        table.insert(botLinks, Workspace.DescendantAdded:Connect(noteBot))

        table.insert(botLinks, Workspace.DescendantRemoving:Connect(function(item)
            if item:IsA("Humanoid") and botModels[item.Parent] == item then
                botModels[item.Parent] = nil
            end
        end))

        for _, item in ipairs(Workspace:GetDescendants()) do
            noteBot(item)
        end
    end

    -- our own avatar in any shape (custom characters keep a visible copy)
    -- Nothing inside our own body can be a target, whatever the model is
    -- called, however it was cloned and whoever owns it: an enemy cannot stand
    -- inside our hitbox, so anything that close IS us.
    local SELF_RADIUS = 3.5

    -- Same rule as the bot ESP: a copy of our own avatar is our avatar. The
    -- copy stands exactly where we stand, so aiming at it points the camera at
    -- ourselves: no effect in first person (the aim point sits on the camera)
    -- and a spinning view in third person.
    local function isOwnAvatar(model, humanoid)
        local char = player.Character

        if char then
            if model == char
                or model:IsDescendantOf(char)
                or char:IsDescendantOf(model) then
                return true
            end

            local ownHum = char:FindFirstChildOfClass("Humanoid")
            local ownRoot = char:FindFirstChild("HumanoidRootPart")
                or char.PrimaryPart

            if ownHum and humanoid == ownHum then
                return true
            end

            local root = humanoid and humanoid.RootPart

            if root then
                if ownRoot and root == ownRoot then
                    return true
                end

                if ownRoot
                    and (root.Position - ownRoot.Position).Magnitude < 1.25 then
                    return true
                end
            end
        end

        local cam = Workspace.CurrentCamera

        if cam and humanoid and cam.CameraSubject == humanoid then
            return true
        end

        if model.Name == player.Name
            or (char and model.Name == char.Name) then
            return true
        end

        return false
    end

    local function aimSpeed()
        local speed = SPEED_FAST * (SPEED_RATIO ^ (cfg.smooth - 1))

        if speed < SPEED_FLOOR then
            speed = SPEED_FLOOR
        end

        return speed
    end

    -- Our own aim, kept between frames. Some games rebuild the camera from the
    -- mouse every frame instead of continuing from where we left it; pulling
    -- only a fraction of the way from THAT view never accumulates, so the
    -- crosshair stopped short of the target (and the miss grew with range).
    -- heldCF is what we wrote last frame, gameCF is what the game gave us
    -- before that write.
    local heldCF, gameCF, heldCamera

    local function dropHold()
        heldCF, gameCF, heldCamera = nil, nil, nil
    end

    local function lookAngle(a, b)
        return math.acos(clamp(a.LookVector:Dot(b.LookVector), -1, 1))
    end

    local function aimAt(cam, point, dt)
        local view = cam.CFrame
        local origin = view.Position

        if (point - origin).Magnitude < 0.1 then
            return
        end

        local desired = CFrame.lookAt(origin, point)

        -- No dead zone, interpolation lag or guessed lead in exact mode.
        -- Recompute from the live target and the final camera origin EVERY
        -- render frame; distance does not weaken the correction.
        if cfg.smooth == 0 then
            cam.CFrame = desired
            dropHold()
            return
        end

        if heldCamera ~= cam then
            dropHold()
        end
        local base = view

        if heldCF and gameCF
            and lookAngle(view, gameCF) <= lookAngle(view, heldCF) then
            -- the game started over from its own view: keep our pull on top
            -- of it and add the mouse movement it made since last frame
            local rotHeld = heldCF - heldCF.Position
            local rotLast = gameCF - gameCF.Position
            local rotNow = view - origin

            base = CFrame.new(origin) * (rotHeld * rotLast:Inverse() * rotNow)
        end

        local k = 1 - math.exp(-aimSpeed() * dt)

        if k > 1 then
            k = 1
        end

        local result = base:Lerp(desired, k)

        cam.CFrame = result
        heldCF, gameCF, heldCamera = result, view, cam
    end

    local function step(dt)
        if uiState.closed then
            return
        end

        local cam = Workspace.CurrentCamera

        if not cam then
            return
        end

        dt = math.min(dt, 0.1)

        local viewport = cam.ViewportSize
        local radius = cfg.fov * (viewport.Y / AIM_REFERENCE)

        ring.Visible = cfg.enabled
        ring.Size = UDim2.fromOffset(radius * 2, radius * 2)

        if not cfg.enabled then
            current = nil
            dropHold()
            return
        end

        -- Our free camera owns the view. A game's own Scriptable camera is
        -- not automatically freecam; many custom camera controllers use it.
        if uiState.freeCamera then
            current = nil
            dropHold()
            return
        end

        if cfg.shootOnly and not UserInputService:IsMouseButtonPressed(
            Enum.UserInputType.MouseButton1
        ) then
            current = nil
            dropHold()
            return
        end

        local camPos = cam.CFrame.Position
        local localChar = player.Character
        local localRoot = localChar
            and (localChar:FindFirstChild("HumanoidRootPart")
                or localChar.PrimaryPart)
        local origin = localRoot and localRoot.Position or camPos
        local localHead = localChar and localChar:FindFirstChild("Head")
        local selfPoint = localHead and localHead.Position or origin
        local centerX = viewport.X * 0.5
        local centerY = viewport.Y * 0.5
        local limit = radius * radius
        local lockedChar = current and current.char

        table.clear(candidates)

        local function consider(model, char, humanoid, owner)
            local preferred = current and current.char == char
                and current.part == cfg.part and current.aimPart or nil
            local point, aimPart = aimPoint(parts(char), cfg.part, preferred)

            if not point or not aimPart or aimPart.Parent ~= char then
                return
            end

            -- our own body, in any shape: never a target
            if (point - selfPoint).Magnitude < SELF_RADIUS then
                return
            end

            -- distance is measured from the character, not from the camera:
            -- pulling the camera back must not extend the aimbot range
            if (point - origin).Magnitude * STUDS_TO_M > cfg.range then
                return
            end

            local screen, onScreen = cam:WorldToViewportPoint(point)

            if not onScreen or screen.Z <= 0 then
                return
            end

            local dx = screen.X - centerX
            local dy = screen.Y - centerY
            local distance = dx * dx + dy * dy

            if distance > limit then
                return
            end

            candidates[#candidates + 1] = {
                char = char,
                humanoid = humanoid,
                model = model,
                owner = owner,
                point = point,
                score = distance,
                locked = char == lockedChar,
                aimPart = aimPart,
                part = cfg.part,
            }
        end

        if cfg.ignoreTeam then
            refreshSides(os.clock())
        end

        for index = 1, #roster do
            local target = roster[index]

            if target ~= player and not (cfg.ignoreTeam and isTeammate(target)) then
                local char = target.Character

                if char and char.Parent then
                    local humanoid = isAlive(char)

                    if humanoid then
                        consider(target, char, humanoid, target)
                    end
                end
            end
        end

        if not cfg.ignoreBots then
            for model, humanoid in pairs(botModels) do
                if model.Parent
                    and humanoid.Parent
                    and isAlive(model)
                    and not isOwnAvatar(model, humanoid)
                    and not Players:GetPlayerFromCharacter(model)
                    and not isFrozenBody(model)
                    and not isLeftoverBody(model) then
                    consider(model, model, humanoid, nil)
                end
            end
        end

        if #candidates == 0 then
            current = nil
            dropHold()
            return
        end

        table.sort(candidates, function(a, b)
            if a.locked ~= b.locked then
                return a.locked
            end
            if a.score == b.score then
                return a.char.Name < b.char.Name
            end
            return a.score < b.score
        end)

        local chosen
        -- Recheck the CURRENT point this frame, not an 80 ms-old pose. The
        -- locked character is checked first; do not arbitrarily stop after
        -- four occluded candidates and miss a visible fifth one.
        for index = 1, #candidates do
            local candidate = candidates[index]
            if not cfg.visible or hasSight(
                camPos, candidate.point, candidate.char, localChar
            ) then
                chosen = candidate
                break
            end
        end

        if not chosen then
            current = nil
            dropHold()
            return
        end

        if not current or current.char ~= chosen.char
            or current.aimPart ~= chosen.aimPart or current.part ~= chosen.part then
            dropHold()
        end
        current = chosen

        -- Resolve once more immediately before writing the camera. Nothing
        -- between reading the part and this write yields to another task.
        local livePoint, livePart = aimPoint(parts(chosen.char), cfg.part, chosen.aimPart)
        if not livePoint or livePart ~= chosen.aimPart
            or livePart.Parent ~= chosen.char then
            current = nil
            dropHold()
            return
        end
        current.point = livePoint
        aimAt(cam, livePoint, dt)
    end

    -- getgenv().shitaro_aim() in the executor: prints every player with the
    -- numbers the aimbot decides on, so a body that still gets picked can be
    -- traced to the exact check that let it through.
    local function dumpAim()
        local cam = Workspace.CurrentCamera

        if not cam then
            return
        end

        local char = player.Character
        local root = char
            and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
        local origin = root and root.Position or cam.CFrame.Position

        warn(string.format(
            "[shitaro/aim] circle=%d/1080p range=%dm smoothing=%d part=%s lock=%s",
            cfg.fov, cfg.range, cfg.smooth, cfg.part,
            current and current.char.Name or "none"
        ))

        for index = 1, #roster do
            local target = roster[index]
            local body = target.Character
            local humanoid = body and body:FindFirstChildOfClass("Humanoid")

            if body and humanoid then
                local point = aimPoint(parts(body), cfg.part)
                local meters = point
                    and (point - origin).Magnitude * STUDS_TO_M
                    or -1

                local off = "-"

                if point then
                    local screen = cam:WorldToViewportPoint(point)

                    off = string.format(
                        "%.0fpx",
                        (Vector2.new(screen.X, screen.Y)
                            - cam.ViewportSize * 0.5).Magnitude
                    )
                end

                warn(string.format(
                    "[shitaro/aim] %s | hp=%.0f | state=%s | ragdoll=%s"
                        .. " | dead=%s | range=%.0fm | teammate=%s | me=%s"
                        .. " | off=%s",
                    target.Name,
                    humanoid.Health,
                    tostring(humanoid:GetState()),
                    tostring(humanoid.PlatformStand),
                    tostring(isAlive(body) == nil),
                    meters,
                    tostring(cfg.ignoreTeam and isTeammate(target)),
                    tostring(isOwnAvatar(body, humanoid)),
                    off
                ))
            end
        end
    end

    pcall(function()
        local env = getgenv and getgenv() or nil

        if env then
            env.shitaro_aim = dumpAim
        end
    end)

    connect(Players.PlayerAdded, refreshRoster)
    connect(Players.PlayerRemoving, refreshRoster)

    -- Aimbot: runtime ----------------------------------------------------------

    local stepName = "ShitaroAim"

    pcall(function()
        RunService:UnbindFromRenderStep(stepName)
    end)

    -- Last of all: the third person offset has already placed the camera
    -- (RenderPriority.Camera + 1), so the aim is computed from the real camera
    -- position and the crosshair lands exactly on the target. The offset never
    -- sees this write, so it cannot feed back into itself.
    local bound = pcall(function()
        RunService:BindToRenderStep(
            stepName,
            Enum.RenderPriority.Last.Value,
            step
        )
    end)

    if not bound then
        connect(RunService.RenderStepped, step)
    end

    -- not registered through connect(): that list is disconnected first
    gui.Destroying:Connect(function()
        current = nil
        dropHold()
        pcall(stopBotScan)
        pcall(function()
            local env = getgenv and getgenv() or nil
            if env and env.shitaro_aim == dumpAim then
                env.shitaro_aim = nil
            end
        end)

        pcall(function()
            RunService:UnbindFromRenderStep(stepName)
        end)

        overlay:Destroy()
    end)

    -- Aimbot: menu -------------------------------------------------------------

    panelWidths[previewScroll] = window.Size.X.Offset - PANEL_RESERVE

    local mainCard = previewPanel(previewScroll, "aim.panel", 1, 4)

    local filterCard, filterHolder =
        previewPanel(previewScroll, "aim.filters", 2, 2)

    panelGapBefore[filterHolder] = 16

    local tuneCard, tuneHolder =
        previewPanel(previewScroll, "aim.tuning", 3, 3)

    panelGapBefore[tuneHolder] = 16

    -- same look as the toggles on the visuals tab
    local function addToggle(frame, state, onChange)
        local track = make("Frame", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -12, 0.5, 0),
            Size = UDim2.fromOffset(26, 14),
            BackgroundColor3 = state and colors.accent or Color3.new(1, 1, 1),
            BackgroundTransparency = state and 0.35 or 0.86,
            ZIndex = 2,
        }, frame)

        corner(track, UDim.new(1, 0))

        local knob = make("Frame", {
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, state and 14 or 2, 0.5, 0),
            Size = UDim2.fromOffset(10, 10),
            BackgroundColor3 = state and colors.accent or colors.sub,
            BackgroundTransparency = 0.15,
            ZIndex = 3,
        }, track)

        corner(knob, UDim.new(1, 0))

        local hit = make("TextButton", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Text = "",
            ZIndex = 5,
        }, frame)

        connect(hit.Activated, function()
            state = not state

            animate(track, {
                BackgroundColor3 = state
                    and colors.accent
                    or Color3.new(1, 1, 1),
                BackgroundTransparency = state and 0.35 or 0.86,
            })

            animate(knob, {
                Position = UDim2.new(0, state and 14 or 2, 0.5, 0),
                BackgroundColor3 = state and colors.accent or colors.sub,
            })

            onChange(state)
        end)
    end

    -- 1: aimbot on/off
    local enableRow, enableLabel = previewRow(mainCard, 1, "", true)
    localize(enableLabel, "aim.enabled")

    addToggle(enableRow, cfg.enabled, function(value)
        cfg.enabled = value
        ring.Visible = value

        if value then
            if not cfg.ignoreBots then
                pcall(startBotScan)
            end
        else
            current = nil
            dropHold()
            pcall(stopBotScan)
        end
    end)

    -- 2: visibility check
    local sightRow, sightLabel = previewRow(mainCard, 2, "", true)
    localize(sightLabel, "aim.visible")

    addToggle(sightRow, cfg.visible, function(value)
        cfg.visible = value
    end)

    -- 3: aim only while shooting
    local shootRow, shootLabel = previewRow(mainCard, 3, "", true)
    localize(shootLabel, "aim.shootOnly")

    addToggle(shootRow, cfg.shootOnly, function(value)
        cfg.shootOnly = value
    end)

    -- 4: target part
    local partRow, partLabel = previewRow(mainCard, 4, "", true)
    localize(partLabel, "aim.part")

    local function addSegments(frame, options, initial, onChange)
        local holder = make("Frame", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -10, 0.5, 0),
            Size = UDim2.new(0.47, 0, 0, 22),
        }, frame)

        local buttons = {}
        local paint

        paint = function(selected)
            for id, entry in pairs(buttons) do
                local active = id == selected

                animate(entry.shell, {
                    BackgroundColor3 = active
                        and colors.accent
                        or Color3.new(1, 1, 1),
                    BackgroundTransparency = active and 0.78 or 0.97,
                })

                animate(entry.label, {
                    TextColor3 = active and colors.accent or colors.sub,
                })
            end
        end

        for index, option in ipairs(options) do
            local shell = make("Frame", {
                Position = UDim2.new((index - 1) / #options, 0, 0, 0),
                Size = UDim2.new(1 / #options, -3, 1, 0),
                BackgroundColor3 = Color3.new(1, 1, 1),
                BackgroundTransparency = 0.97,
            }, holder)

            corner(shell, UDim.new(0, 5))

            local label = make("TextLabel", {
                Text = "",
                TextSize = 11,
                TextColor3 = colors.sub,
                TextXAlignment = Enum.TextXAlignment.Center,
                Size = UDim2.fromScale(1, 1),
                ZIndex = 2,
            }, shell)

            localize(label, option[2])

            local hit = make("TextButton", {
                Size = UDim2.fromScale(1, 1),
                BackgroundTransparency = 1,
                Text = "",
                ZIndex = 5,
            }, shell)

            buttons[option[1]] = { shell = shell, label = label }

            connect(hit.Activated, function()
                onChange(option[1])
                paint(option[1])
            end)
        end

        paint(initial)
    end

    addSegments(partRow, PARTS, cfg.part, function(id)
        cfg.part = id
        current = nil
        dropHold()
    end)

    -- targets: bots + teammates
    local botsRow, botsLabel = previewRow(filterCard, 1, "", true)
    localize(botsLabel, "aim.ignoreBots")

    addToggle(botsRow, cfg.ignoreBots, function(value)
        cfg.ignoreBots = value

        if value then
            pcall(stopBotScan)
        elseif cfg.enabled then
            pcall(startBotScan)
        end
    end)

    local teamRow, teamLabel = previewRow(filterCard, 2, "", true)
    localize(teamLabel, "aim.ignoreTeam")

    addToggle(teamRow, cfg.ignoreTeam, function(value)
        cfg.ignoreTeam = value
    end)

    -- tuning: smoothing, circle, range
    local smoothRow, smoothLabel = previewRow(tuneCard, 1, "", true)
    localize(smoothLabel, "aim.smooth")

    local smoothSlider = rowSlider(
        smoothRow,
        "AimSmooth",
        LIMITS.smoothMin,
        LIMITS.smoothMax,
        function(value)
            return tostring(math.floor(value + 0.5))
        end,
        function(value)
            cfg.smooth = math.floor(value + 0.5)
        end
    )

    smoothSlider.set(cfg.smooth, false)

    local circleRow, circleLabel = previewRow(tuneCard, 2, "", true)
    localize(circleLabel, "aim.fov")

    local circleSlider = rowSlider(
        circleRow,
        "AimCircle",
        LIMITS.circleMin,
        LIMITS.circleMax,
        function(value)
            return tostring(math.floor(value + 0.5))
        end,
        function(value)
            cfg.fov = math.floor(value + 0.5)
        end
    )

    circleSlider.set(cfg.fov, false)

    local rangeRow, rangeLabel = previewRow(tuneCard, 3, "", true)
    localize(rangeLabel, "aim.range")

    local rangeSlider = rowSlider(
        rangeRow,
        "AimRange",
        LIMITS.rangeMin,
        LIMITS.rangeMax,
        function(value)
            return math.floor(value + 0.5) .. "m"
        end,
        function(value)
            cfg.range = math.floor(value + 0.5)
        end
    )

    rangeSlider.set(cfg.range, false)

    layoutPreview()
end, function(err)
    warn("[shitaro/aim] " .. debug.traceback(tostring(err), 2))
end)
end
