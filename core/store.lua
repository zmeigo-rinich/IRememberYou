--[[
    I remember you! -- the entity store.

    Source of truth: PlayerAliasesSV.players (players in IRememberYouSV).
    Lookup indices live in memory only and are rebuilt from `players` after
    every structural change. A merged entity is never deleted: it keeps its
    own data and gets `mergedInto`, which makes undo exact.
]]

local Store = {}
IRY.Store = Store

local sv
local index = { account = {}, character = {} }

local function now()
    return os.time()
end

local function newAlias(source, confidence)
    local t = now()
    return {
        firstSeen  = t,
        lastSeen   = t,
        source     = source or IRY.SOURCE.TARGET,
        confidence = confidence or IRY.CONFIDENCE.PROBABLE,
    }
end

local function newCharacter(info)
    local t = now()
    local character = {
        firstSeen = t,
        lastSeen  = t,
        classId   = 0,
        alliance  = 0,
        level     = 0,
        zoneId    = 0,
        consoleId = "",
    }

    if info then
        for key, value in pairs(info) do
            character[key] = value
        end
    end

    return character
end

local function confidenceForSource(source)
    if source == IRY.SOURCE.MANUAL then
        return IRY.CONFIDENCE.MANUAL
    end
    if source == IRY.SOURCE.FRIEND then
        return IRY.CONFIDENCE.CONFIRMED
    end
    return IRY.CONFIDENCE.PROBABLE
end

local function sourceRank(source)
    return IRY.SOURCE_PRIORITY[source] or 0
end

local function sortedKeys(map)
    local keys = {}
    for key in pairs(map or {}) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    return keys
end

function Store:Initialize(savedVars)
    sv = savedVars
    self:EnsureSchema()
    self:RebuildIndices()
end

function Store:EnsureSchema()
    if not sv then
        return
    end

    sv.schema  = sv.schema or IRY.svVersion
    sv.nextId  = sv.nextId or 1
    sv.nextPendingId = sv.nextPendingId or 1
    sv.players = sv.players or {}
    sv.pending = sv.pending or {}
    sv.stats   = sv.stats or { created = 0, linked = 0, merged = 0 }
    sv.settings = sv.settings or {}

    for key, value in pairs(IRY.SettingsDefaults) do
        if sv.settings[key] == nil then
            sv.settings[key] = value
        end
    end
end

function Store:GetSV()
    return sv
end

function Store:GetSettings()
    return sv and sv.settings
end

function Store:GetPlayer(id)
    if not sv or not id then
        return nil
    end
    return sv.players[id]
end

function Store:GetPlayers()
    return sv and sv.players
end

function Store:RebuildIndices()
    index.account = {}
    index.character = {}

    if not sv then
        return
    end

    for id, player in pairs(sv.players) do
        if not player.mergedInto then
            for account in pairs(player.aliases or {}) do
                index.account[account] = id
            end
            for character in pairs(player.characters or {}) do
                index.character[character] = id
            end
        end
    end
end

function Store:FindByAccount(account)
    if not account then
        return nil
    end
    return index.account[account]
end

function Store:FindByCharacter(character)
    if not character then
        return nil
    end
    return index.character[character]
end

function Store:FindAny(key)
    if not key then
        return nil
    end
    return index.account[key] or index.character[key]
end

function Store:ResolveFinal(id)
    if not id or not sv then
        return nil
    end

    local seen = {}
    while id and sv.players[id] and sv.players[id].mergedInto do
        if seen[id] then
            break
        end
        seen[id] = true
        id = sv.players[id].mergedInto
    end

    return id
end

function Store:Count()
    if not sv then
        return 0
    end

    local count = 0
    for _, player in pairs(sv.players) do
        if not player.mergedInto then
            count = count + 1
        end
    end
    return count
end

function Store:CreatePlayer(account, character, source, confidence, info)
    local id = sv.nextId
    sv.nextId = id + 1

    local player = {
        id          = id,
        displayName = account and IRY.Util.FormatAccount(account) or character or "?",
        isCustom    = false,
        createdAt   = now(),
        updatedAt   = now(),
        notes       = "",
        aliases     = {},
        characters  = {},
    }

    if account then
        player.aliases[account] = newAlias(source, confidence)
        index.account[account] = id
    end

    if character then
        player.characters[character] = newCharacter(info)
        index.character[character] = id
    end

    sv.players[id] = player
    sv.stats.created = sv.stats.created + 1

    return id
