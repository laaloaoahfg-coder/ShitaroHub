-- Block Strike: locate a known in-game name in models and HUD, plus nearby rigs.
-- Client-side observations only; no hooks, game mutations or remote calls.
-- Change TARGET_NAME before running if investigating another player.
local TARGET_NAME = "BbcVetle"
local SAMPLES, INTERVAL, MAX_MODELS, MAX_HUD = 20, 1, 80, 50
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local me = Players.LocalPlayer
local lines, objectIds, previous = {}, setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })
local nextId, started = 0, os.clock()
local target = string.lower(TARGET_NAME)

local function add(line) lines[#lines + 1] = tostring(line) end
local function attempt(fn, fallback)
    local ok, result = pcall(fn)
    if ok and result ~= nil then return result end
    if fallback ~= nil then return fallback end
    return "<unavailable>"
end
local function clean(value)
    local s = tostring(value):gsub("[\r\n\t]", " ")
    if #s > 300 then s = s:sub(1, 300) .. "..." end
    return s
end
local function matches(value)
    return value ~= nil and string.find(string.lower(tostring(value)), target, 1, true) ~= nil
end
local function path(obj)
    if not obj then return "<none>" end
    return attempt(function() return obj:GetFullName() end)
end
local function ident(obj)
    if not obj then return "-" end
    if not objectIds[obj] then nextId = nextId + 1; objectIds[obj] = nextId end
    return tostring(objectIds[obj])
end
local function vec(v)
    if not v then return "<none>" end
    return attempt(function() return string.format("(%.2f, %.2f, %.2f)", v.X, v.Y, v.Z) end)
end
local function part(model, name)
    local p = model and model:FindFirstChild(name)
    if p and p:IsA("BasePart") then return p end
end
local function root(model)
    return part(model, "HumanoidRootPart") or attempt(function() return model.PrimaryPart end, false)
        or part(model, "UpperTorso") or part(model, "Torso")
end
local function screen(camera, p)
    if not camera or not p then return false, math.huge, "<none>" end
    local ok, onScreen, dist, description = pcall(function()
        local point, visible = camera:WorldToViewportPoint(p.Position)
        local size = camera.ViewportSize
        local dx, dy = point.X - size.X / 2, point.Y - size.Y / 2
        local distance = math.sqrt(dx * dx + dy * dy)
        return visible, distance, string.format("x=%.1f y=%.1f z=%.1f onScreen=%s centerDistance=%.1f", point.X, point.Y, point.Z, tostring(visible), distance)
    end)
    if not ok then return false, math.huge, "<unavailable>" end
    return onScreen, dist, description
end
local function attrRelevant(name)
    local n = string.lower(name):gsub("[^%w]", "")
    for _, word in ipairs({ "name", "display", "player", "owner", "userid", "team", "side", "faction", "bot", "npc", "dead", "health", "character", "presentation" }) do
        if n:find(word, 1, true) then return true end
    end
    return false
end
local function valueText(v)
    if typeof(v) == "Instance" then return path(v) .. " [id=" .. ident(v) .. "]" end
    return clean(v)
end
local function metadata(object)
    local out = {}
    if not object then return out end
    local attrs = attempt(function() return object:GetAttributes() end, {})
    for name, value in pairs(attrs) do
        if attrRelevant(name) or matches(value) then out[#out + 1] = "attr " .. clean(name) .. "=" .. valueText(value) end
    end
    for _, child in ipairs(object:GetChildren()) do
        if child:IsA("ValueBase") then
            local value = attempt(function() return child.Value end, "<unavailable>")
            if attrRelevant(child.Name) or matches(value) then
                out[#out + 1] = child.ClassName .. " " .. clean(child.Name) .. "=" .. valueText(value)
            end
        end
    end
    table.sort(out)
    return out
end
local function targetInModel(model)
    if matches(model.Name) then return true end
    for _, item in ipairs(metadata(model)) do if matches(item) then return true end end
    return false
end
local function logPart(label, p, camera)
    if not p then add("    " .. label .. "=<none>"); return end
    local old = previous[p]
    local moved = old and attempt(function() return string.format("%.2f", (p.Position - old).Magnitude) end) or "first"
    previous[p] = p.Position
    local _, _, projection = screen(camera, p)
    add("    " .. label .. " id=" .. ident(p) .. " pos=" .. vec(p.Position) .. " moved=" .. moved .. " " .. projection .. " localTransparency=" .. tostring(p.LocalTransparencyModifier))
end
-- Do not inspect chat, text boxes, script sources, remote traffic or arbitrary HUD
-- text. Record a HUD label only when it contains the exact target substring.
local function chatAncestor(object)
    local cursor = object
    while cursor do
        if tostring(cursor.Name):lower():find("chat", 1, true) then return true end
        cursor = cursor.Parent
    end
    return false
end
local function inspectHud()
    local gui = me:FindFirstChildOfClass("PlayerGui")
    if not gui then add("HUD: PlayerGui unavailable"); return end
    local hits = {}
    for _, object in ipairs(gui:GetDescendants()) do
        if (object:IsA("TextLabel") or object:IsA("TextButton")) and not chatAncestor(object) then
            local label = attempt(function() return object.Text end, "")
            if matches(label) then
                hits[#hits + 1] = "  path=" .. path(object) .. " class=" .. object.ClassName .. " visible=" .. tostring(object.Visible) .. " text=" .. clean(label)
            end
        end
    end
    table.sort(hits)
    add("HUD exact target matches=" .. #hits .. " shown=" .. math.min(#hits, MAX_HUD) .. " (Visible is local property only; ancestor visibility may differ)")
    for i = 1, math.min(#hits, MAX_HUD) do add(hits[i]) end
end
local function snapshot(number)
    local camera = Workspace.CurrentCamera
    local roster = Players:GetPlayers()
    local owner = {}
    add(string.format("\n========== SAMPLE %d/%d elapsed=%.1fs ==========", number, SAMPLES, os.clock() - started))
    add("camera=" .. path(camera) .. " position=" .. (camera and vec(camera.CFrame.Position) or "<none>"))
    table.sort(roster, function(a, b) return a.Name < b.Name end)
    add("PLAYERS=" .. #roster)
    for _, player in ipairs(roster) do
        local char = player.Character
        if char then owner[char] = player end
        local team = player.Team and player.Team.Name or attempt(function() return player:GetAttribute("Team") end, "<none>")
        add("  PLAYER name=" .. clean(player.Name) .. " display=" .. clean(player.DisplayName) .. " userId=" .. tostring(player.UserId) .. " team=" .. clean(team) .. " character=" .. path(char) .. " targetMatch=" .. tostring(matches(player.Name) or matches(player.DisplayName)))
    end
    inspectHud()
    local candidates, seen = {}, {}
    for _, object in ipairs(Workspace:GetDescendants()) do
        if object:IsA("Model") and not seen[object] then
            seen[object] = true
            local ok, candidate = pcall(function()
                local r, h = root(object), part(object, "Head")
                local human = object:FindFirstChildOfClass("Humanoid")
                local anim = object:FindFirstChildOfClass("AnimationController")
                local named = targetInModel(object)
                if not named and not owner[object] and not (r and h and (human or anim)) then return nil end
                local onScreen, distance = screen(camera, h or r)
                return { model = object, r = r, h = h, human = human, anim = anim, named = named, onScreen = onScreen, distance = distance }
            end)
            if ok and candidate then candidates[#candidates + 1] = candidate end
        end
    end
    table.sort(candidates, function(a, b)
        if a.named ~= b.named then return a.named end
        if a.onScreen ~= b.onScreen then return a.onScreen end
        if a.distance ~= b.distance then return a.distance < b.distance end
        return path(a.model) < path(b.model)
    end)
    add("MODELS found=" .. #candidates .. " shown=" .. math.min(#candidates, MAX_MODELS) .. " (target matches first, then projected on-screen rigs nearest crosshair)")
    for i = 1, math.min(#candidates, MAX_MODELS) do
        local c = candidates[i]
        local ok, err = pcall(function()
            local p = owner[c.model]
            add("  MODEL id=" .. ident(c.model) .. " name=" .. clean(c.model.Name) .. " path=" .. path(c.model) .. " targetMatch=" .. tostring(c.named) .. " playerOwner=" .. (p and clean(p.Name) or "<none>") .. " humanoid=" .. tostring(c.human ~= nil) .. " animationController=" .. tostring(c.anim ~= nil))
            local entries = metadata(c.model)
            for j = 1, math.min(#entries, 25) do add("    " .. entries[j]) end
            if #entries > 25 then add("    metadata omitted=" .. (#entries - 25)) end
            logPart("root", c.r, camera)
            logPart("head", c.h, camera)
        end)
        if not ok then add("  MODEL ERROR " .. path(c.model) .. " " .. clean(err)) end
    end
end
local function save(report)
    local folder = "ShitaroHub/diagnostics"
    local file = folder .. "/block_strike_names_" .. os.date("!%Y%m%d_%H%M%S") .. ".txt"
    local fileOk, fileErr = false, "writefile unavailable"
    if type(writefile) == "function" then
        fileOk, fileErr = pcall(function()
            if type(makefolder) == "function" then
                for _, dir in ipairs({ "ShitaroHub", folder }) do
                    if type(isfolder) ~= "function" or not isfolder(dir) then
                        local ok, err = pcall(makefolder, dir)
                        if not ok and (type(isfolder) ~= "function" or not isfolder(dir)) then error(err) end
                    end
                end
            end
            writefile(file, report)
        end)
    end
    local copy = type(setclipboard) == "function" and setclipboard or (type(toclipboard) == "function" and toclipboard or nil)
    local copyOk, copyErr = false, "clipboard unavailable"
    if copy then copyOk, copyErr = pcall(copy, report) end
    local env = (getgenv and getgenv()) or _G
    env.ShitaroBlockStrikeNamesReport = report
    print("[Shitaro names] file: " .. (fileOk and file or "FAILED: " .. tostring(fileErr)))
    print("[Shitaro names] clipboard: " .. (copyOk and "copied" or "FAILED: " .. tostring(copyErr)))
    if not fileOk and not copyOk then warn("[Shitaro names] Both outputs failed; report follows and is stored in getgenv().ShitaroBlockStrikeNamesReport"); print(report) end
end
print("[Shitaro names] Started: 20 samples, about 19 seconds. Keep the target or scoreboard visible.")
local ok, err = xpcall(function()
    add("SHITAROHUB BLOCK STRIKE NAMES DIAGNOSTIC v1")
    add("UTC=" .. os.date("!%Y-%m-%d %H:%M:%S") .. " placeId=" .. tostring(game.PlaceId) .. " gameId=" .. tostring(game.GameId) .. " jobId=" .. tostring(game.JobId))
    add("target=" .. TARGET_NAME .. "; client state only. onScreen is projection, not proof of visibility. Contains nicknames, user IDs, positions, server ID and matching HUD text; review before sharing.")
    for i = 1, SAMPLES do
        local sampleOk, sampleErr = pcall(snapshot, i)
        if not sampleOk then add("SAMPLE ERROR " .. i .. ": " .. clean(sampleErr)) end
        print("[Shitaro names] sample " .. i .. "/" .. SAMPLES)
        if i < SAMPLES then task.wait(INTERVAL) end
    end
end, function(e) return tostring(e) end)
if not ok then add("FATAL ERROR; partial report: " .. clean(err)) end
add("\nEND OF REPORT")
save(table.concat(lines, "\n"))
