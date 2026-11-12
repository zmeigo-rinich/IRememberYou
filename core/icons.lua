--[[
    I remember you! -- the single icon rule.

    Every surface asks this file one question: "which texture belongs to this
    player?" -- and gets either a path or nil. The surfaces never decide among
    themselves, which is what keeps one icon per player across the target
    frame, the social lists, the browser and the 3D world.

    Priority: manual assignment > blacklist marker > nothing. A master toggle
    (showIcons) switches every picture off at once.

    The 3D part is delegated to OdySupportIcons: group members are pushed
    through OSI.SetCustomIconForUnit and the reticle target is drawn as one of
    OSI's position icons. Nothing here renders a texture itself, and nothing is
    written to OSI's SavedVariables: the temporary values in OSI.special and in
    OSI's icon cache are snapshotted before a push and restored afterwards.
]]

local Icons = {}
IRY.Icons = Icons

-- OSI's own 2D overlays. When one of them is enabled, OSI draws the icon we
-- pushed into OSI.special; our list row must then stay quiet.
local OSI_2D = {
    friends = "fluse",
    guild   = "gruse",
    chat    = "cwuse",
}

local WHITE = { 1, 1, 1 }

-- Used only when OSI's own values cannot be read.
local DEFAULT_RETICLE_SIZE = 64
local DEFAULT_OFFSET      = 3.0

local cachedPaths

-- Our pushes, keyed by the plain lowercased account:
--   [key] = {
--       raw     = lowercased display name OSI uses as its key,
--       path    = texture we pushed,
--       special = OSI.special[raw] before our push,
--       cache   = OSI cache[raw] before our push,
--   }
local pushed = {}

-- One position icon slot is enough: only the reticle target is drawn this way.
-- holder.icon is read from OSI's callback on every update.
local reticle = nil
-- Last CreatePositionIcon error, kept for /pa debug reticle: a silent pcall
-- failure would otherwise look exactly like "nothing is drawn".
local reticleError = nil

local function settings()
    return (IRY.Store and IRY.Store:GetSettings()) or {}
end

-- OSI loads after us and may be missing entirely. Every access goes through
-- these guards, so a missing or renamed API only disables the 3D surfaces.
local function osi()
    local o = _G.OSI
    if type(o) ~= "table" then
        return nil
    end
    if type(o.SetCustomIconForUnit) ~= "function"
        or type(o.RemoveCustomIconFromUnit) ~= "function"
        or type(o.special) ~= "table"
    then
        return nil
    end
    return o
end

local function option(o, key)
    if type(o) ~= "table" or type(o.GetOption) ~= "function" then
        return nil
    end

    local ok, value = pcall(o.GetOption, key)
    if ok then
        return value
    end
    return nil
end

local function call(o, method, ...)
    local fn = type(o) == "table" and o[method] or nil
    if type(fn) ~= "function" then
        return false
    end
    return pcall(fn, ...)
end

-- OSI keys its icons by the lowercased display name exactly as the game
-- returns it ("@Account" on PC). Our own bookkeeping uses the undecorated
-- form, so the same person is recognised on every surface.
local function accountKey(name)
    local plain = IRY.Util.NormalizeAccount(name)
    if not plain then
        return nil
    end
    return string.lower(plain)
end

local function cacheSnapshot(o, raw)
    local cache = option(o, "cache")
    if type(cache) == "table" then
        return cache[raw]
    end
    return nil
end

-- With "save" enabled OSI immediately caches whatever we pushed. Put the
-- previous entry back so our icons never survive in OSI's SavedVariables.
local function cacheRestore(o, raw, value)
    if option(o, "save") then
        call(o, "UpdateCache", raw, value)
    end
end

local function pushGroupIcon(o, key, raw, path)
    local record = pushed[key]
    local current = o.special[raw]

    -- Already ours and untouched by OSI's own picker or cache restore.
    if record and record.path == path and current and current.texture == path then
        return
    end

    if record then
        -- Our texture is gone from OSI.special: the player was given an icon
        -- through OSI's own picker in the meantime. Remember that newer choice
        -- so clearing ours gives it back instead of a stale snapshot.
        if current and current.texture ~= path then
            record.special = current
            record.cache = cacheSnapshot(o, raw)
        end
    else
        record = {
            raw     = raw,
            special = current,
            cache   = cacheSnapshot(o, raw),
        }
        pushed[key] = record
    end

    record.path = path
    call(o, "SetCustomIconForUnit", raw, path, WHITE)
    cacheRestore(o, raw, record.cache)
