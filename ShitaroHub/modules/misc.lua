-- modules/misc.lua - character spin and automatic bunny hop.
-- Character physics only: no camera spin, remotes, or replication spoofing.
-- Other clients see rotation only if the game's server replicates this client.
return function(ctx)
    local player, RunService, gui = ctx.player, ctx.RunService, ctx.gui
    local Workspace = game:GetService("Workspace")
    local cfg = {
        spin = false,
        spinSpeed = 360, -- degrees/second
        bhop = false,
        jumpPower = 50, -- studs/second equivalent in either jump mode
    }
    local LIMITS = {
        speedMin = 30, speedMax = 1440,
        powerMin = 10, powerMax = 150,
        reverseEvery = 1.5, -- seconds: alternate left/right
        jumpCooldown = 0.15,
        maxStep = 0.1,
    }
    local closed = false
    local spinOwner, jumpOwner
    local cooldown = 0
    local stepLink
    local paintSpin, paintBhop

    local extra = {
        en = {
            ["misc.movement"] = "movement",
            ["misc.spin"] = "spin",
            ["misc.spinSpeed"] = "spin speed",
            ["misc.bhop"] = "bunny hop",
            ["misc.jumpPower"] = "jump power",
            ["misc.notice"] = "Spin alternates left/right. Server rules may limit movement.",
        },
        ru = {
            ["misc.movement"] = "движение",
            ["misc.spin"] = "крутилка",
            ["misc.spinSpeed"] = "скорость вращения",
            ["misc.bhop"] = "банихоп",
            ["misc.jumpPower"] = "сила прыжка",
            ["misc.notice"] = "Spin меняет направление. Сервер может ограничивать движение.",
        },
    }
    for language, pack in pairs(extra) do
        for key, value in pairs(pack) do
            ctx.locale[language][key] = value
        end
    end

    -- Restore only a value we still own. Do not overwrite a newer game value.
    local function releaseSpin()
        local owner = spinOwner
        spinOwner = nil
        if owner then
            pcall(function()
                if owner.hum.Parent and owner.hum.AutoRotate == owner.written then
                    owner.hum.AutoRotate = owner.original
                end
            end)
        end
    end

    local function releaseJump()
        local owner = jumpOwner
        jumpOwner = nil
        if owner then
            pcall(function()
                if owner.hum.Parent and owner.hum[owner.field] == owner.written then
                    owner.hum[owner.field] = owner.original
                end
            end)
        end
    end

    local function releaseAll()
        releaseSpin()
        releaseJump()
        cooldown = 0
    end

    local function liveCharacter()
        local char = player.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local root = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
        if not char or not char.Parent or not hum or not hum.Parent
            or hum.Health <= 0 or not root or not root:IsA("BasePart")
            or root.Parent ~= char then
            return nil
        end
        local state = hum:GetState()
        if state == Enum.HumanoidStateType.Dead
            or state == Enum.HumanoidStateType.Seated
            or state == Enum.HumanoidStateType.Swimming
            or state == Enum.HumanoidStateType.Climbing
            or state == Enum.HumanoidStateType.Physics
            or state == Enum.HumanoidStateType.Ragdoll
            or hum.Sit or hum.PlatformStand
            or char:GetAttribute("Dead") == true
            or char:GetAttribute("IsDead") == true then
            return nil
        end
        return char, hum, root
    end

    local function updateSpin(hum, root, dt)
        if spinOwner and (spinOwner.hum ~= hum or spinOwner.root ~= root) then
            releaseSpin()
        end
        if not spinOwner then
            spinOwner = {
                hum = hum, root = root,
                original = hum.AutoRotate, written = false,
                basis = root.CFrame - root.Position,
                angle = 0, phase = 0, direction = 1,
            }
        end
        local owner = spinOwner
        if hum.AutoRotate ~= owner.written then
            owner.original = hum.AutoRotate
            hum.AutoRotate = owner.written
        end

        -- Integrate each side of a reversal separately, including a frame
        -- that crosses the boundary. Position and velocity remain untouched.
        local remaining = dt
        while remaining > 1e-7 do
            local slice = math.min(remaining, LIMITS.reverseEvery - owner.phase)
            owner.angle = (owner.angle
                + math.rad(cfg.spinSpeed) * owner.direction * slice) % (2 * math.pi)
            owner.phase = owner.phase + slice
            remaining = remaining - slice
            if owner.phase >= LIMITS.reverseEvery - 1e-7 then
                owner.phase = 0
                owner.direction = -owner.direction
            end
        end
        root.CFrame = CFrame.new(root.Position)
            * CFrame.Angles(0, owner.angle, 0) * owner.basis
    end

    local function setJumpValue(hum, field, value)
        if jumpOwner and (jumpOwner.hum ~= hum or jumpOwner.field ~= field) then
            releaseJump()
        end
        if not jumpOwner then
            jumpOwner = {hum = hum, field = field, original = hum[field]}
        end
        local actual = hum[field]
        if jumpOwner.written ~= nil and actual ~= jumpOwner.written then
            -- Remember buffs/debuffs the game applied while the feature ran.
            jumpOwner.original = actual
        end
        hum[field] = value
        jumpOwner.written = value
    end

    local function updateBhop(hum, dt)
        cooldown = math.max(0, cooldown - dt)
        local power = cfg.jumpPower
        if hum.UseJumpPower then
            setJumpValue(hum, "JumpPower", power)
        else
            local gravity = Workspace.Gravity
            if type(gravity) ~= "number" or gravity <= 0
                or gravity ~= gravity or gravity == math.huge then
                releaseJump()
                return
            end
            setJumpValue(hum, "JumpHeight", power * power / (2 * gravity))
        end

        local state = hum:GetState()
        local groundedState = state == Enum.HumanoidStateType.Running
            or state == Enum.HumanoidStateType.RunningNoPhysics
            or state == Enum.HumanoidStateType.Landed
        if cooldown <= 0 and groundedState
            and hum.FloorMaterial ~= Enum.Material.Air
            and hum:GetStateEnabled(Enum.HumanoidStateType.Jumping) then
            -- Request a normal humanoid jump; never boost velocity in the air.
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
            cooldown = LIMITS.jumpCooldown
        end
    end

    local function stopFeature(name, message)
        if name == "spin" then
            cfg.spin = false
            releaseSpin()
            if paintSpin then paintSpin(false) end
        else
            cfg.bhop = false
            releaseJump()
            cooldown = 0
            if paintBhop then paintBhop(false) end
        end
        warn("[shitaro/misc] " .. name .. " disabled: " .. tostring(message))
    end

    local function step(dt)
        if closed or ctx.uiState.closed then
            releaseAll()
            return
        end
        if not cfg.spin and not cfg.bhop then return end
        if type(dt) ~= "number" or dt ~= dt then return end
        dt = math.clamp(dt, 0, LIMITS.maxStep)
        local _, hum, root = liveCharacter()
        if not hum or root.Anchored or ctx.uiState.freeCamera then
            releaseAll()
            return
        end
        if cfg.spin then
            local ok, err = pcall(updateSpin, hum, root, dt)
            if not ok then stopFeature("spin", err) end
        else
            releaseSpin()
        end
        if cfg.bhop then
            local ok, err = pcall(updateBhop, hum, dt)
            if not ok then stopFeature("bhop", err) end
        else
            releaseJump()
        end
    end

    -- Build using the existing controls, layout and live RU/EN localisation.
    local scroll = ctx.pageScroll(ctx.tabs[4].page, "MiscScroll")
    ctx.panelWidths[scroll] = 330
    local card = ctx.previewPanel(scroll, "misc.movement", 1, 7)

    local function toggle(frame, initial, onChange)
        local value = initial
        local track = ctx.make("Frame", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -12, 0.5, 0),
            Size = UDim2.fromOffset(26, 14),
            ZIndex = 2,
        }, frame)
        ctx.corner(track, UDim.new(1, 0))
        local knob = ctx.make("Frame", {
            AnchorPoint = Vector2.new(0, 0.5),
            Size = UDim2.fromOffset(10, 10),
            BackgroundTransparency = 0.15,
            ZIndex = 3,
        }, track)
        ctx.corner(knob, UDim.new(1, 0))
        local function paint(on)
            value = on
            ctx.animate(track, {
                BackgroundColor3 = on and ctx.colors.accent or Color3.new(1, 1, 1),
                BackgroundTransparency = on and 0.35 or 0.86,
            })
            ctx.animate(knob, {
                Position = UDim2.new(0, on and 14 or 2, 0.5, 0),
                BackgroundColor3 = on and ctx.colors.accent or ctx.colors.sub,
            })
        end
        local hit = ctx.make("TextButton", {
            Size = UDim2.fromScale(1, 1),
            Text = "", ZIndex = 5,
        }, frame)
        ctx.connect(hit.Activated, function()
            paint(not value)
            onChange(value)
        end)
        paint(initial)
        return paint
    end

    local spinRow, spinLabel = ctx.previewRow(card, 1, "", true)
    ctx.localize(spinLabel, "misc.spin")
    paintSpin = toggle(spinRow, cfg.spin, function(on)
        cfg.spin = on
        if not on then releaseSpin() end
    end)

    local speedRow, speedLabel = ctx.previewRow(card, 2, "", true)
    ctx.localize(speedLabel, "misc.spinSpeed")
    local speedSlider = ctx.rowSlider(speedRow, "MiscSpinSpeed",
        LIMITS.speedMin, LIMITS.speedMax,
        function(value) return math.floor(value + 0.5) .. "°/s" end,
        function(value) cfg.spinSpeed = math.floor(value + 0.5) end)
    speedSlider.set(cfg.spinSpeed, false)

    local bhopRow, bhopLabel = ctx.previewRow(card, 3, "", true)
    ctx.localize(bhopLabel, "misc.bhop")
    paintBhop = toggle(bhopRow, cfg.bhop, function(on)
        cfg.bhop = on
        cooldown = 0
        if not on then releaseJump() end
    end)

    local powerRow, powerLabel = ctx.previewRow(card, 4, "", true)
    ctx.localize(powerLabel, "misc.jumpPower")
    local powerSlider = ctx.rowSlider(powerRow, "MiscJumpPower",
        LIMITS.powerMin, LIMITS.powerMax,
        function(value) return tostring(math.floor(value + 0.5)) end,
        function(value) cfg.jumpPower = math.floor(value + 0.5) end)
    powerSlider.set(cfg.jumpPower, false)

    local notice = ctx.make("TextLabel", {
        Position = UDim2.fromOffset(12, 124),
        Size = UDim2.new(1, -24, 0, 72),
        TextSize = 12,
        TextColor3 = ctx.colors.sub,
        TextWrapped = true,
        TextYAlignment = Enum.TextYAlignment.Top,
    }, card)
    ctx.localize(notice, "misc.notice")
    ctx.layoutPreview()

    ctx.connect(player.CharacterAdded, releaseAll)
    if player.CharacterRemoving then
        ctx.connect(player.CharacterRemoving, releaseAll)
    end
    if RunService.PreSimulation then
        stepLink = RunService.PreSimulation:Connect(step)
    else
        stepLink = RunService.Stepped:Connect(function(_, dt) step(dt) end)
    end

    -- Direct connection: ui.lua disconnects its shared connection list first.
    gui.Destroying:Connect(function()
        closed = true
        cfg.spin, cfg.bhop = false, false
        if stepLink then stepLink:Disconnect(); stepLink = nil end
        releaseAll()
    end)
end
