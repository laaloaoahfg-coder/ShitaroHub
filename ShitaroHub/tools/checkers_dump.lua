--[[
    ShitaroHub / tools / checkers_dump.lua

    Read-only diagnostic for a board game (checkers) in Roblox. It changes
    nothing in the game and only reads what a normal client can already see.

    What it collects:
      * board candidates - anchored parts of one size standing on one height,
        so the cell grid, the board bounds and the step between cells can be
        recovered without trusting instance names;
      * the whole workspace tree and the whole PlayerGui tree with the
        properties that matter (Size, Position, Text, Visible, Value, mesh and
        texture ids, attributes on every instance);
      * every RemoteEvent / RemoteFunction / Bindable a client can reach;
      * live traffic: outgoing FireServer / InvokeServer calls (through the
        __namecall metamethod) and every argument a server broadcast brings,
        because the move protocol is exactly what the bot has to speak;
      * GUI texts that change over time - the 35 second move timer shows up
        here as one label counting down and resetting after a move;
      * parts that move on their own, which is how a played move looks.

    Usage:
      loadstring(game:HttpGet("https://raw.githubusercontent.com/laaloaoahfg-coder/ShitaroHub/main/ShitaroHub/tools/checkers_dump.lua"))()

    Capture runs for CONFIG.logSeconds seconds (F9 stops it early), then the
    report is written to CONFIG.filePath when the executor has writefile and
    copied to the clipboard when it has setclipboard. Send that file over.
]]

