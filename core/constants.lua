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
IRY.version   = "0.3.0"
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