end

-- Returns true when the account was not known for this entity yet.
function Store:AttachAccount(id, account, source, confidence)
    id = self:ResolveFinal(id)
    local player = id and sv.players[id]
    if not player or not account then
        return false
    end

    local alias = player.aliases[account]
    if alias then
        alias.lastSeen = now()
        if sourceRank(source) > sourceRank(alias.source) then
            alias.source = source
        end
        if confidence == IRY.CONFIDENCE.CONFIRMED then
            alias.confidence = confidence
        end
        return false
    end

    local owner = index.account[account]
    if owner and owner ~= id then
        -- Belongs to another entity: the caller has to merge, not re-index.
        return false
    end

    player.aliases[account] = newAlias(source, confidence)
    index.account[account] = id
    sv.stats.linked = sv.stats.linked + 1
    return true
end

-- Returns true when the character was not known for this entity yet.
function Store:AttachCharacter(id, character, info)
    id = self:ResolveFinal(id)
    local player = id and sv.players[id]
    if not player or not character then
        return false
    end

    local existing = player.characters[character]
    if existing then
        existing.lastSeen = now()
        if info then
            for key, value in pairs(info) do
                if value ~= nil and value ~= "" and value ~= 0 then
                    existing[key] = value
                end
            end
        end
        return false
    end

    local owner = index.character[character]
    if owner and owner ~= id then
        return false
    end

    player.characters[character] = newCharacter(info)
    index.character[character] = id
    sv.stats.linked = sv.stats.linked + 1
    return true
end

function Store:Touch(id, account, character)
    local player = id and sv.players[id]
    if not player then
        return
    end

    player.updatedAt = now()

    if account then
        local alias = player.aliases[account]
        if alias then
            alias.lastSeen = now()
        end
    end

    if character then
        local entry = player.characters[character]
        if entry then
            entry.lastSeen = now()
        end
    end
end

-- The single entry point for observations.
-- account / character must already be normalized (IRY.Util.Normalize*).
-- Returns: playerId, action, extra...
function Store:Reconcile(account, character, source, info, confidence)
    if not account and not character then
        return nil, "invalid"
    end

    source = source or IRY.SOURCE.TARGET
    confidence = confidence or confidenceForSource(source)

    local pa = account and index.account[account] or nil
    local pc = character and index.character[character] or nil

    -- Two different entities share this observation: same character must mean
    -- the same person, so the entities are merged.
    if pa and pc and pa ~= pc then
        local keep, drop = self:OrderForMerge(pa, pc)
        self:Merge(drop, keep, "conflict")

        if account then
            self:AttachAccount(keep, account, source, confidence)
        end
        if character then
            self:AttachCharacter(keep, character, info)
        end
        self:Touch(keep, account, character)

        sv.stats.linked = sv.stats.linked + 1
        return keep, "merged", pa, pc
    end

    if not pa and not pc then
        local id = self:CreatePlayer(account, character, source, confidence, info)
        return id, "created"
    end

    local id = pa or pc
    local addedAccount, addedCharacter

    if account and not pa then
        if self:AttachAccount(id, account, source, confidence) then
            addedAccount = account
        end
    end

    -- Pass a known character through too: this is where a rare alliance change
    -- (and any level/class update) is applied. AttachCharacter only fills
    -- non-zero values, so an observation without info never erases what we
    -- already know.
    if character then
        if self:AttachCharacter(id, character, info) then
            addedCharacter = character
        end
    end

    self:Touch(id, account, character)

    if addedAccount or addedCharacter then
        return id, "linked", addedAccount, addedCharacter
    end
    return id, "same"
end

