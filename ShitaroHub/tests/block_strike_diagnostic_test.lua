-- Mocked integration test: lua tests/block_strike_diagnostic_test.lua
-- Exercises the standalone script, not the actual Roblox engine or executor.
local nativePrint = print
local messages, files, clipboard = {}, {}, nil
print = function(value) messages[#messages + 1] = tostring(value) end
warn = print

local vector = {}
vector.__index = function(self, key)
    if key == "Magnitude" then return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z) end
    return vector[key]
end
vector.__sub = function(a, b) return setmetatable({ X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z }, vector) end
local function vec(x, y, z) return setmetatable({ X = x, Y = y, Z = z }, vector) end

local object = {}
object.__index = object
function object:IsA(class)
    return self.ClassName == class or (class == "BasePart" and self.ClassName == "Part")
        or (class == "ValueBase" and self.ClassName == "StringValue")
end
function object:GetFullName() return self.Parent and (self.Parent:GetFullName() .. "." .. self.Name) or self.Name end
function object:GetChildren() return self.children end
function object:GetDescendants()
    local out = {}
    local function visit(parent)
        for _, child in ipairs(parent.children) do out[#out + 1] = child; visit(child) end
    end
    visit(self)
    return out
end
function object:GetAttributes() return self.attrs end
function object:FindFirstChild(name)
    for _, child in ipairs(self.children) do if child.Name == name then return child end end
end
function object:FindFirstChildOfClass(class)
    for _, child in ipairs(self.children) do if child.ClassName == class then return child end end
end
function object:FindFirstChildWhichIsA(class)
    for _, child in ipairs(self.children) do if child:IsA(class) then return child end end
end
function object:GetState() return "Running" end
local function new(class, name, parent, extras)
    local obj = setmetatable({ ClassName = class, Name = name, Parent = parent, children = {}, attrs = {} }, object)
    for key, value in pairs(extras or {}) do obj[key] = value end
    if parent then parent.children[#parent.children + 1] = obj end
    return obj
end
function typeof(value)
    if getmetatable(value) == object then return "Instance" end
    return type(value)
end
local workspace = new("Workspace", "Workspace", nil, { StreamingEnabled = true, StreamingTargetRadius = 128, StreamingMinRadius = 64 })
local camera = new("Camera", "Camera", workspace, { CFrame = { Position = vec(0, 3, 0) }, ViewportSize = "1920,1080" })
function camera:WorldToViewportPoint(p) return vec(p.X, p.Y, 1), true end
workspace.CurrentCamera = camera
local red = new("Team", "Red")
local blue = new("Team", "Blue")
local function avatar(name, x)
    local model = new("Model", name, workspace)
    local root = new("Part", "HumanoidRootPart", model, { Position = vec(x, 0, 0), Anchored = false, Transparency = 1, LocalTransparencyModifier = 0 })
    new("Part", "Head", model, { Position = vec(x, 3, 0), Anchored = false, Transparency = 0, LocalTransparencyModifier = 0 })
    new("Humanoid", "Humanoid", model, { RootPart = root, Health = 100 })
    return model, root
end
local own = avatar("Local", 0)
local enemy, enemyRoot = avatar("Enemy", 10)
local friend = avatar("Friend", 20)
local enemyClone, cloneRoot = avatar("Enemy", 15)
local human = enemyClone:FindFirstChildOfClass("Humanoid")
-- Keep a player-name-matched model without Humanoid, to exercise custom avatars.
for i, child in ipairs(enemyClone.children) do if child == human then table.remove(enemyClone.children, i); break end end
local function player(name, userId, team, char)
    return new("Player", name, nil, { DisplayName = name, UserId = userId, Team = team, TeamColor = team.Name, Neutral = false, Character = char })
end
local me = player("Local", 1, red, own)
local target = player("Enemy", 2, blue, enemy)
local teammate = player("Friend", 3, red, friend)
target.attrs.Faction = "Blue"
local players = { LocalPlayer = me }
function players:GetPlayers() return { me, target, teammate } end
local services = { Players = players, Workspace = workspace }
game = { PlaceId = 1, GameId = 2, JobId = "server-test" }
function game:GetService(name) return assert(services[name]) end
local env = {}
function getgenv() return env end
local folders = {}
function isfolder(path) return folders[path] == true end
function makefolder(path) folders[path] = true end
function writefile(path, text) files[path] = text end
function setclipboard(text) clipboard = text end
task = {}
function task.wait()
    enemyRoot.Position = vec(enemyRoot.Position.X + 2, 0, 0)
    cloneRoot.Position = vec(cloneRoot.Position.X + 1, 0, 0)
end

dofile("diagnostics/block_strike.lua")
local report = assert(env.ShitaroBlockStrikeReport)
assert(report == clipboard, "clipboard must contain the complete report")
local saved
for path, text in pairs(files) do saved = text; assert(path:match("^ShitaroHub/diagnostics/block_strike_esp_.*%.txt$")) end
assert(report == saved, "file must contain the same complete report")
assert(select(2, report:gsub("========== SAMPLE %d/8", "")) == 8, "all eight samples")
assert(report:find("second_side_detected=true", 1, true))
assert(report:match("PLAYER name=Friend[^\n]-simulated_teammate=true"))
assert(report:match("PLAYER name=Enemy[^\n]-simulated_teammate=false"))
assert(report:find("player attr Faction=Blue", 1, true))
assert(report:find("name_matches=Enemy humanoid=<none>", 1, true))
assert(report:find("moved_since_last=2.00", 1, true))
assert(report:find("END OF REPORT", 1, true))

-- A filesystem failure must not prevent clipboard output and in-memory recovery.
writefile = function() error("disk unavailable") end
clipboard = nil
dofile("diagnostics/block_strike.lua")
assert(clipboard == env.ShitaroBlockStrikeReport)
local failureReported = false
for _, message in ipairs(messages) do if message:find("file: FAILED", 1, true) then failureReported = true end end
assert(failureReported)
-- If both outputs are unavailable, the full report is printed and retained.
setclipboard = nil
toclipboard = nil
me.Team, target.Team, teammate.Team = nil, nil, nil
me.attrs.Faction, target.attrs.Faction, teammate.attrs.Faction = "red", "blue", "red"
dofile("diagnostics/block_strike.lua")
report = env.ShitaroBlockStrikeReport
assert(report:find("local=attr:faction:red kind=attr second_side_detected=true", 1, true))
assert(report:match("PLAYER name=Friend[^\n]-simulated_teammate=true"))
local printedReport = false
for _, message in ipairs(messages) do if message == report then printedReport = true end end
assert(printedReport, "report should be printed if both output methods fail")
nativePrint("PASS: diagnostic mock integration (sampling, teams, attributes, custom models, output fallbacks)")

-- Focused player report: names, custom avatars, projection, and immediate samples.
function object:GetAttribute(name) return self.attrs[name] end
function object:IsDescendantOf(ancestor)
    local parent = self.Parent
    while parent do
        if parent == ancestor then return true end
        parent = parent.Parent
    end
    return false
end
camera.ViewportSize = vec(1920, 1080, 0)
me.attrs.Team, target.attrs.Team, teammate.attrs.Team = "Counter-Terrorists", "Terrorists", "Counter-Terrorists"
local replicated = new("ReplicatedStorage", "ReplicatedStorage")
local culled = new("Folder", "_PVS_CulledCharacters", replicated)
local waits = 0
function task.wait()
    waits = waits + 1
    enemyRoot.Position = vec(enemyRoot.Position.X + 2, 0, 0)
    if waits == 3 then enemy.Parent = culled end
    if waits == 7 then enemy.Parent = workspace end
end
writefile = function(path, text) files[path] = text end
setclipboard = function(text) clipboard = text end
clipboard = nil
dofile("diagnostics/block_strike_players.lua")
report = assert(env.ShitaroBlockStrikePlayersReport)
assert(report == clipboard)
assert(select(2, report:gsub("========== SAMPLE %d+/15", "")) == 15)
assert(report:find("PLAYER nickname=Enemy display=Enemy userId=2", 1, true))
assert(report:find("team=TeamAttribute:Terrorists", 1, true))
assert(report:find("character=Workspace.Enemy", 1, true))
assert(report:find("inWorkspace=true", 1, true))
assert(report:find("character=ReplicatedStorage._PVS_CulledCharacters.Enemy", 1, true))
assert(report:find("inWorkspace=false", 1, true))
assert(report:find("moved=2.00", 1, true))
assert(report:find("onScreen=true", 1, true))
assert(report:find("END OF REPORT", 1, true))
local savedPlayerReport = false
for path, data in pairs(files) do
    if path:match("block_strike_players_.*%.txt$") then
        assert(data == report)
        savedPlayerReport = true
    end
end
assert(savedPlayerReport)
-- Failed file and clipboard output falls back to console and in-memory report.
writefile = function() error("disk unavailable") end
setclipboard = nil
dofile("diagnostics/block_strike_players.lua")
report = env.ShitaroBlockStrikePlayersReport
local printed = false
for _, message in ipairs(messages) do if message == report then printed = true end end
assert(printed)
nativePrint("PASS: focused player diagnostic (nicknames, sampling, movement, fallback)")

-- Names diagnostic discovers HUD labels and non-Players character models.
local playerGui = new("PlayerGui", "PlayerGui", me)
local scoreboard = new("Frame", "Scoreboard", playerGui)
new("TextLabel", "Victim", scoreboard, { Text = "AnotherPlayer", Visible = true })
local chat = new("Frame", "ChatFrame", playerGui)
new("TextLabel", "Message", chat, { Text = "AnotherPlayer PRIVATE_CHAT", Visible = true })
local enemyNpc, npcRoot = avatar("CustomBot", 30)
enemyNpc.attrs.DisplayName = "AnotherPlayer"
local billboard = new("BillboardGui", "NameGui", enemyNpc)
new("TextLabel", "NameLabel", billboard, { Text = "AnotherPlayer", Visible = true })
writefile = function(path, data) files[path] = data end
setclipboard = function(data) clipboard = data end
clipboard = nil
dofile("diagnostics/block_strike_names.lua")
report = assert(env.ShitaroBlockStrikeNamesReport)
assert(report == clipboard)
assert(select(2, report:gsub("========== SAMPLE %d+/20", "")) == 20)
assert(report:find("HUD scoreboard/kill-feed/known-name entries=1 shown=1", 1, true))
assert(report:find("text=AnotherPlayer", 1, true))
assert(not report:find("PRIVATE_CHAT", 1, true))
assert(report:find("name=CustomBot path=Workspace.CustomBot targetMatch=false playerOwner=<none>", 1, true))
assert(report:find("attr DisplayName=AnotherPlayer", 1, true))
assert(report:find("model_label path=Workspace.CustomBot.NameGui.NameLabel text=AnotherPlayer", 1, true))
assert(report:find("END OF REPORT", 1, true))
local foundNames = false
for path, data in pairs(files) do
    if path:match("block_strike_names_.*%.txt$") then assert(data == report); foundNames = true end
end
assert(foundNames)
writefile = function() error("disk unavailable") end
setclipboard = nil
dofile("diagnostics/block_strike_names.lua")
report = env.ShitaroBlockStrikeNamesReport
printed = false
for _, message in ipairs(messages) do if message == report then printed = true end end
assert(printed)
nativePrint("PASS: name diagnostic (non-player model, HUD target, chat omission, output fallback)")

-- Snapshot probe: passive listener, telemetry redaction, clean disconnect.
services.ReplicatedStorage = replicated
local remoteFolder = new("Folder", "MovementV2Remotes", replicated)
local remote = new("RemoteEvent", "RemoteSnapshot", remoteFolder)
local listener, disconnected
remote.OnClientEvent = {}
function remote.OnClientEvent:Connect(callback)
    listener = callback
    return { Disconnect = function() disconnected = true end }
end
local previousTypeof = typeof
function typeof(value) if getmetatable(value) == vector then return "Vector3" end return previousTypeof(value) end
writefile = function(path, data) files[path] = data end
setclipboard = function(data) clipboard = data end
clipboard = nil
target.Character.attrs.ClientCharacterPresentationVisible = false
function task.wait()
    assert(listener)
    listener({player="Enemy", secret="PASSWORD_HIDDEN", position=vec(1,2,3), userId=2})
end
dofile("diagnostics/block_strike_snapshots.lua")
report = assert(env.ShitaroBlockStrikeSnapshotsReport)
assert(report == clipboard and disconnected)
assert(select(2, report:gsub("SAMPLE %d+/20", "")) == 20)
assert(report:find("RemoteSnapshot listener attached", 1, true))
assert(report:find("REMOTE totals received=19 sampled=", 1, true))
assert(report:find("arg1.position Vector3=(1.00, 2.00, 3.00)", 1, true))
assert(report:find("arg1.player string=Enemy", 1, true))
assert(report:find("arg1.secret string=<redacted>", 1, true))
assert(report:match("PLAYER name=Enemy[^\n]-presentationVisible=false"))
assert(not report:find("PASSWORD_HIDDEN", 1, true))
local foundSnapshot = false
for path, data in pairs(files) do
    if path:match("block_strike_snapshots_.*%.txt$") then assert(data == report); foundSnapshot = true end
end
assert(foundSnapshot)
nativePrint("PASS: passive snapshot probe (sampling, redaction, disconnect, output)")

-- No event and no executor output support: still return a console report.
remote.ClassName = "Folder"
writefile = function() error("disk unavailable") end
setclipboard = nil
task.wait = function() end
dofile("diagnostics/block_strike_snapshots.lua")
report = env.ShitaroBlockStrikeSnapshotsReport
assert(report:find("RemoteSnapshot unavailable", 1, true))
assert(report:find("REMOTE totals received=0 sampled=0", 1, true))
printed = false
for _, message in ipairs(messages) do if message == report then printed = true end end
assert(printed)
nativePrint("PASS: snapshot probe missing-event and output-failure fallbacks")

-- Binary probe: bounded raw buffer samples, 0-based offsets, privacy and fallback.
remote.ClassName = "RemoteEvent"
local fakeBufferMeta = {}
buffer = {}
function buffer.len(value) return #value.bytes end
function buffer.readu8(value, index) return assert(value.bytes[index + 1]) end
local priorTypeof = typeof
function typeof(value) if getmetatable(value) == fakeBufferMeta then return "buffer" end return priorTypeof(value) end
local fakeBytes = {}
for i = 1, 600 do fakeBytes[i] = (i - 1) % 256 end
local fakeBuffer = setmetatable({ bytes = fakeBytes }, fakeBufferMeta)
writefile = function(path, data) files[path] = data end
setclipboard = function(data) clipboard = data end
clipboard, disconnected = nil, false
function task.wait() assert(listener); listener(fakeBuffer) end
dofile("diagnostics/block_strike_buffers.lua")
report = assert(env.ShitaroBlockStrikeBuffersReport)
assert(report == clipboard and disconnected)
assert(select(2, report:gsub("SAMPLE %d+/40", "")) == 40)
assert(report:find("REMOTE totals received=39 sampled=", 1, true))
assert(report:find("arg1 buffer length=600 hex_offset=0 bytes=512 truncated=true hex=000102030405", 1, true))
assert(report:find("RAW BUFFER BYTES", 1, true))
local foundBuffer = false
for path, data in pairs(files) do
    if path:match("block_strike_buffers_.*%.txt$") then assert(data == report); foundBuffer = true end
end
assert(foundBuffer)
remote.ClassName = "Folder"
writefile = function() error("disk unavailable") end
setclipboard = nil
task.wait = function() end
dofile("diagnostics/block_strike_buffers.lua")
report = env.ShitaroBlockStrikeBuffersReport
assert(report:find("RemoteSnapshot unavailable", 1, true))
printed = false
for _, message in ipairs(messages) do if message == report then printed = true end end
assert(printed)
nativePrint("PASS: bounded binary samples (hex, truncation, listener cleanup, fallbacks)")

-- Track ALL received packets after correlating a spawn to a world model.
-- This synthetic buffer does not contain data from the user's game.
remote.ClassName = "RemoteEvent"
target.UserId = 9876543211
target.Character = enemy
enemy.Parent = workspace
enemy.attrs.ClientCharacterPresentationVisible = true
enemyRoot.Position = vec(10, 2, 0)
local function encodeVarint(n)
    local out={}
    repeat
        local b=n%128;n=math.floor(n/128)
        out[#out+1]=string.char(b+(n>0 and 128 or 0))
    until n==0
    return table.concat(out)
end
local function packBuffer(raw)
    local bytes={}
    for i=1,#raw do bytes[i]=string.byte(raw,i) end
    return setmetatable({bytes=bytes},fakeBufferMeta)
end
function buffer.tostring(value)
    local out={}
    for i,b in ipairs(value.bytes) do out[i]=string.char(b) end
    return table.concat(out)
end
function buffer.readf32(value, offset)
    return (string.unpack("<f",buffer.tostring(value),offset+1))
end
local entity=string.char(0xe6,0x25)
local spawn=packBuffer(string.char(6,1)..string.rep("\0",27)..encodeVarint(target.UserId)..entity..string.char(9)..string.pack("<fff",10,2,0)..string.rep("\0",6))
local delta=packBuffer(string.char(6,1)..string.rep("\0",27)..entity..string.char(3)..string.rep("\0",12))
local tickCount=0
function task.wait()
    tickCount=tickCount+1
    if tickCount == 1 then listener(spawn) else
        if tickCount == 3 then enemy.Parent=culled;enemy.attrs.ClientCharacterPresentationVisible=false end
        listener(delta)
    end
end
writefile = function(path,data) files[path]=data end
setclipboard = function(data) clipboard=data end
clipboard,disconnected=nil,false
dofile("diagnostics/block_strike_tracking.lua")
report=assert(env.ShitaroBlockStrikeTrackingReport)
assert(report == clipboard and disconnected)
assert(report:find("MAPPED",1,true) and report:find("name=Enemy userId=9876543211 entity_hex=e625",1,true))
assert(report:find("MATCH",1,true) and report:find("phase=World entity_hex=e625",1,true))
assert(report:find("phase=Hidden entity_hex=e625",1,true))
assert(report:find("SUMMARY received=180 processedBuffers=180 acceptedPackets=180 errors=0",1,true))
assert(report:find("hitsHidden=178/178",1,true))
assert(report:find("HEURISTIC",1,true))
local foundTrack=false
for path,data in pairs(files) do
    if path:match("block_strike_tracking_.*%.txt$") then assert(data==report);foundTrack=true end
end
assert(foundTrack)
remote.ClassName="Folder"
writefile=function() error("disk unavailable") end
setclipboard=nil
task.wait=function() end
dofile("diagnostics/block_strike_tracking.lua")
report=env.ShitaroBlockStrikeTrackingReport
assert(report:find("RemoteSnapshot unavailable",1,true))
printed=false
for _, message in ipairs(messages) do if message==report then printed=true end end
assert(printed)
nativePrint("PASS: full-traffic identity mapping, world/hidden counts and fallbacks")

-- A generation change must invalidate the previous short entity ID.
remote.ClassName="RemoteEvent"
target.Character=enemy;enemy.Parent=workspace;enemy.attrs.ClientCharacterPresentationVisible=true
enemy.attrs.CharacterGeneration=10
enemyRoot.Position=vec(10,2,0)
tickCount=0
function task.wait()
    tickCount=tickCount+1
    if tickCount==1 then listener(spawn) else
        if tickCount==3 then enemy.attrs.CharacterGeneration=11 end
        listener(delta)
    end
end
writefile=function(path,data) files[path]=data end
setclipboard=function(data) clipboard=data end
dofile("diagnostics/block_strike_tracking.lua")
report=env.ShitaroBlockStrikeTrackingReport
assert(report:find("RESET",1,true) and report:find("name=Enemy reason=character_or_generation_changed",1,true))
assert(report:match("RESULT name=Enemy userId=9876543211 mapped=no"))
nativePrint("PASS: tracking forgets entity IDs when a player respawns")

-- Full-state packets can identify players already present before the probe.
-- Stopping via the fallback callback must finalize and disconnect immediately.
remote.ClassName="RemoteEvent"
target.Character=enemy;enemy.Parent=workspace;enemy.attrs.ClientCharacterPresentationVisible=true
enemy.attrs.CharacterGeneration=30;enemyRoot.Position=vec(10,2,0)
local fullSpawn=packBuffer(string.char(6,0)..string.rep("\0",27)..encodeVarint(target.UserId)..entity..string.char(9)..string.pack("<fff",10,2,0)..string.rep("\0",6))
tickCount=0
function task.wait()
    tickCount=tickCount+1
    if tickCount==1 then listener(fullSpawn) else assert(env.ShitaroFinishTracking)() end
end
writefile=function(path,data) files[path]=data end
setclipboard=function(data) clipboard=data end
clipboard,disconnected=nil,false
dofile("diagnostics/block_strike_tracking.lua")
report=env.ShitaroBlockStrikeTrackingReport
assert(disconnected and clipboard==report)
assert(report:find("name=Enemy userId=9876543211 entity_hex=e625",1,true))
assert(report:find("COLLECTION end=user_stopped",1,true))
assert(report:find("SUMMARY received=1 processedBuffers=1 acceptedPackets=1 errors=0",1,true))
assert(env.ShitaroFinishTracking==nil)
nativePrint("PASS: full-state mapping and early-stop callback")

-- Mock the GUI so the on-screen button and cleanup are exercised as well.
local madeGui, clickCallback, clickDisconnected
Instance={new=function(class)
    local item={ClassName=class}
    if class=="ScreenGui" then
        madeGui=item
        function item:Destroy() self.destroyed=true end
    elseif class=="TextButton" then
        item.MouseButton1Click={Connect=function(_,fn)
            clickCallback=fn
            return {Disconnect=function() clickDisconnected=true end}
        end}
    end
    return item
end}
UDim2={fromOffset=function(x,y) return {x=x,y=y} end,new=function(...) return {...} end}
Color3={fromRGB=function(...) return {...} end}
tickCount=0
function task.wait()
    tickCount=tickCount+1
    if tickCount==1 then listener(fullSpawn) else assert(clickCallback)() end
end
clipboard,disconnected=nil,false
dofile("diagnostics/block_strike_tracking.lua")
report=env.ShitaroBlockStrikeTrackingReport
assert(report:find("COLLECTION end=user_stopped",1,true))
assert(disconnected and clickDisconnected and madeGui.destroyed and clipboard==report)
assert(env.ShitaroFinishTracking==nil)
Instance=nil
nativePrint("PASS: in-game stop button, report and cleanup")
