-- Passive correlation probe for Block Strike's observed RemoteSnapshot format.
-- Listens to one client event; does not FireServer, hook or block game handlers.
-- CAUTION: a few bounded raw packet samples are stored as hex and may contain
-- sensitive session data. No network upload is performed.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local localPlayer = Players.LocalPlayer
local SAMPLES, INTERVAL = 60, 0.5
local MAX_PACKET_BYTES, MAX_RAW_PER_PHASE = 512, 8
local started, lines, links = os.clock(), {}, {}
local received, processed, accepted, bad = 0, 0, 0, 0
local roster, states = {}, {}

local function log(value) lines[#lines + 1] = tostring(value) end
local function safe(fn, fallback)
    local ok, value = pcall(fn)
    if ok and value ~= nil then return value end
    if fallback ~= nil then return fallback end
    return "<unavailable>"
end
local function clean(value)
    local str = tostring(value):gsub("[\r\n\t]", " ")
    return #str > 140 and str:sub(1, 140) .. "..." or str
end
local function path(item) return item and safe(function() return item:GetFullName() end) or "<none>" end
local function xyz(value)
    return value and safe(function() return string.format("%.2f,%.2f,%.2f", value.X,value.Y,value.Z) end) or "<none>"
end
local function varint(number)
    if type(number) ~= "number" or number < 0 or number ~= math.floor(number) then return nil end
    local out = {}
    repeat
        local byte = number % 128
        number = math.floor(number / 128)
        out[#out + 1] = string.char(byte + (number > 0 and 128 or 0))
    until number == 0
    return table.concat(out)
end
local function modelInfo(player)
    local char = player.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
    local world = char and safe(function() return char:IsDescendantOf(Workspace) end, false) or false
    local visible
    if char then visible = safe(function() return char:GetAttribute("ClientCharacterPresentationVisible") end, nil) end
    local unavailable = not world or visible == false
    return char, root, world, visible, unavailable
end
local function refreshRoster()
    roster = Players:GetPlayers()
    for _, player in ipairs(roster) do
        if not states[player] then
            states[player] = { needle = varint(player.UserId), totalWorld=0, hitsWorld=0, totalHidden=0, hitsHidden=0, rawWorld=0, rawHidden=0 }
        end
    end
end
-- Reused entity IDs can refer to a different life after respawn. Drop the
-- mapping when the character or generation changes; never infer across lives.
local function refreshIdentity(player, state, now)
    local char = player.Character
    local generation = safe(function() return player:GetAttribute("CharacterGeneration") end, false)
    if generation == false and char then
        generation = safe(function() return char:GetAttribute("CharacterGeneration") end, false)
    end
    if state.initialized and (state.character ~= char or state.generation ~= generation) then
        if state.id or state.pending then
            log(string.format("RESET elapsed=%.2fs name=%s reason=character_or_generation_changed", now-started, clean(player.Name)))
        end
        state.id, state.pending = nil, nil
    end
    state.initialized, state.character, state.generation = true, char, generation
end
local function finite(n)
    return type(n) == "number" and n == n and math.abs(n) < 100000
end
local function validatePending(player, state, now)
    local pending = state.pending
    if not pending or state.id then return end
    if now - pending.at > 2 then state.pending=nil; return end
    local char, root, world, visible = modelInfo(player)
    if not char or not root or not world or visible == false then return end
    local ok, distance = pcall(function()
        local p = root.Position
        local dx, dy, dz = p.X-pending.x, p.Y-pending.y, p.Z-pending.z
        return math.sqrt(dx*dx+dy*dy+dz*dz)
    end)
    if ok and distance < 16 then
        state.id, state.pending = pending.id, nil
        state.mappingAt = now
        log(string.format("MAPPED elapsed=%.2fs name=%s userId=%s entity_hex=%02x%02x candidate_offset=%d distance=%.2f", now-started, clean(player.Name), tostring(player.UserId), string.byte(state.id,1), string.byte(state.id,2), pending.offset, distance))
    end
end
local function hexPrefix(raw)
    local n = math.min(#raw, MAX_PACKET_BYTES)
    local chars = {}
    for i = 1, n do chars[i] = string.format("%02x", string.byte(raw, i)) end
    return table.concat(chars), n
end
local function processPacket(payload)
    received = received + 1
    if typeof(payload) ~= "buffer" then return end
    local now = os.clock()
    local raw = buffer.tostring(payload)
    processed = processed + 1
    if #raw < 2 then return end
    local signature, kind = string.byte(raw,1), string.byte(raw,2)
    if signature ~= 6 or (kind ~= 0 and kind ~= 1) then return end
    accepted = accepted + 1
    -- Observed (not fully documented) delta spawn shape: varint UserId,
    -- 2-byte entity id, flags, three little-endian float32 coordinates.
    -- Only trust a mapping after it agrees with that player's live world root.
    for _, player in ipairs(roster) do
        local state = states[player]
        if state then refreshIdentity(player, state, now) end
        if state and not state.id and kind == 1 and state.needle then
            local idx = string.find(raw, state.needle, 1, true)
            if idx then
                local entityAt = idx + #state.needle
                local posAt = entityAt + 2 -- flags follow the two entity bytes
                if posAt + 12 <= #raw then
                    local ok, x, y, z = pcall(function()
                        return buffer.readf32(payload, posAt), buffer.readf32(payload, posAt+4), buffer.readf32(payload, posAt+8)
                    end)
                    if ok and finite(x) and finite(y) and finite(z) then
                        state.pending = { id=string.sub(raw,entityAt,entityAt+1), x=x, y=y, z=z, at=now, offset=idx-1 }
                    end
                end
            end
        end
        validatePending(player, state, now)
        if state and state.id then
            local char, root, world, visible, unavailable = modelInfo(player)
            local phase = unavailable and "Hidden" or "World"
            local totals = "total" .. phase
            local hits = "hits" .. phase
            local rawCount = "raw" .. phase
            state[totals] = state[totals] + 1
            local idAt = string.find(raw, state.id, 1, true)
            if idAt then
                -- Byte occurrence is only a heuristic: it may be a removal,
                -- other field, random coincidence, or a genuine update.
                state[hits] = state[hits] + 1
                local timeKey = "lastRaw" .. phase
                if state[rawCount] < MAX_RAW_PER_PHASE and (not state[timeKey] or now-state[timeKey] >= 0.7) then
                    state[rawCount], state[timeKey] = state[rawCount]+1, now
                    local hex, bytes = hexPrefix(raw)
                    log(string.format("MATCH elapsed=%.2fs player=%s phase=%s entity_hex=%02x%02x byte_offset=%d packet_kind=%d length=%d bytes=%d truncated=%s char=%s presentationVisible=%s root=%s hex=%s", now-started, clean(player.Name), phase, string.byte(state.id,1), string.byte(state.id,2), idAt-1, kind, #raw, bytes, tostring(bytes<#raw), path(char), tostring(visible), root and xyz(root.Position) or "<none>", hex))
                end
            end
        end
    end
end
local function snapshot(index)
    refreshRoster()
    local now = os.clock()
    log(string.format("\nSAMPLE %d/%d elapsed=%.2fs received=%d buffers=%d errors=%d", index, SAMPLES, now-started, received, processed, bad))
    for _, player in ipairs(roster) do
        local state = states[player]
        refreshIdentity(player, state, now)
        validatePending(player, state, now)
        local char, root, world, visible = modelInfo(player)
        local team = player.Team and player.Team.Name or safe(function() return player:GetAttribute("Team") end, "<none>")
        log(string.format("PLAYER name=%s display=%s userId=%s local=%s team=%s char=%s inWorkspace=%s presentationVisible=%s root=%s mapped=%s hitsWorld=%d/%d hitsHidden=%d/%d", clean(player.Name), clean(player.DisplayName), tostring(player.UserId), tostring(player==localPlayer), clean(team), path(char), tostring(world), tostring(visible), root and xyz(root.Position) or "<none>", state.id and string.format("%02x%02x",string.byte(state.id,1),string.byte(state.id,2)) or "no", state.hitsWorld, state.totalWorld, state.hitsHidden, state.totalHidden))
    end
end
local function finish(report)
    local directory = "ShitaroHub/diagnostics"
    local filename = directory .. "/block_strike_tracking_" .. os.date("!%Y%m%d_%H%M%S") .. ".txt"
    local fileOk, fileErr = false, "writefile unavailable"
    if type(writefile) == "function" then
        fileOk, fileErr = pcall(function()
            if type(makefolder) == "function" then
                for _, dir in ipairs({"ShitaroHub", directory}) do
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
    env.ShitaroBlockStrikeTrackingReport = report
    print("[Shitaro tracking] file: " .. (fileOk and filename or "FAILED: " .. tostring(fileErr)))
    print("[Shitaro tracking] clipboard: " .. (copyOk and "copied" or "FAILED: " .. tostring(copyErr)))
    if not fileOk and not copyOk then warn("[Shitaro tracking] Both outputs failed; report follows and is in getgenv().ShitaroBlockStrikeTrackingReport"); print(report) end
end
print("[Shitaro tracking] Started. After starting, watch an opponent emerge and hide again; about 30 seconds.")
local ok, err = xpcall(function()
    log("SHITAROHUB BLOCK STRIKE TRACKING DIAGNOSTIC v1")
    log("UTC=" .. os.date("!%Y-%m-%d %H:%M:%S") .. " placeId=" .. tostring(game.PlaceId) .. " gameId=" .. tostring(game.GameId) .. " jobId=" .. tostring(game.JobId))
    log("Passive RemoteSnapshot listener. Report contains names, IDs, server ID, positions and bounded RAW packet bytes as hex; raw bytes may contain sensitive session data. No automatic upload.")
    log("The first argument of each event is inspected; only buffer packets with observed header 06 00/01 are counted after mapping. Entity id byte matches are HEURISTIC, not proof of a position update. Zero hits are not conclusive if a player was never mapped, events were missed, or the format changed.")
    refreshRoster()
    local folder = ReplicatedStorage:FindFirstChild("MovementV2Remotes")
    local remote = folder and folder:FindFirstChild("RemoteSnapshot")
    if remote and (remote:IsA("RemoteEvent") or remote:IsA("UnreliableRemoteEvent")) then
        local connected, link = pcall(function()
            return remote.OnClientEvent:Connect(function(payload)
                local success = pcall(processPacket, payload)
                if not success then bad = bad + 1 end
            end)
        end)
        if connected and link then links[#links+1] = link; log("RemoteSnapshot listener attached: " .. path(remote))
        else log("RemoteSnapshot listener failed: " .. clean(link)) end
    else log("RemoteSnapshot unavailable or not an event") end
    for i=1,SAMPLES do
        local sampleOk, sampleErr = pcall(snapshot, i)
        if not sampleOk then log("SAMPLE ERROR: " .. clean(sampleErr)) end
        if i == 1 or i % 10 == 0 or i == SAMPLES then print("[Shitaro tracking] sample " .. i .. "/" .. SAMPLES) end
        if i < SAMPLES then task.wait(INTERVAL) end
    end
end, function(e) return tostring(e) end)
for _, link in ipairs(links) do pcall(function() link:Disconnect() end) end
if not ok then log("FATAL ERROR: " .. clean(err)) end
log("\nSUMMARY received=" .. received .. " processedBuffers=" .. processed .. " acceptedPackets=" .. accepted .. " errors=" .. bad)
for player, s in pairs(states) do
    if s then log(string.format("RESULT name=%s userId=%s mapped=%s hitsWorld=%d/%d hitsHidden=%d/%d", clean(player.Name), tostring(player.UserId), s.id and string.format("%02x%02x",string.byte(s.id,1),string.byte(s.id,2)) or "no",s.hitsWorld,s.totalWorld,s.hitsHidden,s.totalHidden)) end
end
log("END OF REPORT")
finish(table.concat(lines,"\n"))
