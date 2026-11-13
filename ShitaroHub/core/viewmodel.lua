-- core/viewmodel.lua - finds the first person view model.
--
-- Shooters draw your arms and weapon from a separate model that is glued to
-- the camera every frame. Where that model lives depends on the game, so it
-- is searched three ways:
--   1. anything under the camera (Camera.Arms, Camera.ViewModel ...);
--   2. containers in Workspace whose name says what they are
--      (Workspace.ViewModels, Workspace.FirstPerson ...);
--   3. any part near the camera that keeps its place relative to the camera
--      while the camera moves ("glued" parts) - the catch-all.
--
-- Used by modules/camera.lua (hide it in third person / free camera) and by
-- modules/skins.lua (put the skin's hands on it in first person).
--
--   local VM = Loader.module("core/viewmodel.lua")
--   VM.parts(cam, os.clock())      -> array of BaseParts of the view model
--   VM.arms(parts, cam)            -> { Left = {parts}, Right = {parts} }
--   VM.report(player, cam)         -> text for the "copy diagnostics" button

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local VM = {}

local HINTS = {
    "viewmodel", "view_model", "view model", "firstperson", "first_person",
    "first person", "fpsarms", "fparms", "fp_arms", "viewarms", "fpv",
}

local ARM_WORDS = { "arm", "hand", "glove", "sleeve", "wrist", "forearm" }

local NOT_ARM_WORDS = {
    "weapon", "gun", "knife", "mag", "ammo", "sight", "scope", "muzzle",
    "barrel", "trigger", "stock", "grip", "handle", "slide", "bolt", "rail",
}

local glueKnown = {}     -- part -> true once it proved to be glued to the camera
local track = {}         -- part -> last sample
local lastGlue = 0
local namedCache, namedAt = {}, 0

local function contains(text, words)
    for _, word in ipairs(words) do
        if text:find(word, 1, true) then
            return true
        end
    end

    return false
end

-- parts of a character (the player's or any NPC / copy) are never view model
local function inHumanoidModel(part)
    local model = part:FindFirstAncestorOfClass("Model")

    while model do
        if model:FindFirstChildOfClass("Humanoid") then
            return true
        end

        model = model.Parent and model.Parent:FindFirstAncestorOfClass("Model")
    end

    return false
end

local function angleBetween(a, b)
    local dot = math.max(-1, math.min(1, a:Dot(b)))

    return math.acos(dot)
end

-- Remembers where parts near the camera are relative to the camera; a part
-- that follows the camera while the camera moves is part of the view model.
local function sampleGlue(cam, now)
    if now - lastGlue < 0.2 then
        return
    end

    lastGlue = now

    local camCF = cam.CFrame
    local params = OverlapParams.new()
    params.MaxParts = 120

    local ok, near = pcall(function()
        return Workspace:GetPartBoundsInRadius(camCF.Position, 8, params)
    end)

    if not ok then
        return
    end

    local alive = {}

    for _, part in ipairs(near) do
        if part:IsA("BasePart") and not part:IsA("Terrain")
            and not inHumanoidModel(part) then
            alive[part] = true

            local rel = camCF:ToObjectSpace(part.CFrame)
            local entry = track[part]

            if not entry then
                track[part] = {
                    cam = camCF, rel = rel, at = part.CFrame, hits = 0,
                }
            else
                local moved = (camCF.Position - entry.cam.Position).Magnitude > 0.08
                    or angleBetween(camCF.LookVector, entry.cam.LookVector) > 0.02

                if moved then
                    local partMoved = (part.Position - entry.at.Position).Magnitude > 0.03
                    local shift = (rel.Position - entry.rel.Position).Magnitude

                    if partMoved and shift < 0.25 then
                        entry.hits = math.min(entry.hits + 1, 6)
                    else
                        entry.hits = math.max(entry.hits - 2, 0)
                    end

                    if entry.hits >= 3 then
                        glueKnown[part] = true
                    end

                    entry.cam, entry.rel, entry.at = camCF, rel, part.CFrame
                end
            end
        end
    end

    for part in pairs(track) do
        if not alive[part] then
            track[part] = nil
        end
    end
end

local function collectNamed()
    local found = {}

    local function take(container)
        if container:IsA("BasePart") then
            found[#found + 1] = container
        end

        for _, item in ipairs(container:GetDescendants()) do
            if item:IsA("BasePart") then
                found[#found + 1] = item
            end
        end
    end

    for _, child in ipairs(Workspace:GetChildren()) do
        local name = child.Name:lower()

        if contains(name, HINTS) or name == "arms" then
            take(child)
        elseif child:IsA("Folder") then
            for _, inner in ipairs(child:GetChildren()) do
                local innerName = inner.Name:lower()

                if contains(innerName, HINTS) or innerName == "arms" then
                    take(inner)
                end
            end
        end
    end

    return found
end

-- Lets the "glued to the camera" detection learn while you are still in first
-- person, so the view model is already known when you switch to third person.
function VM.sample(cam, now)
    if cam then
        sampleGlue(cam, now)
    end
end

function VM.parts(cam, now)
    local out, seen = {}, {}

    local function add(part)
        if not seen[part] then
            seen[part] = true
            out[#out + 1] = part
        end
    end

    if cam then
        for _, item in ipairs(cam:GetDescendants()) do
            if item:IsA("BasePart") then
                add(item)
            end
        end
    end

    if now - namedAt > 0.5 then
        namedAt = now
        namedCache = collectNamed()
    end

    for _, part in ipairs(namedCache) do
        if part.Parent then
            add(part)
        end
    end

    if cam then
        sampleGlue(cam, now)
    end

    for part in pairs(glueKnown) do
        if part.Parent then
            add(part)
        else
            glueKnown[part] = nil
        end
    end

    return out
end

local function longest(size)
    return math.max(size.X, size.Y, size.Z)
end

local function sideOf(name, part, cam)
    if name:find("left", 1, true) or name:find("^l[^a-z]") or name:find("[^a-z]l$")
        or name:find("^l$") then
        return "Left"
    end

    if name:find("right", 1, true) or name:find("^r[^a-z]") or name:find("[^a-z]r$")
        or name:find("^r$") then
        return "Right"
    end

    if cam then
        return cam.CFrame:PointToObjectSpace(part.Position).X < 0 and "Left" or "Right"
    end

    return nil
end

-- Arm-like parts of the view model, sorted into left and right.
function VM.arms(parts, cam)
    local result = { Left = {}, Right = {} }

    for _, part in ipairs(parts) do
        local name = part.Name:lower()
        local length = longest(part.Size)

        if part.Parent and not name:find("^shitaro")
            and contains(name, ARM_WORDS)
            and not contains(name, NOT_ARM_WORDS)
            and length >= 0.5 and length <= 6 then
            local side = sideOf(name, part, cam)

            if side then
                local list = result[side]
                list[#list + 1] = part
            end
        end
    end

    return result
end

local function describe(item, depth, lines, limit)
    if #lines >= limit or depth > 3 then
        return
    end

    local text = string.rep("  ", depth) .. item.ClassName .. " " .. item.Name

    if item:IsA("BasePart") then
        text = text .. string.format(" size(%.1f,%.1f,%.1f) anch=%s",
            item.Size.X, item.Size.Y, item.Size.Z, tostring(item.Anchored))
    end

    lines[#lines + 1] = text

    for _, child in ipairs(item:GetChildren()) do
        describe(child, depth + 1, lines, limit)
    end
end

function VM.report(player, cam)
    local lines = { "== shitaro diagnostics ==" }
    local now = os.clock()

    lines[#lines + 1] = "-- camera children"

    if cam then
        for _, child in ipairs(cam:GetChildren()) do
            describe(child, 1, lines, 70)
        end
    end

    lines[#lines + 1] = "-- workspace children (first 40)"

    for index, child in ipairs(Workspace:GetChildren()) do
        if index > 40 then
            break
        end

        lines[#lines + 1] = "  " .. child.ClassName .. " " .. child.Name
    end

    local parts = VM.parts(cam, now)
    local names = {}

    for index, part in ipairs(parts) do
        if index > 30 then
            break
        end

        names[#names + 1] = part:GetFullName():gsub("^Workspace%.", "")
    end

    lines[#lines + 1] = "-- view model parts found: " .. #parts
    lines[#lines + 1] = "  " .. table.concat(names, " | ")

    local arms = VM.arms(parts, cam)

    for _, side in ipairs({ "Left", "Right" }) do
        local list = {}

        for _, part in ipairs(arms[side]) do
            list[#list + 1] = part.Name
        end

        lines[#lines + 1] = "-- " .. side .. " arm parts: " .. table.concat(list, ", ")
    end

    lines[#lines + 1] = "-- character"

    local char = player.Character

    if char then
        for _, child in ipairs(char:GetChildren()) do
            describe(child, 1, lines, 140)
        end

        lines[#lines + 1] = "-- joints on the right hand / arm"

        for _, item in ipairs(char:GetDescendants()) do
            if item:IsA("JointInstance") and item.Part0
                and (item.Part0.Name == "RightHand" or item.Part0.Name == "Right Arm") then
                lines[#lines + 1] = string.format("  %s %s: %s -> %s",
                    item.ClassName, item.Name, item.Part0.Name,
                    item.Part1 and item.Part1:GetFullName() or "nil")
            end
        end
    end

    lines[#lines + 1] = "-- humanoid models in Workspace (own copy?)"

    local count = 0

    for _, item in ipairs(Workspace:GetDescendants()) do
        if item:IsA("Humanoid") and item.Parent and count < 12 then
            count = count + 1

            lines[#lines + 1] = "  " .. item.Parent:GetFullName()
                .. (Players:GetPlayerFromCharacter(item.Parent) and " [player]" or "")
        end
    end

    return table.concat(lines, "\n")
end

return VM
