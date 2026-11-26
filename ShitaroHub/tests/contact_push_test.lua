local create=assert(loadfile("core/contact_push.lua"))()
local time=0;local suspended=false;local can=true;local watches,disconnects,starts,stops=0,0,0,0
local char,hum,root={},{},{}
local activeHandler,other={},{}
local currentSpin
local adapter={
    now=function() return time end,
    suspended=function() return suspended end,
    resolve=function() return char,hum,root end,
    canPush=function(h,r) return can and h==hum and r==root end,
    isOtherPlayerPart=function(part,r) return part==other and r==root end,
    watch=function(target,callback)
        assert(target==char);watches=watches+1;activeHandler=callback
        return function() disconnects=disconnects+1 end
    end,
    startSpin=function(r) assert(r==root);starts=starts+1;currentSpin={root=r,valid=true};return currentSpin end,
    spinValid=function(state) return state.valid end,
    stopSpin=function(state) assert(state.root);state.valid=false;stops=stops+1 end,
}
local c=create(adapter)
c.step();assert(watches==0 and starts==0,"disabled by default")
c.setEnabled(true);assert(watches==1)
activeHandler({});assert(starts==0,"non-player contact ignored")
activeHandler(other);assert(starts==1 and stops==0)
time=0.49;c.step();assert(stops==0);time=0.51;c.step();assert(stops==1,"stronger contact spin remains bounded")
activeHandler(other);assert(starts==1,"cooldown suppresses duplicates")
time=1.1;suspended=true;activeHandler(other);assert(starts==1)
suspended=false;can=false;activeHandler(other);assert(starts==1)
can=true;activeHandler(other);assert(starts==2)
suspended=true;c.step();assert(stops==2,"free camera stops an active spin")
suspended=false;time=2.2;activeHandler(other);assert(starts==3)
local oldCallback=activeHandler
char,hum,root={},{},{};c.step();assert(stops==3 and disconnects==1 and watches==2,"respawn releases old character")
oldCallback(other);assert(starts==3,"stale callback cannot act on a new character")
c.setEnabled(false);assert(stops==3 and disconnects==2,"disable removes listeners and actuator")
activeHandler(other);assert(starts==3,"old listener cannot act when disabled")
c.setEnabled(true);assert(watches==3)
time=3.3;activeHandler(other);assert(starts==4)
c.shutdown();assert(stops==4 and disconnects==3)
c.setEnabled(true);c.step();assert(watches==3,"shutdown is final")
-- Continuous mode is independent and uses one actuator even with both
-- switches enabled. It suspends for free camera, seats and respawn.
local d=create(adapter);local w0,s0,t0=watches,starts,stops
time=10;d.setAlways(true)
assert(d.alwaysEnabled and not d.enabled and starts==s0+1 and watches==w0,"continuous mode starts without touch listeners")
time=20;d.step();assert(stops==t0,"continuous spin stays active")
d.setEnabled(true);assert(watches==w0+1)
activeHandler(other);assert(starts==s0+1 and stops==t0,"contact never creates a competing actuator")
d.setEnabled(false);assert(stops==t0,"disabling contact does not stop continuous mode")
suspended=true;d.step();assert(stops==t0+1,"free camera stops continuous spin")
suspended=false;d.step();assert(starts==s0+2,"continuous spin resumes after free camera")
d.setEnabled(true);d.setAlways(false);assert(stops==t0+2,"turning off continuous mode releases actuator")
time=21;activeHandler(other);assert(starts==s0+3,"contact mode still works independently")
d.setAlways(true);assert(stops==t0+3 and starts==s0+4,"continuous mode replaces transient actuator")
can=false;d.step();assert(stops==t0+4,"seating stops continuous spin")
can=true;d.step();assert(starts==s0+5,"standing resumes continuous spin")
local stale=activeHandler;char,hum,root={},{},{};d.step()
assert(stops==t0+5 and starts==s0+6,"respawn stops old and starts new actuator")
stale(other);assert(starts==s0+6,"stale event ignored while spinning")
currentSpin.valid=false;time=22;d.step();assert(stops==t0+6,"removed actuator is cleaned up")
time=22.5;d.step();assert(starts==s0+6,"no per-frame fight when game removes actuator")
time=23.1;d.step();assert(starts==s0+7,"continuous spin retries after a bounded pause")
d.shutdown();assert(stops==t0+7,"shutdown releases continuous actuator")
-- A failed always-on actuator is retried at most once per second.
local attempts=0;adapter.startSpin=function() attempts=attempts+1;return nil end
local e=create(adapter);time=30;e.setAlways(true);assert(attempts==1)
time=30.5;e.step();assert(attempts==1);time=31.1;e.step();assert(attempts==2)
e.shutdown()
io.write("PASS: opt-in contact push filtering, cooldown, suspension, respawn and cleanup\n")
