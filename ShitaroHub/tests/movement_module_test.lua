-- Exercise the actual UI module, physics adapter and cleanup using Roblox mocks.
local function signal()
    local s={listeners={}}
    function s:Connect(f)
        local item={fn=f,enabled=true};self.listeners[#self.listeners+1]=item
        return {Disconnect=function() item.enabled=false end}
    end
    function s:Fire(...) for _,item in ipairs(self.listeners) do if item.enabled then item.fn(...) end end end
    return s
end
local objects={}
local function new(class,props,parent)
    local obj={ClassName=class,Parent=parent,Activated=signal()}
    for k,v in pairs(props or {}) do obj[k]=v end
    function obj:Destroy() self.destroyed=true;self.Parent=nil end
    objects[#objects+1]=obj
    return obj
end
local created={};local failClass
warn=function() end
Instance={new=function(class) if class==failClass then error("unsupported "..class) end
    local o=new(class,{},nil);created[#created+1]=o;return o end}
UDim2={new=function(...) return {...} end,fromOffset=function(...) return {...} end,fromScale=function(...) return {...} end}
UDim={new=function(...) return {...} end}
CFrame={Angles=function(...) return {...} end}
Vector2={new=function(...) return {...} end}
local vector={}
vector.__index=function(v,k) if k=="Magnitude" then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z) end end
vector.__sub=function(a,b) return setmetatable({X=a.X-b.X,Y=a.Y-b.Y,Z=a.Z-b.Z},vector) end
Vector3={new=function(x,y,z) return setmetatable({X=x,Y=y,Z=z},vector) end}
Color3={new=function(...) return {...} end}
Enum={HumanoidStateType={Freefall="Freefall",Running="Running"},Material={Air="Air",Ground="Ground"},ActuatorRelativeTo={World="World"},
    AlignType={PrimaryAxisParallel="PrimaryAxisParallel"},OrientationAlignmentMode={OneAttachment="OneAttachment"}}
local world={Gravity=200}
game={GetService=function(_,n) assert(n=="Workspace");return world end}
local function character()
    local char={Parent={},DescendantAdded=signal()}
    function char:IsA(k) return k=="Model" end
    local hum={Parent=char,Health=100,WalkSpeed=16,JumpPower=50,JumpHeight=7.2,UseJumpPower=true,
        FloorMaterial=Enum.Material.Ground,State=Enum.HumanoidStateType.Running,AutoRotate=true}
    function hum:GetState() return self.State end
    local root={Parent=char,AssemblyMass=10,AssemblyLinearVelocity={Y=0},Anchored=false,
        AssemblyAngularVelocity=Vector3.new(0,0,0),Position=Vector3.new(0,0,0),Touched=signal()}
    function root:IsA(k) return k=="BasePart" end
    function root:ApplyImpulse(impulse) self.lastImpulse=impulse end
    function root:FindFirstAncestorOfClass() return nil end
    function char:GetDescendants() return {root} end
    function char:FindFirstChildOfClass(k) if k=="Humanoid" then return hum end end
    function char:FindFirstChild(k) if k=="HumanoidRootPart" then return root end end
    return char,hum,root
end
local char,hum,root=character();local player={Character=char}
local playersByCharacter={[char]=player}
local players={GetPlayerFromCharacter=function(_,candidate) return playersByCharacter[candidate] end}
local savedClock=os.clock;local mockTime=0;os.clock=function() return mockTime end
local gui={Destroying=signal()};local heartbeat=signal();local links={}
gui.Destroying:Connect(function() for _,link in ipairs(links) do link:Disconnect() end end)
local sliders={}
local uiState={}
local ctx={player=player,Players=players,gui=gui,uiState=uiState,RunService={Heartbeat=heartbeat},
    Loader={module=function(p) return assert(loadfile(p))() end},
    tabs={[4]={page={}}},panelWidths={},colors={sub={},accent={}},locale={en={},ru={}},
    make=new,corner=function() end,animate=function(obj,props) for k,v in pairs(props) do obj[k]=v end end,
    connect=function(event,fn) local link=event:Connect(fn);links[#links+1]=link;return link end,
    pageScroll=function(parent,name) return new("ScrollingFrame",{Name=name},parent) end,
    previewPanel=function(scroll,name) return new("Frame",{Name=name},scroll) end,
    previewRow=function(card,index) return new("Frame",{Name="Row"..index},card),new("TextLabel",{},card) end,
    localize=function() end,layoutPreview=function() end,
    rowSlider=function(row,name,min,max,format,onChange)
        local s={min=min,max=max}
        function s.set(value,notify) s.value=value;if notify then onChange(value) end end
        sliders[name]=s;return s
    end,
}
assert(loadfile("modules/movement.lua"))()(ctx)
local function control(name)
    for _,o in ipairs(objects) do if o.Name==name then return o end end
    error("missing "..name)
end
local speed=control("MovementspeedToggle")
local jump=control("MovementjumpToggle")
local fall=control("MovementfallToggle")
local contact=control("MovementcontactToggle")
local always=control("MovementalwaysSpinToggle")
assert(contact.Parent.Name=="Row7" and always.Parent.Name=="Row8","always spin is next to touch push")
heartbeat:Fire();assert(hum.WalkSpeed==16 and hum.JumpPower==50 and #created==0,"starts disabled")
assert(sliders.Movementspeed.max==200,"UI exposes 200 maximum")
sliders.Movementspeed.set(200,true);speed.Activated:Fire();assert(hum.WalkSpeed==200)
sliders.Movementspeed.set(65,true);assert(hum.WalkSpeed==65)
sliders.MovementjumpPower.set(80,true);jump.Activated:Fire();assert(hum.JumpPower==80)
fall.Activated:Fire();assert(#created==0,"ground does not create a force")
-- Contact falls back to a short local spin when ownership is unavailable.
local otherChar,otherHum,otherRoot=character();local otherPlayer={Character=otherChar};playersByCharacter[otherChar]=otherPlayer
otherRoot.Position=Vector3.new(2,0,0)
contact.Activated:Fire();local objectsBeforeContact=#created
root.Touched:Fire(root);assert(#created==objectsBeforeContact,"own character ignored")
otherRoot.Position=Vector3.new(30,0,0);root.Touched:Fire(otherRoot);assert(#created==objectsBeforeContact,"distant player ignored")
otherRoot.Position=Vector3.new(2,0,0);hum.SeatPart={};root.Touched:Fire(otherRoot);assert(#created==objectsBeforeContact,"seated avatar ignored");hum.SeatPart=nil
root.Touched:Fire(otherRoot)
local contactAttachment,contactSpin,contactUpright=created[#created-2],created[#created-1],created[#created]
assert(contactSpin.ClassName=="AngularVelocity" and contactSpin.AngularVelocity.Y==600 and contactUpright.ClassName=="AlignOrientation"
    and contactUpright.PrimaryAxis.Y==1 and hum.AutoRotate==false and not otherRoot.lastImpulse,"unowned contact creates stabilized spin")
mockTime=0.21;heartbeat:Fire();assert(contactSpin.AngularVelocity.Y==0,"contact pulse turns off")
mockTime=0.31;heartbeat:Fire();assert(contactSpin.AngularVelocity.Y==600,"contact pulse turns back on")
mockTime=0.61;root.AssemblyAngularVelocity=Vector3.new(3,600,4);heartbeat:Fire()
assert(contactAttachment.destroyed and contactSpin.destroyed and contactUpright.destroyed and hum.AutoRotate==true
    and root.AssemblyAngularVelocity.Y==0 and root.AssemblyAngularVelocity.X==3,"contact spin and stabilizer are cleaned up")
_G.isnetworkowner=function(target) return target==otherRoot end
mockTime=1.1;local count=#created;root.Touched:Fire(otherRoot)
assert(otherRoot.lastImpulse and otherRoot.lastImpulse.X==800 and otherRoot.lastImpulse.Y==200
    and #created==count,"owned target receives directional impulse without local spin")
otherRoot.lastImpulse=nil;root.Touched:Fire(otherRoot);assert(not otherRoot.lastImpulse,"owned impulses respect cooldown")
_G.isnetworkowner=function() return false end
mockTime=2.2;root.Touched:Fire(otherRoot);assert(not otherRoot.lastImpulse and #created==count+3,"unowned target gets fallback spin")
contactSpin,contactUpright=created[#created-1],created[#created];contact.Activated:Fire()
assert(contactSpin.destroyed and contactUpright.destroyed and hum.AutoRotate==true,"toggle stops contact spin")
_G.isnetworkowner=function() error("ownership check failed") end
contact.Activated:Fire();mockTime=3.3;root.Touched:Fire(otherRoot)
assert(not otherRoot.lastImpulse and created[#created-1].ClassName=="AngularVelocity","failed ownership check falls back to local spin")
contactSpin=created[#created-1];contact.Activated:Fire();assert(contactSpin.destroyed)
_G.isnetworkowner=nil
mockTime=4.4;count=#created;root.Touched:Fire(otherRoot);assert(#created==count,"disabled contact unsubscribes")
hum.State=Enum.HumanoidStateType.Freefall;hum.FloorMaterial=Enum.Material.Air;root.AssemblyLinearVelocity={Y=-20}
heartbeat:Fire()
local attachment,force=created[#created-1],created[#created]
assert(attachment.ClassName=="Attachment" and force.ClassName=="VectorForce" and force.Parent==root and force.Attachment0==attachment)
assert(force.RelativeTo==Enum.ActuatorRelativeTo.World and force.ApplyAtCenterOfMass and force.Force.Y==1300,"force uses current mass and gravity")
sliders.MovementfallPercent.set(50,true);assert(force.Force.Y==1000)
root.AssemblyLinearVelocity={Y=-100};heartbeat:Fire()
assert(force.Force.Y>1000 and force.Force.Y<=6000,"fast falls get bounded extra damping")
root.AssemblyLinearVelocity={Y=10};heartbeat:Fire();assert(force.destroyed and attachment.destroyed,"no lift while rising")
root.AssemblyLinearVelocity={Y=-20};heartbeat:Fire();force=created[#created]
hum.SeatPart={};heartbeat:Fire();assert(force.destroyed,"no lift while seated");hum.SeatPart=nil
uiState.freeCamera=true;hum.WalkSpeed=0;heartbeat:Fire();assert(hum.WalkSpeed==0,"free camera owns movement")
uiState.freeCamera=false;hum.WalkSpeed=65;heartbeat:Fire();assert(hum.WalkSpeed==65)
local oldHum,oldRoot=hum,root;char,hum,root=character();player.Character=char;playersByCharacter[char]=player;heartbeat:Fire()
assert(oldHum.WalkSpeed==16 and oldHum.JumpPower==50 and hum.WalkSpeed==65 and hum.JumpPower==80,"respawn restores old and applies to new")
hum.State=Enum.HumanoidStateType.Freefall;hum.FloorMaterial=Enum.Material.Air;root.AssemblyLinearVelocity={Y=-20};heartbeat:Fire();force=created[#created]
fall.Activated:Fire();assert(force.destroyed,"fall toggle immediately destroys force")
speed.Activated:Fire();assert(hum.WalkSpeed==16 and hum.JumpPower==80,"speed toggle only restores its property")
jump.Activated:Fire();assert(hum.JumpPower==50,"jump toggle restores its property")
speed.Activated:Fire();jump.Activated:Fire();fall.Activated:Fire();force=created[#created]
assert(hum.WalkSpeed==65 and hum.JumpPower==80 and force.Parent==root)
contact.Activated:Fire();local oldCreated=#created
oldRoot.Touched:Fire(otherRoot);assert(#created==oldCreated,"old character has no active contact listener")
mockTime=5;root.Touched:Fire(otherRoot)
local oldContactSpin,oldContactUpright=created[#created-1],created[#created]
assert(oldContactSpin.ClassName=="AngularVelocity" and oldContactSpin.Parent==root,"contact works after respawn")
-- Continuous mode replaces the transient spin without stacking actuators.
always.Activated:Fire();local alwaysSpin,alwaysUpright=created[#created-1],created[#created]
assert(oldContactSpin.destroyed and oldContactUpright.destroyed and alwaysSpin.ClassName=="AngularVelocity" and alwaysSpin.Parent==root)
assert(alwaysSpin.AngularVelocity.Y==600 and alwaysUpright.PrimaryAxis.Y==1 and hum.AutoRotate==false,"continuous mode uses a faster upright spin")
mockTime=5.21;heartbeat:Fire();assert(alwaysSpin.AngularVelocity.Y==0,"always pulse turns off")
mockTime=5.31;heartbeat:Fire();assert(alwaysSpin.AngularVelocity.Y==600,"always pulse turns on")
local countBeforeSpinTouch=#created;mockTime=10;root.Touched:Fire(otherRoot);heartbeat:Fire()
assert(#created==countBeforeSpinTouch and not alwaysSpin.destroyed,"continuous mode ignores touch-triggered duplicates")
contact.Activated:Fire();assert(not alwaysSpin.destroyed,"continuous mode independent of touch toggle")
root.AssemblyAngularVelocity=Vector3.new(0,600,0)
always.Activated:Fire();assert(alwaysSpin.destroyed and alwaysUpright.destroyed and hum.AutoRotate==true and root.AssemblyAngularVelocity.Y==0,"turning off stops continuous spin immediately")
-- Free camera and seating release the stabilizer and restore AutoRotate.
always.Activated:Fire();alwaysSpin,alwaysUpright=created[#created-1],created[#created]
uiState.freeCamera=true;heartbeat:Fire();assert(alwaysSpin.destroyed and alwaysUpright.destroyed and hum.AutoRotate==true)
uiState.freeCamera=false;heartbeat:Fire();alwaysSpin,alwaysUpright=created[#created-1],created[#created]
hum.SeatPart={};heartbeat:Fire();assert(alwaysSpin.destroyed and alwaysUpright.destroyed and hum.AutoRotate==true)
hum.SeatPart=nil;heartbeat:Fire();alwaysSpin,alwaysUpright=created[#created-1],created[#created]
local previousHum=hum;char,hum,root=character();player.Character=char;playersByCharacter[char]=player;heartbeat:Fire()
assert(alwaysSpin.destroyed and alwaysUpright.destroyed and previousHum.AutoRotate==true and hum.AutoRotate==false,"respawn cleans up old spin")
alwaysSpin,alwaysUpright=created[#created-1],created[#created]
-- Respect a different AutoRotate value written by the game while spinning.
hum.AutoRotate=true;always.Activated:Fire();assert(hum.AutoRotate==true and alwaysUpright.destroyed)
-- Unsupported stabilizer must roll back both partial objects and AutoRotate.
failClass="AlignOrientation";always.Activated:Fire()
local failedAttachment,failedActuator=created[#created-1],created[#created]
assert(failedAttachment.destroyed and failedActuator.destroyed and hum.AutoRotate==true,"failed setup rolls back")
failClass=nil;mockTime=12;heartbeat:Fire();alwaysSpin,alwaysUpright=created[#created-1],created[#created]
assert(alwaysSpin.Parent==root and alwaysUpright.Parent==root and hum.AutoRotate==false,"spin retries after unsupported setup")
root.AssemblyAngularVelocity=Vector3.new(0,600,0)
gui.Destroying:Fire()
assert(alwaysSpin.destroyed and alwaysUpright.destroyed and hum.AutoRotate==true and root.AssemblyAngularVelocity.Y==0,"closing hub clears continuous spin")
assert(hum.WalkSpeed==16 and hum.JumpPower==50,"closing hub restores movement even after shared connections disconnect")
heartbeat:Fire();assert(hum.WalkSpeed==16)
os.clock=savedClock
io.write("PASS: movement UI, sliders, character physics, respawn and shutdown integration\n")
