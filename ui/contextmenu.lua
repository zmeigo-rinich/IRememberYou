--[[
    I remember you! -- "open in IRY" in the social context menus.

    Surfaces: guild roster, friends list and group list. Chat is deliberately
    absent: a chat link carries only one of the two identities (@account or
    character), so an explicit add there would create half-players and
    duplicates. A social row carries both, which is what makes the action safe.

    The menu itself comes from LibCustomMenu, an optional dependency. It
    already owns the secure item pool and the right hook points, so this module
    only registers callbacks and never calls AddMenuItem itself.

    The action never merges entities: it creates a missing player or enriches
    the known one (Observer:EnsurePlayer). If the account and the character
    from the same row already belong to two different players, both are shown
    and merging stays a deliberate action in the browser.
]]

local ContextMenu = {}
IRY.ContextMenu = ContextMenu

-- Warned once per session: the user must see why the feature is partial.
local warned = false

local function library()
    return _G.LibCustomMenu
end

local function hasGuildSurface()
    local lib = library()
    return lib ~= nil and lib.RegisterGuildRosterContextMenu ~= nil
end

local function missingSurfaces()
    local lib = library()
    if not lib then
        return true
    end
    return lib.RegisterFriendsListContextMenu == nil
        or lib.RegisterGroupListContextMenu == nil
end

-- rowData -> normalized keys. Guild and friends expose displayName and
-- characterName; the group list additionally has rawCharacterName and live
-- class/level values.
local function identity(rowData, surface)
    if not rowData then
        return nil
    end

    local account = IRY.Util.NormalizeAccount(rowData.displayName)

    local character
    if surface == "group" then
        character = IRY.Util.NormalizeCharacter(rowData.rawCharacterName or rowData.characterName)
    elseif rowData.characterName and rowData.characterName ~= "" then
        character = IRY.Util.NormalizeCharacter(rowData.characterName)
    end

    if not account and not character then
        return nil
    end

    local info
    if surface == "group" then
        info = {
            classId = rowData.class,
            level   = rowData.level,
        }
    end

    return account, character, info
end

local function label(account, character)
    if account then
        return IRY.Util.FormatAccount(account)
    end
    return character or "?"
end

-- Shared by the menu callbacks and /pa find. Exposed for the harness.
function ContextMenu:Open(rowData, surface)
    local account, character, info = identity(rowData, surface)
    if not account and not character then
        return nil, "invalid"
    end

    -- Deliberately also covers the character name, so a character row that
    -- belongs to the player themself never creates an entity either.
    if IRY.Observer:IsSelf(account, character) then
        return nil, "self"
    end

    local id, action, first, second = IRY.Observer:EnsurePlayer(account, character, info)

    if action == "ambiguous" then
        IRY:Print(string.format(IRY.L.CONTEXT_AMBIGUOUS,
            label(account, character), first, second))
        IRY.Browser:ShowPlayers({ first, second })
        return nil, action
    end

    if not id then
        return nil, action
    end

    IRY.Browser:ShowPlayers({ id }, label(account, character))
    return id, action
end

local function callback(surface)
    return function(rowData)
        local account, character = identity(rowData, surface)
        if not account and not character then
            return
        end

        -- Never offer the item on the player's own row.
        if IRY.Observer:IsSelf(account, character) then
            return
        end

        -- Called by LibCustomMenu while it builds the menu, so the item is
        -- added synchronously. The action itself is deferred one frame: the
        -- menu is still closing when the callback runs, and opening a
        -- top-level window inside that handler is racy.
        AddCustomMenuItem(IRY.L.CONTEXT_OPEN, function()
            zo_callLater(function()
                IRY.ContextMenu:Open(rowData, surface)
            end, 0)
        end)
    end
end

local function warn()
    if warned then
        return
    end
    warned = true

    if not hasGuildSurface() then
        IRY:Print(IRY.L.CONTEXT_NO_LIB)
    elseif missingSurfaces() then
        IRY:Print(IRY.L.CONTEXT_OLD_LIB)
    end
end

-- Registers only what the installed library actually supports. Safe to call
-- more than once; each surface is registered at most once.
function ContextMenu:Install()
    local lib = library()
    if not lib or not lib.RegisterGuildRosterContextMenu then
        return false
    end

    local category = lib.CATEGORY_LATE

    if not self.guildHooked then
        lib:RegisterGuildRosterContextMenu(callback("guild"), category)
        self.guildHooked = true
    end

    if lib.RegisterFriendsListContextMenu and not self.friendsHooked then
        lib:RegisterFriendsListContextMenu(callback("friends"), category)
        self.friendsHooked = true
    end

    if lib.RegisterGroupListContextMenu and not self.groupHooked then
        lib:RegisterGroupListContextMenu(callback("group"), category)
        self.groupHooked = true
    end

    return true
end

function ContextMenu:Initialize()
    self:Install()

    -- Libraries normally load first, but a late LibCustomMenu or a library
    -- update during the session is picked up here as well.
    EVENT_MANAGER:RegisterForEvent(IRY.name, EVENT_PLAYER_ACTIVATED, function()
        IRY.ContextMenu:Install()
        warn()
    end)
end

-- Exposed for the harness.
ContextMenu.Identity = identity
ContextMenu.Warn = warn
