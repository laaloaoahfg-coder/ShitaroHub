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
c.start();c.vote("Start",{hasLocal=true});c.vote("Result","American");c.event("GameStarted");c.event("TurnChanged","me");c.tick();c.tick();c.tick();time=time+10;c.tick()
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
-- An unlaid vote button doesn't exhaust the three attempts.
local layoutCalls=0
a.vote=function(_,attempt)
    layoutCalls=layoutCalls+1
    assert(attempt==1,"waiting for layout must not consume a vote attempt")
    if layoutCalls<=5 then return nil end
    return true
end
c.start();c.vote("Start",{hasLocal=true})
for i=1,6 do time=time+0.5;c.tick() end
assert(layoutCalls==6 and c.running,"layout can settle before the first click")
c.stop()
-- A late server acknowledgement replaces the warning; the final rule remains visible.
a.vote=function() return true end
c.start();c.vote("Start",{hasLocal=true})
for i=1,3 do time=time+2;c.tick() end
time=time+2;c.tick();assert(c.status:find("пока не подтверждён",1,true),"timeout must describe uncertainty")
c.vote("Voted",42,"American");assert(c.status:find("подтверждён",1,true) and not c.status:find("пока",1,true),"late confirmation clears warning")
c.vote("Result","Classic");time=time+2;c.tick();assert(c.status:find("Classic",1,true),"final result must stay displayed while awaiting game")
c.stop()
-- A distinct detector gets one try; physical input waits, and an ack cancels it.
local alt,physical=0,0;local physicalMethods={}
a.retryDetector=function() alt=alt+1;return true end
a.retryPiece=function(_,_,method) physical=physical+1;physicalMethods[#physicalMethods+1]=method or "first";return true end
c.start();c.vote("Start",{hasLocal=true});c.vote("Result","American");c.event("GameStarted");c.event("TurnChanged","me");c.tick();c.tick();c.tick()
local tilesBefore=cells;time=time+2;c.tick();assert(alt==1 and physical==0 and cells==tilesBefore,"alternate detector only, no blind destination")
time=time+1;c.tick();assert(alt==1 and physical==0,"wait for detector acknowledgement")
c.event("PieceSelected","own",{{row=5,col=4,isCapture=true}});time=time+2;c.tick()
assert(physical==0 and cells==tilesBefore+1,"confirmed selection suppresses physical retry")
c.stop()
-- If alternate detector doesn't confirm, physical retry is sent once and timeout halts.
c.start();c.vote("Start",{hasLocal=true});c.vote("Result","American");c.event("GameStarted");c.event("TurnChanged","me");c.tick();c.tick();c.tick()
time=time+2;c.tick();time=time+2;c.tick();c.tick();assert(alt==2 and physical==1,"retry methods must be staged and limited")
time=time+2;c.tick();assert(physical==2 and physicalMethods[2]=="virtual","virtual pointer retried only after the wait")
time=time+4;c.tick();assert(not c.running and cells==tilesBefore+1,"no confirmation means halt without extra cell")
a.retryDetector=nil
-- Late selection acknowledgment cancels a scheduled virtual retry, including
-- after the opponent's turn has begun and a new plan is chosen.
local virtualCalls,firstCalls=0,0
a.retryDetector=nil
a.retryPiece=function(_,_,method)
    if method=="virtual" then virtualCalls=virtualCalls+1 else firstCalls=firstCalls+1 end
    return true
end
c.start();c.vote("Start",{hasLocal=true});c.vote("Result","American");c.event("GameStarted");c.event("TurnChanged","me");c.tick();c.tick();c.tick()
time=time+2;c.tick();assert(firstCalls==1 and virtualCalls==0)
c.event("PieceSelected","own",{{row=5,col=4,isCapture=true}})
time=time+1.5;c.event("TurnChanged","foe");c.event("TurnChanged","me");c.tick();c.tick()
time=time+0.6;c.tick();assert(virtualCalls==0 and firstCalls==1,"prior selection cannot trigger retry for a new plan")
c.stop();time=time+5;c.tick();assert(virtualCalls==0,"stop cancels pending virtual retry")
-- Only a server-confirmed destination may receive a physical retry.
local cellRetries=0
a.retryCell=function(r,col,pending)
    assert(r==5 and col==4 and pending(),"retry only the planned confirmed destination")
    cellRetries=cellRetries+1;return true
end
a.retryPiece=function() return true end
c.start();c.vote("Start",{hasLocal=true});c.vote("Result","American");c.event("GameStarted");c.event("TurnChanged","me");c.tick();c.tick();c.tick()
time=time+2;c.tick();assert(cellRetries==0,"never retry a destination before selection ack")
c.event("PieceSelected","own",{{row=5,col=4,isCapture=true}});c.tick()
time=time+2;c.tick();c.tick();assert(cellRetries==1,"retry destination once while awaiting move ack")
c.event("PieceMoved","own",5,4,"foe1",false);time=time+3;c.tick();assert(cellRetries==1,"ack cancels destination retry")
c.stop()
-- A delayed confirmation inside retry cannot produce a second click.
a.retryCell=function(r,col,pending)
    assert(pending());cellRetries=cellRetries+1
    c.event("PieceMoved","own",r,col,"foe1",false)
    assert(not pending());return true
end
c.start();c.vote("Start",{hasLocal=true});c.vote("Result","American");c.event("GameStarted");c.event("TurnChanged","me");c.tick();c.tick();c.tick()
c.event("PieceSelected","own",{{row=5,col=4,isCapture=true}});c.tick();time=time+2;c.tick();c.tick()
assert(cellRetries==2 and c.running,"ack inside retry leaves no pending duplicate");c.stop()
-- The confirmed destination may get one virtual retry after the first
-- physical attempt, but never another destination or another click after ack.
local cellMethods={}
a.retryCell=function(r,col,pending,method)
    assert(r==5 and col==4 and pending());cellMethods[#cellMethods+1]=method or "first";return true
end
c.start();c.vote("Start",{hasLocal=true});c.vote("Result","American");c.event("GameStarted");c.event("TurnChanged","me");c.tick();c.tick();c.tick()
c.event("PieceSelected","own",{{row=5,col=4,isCapture=true}});c.tick()
time=time+2;c.tick();assert(#cellMethods==1 and cellMethods[1]=="first")
time=time+2;c.tick();assert(#cellMethods==2 and cellMethods[2]=="virtual")
c.event("PieceMoved","own",5,4,"foe1",false);time=time+3;c.tick();assert(#cellMethods==2,"move ack cancels cell retries")
c.stop();a.retryCell=nil
-- If automation can't select, guide only the planned piece for a bounded time.
local guides,clears=0,0
a.showGuide=function(id) assert(id=="own");guides=guides+1;return true end
a.clearGuide=function() clears=clears+1 end
a.retryPiece=function() return false end
c.start();c.vote("Start",{hasLocal=true});c.vote("Result","American");c.event("GameStarted");c.event("TurnChanged","me");c.event("YourTurn",35)
c.tick();c.tick();c.tick();local beforeGuideCells=cells;time=time+2;c.tick();time=time+2;c.tick()
assert(guides==1 and c.status=="Нажмите подсвеченную шашку" and cells==beforeGuideCells,"manual guide is shown only after retry fails")
time=time+6;c.tick();assert(c.running and guides==1 and cells==beforeGuideCells,"bounded guide does not repeat clicks")
local beforeClear=clears
c.event("PieceSelected","own",{{row=5,col=4,isCapture=true}});assert(clears>beforeClear and c.status=="Шашка подтверждена")
c.tick();assert(cells==beforeGuideCells+1,"confirmed manual selection may proceed to the planned destination")
c.stop()
-- Wrong manual selection and Stop both remove guides and never guess a cell.
c.start();c.vote("Start",{hasLocal=true});c.vote("Result","American");c.event("GameStarted");c.event("TurnChanged","me");c.tick();c.tick();c.tick();time=time+2;c.tick();time=time+2;c.tick()
beforeClear=clears;local beforeWrong=cells;c.event("PieceSelected","other",{{row=5,col=4,isCapture=true}})
assert(not c.running and clears>beforeClear and cells==beforeWrong,"wrong selection halts and removes guide")
c.start();c.vote("Start",{hasLocal=true});c.vote("Result","American");c.event("GameStarted");c.event("TurnChanged","me");c.tick();c.tick();c.tick();time=time+2;c.tick();time=time+2;c.tick()
beforeClear=clears;c.stop();assert(clears>beforeClear,"stop clears guide")
-- The guide cannot extend automation past the server turn deadline.
c.start();c.vote("Start",{hasLocal=true});c.vote("Result","American");c.event("GameStarted");c.event("TurnChanged","me");c.event("YourTurn",6)
c.tick();c.tick();c.tick();time=time+2;c.tick();time=time+2;c.tick();time=time+2;c.tick();assert(not c.running,"guide stops at turn deadline")
a.showGuide=nil;a.clearGuide=nil
-- If cell automation is not acknowledged, assist only the exact destination
-- approved by PieceSelected / MustContinueCapture, and resume on PieceMoved.
local cellGuides,cellClears={},0
a.clearGuide=function() cellClears=cellClears+1 end
a.showCellGuide=function(r,col) cellGuides[#cellGuides+1]={r,col};return true end
a.retryCell=function() return false end
a.retryPiece=function() return false end
local function beginManualCell()
    c.start();c.vote("Start",{hasLocal=true});c.vote("Result","American");c.event("GameStarted");c.event("TurnChanged","me");c.event("YourTurn",35)
    c.tick();c.tick();c.tick();c.event("PieceSelected","own",{{row=5,col=4,isCapture=true}});c.tick()
    time=time+2;c.tick();time=time+2;c.tick()
end
beginManualCell()
assert(#cellGuides==1 and cellGuides[1][1]==5 and cellGuides[1][2]==4 and c.activity()=="Нажмите подсвеченную клетку")
time=time+6;c.tick();assert(c.running and #cellGuides==1,"manual cell waits without repeating input")
local beforeManualClear=cellClears
c.event("PieceMoved","own",5,4,"foe1",false)
assert(c.running and cellClears>beforeManualClear,"manual move acknowledgment removes guide")
c.event("MustContinueCapture","own",{{row=7,col=6,isCapture=true}});c.tick()
time=time+2;c.tick();time=time+2;c.tick()
assert(#cellGuides==2 and cellGuides[2][1]==7 and cellGuides[2][2]==6,"chain guide uses next server-confirmed jump")
c.event("PieceMoved","own",7,6,"foe2",false);c.event("TurnChanged","foe");assert(c.running);c.stop()
-- A different move or an early turn change cannot silently resume on a guessed board.
beginManualCell();beforeManualClear=cellClears
c.event("PieceMoved","own",4,1,nil,false)
assert(not c.running and cellClears>beforeManualClear,"wrong manual move halts and clears guide")
beginManualCell();beforeManualClear=cellClears;c.event("TurnChanged","foe")
assert(not c.running and cellClears>beforeManualClear,"turn change before move ack halts and clears guide")
beginManualCell();beforeManualClear=cellClears;c.stop();assert(cellClears>beforeManualClear)
local guidesBefore=#cellGuides;time=time+15;c.tick();assert(#cellGuides==guidesBefore,"Stop cancels cell guide")
-- Do not extend the manual wait beyond the server deadline.
c.start();c.vote("Start",{hasLocal=true});c.vote("Result","American");c.event("GameStarted");c.event("TurnChanged","me");c.event("YourTurn",8)
c.tick();c.tick();c.tick();c.event("PieceSelected","own",{{row=5,col=4,isCapture=true}});c.tick()
time=time+2;c.tick();time=time+2;c.tick();assert(c.running)
time=time+4;c.tick();assert(not c.running,"manual cell assist stops at deadline")
a.showCellGuide=nil;a.clearGuide=nil;a.retryCell=nil
-- Selection assistance stays available beyond ten seconds when the turn
-- deadline permits; the player can still acknowledge and proceed.
a.showGuide=function(id) assert(id=="own");return true end
a.clearGuide=function() end
a.retryPiece=function() return false end
c.start();c.vote("Start",{hasLocal=true});c.vote("Result","American");c.event("GameStarted");c.event("TurnChanged","me");c.event("YourTurn",35)
c.tick();c.tick();c.tick();time=time+2;c.tick();time=time+2;c.tick()
time=time+12;c.tick();assert(c.running and c.activity()=="Нажмите подсвеченную шашку","guide can use remaining turn")
c.event("PieceSelected","own",{{row=5,col=4,isCapture=true}});c.tick();assert(c.running,"manual acknowledgment resumes")
c.stop();a.showGuide=nil;a.clearGuide=nil
-- A vote handler that yields may resume after Stop and a new Start.
a.vote=function(_,_,pending)
    assert(pending());c.stop();c.start();assert(not pending(),"old pending predicate must not match a new session")
    return false
end
c.start();c.vote("Start",{hasLocal=true});c.tick()
assert(c.running and c.status=="Поиск стола","stale vote must not alter a restarted session");c.stop()
io.write("PASS: checkers controller votes, server legal checks, multi-jump, stop, stats and timeout\n")
