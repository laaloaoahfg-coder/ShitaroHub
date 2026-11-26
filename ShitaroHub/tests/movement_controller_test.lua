local create=assert(loadfile("core/movement_controller.lua"))()
local hum={Parent={},Health=100,WalkSpeed=16,JumpPower=50,JumpHeight=7.2,UseJumpPower=true}
local root={Parent={}}
local currentH,currentR=hum,root
local suspended=false
local falling=false
local force,clears,gravity=nil,0,200
local a={
    resolve=function() return currentH,currentR end,
    suspended=function() return suspended end,
    gravity=function() return gravity end,
    shouldSlowFall=function(h,r) assert(h==currentH and r==currentR);return falling end,
    clearFall=function() force=nil;clears=clears+1 end,
    applyFall=function(r,value) force={root=r,percent=value} end,
}
local c=create(a)
c.step();assert(hum.WalkSpeed==16 and hum.JumpPower==50 and not force,"disabled by default")
assert(c.setValue("speed",45));c.setEnabled("speed",true);assert(hum.WalkSpeed==45)
c.setValue("speed",70);c.step();assert(hum.WalkSpeed==70,"speed slider applies")
-- The last game-provided value is restored, not a hard-coded default.
hum.WalkSpeed=22;c.step();assert(hum.WalkSpeed==70)
c.setEnabled("speed",false);assert(hum.WalkSpeed==22,"restore latest external speed")
-- An external change made after our last update is not overwritten by Stop.
c.setEnabled("speed",true);hum.WalkSpeed=11;c.setEnabled("speed",false);assert(hum.WalkSpeed==11)
c.setEnabled("jump",true);assert(hum.JumpPower==70)
c.setValue("jumpPower",100);c.step();assert(hum.JumpPower==100)
hum.UseJumpPower=false;c.step()
assert(hum.JumpPower==50 and math.abs(hum.JumpHeight-25)<1e-5,"honor jump mode and restore previous field")
gravity=100;c.step();assert(math.abs(hum.JumpHeight-50)<1e-5,"height reflects current gravity")
c.setEnabled("jump",false);assert(hum.JumpHeight==7.2)
c.setEnabled("fall",true);assert(not force,"ground does not apply fall force")
falling=true;c.step();assert(force and force.root==root and force.percent==0.35)
c.setValue("fallPercent",10);c.step();assert(force.percent==0.1)
suspended=true;c.step();assert(not force,"free camera suspends fall")
suspended=false;c.step();assert(force)
c.setEnabled("speed",true);c.setEnabled("jump",true)
local old=hum;local oldRoot=root
hum={Parent={},WalkSpeed=18,JumpPower=45,JumpHeight=6,UseJumpPower=true};root={Parent={}}
currentH,currentR=hum,root;c.step()
assert(old.WalkSpeed==11 and old.JumpHeight==7.2,"old humanoid restored on respawn")
assert(hum.WalkSpeed==70 and hum.JumpPower==100 and force.root==root,"enabled settings follow respawn")
falling=false;c.step();assert(not force)
-- Free-camera ownership must not be replaced by movement.
suspended=true;hum.WalkSpeed=0;c.step();assert(hum.WalkSpeed==0)
suspended=false;hum.WalkSpeed=70;c.step();assert(hum.WalkSpeed==70)
c.shutdown();assert(hum.WalkSpeed==18 and hum.JumpPower==45 and not force,"shutdown restores and clears force")
c.step();assert(hum.WalkSpeed==18,"shutdown is final")
assert(not c.setValue("speed",0/0) and not c.setValue("x",1) and not c.setEnabled("x",true))
local d=create(a);d.setValue("speed",10000);assert(d.speed==120);d.setValue("fallPercent",-100);assert(d.fallPercent==10)
d.shutdown()
io.write("PASS: movement settings, external changes, jump modes, slow fall, free camera, respawn and shutdown\n")
