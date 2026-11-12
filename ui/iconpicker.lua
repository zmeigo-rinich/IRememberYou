--[[
    I remember you! -- the icon picker.

    A fixed 8 x 5 grid of tiles. The list comes from core/iconpacks.lua; the
    picker itself owns no icon data. It has two modes:

      * player    -- assign a manual icon to one entity (opened from the detail
                     panel in ui/browser.lua);
      * blacklist -- pick the marker used for ignored players (opened from the
                     settings panel).

    ESC works because the window is registered as a top level window, the same
    way the browser is.
]]

local IconPicker = {}
IRY.IconPicker = IconPicker

local COLS = 8
local ROWS = 5
local TILE = 64
local GAP  = 8
local PER_PAGE = COLS * ROWS

local usesTopLevel = false

local state = {
    page   = 1,
    target = nil,   -- { kind = "player", id = n } | { kind = "blacklist" }
    tiles  = {},
}

local function settings()
    return (IRY.Store and IRY.Store:GetSettings()) or {}
end

function IconPicker:BuildTiles()
    if #state.tiles > 0 or not IRY_IconPickerGrid then
        return
    end

    for index = 1, PER_PAGE do
        local tile = CreateControlFromVirtual("IRY_IconTile" .. index, IRY_IconPickerGrid, "IRY_IconTile")
        local col = (index - 1) % COLS
        local row = math.floor((index - 1) / COLS)

        tile:SetAnchor(TOPLEFT, IRY_IconPickerGrid, TOPLEFT, col * (TILE + GAP), row * (TILE + GAP))
        tile.index = index
        tile:SetHidden(true)
        state.tiles[index] = tile
    end
end

function IconPicker:PageCount()
    return math.max(1, math.ceil(#IRY.Icons:AllPaths() / PER_PAGE))
end

function IconPicker:Render()
    local paths = IRY.Icons:AllPaths()
    local pages = self:PageCount()

    state.page = math.max(1, math.min(pages, state.page))

    local offset = (state.page - 1) * PER_PAGE
    local current
    if state.target and state.target.kind == "player" then
        current = IRY.Store:GetIconPath(state.target.id)
    elseif state.target and state.target.kind == "blacklist" then
        current = IRY.Icons:BlacklistPath()
    end

    for index, tile in ipairs(state.tiles) do
        local path = paths[offset + index]
        if path then
            tile:SetHidden(false)
            tile.path = path
            tile:GetNamedChild("Texture"):SetTexture(path)
            tile:GetNamedChild("Selected"):SetHidden(path ~= current)
        else
            tile:SetHidden(true)
            tile.path = nil
        end
    end

    IRY_IconPickerEmpty:SetHidden(#paths > 0)
    IRY_IconPickerPageLabel:SetText(string.format(IRY.L.PICKER_PAGE, state.page, pages))
    IRY_IconPickerPrev:SetEnabled(state.page > 1)
    IRY_IconPickerNext:SetEnabled(state.page < pages)
end

function IconPicker:Open(target)
    if not IRY_IconPicker then
        return
    end

    state.target = target
    state.page = 1

    self:BuildTiles()
    self:Render()

    if usesTopLevel then
        SCENE_MANAGER:ShowTopLevel(IRY_IconPicker)
    else
        IRY_IconPicker:SetHidden(false)
    end

    if IRY_IconPicker.BringWindowToTop then
        IRY_IconPicker:BringWindowToTop()
    end
end

function IconPicker:OpenPlayer(playerId)
    if not playerId then
        return
    end
    self:Open({ kind = "player", id = IRY.Store:ResolveFinal(playerId) })
end

function IconPicker:OpenBlacklist()
    self:Open({ kind = "blacklist" })
end

function IconPicker:Close()
    if not IRY_IconPicker then
        return
    end

    if usesTopLevel then
        SCENE_MANAGER:HideTopLevel(IRY_IconPicker)
    else
        IRY_IconPicker:SetHidden(true)
    end

    state.target = nil
end

function IconPicker:TurnPage(delta)
    local pages = self:PageCount()
    state.page = math.max(1, math.min(pages, state.page + (tonumber(delta) or 0)))
    self:Render()
end

function IconPicker:OnTileClicked(tile)
    local target = state.target
    local path = tile and tile.path
    if not target or not path then
        return
    end

    if target.kind == "player" then
        IRY.Icons:Assign(target.id, path)
    elseif target.kind == "blacklist" then
        -- Empty string means "follow the manifest default" again.
        settings().blacklistIcon = path
        IRY:RefreshUI()
    end

    self:Close()
end

function IconPicker:Initialize()
    if not IRY_IconPicker then
        return
    end

    self:BuildTiles()

    IRY_IconPickerTitle:SetText(IRY.L.PICKER_TITLE)
    IRY_IconPickerEmpty:SetText(IRY.L.PICKER_EMPTY)
    IRY_IconPickerPageLabel:SetText(string.format(IRY.L.PICKER_PAGE, 1, 1))
    IRY_IconPicker:SetHidden(true)

    usesTopLevel = SCENE_MANAGER ~= nil and SCENE_MANAGER.RegisterTopLevel ~= nil
    if usesTopLevel then
        SCENE_MANAGER:RegisterTopLevel(IRY_IconPicker, false)
    end
end
