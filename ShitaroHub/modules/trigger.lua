-- modules/trigger.lua - triggerbot
-- fires the equipped tool when the crosshair is already on a living player
-- returns function(ctx); ctx is built by core/ui.lua (shared UI helpers).

return function(ctx)
local locale, make, corner, colors, player, uiState, connect, RunService, gui, panelWidths, window, PANEL_RESERVE, pageScroll, tabs, previewPanel, panelGapBefore, animate, previewRow, localize, rowSlider, layoutPreview =
    ctx.locale,
    ctx.make,
    ctx.corner,
    ctx.colors,
    ctx.player,
    ctx.uiState,
    ctx.connect,
    ctx.RunService,
    ctx.gui,
    ctx.panelWidths,
    ctx.window,
    ctx.PANEL_RESERVE,
    ctx.pageScroll,
    ctx.tabs,
    ctx.previewPanel,
    ctx.panelGapBefore,
    ctx.animate,
    ctx.previewRow,
    ctx.localize,
    ctx.rowSlider,
    ctx.layoutPreview

-- Trigger -------------------------------------------------------------------
--
-- Nothing is aimed and nothing is written into anyone's state: the module only
-- asks where the crosshair already is. A shot goes out when the centre of the
-- screen is covered by a part of a living player, the range filter passes and,
-- with the visibility filter on, the ray from the camera reaches that part.
--
-- Firing is done through the equipped Tool (Tool:Activate), the same call the
-- game's own click handler makes. Executors that expose mouse1click are used as
-- a fallback when the character holds nothing.
--
-- Lives in its own xpcall closure like the other modules: it adds nothing to the
-- main chunk's 200-local budget and a failure here only warns.

