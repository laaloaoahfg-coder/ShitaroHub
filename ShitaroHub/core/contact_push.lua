-- Opt-in contact impulse and continuous spin. Never alters another character.
-- Both modes share one local actuator; the adapter owns subscriptions/physics.
return function(adapter)
    local c={enabled=false,alwaysEnabled=false}
    local character,humanoid,root,disconnect,spin,spinMode
    local spinUntil,nextAllowed,alwaysRetryAt=0,0,0
    local closed=false
    local function stopSpin()
        if spin then pcall(adapter.stopSpin,spin);spin=nil end
        spinMode=nil;spinUntil=0
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
        local ok,result=pcall(adapter.startSpin,root)
        if not ok or not result then return false end
        spin=result;spinMode=mode
        if mode=="contact" then spinUntil=now+0.5 end
        return true
    end
    local function touched(otherPart)
        if closed or not c.enabled or c.alwaysEnabled or not root or adapter.suspended() then return end
        local char,h,r=adapter.resolve()
        if char~=character or h~=humanoid or r~=root or not adapter.canPush(h,r) then return end
        local now=adapter.now()
        if now<nextAllowed or not adapter.isOtherPlayerPart(otherPart,r) then return end
        if startSpin("contact",now) then nextAllowed=now+1 end
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
    end
    function c.setEnabled(enabled)
        if closed then return end
        c.enabled=enabled==true
        -- A contact-triggered spin must stop as soon as contact mode is off.
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
