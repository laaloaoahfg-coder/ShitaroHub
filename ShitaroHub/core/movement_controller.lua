-- Local character movement controls. The adapter supplies Roblox-specific
-- character lookup and fall assistance, making lifecycle behavior testable.
return function(adapter)
    local c={speedEnabled=false,jumpEnabled=false,fallEnabled=false,
        speed=32,jumpPower=70,fallPercent=35}
    local humanoid,root
    local owned={}
    local closed=false

    local function read(h,property)
        local ok,value=pcall(function() return h[property] end)
        if ok and type(value)=="number" then return value end
    end
    local function restore(property)
        local record=owned[property]
        if not record then return end
        if humanoid and humanoid.Parent then
            local current=read(humanoid,property)
            -- Do not undo a later change made by the game or another feature.
            if current and math.abs(current-record.written)<0.001 then
                pcall(function() humanoid[property]=record.original end)
            end
        end
        owned[property]=nil
    end
    local function releaseCharacter()
        adapter.clearFall()
        restore("WalkSpeed");restore("JumpPower");restore("JumpHeight")
        humanoid=nil;root=nil
    end
    local function write(property,value)
        local current=read(humanoid,property)
        if not current then return end
        local record=owned[property]
        if not record then
            record={original=current,written=value};owned[property]=record
        elseif math.abs(current-record.written)>0.001 then
            -- Preserve the latest external value, not a stale initial default.
            record.original=current
        end
        if math.abs(current-value)>0.001 then
            local ok=pcall(function() humanoid[property]=value end)
            if not ok then owned[property]=nil;return end
        end
        record.written=value
    end
    local limits={speed={1,200},jumpPower={20,140},fallPercent={10,100}}
    function c.setValue(name,value)
        local range=limits[name]
        if not range or type(value)~="number" or value~=value then return false end
        c[name]=math.max(range[1],math.min(range[2],value))
        return true
    end
    function c.setEnabled(name,value)
        if name~="speed" and name~="jump" and name~="fall" then return false end
        c[name.."Enabled"]=value==true
        c.step()
        return true
    end
    function c.step()
        if closed then return end
        local h,r=adapter.resolve()
        if h~=humanoid or r~=root then
            releaseCharacter()
            humanoid,root=h,r
        end
        if not humanoid or not root then return end
        if not c.speedEnabled then restore("WalkSpeed") end
        if not c.jumpEnabled then restore("JumpPower");restore("JumpHeight") end
        if adapter.suspended() then
            adapter.clearFall()
            return
        end
        if c.speedEnabled then write("WalkSpeed",c.speed) end
        if c.jumpEnabled then
            if humanoid.UseJumpPower then
                restore("JumpHeight");write("JumpPower",c.jumpPower)
            else
                restore("JumpPower")
                local gravity=math.max(1,adapter.gravity())
                write("JumpHeight",c.jumpPower*c.jumpPower/(2*gravity))
            end
        end
        if c.fallEnabled and adapter.shouldSlowFall(humanoid,root) then
            adapter.applyFall(root,c.fallPercent/100)
        else
            adapter.clearFall()
        end
    end
    function c.shutdown()
        if closed then return end
        closed=true;releaseCharacter()
    end
    return c
end
