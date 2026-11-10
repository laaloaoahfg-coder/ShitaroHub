-- modules/skins.lua - skins tab
-- A card with the anime girl: click it to swap your character's look for her
-- model, "reset" brings your own avatar back. Client side only: nobody else
-- sees it.
-- Returns function(ctx); ctx is built by core/ui.lua (shared UI helpers).
--
-- How the swap works
--   models/angel_v2.pack holds the model as 36 Roblox .mesh pieces (one per
--   body part and texture) plus textures. The pack is downloaded once into
--   the executor workspace (ShitaroHub/cache/angel_v2), then every piece is a
--   Part + SpecialMesh welded to the matching limb of your character. The
--   real body, hair, accessories and face are made invisible while it is on.
--   Needs an executor with writefile / readfile / isfile / makefolder /
--   getcustomasset.

return function(ctx)
local locale, player, Players, RunService, connect, make, corner, colors,
    animate, localize, previewPanel, pageScroll, tabs, window, layoutPreview,
    uiState, gui, Loader, L =
    ctx.locale,
    ctx.player,
    ctx.Players,
    ctx.RunService,
    ctx.connect,
    ctx.make,
    ctx.corner,
    ctx.colors,
    ctx.animate,
    ctx.localize,
    ctx.previewPanel,
    ctx.pageScroll,
    ctx.tabs,
    ctx.window,
    ctx.layoutPreview,
    ctx.uiState,
    ctx.gui,
    ctx.Loader,
    ctx.L

