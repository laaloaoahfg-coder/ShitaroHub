-- Passive local physics probe. Run alongside the hub; no physics properties are changed.
-- Does not collect names, user IDs, server ID, chat, remotes, or coordinates.
local Players=game:GetService("Players")
local PhysicsService=game:GetService("PhysicsService")
local player=Players.LocalPlayer
local lines={"Shitaro contact physics v1", "Client observations only; no server outcome is proven."}
local connections={}
local start=os.clock()
local lastTouchTime=-1
local touchCount=0
local watchedCharacter,lastTarget
local function value(fn)
    local ok,result=pcall(fn)
    if not ok or result==nil then return "?" end
    return tostring(result)
end
local function number(fn)
    local ok,result=pcall(fn)
    if not ok or type(result)~="number" or result~=result or math.abs(result)==math.huge then return "?" end
    return string.format("%.1f",result)
end
local bodyNames={HumanoidRootPart=true,Head=true,Torso=true,UpperTorso=true,LowerTorso=true,
    ["Left Arm"]=true,["Right Arm"]=true,["Left Leg"]=true,["Right Leg"]=true,
    LeftUpperArm=true,LeftLowerArm=true,LeftHand=true,RightUpperArm=true,RightLowerArm=true,RightHand=true,
    LeftUpperLeg=true,LeftLowerLeg=true,LeftFoot=true,RightUpperLeg=true,RightLowerLeg=true,RightFoot=true}
local function bodyName(part)
    local ok,name=pcall(function() return part.Name end)
    return ok and bodyNames[name] and name or "other"
end
local function disconnectAll()
    for _,link in ipairs(connections) do pcall(function() link:Disconnect() end) end
    connections={}
end
local function rootOf(char)
    if not char then return nil end
    local root=char:FindFirstChild("HumanoidRootPart")
    if root and root:IsA("BasePart") and root.Parent then return root end
end
local function findOther(part,char)
    local node=part and part.Parent
    for _=1,16 do
        if not node then break end
        if node:IsA("Model") then
            local other=Players:GetPlayerFromCharacter(node)
            if other and other~=player and other.Character==node and node~=char then return other end
        end
        node=node.Parent
    end
end
local function watch(char)
    disconnectAll();watchedCharacter=char;lastTarget=nil
    if not char then return end
    local seen={}
    local function add(part)
        if seen[part] or not part:IsA("BasePart") or part:FindFirstAncestorOfClass("Tool") then return end
        seen[part]=true
        local ok,link=pcall(function() return part.Touched:Connect(function(otherPart)
            local other=findOther(otherPart,char)
            if not other then return end
            lastTarget=other
            local now=os.clock()
            if touchCount>=30 or now-lastTouchTime<0.2 then return end
            lastTouchTime=now;touchCount=touchCount+1
            local canCollide=value(function() return PhysicsService:CollisionGroupsAreCollidable(part.CollisionGroup,otherPart.CollisionGroup) end)
            lines[#lines+1]=string.format("touch t=%.2f localPart=%s otherPart=%s localCollide=%s otherCollide=%s localTouch=%s otherTouch=%s groupPairCollides=%s",
                now-start,bodyName(part),bodyName(otherPart),
                value(function() return part.CanCollide end),value(function() return otherPart.CanCollide end),
                value(function() return part.CanTouch end),value(function() return otherPart.CanTouch end),canCollide)
        end) end)
        if ok and link then connections[#connections+1]=link end
    end
    for _,part in ipairs(char:GetDescendants()) do add(part) end
    connections[#connections+1]=char.DescendantAdded:Connect(add)
end
local function owner(root)
    if type(isnetworkowner)~="function" then return "unavailable" end
    return value(function() return isnetworkowner(root) end)
end
local function nearest(root)
    local best,bestDistance
    for _,other in ipairs(Players:GetPlayers()) do
        if other~=player then
            local target=rootOf(other.Character)
            if target then
                local ok,distance=pcall(function() return (target.Position-root.Position).Magnitude end)
                if ok and (not bestDistance or distance<bestDistance) then best,bestDistance=other,distance end
            end
        end
    end
    return best
end
local function snapshot()
    local char=player.Character
    if char~=watchedCharacter then watch(char) end
    local root=rootOf(char)
    if not root then lines[#lines+1]=string.format("sample t=%.2f localRoot=missing",os.clock()-start);return end
    local hum=char:FindFirstChildOfClass("Humanoid")
    local spin=root:FindFirstChild("ShitaroContactPush")
    local target=lastTarget
    if not target or not rootOf(target.Character) then target=nearest(root);lastTarget=nil end
    local targetRoot=target and rootOf(target.Character)
    local otherLabel=lastTarget and "lastTouched" or "nearest"
    lines[#lines+1]=string.format("sample t=%.2f rig=%s state=%s localSpeed=%s localAngular=%s spinTargetY=%s localOwner=%s other=%s distance=%s otherSpeed=%s otherAngular=%s otherOwner=%s",
        os.clock()-start,value(function() return hum.RigType end),value(function() return hum:GetState() end),
        number(function() return root.AssemblyLinearVelocity.Magnitude end),number(function() return root.AssemblyAngularVelocity.Magnitude end),
        number(function() return spin.AngularVelocity.Y end),owner(root),targetRoot and otherLabel or "none",
        number(function() return (targetRoot.Position-root.Position).Magnitude end),
        number(function() return targetRoot.AssemblyLinearVelocity.Magnitude end),
        number(function() return targetRoot.AssemblyAngularVelocity.Magnitude end),targetRoot and owner(targetRoot) or "?")
end
local function finish()
    disconnectAll()
    lines[#lines+1]="touchRecords="..touchCount.." (max 30); no player names or positions collected."
    local report=table.concat(lines,"\n")
    pcall(function() getgenv().ShitaroContactPhysicsReport=report end)
    local copied=false
    local copy=type(setclipboard)=="function" and setclipboard or (type(toclipboard)=="function" and toclipboard or nil)
    if copy then copied=pcall(copy,report) end
    local saved=false
    if type(writefile)=="function" then
        saved=pcall(function()
            if type(makefolder)=="function" then
                pcall(makefolder,"ShitaroHub");pcall(makefolder,"ShitaroHub/diagnostics")
            end
            writefile("ShitaroHub/diagnostics/contact_physics.txt",report)
        end)
    end
    print("[Shitaro] Contact physics report: clipboard="..tostring(copied).." file="..tostring(saved))
    if not copied and not saved then print(report) end
end
print("[Shitaro] Contact physics recording for 20 seconds. Reproduce the contact once or twice.")
local ok=pcall(function()
    lines[#lines+1]="placeId="..value(function() return game.PlaceId end)
    -- Fixed iteration count as well as time bounds the report and runtime.
    for i=1,101 do
        snapshot()
        if i==101 or os.clock()-start>=20 then break end
        task.wait(0.2)
    end
end)
if not ok then lines[#lines+1]="probeError=sample failed" end
finish()
