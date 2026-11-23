-- Test the real tracker and the production ESP marker/target closures using a
-- mocked Roblox API. This is not a Roblox engine or executor integration test.
local helper = assert(loadfile("core/esp_last_seen.lua"))()
local sourceFile = assert(io.open("modules/esp.lua", "rb"))
local source = sourceFile:read("*a")
sourceFile:close()
local function section(first, last)
    local a = assert(source:find(first, 1, true), first)
    local b = assert(source:find(last, a, true), last)
    return source:sub(a, b - 1)
end
local eligibility = section("    local DEAD_FLAGS = {", "    -- Per-player objects")
local markerSource = section("    local function hideLastSeen(target)", "    local HEALTH_COLORS =")
local drawSource = section("    local function drawPlayer(target, cam, camPos, viewport, origin, localChar, now, dt)", "    local function anyPlayerEnabled()")
local vec = {}
vec.__index = function(t, key)
    if key == "Magnitude" then return math.sqrt(t.X*t.X + t.Y*t.Y + t.Z*t.Z) end
    return vec[key]
end
vec.__sub = function(a,b) return setmetatable({X=a.X-b.X,Y=a.Y-b.Y,Z=a.Z-b.Z},vec) end
local function v(x,y,z) return setmetatable({X=x,Y=y,Z=z},vec) end
local O = {}; O.__index = O
function O:GetAttribute(key) return self.attrs[key] end
function O:FindFirstChildOfClass(name) return self.humanoid and name == "Humanoid" and self.humanoid or nil end
function O:FindFirstChild(name) return self.parts and self.parts[name] or nil end
function O:IsDescendantOf(parent)
    local cursor=self.Parent
    while cursor do if cursor == parent then return true end; cursor=cursor.Parent end
    return false
end
function O:IsA(class) return self.ClassName == class or (class == "BasePart" and self.ClassName == "Part") end
function O:GetState() return self.state end
local function obj(name, class, parent, attrs)
    return setmetatable({Name=name,ClassName=class,Parent=parent,attrs=attrs or {}}, O)
end
local workspace=obj("Workspace","Workspace")
local players=obj("Players","Players")
local storage=obj("Storage","ReplicatedStorage")
local worldFolder=obj("Characters","Folder",workspace)
local culled=obj("Culled","Folder",storage)
local enemy=obj("Enemy","Player",players,{Health=100,Dead=false,CharacterGeneration=1});enemy.UserId=99
local char=obj("Enemy","Model",worldFolder,{CharacterType="PlayerCustomCharacter",Health=100,ClientCharacterPresentationVisible=true})
local root=obj("HumanoidRootPart","Part",char);root.Position=v(10,2,0)
char.parts={HumanoidRootPart=root};char.PrimaryPart=root;enemy.Character=char
local origin=v(0,0,0)
local cam={onScreen=true}
function cam:WorldToViewportPoint(pos) return {X=pos.X+100,Y=pos.Y+100,Z=1},self.onScreen end
local env=setmetatable({
    Players=players, Workspace=workspace, cfg={lastSeen=true,ignoreTeam=true,ignoreFriends=true,range=500},
    tracker=helper.new(10), lastSeenLabels={}, entries={}, friendCache={},
    overlay={}, BLACK={}, STUDS_TO_M=.28, floor=math.floor,
    Vector2={new=function(x,y) return {x=x,y=y} end},
    UDim2={fromOffset=function(x,y) return {x=x,y=y} end},
    Color3={fromRGB=function(r,g,b) return {r,g,b} end},
    Enum={HumanoidStateType={Dead="Dead"},TextXAlignment={Center=1},TextYAlignment={Center=1}},
}, {__index=_G})
env.make=function(_,props) return props end
local getEligibility=assert(load(eligibility .. "\nreturn isAlive,flagged", "eligibility", "t", env))
env.isAlive,env.flagged=getEligibility()
local getMarkers=assert(load(markerSource .. "\nreturn hideLastSeen,clearLastSeen,characterGeneration,canKeepLastSeen,showLastSeen", "markers", "t", env))
env.hideLastSeen,env.clearLastSeen,env.characterGeneration,env.canKeepLastSeen,env.showLastSeen=getMarkers()
env.isTeammate=function(t) return t.teammate == true end
env.hideEntry=function(e) if e then e.holder.Visible=false end end
env.createEntry=function(t) local e={holder={Visible=true}};env.entries[t]=e;return e end
env.drawEntity=function(e) e.holder.Visible=true end
local drawPlayer=assert(load(drawSource .. "\nreturn drawPlayer", "drawPlayer", "t", env))()
local function draw(now) drawPlayer(enemy,cam,v(0,0,0),nil,origin,nil,now,1/60) end
local function label() return env.lastSeenLabels[enemy] end

