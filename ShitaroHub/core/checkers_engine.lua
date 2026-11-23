-- Deterministic English/American checkers analysis (no Roblox dependencies).
-- Board[r][c] = nil or {side=1|2, king=boolean, id=string}; rows 1..8.
-- Side 1 advances toward row 1; side 2 advances toward row 8. A king moves
-- one diagonal square. Captures continue with the same piece in both modes,
-- based on the observed MustContinueCapture event. Promotion ends the turn.
local Engine = {}
local function inside(r,c) return r>=1 and r<=8 and c>=1 and c<=8 end
local function clone(board)
    local out={}
    for r=1,8 do
        out[r]={}
        for c=1,8 do
            local p=board[r] and board[r][c]
            if p then out[r][c]={side=p.side,king=p.king==true,id=p.id} end
        end
    end
    return out
end
Engine.copy = clone
local function dirs(p)
    if p.king then return {-1,1} end
    return {p.side==1 and -1 or 1}
end
local function jumped(board,r,c,p)
    local result={}
    for _,dr in ipairs(dirs(p)) do
        for _,dc in ipairs({-1,1}) do
            local rr,cc=r+2*dr,c+2*dc
            local mid=inside(r+dr,c+dc) and board[r+dr][c+dc]
            if inside(rr,cc) and mid and mid.side~=p.side and not board[rr][cc] then
                result[#result+1]={r=rr,c=cc,cr=r+dr,cc=c+dc}
            end
        end
    end
    return result
end
local function promote(p,r) return not p.king and ((p.side==1 and r==1) or (p.side==2 and r==8)) end
local function chains(board,r,c,firstR,firstC,path,out)
    local p=board[r][c]
    local options=jumped(board,r,c,p)
    if #options==0 then
        if #path>0 then out[#out+1]={r=firstR,c=firstC,steps=path} end
        return
    end
    for _,step in ipairs(options) do
        local b=clone(board)
        local piece=b[r][c];b[r][c]=nil;b[step.cr][step.cc]=nil;b[step.r][step.c]=piece
        local nextPath={};for i,v in ipairs(path) do nextPath[i]=v end
        nextPath[#nextPath+1]=step
        if promote(piece,step.r) then
            out[#out+1]={r=firstR,c=firstC,steps=nextPath}
        else
            chains(b,step.r,step.c,firstR,firstC,nextPath,out)
        end
    end
end
function Engine.moves(board, side, mode)
    assert(side==1 or side==2, "invalid side")
    assert(mode=="American" or mode=="Classic", "unknown mode")
    local captures, simple={},{}
    for r=1,8 do
        for c=1,8 do
            local p=board[r][c]
            if p and p.side==side then
                chains(board,r,c,r,c,{},captures)
                for _,dr in ipairs(dirs(p)) do
                    for _,dc in ipairs({-1,1}) do
                        local rr,cc=r+dr,c+dc
                        if inside(rr,cc) and not board[rr][cc] then
                            simple[#simple+1]={r=r,c=c,steps={{r=rr,c=cc}}}
                        end
                    end
                end
            end
        end
    end
    if mode=="American" and #captures>0 then return captures end
    for _,m in ipairs(simple) do captures[#captures+1]=m end
    return captures
end
function Engine.apply(board, move)
    local out=clone(board);local r,c=move.r,move.c
    local piece=assert(out[r] and out[r][c],"missing piece")
    out[r][c]=nil
    for _,step in ipairs(move.steps) do
        if step.cr then out[step.cr][step.cc]=nil end
        r,c=step.r,step.c
    end
    if promote(piece,r) then piece.king=true end
    out[r][c]=piece
    return out
end
local function evaluate(board, side)
    local value=0
    for r=1,8 do
        for c=1,8 do
            local p=board[r][c]
            if p then
                local advance=p.side==1 and (8-r) or (r-1)
                local centre=(c>=3 and c<=6 and r>=3 and r<=6) and 4 or 0
                local score=p.king and (185+centre) or (100+advance*3+centre)
                value=value+(p.side==side and score or -score)
            end
        end
    end
    return value
end
-- A node budget bounds planning time even in tactically dense positions.
function Engine.best(board, side, mode, opts)
    opts=opts or {};local maxDepth=opts.depth or 4;local maxNodes=opts.nodes or 5000
    local choices=Engine.moves(board,side,mode)
    if #choices==0 then return nil,{nodes=0,depth=0} end
    local nodes, limitHit=0,false
    local function search(b,turn,depth,alpha,beta)
        nodes=nodes+1
        if nodes>maxNodes then limitHit=true;return evaluate(b,side) end
        local moves=Engine.moves(b,turn,mode)
        if #moves==0 then return turn==side and (-100000-depth) or (100000+depth) end
        if depth<=0 then return evaluate(b,side) end
        local maxing=turn==side
        local best=maxing and -math.huge or math.huge
        for _,m in ipairs(moves) do
            local value=search(Engine.apply(b,m),3-turn,depth-1,alpha,beta)
            if maxing then best=math.max(best,value);alpha=math.max(alpha,best)
            else best=math.min(best,value);beta=math.min(beta,best) end
            if beta<=alpha or limitHit then break end
        end
        return best
    end
    local bestMove,bestScore,completed=choices[1],-math.huge,0
    for depth=1,maxDepth do
        local roundMove,roundScore=nil,-math.huge
        limitHit=false
        for _,m in ipairs(choices) do
            local score=search(Engine.apply(board,m),3-side,depth-1,-math.huge,math.huge)
            if limitHit then break end
            if not roundMove or score>roundScore then roundMove,roundScore=m,score end
        end
        if limitHit then break end
        bestMove,bestScore,completed=roundMove,roundScore,depth
    end
    return bestMove,{nodes=nodes,depth=completed,score=bestScore}
end
return Engine
