-- Match state machine. All game interaction is delegated to the adapter; a
-- failed/ambiguous acknowledgement stops automation rather than guessing.
return function(engine, adapter)
    local c={running=false,status="Остановлен",stats={wins=0,losses=0,unknown=0,games=0}}
    local s={}
    local function now() return adapter.now() end
    local function status(text) c.status=text;if adapter.changed then adapter.changed(c) end end
    local function clearRound()
        s.match=false;s.mode=nil;c.mode=nil;s.board=nil;s.side=nil;s.turn=false;s.phase=nil;s.plan=nil
        s.voteOpen=false;s.voteAck=false;s.voteAttempts=0;s.initializing=false;s.lostSeatAt=nil;s.voteSeat=nil
        if adapter.releaseBoard then adapter.releaseBoard() end
    end
    local function halt(reason)
        c.running=false;s.phase=nil
        if adapter.cancel then pcall(adapter.cancel) end
        status("Остановлен: "..tostring(reason))
    end
    function c.start()
        if c.running then return end
        s={};clearRound();c.running=true;s.nextSeat=0
        status("Поиск стола")
    end
    function c.stop()
        if not c.running then return end
        c.running=false;clearRound()
        if adapter.cancel then pcall(adapter.cancel) end
        status("Остановлен")
    end
    local function findPiece(id)
        if not s.board then return nil end
        for r=1,8 do for col=1,8 do local p=s.board[r][col];if p and p.id==id then return p,r,col end end end
    end
    local function validOptions(options)
        return type(options)=="table" and #options>0
    end
    local function findOption(options,step)
        if not validOptions(options) then return false end
        for _,v in ipairs(options) do
            if type(v)=="table" and v.row==step.r and v.col==step.c and (v.isCapture==true)==(step.cr~=nil) then return true end
        end
        return false
    end
    function c.vote(action,a,b)
        if not c.running then return end
        if action=="Start" then
            if s.match then return end
            if not adapter.isSeated() or not adapter.containsLocal(a) then return end
            s.voteSeat=adapter.seatKey()
            if not s.voteSeat then return end
            s.voteOpen=true;s.voteAck=false;s.mode=nil;s.voteAttempts=0;s.nextVote=0
            status("Голосование")
        elseif action=="Voted" and s.voteOpen and adapter.isLocalId(a) then
            s.voteAck=true
        elseif action=="Result" and s.voteOpen then
            if adapter.seatKey()~=s.voteSeat then halt("стол изменился во время голосования") return end
            s.voteOpen=false
            if a=="Classic" or a=="American" then s.mode=a;c.mode=a;status("Правила: "..a)
            else halt("неизвестные правила") end
        elseif action=="Close" then s.voteOpen=false end
    end
    function c.event(action,a,b,d,e,f)
        if not c.running then return end
        if action=="GameStarted" then
            if not adapter.isSeated() then return end
            if s.match then halt("повторное начало партии") return end
            if not s.mode or not s.voteSeat or adapter.seatKey()~=s.voteSeat then halt("пропущен итог голосования; начните до новой партии") return end
            s.match=true;s.board=nil;s.turn=false;s.phase=nil;s.initializing=true;s.initUntil=now()+10
            status("Читаю начальную доску")
        elseif action=="GameOver" and s.match then
            local result=adapter.result(a)
            c.stats.games=c.stats.games+1
            if result=="win" then c.stats.wins=c.stats.wins+1
            elseif result=="loss" then c.stats.losses=c.stats.losses+1
            else c.stats.unknown=c.stats.unknown+1 end
            if adapter.saveStats then pcall(adapter.saveStats,c.stats) end
            clearRound();s.nextSeat=now()+4
            status("Партия завершена: "..result)
        elseif action=="TurnChanged" and s.match then
            s.turn=adapter.isLocal(a);s.phase=nil;s.plan=nil;s.deadline=nil
            status(s.turn and "Наш ход" or "Ход соперника")
        elseif action=="YourTurn" and s.match then
            if type(a)=="number" and a>0 then s.deadline=now()+a end
        elseif action=="PieceMoved" and s.match then
            if s.turn and s.phase and s.phase~="move" then halt("неожиданный ход во время работы бота") return end
            if not s.board then halt("ход до завершения чтения доски") return end
            local p,r,col=findPiece(a)
            if not p or type(b)~="number" or type(d)~="number" or b%1~=0 or d%1~=0 or b<1 or b>8 or d<1 or d>8 or s.board[b][d] then
                halt("непонятное перемещение; доска могла рассинхронизироваться") return
            end
            if e~=nil then
                local victim,vr,vc=findPiece(e)
                if not victim or victim.side==p.side then halt("не найдена взятая шашка") return end
                s.board[vr][vc]=nil
            end
            s.board[r][col]=nil;s.board[b][d]=p
            if f==true then p.king=true end
            if s.phase=="move" then
                local step=s.plan and s.plan.steps[s.stepIndex]
                if not step or a~=s.planId or step.r~=b or step.c~=d then halt("сервер подтвердил другой ход") return end
                s.stepIndex=s.stepIndex+1
                s.phase=s.stepIndex<=#s.plan.steps and "continue" or "turn"
                s.phaseUntil=now()+6
            end
        elseif action=="KingPromoted" and s.match and s.board then
            local p=findPiece(a);if p then p.king=true else halt("не найдена коронованная шашка") end
        elseif action=="PieceSelected" and s.match and s.turn and (s.phase=="select" or s.phase=="cell") then
            local step=s.plan and s.plan.steps[s.stepIndex]
            if a~=s.planId or not step or not findOption(b,step) then halt("запланированный ход не подтверждён сервером") return end
            s.phase="cell";s.options=b;s.phaseUntil=now()+5
        elseif action=="MustContinueCapture" and s.match and s.turn then
            if s.phase~="continue" or a~=s.planId then halt("неожиданное продолжение взятия") return end
            local step=s.plan.steps[s.stepIndex]
            if not step or not findOption(b,step) then halt("продолжение не подтверждено сервером") return end
            s.phase="cell";s.options=b;s.phaseUntil=now()+5
        end
    end
    function c.timeLeft()
        if not c.running or not s.turn or not s.deadline then return nil end
        return math.max(0,math.ceil(s.deadline-now()))
    end
    function c.tick()
        if not c.running then return end
        if s.voteOpen and not s.voteAck and now()>=(s.nextVote or 0) and s.voteAttempts<3 then
            s.voteAttempts=s.voteAttempts+1;s.nextVote=now()+2
            local ok=adapter.vote("American")
            if not ok then status("Не удалось голосовать автоматически — выберите вручную") end
        end
        if not s.match then
            if not s.voteOpen and now()>=(s.nextSeat or 0) then
                s.nextSeat=now()+2
                if not adapter.isSeated() then adapter.seekSeat() else status("Ожидание соперника") end
            end
            return
        end
        if not adapter.isSeated() then
            s.lostSeatAt=s.lostSeatAt or now()
            if now()-s.lostSeatAt>3 then halt("место покинуто") end
            return
        end
        s.lostSeatAt=nil
        if s.initializing then
            local board,side=adapter.initialBoard()
            if board and (side==1 or side==2) then
                s.board=board;s.side=side;s.initializing=false
                status(s.turn and "Наш ход" or "Ход соперника")
            elseif now()>s.initUntil then halt("не удалось надёжно прочитать начальную доску") end
            return
        end
        if not s.turn or not s.board then return end
        if s.phase and now()>(s.phaseUntil or 0) then halt("нет подтверждения от игры") return end
        if not s.phase then
            local move=engine.best(s.board,s.side,s.mode,{depth=4,nodes=5000})
            if not move then halt("нет допустимого хода") return end
            local p=s.board[move.r][move.c]
            if not p or not p.id then halt("не найдена выбранная шашка") return end
            s.plan=move;s.planId=p.id;s.stepIndex=1;s.phase="selectReady";s.phaseUntil=now()+5
        elseif s.phase=="selectReady" then
            s.phase="select"
            local result=adapter.selectPiece(s.planId)
            if result==nil and s.phase=="select" then s.phase="selectReady"
            elseif result==false then halt("не удалось выбрать шашку")
            elseif result==true and s.phase=="select" then s.phaseUntil=now()+5 end
        elseif s.phase=="cell" then
            local step=s.plan.steps[s.stepIndex]
            local waitUntil=s.phaseUntil
            s.phase="move"
            local result=adapter.clickCell(step.r,step.c)
            if result==nil and s.phase=="move" then s.phase="cell";s.phaseUntil=waitUntil
            elseif result==false then halt("не удалось нажать клетку")
            elseif result==true and s.phase=="move" then s.phaseUntil=now()+5 end
        end
    end
    return c
end
