-- Runs the ACTUAL modules/aim.lua against a small Roblox API simulation.
-- Geometry uses Lua doubles. This is not an engine/executor integration test.
math.clamp = function(x, a, b) return math.max(a, math.min(b, x)) end
table.clear = function(t) for k in pairs(t) do t[k] = nil end end

local V = {}
V.__index = function(v, k)
    if k == "Magnitude" then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z) end
    if k == "Unit" then return v / v.Magnitude end
    return V[k]
end
Vector3 = {new = function(x,y,z) return setmetatable({X=x or 0,Y=y or 0,Z=z or 0},V) end}
local v3 = Vector3.new
V.__add = function(a,b) return v3(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
V.__sub = function(a,b) return v3(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
V.__unm = function(a) return v3(-a.X,-a.Y,-a.Z) end
V.__mul = function(a,b) if type(a)=="number" then a,b=b,a end return v3(a.X*b,a.Y*b,a.Z*b) end
V.__div = function(a,b) return v3(a.X/b,a.Y/b,a.Z/b) end
function V:Dot(b) return self.X*b.X+self.Y*b.Y+self.Z*b.Z end
function V:Cross(b) return v3(self.Y*b.Z-self.Z*b.Y,self.Z*b.X-self.X*b.Z,self.X*b.Y-self.Y*b.X) end
local CF = {}
CF.__index = function(c,k)
    if k=="LookVector" then return -c.b end
    if k=="RightVector" then return c.r end
    if k=="UpVector" then return c.u end
    return CF[k]
end
local function cf(p,r,u,b) return setmetatable({Position=p,r=r,u=u,b=b},CF) end
local function vector(c,v) return c.r*v.X+c.u*v.Y+c.b*v.Z end
CFrame = {}
function CFrame.new(x,y,z)
    return cf(type(x)=="table" and x or v3(x,y,z),v3(1,0,0),v3(0,1,0),v3(0,0,1))
end
function CFrame.lookAt(p,t)
    local look=(t-p).Unit
    local up=math.abs(look.Y)>0.99999 and v3(0,0,1) or v3(0,1,0)
    local right=look:Cross(up).Unit
    return cf(p,right,right:Cross(look).Unit,-look)
end
CF.__mul = function(a,b)
    if getmetatable(b)==V then return a.Position+vector(a,b) end
    return cf(a*b.Position,vector(a,b.r),vector(a,b.u),vector(a,b.b))
end
CF.__sub = function(a,b) return cf(a.Position-b,a.r,a.u,a.b) end
function CF:Inverse()
    local r=v3(self.r.X,self.u.X,self.b.X)
    local u=v3(self.r.Y,self.u.Y,self.b.Y)
    local b=v3(self.r.Z,self.u.Z,self.b.Z)
    local c=cf(v3(),r,u,b)
    c.Position=-vector(c,self.Position)
    return c
end
-- Nlerp is enough for the smoothing smoke check; no claim of matching
-- Roblox's rotation interpolation or numerical precision is made.
function CF:Lerp(other,k)
    local look=(self.LookVector*(1-k)+other.LookVector*k).Unit
    return CFrame.lookAt(self.Position*(1-k)+other.Position*k,self.Position*(1-k)+other.Position*k+look)
end
function CFrame.Angles(_,_,z)
    return cf(v3(),v3(math.cos(z),math.sin(z),0),v3(-math.sin(z),math.cos(z),0),v3(0,0,1))
end
Vector2 = {new=function(x,y) return v3(x,y,0) end}
UDim = {new=function(s,o) return {Scale=s,Offset=o} end}
UDim2 = {
 new=function(xs,xo,ys,yo) return {X=UDim.new(xs,xo),Y=UDim.new(ys,yo)} end,
 fromScale=function(x,y) return {X=UDim.new(x,0),Y=UDim.new(y,0)} end,
 fromOffset=function(x,y) return {X=UDim.new(0,x),Y=UDim.new(0,y)} end,
}
Color3 = {new=function(...) return {...} end,fromRGB=function(...) return {...} end}
Enum = {
 ScreenInsets={None="None"},ZIndexBehavior={Sibling="Sibling"},
 ApplyStrokeMode={Border="Border"},RaycastFilterType={Exclude="Exclude"},
 CameraType={Custom="Custom",Scriptable="Scriptable"},
 HumanoidStateType={Dead="Dead",Running="Running",Physics="Physics",Ragdoll="Ragdoll",PlatformStanding="PlatformStanding"},
 UserInputType={MouseButton1="MouseButton1"},RenderPriority={Last={Value=2000}},
 TextXAlignment={Center="Center"},
}
RaycastParams={new=function() return {} end}
local function signal()
    local s={links={}}
    function s:Connect(fn)
        local l={fn=fn,on=true}
        function l:Disconnect() self.on=false end
        table.insert(self.links,l)
        return l
    end
    function s:fire(...)
        for _,l in ipairs(self.links) do if l.on then l.fn(...) end end
    end
    return s
end
local O={}
O.__index=function(o,k)
    if k=="Position" and o.CFrame then return o.CFrame.Position end
    return O[k]
end
local function obj(class,name,parent)
    local o=setmetatable({ClassName=class,Name=name or class,Parent=parent,children={},attrs={},Activated=signal(),Destroying=signal()},O)
    if parent and parent.children then table.insert(parent.children,o) end
    return o
end
function O:IsA(c) return c==self.ClassName or (c=="BasePart" and self.ClassName=="Part") end
function O:GetChildren()
    local out={}
    for _,c in ipairs(self.children) do if c.Parent==self then table.insert(out,c) end end
    return out
end
function O:GetDescendants()
    local out={}
    for _,c in ipairs(self:GetChildren()) do
        table.insert(out,c)
        for _,d in ipairs(c:GetDescendants()) do table.insert(out,d) end
    end
    return out
end
function O:FindFirstChild(n)
    for _,c in ipairs(self.children) do if c.Parent==self and c.Name==n then return c end end
end
function O:FindFirstChildOfClass(n)
    for _,c in ipairs(self:GetChildren()) do if c:IsA(n) then return c end end
end
function O:FindFirstAncestorOfClass(n)
    local p=self.Parent
    while p do if p:IsA(n) then return p end p=p.Parent end
end
function O:IsDescendantOf(p)
    local q=self.Parent
    while q do if q==p then return true end q=q.Parent end
    return false
end
function O:GetAttribute(k) return self.attrs[k] end
function O:GetState() return self.state or "Running" end
function O:Destroy() self.Destroying:fire(); self.Parent=nil; self.destroyed=true end
local function bodyPart(char,name,pos)
    local p=obj("Part",name,char)
    p.CFrame=CFrame.new(pos);p.Size=v3(2,2,1);p.Transparency=0
    return p
end
local function camera()
    local c=obj("Camera","Camera")
    c.CFrame=CFrame.new();c.ViewportSize=v3(1920,1080,0);c.CameraType="Custom";c.FieldOfView=70
    function c:WorldToViewportPoint(p)
        local rel=self.CFrame:Inverse()*p
        local d=-rel.Z
        if d<=0 then return v3(-1,-1,d),false end
        local f=self.ViewportSize.Y/(2*math.tan(math.rad(self.FieldOfView)/2))
        local x=self.ViewportSize.X/2+rel.X*f/d
        local y=self.ViewportSize.Y/2-rel.Y*f/d
        return v3(x,y,d),x>=0 and y>=0 and x<=self.ViewportSize.X and y<=self.ViewportSize.Y
    end
    return c
end
local env={}
getgenv=function() return env end
local warnings={}
warn=function(msg) table.insert(warnings,tostring(msg)) end
local entry=assert(loadfile("modules/aim.lua"))()
local function fixture()
    warnings={}
    local f={rows={},objects={},sliders={},casts=0,pressed=true,rayTargets={}}
    local world=obj("Workspace","Workspace")
    world.DescendantAdded=signal();world.DescendantRemoving=signal();world.CurrentCamera=camera()
    function world:Raycast(from,dir,params)
        f.casts=f.casts+1
        table.insert(f.rayTargets,{from=from,to=from+dir,params=params.FilterDescendantsInstances})
        if f.cast then return f.cast(from,dir,params) end
    end
    local players=obj("Players","Players")
    players.PlayerAdded=signal();players.PlayerRemoving=signal()
    local me=obj("Player","ww",players);me.Team="blue"
    local own=obj("Model","ww",world)
    own.PrimaryPart=bodyPart(own,"HumanoidRootPart",v3())
    bodyPart(own,"Head",v3(0,2,0))
    local ownHum=obj("Humanoid","Humanoid",own);ownHum.Health=100;ownHum.RootPart=own.PrimaryPart
    me.Character=own;players.LocalPlayer=me
    function players:GetPlayers() return self:GetChildren() end
    function players:GetPlayerFromCharacter(char)
        for _,p in ipairs(self:GetPlayers()) do if p.Character==char then return p end end
    end
    local run={bound={}}
    function run:BindToRenderStep(name,priority,fn) self.bound[name]={fn=fn,priority=priority} end
    function run:UnbindFromRenderStep(name) self.bound[name]=nil end
    local input={IsMouseButtonPressed=function() return f.pressed end}
    local services={Workspace=world,Players=players,RunService=run,UserInputService=input}
    game={GetService=function(_,name) return assert(services[name],name) end}
    local pg=obj("PlayerGui","PlayerGui",me)
    local gui=obj("ScreenGui","Menu",pg)
    local ctx={locale={en={},ru={}},playerGui=pg,player=me,Players=players,RunService=run,gui=gui,
        colors={accent={},sub={}},uiState={},panelWidths={},panelGapBefore={},PANEL_RESERVE=370,
        previewScroll=obj("ScrollingFrame"),window={Size=UDim2.fromOffset(1000,600)}}
    ctx.connect=function(s,fn) return s:Connect(fn) end
    ctx.make=function(class,props,parent)
        local o=obj(class,props.Name,parent)
        for k,v in pairs(props) do o[k]=v end
        table.insert(f.objects,o)
        return o
    end
    ctx.corner=function() end
    ctx.animate=function(o,props) for k,v in pairs(props) do o[k]=v end end
    ctx.previewPanel=function() return obj("Frame"),obj("Frame") end
    ctx.previewRow=function(parent)
        local row=obj("Frame",nil,parent)
        local label=obj("TextLabel",nil,row)
        return row,label
    end
    ctx.localize=function(label,key) label.Parent.key=key;f.rows[key]=label.Parent end
    ctx.rowSlider=function(_,name,min,max,_,onChange)
        local slider={min=min,max=max}
        slider.set=function(value,notify)
            assert(value>=min and value<=max,"slider value out of bounds: "..name)
            slider.value=value
            if notify~=false then onChange(value) end
        end
        f.sliders[name]=slider
        return slider
    end
    ctx.layoutPreview=function() end
    function f:addTarget(name,point,rig)
        local owner=obj("Player",name,players);owner.Team="red"
        local char=obj("Model",name,world);owner.Character=char
        local root=bodyPart(char,"HumanoidRootPart",point-v3(0,2,0));char.PrimaryPart=root
        local hum=obj("Humanoid","Humanoid",char);hum.Health=100;hum.RootPart=root
        local head=bodyPart(char,"Head",point)
        local torso=bodyPart(char,rig=="R6" and "Torso" or "UpperTorso",point-v3(0,1.8,0))
        local left=bodyPart(char,rig=="R6" and "Left Leg" or "LeftUpperLeg",point+v3(-0.6,-4,0))
        local right=bodyPart(char,rig=="R6" and "Right Leg" or "RightUpperLeg",point+v3(0.6,-4,0))
        players.PlayerAdded:fire(owner)
        return {owner=owner,char=char,hum=hum,root=root,head=head,torso=torso,left=left,right=right}
    end
    function f:click(key)
        local row=assert(self.rows[key],"missing UI key "..key)
        for _,o in ipairs(row:GetChildren()) do if o.ClassName=="TextButton" then o.Activated:fire();return end end
        error("no button: "..key)
    end
    function f:tick(dt)
        local b=assert(run.bound.ShitaroAim,"render step not bound")
        b.fn(dt or 1/60)
    end
    function f:resetCamera() world.CurrentCamera.CFrame=CFrame.new() end
    function f:assertAim(point)
        local cam=world.CurrentCamera
        local p,on=cam:WorldToViewportPoint(point)
        local residual=math.sqrt((p.X-cam.ViewportSize.X/2)^2+(p.Y-cam.ViewportSize.Y/2)^2)
        assert(on and residual<1e-7,"screen error "..residual)
    end
    f.world=world;f.ctx=ctx;f.run=run;f.gui=gui;f.players=players;f.me=me
    entry(ctx)
    assert(#warnings==0,table.concat(warnings,"\n"))
    return f
end
local tests={}
local function test(name,fn) tests[#tests+1]={name,fn} end
local function active(point)
    local f=fixture()
    local t=f:addTarget("enemy",point or v3(20,2,-100))
    f:click("aim.enabled")
    return f,t
end

test("module starts and exposes enlarged controls",function()
    local f=fixture()
    assert(f.sliders.AimCircle.max==500 and f.sliders.AimCircle.value==240)
    assert(f.sliders.AimRange.max==800 and f.sliders.AimRange.value==800)
    assert(f.sliders.AimSmooth.min==0 and f.sliders.AimSmooth.value==0)
    assert(f.run.bound.ShitaroAim.priority==Enum.RenderPriority.Last.Value)
end)
test("500 circle acquires a target outside old 150 px limit",function()
    local f,t=active(v3(45,0,-100))
    f.sliders.AimCircle.set(500)
    f:tick();f:assertAim(t.head.Position)
end)
test("circle boundary still rejects outside targets",function()
    local f=active(v3(90,0,-100));f.sliders.AimCircle.set(150)
    local before=f.world.CurrentCamera.CFrame
    f:tick();assert(f.world.CurrentCamera.CFrame==before)
end)
test("exact moving-target aim within 800 metres with camera resets",function()
    local f,t=active(v3(50,3,-2550))
    f.sliders.AimRange.set(800)
    for i=1,120 do
        t.head.CFrame=CFrame.new(v3(50+i*0.2,3+math.sin(i/9)*2,-2550-i))
        f:resetCamera();f:tick(1/144);f:assertAim(t.head.Position)
    end
end)
test("head follows crouch, jump and prone at varied frame rates",function()
    local f,t=active()
    for _,pose in ipairs({{2,1/30},{-1,1/144},{8,1/60},{-2,1/20}}) do
        t.head.CFrame=CFrame.new(v3(20,pose[1],-100))*CFrame.Angles(0,0,math.pi/2)
        f:resetCamera();f:tick(pose[2]);f:assertAim(t.head.Position)
    end
end)
test("living prone/physics/platform-standing states remain targetable",function()
    local f,t=active()
    for _,state in ipairs({"Physics","Ragdoll","PlatformStanding"}) do
        t.hum.state=state;t.hum.PlatformStand=true
        f:resetCamera();f:tick();f:assertAim(t.head.Position)
    end
end)
test("dead state, death flags and zero HP are excluded",function()
    for _,kind in ipairs({"hp","state","charflag","humflag"}) do
        local f,t=active()
        if kind=="hp" then t.hum.Health=0 elseif kind=="state" then t.hum.state="Dead"
        elseif kind=="charflag" then t.char.attrs.Dead=true else t.hum.attrs.IsDead=true end
        local before=f.world.CurrentCamera.CFrame
        f:tick();assert(f.world.CurrentCamera.CFrame==before,kind)
    end
end)
test("reparented head is not used and replacement head is reacquired",function()
    local f,t=active();f:tick()
    t.head.Parent=obj("Model","oldhead")
    f:resetCamera();local before=f.world.CurrentCamera.CFrame
    f:tick();assert(f.world.CurrentCamera.CFrame==before)
    local newHead=bodyPart(t.char,"Head",v3(-12,4,-90))
    f:tick();f:assertAim(newHead.Position)
end)
test("R15 neck follows the live attachment, including rotation",function()
    local f,t=active();f:click("aim.part.neck")
    local a=obj("Attachment","NeckRigAttachment",t.head)
    a.WorldPosition=v3(20,1.2,-100)
    f:tick();f:assertAim(a.WorldPosition)
    a.WorldPosition=v3(21,-1,-103)
    f:tick();f:assertAim(a.WorldPosition)
end)
test("R6 neck uses the posed Motor6D head frame",function()
    local f=fixture();local t=f:addTarget("r6",v3(10,2,-100),"R6")
    local neck=obj("Motor6D","Neck",t.torso);neck.Part1=t.head;neck.C1=CFrame.new(0,-0.5,0)
    t.head.CFrame=t.head.CFrame*CFrame.Angles(0,0,math.pi/2)
    f:click("aim.enabled");f:click("aim.part.neck");f:tick()
    f:assertAim((t.head.CFrame*neck.C1).Position)
end)
test("body follows torso instead of a root-height estimate",function()
    local f,t=active();f:click("aim.part.body")
    t.torso.CFrame=CFrame.new(v3(19,-2,-102))
    f:tick();f:assertAim(t.torso.Position)
end)
test("legs aim at a real limb, not the gap, and keep that limb",function()
    local f,t=active();f:click("aim.part.legs");f:tick();f:assertAim(t.left.Position)
    t.left.CFrame=CFrame.new(v3(22,-3,-104));t.right.CFrame=CFrame.new(v3(12,-1,-100))
    f:tick();f:assertAim(t.left.Position)
    t.left.Parent=nil
    f:tick();f:assertAim(t.right.Position)
end)
test("lower-leg reference is refreshed after replacement",function()
    local f,t=active();t.left.Parent=nil;t.right.Parent=nil
    local old=bodyPart(t.char,"LeftLowerLeg",v3(20,-3,-100))
    f:click("aim.part.legs");f:tick();f:assertAim(old.Position)
    old.Parent=nil
    local new=bodyPart(t.char,"LeftLowerLeg",v3(17,-2,-101))
    f:tick();f:assertAim(new.Position)
end)
test("lock does not jump to a closer on-screen opponent",function()
    local f,t=active();f:tick()
    local other=f:addTarget("distractor",v3(0,0,-100))
    t.head.CFrame=CFrame.new(v3(27,2,-100))
    f:resetCamera();f:tick();f:assertAim(t.head.Position)
    t.hum.Health=0
    f:resetCamera();f:tick();f:assertAim(other.head.Position)
end)
test("visibility is checked against the new pose on each frame",function()
    local f,t=active();f:tick()
    local wall=obj("Part","Wall",f.world);wall.Transparency=0
    f.cast=function() return {Instance=wall} end
    t.head.CFrame=CFrame.new(v3(20,-1,-100))
    f:resetCamera();local before=f.world.CurrentCamera.CFrame
    f:tick();assert(f.world.CurrentCamera.CFrame==before)
    local last=f.rayTargets[#f.rayTargets]
    assert((last.to-t.head.Position).Magnitude<1e-9)
end)
test("visible fifth candidate is not lost behind four occluded ones",function()
    local f=fixture();local target
    local wall=obj("Part","Wall",f.world);wall.Transparency=0
    for i=1,5 do target=f:addTarget("enemy"..i,v3(i*2,0,-100)) end
    f.cast=function(_,_,params)
        if params.FilterDescendantsInstances[1]~=target.char then return {Instance=wall} end
    end
    f:click("aim.enabled");f:tick();f:assertAim(target.head.Position)
    assert(f.casts==5)
end)
test("visibility filter excludes camera descendants and local avatar",function()
    local f,t=active();f:tick()
    local filters=f.rayTargets[1].params
    assert(filters[1]==t.char and filters[2]==f.world.CurrentCamera and filters[3]==f.me.Character)
end)
test("only-while-shooting gate and freecam gate stop camera writes",function()
    local f,t=active();f:click("aim.shootOnly");f.pressed=false
    local before=f.world.CurrentCamera.CFrame
    f:tick();assert(f.world.CurrentCamera.CFrame==before)
    f.pressed=true;f:tick();f:assertAim(t.head.Position)
    f.ctx.uiState.freeCamera=true;f:resetCamera();before=f.world.CurrentCamera.CFrame
    f:tick();assert(f.world.CurrentCamera.CFrame==before)
end)
test("game-owned Scriptable cameras and camera replacement are supported",function()
    local f,t=active();f.world.CurrentCamera.CameraType="Scriptable";f:tick();f:assertAim(t.head.Position)
    f.world.CurrentCamera=camera();f:tick();f:assertAim(t.head.Position)
end)
test("range and teammate filters still apply",function()
    local f,t=active(v3(20,2,-2500))
    f.sliders.AimRange.set(400)
    local before=f.world.CurrentCamera.CFrame
    f:tick();assert(f.world.CurrentCamera.CFrame==before)
    f.sliders.AimRange.set(800);f:tick();f:assertAim(t.head.Position)
    f.ctx.uiState.isTeammate=function() return true end
    f:resetCamera();before=f.world.CurrentCamera.CFrame
    f:tick();assert(f.world.CurrentCamera.CFrame==before)
end)
test("smoothing remains optional and moves without an immediate snap",function()
    local f,t=active();f.sliders.AimSmooth.set(5)
    f:tick()
    local look=f.world.CurrentCamera.CFrame.LookVector
    local desired=t.head.Position.Unit
    assert(look.X>0 and look:Dot(desired)<1-1e-8)
    for _=1,120 do f:tick() end
    assert(f.world.CurrentCamera.CFrame.LookVector:Dot(desired)>0.999)
end)
test("viewport scaling matches the configured 1080p radius",function()
    local f,t=active();f.world.CurrentCamera.ViewportSize=v3(1280,720,0)
    f.sliders.AimCircle.set(500);f:tick();f:assertAim(t.head.Position)
    local ring=f.ctx.playerGui:FindFirstChild("ShitaroAim"):FindFirstChild("FovCircle")
    assert(math.abs(ring.Size.X.Offset-(2*500*720/1080))<1e-9)
end)
test("shutdown removes the callback, circle and owned diagnostics",function()
    local f=active();assert(type(env.shitaro_aim)=="function")
    local overlay=f.ctx.playerGui:FindFirstChild("ShitaroAim")
    f.gui:Destroy()
    assert(f.run.bound.ShitaroAim==nil and overlay.destroyed and env.shitaro_aim==nil)
end)

test("800 metre maximum rejects a target just beyond the limit",function()
    local f,t=active(v3(0,0,-799.9/0.28))
    f.sliders.AimRange.set(800)
    f:tick();f:assertAim(t.head.Position)
    t.head.CFrame=CFrame.new(v3(0,0,-800.1/0.28))
    f:resetCamera();local before=f.world.CurrentCamera.CFrame
    f:tick();assert(f.world.CurrentCamera.CFrame==before)
end)
test("500 radius acquires at 499 pixels but not at 501 pixels",function()
    local focal=1080/(2*math.tan(math.rad(70)/2))
    local f,t=active(v3(499*100/focal,0,-100))
    f.sliders.AimCircle.set(500)
    f:tick();f:assertAim(t.head.Position)
    t.head.CFrame=CFrame.new(v3(501*100/focal,0,-100))
    f:resetCamera();local before=f.world.CurrentCamera.CFrame
    f:tick();assert(f.world.CurrentCamera.CFrame==before)
end)

local passed=0
for _,t in ipairs(tests) do
    local ok,err=xpcall(t[2],debug.traceback)
    if not ok then error("FAIL "..t[1].."\n"..err,0) end
    passed=passed+1
    print("PASS: "..t[1])
end
print(string.format("RESULT: %d/%d mocked regression tests passed",passed,#tests))