-- Older entity survives: it holds the custom name, notes and history.
function Store:OrderForMerge(idA, idB)
    local a = sv.players[idA]
    local b = sv.players[idB]

    if not a then
        return idB, idA
    end
    if not b then
        return idA, idB
    end

    if a.createdAt ~= b.createdAt then
        if a.createdAt < b.createdAt then
            return idA, idB
        end
        return idB, idA
    end

    if a.id <= b.id then
        return idA, idB
    end
    return idB, idA
end

function Store:Merge(srcId, dstId, reason)
    srcId = self:ResolveFinal(srcId)
    dstId = self:ResolveFinal(dstId)

    if not srcId or not dstId or srcId == dstId then
        return dstId
    end

    local src = sv.players[srcId]
    local dst = sv.players[dstId]
    if not src or not dst then
        return nil
    end

    for account, alias in pairs(src.aliases or {}) do
        local existing = dst.aliases[account]
        if not existing then
            dst.aliases[account] = alias
        else
            existing.firstSeen = math.min(existing.firstSeen, alias.firstSeen)
            existing.lastSeen  = math.max(existing.lastSeen, alias.lastSeen)
            if sourceRank(alias.source) > sourceRank(existing.source) then
                existing.source = alias.source
            end
            if alias.confidence == IRY.CONFIDENCE.CONFIRMED then
                existing.confidence = alias.confidence
            end
        end
    end

    for character, entry in pairs(src.characters or {}) do
        local existing = dst.characters[character]
        if not existing then
            dst.characters[character] = entry
        else
            existing.firstSeen = math.min(existing.firstSeen, entry.firstSeen)
            existing.lastSeen  = math.max(existing.lastSeen, entry.lastSeen)
            for key, value in pairs(entry) do
                if key ~= "firstSeen" and key ~= "lastSeen" then
                    if existing[key] == nil or existing[key] == "" or existing[key] == 0 then
                        if value ~= nil and value ~= "" and value ~= 0 then
                            existing[key] = value
                        end
                    end
                end
            end
        end
    end

    if not dst.isCustom and src.isCustom then
        dst.displayName = src.displayName
        dst.isCustom = true
    end

    -- The icon belongs to the player it was assigned to. It is inherited only
    -- when the surviving entity has none. iconFrom records the direct source so
    -- undo can detach the inheritance without touching a manual choice.
    if not dst.icon and src.icon then
        dst.icon = src.icon
        dst.iconFrom = srcId
    end

    if src.notes and src.notes ~= "" then
        if dst.notes and dst.notes ~= "" then
            dst.notes = dst.notes .. "\n" .. src.notes
        else
            dst.notes = src.notes
        end
    end

    src.mergedInto = dstId
    src.mergedAt = now()
    src.mergeReason = reason or "merge"

    dst.updatedAt = now()
    sv.stats.merged = sv.stats.merged + 1

    self:RebuildIndices()
    return dstId
end

-- srcId must be the id of the absorbed (tombstone) entity.
function Store:UndoMerge(srcId)
    local src = srcId and sv.players[srcId]
    if not src or not src.mergedInto then
        return false, nil
    end

    local dstId = self:ResolveFinal(src.mergedInto)
    local dst = sv.players[dstId]
    if not dst then
        return false, nil
    end

    -- Keys are disjoint by construction: an account or character belongs to one
    -- entity only, so everything listed on src was copied by the merge. The
    -- index check keeps nested merges consistent if something was unmerged in
    -- a different order.
    for account in pairs(src.aliases or {}) do
        if index.account[account] == dstId then
            dst.aliases[account] = nil
        end
    end
    for character in pairs(src.characters or {}) do
        if index.character[character] == dstId then
            dst.characters[character] = nil
        end
    end

    -- Put the inherited icon back on src. A survivor may have inherited the same
    -- texture through a later merge, so detach the whole chain: src -> child ->
    -- child's child, stopping as soon as an entity owns its icon.
    local child = src
    while child.mergedInto do
        local nextChild = sv.players[child.mergedInto]
        if not nextChild or nextChild.iconFrom ~= child.id then
            break
        end
        nextChild.icon = nil
        nextChild.iconFrom = nil
        child = nextChild
    end

    src.mergedInto = nil
    src.mergedAt = nil
    src.mergeReason = nil
    dst.updatedAt = now()

    self:RebuildIndices()
    return true, dstId
