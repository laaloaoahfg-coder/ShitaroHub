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
Enum.KeyCode = {Space="Space"}
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
    f.space=false
    f.input={
        WindowFocusReleased=signal(),WindowFocused=signal(),
        IsKeyDown=function(_,key) assert(key=="Space");return f.space end,
        GetFocusedTextBox=function() return f.textBox end,
    }
    f.ctx.UserInputService=f.input
    local function configure(char,power,auto)
        local root=char.PrimaryPart
        root.Anchored=false;root.AssemblyLinearVelocity=v3(2,0,3)
        local hum=char:FindFirstChildOfClass("Humanoid")
        hum.AutoRotate=auto;hum.UseJumpPower=true;hum.JumpPower=power;hum.JumpHeight=7.2
        hum.FloorMaterial="Concrete";hum.Sit=false;hum.PlatformStand=false;hum.MoveDirection=v3(0,0,-1)
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
    local boost=f.sliders.MiscHopBoost
    assert(boost.min==0 and boost.max==50 and boost.value==8)
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
test("spin keeps one direction for 12 seconds through full-turn wraps",function()
    local f=fixture();f.sliders.MiscSpinSpeed.set(60);f:click('misc.spin')
    local previous=yaw(f.root)
    local total=0
    for _=1,720 do
        f:physics(1/60)
        local angle=yaw(f.root)
        local delta=(angle-previous+math.pi)%(2*math.pi)-math.pi
        assert(delta>0, 'spin reversed or stopped')
        near(delta,math.rad(1),1e-7)
        total=total+delta
        previous=angle
    end
    near(total,math.rad(720),1e-6)
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
local function enabled()
    local f=fixture()
    f.root.AssemblyLinearVelocity=v3(0,0,-20)
    f.hum.MoveDirection=v3(0,0,-1)
    f:click('misc.bhop');f:physics()
    return f
end
local function request(f)
    f.space=true;f:physics()
end
local function takeoff(f,y)
    f.hum.FloorMaterial='Air';f.hum.state='Jumping'
    local v=f.root.AssemblyLinearVelocity
    f.root.AssemblyLinearVelocity=v3(v.X,y or 50,v.Z)
    f:physics()
end
local function airTime(f)
    for _=1,20 do f:physics() end
end
local function land(f)
    f.hum.FloorMaterial='Concrete';f.hum.state='Landed'
    local v=f.root.AssemblyLinearVelocity
    f.root.AssemblyLinearVelocity=v3(v.X,0,v.Z)
    f:physics()
end

test('enabled bhop does not jump or accelerate without Space',function()
    local f=enabled();local v=f.root.AssemblyLinearVelocity
    for _=1,120 do f:physics() end
    assert(f.jumps==0);sameVector(v,f.root.AssemblyLinearVelocity)
end)
test('Space requests a normal jump without changing height properties',function()
    local f=enabled();request(f)
    assert(f.jumps==1 and f.hum.state=='Jumping')
    assert(f.hum.JumpPower==55 and f.hum.JumpHeight==7.2 and f.hum.UseJumpPower==true)
end)
test('no acceleration is applied until an actual upward takeoff',function()
    local f=enabled();request(f)
    sameVector(f.root.AssemblyLinearVelocity,v3(0,0,-20))
    for _=1,40 do f.hum.state='Running';f:physics() end
    sameVector(f.root.AssemblyLinearVelocity,v3(0,0,-20))
end)
test('confirmed takeoff adds horizontal boost and preserves vertical velocity',function()
    local f=enabled();request(f);takeoff(f,55)
    sameVector(f.root.AssemblyLinearVelocity,v3(0,55,-28))
end)
test('holding Space does not add more boost during the same flight',function()
    local f=enabled();request(f);takeoff(f);local v=f.root.AssemblyLinearVelocity
    for _=1,120 do f:physics() end
    sameVector(v,f.root.AssemblyLinearVelocity);assert(f.jumps==1)
end)
test('subsequent landing and takeoff add the next boost',function()
    local f=enabled();request(f);takeoff(f);airTime(f);land(f)
    assert(f.jumps==2);takeoff(f)
    sameVector(f.root.AssemblyLinearVelocity,v3(0,50,-36))
end)
test('releasing Space prevents repeated jumps after landing',function()
    local f=enabled();request(f);takeoff(f);airTime(f);f.space=false;land(f)
    assert(f.jumps==1)
    local v=f.root.AssemblyLinearVelocity
    for _=1,20 do f:physics() end
    sameVector(v,f.root.AssemblyLinearVelocity)
end)
test('releasing Space before takeoff prevents the pending boost',function()
    local f=enabled();request(f);f.space=false;takeoff(f)
    sameVector(f.root.AssemblyLinearVelocity,v3(0,50,-20))
end)
test('live acceleration slider affects the next takeoff',function()
    local f=enabled();f.sliders.MiscHopBoost.set(20);request(f);takeoff(f)
    sameVector(f.root.AssemblyLinearVelocity,v3(0,50,-40))
end)
test('zero boost retains Space-held normal hopping',function()
    local f=enabled();f.sliders.MiscHopBoost.set(0);request(f);takeoff(f)
    assert(f.jumps==1);sameVector(f.root.AssemblyLinearVelocity,v3(0,50,-20))
end)
test('stationary jumping does not invent a horizontal direction',function()
    local f=enabled();f.hum.MoveDirection=v3();request(f);takeoff(f)
    sameVector(f.root.AssemblyLinearVelocity,v3(0,50,-20))
end)
test('movement direction controls horizontal acceleration, not camera yaw',function()
    local f=enabled();f.hum.MoveDirection=v3(1,0,0);request(f);takeoff(f)
    sameVector(f.root.AssemblyLinearVelocity,v3(8,50,-20))
end)
test('planar speed is capped without changing the vertical impulse',function()
    local f=enabled();f.root.AssemblyLinearVelocity=v3(0,0,-118)
    f.sliders.MiscHopBoost.set(50);request(f);takeoff(f,61)
    sameVector(f.root.AssemblyLinearVelocity,v3(0,61,-120))
end)
test('external speed above the cap is not reduced',function()
    local f=enabled();f.root.AssemblyLinearVelocity=v3(0,0,-160)
    request(f);takeoff(f)
    sameVector(f.root.AssemblyLinearVelocity,v3(0,50,-160))
end)
test('normal JumpHeight mode remains entirely unchanged',function()
    local f=enabled();f.hum.UseJumpPower=false;f.hum.JumpHeight=9.5
    request(f);takeoff(f)
    assert(f.hum.JumpHeight==9.5 and f.hum.JumpPower==55 and not f.hum.UseJumpPower)
end)
test('game changes to jump settings are never overwritten',function()
    local f=enabled();f.hum.JumpPower=77;f.hum.JumpHeight=11
    request(f);takeoff(f);f:click('misc.bhop')
    assert(f.hum.JumpPower==77 and f.hum.JumpHeight==11)
end)
test('disabled Jumping state prevents jump and boost',function()
    local f=enabled();f.jumpAllowed=false;request(f);assert(f.jumps==0)
    takeoff(f);sameVector(f.root.AssemblyLinearVelocity,v3(0,50,-20))
end)
test('an active text box prevents automatic jump and boost',function()
    local f=enabled();f.textBox={};request(f);assert(f.jumps==0)
    takeoff(f);sameVector(f.root.AssemblyLinearVelocity,v3(0,50,-20))
end)
test('loss of focus stops bhop and focus return does not boost midair',function()
    local f=enabled();f.input.WindowFocusReleased:fire();request(f);assert(f.jumps==0)
    takeoff(f);sameVector(f.root.AssemblyLinearVelocity,v3(0,50,-20))
    f.input.WindowFocused:fire();f:physics()
    sameVector(f.root.AssemblyLinearVelocity,v3(0,50,-20))
end)
test('enabling bhop while airborne does not grant a boost',function()
    local f=fixture();f.space=true;f.hum.FloorMaterial='Air';f.hum.state='Jumping'
    f.root.AssemblyLinearVelocity=v3(0,50,-20)
    f:click('misc.bhop');f:physics();sameVector(f.root.AssemblyLinearVelocity,v3(0,50,-20))
end)
test('walking off a ledge while falling does not grant a boost',function()
    local f=enabled();f.space=true;f.hum.FloorMaterial='Air';f.hum.state='Freefall'
    f.root.AssemblyLinearVelocity=v3(0,-4,-20)
    f:physics();sameVector(f.root.AssemblyLinearVelocity,v3(0,-4,-20))
end)
test('repressing Space in midair cannot grant another boost',function()
    local f=enabled();request(f);takeoff(f)
    f.space=false;f:physics();f.space=true;f:physics()
    sameVector(f.root.AssemblyLinearVelocity,v3(0,50,-28))
end)
test('takeoff grace handles floor transition before vertical impulse',function()
    local f=enabled();request(f);takeoff(f,0)
    sameVector(f.root.AssemblyLinearVelocity,v3(0,0,-20))
    f.root.AssemblyLinearVelocity=v3(0,50,-20);f:physics()
    sameVector(f.root.AssemblyLinearVelocity,v3(0,50,-28))
end)
test('expired takeoff cannot apply a delayed boost',function()
    local f=enabled();request(f);takeoff(f,0)
    for _=1,20 do f:physics() end
    f.root.AssemblyLinearVelocity=v3(0,50,-20);f:physics()
    sameVector(f.root.AssemblyLinearVelocity,v3(0,50,-20))
end)
test('a normal Space jump started before our callback is recognised',function()
    local f=enabled();f.space=true
    takeoff(f)
    assert(f.jumps==0);sameVector(f.root.AssemblyLinearVelocity,v3(0,50,-28))
end)
test('freecam blocks hopping and acceleration, and resumption re-arms on ground',function()
    local f=enabled();f.ctx.uiState.freeCamera=true;request(f);assert(f.jumps==0)
    takeoff(f);sameVector(f.root.AssemblyLinearVelocity,v3(0,50,-20))
    f.ctx.uiState.freeCamera=false;f:physics()
    sameVector(f.root.AssemblyLinearVelocity,v3(0,50,-20))
    airTime(f);land(f);assert(f.jumps==1)
    takeoff(f);sameVector(f.root.AssemblyLinearVelocity,v3(0,50,-28))
end)
test('death, seating, swimming, climbing and ragdoll suspend movement',function()
    for _,state in ipairs({'Dead','Seated','Swimming','Climbing','Physics','Ragdoll'}) do
        local f=enabled();f:click('misc.spin');f:physics();f.hum.state=state;f.space=true
        local before=f.root.CFrame;f:physics()
        assert(f.root.CFrame==before and f.jumps==0 and f.hum.AutoRotate)
    end
end)
test('respawn preserves settings but does not change native jump properties',function()
    local f=enabled();f:click('misc.spin');f:physics();local old=f.hum
    f:respawn('R15',67,false)
    assert(old.AutoRotate and old.JumpPower==55)
    request(f);assert(f.hum.JumpPower==67 and not f.hum.AutoRotate)
    f:click('misc.spin');f:click('misc.bhop')
    assert(f.hum.JumpPower==67 and f.hum.AutoRotate==false)
end)
test('disabling bhop leaves current momentum to normal game physics',function()
    local f=enabled();request(f);takeoff(f);local velocity=f.root.AssemblyLinearVelocity
    f:click('misc.bhop');f:physics();sameVector(velocity,f.root.AssemblyLinearVelocity)
end)
test('shutdown restores spin and disconnects movement updates',function()
    local f=enabled();f:click('misc.spin');request(f);takeoff(f);f.gui:Destroy()
    assert(f.hum.AutoRotate and f.hum.JumpPower==55)
    local before=f.root.CFrame;local velocity=f.root.AssemblyLinearVelocity
    f:physics();assert(f.root.CFrame==before);sameVector(velocity,f.root.AssemblyLinearVelocity)
end)
test('Stepped fallback uses the delta-time parameter',function()
    local f=fixture(true);f:click('misc.spin');f:physics(1/60)
    near(yaw(f.root),math.rad(6))
end)
test('a jump request failure disables only bhop',function()
    local f=enabled();f.jumpError=true;f:click('misc.spin');request(f)
    assert(not f.hum.AutoRotate and f.hum.JumpPower==55)
    local before=f.root.CFrame.LookVector;f:physics()
    assert((f.root.CFrame.LookVector-before).Magnitude>0.001)
end)

local passed=0
for _,t in ipairs(tests) do
    local ok,err=xpcall(t[2],debug.traceback)
    if not ok then error('FAIL '..t[1]..'\n'..err,0) end
    passed=passed+1;print('PASS: '..t[1])
end
print(string.format('RESULT: %d/%d mocked misc regression tests passed',passed,#tests))
