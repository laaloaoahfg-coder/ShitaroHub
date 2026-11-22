-- core/ui.lua - menu window, tabs, settings, colour panel, cursor, shutdown.
-- Started by loader.lua (receives the Loader as ...). It can also run alone;
-- the feature modules are then skipped.

-- UI-only reconstruction. No remote code or gameplay features.
-- Install as a LocalScript in StarterPlayer > StarterPlayerScripts.
-- Runtime and pixel-level parity must be checked in Roblox Studio.
--
-- v2 changes:
--   * every feature row of the aim section was removed (empty state only);
--   * settings tab holds a language switch (en/ru) and a live keybind
--     field (right click -> field blanks out -> next keyboard press binds).
--
-- v8 changes:
--   * third person / free camera: the first person arms and gun (the model the
--     game parents to the camera) are hidden while the camera is away from the
--     head, so they stay with the real body instead of floating with the view.
--
-- v7 changes:
--   * aimbot: keeps its own aim between frames (the pull accumulates even when
--     the game rebuilds the camera from the mouse every frame), so the
--     crosshair converges on the chosen part instead of stopping short;
--     shitaro_aim() also prints how far the aim point is from the screen centre.
--   * aim tab: part names are centred in their segments.
--
-- v6 changes:
--   * esp: the root part is the anchor of every box (limbs that freeze while
--     a player is off screen / behind a wall no longer outvote it); the box
--     proportions are measured while all parts agree and reused afterwards.
--   * camera: the field of view slider is absolute (1-120 degrees), applies
--     at once and has a reset button; it is written late in the frame (before
--     the aimbot and ESP) and re-asserted if the game overwrites it.
--
-- v5 changes:
--   * "ignore teammates" (ESP and aimbot) shares one side resolver: Roblox
--     Team, side attributes, side value objects, character folders; the
--     filter only applies while a second side exists in the match;
--     getgenv().shitaro_dump() prints the resolved side of every player.
--
-- v4 changes:
--   * aim tab: aimbot (on/off, visibility check, only while shooting, target
--     part head/neck/body/legs, ignore bots/teammates, smoothing 1-10, FOV
--     circle 1-150, range 1-800 m) with its own circle overlay; the empty
--     state of that tab is gone.
--
-- v3 changes:
--   * visuals tab: ESP (box, line, nickname, distance, skeleton, health,
--     ignore teammates / friends, range 0-800), two colour squares per
--     function (exposed / behind cover) edited in the docked colour panel.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local Stats = game:GetService("Stats")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Replace only an earlier instance of this UI.
local previous = playerGui:FindFirstChild("ShitaroMenuOnly")
if previous then
    previous:Destroy()
end

local colors = {
    bg = Color3.fromRGB(7, 7, 9),
    text = Color3.fromRGB(230, 230, 236),
    sub = Color3.fromRGB(170, 170, 178),
    dim = Color3.fromRGB(112, 112, 122),
    faint = Color3.fromRGB(68, 68, 76),
    accent = Color3.fromRGB(200, 148, 232),
}

-- The docked colour panel edits the menu surface.
local picker = {
    target = { kind = "menu" },
    listeners = {},
}

-- width reserved on the right for the docked picker (panel + margins)
local PANEL_RESERVE = 370

local fonts = {
    normal = Font.new(
        "rbxasset://fonts/families/BuilderSans.json",
        Enum.FontWeight.SemiBold
    ),
    bold = Font.new(
        "rbxasset://fonts/families/BuilderSans.json",
        Enum.FontWeight.Bold
    ),
    watermark = Font.new(
        "rbxasset://fonts/families/SourceSansPro.json"
    ),
}

local icons = {
    code = 106124864132557,
    crosshair = 83752373575368,
    trigger = 81854854241463,
    eye = 127234874352422,
    gear = 109485777305919,
    skins = 127369887384101,
    sliders = 125396339381135,
    save = 122894934359450,
    chevron = 71457658246709,
    grip = 128492050787735,
    layers = 114499998778667,
    wifi = 104941258142372,
    ram = 82464660673318,
    clock = 136533241128438,
}

local function make(class, properties, parent)
    local object = Instance.new(class)

    if object:IsA("GuiObject") then
        object.BorderSizePixel = 0
        object.BackgroundTransparency = 1
    end

    if object:IsA("TextLabel") or object:IsA("TextButton") then
        object.Text = ""
        object.FontFace = fonts.normal
        object.TextSize = 14
        object.TextColor3 = colors.text
        object.TextXAlignment = Enum.TextXAlignment.Left
        object.AutoLocalize = false
    end

    if object:IsA("GuiButton") then
        object.AutoButtonColor = false
    end

    for key, value in pairs(properties or {}) do
        object[key] = value
    end

    object.Parent = parent
    return object
end

local function corner(parent, radius)
    return make("UICorner", {
        CornerRadius = radius,
    }, parent)
end

local function stroke(parent, transparency)
    make("UIStroke", {
        Color = Color3.new(1, 1, 1),
        Transparency = transparency,
        Thickness = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, parent)
end

local function padding(parent, left, right, top, bottom)
    make("UIPadding", {
        PaddingLeft = UDim.new(0, left),
        PaddingRight = UDim.new(0, right),
        PaddingTop = UDim.new(0, top),
        PaddingBottom = UDim.new(0, bottom),
    }, parent)
end

local function row(parent, gap, alignment)
    return make("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, gap),
        VerticalAlignment = Enum.VerticalAlignment.Center,
        HorizontalAlignment = alignment
            or Enum.HorizontalAlignment.Left,
    }, parent)
end

local function image(parent, key, size, order, transparency)
    return make("ImageLabel", {
        Size = UDim2.fromOffset(size, size),
        Image = "rbxassetid://" .. icons[key],
        ScaleType = Enum.ScaleType.Fit,
        LayoutOrder = order or 0,
        ImageTransparency = transparency or 0,
    }, parent)
end

local function animate(object, properties, duration)
    TweenService:Create(
        object,
        TweenInfo.new(
            duration or 0.14,
            Enum.EasingStyle.Quad,
            Enum.EasingDirection.Out
        ),
        properties
    ):Play()
end

-- Localisation --------------------------------------------------------------

local locale = {
    en = {
        ["tab.aim"] = "aim",
        ["tab.trigger"] = "trigger",
        ["tab.visuals"] = "visuals",
        ["tab.misc"] = "misc",
        ["tab.skins"] = "skins",
        ["tab.settings"] = "settings",
        ["header.config"] = "No config",
        ["header.profile"] = "global",
        ["close.title"] = "disable cheat",
        ["close.body"] = "the cheat will be turned off: the menu closes and "
            .. "the menu key stops working. you can only bring it back by "
            .. "running the script again.",
        ["close.cancel"] = "cancel",
        ["close.confirm"] = "okay",
        ["settings.panel"] = "interface",
        ["settings.language"] = "language",
        ["settings.keybind"] = "menu key",
        ["settings.hint"] = "left click the key to rebind",
        ["settings.color"] = "menu color",
        ["settings.opacity"] = "transparency",
        ["palette.title"] = "menu color",
        ["palette.subtitle"] = "pick the interface color",
        ["palette.apply"] = "apply",
        ["palette.reset"] = "reset",
        ["settings.watermark"] = "watermark",
        ["settings.wmScale"] = "size",
        ["settings.wmX"] = "position X",
        ["settings.wmY"] = "position Y",
        ["settings.wmReset"] = "reset position",
        ["esp.panel"] = "esp",
        ["esp.filters"] = "filters",
        ["esp.box"] = "box",
        ["esp.line"] = "line",
        ["esp.name"] = "nickname",
        ["esp.distance"] = "distance",
        ["esp.skeleton"] = "skeleton",
        ["esp.health"] = "health",
        ["esp.bots"] = "bot esp",
        ["esp.ignoreTeam"] = "ignore teammates",
        ["esp.ignoreFriends"] = "ignore friends",
        ["esp.range"] = "max distance",
        ["esp.picker.title"] = "esp color",
        ["esp.state.visible"] = "exposed",
        ["esp.state.hidden"] = "behind cover",
    },
    ru = {
        ["tab.aim"] = "прицел",
        ["tab.trigger"] = "триггер",
        ["tab.visuals"] = "визуалы",
        ["tab.misc"] = "прочее",
        ["tab.skins"] = "скины",
        ["tab.settings"] = "настройки",
        ["header.config"] = "нет конфига",
        ["header.profile"] = "глобальный",
        ["close.title"] = "отключение чита",
        ["close.body"] = "чит будет отключён: меню закроется, а клавиша "
            .. "перестанет работать. вернуть можно только повторным "
            .. "запуском скрипта.",
        ["close.cancel"] = "отмена",
        ["close.confirm"] = "хорошо",
        ["settings.panel"] = "интерфейс",
        ["settings.language"] = "язык",
        ["settings.keybind"] = "клавиша меню",
        ["settings.hint"] = "ЛКМ по клавише — смена",
        ["settings.color"] = "цвет меню",
        ["settings.opacity"] = "прозрачность",
        ["palette.title"] = "изменение цвета меню",
        ["palette.subtitle"] = "выберите цвет интерфейса",
        ["palette.apply"] = "применить",
        ["palette.reset"] = "сброс",
        ["settings.watermark"] = "вотермарка",
        ["settings.wmScale"] = "размер",
        ["settings.wmX"] = "позиция X",
        ["settings.wmY"] = "позиция Y",
        ["settings.wmReset"] = "сброс положения",
        ["esp.panel"] = "есп",
        ["esp.filters"] = "фильтры",
        ["esp.box"] = "коробка",
        ["esp.line"] = "линия",
        ["esp.name"] = "никнейм",
        ["esp.distance"] = "расстояние",
        ["esp.skeleton"] = "скелет",
        ["esp.health"] = "здоровье",
        ["esp.bots"] = "есп на ботов",
        ["esp.ignoreTeam"] = "игнорировать тиммейтов",
        ["esp.ignoreFriends"] = "игнорировать друзей",
        ["esp.range"] = "дистанция",
        ["esp.picker.title"] = "изменение цвета есп",
        ["esp.state.visible"] = "на виду",
        ["esp.state.hidden"] = "за укрытием",
    },
}

local languageNames = {
    en = "english",
    ru = "русский",
}

local currentLanguage = "en"
local localized = {}
local languageChanged = {}

local function L(key)
    local pack = locale[currentLanguage]

    if pack and pack[key] then
        return pack[key]
    end

    return locale.en[key] or key
end

-- Registers a TextLabel/TextButton so it is retranslated on every switch.
local function localize(object, key)
    table.insert(localized, {
        object = object,
        key = key,
    })

    object.Text = L(key)
    return object
end

local function onLanguageChanged(callback)
    table.insert(languageChanged, callback)
end