end

function Store:DefaultDisplayName(player)
    local account, accountTime
    for key, alias in pairs(player.aliases or {}) do
        local t = alias.firstSeen or 0
        if not accountTime or t < accountTime then
            account, accountTime = key, t
        end
    end
    if account then
        return IRY.Util.FormatAccount(account)
    end

    local bestCharacter, bestTime
    for key, entry in pairs(player.characters or {}) do
        local t = entry.firstSeen or 0
        if not bestTime or t < bestTime then
            bestCharacter, bestTime = key, t
        end
    end
    if bestCharacter then
        return bestCharacter
    end

    return "?"
end

function Store:SetDisplayName(id, name)
    id = self:ResolveFinal(id)
    local player = id and sv.players[id]
    if not player then
        return false
    end

    local clean = IRY.Util.SanitizeDisplayName(name)
    if not clean then
        return false
    end

    player.displayName = clean
    player.isCustom = true
    player.updatedAt = now()
    return true
end

function Store:ResetDisplayName(id)
    id = self:ResolveFinal(id)
    local player = id and sv.players[id]
    if not player then
        return false, nil
    end

    player.isCustom = false
    player.displayName = self:DefaultDisplayName(player)
    player.updatedAt = now()

    return true, player.displayName
end

-- Icons ----------------------------------------------------------------------
-- player.icon is a single texture path, shared by every surface and by the
-- 3D bridge. The path is validated here so a typo cannot reach the renderer.

function Store:GetIconPath(id)
    id = self:ResolveFinal(id)
    local player = id and sv and sv.players[id]
    return player and player.icon or nil
end

function Store:SetIcon(id, path)
    id = self:ResolveFinal(id)
    local player = id and sv and sv.players[id]
    if not player then
        return false, "not-found"
    end

    if not IRY.IsIconPath(path) then
        return false, "invalid"
    end

    player.icon = path
    player.iconFrom = nil
    player.updatedAt = now()
    return true
end

function Store:ClearIcon(id)
    id = self:ResolveFinal(id)
    local player = id and sv and sv.players[id]
    if not player then
        return false, "not-found"
    end

    player.icon = nil
    player.iconFrom = nil
    player.updatedAt = now()
    return true
end

