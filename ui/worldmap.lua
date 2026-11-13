--[[
    I remember you! -- player icons on the world map and minimaps.

    ESO only creates player pins for group members: it does not expose the
    position of anyone else and has no pin for an arbitrary remembered player.
    This module therefore decorates the pins the game already has. When a pin
    belongs to a group member with an IRY icon, only its background texture is
    replaced; size, anchors and the game's own pin state stay untouched.

    The hook is the same pin manager OdySupportIcons uses:

        ZO_WorldMap_GetPinManager().CreatePin

    It covers the world map and minimaps that reuse the standard pin manager
    (Votan's Minimap). There is no dependency on OSI and nothing here writes to
    its settings. If OSI is installed, both modules may set the same texture:
    the icon is resolved in one place, so the result is identical.

    No pin exists for players outside the group, so none can be decorated. A
    future official minimap gets the same treatment for free if it reuses the
    standard pin manager; otherwise only this file needs an adapter.
]]

local WorldMap = {}
IRY.WorldMap = WorldMap

-- Pins we changed, with weak keys: the game may recreate or destroy them at
-- any time and we must not keep them alive.
local tracked = setmetatable({}, { __mode = "k" })

local wrapper

local function settings()
    return (IRY.Store and IRY.Store:GetSettings()) or {}
end

-- The map follows the same master switch as every other surface. The separate
-- mapIcons setting only lets the player turn the map off without losing the
-- 2D rows, the reticle marker or the 3D icons.
local function enabled()
    local s = settings()
    return s.showIcons ~= false and s.mapIcons ~= false
end

local function rememberTexture(pin, icon)
    local state = pin.__iryMapPin
    if state then
        return state
    end

    state = {}

    -- GetTextureFileName is the only portable way to read the game's pin
    -- texture back. It may be missing on a mock or a future control, so the
    -- access is guarded; without it restore is best-effort only.
    if type(icon.GetTextureFileName) == "function" then
        local ok, texture = pcall(icon.GetTextureFileName, icon)
        if ok and type(texture) == "string" and texture ~= "" then
            state.texture = texture
        end
    end

    -- Pins can be tinted by the game (roles, death, PvP). Our own icons must
    -- show their true colours, so the tint is stored and put back on restore.
    if type(icon.GetColor) == "function" then
        local ok, r, g, b, a = pcall(icon.GetColor, icon)
        if ok then
            state.color = { r, g, b, a }
        end
    end

    pin.__iryMapPin = state
    return state
end

local function currentTexture(icon)
    if type(icon.GetTextureFileName) ~= "function" then
        return nil
    end

    local ok, texture = pcall(icon.GetTextureFileName, icon)
    if ok and type(texture) == "string" then
        return texture
    end

    return nil
end

local function restorePin(pin)
    local state = pin.__iryMapPin
    if not state then
        return
    end

    local icon = pin.backgroundControl

    -- Pin objects are pooled and reused for other pin tags. The game writes the
    -- new pin's texture before our wrapper runs, so only restore when the
    -- control still shows the picture we put there; a newer value wins.
    local current = icon and currentTexture(icon)
    local ours = state.applied ~= nil and (current == nil or current == state.applied)

    if icon and ours and state.texture and type(icon.SetTexture) == "function" then
        icon:SetTexture(state.texture)
    end

    if icon and ours and state.color and type(icon.SetColor) == "function" then
        local c = state.color
        icon:SetColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
    end

    pin.__iryMapPin = nil
    -- The pin stays tracked on purpose: the game may reuse it without calling
    -- CreatePin again, and a later Refresh must still be able to decorate it
    -- when an icon comes back. The table has weak keys, so closed maps and
    -- destroyed pins are collected.
end

local function applyPin(pin)
    if type(pin) ~= "table" then
        return
    end

    local icon = pin.backgroundControl

    -- Only group member pins carry a unit tag. Everything else (wayshrines,
    -- quests, vendors, the player marker) keeps the game's texture. A pin that
    -- was ours and is being reused for such a tag is restored first.
    local isGroup = type(pin.IsGroup) == "function" and pin:IsGroup()
    if not isGroup or not icon or type(icon.SetTexture) ~= "function" then
        restorePin(pin)
        return
    end

    -- In another zone the game draws a breadcrumb pin with the last known
    -- position. It has no live unit behind it, so an icon would be misleading.
    local tagData = pin.m_PinTag
    if type(tagData) == "table" and tagData.isBreadcrumb then
        restorePin(pin)
        return
    end

    local tag = type(pin.GetUnitTag) == "function" and pin:GetUnitTag() or nil
    local path = nil
    if enabled() and tag and IRY.Icons then
        path = IRY.Icons:ForUnit(tag)
    end

    if not path then
        restorePin(pin)
        return
    end

    local state = rememberTexture(pin, icon)
    state.applied = path

    icon:SetTexture(path)
    if type(icon.SetColor) == "function" then
        icon:SetColor(1, 1, 1, 1)
    end

    tracked[pin] = true
end

-- Install, or re-install over a hook another addon put on top of ours. Pins are
-- created lazily, so being the outermost wrapper is what makes the IRY icon win
-- when both IRY and OSI draw the same group pin.
local function install()
    local getManager = _G.ZO_WorldMap_GetPinManager
    if type(getManager) ~= "function" then
        return false
    end

    local manager = getManager()
    if not manager or type(manager.CreatePin) ~= "function" then
        return false
    end

    if manager.CreatePin == wrapper then
        return true
    end

    local previous = manager.CreatePin
    wrapper = function(...)
        local pin = previous(...)
        pcall(applyPin, pin)
        return pin
    end
    manager.CreatePin = wrapper

    return true
end

-- Redraw the pins that already exist and ask the game to recreate the group
-- pins. Resolution is cheap, and this path must also restore the game's
-- texture when the icon is cleared, the map is switched off or the master
-- switch is turned off, so it is deliberately idempotent.
function WorldMap:Refresh()
    install()

    -- Refresh first: the game may rebuild the group pins and reset their
    -- textures. Whatever it does, the loop below and the CreatePin wrapper are
    -- the last writers.
    if type(_G.ZO_WorldMap_RefreshGroupPins) == "function" then
        pcall(_G.ZO_WorldMap_RefreshGroupPins)
    end

    local pins = {}
    for pin in pairs(tracked) do
        pins[#pins + 1] = pin
    end
    for index = 1, #pins do
        pcall(applyPin, pins[index])
    end
end

-- Not every client exposes every event; a nil constant would abort the whole
-- Initialize, so missing ones are skipped instead.
local function register(namespace, eventName, handler)
    if not eventName then
        return
    end

    EVENT_MANAGER:RegisterForEvent(namespace, eventName, handler)
end

function WorldMap:Initialize()
    local namespace = IRY.name .. "WorldMap"

    local function refresh()
        WorldMap:Refresh()
    end

    register(namespace, EVENT_PLAYER_ACTIVATED, function()
        install()
        refresh()
    end)

    -- The map has to follow group membership, renames and new icons.
    register(namespace, EVENT_GROUP_MEMBER_JOINED, refresh)
    register(namespace, EVENT_GROUP_MEMBER_LEFT, refresh)
    register(namespace, EVENT_GROUP_MEMBER_CONNECTED, refresh)
    register(namespace, EVENT_GROUP_MEMBER_DISCONNECTED, refresh)
    register(namespace, EVENT_GROUP_MEMBER_ACCOUNT_NAME_UPDATED, refresh)
    register(namespace, EVENT_UNIT_CHARACTER_NAME_CHANGED, function(_, unitTag)
        if unitTag and unitTag:match("^group%d+$") then
            refresh()
        end
    end)

    -- The pin manager exists by the time addons load; installing now covers a
    -- pin manager that is already in use, and EVENT_PLAYER_ACTIVATED re-checks
    -- after every other addon has finished loading.
    install()
end