local function setLanguage(id)
    if not locale[id] or id == currentLanguage then
        return
    end

    currentLanguage = id

    for _, entry in ipairs(localized) do
        entry.object.Text = L(entry.key)
    end

    for _, callback in ipairs(languageChanged) do
        callback(id)
    end
end

local function currentLanguageName()
    return languageNames[currentLanguage] or currentLanguage
end

local gui = make("ScreenGui", {
    Name = "ShitaroMenuOnly",
    IgnoreGuiInset = true,
    ResetOnSpawn = false,
    ScreenInsets = Enum.ScreenInsets.None,
    ClipToDeviceSafeArea = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 10000,
}, playerGui)

local connections = {}

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(connections, connection)
    return connection
end

connect(gui.Destroying, function()
    for _, connection in ipairs(connections) do
        connection:Disconnect()
    end
end)

-- Window

local window = make("Frame", {
    Name = "Menu",
    Position = UDim2.fromOffset(0, 0),
    Visible = false,
    Size = UDim2.fromOffset(780, 470),
    BackgroundTransparency = 0.16,
    BackgroundColor3 = colors.bg,
    Active = true,
}, gui)

local menuScale = make("UIScale", {
    Scale = 1,
}, window)

corner(window, UDim.new(0, 10))
stroke(window, 0.935)

local header = make("Frame", {
    Size = UDim2.new(1, 0, 0, 40),
}, window)

local tintClip = make("Frame", {
    Size = UDim2.fromScale(1, 1),
    ClipsDescendants = true,
}, header)

local tint = make("Frame", {
    Size = UDim2.new(1, 0, 1, 12),
    BackgroundColor3 = Color3.new(1, 1, 1),
    BackgroundTransparency = 0.976,
}, tintClip)

corner(tint, UDim.new(0, 10))

make("Frame", {
    Position = UDim2.fromOffset(0, 40),
    Size = UDim2.new(1, 0, 0, 1),
    BackgroundColor3 = Color3.new(1, 1, 1),
    BackgroundTransparency = 0.94,
}, window)

local dragHandle = make("TextButton", {
    Size = UDim2.fromScale(1, 1),
    ZIndex = 1,
}, header)

local titleRow = make("Frame", {
    Position = UDim2.fromOffset(14, 0),
    Size = UDim2.fromOffset(0, 40),
    AutomaticSize = Enum.AutomaticSize.X,
    ZIndex = 2,
}, header)

row(titleRow, 8)

make("TextLabel", {
    Text = "shitaro",
    FontFace = fonts.bold,
    TextSize = 15,
    Size = UDim2.fromOffset(0, 40),
    AutomaticSize = Enum.AutomaticSize.X,
    LayoutOrder = 1,
}, titleRow)

make("Frame", {
    Size = UDim2.fromOffset(4, 1),
    LayoutOrder = 2,
}, titleRow)

-- Configuration controls are decorative only.
local save = make("Frame", {
    Size = UDim2.fromOffset(24, 24),
    LayoutOrder = 3,
    BackgroundColor3 = Color3.new(1, 1, 1),
    BackgroundTransparency = 0.952,
}, titleRow)

corner(save, UDim.new(0, 6))
stroke(save, 0.925)

local saveIcon = image(save, "save", 13)
saveIcon.AnchorPoint = Vector2.new(0.5, 0.5)
saveIcon.Position = UDim2.fromScale(0.5, 0.5)
saveIcon.ImageColor3 = colors.dim

local config = make("Frame", {
    Size = UDim2.fromOffset(0, 24),
    AutomaticSize = Enum.AutomaticSize.X,
    LayoutOrder = 4,
}, titleRow)

row(config, 6)

localize(make("TextLabel", {
    Text = "No config",
    TextSize = 13,
    TextColor3 = colors.dim,
    Size = UDim2.fromOffset(0, 24),
    AutomaticSize = Enum.AutomaticSize.X,
    LayoutOrder = 1,
}, config), "header.config")

local configIcon = image(config, "chevron", 10, 2)
configIcon.ImageColor3 = colors.dim

-- Auto width: Cyrillic labels ("глобальный") are wider than "global", so the
-- chip has to hug its text instead of using a fixed 70 px box.
local profile = make("Frame", {
    Size = UDim2.fromOffset(0, 24),
    AutomaticSize = Enum.AutomaticSize.X,
    LayoutOrder = 5,
    BackgroundColor3 = Color3.new(1, 1, 1),
    BackgroundTransparency = 0.952,
}, titleRow)

corner(profile, UDim.new(0, 6))
stroke(profile, 0.925)
padding(profile, 10, 24, 0, 0)

localize(make("TextLabel", {
    Text = "global",
    TextSize = 13,
    Size = UDim2.fromOffset(0, 24),
    AutomaticSize = Enum.AutomaticSize.X,
}, profile), "header.profile")

local profileIcon = image(profile, "chevron", 10)
profileIcon.AnchorPoint = Vector2.new(1, 0.5)
profileIcon.Position = UDim2.new(1, -8, 0.5, 0)
profileIcon.ImageColor3 = colors.dim

-- Close button in the top-right corner. The confirmation sheet itself is
-- built further down (it needs the finished window), so only the handler is
-- declared here and assigned there.
local openShutdownConfirm

local closeButton = make("TextButton", {
    Name = "CloseButton",
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -12, 0.5, 0),
    Size = UDim2.fromOffset(24, 24),
    BackgroundColor3 = Color3.new(1, 1, 1),
    BackgroundTransparency = 0.952,
    AutoButtonColor = false,
    Text = "",
    -- the header drag handle is raised to ZIndex 30 further down, so the
    -- cross has to stay above it or it only starts a window drag
    ZIndex = 31,
}, header)

corner(closeButton, UDim.new(0, 6))
stroke(closeButton, 0.925)

-- The cross is two rotated bars, so the button needs no extra asset.
local crossBars = {}

for _, rotation in ipairs({ 45, -45 }) do
    local bar = make("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(11, 2),
        Rotation = rotation,
        BackgroundColor3 = colors.dim,
        BackgroundTransparency = 0.15,
        ZIndex = 32,
    }, closeButton)

    table.insert(crossBars, bar)
end

connect(closeButton.MouseEnter, function()
    animate(closeButton, { BackgroundTransparency = 0.88 })

    for _, bar in ipairs(crossBars) do
        animate(bar, { BackgroundColor3 = Color3.fromRGB(226, 96, 96) })
    end
end)

connect(closeButton.MouseLeave, function()
    animate(closeButton, { BackgroundTransparency = 0.952 })

    for _, bar in ipairs(crossBars) do
        animate(bar, { BackgroundColor3 = colors.dim })
    end
end)

local body = make("Frame", {
    Name = "EmptyPages",
    Position = UDim2.fromOffset(0, 41),
    Size = UDim2.new(1, 0, 1, -89),
}, window)

-- Navigation

local nav = make("Frame", {
    AnchorPoint = Vector2.new(0.5, 1),
    Position = UDim2.new(0.5, 0, 1, -9),
    Size = UDim2.fromOffset(0, 32),
    AutomaticSize = Enum.AutomaticSize.X,
    BackgroundColor3 = Color3.new(1, 1, 1),
    BackgroundTransparency = 0.958,
    ZIndex = 3,
}, window)

local navCorner = corner(nav, UDim.new(1, 0))
stroke(nav, 0.935)
padding(nav, 3, 3, 3, 3)

local highlight = make("Frame", {
    Size = UDim2.fromOffset(0, 26),
    BackgroundColor3 = Color3.new(1, 1, 1),
    BackgroundTransparency = 0.925,
    ZIndex = 3,
}, nav)

corner(highlight, UDim.new(1, 0))

local tabRow = make("Frame", {
    Size = UDim2.fromOffset(0, 26),
    AutomaticSize = Enum.AutomaticSize.X,
    ZIndex = 4,
}, nav)

local navigationLayout = row(tabRow, 2)
local tabs = {}
local selected

local function updateHighlight()
    if not selected or not gui.Parent then
        return
    end

    local scale = menuScale.Scale
    local delta = (
        selected.button.AbsolutePosition
        - tabRow.AbsolutePosition
    ) / scale

    animate(highlight, {
        Position = UDim2.fromOffset(delta.X, delta.Y),
        Size = UDim2.fromOffset(
            selected.button.AbsoluteSize.X / scale,
            selected.button.AbsoluteSize.Y / scale
        ),
    }, 0.24)
end

local function drawTab(tab)
    local active = tab == selected

    tab.label.FontFace = active and fonts.bold or fonts.normal

    animate(tab.label, {
        TextColor3 = active and colors.text
            or (tab.hover and colors.sub or colors.dim),
    })

    animate(tab.icon, {
        ImageColor3 = active and colors.accent
            or (tab.hover and colors.sub or colors.dim),
    })

    tab.page.Visible = active
end

for index, entry in ipairs({
    { "aim", "crosshair" },
    { "trigger", "trigger" },
    { "visuals", "eye" },
    { "misc", "gear" },
    { "skins", "skins" },
    { "settings", "sliders" },
}) do
    local button = make("TextButton", {
        Name = entry[1],
        Size = UDim2.fromOffset(0, 26),
        AutomaticSize = Enum.AutomaticSize.X,
        LayoutOrder = index,
        ZIndex = 4,
    }, tabRow)

    padding(button, 10, 12, 0, 0)
    row(button, 6)

    local tab = {
        button = button,
        icon = image(button, entry[2], 13, 1),

        label = make("TextLabel", {
            Text = entry[1],
            TextSize = 13,
            Size = UDim2.fromOffset(0, 26),
            AutomaticSize = Enum.AutomaticSize.X,
            LayoutOrder = 2,
            ZIndex = 4,
        }, button),

        page = make("Frame", {
            Name = entry[1],
            Size = UDim2.fromScale(1, 1),
            Visible = false,
        }, body),
    }

    tab.icon.ZIndex = 4
    localize(tab.label, "tab." .. entry[1])
    table.insert(tabs, tab)
    selected = selected or tab

    connect(button.MouseEnter, function()
        tab.hover = true
        drawTab(tab)
    end)

    connect(button.MouseLeave, function()
        tab.hover = false
        drawTab(tab)
    end)

    connect(button.Activated, function()
        selected = tab

        for _, item in ipairs(tabs) do
            drawTab(item)
        end

        if picker.sync then
            picker.sync(tab)
        end

        task.defer(updateHighlight)
    end)

    connect(
        button:GetPropertyChangedSignal("AbsoluteSize"),
        updateHighlight
    )

    drawTab(tab)
end

connect(
    tabRow:GetPropertyChangedSignal("AbsolutePosition"),
    updateHighlight
)

task.defer(updateHighlight)

local grip = make("ImageButton", {
    AnchorPoint = Vector2.new(1, 1),
    Position = UDim2.new(1, -6, 1, -6),
    Size = UDim2.fromOffset(11, 11),
    Image = "rbxassetid://" .. icons.grip,
    ImageColor3 = colors.faint,
    ZIndex = 10,
}, window)

