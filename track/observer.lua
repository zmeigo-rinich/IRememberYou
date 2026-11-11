--[[
    I remember you! -- observation layer.

    Every write to the store goes through Observer:Observe. Render paths
    (target frame, chat) never call it.

    Sources and how much we trust them:

      friend   account and character come from the friend list, which is tied
               to the account itself: confirmed. Every friend may create an
               entity, online or offline; offline friends contribute their last
               known character.
      group    account + character observed together on a group unit: confirmed.
      target   account + character observed together on reticleover: confirmed
               pairing, but a *new account* on a known character is only a
               probable rename, so it waits for /pa yes (see autoAcceptProbable).
      guild    enrichment only: never creates entities, only adds characters to
               accounts we already know.
      killfeed character + account guessed from the feed: probable, and it may
               create an entity when both names are new.
]]

local Observer = {}
IRY.Observer = Observer

-- unitTag -> last account key, for group account renames.
Observer.unitAccounts = {}

local GUILD_SCAN_CHUNK = 100
local GUILD_SCAN_DELAY = 100

local guildScan = {
    running = false,
    guildIndex = 1,
    memberIndex = 1,
    guildId = nil,
    numMembers = 0,
}

local function settings()
    return IRY.Store:GetSettings() or {}
end

-- The player themself. Parameters are already normalized keys.
function Observer:IsSelf(account, character)
    if account and IRY.Util.SameName(account,
        IRY.Util.NormalizeAccount(GetUnitDisplayName("player"))) then
        return true
    end

    if character and IRY.Util.SameName(character,
        IRY.Util.NormalizeCharacter(GetUnitName("player"))) then
        return true
    end

    return false
end

local function unitCharacterInfo(unitTag)
    local info = {}
    if GetUnitClassId then
        info.classId = GetUnitClassId(unitTag) or 0
    end
    if GetUnitAlliance then
        info.alliance = GetUnitAlliance(unitTag) or 0
    end
    if GetUnitLevel then
        info.level = GetUnitLevel(unitTag) or 0
    end
    return info
end

-- The single gate for every observation.
-- opts.create    -> may a new entity be created (default true)
-- opts.quiet     -> suppress the chat notification
-- opts.confidence-> override the confidence implied by the source
function Observer:Observe(account, character, source, info, opts)
    opts = opts or {}
    source = source or IRY.SOURCE.TARGET

    if not account and not character then
        return nil, "invalid"
    end

    local settingsNow = settings()

    -- Yourself is never a "remembered player". This is the central guard, so it
    -- covers the target frame, group snapshots, kill feed, friends and the
    -- character-rename event alike.
    if settingsNow.ignoreSelf and self:IsSelf(account, character) then
        return nil, "self"
    end

    local conf = opts.confidence
    if not conf then
        conf = (source == IRY.SOURCE.FRIEND or source == IRY.SOURCE.GROUP)
            and IRY.CONFIDENCE.CONFIRMED
            or IRY.CONFIDENCE.PROBABLE
    end

    local create = opts.create
    if create == nil then
        create = true
    end

    local pa = account and IRY.Store:FindByAccount(account) or nil
    local pc = character and IRY.Store:FindByCharacter(character) or nil

    if not pa and not pc and not create then
        return nil, "unknown"
    end

    -- Same character with two different accounts: one person, merge.
    if pa and pc and pa ~= pc then
        if not settingsNow.autoMergeOnConflict then
            if not opts.quiet then
                IRY:NotifyPending(self:AddConflictPending(pa, pc, account, character))
            end
            IRY:RefreshUI()
            return nil, "pending"
        end

        local keep, drop = IRY.Store:OrderForMerge(pa, pc)
        local id = IRY.Store:Merge(drop, keep, "conflict")
        IRY.Store:AttachAccount(keep, account, source, conf)
        IRY.Store:AttachCharacter(keep, character, info)
        IRY.Store:Touch(keep, account, character)

        if not opts.quiet then
            IRY:NotifyMerged(keep, character, pa, pc, drop)
        end
        IRY:RefreshUI()
        return id, "merged"
    end

    -- A new account seen together with a character we already know. The
    -- pairing itself is authoritative, but the inference "this is the same
    -- person" is not, so by default it waits for confirmation.
    if not pa and pc and account and conf == IRY.CONFIDENCE.PROBABLE
        and not settingsNow.autoAcceptProbable then
        local pendingId = IRY.Store:FindBridgePending(account, pc)
        if not pendingId then
            pendingId = IRY.Store:AddPending({
                kind       = "bridge",
                account    = account,
                character  = character,
                targetId   = pc,
                source     = source,
                confidence = conf,
            })
            if not opts.quiet then
                IRY:NotifyPending(pendingId)
            end
        end
        IRY:RefreshUI()
        return nil, "pending"
    end

    local id, action, addedAccount, addedCharacter =
        IRY.Store:Reconcile(account, character, source, info, conf)

    if action == "linked" and addedAccount and not opts.quiet then
        IRY:NotifyAccountLinked(id, nil, addedAccount, conf)
    end

    if action == "linked" or action == "merged" then
        IRY:RefreshUI()
    end

    return id, action, addedAccount, addedCharacter
