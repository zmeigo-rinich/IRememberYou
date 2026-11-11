--[[
    I remember you! -- rename detection.

    Three independent bridges between "before" and "after":

      1. the game tells us the @account changed (friends, group),
      2. the same character name shows up with a new @account (target, feed),
      3. a friend or guildie logs in on another character (same @account).

    (1) is confirmed by the client itself, (2) is a probable link handled by
    Observer (pending or merge), (3) needs no link at all.
]]

local Rename = {}
IRY.Rename = Rename

local function onlineFromStatus(status)
    return status == nil or status ~= PLAYER_STATUS_OFFLINE
end

-- displayName from GetFriendInfo/GetGuildMemberInfo back to a normal key.
local function fromDisplayName(value)
    return IRY.Util.NormalizeAccount(value)
end

function Rename:OnFriendRenamed(oldDisplayName, newDisplayName)
    local oldAccount = fromDisplayName(oldDisplayName)
    local newAccount = fromDisplayName(newDisplayName)

    if not oldAccount or not newAccount or oldAccount == newAccount then
        return
    end

    IRY:Debug(string.format("friend rename: %s -> %s",
        IRY.Util.FormatAccount(oldAccount), IRY.Util.FormatAccount(newAccount)))

    local idOld = IRY.Store:FindByAccount(oldAccount)
    local idNew = IRY.Store:FindByAccount(newAccount)

    -- Both names already known as separate entities: the game just told us
    -- they are one friend, so merge them.
    if idOld and idNew and idOld ~= idNew then
        local keep, drop = IRY.Store:OrderForMerge(idOld, idNew)
        IRY.Store:Merge(drop, keep, "friend-rename")
        IRY:NotifyMerged(keep, nil, idOld, idNew, drop)
        IRY:RefreshUI()
        return
    end

    if idOld then
        if IRY.Store:AttachAccount(idOld, newAccount, IRY.SOURCE.FRIEND, IRY.CONFIDENCE.CONFIRMED) then
            IRY:NotifyAccountLinked(idOld, oldAccount, newAccount, IRY.CONFIDENCE.CONFIRMED)
            IRY:RefreshUI()
        end
        return
    end

    -- We knew the new name but not the old one (first observation was after
    -- the rename): keep the old alias for history.
    if idNew then
        IRY.Store:AttachAccount(idNew, oldAccount, IRY.SOURCE.FRIEND, IRY.CONFIDENCE.CONFIRMED)
    end
end

function Rename:FindFriendIndex(account)
    local count = GetNumFriends() or 0
    for index = 1, count do
        local displayName = GetFriendInfo(index)
        if fromDisplayName(displayName) == account then
            return index
        end
    end
    return nil
end

function Rename:OnFriendCharacterUpdated(displayName)
    local account = fromDisplayName(displayName)
    if not account then
        return
    end

    local id = IRY.Store:FindByAccount(account)
    if not id then
        return
    end

    local index = self:FindFriendIndex(account)
    if not index then
        return
    end

    local hasCharacter, characterName, _, class, alliance, level, _, _, consoleId = GetFriendCharacterInfo(index)
    if not hasCharacter or not characterName then
        return
    end

    IRY.Observer:Observe(account, IRY.Util.NormalizeCharacter(characterName), IRY.SOURCE.FRIEND, {
        classId   = class or 0,
        alliance  = alliance or 0,
        level     = level or 0,
        consoleId = consoleId or "",
    }, {
        create = false,
        quiet  = true,
    })
end

-- A friend logged in (possibly on a new character): same account, new
-- character name, nothing to infer.
function Rename:OnFriendStatusChanged(displayName, oldStatus, newStatus)
    local account = fromDisplayName(displayName)
    if not account then
        return
    end

    local id = IRY.Store:FindByAccount(account)
    if not id then
        return
    end

    if onlineFromStatus(oldStatus) or not onlineFromStatus(newStatus) then
        return
    end

    self:OnFriendCharacterUpdated(displayName)
end

