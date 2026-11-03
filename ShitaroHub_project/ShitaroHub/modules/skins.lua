-- modules/skins.lua - skins tab
-- A card with the anime girl: click it to swap your character's look for her
-- model, "reset" brings your own avatar back. Client side only: nobody else
-- sees it.
-- Returns function(ctx); ctx is built by core/ui.lua (shared UI helpers).
--
-- How the swap works
--   models/angel_v1.pack holds the model as 36 Roblox .mesh pieces (one per
--   body part and texture) plus textures. The pack is downloaded once into
--   the executor workspace (ShitaroHub/cache/angel_v1), then every piece is a
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

    local PACK_PATH = "models/angel_v1.pack"
    local PACK_NAME = "angel_v1"
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

    local function restoreOriginal()
        for item, value in pairs(hidden) do
            pcall(function()
                item.Transparency = value
            end)
        end

        hidden = {}
    end

    local function removeSkin()
        clearWatchers()
        restoreOriginal()

        if skinFolder then
            pcall(function()
                skinFolder:Destroy()
            end)

            skinFolder = nil
        end
    end

    local function hide(item)
        if skinFolder and item:IsDescendantOf(skinFolder) then
            return
        end

        if item:IsA("BasePart") or item:IsA("Decal")
            or item:IsA("Texture") then
            -- the root part is already invisible, tools must stay visible
            if item.Name == "HumanoidRootPart"
                or item:FindFirstAncestorOfClass("Tool") then
                return
            end

            if hidden[item] == nil then
                hidden[item] = item.Transparency
            end

            item.Transparency = 1
        end
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
        local origin = CFrame.new(0, bottom, 0)

        removeSkin()

        skinFolder = Instance.new("Folder")
        skinFolder.Name = "ShitaroSkin"
        skinFolder.Parent = char

        for _, piece in ipairs(description.pieces) do
            local part = char:FindFirstChild(
                r6 and R6_PART[piece.group] or piece.group
            )

            if part and rest[part] then
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

                carrier.CFrame = root.CFrame * origin

                local mesh = Instance.new("SpecialMesh")
                mesh.MeshType = Enum.MeshType.FileMesh
                mesh.MeshId = assetUrl(meshFile)
                mesh.TextureId = assetUrl(CACHE_DIR .. "/" .. piece.texture)
                mesh.Scale = Vector3.new(scale, scale, scale)
                mesh.Parent = carrier

                local weld = Instance.new("Weld")
                weld.Part0 = part
                weld.Part1 = carrier
                weld.C0 = rest[part]:Inverse() * origin
                weld.C1 = CFrame.new()
                weld.Parent = carrier

                carrier.Parent = skinFolder
            end
        end

        -- hide the real avatar now and whatever it loads later (hats, face)
        for _, item in ipairs(char:GetDescendants()) do
            hide(item)
        end

        watchers[#watchers + 1] = char.DescendantAdded:Connect(function(item)
            task.defer(hide, item)
        end)
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

    -- keep the skin through respawns
    connect(player.CharacterAdded, function(char)
        removeSkin()

        if not state.enabled then
            return
        end

        task.spawn(function()
            local hum = char:WaitForChild("Humanoid", 10)
            char:WaitForChild("HumanoidRootPart", 10)

            if not hum or not state.enabled then
                return
            end

            waitForAppearance(char)

            if state.enabled and not state.busy then
                state.busy = true
                paintCard()

                local ok, err = pcall(function()
                    local live, humanoid, root = liveCharacter()

                    if live then
                        buildSkin(live, humanoid, root)
                    end
                end)

                state.busy = false

                if not ok then
                    failure(err)
                end

                paintCard()
            end
        end)
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