end

function Observer:AddConflictPending(keepId, dropId, account, character)
    for _, entry in ipairs(IRY.Store:GetPendingList()) do
        if entry.kind == "conflict" and entry.keepId == keepId and entry.dropId == dropId then
            return entry.id
        end
    end

    return IRY.Store:AddPending({
        kind       = "conflict",
        keepId     = keepId,
        dropId     = dropId,
        account    = account,
        character  = character,
        targetId   = keepId,
        source     = IRY.SOURCE.TARGET,
        confidence = IRY.CONFIDENCE.PROBABLE,
    })
end

function Observer:ApplyPending(pendingId)
    local entry = IRY.Store:GetPending(pendingId)
    if not entry then
        return nil, "gone"
    end

    if entry.kind == "conflict" then
        local keep, drop = IRY.Store:OrderForMerge(entry.keepId, entry.dropId)
        IRY.Store:Merge(drop, keep, "conflict-approved")
    else
        IRY.Store:Reconcile(entry.account, entry.character, entry.source, nil, entry.confidence)
    end

    IRY.Store:RemovePending(pendingId)
    return entry
end

function Observer:RejectPending(pendingId)
    return IRY.Store:RemovePending(pendingId)
end

-- Unit snapshots --------------------------------------------------------------

function Observer:KeepUnit(unitTag, source, opts)
    opts = opts or {}

    if not unitTag or not DoesUnitExist(unitTag) or not IsUnitPlayer(unitTag) then
        return
    end

    local account   = IRY.Util.NormalizeAccount(GetUnitDisplayName(unitTag))
    local character = IRY.Util.NormalizeCharacter(GetUnitName(unitTag))

    if not account and not character then
        return
    end

    if account and unitTag:match("^group%d+$") then
        Observer.unitAccounts[unitTag] = account
    end

    self:Observe(account, character, source, unitCharacterInfo(unitTag), opts)
end

function Observer:SnapshotTarget(opts)
    if not settings().captureTarget then
        return
    end
    self:KeepUnit("reticleover", IRY.SOURCE.TARGET, opts)
end

function Observer:SnapshotGroup(opts)
    if not settings().captureGroup then
        return
    end

    local size = GetGroupSize() or 0
    for index = 1, size do
        local unitTag = GetGroupUnitTagByIndex(index)
        if unitTag then
            self:KeepUnit(unitTag, IRY.SOURCE.GROUP, opts)
        end
    end
end

-- Friends: the friend list is curated, so every friend may create an entity,
-- online or offline. For an offline friend the character is their last known
-- one; if the client has no character info at all, the entity is created from
-- the account alone.
function Observer:SnapshotFriends(opts)
    if not settings().captureFriends then
        return
    end

    local count = GetNumFriends() or 0

    for index = 1, count do
        local displayName = GetFriendInfo(index)
        local account = IRY.Util.NormalizeAccount(displayName)

        if account then
            local hasCharacter, characterName, _, class, alliance, level, _, _, consoleId =
                GetFriendCharacterInfo(index)

            local character, info
            if hasCharacter and characterName then
                character = IRY.Util.NormalizeCharacter(characterName)
                info = {
                    classId   = class or 0,
                    alliance  = alliance or 0,
                    level     = level or 0,
                    consoleId = consoleId or "",
                }
            end

            self:Observe(account, character, IRY.SOURCE.FRIEND, info, {
                create     = true,
                -- bulk snapshots never chat, only real events do
                quiet      = true,
                confidence = IRY.CONFIDENCE.CONFIRMED,
            })
        end
    end
