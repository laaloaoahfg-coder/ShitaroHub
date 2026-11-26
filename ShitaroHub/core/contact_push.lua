-- Opt-in ownership-checked contact impulse and independent local spin.
-- The adapter owns subscriptions and physics; no ownership is forced.
return function(adapter)
    local c={enabled=false,alwaysEnabled=false}
    local character,humanoid,root,disconnect,spin
    local nextAllowed,alwaysRetryAt=0,0
    local closed=false
    local function stopSpin()
        if spin then pcall(adapter.stopSpin,spin);spin=nil end
    end
    local function stopWatching()
        if disconnect then pcall(disconnect);disconnect=nil end
    end
    local function unbind()
        stopSpin();stopWatching()
        character,humanoid,root=nil,nil,nil
    end
    local function startSpin()
        stopSpin()
        local ok,result=pcall(adapter.startSpin,root,humanoid)
        if not ok or not result then return false end
        spin=result
        return true
    end
    local function touched(otherPart)
        if closed or not c.enabled or not root or adapter.suspended() then return end
        local char,h,r=adapter.resolve()
        if char~=character or h~=humanoid or r~=root or not adapter.canPush(h,r) then return end
        local now=adapter.now()
        if now<nextAllowed then return end
        local eligible,target=adapter.isOtherPlayerPart(otherPart,r)
        if not eligible then return end
        -- Never fall back to spinning our own character on touch: that can
        -- throw the user instead. Rate-limit even failed/unavailable attempts.
        nextAllowed=now+1
        if adapter.tryOwnedPush and target then pcall(adapter.tryOwnedPush,target,r) end
    end
    function c.step()
        if closed then return end
        if not c.enabled and not c.alwaysEnabled then unbind();return end
        local char,h,r=adapter.resolve()
        if char~=character or h~=humanoid or r~=root then
            unbind();character,humanoid,root=char,h,r;alwaysRetryAt=0
        end
        if character and humanoid and root and c.enabled and not disconnect then
            local watchedChar,watchedHum,watchedRoot=character,humanoid,root
            disconnect=adapter.watch(character,function(part)
                if character==watchedChar and humanoid==watchedHum and root==watchedRoot then touched(part) end
            end)
        elseif not c.enabled then
            stopWatching()
        end
        if adapter.suspended() or not humanoid or not root or not adapter.canPush(humanoid,root) then
            stopSpin();return
        end
        local now=adapter.now()
        if spin and adapter.spinValid then
            local ok,valid=pcall(adapter.spinValid,spin)
            if not ok or not valid then
                stopSpin()
                -- Avoid fighting a game that keeps removing the actuator.
                if c.alwaysEnabled then alwaysRetryAt=now+1 end
            end
        end
        if c.alwaysEnabled then
            if not spin and now>=alwaysRetryAt then
                if not startSpin() then alwaysRetryAt=now+1 end
            end
        elseif spin then
            stopSpin()
        end
    end
    function c.setEnabled(enabled)
        if closed then return end
        c.enabled=enabled==true
        c.step()
    end
    function c.setAlways(enabled)
        if closed then return end
        c.alwaysEnabled=enabled==true;alwaysRetryAt=0
        c.step()
    end
    function c.shutdown()
        if closed then return end
        c.enabled=false;c.alwaysEnabled=false;closed=true;unbind()
    end
    return c
end
