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
Vector3={new=function(x,y,z) return {X=x,Y=y,Z=z} end}
Color3={new=function(...) return {...} end}
Enum={HumanoidStateType={Freefall="Freefall",Running="Running"},Material={Air="Air",Ground="Ground"},ActuatorRelativeTo={World="World"}}
local world={Gravity=200}
game={GetService=function(_,n) assert(n=="Workspace");return world end}
local function character()
    local char={Parent={}}
    local hum={Parent=char,Health=100,WalkSpeed=16,JumpPower=50,JumpHeight=7.2,UseJumpPower=true,
        FloorMaterial=Enum.Material.Ground,State=Enum.HumanoidStateType.Running}
    function hum:GetState() return self.State end
    local root={Parent=char,AssemblyMass=10,AssemblyLinearVelocity={Y=0},Anchored=false}
    function root:IsA(k) return k=="BasePart" end
    function char:FindFirstChildOfClass(k) if k=="Humanoid" then return hum end end
    function char:FindFirstChild(k) if k=="HumanoidRootPart" then return root end end
    return char,hum,root
end
local char,hum,root=character();local player={Character=char}
local gui={Destroying=signal()};local heartbeat=signal();local links={}
gui.Destroying:Connect(function() for _,link in ipairs(links) do link:Disconnect() end end)
local sliders={}
local uiState={}
local ctx={player=player,gui=gui,uiState=uiState,RunService={Heartbeat=heartbeat},
    Loader={module=function(p) return assert(loadfile(p))() end},
    tabs={[4]={page={}}},panelWidths={},colors={sub={},accent={}},locale={en={},ru={}},
    make=new,corner=function() end,animate=function(obj,props) for k,v in pairs(props) do obj[k]=v end end,
    connect=function(event,fn) local link=event:Connect(fn);links[#links+1]=link;return link end,
    pageScroll=function(parent,name) return new("ScrollingFrame",{Name=name},parent) end,
    previewPanel=function(scroll,name) return new("Frame",{Name=name},scroll) end,
    previewRow=function(card,index) return new("Frame",{Name="Row"..index},card),new("TextLabel",{},card) end,
    localize=function() end,layoutPreview=function() end,
    rowSlider=function(row,name,min,max,format,onChange)
        local s={}
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
heartbeat:Fire();assert(hum.WalkSpeed==16 and hum.JumpPower==50 and #created==0,"starts disabled")
sliders.Movementspeed.set(65,true);speed.Activated:Fire();assert(hum.WalkSpeed==65)
sliders.MovementjumpPower.set(80,true);jump.Activated:Fire();assert(hum.JumpPower==80)
fall.Activated:Fire();assert(#created==0,"ground does not create a force")
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
local oldHum=hum;char,hum,root=character();player.Character=char;heartbeat:Fire()
assert(oldHum.WalkSpeed==16 and oldHum.JumpPower==50 and hum.WalkSpeed==65 and hum.JumpPower==80,"respawn restores old and applies to new")
hum.State=Enum.HumanoidStateType.Freefall;hum.FloorMaterial=Enum.Material.Air;root.AssemblyLinearVelocity={Y=-20};heartbeat:Fire();force=created[#created]
fall.Activated:Fire();assert(force.destroyed,"fall toggle immediately destroys force")
speed.Activated:Fire();assert(hum.WalkSpeed==16 and hum.JumpPower==80,"speed toggle only restores its property")
jump.Activated:Fire();assert(hum.JumpPower==50,"jump toggle restores its property")
speed.Activated:Fire();jump.Activated:Fire();fall.Activated:Fire();force=created[#created]
assert(hum.WalkSpeed==65 and hum.JumpPower==80 and force.Parent==root)
gui.Destroying:Fire()
assert(force.destroyed and hum.WalkSpeed==16 and hum.JumpPower==50,"closing hub restores movement even after shared connections disconnect")
heartbeat:Fire();assert(hum.WalkSpeed==16)
io.write("PASS: movement UI, sliders, character physics, respawn and shutdown integration\n")