-- Watermark: no top or right offset.

local inset = GuiService:GetGuiInset()

local watermark = make("TextButton", {
    Name = "Watermark",
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, 0, 0, 0),
    ZIndex = 20,
    Size = UDim2.fromOffset(0, 34),
    AutomaticSize = Enum.AutomaticSize.X,
}, gui)

row(watermark, 10, Enum.HorizontalAlignment.Left)

-- The whole watermark is one scalable unit; pills are retinted with the menu
-- theme through `watermarkPills` (style hook lives in the settings section).
local watermarkScale = make("UIScale", {
    Name = "WatermarkScale",
    Scale = 1,
}, watermark)

local watermarkPills = {}

local function pill(order)
    local frame = make("Frame", {
        Size = UDim2.fromOffset(0, 34),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = Color3.fromRGB(12, 20, 25),
        BackgroundTransparency = 0.686274528503418,
        LayoutOrder = order,
    }, watermark)

    table.insert(watermarkPills, frame)

    corner(frame, UDim.new(1, 0))
    padding(frame, 12, 12, 8, 8)
    row(frame, 0)

    return frame
end

local function spacer(parent, width, order)
    make("Frame", {
        Size = UDim2.fromOffset(width, 1),
        LayoutOrder = order,
    }, parent)
end

local function watermarkText(parent, text, order)
    local container = make("Frame", {
        Size = UDim2.fromOffset(0, 18),
        AutomaticSize = Enum.AutomaticSize.X,
        LayoutOrder = order,
    }, parent)

    local shadow = make("TextLabel", {
        Text = text,
        FontFace = fonts.watermark,
        TextSize = 16,
        TextColor3 = Color3.new(),
        TextTransparency = 0.15,
        Position = UDim2.fromOffset(1, 1),
        Size = UDim2.fromOffset(0, 18),
        AutomaticSize = Enum.AutomaticSize.X,
    }, container)

    local label = make("TextLabel", {
        Text = text,
        FontFace = fonts.watermark,
        TextSize = 16,
        TextColor3 = Color3.new(1, 1, 1),
        Size = UDim2.fromOffset(0, 18),
        AutomaticSize = Enum.AutomaticSize.X,
        ZIndex = 2,
    }, container)

    connect(label:GetPropertyChangedSignal("Text"), function()
        shadow.Text = label.Text
    end)

    return label
end

local brand = pill(1)
image(brand, "code", 18, 1, 0.392)
spacer(brand, 8, 2)
watermarkText(brand, "shitaro.lol", 3)

local metrics = pill(2)
local values = {}

for index, name in ipairs({
    "User",
    "FPS",
    "Ping",
    "RAM",
    "Time",
}) do
    if index > 1 then
        local separator = make("Frame", {
            Size = UDim2.fromOffset(25, 14),
            LayoutOrder = index * 2 - 1,
        }, metrics)

        make("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(1, 14),
            BackgroundColor3 = Color3.new(1, 1, 1),
            BackgroundTransparency = 0.392,
        }, separator)
    end

    local group = make("Frame", {
        Size = UDim2.fromOffset(0, 18),
        AutomaticSize = Enum.AutomaticSize.X,
        LayoutOrder = index * 2,
    }, metrics)

    row(group, 0)

    if name == "User" then
        local avatar = make("ImageLabel", {
            Size = UDim2.fromOffset(18, 18),
            LayoutOrder = 1,
            Image = "rbxthumb://type=AvatarHeadShot&id="
                .. player.UserId .. "&w=48&h=48",
            ScaleType = Enum.ScaleType.Crop,
            BackgroundColor3 = Color3.fromRGB(20, 20, 20),
            BackgroundTransparency = 0,
        }, group)

        corner(avatar, UDim.new(1, 0))
    else
        local keys = {
            FPS = "layers",
            Ping = "wifi",
            RAM = "ram",
            Time = "clock",
        }

        image(group, keys[name], 14, 1, 0.392)
    end

    spacer(group, 8, 2)

    values[name] = watermarkText(
        group,
        name == "User" and player.Name or "-",
        3
    )
end

-- Controls store UI state only, without gameplay callbacks.

local gesture
local safeOrigin = Vector2.zero
local safeSize = Vector2.new(780, 470)
local activeSlider
local uiState = {}

local function pageScroll(page, name)
    return make("ScrollingFrame", {
        Name = name,
        Size = UDim2.fromScale(1, 1),
        CanvasSize = UDim2.fromOffset(0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = colors.dim,
        ScrollingDirection = Enum.ScrollingDirection.Y,
    }, page)
end

local previewScroll = pageScroll(tabs[1].page, "AimScroll")
local settingsScroll = pageScroll(tabs[6].page, "SettingsScroll")

-- panels are tracked per scroll frame so each page lays out its own columns
local panelGroups = {}
local panelWidths = {}

-- Extra space a panel asks for above itself (default gap is 12 px).
local panelGapBefore = {}

local function previewPanel(parent, key, order, count)
    local holder = make("Frame", {
        Name = key,
        Size = UDim2.fromOffset(240, 22 + count * 30),
        LayoutOrder = order,
    }, parent)

    localize(make("TextLabel", {
        Text = "",
        TextSize = 12,
        TextColor3 = colors.dim,
        Position = UDim2.fromOffset(10, 0),
        Size = UDim2.new(1, -20, 0, 22),
    }, holder), key)

    local card = make("Frame", {
        Position = UDim2.fromOffset(0, 22),
        Size = UDim2.new(1, 0, 0, count * 30),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BackgroundTransparency = 0.958,
        ClipsDescendants = true,
    }, holder)

    corner(card, UDim.new(0, 10))
    stroke(card, 0.935)

    local group = panelGroups[parent]

    if not group then
        group = {}
        panelGroups[parent] = group
    end

    table.insert(group, holder)
    return card, holder
end

local function previewRow(card, index, name, enabled)
    local frame = make("Frame", {
        Position = UDim2.fromOffset(0, (index - 1) * 30),
        Size = UDim2.new(1, 0, 0, 30),
    }, card)

    if index > 1 then
        make("Frame", {
            Size = UDim2.new(1, 0, 0, 1),
            BackgroundColor3 = Color3.new(1, 1, 1),
            BackgroundTransparency = 0.955,
        }, frame)
    end

    local label = make("TextLabel", {
        Text = name,
        TextSize = 13,
        TextColor3 = enabled and colors.text or colors.faint,
        Position = UDim2.fromOffset(12, 0),
        Size = UDim2.new(0.48, -12, 1, 0),
    }, frame)

    return frame, label
end

local function previewToggle(frame, on, enabled)
    local track = make("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.fromOffset(26, 14),
        BackgroundColor3 = on
            and colors.accent
            or Color3.new(1, 1, 1),
        BackgroundTransparency = on
            and 0.5
            or (enabled and 0.86 or 0.95),
    }, frame)

    corner(track, UDim.new(1, 0))

    local knob = make("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, on and 14 or 2, 0.5, 0),
        Size = UDim2.fromOffset(10, 10),
        BackgroundColor3 = on and colors.accent or colors.sub,
        BackgroundTransparency = enabled and 0.15 or 0.6,
    }, track)

    corner(knob, UDim.new(1, 0))

    local hit = make("TextButton", {
        Size = UDim2.fromScale(1, 1),
        ZIndex = 5,
    }, frame)

    local key = frame.Parent.Parent.Name
        .. "/" .. frame.Position.Y.Offset

    uiState[key] = on

    connect(hit.Activated, function()
        on = not on
        uiState[key] = on

        animate(track, {
            BackgroundColor3 = on
                and colors.accent
                or Color3.new(1, 1, 1),
            BackgroundTransparency = on and 0.35 or 0.86,
        })

        animate(knob, {
            Position = UDim2.new(0, on and 14 or 2, 0.5, 0),
            BackgroundColor3 = on and colors.accent or colors.sub,
            BackgroundTransparency = 0.15,
        })
    end)
end

-- Dropdowns remain decorative.
local function previewDropdown(frame, text)
    local field = make("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.new(0.47, 0, 0, 24),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BackgroundTransparency = 0.97,
    }, frame)

    corner(field, UDim.new(0, 6))
    stroke(field, 0.96)

    make("TextLabel", {
        Text = text,
        TextSize = 12,
        TextColor3 = colors.faint,
        Position = UDim2.fromOffset(10, 0),
        Size = UDim2.new(1, -28, 1, 0),
    }, field)

    local arrow = image(field, "chevron", 9)
    arrow.AnchorPoint = Vector2.new(1, 0.5)
    arrow.Position = UDim2.new(1, -8, 0.5, 0)
    arrow.ImageColor3 = colors.faint
end

local function previewSlider(frame, text)
    local area = make("Frame", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -10, 0, 0),
        Size = UDim2.new(0.47, 0, 1, 0),
    }, frame)

    local number = make("Frame", {
        Position = UDim2.new(0, 0, 0.5, -10),
        Size = UDim2.new(0.45, 0, 0, 20),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BackgroundTransparency = 0.97,
    }, area)

    corner(number, UDim.new(0, 5))
    stroke(number, 0.96)

    local valueLabel = make("TextLabel", {
        Text = text,
        TextSize = 12,
        TextColor3 = colors.faint,
        TextXAlignment = Enum.TextXAlignment.Center,
        Size = UDim2.fromScale(1, 1),
    }, number)

    local track = make("Frame", {
        Position = UDim2.new(0.51, 0, 0.5, -1.5),
        Size = UDim2.new(0.49, 0, 0, 3),
        BackgroundColor3 = colors.faint,
        BackgroundTransparency = 0.3,
    }, area)

    corner(track, UDim.new(1, 0))

    local dot = make("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.fromScale(0, 0.5),
        Size = UDim2.fromOffset(10, 10),
        BackgroundColor3 = colors.sub,
        BackgroundTransparency = 0.35,
    }, track)

    corner(dot, UDim.new(1, 0))

    local maximum = text == "8°" and 180 or 100
    local suffix = text == "8°" and "°" or ""
    local key = frame.Parent.Parent.Name
        .. "/" .. frame.Position.Y.Offset

    local function setValue(value)
        value = math.clamp(
            math.floor(value + 0.5),
            0,
            maximum
        )

        uiState[key] = value
        valueLabel.Text = tostring(value) .. suffix
        dot.Position = UDim2.fromScale(value / maximum, 0.5)
        dot.AnchorPoint = Vector2.new(0.5, 0.5)
    end

    local function update(x)
        setValue(
            (x - track.AbsolutePosition.X)
                / math.max(1, track.AbsoluteSize.X)
                * maximum
        )
    end

    local hit = make("TextButton", {
        Position = UDim2.new(0.51, -8, 0, 0),
        Size = UDim2.new(0.49, 16, 1, 0),
        ZIndex = 5,
    }, area)

    connect(hit.InputBegan, function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end

        gesture = nil
        activeSlider = {
            input = input,
            update = update,
        }

        previewScroll.ScrollingEnabled = false
        update(input.Position.X)
    end)

    setValue(tonumber(string.match(text, "%d+")) or 0)
