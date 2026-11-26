-- Opt-in contact impulse experiment. Does not alter another player's character.
-- The adapter owns Roblox event subscriptions and the local transient actuator.
return function(adapter)
    local c={enabled=false}
    local character,humanoid,root,disconnect,spin
    local spinUntil,nextAllowed=0,0
    local closed=false
    local function stopSpin()
        if spin then pcall(adapter.stopSpin,spin);spin=nil end
        spinUntil=0
    end
    local function unbind()
        stopSpin()
        if disconnect then pcall(disconnect);disconnect=nil end
        character,humanoid,root=nil,nil,nil
    end
    local function touched(otherPart)
        if closed or not c.enabled or not root or adapter.suspended() then return end
        local char,h,r=adapter.resolve()
        if char~=character or h~=humanoid or r~=root or not adapter.canPush(h,r) then return end
        local now=adapter.now()
        if now<nextAllowed or not adapter.isOtherPlayerPart(otherPart,r) then return end
        stopSpin()
        local ok,result=pcall(adapter.startSpin,r)
        if ok and result then
            spin=result
            spinUntil=now+0.25;nextAllowed=now+1
        end
    end
    function c.step()
        if closed then return end
        if not c.enabled then unbind();return end
        local char,h,r=adapter.resolve()
        if char~=character or h~=humanoid or r~=root then
            unbind();character,humanoid,root=char,h,r
            if char and h and r then
                local watchedChar,watchedHum,watchedRoot=char,h,r
                disconnect=adapter.watch(char,function(part)
                    if character==watchedChar and humanoid==watchedHum and root==watchedRoot then touched(part) end
                end)
            end
        end
        if spin and (adapter.suspended() or not humanoid or not root
            or not adapter.canPush(humanoid,root) or adapter.now()>=spinUntil) then stopSpin() end
    end
    function c.setEnabled(enabled)
        if closed then return end
        c.enabled=enabled==true
        c.step()
    end
    function c.shutdown()
        if closed then return end
        c.enabled=false;closed=true;unbind()
    end
    return c
end
