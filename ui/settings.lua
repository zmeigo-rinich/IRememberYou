--[[
    I remember you! -- LibAddonMenu-2.0 settings panel.

    LAM is declared as OptionalDependsOn, so the addon loads and runs without
    it; in that case the panel is simply never registered and every setting can
    still be changed through SavedVariables or the slash commands.
]]

local Settings = {}
IRY.Settings = Settings

local LAM = LibAddonMenu2

local PANEL_ID = "IRememberYouOptions"

local function current()
    return IRY.Store and IRY.Store:GetSettings()
end

local function getter(key)
    return function()
        local settings = current()
        return settings and settings[key]
    end
end

local function setter(key, after)
    return function(value)
        local settings = current()
        if not settings then
            return
        end

        settings[key] = value

        if after then
            after(value)
        end
    end
end

local function refresh()
    IRY:RefreshUI()
end

-- The marker controls (size, filters) only make sense while the marker and the
-- icon master switch are on. The move-mode checkbox stays enabled on purpose,
-- because checking it switches the marker on by itself.
local function markerDisabled()
    local settings = current()
    return not settings
        or settings.showIcons == false
        or settings.reticleMarker ~= true
end

local function applyPoller()
    if IRY.Poller then
        IRY.Poller:Apply()
    end
end

local function checkbox(name, tooltip, key, after, disabled)
    return {
        type    = "checkbox",
        name    = name,
        tooltip = tooltip,
        getFunc = getter(key),
        setFunc = setter(key, after),
        default = IRY.SettingsDefaults[key],
        disabled = disabled,
    }
end