end

-- Settings section -----------------------------------------------------------
--
-- Two columns on the settings page:
--   * left  - feature rows (language, menu key, hint);
--   * right - the colour panel, docked and visible immediately, no modal.
--
-- The aim section builds its own cards further down (the aimbot closure).

local menuColor = colors.bg
local menuTransparency = window.BackgroundTransparency
local styleHooks = {}

local function onMenuStyleChanged(callback)
    table.insert(styleHooks, callback)
end

local function notifyMenuStyle()
    for _, callback in ipairs(styleHooks) do
        callback(menuColor, menuTransparency)
    end
end

local function applyMenuStyle(color, transparency)
    menuColor = color
    menuTransparency = transparency
    window.BackgroundColor3 = color
    window.BackgroundTransparency = transparency
    notifyMenuStyle()
end

-- The curtain is a cut-out of the menu surface: exactly the menu colour and
-- exactly the menu transparency, no lift and no extra alpha. Anything else
-- reads as a foreign plate stuck on top of the window.
local function languageSurface()
    return menuColor, menuTransparency
end


-- One pointer gesture at a time: sliders and on-screen dragging both run
-- through this channel, so nothing fights over InputChanged.
local function isPressInput(input)
    return input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
end

local activeDrag

local function beginUIDrag(input, move, release)
    move(input.Position.X, input.Position.Y)
    activeDrag = {
        move = move,
        release = release,
    }
end

connect(UserInputService.InputChanged, function(input)
    if not activeDrag then
        return
    end

    if input.UserInputType ~= Enum.UserInputType.MouseMovement
        and input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end

    activeDrag.move(input.Position.X, input.Position.Y)
end)

connect(UserInputService.InputEnded, function(input)
    if not isPressInput(input) or not activeDrag then
        return
    end

    local drag = activeDrag
    activeDrag = nil

    if drag.release then
        drag.release()
    end
end)

-- watermark surface follows the menu theme (it lives over the world, so it
-- keeps a bit more transparency than the window itself to stay unobtrusive)
local function applyWatermarkTheme()
    local transparency = math.clamp(menuTransparency + 0.5, 0, 0.92)

    for _, surface in ipairs(watermarkPills) do
        surface.BackgroundColor3 = menuColor
        surface.BackgroundTransparency = transparency
    end
end

onMenuStyleChanged(applyWatermarkTheme)

local settings = previewPanel(settingsScroll, "settings.panel", 1, 3)

local function settingField(parent)
    local field = make("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.new(0.47, 0, 0, 24),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BackgroundTransparency = 0.97,
        Text = "",
        Active = true,
        ZIndex = 2,
    }, parent)

    corner(field, UDim.new(0, 6))
    stroke(field, 0.96)

    local label = make("TextLabel", {
        Text = "",
        TextSize = 12,
        TextColor3 = colors.sub,
        TextXAlignment = Enum.TextXAlignment.Center,
        Position = UDim2.fromOffset(6, 0),
        Size = UDim2.new(1, -24, 1, 0),
        ZIndex = 2,
    }, field)

    local arrow = image(field, "chevron", 9)
    arrow.AnchorPoint = Vector2.new(1, 0.5)
    arrow.Position = UDim2.new(1, -8, 0.5, 0)
    arrow.ImageColor3 = colors.faint
    arrow.ZIndex = 2

    return field, label
end

-- language ----------------------------------------------------------------

local languageOrder = { "en", "ru" }

local languageRow, languageLabel = previewRow(settings, 1, "", true)
localize(languageLabel, "settings.language")

local languageField, languageValue = settingField(languageRow)

local function refreshLanguageValue()
    languageValue.Text = currentLanguageName()
end

refreshLanguageValue()

-- Language dropdown (the "curtain"). It lists every language except the
-- active one: with EN selected it offers "русский", after the switch it
-- offers "english". Parented to the window so the scrolling frame / card
-- clipping cannot cut it off, and it inherits the menu surface colour.

local curtainColor, curtainTransparency = languageSurface()

local languageMenu = make("Frame", {
    Name = "LanguageMenu",
    Visible = false,
    Size = UDim2.fromOffset(0, 0),
    BackgroundColor3 = curtainColor,
    BackgroundTransparency = curtainTransparency,
    ClipsDescendants = true,
    ZIndex = 10,
    AnchorPoint = Vector2.new(0, 0),
}, gui)

local languageCorner = corner(languageMenu, UDim.new(0, 10))

-- Flip to true to print the measured geometry (useful if a specific client
-- disagrees about AbsolutePosition).
local DEBUG_LAYOUT = false

-- Places a ScreenGui-level frame exactly at a screen position. Two probe
-- writes measure the local -> screen mapping of the parent (UI scale, insets,
-- rounding), so the result is the same on every client instead of relying on
-- AbsolutePosition and Position sharing one coordinate space.
local function pinToScreen(frame, targetX, targetY)
    frame.Position = UDim2.fromOffset(0, 0)

    local origin = frame.AbsolutePosition

    frame.Position = UDim2.fromOffset(1000, 1000)

    local probe = frame.AbsolutePosition
    local scaleX = (probe.X - origin.X) / 1000
    local scaleY = (probe.Y - origin.Y) / 1000

    if math.abs(scaleX) < 0.001 then
        scaleX = 1
    end

    if math.abs(scaleY) < 0.001 then
        scaleY = 1
    end

    frame.Position = UDim2.fromOffset(
        (targetX - origin.X) / scaleX,
        (targetY - origin.Y) / scaleY
    )

    -- residual correction: whatever is left is a pure offset now
    for _ = 1, 2 do
        local actual = frame.AbsolutePosition
        local errorX = (targetX - actual.X) / scaleX
        local errorY = (targetY - actual.Y) / scaleY

        if math.abs(errorX) < 0.5 and math.abs(errorY) < 0.5 then
            return
        end

        frame.Position = UDim2.fromOffset(
            frame.Position.X.Offset + errorX,
            frame.Position.Y.Offset + errorY
        )
    end
end
stroke(languageMenu, 0.935)

local function refreshLanguageSurface()
    local color, transparency = languageSurface()

    languageMenu.BackgroundColor3 = color
    languageMenu.BackgroundTransparency = transparency
end

onMenuStyleChanged(refreshLanguageSurface)

local languageItems = {}
local closeLanguageMenu

local function clearLanguageItems()
    for _, item in ipairs(languageItems) do
        item:Destroy()
    end

    languageItems = {}
end

closeLanguageMenu = function()
    if not languageMenu.Visible then
        return
    end

    languageMenu.Visible = false
    languageMenu.Size = UDim2.fromOffset(languageMenu.Size.X.Offset, 0)
end

local function openLanguageMenu()
    local scale = menuScale.Scale
    local fieldPosition = languageField.AbsolutePosition
    local fieldSize = languageField.AbsoluteSize

    -- Always drop below the field: top-left anchor, so the height animation
    -- grows downwards and the top edge never moves.
    languageMenu.AnchorPoint = Vector2.new(0, 0)
    languageMenu.Size = UDim2.fromOffset(fieldSize.X, 0)
    pinToScreen(
        languageMenu,
        fieldPosition.X,
        fieldPosition.Y + fieldSize.Y + 4 * scale
    )

    if DEBUG_LAYOUT then
        print(
            "[shitaro] field", fieldPosition.X, fieldPosition.Y,
            fieldSize.X, fieldSize.Y, "scale", scale
        )
        print(
            "[shitaro] curtain",
            languageMenu.AbsolutePosition.X,
            languageMenu.AbsolutePosition.Y,
            "size", languageMenu.Size.X.Offset, languageMenu.Size.Y.Offset
        )
    end

    -- keep the surface in sync with the menu every time it opens
    refreshLanguageSurface()
    languageCorner.CornerRadius = UDim.new(0, 10 * scale)

    clearLanguageItems()

    local index = 0

    for _, id in ipairs(languageOrder) do
        if id ~= currentLanguage then
            local item = make("TextButton", {
                Name = id,
                Position = UDim2.fromOffset(4 * scale, (4 + index * 28) * scale),
                Size = UDim2.new(1, -8 * scale, 0, 26 * scale),
                BackgroundColor3 = Color3.new(1, 1, 1),
                BackgroundTransparency = 1,
                ZIndex = 51,
            }, languageMenu)

            corner(item, UDim.new(0, 6 * scale))

            local label = make("TextLabel", {
                Text = languageNames[id] or id,
                TextSize = 12 * scale,
                TextColor3 = colors.sub,
                TextXAlignment = Enum.TextXAlignment.Center,
                Position = UDim2.fromOffset(0, 0),
                Size = UDim2.fromScale(1, 1),
                ZIndex = 52,
            }, item)

            connect(item.MouseEnter, function()
                animate(item, { BackgroundTransparency = 0.9 }, 0.1)
                animate(label, { TextColor3 = colors.text }, 0.1)
            end)

            connect(item.MouseLeave, function()
                animate(item, { BackgroundTransparency = 1 }, 0.1)
                animate(label, { TextColor3 = colors.sub }, 0.1)
            end)

            connect(item.Activated, function()
                setLanguage(id)
                closeLanguageMenu()
            end)

            table.insert(languageItems, item)
            index = index + 1
        end
    end

    local height = (4 + index * 28) * scale

    languageMenu.Visible = true

    animate(languageMenu, {
        Size = UDim2.fromOffset(fieldSize.X, height),
    }, 0.16)
end

connect(languageField.Activated, function()
    if languageMenu.Visible then
        closeLanguageMenu()
    else
        openLanguageMenu()
    end
end)

-- Click anywhere outside the curtain (but not on the field itself, which
-- owns the toggle) and it slides away.
local function insideRect(origin, size, point)
    return point.X >= origin.X - 2
        and point.X <= origin.X + size.X + 2
        and point.Y >= origin.Y - 2
        and point.Y <= origin.Y + size.Y + 2
end

connect(UserInputService.InputBegan, function(input)
    if not languageMenu.Visible then
        return
    end

    if input.UserInputType ~= Enum.UserInputType.MouseButton1
        and input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end

    if insideRect(
        languageField.AbsolutePosition,
        languageField.AbsoluteSize,
        input.Position
    ) then
        return
    end

    if insideRect(
        languageMenu.AbsolutePosition,
        languageMenu.AbsoluteSize,
        input.Position
    ) then
        return
    end

    closeLanguageMenu()
end)

onLanguageChanged(function()
    refreshLanguageValue()
end)

-- menu key ----------------------------------------------------------------