-- Group member changed @account without leaving the group. The unitTag is the
-- bridge; the client gives us the new account name directly.
function Rename:OnGroupAccountUpdated(unitTag, accountName)
    -- Be tolerant about the argument order: the event is console facing and
    -- documented only by its XML annotation.
    if type(unitTag) == "string" and unitTag:sub(1, 1) == "@"
        and type(accountName) == "string" and accountName:match("^group%d+$") then
        unitTag, accountName = accountName, unitTag
    end

    local account = IRY.Util.NormalizeAccount(accountName)
    if not account then
        return
    end

    local previous = IRY.Observer.unitAccounts[unitTag]
    IRY.Observer.unitAccounts[unitTag] = account

    if previous == account then
        return
    end

    local character
    if DoesUnitExist(unitTag) then
        character = IRY.Util.NormalizeCharacter(GetUnitName(unitTag))
    end

    IRY:Debug(string.format("group account update: %s -> %s",
        tostring(previous), IRY.Util.FormatAccount(account)))

    -- The client just told us this unit's account name changed, so the old
    -- and the new account are the same person even if we never saw their
    -- character before.
    local previousId = previous and IRY.Store:FindByAccount(previous) or nil
    if previousId then
        local newId = IRY.Store:FindByAccount(account)

        if newId and newId ~= previousId then
            local keep, drop = IRY.Store:OrderForMerge(previousId, newId)
            IRY.Store:Merge(drop, keep, "group-rename")
            IRY:NotifyMerged(keep, character, previousId, newId, drop)
            IRY:RefreshUI()
            return
        end

        if not newId then
            local attached = IRY.Store:AttachAccount(previousId, account, IRY.SOURCE.GROUP, IRY.CONFIDENCE.CONFIRMED)
            if character then
                IRY.Store:AttachCharacter(previousId, character, nil)
            end
            if attached then
                IRY:NotifyAccountLinked(previousId, previous, account, IRY.CONFIDENCE.CONFIRMED)
            end
            IRY:RefreshUI()
            return
        end
    end

    IRY.Observer:Observe(account, character, IRY.SOURCE.GROUP, nil, {
        confidence = IRY.CONFIDENCE.CONFIRMED,
    })
end

-- Character rename while the unit is around: the account did not change, the
-- new character name simply becomes another alias of the same entity.
function Rename:OnUnitCharacterRenamed(unitTag)
    if type(unitTag) ~= "string" then
        return
    end

    -- The event also fires for "player" (zoning, reload, character load) and
    -- for arbitrary units; only the reticle target and group members matter.
    if unitTag ~= "reticleover" and not unitTag:match("^group%d+$") then
        return
    end

    local source = (unitTag == "reticleover") and IRY.SOURCE.TARGET or IRY.SOURCE.GROUP
    IRY.Observer:KeepUnit(unitTag, source, {
        quiet      = true,
        confidence = IRY.CONFIDENCE.CONFIRMED,
    })
end

function Rename:Initialize()
    local name = IRY.name

    EVENT_MANAGER:RegisterForEvent(name, EVENT_FRIEND_DISPLAY_NAME_CHANGED, function(_, oldName, newName)
        IRY.Rename:OnFriendRenamed(oldName, newName)
    end)

    EVENT_MANAGER:RegisterForEvent(name, EVENT_FRIEND_CHARACTER_UPDATED, function(_, displayName)
        IRY.Rename:OnFriendCharacterUpdated(displayName)
    end)

    EVENT_MANAGER:RegisterForEvent(name, EVENT_FRIEND_PLAYER_STATUS_CHANGED, function(_, displayName, _, oldStatus, newStatus)
        IRY.Rename:OnFriendStatusChanged(displayName, oldStatus, newStatus)
    end)

    EVENT_MANAGER:RegisterForEvent(name, EVENT_GROUP_MEMBER_ACCOUNT_NAME_UPDATED, function(_, unitTag, accountName)
        IRY.Rename:OnGroupAccountUpdated(unitTag, accountName)
    end)

    EVENT_MANAGER:RegisterForEvent(name, EVENT_UNIT_CHARACTER_NAME_CHANGED, function(_, unitTag)
        IRY.Rename:OnUnitCharacterRenamed(unitTag)
    end)
end