xpcall(function()
    local Players = game:GetService("Players")
    local Workspace = game:GetService("Workspace")
    local Teams = game:GetService("Teams")
    local UserInputService = game:GetService("UserInputService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local ReplicatedFirst = game:GetService("ReplicatedFirst")

    -- Everything worth tuning lives here.
    local CONFIG = {
        workspaceDepth = 5,
        workspaceBudget = 3000,
        guiDepth = 12,
        guiBudget = 2500,
        coreGuiBudget = 300,

        -- long enough for a few moves plus at least one timer reset
        logSeconds = 150,
        maxLogLines = 600,
        maxTrackedParts = 600,
        moveThreshold = 0.75, -- studs before a part counts as moved

        filePath = "checkers_dump.txt",
        maxReportChars = 400000,
    }

    local player = Players.LocalPlayer
    local report = {}
    local reportChars = 0
    local finished = false
    local stopRequested = false
    local startedAt = os.clock()

    -- Report helpers ---------------------------------------------------------

    local function add(line)
        if reportChars >= CONFIG.maxReportChars then
            return
        end
        line = tostring(line)
        report[#report + 1] = line
        reportChars = reportChars + #line + 1
    end

    local function section(title)
        add("")
        add(string.rep("=", 68))
        add(title)
        add(string.rep("=", 68))
    end

    local function note(line)
        add("  " .. line)
    end

    local function trim(text, limit)
        text = tostring(text)
        if #text > limit then
            return text:sub(1, limit) .. "..."
        end
        return text
    end

    local function quote(text)
        text = trim(text, 160)
        text = text:gsub("\n", "\\n")
        text = text:gsub("\r", "")
        return '"' .. text .. '"'
    end

    local function roundTo(number, step)
        return math.floor(number / step + 0.5) * step
    end

    local function stamp()
        return string.format("%7.2f", os.clock() - startedAt)
    end

    local function pathOf(inst)
        local parts = {}
        local node = inst
        while node and node ~= game do
            table.insert(parts, 1, node.Name)
            node = node.Parent
        end
        return table.concat(parts, ".")
    end

    -- Printing a value the way it reads in the report
    local function value(v, depth)
        depth = depth or 0
        local kind = typeof(v)

        if kind == "nil" then
            return "nil"
        elseif kind == "boolean" or kind == "number" then
            return tostring(v)
        elseif kind == "string" then
            return quote(v)
        elseif kind == "Instance" then
            return pathOf(v) .. " [" .. v.ClassName .. "]"
        elseif kind == "Vector3" then
            return string.format("V3(%.2f, %.2f, %.2f)", v.X, v.Y, v.Z)
        elseif kind == "Vector2" then
            return string.format("V2(%.2f, %.2f)", v.X, v.Y)
        elseif kind == "CFrame" then
            local p = v.Position
            return string.format("CFrame(%.2f, %.2f, %.2f)", p.X, p.Y, p.Z)
        elseif kind == "EnumItem" then
            return tostring(v)
        elseif kind == "table" then
            if depth >= 3 then
                return "{...}"
            end
            local pieces = {}
            local count = 0
            for key, item in pairs(v) do
                count = count + 1
                if count > 20 then
                    pieces[#pieces + 1] = "..."
                    break
                end
                pieces[#pieces + 1] = tostring(key) .. "=" .. value(item, depth + 1)
            end
            return "{" .. table.concat(pieces, ", ") .. "}"
        end

        return tostring(v)
    end

    -- Tree dump --------------------------------------------------------------

    local function propsOf(inst)
        local parts = {}

        if inst:IsA("BasePart") then
            local size = inst.Size
            local pos = inst.Position
            parts[#parts + 1] = string.format("Size=(%.2f, %.2f, %.2f)", size.X, size.Y, size.Z)
            parts[#parts + 1] = string.format("Pos=(%.2f, %.2f, %.2f)", pos.X, pos.Y, pos.Z)
            parts[#parts + 1] = "Anchored=" .. tostring(inst.Anchored)
            if inst.Transparency > 0 then
                parts[#parts + 1] = string.format("Transparency=%.2f", inst.Transparency)
            end
            if inst:IsA("MeshPart") and inst.MeshId ~= "" then
                parts[#parts + 1] = "MeshId=" .. trim(inst.MeshId, 120)
            end
            if inst:IsA("Part") and inst.TextureID ~= "" then
                parts[#parts + 1] = "TextureID=" .. trim(inst.TextureID, 120)
            end
        end

        if inst:IsA("GuiObject") then
            parts[#parts + 1] = "Size=" .. tostring(inst.Size)
            parts[#parts + 1] = "Pos=" .. tostring(inst.Position)
            parts[#parts + 1] = "Visible=" .. tostring(inst.Visible)
            if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
                if inst.Image ~= "" then
                    parts[#parts + 1] = "Image=" .. trim(inst.Image, 140)
                end
            end
        end

        if inst:IsA("LayerCollector") then
            parts[#parts + 1] = "Enabled=" .. tostring(inst.Enabled)
            parts[#parts + 1] = "DisplayOrder=" .. tostring(inst.DisplayOrder)
        end

        if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
            parts[#parts + 1] = "Text=" .. quote(inst.Text)
        end

        if inst:IsA("ValueBase") then
            parts[#parts + 1] = "Value=" .. value(inst.Value)
        end

        if inst:IsA("Camera") then
            parts[#parts + 1] = "CameraType=" .. tostring(inst.CameraType)
            parts[#parts + 1] = "FieldOfView=" .. tostring(inst.FieldOfView)
        end

        local okAttrs, attrs = pcall(function()
            return inst:GetAttributes()
        end)

        if okAttrs and type(attrs) == "table" then
            local names = {}
            for key in pairs(attrs) do
                names[#names + 1] = key
            end
            table.sort(names)
            for _, key in ipairs(names) do
                parts[#parts + 1] = "@" .. key .. "=" .. value(attrs[key])
            end
        end

        return table.concat(parts, " ")
    end

    local function dumpTree(root, maxDepth, budget)
        local used = 0

        local function walk(inst, depth)
            if used >= budget then
                return
            end

            used = used + 1

            if inst:IsA("Model") and Players:GetPlayerFromCharacter(inst) then
                add(string.rep("  ", depth) .. inst.Name .. " [" .. inst.ClassName .. "] player character, children skipped")
                return
            end

            add(string.rep("  ", depth) .. inst.Name .. " [" .. inst.ClassName .. "] " .. propsOf(inst))

            local children = inst:GetChildren()
            if depth >= maxDepth then
                if #children > 0 then
                    add(string.rep("  ", depth + 1) .. "... " .. #children .. " children")
                end
                return
            end

            for _, child in ipairs(children) do
                walk(child, depth + 1)
            end
        end

        walk(root, 0)

        if used >= budget then
            add("... tree cut at " .. budget .. " nodes")
        end
    end

    -- Board inference --------------------------------------------------------

    local function sortedUnique(list, step)
        table.sort(list)
        local result = {}
        for _, item in ipairs(list) do
            local rounded = roundTo(item, step)
            local last = result[#result]
            if last == nil or math.abs(last - rounded) > step * 0.5 then
                result[#result + 1] = rounded
            end
        end
        return result
    end

    local function inferBoard()
        local groups = {}
        local scanned = 0

        for _, inst in ipairs(Workspace:GetDescendants()) do
            scanned = scanned + 1
            if scanned > 60000 then
                break
            end

            if inst:IsA("BasePart") and inst.Anchored then
                local model = inst:FindFirstAncestorOfClass("Model")
                local isCharacter = model ~= nil and Players:GetPlayerFromCharacter(model) ~= nil

                if not isCharacter then
                    local key = string.format("%.2f|%.2f|%.2f|%.2f", inst.Size.X, inst.Size.Y, inst.Size.Z, inst.Position.Y)
                    local group = groups[key]
                    if not group then
                        group = { size = inst.Size, height = inst.Position.Y, parts = {} }
                        groups[key] = group
                    end
                    group.parts[#group.parts + 1] = inst
                end
            end
        end

        local ranked = {}
        for _, group in pairs(groups) do
            if #group.parts >= 8 then
                ranked[#ranked + 1] = group
            end
        end

        table.sort(ranked, function(a, b)
            return #a.parts > #b.parts
        end)

        section("BOARD CANDIDATES (anchored parts, one size, one height)")
        note("scanned " .. scanned .. " workspace instances, " .. #ranked .. " homogeneous groups with 8+ parts")

        for index = 1, math.min(#ranked, 4) do
            local group = ranked[index]
            local xs, zs, ys = {}, {}, {}

            for _, part in ipairs(group.parts) do
                xs[#xs + 1] = part.Position.X
                zs[#zs + 1] = part.Position.Z
                ys[#ys + 1] = part.Position.Y
            end

            local size = group.size
            local step = math.max(size.X, size.Z)
            local uniqueX = sortedUnique(xs, step * 0.5)
            local uniqueZ = sortedUnique(zs, step * 0.5)
            local minX, maxX, minZ, maxZ = xs[1], xs[1], zs[1], zs[1]

            for _, x in ipairs(xs) do
                minX = math.min(minX, x)
                maxX = math.max(maxX, x)
            end
            for _, z in ipairs(zs) do
                minZ = math.min(minZ, z)
                maxZ = math.max(maxZ, z)
            end

            add("")
            add(string.format("candidate %d: %d parts, size (%.2f, %.2f, %.2f), height %.2f",
                index, #group.parts, size.X, size.Y, size.Z, group.height))
            add(string.format("  unique x = %d, unique z = %d, step %.2f, x %.2f..%.2f, z %.2f..%.2f",
                #uniqueX, #uniqueZ, step, minX, maxX, minZ, maxZ))
            add("  sample paths:")

            for sample = 1, math.min(#group.parts, 6) do
                note(pathOf(group.parts[sample]))
            end
        end
    end

    -- Live capture -----------------------------------------------------------

    local traffic = {}
    local trafficCount = 0
    local guiLog = {}
    local moveLog = {}

    local function logTraffic(kind, remote, ...)
        if finished then
            return
        end

        local args = table.pack(...)
        local pieces = {}

        for index = 1, args.n do
            pieces[index] = value(args[index], 1)
        end

        local line = stamp() .. " " .. kind .. " " .. pathOf(remote) .. "(" .. table.concat(pieces, ", ") .. ")"
        trafficCount = trafficCount + 1

        if #traffic < CONFIG.maxLogLines then
            traffic[#traffic + 1] = line
        end
        if trafficCount <= 200 then
            print("[checkers/dump] " .. line)
        end
    end

    local watched = {}

    local function watchRemote(inst)
        if watched[inst] then
            return
        end
        watched[inst] = true

        if inst:IsA("RemoteEvent") or inst:IsA("UnreliableRemoteEvent") then
            pcall(function()
                inst.OnClientEvent:Connect(function(...)
                    logTraffic("IN ", inst, ...)
                end)
            end)
        end
    end

    local guiTexts = {}

    local function scanGuiTexts()
        if finished then
            return
        end

        local gui = player:FindFirstChildOfClass("PlayerGui")
        if not gui then
            return
        end

        for _, inst in ipairs(gui:GetDescendants()) do
            if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
                local ok, text = pcall(function()
                    return inst.Text
                end)

                if ok then
                    local previous = guiTexts[inst]
                    if previous ~= nil and previous ~= text and text ~= "" then
                        if #guiLog < CONFIG.maxLogLines then
                            guiLog[#guiLog + 1] = stamp() .. " " .. pathOf(inst) .. " : " .. quote(previous) .. " -> " .. quote(text)
                        end
                    end
                    guiTexts[inst] = text
                end
            end
        end
    end

    local trackedParts = nil
    local partPositions = {}

    local function collectTrackedParts()
        local list = {}
        local scanned = 0

        for _, inst in ipairs(Workspace:GetDescendants()) do
            scanned = scanned + 1
            if scanned > 60000 then
                break
            end

            if inst:IsA("BasePart") then
                local model = inst:FindFirstAncestorOfClass("Model")
                local isCharacter = model ~= nil and Players:GetPlayerFromCharacter(model) ~= nil
                local biggest = math.max(inst.Size.X, inst.Size.Y, inst.Size.Z)

                if not isCharacter and biggest <= 12 then
                    list[#list + 1] = inst
                    if #list >= CONFIG.maxTrackedParts then
                        break
                    end
                end
            end
        end

        return list
    end

    local function scanMovingParts()
        if finished or not trackedParts then
            return
        end

        for _, part in ipairs(trackedParts) do
            if part.Parent then
                local pos = part.Position
                local previous = partPositions[part]

                if previous == nil then
                    partPositions[part] = pos
                elseif (pos - previous).Magnitude >= CONFIG.moveThreshold then
                    if #moveLog < CONFIG.maxLogLines then
                        moveLog[#moveLog + 1] = stamp() .. " " .. pathOf(part) .. " " .. value(previous, 1) .. " -> " .. value(pos, 1)
                    end
                    partPositions[part] = pos
                end
            end
        end
    end

    -- Hook outgoing remote calls ---------------------------------------------

    local hookNote = "hookmetamethod is not available"

    if type(hookmetamethod) == "function" and type(getnamecallmethod) == "function" then
        local hooked = pcall(function()
            local original
            original = hookmetamethod(game, "__namecall", function(self, ...)
                local method = getnamecallmethod()
                if method == "FireServer" or method == "InvokeServer" then
                    pcall(logTraffic, "OUT", self, ...)
                end
                return original(self, ...)
            end)
        end)

        hookNote = hooked and "installed, outgoing FireServer / InvokeServer are logged" or "failed"
    end

    -- Static snapshot --------------------------------------------------------

    section("SESSION")
    add("game            " .. game.Name)
    add("place id        " .. tostring(game.PlaceId))
    add("job id          " .. tostring(game.JobId))
    add("creator id      " .. tostring(game.CreatorId))
    add("local player    " .. player.Name .. " (" .. tostring(player.UserId) .. ")")
    add("captured at     " .. tostring(os.date("%Y-%m-%d %H:%M:%S")))
    add("capture length  " .. CONFIG.logSeconds .. "s")

    section("EXECUTOR")
    add("writefile        " .. tostring(type(writefile) == "function"))
    add("setclipboard     " .. tostring(type(setclipboard) == "function"))
    add("hookmetamethod   " .. tostring(type(hookmetamethod) == "function"))
    add("namecall hook    " .. hookNote)
    add("identifyexecutor " .. (type(identifyexecutor) == "function" and tostring(identifyexecutor()) or "n/a"))

    section("LOCAL PLAYER STATE")
    add("character        " .. (player.Character and player.Character.Name or "none"))
    add("team             " .. (player.Team and player.Team.Name or "none"))

    local playerAttrs = player:GetAttributes()
    local attrCount = 0
    for key, val in pairs(playerAttrs) do
        attrCount = attrCount + 1
        add("@" .. key .. "=" .. value(val))
    end
    if attrCount == 0 then
        note("no attributes on the player - turn and time state lives elsewhere")
    end

    section("PLAYERS AND TEAMS")
    for _, other in ipairs(Players:GetPlayers()) do
        local flags = {}
        flags[#flags + 1] = other == player and "local" or "remote"
        if other.Team then
            flags[#flags + 1] = "team=" .. other.Team.Name
        end

        local leaderstats = other:FindFirstChild("leaderstats")
        if leaderstats then
            for _, stat in ipairs(leaderstats:GetChildren()) do
                if stat:IsA("ValueBase") then
                    flags[#flags + 1] = stat.Name .. "=" .. value(stat.Value)
                end
            end
        end

        for key, val in pairs(other:GetAttributes()) do
            flags[#flags + 1] = "@" .. key .. "=" .. value(val)
        end

        add(other.Name .. ": " .. table.concat(flags, " "))
    end

    for _, team in ipairs(Teams:GetChildren()) do
        add("team " .. team.Name .. " color=" .. tostring(team.TeamColor))
    end

    section("VALUE OBJECTS IN REPLICATEDSTORAGE")
    local valueCount = 0
    for _, inst in ipairs(ReplicatedStorage:GetDescendants()) do
        if inst:IsA("ValueBase") then
            valueCount = valueCount + 1
            add(pathOf(inst) .. " [" .. inst.ClassName .. "] = " .. value(inst.Value))
        end
    end
    if valueCount == 0 then
        note("no value objects - the state is probably kept in plain scripts or attributes")
    end

    -- Remotes ----------------------------------------------------------------

    local remotes = {}

    local function collectRemotes(root)
        if not root then
            return
        end
        for _, inst in ipairs(root:GetDescendants()) do
            if inst:IsA("RemoteEvent") or inst:IsA("UnreliableRemoteEvent")
                or inst:IsA("RemoteFunction") or inst:IsA("BindableEvent")
                or inst:IsA("BindableFunction") then
                remotes[#remotes + 1] = inst
            end
        end
    end

    pcall(collectRemotes, ReplicatedStorage)
    pcall(collectRemotes, ReplicatedFirst)
    pcall(collectRemotes, Workspace)
    pcall(collectRemotes, player:FindFirstChildOfClass("PlayerGui"))

    section("REMOTES (" .. #remotes .. ")")
    for _, inst in ipairs(remotes) do
        add(pathOf(inst) .. " [" .. inst.ClassName .. "]")
        watchRemote(inst)
    end
    if #remotes == 0 then
        note("no remotes found - the protocol may run through a single shared table or attributes")
    end

    -- New remotes are often created per match, so keep watching
    for _, root in ipairs({ ReplicatedStorage, ReplicatedFirst, Workspace }) do
        pcall(function()
            root.DescendantAdded:Connect(function(inst)
                if inst:IsA("RemoteEvent") or inst:IsA("UnreliableRemoteEvent") or inst:IsA("RemoteFunction") then
                    logTraffic("NEW", inst, "remote appeared")
                    watchRemote(inst)
                end
            end)
        end)
    end

    -- Tree snapshots ---------------------------------------------------------

    section("WORKSPACE TREE (depth " .. CONFIG.workspaceDepth .. ", budget " .. CONFIG.workspaceBudget .. " nodes)")
    pcall(dumpTree, Workspace, CONFIG.workspaceDepth, CONFIG.workspaceBudget)

    section("PLAYERGUI TREE (depth " .. CONFIG.guiDepth .. ", budget " .. CONFIG.guiBudget .. " nodes)")
    local gui = player:FindFirstChildOfClass("PlayerGui")
    if gui then
        pcall(dumpTree, gui, CONFIG.guiDepth, CONFIG.guiBudget)
    else
        note("PlayerGui not found")
    end

    section("COREGUI (may be inaccessible)")
    local coreOk, coreGui = pcall(function()
        return game:GetService("CoreGui")
    end)
    if coreOk and coreGui then
        pcall(dumpTree, coreGui, 3, CONFIG.coreGuiBudget)
    else
        note("CoreGui is protected in this executor")
    end

    pcall(inferBoard)

    -- Start capture ----------------------------------------------------------

    trackedParts = collectTrackedParts()
    scanGuiTexts()

    local deadline = startedAt + CONFIG.logSeconds

    pcall(function()
        UserInputService.InputBegan:Connect(function(input)
            if input.KeyCode == Enum.KeyCode.F9 then
                stopRequested = true
            end
        end)
    end)

    print("[checkers/dump] capturing for " .. CONFIG.logSeconds .. "s, F9 stops early")

    task.spawn(function()
        while not finished and not stopRequested and os.clock() < deadline do
            task.wait(0.2)
            pcall(scanGuiTexts)
            pcall(scanMovingParts)
        end
        finished = true
    end)

    while not finished do
        task.wait(5)
        if not finished then
            local left = math.max(0, deadline - os.clock())
            print(string.format("[checkers/dump] %ds left, %d remote events, %d gui changes, %d moves",
                math.ceil(left), trafficCount, #guiLog, #moveLog))
        end
    end

    -- Live results -----------------------------------------------------------

    section("REMOTE TRAFFIC (" .. trafficCount .. " events)")
    if #traffic == 0 then
        note("nothing was sent or received - move a piece during the capture next time")
    end
    for _, line in ipairs(traffic) do
        add(line)
    end

    section("GUI TEXT CHANGES (timer candidates)")
    if #guiLog == 0 then
        note("no text changed - if the timer was not running, capture during a real match")
    end
    for _, line in ipairs(guiLog) do
        add(line)
    end

    section("PARTS THAT MOVED (candidate moves)")
    if #moveLog == 0 then
        note("nothing moved - pieces may be GUI frames, check the PlayerGui tree")
    end
    for _, line in ipairs(moveLog) do
        add(line)
    end

    section("HOW TO READ THIS")
    add("- the board is the candidate whose part count is a square (64 or 100) and")
    add("  whose step equals the part size; a cell is (x - minX) / step + 1 by")
    add("  (z - minZ) / step + 1, so a move is two cells plus a capture target")
    add("- a move usually shows as one outgoing FireServer carrying the cells, and")
    add("  the incoming events after it only redraw the board - compare timestamps")
    add("- the 35 second timer is the label whose text counts down and resets right")
    add("  after a move; its path plus the traffic timing gives the turn budget")
    add("- pieces drawn as GUI frames instead of parts mean the move protocol is")
    add("  cell indices, not positions: the PlayerGui tree holds those buttons")

    -- Save -------------------------------------------------------------------

    local text = table.concat(report, "\n")

    if type(writefile) == "function" then
        local saved = pcall(writefile, CONFIG.filePath, text)
        if saved then
            print("[checkers/dump] saved " .. #text .. " bytes to " .. CONFIG.filePath)
        else
            warn("[checkers/dump] writefile failed")
        end
    else
        print("[checkers/dump] writefile is not available in this executor")
    end

    if type(setclipboard) == "function" then
        local copied = pcall(setclipboard, text)
        print("[checkers/dump] clipboard " .. (copied and "filled with the same report" or "failed"))
    end

    print(string.format("[checkers/dump] done: %d lines, %d chars", #report, reportChars))
end, function(err)
    warn("[checkers/dump] " .. debug.traceback(tostring(err), 2))
end)
