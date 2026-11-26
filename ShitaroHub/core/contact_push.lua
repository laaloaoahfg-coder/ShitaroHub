-- Opt-in contact experiment and continuous local spin. No ownership is forced.
-- Spinning can throw the local character as well as (or instead of) a target.
return function(adapter)
    local c={enabled=false,alwaysEnabled=false}
    local character,humanoid,root,disconnect,spin,spinMode
    local nextAllowed,spinUntil,alwaysRetryAt=0,0,0
    local spinStarted,pulseOn=0,nil
    local closed=false
    local function stopSpin()
        if spin then pcall(adapter.stopSpin,spin);spin=nil end
        spinMode=nil;spinUntil=0;spinStarted=0;pulseOn=nil
    end
    local function stopWatching()
        if disconnect then pcall(disconnect);disconnect=nil end
    end
    local function unbind()
        stopSpin();stopWatching()
        character,humanoid,root=nil,nil,nil
    end
    local function startSpin(mode,now)
        stopSpin()
        local ok,result=pcall(adapter.startSpin,root,humanoid)
        if not ok or not result then return false end
        spin=result;spinMode=mode;spinStarted=now;pulseOn=true
        if mode=="contact" then spinUntil=now+0.6 end
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
        -- Prefer a direct push only when ownership can be verified. Otherwise
        -- briefly spin our own character: collision results are unpredictable.
        -- Rate-limit even failed attempts and never stack two spin actuators.
        nextAllowed=now+1
        local attempted=false
        if adapter.tryOwnedPush and target then
            local ok,result=pcall(adapter.tryOwnedPush,target,r)
            attempted=ok and result==true
        end
        if not attempted and not c.alwaysEnabled then startSpin("contact",now) end
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
            if spinMode~="always" and now>=alwaysRetryAt then
                if not startSpin("always",now) then alwaysRetryAt=now+1 end
            end
        elseif spinMode=="always" or (spinMode=="contact" and now>=spinUntil) then
            stopSpin()
        end
        if spin and adapter.setSpinActive then
            -- Periodic target changes, not a guarantee of actual angular speed.
            -- Use elapsed time, not queued tasks, so shutdown cannot restart it.
            local on=((now-spinStarted)%0.3)<0.2
            if on~=pulseOn then
                local ok=pcall(adapter.setSpinActive,spin,on)
                if ok then pulseOn=on else
                    stopSpin()
                    if c.alwaysEnabled then alwaysRetryAt=now+1 end
                end
            end
        end
    end
    function c.setEnabled(enabled)
        if closed then return end
        c.enabled=enabled==true
        if not c.enabled and spinMode=="contact" then stopSpin() end
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