local function buildOptions()
    return {
        {
            type = "description",
            text = IRY.L.OPT_DESC,
        },
        {
            type    = "button",
            name    = IRY.L.OPT_OPEN_LIST,
            tooltip = IRY.L.OPT_OPEN_LIST_TIP,
            func    = function()
                IRY.Browser:Toggle()
            end,
            width   = "full",
        },

        -- Target frame --------------------------------------------------------
        {
            type = "header",
            name = IRY.L.OPT_SEC_TARGET,
        },
        checkbox(IRY.L.OPT_TARGET_NAME, IRY.L.OPT_TARGET_NAME_TIP, "replaceTargetName", refresh),
        checkbox(IRY.L.OPT_TARGET_CAPTION, IRY.L.OPT_TARGET_CAPTION_TIP, "replaceTargetCaption", refresh),
        checkbox(IRY.L.OPT_HIDE_CAPTION, IRY.L.OPT_HIDE_CAPTION_TIP, "hideTargetCaption", refresh),

        -- Chat ----------------------------------------------------------------
        {
            type = "header",
            name = IRY.L.OPT_SEC_CHAT,
        },
        checkbox(IRY.L.OPT_ANNOTATE_CHAT, IRY.L.OPT_ANNOTATE_CHAT_TIP, "annotateChat"),
        checkbox(IRY.L.OPT_ANNOTATE_KILLFEED, IRY.L.OPT_ANNOTATE_KILLFEED_TIP, "annotateKillFeed"),
        checkbox(IRY.L.OPT_ANNOTATE_SOCIAL, IRY.L.OPT_ANNOTATE_SOCIAL_TIP, "annotateSocial"),

        -- Data collection -----------------------------------------------------
        {
            type = "header",
            name = IRY.L.OPT_SEC_DATA,
        },
        checkbox(IRY.L.OPT_CAPTURE_TARGET, IRY.L.OPT_CAPTURE_TARGET_TIP, "captureTarget", applyPoller),
        checkbox(IRY.L.OPT_CAPTURE_GROUP, IRY.L.OPT_CAPTURE_GROUP_TIP, "captureGroup"),
        checkbox(IRY.L.OPT_CAPTURE_FRIENDS, IRY.L.OPT_CAPTURE_FRIENDS_TIP, "captureFriends"),
        checkbox(IRY.L.OPT_CAPTURE_GUILD, IRY.L.OPT_CAPTURE_GUILD_TIP, "captureGuild"),
        checkbox(IRY.L.OPT_CAPTURE_KILLFEED, IRY.L.OPT_CAPTURE_KILLFEED_TIP, "captureKillFeed"),
        checkbox(IRY.L.OPT_IGNORE_SELF, IRY.L.OPT_IGNORE_SELF_TIP, "ignoreSelf"),
        checkbox(IRY.L.OPT_POLL_TARGET, IRY.L.OPT_POLL_TARGET_TIP, "pollTarget", applyPoller),
        {
            type     = "slider",
            name     = IRY.L.OPT_POLL_INTERVAL,
            tooltip  = IRY.L.OPT_POLL_INTERVAL_TIP,
            min      = 250,
            max      = 5000,
            step     = 250,
            decimals = 0,
            getFunc  = getter("pollIntervalMs"),
            setFunc  = setter("pollIntervalMs", applyPoller),
            default  = IRY.SettingsDefaults.pollIntervalMs,
        },

        -- Linking -------------------------------------------------------------
        {
            type = "header",
            name = IRY.L.OPT_SEC_LINKS,
        },
        {
            type     = "dropdown",
            name     = IRY.L.OPT_NOTIFY_LEVEL,
            tooltip  = IRY.L.OPT_NOTIFY_LEVEL_TIP,
            choices  = { IRY.L.NOTIFY_OFF, IRY.L.NOTIFY_CONFIRMED, IRY.L.NOTIFY_ALL },
            choicesValues = { "off", "confirmed", "all" },
            getFunc  = getter("notifyLevel"),
            setFunc  = setter("notifyLevel"),
            default  = IRY.SettingsDefaults.notifyLevel,
        },
        checkbox(IRY.L.OPT_AUTO_ACCEPT, IRY.L.OPT_AUTO_ACCEPT_TIP, "autoAcceptProbable"),
        checkbox(IRY.L.OPT_AUTO_MERGE, IRY.L.OPT_AUTO_MERGE_TIP, "autoMergeOnConflict"),

        -- Player icons --------------------------------------------------------
        {
            type = "header",
            name = IRY.L.OPT_SEC_ICONS,
        },
        checkbox(IRY.L.OPT_SHOW_ICONS, IRY.L.OPT_SHOW_ICONS_TIP, "showIcons", refresh),
        {
            type     = "slider",
            name     = IRY.L.OPT_ICON_SIZE,
            tooltip  = IRY.L.OPT_ICON_SIZE_TIP,
            min      = IRY.ICON.min,
            max      = IRY.ICON.max,
            step     = 2,
            decimals = 0,
            getFunc  = getter("iconSize2d"),
            setFunc  = setter("iconSize2d", refresh),
            default  = IRY.SettingsDefaults.iconSize2d,
            disabled = function()
                local settings = current()
                return settings and settings.showIcons == false
            end,
        },
        checkbox(IRY.L.OPT_RETICLE_MARKER, IRY.L.OPT_RETICLE_MARKER_TIP,
            "reticleMarker", refresh, function()
                local settings = current()
                return settings and settings.showIcons == false
            end),
        {
            type     = "slider",
            name     = IRY.L.OPT_RETICLE_MARKER_SIZE,
            tooltip  = IRY.L.OPT_RETICLE_MARKER_SIZE_TIP,
            min      = IRY.ICON.markerMin,
            max      = IRY.ICON.markerMax,
            step     = 2,
            decimals = 0,
            getFunc  = getter("reticleMarkerSize"),
            setFunc  = setter("reticleMarkerSize", refresh),
            default  = IRY.SettingsDefaults.reticleMarkerSize,
            disabled = markerDisabled,
        },
        {
            -- A checked box is the "pressed" state of move mode. It reads
            -- better than a button that looks identical in both states.
            type    = "checkbox",
            name    = IRY.L.OPT_RETICLE_MARKER_MOVE,
            tooltip = IRY.L.OPT_RETICLE_MARKER_MOVE_TIP,
            getFunc = function()
                local settings = current()
                return settings ~= nil and settings.reticleMarkerLocked == false
            end,
            setFunc = function(value)
                local settings = current()
                if not settings then
                    return
                end

                local unlocked = value == true
                if unlocked == (settings.reticleMarkerLocked == false) then
                    return
                end

                if unlocked then
                    -- Unlocking without a visible marker would be confusing, so
                    -- the marker is switched on together with move mode.
                    settings.reticleMarker = true
                    settings.reticleMarkerLocked = false
                    IRY:Print(IRY.L.MARKER_UNLOCKED)
                else
                    if IRY.ReticleMarker then
                        IRY.ReticleMarker:FinishDrag()
                    end
                    settings.reticleMarkerLocked = true
                    IRY:Print(IRY.L.MARKER_LOCKED)
                end

                IRY:RefreshUI()
            end,
            default = false,
            disabled = function()
                local settings = current()
                return settings and settings.showIcons == false
            end,
        },
        checkbox(IRY.L.OPT_MARKER_SKIP_DEAD, IRY.L.OPT_MARKER_SKIP_DEAD_TIP,
            "markerSkipDead", refresh, markerDisabled),
        checkbox(IRY.L.OPT_MARKER_HOSTILE_ONLY, IRY.L.OPT_MARKER_HOSTILE_ONLY_TIP,
            "markerHostileOnly", refresh, markerDisabled),
        checkbox(IRY.L.OPT_MARKER_PVP_ONLY, IRY.L.OPT_MARKER_PVP_ONLY_TIP,
            "markerPvPOnly", refresh, markerDisabled),
        checkbox(IRY.L.OPT_BLACKLIST_ICONS, IRY.L.OPT_BLACKLIST_ICONS_TIP, "blacklistIcons", refresh),
        {
            type    = "button",
            name    = IRY.L.OPT_BLACKLIST_ICON,
            tooltip = IRY.L.OPT_BLACKLIST_ICON_TIP,
            func    = function()
                IRY.IconPicker:OpenBlacklist()
            end,
            width   = "full",
        },
        {
            type = "description",
            text = IRY.L.OPT_ICONS_3D,
        },

        -- Maintenance ---------------------------------------------------------
        {
            type = "header",
            name = IRY.L.OPT_SEC_MAINT,
        },
        {
            type     = "slider",
            name     = IRY.L.OPT_PURGE_DAYS,
            tooltip  = IRY.L.OPT_PURGE_DAYS_TIP,
            min      = 0,
            max      = 3650,
            step     = 30,
            decimals = 0,
            getFunc  = getter("purgeAfterDays"),
            setFunc  = setter("purgeAfterDays"),
            default  = IRY.SettingsDefaults.purgeAfterDays,
        },
        {
            type    = "button",
            name    = IRY.L.OPT_PURGE_NOW,
            tooltip = IRY.L.OPT_PURGE_NOW_TIP,
            func    = function()
                IRY:PurgeOldPlayers()
            end,
            width   = "full",
        },
        checkbox(IRY.L.OPT_DEBUG, IRY.L.OPT_DEBUG_TIP, "debug"),
    }
end

function Settings:Initialize()
    if not LAM then
        return false
    end

    local panelData = {
        type                = "panel",
        name                = IRY.title,
        displayName         = "|c7FBF7F" .. IRY.title .. "|r",
        author              = IRY.author,
        version             = IRY.version,
        slashCommand        = "/iryoptions",
        registerForRefresh  = true,
        registerForDefaults = true,
    }

    LAM:RegisterAddonPanel(PANEL_ID, panelData)
    LAM:RegisterOptionControls(PANEL_ID, buildOptions())

    return true
end