local bindRow, bindLabel = previewRow(settings, 2, "", true)
localize(bindLabel, "settings.keybind")

local bindField, bindValue = settingField(bindRow)

local bindKey = Enum.KeyCode.Insert
local capturingBind = false

local function refreshBindValue()
    bindValue.Text = capturingBind and "..." or bindKey.Name
end

refreshBindValue()

local function beginBindCapture()
    capturingBind = true
    refreshBindValue()
end

-- Left click / tap resets the field to "..." and starts listening. A second
-- click on the same field aborts the capture and restores the key name.
connect(bindField.Activated, function()
    closeLanguageMenu()

    if capturingBind then
        capturingBind = false
        refreshBindValue()
        return
    end

    beginBindCapture()
end)

-- Right click is kept as an alias for the same reset.
connect(bindField.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        closeLanguageMenu()
        beginBindCapture()
    end
end)

-- colour panel -------------------------------------------------------------
--
-- Docked to the right edge of the settings page: it is simply part of the
-- page, so it is on screen the moment the settings tab opens.
--
-- NOTE: `make()` gives every GuiObject BackgroundTransparency = 1 by default,
-- so any frame that must actually paint has to reset it to 0 explicitly.

-- Wrapped in a block: the chunk already sits near Lua's 200-local limit.
do
local function colorToHex(color)
    local r = math.floor(color.R * 255 + 0.5)
    local g = math.floor(color.G * 255 + 0.5)
    local b = math.floor(color.B * 255 + 0.5)

    return string.format("#%02X%02X%02X", r, g, b)
end

local panelW, panelH = 330, 356
local pad = 16
local content = panelW - pad * 2
local hueW = 26
local svH = 140
local svW = content - hueW - 10

-- The panel lives on the window (not inside the settings page) so it stays on
-- screen the whole time the settings tab is open.
local colorPanel = make("Frame", {
    Name = "ColorPanel",
    Visible = false,
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -10, 0, 51),
    Size = UDim2.fromOffset(panelW, panelH),
    BackgroundTransparency = 1,
    ClipsDescendants = true,
    ZIndex = 5,
}, window)

-- Same radius / stroke as the window, and no fill of its own: a second
-- layered background would render darker than the menu surface.
corner(colorPanel, UDim.new(0, 10))
stroke(colorPanel, 0.935)

-- the row card fills the space left of the docked panel (10 + gap 20 + panel)
panelWidths[settingsScroll] = window.Size.X.Offset - PANEL_RESERVE
picker.panel = colorPanel

local panelIcon = image(colorPanel, "sliders", 20)
panelIcon.Position = UDim2.fromOffset(pad, 14)
panelIcon.ImageColor3 = colors.accent
panelIcon.ZIndex = 6

picker.title = localize(make("TextLabel", {
    Text = "",
    TextSize = 15,
    FontFace = fonts.bold,
    Position = UDim2.fromOffset(pad + 28, 10),
    Size = UDim2.new(1, -60, 0, 18),
    ZIndex = 6,
}, colorPanel), "palette.title")

picker.subtitle = localize(make("TextLabel", {
    Text = "",
    TextSize = 12,
    TextColor3 = colors.dim,
    Position = UDim2.fromOffset(pad + 28, 28),
    Size = UDim2.new(1, -60, 0, 14),
    ZIndex = 6,
}, colorPanel), "palette.subtitle")


-- live preview bar
local previewBar = make("Frame", {
    Name = "PreviewBar",
    Position = UDim2.fromOffset(pad, 58),
    Size = UDim2.fromOffset(content, 26),
    BackgroundColor3 = menuColor,
    BackgroundTransparency = menuTransparency,
    ZIndex = 6,
}, colorPanel)

corner(previewBar, UDim.new(0, 8))
stroke(previewBar, 0.94)

-- saturation / value square -------------------------------------------------

local svY = 96

local sv = make("Frame", {
    Name = "SVArea",
    Position = UDim2.fromOffset(pad, svY),
    Size = UDim2.fromOffset(svW, svH),
    BackgroundColor3 = Color3.fromHSV(1, 1, 1),
    BackgroundTransparency = 0,
    ZIndex = 6,
}, colorPanel)

corner(sv, UDim.new(0, 8))

local svWhite = make("Frame", {
    Size = UDim2.fromScale(1, 1),
    BackgroundColor3 = Color3.new(1, 1, 1),
    BackgroundTransparency = 0,
    ZIndex = 6,
}, sv)

corner(svWhite, UDim.new(0, 8))

make("UIGradient", {
    Color = ColorSequence.new(Color3.new(1, 1, 1)),
    Transparency = NumberSequence.new(0, 1),
}, svWhite)

local svBlack = make("Frame", {
    Size = UDim2.fromScale(1, 1),
    BackgroundColor3 = Color3.new(0, 0, 0),
    BackgroundTransparency = 0,
    ZIndex = 7,
}, sv)

corner(svBlack, UDim.new(0, 8))

make("UIGradient", {
    Color = ColorSequence.new(Color3.new(0, 0, 0)),
    Transparency = NumberSequence.new(1, 0),
    Rotation = 90,
}, svBlack)

local svCursor = make("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Size = UDim2.fromOffset(14, 14),
    BackgroundTransparency = 1,
    ZIndex = 8,
}, sv)

corner(svCursor, UDim.new(1, 0))

make("UIStroke", {
    Color = Color3.new(1, 1, 1),
    Transparency = 0.1,
    Thickness = 2,
}, svCursor)

-- hue strip ----------------------------------------------------------------

local hueBar = make("Frame", {
    Name = "HueBar",
    Position = UDim2.fromOffset(pad + svW + 10, svY),
    Size = UDim2.fromOffset(hueW, svH),
    BackgroundColor3 = Color3.new(1, 1, 1),
    BackgroundTransparency = 0,
    ZIndex = 6,
}, colorPanel)

corner(hueBar, UDim.new(1, 0))

make("UIGradient", {
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 0, 0)),
        ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 255, 0)),
        ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 255, 0)),
        ColorSequenceKeypoint.new(0.50, Color3.fromRGB(0, 255, 255)),
        ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 0, 255)),
        ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 0, 255)),
        ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 0, 0)),
    }),
    Rotation = 90,
}, hueBar)

local hueCursor = make("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0),
    Size = UDim2.new(1, 8, 0, 12),
    BackgroundTransparency = 1,
    ZIndex = 8,
}, hueBar)

corner(hueCursor, UDim.new(1, 0))

make("UIStroke", {
    Color = Color3.new(1, 1, 1),
    Transparency = 0.05,
    Thickness = 2,
}, hueCursor)

local svHit = make("TextButton", {
    Name = "SVHit",
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    Text = "",
    ZIndex = 9,
}, sv)

local hueHit = make("TextButton", {
    Name = "HueHit",
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    Text = "",
    ZIndex = 9,
}, hueBar)

-- hex readout --------------------------------------------------------------

local hexY = svY + svH + 12

local hexSwatch = make("Frame", {
    Name = "HexSwatch",
    Position = UDim2.fromOffset(pad, hexY),
    Size = UDim2.fromOffset(24, 24),
    BackgroundColor3 = menuColor,
    BackgroundTransparency = 0,
    ZIndex = 6,
}, colorPanel)

corner(hexSwatch, UDim.new(0, 6))
stroke(hexSwatch, 0.86)

local hexLabel = make("TextLabel", {
    Text = "",
    TextSize = 14,
    FontFace = fonts.bold,
    Position = UDim2.fromOffset(pad + 32, hexY),
    Size = UDim2.fromOffset(120, 24),
    ZIndex = 6,
}, colorPanel)

-- transparency slider ------------------------------------------------------

local opacityLabelY = hexY + 32

picker.opacityTitle = localize(make("TextLabel", {
    Text = "",
    TextSize = 12,
    TextColor3 = colors.dim,
    Position = UDim2.fromOffset(pad, opacityLabelY),
    Size = UDim2.fromOffset(92, 18),
    ZIndex = 6,
}, colorPanel), "settings.opacity")

local opValue = make("TextLabel", {
    Text = "",
    TextSize = 12,
    TextColor3 = colors.sub,
    TextXAlignment = Enum.TextXAlignment.Right,
    Position = UDim2.fromOffset(panelW - pad - 48, opacityLabelY),
    Size = UDim2.fromOffset(48, 18),
    ZIndex = 6,
}, colorPanel)

local opTrackX = pad + 96
local opTrackW = panelW - pad - 58 - opTrackX

local opTrack = make("Frame", {
    Name = "OpacityTrack",
    Position = UDim2.fromOffset(opTrackX, opacityLabelY + 8),
    Size = UDim2.fromOffset(opTrackW, 4),
    BackgroundColor3 = Color3.new(1, 1, 1),
    BackgroundTransparency = 0.84,
    ZIndex = 6,
}, colorPanel)

corner(opTrack, UDim.new(1, 0))

local opFill = make("Frame", {
    Name = "OpacityFill",
    Size = UDim2.fromScale(0, 1),
    BackgroundColor3 = colors.accent,
    BackgroundTransparency = 0.35,
    ZIndex = 7,
}, opTrack)

corner(opFill, UDim.new(1, 0))

local opKnob = make("Frame", {
    Name = "OpacityKnob",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0, 0.5),
    Size = UDim2.fromOffset(12, 12),
    BackgroundColor3 = Color3.new(1, 1, 1),
    BackgroundTransparency = 0.05,
    ZIndex = 8,
}, opTrack)

corner(opKnob, UDim.new(1, 0))

local opHit = make("TextButton", {
    Name = "OpacityHit",
    Position = UDim2.new(0, 0, 0, -10),
    Size = UDim2.new(1, 0, 0, 24),
    BackgroundTransparency = 1,
    Text = "",
    ZIndex = 9,
}, opTrack)

-- buttons ------------------------------------------------------------------

local buttonY = opacityLabelY + 34

local resetButton = make("TextButton", {
    Name = "PickerReset",
    Position = UDim2.fromOffset(pad, buttonY),
    Size = UDim2.fromOffset(94, 30),
    BackgroundColor3 = Color3.new(1, 1, 1),
    BackgroundTransparency = 0.94,
    Text = "",
    ZIndex = 6,
}, colorPanel)

corner(resetButton, UDim.new(0, 8))
stroke(resetButton, 0.9)

localize(make("TextLabel", {
    Text = "",
    TextSize = 13,
    TextColor3 = colors.sub,
    TextXAlignment = Enum.TextXAlignment.Center,
    Size = UDim2.fromScale(1, 1),
    ZIndex = 7,
}, resetButton), "palette.reset")

local applyButton = make("TextButton", {
    Name = "PickerApply",
    Position = UDim2.fromOffset(pad + 104, buttonY),
    Size = UDim2.fromOffset(panelW - pad * 2 - 104, 30),
    BackgroundColor3 = colors.accent,
    BackgroundTransparency = 0.78,
    Text = "",
    ZIndex = 6,
}, colorPanel)

