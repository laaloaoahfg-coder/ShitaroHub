-- Anonymized board/move sequence from one Classic game. No account names,
-- user IDs, server ID, raw packet data, or positions in the world are stored.
-- Tests hypotheses against received events; it is not a Roblox integration test.
local engine=assert(loadfile("core/checkers_engine.lua"))()
local board={};for r=1,8 do board[r]={} end
local initial={
    {"Piece1_1",6,1},
    {"Piece1_10",8,3},
    {"Piece1_11",8,5},
    {"Piece1_12",8,7},
    {"Piece1_2",6,3},
    {"Piece1_3",6,5},
    {"Piece1_4",6,7},
    {"Piece1_5",7,2},
    {"Piece1_6",7,4},
    {"Piece1_7",7,6},
    {"Piece1_8",7,8},
    {"Piece1_9",8,1},
    {"Piece2_1",1,2},
    {"Piece2_10",3,4},
    {"Piece2_11",3,6},
    {"Piece2_12",3,8},
    {"Piece2_2",1,4},
    {"Piece2_3",1,6},
    {"Piece2_4",1,8},
    {"Piece2_5",2,1},
    {"Piece2_6",2,3},
    {"Piece2_7",2,5},
    {"Piece2_8",2,7},
    {"Piece2_9",3,2},
}
for _,v in ipairs(initial) do board[v[2]][v[3]]={id=v[1],side=tonumber(v[1]:sub(6,6)),king=false} end
local events={
    {"move","Piece1_3",5,4,nil},
    {"move","Piece2_9",4,1,nil},
    {"move","Piece1_6",6,5,nil},
    {"move","Piece2_6",3,2,nil},
    {"move","Piece1_1",5,2,nil},
    {"move","Piece2_6",4,3,nil},
    {"move","Piece1_3",3,2,"Piece2_6"},
    {"move","Piece2_5",4,3,"Piece1_3"},
    {"MustContinueCapture","Piece2_5"},
    {"move","Piece2_5",6,1,"Piece1_1"},
    {"move","Piece1_2",5,4,nil},
    {"move","Piece2_9",5,2,nil},
    {"move","Piece1_4",5,8,nil},
    {"move","Piece2_12",4,7,nil},
    {"move","Piece1_5",6,3,nil},
    {"move","Piece2_9",7,4,"Piece1_5"},
    {"move","Piece1_11",6,3,"Piece2_9"},
    {"move","Piece2_1",2,1,nil},
    {"move","Piece1_8",6,7,nil},
    {"move","Piece2_10",4,5,nil},
    {"move","Piece1_12",7,8,nil},
    {"move","Piece2_8",3,8,nil},
    {"move","Piece1_8",5,6,nil},
    {"move","Piece2_10",6,7,"Piece1_8"},
    {"MustContinueCapture","Piece2_10"},
    {"move","Piece2_10",8,5,"Piece1_7"},
    {"KingPromoted","Piece2_10"},
    {"move","Piece1_2",4,3,nil},
    {"move","Piece2_2",2,3,nil},
    {"move","Piece1_6",5,4,nil},
    {"move","Piece2_2",3,4,nil},
    {"move","Piece1_11",5,2,nil},
    {"move","Piece2_2",4,5,nil},
    {"move","Piece1_11",4,1,nil},
    {"move","Piece2_2",6,3,"Piece1_6"},
    {"move","Piece1_11",3,2,nil},
    {"move","Piece2_10",7,6,nil},
    {"move","Piece1_12",6,7,nil},
    {"move","Piece2_10",8,7,nil},
    {"move","Piece1_2",3,4,nil},
    {"move","Piece2_7",4,3,"Piece1_2"},
    {"move","Piece1_11",2,3,nil},
    {"move","Piece2_10",7,8,nil},
    {"move","Piece1_11",1,2,nil},
    {"KingPromoted","Piece1_11"},
    {"move","Piece2_10",5,6,"Piece1_12"},
    {"move","Piece1_11",2,3,nil},
    {"move","Piece2_10",4,5,nil},
    {"move","Piece1_11",1,4,nil},
    {"move","Piece2_10",3,4,nil},
    {"move","Piece1_9",7,2,nil},
    {"move","Piece2_2",8,1,"Piece1_9"},
    {"KingPromoted","Piece2_2"},
    {"move","Piece1_10",7,2,nil},
    {"move","Piece2_5",8,3,"Piece1_10"},
    {"KingPromoted","Piece2_5"},
    {"move","Piece1_11",2,5,nil},
    {"move","Piece2_2",7,2,nil},
    {"move","Piece1_11",1,4,nil},
    {"move","Piece2_2",6,1,nil},
    {"move","Piece1_11",2,3,nil},
    {"move","Piece2_10",1,2,"Piece1_11"},
}
local function locate(id)
    for r=1,8 do for c=1,8 do local p=board[r][c];if p and p.id==id then return p,r,c end end end
end
local forced, count, chains, crowns=nil,0,0,0
for _,event in ipairs(events) do
    local typ,id=event[1],event[2]
    if typ=="MustContinueCapture" then
        forced=id;chains=chains+1
    elseif typ=="KingPromoted" then
        local p=assert(locate(id),"promoted figure must exist");p.king=true;crowns=crowns+1
    else
        local p,r,c=locate(id);assert(p,"moving piece must exist: "..id)
        if forced then assert(forced==id and event[5],"same piece must complete the observed capture chain");forced=nil end
        local allowed=false
        for _,move in ipairs(engine.moves(board,p.side,"Classic")) do
            local step=move.steps[1]
            if move.r==r and move.c==c and step.r==event[3] and step.c==event[4] then
                local victim=step.cr and board[step.cr][step.cc]
                if (victim and victim.id or nil)==event[5] then allowed=true end
            end
        end
        assert(allowed,"recorded move must be legal under the current model: "..id.." to "..event[3]..","..event[4])
        if event[5] then local _,vr,vc=locate(event[5]);assert(vr and vc);board[vr][vc]=nil end
        board[r][c]=nil;assert(not board[event[3]][event[4]],"destination must be empty")
        board[event[3]][event[4]]=p;count=count+1
    end
end
assert(count==56 and chains==2 and crowns==4 and not forced)
io.write("PASS: anonymized recorded Classic match (56 moves, 2 chains, 4 promotions)\n")
