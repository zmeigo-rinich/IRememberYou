--[[
    I remember you! -- slash commands.

    Phase 1 is deliberately command driven: everything the UI will do later
    (rename, merge, undo, inspect, confirm) is available here, which also makes
    the addon testable without any widgets.
]]

local function words(text)
    local list = {}
    for word in tostring(text):gmatch("%S+") do
        list[#list + 1] = word
    end
    return list
end

local function sortedKeys(map)
    local keys = {}
    for key in pairs(map or {}) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    return keys
end

-- Accepts "#12", "12", "@Account", "Account" or a character name.
local function resolveId(value)
    if type(value) ~= "string" or value == "" then
        return nil
    end

    local numeric = tonumber(value:gsub("^#", ""))
    if numeric and IRY.Store:GetPlayer(numeric) then
        return IRY.Store:ResolveFinal(numeric)
    end

    return IRY.Resolver:ForName(value)
end

local function resolveRawId(value)
    local numeric = value and tonumber(tostring(value):gsub("^#", ""))
    if numeric and IRY.Store:GetPlayer(numeric) then
        return numeric
    end
    return resolveId(value)
end

local function entityLabel(id)
    local player = id and IRY.Store:GetPlayer(IRY.Store:ResolveFinal(id))
    return player and player.displayName or "?"
end

local function pendingLabel(entry)
    if entry.account then
        return IRY.Util.FormatAccount(entry.account)
    end
    return tostring(entry.character or "?")
end

local function resolvePending(value)
    if value and value ~= "" then
        local id = tonumber(value:gsub("^#", ""))
        if id and IRY.Store:GetPending(id) then
            return id
        end
        return nil
    end

    local list = IRY.Store:GetPendingList()
    return list[1] and list[1].id or nil
end

local function printHelp()
    IRY:PrintLines(IRY.L.HELP)
end

local function cmdWho(value)
    if not value or value == "" then
        local id, account, character = IRY.Resolver:ForUnit("reticleover")
        if not id then
            IRY:Print(string.format(IRY.L.USAGE_ONE_ID, "who"))
            return
        end
        IRY:Debug(string.format("reticleover is %s / %s",
            tostring(account or "-"), tostring(character or "-")))
        value = tostring(id)
    end

    local id = resolveId(value)
    if not id then
        IRY:Print(string.format(IRY.L.NOT_FOUND, tostring(value)))
        return
    end

    local player = IRY.Store:GetPlayer(id)
    if not player then
        IRY:Print(string.format(IRY.L.ID_NOT_FOUND, tostring(value)))
        return
    end

    IRY:Print(string.format(IRY.L.WHO_HEADER, player.id, player.displayName,
        player.isCustom and IRY.L.CUSTOM or IRY.L.DEFAULT))

    for _, account in ipairs(sortedKeys(player.aliases)) do
        local alias = player.aliases[account]
        IRY:Print(string.format(IRY.L.WHO_ALIAS,
            IRY.Util.FormatAccount(account), alias.source, alias.confidence,
            IRY.Util.FormatTime(alias.lastSeen)))
    end

    for _, character in ipairs(sortedKeys(player.characters)) do
        local entry = player.characters[character]
        IRY:Print(string.format(IRY.L.WHO_CHARACTER, character,
            IRY.Util.FormatTime(entry.lastSeen)))
    end

    if player.notes and player.notes ~= "" then
        IRY:Print(string.format(IRY.L.WHO_NOTES, player.notes))
    end
end

local function cmdList(limitText)
    local list = IRY.Store:List(tonumber(limitText) or 10)
    if #list == 0 then
        IRY:Print(IRY.L.NO_PLAYERS)
        return
    end

    IRY:Print(string.format(IRY.L.LIST_HEADER, IRY.Store:Count()))
    for _, player in ipairs(list) do
        IRY:Print(string.format(IRY.L.LIST_LINE, player.id, player.displayName,
            player.isCustom and IRY.L.CUSTOM or IRY.L.DEFAULT,
            IRY.Util.FormatTime(player.updatedAt)))
    end
end

local function cmdMerge(first, second)
    local idA = resolveId(first)
    local idB = resolveId(second)

    if not idA or not idB then
        IRY:Print(IRY.L.MERGE_FAILED)
        return
    end

    if idA == idB then
        IRY:Print(string.format(IRY.L.SAME_PLAYER, idA))
        return
    end

    local keep, drop = IRY.Store:OrderForMerge(idA, idB)
    IRY.Store:Merge(drop, keep, "manual")
    IRY:Print(string.format(IRY.L.MERGED, drop, keep))
    IRY:RefreshUI()
end

local function cmdUndo(value)
    local raw = resolveRawId(value)
    local player = raw and IRY.Store:GetPlayer(raw)
    if not player then
        IRY:Print(string.format(IRY.L.ID_NOT_FOUND, tostring(value)))
        return
    end

    if not player.mergedInto then
        IRY:Print(string.format(IRY.L.NOT_MERGED, raw))
        return
    end

    local ok, dstId = IRY.Store:UndoMerge(raw)
    if not ok then
        IRY:Print(string.format(IRY.L.CANNOT_UNDO, raw))
        return
    end

    IRY:Print(string.format(IRY.L.UNDONE, raw, dstId))
    IRY:RefreshUI()
end

local function cmdRename(idText, name)
    local id = resolveId(idText)
    if not id then
        IRY:Print(string.format(IRY.L.NOT_FOUND, tostring(idText)))
        return
    end

    if not IRY.Store:SetDisplayName(id, name) then
        IRY:Print(IRY.L.RENAME_FAILED)
        return
    end

    IRY:Print(string.format(IRY.L.RENAMED, id, IRY.Resolver:DisplayName(id)))
    IRY:RefreshUI()
end

local function cmdReset(idText)
    local id = resolveId(idText)
    if not id then
        IRY:Print(string.format(IRY.L.NOT_FOUND, tostring(idText)))
        return
    end

    local ok, name = IRY.Store:ResetDisplayName(id)
    if not ok then
        IRY:Print(string.format(IRY.L.RESET_FAILED, id))
        return
    end

    IRY:Print(string.format(IRY.L.RESET_NAME, id, name))
    IRY:RefreshUI()
end

local function cmdForget(value)
    if not value or value == "" then
        IRY:Print(string.format(IRY.L.USAGE_ONE_ID, "forget"))
        return
    end

    local id = resolveRawId(value)
    if not id then
        IRY:Print(string.format(IRY.L.NOT_FOUND, tostring(value)))
        return
    end

    local ok, reason = IRY.Store:Forget(id)
    if not ok then
        if reason == "merged" then
            local player = IRY.Store:GetPlayer(id)
            local dst = player and IRY.Store:ResolveFinal(player.mergedInto) or 0
            IRY:Print(string.format(IRY.L.FORGET_MERGED, id, dst))
        elseif reason == "has-tombstones" then
            IRY:Print(string.format(IRY.L.FORGET_LOCKED, id))
        else
            IRY:Print(string.format(IRY.L.FORGET_FAILED, id))
        end
        return
    end

    IRY:Print(string.format(IRY.L.FORGOT, id))
    IRY:RefreshUI()
end

local function cmdPending()
    local list = IRY.Store:GetPendingList()
    if #list == 0 then
        IRY:Print(IRY.L.PENDING_NONE)
        return
    end

    IRY:Print(string.format(IRY.L.PENDING_HEADER, #list))
    for _, entry in ipairs(list) do
        IRY:Print(string.format(IRY.L.PENDING_LINE,
            entry.id,
            pendingLabel(entry),
            entityLabel(entry.targetId),
            entry.targetId or 0,
            entry.kind or "?"))
    end
end

local function cmdYes(value)
    local pendingId = resolvePending(value)
    if not pendingId then
        IRY:Print(IRY.L.PENDING_NONE)
        return
    end

    local entry = IRY.Observer:ApplyPending(pendingId)
    if not entry then
        IRY:Print(string.format(IRY.L.PENDING_GONE, pendingId))
        return
    end

    IRY:Print(string.format(IRY.L.PENDING_APPROVED, pendingId))
    IRY:RefreshUI()
end

local function cmdNo(value)
    local pendingId = resolvePending(value)
    if not pendingId then
        IRY:Print(IRY.L.PENDING_NONE)
        return
    end

    IRY.Observer:RejectPending(pendingId)
    IRY:Print(string.format(IRY.L.PENDING_REJECTED, pendingId))
end

-- The word is deliberately a separate token, so a stray Enter after the
-- command cannot delete anything. Both spellings are accepted whatever the
-- client language is, matching the existing `/pa debug wipe confirm` guard.
local function isPurgeConfirmed(word)
    if not word then
        return false
    end

    word = word:lower()
    return word == "confirm" or word == "подтверждаю" or word == "подтвердить"
end

local function cmdPurge(rest)
    local settings = IRY.Store:GetSettings() or {}
    local parts = {}

    for token in tostring(rest or ""):gmatch("%S+") do
        parts[#parts + 1] = token
    end

    local days = tonumber(settings.purgeAfterDays)
    local confirmed = false

    if parts[1] then
        local number = tonumber(parts[1])
        if number then
            days = number
            confirmed = isPurgeConfirmed(parts[2])
        elseif isPurgeConfirmed(parts[1]) then
            confirmed = true
        else
            IRY:Print(IRY.L.PURGE_USAGE)
            return
        end
    end

    if not days or days <= 0 then
        IRY:Print(IRY.L.PURGE_DISABLED)
        return
    end

    IRY:PurgeOldPlayers(days, confirmed)
end

local function sourceLabel(source)
    if source == IRY.ICON_SOURCE.MANUAL then
        return IRY.L.ICON_SOURCE_MANUAL
    end
    if source == IRY.ICON_SOURCE.BLACKLIST then
        return IRY.L.ICON_SOURCE_BLACKLIST
    end
    if source == IRY.ICON_SOURCE.DISABLED then
        return IRY.L.ICON_SOURCE_DISABLED
    end
    return IRY.L.ICON_SOURCE_NONE
end

local function cmdIcons(rest)
    local settings = IRY.Store:GetSettings() or {}
    local action = (rest or ""):lower()

    if action == "on" or action == "off" then
        settings.showIcons = (action == "on")
        IRY:RefreshUI()
        IRY:Print(action == "on" and IRY.L.CMD_ICONS_ON or IRY.L.CMD_ICONS_OFF)
        return
    end

    local osiStatus = IRY.Icons:OsiStatus()
    local osiLabel = IRY.L.ICON_OSI_MISSING
    if osiStatus == "ready" then
        osiLabel = IRY.L.ICON_OSI_READY
    elseif osiStatus == "custom-off" then
        osiLabel = IRY.L.ICON_OSI_CUSTOM_OFF
    end

    IRY:Print(string.format(IRY.L.CMD_ICONS_STATUS,
        settings.showIcons ~= false and IRY.L.ICONS_ON or IRY.L.ICONS_OFF,
        tonumber(settings.iconSize2d) or IRY.ICON.default,
        settings.blacklistIcons ~= false and IRY.L.ICONS_ON or IRY.L.ICONS_OFF,
        osiLabel))
end

local function cmdIcon(rest)
    local idText, argument = rest:match("^(%S+)%s*(.-)$")
    if not idText then
        IRY:Print(IRY.L.ICON_USAGE)
        return
    end

    local id = resolveId(idText)
    if not id then
        IRY:Print(string.format(IRY.L.NOT_FOUND, tostring(idText)))
        return
    end

    if argument == "" then
        local source, path = IRY.Icons:ResolvePlayer(id)
        IRY:Print(string.format(IRY.L.ICON_CURRENT, id, path or "-", sourceLabel(source)))
        return
    end

    if argument:lower() == "clear" then
        IRY.Icons:Clear(id)
        IRY:Print(string.format(IRY.L.ICON_CLEARED, id))
        return
    end

    local ok, reason = IRY.Icons:Assign(id, argument)
    if not ok then
        if reason == "invalid" then
            IRY:Print(IRY.L.ICON_INVALID)
        else
            IRY:Print(string.format(IRY.L.ID_NOT_FOUND, tostring(idText)))
        end
        return
    end

    IRY:Print(string.format(IRY.L.ICON_SET, id, argument))
end

-- Diagnostic entry point for the reticle marker: `/pa marker` reports the
-- settings, the control and the unit under the reticle; `/pa marker test` draws
-- a placeholder regardless of any setting.
local function cmdMarker(rest)
    if not IRY.ReticleMarker then
        IRY:Print(IRY.L.MARKER_MISSING)
        return
    end

    if (rest or ""):lower() == "test" then
        IRY.ReticleMarker:Test()
        return
    end

    IRY:PrintLines(IRY.ReticleMarker:Describe())
end

local function cmdDebug(rest)
    local parts = words(rest)
    local action = parts[1] and parts[1]:lower() or ""

    if action == "on" or action == "off" then
        IRY.Store:GetSettings().debug = (action == "on")
        IRY:Print(action == "on" and IRY.L.DEBUG_ON or IRY.L.DEBUG_OFF)
        return
    end

    if action == "fake" then
        local account = IRY.Util.NormalizeAccount(parts[2])
        local character = IRY.Util.NormalizeCharacter(parts[3])
        if not account and not character then
            IRY:Print(IRY.L.USAGE_FAKE)
            return
        end

        local id, result = IRY.Observer:Observe(account, character, IRY.SOURCE.TARGET)
        IRY:Print(string.format(IRY.L.DEBUG_FAKE,
            account and IRY.Util.FormatAccount(account) or "-",
            character or "-", id or -1, result or "?"))
        return
    end

    if action == "bridge" then
        local account = IRY.Util.NormalizeAccount(parts[2])
        local character = IRY.Util.NormalizeCharacter(parts[3])
        if not account and not character then
            IRY:Print(IRY.L.USAGE_FAKE)
            return
        end

        local id, result = IRY.Observer:Observe(account, character, IRY.SOURCE.TARGET)
        IRY:Print(string.format(IRY.L.DEBUG_BRIDGE,
            account and IRY.Util.FormatAccount(account) or "-",
            character or "-", id or -1, result or "?"))
        return
    end

    if action == "conflict" then
        local first  = IRY.Observer:Observe("TestAccA", "TestCharB", IRY.SOURCE.TARGET)
        local second = IRY.Observer:Observe("TestAccC", "TestCharD", IRY.SOURCE.TARGET)
        local merged, result = IRY.Observer:Observe("TestAccC", "TestCharB", IRY.SOURCE.TARGET)

        IRY:Print(string.format(IRY.L.DEBUG_CONFLICT, first or -1, second or -1,
            merged or -1, result or "?"))
        return
    end

    if action == "dump" then
        local id = resolveRawId(parts[2])
        local lines = id and IRY.Store:Dump(id)
        if not lines then
            IRY:Print(string.format(IRY.L.ID_NOT_FOUND, tostring(parts[2])))
            return
        end
        IRY:PrintLines(lines)
        return
    end

    if action == "ignore" then
        local list = IRY.Blacklist:List()
        if #list == 0 then
            IRY:Print(IRY.L.DEBUG_IGNORE_EMPTY)
        else
            IRY:Print(string.format(IRY.L.DEBUG_IGNORE, #list, table.concat(list, ", ")))
        end
        return
    end

    if action == "wipe" then
        if parts[2] ~= "confirm" then
            IRY:Print(IRY.L.WIPE_NEEDS_CONFIRM)
            return
        end
        IRY.Store:Wipe()
        IRY:Print(IRY.L.WIPED)
        return
    end

    printHelp()
end

local function handle(args)
    args = args or ""
    local command, rest = args:match("^%s*(%S+)%s*(.-)%s*$")

    if not command then
        printHelp()
        return
    end

    command = command:lower()

    if command == "who" then
        cmdWho(rest)

    elseif command == "list" then
        cmdList(rest)

    elseif command == "count" then
        IRY:Print(string.format(IRY.L.COUNT, IRY.Store:Count()))

    elseif command == "merge" then
        local first, second = rest:match("^(%S+)%s+(%S+)$")
        if not first then
            IRY:Print(string.format(IRY.L.USAGE_TWO_IDS, "merge"))
            return
        end
        cmdMerge(first, second)

    elseif command == "undo" then
        if rest == "" then
            IRY:Print(string.format(IRY.L.USAGE_ONE_ID, "undo"))
            return
        end
        cmdUndo(rest)

    elseif command == "rename" then
        local idText, name = rest:match("^(%S+)%s+(.+)$")
        if not idText or not name then
            IRY:Print(IRY.L.USAGE_RENAME)
            return
        end
        cmdRename(idText, name)

    elseif command == "reset" then
        if rest == "" then
            IRY:Print(string.format(IRY.L.USAGE_ONE_ID, "reset"))
            return
        end
        cmdReset(rest)

    elseif command == "forget" then
        cmdForget(rest)

    elseif command == "pending" then
        cmdPending()

    elseif command == "yes" then
        cmdYes(rest)

    elseif command == "no" then
        cmdNo(rest)

    elseif command == "purge" then
        cmdPurge(rest)

    elseif command == "icon" then
        cmdIcon(rest)

    elseif command == "icons" then
        cmdIcons(rest)

    elseif command == "marker" then
        cmdMarker(rest)

    elseif command == "browse" then
        IRY.Browser:Toggle()

    elseif command == "debug" then
        cmdDebug(rest)

    else
        IRY:Print(string.format(IRY.L.UNKNOWN_COMMAND, tostring(command)))
    end
end

function IRY:RegisterCommands()
    SLASH_COMMANDS["/pa"] = handle
    SLASH_COMMANDS["/iry"] = handle
end

-- Exposed so the browser window and tests can resolve a typed id the same way
-- the slash commands do.
IRY.Commands = {
    Handle = handle,
    ResolveId = resolveId,
}
