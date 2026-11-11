--[[
    I remember you! -- stable name in chat.

    Two surfaces, both display only:

      1. player links (the name the game shows for a sender, for mentions and
         for every chat line): the suffix is inserted *inside* the link text,
         the link payload is untouched, so clicking still resolves the real
         @account.

      2. the PvP kill feed: it is built from colorized strings, not links, so
         the registered formatter is wrapped and the names are annotated in
         the finished message. The same event is also a data source.

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

-- Insert `suffix` right after the first plain-text occurrence of `needle`.
local function insertAfter(haystack, needle, suffix)
    if not haystack or not needle or needle == "" or not suffix then
        return haystack
    end

    local first, last = haystack:find(needle, 1, true)
    if not first then
        return haystack
    end

    return haystack:sub(1, last) .. suffix .. haystack:sub(last + 1)
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

local function allianceColor(alliance, isBattleground)
    if isBattleground then
        return GetBattlegroundTeamColor(alliance):GetBright()
    end
    return GetAllianceColor(alliance):GetBright()
end

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

        local isBattleground = IsActiveWorldBattleground()
        local killerShown = ZO_GetPrimaryPlayerName(killerDisplayName, killerCharacterName)
        local victimShown = ZO_GetPrimaryPlayerName(victimDisplayName, victimCharacterName)

        local killerSuffix = Chat:Suffix(killerDisplayName, killerCharacterName, killerShown)
        local victimSuffix = Chat:Suffix(victimDisplayName, victimCharacterName, victimShown)

        if killerSuffix then
            local colored = allianceColor(killerAlliance, isBattleground):Colorize(killerShown)
            message = insertAfter(message, colored, killerSuffix)
        end

        if victimSuffix then
            local colored = allianceColor(victimAlliance, isBattleground):Colorize(victimShown)
            message = insertAfter(message, colored, victimSuffix)
        end

        if narration then
            if killerSuffix then
                narration = insertAfter(narration, killerShown, killerSuffix)
            end
            if victimSuffix then
                narration = insertAfter(narration, victimShown, victimSuffix)
            end
        end

        return message, channel, fromName, rawText, narration, color
    end
end

local function installKillFeedHook()
    if not CHAT_ROUTER or not CHAT_ROUTER.GetRegisteredMessageFormatters then
        return
    end

    local formatters = CHAT_ROUTER:GetRegisteredMessageFormatters()
    if type(formatters) ~= "table" then
        return
    end

    local original = formatters[EVENT_PVP_KILL_FEED_DEATH]
    if type(original) ~= "function" or original == Chat.KillFeedWrapper then
        return
    end

    local wrapper = annotateKillFeed(original)
    Chat.KillFeedOriginal = original
    Chat.KillFeedWrapper = wrapper
    formatters[EVENT_PVP_KILL_FEED_DEATH] = wrapper
end

function Chat:Initialize()
    installLinkHook()
    installKillFeedHook()

    -- The chat router may finish registering formatters after addons load, and
    -- another addon may replace the table entry later; retry once in game.
    EVENT_MANAGER:RegisterForEvent(IRY.name, EVENT_PLAYER_ACTIVATED, function()
        installKillFeedHook()
    end)
end

-- Exposed for the browser and for debug commands.
Chat.InsertAfter = insertAfter