corner(applyButton, UDim.new(0, 8))

make("UIStroke", {
    Color = colors.accent,
    Transparency = 0.45,
    Thickness = 1,
    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
}, applyButton)

localize(make("TextLabel", {
    Text = "",
    TextSize = 13,
    FontFace = fonts.bold,
    TextColor3 = colors.text,
    TextXAlignment = Enum.TextXAlignment.Center,
    Size = UDim2.fromScale(1, 1),
    ZIndex = 7,
}, applyButton), "palette.apply")

-- esp targets edit a plain colour: no transparency row, panel is shorter
function picker.layoutFor(kind)
    local esp = kind == "esp"
    local shift = esp and 34 or 0

    picker.opacityTitle.Visible = not esp
    opValue.Visible = not esp
    opTrack.Visible = not esp

    resetButton.Position = UDim2.fromOffset(pad, buttonY - shift)
    applyButton.Position = UDim2.fromOffset(pad + 104, buttonY - shift)
    colorPanel.Size = UDim2.fromOffset(panelW, panelH - shift)
end

-- picker state -------------------------------------------------------------

local pickedHue, pickedSat, pickedVal = menuColor:ToHSV()
local pickedAlpha = menuTransparency

local function pickedColor()
    return Color3.fromHSV(pickedHue, pickedSat, pickedVal)
end

local function refreshPalette()
    local color = pickedColor()

    sv.BackgroundColor3 = Color3.fromHSV(pickedHue, 1, 1)
    svCursor.Position = UDim2.fromScale(pickedSat, 1 - pickedVal)
    hueCursor.Position = UDim2.fromScale(0.5, pickedHue)
    previewBar.BackgroundColor3 = color
    previewBar.BackgroundTransparency = pickedAlpha
    hexSwatch.BackgroundColor3 = color
    hexLabel.Text = colorToHex(color)
    -- 0 % = fully opaque at the far left, 100 % = fully transparent at the
    -- far right; handle and fill travel with the value, never against it.
    opValue.Text = tostring(math.floor(pickedAlpha * 100 + 0.5)) .. "%"
    opFill.Size = UDim2.fromScale(pickedAlpha, 1)
    opKnob.Position = UDim2.fromScale(pickedAlpha, 0.5)

    -- esp colours are applied live while dragging
    if picker.target and picker.target.kind == "esp"
        and picker.target.apply then
        picker.target.apply(color)
    end
end

local function updateFromSV(x, y)
    local origin = sv.AbsolutePosition
    local size = sv.AbsoluteSize

    pickedSat = math.clamp((x - origin.X) / math.max(1, size.X), 0, 1)
    pickedVal = 1 - math.clamp((y - origin.Y) / math.max(1, size.Y), 0, 1)
    refreshPalette()
end

local function updateFromHue(x, y)
    local origin = hueBar.AbsolutePosition
    local size = hueBar.AbsoluteSize

    pickedHue = math.clamp((y - origin.Y) / math.max(1, size.Y), 0, 1)
    refreshPalette()
end

local function updateFromOpacity(x, y)
    local origin = opTrack.AbsolutePosition
    local size = opTrack.AbsoluteSize

    pickedAlpha = math.clamp((x - origin.X) / math.max(1, size.X), 0, 1)
    refreshPalette()
end

-- picker target -------------------------------------------------------------
-- The panel edits the window surface: menu colour + menu transparency.

function picker.refreshText()
    local target = picker.target

    if target and target.kind == "esp" then
        picker.title.Text = L("esp.picker.title")
        picker.subtitle.Text = L("esp." .. target.feature)
            .. " - " .. L("esp.state." .. target.state)
    else
        picker.title.Text = L("palette.title")
        picker.subtitle.Text = L("palette.subtitle")
    end
end

function picker.notify()
    for _, callback in ipairs(picker.listeners) do
        callback()
    end
end

function picker.setTarget(target, color)
    picker.target = target

    local hue, sat, val = color:ToHSV()

    pickedHue, pickedSat, pickedVal = hue, sat, val
    pickedAlpha = target.kind == "menu"
        and window.BackgroundTransparency
        or 0

    picker.layoutFor(target.kind)
    refreshPalette()
    picker.refreshText()
end

function picker.sync(tab)
    -- leaving the visuals tab closes an open esp colour editor
    if picker.espOpen and tab ~= tabs[3] and picker.onLeave then
        picker.onLeave()
    end

    if tab == tabs[6] then
        picker.setTarget({ kind = "menu" }, window.BackgroundColor3)
        colorPanel.Visible = true
    elseif tab == tabs[3] and picker.espOpen then
        colorPanel.Visible = true
    else
        colorPanel.Visible = false
    end
end

-- the committed value is applied once the pointer is released
local function commitPalette()
    if picker.target and picker.target.kind == "esp" then
        if picker.target.apply then
            picker.target.apply(pickedColor())
        end

        return
    end

    applyMenuStyle(pickedColor(), pickedAlpha)
end

connect(svHit.InputBegan, function(input)
    if not isPressInput(input) then
        return
    end

    beginUIDrag(input, updateFromSV, commitPalette)
end)

connect(hueHit.InputBegan, function(input)
    if not isPressInput(input) then
        return
    end

    beginUIDrag(input, updateFromHue, commitPalette)
end)

connect(opHit.InputBegan, function(input)
    if not isPressInput(input) then
        return
    end

    beginUIDrag(input, updateFromOpacity, commitPalette)
end)

connect(resetButton.Activated, function()
    if picker.target and picker.target.kind == "esp"
        and picker.target.default then
        pickedHue, pickedSat, pickedVal = picker.target.default:ToHSV()
    else
        pickedHue, pickedSat, pickedVal = colors.bg:ToHSV()
        pickedAlpha = 0.16
    end

    refreshPalette()
end)

connect(applyButton.Activated, function()
    commitPalette()

    -- an esp colour is already live: "apply" just closes the editor
    if picker.target and picker.target.kind == "esp" and picker.onLeave then
        picker.onLeave()
    end
end)


onLanguageChanged(function()
    picker.refreshText()
end)

refreshPalette()
picker.refreshText()
end

-- watermark card -----------------------------------------------------------

local watermarkOffset = Vector2.new(0, 0)
local watermarkSizePercent = 100

local function applyWatermarkLayout()
    watermarkScale.Scale = watermarkSizePercent / 100
    watermark.Position = UDim2.new(
        1,
        watermarkOffset.X,
        0,
        watermarkOffset.Y
    )
end

-- compact slider used by the watermark rows (no instances are created while
-- dragging: only Position/Size/Text of existing objects change)
local function rowSlider(row, name, minValue, maxValue, format, onChange)
    local area = make("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.new(0.47, 0, 0, 24),
        ZIndex = 2,
    }, row)

    local valueLabel = make("TextLabel", {
        Name = name,
        Text = "",
        TextSize = 12,
        TextColor3 = colors.sub,
        TextXAlignment = Enum.TextXAlignment.Right,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.fromOffset(54, 18),
        ZIndex = 2,
    }, area)

    local track = make("Frame", {
        Name = name .. "Track",
        Position = UDim2.new(0, 0, 0.5, -2),
        Size = UDim2.new(1, -62, 0, 4),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BackgroundTransparency = 0.84,
        ZIndex = 2,
    }, area)

    corner(track, UDim.new(1, 0))

    local fill = make("Frame", {
        Size = UDim2.fromScale(0, 1),
        BackgroundColor3 = colors.accent,
        BackgroundTransparency = 0.35,
        ZIndex = 3,
    }, track)

    corner(fill, UDim.new(1, 0))

    local knob = make("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0, 0.5),
        Size = UDim2.fromOffset(12, 12),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BackgroundTransparency = 0.05,
        ZIndex = 4,
    }, track)

    corner(knob, UDim.new(1, 0))

    local hit = make("TextButton", {
        Name = name .. "Hit",
        Position = UDim2.new(0, 0, 0, -10),
        Size = UDim2.new(1, 0, 0, 24),
        BackgroundTransparency = 1,
        Text = "",
        ZIndex = 5,
    }, track)

    local value = minValue

    local function paint()
        local span = math.max(0.0001, maxValue - minValue)
        local fraction = (value - minValue) / span

        fill.Size = UDim2.fromScale(fraction, 1)
        knob.Position = UDim2.fromScale(fraction, 0.5)
        valueLabel.Text = format(value)
    end

    local function set(newValue, notify)
        value = math.clamp(newValue, minValue, maxValue)
        paint()

        if notify and onChange then
            onChange(value)
        end
    end

    local function moveTo(x)
        local origin = track.AbsolutePosition
        local size = track.AbsoluteSize
        local fraction = math.clamp((x - origin.X) / math.max(1, size.X), 0, 1)

        set(minValue + fraction * (maxValue - minValue), true)
    end

    connect(hit.InputBegan, function(input)
        if not isPressInput(input) then
            return
        end

        beginUIDrag(input, moveTo, nil)
    end)

    paint()

    return {
        set = set,
        get = function()
            return value
        end,
    }
end

local wmSliders = {}

local function setWatermarkOffset(x, y)
    watermarkOffset = Vector2.new(
        math.clamp(x, -800, 800),
        math.clamp(y, -500, 500)
    )

    applyWatermarkLayout()
    wmSliders.x.set(watermarkOffset.X, false)
    wmSliders.y.set(watermarkOffset.Y, false)
end

-- size
local watermarkCard, watermarkHolder = previewPanel(settingsScroll, "settings.watermark", 2, 4)

-- The watermark block simply sits a little under the language / menu-key
-- card: same column, just a bit more air than the default 12 px gap.
panelGapBefore[watermarkHolder] = 16

local wmSizeRow, wmSizeLabel = previewRow(watermarkCard, 1, "", true)
localize(wmSizeLabel, "settings.wmScale")

wmSliders.size = rowSlider(
    wmSizeRow,
    "WatermarkSize",
    50,
    200,
    function(value)
        return tostring(math.floor(value + 0.5)) .. "%"
    end,
    function(value)
        watermarkSizePercent = value
        applyWatermarkLayout()
    end
)

wmSliders.size.set(watermarkSizePercent, false)

-- position X
local wmXRow, wmXLabel = previewRow(watermarkCard, 2, "", true)
localize(wmXLabel, "settings.wmX")

wmSliders.x = rowSlider(
    wmXRow,
    "WatermarkX",
    -800,
    800,
    function(value)
        local rounded = math.floor(value + 0.5)

        if rounded > 0 then
            return "+" .. rounded .. " px"
        end

        return tostring(rounded) .. " px"
    end,
    function(value)
        setWatermarkOffset(value, watermarkOffset.Y)
    end
)

wmSliders.x.set(watermarkOffset.X, false)

