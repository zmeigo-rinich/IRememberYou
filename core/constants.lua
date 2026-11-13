--[[
    I remember you! -- constants and shared namespace.

    Every other file attaches to the global IRY table. Kept deliberately small:
    no game API calls here, so this file is safe to load first.
]]

local ADDON_NAME  = "IRememberYou"
local ADDON_TITLE = "I remember you!"
local SV_NAME     = "IRememberYouSV"
local SV_VERSION  = 1

IRY = IRY or {}

IRY.name      = ADDON_NAME
IRY.title     = ADDON_TITLE
IRY.version   = "0.5.0"
IRY.author    = "I remember you! contributors"
IRY.svName    = SV_NAME
IRY.svVersion = SV_VERSION

-- Where an alias or character was observed.
IRY.SOURCE = {
    TARGET   = "target",
    GROUP    = "group",
    FRIEND   = "friend",
    GUILD    = "guild",
    KILLFEED = "killfeed",
    MANUAL   = "manual",
}

-- How sure we are that an alias belongs to a player entity.
IRY.CONFIDENCE = {
    CONFIRMED = "confirmed",
    PROBABLE  = "probable",
    MANUAL    = "manual",
}

-- Higher value wins when two entities are merged and share an alias.
IRY.SOURCE_PRIORITY = {
    [IRY.SOURCE.TARGET]   = 1,
    [IRY.SOURCE.KILLFEED] = 1,
    [IRY.SOURCE.GUILD]    = 2,
    [IRY.SOURCE.GROUP]    = 3,
    [IRY.SOURCE.FRIEND]   = 3,
    [IRY.SOURCE.MANUAL]   = 4,
}

IRY.MAX_DISPLAY_NAME = 32
IRY.MSG_PREFIX = "|c7FBF7F[" .. ADDON_TITLE .. "]|r "

-- Player icons ---------------------------------------------------------------
-- One curated library, shipped inside the addon. The game cannot enumerate
-- files, so every available texture is listed by hand in core/iconpacks.lua.
IRY.ICON_FOLDER = "IRememberYou/icons/"
-- ESO's own art, used by the lore pack: those DDS files ship with the game, so
-- they cost nothing in the download and never go missing with an addon update.
IRY.ESOUI_FOLDER = "esoui/art/"

IRY.ICON = {
    min       = 16,
    max       = 40,
    default   = 28,
    socialMax = 28,
    -- The screen-space marker has its own size range: it is a single picture
    -- over the world, not a row icon, so it can be larger without moving any
    -- layout.
    markerMin = 16,
    markerMax = 128,
    markerDefault = 28,
    -- Placeholder while the reticle marker is unlocked and there is no target
    -- to take an icon from. Deliberately different from the blacklist icon, so
    -- it reads as "move me", not as "this player is ignored".
    markerPlaceholder = "IRememberYou/icons/base/green_arrow.dds",
    -- Marker for ignored players until the user picks another one. It must stay
    -- in the manifest: Icons:BlacklistPath() falls back to the first icon of the
    -- first pack when this one is missing.
    blacklistDefault = "IRememberYou/icons/base/rooster.dds",
}

-- Where an icon came from. Manual beats blacklist, blacklist beats nothing.
IRY.ICON_SOURCE = {
    DISABLED  = "disabled",
    MANUAL    = "manual",
    BLACKLIST = "blacklist",
    NONE      = "none",
}

-- ESO silently renders nothing for a missing texture, so the only cheap guard
-- is refusing obviously wrong paths. Two shapes are accepted:
--   IRememberYou/icons/<pack>/<name>.dds   -- files shipped in this addon
--   esoui/art/<anything>/<name>.dds        -- the game's own art (lore pack)
-- Both must be lowercase, contain no spaces or "..", and end in .dds.
function IRY.IsIconPath(path)
    if type(path) ~= "string" or path == "" then
        return false
    end

    if path:find("%s") or path:find("%.%.") then
        return false
    end

    local rest
    if path:sub(1, #IRY.ICON_FOLDER) == IRY.ICON_FOLDER then
        rest = path:sub(#IRY.ICON_FOLDER + 1)
        if rest ~= rest:lower() then
            return false
        end
        return rest:match("^[%w_%-]+/[%w_%-]+%.dds$") ~= nil
    end

    if path:sub(1, #IRY.ESOUI_FOLDER) == IRY.ESOUI_FOLDER then
        rest = path:sub(#IRY.ESOUI_FOLDER + 1)
        if rest ~= rest:lower() then
            return false
        end
        if rest:find("^/") or rest:find("/$") or rest:find("//") then
            return false
        end
        return rest:find("/") ~= nil and rest:match("^[%w_%-/]+%.dds$") ~= nil
    end

    return false
end

-- Read-only defaults. Never hand the same table to ZO_SavedVars twice,
-- always build a fresh copy with IRY.BuildDefaults().
IRY.SettingsDefaults = {
    -- target frame (variant 2: reticle frame only)
    replaceTargetName    = true,
    replaceTargetCaption = true,
    hideTargetCaption    = false,

    -- chat
    annotateChat         = true,
    annotateKillFeed     = true,
    annotateSocial       = true,
    annotateSelf         = false,

    -- data collection
    captureTarget        = true,
    captureGroup         = true,
    captureFriends       = true,
    captureGuild         = true,
    captureKillFeed      = true,
    pollTarget           = true,
    pollIntervalMs       = 1000,
    ignoreSelf           = true,

    -- rename notifications
    notifyLevel          = "confirmed", -- off | confirmed | all
    autoAcceptProbable   = false,
    autoMergeOnConflict  = true,
    pendingTtlDays       = 30,

    -- player icons
    showIcons            = true,
    iconSize2d           = IRY.ICON.default,
    blacklistIcons       = true,
    -- Player icons on group pins: the world map and minimaps that reuse the
    -- standard pin manager (Votan's Minimap). On by default: the feature is
    -- invisible until a map is opened, and showIcons still switches it off.
    mapIcons             = true,
    -- An optional screen-space picture above the crosshair. Off by default so
    -- the screen does not change for anyone who never asked for it. X/Y are
    -- offsets from the screen centre, in UI pixels; the user drags the marker
    -- and the result is stored here. Locked, it cannot be grabbed by the mouse.
    reticleMarker        = false,
    reticleMarkerX       = 0,
    reticleMarkerY       = -60,
    reticleMarkerSize    = IRY.ICON.markerDefault,
    reticleMarkerLocked  = true,
    -- Extra filters for the marker. Off by default: the toggle alone decides.
    markerSkipDead       = false,
    markerHostileOnly    = false,
    markerPvPOnly        = false,
    -- blacklistIcon stays nil on purpose: nil means "use the shipped marker"
    -- (IRY.ICON.blacklistDefault), so the default follows the addon instead of
    -- being frozen into every SavedVariables file.

    -- maintenance
    purgeAfterDays       = 0,
    debug                = false,
}

-- The browser window geometry is stored lazily as settings.browserLeft,
-- settings.browserTop, settings.browserWidth and settings.browserHeight: nil
-- means "use the default", so none of them is part of the defaults.

function IRY.BuildDefaults()
    local settings = {}
    for key, value in pairs(IRY.SettingsDefaults) do
        settings[key] = value
    end

    return {
        schema   = SV_VERSION,
        nextId   = 1,
        nextPendingId = 1,
        players  = {},
        pending  = {},
        stats    = { created = 0, linked = 0, merged = 0 },
        settings = settings,
    }
end
