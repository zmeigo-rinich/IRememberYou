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
-- A leading inline texture is our icon marker. Captures width, height, path.
local ICON_MARK = "^|t(%d+):(%d+):([^|]+)|t ?"
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

-- Colour codes and inline textures must not reach the measuring function: the
-- visible width of "|c8F8F8Fabc|r" is the width of "abc".
local function plain(text)
    return (text:gsub("|c%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|t%d+:%d+:[^|]+|t", ""))
end

-- Split a label text into the icon marker we may have added and the rest.
local function splitIcon(text)
    local width, height, path = text:match(ICON_MARK)
    if not path then
        return nil, text
    end

    return { width = tonumber(width), height = tonumber(height), path = path },
        (text:gsub(ICON_MARK, "", 1))
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
    -- The icon is rendered inside the label but removed from measurements, so
    -- reserve its width explicitly.
    local iconWidth = tonumber(baseText:match("^|t(%d+):")) or 0
    room = room - 2 - iconWidth

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

function Social:IconMark(path)
    local size = tonumber(settings().iconSize2d) or IRY.ICON.default
    if size < IRY.ICON.min then
        size = IRY.ICON.min
    elseif size > IRY.ICON.socialMax then
        size = IRY.ICON.socialMax
    end

    return string.format("|t%d:%d:%s|t ", size, size, path)
end

-- Friends and guild rows carry @account + character; ignore rows carry only a
-- character name. Manual icons are looked up by whichever keys the row has.
function Social:IconFor(data, surface)
    if not data then
        return nil
    end

    if surface == "ignore" then
        local character = IRY.Util.NormalizeCharacter(data.displayName)
        if not character then
            return nil
        end

        local id = IRY.Store:FindByCharacter(character)
        return IRY.Icons:Effective(id and IRY.Store:ResolveFinal(id) or nil, character)
    end

    local account = IRY.Util.NormalizeAccount(data.displayName)
    local character
    if data.characterName and data.characterName ~= "" then
        character = IRY.Util.NormalizeCharacter(data.characterName)
    end

    if not account and not character then
        return nil
    end

    local id = account and IRY.Store:FindByAccount(account)
    if not id and character then
        id = IRY.Store:FindByCharacter(character)
    end

    return IRY.Icons:Effective(id and IRY.Store:ResolveFinal(id) or nil, character or account)
end

function Social:DecorateRow(control, data, surface)
    if not control or not keyboardMode() then
        return
    end

    local label = control:GetNamedChild("DisplayName")
    if not label then
        return
    end

    local raw = label:GetText() or ""
    local existing, rest = splitIcon(raw)
    local path = self:IconFor(data, surface)
    if path and IRY.Icons.OsiHandles2D and IRY.Icons:OsiHandles2D(surface, data and data.displayName) then
        -- OSI's own overlay already draws this player's icon in the same row.
        -- The remembered-name suffix is still ours to append.
        path = nil
    end

    if rest:find(SUFFIX_MARK, 1, true) then
        -- SetupEntry or a second hook already decorated the row. Refresh the
        -- icon in place and never append the suffix twice.
        if path then
            label:SetText(self:IconMark(path) .. rest)
        elseif existing then
            label:SetText(rest)
        end
        return
    end

    local base = rest
    if path then
        base = self:IconMark(path) .. rest
    elseif existing then
        -- The icon disappeared (master toggle, ignore list change, a group
        -- member leaving); do not leave a stale picture in the row.
        label:SetText(rest)
    end

    local suffix = self:SuffixFor(data)
    if not suffix then
        if path then
            label:SetText(base)
        end
        return
    end

    self:AppendSuffix(label, base, suffix)
end

local function hookManager(manager, surface)
    if not manager or not ZO_PostHook then
        return false
    end

    ZO_PostHook(manager, "SetupEntry", function(_, control, data)
        IRY.Social:DecorateRow(control, data, surface)
    end)
    return true
end

function Social:Install()
    if not self.friendsHooked then
        self.friendsHooked = hookManager(FRIENDS_LIST_MANAGER, "friends")
    end
    if not self.guildHooked then
        self.guildHooked = hookManager(GUILD_ROSTER_MANAGER, "guild")
    end
    if not self.ignoreHooked then
        self.ignoreHooked = hookManager(IGNORE_LIST_MANAGER, "ignore")
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