end

-- Guild roster: enrichment only. We never create entities from a roster,
-- we only add missing character names to accounts we already remember.
function Observer:GuildMember(guildId, memberIndex)
    local displayName = GetGuildMemberInfo(guildId, memberIndex)
    local account = IRY.Util.NormalizeAccount(displayName)
    if not account then
        return
    end

    if not IRY.Store:FindByAccount(account) then
        return
    end

    local hasCharacter, characterName, _, class, alliance, level = GetGuildMemberCharacterInfo(guildId, memberIndex)
    if not hasCharacter or not characterName then
        return
    end

    self:Observe(account, IRY.Util.NormalizeCharacter(characterName), IRY.SOURCE.GUILD, {
        classId  = class or 0,
        alliance = alliance or 0,
        level    = level or 0,
    }, {
        create = false,
        quiet  = true,
    })
end

local function nextGuild(scan)
    local numGuilds = GetNumGuilds() or 0

    while scan.guildIndex <= numGuilds do
        local guildId = GetGuildId(scan.guildIndex)
        local numMembers = guildId and (GetNumGuildMembers(guildId) or 0) or 0

        if numMembers > 0 then
            scan.guildId     = guildId
            scan.numMembers  = numMembers
            scan.memberIndex = 1
            return true
        end

        scan.guildIndex = scan.guildIndex + 1
    end

    return false
end

function Observer:GuildStep()
    if not guildScan.running then
        return
    end

    if not settings().captureGuild then
        guildScan.running = false
        return
    end

    local processed = 0
    while processed < GUILD_SCAN_CHUNK do
        if not guildScan.guildId then
            if not nextGuild(guildScan) then
                guildScan.running = false
                return
            end
        end

        if guildScan.memberIndex > guildScan.numMembers then
            guildScan.guildId = nil
            guildScan.guildIndex = guildScan.guildIndex + 1
        else
            self:GuildMember(guildScan.guildId, guildScan.memberIndex)
            guildScan.memberIndex = guildScan.memberIndex + 1
            processed = processed + 1
        end
    end

    zo_callLater(function()
        IRY.Observer:GuildStep()
    end, GUILD_SCAN_DELAY)
end

function Observer:StartGuildScan()
    if not settings().captureGuild then
        return
    end
    if guildScan.running then
        return
    end

    guildScan.running     = true
    guildScan.guildIndex  = 1
    guildScan.memberIndex = 1
    guildScan.guildId     = nil
    guildScan.numMembers  = 0

    zo_callLater(function()
        IRY.Observer:GuildStep()
    end, GUILD_SCAN_DELAY)
end

function Observer:Initialize()
    local name = IRY.name

    EVENT_MANAGER:RegisterForEvent(name, EVENT_RETICLE_TARGET_CHANGED, function()
        IRY.Observer:SnapshotTarget()
    end)

    EVENT_MANAGER:RegisterForEvent(name, EVENT_GROUP_MEMBER_JOINED, function()
        IRY.Observer:SnapshotGroup({ quiet = true })
        IRY.Observer:SnapshotTarget()
    end)

    EVENT_MANAGER:RegisterForEvent(name, EVENT_GROUP_MEMBER_LEFT, function()
        IRY.Observer:SnapshotGroup({ quiet = true })
    end)

    EVENT_MANAGER:RegisterForEvent(name, EVENT_FRIEND_ADDED, function()
        IRY.Observer:SnapshotFriends({ quiet = true })
    end)

    EVENT_MANAGER:RegisterForEvent(name, EVENT_PLAYER_ACTIVATED, function()
        IRY.Observer:SnapshotGroup({ quiet = true })
        IRY.Observer:SnapshotFriends({ quiet = true })
        IRY.Observer:StartGuildScan()
    end)

    EVENT_MANAGER:RegisterForEvent(name, EVENT_GUILD_DATA_LOADED, function()
        IRY.Observer:StartGuildScan()
    end)

    EVENT_MANAGER:RegisterForEvent(name, EVENT_GUILD_MEMBER_CHARACTER_UPDATED, function(_, guildId, displayName)
        local index = GetGuildMemberIndexFromDisplayName(guildId, displayName)
        if index then
            IRY.Observer:GuildMember(guildId, index)
        end
    end)
end
