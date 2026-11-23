-- Test the real ESP player eligibility and side resolver closures in isolation.
-- Extracted from modules/esp.lua to prevent divergence from the shipped logic.
local source = assert(io.open("modules/esp.lua", "rb")):read("*a")
local function section(first, last)
    local start = assert(source:find(first, 1, true), first)
    local stop = assert(source:find(last, start, true), last)
    return source:sub(start, stop - 1)
end
local eligibility = section("    local DEAD_FLAGS = {", "    -- Per-player objects")
local sides = section("    local function teamFolderOf(char)", "    local function describeSide(target)")
local build = assert(load("return function(Players, Workspace, Enum)\n" .. eligibility .. "\nreturn isAlive end"))()
local buildSides = assert(load("return function(Players, Workspace, player, uiState)\nlocal folderModeAt, folderMode = -math.huge, false\n" .. sides .. "\nreturn refreshSides,isTeammate end"))()
local O = {}
O.__index = O
function O:GetAttribute(name) return self.attrs[name] end
function O:GetAttributes() return self.attrs end
function O:GetChildren() return self.children or {} end
function O:FindFirstChildOfClass(class) return self.humanoid and class == "Humanoid" and self.humanoid or nil end
function O:IsDescendantOf(ancestor)
    local p = self.Parent
    while p do if p == ancestor then return true end; p = p.Parent end
    return false
end
function O:GetState() return self.state end
function O:IsA(class) return class == self.ClassName end
function O:GetFullName() return self.Parent and self.Parent:GetFullName() .. "." .. self.Name or self.Name end
local function obj(name, parent, attrs)
    return setmetatable({Name=name, Parent=parent, attrs=attrs or {}, children={}}, O)
end
typeof = function(value) return getmetatable(value) == O and "Instance" or type(value) end
table.clear = function(t) for k in pairs(t) do t[k] = nil end end
local workspace = obj("Workspace")
local storage = obj("ReplicatedStorage")
local worldFolder = obj("Characters", workspace)
local culled = obj("_PVS_CulledCharacters", storage)
local players = obj("Players")
function players:GetPlayers() return self.children end
local enum = {HumanoidStateType={Dead="Dead"}}
local function player(name, side, parent)
    local p=obj(name, players, {Team=side, Health=100, Dead=false})
    p.Character=obj(name, parent or worldFolder, {CharacterType="PlayerCustomCharacter", ClientCharacterPresentationVisible=true, Health=100})
    table.insert(players.children, p)
    return p
end
local me=player("Me", "Terrorists")
local ally=player("Ally", "Terrorists")
local enemy=player("Enemy", "Counter-Terrorists")
local isAlive = build(players, workspace, enum)
assert(isAlive(enemy), "custom no-Humanoid character in Workspace")
enemy.Character.Parent=culled
assert(not isAlive(enemy), "culled ReplicatedStorage character must be hidden")
enemy.Character.Parent=worldFolder
enemy.Character.attrs.ClientCharacterPresentationVisible=false
assert(not isAlive(enemy), "hidden custom character must be hidden")
enemy.Character.attrs.ClientCharacterPresentationVisible=true
assert(isAlive(enemy), "restored world character must reappear")
enemy.attrs.Dead=true
assert(not isAlive(enemy), "dead player must be hidden")
enemy.attrs.Dead=false
enemy.Character.attrs.Health=0
assert(not isAlive(enemy), "zero health must be hidden")
enemy.Character.attrs.Health=100
local hum=obj("Humanoid", enemy.Character, {})
hum.Health=100;hum.state="Running";enemy.Character.humanoid=hum
assert(isAlive(enemy), "ordinary living Humanoid still works")
hum.state="Dead";assert(not isAlive(enemy), "dead Humanoid must be hidden")
enemy.Character.humanoid=nil
local refresh, teammate=buildSides(players, workspace, me, {})
refresh(10)
assert(teammate(ally), "matching Team attribute should be teammate")
assert(not teammate(enemy), "opposite Team attribute should not be teammate")
print("PASS: actual ESP eligibility and side resolver (custom rigs, culling, respawn, teams)")
