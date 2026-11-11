--[[
    I remember you! -- remembered names in the friends list and guild roster.

    The game draws these rows itself, so this is display only: after the row has
    been set up, the remembered name is appended to the account label. The
    account name stays where it is; nothing is replaced.

    Nothing is resized. In both lists the Zone label follows the right end of
    DisplayName, so widening the name dragged the location column to the right,
    and shrinking Zone then clipped the location text. The suffix is therefore
    fitted into the width the label already has and shortened when it does not
    fit.

    The rows are recycled, and SetupEntry rewrites the label on every refresh,
    so decorating a row is idempotent: read the fresh text, append once.
]]

local Social = {}
IRY.Social = Social

local SUFFIX_COLOR = "|c8F8F8F"
local SUFFIX_MARK = SUFFIX_COLOR .. " ("
-- Only used while the row has not been laid out yet and reports no width.
local FALLBACK_LABEL_WIDTH = 225
-- Free pixels below which a shortened remembered name is not worth showing:
-- roughly the brackets plus the ellipsis plus two or three letters.
local MIN_SUFFIX_WIDTH = 60

local function settings()
    return IRY.Store:GetSettings() or {}
end

local function keyboardMode()
    return not (IsInGamepadPreferredMode and IsInGamepadPreferredMode())
end

-- Colour codes must not reach the measuring function: the visible width of
-- "|c8F8F8Fabc|r" is the width of "abc".
local function plain(text)
    return (text:gsub("|c%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function measureWidth(label, value)
    if type(label.GetTextWidth) ~= "function" then
        return nil
    end

    local width = label:GetTextWidth(value)
    if not width or width <= 0 then
        return nil
    end
    return width
end

-- The first `count` bytes of `text`, backed off to a UTF-8 character boundary
-- so a Cyrillic name is never cut in the middle of a character.
local function utf8Prefix(text, count)
    if count >= #text then
        return text
    end

    local cut = count
    while cut > 0 do
        local byte = text:byte(cut + 1)
        if byte and byte >= 0x80 and byte <= 0xBF then
            cut = cut - 1
        else
            break
        end
    end

    if cut <= 0 then
        return ""
    end
    return text:sub(1, cut)
end

-- Remembered name for a social row, or nil when there is nothing new to show.
function Social:SuffixFor(data)
    if not settings().annotateSocial or not data then
        return nil
    end

    local account = IRY.Util.NormalizeAccount(data.displayName)
    local character
    if data.characterName and data.characterName ~= "" then
        character = IRY.Util.NormalizeCharacter(data.characterName)
    end

    if not account and not character then
        return nil
    end

    return IRY.Chat:SocialSuffix(account, character, data.displayName)
end

-- Append `suffix` (" (Name)") to the label without touching its width. The
-- whole suffix is used when it fits; otherwise the remembered name itself is
-- shortened with an ellipsis, so the account name keeps its place.
function Social:AppendSuffix(label, baseText, suffix)
    local room = label:GetWidth()
    if not room or room <= 0 then
        room = FALLBACK_LABEL_WIDTH
    end
    room = room - 2

    local baseWidth = measureWidth(label, plain(baseText))
    if not baseWidth then
        -- The label cannot be measured; let the game ellipsize if needed.
        label:SetText(baseText .. SUFFIX_COLOR .. suffix .. "|r")
        return
    end

    local fullWidth = measureWidth(label, plain(baseText .. suffix))
    if fullWidth and fullWidth <= room then
        label:SetText(baseText .. SUFFIX_COLOR .. suffix .. "|r")
        return
    end

    -- suffix is " (Name)"; keep the account name whole and shorten the name.
    local name = suffix:match("^ %((.+)%)$")
    if not name or #name < 2 then
        return
    end

    local best
    for count = #name - 1, 1, -1 do
        local prefix = utf8Prefix(name, count)
        if prefix ~= "" then
            local candidate = baseText .. " (" .. prefix .. "...)"
            local candidateWidth = measureWidth(label, plain(candidate))
            if candidateWidth and candidateWidth <= room then
                if candidateWidth < baseWidth + MIN_SUFFIX_WIDTH then
                    break
                end
                best = prefix
                break
            end
        end
    end

    if not best then
        return
    end

    label:SetText(baseText .. SUFFIX_COLOR .. " (" .. best .. "...)|r")
end

function Social:DecorateRow(control, data)
    if not control or not keyboardMode() then
        return
    end

    local label = control:GetNamedChild("DisplayName")
    if not label then
        return
    end

    local suffix = self:SuffixFor(data)
    if not suffix then
        return
    end

    local text = label:GetText() or ""
    -- SetupEntry rewrites the label on every refresh. The marker only matters
    -- if this hook is somehow installed twice for the same row.
    if text:find(SUFFIX_MARK, 1, true) then
        return
    end

    self:AppendSuffix(label, text, suffix)
end

local function hookManager(manager)
    if not manager or not ZO_PostHook then
        return false
    end

    ZO_PostHook(manager, "SetupEntry", function(_, control, data)
        IRY.Social:DecorateRow(control, data)
    end)
    return true
end

function Social:Install()
    if not self.friendsHooked then
        self.friendsHooked = hookManager(FRIENDS_LIST_MANAGER)
    end
    if not self.guildHooked then
        self.guildHooked = hookManager(GUILD_ROSTER_MANAGER)
    end
end

function Social:Initialize()
    self:Install()

    -- The social managers are part of the base UI, but re-check after login so
    -- an addon that replaces them late is still covered.
    EVENT_MANAGER:RegisterForEvent(IRY.name, EVENT_PLAYER_ACTIVATED, function()
        IRY.Social:Install()
    end)
end
