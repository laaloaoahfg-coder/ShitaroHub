local create=assert(loadfile("core/contact_push.lua"))()
local time=0;local suspended=false;local can=true;local watches,disconnects,starts,stops=0,0,0,0
local char,hum,root={},{},{}
local activeHandler,other={},{}
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
    startSpin=function(r) assert(r==root);starts=starts+1;return {root=r} end,
    stopSpin=function(state) assert(state.root);stops=stops+1 end,
}
local c=create(adapter)
c.step();assert(watches==0 and starts==0,"disabled by default")
c.setEnabled(true);assert(watches==1)
activeHandler({});assert(starts==0,"non-player contact ignored")
activeHandler(other);assert(starts==1 and stops==0)
time=0.24;c.step();assert(stops==0);time=0.26;c.step();assert(stops==1,"spin is short and released")
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
io.write("PASS: opt-in contact push filtering, cooldown, suspension, respawn and cleanup\n")
