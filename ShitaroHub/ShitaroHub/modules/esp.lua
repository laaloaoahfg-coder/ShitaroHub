-- modules/esp.lua - ESP
-- box, line, name, distance, skeleton, health + visuals tab
-- Returns function(ctx); ctx is built by core/ui.lua (shared UI helpers).

return function(ctx)
local playerGui, make, player, Players, uiState, gui, connect, RunService, pageScroll, tabs, panelWidths, window, PANEL_RESERVE, previewPanel, panelGapBefore, colors, corner, animate, picker, previewRow, localize, rowSlider, layoutPreview =
    ctx.playerGui,
    ctx.make,
    ctx.player,
    ctx.Players,
    ctx.uiState,
    ctx.gui,
    ctx.connect,
    ctx.RunService,
    ctx.pageScroll,
    ctx.tabs,
    ctx.panelWidths,
    ctx.window,
    ctx.PANEL_RESERVE,
    ctx.previewPanel,
    ctx.panelGapBefore,
    ctx.colors,
    ctx.corner,
    ctx.animate,
    ctx.picker,
    ctx.previewRow,
    ctx.localize,
    ctx.rowSlider,
    ctx.layoutPreview

-- Visuals / ESP ------------------------------------------------------------
--
-- Rendering uses plain Frames in a separate ScreenGui, so it does not depend
-- on the executor's Drawing library. Everything lives in one closure: it adds
-- nothing to the main chunk's 200-local budget, and a failure here can never
-- break the menu (errors are only printed with warn).
--
-- Rig detection is structural (UpperTorso/LowerTorso = R15, Torso = R6,
-- anything else = generic Motor6D skeleton), not trusted from Humanoid.RigType,
-- because custom games often lie about it.

