-- loader.lua - the one file you launch from the injector.
--
--   loadstring(game:HttpGet("https://raw.githubusercontent.com/laaloaoahfg-coder/ShitaroHub/main/loader.lua"))()
--
-- It downloads core/ui.lua and modules/*.lua from BASE_URL, compiles them and
-- starts the menu. Optional settings go in getgenv().ShitaroConfig BEFORE
-- the launch line:
--
--   getgenv().ShitaroConfig = {
--       BaseUrl = "https://raw.githubusercontent.com/laaloaoahfg-coder/ShitaroHub/main/",
--       Mode    = "remote",       -- "remote" | "local"
--       Folder  = "ShitaroHub",   -- executor workspace folder used by Mode = "local"
--   }

local BASE_URL = "https://raw.githubusercontent.com/laaloaoahfg-coder/ShitaroHub/main/"

local env = (getgenv and getgenv()) or _G
local cfg = env.ShitaroConfig or {}

local baseUrl = cfg.BaseUrl or BASE_URL
local folder = cfg.Folder or "ShitaroHub"
local mode = cfg.Mode or "remote"

if baseUrl:sub(-1) ~= "/" then
    baseUrl = baseUrl .. "/"
end

local Loader = { cache = {}, mode = mode }

-- returns the raw text/bytes of a file of the project
local function fetch(path)
    if mode == "local" then
        if type(readfile) ~= "function" then
            error("this executor has no readfile, use Mode = \"remote\"")
        end

        return readfile(folder .. "/" .. path)
    end

    if baseUrl:find("YOUR_NAME", 1, true) then
        error("set BASE_URL in loader.lua (or ShitaroConfig.BaseUrl) to your repository first")
    end

    local lastError

    for attempt = 1, 3 do
        local ok, body = pcall(function()
            return game:HttpGet(baseUrl .. path)
        end)

        if ok and type(body) == "string" and body ~= "" then
            -- raw.githubusercontent answers a missing file with this text
            if body:sub(1, 4) == "404:" then
                error("not found: " .. baseUrl .. path)
            end

            return body
        end

        lastError = body

        if attempt < 3 then
            task.wait(0.4 * attempt)
        end
    end

    error("download failed for " .. path .. ": " .. tostring(lastError))
end

Loader.fetch = fetch

-- runs a file and returns whatever the chunk returns
function Loader.run(path, ...)
    local chunk, message = loadstring(fetch(path), "=" .. path)

    if not chunk then
        error("syntax error in " .. path .. ": " .. tostring(message))
    end

    return chunk(...)
end

-- like require: runs a file once and keeps its return value
function Loader.module(path)
    local entry = Loader.cache[path]

    if entry == nil then
        entry = Loader.run(path, Loader)
        Loader.cache[path] = entry == nil and false or entry
    end

    return entry or nil
end

env.ShitaroLoader = Loader

local ok, err = xpcall(function()
    Loader.run("core/ui.lua", Loader)
end, function(message)
    return debug.traceback(tostring(message), 2)
end)

if not ok then
    warn("[shitaro/loader] " .. tostring(err))
end
