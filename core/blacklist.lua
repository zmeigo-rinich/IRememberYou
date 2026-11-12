--[[
    I remember you! -- the in-game ignore list, cached.

    The game's Ignore list is the blacklist: an ignored character gets the
    marker icon on every surface. The list lives in the client, never in our
    SavedVariables, so the cache is rebuilt from the API and kept in memory.

    Entries are character names, not @accounts. Keys are lowercased because
    name comparisons in the game are case-insensitive and the same person can
    be reported with different capitalisation.
]]

local Blacklist = {}
IRY.Blacklist = Blacklist

local entries = {}   -- [lower(character)] = display name as the game gave it
local ready = false

local function key(name)
    local clean = IRY.Util.NormalizeCharacter(name)
    if not clean then
        return nil
    end
    return string.lower(clean)
end

-- The argument order of GetIgnoredInfo changed between API levels, so take the
-- first non-empty string instead of a fixed position: a display name is always
-- a string and a note is optional.
local function infoName(index)
    local results = { pcall(GetIgnoredInfo, index) }
    if not results[1] then
        return nil
    end

    for position = 2, #results do
        local value = results[position]
        if type(value) == "string" and value ~= "" then
            return value
        end
    end

    return nil
end

function Blacklist:Rebuild()
    local nextEntries = {}

    if GetNumIgnored then
        local ok, total = pcall(GetNumIgnored)
        if ok and type(total) == "number" then
            for index = 1, total do
                local displayName = infoName(index)
                local k = key(displayName)
                if k then
                    nextEntries[k] = displayName
                end
            end
        end
    end

    entries = nextEntries
    ready = true
end

function Blacklist:IsIgnored(name)
    local clean = IRY.Util.NormalizeCharacter(name)
    if not clean then
        return false
    end

    -- The client's own check is authoritative when present; the cache covers
    -- clients that do not expose it and keeps /pa debug ignore meaningful.
    if type(_G.IsIgnored) == "function" then
        local ok, ignored = pcall(IsIgnored, clean)
        if ok and ignored ~= nil then
            return ignored == true
        end
    end

    if not ready then
        self:Rebuild()
    end

    local k = key(clean)
    return k ~= nil and entries[k] ~= nil
end

-- The entity may hold several characters; any ignored one marks the player.
-- Used by the browser and the slash commands, never by the 3D bridge.
function Blacklist:AnyIgnored(player)
    if not ready then
        self:Rebuild()
    end

    for character in pairs((player and player.characters) or {}) do
        if self:IsIgnored(character) then
            return true
        end
    end

    return false
end

function Blacklist:List()
    local list = {}
    for _, name in pairs(entries) do
        list[#list + 1] = name
    end

    table.sort(list, function(a, b)
        return string.lower(a) < string.lower(b)
    end)

    return list
end

function Blacklist:Count()
    local count = 0
    for _ in pairs(entries) do
        count = count + 1
    end
    return count
end

local function onAdded(_, displayName)
    local k = key(displayName)
    if k then
        entries[k] = displayName
    end
end

local function onRemoved(_, displayName)
    local k = key(displayName)
    if k then
        entries[k] = nil
    end
end

local function onRebuild()
    Blacklist:Rebuild()
end

-- Only the events this client actually has: a nil constant must not abort
-- Initialize. A missed event is covered by the next Rebuild trigger.
local function register(eventName, handler)
    if not eventName then
        return
    end

    EVENT_MANAGER:RegisterForEvent(IRY.name, eventName, handler)
end

function Blacklist:Initialize()
    -- The list can be empty this early; EVENT_PLAYER_ACTIVATED and the ignore
    -- events rebuild it as soon as the client has the data.
    self:Rebuild()

    register(EVENT_IGNORE_ADDED, onAdded)
    register(EVENT_IGNORE_REMOVED, onRemoved)
    register(EVENT_IGNORE_NOTE_UPDATED, onRebuild)
    register(EVENT_PLAYER_ACTIVATED, onRebuild)
end