draw(1)
assert(env.entries[enemy].holder.Visible and not label(), "eligible live player")
char.Parent=culled
char.attrs.ClientCharacterPresentationVisible=false
draw(3)
assert(not env.entries[enemy].holder.Visible and label().Visible, "hidden character should show only marker")
assert(label().Text == "Enemy  ? 2s", "uncertainty marker and age")
assert(label().Position.x==110 and label().Position.y==102)
cam.onScreen=false;draw(4);assert(not label().Visible,"outside viewport must hide")
cam.onScreen=true;draw(5);assert(label().Visible,"back on screen")
env.cfg.range=1;draw(5);assert(not label().Visible,"range filter must apply")
env.cfg.range=500;draw(5);assert(label().Visible)
enemy.teammate=true;draw(5);assert(not label().Visible,"ally filter must hide and forget")
enemy.teammate=false;draw(5);assert(not label().Visible,"filter must clear stored position")

char.Parent=worldFolder;char.attrs.ClientCharacterPresentationVisible=true;draw(6)
char.Parent=culled;draw(17);assert(not label().Visible,"last-known position must expire after ten seconds")
char.Parent=worldFolder;draw(20);char.Parent=culled;enemy.attrs.Dead=true;draw(21);assert(not label().Visible,"dead players must be cleared")
enemy.attrs.Dead=false;draw(21);assert(not label().Visible,"death must clear the cache")
char.Parent=worldFolder;draw(22);char.Parent=culled;enemy.attrs.CharacterGeneration=2;draw(23);assert(not label().Visible,"generation change invalidates prior spawn")
enemy.attrs.CharacterGeneration=1;char.Parent=worldFolder;draw(24)
local replacement=obj("Enemy","Model",culled,{CharacterType="PlayerCustomCharacter",Health=100});enemy.Character=replacement
draw(25);assert(not label().Visible,"different character invalidates cache")
enemy.Character=char;char.Parent=worldFolder;draw(26);char.Parent=culled;env.friendCache[enemy.UserId]=true;draw(27);assert(not label().Visible,"friend filter must hide marker")
env.friendCache[enemy.UserId]=nil;env.cfg.lastSeen=false;env.tracker.clear();char.Parent=worldFolder;draw(28);char.Parent=culled;draw(29);assert(not label().Visible,"disabled feature must not collect or render")
-- Nil characters, detached Players, and disappearing root cannot retain ghosts.
env.cfg.lastSeen=true;char.Parent=worldFolder;draw(30);enemy.Character=nil;draw(31);assert(not label().Visible)
enemy.Character=char;char.Parent=worldFolder;draw(32);char.Parent=culled;enemy.Parent=nil;draw(33);assert(not label().Visible)
enemy.Parent=players;char.Parent=worldFolder;char.parts={};char.PrimaryPart=nil;draw(34);char.Parent=culled;draw(35);assert(not label().Visible)
print("PASS: last-seen marker (world/PVS, uncertainty, age, range, filters, death, respawn, disable)")
