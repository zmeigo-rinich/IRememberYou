--[[
    I remember you! -- reticle target poll.

    The client fires EVENT_RETICLE_TARGET_CHANGED when the target changes, but
    not when the *same* target silently changes its @account. That is exactly
    the case we care about, so we re-read the target on a timer and only do
    something when the account/character pair actually changed.
]]

local Poller = {}
IRY.Poller = Poller

local UPDATE_KEY = IRY.name .. "TargetPoll"

local lastAccount, lastCharacter

local function reset()
    lastAccount, lastCharacter = nil, nil
end

function Poller:Apply()
    EVENT_MANAGER:UnregisterForUpdate(UPDATE_KEY)

    local settings = IRY.Store:GetSettings() or {}
    if not settings.pollTarget or not settings.captureTarget then
        return
    end

    local interval = tonumber(settings.pollIntervalMs) or 1000
    if interval < 250 then
        interval = 250
    end

    EVENT_MANAGER:RegisterForUpdate(UPDATE_KEY, interval, function()
        IRY.Poller:Tick()
    end)
end

function Poller:Tick()
    if not DoesUnitExist("reticleover") or not IsUnitPlayer("reticleover") then
        reset()
        return
    end

    local account   = IRY.Util.NormalizeAccount(GetUnitDisplayName("reticleover"))
    local character = IRY.Util.NormalizeCharacter(GetUnitName("reticleover"))

    if account == lastAccount and character == lastCharacter then
        return
    end

    lastAccount, lastCharacter = account, character
    IRY.Observer:KeepUnit("reticleover", IRY.SOURCE.TARGET, nil)
end

function Poller:Initialize()
    EVENT_MANAGER:RegisterForEvent(IRY.name, EVENT_PLAYER_ACTIVATED, reset)
    EVENT_MANAGER:RegisterForEvent(IRY.name, EVENT_RETICLE_TARGET_CHANGED, reset)
    self:Apply()
end
