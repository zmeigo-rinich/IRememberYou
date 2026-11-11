--[[
    I remember you! -- read only lookup layer.

    Render paths (target frame, chat) may call this. Nothing here writes to
    SavedVariables: observation happens in track/*, never while drawing.
]]

local Resolver = {}
IRY.Resolver = Resolver

-- Returns: playerId or nil, account key, character key
function Resolver:ForUnit(unitTag)
    if not unitTag or not DoesUnitExist(unitTag) or not IsUnitPlayer(unitTag) then
        return nil
    end

    local account   = IRY.Util.NormalizeAccount(GetUnitDisplayName(unitTag))
    local character = IRY.Util.NormalizeCharacter(GetUnitName(unitTag))

    local id
    if account then
        id = IRY.Store:FindByAccount(account)
    end
    if not id and character then
        id = IRY.Store:FindByCharacter(character)
    end

    return id, account, character
end

-- Works with a decorated account, an undecorated one, or a character name.
function Resolver:ForName(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end

    local account   = IRY.Util.NormalizeAccount(name)
    local character = IRY.Util.NormalizeCharacter(name)

    local id
    if account then
        id = IRY.Store:FindByAccount(account)
    end
    if not id and character then
        id = IRY.Store:FindByCharacter(character)
    end

    return id
end

function Resolver:DisplayName(id)
    if not id then
        return nil
    end

    local player = IRY.Store:GetPlayer(IRY.Store:ResolveFinal(id))
    if not player then
        return nil
    end

    return player.displayName
end

function Resolver:IsCustom(id)
    local player = id and IRY.Store:GetPlayer(IRY.Store:ResolveFinal(id))
    return player and player.isCustom or false
end

-- True when the entity remembers this exact @account.
function Resolver:KnowsAccount(id, account)
    local player = id and IRY.Store:GetPlayer(IRY.Store:ResolveFinal(id))
    if not player or not account then
        return false
    end
    return player.aliases[account] ~= nil
end