function Store:List(limit)
    if not sv then
        return {}
    end

    local list = {}
    for _, player in pairs(sv.players) do
        if not player.mergedInto then
            list[#list + 1] = player
        end
    end

    table.sort(list, function(a, b)
        if a.updatedAt == b.updatedAt then
            return a.id < b.id
        end
        return a.updatedAt > b.updatedAt
    end)

    if limit and limit > 0 and #list > limit then
        local trimmed = {}
        for i = 1, limit do
            trimmed[i] = list[i]
        end
        return trimmed
    end

    return list
end

function Store:Dump(id)
    local player = sv and sv.players[id]
    if not player then
        return nil
    end

    local lines = {}
    lines[#lines + 1] = string.format("#%d  %s  (custom=%s, created=%s, updated=%s)",
        player.id, player.displayName, tostring(player.isCustom),
        IRY.Util.FormatTime(player.createdAt), IRY.Util.FormatTime(player.updatedAt))

    if player.mergedInto then
        lines[#lines + 1] = string.format("  merged into #%d  (%s)", player.mergedInto, tostring(player.mergeReason))
    end

    if player.icon then
        lines[#lines + 1] = "  icon: " .. player.icon
            .. (player.iconFrom and ("  (from #" .. tostring(player.iconFrom) .. ")") or "")
    end

    for _, account in ipairs(sortedKeys(player.aliases)) do
        local alias = player.aliases[account]
        lines[#lines + 1] = string.format("  account %s  [%s/%s]  first=%s  last=%s",
            IRY.Util.FormatAccount(account), alias.source, alias.confidence,
            IRY.Util.FormatTime(alias.firstSeen), IRY.Util.FormatTime(alias.lastSeen))
    end

    for _, character in ipairs(sortedKeys(player.characters)) do
        local entry = player.characters[character]
        lines[#lines + 1] = string.format("  character %s  first=%s  last=%s  class=%d  alliance=%d  level=%d  zone=%d  console=%s",
            character, IRY.Util.FormatTime(entry.firstSeen), IRY.Util.FormatTime(entry.lastSeen),
            entry.classId or 0, entry.alliance or 0, entry.level or 0, entry.zoneId or 0,
            tostring(entry.consoleId or ""))
    end

    if player.notes and player.notes ~= "" then
        lines[#lines + 1] = "  notes: " .. player.notes
    end

    return lines
end

-- Deletes one entity. Deliberately does not resolve merged ids: forgetting a
-- tombstone must not delete the entity it was merged into. Entities that have
-- tombstones pointing at them are locked until those merges are undone, which
-- keeps the undo chain valid.
function Store:Forget(id)
    local player = id and sv and sv.players[id]
    if not player then
        return false, "not-found"
    end

    if player.mergedInto then
        return false, "merged"
    end

    for _, other in pairs(sv.players) do
        if other.mergedInto == id then
            return false, "has-tombstones"
        end
    end

    -- Pending entries referencing this entity would dangle after the delete.
    local list = self:GetPendingList()
    for index = #list, 1, -1 do
        local entry = list[index]
        if entry.targetId == id or entry.keepId == id or entry.dropId == id then
            table.remove(list, index)
        end
    end

    sv.players[id] = nil
    self:RebuildIndices()
    return true
end

-- Pending confirmations -------------------------------------------------------
-- A "bridge" is an account that showed up together with a character we already
-- know. It is stored instead of applied until the user says /pa yes.
function Store:AddPending(entry)
    if not sv then
        return nil
    end

    entry.id = sv.nextPendingId or 1
    sv.nextPendingId = entry.id + 1
    entry.createdAt = now()
    sv.pending[#sv.pending + 1] = entry
    return entry.id
end

function Store:GetPending(id)
    if not sv or not id then
        return nil
    end

    for _, entry in ipairs(sv.pending) do
        if entry.id == id then
            return entry
        end
    end
    return nil
end

function Store:GetPendingList()
    return (sv and sv.pending) or {}
end

function Store:FindBridgePending(account, targetId)
    for _, entry in ipairs(self:GetPendingList()) do
        if entry.kind == "bridge" and entry.account == account and entry.targetId == targetId then
            return entry.id
        end
    end
    return nil
end

function Store:RemovePending(id)
    local list = self:GetPendingList()
    for index, entry in ipairs(list) do
        if entry.id == id then
            table.remove(list, index)
            return true
        end
    end
    return false
end

function Store:PrunePending(days)
    local list = self:GetPendingList()
    if #list == 0 then
        return 0
    end

    days = tonumber(days) or (sv.settings and sv.settings.pendingTtlDays) or 30
    if days <= 0 then
        return 0
    end

    local cutoff = now() - days * 24 * 60 * 60
    local removed = 0

    for index = #list, 1, -1 do
        if (list[index].createdAt or 0) < cutoff then
            table.remove(list, index)
            removed = removed + 1
        end
    end

    return removed
end

function Store:Purge(days)
    if not sv then
        return 0
    end

    days = tonumber(days) or sv.settings.purgeAfterDays
    if not days or days <= 0 then
        return 0
    end

    local cutoff = now() - days * 24 * 60 * 60
    local removed = 0

    for id, player in pairs(sv.players) do
        if not player.mergedInto and not player.isCustom then
            local newest = 0
            for _, alias in pairs(player.aliases or {}) do
                newest = math.max(newest, alias.lastSeen or 0)
            end
            for _, entry in pairs(player.characters or {}) do
                newest = math.max(newest, entry.lastSeen or 0)
            end

            if newest < cutoff then
                sv.players[id] = nil
                removed = removed + 1
            end
        end
    end

    if removed > 0 then
        self:RebuildIndices()
    end

    return removed
end

function Store:Wipe()
    if not sv then
        return
    end

    sv.players = {}
    sv.pending = {}
    sv.nextId = 1
    sv.nextPendingId = 1
    sv.stats = { created = 0, linked = 0, merged = 0 }

    self:RebuildIndices()
end