xpcall(function()
    local HttpService = game:GetService("HttpService")

    local PACK_PATH = "models/angel_v2.pack"
    local PACK_NAME = "angel_v2"
    local WHITE = Color3.new(1, 1, 1)
    local HALO_COLOR = Color3.fromRGB(190, 235, 255)

    local config = (getgenv and getgenv().ShitaroConfig) or {}
    local ROOT_DIR = config.Folder or "ShitaroHub"
    local CACHE_DIR = ROOT_DIR .. "/cache/" .. PACK_NAME

    -- Text ---------------------------------------------------------------------

    local extra = {
        en = {
            ["skins.panel"] = "player model",
            ["skins.name"] = "Angel",
            ["skins.desc"] = "anime girl with wings and a halo",
            ["skins.hint"] = "To change your player model, click the card "
                .. "with the anime girl. Only you can see it.",
            ["skins.reset"] = "reset",
            ["skins.flip"] = "flip faces (model looks inside out)",
            ["skins.chip.apply"] = "click to apply",
            ["skins.chip.active"] = "active",
            ["skins.chip.busy"] = "working...",
            ["skins.s.idle"] = "your own model",
            ["skins.s.download"] = "downloading the model (about 5 MB)...",
            ["skins.s.ready"] = "model downloaded",
            ["skins.s.loading"] = "building the model...",
            ["skins.s.applied"] = "model applied",
            ["skins.s.reset"] = "your own model is back",
            ["skins.s.fail"] = "failed",
            ["skins.s.unsupported"] = "this executor cannot load custom "
                .. "models (needs writefile and getcustomasset)",
            ["skins.s.nochar"] = "no living character found",
        },
        ru = {
            ["skins.panel"] = "модель игрока",
            ["skins.name"] = "Ангел",
            ["skins.desc"] = "аниме девушка с крыльями и нимбом",
            ["skins.hint"] = "Чтобы изменить модель игрока, нажмите на "
                .. "карточку с аниме девушкой. Видно только вам.",
            ["skins.reset"] = "сброс",
            ["skins.flip"] = "перевернуть грани (модель выглядит наизнанку)",
            ["skins.chip.apply"] = "нажмите, чтобы применить",
            ["skins.chip.active"] = "включена",
            ["skins.chip.busy"] = "подождите...",
            ["skins.s.idle"] = "ваша обычная модель",
            ["skins.s.download"] = "скачиваю модель (около 5 МБ)...",
            ["skins.s.ready"] = "модель скачана",
            ["skins.s.loading"] = "собираю модель...",
            ["skins.s.applied"] = "модель применена",
            ["skins.s.reset"] = "обычная модель возвращена",
            ["skins.s.fail"] = "ошибка",
            ["skins.s.unsupported"] = "этот инжектор не умеет загружать "
                .. "модели (нужны writefile и getcustomasset)",
            ["skins.s.nochar"] = "живой персонаж не найден",
        },
    }

    for language, pack in pairs(extra) do
        for key, text in pairs(pack) do
            locale[language][key] = text
        end
    end

    -- State --------------------------------------------------------------------

    local state = {
        enabled = false,   -- the skin should be on (also after respawn)
        busy = false,
        flip = false,      -- winding fix, see the toggle
    }

    local assets            -- the pack description once it is on disk
    local preparing = false
    local assetUrls = {}    -- file name -> rbxasset:// url
    local skinFolder
    local hidden = {}       -- instance -> original Transparency
    local watchers = {}     -- connections tied to the current skin
    local skinChar          -- the character the skin was built for
    local fit               -- where the model's right palm is, for held tools
    local gripOriginal = {} -- RightGrip weld -> its original C0
    local lastRebuild = 0

    -- UI -----------------------------------------------------------------------

    local skinScroll = pageScroll(tabs[5].page, "SkinsScroll")
    local card, holder = previewPanel(skinScroll, "skins.panel", 1, 9)

    local modelCard = make("TextButton", {
        Position = UDim2.fromOffset(12, 12),
        Size = UDim2.new(1, -24, 0, 112),
        BackgroundColor3 = WHITE,
        BackgroundTransparency = 0.93,
        ZIndex = 3,
    }, card)

    corner(modelCard, UDim.new(0, 10))

    local modelStroke = make("UIStroke", {
        Color = colors.accent,
        Transparency = 1,
        Thickness = 1.5,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, modelCard)

    local thumb = make("ImageLabel", {
        Position = UDim2.fromOffset(8, 8),
        Size = UDim2.fromOffset(68, 96),
        BackgroundColor3 = WHITE,
        BackgroundTransparency = 0.9,
        ScaleType = Enum.ScaleType.Fit,
        ZIndex = 4,
    }, modelCard)

    corner(thumb, UDim.new(0, 8))

    localize(make("TextLabel", {
        Position = UDim2.fromOffset(88, 14),
        Size = UDim2.new(1, -96, 0, 20),
        TextSize = 15,
        FontFace = Font.new(
            "rbxasset://fonts/families/BuilderSans.json",
            Enum.FontWeight.Bold
        ),
        ZIndex = 4,
    }, modelCard), "skins.name")

    local descLabel = make("TextLabel", {
        Position = UDim2.fromOffset(88, 36),
        Size = UDim2.new(1, -96, 0, 32),
        TextSize = 12,
        TextColor3 = colors.dim,
        TextWrapped = true,
        TextYAlignment = Enum.TextYAlignment.Top,
        ZIndex = 4,
    }, modelCard)

    localize(descLabel, "skins.desc")

    local chip = make("TextLabel", {
        Position = UDim2.new(0, 88, 1, -32),
        Size = UDim2.fromOffset(150, 22),
        BackgroundColor3 = WHITE,
        BackgroundTransparency = 0.9,
        TextSize = 11,
        TextColor3 = colors.sub,
        TextXAlignment = Enum.TextXAlignment.Center,
        ZIndex = 4,
    }, modelCard)

    corner(chip, UDim.new(1, 0))

    local hint = make("TextLabel", {
        Position = UDim2.fromOffset(14, 134),
        Size = UDim2.new(1, -28, 0, 34),
        TextSize = 12,
        TextColor3 = colors.sub,
        TextWrapped = true,
        TextYAlignment = Enum.TextYAlignment.Top,
        ZIndex = 3,
    }, card)

    localize(hint, "skins.hint")

    local resetButton = make("TextButton", {
        Position = UDim2.fromOffset(12, 176),
        Size = UDim2.fromOffset(96, 26),
        BackgroundColor3 = WHITE,
        BackgroundTransparency = 0.93,
        TextSize = 12,
        TextColor3 = colors.text,
        TextXAlignment = Enum.TextXAlignment.Center,
        ZIndex = 4,
    }, card)

    corner(resetButton, UDim.new(0, 8))
    localize(resetButton, "skins.reset")

    local statusLabel = make("TextLabel", {
        Position = UDim2.fromOffset(118, 172),
        Size = UDim2.new(1, -130, 0, 34),
        TextSize = 11,
        TextColor3 = colors.dim,
        TextWrapped = true,
        ZIndex = 3,
    }, card)

    -- flip-faces toggle (fallback for the one thing that cannot be tested
    -- without Roblox: whether the engine treats the faces as inside out)
    local flipRow = make("Frame", {
        Position = UDim2.fromOffset(0, 214),
        Size = UDim2.new(1, 0, 0, 30),
        ZIndex = 3,
    }, card)

    localize(make("TextLabel", {
        Position = UDim2.fromOffset(14, 0),
        Size = UDim2.new(1, -70, 1, 0),
        TextSize = 12,
        TextColor3 = colors.sub,
        ZIndex = 3,
    }, flipRow), "skins.flip")

    local flipTrack = make("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.fromOffset(26, 14),
        BackgroundColor3 = WHITE,
        BackgroundTransparency = 0.86,
        ZIndex = 3,
    }, flipRow)

    corner(flipTrack, UDim.new(1, 0))

    local flipKnob = make("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 2, 0.5, 0),
        Size = UDim2.fromOffset(10, 10),
        BackgroundColor3 = colors.sub,
        BackgroundTransparency = 0.15,
        ZIndex = 4,
    }, flipTrack)

    corner(flipKnob, UDim.new(1, 0))

    local flipHit = make("TextButton", {
        Size = UDim2.fromScale(1, 1),
        ZIndex = 6,
    }, flipRow)

    local function paintFlip()
        animate(flipTrack, {
            BackgroundColor3 = state.flip and colors.accent or WHITE,
            BackgroundTransparency = state.flip and 0.35 or 0.86,
        })

        animate(flipKnob, {
            Position = UDim2.new(0, state.flip and 14 or 2, 0.5, 0),
            BackgroundColor3 = state.flip and colors.accent or colors.sub,
        })
    end

    local function setStatus(key, detail)
        local text = L(key)

        if detail then
            text = text .. ": " .. tostring(detail)
        end

        statusLabel.Text = text
    end

    local function paintCard()
        local key = state.busy and "skins.chip.busy"
            or (state.enabled and "skins.chip.active" or "skins.chip.apply")

        chip.Text = L(key)

        animate(modelStroke, {
            Transparency = state.enabled and 0.25 or 1,
        })

        animate(chip, {
            BackgroundColor3 = state.enabled and colors.accent or WHITE,
            BackgroundTransparency = state.enabled and 0.55 or 0.9,
        })
    end

    setStatus("skins.s.idle")
    paintCard()

    connect(modelCard.MouseEnter, function()
        animate(modelCard, { BackgroundTransparency = 0.88 })
    end)

    connect(modelCard.MouseLeave, function()
        animate(modelCard, { BackgroundTransparency = 0.93 })
    end)

    -- Pack on disk ---------------------------------------------------------------

    local function u32(text, index)
        local a, b, c, d = text:byte(index, index + 3)

        return a + b * 256 + c * 65536 + d * 16777216
    end

    local function supported()
        return type(writefile) == "function"
            and type(readfile) == "function"
            and type(isfile) == "function"
            and type(makefolder) == "function"
            and type(isfolder) == "function"
            and type(getcustomasset) == "function"
    end

    local function ensureFolder(path)
        if not isfolder(path) then
            makefolder(path)
        end
    end

    local function allFilesPresent(description)
        for _, file in ipairs(description.files) do
            if not isfile(CACHE_DIR .. "/" .. file.name) then
                return false
            end
        end

        return true
    end

    -- Downloads the pack once and unpacks it into the workspace folder.
    local function prepare()
        if assets then
            return assets
        end

        if not supported() then
            error("unsupported", 0)
        end

        while preparing do
            task.wait(0.1)
        end

        if assets then
            return assets
        end

        preparing = true

        local ok, result = pcall(function()
            ensureFolder(ROOT_DIR)
            ensureFolder(ROOT_DIR .. "/cache")
            ensureFolder(CACHE_DIR)

            local marker = CACHE_DIR .. "/pack.json"

            if isfile(marker) then
                local description = HttpService:JSONDecode(readfile(marker))

                if allFilesPresent(description) then
                    return description
                end
            end

            setStatus("skins.s.download")

            local data = Loader.fetch(PACK_PATH)

            if type(data) ~= "string" or data:sub(1, 4) ~= "SHP1" then
                error("the model file is missing or damaged (" .. PACK_PATH
                    .. ")", 0)
            end

            local headerLength = u32(data, 5)
            local description = HttpService:JSONDecode(
                data:sub(9, 8 + headerLength)
            )
            local offset = 9 + headerLength

            for _, file in ipairs(description.files) do
                writefile(
                    CACHE_DIR .. "/" .. file.name,
                    data:sub(offset, offset + file.size - 1)
                )

                offset = offset + file.size
            end

            writefile(marker, HttpService:JSONEncode(description))
            return description
        end)

        preparing = false

        if not ok then
            error(result, 0)
        end

        assets = result
        return assets
    end

    local function assetUrl(path)
        local url = assetUrls[path]

        if not url then
            url = getcustomasset(path)
            assetUrls[path] = url
        end

        if not url or url == "" then
            error("getcustomasset returned nothing for " .. path, 0)
        end

        return url
    end

    -- Copy of a mesh with every face's winding reversed (inside-out fix).
    local function flippedMeshPath(name)
        local path = CACHE_DIR .. "/flip_" .. name

        if not isfile(path) then
            local data = readfile(CACHE_DIR .. "/" .. name)
            local vertices = u32(data, 18)
            local faces = u32(data, 22)
            local start = 26 + vertices * 40
            local out = { data:sub(1, start - 1) }

            for index = 0, faces - 1 do
                local at = start + index * 12

                out[#out + 1] = data:sub(at, at + 3)
                    .. data:sub(at + 8, at + 11)
                    .. data:sub(at + 4, at + 7)

                if index % 30000 == 29999 then
                    task.wait()
                end
            end

            writefile(path, table.concat(out))
        end

        return path
    end

    -- Character ------------------------------------------------------------------

    local R6_PART = {
        LowerTorso = "Torso", UpperTorso = "Torso", Head = "Head",
        LeftUpperArm = "Left Arm", LeftLowerArm = "Left Arm",
        LeftHand = "Left Arm",
        RightUpperArm = "Right Arm", RightLowerArm = "Right Arm",
        RightHand = "Right Arm",
        LeftUpperLeg = "Left Leg", LeftLowerLeg = "Left Leg",
        LeftFoot = "Left Leg",
        RightUpperLeg = "Right Leg", RightLowerLeg = "Right Leg",
        RightFoot = "Right Leg",
    }

    local function liveCharacter()
        local char = player.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local root = char and char:FindFirstChild("HumanoidRootPart")

        if char and hum and root and root:IsA("BasePart") and hum.Health > 0 then
            return char, hum, root
        end

        return nil
    end

    -- Every part's CFrame in the root part's space with all joints at rest
    -- (animations ignored), so the skin lines up whatever pose we are in.
    local function restPose(char, root)
        local rest = { [root] = CFrame.new() }
        local joints = {}

        for _, item in ipairs(char:GetDescendants()) do
            if item:IsA("Motor6D") and item.Part0 and item.Part1 then
                joints[#joints + 1] = item
            end
        end

        for _ = 1, 30 do
            local changed = false

            for _, joint in ipairs(joints) do
                if rest[joint.Part0] and not rest[joint.Part1] then
                    rest[joint.Part1] = rest[joint.Part0]
                        * joint.C0 * joint.C1:Inverse()

                    changed = true
                end
            end

            if not changed then
                break
            end
        end

        return rest
    end

    local function clearWatchers()
        for _, connection in ipairs(watchers) do
            connection:Disconnect()
        end

        watchers = {}
    end

    -- While the skin is on, a held tool is moved from the real avatar's grip
    -- point onto the model's palm; this puts it back.
    local function restoreGrips()
        for weld, original in pairs(gripOriginal) do
            pcall(function()
                weld.C0 = original
            end)
        end

        gripOriginal = {}
    end

    local function restoreOriginal()
        for item, value in pairs(hidden) do
            pcall(function()
                item.Transparency = value
            end)
        end

        hidden = {}
        restoreGrips()
    end

    local function removeSkin()
        clearWatchers()
        restoreOriginal()
        fit = nil
        skinChar = nil

        if skinFolder then
            pcall(function()
                skinFolder:Destroy()
            end)

            skinFolder = nil
        end
    end

    -- Makes one piece of the real avatar invisible and keeps it that way.
    local function hide(item)
        if skinFolder and item:IsDescendantOf(skinFolder) then
            return
        end

        if not (item:IsA("BasePart") or item:IsA("Decal")
            or item:IsA("Texture")) then
            return
        end

        -- the root part is already invisible, tools must stay visible
        if item.Name == "HumanoidRootPart"
            or item:FindFirstAncestorOfClass("Tool") then
            return
        end

        if hidden[item] == nil then
            hidden[item] = item.Transparency

            -- games bring the real avatar back (new round, respawn scripts):
            -- put it away again the moment that happens
            watchers[#watchers + 1] = item
                :GetPropertyChangedSignal("Transparency")
                :Connect(function()
                    if hidden[item] ~= nil and item.Transparency ~= 1 then
                        item.Transparency = 1
                    end
                end)
        end

        item.Transparency = 1
    end

    -- The held tool sits at the real avatar's grip point; move it to the
    -- palm of the model so the weapon is in her hand, not next to it.
    local function adjustGrip(weld)
        if not fit or gripOriginal[weld] ~= nil or weld.Part0 ~= fit.gripPart then
            return
        end

        gripOriginal[weld] = weld.C0

        local grip = (fit.gripRest * weld.C0).Position
        local shift = fit.gripRest:VectorToObjectSpace(fit.palm - grip)

        weld.C0 = CFrame.new(shift) * weld.C0
    end

    -- Position of the joint that carries `part`, in the root part's space.
    local function jointPosition(char, rest, part)
        for _, item in ipairs(char:GetDescendants()) do
            if item:IsA("Motor6D") and item.Part1 == part
                and item.Part0 and rest[item.Part0] then
                return (rest[item.Part0] * item.C0).Position
            end
        end

        return nil
    end

    -- Shoulder, elbow, wrist and hand end of this avatar's arm (rest pose).
    local function avatarArm(char, rest, r6, side, model)
        if r6 then
            local arm = char:FindFirstChild(side .. " Arm")
            local shoulder = arm and rest[arm] and jointPosition(char, rest, arm)

            if not shoulder then
                return nil
            end

            local tip = rest[arm].Position - Vector3.new(0, arm.Size.Y / 2, 0)
            local total = model.S[2] - model.End[2]

            return {
                S = shoulder,
                E = shoulder:Lerp(tip, (model.S[2] - model.E[2]) / total),
                W = shoulder:Lerp(tip, (model.S[2] - model.W[2]) / total),
                End = tip,
            }
        end

        local upper = char:FindFirstChild(side .. "UpperArm")
        local lower = char:FindFirstChild(side .. "LowerArm")
        local hand = char:FindFirstChild(side .. "Hand")

        if not (upper and lower and hand and rest[hand]) then
            return nil
        end

        local shoulder = jointPosition(char, rest, upper)
        local elbow = jointPosition(char, rest, lower)
        local wrist = jointPosition(char, rest, hand)

        if not (shoulder and elbow and wrist) then
            return nil
        end

        return {
            S = shoulder, E = elbow, W = wrist,
            End = rest[hand].Position - Vector3.new(0, hand.Size.Y / 2, 0),
        }
    end

    -- which two joints of the arm a piece spans
    local ARM_SEGMENT = {
        UpperArm = { "S", "E" },
        LowerArm = { "E", "W" },
        Hand = { "W", "End" },
    }

    local function sideOf(group)
        if group:sub(1, 4) == "Left" then
            return "Left", group:sub(5)
        end

        if group:sub(1, 5) == "Right" then
            return "Right", group:sub(6)
        end

        return nil, group
    end

    local function buildSkin(char, hum, root)
        local description = assets
        local rest = restPose(char, root)
        local r6 = hum.RigType == Enum.HumanoidRigType.R6

        -- standing height of this avatar -> scale of the model
        local feet = r6 and { "Left Leg", "Right Leg" }
            or { "LeftFoot", "RightFoot" }

        local bottom = math.huge

        for _, name in ipairs(feet) do
            local part = char:FindFirstChild(name)

            if part and rest[part] then
                bottom = math.min(
                    bottom,
                    rest[part].Position.Y - part.Size.Y / 2
                )
            end
        end

        local head = char:FindFirstChild("Head")

        if bottom == math.huge or not head or not rest[head] then
            error("could not read the avatar's body parts", 0)
        end

        local top = rest[head].Position.Y + head.Size.Y / 2
        local scale = (top - bottom) / description.ref_height

        -- the arms are fitted joint by joint to this avatar's arms, so the
        -- hand ends up where the avatar's hand (and its weapon) is
        local arms = {}

        for _, side in ipairs({ "Left", "Right" }) do
            arms[side] = avatarArm(
                char, rest, r6, side, description.arms[side]
            )
        end

        removeSkin()

        skinFolder = Instance.new("Folder")
        skinFolder.Name = "ShitaroSkin"
        skinFolder.Parent = char
        skinChar = char

        local palm, palmPart

        for _, piece in ipairs(description.pieces) do
            local part = char:FindFirstChild(
                r6 and R6_PART[piece.group] or piece.group
            )

            if part and rest[part] then
                -- y scale and y / z shift of this piece (x stays: the model
                -- keeps its own width, arms swing around an x-parallel axis)
                local sy, ty, tz = scale, bottom, 0
                local side, kind = sideOf(piece.group)
                local segment = ARM_SEGMENT[kind]
                local avatar = side and arms[side]
                local model = side and description.arms[side]

                if segment and avatar and model then
                    local from, to = model[segment[1]], model[segment[2]]
                    local a, b = avatar[segment[1]], avatar[segment[2]]
                    local length = math.abs(to[2] - from[2])

                    if length > 1e-4 then
                        sy = math.clamp(
                            math.abs(b.Y - a.Y) / length,
                            scale * 0.6,
                            scale * 1.6
                        )
                    end

                    ty = a.Y - sy * from[2]
                    tz = a.Z - scale * from[3]
                end

                local offset = CFrame.new(0, ty, tz)

                local meshFile = state.flip and flippedMeshPath(piece.mesh)
                    or (CACHE_DIR .. "/" .. piece.mesh)

                local carrier = Instance.new("Part")
                carrier.Name = "Skin_" .. piece.group
                carrier.Size = Vector3.new(2, 2, 2)
                carrier.Transparency = 0
                carrier.Anchored = false
                carrier.CanCollide = false
                carrier.CanTouch = false
                carrier.CanQuery = false
                carrier.Massless = true
                carrier.Material = piece.neon and Enum.Material.Neon
                    or Enum.Material.SmoothPlastic

                if piece.neon then
                    carrier.Color = HALO_COLOR
                end

                carrier.CFrame = root.CFrame * offset

                local mesh = Instance.new("SpecialMesh")
                mesh.MeshType = Enum.MeshType.FileMesh
                mesh.MeshId = assetUrl(meshFile)
                mesh.TextureId = assetUrl(CACHE_DIR .. "/" .. piece.texture)
                mesh.Scale = Vector3.new(scale, sy, scale)
                mesh.Parent = carrier

                local weld = Instance.new("Weld")
                weld.Part0 = part
                weld.Part1 = carrier
                weld.C0 = rest[part]:Inverse() * offset
                weld.C1 = CFrame.new()
                weld.Parent = carrier

                carrier.Parent = skinFolder

                -- where the model's right palm is (for held tools)
                if piece.group == "RightHand" and model then
                    palmPart = part
                    palm = Vector3.new(
                        scale * model.Palm[1],
                        sy * model.Palm[2] + ty,
                        scale * model.Palm[3] + tz
                    )
                end
            end
        end

        if palm and palmPart then
            fit = { gripPart = palmPart, gripRest = rest[palmPart], palm = palm }
        end

        -- hide the real avatar now and whatever it loads later (hats, face)
        for _, item in ipairs(char:GetDescendants()) do
            hide(item)
        end

        watchers[#watchers + 1] = char.DescendantAdded:Connect(function(item)
            task.defer(hide, item)
        end)

        if fit then
            local grip = fit.gripPart:FindFirstChild("RightGrip")

            if grip then
                adjustGrip(grip)
            end
        end
    end

    -- Actions --------------------------------------------------------------------

    local function waitForAppearance(char)
        for _ = 1, 32 do
            if player:HasAppearanceLoaded() and char.Parent then
                return
            end

            task.wait(0.25)
        end
    end

    local function failure(err)
        local message = tostring(err)

        if message == "unsupported" then
            setStatus("skins.s.unsupported")
        else
            setStatus("skins.s.fail", message)
        end

        warn("[shitaro/skins] " .. message)
    end

    local function apply()
        if state.busy then
            return
        end

        state.busy = true
        paintCard()
        setStatus("skins.s.loading")

        task.spawn(function()
            local ok, err = pcall(function()
                prepare()

                local char, hum, root = liveCharacter()

                if not char then
                    error("nochar", 0)
                end

                buildSkin(char, hum, root)
            end)

            state.busy = false

            if ok then
                state.enabled = true
                setStatus("skins.s.applied")
            elseif tostring(err) == "nochar" then
                setStatus("skins.s.nochar")
            else
                state.enabled = false
                removeSkin()
                failure(err)
            end

            paintCard()
        end)
    end

    -- Builds the skin again for the current character (respawn, new round,
    -- or the game replaced body parts and the skin lost its welds).
    local function rebuild(delay)
        if state.busy or not state.enabled then
            return
        end

        state.busy = true
        lastRebuild = os.clock()
        paintCard()

        task.spawn(function()
            if delay and delay > 0 then
                task.wait(delay)
            end

            local char = player.Character

            if char then
                waitForAppearance(char)
            end

            local ok, err = pcall(function()
                local live, hum, root = liveCharacter()

                if live then
                    buildSkin(live, hum, root)
                end
            end)

            state.busy = false

            if not ok then
                failure(err)
            end

            paintCard()
        end)
    end

    local function reset()
        state.enabled = false
        removeSkin()
        setStatus("skins.s.reset")
        paintCard()
    end

    connect(modelCard.Activated, function()
        if not state.enabled then
            apply()
        end
    end)

    connect(resetButton.Activated, reset)

    connect(flipHit.Activated, function()
        state.flip = not state.flip
        paintFlip()

        if state.enabled and not state.busy then
            apply()
        end
    end)

    -- a new character (respawn, next round): build the skin for it
    connect(player.CharacterAdded, function(char)
        removeSkin()

        if not state.enabled then
            return
        end

        task.spawn(function()
            char:WaitForChild("Humanoid", 10)
            char:WaitForChild("HumanoidRootPart", 10)
            rebuild(0)
        end)
    end)

    local function skinHealthy(char)
        if not skinFolder or skinFolder.Parent ~= char or skinChar ~= char then
            return false
        end

        for _, carrier in ipairs(skinFolder:GetChildren()) do
            local weld = carrier:FindFirstChildOfClass("Weld")

            if not weld or not weld.Part0
                or not weld.Part0:IsDescendantOf(char) then
                return false
            end
        end

        return true
    end

    -- Watchdog (4 times a second while the skin is on): rebuilds the skin if
    -- the game replaced the character or its body parts, keeps the real
    -- avatar hidden and puts a newly equipped tool into the model's hand.
    local watchTime = 0

    connect(RunService.Heartbeat, function(dt)
        watchTime = watchTime + dt

        if watchTime < 0.25 or not state.enabled or state.busy then
            return
        end

        watchTime = 0

        local char = liveCharacter()

        if not char then
            return
        end

        if not skinHealthy(char) then
            if os.clock() - lastRebuild > 1.5 then
                rebuild(0.1)
            end

            return
        end

        for item in pairs(hidden) do
            if item.Parent and item.Transparency ~= 1 then
                item.Transparency = 1
            end
        end

        for _, item in ipairs(char:GetDescendants()) do
            hide(item)
        end

        if fit then
            local grip = fit.gripPart:FindFirstChild("RightGrip")

            if grip then
                adjustGrip(grip)
            end
        end
    end)

    -- Thumbnail: download the pack the first time the tab is opened ----------------

    local thumbRequested = false

    local function loadThumbnail()
        if thumbRequested then
            return
        end

        thumbRequested = true

        task.spawn(function()
            local ok, err = pcall(function()
                prepare()
                thumb.Image = assetUrl(CACHE_DIR .. "/thumb.png")
            end)

            if ok then
                if not state.enabled then
                    setStatus("skins.s.ready")
                end
            else
                thumbRequested = false
                failure(err)
            end
        end)
    end

    connect(tabs[5].page:GetPropertyChangedSignal("Visible"), function()
        if tabs[5].page.Visible then
            loadThumbnail()
        end
    end)

    if tabs[5].page.Visible then
        loadThumbnail()
    end

    -- not registered through connect(): that list is disconnected first
    gui.Destroying:Connect(function()
        state.enabled = false
        pcall(removeSkin)
    end)

    -- the card is taller than a row panel: tell the layout
    holder.Size = UDim2.fromOffset(240, 22 + 270)
    layoutPreview()
end, function(err)
    warn("[shitaro/skins] " .. tostring(err) .. "\n" .. debug.traceback())
end)
end
