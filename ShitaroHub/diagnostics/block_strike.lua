-- Standalone Block Strike / Shitaro ESP diagnostic. Run in the executor in-game.
-- Read-only: no hooks, remote calls, movement or changes to game instances.
-- Samples replicated client state; it cannot recover server-only positions.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local localPlayer = Players.LocalPlayer

local SAMPLE_COUNT = 8
local SAMPLE_INTERVAL = 2
local MAX_MODELS = 200
local MAX_VALUES = 32
local OUTPUT_DIR = "ShitaroHub/diagnostics"
local lines = {}
local ids = setmetatable({}, { __mode = "k" })
local nextId = 0
local lastPositions = setmetatable({}, { __mode = "k" })
local started = os.clock()

local function log(text)
    lines[#lines + 1] = tostring(text)
end

local function safe(fn, fallback)
    local ok, result = pcall(fn)
    if ok and result ~= nil then return result end
    if fallback ~= nil then return fallback end
    return "<unavailable>"
end

local function clean(value)
    local text = tostring(value):gsub("[\r\n\t]", " ")
    if #text > 180 then text = text:sub(1, 180) .. "..." end
    return text
end

local function path(instance)
    if not instance then return "<none>" end
    return safe(function() return instance:GetFullName() end)
end

local function id(instance)
    if not instance then return "-" end
    if not ids[instance] then
        nextId = nextId + 1
        ids[instance] = nextId
    end
    return tostring(ids[instance])
end

local function pos(value)
    if not value then return "<none>" end
    return safe(function() return string.format("(%.2f, %.2f, %.2f)", value.X, value.Y, value.Z) end)
end

local function normalize(name)
    return string.lower(tostring(name)):gsub("[^%w]", "")
end

-- Limit captured metadata to player/team/replication hints; do not dump chat,
-- arbitrary remote arguments, private GUI content or every attribute/value.
local function relevant(name)
    local n = normalize(name)
    for _, word in ipairs({ "team", "side", "faction", "alliance", "squad", "group", "role", "class", "player", "owner", "userid", "character", "avatar", "bot", "npc", "alive", "health", "dead", "spectat", "spawn", "round", "match" }) do
        if n:find(word, 1, true) then return true end
    end
    return false
end

local function valueText(value)
    if typeof(value) == "Instance" then
        return path(value) .. " [id=" .. id(value) .. "]"
    end
    return clean(value)
end

local function metadata(instance, label)
    if not instance then return end
    local found = {}
    local attrs = safe(function() return instance:GetAttributes() end, {})
    for name, value in pairs(attrs) do
        if relevant(name) then
            found[#found + 1] = "attr " .. clean(name) .. "=" .. valueText(value)
        end
    end
    for _, child in ipairs(instance:GetChildren()) do
        if child:IsA("ValueBase") and relevant(child.Name) then
            found[#found + 1] = child.ClassName .. " " .. clean(child.Name) .. "=" .. safe(function() return valueText(child.Value) end)
        end
    end
    table.sort(found)
    local shown = math.min(#found, MAX_VALUES)
    for i = 1, shown do log("    " .. label .. " " .. found[i]) end
    if #found > shown then log("    " .. label .. " metadata omitted=" .. (#found - shown)) end
end

local SIDE_ORDER = { "team", "teamname", "teamid", "teamnumber", "teamindex", "teamcolor", "teamcolour", "side", "sidename", "sideid", "faction", "factionname", "alliance" }
local NO_SIDE = { [""] = true, spectator = true, spectators = true, spectating = true, spec = true, neutral = true, none = true, ["nil"] = true, null = true, lobby = true, dead = true, unassigned = true, noteam = true, waiting = true }
local function sideText(value)
    local kind = typeof(value)
    if kind == "string" then
        local text = string.lower(value:match("^%s*(.-)%s*$"))
        if not NO_SIDE[text] then return text end
    elseif kind == "number" or kind == "Color3" or kind == "BrickColor" then
        return tostring(value)
    elseif kind == "Instance" then
        local text = string.lower(value.Name)
        if not NO_SIDE[text] then return text end
    end
    return nil
end

local function sideFrom(instance, label, attrs)
    if not instance then return nil end
    local found, names = {}, {}
    if attrs then
        for name, value in pairs(instance:GetAttributes()) do
            local key = normalize(name)
            found[key], names[key] = value, name
        end
    else
        for _, child in ipairs(instance:GetChildren()) do
            if child:IsA("ValueBase") then
                local key = normalize(child.Name)
                found[key], names[key] = child.Value, child.Name
            end
        end
    end
    for _, key in ipairs(SIDE_ORDER) do
        local text = sideText(found[key])
        if text then
            local kind = attrs and "attr" or "value"
            return kind .. ":" .. key .. ":" .. text, kind, label .. " " .. kind .. " " .. names[key] .. "=" .. text
        end
    end
end

local function charFolder(character)
    if character and character.Parent and character.Parent ~= Workspace then return character.Parent end
end

local function resolveSides(roster)
    local first, multiple
    for _, player in ipairs(roster) do
        local folder = charFolder(player.Character)
        if folder then
            if not first then first = folder elseif first ~= folder then multiple = true end
        end
    end
    local sides = {}
    for _, player in ipairs(roster) do
        local character = player.Character
        local human = character and character:FindFirstChildOfClass("Humanoid")
        local key, kind, via
        if player.Team then
            key, kind, via = "team:" .. player.Team.Name, "team", "Team " .. player.Team.Name
        else
            key, kind, via = sideFrom(player, "player", true)
            if not key then key, kind, via = sideFrom(character, "character", true) end
            if not key then key, kind, via = sideFrom(human, "humanoid", true) end
            if not key then key, kind, via = sideFrom(player, "player", false) end
            if not key then
                for _, child in ipairs(player:GetChildren()) do
                    local name = normalize(child.Name)
                    if name == "leaderstats" or name == "leaderboard" or name == "stats" then
                        key, kind, via = sideFrom(child, "leaderstats", false)
                        break
                    end
                end
            end
            if not key then key, kind, via = sideFrom(character, "character", false) end
            local folder = charFolder(character)
            if not key and multiple and folder then
                key, kind, via = "folder:" .. path(folder), "folder", "folder " .. folder.Name
            end
        end
        sides[player] = { key = key, kind = kind, via = via }
    end
    local mine = sides[localPlayer] or {}
    local enabled = false
    for _, player in ipairs(roster) do
        local other = sides[player]
        if player ~= localPlayer and mine.key and other.key and mine.kind == other.kind and mine.key ~= other.key then
            enabled = true
        end
    end
    return sides, enabled, multiple
end

local function part(model, name)
    local object = model and model:FindFirstChild(name)
    if object and object:IsA("BasePart") then return object end
end

local function rootOf(model)
    return part(model, "HumanoidRootPart") or safe(function() return model.PrimaryPart end, false)
        or part(model, "UpperTorso") or part(model, "Torso")
        or model:FindFirstChildWhichIsA("BasePart")
end

local function partLine(label, object, root, cam)
    if not object or not object:IsA("BasePart") then
        log("    " .. label .. "=<none>")
        return
    end
    local position = object.Position
    local delta = root and safe(function() return string.format("%.2f", (position - root.Position).Magnitude) end) or "-"
    local previous = lastPositions[object]
    local change = previous and safe(function() return string.format("%.2f", (position - previous).Magnitude) end) or "first"
    lastPositions[object] = position
    local screen = "<no camera>"
    if cam then
        screen = safe(function()
            local projected, visible = cam:WorldToViewportPoint(position)
            return string.format("(%.1f, %.1f, z=%.1f) onScreen=%s", projected.X, projected.Y, projected.Z, tostring(visible))
        end)
    end
    log(string.format("    %s id=%s path=%s pos=%s delta_from_root=%s moved_since_last=%s screen=%s anchored=%s transparency=%s localTransparency=%s", label, id(object), path(object), pos(position), delta, change, screen, tostring(object.Anchored), tostring(object.Transparency), tostring(object.LocalTransparencyModifier)))
end

local function reportModel(model, cam, characterOwner, matches, sampleNumber)
    local human = model:FindFirstChildOfClass("Humanoid")
    local root = rootOf(model)
    local owner = characterOwner[model]
    log(string.format("  MODEL id=%s path=%s name=%s owner=%s name_matches=%s humanoid=%s primary=%s", id(model), path(model), clean(model.Name), owner and clean(owner.Name) or "<none>", #matches > 0 and table.concat(matches, ",") or "<none>", human and ("id=" .. id(human) .. " hp=" .. tostring(human.Health) .. " state=" .. safe(function() return tostring(human:GetState()) end) .. " root=" .. path(human.RootPart)) or "<none>", path(model.PrimaryPart)))
    partLine("ESP root candidate", root, root, cam)
    partLine("Head", part(model, "Head"), root, cam)
    partLine("UpperTorso", part(model, "UpperTorso"), root, cam)
    partLine("Torso", part(model, "Torso"), root, cam)
    if sampleNumber == 1 then
        metadata(model, "model")
        metadata(human, "humanoid")
        local names = {}
        for _, child in ipairs(model:GetChildren()) do names[#names + 1] = clean(child.Name) .. ":" .. child.ClassName end
        table.sort(names)
        if #names > 60 then
            while #names > 60 do table.remove(names) end
            names[#names + 1] = "<remaining children omitted>"
        end
        log("    direct_children=" .. table.concat(names, ", "))
    end
end

-- Search replicated metadata names only. Never inspect remote traffic, module
-- sources, chat messages or arbitrary string values. This may still contain
-- names/user IDs: the report must be reviewed before it is shared.
local function replicatedHints()
    local storage = safe(function() return game:GetService("ReplicatedStorage") end, false)
    if not storage then log("REPLICATED HINTS: ReplicatedStorage unavailable"); return end
    local matches = {}
    for _, item in ipairs(storage:GetDescendants()) do
        if relevant(item.Name) then matches[#matches + 1] = item end
    end
    table.sort(matches, function(a, b) return path(a) < path(b) end)
    log("REPLICATED HINTS: matches=" .. #matches .. " shown=" .. math.min(#matches, 120))
    for i = 1, math.min(#matches, 120) do
        local item = matches[i]
        local value = ""
        if item:IsA("ValueBase") then value = " value=" .. safe(function() return valueText(item.Value) end) end
        log("  " .. path(item) .. " class=" .. item.ClassName .. value)
        metadata(item, "replicated")
    end
end

local function snapshot(index)
    local roster = Players:GetPlayers()
    if index == 1 then replicatedHints() end
    local cam = Workspace.CurrentCamera
    local sides, sidesOn, folders = resolveSides(roster)
    local mine = sides[localPlayer] or {}
    log(string.format("\n========== SAMPLE %d/%d elapsed=%.1fs =========", index, SAMPLE_COUNT, os.clock() - started))
    log("camera=" .. path(cam) .. " position=" .. (cam and pos(cam.CFrame.Position) or "<none>") .. " viewport=" .. (cam and clean(cam.ViewportSize) or "<none>"))
    log("ESP side simulation (instantaneous, no cache): local=" .. tostring(mine.key) .. " kind=" .. tostring(mine.kind) .. " second_side_detected=" .. tostring(sidesOn) .. " multiple_character_folders=" .. tostring(folders == true))
    log("NOTE: actual ESP caches sides and retains the last local side; this diagnostic does not read its private state. Bot ESP is filtered separately from player teammates.")
    local characterOwner = {}
    for _, player in ipairs(roster) do
        if player.Character then characterOwner[player.Character] = player end
        local info = sides[player]
        local teammate = sidesOn and mine.key ~= nil and info.key ~= nil and mine.key == info.key
        local char = player.Character
        log(string.format("PLAYER name=%s display=%s userId=%s local=%s team=%s teamColor=%s neutral=%s char=%s charId=%s resolved=%s via=%s simulated_teammate=%s", clean(player.Name), clean(player.DisplayName), tostring(player.UserId), tostring(player == localPlayer), path(player.Team), clean(player.TeamColor), tostring(player.Neutral), path(char), id(char), tostring(info.key), tostring(info.via), tostring(teammate)))
        metadata(player, "player")
        if char then
            metadata(char, "character")
            metadata(char:FindFirstChildOfClass("Humanoid"), "humanoid")
        end
        for _, child in ipairs(player:GetChildren()) do
            local n = normalize(child.Name)
            if n == "stats" or n == "leaderboard" or n == "leaderstats" then metadata(child, child.Name) end
        end
    end
    local candidates, seen = {}, {}
    local function add(model)
        if model and model:IsA("Model") and not seen[model] then
            seen[model] = true
            local matches = {}
            local n = string.lower(model.Name)
            for _, player in ipairs(roster) do
                if n == string.lower(player.Name) or n == string.lower(player.DisplayName) or n == tostring(player.UserId) then matches[#matches + 1] = clean(player.Name) end
            end
            local human = model:FindFirstChildOfClass("Humanoid")
            local looksLikeRig = part(model, "Head") and (part(model, "HumanoidRootPart") or part(model, "UpperTorso") or part(model, "Torso"))
            if characterOwner[model] or human or #matches > 0 or looksLikeRig then
                candidates[#candidates + 1] = { model = model, matches = matches, priority = characterOwner[model] and 0 or (#matches > 0 and 1 or (looksLikeRig and 2 or 3)) }
            end
        end
    end
    for _, player in ipairs(roster) do add(player.Character) end
    for _, object in ipairs(Workspace:GetDescendants()) do if object:IsA("Model") then add(object) end end
    table.sort(candidates, function(a, b)
        if a.priority ~= b.priority then return a.priority < b.priority end
        return path(a.model) < path(b.model)
    end)
    log(string.format("MODELS candidates=%d shown=%d (characters first, name matches next, rig-like models next, other Humanoids last)", #candidates, math.min(#candidates, MAX_MODELS)))
    for i = 1, math.min(#candidates, MAX_MODELS) do
        local item = candidates[i]
        local ok, err = pcall(reportModel, item.model, cam, characterOwner, item.matches, index)
        if not ok then log("  MODEL ERROR " .. path(item.model) .. " " .. clean(err)) end
    end
    if #candidates > MAX_MODELS then log("MODEL LIMIT REACHED; omitted=" .. (#candidates - MAX_MODELS)) end
end

local function output(report)
    local filename = "block_strike_esp_" .. os.date("!%Y%m%d_%H%M%S") .. ".txt"
    local filePath = OUTPUT_DIR .. "/" .. filename
    local diskOk, diskErr = false, "writefile unavailable"
    if type(writefile) == "function" then
        diskOk, diskErr = pcall(function()
            if type(makefolder) == "function" then
                for _, folder in ipairs({ "ShitaroHub", OUTPUT_DIR }) do
                    if type(isfolder) ~= "function" or not isfolder(folder) then
                        local ok, err = pcall(makefolder, folder)
                        if not ok and (type(isfolder) ~= "function" or not isfolder(folder)) then error(err) end
                    end
                end
            end
            writefile(filePath, report)
        end)
    end
    local copy = type(setclipboard) == "function" and setclipboard or (type(toclipboard) == "function" and toclipboard or nil)
    local copyOk, copyErr = false, "clipboard function unavailable"
    if copy then copyOk, copyErr = pcall(copy, report) end
    local env = (getgenv and getgenv()) or _G
    env.ShitaroBlockStrikeReport = report
    print("[Shitaro diagnostic] file: " .. (diskOk and filePath or "FAILED: " .. tostring(diskErr)))
    print("[Shitaro diagnostic] clipboard: " .. (copyOk and "copied" or "FAILED: " .. tostring(copyErr)))
    if not diskOk and not copyOk then
        warn("[Shitaro diagnostic] Both outputs failed; report follows and is also in getgenv().ShitaroBlockStrikeReport")
        print(report)
    end
end

print("[Shitaro diagnostic] Started. Watch moving players for about 14 seconds; results will be saved and copied.")
local ok, err = xpcall(function()
    log("SHITAROHUB BLOCK STRIKE ESP DIAGNOSTIC v1")
    log("UTC=" .. os.date("!%Y-%m-%d %H:%M:%S") .. " placeId=" .. tostring(game.PlaceId) .. " gameId=" .. tostring(game.GameId) .. " jobId=" .. tostring(game.JobId))
    log("Samples=" .. SAMPLE_COUNT .. " interval=" .. SAMPLE_INTERVAL .. " seconds; positions are CLIENT REPLICATED, not ground truth.")
    log("Contains player names, user IDs, server ID and positions. Review before sharing.")
    log("StreamingEnabled=" .. safe(function() return tostring(Workspace.StreamingEnabled) end) .. " targetRadius=" .. safe(function() return tostring(Workspace.StreamingTargetRadius) end) .. " minRadius=" .. safe(function() return tostring(Workspace.StreamingMinRadius) end))
    for index = 1, SAMPLE_COUNT do
        local sampleOk, sampleErr = xpcall(function() snapshot(index) end, function(e) return tostring(e) end)
        if not sampleOk then log("SAMPLE ERROR " .. index .. ": " .. clean(sampleErr)) end
        print("[Shitaro diagnostic] sample " .. index .. "/" .. SAMPLE_COUNT)
        if index < SAMPLE_COUNT then task.wait(SAMPLE_INTERVAL) end
    end
end, function(e) return tostring(e) end)
if not ok then log("FATAL ERROR; partial report: " .. clean(err)) end
log("\nEND OF REPORT")
output(table.concat(lines, "\n"))
