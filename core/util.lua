--[[
    I remember you! -- small helpers shared by every module.
]]

local Util = {}
IRY.Util = Util

local function trim(value)
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end
Util.Trim = trim

-- Strip grammar markup that can appear in names coming from events.
function Util.StripMarkup(value)
    if type(value) ~= "string" or value == "" then
        return ""
    end
    return zo_strformat("<<1>>", value)
end

-- Canonical key for an @account.
-- We store accounts undecorated: "@Name" on PC, "Name" and "@Name" both
-- normalize to "Name". That keeps one key per person regardless of which
-- API produced the string.
function Util.NormalizeAccount(value)
    local name = Util.StripMarkup(value)
    if name == "" then
        return nil
    end

    if IsDecoratedDisplayName and IsDecoratedDisplayName(name) then
        name = UndecorateDisplayName and UndecorateDisplayName(name) or name
    end

    name = trim(name)
    if name == "" then
        return nil
    end
    return name
end

-- Canonical key for a character name.
function Util.NormalizeCharacter(value)
    local name = trim(Util.StripMarkup(value))
    if name == "" then
        return nil
    end
    return name
end

-- Account key back to the string a player expects to see.
function Util.FormatAccount(key)
    if type(key) ~= "string" or key == "" then
        return ""
    end

    if ZO_IsConsoleOrGameCoreUI and ZO_IsConsoleOrGameCoreUI() then
        return key
    end

    if IsDecoratedDisplayName and IsDecoratedDisplayName(key) then
        return key
    end

    return "@" .. key
end

-- Truncate on a UTF-8 boundary so Cyrillic names are not cut mid-codepoint.
local function utf8SafeSub(text, maxBytes)
    if #text <= maxBytes then
        return text
    end

    local cut = maxBytes
    while cut > 0 do
        local byte = text:byte(cut + 1)
        if byte and byte >= 0x80 and byte < 0xC0 then
            cut = cut - 1
        else
            break
        end
    end

    return text:sub(1, cut)
end

-- User input for a custom display name. Removes markup the chat and the
-- target frame would otherwise interpret.
function Util.SanitizeDisplayName(value)
    if type(value) ~= "string" then
        return nil
    end

    local text = value
    text = text:gsub("[|<>\r\n\t]", " ")
    text = text:gsub("%^", "")
    text = text:gsub("%s+", " ")
    text = trim(text)

    if text == "" then
        return nil
    end

    return utf8SafeSub(text, IRY.MAX_DISPLAY_NAME)
end

function Util.SameName(a, b)
    if not a or not b then
        return false
    end
    if a == b then
        return true
    end
    return a:lower() == b:lower()
end

function Util.FormatTime(timestamp)
    if not timestamp or timestamp <= 0 then
        return "-"
    end
    return os.date("%Y-%m-%d %H:%M", timestamp)
end

-- Localized alliance name for an alliance id (1/2/3), or "" when unknown.
-- The client returns the raw name; SI_ALLIANCE_NAME applies the correct
-- grammatical form for the current language.
function Util.FormatAlliance(alliance)
    alliance = tonumber(alliance)
    if not alliance or alliance <= 0 or not GetAllianceName then
        return ""
    end

    local name = GetAllianceName(alliance)
    if type(name) ~= "string" or name == "" then
        return ""
    end

    if ZO_CachedStrFormat and SI_ALLIANCE_NAME then
        return ZO_CachedStrFormat(SI_ALLIANCE_NAME, name)
    end

    return name
end

function Util.Now()
    return os.time()
end
