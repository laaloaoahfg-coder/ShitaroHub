-- core/models.lua - helper for the 3D models kept in models/.
-- Nothing in the menu uses it yet; it is the ready-made place to plug models
-- into. Use it from a module:
--
--   local Models = ctx.Loader.module("core/models.lua")
--   local model = Models.load("example")      -- a cloned, unparented Model
--   if model then model.Parent = workspace end
--
-- An entry of models/manifest.lua is either
--   { id = 123456789 }             a Roblox asset (game:GetObjects)
--   { file = "models/thing.rbxm" } a file in the executor workspace
--                                  (Mode = "local", needs getcustomasset)

local Models = {}
local manifest
local cache = {}

local function getManifest(loader)
    if manifest == nil then
        local ok, data = pcall(loader.module, "models/manifest.lua")

        manifest = ok and type(data) == "table" and data or {}
    end

    return manifest
end

function Models.list()
    local names = {}

    for name in pairs(getManifest(getgenv().ShitaroLoader)) do
        names[#names + 1] = name
    end

    table.sort(names)
    return names
end

function Models.load(name)
    if cache[name] then
        return cache[name]:Clone()
    end

    local entry = getManifest(getgenv().ShitaroLoader)[name]

    if type(entry) ~= "table" then
        warn("[shitaro/models] unknown model: " .. tostring(name))
        return nil
    end

    local url

    if entry.id then
        url = "rbxassetid://" .. tostring(entry.id)
    elseif entry.file and type(getcustomasset) == "function" then
        local folder = (getgenv().ShitaroConfig or {}).Folder or "ShitaroHub"
        local okAsset, asset = pcall(getcustomasset, folder .. "/" .. entry.file)

        url = okAsset and asset or nil
    end

    if not url then
        warn("[shitaro/models] no way to load " .. name)
        return nil
    end

    local ok, objects = pcall(function()
        return game:GetObjects(url)
    end)

    if not ok or not objects or not objects[1] then
        warn("[shitaro/models] failed to load " .. name .. ": " .. tostring(objects))
        return nil
    end

    cache[name] = objects[1]
    return objects[1]:Clone()
end

return Models
