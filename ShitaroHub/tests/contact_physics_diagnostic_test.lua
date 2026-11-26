-- Probe is passive, bounded, anonymous, and cleans up even on errors.
local function signal()
    local s={links={}}
    function s:Connect(fn)
        local item={enabled=true,fn=fn};self.links[#self.links+1]=item
        return {Disconnect=function() item.enabled=false end}
    end
    function s:Fire(...) for _,item in ipairs(self.links) do if item.enabled then item.fn(...) end end end
    return s
end
local v={};v.__index=function(t,k) if k=="Magnitude" then return math.sqrt(t.X*t.X+t.Y*t.Y+t.Z*t.Z) end end
v.__sub=function(a,b) return setmetatable({X=a.X-b.X,Y=a.Y-b.Y,Z=a.Z-b.Z},v) end
local function vec(x,y,z) return setmetatable({X=x,Y=y,Z=z},v) end
local function character(x)
    local c={Parent={},DescendantAdded=signal()}
    function c:IsA(k) return k=="Model" end
    local root={Name="HumanoidRootPart",Parent=c,Position=vec(x,0,0),AssemblyLinearVelocity=vec(0,0,0),
        AssemblyAngularVelocity=vec(0,0,0),CanTouch=true,CanCollide=true,CollisionGroup="players",Touched=signal()}
    function root:IsA(k) return k=="BasePart" end
    function root:FindFirstAncestorOfClass() return nil end
    function root:FindFirstChild(name) if name=="ShitaroContactPush" then return self.spin end end
    local hum={RigType="R15"};function hum:GetState() return "Running" end
    function c:GetDescendants() return {root} end
    function c:FindFirstChild(name) if name=="HumanoidRootPart" then return root end end
    function c:FindFirstChildOfClass(name) if name=="Humanoid" then return hum end end
    return c,root
end
local c,r=character(0);local otherChar,otherRoot=character(3)
local player={Character=c};local other={Character=otherChar,Name="private_user",UserId=12345}
local players={LocalPlayer=player}
function players:GetPlayers() return {player,other} end
function players:GetPlayerFromCharacter(ch) if ch==otherChar then return other elseif ch==c then return player end end
local physics={};function physics:CollisionGroupsAreCollidable(a,b) assert(a=="players" and b=="players");return false end
game={PlaceId=123,GetService=function(_,name) if name=="Players" then return players elseif name=="PhysicsService" then return physics end error(name) end}
local time=0;local oldClock=os.clock;os.clock=function() return time end
local waits=0
r.spin={AngularVelocity={Y=600}};r.AssemblyAngularVelocity=vec(0,35,0)
task={wait=function(dt)
    waits=waits+1;time=time+dt
    if waits==1 then r.Touched:Fire(otherRoot);r.AssemblyLinearVelocity=vec(100,0,0);otherRoot.AssemblyLinearVelocity=vec(5,0,0) end
end}
local env={};getgenv=function() return env end
local clipboard;setclipboard=function(text) clipboard=text end
isnetworkowner=function(root) return root==r end
writefile=nil;makefolder=nil;toclipboard=nil
assert(loadfile("diagnostics/contact_physics.lua"))()
local report=env.ShitaroContactPhysicsReport
assert(report==clipboard and report:find("placeId=123",1,true))
assert(report:find("groupPairCollides=false",1,true) and report:find("other=lastTouched",1,true))
assert(report:find("localSpeed=100.0",1,true) and report:find("otherSpeed=5.0",1,true))
assert(report:find("localAngular=35.0",1,true) and report:find("spinTargetY=600.0",1,true))
assert(report:find("localOwner=true",1,true) and report:find("otherOwner=false",1,true))
assert(not report:find("private_user",1,true) and not report:find("12345",1,true),"report is anonymous")
assert(waits<=100 and not r.Touched.links[1].enabled and not c.DescendantAdded.links[1].enabled,"bounded and disconnected")
-- If the sampled world becomes unreadable, save partial data and disconnect.
time=0;waits=0;clipboard=nil
players.GetPlayers=function() error("world unavailable") end
assert(loadfile("diagnostics/contact_physics.lua"))()
assert(clipboard:find("probeError=",1,true) and not r.Touched.links[#r.Touched.links].enabled,"failure still cleans up and exports")
-- Respawn rebinds to the new root; clipboard failure independently falls back to file.
players.GetPlayers=function() return {player,other} end
time=0;waits=0;local newChar,newRoot=character(0);local saved
setclipboard=function() error("clipboard unavailable") end
writefile=function(path,text) assert(path=="ShitaroHub/diagnostics/contact_physics.txt");saved=text end
makefolder=function() end
task.wait=function(dt)
    waits=waits+1;time=time+dt
    if waits==1 then player.Character=newChar end
    if waits==2 then newRoot.Touched:Fire(otherRoot) end
end
assert(loadfile("diagnostics/contact_physics.lua"))()
assert(saved and saved:find("touch t=",1,true),"respawn character is watched and file fallback succeeds")
assert(not r.Touched.links[#r.Touched.links].enabled and not newRoot.Touched.links[1].enabled,"respawn and shutdown disconnect")
os.clock=oldClock
io.write("PASS: passive contact physics diagnostic, privacy, failure and cleanup\n")
