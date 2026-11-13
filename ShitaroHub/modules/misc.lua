-- modules/misc.lua - character spin and Space-held momentum bunny hop.
-- Character physics only: no camera spin, remotes, or replication spoofing.
-- Other clients see rotation only if the game's server replicates this client.
return function(ctx)
    local player, RunService, gui = ctx.player, ctx.RunService, ctx.gui
    local Input = ctx.UserInputService
    local cfg = {
        spin = false,
        spinSpeed = 360, -- degrees/second
        bhop = false,
        hopBoost = 8, -- horizontal studs/second added per confirmed takeoff
    }
    local LIMITS = {
        speedMin = 30, speedMax = 1440,
        boostMin = 0, boostMax = 50,
        hopSpeedLimit = 120, -- chosen planar speed cap; not a game constant
        takeoffGrace = 0.25, -- allow floor/state/vertical velocity to settle
        jumpCooldown = 0.15,
        maxStep = 0.1,
    }
    local closed = false
    local spinOwner, hopOwner
    local focused = true
    local stepLink
    local paintSpin, paintBhop

    local extra = {
        en = {
            ["misc.movement"] = "movement",
            ["misc.spin"] = "spin",
            ["misc.spinSpeed"] = "spin speed",
            ["misc.bhop"] = "bunny hop",
            ["misc.hopBoost"] = "hop acceleration",
            ["misc.notice"] = "Bhop: hold Space + move. Spin rotates in one direction.",
        },
        ru = {
            ["misc.movement"] = "движение",
            ["misc.spin"] = "крутилка",
            ["misc.spinSpeed"] = "скорость вращения",
            ["misc.bhop"] = "банихоп",
            ["misc.hopBoost"] = "сила разгона",
            ["misc.notice"] = "Банихоп: удерживай пробел + двигайся. Spin вращается в одну сторону.",
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

    local function releaseHop()
        -- No jump-height, WalkSpeed or velocity override is held between hops.
        hopOwner = nil
    end

    local function releaseAll()
        releaseSpin()
        releaseHop()
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
                angle = 0,
            }
        end
        local owner = spinOwner
        if hum.AutoRotate ~= owner.written then
            owner.original = hum.AutoRotate
            hum.AutoRotate = owner.written
        end

        -- Keep a fixed positive yaw direction, including across full turns.
        -- Position and velocity remain untouched; speed is degrees/second.
        owner.angle = (owner.angle + math.rad(cfg.spinSpeed) * dt) % (2 * math.pi)
        root.CFrame = CFrame.new(root.Position)
            * CFrame.Angles(0, owner.angle, 0) * owner.basis
    end

    local function boostTakeoff(hum, root)
        if cfg.hopBoost <= 0 then return end
        local move = hum.MoveDirection
        local direction = Vector3.new(move.X, 0, move.Z)
        if direction.Magnitude < 0.01 then return end

        local velocity = root.AssemblyLinearVelocity
        local planar = Vector3.new(velocity.X, 0, velocity.Z)
        local speed = planar.Magnitude
        if speed >= LIMITS.hopSpeedLimit then return end
        local accelerated = planar + direction.Unit * cfg.hopBoost
        if accelerated.Magnitude > LIMITS.hopSpeedLimit then
            accelerated = accelerated.Unit * LIMITS.hopSpeedLimit
        end
        -- Preserve the engine's vertical impulse. This is a horizontal impulse
        -- ONCE per confirmed takeoff, never an increased jump height.
        root.AssemblyLinearVelocity = Vector3.new(
            accelerated.X, velocity.Y, accelerated.Z
        )
    end

    local function updateBhop(hum, root, dt)
        local state = hum:GetState()
        local groundedState = state == Enum.HumanoidStateType.Running
            or state == Enum.HumanoidStateType.RunningNoPhysics
            or state == Enum.HumanoidStateType.Landed
        local onFloor = hum.FloorMaterial ~= Enum.Material.Air
        local grounded = onFloor and groundedState
        if not hopOwner or hopOwner.hum ~= hum or hopOwner.root ~= root then
            hopOwner = {hum = hum, root = root, armed = grounded,
                cooldown = 0, airTime = 0}
        end
        local owner = hopOwner
        owner.cooldown = math.max(0, owner.cooldown - dt)
        local held = focused and Input:IsKeyDown(Enum.KeyCode.Space)
            and Input:GetFocusedTextBox() == nil
        local jumpAllowed = hum:GetStateEnabled(Enum.HumanoidStateType.Jumping)

        if grounded then
            -- Tracking the ground even while Space is released lets the normal
            -- Roblox Space jump be recognised if it starts before our callback.
            owner.armed = true
            owner.airTime = 0
            if not held then owner.cooldown = 0; return end
            if jumpAllowed and owner.cooldown <= 0 then
                hum:ChangeState(Enum.HumanoidStateType.Jumping)
                owner.cooldown = LIMITS.jumpCooldown
            end
            return
        end

        if not held or not jumpAllowed then
            owner.armed = false
            return
        end
        if not onFloor and owner.armed then
            owner.airTime = owner.airTime + dt
            local vertical = root.AssemblyLinearVelocity.Y
            if (state == Enum.HumanoidStateType.Jumping
                or state == Enum.HumanoidStateType.Freefall) and vertical > 0 then
                owner.armed = false
                boostTakeoff(hum, root)
            elseif vertical < 0 or owner.airTime > LIMITS.takeoffGrace then
                -- Walking off a ledge, a denied jump or an expired takeoff
                -- cannot repeatedly build speed while the player is airborne.
                owner.armed = false
            end
        end
    end

    local function stopFeature(name, message)
        if name == "spin" then
            cfg.spin = false
            releaseSpin()
            if paintSpin then paintSpin(false) end
        else
            cfg.bhop = false
            releaseHop()
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
            local ok, err = pcall(updateBhop, hum, root, dt)
            if not ok then stopFeature("bhop", err) end
        else
            releaseHop()
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
        releaseHop()
    end)

    local boostRow, boostLabel = ctx.previewRow(card, 4, "", true)
    ctx.localize(boostLabel, "misc.hopBoost")
    local boostSlider = ctx.rowSlider(boostRow, "MiscHopBoost",
        LIMITS.boostMin, LIMITS.boostMax,
        function(value) return "+" .. math.floor(value + 0.5) end,
        function(value) cfg.hopBoost = math.floor(value + 0.5) end)
    boostSlider.set(cfg.hopBoost, false)

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

    ctx.connect(Input.WindowFocusReleased, function()
        focused = false
        releaseHop()
    end)
    ctx.connect(Input.WindowFocused, function()
        focused = true
        releaseHop()
    end)
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
