--[[
    I remember you! -- local chat output and rename notifications.

    Everything printed here stays local: AddSystemMessage never reaches
    other players.
]]

function IRY:Print(text)
    CHAT_ROUTER:AddSystemMessage(IRY.MSG_PREFIX .. tostring(text))
end

function IRY:PrintLines(lines)
    for _, line in ipairs(lines) do
        self:Print(line)
    end
end

function IRY:Debug(text)
    local settings = IRY.Store and IRY.Store:GetSettings()
    if settings and settings.debug then
        CHAT_ROUTER:AddSystemMessage(IRY.MSG_PREFIX .. "|c888888" .. tostring(text) .. "|r")
    end
end

-- Redraw the reticle frame right away instead of waiting for the game to
-- change targets. Defined in ui/targetframe.lua.
function IRY:RefreshTargets()
    if IRY.TargetFrame then
        IRY.TargetFrame:Refresh()
    end
end

-- Every surface that shows a name: call this after any store change that can
-- rename or merge an entity. The browser only redraws when it is open.
function IRY:RefreshUI()
    self:RefreshTargets()

    if IRY.Browser then
        IRY.Browser:RefreshIfShown()
    end
end

-- notifyLevel: off | confirmed | all
local function shouldNotify(confidence)
    local settings = IRY.Store and IRY.Store:GetSettings()
    local level = (settings and settings.notifyLevel) or "confirmed"

    if level == "off" then
        return false
    end
    if level == "all" then
        return true
    end

    return confidence == IRY.CONFIDENCE.CONFIRMED or confidence == IRY.CONFIDENCE.MANUAL
end
IRY.ShouldNotify = shouldNotify

-- Raw entity name: intentionally not resolved through mergedInto, because a
-- merge notification has to show the name the absorbed entity had *before*.
local function entityName(id)
    local player = id and IRY.Store:GetPlayer(id)
    return player and player.displayName or "?"
end

-- A new @account was attached to an entity we already knew. That is exactly a
-- rename from the user's point of view: the stable display name stays, the
-- account behind it changed.
function IRY:NotifyAccountLinked(id, oldAccount, newAccount, confidence)
    if not shouldNotify(confidence) then
        return
    end

    local player = IRY.Store:GetPlayer(IRY.Store:ResolveFinal(id))
    if not player then
        return
    end

    local oldName = oldAccount and IRY.Util.FormatAccount(oldAccount)
        or IRY.Store:DefaultDisplayName(player)

    self:Print(string.format(IRY.L.ACCOUNT_LINKED,
        oldName,
        IRY.Util.FormatAccount(newAccount),
        player.displayName,
        player.id,
        tostring(confidence or IRY.CONFIDENCE.PROBABLE)))
end

-- Two entities turned out to be one person, because the same character was
-- seen with two different @accounts.
function IRY:NotifyMerged(keepId, character, idA, idB, dropId)
    local keep = IRY.Store:GetPlayer(IRY.Store:ResolveFinal(keepId))
    if not keep then
        return
    end

    local nameA = entityName(idA)
    local nameB = entityName(idB)

    self:Print(string.format(IRY.L.MERGED_AUTO,
        tostring(character or "?"),
        nameA,
        nameB,
        keep.displayName,
        keep.id,
        tonumber(dropId) or 0))
end

function IRY:NotifyPending(pendingId)
    local entry = IRY.Store:GetPending(pendingId)
    if not entry then
        return
    end

    local target = entityName(entry.targetId)
    local subject = entry.account and IRY.Util.FormatAccount(entry.account) or tostring(entry.character or "?")

    self:Print(string.format(IRY.L.PENDING_ADDED,
        entry.id,
        subject,
        target,
        IRY.Store:ResolveFinal(entry.targetId) or 0,
        entry.id,
        entry.id))
end

-- Applies the retention setting and reports the result in chat. Shared by the
-- settings panel button and the browser, so both behave identically.
function IRY:PurgeOldPlayers(days)
    local settings = IRY.Store and IRY.Store:GetSettings()
    days = tonumber(days) or (settings and tonumber(settings.purgeAfterDays)) or 0

    if days <= 0 then
        self:Print(IRY.L.PURGE_DISABLED)
        return 0
    end

    local removed = IRY.Store:Purge(days)
    if removed > 0 then
        self:Print(string.format(IRY.L.PURGED, removed, days))
    else
        self:Print(string.format(IRY.L.PURGE_NONE, days))
    end

    self:RefreshUI()
    return removed
end