end

local function unpushGroupIcon(o, key)
    local record = pushed[key]
    if not record then
        return
    end

    call(o, "RemoveCustomIconFromUnit", record.raw)

    -- The player may already have had an OSI icon of their own. Restore it
    -- from special when it was visible, otherwise from the saved cache.
    local previous = record.special or record.cache
    if previous and previous.texture then
        call(o, "SetCustomIconForUnit", record.raw, previous.texture, previous.color)
    end

    cacheRestore(o, record.raw, record.cache)
    pushed[key] = nil
end

-- Flat, de-duplicated list of every texture in the manifest. Bad paths are
-- dropped with a debug line: the renderer would silently draw nothing.
function Icons:AllPaths()
    if cachedPaths then
        return cachedPaths
    end

    local list = {}
    local seen = {}

    for _, pack in ipairs(IRY.IconPacks or {}) do
        for _, path in ipairs(pack.icons or {}) do
            if not seen[path] then
                seen[path] = true
                if IRY.IsIconPath(path) then
                    list[#list + 1] = path
                else
                    IRY:Debug("icon manifest: ignoring bad path " .. tostring(path))
                end
            end
        end
    end

    cachedPaths = list
    return list
end

-- Called by the picker and by a future pack refresh.
function Icons:RefreshPacks()
    cachedPaths = nil
end

-- The default marker is the shipped rooster icon; an explicit choice in the
-- settings always wins. If the shipped default is not in the manifest (a pack
-- was removed), the first icon of the first pack is used instead, so an ignored
-- player is still marked.
function Icons:BlacklistPath()
    local path = settings().blacklistIcon
    if IRY.IsIconPath(path) then
        return path
    end

    local shipped = IRY.ICON.blacklistDefault
    local paths = self:AllPaths()
    for _, candidate in ipairs(paths) do
        if candidate == shipped then
            return shipped
        end
    end

    return paths[1]
end

-- Returns source, path. `name` is a character name when the surface has one;
-- the blacklist stores character names, not @accounts.
function Icons:Resolve(playerId, name)
    local s = settings()

    if s.showIcons == false then
        return IRY.ICON_SOURCE.DISABLED, nil
    end

    if playerId then
        local path = IRY.Store:GetIconPath(playerId)
        if path then
            return IRY.ICON_SOURCE.MANUAL, path
        end
    end

    if s.blacklistIcons ~= false and name and IRY.Blacklist:IsIgnored(name) then
        local path = self:BlacklistPath()
        if path then
            return IRY.ICON_SOURCE.BLACKLIST, path
        end
    end

    return IRY.ICON_SOURCE.NONE, nil
end

function Icons:Effective(playerId, name)
    local _, path = self:Resolve(playerId, name)
    return path
end

-- A player entity can hold several characters. The command line and the
-- browser have no single character at hand, so any ignored character counts.
function Icons:ResolvePlayer(playerId)
    local source, path = self:Resolve(playerId, nil)
    if source ~= IRY.ICON_SOURCE.NONE then
        return source, path
    end

    local player = playerId and IRY.Store:GetPlayer(IRY.Store:ResolveFinal(playerId))
    if player and settings().blacklistIcons ~= false and IRY.Blacklist:AnyIgnored(player) then
        local blackPath = self:BlacklistPath()
        if blackPath then
            return IRY.ICON_SOURCE.BLACKLIST, blackPath
        end
    end

    return source, path
end

-- The blacklist is a list of character names, so it must never be asked about
-- the @account. The manual icon, on the other hand, is keyed by player entity.
function Icons:ForUnit(unitTag)
    if not unitTag or not DoesUnitExist(unitTag) then
        return nil
    end

    local id, account, character = IRY.Resolver:ForUnit(unitTag)
    if not id and not account and not character then
        return nil
    end

    return self:Effective(id, character or account)
end

-- Manual assignment is the only write path; both the browser and the slash
-- commands go through it.
function Icons:Assign(playerId, path)
    local ok, reason = IRY.Store:SetIcon(playerId, path)
    if ok then
        IRY:RefreshUI()
    end
    return ok, reason
end

function Icons:Clear(playerId)
    local ok, reason = IRY.Store:ClearIcon(playerId)
    if ok then
        IRY:RefreshUI()
    end
    return ok, reason
end

-- Reticle target -------------------------------------------------------------
-- OSI.special only works for group members, so the reticle target is drawn as
-- a position icon whose coordinates are refreshed inside OSI's own callback.

-- The client does not expose a world position for every unit tag on every API
-- level, so both variants are tried. Returns x, y, z and the source that
-- answered (nil when neither did), which /pa debug reticle reports.
local function unitWorldPosition(unitTag)
    local function read(fn)
        if type(fn) ~= "function" then
            return nil
        end
        local ok, _, x, y, z = pcall(fn, unitTag)
        -- 0, 0, 0 is not a place in Tamriel: clients use it for "no position"
        -- on units they do not track, so it must not hide a real answer from
        -- the other function.
        if ok and type(x) == "number" and type(y) == "number" and type(z) == "number"
            and not (x == 0 and y == 0 and z == 0)
        then
            return x, y, z
        end
        return nil
    end

    local x, y, z = read(GetUnitRawWorldPosition)
    if x then
        return x, y, z, "raw"
    end

    x, y, z = read(GetUnitWorldPosition)
    if x then
        return x, y, z, "world"
    end

    return nil
end

local function reticleSize(o)
    if type(o.GetIconSize) == "function" then
        local ok, size = pcall(o.GetIconSize)
        if ok and type(size) == "number" then
            return size
        end
    end
    return DEFAULT_RETICLE_SIZE
end

local function reticleOffset(o)
    local offset = option(o, "offset")
    if type(offset) == "number" then
        return offset
    end
    return DEFAULT_OFFSET
end

function Icons:RemoveReticle(o)
    if reticle and reticle.icon then
        call(o or osi(), "DiscardPositionIcon", reticle.icon)
    end
    reticle = nil
end

function Icons:ApplyReticle(o, enabled)
    if not o then
        return
    end

    if not enabled or not DoesUnitExist("reticleover") then
        self:RemoveReticle(o)
        return
    end

    local path = self:ForUnit("reticleover")
    if not path then
        self:RemoveReticle(o)
        return
    end

    if reticle then
        local icon = reticle.icon
        local data = icon and icon.data
        if not data or icon.use == false then
            -- Discarded behind our back (or a half-built slot): take a new one.
            self:RemoveReticle(o)
        else
            -- OSI reads texture, size, offset and colour from icon.data on every
            -- update; the control changes only through UpdateIconData.
            data.size   = reticleSize(o)
            data.offset = reticleOffset(o)
            data.color  = WHITE
            if reticle.path ~= path or reticle.icon.tex ~= path then
                data.texture = path
                call(o, "UpdateIconData", reticle.icon, path, WHITE)
            end
            reticle.path = path
            return
        end
    end

    if type(o.CreatePositionIcon) ~= "function" then
        return
    end

    local holder = {}
    local ok, icon, err = pcall(o.CreatePositionIcon, 0, 0, 0, path,
        reticleSize(o), WHITE, reticleOffset(o),
        function()
            -- Called by OSI's update loop, so there is no timer of our own.
            if not holder.icon then
                return
            end

            local x, y, z, source = unitWorldPosition("reticleover")
            if x then
                holder.icon.x, holder.icon.y, holder.icon.z = x, y, z
                holder.coords = source
            end
        end)

    if not ok or not icon then
        reticleError = tostring(err)
        IRY:Debug("reticle icon: " .. tostring(err))
        return
    end

    reticleError = nil
    holder.icon = icon
    holder.path = path
    reticle = holder
end

-- Same decision, without the caller having to know whether OSI is loaded.
function Icons:RefreshReticle()
    self:ApplyReticle(osi(), settings().showIcons ~= false)
end

-- Everything the 3D reticle path depends on, for /pa debug reticle.
function Icons:ReticleDebug()
    local lines = {}
    local o = _G.OSI

    lines[#lines + 1] = string.format("OSI: %s | show=%s customuse=%s interval=%s",
        type(o) == "table" and "loaded" or "missing",
        tostring(type(o) == "table" and o.show or nil),
        tostring(option(o, "customuse")),
        tostring(option(o, "interval")))

    local exists = DoesUnitExist("reticleover") and true or false
    local player = exists and IsUnitPlayer("reticleover") or false
    lines[#lines + 1] = string.format("unit: exists=%s player=%s name=%s account=%s",
        tostring(exists), tostring(player),
        tostring(exists and GetUnitName("reticleover") or nil),
        tostring(exists and GetUnitDisplayName("reticleover") or nil))

    lines[#lines + 1] = "icon path: " .. tostring(self:ForUnit("reticleover"))

    local x, y, z, source
    if exists then
        x, y, z, source = unitWorldPosition("reticleover")
    end
    lines[#lines + 1] = string.format("unit position: %s, %s, %s (%s)",
        tostring(x), tostring(y), tostring(z), tostring(source))

    if reticle then
        local icon = reticle.icon
        local data = (icon and icon.data) or {}

        lines[#lines + 1] = string.format(
            "holder: path=%s coords=%s x/y/z=%s,%s,%s use=%s",
            tostring(reticle.path), tostring(reticle.coords),
            tostring(icon and icon.x), tostring(icon and icon.y),
            tostring(icon and icon.z), tostring(icon and icon.use))

        lines[#lines + 1] = string.format(
            "data: texture=%s size=%s offset=%s",
            tostring(data.texture), tostring(data.size), tostring(data.offset))

        local ctrl = icon and icon.ctrl
        if ctrl then
            local w, h = ctrl:GetDimensions()
            lines[#lines + 1] = string.format(
                "ctrl: hidden=%s alpha=%.2f scale=%.2f size=%.0fx%.0f",
                tostring(ctrl:IsHidden()), ctrl:GetAlpha(), ctrl:GetScale(),
                tonumber(w) or 0, tonumber(h) or 0)
        end
    else
        lines[#lines + 1] = "holder: none"
    end

    if reticleError then
        lines[#lines + 1] = "create error: " .. reticleError
    end

    lines[#lines + 1] = string.format("fade: out=%s dist=%s offset=%s alpha=%s",
        tostring(option(o, "fadeout")), tostring(option(o, "fadedist")),
        tostring(option(o, "offset")), tostring(option(o, "alpha")))

    return lines
end

-- Bridge ---------------------------------------------------------------------

function Icons:Apply()
    local o = osi()
    if not o then
        -- OSI is not loaded (or its API changed). Nothing to push, and the
        -- bookkeeping must survive: a later Apply still knows what to restore.
        return
    end

    if settings().showIcons == false then
        self:RemoveAll()
        return
    end

    local present = {}

    for index = 1, GROUP_SIZE_MAX or 24 do
        local unitTag = "group" .. index
        local displayName = GetUnitDisplayName and GetUnitDisplayName(unitTag)

        if displayName and displayName ~= "" then
            local key = accountKey(displayName)
            if key then
                present[key] = true

                local path = self:ForUnit(unitTag)
                if path then
                    pushGroupIcon(o, key, string.lower(displayName), path)
                elseif pushed[key] then
                    unpushGroupIcon(o, key)
                end
            end
        end
    end

    -- Members who left, renamed or lost their icon.
    for key in pairs(pushed) do
        if not present[key] then
            unpushGroupIcon(o, key)
        end
    end

    self:ApplyReticle(o, true)
end

-- OSI can draw our pushed icon in the friends and guild lists itself. When it
-- does, our row must not draw a second one -- but only for that same person:
-- friends outside the group have nothing pushed and still need our icon.
function Icons:OsiHandles2D(surface, name)
    if settings().showIcons == false then
        return false
    end

    local setting = OSI_2D[surface]
    if not setting then
        return false
    end

    local o = osi()
    if not o or option(o, setting) ~= true then
        return false
    end

    local key = accountKey(name)
    return key ~= nil and pushed[key] ~= nil
end

function Icons:RemoveAll()
    local o = osi()
    if o then
        for key in pairs(pushed) do
            unpushGroupIcon(o, key)
        end
    end

    pushed = {}
    self:RemoveReticle(o)
end

-- "ready" | "custom-off" | "missing", for the settings panel.
function Icons:OsiStatus()
    local o = osi()
    if not o then
        return "missing"
    end
    if option(o, "customuse") == false then
        return "custom-off"
    end
    return "ready"
end

local function scheduleApply()
    zo_callLater(function()
        if IRY.Icons then
            IRY.Icons:Apply()
        end
    end, 0)
end

local function refreshReticle()
    IRY.Icons:RefreshReticle()

    -- The unit state behind the event can lag by a frame: the target is not
    -- always resolvable yet when EVENT_RETICLE_TARGET_CHANGED fires. Read it
    -- again after the client has finished updating the target.
    zo_callLater(function()
        if IRY.Icons then
            IRY.Icons:RefreshReticle()
        end
    end, 0)
end

-- Not every client exposes every event; a nil constant would abort the whole
-- Initialize, so missing ones are skipped instead.
local function register(namespace, eventName, handler)
    if not eventName then
        return
    end

    EVENT_MANAGER:RegisterForEvent(namespace, eventName, handler)
end

function Icons:Initialize()
    local namespace = IRY.name .. "Icons"

    -- Normally OSI loads after us and the event below starts the bridge. If it
    -- was already loaded (a forced load order), start right away.
    if osi() then
        scheduleApply()
    end

    -- OSI loads after us alphabetically. Its own activation handler must run
    -- before our first push, hence the deferred call.
    register(namespace, EVENT_ADD_ON_LOADED, function(_, addOnName)
        if addOnName ~= "OdySupportIcons" then
            return
        end
        EVENT_MANAGER:UnregisterForEvent(namespace, EVENT_ADD_ON_LOADED)
        scheduleApply()
    end)

    -- After login and reloads OSI restores its cached icons; run after that.
    register(namespace, EVENT_PLAYER_ACTIVATED, scheduleApply)

    register(namespace, EVENT_GROUP_MEMBER_JOINED, function()
        IRY.Icons:Apply()
    end)
    register(namespace, EVENT_GROUP_MEMBER_LEFT, function()
        IRY.Icons:Apply()
    end)
    register(namespace, EVENT_GROUP_MEMBER_CONNECTED, function()
        IRY.Icons:Apply()
    end)
    register(namespace, EVENT_GROUP_MEMBER_DISCONNECTED, function()
        IRY.Icons:Apply()
    end)
    register(namespace, EVENT_GROUP_MEMBER_ACCOUNT_NAME_UPDATED, function()
        IRY.Icons:Apply()
    end)
    register(namespace, EVENT_UNIT_CHARACTER_NAME_CHANGED, function(_, unitTag)
        if unitTag == "reticleover" then
            refreshReticle()
        elseif unitTag and unitTag:match("^group%d+$") then
            IRY.Icons:Apply()
        end
    end)

    register(namespace, EVENT_RETICLE_TARGET_CHANGED, refreshReticle)
    register(namespace, EVENT_RETICLE_TARGET_PLAYER_CHANGED, refreshReticle)

    -- OSI re-reads icon.data on its own tick, but a target that was already
    -- under the reticle when we loaded, or a size/offset change in OSI's own
    -- options, would otherwise wait for the next target change. One cheap
    -- check per second also retries a position icon that failed to create.
    EVENT_MANAGER:RegisterForUpdate(namespace .. "Reticle", 1000, function()
        IRY.Icons:RefreshReticle()
    end)

    -- The ignore list is the blacklist; a change can add or remove a marker.
    register(namespace, EVENT_IGNORE_ADDED, function()
        IRY:RefreshUI()
    end)
    register(namespace, EVENT_IGNORE_REMOVED, function()
        IRY:RefreshUI()
    end)
end