-- position Y
local wmYRow, wmYLabel = previewRow(watermarkCard, 3, "", true)
localize(wmYLabel, "settings.wmY")

wmSliders.y = rowSlider(
    wmYRow,
    "WatermarkY",
    -500,
    500,
    function(value)
        return tostring(math.floor(value + 0.5)) .. " px"
    end,
    function(value)
        setWatermarkOffset(watermarkOffset.X, value)
    end
)

wmSliders.y.set(watermarkOffset.Y, false)

-- reset
local wmResetRow = previewRow(watermarkCard, 4, "", false)

local wmResetButton = make("TextButton", {
    Name = "WatermarkReset",
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -10, 0.5, 0),
    Size = UDim2.new(0.47, 0, 0, 24),
    BackgroundColor3 = Color3.new(1, 1, 1),
    BackgroundTransparency = 0.94,
    Text = "",
    ZIndex = 2,
}, wmResetRow)

corner(wmResetButton, UDim.new(0, 6))
stroke(wmResetButton, 0.9)

localize(make("TextLabel", {
    Text = "",
    TextSize = 11,
    TextColor3 = colors.sub,
    TextXAlignment = Enum.TextXAlignment.Center,
    Size = UDim2.fromScale(1, 1),
    ZIndex = 3,
}, wmResetButton), "settings.wmReset")

connect(wmResetButton.Activated, function()
    watermarkSizePercent = 100
    wmSliders.size.set(watermarkSizePercent, false)
    setWatermarkOffset(0, 0)
    applyWatermarkLayout()
end)

local hintRow, hintLabel = previewRow(settings, 3, "", false)
localize(hintLabel, "settings.hint")
hintLabel.TextSize = 11

applyWatermarkLayout()
applyWatermarkTheme()

-- UIScale scales all children together.

local function layoutPreview()
    local width = window.Size.X.Offset
    local columnWidth = (width - 36) / 3

    for parent, group in pairs(panelGroups) do
        -- The space the cards actually get: on the settings page the right
        -- docked colour panel already takes 370 px away, so "narrow" has to be
        -- judged against the free area, not against the window width.
        local available = panelWidths[parent] or (width - 20)
        local narrow = available < 620

        local y = 10

        for index, panel in ipairs(group) do
            -- The gap is the space this panel asks for *above itself*, so it
            -- has to be applied before the panel is placed.
            if narrow and index > 1 then
                y = y + (panelGapBefore[panel] or 12)
            end

            panel.Position = narrow
                and UDim2.fromOffset(10, y)
                or UDim2.fromOffset(
                    10 + (index - 1) * (columnWidth + 8),
                    10
                )

            panel.Size = UDim2.fromOffset(available, panel.Size.Y.Offset)

            if narrow then
                y = y + panel.Size.Y.Offset
            end
        end
    end
end

local function clampWindow()
    local size = window.AbsoluteSize
    local position = window.Position

    window.Position = UDim2.fromOffset(
        math.clamp(
            position.X.Offset,
            safeOrigin.X,
            safeOrigin.X + math.max(0, safeSize.X - size.X)
        ),
        math.clamp(
            position.Y.Offset,
            safeOrigin.Y,
            safeOrigin.Y + math.max(0, safeSize.Y - size.Y)
        )
    )
end

local function layoutNavigation()
    local width = window.Size.X.Offset
    local touch = false
    local narrow = width < 620
    local cellHeight = touch and 44 or 26

    local navHeight = narrow
        and (cellHeight * 2 + 8)
        or (cellHeight + 6)

    nav.Size = UDim2.fromOffset(
        narrow and (width - 20) or 0,
        navHeight
    )

    nav.AutomaticSize = narrow
        and Enum.AutomaticSize.None
        or Enum.AutomaticSize.X

    navCorner.CornerRadius = UDim.new(
        0,
        narrow and 12 or math.floor(navHeight / 2)
    )

    body.Size = UDim2.new(
        1, 0,
        1, -(41 + navHeight + 17)
    )

    tabRow.Size = UDim2.fromOffset(
        narrow and (width - 26) or 0,
        navHeight - 6
    )

    tabRow.AutomaticSize = narrow
        and Enum.AutomaticSize.None
        or Enum.AutomaticSize.X

    local useGrid = navigationLayout:IsA("UIGridLayout")

    if narrow ~= useGrid then
        navigationLayout:Destroy()

        if narrow then
            navigationLayout = make("UIGridLayout", {
                SortOrder = Enum.SortOrder.LayoutOrder,
                FillDirection = Enum.FillDirection.Horizontal,
                FillDirectionMaxCells = 3,
            }, tabRow)
        else
            navigationLayout = row(tabRow, 2)
        end
    end

    if narrow then
        navigationLayout.CellPadding = UDim2.fromOffset(2, 2)
        navigationLayout.CellSize = UDim2.new(
            1 / 3, -4 / 3,
            0, cellHeight
        )
    end

    for _, tab in ipairs(tabs) do
        tab.button.AutomaticSize = narrow
            and Enum.AutomaticSize.None
            or Enum.AutomaticSize.X

        tab.button.Size = UDim2.fromOffset(0, cellHeight)
    end

    highlight.Visible = not narrow

    for _, tab in ipairs(tabs) do
        tab.button.BackgroundColor3 = Color3.new(1, 1, 1)
        tab.button.BackgroundTransparency =
            narrow and tab == selected and 0.925 or 1
    end

    task.defer(updateHighlight)
    layoutPreview()
end

local function fitScreen()
    gesture = nil
    applyWatermarkLayout()

    local viewport = gui.AbsoluteSize
    safeOrigin = Vector2.zero

    safeSize = Vector2.new(
        math.max(1, viewport.X),
        math.max(1, viewport.Y)
    )

    -- Reference screenshot: 1568 x 724.
    -- Approximate window bounds: (224, 14) to (1300, 662).
    local referenceScale = math.min(
        safeSize.X / 1568,
        safeSize.Y / 724
    )

    menuScale.Scale = (1076 / 780) * referenceScale
    window.Size = UDim2.fromOffset(780, 470)

    window.Position = UDim2.fromOffset(
        (safeSize.X - 1568 * referenceScale) / 2
            + 224 * referenceScale,
        (safeSize.Y - 724 * referenceScale) / 2
            + 14 * referenceScale
    )

    layoutNavigation()
end

-- Translated labels change width, so the highlight/nav must be redrawn.
onLanguageChanged(function()
    task.defer(function()
        layoutNavigation()
        updateHighlight()
    end)
end)

connect(
    gui:GetPropertyChangedSignal("AbsoluteSize"),
    fitScreen
)

connect(
    window:GetPropertyChangedSignal("Size"),
    layoutNavigation
)

connect(
    UserInputService:GetPropertyChangedSignal("TouchEnabled"),
    layoutNavigation
)

for _, tab in ipairs(tabs) do
    connect(tab.button.Activated, function()
        closeLanguageMenu()
        task.defer(layoutNavigation)
    end)
end

-- Input

local function beginGesture(input, target, resize)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1
        and input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end

    gesture = {
        input = input,
        target = target,
        resize = resize,
        origin = input.Position,
        position = target.Position,
        size = target.Size,
        scale = menuScale.Scale,
    }
end

-- Use GUI hit-testing instead of comparing global and GUI coordinates.
dragHandle.ZIndex = 30
dragHandle.Active = true

connect(dragHandle.InputBegan, function(input)
    if not window.Visible then
        return
    end

    beginGesture(input, window, false)
end)

connect(grip.InputBegan, function(input)
    beginGesture(input, window, true)
end)

