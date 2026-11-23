-- Exercise the shipped player draw gate and coherence logic with mock objects.
-- This checks only client-provided positions, not Roblox networking or Xeno.
local source = assert(io.open("modules/esp.lua", "rb")):read("*a")
local function section(first, last)
    local a = assert(source:find(first, 1, true), first)
    local b = assert(source:find(last, a, true), last)
    return source:sub(a, b-1)
end
local eligibility = section("    local DEAD_FLAGS = {", "    -- Per-player objects")
local coherenceSource = section("    local SPAN = 12", "    -- Returns an oriented box")
local drawSource = section("    local function drawPlayer(target, cam, camPos, viewport, origin, localChar, now, dt)", "    local function anyPlayerEnabled()")
local V = {}; V.__index=V
V.__add=function(a,b) return setmetatable({X=a.X+b.X,Y=a.Y+b.Y,Z=a.Z+b.Z},V) end
local function v(x,y,z) return setmetatable({X=x,Y=y,Z=z},V) end
local O = {}; O.__index=O
function O:GetAttribute(k) return self.attrs[k] end
function O:FindFirstChildOfClass(k) return self.humanoid and k == "Humanoid" and self.humanoid or nil end
function O:IsDescendantOf(p) local c=self.Parent; while c do if c==p then return true end;c=c.Parent end;return false end
local function object(name,parent,attrs) return setmetatable({Name=name,Parent=parent,attrs=attrs or {}},O) end
local workspace=object("Workspace")
local storage=object("Storage")
local players=object("Players")
local world=object("Characters",workspace)
local culled=object("Culled",storage)
local enemy=object("Enemy",players,{Health=100});enemy.UserId=99
local char=object("Enemy",world,{CharacterType="PlayerCustomCharacter",ClientCharacterPresentationVisible=true,Health=100})
local root=object("Root",char);root.Position=v(10,2,0)
local head=object("Head",char);head.Position=v(10,4,0)
enemy.Character=char
local rig={root=root,head=head,body=nil,parts={},count=0,feet={}}
local env=setmetatable({Players=players,Workspace=workspace,Enum={HumanoidStateType={Dead="Dead"}},
    cfg={ignoreTeam=true,ignoreFriends=true,palette={}},entries={},friendCache={},
    Vector3={zero=v(0,0,0)},table=setmetatable({clear=function(t) for k in pairs(t) do t[k]=nil end end},{__index=table})}, {__index=_G})
env.isAlive=assert(load(eligibility .. "\nreturn isAlive", "eligibility", "t", env))()
local coherence=assert(load(coherenceSource .. "\nreturn coherence", "coherence", "t", env))()
env.isTeammate=function(p) return p.teammate end
env.hideEntry=function(e) if e then e.visible=false end end
env.createEntry=function(p) local e={};env.entries[p]=e;return e end
env.drawEntity=function(entry, passedChar)
    entry.visible=true
    entry.character=passedChar
    local currentRig = passedChar.rig
    entry.position=coherence(currentRig)
end
char.rig=rig
local draw=assert(load(drawSource .. "\nreturn drawPlayer", "draw", "t", env))()
local function step() draw(enemy,nil,nil,nil,nil,nil,0,0) end
step();local entry=env.entries[enemy];assert(entry.visible and entry.position.X==10)
root.Position=v(30,2,0) -- a stale head must not override a fresh root
step();assert(entry.visible and entry.position.X==30,"ESP must follow current root")
char.Parent=culled;char.attrs.ClientCharacterPresentationVisible=false
root.Position=v(40,2,0);step();assert(not entry.visible,"PVS data is not displayed as current")
char.Parent=world;char.attrs.ClientCharacterPresentationVisible=true
step();assert(entry.visible and entry.position.X==40,"reappearing target uses new root")
enemy.teammate=true;step();assert(not entry.visible,"team filter")
enemy.teammate=false;env.friendCache[99]=true;step();assert(not entry.visible,"friend filter")
env.friendCache[99]=nil
local replacement=object("Enemy",world,{CharacterType="PlayerCustomCharacter",ClientCharacterPresentationVisible=true,Health=100})
local newRoot=object("Root",replacement);newRoot.Position=v(55,2,0)
replacement.rig={root=newRoot,parts={},count=0,feet={}};enemy.Character=replacement
step();assert(entry.visible and entry.character==replacement and entry.position.X==55,"respawn uses the new character")
print("PASS: live client root movement, PVS suppression, recovery, respawn and filters")
