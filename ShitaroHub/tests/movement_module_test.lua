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
local created={}
Instance={new=function(class) local o=new(class,{},nil);created[#created+1]=o;return o end}
UDim2={new=function(...) return {...} end,fromOffset=function(...) return {...} end,fromScale=function(...) return {...} end}
UDim={new=function(...) return {...} end}
Vector2={new=function(...) return {...} end}
local vector={}
vector.__index=function(v,k) if k=="Magnitude" then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z) end end
vector.__sub=function(a,b) return setmetatable({X=a.X-b.X,Y=a.Y-b.Y,Z=a.Z-b.Z},vector) end
Vector3={new=function(x,y,z) return setmetatable({X=x,Y=y,Z=z},vector) end}
Color3={new=function(...) return {...} end}
Enum={HumanoidStateType={Freefall="Freefall",Running="Running"},Material={Air="Air",Ground="Ground"},ActuatorRelativeTo={World="World"}}
local world={Gravity=200}
game={GetService=function(_,n) assert(n=="Workspace");return world end}
local function character()
    local char={Parent={},DescendantAdded=signal()}
    function char:IsA(k) return k=="Model" end
    local hum={Parent=char,Health=100,WalkSpeed=16,JumpPower=50,JumpHeight=7.2,UseJumpPower=true,
        FloorMaterial=Enum.Material.Ground,State=Enum.HumanoidStateType.Running}
    function hum:GetState() return self.State end
    local root={Parent=char,AssemblyMass=10,AssemblyLinearVelocity={Y=0},Anchored=false,
        AssemblyAngularVelocity=Vector3.new(0,0,0),Position=Vector3.new(0,0,0),Touched=signal()}
    function root:IsA(k) return k=="BasePart" end
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
heartbeat:Fire();assert(hum.WalkSpeed==16 and hum.JumpPower==50 and #created==0,"starts disabled")
assert(sliders.Movementspeed.max==200,"UI exposes 200 maximum")
sliders.Movementspeed.set(200,true);speed.Activated:Fire();assert(hum.WalkSpeed==200)
sliders.Movementspeed.set(65,true);assert(hum.WalkSpeed==65)
sliders.MovementjumpPower.set(80,true);jump.Activated:Fire();assert(hum.JumpPower==80)
fall.Activated:Fire();assert(#created==0,"ground does not create a force")
-- Only close, living other players trigger the local timed actuator.
local otherChar,otherHum,otherRoot=character();local otherPlayer={Character=otherChar};playersByCharacter[otherChar]=otherPlayer
otherRoot.Position=Vector3.new(2,0,0)
contact.Activated:Fire();local objectsBeforeContact=#created
root.Touched:Fire(root);assert(#created==objectsBeforeContact,"own character ignored")
otherRoot.Position=Vector3.new(30,0,0);root.Touched:Fire(otherRoot);assert(#created==objectsBeforeContact,"distant player ignored")
otherRoot.Position=Vector3.new(2,0,0);hum.SeatPart={};root.Touched:Fire(otherRoot);assert(#created==objectsBeforeContact,"seated avatar ignored");hum.SeatPart=nil
root.Touched:Fire(otherRoot)
local spinAttachment,spinForce=created[#created-1],created[#created]
assert(spinAttachment.ClassName=="Attachment" and spinForce.ClassName=="AngularVelocity" and spinForce.Parent==root)
assert(spinForce.MaxTorque==2000000 and spinForce.AngularVelocity.Y==80 and otherRoot.AssemblyAngularVelocity.Y==0,"only local character gets actuator")
root.AssemblyAngularVelocity=Vector3.new(3,80,4);mockTime=0.3;heartbeat:Fire()
assert(spinForce.destroyed and spinAttachment.destroyed and root.AssemblyAngularVelocity.Y==0 and root.AssemblyAngularVelocity.X==3,"spin clears and does not leave local avatar spinning")
root.Touched:Fire(otherRoot);assert(#created==objectsBeforeContact+2,"contact cooldown")
contact.Activated:Fire();mockTime=2;root.Touched:Fire(otherRoot);assert(#created==objectsBeforeContact+2,"disabled contact unsubscribes")
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
mockTime=4;root.Touched:Fire(otherRoot);local finalSpin=created[#created]
assert(finalSpin.ClassName=="AngularVelocity" and finalSpin.Parent==root)
root.AssemblyAngularVelocity=Vector3.new(0,80,0)
gui.Destroying:Fire()
assert(finalSpin.destroyed and root.AssemblyAngularVelocity.Y==0,"closing hub clears active contact spin")
assert(force.destroyed and hum.WalkSpeed==16 and hum.JumpPower==50,"closing hub restores movement even after shared connections disconnect")
heartbeat:Fire();assert(hum.WalkSpeed==16)
os.clock=savedClock
io.write("PASS: movement UI, sliders, character physics, respawn and shutdown integration\n")
