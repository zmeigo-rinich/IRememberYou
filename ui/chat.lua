--[[
    I remember you! -- stable name in chat.

    Two surfaces, both display only:

      1. player links (the name the game shows for a sender, for mentions and
         for every chat line): the suffix is inserted *inside* the link text,
         the link payload is untouched, so clicking still resolves the real
         @account.

      2. the PvP kill feed: it is built from colorized strings, not links, so
         the registered formatter is wrapped and the names are annotated in
         the finished message. The same event is also a data source. The names
         are found by their visible text (colour codes stripped), because the
         game's colour depends on the alliance and another addon's formatter
         may have already rewritten the line.

    Nothing here ever writes to chat for other players: AddSystemMessage and
    the formatters are local.
]]

local Chat = {}
IRY.Chat = Chat

local function settings()
    return IRY.Store:GetSettings() or {}
end

local function selfAccount()
    return IRY.Util.NormalizeAccount(GetUnitDisplayName("player"))
end

local function selfCharacter()
    return IRY.Util.NormalizeCharacter(GetUnitName("player"))
end

function Chat:IsSelf(account, character)
    if account and IRY.Util.SameName(account, selfAccount()) then
        return true
    end
    if character and IRY.Util.SameName(character, selfCharacter()) then
        return true
    end
    return false
end

-- Resolve a name that came from the UI (a link argument or a message) to the
-- display name of the entity behind it. All arguments are normalized keys.
function Chat:DisplayNameFor(account, character)
    local id

    if account then
        id = IRY.Store:FindByAccount(account)
    end
    if not id and character then
        id = IRY.Store:FindByCharacter(character)
    end
    if not id then
        return nil
    end

    return IRY.Resolver:DisplayName(id)
end

-- Shared suffix builder: returns " (Stable Name)" or nil. `shownName` is the
-- name the game displays; nothing is appended when it already matches.
local function buildSuffix(account, character, shownName)
    local accountKey = account and IRY.Util.NormalizeAccount(account) or nil
    local characterKey = character and IRY.Util.NormalizeCharacter(character) or nil

    -- A bare name from a player link is either a decorated @account or a
    -- character name. Undecorated names are characters (a character cannot be
    -- confused with the account of the same person, only with a stranger's
    -- account that happens to have the same text, which we prefer to avoid).
    if not accountKey and not characterKey then
        if not shownName or shownName == "" then
            return nil
        end
        if IsDecoratedDisplayName and IsDecoratedDisplayName(shownName) then
            accountKey = IRY.Util.NormalizeAccount(shownName)
        else
            characterKey = IRY.Util.NormalizeCharacter(shownName)
        end
    end

    if not settings().annotateSelf and Chat:IsSelf(accountKey, characterKey) then
        return nil
    end

    local displayName = Chat:DisplayNameFor(accountKey, characterKey)
    if not displayName or displayName == "" then
        return nil
    end

    if shownName and IRY.Util.SameName(displayName, shownName) then
        return nil
    end
    if characterKey and IRY.Util.SameName(displayName, characterKey) then
        return nil
    end

    return " (" .. displayName .. ")"
end

-- Player links and the kill feed.
function Chat:Suffix(account, character, shownName)
    if not settings().annotateChat then
        return nil
    end
    return buildSuffix(account, character, shownName)
end

-- Friends list and guild roster rows. A separate setting, because some people
-- want chat clean but the social lists annotated (or the other way round).
function Chat:SocialSuffix(account, character, shownName)
    if not settings().annotateSocial then
        return nil
    end
    return buildSuffix(account, character, shownName)
end

-- Player links ----------------------------------------------------------------

local function installLinkHook()
    local original = ZO_LinkHandler_CreatePlayerLink
    if type(original) ~= "function" or original == Chat.LinkWrapper then
        return
    end

    local function wrapped(name)
        local link = original(name)
        if type(link) ~= "string" then
            return link
        end

        local suffix = IRY.Chat:Suffix(nil, nil, name)
        if not suffix then
            return link
        end

        -- |H0:display:0:|h[@Name]|h  ->  |H0:display:0:|h[@Name] (Stable)|h
        local head, text = link:match("^(.-)|h(.-)|h$")
        if not head or not text then
            return link
        end

        return head .. "|h" .. text .. suffix .. "|h"
    end

    Chat.LinkWrapper = wrapped
    ZO_LinkHandler_CreatePlayerLink = wrapped
