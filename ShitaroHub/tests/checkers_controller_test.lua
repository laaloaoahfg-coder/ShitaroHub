local engine=assert(loadfile("core/checkers_engine.lua"))()
local make=assert(loadfile("core/checkers_controller.lua"))()
local function board()
    local b={};for r=1,8 do b[r]={} end
    b[3][2]={side=2,id="own",king=false};b[4][3]={side=1,id="foe1"};b[6][5]={side=1,id="foe2"};return b
end
local time=0;local picks,cells,stats=0,0,0
local a={now=function() return time end,isSeated=function() return true end,
    seatKey=function() return "table1" end,containsLocal=function(a) return a and a.hasLocal end,isLocalId=function(x) return x==42 end,
    isLocal=function(x) return x=="me" end,result=function(x) return x=="me" and "win" or x and "loss" or "unknown" end,
    seekSeat=function() end,initialBoard=function() return board(),2 end,vote=function() return true end,
    selectPiece=function(id) picks=picks+1;return id=="own" end,
    clickCell=function() cells=cells+1;return true end,saveStats=function() stats=stats+1 end}
local c=make(engine,a)
c.start();c.event("GameStarted");assert(not c.running and picks==0,"must not guess missing vote")
c.start();c.vote("Start",{hasLocal=true});c.vote("Voted",42,"American");c.vote("Result","Classic")
c.event("GameStarted");c.event("TurnChanged","me");c.event("YourTurn",35);c.tick();assert(c.timeLeft()==35)
c.tick();c.tick();assert(picks==1,"one selection after known actual rules")
c.event("PieceSelected","own",{{row=5,col=4,isCapture=true}});c.tick();assert(cells==1)
c.event("PieceMoved","own",5,4,"foe1",false)
c.event("MustContinueCapture","own",{{row=7,col=6,isCapture=true}});c.tick();assert(cells==2)
c.event("PieceMoved","own",7,6,"foe2",false);c.event("TurnChanged","foe")
c.event("GameOver","me",true);c.event("GameOver","me",true)
assert(c.stats.games==1 and c.stats.wins==1 and stats==1,"finish counted exactly once")
c.stop();c.tick();assert(cells==2,"stop stops actions")
-- Missing/incorrect legal response must halt, never click a guessed cell.
c.start();c.vote("Start",{hasLocal=true});c.vote("Result","American");c.event("GameStarted");c.event("TurnChanged","me");c.tick();c.tick();c.tick()
local before=cells;c.event("PieceSelected","own",{{row=8,col=8,isCapture=true}});c.tick()
assert(not c.running and cells==before,"server legal moves must match plan")
-- Timeout must not repeatedly send clicks.
c.start();c.vote("Start",{hasLocal=true});c.vote("Result","American");c.event("GameStarted");c.event("TurnChanged","me");c.tick();c.tick();c.tick();time=time+6;c.tick()
assert(not c.running and cells==before,"missing acknowledgement must halt")
-- A different selection while ours is pending must not result in a tile click.
c.start();c.vote("Start",{hasLocal=true});c.vote("Result","American");c.event("GameStarted");c.event("TurnChanged","me");c.tick();c.tick();c.tick()
c.event("PieceSelected","other",{{row=5,col=4,isCapture=true}})
assert(not c.running and cells==before,"unexpected selection must halt")
-- Results for a seat that changed cannot determine the next game's mode.
local seat="table1";a.seatKey=function() return seat end
c.start();c.vote("Start",{hasLocal=true});seat="table2";c.vote("Result","American")
assert(not c.running,"changing tables invalidates vote")
-- A temporarily disabled detector must not extend the timeout indefinitely.
a.seatKey=function() return "table1" end;a.clickCell=function() return nil end
c.start();c.vote("Start",{hasLocal=true});c.vote("Result","American");c.event("GameStarted");c.event("TurnChanged","me");c.tick();c.tick();c.tick()
c.event("PieceSelected","own",{{row=5,col=4,isCapture=true}})
for i=1,6 do time=time+1;c.tick() end
assert(not c.running,"unavailable cell detector must time out")
-- A single delayed retry is allowed, but never a tile before confirmation.
local retries=0;local attempts={}
a.vote=function(_,attempt) attempts[#attempts+1]=attempt;return true end
a.retryPiece=function(id) assert(id=="own");retries=retries+1;return true end
a.clickCell=function() cells=cells+1;return true end
c.start();c.vote("Start",{hasLocal=true});c.tick();time=time+2;c.tick();time=time+2;c.tick()
assert(#attempts==3 and attempts[1]==1 and attempts[2]==2 and attempts[3]==3,"vote tries methods in order")
c.vote("Voted",42,"American");time=time+3;c.tick();assert(#attempts==3,"confirmed vote stops retries")
c.vote("Result","American");c.event("GameStarted");c.event("TurnChanged","me");c.tick();c.tick();c.tick()
local beforeRetryCells=cells;time=time+2;c.tick();c.tick();assert(retries==1 and cells==beforeRetryCells,"only one retry, no blind cell")
c.event("PieceSelected","own",{{row=5,col=4,isCapture=true}});c.tick();assert(cells==beforeRetryCells+1)
c.stop()
c.start();c.vote("Start",{hasLocal=true});c.vote("Result","American");c.event("GameStarted");c.event("TurnChanged","me");c.tick();c.tick();c.tick()
c.event("PieceSelected","own",{{row=5,col=4,isCapture=true}});time=time+3;c.tick()
assert(retries==1,"acknowledgement suppresses selection retry");c.stop()
io.write("PASS: checkers controller votes, server legal checks, multi-jump, stop, stats and timeout\n")
