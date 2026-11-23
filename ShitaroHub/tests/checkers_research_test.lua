-- Mock integration for the research probe; not a Roblox/Xeno test.
local nativePrint=print
local printed, files, copied, disconnected = {}, {}, nil, 0
print=function(s) printed[#printed+1]=tostring(s) end
warn=print
local Vector={};Vector.__index=function(t,k) if k=="Magnitude" then return math.sqrt(t.X*t.X+t.Y*t.Y+t.Z*t.Z) end end
Vector.__sub=function(a,b) return setmetatable({X=a.X-b.X,Y=a.Y-b.Y,Z=a.Z-b.Z},Vector) end
local function vec(x,y,z) return setmetatable({X=x,Y=y,Z=z},Vector) end
local function signal()
    local s={callbacks={}}
    function s:Connect(fn)
        local item={fn=fn,active=true};self.callbacks[#self.callbacks+1]=item
        return {Disconnect=function() if item.active then item.active=false;disconnected=disconnected+1 end end}
    end
    function s:Fire(...) for _,item in ipairs(self.callbacks) do if item.active then item.fn(...) end end end
    return s
end
local Obj={};Obj.__index=Obj
function Obj:IsA(c)
    if self.ClassName==c then return true end
    if c=="BasePart" then return self.ClassName=="Part" or self.ClassName=="Seat" end
    if c=="ValueBase" then return self.ClassName=="StringValue" or self.ClassName=="IntValue" end
    if c=="GuiObject" then return self.ClassName=="TextLabel" or self.ClassName=="TextButton" or self.ClassName=="TextBox" end
    return false
end
function Obj:GetFullName() return self.Parent and (self.Parent:GetFullName().."."..self.Name) or self.Name end
function Obj:GetAttributes() return self.attrs end
function Obj:GetChildren() return self.children end
function Obj:GetDescendants()
    local out={};local function visit(a) for _,c in ipairs(a.children) do out[#out+1]=c;visit(c) end end;visit(self);return out
end
function Obj:FindFirstChildOfClass(c) for _,v in ipairs(self.children) do if v:IsA(c) then return v end end end
function Obj:FindFirstChild(n) for _,v in ipairs(self.children) do if v.Name==n then return v end end end
function Obj:FindFirstAncestorOfClass(c) local p=self.Parent;while p do if p:IsA(c) then return p end;p=p.Parent end end
local function new(class,name,parent)
    local o=setmetatable({ClassName=class,Name=name,Parent=parent,children={},attrs={},DescendantAdded=signal()},Obj)
    if parent then parent.children[#parent.children+1]=o end
    return o
end
function typeof(v) if getmetatable(v)==Obj then return "Instance" end;if getmetatable(v)==Vector then return "Vector3" end;return type(v) end
local workspace=new("Workspace","Workspace")
local board=new("Model","GameTable",workspace)
local seat=new("Seat","Seat",board);seat.Position=vec(0,0,0);seat.Size=vec(2,1,2);seat.Color="brown";seat.Anchored=true;seat.Transparency=0
local piece=new("Part","Piece",board);piece.Position=vec(2,0,2);piece.Size=vec(1,.2,1);piece.Color="red";piece.Anchored=true;piece.Transparency=0
local turn=new("StringValue","Turn",board);turn.Value="Local"
local rep=new("ReplicatedStorage","ReplicatedStorage")
local initial=new("RemoteEvent","Move",rep);initial.OnClientEvent=signal()
local other=new("RemoteEvent","Vote",rep);other.OnClientEvent=signal()
local first=new("ReplicatedFirst","ReplicatedFirst")
local me=new("Player","Local");me.DisplayName="Local";me.UserId=1
local gui=new("PlayerGui","PlayerGui",me)
local label=new("TextLabel","Rules",gui);label.Text="American Checkers";label.Visible=true;label.Position="p";label.Size="s"
local secretChat=new("TextLabel","Chat",gui);secretChat.Text="private message";secretChat.Visible=true
local textBox=new("TextBox","Entry",gui);textBox.Text="private typing";textBox.Visible=true
local char=new("Model","Character",workspace);me.Character=char
local humanoid=new("Humanoid","Humanoid",char);humanoid.SeatPart=seat;seat.Occupant=humanoid
local players={LocalPlayer=me};function players:GetPlayers() return {me} end;function players:GetPlayerFromCharacter(m) if m==char then return me end end
local input={InputBegan=signal()}
local services={Players=players,Workspace=workspace,ReplicatedStorage=rep,ReplicatedFirst=first,UserInputService=input}
game={PlaceId=10,GameId=11,JobId="test-job"};function game:GetService(n) return services[n] end
local env={};function getgenv() return env end
local folders={};function isfolder(n) return folders[n] end;function makefolder(n) folders[n]=true end
function writefile(p,s) files[p]=s end;function setclipboard(s) copied=s end
task={};local waits
local currentMethod, namecallHook, originalCalls
function getnamecallmethod() return currentMethod end
function hookmetamethod(_,name,fn)
    assert(name=="__namecall");namecallHook=fn
    return function(_,...) originalCalls=originalCalls+1;if select(1,...)=="raise" then error("original failure") end;return "forwarded",nil,42 end
end
local function run(enabled)
    env.ShitaroCheckersResearchConfig={CaptureOutgoing=enabled};waits=0;copied=nil;originalCalls=0
    function task.wait()
        waits=waits+1
        if waits==1 then
            for i=1,45 do initial.OnClientEvent:Fire({turn="Enemy",token="secret-test",row=3}) end
            other.OnClientEvent:Fire("Checkers with Skips")
            piece.Position=vec(3,0,3);turn.Value="Enemy";label.Text="Checkers with Skips"
            if enabled then
                currentMethod="FireServer"
                local a,b,c=namecallHook(other,"move",3,4)
                assert(a=="forwarded" and b==nil and c==42)
            end
        elseif waits==2 then
            local newcomer=new("RemoteEvent","NewVote",rep);newcomer.OnClientEvent=signal()
            rep.DescendantAdded:Fire(newcomer);newcomer.OnClientEvent:Fire("final rules")
            piece.Parent=nil
            for i,child in ipairs(board.children) do if child==piece then table.remove(board.children,i);break end end
        elseif waits==3 then env.ShitaroFinishCheckersResearch() end
    end
    -- Put the same piece back before repeating the capture.
    if not piece.Parent then piece.Parent=board;board.children[#board.children+1]=piece end
    piece.Position=vec(2,0,2);turn.Value="Local";label.Text="American Checkers"
    dofile("diagnostics/checkers_research.lua")
    local r=assert(env.ShitaroCheckersResearchReport)
    assert(copied==r and r:find("END OF REPORT",1,true))
    assert(r:find("seat=#",1,true) and r:find("group=near_part",1,true))
    assert(r:find("pos=3.00,0.00,3.00",1,true) and r:find('value="Enemy"',1,true))
    assert(r:find('text="Checkers with Skips"',1,true))
    assert(r:find('NOT_OBSERVED',1,true),"disappeared pieces must be recorded")
    assert(r:find('remote=#',1,true) and r:find('ReplicatedStorage.NewVote',1,true))
    assert(r:find('token=<redacted>',1,true) and not r:find('secret-test',1,true))
    assert(not r:find('private message',1,true) and not r:find('private typing',1,true))
    assert(not env.ShitaroFinishCheckersResearch)
    assert(r:find("observedEvents=47",1,true) or enabled)
    assert(select(2,r:gsub("direction=IN remote=#%d+:ReplicatedStorage.Move", ""))==40)
    if enabled then
        -- This remote hit its cap, but other remotes are independently recorded.
        assert(env.ShitaroCheckersResearchHook.sink==nil and originalCalls==1)
        currentMethod="InvokeServer";local a,b,c=namecallHook(other,"after")
        assert(a=="forwarded" and b==nil and c==42 and originalCalls==2)
        local ok,err=pcall(namecallHook,other,"raise")
        assert(not ok and tostring(err):find("original failure",1,true),"original errors must propagate")
        assert(r:find("hook remains installed",1,true))
    else assert(r:find("disabled; outgoing calls not captured",1,true)) end
    return r
end
run(false)
local result=run(true)
assert(result:find("direction=OUT/FireServer",1,true), "outgoing call should be observed")
assert(disconnected>0)
-- Exercise the actual in-game stop button using mock GUI instances.
local madeGui, clicked, buttonDisconnected
Instance={new=function(class)
    local inst={ClassName=class}
    if class=="ScreenGui" then madeGui=inst;function inst:Destroy() self.destroyed=true end end
    if class=="TextButton" then inst.MouseButton1Click={Connect=function(_,fn)
        clicked=fn;return {Disconnect=function() buttonDisconnected=true end}
    end} end
    return inst
end}
UDim2={fromOffset=function(...) return {...} end,new=function(...) return {...} end}
Color3={fromRGB=function(...) return {...} end}
env.ShitaroCheckersResearchConfig={CaptureOutgoing=false}
function task.wait() assert(clicked)() end
copied=nil;dofile("diagnostics/checkers_research.lua")
assert(madeGui.destroyed and buttonDisconnected and copied==env.ShitaroCheckersResearchReport)
Instance=nil
-- Missing hook support and all output failures still leave an in-memory report.
env.ShitaroCheckersResearchHook=nil;hookmetamethod=nil
writefile=function() error("disk unavailable") end;setclipboard=nil;toclipboard=nil
env.ShitaroCheckersResearchConfig={CaptureOutgoing=true}
function task.wait() env.ShitaroFinishCheckersResearch() end
dofile("diagnostics/checkers_research.lua")
local fallback=assert(env.ShitaroCheckersResearchReport)
assert(fallback:find("unavailable; outgoing calls not captured",1,true))
local reported=false
for _,message in ipairs(printed) do if message==fallback then reported=true end end
assert(reported,"report must be printed if file and clipboard fail")
io.write("PASS: checkers research capture, limits, privacy, stop, fallback and optional hook\n")
