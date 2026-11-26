-- Speed, longer jumps and local slow fall. Disabled until explicitly enabled.
return function(ctx)
    local player,gui,uiState=ctx.player,ctx.gui,ctx.uiState
    local RunService=ctx.RunService
    local Workspace=game:GetService("Workspace")
    local controllerFactory=ctx.Loader.module("core/movement_controller.lua")
    local make,connect,corner=ctx.make,ctx.connect,ctx.corner
    local colors=ctx.colors
    local fallRoot,fallAttachment,fallForce
    local fallWarning=false

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

    local strings={
        en={ ["movement.panel"]="movement",["movement.speed"]="fast walk",
            ["movement.speedValue"]="walk speed",["movement.jump"]="long jump",
            ["movement.jumpValue"]="jump power",["movement.fall"]="slow fall",
            ["movement.fallValue"]="fall gravity",["movement.hint"]="Local changes; the game may limit them." },
        ru={ ["movement.panel"]="движение",["movement.speed"]="быстрая ходьба",
            ["movement.speedValue"]="скорость",["movement.jump"]="дальний прыжок",
            ["movement.jumpValue"]="сила прыжка",["movement.fall"]="плавное падение",
            ["movement.fallValue"]="сила падения",["movement.hint"]="Локально; игра может ограничивать." },
    }
    for lang,items in pairs(strings) do
        for key,value in pairs(items) do ctx.locale[lang][key]=value end
    end

    local scroll=ctx.pageScroll(ctx.tabs[4].page,"MovementScroll")
    ctx.panelWidths[scroll]=350
    local card=ctx.previewPanel(scroll,"movement.panel",1,7)
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
            local on=not movement[field.."Enabled"]
            movement.setEnabled(field,on)
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
    slider(2,"movement.speedValue","speed",1,120,"")
    toggle(3,"movement.jump","jump")
    slider(4,"movement.jumpValue","jumpPower",20,140,"")
    toggle(5,"movement.fall","fall")
    slider(6,"movement.fallValue","fallPercent",10,100,"%")
    local _,hint=ctx.previewRow(card,7,"",true)
    hint.Size=UDim2.new(1,-24,1,0);hint.TextSize=11;hint.TextWrapped=true
    ctx.localize(hint,"movement.hint")
    ctx.layoutPreview()

    connect(RunService.Heartbeat,function()
        if uiState.closed then movement.shutdown();return end
        local ok,err=pcall(movement.step)
        if not ok and not fallWarning then
            fallWarning=true;warn("[shitaro/movement] update failed: "..tostring(err))
        end
    end)
    -- The hub's shared Destroying handler disconnects ctx connections first.
    -- Use a separate listener so shutdown still restores properties and forces.
    gui.Destroying:Connect(function() movement.shutdown() end)
end
