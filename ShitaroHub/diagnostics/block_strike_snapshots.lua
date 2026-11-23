-- Passive ESP investigation. Observes only the named server-to-client signal.
-- Does not call FireServer, hook, block or modify other event listeners.
-- It may still create an extra client event listener until collection ends.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local me = Players.LocalPlayer
local SAMPLES, INTERVAL, MAX_EVENTS, MAX_FIELDS, MAX_DEPTH = 20, 1, 60, 80, 5
local started, lines, links, observations = os.clock(), {}, {}, {}
local received, captured, lastCapture = 0, 0, -math.huge

local function add(s) lines[#lines + 1] = tostring(s) end
local function safe(fn, fallback)
    local ok, result = pcall(fn)
    if ok and result ~= nil then return result end
    if fallback ~= nil then return fallback end
    return "<unavailable>"
end
local function clean(v)
    local s = tostring(v):gsub("[\r\n\t]", " ")
    return #s > 150 and s:sub(1, 150) .. "..." or s
end
local function path(o) return o and safe(function() return o:GetFullName() end) or "<none>" end
local function vec(v) return safe(function() return string.format("(%.2f, %.2f, %.2f)", v.X, v.Y, v.Z) end) end
local function team(p)
    return p.Team and p.Team.Name or safe(function() return p:GetAttribute("Team") end, "<none>")
end

-- String VALUES are recorded only if they exactly match an active player name;
-- arbitrary strings and buffers are not copied. Numeric fields may contain
-- gameplay telemetry. The user can review the report before sharing it.
local function knownName(s)
    for _, p in ipairs(Players:GetPlayers()) do
        if s == p.Name or s == p.DisplayName then return true end
    end
    return false
end
local function keyName(k)
    if type(k) == "number" then return tostring(k) end
    if type(k) == "string" and #k <= 64 and k:match("^[%w_%-]+$") then return k end
    return "<redacted-key>"
end
local function describeArgs(...)
    local out, seen, count = {}, {}, 0
    local function put(s)
        if count < MAX_FIELDS then out[#out + 1] = s; count = count + 1 end
    end
    local function visit(value, label, depth)
        if count >= MAX_FIELDS then return end
        local kind = typeof(value)
        if kind == "Vector3" then
            put(label .. " Vector3=" .. vec(value))
        elseif kind == "Vector2" then
            put(label .. " Vector2=" .. safe(function() return string.format("(%.2f, %.2f)", value.X, value.Y) end))
        elseif kind == "CFrame" then
            put(label .. " CFrame.position=" .. vec(value.Position))
        elseif kind == "Instance" then
            put(label .. " Instance=" .. path(value))
        elseif kind == "buffer" then
            put(label .. " buffer length=" .. safe(function() return buffer.len(value) end) .. " bytes (content omitted)")
        elseif kind == "number" or kind == "boolean" then
            put(label .. " " .. kind .. "=" .. tostring(value))
        elseif kind == "string" then
            put(label .. " string=" .. (knownName(value) and clean(value) or "<redacted>"))
        elseif kind == "table" then
            if seen[value] then put(label .. " table=<cycle>"); return end
            if depth >= MAX_DEPTH then put(label .. " table=<depth-limit>"); return end
            seen[value] = true
            local keys, truncated = {}, false
            for key in pairs(value) do
                if #keys >= MAX_FIELDS then truncated = true; break end
                keys[#keys + 1] = key
            end
            table.sort(keys, function(a, b) return keyName(a) < keyName(b) end)
            put(label .. " table fields_sampled=" .. #keys .. (truncated and " (truncated)" or ""))
            for _, key in ipairs(keys) do
                if count >= MAX_FIELDS then break end
                visit(value[key], label .. "." .. keyName(key), depth + 1)
            end
            seen[value] = nil
        else
            put(label .. " " .. tostring(kind))
        end
    end
    local args = { n = select("#", ...), ... }
    for i = 1, args.n do visit(args[i], "arg" .. i, 0) end
    if count >= MAX_FIELDS then out[#out + 1] = "<field limit reached>" end
    return table.concat(out, " | ")
end

local function samplePlayers(index)
    add(string.format("\nSAMPLE %d/%d elapsed=%.1fs events_received=%d events_captured=%d", index, SAMPLES, os.clock()-started, received, captured))
    for _, p in ipairs(Players:GetPlayers()) do
        local char = p.Character
        local root = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
        local inWorld = char and safe(function() return char:IsDescendantOf(Workspace) end, false) or false
        local visible = char and safe(function() return char:GetAttribute("ClientCharacterPresentationVisible") end, "<none>") or "<none>"
        local position = root and safe(function() return vec(root.Position) end) or "<none>"
        add("PLAYER name=" .. clean(p.Name) .. " display=" .. clean(p.DisplayName) .. " userId=" .. tostring(p.UserId) .. " team=" .. clean(team(p)) .. " local=" .. tostring(p == me) .. " char=" .. path(char) .. " inWorkspace=" .. tostring(inWorld) .. " presentationVisible=" .. tostring(visible) .. " root=" .. position)
    end
end
local function finish(report)
    local folder = "ShitaroHub/diagnostics"
    local filename = folder .. "/block_strike_snapshots_" .. os.date("!%Y%m%d_%H%M%S") .. ".txt"
    local fileOk, fileErr = false, "writefile unavailable"
    if type(writefile) == "function" then
        fileOk, fileErr = pcall(function()
            if type(makefolder) == "function" then
                for _, dir in ipairs({"ShitaroHub", folder}) do
                    if type(isfolder) ~= "function" or not isfolder(dir) then
                        local ok, err = pcall(makefolder, dir)
                        if not ok and (type(isfolder) ~= "function" or not isfolder(dir)) then error(err) end
                    end
                end
            end
            writefile(filename, report)
        end)
    end
    local copy = type(setclipboard) == "function" and setclipboard or (type(toclipboard) == "function" and toclipboard or nil)
    local copyOk, copyErr = false, "clipboard unavailable"
    if copy then copyOk, copyErr = pcall(copy, report) end
    local env = (getgenv and getgenv()) or _G
    env.ShitaroBlockStrikeSnapshotsReport = report
    print("[Shitaro snapshot] file: " .. (fileOk and filename or "FAILED: " .. tostring(fileErr)))
    print("[Shitaro snapshot] clipboard: " .. (copyOk and "copied" or "FAILED: " .. tostring(copyErr)))
    if not fileOk and not copyOk then warn("[Shitaro snapshot] Both outputs failed; report follows and is stored in getgenv().ShitaroBlockStrikeSnapshotsReport"); print(report) end
end

print("[Shitaro snapshot] Started. Watch an opponent enter and leave cover for about 20 seconds.")
local ok, err = xpcall(function()
    add("SHITAROHUB BLOCK STRIKE SNAPSHOT DIAGNOSTIC v1")
    add("UTC=" .. os.date("!%Y-%m-%d %H:%M:%S") .. " placeId=" .. tostring(game.PlaceId) .. " gameId=" .. tostring(game.GameId) .. " jobId=" .. tostring(game.JobId))
    add("Passive named server-to-client listener, no FireServer. Report includes user names, IDs, server ID, positions and numeric telemetry; review before sharing. Arbitrary strings and buffer contents omitted.")
    local folder = ReplicatedStorage:FindFirstChild("MovementV2Remotes")
    local remote = folder and folder:FindFirstChild("RemoteSnapshot")
    if remote and (remote:IsA("RemoteEvent") or remote:IsA("UnreliableRemoteEvent")) then
        local connectOk, connection = pcall(function()
            return remote.OnClientEvent:Connect(function(...)
                received = received + 1
                local now = os.clock()
                if captured >= MAX_EVENTS or now - lastCapture < 0.4 then return end
                captured, lastCapture = captured + 1, now
                local eventOk, description = pcall(describeArgs, ...)
                observations[#observations + 1] = string.format("EVENT elapsed=%.2fs %s", now-started, eventOk and description or "<decode error>")
            end)
        end)
        if connectOk and connection then links[#links + 1] = connection; add("RemoteSnapshot listener attached: " .. path(remote))
        else add("RemoteSnapshot listener failed: " .. tostring(connection)) end
    else
        add("RemoteSnapshot unavailable or not a RemoteEvent (no listener attached)")
    end
    for i = 1, SAMPLES do
        local sampleOk, sampleErr = pcall(samplePlayers, i)
        if not sampleOk then add("SAMPLE ERROR: " .. clean(sampleErr)) end
        print("[Shitaro snapshot] sample " .. i .. "/" .. SAMPLES)
        if i < SAMPLES then task.wait(INTERVAL) end
    end
end, function(e) return tostring(e) end)
for _, link in ipairs(links) do pcall(function() link:Disconnect() end) end
if not ok then add("FATAL ERROR; partial report: " .. clean(err)) end
add("\nREMOTE totals received=" .. received .. " sampled=" .. captured)
for _, line in ipairs(observations) do add(line) end
add("\nEND OF REPORT")
finish(table.concat(lines, "\n"))
