-- Speed, longer jumps and local slow fall. Disabled until explicitly enabled.
return function(ctx)
    local player,gui,uiState=ctx.player,ctx.gui,ctx.uiState
    local RunService=ctx.RunService
    local Workspace=game:GetService("Workspace")
    local controllerFactory=ctx.Loader.module("core/movement_controller.lua")
    local contactFactory=ctx.Loader.module("core/contact_push.lua")
    local make,connect,corner=ctx.make,ctx.connect,ctx.corner
    local colors=ctx.colors
    local fallRoot,fallAttachment,fallForce
    local fallWarning=false
    local contactWarning=false

    local function clearFall()
        if fallForce then pcall(function() fallForce:Destroy() end) end
        if fallAttachment then pcall(function() fallAttachment:Destroy() end) end
        fallForce=nil;fallAttachment=nil;fallRoot=nil
    end
    local adapter={}
    function adapter.resolve()
        local char=player.Character
        local hum=char and char:FindFirstChildOfClass("Humanoid")
        local root=char and char:FindFirstChild("HumanoidRootPart")
        if not char or not char.Parent or not hum or not hum.Parent or hum.Health<=0
            or not root or not root.Parent or not root:IsA("BasePart") then return nil,nil end
        return hum,root
    end
    function adapter.suspended() return uiState.closed or uiState.freeCamera==true end
    function adapter.gravity() return Workspace.Gravity end
    function adapter.shouldSlowFall(hum,root)
        if hum.SeatPart or hum.PlatformStand or root.Anchored then return false end
        return hum:GetState()==Enum.HumanoidStateType.Freefall
            and hum.FloorMaterial==Enum.Material.Air and root.AssemblyLinearVelocity.Y < -1
    end
    function adapter.clearFall() clearFall() end
    function adapter.applyFall(root,percent)
        local ok,err=pcall(function()
            if fallRoot~=root or not fallForce or not fallForce.Parent then
                clearFall()
                fallRoot=root
                fallAttachment=Instance.new("Attachment")
                fallAttachment.Name="ShitaroSlowFallAttachment"
                fallAttachment.Parent=root
                fallForce=Instance.new("VectorForce")
                fallForce.Name="ShitaroSlowFall"
                fallForce.Attachment0=fallAttachment
                fallForce.RelativeTo=Enum.ActuatorRelativeTo.World
                fallForce.ApplyAtCenterOfMass=true
                fallForce.Parent=root
            end
            local mass=root.AssemblyMass
            if type(mass)~="number" or mass<=0 or mass==math.huge then clearFall();return end
            -- Reduced gravity eases the initial fall; a bounded damping term
            -- prevents long drops from accelerating forever. It affects only
            -- this character and never writes Workspace.Gravity or velocity.
            local gravity=Workspace.Gravity
            local descent=math.max(0,-root.AssemblyLinearVelocity.Y)
            local target=math.max(5,70*percent)
            local acceleration=gravity*(1-percent)+math.max(0,descent-target)*12
            local lift=mass*math.min(gravity*3,math.max(0,acceleration))
            fallForce.Force=Vector3.new(0,lift,0)
        end)
        if not ok then
            clearFall()
            if not fallWarning then warn("[shitaro/movement] slow fall unavailable: "..tostring(err));fallWarning=true end
        end
    end
    local movement=controllerFactory(adapter)

    -- If direct target ownership is unavailable, contact triggers a brief
    -- local spin. Either spin can throw the local avatar instead of a target.
    local contactAdapter={}
    contactAdapter.now=os.clock
    contactAdapter.suspended=adapter.suspended
    function contactAdapter.resolve()
        local h,r=adapter.resolve()
        return h and player.Character or nil,h,r
    end
    function contactAdapter.canPush(h,r)
        return h and h.Health>0 and not h.SeatPart and not h.PlatformStand and r and r.Parent and not r.Anchored
    end
    function contactAdapter.isOtherPlayerPart(part,localRoot)
        if not part or not part.Parent or not part:IsA("BasePart") then return false end
        local ancestor=part.Parent
        for _=1,16 do
            if not ancestor then return false end
            if ancestor:IsA("Model") then
                local other=ctx.Players:GetPlayerFromCharacter(ancestor)
                if other then
                    if other==player or other.Character~=ancestor then return false end
                    local h=ancestor:FindFirstChildOfClass("Humanoid")
                    local target=ancestor:FindFirstChild("HumanoidRootPart")
                    if h and h.Health>0 and target and target:IsA("BasePart") and not target.Anchored
                        and (target.Position-localRoot.Position).Magnitude<=10 then return true,target end
                    return false
                end
            end
            ancestor=ancestor.Parent
        end
        return false
    end
    function contactAdapter.watch(char,onTouch)
        local links,watched={},{}
        local function add(part)
            if watched[part] or not part:IsA("BasePart") then return end
            -- Tools and weapons can be long and should not act as touch sensors.
            if part:FindFirstAncestorOfClass("Tool") then return end
            watched[part]=true
            links[#links+1]=part.Touched:Connect(onTouch)
        end
        for _,part in ipairs(char:GetDescendants()) do add(part) end
        links[#links+1]=char.DescendantAdded:Connect(add)
        return function()
            for _,link in ipairs(links) do pcall(function() link:Disconnect() end) end
        end
    end
    -- A direct impulse is only attempted when the executor can positively
    -- verify local ownership of the other player's assembly. Most player
    -- characters are owned elsewhere; do not force or assume ownership.
    function contactAdapter.tryOwnedPush(target,localRoot)
        if type(isnetworkowner)~="function" then return false end
        local ok,owned=pcall(isnetworkowner,target)
        if not ok or owned~=true or not target.Parent or target.Anchored then return false end
        local mass=target.AssemblyMass
        if type(mass)~="number" or mass<=0 or mass>10000 then return false end
        local delta=target.Position-localRoot.Position
        local length=math.sqrt(delta.X*delta.X+delta.Z*delta.Z)
        if length<0.05 then return false end
        local impulse=Vector3.new(delta.X/length*mass*80,mass*20,delta.Z/length*mass*80)
        local did=pcall(function() target:ApplyImpulse(impulse) end)
        return did -- invocation only; server replication is not guaranteed
    end
    function contactAdapter.startSpin(root,hum)
        local attachment,actuator,upright
        local original=root.AssemblyAngularVelocity
        local oldAutoRotate=hum.AutoRotate
        local ok,err=pcall(function()
            -- Keep the humanoid's facing controller from fighting the spin.
            hum.AutoRotate=false
            attachment=Instance.new("Attachment")
            attachment.Name="ShitaroContactAttachment"
            -- Attachment's primary X axis points along the avatar's local Y.
            attachment.CFrame=CFrame.Angles(0,0,math.pi/2)
            attachment.Parent=root
            actuator=Instance.new("AngularVelocity")
            actuator.Name="ShitaroContactPush";actuator.Attachment0=attachment
            actuator.RelativeTo=Enum.ActuatorRelativeTo.World
            actuator.AngularVelocity=Vector3.new(0,600,0)
            actuator.MaxTorque=10000000;actuator.Parent=root
            -- Align only the upright axis; do not resist yaw/spinning.
            upright=Instance.new("AlignOrientation")
            upright.Name="ShitaroSpinUpright";upright.Attachment0=attachment
            upright.Mode=Enum.OrientationAlignmentMode.OneAttachment
            upright.AlignType=Enum.AlignType.PrimaryAxisParallel
            upright.PrimaryAxis=Vector3.new(0,1,0)
            upright.RigidityEnabled=false;upright.Responsiveness=40
            upright.MaxTorque=2000000;upright.MaxAngularVelocity=50
            upright.Parent=root
        end)
        if not ok then
            if upright then pcall(function() upright:Destroy() end) end
            if actuator then pcall(function() actuator:Destroy() end) end
            if attachment then pcall(function() attachment:Destroy() end) end
            pcall(function() if hum.Parent and hum.AutoRotate==false then hum.AutoRotate=oldAutoRotate end end)
            if not contactWarning then
                contactWarning=true;warn("[shitaro/movement] contact push unavailable: "..tostring(err))
            end
            return nil
        end
        return {root=root,humanoid=hum,oldAutoRotate=oldAutoRotate,
            attachment=attachment,actuator=actuator,upright=upright,original=original}
    end
    function contactAdapter.spinValid(state)
        return state.root and state.root.Parent and state.actuator and state.actuator.Parent==state.root
            and state.attachment and state.attachment.Parent==state.root
            and state.upright and state.upright.Parent==state.root
    end
    function contactAdapter.setSpinActive(state,on)
        state.actuator.AngularVelocity=Vector3.new(0,on and 600 or 0,0)
    end
    function contactAdapter.stopSpin(state)
        if state.upright then pcall(function() state.upright:Destroy() end) end
        if state.actuator then pcall(function() state.actuator:Destroy() end) end
        if state.attachment then pcall(function() state.attachment:Destroy() end) end
        pcall(function()
            if state.humanoid and state.humanoid.Parent and state.humanoid.AutoRotate==false then
                state.humanoid.AutoRotate=state.oldAutoRotate
            end
        end)
        -- Do not leave our own character spinning. Preserve X/Z and only
        -- correct a high positive Y spin consistent with our actuator.
        pcall(function()
            local r=state.root
            if r and r.Parent and not r.Anchored then
                local v=r.AssemblyAngularVelocity
                if v.Y>10 then
                    local oldY=math.max(-20,math.min(20,state.original.Y))
                    r.AssemblyAngularVelocity=Vector3.new(v.X,oldY,v.Z)
                end
            end
        end)
    end
    local contact=contactFactory(contactAdapter)

    local strings={
        en={ ["movement.panel"]="movement",["movement.speed"]="fast walk",
            ["movement.speedValue"]="walk speed",["movement.jump"]="long jump",
            ["movement.jumpValue"]="jump power",["movement.fall"]="slow fall",
            ["movement.fallValue"]="fall gravity",["movement.contact"]="touch push (test)",["movement.spin"]="always spin",["movement.hint"]="Spinning may throw you too." },
        ru={ ["movement.panel"]="движение",["movement.speed"]="быстрая ходьба",
            ["movement.speedValue"]="скорость",["movement.jump"]="дальний прыжок",
            ["movement.jumpValue"]="сила прыжка",["movement.fall"]="плавное падение",
            ["movement.fallValue"]="сила падения",["movement.contact"]="отталкивание (тест)",["movement.spin"]="крутиться всегда",["movement.hint"]="Вращение может отбросить и вас." },
    }
    for lang,items in pairs(strings) do
        for key,value in pairs(items) do ctx.locale[lang][key]=value end
    end

    local scroll=ctx.pageScroll(ctx.tabs[4].page,"MovementScroll")
    ctx.panelWidths[scroll]=350
    local card=ctx.previewPanel(scroll,"movement.panel",1,9)
    local function toggle(index,labelKey,field)
        local row,label=ctx.previewRow(card,index,"",true)
        ctx.localize(label,labelKey)
        local track=make("Frame",{AnchorPoint=Vector2.new(1,0.5),
            Position=UDim2.new(1,-12,0.5,0),Size=UDim2.fromOffset(26,14),
            BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=0.86,ZIndex=2},row)
        corner(track,UDim.new(1,0))
        local knob=make("Frame",{AnchorPoint=Vector2.new(0,0.5),
            Position=UDim2.new(0,2,0.5,0),Size=UDim2.fromOffset(10,10),
            BackgroundColor3=colors.sub,BackgroundTransparency=0.15,ZIndex=3},track)
        corner(knob,UDim.new(1,0))
        local hit=make("TextButton",{Name="Movement"..field.."Toggle",Size=UDim2.fromScale(1,1),ZIndex=5},row)
        connect(hit.Activated,function()
            local on
            if field=="contact" then on=not contact.enabled;contact.setEnabled(on)
            elseif field=="alwaysSpin" then on=not contact.alwaysEnabled;contact.setAlways(on)
            else on=not movement[field.."Enabled"];movement.setEnabled(field,on) end
            ctx.animate(track,{BackgroundColor3=on and colors.accent or Color3.new(1,1,1),
                BackgroundTransparency=on and 0.35 or 0.86})
            ctx.animate(knob,{Position=UDim2.new(0,on and 14 or 2,0.5,0),
                BackgroundColor3=on and colors.accent or colors.sub})
        end)
    end
    local function slider(index,labelKey,field,min,max,suffix)
        local row,label=ctx.previewRow(card,index,"",true)
        ctx.localize(label,labelKey)
        local slider=ctx.rowSlider(row,"Movement"..field,min,max,function(v)
            return tostring(math.floor(v+0.5))..suffix
        end,function(v)
            movement.setValue(field,math.floor(v+0.5))
            movement.step()
        end)
        slider.set(movement[field],false)
    end
    toggle(1,"movement.speed","speed")
    slider(2,"movement.speedValue","speed",1,200,"")
    toggle(3,"movement.jump","jump")
    slider(4,"movement.jumpValue","jumpPower",20,140,"")
    toggle(5,"movement.fall","fall")
    slider(6,"movement.fallValue","fallPercent",10,100,"%")
    toggle(7,"movement.contact","contact")
    toggle(8,"movement.spin","alwaysSpin")
    local _,hint=ctx.previewRow(card,9,"",true)
    hint.Size=UDim2.new(1,-24,1,0);hint.TextSize=11;hint.TextWrapped=true
    ctx.localize(hint,"movement.hint")
    ctx.layoutPreview()

    connect(RunService.Heartbeat,function()
        if uiState.closed then movement.shutdown();contact.shutdown();return end
        local ok,err=pcall(movement.step)
        if not ok and not fallWarning then
            fallWarning=true;warn("[shitaro/movement] update failed: "..tostring(err))
        end
        local contactOk,contactErr=pcall(contact.step)
        if not contactOk and not contactWarning then
            contactWarning=true;warn("[shitaro/movement] contact update failed: "..tostring(contactErr))
        end
    end)
    -- The hub's shared Destroying handler disconnects ctx connections first.
    -- Use a separate listener so shutdown still restores properties and forces.
    gui.Destroying:Connect(function() movement.shutdown();contact.shutdown() end)
end
