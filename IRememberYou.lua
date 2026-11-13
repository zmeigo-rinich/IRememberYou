--[[
    I remember you! -- bootstrap.

    Registered last in the manifest: every module is already defined by the
    time EVENT_ADD_ON_LOADED fires.
]]

local SUPPORTED_API = {
    [101050] = true,
    [101051] = true,
}

local function checkApiVersion()
    local api = tonumber(GetAPIVersion())
    if not api then
        return
    end

    if not SUPPORTED_API[api] then
        IRY:Print(string.format(IRY.L.API_MISMATCH, tostring(api)))
    end
end

local function onAddOnLoaded(_, addOnName)
    if addOnName ~= IRY.name then
        return
    end

    EVENT_MANAGER:UnregisterForEvent(IRY.name, EVENT_ADD_ON_LOADED)

    IRY.sv = ZO_SavedVars:NewAccountWide(IRY.svName, IRY.svVersion, nil, IRY.BuildDefaults())
    IRY.Store:Initialize(IRY.sv)
    IRY.Store:PrunePending()
    IRY.Blacklist:Initialize()
    IRY.Icons:Initialize()

    IRY:RegisterCommands()
    IRY.Observer:Initialize()
    IRY.Rename:Initialize()
    IRY.Poller:Initialize()
    IRY.TargetFrame:Initialize()
    IRY.Chat:Initialize()
    IRY.ReticleMarker:Initialize()
    IRY.WorldMap:Initialize()
    IRY.Social:Initialize()
    IRY.IconPicker:Initialize()
    IRY.Browser:Initialize()
    IRY.Settings:Initialize()

    checkApiVersion()
    IRY:Print(string.format(IRY.L.LOADED, IRY.title, IRY.version))
    IRY:Debug(string.format("API %s, entities %d, pending %d",
        tostring(GetAPIVersion()), IRY.Store:Count(), #IRY.Store:GetPendingList()))
end

EVENT_MANAGER:RegisterForEvent(IRY.name, EVENT_ADD_ON_LOADED, onAddOnLoaded)
