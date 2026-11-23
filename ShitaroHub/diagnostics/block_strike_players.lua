-- ShitaroHub: focused player/position diagnostic for Block Strike.
-- Run this separately in the executor. No hooks or changes to game objects.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local me = Players.LocalPlayer
local SAMPLE_COUNT = 15
local INTERVAL = 1
local folder = "ShitaroHub/diagnostics"
local started = os.clock()
local lines = {}
local objectIds = setmetatable({}, { __mode = "k" })
local lastPos = setmetatable({}, { __mode = "k" })
local nextId = 0

local function log(text)
    lines[#lines + 1] = tostring(text)
end

local function safe(fn, fallback)
    local ok, result = pcall(fn)
    if ok and result ~= nil then return result end
    if fallback ~= nil then return fallback end
    return "<unavailable>"
end

local function text(value)
    local result = tostring(value):gsub("[\r\n\t]", " ")
    if #result > 180 then return result:sub(1, 180) .. "..." end
    return result
end

local function path(object)
    if not object then return "<none>" end
    return safe(function() return object:GetFullName() end)
end

local function id(object)
    if not object then return "-" end
    if not objectIds[object] then
        nextId = nextId + 1
        objectIds[object] = nextId
    end
    return tostring(objectIds[object])
end

local function position(vector)
    if not vector then return "<none>" end
    return safe(function() return string.format("(%.2f, %.2f, %.2f)", vector.X, vector.Y, vector.Z) end)
end

local function attr(object, name)
    if not object then return "<none>" end
    local value = safe(function() return object:GetAttribute(name) end, "<none>")
    return text(value)
end

local function part(char, name)
    local object = char and char:FindFirstChild(name)
    if object and object:IsA("BasePart") then return object end
end

local function team(player)
    if player.Team then return "RobloxTeam:" .. text(player.Team.Name) end
    local teamAttr = safe(function() return player:GetAttribute("Team") end, false)
    if teamAttr ~= false then return "TeamAttribute:" .. text(teamAttr) end
    return "<none>"
end

local function geometry(label, piece, camera)
    if not piece then log("    " .. label .. "=<none>"); return end
    local p = piece.Position
    local previous = lastPos[piece]
    local moved = previous and safe(function() return string.format("%.2f", (p - previous).Magnitude) end) or "first"
    lastPos[piece] = p
    local screen = "<no camera>"
    if camera then
        screen = safe(function()
            local projected, onScreen = camera:WorldToViewportPoint(p)
            local center = camera.ViewportSize
            local dx, dy = projected.X - center.X / 2, projected.Y - center.Y / 2
            return string.format("x=%.1f y=%.1f z=%.1f onScreen=%s fromCenter=%.1fpx", projected.X, projected.Y, projected.Z, tostring(onScreen), math.sqrt(dx * dx + dy * dy))
        end)
    end
    log("    " .. label .. " id=" .. id(piece) .. " position=" .. position(p) .. " moved=" .. moved .. " " .. screen .. " transparency=" .. text(piece.Transparency) .. " localTransparency=" .. text(piece.LocalTransparencyModifier))
end

local function snapshot(number)
    local camera = Workspace.CurrentCamera
    local roster = Players:GetPlayers()
    table.sort(roster, function(a, b) return a.Name < b.Name end)
    log(string.format("\n========== SAMPLE %d/%d elapsed=%.1fs ==========", number, SAMPLE_COUNT, os.clock() - started))
    log("LOCAL nickname=" .. text(me.Name) .. " display=" .. text(me.DisplayName) .. " team=" .. team(me))
    log("CAMERA path=" .. path(camera) .. " position=" .. (camera and position(camera.CFrame.Position) or "<none>") .. " viewport=" .. (camera and text(camera.ViewportSize) or "<none>"))
    log("PLAYERS count=" .. #roster)
    for _, player in ipairs(roster) do
        local ok, err = pcall(function()
            local char = player.Character
            local human = char and char:FindFirstChildOfClass("Humanoid")
            local anim = char and char:FindFirstChildOfClass("AnimationController")
            local inWorld = char and safe(function() return char:IsDescendantOf(Workspace) end, false) or false
            log("PLAYER nickname=" .. text(player.Name) .. " display=" .. text(player.DisplayName) .. " userId=" .. tostring(player.UserId) .. " local=" .. tostring(player == me) .. " team=" .. team(player) .. " neutral=" .. tostring(player.Neutral))
            log("    character=" .. path(char) .. " id=" .. id(char) .. " inWorkspace=" .. tostring(inWorld) .. " presentationVisible=" .. attr(char, "ClientCharacterPresentationVisible") .. " characterType=" .. attr(char, "CharacterType") .. " generation=" .. attr(char, "CharacterGeneration"))
            log("    health=" .. attr(player, "Health") .. " dead=" .. attr(player, "Dead") .. " characterHealth=" .. attr(char, "Health") .. " characterDead=" .. attr(char, "Dead") .. " ownerUserId=" .. attr(char, "PresentationOwnerUserId") .. " humanoid=" .. tostring(human ~= nil) .. " animationController=" .. tostring(anim ~= nil))
            geometry("root", part(char, "HumanoidRootPart") or (char and safe(function() return char.PrimaryPart end, false)), camera)
            geometry("head", part(char, "Head"), camera)
            geometry("upperTorso", part(char, "UpperTorso") or part(char, "Torso"), camera)
        end)
        if not ok then log("PLAYER ERROR nickname=" .. text(player.Name) .. " error=" .. text(err)) end
    end
end

local function save(report)
    local name = "block_strike_players_" .. os.date("!%Y%m%d_%H%M%S") .. ".txt"
    local filename = folder .. "/" .. name
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
            writefile(filename, report)
        end)
    end
    local copy = type(setclipboard) == "function" and setclipboard or (type(toclipboard) == "function" and toclipboard or nil)
    local copyOk, copyErr = false, "clipboard function unavailable"
    if copy then copyOk, copyErr = pcall(copy, report) end
    local env = (getgenv and getgenv()) or _G
    env.ShitaroBlockStrikePlayersReport = report
    print("[Shitaro players] file: " .. (fileOk and filename or "FAILED: " .. tostring(fileErr)))
    print("[Shitaro players] clipboard: " .. (copyOk and "copied" or "FAILED: " .. tostring(copyErr)))
    if not fileOk and not copyOk then
        warn("[Shitaro players] Both outputs failed; printing report. Also available as getgenv().ShitaroBlockStrikePlayersReport")
        print(report)
    end
end

print("[Shitaro players] Started immediately; watch an enemy for about 14 seconds.")
local ok, err = xpcall(function()
    log("SHITAROHUB BLOCK STRIKE PLAYERS DIAGNOSTIC v1")
    log("UTC=" .. os.date("!%Y-%m-%d %H:%M:%S") .. " placeId=" .. tostring(game.PlaceId) .. " gameId=" .. tostring(game.GameId) .. " jobId=" .. tostring(game.JobId))
    log("CLIENT state only; screen projection does not prove line of sight. Contains player nicknames, user IDs, server ID and positions; review before sharing.")
    for i = 1, SAMPLE_COUNT do
        local sampleOk, sampleErr = pcall(snapshot, i)
        if not sampleOk then log("SAMPLE ERROR " .. i .. ": " .. text(sampleErr)) end
        print("[Shitaro players] sample " .. i .. "/" .. SAMPLE_COUNT)
        if i < SAMPLE_COUNT then task.wait(INTERVAL) end
    end
end, function(e) return tostring(e) end)
if not ok then log("FATAL ERROR; partial report: " .. text(err)) end
log("\nEND OF REPORT")
save(table.concat(lines, "\n"))
