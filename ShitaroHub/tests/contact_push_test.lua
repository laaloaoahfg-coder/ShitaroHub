local create=assert(loadfile("core/contact_push.lua"))()
local time=0;local suspended=false;local can=true;local watches,disconnects,starts,stops,pushes=0,0,0,0,0
local char,hum,root={},{},{}
local activeHandler,other={},{}
local currentSpin
local adapter={
    now=function() return time end,
    suspended=function() return suspended end,
    resolve=function() return char,hum,root end,
    canPush=function(h,r) return can and h==hum and r==root end,
    isOtherPlayerPart=function(part,r) if part==other and r==root then return true,other end return false end,
    tryOwnedPush=function(target,r) assert(target==other and r==root);pushes=pushes+1 end,
    watch=function(target,callback)
        assert(target==char);watches=watches+1;activeHandler=callback
        return function() disconnects=disconnects+1 end
    end,
    startSpin=function(r,h) assert(r==root and h==hum);starts=starts+1;currentSpin={root=r,valid=true};return currentSpin end,
    spinValid=function(state) return state.valid end,
    stopSpin=function(state) assert(state.root);state.valid=false;stops=stops+1 end,
}
local c=create(adapter)
c.step();assert(watches==0 and starts==0,"disabled by default")
c.setEnabled(true);assert(watches==1)
activeHandler({});assert(pushes==0,"non-player contact ignored")
activeHandler(other);assert(pushes==1 and starts==0,"touch never spins user")
time=0.5;activeHandler(other);assert(pushes==1,"cooldown suppresses duplicates")
time=1.1;suspended=true;activeHandler(other);assert(pushes==1)
suspended=false;can=false;activeHandler(other);assert(pushes==1)
can=true;activeHandler(other);assert(pushes==2)
local oldCallback=activeHandler
char,hum,root={},{},{};c.step();assert(disconnects==1 and watches==2,"respawn releases old character")
oldCallback(other);assert(pushes==2,"stale callback cannot act on a new character")
c.setEnabled(false);assert(disconnects==2,"disable removes listener")
activeHandler(other);assert(pushes==2,"old listener cannot act when disabled")
c.setEnabled(true);assert(watches==3)
c.shutdown();assert(disconnects==3)
c.setEnabled(true);c.step();assert(watches==3,"shutdown is final")
local d=create(adapter);local w0,s0,t0=watches,starts,stops
time=10;d.setAlways(true)
assert(d.alwaysEnabled and not d.enabled and starts==s0+1 and watches==w0,"spin starts without touch listener")
d.setEnabled(true);assert(watches==w0+1)
activeHandler(other);assert(starts==s0+1 and stops==t0 and pushes==3,"contact works independently while spinning")
d.setEnabled(false);assert(stops==t0,"disabling contact does not stop spin")
suspended=true;d.step();assert(stops==t0+1,"free camera stops spin")
suspended=false;d.step();assert(starts==s0+2,"spin resumes")
can=false;d.step();assert(stops==t0+2,"seating stops spin")
can=true;d.step();assert(starts==s0+3,"standing resumes spin")
char,hum,root={},{},{};d.step();assert(stops==t0+3 and starts==s0+4,"respawn replaces actuator")
currentSpin.valid=false;time=22;d.step();assert(stops==t0+4,"removed actuator is cleaned up")
time=22.5;d.step();assert(starts==s0+4,"bounded retry")
time=23.1;d.step();assert(starts==s0+5,"retry after pause")
d.setAlways(false);assert(stops==t0+5,"toggle stops spin")
d.shutdown()
local attempts=0;adapter.startSpin=function() attempts=attempts+1;return nil end
local e=create(adapter);time=30;e.setAlways(true);assert(attempts==1)
time=30.5;e.step();assert(attempts==1);time=31.1;e.step();assert(attempts==2)
e.shutdown()
io.write("PASS: opt-in contact push filtering, cooldown, suspension, respawn and cleanup\n")
