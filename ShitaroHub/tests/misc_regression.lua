-- Execute the actual misc.lua using the project's existing API/math mocks.
-- This checks state/control logic, NOT Roblox physics or server replication.
local file = assert(io.open("tests/aim_regression.lua", "r"))
local source = file:read("*a"); file:close()
local start = assert(source:find("local tests={}", 1, true))
local prelude = source:sub(1, start - 1)
local M = assert(load(prelude .. [[
return {fixture=fixture, obj=obj, signal=signal, v3=v3, bodyPart=bodyPart}
]], "@misc_mock_prelude"))()
local v3, obj, signal = M.v3, M.obj, M.signal
local oldAngles = CFrame.Angles
CFrame.Angles = function(x,y,z)
    if y ~= 0 then
        assert(x==0 and z==0)
        return CFrame.lookAt(v3(), v3(-math.sin(y),0,-math.cos(y)))
    end
    return oldAngles(x,y,z)
end
Enum.TextYAlignment = {Top="Top"}
Enum.Material = {Air="Air",Concrete="Concrete"}
for _,name in ipairs({"Jumping","Freefall","Landed","RunningNoPhysics","Seated","Swimming","Climbing"}) do
    Enum.HumanoidStateType[name] = name
end
local entry = assert(loadfile("modules/misc.lua"))()
local function fixture(fallback)
    local f=M.fixture()
    f.me.CharacterAdded=signal();f.me.CharacterRemoving=signal()
    f.world.Gravity=196.2
    f.run.Stepped=signal()
    if not fallback then f.run.PreSimulation=signal() end
    f.ctx.tabs={}
    for i=1,6 do f.ctx.tabs[i]={page=obj("Frame","Tab"..i)} end
    f.ctx.pageScroll=function(page,name)
        local scroll=obj("ScrollingFrame",name,page)
        f.miscPage=page
        return scroll
    end
    f.jumpAllowed=true;f.jumps=0
    local function configure(char,power,auto)
        local root=char.PrimaryPart
        root.Anchored=false;root.AssemblyLinearVelocity=v3(2,0,3)
        local hum=char:FindFirstChildOfClass("Humanoid")
        hum.AutoRotate=auto;hum.UseJumpPower=true;hum.JumpPower=power;hum.JumpHeight=7.2
        hum.FloorMaterial="Concrete";hum.Sit=false;hum.PlatformStand=false
        function hum:GetStateEnabled(state) assert(state=="Jumping");return f.jumpAllowed end
        function hum:ChangeState(state)
            if f.jumpError then error("simulated jump request error") end
            assert(state=="Jumping")
            self.state=state;f.jumps=f.jumps+1
        end
        f.hum=hum;f.root=root
    end
    configure(f.me.Character,55,true)
    function f:physics(dt)
        if self.run.PreSimulation then self.run.PreSimulation:fire(dt or 1/60)
        else self.run.Stepped:fire(12345,dt or 1/60) end
    end
    function f:respawn(rig,power,auto)
        local old=self.me.Character
        self.me.CharacterRemoving:fire(old)
        local char=obj("Model","respawn_"..rig,self.world)
        char.PrimaryPart=M.bodyPart(char,"HumanoidRootPart",v3(10,3,-20))
        M.bodyPart(char,"Head",v3(10,5,-20))
        local hum=obj("Humanoid","Humanoid",char);hum.Health=100;hum.RigType=rig
        hum.RootPart=char.PrimaryPart
        self.me.Character=char
        configure(char,power,auto)
        self.me.CharacterAdded:fire(char)
    end
    entry(f.ctx)
    return f
end
local function near(a,b,eps) assert(math.abs(a-b)<(eps or 1e-8),tostring(a).." ~= "..tostring(b)) end
local function sameVector(a,b) assert((a-b).Magnitude<1e-8) end
local function yaw(root)
    local look=root.CFrame.LookVector
    return math.atan(-look.X,-look.Z)