-- The watermark itself is the button; no full-screen input layer.
-- Feature modules ------------------------------------------------------------
-- ESP, camera and aimbot live in modules/*.lua. They receive this context
-- (the shared UI helpers) and are loaded in the same order the old single
-- file ran them. A module that fails to load or run only warns: the menu
-- and the other modules keep working.
do
    local Loader = ...

    local ctx = {
        playerGui = playerGui, player = player, Players = Players,
        RunService = RunService, UserInputService = UserInputService,
        uiState = uiState, gui = gui, connect = connect, make = make,
        corner = corner, colors = colors, animate = animate,
        window = window, tabs = tabs, panelWidths = panelWidths,
        panelGapBefore = panelGapBefore, PANEL_RESERVE = PANEL_RESERVE,
        pageScroll = pageScroll, previewPanel = previewPanel,
        previewRow = previewRow, previewScroll = previewScroll,
        rowSlider = rowSlider, layoutPreview = layoutPreview,
        localize = localize, locale = locale, picker = picker,
        settingField = settingField, closeLanguageMenu = closeLanguageMenu,
        refreshBindValue = refreshBindValue, bindField = bindField,
        Loader = Loader, L = L,
        -- the menu key state is mutable, so it is shared through accessors
        getBindKey = function() return bindKey end,
        isCapturingBind = function() return capturingBind end,
        setCapturingBind = function(value) capturingBind = value end,
    }

    local function trace(err)
        return debug.traceback(tostring(err), 2)
    end

    for _, path in ipairs({
        "modules/esp.lua",
        "modules/camera.lua",
        "modules/aim.lua",
        "modules/skins.lua",
    }) do
        if not Loader then
            warn("[shitaro] no loader, module skipped: " .. path)
        else
            local okLoad, entry = pcall(Loader.module, path)

            if not okLoad or type(entry) ~= "function" then
                warn("[shitaro] cannot load " .. path .. ": " .. tostring(entry))
            else
                local okRun, err = xpcall(entry, trace, ctx)

                if not okRun then
                    warn("[shitaro] " .. path .. " failed: " .. tostring(err))
                end
            end
        end
    end
end

-- Shutdown confirmation ------------------------------------------------------
-- "x" in the header does not close the menu: it turns the cheat off, so it
-- always asks first. The sheet swallows clicks on everything underneath it.

-- Wrapped in a block: the chunk already sits near Lua's 200-local limit.
do
local sheet = make("TextButton", {
    Name = "ShutdownConfirm",
    Visible = false,
    Size = UDim2.fromScale(1, 1),
    BackgroundColor3 = Color3.new(),
    BackgroundTransparency = 0.45,
    AutoButtonColor = false,
    Text = "",
    ZIndex = 40,
}, window)

corner(sheet, UDim.new(0, 10))

local dialog = make("Frame", {
    Name = "ShutdownDialog",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(330, 150),
    BackgroundColor3 = colors.bg,
    BackgroundTransparency = 0.02,
    ZIndex = 41,
}, sheet)

corner(dialog, UDim.new(0, 10))
stroke(dialog, 0.9)

onMenuStyleChanged(function(color)
    dialog.BackgroundColor3 = color
end)

localize(make("TextLabel", {
    Text = "",
    FontFace = fonts.bold,
    TextSize = 13,
    TextColor3 = colors.text,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Center,
    Position = UDim2.fromOffset(16, 12),
    Size = UDim2.new(1, -32, 0, 20),
    ZIndex = 41,
}, dialog), "close.title")

localize(make("TextLabel", {
    Text = "",
    TextSize = 11,
    TextColor3 = colors.dim,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
    TextWrapped = true,
    Position = UDim2.fromOffset(16, 36),
    Size = UDim2.new(1, -32, 0, 56),
    ZIndex = 41,
}, dialog), "close.body")

local actions = make("Frame", {
    AnchorPoint = Vector2.new(1, 1),
    Position = UDim2.new(1, -16, 1, -14),
    Size = UDim2.fromOffset(0, 30),
    AutomaticSize = Enum.AutomaticSize.X,
    ZIndex = 41,
}, dialog)

row(actions, 8, Enum.HorizontalAlignment.Right)

local function dialogButton(parent, name, key, order, red)
    local button = make("TextButton", {
        Name = name,
        Size = UDim2.fromOffset(0, 30),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = red and Color3.fromRGB(198, 58, 58)
            or Color3.new(1, 1, 1),
        BackgroundTransparency = red and 0.05 or 0.952,
        AutoButtonColor = false,
        FontFace = fonts.bold,
        TextSize = 12,
        TextColor3 = red and Color3.new(1, 1, 1) or colors.dim,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
        LayoutOrder = order,
        ZIndex = 41,
    }, parent)

    padding(button, 16, 16, 0, 0)
    corner(button, UDim.new(0, 8))

    if red then
        button.BackgroundTransparency = 0.05
    else
        stroke(button, 0.925)
    end

    connect(button.MouseEnter, function()
        animate(button, {
            BackgroundTransparency = red and 0 or 0.9,
        })
    end)

    connect(button.MouseLeave, function()
        animate(button, {
            BackgroundTransparency = red and 0.05 or 0.952,
        })
    end)

    return localize(button, key)
end

local cancelButton = dialogButton(actions, "ShutdownCancel", "close.cancel", 1, false)
local confirmButton = dialogButton(actions, "ShutdownConfirmOK", "close.confirm", 2, true)

openShutdownConfirm = function()
    closeLanguageMenu()
    gesture = nil
    sheet.Visible = true
end

connect(closeButton.Activated, function()
    openShutdownConfirm()
end)

connect(cancelButton.Activated, function()
    sheet.Visible = false
end)

-- A click on the dim area does nothing on purpose: the only ways out are
-- "cancel" or a full shutdown.

connect(confirmButton.Activated, function()
    local wasOpen = window.Visible

    sheet.Visible = false
    capturingBind = false
    window.Visible = false

    if uiState.shutdown then
        pcall(uiState.shutdown, wasOpen)
    end

    -- an older build of this script may have left its overlay behind
    local overlay = playerGui:FindFirstChild("ShitaroESP")

    if overlay then
        overlay:Destroy()
    end

    gui:Destroy()
end)
end

-- Games lock the mouse to the centre on every one of their frames, so undoing
-- it afterwards is not enough: while the menu is open the write from the game
-- is blocked at the metatable. If the executor has no hooking API the guard
-- flag is useless and the per-frame re-assert below does the job instead.
local cursorLocked = false
local cursorHookInstalled = false

local function wrapCallback(callback)
    if type(newcclosure) ~= "function" then
        return callback
    end

    local ok, wrapped = pcall(newcclosure, callback)

    return ok and wrapped or callback
end

local function installCursorHook()
    if cursorHookInstalled then
        return
    end

    cursorHookInstalled = true

    if type(getrawmetatable) ~= "function"
        or type(hookmetamethod) ~= "function" then
        return
    end

    local okMeta, meta = pcall(getrawmetatable, UserInputService)

    if not okMeta or type(meta) ~= "table" then
        return
    end

    local oldNewIndex = meta.__newindex

    if type(oldNewIndex) ~= "function" then
        return
    end

    pcall(hookmetamethod, UserInputService, "__newindex", wrapCallback(
        function(self, key, value)
            if cursorLocked
                and not uiState.closed
                and (key == "MouseBehavior" or key == "MouseIconEnabled") then
                return
            end

            return oldNewIndex(self, key, value)
        end
    ))
end

-- writes that have to go through even while the game is blocked
local function writeCursor(behavior, icon)
    local wasLocked = cursorLocked
    cursorLocked = false

    pcall(function()
        if UserInputService.MouseBehavior ~= behavior then
            UserInputService.MouseBehavior = behavior
        end

        if UserInputService.MouseIconEnabled ~= icon then
            UserInputService.MouseIconEnabled = icon
        end
    end)

    cursorLocked = wasLocked
end

local function forceCursor()
    uiState.mouseBehavior = UserInputService.MouseBehavior
    uiState.mouseIcon = UserInputService.MouseIconEnabled

    installCursorHook()
    writeCursor(Enum.MouseBehavior.Default, true)
    cursorLocked = true
end

local function releaseCursor()
    cursorLocked = false

    writeCursor(
        uiState.mouseBehavior or Enum.MouseBehavior.Default,
        uiState.mouseIcon ~= false
    )
end

local function toggleMenu()
    closeLanguageMenu()
    window.Visible = not window.Visible
    gesture = nil

    if window.Visible then
        clampWindow()
        forceCursor()
    else
        releaseCursor()
    end
end

-- Keep re-asserting it: games re-lock the mouse on every one of their frames.
-- Heartbeat is checked as well, because it runs after the game's own render
-- step, so the cursor wins even against a camera script that never gives up.
local function assertCursor()
    if not window.Visible then
        -- menu closed: the game gets its mouse back
        cursorLocked = false
        return
    end

    if UserInputService.MouseBehavior == Enum.MouseBehavior.Default
        and UserInputService.MouseIconEnabled then
        return
    end

    writeCursor(Enum.MouseBehavior.Default, true)
end

connect(RunService.RenderStepped, assertCursor)

if RunService.Heartbeat then
    connect(RunService.Heartbeat, assertCursor)
end

if RunService.Stepped then
    connect(RunService.Stepped, assertCursor)
end

-- last render priority: runs after the game's own render step
if RunService.BindToRenderStep then
    pcall(function()
        RunService:UnbindFromRenderStep("ShitaroCursor")
    end)

    pcall(function()
        RunService:BindToRenderStep(
            "ShitaroCursor",
            Enum.RenderPriority.Last.Value,
            assertCursor
        )
    end)
end

-- Full shutdown: called from the confirm dialog before the gui is destroyed.
uiState.shutdown = function(wasOpen)
    if uiState.closed then
        return
    end

    uiState.closed = true
    cursorLocked = false

    pcall(function()
        RunService:UnbindFromRenderStep("ShitaroCursor")
    end)

    if wasOpen then
        releaseCursor()
    end

    pcall(function()
        getgenv().shitaro_dump = nil
    end)
end

-- Watermark: drag it anywhere with a finger or the cursor; a plain click
-- (no movement past the threshold) keeps the old toggle behaviour.
local watermarkGesture

local function moveWatermark(x, y)
    if not watermarkGesture then
        return
    end

    -- closed menu: the watermark stays put, a tap just re-opens the menu
    if not window.Visible then
        return
    end

    local deltaX = x - watermarkGesture.start.X
    local deltaY = y - watermarkGesture.start.Y

    if math.abs(deltaX) > 4 or math.abs(deltaY) > 4 then
        watermarkGesture.moved = true
    end

    if watermarkGesture.moved then
        setWatermarkOffset(
            watermarkGesture.offset.X + deltaX,
            watermarkGesture.offset.Y + deltaY
        )
    end
end

local function releaseWatermark()
    local clicked = watermarkGesture ~= nil
        and watermarkGesture.moved == false

    watermarkGesture = nil

    if clicked then
        toggleMenu()
    end
end

connect(watermark.InputBegan, function(input)
    if not isPressInput(input) then
        return
    end

    watermarkGesture = {
        start = input.Position,
        offset = watermarkOffset,
        moved = false,
    }

    beginUIDrag(input, moveWatermark, releaseWatermark)
end)

connect(UserInputService.InputChanged, function(input)
    if activeSlider then
        if (
            input.UserInputType == Enum.UserInputType.MouseMovement
            and activeSlider.input.UserInputType
                == Enum.UserInputType.MouseButton1
        ) or input == activeSlider.input then
            activeSlider.update(input.Position.X)
        end

        return
    end

    if not gesture then
        return
    end

    if input.UserInputType ~= Enum.UserInputType.MouseMovement
        and input ~= gesture.input then
        return
    end

    local delta = input.Position - gesture.origin

    if gesture.resize then
        local maximum = math.max(
            0.01,
            math.min(
                safeSize.X / 780,
                safeSize.Y / 470
            )
        )

        menuScale.Scale = math.clamp(
            gesture.scale + delta.X / 780,
            math.min(0.2, maximum),
            maximum
        )

        task.defer(updateHighlight)
    else
        local p = gesture.position

        gesture.target.Position = UDim2.new(
            p.X.Scale,
            p.X.Offset + delta.X,
            p.Y.Scale,
            p.Y.Offset + delta.Y
        )
    end

    clampWindow()
end)

connect(UserInputService.InputEnded, function(input)
    if activeSlider and input == activeSlider.input then
        activeSlider = nil
        previewScroll.ScrollingEnabled = true
    end

    if gesture and input == gesture.input then
        gesture = nil
    end
end)

connect(UserInputService.WindowFocusReleased, function()
    gesture = nil
    activeSlider = nil
    previewScroll.ScrollingEnabled = true
end)

connect(UserInputService.InputBegan, function(input)
    -- Rebinding mode swallows the next keyboard press, whatever key it is.
    if capturingBind then
        if input.UserInputType == Enum.UserInputType.Keyboard then
            bindKey = input.KeyCode
            capturingBind = false
            refreshBindValue()
        end

        return
    end

    if UserInputService:GetFocusedTextBox() then
        return
    end

    if input.KeyCode == bindKey then
        toggleMenu()
    end
end)

-- Watermark metrics

local frames, elapsed = 0, 0

connect(RunService.Heartbeat, function(dt)
    frames = frames + 1
    elapsed = elapsed + dt

    if elapsed < 0.5 then
        return
    end

    values.FPS.Text = tostring(
        math.floor(frames / elapsed + 0.5)
    )

    frames, elapsed = 0, 0

    local pingOK, ping = pcall(player.GetNetworkPing, player)

    values.Ping.Text = pingOK
        and (math.floor(ping * 1000 + 0.5) .. "ms")
        or "-"

    local memoryOK, memory = pcall(
        Stats.GetTotalMemoryUsageMb,
        Stats
    )

    values.RAM.Text = memoryOK
        and (math.floor(memory + 0.5) .. "mb")
        or "-"

    values.Time.Text = os.date("%H:%M")
end)


task.defer(fitScreen)