end

-- PvP kill feed ---------------------------------------------------------------

local function observeCombatant(displayName, characterName)
    if not settings().captureKillFeed then
        return
    end

    local account = IRY.Util.NormalizeAccount(displayName)
    local character = IRY.Util.NormalizeCharacter(characterName)
    if not account and not character then
        return
    end

    IRY.Observer:Observe(account, character, IRY.SOURCE.KILLFEED, nil, {
        quiet = true,
    })
end

-- The kill feed has its own setting: turning chat links off must not silently
-- turn the feed off as well.
local function killFeedSuffix(displayName, characterName, shownName)
    if not settings().annotateKillFeed then
        return nil
    end
    return buildSuffix(displayName, characterName, shownName)
end

-- The game colorizes the name it prints, and the colour depends on the
-- alliance, the battleground team and sometimes on another addon's formatter.
-- Matching the visible text instead of the colorized needle keeps the
-- annotation working no matter which colour (or no colour at all) was used.
local function visibleText(text)
    local chars = {}
    local map = {}
    local index = 1

    while index <= #text do
        local colorCode = text:sub(index, index + 7)
        if colorCode:sub(1, 2) == "|c" and colorCode:match("^|c%x%x%x%x%x%x$") then
            index = index + 8
        elseif text:sub(index, index + 1) == "|r" then
            index = index + 2
        else
            chars[#chars + 1] = text:sub(index, index)
            map[#chars] = index
            index = index + 1
        end
    end

    return table.concat(chars), map
end

local function primaryName(displayName, characterName)
    if type(ZO_GetPrimaryPlayerName) == "function" then
        local ok, name = pcall(ZO_GetPrimaryPlayerName, displayName, characterName)
        if ok and type(name) == "string" and name ~= "" then
            return name
        end
    end
    return characterName or displayName
end

-- The first candidate is the name the game itself prints (ZO_GetPrimaryPlayerName
-- is exactly what the kill feed formatter uses). The rest cover clients where the
-- formatter falls back to the other name or drops the leading @.
local function nameCandidates(displayName, characterName, shownName)
    local list = {}
    local seen = {}

    local function add(name)
        if type(name) == "string" and name ~= "" and not seen[name] then
            seen[name] = true
            list[#list + 1] = name
        end
    end

    add(shownName)
    add(characterName)
    add(displayName)

    if type(displayName) == "string" then
        add(displayName:gsub("^@", ""))
    end

    return list
end

local function findCandidate(visible, candidates, from)
    for _, name in ipairs(candidates) do
        local _, last = visible:find(name, from, true)
        if last then
            return last
        end
    end
    return nil
end

-- Insert both suffixes into one finished message/narration. The victim is
-- searched for after the killer, so a self-kill annotates the second occurrence
-- instead of the first one twice. Insertion goes right to left, so the byte
-- offsets collected on the original string stay valid.
local function annotateTargets(text, killerNames, killerSuffix, victimNames, victimSuffix)
    if type(text) ~= "string" or text == "" or (not killerSuffix and not victimSuffix) then
        return text
    end

    local visible, map = visibleText(text)

    -- The killer is located even when there is no suffix for them: it lets the
    -- victim search skip the first name in a "Killer killed Victim" line.
    local killerLast = findCandidate(visible, killerNames, 1)

    local victimLast
    if victimSuffix then
        victimLast = findCandidate(visible, victimNames, (killerLast or 0) + 1)
    end

    local function alreadyAnnotated(last, suffix)
        return last ~= nil and visible:sub(last + 1, last + #suffix) == suffix
    end

    local inserts = {}

    if killerLast and killerSuffix and not alreadyAnnotated(killerLast, killerSuffix) then
        inserts[#inserts + 1] = { position = map[killerLast], suffix = killerSuffix }
    end
    if victimLast and victimSuffix and not alreadyAnnotated(victimLast, victimSuffix) then
        inserts[#inserts + 1] = { position = map[victimLast], suffix = victimSuffix }
    end

    table.sort(inserts, function(left, right)
        return left.position > right.position
    end)

    for _, insertion in ipairs(inserts) do
        text = text:sub(1, insertion.position) .. insertion.suffix
            .. text:sub(insertion.position + 1)
    end

    return text
end

local function annotateKillFeed(original)
    return function(killLocation, killerDisplayName, killerCharacterName, killerAlliance, killerRank,
                    victimDisplayName, victimCharacterName, victimAlliance, victimRank, isKillLocation)
        local message, channel, fromName, rawText, narration, color =
            original(killLocation, killerDisplayName, killerCharacterName, killerAlliance, killerRank,
                     victimDisplayName, victimCharacterName, victimAlliance, victimRank, isKillLocation)

        -- The event is a data source whether or not the line is shown.
        observeCombatant(killerDisplayName, killerCharacterName)
        observeCombatant(victimDisplayName, victimCharacterName)

        if not message or not settings().annotateKillFeed then
            return message, channel, fromName, rawText, narration, color
        end

        local killerShown = primaryName(killerDisplayName, killerCharacterName)
        local victimShown = primaryName(victimDisplayName, victimCharacterName)

        local killerSuffix = killFeedSuffix(killerDisplayName, killerCharacterName, killerShown)
        local victimSuffix = killFeedSuffix(victimDisplayName, victimCharacterName, victimShown)

        message = annotateTargets(message,
            nameCandidates(killerDisplayName, killerCharacterName, killerShown), killerSuffix,
            nameCandidates(victimDisplayName, victimCharacterName, victimShown), victimSuffix)

        if narration then
            narration = annotateTargets(narration,
                nameCandidates(killerDisplayName, killerCharacterName, killerShown), killerSuffix,
                nameCandidates(victimDisplayName, victimCharacterName, victimShown), victimSuffix)
        end

        return message, channel, fromName, rawText, narration, color
    end
end

local function installKillFeedHook()
    if not CHAT_ROUTER or not CHAT_ROUTER.GetRegisteredMessageFormatters then
        return
    end

    local eventCode = EVENT_PVP_KILL_FEED_DEATH
    if not eventCode then
        return
    end

    local formatters = CHAT_ROUTER:GetRegisteredMessageFormatters()
    if type(formatters) ~= "table" then
        return
    end

    local original = formatters[eventCode]
    if type(original) ~= "function" or original == Chat.KillFeedWrapper then
        return
    end

    local wrapper = annotateKillFeed(original)
    Chat.KillFeedOriginal = original
    Chat.KillFeedWrapper = wrapper
    formatters[eventCode] = wrapper
end

-- Addons such as pChat register their own kill feed formatter on
-- EVENT_PLAYER_ACTIVATED, which comes after our first install and silently
-- replaces it. Re-wrap every later registration, so the annotation does not
-- disappear just because another addon loaded last.
local function installFormatterHook()
    local router = _G.CHAT_ROUTER
    if type(router) ~= "table" then
        return
    end

    local original = router.RegisterMessageFormatter
    if type(original) ~= "function" or original == Chat.RegisterFormatterWrapper then
        return
    end

    local function wrapped(self, eventKey, formatter)
        local result = original(self, eventKey, formatter)

        if eventKey == EVENT_PVP_KILL_FEED_DEATH and type(formatter) == "function" then
            local current = self.registeredMessageFormatters
                and self.registeredMessageFormatters[eventKey]
            if type(current) == "function" and current ~= Chat.KillFeedWrapper then
                Chat.KillFeedOriginal = current
                Chat.KillFeedWrapper = annotateKillFeed(current)
                self.registeredMessageFormatters[eventKey] = Chat.KillFeedWrapper
            end
        end

        return result
    end

    Chat.RegisterFormatterWrapper = wrapped
    router.RegisterMessageFormatter = wrapped
end

function Chat:Initialize()
    installLinkHook()
    installKillFeedHook()
    installFormatterHook()

    -- The chat router may finish registering formatters after addons load, and
    -- another addon may replace the table entry later; retry once in game.
    EVENT_MANAGER:RegisterForEvent(IRY.name, EVENT_PLAYER_ACTIVATED, function()
        installFormatterHook()
        installKillFeedHook()
    end)
end

-- Exposed for tests and debug commands.
Chat.AnnotateTargets = annotateTargets