end
local tests={}
local function test(name,fn) tests[#tests+1]={name,fn} end

test("misc tab receives working controls with correct defaults",function()
    local f=fixture()
    assert(f.miscPage==f.ctx.tabs[4].page)
    local speed=f.sliders.MiscSpinSpeed
    assert(speed.min==30 and speed.max==1440 and speed.value==360)
    local power=f.sliders.MiscJumpPower
    assert(power.min==10 and power.max==150 and power.value==50)
    local before=f.root.CFrame
    f:physics();assert(f.root.CFrame==before and f.jumps==0)
    assert(f.hum.AutoRotate and f.hum.JumpPower==55)
    assert(f.ctx.locale.ru['misc.bhop']=='банихоп')
    assert(f.ctx.locale.en['misc.bhop']=='bunny hop')
end)
test("spin rotates the character, not camera, preserving position and velocity",function()
    local f=fixture();local pos=f.root.Position;local velocity=f.root.AssemblyLinearVelocity
    local camera=f.world.CurrentCamera.CFrame
    f:click('misc.spin');f:physics()
    near(yaw(f.root),math.rad(6));assert(not f.hum.AutoRotate)
    sameVector(pos,f.root.Position);sameVector(velocity,f.root.AssemblyLinearVelocity)
    assert(f.world.CurrentCamera.CFrame==camera)
end)
test("spin reverses direction after 1.5 seconds",function()
    local f=fixture();f.sliders.MiscSpinSpeed.set(60);f:click('misc.spin')
    for _=1,14 do f:physics(0.1) end
    local before=f.root.CFrame.LookVector
    f:physics(0.1);near(yaw(f.root),math.rad(90))
    f:physics(0.1);sameVector(f.root.CFrame.LookVector,before)
end)
test("spin is time-based at 30, 60 and 144 FPS",function()
    local looks={}
    for _,fps in ipairs({30,60,144}) do
        local f=fixture();f.sliders.MiscSpinSpeed.set(90);f:click('misc.spin')
        for _=1,fps do f:physics(1/fps) end
        looks[#looks+1]=f.root.CFrame.LookVector
    end
    sameVector(looks[1],looks[2]);sameVector(looks[2],looks[3])
end)
test("spin speed slider takes effect without restarting",function()
    local f=fixture();f.sliders.MiscSpinSpeed.set(60);f:click('misc.spin');f:physics(0.1)
    f.sliders.MiscSpinSpeed.set(120);f:physics(0.1)
    near(yaw(f.root),math.rad(18))
end)
test("spin toggle immediately restores AutoRotate",function()
    local f=fixture();f:click('misc.spin');f:physics();assert(not f.hum.AutoRotate)
    f:click('misc.spin');assert(f.hum.AutoRotate)
    local before=f.root.CFrame;f:physics();assert(f.root.CFrame==before)
end)
test("original false AutoRotate and newer game writes are preserved",function()
    local f=fixture();f.hum.AutoRotate=false
    f:click('misc.spin');f:physics();f:click('misc.spin');assert(f.hum.AutoRotate==false)
    f:click('misc.spin');f:physics();f.hum.AutoRotate=true
    f:click('misc.spin');assert(f.hum.AutoRotate==true)
end)
test("anchored characters pause spin and recover after unanchoring",function()
    local f=fixture();f:click('misc.spin');f:physics()
    f.root.Anchored=true;local before=f.root.CFrame
    f:physics();assert(f.root.CFrame==before and f.hum.AutoRotate)
    f.root.Anchored=false;f:physics();assert(not f.hum.AutoRotate)
end)
test("bhop requests a normal jump with configured power",function()
    local f=fixture();local velocity=f.root.AssemblyLinearVelocity
    f:click('misc.bhop');f:physics()
    assert(f.jumps==1 and f.hum.state=='Jumping' and f.hum.JumpPower==50)
    sameVector(velocity,f.root.AssemblyLinearVelocity)
end)
test("bhop does not jump in the air and repeats after landing",function()
    local f=fixture();f:click('misc.bhop');f:physics()
    f.hum.FloorMaterial='Air';f.hum.state='Freefall'
    for _=1,10 do f:physics(0.1) end
    assert(f.jumps==1)
    f.hum.FloorMaterial='Concrete';f.hum.state='Landed';f:physics()
    assert(f.jumps==2)
end)
test("jumping state or missing floor cannot produce another jump",function()
    local f=fixture();f:click('misc.bhop')
    f.hum.FloorMaterial='Air';f:physics();assert(f.jumps==0)
    f.hum.FloorMaterial='Concrete';f.hum.state='Jumping';f:physics();assert(f.jumps==0)
end)
test("jump cooldown prevents repeated requests on a stale grounded state",function()
    local f=fixture();f:click('misc.bhop');f:physics()
    f.hum.state='Running';f:physics(0.01);assert(f.jumps==1)
    f:physics(0.1);assert(f.jumps==1)
    f:physics(0.05);assert(f.jumps==2)
end)
test("jump power slider updates live and restores original on disable",function()
    local f=fixture();f:click('misc.bhop');f:physics()
    f.sliders.MiscJumpPower.set(150);f:physics();assert(f.hum.JumpPower==150)
    f:click('misc.bhop');assert(f.hum.JumpPower==55)
end)
test("JumpHeight mode uses equivalent launch power and restores height",function()
    local f=fixture();f.hum.UseJumpPower=false;f:click('misc.bhop');f:physics()
    near(f.hum.JumpHeight,2500/(2*196.2));assert(f.hum.JumpPower==55)
    f:click('misc.bhop');near(f.hum.JumpHeight,7.2)
end)
test("JumpHeight follows gravity changes",function()
    local f=fixture();f.hum.UseJumpPower=false;f.world.Gravity=100
    f:click('misc.bhop');f:physics();near(f.hum.JumpHeight,12.5)
    f.world.Gravity=200;f:physics();near(f.hum.JumpHeight,6.25)
end)
test("invalid or zero gravity pauses height-mode hopping",function()
    local f=fixture();f.hum.UseJumpPower=false;f:click('misc.bhop');f:physics()
    f.world.Gravity=0;f.hum.state='Running';f:physics();near(f.hum.JumpHeight,7.2)
    local jumps=f.jumps
    f.world.Gravity=0/0;f:physics();assert(f.jumps==jumps)
end)
test("changing jump mode releases the previously owned property",function()
    local f=fixture();f:click('misc.bhop');f:physics()
    f.hum.UseJumpPower=false;f:physics();assert(f.hum.JumpPower==55)
    near(f.hum.JumpHeight,2500/(2*196.2))
    f.hum.UseJumpPower=true;f:physics();near(f.hum.JumpHeight,7.2)
    assert(f.hum.JumpPower==50)
    f:click('misc.bhop');assert(f.hum.JumpPower==55)
end)
test("game jump-power changes during bhop become the restoration value",function()
    local f=fixture();f:click('misc.bhop');f:physics()
    f.hum.JumpPower=100;f:physics();assert(f.hum.JumpPower==50)
    f:click('misc.bhop');assert(f.hum.JumpPower==100)
end)
test("disable does not overwrite a newer external jump-power value",function()
    local f=fixture();f:click('misc.bhop');f:physics()
    f.hum.JumpPower=88;f:click('misc.bhop');assert(f.hum.JumpPower==88)
end)
test("disabled Jumping state is respected",function()
    local f=fixture();f.jumpAllowed=false;f:click('misc.bhop');f:physics()
    assert(f.jumps==0)
end)
test("death and seated/swimming/climbing/ragdoll states suspend both features",function()
    for _,state in ipairs({'Dead','Seated','Swimming','Climbing','Physics','Ragdoll'}) do
        local f=fixture();f:click('misc.spin');f:click('misc.bhop');f:physics()
        f.hum.state=state;local before=f.root.CFrame;local jumps=f.jumps
        f:physics();assert(f.root.CFrame==before and f.jumps==jumps)
        assert(f.hum.AutoRotate and f.hum.JumpPower==55,state)
    end
end)
test("zero health, explicit death flags and platform stand suspend movement",function()
    for _,kind in ipairs({'health','flag','platform'}) do
        local f=fixture();f:click('misc.spin');f:click('misc.bhop')
        if kind=='health' then f.hum.Health=0 elseif kind=='flag' then f.me.Character.attrs.Dead=true
        else f.hum.PlatformStand=true end
        local before=f.root.CFrame;f:physics()
        assert(f.root.CFrame==before and f.jumps==0 and f.hum.JumpPower==55)
    end
end)
test("freecam pauses both features and leaving freecam resumes them",function()
    local f=fixture();f:click('misc.spin');f:click('misc.bhop');f:physics()
    f.ctx.uiState.freeCamera=true;local before=f.root.CFrame;local jumps=f.jumps
    f:physics();assert(f.root.CFrame==before and f.jumps==jumps)
    assert(f.hum.AutoRotate and f.hum.JumpPower==55)
    f.ctx.uiState.freeCamera=false;f.hum.state='Running';f:physics()
    assert(not f.hum.AutoRotate and f.hum.JumpPower==50 and f.jumps==jumps+1)
end)
test("respawn restores old properties and configures new R6/R15 characters",function()
    local f=fixture();f:click('misc.spin');f:click('misc.bhop');f:physics()
    for _,rig in ipairs({'R6','R15'}) do
        local old=f.hum
        f:respawn(rig,67,false)
        assert(old.AutoRotate==(rig=='R6'))
        assert(old.JumpPower==(rig=='R6' and 55 or 67))
        f:physics();assert(f.hum.JumpPower==50 and not f.hum.AutoRotate)
    end
    f:click('misc.spin');f:click('misc.bhop')
    assert(f.hum.AutoRotate==false and f.hum.JumpPower==67)
end)
test("root replacement releases old spin ownership and uses the new root",function()
    local f=fixture();f:click('misc.spin');f:physics()
    f.root.Parent=nil
    f.root=M.bodyPart(f.me.Character,'HumanoidRootPart',v3(5,3,7))
    f.root.Anchored=false
    f:physics();assert(not f.hum.AutoRotate)
    sameVector(f.root.Position,v3(5,3,7))
end)
test("shutdown restores properties and disconnects the physics callback",function()
    local f=fixture();f:click('misc.spin');f:click('misc.bhop');f:physics()
    f.gui:Destroy();assert(f.hum.AutoRotate and f.hum.JumpPower==55)
    local before=f.root.CFrame;local jumps=f.jumps
    f:physics();assert(f.root.CFrame==before and f.jumps==jumps)
end)
test("Stepped fallback uses delta-time, not the first time parameter",function()
    local f=fixture(true);f:click('misc.spin');f:physics(1/60)
    near(yaw(f.root),math.rad(6))
    f.gui:Destroy();local before=f.root.CFrame;f:physics();assert(f.root.CFrame==before)
end)
test("closed shared UI restores owned movement properties",function()
    local f=fixture();f:click('misc.spin');f:click('misc.bhop');f:physics()
    f.ctx.uiState.closed=true;f:physics()
    assert(f.hum.AutoRotate and f.hum.JumpPower==55)
end)
test("a jump-request failure disables only bhop, leaving spin running",function()
    local f=fixture();f.jumpError=true;f:click('misc.spin');f:click('misc.bhop');f:physics()
    assert(f.hum.JumpPower==55 and not f.hum.AutoRotate)
    local before=f.root.CFrame.LookVector
    f:physics();assert((f.root.CFrame.LookVector-before).Magnitude>0.001)
end)

local passed=0
for _,t in ipairs(tests) do
    local ok,err=xpcall(t[2],debug.traceback)
    if not ok then error('FAIL '..t[1]..'\n'..err,0) end
    passed=passed+1;print('PASS: '..t[1])
end
print(string.format('RESULT: %d/%d mocked misc regression tests passed',passed,#tests))