xpcall(function()
    local Workspace = game:GetService("Workspace")
    local Players = game:GetService("Players")
    local UserInputService = game:GetService("UserInputService")

    -- the range slider uses metres, 1 stud = 0.28 m
    local STUDS_TO_M = 0.28

    local LIMITS = {
        delayMin = 0, delayMax = 500,
        toleranceMin = 1, toleranceMax = 60,
        rangeMin = 1, rangeMax = 2000,
    }

    local cfg = {
        enabled = false,
        visible = true,       -- needs a clear ray from the camera
        requireClick = false, -- false = fires as soon as the crosshair is on
        ignoreTeam = true,
        delay = 60,           -- ms between shots
        tolerance = 6,        -- px from the screen centre
        range = 400,          -- metres
    }

    -- locale keys live here so the main locale tables stay untouched
    local extra = {
        en = {
            ["trigger.panel"] = "trigger",
            ["trigger.filters"] = "targets",
            ["trigger.tuning"] = "tuning",
            ["trigger.enabled"] = "triggerbot",
            ["trigger.visible"] = "visibility check",
            ["trigger.requireClick"] = "only while shooting",
            ["trigger.ignoreTeam"] = "ignore teammates",
            ["trigger.delay"] = "shot delay",
            ["trigger.tolerance"] = "crosshair size",
            ["trigger.range"] = "max distance",
        },
        ru = {
            ["trigger.panel"] = "триггер",
            ["trigger.filters"] = "цели",
            ["trigger.tuning"] = "настройки",
            ["trigger.enabled"] = "триггербот",
            ["trigger.visible"] = "проверка видимости",
            ["trigger.requireClick"] = "только при стрельбе",
            ["trigger.ignoreTeam"] = "игнорировать тиммейтов",
            ["trigger.delay"] = "задержка выстрела",
            ["trigger.tolerance"] = "размер прицела",
            ["trigger.range"] = "дальность",
        },
    }

    for language, pack in pairs(extra) do
        for key, text in pairs(pack) do
            locale[language][key] = text
        end
    end

    -- Targets ------------------------------------------------------------------

    local roster = {}

    local function refreshRoster()
        local list = {}

        for _, target in ipairs(Players:GetPlayers()) do
            if target ~= player then
                list[#list + 1] = target
            end
        end

        roster = list
    end

    refreshRoster()

    -- the ESP builds the team map once per frame and shares it; fall back to
    -- the plain Team comparison when it is not there
    local function isTeammate(target)
        local shared = uiState.isTeammate

        if shared then
            return shared(target)
        end

        local mine = player.Team

        return mine ~= nil and target.Team == mine
    end

    local function isAlive(char)
        local humanoid = char and char:FindFirstChildOfClass("Humanoid")

        if not humanoid or not humanoid.Parent or humanoid.Health <= 0
            or humanoid:GetState() == Enum.HumanoidStateType.Dead then
            return nil
        end

        if char:GetAttribute("Dead") == true
            or char:GetAttribute("IsDead") == true
            or humanoid:GetAttribute("Dead") == true
            or humanoid:GetAttribute("IsDead") == true then
            return nil
        end

        return humanoid
    end

    -- visibility ---------------------------------------------------------------

    local rayParams = RaycastParams.new()

    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.IgnoreWater = true

    local filter = {}

    local function hasSight(origin, point, char)
        local cam = Workspace.CurrentCamera

        table.clear(filter)
        filter[1] = char

        if player.Character then
            filter[2] = player.Character
        end

        -- the first person arms sit on the ray; they are not cover
        if cam then
            for _, item in ipairs(cam:GetChildren()) do
                filter[#filter + 1] = item
            end
        end

        rayParams.FilterDescendantsInstances = filter

        return Workspace:Raycast(origin, point - origin, rayParams) == nil
    end

    -- Wanted part under the crosshair ------------------------------------------

    -- every visible part is projected and the closest one to the screen centre
    -- within the tolerance wins, so a head above a shoulder is picked correctly
    local function crosshairPoint(char, cam, viewport, origin)
        local center = viewport * 0.5
        local best, bestScore, bestPart

        for _, part in ipairs(char:GetChildren()) do
            if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart"
                and part.Transparency < 1 then
                local point = part.Position

                if (point - origin).Magnitude * STUDS_TO_M <= cfg.range then
                    local screen, onScreen = cam:WorldToViewportPoint(point)

                    if onScreen and screen.Z > 0 then
                        local score = (
                            Vector2.new(screen.X, screen.Y) - center
                        ).Magnitude

                        if score <= cfg.tolerance
                            and (bestScore == nil or score < bestScore) then
                            best, bestScore, bestPart = point, score, part
                        end
                    end
                end
            end
        end

        return best, bestPart
    end

    -- Firing -------------------------------------------------------------------

    local function equippedTool()
        local char = player.Character

        if not char then
            return nil
        end

        for _, item in ipairs(char:GetChildren()) do
            if item:IsA("Tool") then
                return item
            end
        end

        return nil
    end

    local function fire()
        local tool = equippedTool()

        if tool then
            local ok = pcall(function()
                tool:Activate()
            end)

            if ok then
                return true
            end
        end

        if type(mouse1click) == "function" then
            return pcall(mouse1click)
        end

        return false
    end

    -- Frame step ---------------------------------------------------------------

    local nextFire = 0

    local function step()
        if uiState.closed or not cfg.enabled then
            return
        end

        -- the menu owns the pointer, and the free camera owns the view
        if window.Visible or uiState.freeCamera then
            return
        end

        if cfg.requireClick and not UserInputService:IsMouseButtonPressed(
            Enum.UserInputType.MouseButton1
        ) then
            return
        end

        local cam = Workspace.CurrentCamera

        if not cam then
            return
        end

        local char = player.Character
        local root = char
            and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
        local origin = root and root.Position or cam.CFrame.Position
        local viewport = cam.ViewportSize
        local now = os.clock()

        for index = 1, #roster do
            local target = roster[index]

            if not (cfg.ignoreTeam and isTeammate(target)) then
                local body = target.Character
                local humanoid = isAlive(body)

                if body and humanoid then
                    local point = crosshairPoint(body, cam, viewport, origin)

                    if point and (not cfg.visible or hasSight(
                        cam.CFrame.Position, point, body
                    )) then
                        if now >= nextFire and fire() then
                            nextFire = now + cfg.delay / 1000
                        end

                        return
                    end
                end
            end
        end
    end

    local stepName = "ShitaroTrigger"

    pcall(function()
        RunService:UnbindFromRenderStep(stepName)
    end)

    local bound = pcall(function()
        RunService:BindToRenderStep(
            stepName,
            Enum.RenderPriority.Last.Value,
            step
        )
    end)

    if not bound then
        connect(RunService.RenderStepped, step)
    end

    connect(Players.PlayerAdded, refreshRoster)
    connect(Players.PlayerRemoving, refreshRoster)

    -- Trigger: menu ------------------------------------------------------------

    local page

    for _, tab in ipairs(tabs) do
        if tab.button and tab.button.Name == "trigger" then
            page = tab.page
            break
        end
    end

    if not page then
        return
    end

    local scroll = pageScroll(page, "TriggerScroll")

    panelWidths[scroll] = window.Size.X.Offset - PANEL_RESERVE

    local mainCard = previewPanel(scroll, "trigger.panel", 1, 3)
    local filterCard, filterHolder = previewPanel(scroll, "trigger.filters", 2, 1)
    local tuneCard, tuneHolder = previewPanel(scroll, "trigger.tuning", 3, 3)

    panelGapBefore[filterHolder] = 16
    panelGapBefore[tuneHolder] = 16

    -- same look as the toggles on the aim and visuals tabs
    local function addToggle(frame, state, onChange)
        local track = make("Frame", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -12, 0.5, 0),
            Size = UDim2.fromOffset(26, 14),
            BackgroundColor3 = state and colors.accent or Color3.new(1, 1, 1),
            BackgroundTransparency = state and 0.35 or 0.86,
            ZIndex = 2,
        }, frame)

        corner(track, UDim.new(1, 0))

        local knob = make("Frame", {
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, state and 14 or 2, 0.5, 0),
            Size = UDim2.fromOffset(10, 10),
            BackgroundColor3 = state and colors.accent or colors.sub,
            BackgroundTransparency = 0.15,
            ZIndex = 3,
        }, track)

        corner(knob, UDim.new(1, 0))

        local hit = make("TextButton", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Text = "",
            ZIndex = 5,
        }, frame)

        connect(hit.Activated, function()
            state = not state

            animate(track, {
                BackgroundColor3 = state
                    and colors.accent
                    or Color3.new(1, 1, 1),
                BackgroundTransparency = state and 0.35 or 0.86,
            })

            animate(knob, {
                Position = UDim2.new(0, state and 14 or 2, 0.5, 0),
                BackgroundColor3 = state and colors.accent or colors.sub,
            })

            onChange(state)
        end)
    end

    local enableRow, enableLabel = previewRow(mainCard, 1, "", true)
    localize(enableLabel, "trigger.enabled")

    addToggle(enableRow, cfg.enabled, function(value)
        cfg.enabled = value
        nextFire = 0
    end)

    local sightRow, sightLabel = previewRow(mainCard, 2, "", true)
    localize(sightLabel, "trigger.visible")

    addToggle(sightRow, cfg.visible, function(value)
        cfg.visible = value
    end)

    local clickRow, clickLabel = previewRow(mainCard, 3, "", true)
    localize(clickLabel, "trigger.requireClick")

    addToggle(clickRow, cfg.requireClick, function(value)
        cfg.requireClick = value
    end)

    local teamRow, teamLabel = previewRow(filterCard, 1, "", true)
    localize(teamLabel, "trigger.ignoreTeam")

    addToggle(teamRow, cfg.ignoreTeam, function(value)
        cfg.ignoreTeam = value
    end)

    local delayRow, delayLabel = previewRow(tuneCard, 1, "", true)
    localize(delayLabel, "trigger.delay")

    local delaySlider = rowSlider(
        delayRow,
        "TriggerDelay",
        LIMITS.delayMin,
        LIMITS.delayMax,
        function(value)
            return math.floor(value + 0.5) .. "ms"
        end,
        function(value)
            cfg.delay = math.floor(value + 0.5)
        end
    )

    delaySlider.set(cfg.delay, false)

    local toleranceRow, toleranceLabel = previewRow(tuneCard, 2, "", true)
    localize(toleranceLabel, "trigger.tolerance")

    local toleranceSlider = rowSlider(
        toleranceRow,
        "TriggerTolerance",
        LIMITS.toleranceMin,
        LIMITS.toleranceMax,
        function(value)
            return math.floor(value + 0.5) .. "px"
        end,
        function(value)
            cfg.tolerance = math.floor(value + 0.5)
        end
    )

    toleranceSlider.set(cfg.tolerance, false)

    local rangeRow, rangeLabel = previewRow(tuneCard, 3, "", true)
    localize(rangeLabel, "trigger.range")

    local rangeSlider = rowSlider(
        rangeRow,
        "TriggerRange",
        LIMITS.rangeMin,
        LIMITS.rangeMax,
        function(value)
            return math.floor(value + 0.5) .. "m"
        end,
        function(value)
            cfg.range = math.floor(value + 0.5)
        end
    )

    rangeSlider.set(cfg.range, false)

    layoutPreview()

    -- not registered through connect(): that list is disconnected first
    gui.Destroying:Connect(function()
        pcall(function()
            RunService:UnbindFromRenderStep(stepName)
        end)

        table.clear(filter)
        table.clear(roster)
    end)
end, function(err)
    warn("[shitaro/trigger] " .. debug.traceback(tostring(err), 2))
end)
end
