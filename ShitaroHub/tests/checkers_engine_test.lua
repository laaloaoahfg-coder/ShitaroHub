local e=assert(loadfile("core/checkers_engine.lua"))()
local function empty() local b={};for i=1,8 do b[i]={} end;return b end
local function p(side,king,id) return {side=side,king=king or false,id=id} end
local b=empty();b[3][2]=p(2);b[4][3]=p(1);b[6][5]=p(1);b[2][7]=p(2)
local forced=e.moves(b,2,"American")
assert(#forced==1 and #forced[1].steps==2,"American forces full multi-capture")
assert(forced[1].steps[1].r==5 and forced[1].steps[2].r==7)
local optional=e.moves(b,2,"Classic");assert(#optional>1,"Classic allows other moves")
local applied=e.apply(b,forced[1]);assert(applied[7][6] and not applied[4][3] and not applied[6][5])
assert(b[3][2] and b[4][3],"search must not mutate board")
b=empty();b[5][4]=p(2);local moves=e.moves(b,2,"Classic")
for _,m in ipairs(moves) do assert(m.steps[1].r==6,"man cannot move backward") end
b[5][4].king=true;local back=false
for _,m in ipairs(e.moves(b,2,"Classic")) do if m.steps[1].r==4 then back=true end end
assert(back,"king can move backward")
b=empty();b[6][1]=p(2);b[7][2]=p(1);b[7][4]=p(1)
local crown=e.moves(b,2,"American");assert(#crown==1 and #crown[1].steps==1,"promotion ends jump sequence")
assert(e.apply(b,crown[1])[8][3].king,"promotion")
b=empty();b[3][2]=p(2);b[4][3]=p(1);b[6][5]=p(1);b[1][8]=p(1)
local chosen,stats=e.best(b,2,"Classic",{depth=3,nodes=4000})
assert(chosen and #chosen.steps==2 and stats.depth>=1,"search selects profitable combination")
b=empty();b[8][1]=p(2);assert(e.best(b,2,"American")==nil,"no legal move")
io.write("PASS: checkers engine mandatory/optional, chains, promotion, king, search and no mutation\n")