xpcall(function()
    local Workspace = game:GetService("Workspace")
    local floor, ceil, clamp = math.floor, math.ceil, math.clamp
    local huge = math.huge

    local FEATURES = {
        "box", "line", "name", "distance", "skeleton", "health",
    }

    local RED = Color3.fromRGB(255, 72, 72)
    local GREEN = Color3.fromRGB(72, 255, 112)
    local WHITE = Color3.new(1, 1, 1)
    local BLACK = Color3.new(0, 0, 0)
    local ORANGE = Color3.fromRGB(255, 150, 40)
    local BLUE = Color3.fromRGB(64, 140, 255)
    local BOT_NAME = "бот"

    -- where the line starts on the screen: "top" | "center" | "bottom"
    local LINE_ORIGIN = "top"

    -- Stale data: with streaming, a far player's parts can stop updating. A
    -- player further than STALE_MIN_DIST whose position did not change for
    -- STALE_AFTER seconds is "unverified" (also true for a player who really
    -- stands still). STALE_MODE: "mark" = draw with a "?" after name/distance,
    -- "hide" = do not draw.
    -- cover / skeleton cadence (see drawEntity)
    local COVER_INTERVAL = 0.1
    local COVER_FAR_INTERVAL = 0.25
    local COVER_FAR_DIST = 200
    local SKELETON_FAR_DIST = 80

    local STALE_AFTER = 3
    local STALE_MIN_DIST = 60
    local STALE_MODE = "hide"

    -- Roblox: 1 stud = 0.28 m. The game HUD shows metres, so the ESP distance
    -- label and the range slider (0-800) use metres as well.
    local STUDS_TO_M = 0.28

    local cfg = {
        enabled = {},
        palette = {},
        ignoreTeam = false,
        ignoreFriends = false,
        range = 500,
    }

    for _, key in ipairs(FEATURES) do
        cfg.enabled[key] = false
        -- visible = enemy is exposed (red), hidden = behind cover (green)
        cfg.palette[key] = { visible = RED, hidden = GREEN }
    end

    -- bots: orange = exposed, blue = behind cover
    cfg.enabled.bots = false
    cfg.palette.bots = { visible = ORANGE, hidden = BLUE }

    -- Overlay -----------------------------------------------------------------

    local stale = playerGui:FindFirstChild("ShitaroESP")

    if stale then
        stale:Destroy()
    end

    local overlay = make("ScreenGui", {
        Name = "ShitaroESP",
        IgnoreGuiInset = true,
        ResetOnSpawn = false,
        ScreenInsets = Enum.ScreenInsets.None,
        ClipToDeviceSafeArea = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 9000,
    }, playerGui)

    -- Rig descriptions --------------------------------------------------------
    -- Each point is {part name, mode}: mode 1 = part centre, 2 = top centre,
    -- 3 = bottom centre. Using part extents instead of joint names keeps the
    -- skeleton correct for scaled characters.

    local RIGS = {
        R15 = {
            points = {
                { "Head", 1 },              -- 1
                { "UpperTorso", 2 },        -- 2 neck
                { "LowerTorso", 1 },        -- 3 pelvis
                { "LeftUpperArm", 2 },      -- 4 shoulder
                { "LeftUpperArm", 3 },      -- 5 elbow
                { "LeftLowerArm", 3 },      -- 6 wrist
                { "LeftHand", 3 },          -- 7 fingertip
                { "RightUpperArm", 2 },     -- 8
                { "RightUpperArm", 3 },     -- 9
                { "RightLowerArm", 3 },     -- 10
                { "RightHand", 3 },         -- 11
                { "LeftUpperLeg", 2 },      -- 12 hip
                { "LeftUpperLeg", 3 },      -- 13 knee
                { "LeftLowerLeg", 3 },      -- 14 ankle
                { "LeftFoot", 3 },          -- 15 sole
                { "RightUpperLeg", 2 },     -- 16
                { "RightUpperLeg", 3 },     -- 17
                { "RightLowerLeg", 3 },     -- 18
                { "RightFoot", 3 },         -- 19
            },
            bones = {
                { 1, 2 }, { 2, 3 },
                { 2, 4 }, { 4, 5 }, { 5, 6 }, { 6, 7 },
                { 2, 8 }, { 8, 9 }, { 9, 10 }, { 10, 11 },
                { 3, 12 }, { 12, 13 }, { 13, 14 }, { 14, 15 },
                { 3, 16 }, { 16, 17 }, { 17, 18 }, { 18, 19 },
            },
            body = "UpperTorso",
            feet = { "LeftFoot", "RightFoot" },
        },

        R6 = {
            points = {
                { "Head", 1 },              -- 1
                { "Torso", 2 },             -- 2 neck
                { "Torso", 3 },             -- 3 pelvis
                { "Left Arm", 2 },          -- 4 shoulder
                { "Left Arm", 3 },          -- 5 hand
                { "Right Arm", 2 },         -- 6
                { "Right Arm", 3 },         -- 7
                { "Left Leg", 2 },          -- 8 hip
                { "Left Leg", 3 },          -- 9 sole
                { "Right Leg", 2 },         -- 10
                { "Right Leg", 3 },         -- 11
            },
            bones = {
                { 1, 2 }, { 2, 3 },
                { 2, 4 }, { 4, 5 },
                { 2, 6 }, { 6, 7 },
                { 3, 8 }, { 8, 9 },
                { 3, 10 }, { 10, 11 },
            },
            body = "Torso",
            feet = { "Left Leg", "Right Leg" },
        },
    }

    local CORNERS = {}

    for _, sx in ipairs({ -1, 1 }) do
        for _, sy in ipairs({ -1, 1 }) do
            for _, sz in ipairs({ -1, 1 }) do
                table.insert(CORNERS, Vector3.new(sx, sy, sz))
            end
        end
    end

    local function buildRig(char, now)
        local rig = {
            char = char,
            parts = {},
            modes = {},
            bones = {},
            count = 0,
            feet = {},
            samples = {},
            retry = now + 1,
        }

        rig.head = char:FindFirstChild("Head")

        local def

        if char:FindFirstChild("UpperTorso")
            and char:FindFirstChild("LowerTorso") then
            def = RIGS.R15
            rig.kind = "R15"
        elseif char:FindFirstChild("Torso") then
            def = RIGS.R6
            rig.kind = "R6"
        else
            rig.kind = "generic"
        end

        rig.root = char:FindFirstChild("HumanoidRootPart")
            or char.PrimaryPart

        if def then
            rig.body = char:FindFirstChild(def.body)
            rig.root = rig.root or rig.body
            rig.bones = def.bones
            rig.count = #def.points

            local complete = rig.head ~= nil and rig.body ~= nil

            for index, entry in ipairs(def.points) do
                local part = char:FindFirstChild(entry[1])

                if part and part:IsA("BasePart") then
                    rig.parts[index] = part
                else
                    complete = false
                end

                rig.modes[index] = entry[2]
            end

            for _, name in ipairs(def.feet) do
                local foot = char:FindFirstChild(name)

                if foot and foot:IsA("BasePart") then
                    table.insert(rig.feet, foot)
                else
                    complete = false
                end
            end

            -- a rig that is still streaming in is re-scanned every second
            if complete then
                rig.retry = huge
            end
        else
            rig.root = rig.root or char:FindFirstChildWhichIsA("BasePart")

            local index = {}

            local function point(part)
                local found = index[part]

                if not found then
                    rig.count = rig.count + 1
                    found = rig.count
                    index[part] = found
                    rig.parts[found] = part
                    rig.modes[found] = 1
                end

                return found
            end

            for _, item in ipairs(char:GetDescendants()) do
                if #rig.bones >= 30 then
                    break
                end

                if item:IsA("Motor6D") then
                    local a, b = item.Part0, item.Part1

                    if a and b
                        and a:IsA("BasePart") and b:IsA("BasePart")
                        and a ~= rig.root and b ~= rig.root then
                        table.insert(rig.bones, { point(a), point(b) })
                    end
                end
            end
        end

        if rig.head then
            table.insert(rig.samples, rig.head)
        end

        if rig.root then
            table.insert(rig.samples, rig.root)
        end

        if rig.feet[1] then
            table.insert(rig.samples, rig.feet[1])
        end

        return rig
    end

    -- Coherence ----------------------------------------------------------------
    -- With streaming, the parts of ONE character can arrive at different times:
    -- the root may already be at the real position while head / feet / limbs
    -- still sit at an old one. Mixing them gives boxes floating in the sky or
    -- shifted sideways. Every part is compared with a reference part; parts
    -- further than SPAN studs from the best-agreeing group are ignored.
    local SPAN = 12
    local SPAN2 = SPAN * SPAN

    local function coherence(rig)
        local list = rig.list

        if not list then
            list = {}
            local seen = {}

            local function add(part)
                if part and not seen[part] then
                    seen[part] = true
                    list[#list + 1] = part
                end
            end

            add(rig.root)
            add(rig.head)
            add(rig.body)

            for index = 1, rig.count do
                add(rig.parts[index])
            end

            for _, foot in ipairs(rig.feet) do
                add(foot)
            end

            rig.list = list
            rig.valid = {}
        end

        -- Same rule as before (root, then body, then head; the first one with
        -- the largest agreeing group wins), but every part position is read
        -- once instead of three times, the distances are compared squared (no
        -- square root), and the freshness signature is summed in the same pass
        -- - this used to be the hottest loop of the renderer.
        local refs = rig.refs

        if not refs then
            refs = { {}, {}, {} }
            rig.refs = refs
        end

        for index = 1, 3 do
            local candidate

            if index == 1 then
                candidate = rig.root
            elseif index == 2 then
                candidate = rig.body
            else
                candidate = rig.head
            end

            local slot = refs[index]

            if candidate and candidate.Parent then
                slot.pos = candidate.Position
            else
                slot.pos = nil
            end

            slot.agree = 0
        end

        for j = 1, #list do
            local part = list[j]

            if part.Parent then
                local pos = part.Position

                for index = 1, 3 do
                    local slot = refs[index]
                    local ref = slot.pos

                    if ref then
                        local dx, dy, dz = pos.X - ref.X, pos.Y - ref.Y, pos.Z - ref.Z

                        if dx * dx + dy * dy + dz * dz <= SPAN2 then
                            slot.agree = slot.agree + 1
                        end
                    end
                end
            end
        end

        -- The root is a physics part and always carries the live position.
        -- Head / limbs are animated and can freeze while the player is off
        -- screen or behind a wall; that stale group used to outvote the root
        -- and the box stayed where the player had been. The vote below only
        -- decides when there is no root at all.
        local bestPos, bestCount = nil, 0

        if refs[1].pos then
            bestPos, bestCount = refs[1].pos, refs[1].agree
        else
            for index = 2, 3 do
                local slot = refs[index]

                if slot.pos and slot.agree > bestCount then
                    bestCount = slot.agree
                    bestPos = slot.pos
                end
            end
        end

        if not bestPos then
            return nil
        end

        local valid = rig.valid
        table.clear(valid)

        local signature = Vector3.zero
        local total = 0
        local bx, by, bz = bestPos.X, bestPos.Y, bestPos.Z

        for j = 1, #list do
            local part = list[j]

            if part.Parent then
                total = total + 1

                local pos = part.Position
                local dx, dy, dz = pos.X - bx, pos.Y - by, pos.Z - bz

                if dx * dx + dy * dy + dz * dz <= SPAN2 then
                    valid[part] = true
                    signature = signature + pos
                end
            end
        end

        valid.all = bestCount == total

        return bestPos, valid, signature
    end

    -- Returns an oriented box: CFrame, local centre offset, half extents.
    -- Built from the root part, so it is stable while limbs animate and it
    -- follows a rotated (ragdolled / lying) character. The proportions
    -- (height above / below the root, half width, half depth) are measured
    -- while head and feet agree with the root and reused when they freeze.
    local function boxSpec(rig, valid, anchor)
        local root = rig.root
        local head = rig.head
        local feet = rig.feet
        local rootOk = root and root.Parent and valid[root]

        if rootOk and head and head.Parent and valid[head] and #feet > 0 then
            -- The box is aligned to the WORLD (yaw only), not to the root part:
            -- when the root tilts (lean / crouch / custom animation) a box built
            -- in the root's local space is shoved sideways.
            local look = root.CFrame.LookVector

            if look.X * look.X + look.Z * look.Z < 0.09 then
                look = head.CFrame.LookVector
            end

            local yaw = math.atan2(-look.X, -look.Z)
            local body = rig.body
            local centre = body and valid[body] and body.Position
                or root.Position

            local top = head.Position.Y + head.Size.Y * 0.5
            local bottom = huge

            for _, foot in ipairs(feet) do
                if foot.Parent and valid[foot] then
                    local y = foot.Position.Y - foot.Size.Y * 0.5

                    if y < bottom then
                        bottom = y
                    end
                end
            end

            if bottom < top then
                local halfWidth = body and body.Size.X * 0.85 or 1.7
                local halfDepth = body and body.Size.Z * 0.5 or 0.5
                local rootY = root.Position.Y

                rig.topOff = top - rootY
                rig.botOff = bottom - rootY
                rig.halfW = halfWidth
                rig.halfD = halfDepth
                rig.yaw = yaw

                return CFrame.new(centre.X, 0, centre.Z)
                        * CFrame.Angles(0, yaw, 0),
                    Vector3.new(0, (top + bottom) * 0.5, 0),
                    Vector3.new(halfWidth, (top - bottom) * 0.5, halfDepth)
            end
        end

        -- head / feet froze (or are still streaming): a root-anchored box from
        -- the proportions measured earlier
        if rootOk and rig.topOff then
            local look = root.CFrame.LookVector
            local yaw = rig.yaw or 0

            if look.X * look.X + look.Z * look.Z >= 0.09 then
                yaw = math.atan2(-look.X, -look.Z)
                rig.yaw = yaw
            end

            local rootPos = root.Position
            local top = rootPos.Y + rig.topOff
            local bottom = rootPos.Y + rig.botOff

            return CFrame.new(rootPos.X, 0, rootPos.Z)
                    * CFrame.Angles(0, yaw, 0),
                Vector3.new(0, (top + bottom) * 0.5, 0),
                Vector3.new(rig.halfW, (top - bottom) * 0.5, rig.halfD)
        end

        -- unknown model shape: its bounding box is the only size there is.
        -- R6 / R15 never use it (weapons and accessories would fatten the box)
        if valid.all and rig.kind == "generic" then
            local cf, size = rig.char:GetBoundingBox()
            return cf, Vector3.zero, size * 0.5
        end

        return CFrame.new(anchor), Vector3.zero, Vector3.new(1.8, 3, 1)
    end

    -- Visibility ---------------------------------------------------------------

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.IgnoreWater = true

    -- Casts camera -> point. Invisible parts and other characters do not count
    -- as cover; walls, terrain and props do.
    local function isBlocked(from, to, filter)
        local direction = to - from

        for _ = 1, 4 do
            rayParams.FilterDescendantsInstances = filter

            local hit = Workspace:Raycast(from, direction, rayParams)

            if not hit then
                return false
            end

            local part = hit.Instance

            if part:IsA("Terrain") then
                return true
            end

            local model = part:FindFirstAncestorOfClass("Model")

            if model and model:FindFirstChildOfClass("Humanoid") then
                filter[#filter + 1] = model
            elseif part.Transparency >= 0.9 then
                filter[#filter + 1] = part
            else
                return true
            end
        end

        return true
    end

    local function isExposed(rig, camPos, localChar, valid)
        for index = 1, #rig.samples do
            local part = rig.samples[index]

            if part.Parent and valid[part] then
                local filter = { rig.char }

                if localChar then
                    filter[2] = localChar
                end

                if not isBlocked(camPos, part.Position, filter) then
                    return true
                end
            end
        end

        return false
    end

    -- Player filters -----------------------------------------------------------

    local friendCache = {}

    local function refreshFriend(target)
        task.spawn(function()
            local ok, result = pcall(
                player.IsFriendsWith,
                player,
                target.UserId
            )

            friendCache[target.UserId] = ok and result == true
        end)
    end

    -- Folder-based sides (Lost Front): no Roblox teams and no attributes, the
    -- side is the folder the character sits in:
    -- Workspace.<root>.<team folder>.<nick>. Folder names are obfuscated, so
    -- they are never hardcoded: a teammate is whoever shares MY folder.
    -- Dead / spectating characters sit directly in Workspace (no folder).
    local myTeamFolder
    local folderModeAt, folderMode = -huge, false

    local function teamFolderOf(char)
        local parent = char and char.Parent

        if parent and parent ~= Workspace then
            return parent
        end

        return nil
    end

    -- The folder rule is trusted only when at least two different folders
    -- hold characters. Modes where everybody shares one folder (Defusal:
    -- Workspace.Players) must not turn the whole lobby into "teammates".
    local function hasTeamFolders()
        local now = os.clock()

        if now - folderModeAt < 1 then
            return folderMode
        end

        folderModeAt = now
        folderMode = false

        local first

        for _, other in ipairs(Players:GetPlayers()) do
            local folder = teamFolderOf(other.Character)

            if folder then
                if not first then
                    first = folder
                elseif folder ~= first then
                    folderMode = true
                    break
                end
            end
        end

        return folderMode
    end

    -- Players:GetPlayers() builds a new table on every call, and that used to
    -- happen once per frame. One list is kept and refreshed only when the
    -- roster really changes.
    local roster = {}

    local function refreshRoster()
        local list = Players:GetPlayers()

        for index = 1, #list do
            roster[index] = list[index]
        end

        for index = #list + 1, #roster do
            roster[index] = nil
        end
    end

    refreshRoster()

    -- Sides ----------------------------------------------------------------------
    --
    -- Which side a player is on lives in a different place in every game, so it
    -- is read from every place games commonly keep it, in this order:
    --   1. the Roblox Team;
    --   2. attributes on the player, then the character, then its Humanoid;
    --   3. value objects (StringValue, IntValue, ...) directly on the player,
    --      inside its leaderstats / leaderboard folder, or on the character;
    --   4. the folder the character sits in (Lost Front).
    -- Only names from SIDE_ORDER count (case and punctuation are ignored), so
    -- unrelated values such as "TeamKills" or "device" are never mistaken for a
    -- side. "Spectator" / "neutral" / "none" style values are not a side.
    --
    -- Everything else (isTeammate, the aimbot, the dump) goes through sideOf,
    -- which is cached: GetAttributes builds a new table on every call and the
    -- filter is asked once per player per frame.

    local SIDE_ORDER = {
        "team", "teamname", "teamid", "teamnumber", "teamindex",
        "teamcolor", "teamcolour", "side", "sidename", "sideid",
        "faction", "factionname", "alliance",
    }

    local SIDE_NAMES = {}

    for _, id in ipairs(SIDE_ORDER) do
        SIDE_NAMES[id] = true
    end

    local STATS_NAMES = { leaderstats = true, leaderboard = true, stats = true }

    local NO_SIDE = {
        [""] = true, spectator = true, spectators = true, spectating = true,
        spec = true, neutral = true, none = true, ["nil"] = true,
        null = true, lobby = true, dead = true, unassigned = true,
        noteam = true, waiting = true,
    }

    local function normalizeName(name)
        return (string.gsub(string.lower(name), "[^%w]", ""))
    end

    -- value -> comparable text, or nil when it does not name a side
    local function sideText(value)
        local kind = typeof(value)

        if kind == "string" then
            local text = string.lower(string.match(value, "^%s*(.-)%s*$"))

            if NO_SIDE[text] then
                return nil
            end

            return text
        elseif kind == "number" or kind == "Color3" or kind == "BrickColor" then
            return tostring(value)
        elseif kind == "Instance" then
            local text = string.lower(value.Name)

            if NO_SIDE[text] then
                return nil
            end

            return text
        end

        return nil
    end

    -- scratch tables: one scan fills them, pickFound reads them
    local foundValue, foundName = {}, {}

    local function pickFound()
        for _, id in ipairs(SIDE_ORDER) do
            local value = foundValue[id]

            if value ~= nil then
                local text = sideText(value)

                if text then
                    return id, text, foundName[id]
                end
            end
        end

        return nil
    end

    local function attributeSide(inst, label)
        if not inst then
            return nil
        end

        table.clear(foundValue)
        table.clear(foundName)

        for name, value in pairs(inst:GetAttributes()) do
            local id = normalizeName(name)

            if SIDE_NAMES[id] then
                foundValue[id] = value
                foundName[id] = name
            end
        end

        local id, text, name = pickFound()

        if not id then
            return nil
        end

        return "attr:" .. id .. ":" .. text, "attr",
            label .. " attr " .. name .. "=" .. text
    end

    local function valueSide(inst, label)
        if not inst then
            return nil
        end

        table.clear(foundValue)
        table.clear(foundName)

        for _, child in ipairs(inst:GetChildren()) do
            if child:IsA("ValueBase") then
                local id = normalizeName(child.Name)

                if SIDE_NAMES[id] then
                    foundValue[id] = child.Value
                    foundName[id] = child.Name
                end
            end
        end

        local id, text, name = pickFound()

        if not id then
            return nil
        end

        return "value:" .. id .. ":" .. text, "value",
            label .. " value " .. name .. "=" .. text
    end

    local function statsOf(target)
        for _, child in ipairs(target:GetChildren()) do
            if STATS_NAMES[normalizeName(child.Name)] then
                return child
            end
        end

        return nil
    end

    -- Uncached lookup: returns key, kind, via (via is for the dump only).
    local function resolveSide(target)
        local team = target.Team

        if team ~= nil then
            return "team:" .. team.Name, "team", "Team " .. team.Name
        end

        local char = target.Character
        local human = char and char:FindFirstChildOfClass("Humanoid")
        local key, kind, via

        key, kind, via = attributeSide(target, "player")

        if key then
            return key, kind, via
        end

        key, kind, via = attributeSide(char, "character")

        if key then
            return key, kind, via
        end

        key, kind, via = attributeSide(human, "humanoid")

        if key then
            return key, kind, via
        end

        key, kind, via = valueSide(target, "player")

        if key then
            return key, kind, via
        end

        key, kind, via = valueSide(statsOf(target), "leaderstats")

        if key then
            return key, kind, via
        end

        key, kind, via = valueSide(char, "character")

        if key then
            return key, kind, via
        end

        if hasTeamFolders() then
            local folder = teamFolderOf(char)

            if folder then
                return "folder:" .. folder:GetFullName(), "folder",
                    "folder " .. folder.Name
            end
        end

        return nil
    end

    local SIDE_TTL = 0.5
    local sideCache = setmetatable({}, { __mode = "k" })

    local function sideOf(target, now)
        local cached = sideCache[target]

        if cached and now - cached.at < SIDE_TTL then
            return cached.key, cached.kind, cached.via
        end

        local key, kind, via = resolveSide(target)

        if not cached then
            cached = {}
            sideCache[target] = cached
        end

        cached.key, cached.kind, cached.via, cached.at = key, kind, via, now

        return key, kind, via
    end

    -- Teams are not always a real thing: some modes give everybody the same
    -- team (or the same team attribute), and filtering "teammates" there left
    -- no targets at all. The filter therefore only applies while the game
    -- really has a second side in play, measured on the same kind of source
    -- as my own. My last known side is remembered, because a dead or
    -- spectating local player has no side of his own to read.
    local sidesOn = false
    local sidesAt = -1
    local mySide, myKind

    local function refreshSides(now)
        if now - sidesAt < 1 then
            return
        end

        sidesAt = now
        sidesOn = false

        local key, kind = sideOf(player, now)

        if key then
            mySide, myKind = key, kind
        end

        if not mySide then
            return
        end

        for index = 1, #roster do
            local other = roster[index]

            if other ~= player then
                local otherKey, otherKind = sideOf(other, now)

                if otherKey and otherKind == myKind and otherKey ~= mySide then
                    sidesOn = true
                    return
                end
            end
        end
    end

    local function isTeammate(target)
        if not sidesOn or not mySide then
            return false
        end

        local key = sideOf(target, os.clock())

        return key ~= nil and key == mySide
    end

    -- shared with the aimbot (it lives in another closure) and the dump
    uiState.isTeammate = isTeammate
    uiState.refreshSides = refreshSides

    local function describeSide(target)
        local key, _, via = resolveSide(target)

        return key and (key .. " [" .. via .. "]") or "none"
    end

    -- Some games keep the real hp in player attributes and never touch
    -- Humanoid.Health. Attributes win when they are numeric.
    local function readHealth(owner, humanoid)
        if owner then
            local hp = owner:GetAttribute("Health")
            local maxHp = owner:GetAttribute("MaxHealth")

            if type(hp) == "number" and type(maxHp) == "number"
                and maxHp > 0 then
                return hp, maxHp
            end
        end

        if humanoid then
            return humanoid.Health, humanoid.MaxHealth
        end

        return nil
    end

    -- Games with custom health / death often leave Humanoid.Health untouched
    -- and flag death with attributes instead.
    local DEAD_FLAGS = {
        "Dead", "IsDead", "Died", "Eliminated", "Downed", "Knocked",
        "Spectating", "Respawning",
    }

    local ALIVE_FLAGS = { "Alive", "IsAlive" }

    local function flagged(inst)
        if not inst then
            return false
        end

        for _, key in ipairs(DEAD_FLAGS) do
            if inst:GetAttribute(key) == true then
                return true
            end
        end

        for _, key in ipairs(ALIVE_FLAGS) do
            if inst:GetAttribute(key) == false then
                return true
            end
        end

        local hp = inst:GetAttribute("Health")

        return type(hp) == "number" and hp <= 0
    end

    -- still in the game, has a character in the world and is not dead
    local function isAlive(target)
        if target.Parent ~= Players then
            return false
        end

        local char = target.Character

        if not char or not char.Parent then
            return false
        end

        if flagged(char) or flagged(target) then
            return false
        end

        local humanoid = char:FindFirstChildOfClass("Humanoid")

        if humanoid then
            if humanoid.Health <= 0
                or humanoid:GetState() == Enum.HumanoidStateType.Dead
                or flagged(humanoid) then
                return false
            end
        end

        return true
    end

    -- Per-player objects -------------------------------------------------------

    local entries = {}
    local botEntries = {}

    local HEALTH_COLORS = ColorSequence.new({
        ColorSequenceKeypoint.new(0.00, Color3.fromRGB(64, 230, 96)),
        ColorSequenceKeypoint.new(0.20, Color3.fromRGB(64, 230, 96)),
        ColorSequenceKeypoint.new(0.50, Color3.fromRGB(255, 214, 40)),
        ColorSequenceKeypoint.new(0.80, Color3.fromRGB(240, 56, 56)),
        ColorSequenceKeypoint.new(1.00, Color3.fromRGB(240, 56, 56)),
    })

    local function textLabel(parent, name, size, anchorY)
        return make("TextLabel", {
            Name = name,
            TextSize = size,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextYAlignment = anchorY == 1
                and Enum.TextYAlignment.Bottom
                or Enum.TextYAlignment.Top,
            AnchorPoint = Vector2.new(0.5, anchorY),
            Size = UDim2.fromOffset(260, size + 3),
            TextStrokeColor3 = BLACK,
            TextStrokeTransparency = 0.35,
            Visible = false,
        }, parent)
    end

    local function createEntry(target, registry, key)
        local holder = make("Frame", {
            Name = target.Name,
            Size = UDim2.fromScale(1, 1),
            Visible = false,
        }, overlay)

        local entry = {
            holder = holder,
            vis = {},
            col = {},
            groups = {},
            bones = {},
            boneVis = {},
            visible = true,
            nameText = target.Name,
            nextVis = os.clock() + math.random() * 0.1,
        }

        -- box: coloured frame + black frames just outside and inside of it
        local function boxFrame(name, color, transparency)
            local frame = make("Frame", {
                Name = name,
                Visible = false,
            }, holder)

            local border = make("UIStroke", {
                Color = color,
                Transparency = transparency,
                Thickness = 1,
                ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
            }, frame)

            return frame, border
        end

        local main, mainStroke = boxFrame("Box", WHITE, 0)
        local outer = boxFrame("BoxOuter", BLACK, 0.35)
        local inner = boxFrame("BoxInner", BLACK, 0.35)

        entry.boxMain, entry.boxStroke = main, mainStroke
        entry.boxOuter, entry.boxInner = outer, inner
        entry.groups.box = { main, outer, inner }

        entry.line = make("Frame", {
            Name = "Line",
            AnchorPoint = Vector2.new(0.5, 0.5),
            Size = UDim2.fromOffset(0, 1),
            BackgroundColor3 = WHITE,
            BackgroundTransparency = 0,
            Visible = false,
        }, holder)

        entry.groups.line = { entry.line }

        entry.name = textLabel(holder, "Name", 8, 1)
        entry.name.Text = target.Name
        entry.groups.name = { entry.name }

        entry.dist = textLabel(holder, "Distance", 12, 0)
        entry.groups.distance = { entry.dist }

        -- health: black plate, bottom-anchored clip, full-height gradient
        local back = make("Frame", {
            Name = "HealthBack",
            BackgroundColor3 = BLACK,
            BackgroundTransparency = 0.35,
            Visible = false,
        }, holder)

        entry.hpStroke = make("UIStroke", {
            Color = WHITE,
            Transparency = 0.2,
            Thickness = 1,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        }, back)

        entry.hpClip = make("Frame", {
            Name = "Clip",
            AnchorPoint = Vector2.new(0, 1),
            ClipsDescendants = true,
        }, back)

        entry.hpFill = make("Frame", {
            Name = "Fill",
            AnchorPoint = Vector2.new(0, 1),
            Position = UDim2.fromScale(0, 1),
            BackgroundColor3 = WHITE,
            BackgroundTransparency = 0,
        }, entry.hpClip)

        make("UIGradient", {
            Rotation = 90,
            Color = HEALTH_COLORS,
        }, entry.hpFill)

        entry.hpBack = back
        -- tiny number centred right under the dash
        entry.hpText = textLabel(holder, "HealthText", 6, 0)
        entry.hpText.TextColor3 = WHITE

        -- short dash across the middle of the bar; it rides the fill edge
        entry.hpMark = make("Frame", {
            Name = "HealthMark",
            Size = UDim2.fromOffset(5, 2),
            BackgroundColor3 = WHITE,
            BackgroundTransparency = 0,
            Visible = false,
        }, holder)

        entry.groups.health = { back, entry.hpText, entry.hpMark }

        registry = registry or entries
        registry[key or target] = entry
        return entry
    end

    local function ensureBones(entry, count)
        for index = #entry.bones + 1, count do
            entry.bones[index] = make("Frame", {
                Name = "Bone",
                AnchorPoint = Vector2.new(0.5, 0.5),
                Size = UDim2.fromOffset(0, 1),
                BackgroundColor3 = entry.col.skeleton or WHITE,
                BackgroundTransparency = 0,
                Visible = false,
            }, entry.holder)

            entry.boneVis[index] = false
        end
    end

    local function setGroup(entry, key, value)
        if entry.vis[key] == value then
            return
        end

        entry.vis[key] = value

        for _, object in ipairs(entry.groups[key]) do
            object.Visible = value
        end
    end

    local function hideEntry(entry)
        if entry and entry.holder.Visible then
            entry.holder.Visible = false
        end
    end

    -- A 1 px line between two screen points (rotated Frame).
    -- `cache` is an optional {x, y, length, rotation} table owned by the entry:
    -- a line that did not move costs nothing, which matters because the
    -- skeleton alone is up to 19 lines per target per frame.
    local function placeLine(frame, ax, ay, bx, by, cache)
        local dx, dy = bx - ax, by - ay
        local length = math.sqrt(dx * dx + dy * dy)

        if length < 0.5 then
            return false
        end

        local px, py = (ax + bx) * 0.5, (ay + by) * 0.5
        local rotation = math.deg(math.atan2(dy, dx))

        if cache
            and cache[1] == px
            and cache[2] == py
            and cache[3] == length
            and cache[4] == rotation then
            return true
        end

        if cache then
            cache[1], cache[2], cache[3], cache[4] = px, py, length, rotation
        end

        frame.Position = UDim2.fromOffset(px, py)
        frame.Size = UDim2.fromOffset(length, 1)
        frame.Rotation = rotation

        return true
    end

    -- Cheap cull: can this character possibly be on screen? Everything is
    -- assumed to sit inside a CULL_MARGIN sphere around the root, and the cone
    -- test is skipped for close targets, so the cull only fires when the box
    -- would have been hidden anyway (roughly half of the server sits behind
    -- the camera at any moment).
    local CULL_MARGIN = 12
    local CULL_NEAR = 40
    local CULL_ANGLE = 40

    local function cullTarget(rootPos, camPos, look, fov)
        local dx = rootPos.X - camPos.X
        local dy = rootPos.Y - camPos.Y
        local dz = rootPos.Z - camPos.Z
        local behind = dx * look.X + dy * look.Y + dz * look.Z

        if behind < -CULL_MARGIN then
            return true
        end

        local reach = math.sqrt(dx * dx + dy * dy + dz * dz)

        if reach <= CULL_NEAR or reach <= CULL_MARGIN then
            return false
        end

        local half = clamp(fov or 70, 1, 120) * 0.5 + CULL_ANGLE

        return behind / reach < math.cos(math.rad(half))
    end

    -- Per-frame drawing --------------------------------------------------------

    -- Shared by players and bots: the entry already exists, the caller has
    -- done its own alive / filter checks. `palette` maps a feature to its
    -- {visible, hidden} colours, `checkStale` enables the frozen-data hide.
    local function drawEntity(entry, char, humanoid, palette, checkStale, cam, camPos, viewport, origin, localChar, now, dt)
        local rig = entry.rig

        if not rig
            or rig.char ~= char
            or now >= rig.retry
            or (rig.root and not rig.root.Parent) then
            rig = buildRig(char, now)
            entry.rig = rig
        end

        local root = rig.root

        if not root then
            return hideEntry(entry)
        end

        -- cheapest test first: nothing behind the camera can be on screen
        if cullTarget(
            root.Position,
            camPos,
            cam.CFrame.LookVector,
            cam.FieldOfView
        ) then
            return hideEntry(entry)
        end

        -- "fresh" = ANY agreeing part of the rig moved: a living player who
        -- stands still still animates, a model that gets no data is frozen.
        -- coherence() sums that signature in the pass it already runs.
        local anchor, valid, signature = coherence(rig)

        if not anchor then
            return hideEntry(entry)
        end

        local distance = (anchor - origin).Magnitude
        local meters = distance * STUDS_TO_M

        if meters > cfg.range then
            return hideEntry(entry)
        end

        if not entry.lastSig
            or (signature - entry.lastSig).Magnitude > 0.02 then
            entry.lastSig = signature
            entry.lastMove = now
        end

        local isStale = checkStale
            and distance > STALE_MIN_DIST
            and now - entry.lastMove > STALE_AFTER

        if isStale and STALE_MODE == "hide" then
            return hideEntry(entry)
        end

        local mark = isStale and "?" or ""

        -- distance to the LAST KNOWN spot + how long ago it was updated
        local ageMark = isStale
            and (" ?" .. floor(now - entry.lastMove) .. "s")
            or ""

        -- screen-space bounds of the oriented box
        local cf, offset, half = boxSpec(rig, valid, anchor)
        local minX, minY, maxX, maxY = huge, huge, -huge, -huge

        for index = 1, 8 do
            local v = cam:WorldToViewportPoint(
                cf * (offset + CORNERS[index] * half)
            )

            if v.Z <= 0.05 then
                return hideEntry(entry)
            end

            if v.X < minX then minX = v.X end
            if v.X > maxX then maxX = v.X end
            if v.Y < minY then minY = v.Y end
            if v.Y > maxY then maxY = v.Y end
        end

        if maxX < 0 or minX > viewport.X or maxY < 0 or minY > viewport.Y then
            return hideEntry(entry)
        end

        minX, minY = floor(minX), floor(minY)
        maxX, maxY = ceil(maxX), ceil(maxY)

        local width = math.max(2, maxX - minX)
        local height = math.max(2, maxY - minY)
        local centerX = (minX + maxX) * 0.5

        -- cover check, throttled and staggered between players; the raycasts
        -- are the most expensive thing in this renderer, and a far target's
        -- exposed/behind-cover state does not change often
        if now >= entry.nextVis then
            entry.nextVis = now + (distance > COVER_FAR_DIST
                and COVER_FAR_INTERVAL
                or COVER_INTERVAL)

            entry.visible = isExposed(rig, camPos, localChar, valid)
        end

        local exposed = entry.visible
        local on = cfg.enabled

        if not entry.holder.Visible then
            entry.holder.Visible = true
        end

        -- box
        if on.box then
            local color = exposed and palette.box.visible
                or palette.box.hidden

            if entry.col.box ~= color then
                entry.col.box = color
                entry.boxStroke.Color = color
            end

            -- six property writes per target per frame: skip them wholesale
            -- when the box sits exactly where it did on the previous frame
            local box = entry.boxGeo

            if not box
                or box[1] ~= minX
                or box[2] ~= minY
                or box[3] ~= width
                or box[4] ~= height then
                if not box then
                    box = {}
                    entry.boxGeo = box
                end

                box[1], box[2], box[3], box[4] = minX, minY, width, height

                entry.boxMain.Position = UDim2.fromOffset(minX, minY)
                entry.boxMain.Size = UDim2.fromOffset(width, height)
                entry.boxOuter.Position = UDim2.fromOffset(minX - 1, minY - 1)
                entry.boxOuter.Size = UDim2.fromOffset(width + 2, height + 2)
                entry.boxInner.Position = UDim2.fromOffset(minX + 1, minY + 1)
                entry.boxInner.Size = UDim2.fromOffset(
                    math.max(0, width - 2),
                    math.max(0, height - 2)
                )
            end
        end

        setGroup(entry, "box", on.box)

        -- health bar + dash with the exact hp number
        local hpLevelY

        local hpNow, hpMax

        if on.health then
            hpNow, hpMax = readHealth(Players:GetPlayerFromCharacter(char), humanoid)
        end

        if hpNow then
            local fraction = hpMax > 0
                and clamp(hpNow / hpMax, 0, 1)
                or 1

            if not entry.hp then
                entry.hp = fraction
            end

            -- smooth fill: eases toward the real value
            entry.hp = entry.hp + (fraction - entry.hp) * math.min(1, dt * 14)

            if math.abs(entry.hp - fraction) < 0.002 then
                entry.hp = fraction
            end

            -- top edge of the (eased) fill, kept inside the bar
            hpLevelY = clamp(
                minY + height * (1 - entry.hp),
                minY,
                minY + height
            )

            -- same for the health stack: five writes, skipped when unchanged
            local hpGeo = entry.hpGeo

            if not hpGeo
                or hpGeo[1] ~= minX
                or hpGeo[2] ~= minY
                or hpGeo[3] ~= height
                or hpGeo[4] ~= entry.hp then
                if not hpGeo then
                    hpGeo = {}
                    entry.hpGeo = hpGeo
                end

                hpGeo[1], hpGeo[2] = minX, minY
                hpGeo[3], hpGeo[4] = height, entry.hp

                entry.hpBack.Position = UDim2.fromOffset(minX - 7, minY - 1)
                entry.hpBack.Size = UDim2.fromOffset(5, height + 2)
                entry.hpClip.Position = UDim2.fromOffset(1, height + 1)
                entry.hpClip.Size = UDim2.fromOffset(3, height * entry.hp)
                entry.hpFill.Size = UDim2.fromOffset(3, height)
            end

            -- the number jumps straight to the real value
            local hpNumber = tostring(math.max(0, floor(hpNow + 0.5)))

            if entry.hpText.Text ~= hpNumber then
                entry.hpText.Text = hpNumber
            end

            if entry.hpMarkY ~= hpLevelY or entry.hpMarkX ~= minX then
                entry.hpMarkX, entry.hpMarkY = minX, hpLevelY

                entry.hpMark.Position = UDim2.fromOffset(minX - 7, hpLevelY - 1)
                entry.hpText.Position = UDim2.fromOffset(minX - 4.5, hpLevelY + 1)
            end
        end

        setGroup(entry, "health", hpNow ~= nil)

        -- nickname
        local topY = minY

        if on.name then
            local bottom = minY - 3

            local color = exposed and palette.name.visible
                or palette.name.hidden

            if entry.col.name ~= color then
                entry.col.name = color
                entry.name.TextColor3 = color
            end

            local shownName = entry.nameText .. mark

            if entry.name.Text ~= shownName then
                entry.name.Text = shownName
            end

            if entry.nameX ~= centerX or entry.nameY ~= bottom then
                entry.nameX, entry.nameY = centerX, bottom
                entry.name.Position = UDim2.fromOffset(centerX, bottom)
            end

            topY = bottom - 10
        end

        setGroup(entry, "name", on.name)

        -- distance
        if on.distance then
            local color = exposed and palette.distance.visible
                or palette.distance.hidden

            if entry.col.distance ~= color then
                entry.col.distance = color
                entry.dist.TextColor3 = color
            end

            local text = floor(meters + 0.5) .. "m" .. ageMark

            if entry.distText ~= text then
                entry.distText = text
                entry.dist.Text = text
            end

            if entry.distX ~= centerX or entry.distY ~= maxY then
                entry.distX, entry.distY = centerX, maxY
                entry.dist.Position = UDim2.fromOffset(centerX, maxY + 2)
            end
        end

        setGroup(entry, "distance", on.distance)

        -- line: screen anchor -> top centre of the box
        if on.line then
            local color = exposed and palette.line.visible
                or palette.line.hidden

            if entry.col.line ~= color then
                entry.col.line = color
                entry.line.BackgroundColor3 = color
            end

            local startX = viewport.X * 0.5
            local startY = 0

            if LINE_ORIGIN == "bottom" then
                startY = viewport.Y
            elseif LINE_ORIGIN == "center" then
                startY = viewport.Y * 0.5
            end

            local lineCache = entry.lineCache

            if not lineCache then
                lineCache = {}
                entry.lineCache = lineCache
            end

            local drawn = placeLine(
                entry.line, startX, startY, centerX, topY, lineCache
            )
            setGroup(entry, "line", drawn)
        else
            setGroup(entry, "line", false)
        end

        -- skeleton
        local bones = rig.bones

        -- Show at 12 px, keep until 8 px. With one threshold the box height
        -- jitters by a pixel and the whole skeleton blinked on and off.
        local skeletonOn = on.skeleton
            and height >= (entry.skeletonShown and 8 or 12)
            and #bones > 0
        local skeletonTick = true

        if skeletonOn and distance > SKELETON_FAR_DIST then
            -- far targets: the bones are a few pixels, updating them every
            -- other frame is invisible and halves the bone work
            entry.skelFlip = not entry.skelFlip

            if entry.skelFlip then
                skeletonTick = false
            end
        end

        if skeletonOn and skeletonTick then
            ensureBones(entry, #bones)

            local projected = entry.projected

            if not projected then
                projected = {}
                entry.projected = projected
            end

            for index = 1, rig.count do
                local part = rig.parts[index]
                local point = false

                if part and part.Parent and valid[part] then
                    local mode = rig.modes[index]
                    local world

                    if mode == 1 then
                        world = part.Position
                    elseif mode == 2 then
                        world = part.CFrame
                            * Vector3.new(0, part.Size.Y * 0.5, 0)
                    else
                        world = part.CFrame
                            * Vector3.new(0, -part.Size.Y * 0.5, 0)
                    end

                    local v = cam:WorldToViewportPoint(world)

                    if v.Z > 0 then
                        point = v
                    end
                end

                projected[index] = point
            end

            local color = exposed and palette.skeleton.visible
                or palette.skeleton.hidden

            if entry.col.skeleton ~= color then
                entry.col.skeleton = color

                for _, frame in ipairs(entry.bones) do
                    frame.BackgroundColor3 = color
                end
            end

            local boneCache = entry.boneCache

            if not boneCache then
                boneCache = {}
                entry.boneCache = boneCache
            end

            for index, bone in ipairs(bones) do
                local a, b = projected[bone[1]], projected[bone[2]]
                local frame = entry.bones[index]
                local drawn = false

                if a and b then
                    local cache = boneCache[index]

                    if not cache then
                        cache = {}
                        boneCache[index] = cache
                    end

                    drawn = placeLine(frame, a.X, a.Y, b.X, b.Y, cache)
                end

                if entry.boneVis[index] ~= drawn then
                    entry.boneVis[index] = drawn
                    frame.Visible = drawn
                end
            end

            entry.skeletonShown = true
        elseif not skeletonOn and entry.skeletonShown then
            entry.skeletonShown = false

            for index, frame in ipairs(entry.bones) do
                entry.boneVis[index] = false
                frame.Visible = false
            end
        end
    end

    local function drawPlayer(target, cam, camPos, viewport, origin, localChar, now, dt)
        local entry = entries[target]
        local char = target.Character

        if not isAlive(target) then
            return hideEntry(entry)
        end

        local humanoid = char:FindFirstChildOfClass("Humanoid")

        if humanoid and humanoid.Health <= 0 then
            return hideEntry(entry)
        end

        if cfg.ignoreTeam and isTeammate(target) then
            return hideEntry(entry)
        end

        if cfg.ignoreFriends and friendCache[target.UserId] then
            return hideEntry(entry)
        end

        entry = entry or createEntry(target)

        return drawEntity(
            entry, char, humanoid, cfg.palette, true,
            cam, camPos, viewport, origin, localChar, now, dt
        )
    end

    local function anyPlayerEnabled()
        for _, key in ipairs(FEATURES) do
            if cfg.enabled[key] then
                return true
            end
        end

        return false
    end

    local function anyEnabled()
        return anyPlayerEnabled() or cfg.enabled.bots == true
    end

    -- Bots ---------------------------------------------------------------------
    -- A bot is a Model with a Humanoid in Workspace that is not a player's
    -- character. Discovery runs only while the bot ESP is switched on.

    -- Whether a model is our own avatar. Games with custom characters keep a
    -- visible copy that is not player.Character, and once the camera is pulled
    -- back (third person) that copy is no longer culled by the near plane, so
    -- it used to get a bot box on the player himself. Identity is therefore
    -- checked through every handle we have, not just one comparison.
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

            local root = humanoid.RootPart

            if root then
                if ownRoot and root == ownRoot then
                    return true
                end

                -- a copy of the avatar stands exactly where we stand
                if ownRoot and (root.Position - ownRoot.Position).Magnitude < 1.25 then
                    return true
                end
            end
        end

        local cam = Workspace.CurrentCamera

        if cam and cam.CameraSubject == humanoid then
            return true
        end

        if model.Name == player.Name
            or (char and model.Name == char.Name) then
            return true
        end

        return false
    end

    local botHumanoids = {}
    local botLinks = {}

    local function considerBot(item)
        if item:IsA("Humanoid") then
            local model = item.Parent

            if model and model:IsA("Model") then
                botHumanoids[model] = item
            end
        end
    end

    -- getgenv().shitaro_bots() in the executor while bot ESP is on: prints every
    -- model the scan considers a bot, with the reason it was NOT filtered out.
    local function dumpBots()
        for model, humanoid in pairs(botHumanoids) do
            local char = player.Character
            local ownRoot = char
                and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
            local root = humanoid.RootPart
            local distance = root and ownRoot
                and (root.Position - ownRoot.Position).Magnitude
                or -1

            warn(string.format(
                "[shitaro/bots] %s | parent=%s | self=%s | player=%s | dist=%.1f | hp=%.0f",
                model.Name,
                model.Parent and model.Parent:GetFullName() or "-",
                tostring(isOwnAvatar(model, humanoid)),
                tostring(Players:GetPlayerFromCharacter(model) ~= nil),
                distance,
                humanoid.Health
            ))
        end
    end

    pcall(function()
        local env = getgenv and getgenv() or nil

        if env then
            env.shitaro_bots = dumpBots
        end
    end)

    local function stopBotScan()
        for _, link in ipairs(botLinks) do
            link:Disconnect()
        end

        table.clear(botLinks)
        table.clear(botHumanoids)
    end

    local function startBotScan()
        if #botLinks > 0 then
            return
        end

        table.insert(botLinks, Workspace.DescendantAdded:Connect(considerBot))

        table.insert(botLinks, Workspace.DescendantRemoving:Connect(function(item)
            if item:IsA("Humanoid") and botHumanoids[item.Parent] == item then
                botHumanoids[item.Parent] = nil
            end
        end))

        for _, item in ipairs(Workspace:GetDescendants()) do
            considerBot(item)
        end
    end

    -- every feature of a bot uses the one bot palette (orange / blue)
    local botPalette = {}

    for _, key in ipairs(FEATURES) do
        botPalette[key] = cfg.palette.bots
    end

    local function drawBot(model, humanoid, cam, camPos, viewport, origin, localChar, now, dt)
        local entry = botEntries[model]

        if not model.Parent
            or isOwnAvatar(model, humanoid)
            or humanoid.Health <= 0
            or humanoid:GetState() == Enum.HumanoidStateType.Dead
            or flagged(model)
            or flagged(humanoid)
            or Players:GetPlayerFromCharacter(model) then
            return hideEntry(entry)
        end

        entry = entry or createEntry({ Name = BOT_NAME }, botEntries, model)

        return drawEntity(
            entry, model, humanoid, botPalette, false,
            cam, camPos, viewport, origin, localChar, now, dt
        )
    end

    local warned = {}

    local function step(dt)
        if not anyEnabled() then
            for _, entry in pairs(entries) do
                hideEntry(entry)
            end

            for _, entry in pairs(botEntries) do
                hideEntry(entry)
            end

            return
        end

        local cam = Workspace.CurrentCamera

        if not cam then
            return
        end

        local camPos = cam.CFrame.Position
        local viewport = cam.ViewportSize
        local localChar = player.Character

        local localRoot = localChar
            and (localChar:FindFirstChild("HumanoidRootPart")
                or localChar.PrimaryPart)

        local origin = localRoot and localRoot.Position or camPos
        local now = os.clock()

        if cfg.ignoreTeam then
            refreshSides(now)
        end

        for target, entry in pairs(entries) do
            if target.Parent ~= Players then
                entry.holder:Destroy()
                entries[target] = nil
            end
        end

        if anyPlayerEnabled() then
            for index = 1, #roster do
                local target = roster[index]

                if target ~= player then
                    local ok, err = pcall(
                        drawPlayer,
                        target, cam, camPos, viewport, origin, localChar, now, dt
                    )

                    if not ok then
                        hideEntry(entries[target])

                        if not warned[tostring(err)] then
                            warned[tostring(err)] = true
                            warn("[shitaro/esp] " .. tostring(err))
                        end
                    end
                end
            end
        else
            for _, entry in pairs(entries) do
                hideEntry(entry)
            end
        end

        if cfg.enabled.bots then
            for model, entry in pairs(botEntries) do
                if not model.Parent or not botHumanoids[model] then
                    entry.holder:Destroy()
                    botEntries[model] = nil
                end
            end

            for model, humanoid in pairs(botHumanoids) do
                local ok, err = pcall(
                    drawBot,
                    model, humanoid, cam, camPos, viewport, origin, localChar, now, dt
                )

                if not ok then
                    hideEntry(botEntries[model])

                    if not warned[tostring(err)] then
                        warned[tostring(err)] = true
                        warn("[shitaro/esp] " .. tostring(err))
                    end
                end
            end
        else
            for _, entry in pairs(botEntries) do
                hideEntry(entry)
            end
        end
    end

    -- Stream assist ------------------------------------------------------------
    --
    -- With Workspace.StreamingEnabled the server only replicates parts that are
    -- inside the streaming radius around the local player. A far enemy model may
    -- still exist on the client (persistent / not yet streamed out) but its parts
    -- are frozen at the last position the client received, so the ESP draws a
    -- player "standing at spawn" until they come close.
    --
    -- Fix: keep asking the server to stream the area around each enemy's last
    -- known position. The enemy is inside that radius, so fresh data arrives,
    -- the position updates, and the next request is centred on the new position
    -- (the request follows the enemy). Matches start with everyone at spawn, so
    -- the very first known position is already correct.
    -- OFF by default: the requests load the map around every far enemy
    -- (lag) and did not make far positions update in testing.
    local STREAM_ASSIST = false
    local STREAM_INTERVAL = 0.25 -- seconds between sweeps
    local STREAM_TIMEOUT = 0.5   -- max yield per request
    -- skip players that normal streaming already covers (fraction of the radius)
    local STREAM_NEAR_FRACTION = 0.5

    local streamBusy = {}
    local lastKnown = {}

    local function streamAssist()
        if not STREAM_ASSIST or not Workspace.StreamingEnabled then
            return
        end

        if not anyEnabled() then
            return
        end

        local cam = Workspace.CurrentCamera

        if not cam then
            return
        end

        local camPos = cam.CFrame.Position
        local nearRadius = Workspace.StreamingTargetRadius * STREAM_NEAR_FRACTION

        for _, target in ipairs(Players:GetPlayers()) do
            if target ~= player
                and not streamBusy[target]
                and not (cfg.ignoreTeam and isTeammate(target))
                and isAlive(target) then
                local char = target.Character
                local root = char
                    and (char:FindFirstChild("HumanoidRootPart")
                        or char.PrimaryPart)

                if root then
                    lastKnown[target] = root.Position
                end

                -- the model can be streamed out entirely: use the last position
                local position = lastKnown[target]

                if position and (position - camPos).Magnitude > nearRadius then
                    streamBusy[target] = true

                    task.spawn(function()
                        pcall(
                            Workspace.RequestStreamAroundAsync,
                            Workspace,
                            position,
                            STREAM_TIMEOUT
                        )

                        streamBusy[target] = nil
                    end)
                end
            end
        end
    end

    task.spawn(function()
        while gui.Parent do
            pcall(streamAssist)
            task.wait(STREAM_INTERVAL)
        end
    end)

    -- Debug dump: run getgenv().shitaro_dump() in the executor while looking at
    -- a dead / odd player; output goes to the console (F9).
    local function attrText(inst)
        local parts = {}

        for key, value in pairs(inst:GetAttributes()) do
            parts[#parts + 1] = key .. "=" .. tostring(value)
        end

        return #parts > 0 and table.concat(parts, ", ") or "-"
    end

    local function dumpPlayers()
        refreshSides(os.clock())

        warn(string.format(
            "[shitaro/dump] sides: on=%s | mine=%s | me: %s",
            tostring(sidesOn),
            tostring(mySide),
            describeSide(player)
        ))

        for _, target in ipairs(Players:GetPlayers()) do
            if target ~= player then
                local char = target.Character
                local humanoid = char and char:FindFirstChildOfClass("Humanoid")
                local names = {}

                if char then
                    for _, child in ipairs(char:GetChildren()) do
                        names[#names + 1] = child.Name
                    end
                end

                warn(string.format(
                    "[shitaro/dump] %s | alive=%s team=%s | side=%s | teammate=%s | player attrs: %s | char attrs: %s | hum: %s | children: %s",
                    target.Name,
                    tostring(isAlive(target)),
                    tostring(target.Team),
                    describeSide(target),
                    tostring(isTeammate(target)),
                    attrText(target),
                    char and attrText(char) or "no char",
                    humanoid and (
                        "hp=" .. humanoid.Health
                        .. " state=" .. tostring(humanoid:GetState())
                        .. " attrs: " .. attrText(humanoid)
                    ) or "none",
                    table.concat(names, ",")
                ))
            end
        end
    end

    pcall(function()
        getgenv().shitaro_dump = dumpPlayers
    end)

    -- Lifecycle ----------------------------------------------------------------

    for _, target in ipairs(Players:GetPlayers()) do
        refreshFriend(target)
    end

    connect(Players.PlayerAdded, refreshRoster)
    connect(Players.PlayerAdded, refreshFriend)

    connect(Players.PlayerRemoving, function(target)
        refreshRoster()

        local entry = entries[target]

        if entry then
            entry.holder:Destroy()
            entries[target] = nil
        end

        friendCache[target.UserId] = nil
        lastKnown[target] = nil
        streamBusy[target] = nil
    end)

    -- runs after the FINAL camera of the frame: the camera block writes the
    -- field of view at RenderPriority.Last - 1 and the aimbot works at Last,
    -- so boxes are drawn one step later or they would lag behind (or sit
    -- beside) a zoomed / free camera
    local stepName = "ShitaroESP"
        .. tostring(floor(os.clock() * 1000))
        .. tostring(math.random(1000, 9999))

    local bound = pcall(function()
        RunService:BindToRenderStep(
            stepName,
            Enum.RenderPriority.Last.Value + 1,
            step
        )
    end)

    if not bound then
        connect(RunService.RenderStepped, step)
    end

    -- not registered through connect(): that list is disconnected first
    gui.Destroying:Connect(function()
        pcall(function()
            RunService:UnbindFromRenderStep(stepName)
        end)

        pcall(stopBotScan)
        overlay:Destroy()
    end)

    -- Menu: visuals tab --------------------------------------------------------

    local visualsScroll = pageScroll(tabs[3].page, "VisualsScroll")
    panelWidths[visualsScroll] = window.Size.X.Offset - PANEL_RESERVE

    local espCard = previewPanel(visualsScroll, "esp.panel", 1, #FEATURES + 1)

    local filterCard, filterHolder =
        previewPanel(visualsScroll, "esp.filters", 2, 3)

    panelGapBefore[filterHolder] = 16

    local function addToggle(frame, initial, onChange)
        local state = initial

        local track = make("Frame", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -12, 0.5, 0),
            Size = UDim2.fromOffset(26, 14),
            BackgroundColor3 = state and colors.accent or WHITE,
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
            ZIndex = 5,
        }, frame)

        connect(hit.Activated, function()
            state = not state

            animate(track, {
                BackgroundColor3 = state and colors.accent or WHITE,
                BackgroundTransparency = state and 0.35 or 0.86,
            })

            animate(knob, {
                Position = UDim2.new(0, state and 14 or 2, 0.5, 0),
                BackgroundColor3 = state and colors.accent or colors.sub,
            })

            onChange(state)
        end)
    end

    -- colour squares ---------------------------------------------------------

    local swatches = {}
    local selection

    local function paintSelection()
        for key, swatch in pairs(swatches) do
            local active = selection ~= nil and selection == key

            swatch.outline.Color = active and colors.accent or WHITE
            swatch.outline.Transparency = active and 0 or 0.8
            swatch.outline.Thickness = active and 2 or 1
        end
    end

    local function closeEditor()
        picker.espOpen = false
        selection = nil
        picker.target = { kind = "menu" }
        picker.panel.Visible = false
        paintSelection()
    end

    picker.onLeave = closeEditor

    local function setColor(feature, state, color)
        cfg.palette[feature][state] = color
        swatches[feature .. "/" .. state].button.BackgroundColor3 = color

        -- force the entries to repaint with the new colour next frame
        for _, entry in pairs(entries) do
            entry.col[feature] = nil
        end

        if feature == "bots" then
            for _, entry in pairs(botEntries) do
                table.clear(entry.col)
            end
        end
    end

    local function openEditor(feature, state)
        local key = feature .. "/" .. state

        if picker.espOpen and selection == key then
            closeEditor()
            return
        end

        selection = key
        picker.espOpen = true

        picker.setTarget({
            kind = "esp",
            feature = feature,
            state = state,
            default = feature == "bots"
                and (state == "visible" and ORANGE or BLUE)
                or (state == "visible" and RED or GREEN),
            apply = function(color)
                setColor(feature, state, color)
            end,
        }, cfg.palette[feature][state])

        picker.panel.Visible = true
        paintSelection()
    end

    local function addSwatch(frame, feature, state, offset)
        local button = make("TextButton", {
            Name = feature .. state,
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -offset, 0.5, 0),
            Size = UDim2.fromOffset(16, 16),
            BackgroundColor3 = cfg.palette[feature][state],
            BackgroundTransparency = 0,
            ZIndex = 6,
        }, frame)

        corner(button, UDim.new(0, 4))

        local outline = make("UIStroke", {
            Color = WHITE,
            Transparency = 0.8,
            Thickness = 1,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        }, button)

        swatches[feature .. "/" .. state] = {
            button = button,
            outline = outline,
        }

        connect(button.Activated, function()
            openEditor(feature, state)
        end)
    end

    -- rows ---------------------------------------------------------------------

    for index, feature in ipairs(FEATURES) do
        local frame, label = previewRow(espCard, index, "", true)

        localize(label, "esp." .. feature)

        addToggle(frame, false, function(value)
            cfg.enabled[feature] = value
        end)

        -- left: exposed (red), right: behind cover (green); health has none
        if feature ~= "health" then
            addSwatch(frame, feature, "visible", 70)
            addSwatch(frame, feature, "hidden", 48)
        end
    end

    local teamFrame, teamLabel = previewRow(filterCard, 1, "", true)
    localize(teamLabel, "esp.ignoreTeam")

    addToggle(teamFrame, false, function(value)
        cfg.ignoreTeam = value
    end)

    local friendsFrame, friendsLabel = previewRow(filterCard, 2, "", true)
    localize(friendsLabel, "esp.ignoreFriends")

    addToggle(friendsFrame, false, function(value)
        cfg.ignoreFriends = value

        if value then
            for _, target in ipairs(Players:GetPlayers()) do
                refreshFriend(target)
            end
        end
    end)

    local rangeFrame, rangeLabel = previewRow(filterCard, 3, "", true)
    localize(rangeLabel, "esp.range")

    local rangeSlider = rowSlider(
        rangeFrame,
        "EspRange",
        0,
        800,
        function(value)
            return floor(value + 0.5) .. "m"
        end,
        function(value)
            cfg.range = floor(value + 0.5)
        end
    )

    rangeSlider.set(cfg.range, false)

    -- bots: row right after "health"; left square = exposed (orange),
    -- right square = behind cover (blue)
    local botFrame, botLabel = previewRow(espCard, #FEATURES + 1, "", true)
    localize(botLabel, "esp.bots")

    addToggle(botFrame, false, function(value)
        cfg.enabled.bots = value

        if value then
            pcall(startBotScan)
        else
            pcall(stopBotScan)
        end
    end)

    addSwatch(botFrame, "bots", "visible", 70)
    addSwatch(botFrame, "bots", "hidden", 48)

    layoutPreview()
end, function(err)
    warn("[shitaro/esp] " .. debug.traceback(tostring(err), 2))
end)
end
