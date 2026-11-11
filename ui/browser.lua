--[[
    I remember you! -- the browser window.

    No ZO_ScrollList here on purpose: a fixed pool of row buttons, filled from
    a paged snapshot of the store. That keeps the window cheap to build and
    immune to scroll list API changes.

    The window is resizable. The row pool is fixed (MAX_ROWS), but only as many
    rows as fit into the current height are filled and shown: the page size is
    derived from IRY_BrowserRows:GetHeight(). Geometry is persisted lazily in
    settings (browserLeft/Top/Width/Height), never in the defaults.

    The detail panel is a single child control of the main window. It is never
    duplicated: clicking another player replaces its contents, closing the list
    hides it together with its parent, and switching tabs closes it.

    The window is read only with respect to the game: it talks to IRY.Store
    through the same methods the slash commands use.
]]

local Browser = {}
IRY.Browser = Browser

local DEFAULT_WIDTH  = 660
local DEFAULT_HEIGHT = 680
local MIN_WIDTH      = 660
local MIN_HEIGHT     = 420
local MAX_WIDTH      = 1600
local MAX_HEIGHT     = 1200

local ROW_HEIGHT          = 26
local MAX_ROWS            = 40
local DETAIL_LINE_HEIGHT  = 18
local MAX_DETAIL_LINES    = 40
local DETAIL_WIDTH        = 320
local DETAIL_GAP          = 8

-- Vertical space reserved by the fixed header and the footer.
local ROWS_TOP_OFFSET    = 124
local ROWS_BOTTOM_OFFSET = 112

-- True once the window is registered with the scene manager, which is what
-- makes the game's own UI-mode and Escape handling work on it.
local usesTopLevel = false

local state = {
    tab        = "players",
    page       = 1,
    search     = "",
    selected   = nil,       -- player id (players tab) or pending id
    mergeFirst = nil,       -- first id picked for a merge
    data       = {},
    left       = nil,
    top        = nil,
    width      = nil,
    height     = nil,
    rowsPerPage = 12,

    detailOpen     = false,
    detailPlayerId = nil,
    detailOffset   = 0,
    detailVisible  = 0,
    detailItems    = {},
}

local function settings()
    return IRY.Store:GetSettings() or {}
end

local function shortTime(timestamp)
    if not timestamp or timestamp <= 0 then
        return "-"
    end
    return os.date("%m-%d %H:%M", timestamp)
end

local function keysOf(map)
    local keys = {}
    for key in pairs(map or {}) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    return keys
end

local function matches(player, needle)
    if needle == "" then
        return true
    end

    local displayName = player.displayName or ""
    if displayName:lower():find(needle, 1, true) or displayName:find(needle, 1, true) then
        return true
    end

    for _, account in ipairs(keysOf(player.aliases)) do
        if account:lower():find(needle, 1, true) then
            return true
        end
    end

    for _, character in ipairs(keysOf(player.characters)) do
        if character:lower():find(needle, 1, true) then
            return true
        end
    end

    return false
end

local function pendingLabel(entry)
    if entry.account then
        return IRY.Util.FormatAccount(entry.account)
    end
    return tostring(entry.character or "?")
end

local function pendingTarget(entry)
    local player = IRY.Store:GetPlayer(IRY.Store:ResolveFinal(entry.targetId))
    return player and player.displayName or "?"
end

local function addDetailItem(items, kind, name, meta)
    items[#items + 1] = {
        kind = kind,
        name = name or "",
        meta = meta or "",
    }
end

-- Data ------------------------------------------------------------------------

function Browser:Collect()
    local needle = state.search:lower()
    -- Accounts are stored without the leading '@', so let people type it.
    needle = needle:gsub("^@", "")
    local result = {}

    if state.tab == "pending" then
        for _, entry in ipairs(IRY.Store:GetPendingList()) do
            local label = pendingLabel(entry):lower()
            local target = pendingTarget(entry):lower()
            if needle == "" or label:find(needle, 1, true) or target:find(needle, 1, true) then
                result[#result + 1] = { kind = "pending", entry = entry }
            end
        end
        table.sort(result, function(a, b)
            return a.entry.id < b.entry.id
        end)
        return result
    end

    for _, player in ipairs(IRY.Store:List()) do
        if matches(player, needle) then
            result[#result + 1] = { kind = "player", player = player }
        end
    end
    return result
end

function Browser:GetPageSize()
    return state.rowsPerPage or 12
end

-- The number of rows that fit into the current window height. Called on every
-- refresh and on resize, so a grown window immediately shows more players.
function Browser:UpdatePageSize()
    local height = IRY_BrowserRows and IRY_BrowserRows:GetHeight() or 0
    if not height or height <= 0 then
        local windowHeight = IRY_Browser and IRY_Browser:GetHeight() or DEFAULT_HEIGHT
        height = windowHeight - ROWS_TOP_OFFSET - ROWS_BOTTOM_OFFSET
    end

    local count = math.floor(height / ROW_HEIGHT)
    if count < 5 then
        count = 5
    end
    if count > MAX_ROWS then
        count = MAX_ROWS
    end

    state.rowsPerPage = count
end

-- Rendering -------------------------------------------------------------------

function Browser:RenderRows()
    if not self.rows then
        return
    end

    local pageSize = self:GetPageSize()
    local offset = (state.page - 1) * pageSize

    for index = 1, MAX_ROWS do
        local row = self.rows[index]
        local item = (index <= pageSize) and state.data[offset + index] or nil

        if not item then
            row:SetHidden(true)
        else
            row:SetHidden(false)

            local idLabel = row:GetNamedChild("Id")
            local nameLabel = row:GetNamedChild("Name")
            local metaLabel = row:GetNamedChild("Meta")
            local seenLabel = row:GetNamedChild("Seen")

            if item.kind == "pending" then
                local entry = item.entry
                idLabel:SetText(string.format("#%d", entry.id))
                nameLabel:SetText(string.format("%s -> %s", pendingLabel(entry), pendingTarget(entry)))
                metaLabel:SetText(entry.kind == "conflict" and "conflict" or "bridge")
                seenLabel:SetText(shortTime(entry.createdAt))

                local selected = state.selected == entry.id
                nameLabel:SetColor(1, selected and 0.94 or 1, selected and 0.63 or 1, 1)
            else
                local player = item.player
                idLabel:SetText(string.format("#%d", player.id))
                nameLabel:SetText(player.displayName)
                metaLabel:SetText(string.format("%d acc / %d char",
                    self:CountKeys(player.aliases), self:CountKeys(player.characters)))
                seenLabel:SetText(shortTime(player.updatedAt))

                if state.selected == player.id then
                    nameLabel:SetColor(1, 0.94, 0.63, 1)
                elseif player.isCustom then
                    nameLabel:SetColor(0.49, 0.98, 0.49, 1)
                else
                    nameLabel:SetColor(1, 1, 1, 1)
                end
            end
        end
    end
end

function Browser:CountKeys(map)
    local count = 0
    for _ in pairs(map or {}) do
        count = count + 1
    end
    return count
end

function Browser:RenderDetail()
    local detail = IRY_BrowserDetail
    if not detail then
        return
    end

    if state.tab == "pending" then
        local entry = state.selected and IRY.Store:GetPending(state.selected)
        if entry then
            detail:SetText(string.format("%s  ->  %s",
                pendingLabel(entry), pendingTarget(entry)))
        else
            detail:SetText(IRY.L.BROWSER_SELECT)
        end
        return
    end

    local player = state.selected and IRY.Store:GetPlayer(IRY.Store:ResolveFinal(state.selected))
    if not player then
        detail:SetText(IRY.L.BROWSER_SELECT)
        return
    end

    -- The full account/character lists live in the detail panel; this line is
    -- just a compact summary that can never overflow the footer.
    local text = string.format("#%d  %s   |c8F8F8F%s|r",
        player.id,
        player.displayName,
        string.format(IRY.L.BROWSER_SUMMARY,
            self:CountKeys(player.aliases),
            self:CountKeys(player.characters)))

    if state.mergeFirst then
        text = text .. string.format("   |cFFD080%s|r",
            string.format(IRY.L.BROWSER_MERGE_PROMPT, state.mergeFirst))
    end

    detail:SetText(text)
end

function Browser:BuildDetailItems(player)
    local items = {}

    addDetailItem(items, "header", IRY.L.DETAIL_ACCOUNTS, "")

    local accounts = keysOf(player.aliases)
    if #accounts == 0 then
        addDetailItem(items, "muted", IRY.L.DETAIL_NO_ACCOUNTS, "")
    else
        for _, account in ipairs(accounts) do
            local alias = player.aliases[account] or {}
            addDetailItem(items, "account",
                IRY.Util.FormatAccount(account),
                IRY.Util.FormatTime(alias.lastSeen))
        end
    end

    addDetailItem(items, "blank", "", "")

    addDetailItem(items, "header", IRY.L.DETAIL_CHARACTERS, "")

    local characters = keysOf(player.characters)
    if #characters == 0 then
        addDetailItem(items, "muted", IRY.L.DETAIL_NO_CHARACTERS, "")
    else
        for _, character in ipairs(characters) do
            local entry = player.characters[character] or {}
            local parts = {}

            local allianceName = IRY.Util.FormatAlliance(entry.alliance)
            if allianceName ~= "" then
                parts[#parts + 1] = allianceName
            end

            local level = tonumber(entry.level) or 0
            if level > 0 then
                parts[#parts + 1] = tostring(level)
            end

            addDetailItem(items, "character", character, table.concat(parts, " · "))
        end
    end

    return items
end

function Browser:RenderDetailPanel()
    local panel = IRY_BrowserDetailPanel
    if not panel then
        return
    end

    local player
    if state.detailOpen and state.detailPlayerId then
        player = IRY.Store:GetPlayer(IRY.Store:ResolveFinal(state.detailPlayerId))
    end

    if not player then
        if state.detailOpen then
            self:CloseDetail()
        else
            panel:SetHidden(true)
        end
        return
    end

    panel:SetHidden(false)

    local linesHeight = IRY_BrowserDetailPanelLines and IRY_BrowserDetailPanelLines:GetHeight() or 0
    if not linesHeight or linesHeight <= 0 then
        local panelHeight = panel:GetHeight() or MIN_HEIGHT
        linesHeight = panelHeight - 68
    end

    local visible = math.floor(linesHeight / DETAIL_LINE_HEIGHT)
    if visible < 5 then
        visible = 5
    end
    if visible > MAX_DETAIL_LINES then
        visible = MAX_DETAIL_LINES
    end
    state.detailVisible = visible

    local items = self:BuildDetailItems(player)
    state.detailItems = items

    local maxOffset = math.max(0, #items - visible)
    if state.detailOffset > maxOffset then
        state.detailOffset = maxOffset
    end
    if state.detailOffset < 0 then
        state.detailOffset = 0
    end

    for index = 1, MAX_DETAIL_LINES do
        local line = self.detailLines[index]
        local item = (index <= visible) and items[state.detailOffset + index] or nil

        if not item then
            line:SetHidden(true)
        else
            line:SetHidden(false)

            local name = line:GetNamedChild("Name")
            local meta = line:GetNamedChild("Meta")
            name:SetText(item.name or "")
            meta:SetText(item.meta or "")

            if item.kind == "header" then
                name:SetWidth(300)
                name:SetColor(0.56, 0.86, 0.56, 1)
            elseif item.kind == "muted" then
                name:SetWidth(300)
                name:SetColor(0.56, 0.56, 0.56, 1)
            else
                name:SetWidth(150)
                if item.kind == "character" then
                    name:SetColor(1, 1, 1, 1)
                else
                    name:SetColor(0.86, 0.94, 0.74, 1)
                end
            end

            meta:SetColor(0.56, 0.56, 0.56, 1)
        end
    end

    IRY_BrowserDetailPanelTitle:SetText(string.format(IRY.L.DETAIL_TITLE, player.id, player.displayName))

    local hint = IRY.L.DETAIL_HINT
    if maxOffset > 0 then
        hint = string.format("%s  (%d/%d)", hint, state.detailOffset + 1, #items)
    end
    IRY_BrowserDetailPanelHint:SetText(hint)
end

function Browser:Refresh()
    if not IRY_Browser then
        return
    end

    self:UpdatePageSize()

    state.data = self:Collect()

    local pageSize = self:GetPageSize()
    local pages = math.max(1, math.ceil(#state.data / pageSize))
    if state.page > pages then
        state.page = pages
    end
    if state.page < 1 then
        state.page = 1
    end

    self:RenderRows()
    self:RenderDetail()
    self:RenderDetailPanel()

    local pendingCount = #IRY.Store:GetPendingList()
    IRY_BrowserCount:SetText(string.format(IRY.L.BROWSER_COUNT, #state.data, pendingCount))
    IRY_BrowserPageLabel:SetText(string.format(IRY.L.BROWSER_PAGE, state.page, pages))

    local isPlayers = state.tab == "players"
    IRY_BrowserRename:SetHidden(not isPlayers)
    IRY_BrowserReset:SetHidden(not isPlayers)
    IRY_BrowserMerge:SetHidden(not isPlayers)
    IRY_BrowserUndo:SetHidden(not isPlayers)
    IRY_BrowserRenameBG:SetHidden(not isPlayers)

    IRY_BrowserYes:SetHidden(isPlayers)
    IRY_BrowserNo:SetHidden(isPlayers)
end

function Browser:RefreshIfShown()
    if IRY_Browser and not IRY_Browser:IsHidden() then
        self:Refresh()
    end
end

-- Detail panel ----------------------------------------------------------------

function Browser:PlaceDetailPanel()
    local panel = IRY_BrowserDetailPanel
    if not panel or not IRY_Browser then
        return
    end

    local screenWidth = GuiRoot and GuiRoot:GetWidth() or 1920
    local right = IRY_Browser:GetRight() or 0

    panel:ClearAnchors()

    -- Prefer the right side; fall back to the left when the window is already
    -- near the right edge of the screen.
    if right + DETAIL_GAP + DETAIL_WIDTH <= screenWidth then
        panel:SetAnchor(TOPLEFT, IRY_Browser, TOPRIGHT, DETAIL_GAP, 0)
        panel:SetAnchor(BOTTOMRIGHT, IRY_Browser, BOTTOMRIGHT, DETAIL_GAP + DETAIL_WIDTH, 0)
    else
        panel:SetAnchor(TOPRIGHT, IRY_Browser, TOPLEFT, -DETAIL_GAP, 0)
        panel:SetAnchor(BOTTOMLEFT, IRY_Browser, BOTTOMLEFT, -(DETAIL_GAP + DETAIL_WIDTH), 0)
    end
end

function Browser:OpenDetail(id)
    if not id then
        return
    end

    state.detailOpen = true
    state.detailPlayerId = id
    state.detailOffset = 0

    self:PlaceDetailPanel()
    self:RenderDetailPanel()
end

function Browser:CloseDetail()
    state.detailOpen = false
    state.detailPlayerId = nil
    state.detailOffset = 0

    if IRY_BrowserDetailPanel then
        IRY_BrowserDetailPanel:SetHidden(true)
    end
end

function Browser:ScrollDetail(delta)
    if not state.detailOpen then
        return
    end

    local visible = state.detailVisible or 0
    local maxOffset = math.max(0, #state.detailItems - visible)
    if maxOffset == 0 then
        return
    end

    local step = (math.abs(delta) >= 3) and 3 or 1
    local nextOffset = state.detailOffset + ((delta > 0) and step or -step)

    if nextOffset < 0 then
        nextOffset = 0
    elseif nextOffset > maxOffset then
        nextOffset = maxOffset
    end

    if nextOffset == state.detailOffset then
        return
    end

    state.detailOffset = nextOffset
    self:RenderDetailPanel()
end

-- Actions ---------------------------------------------------------------------

function Browser:Select(id, openDetail)
    state.selected = id

    if state.tab == "players" and openDetail and id then
        self:OpenDetail(id)
    else
        self:CloseDetail()
    end

    -- Only the players tab has a rename box, and player ids and pending ids
    -- come from separate counters, so never look a pending id up as a player.
    if id and state.tab == "players" then
        local player = IRY.Store:GetPlayer(id)
        if player then
            IRY_BrowserRenameBGEdit:SetText(player.displayName)
        end
    end

    self:Refresh()
end

function Browser:OnRowClicked(row)
    local index = (state.page - 1) * self:GetPageSize() + row.index
    local item = state.data[index]
    if not item then
        return
    end

    if item.kind == "pending" then
        self:Select(item.entry.id)
    else
        self:Select(item.player.id, true)
    end
end

function Browser:OnRowEnter(row)
    local highlight = row:GetNamedChild("Highlight")
    if highlight then
        highlight:SetHidden(false)
    end
end

function Browser:OnRowLeave(row)
    local highlight = row:GetNamedChild("Highlight")
    if highlight then
        highlight:SetHidden(true)
    end
end

function Browser:CommitRename()
    if state.tab ~= "players" or not state.selected then
        return
    end

    local text = IRY_BrowserRenameBGEdit:GetText()
    if not IRY.Store:SetDisplayName(state.selected, text) then
        IRY:Print(IRY.L.RENAME_FAILED)
        return
    end

    IRY:Print(string.format(IRY.L.RENAMED, state.selected, IRY.Resolver:DisplayName(state.selected)))
    IRY:RefreshUI()
    self:Refresh()
end

-- Clicking a button or another row blurs the edit box; commit then too, but
-- only when the text really changed, so a plain focus change stays silent.
function Browser:OnRenameFocusLost()
    if state.tab ~= "players" or not state.selected then
        return
    end

    local player = IRY.Store:GetPlayer(state.selected)
    if not player then
        return
    end

    if IRY_BrowserRenameBGEdit:GetText() == player.displayName then
        return
    end

    self:CommitRename()
end

function Browser:PurgeOld()
    IRY:PurgeOldPlayers()
    self:Refresh()
end

function Browser:ResetName()
    if state.tab ~= "players" or not state.selected then
        return
    end

    local ok, name = IRY.Store:ResetDisplayName(state.selected)
    if not ok then
        IRY:Print(string.format(IRY.L.RESET_FAILED, state.selected))
        return
    end

    IRY:Print(string.format(IRY.L.RESET_NAME, state.selected, name))
    IRY_BrowserRenameBGEdit:SetText(name)
    IRY:RefreshUI()
    self:Refresh()
end

function Browser:MergeSelected()
    if state.tab ~= "players" or not state.selected then
        return
    end

    if not state.mergeFirst then
        state.mergeFirst = state.selected
        self:RenderDetail()
        return
    end

    local first, second = state.mergeFirst, state.selected
    state.mergeFirst = nil

    if first == second then
        IRY:Print(string.format(IRY.L.SAME_PLAYER, first))
        self:Refresh()
        return
    end

    local keep, drop = IRY.Store:OrderForMerge(first, second)
    IRY.Store:Merge(drop, keep, "manual")
    IRY:Print(string.format(IRY.L.MERGED, drop, keep))

    state.selected = keep
    if state.detailOpen then
        state.detailPlayerId = keep
        state.detailOffset = 0
    end

    IRY:RefreshUI()
    self:Refresh()
end

function Browser:UndoLastMerge()
    local sv = IRY.Store:GetSV()
    local newest

    for _, player in pairs(sv and sv.players or {}) do
        if player.mergedInto and (not newest or (player.mergedAt or 0) > (newest.mergedAt or 0)) then
            newest = player
        end
    end

    if not newest then
        IRY:Print(IRY.L.BROWSER_NO_UNDO)
        return
    end

    local ok, dstId = IRY.Store:UndoMerge(newest.id)
    if not ok then
        IRY:Print(string.format(IRY.L.CANNOT_UNDO, newest.id))
        return
    end

    IRY:Print(string.format(IRY.L.UNDONE, newest.id, dstId))
    state.selected = newest.id
    if state.detailOpen then
        state.detailPlayerId = newest.id
        state.detailOffset = 0
    end

    IRY:RefreshUI()
    self:Refresh()
end

function Browser:ConfirmSelected(accept)
    if state.tab ~= "pending" or not state.selected then
        return
    end

    local id = state.selected
    if accept then
        local entry = IRY.Observer:ApplyPending(id)
        if not entry then
            IRY:Print(string.format(IRY.L.PENDING_GONE, id))
        else
            IRY:Print(string.format(IRY.L.PENDING_APPROVED, id))
        end
    else
        IRY.Observer:RejectPending(id)
        IRY:Print(string.format(IRY.L.PENDING_REJECTED, id))
    end

    state.selected = nil
    self:CloseDetail()
    IRY:RefreshUI()
    self:Refresh()
end

function Browser:SetTab(tab)
    if state.tab == tab then
        return
    end

    state.tab = tab
    state.page = 1
    state.selected = nil
    state.mergeFirst = nil
    self:CloseDetail()
    self:Refresh()
end

function Browser:OnSearchChanged(text)
    state.search = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    state.page = 1
    self:Refresh()
end

function Browser:TurnPage(delta)
    delta = tonumber(delta) or 0
    local pages = math.max(1, math.ceil(#state.data / self:GetPageSize()))
    state.page = math.max(1, math.min(pages, state.page + delta))
    self:Refresh()
end

-- Window ----------------------------------------------------------------------

function Browser:SavePosition()
    if not IRY_Browser or IRY_Browser:IsHidden() then
        return
    end

    state.left = IRY_Browser:GetLeft()
    state.top = IRY_Browser:GetTop()
    state.width = IRY_Browser:GetWidth()
    state.height = IRY_Browser:GetHeight()

    local saved = settings()
    saved.browserLeft = state.left
    saved.browserTop = state.top
    saved.browserWidth = state.width
    saved.browserHeight = state.height
end

function Browser:OnResizeStop()
    if not IRY_Browser then
        return
    end

    state.width = IRY_Browser:GetWidth()
    state.height = IRY_Browser:GetHeight()
    state.left = IRY_Browser:GetLeft()
    state.top = IRY_Browser:GetTop()

    local saved = settings()
    saved.browserWidth = state.width
    saved.browserHeight = state.height
    saved.browserLeft = state.left
    saved.browserTop = state.top

    if state.detailOpen then
        self:PlaceDetailPanel()
    end

    -- Recompute the page size and (re)fill the rows for the new height.
    self:Refresh()
end

local function clampSize(value, minimum, maximum)
    value = tonumber(value) or minimum
    if value < minimum then
        value = minimum
    end
    if value > maximum then
        value = maximum
    end
    return value
end

function Browser:Show()
    if not IRY_Browser then
        return
    end

    if usesTopLevel then
        SCENE_MANAGER:ShowTopLevel(IRY_Browser)
    else
        IRY_Browser:SetHidden(false)
    end

    local saved = settings()

    local screenWidth = GuiRoot and GuiRoot:GetWidth() or 1920
    local screenHeight = GuiRoot and GuiRoot:GetHeight() or 1080

    local width = clampSize(state.width or saved.browserWidth or DEFAULT_WIDTH, MIN_WIDTH, MAX_WIDTH)
    local height = clampSize(state.height or saved.browserHeight or DEFAULT_HEIGHT, MIN_HEIGHT, MAX_HEIGHT)
    width = math.min(width, math.max(MIN_WIDTH, screenWidth - 20))
    height = math.min(height, math.max(MIN_HEIGHT, screenHeight - 20))

    state.width, state.height = width, height
    IRY_Browser:SetWidth(width)
    IRY_Browser:SetHeight(height)

    local left = state.left or saved.browserLeft
    local top = state.top or saved.browserTop

    if left and top then
        state.left, state.top = left, top
        IRY_Browser:ClearAnchors()
        IRY_Browser:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, left, top)
    end

    -- ESO stacks visible top-level windows in the order they were registered,
    -- so a window opened from a slash command can start behind a window that
    -- was registered later; the game only raises it on the first mouse click.
    -- Raising it here makes the list usable (and on top) immediately.
    if IRY_Browser.BringWindowToTop then
        IRY_Browser:BringWindowToTop()
    end

    self:Refresh()
end

function Browser:Hide()
    if not IRY_Browser then
        return
    end

    -- The detail panel goes away with the list, both visually (it is a child)
    -- and in state, so reopening the list starts with a clean slate.
    self:CloseDetail()
    self:SavePosition()

    if usesTopLevel then
        SCENE_MANAGER:HideTopLevel(IRY_Browser)
    else
        IRY_Browser:SetHidden(true)
    end
end

function Browser:Toggle()
    if not IRY_Browser then
        return
    end

    if IRY_Browser:IsHidden() then
        self:Show()
    else
        self:Hide()
    end
end

function Browser:Initialize()
    if not IRY_Browser then
        return
    end

    self.rows = {}
    for index = 1, MAX_ROWS do
        local row = CreateControlFromVirtual("IRY_BrowserRow" .. index, IRY_BrowserRows, "IRY_BrowserRow")
        row:SetAnchor(TOPLEFT, IRY_BrowserRows, TOPLEFT, 0, (index - 1) * ROW_HEIGHT)
        row:SetAnchor(TOPRIGHT, IRY_BrowserRows, TOPRIGHT, 0, (index - 1) * ROW_HEIGHT)
        row.index = index
        row:SetHidden(true)
        self.rows[index] = row
    end

    self.detailLines = {}
    for index = 1, MAX_DETAIL_LINES do
        local line = CreateControlFromVirtual("IRY_DetailLine" .. index, IRY_BrowserDetailPanelLines, "IRY_DetailLine")
        line:SetAnchor(TOPLEFT, IRY_BrowserDetailPanelLines, TOPLEFT, 0, (index - 1) * DETAIL_LINE_HEIGHT)
        line.index = index
        line:SetHidden(true)
        self.detailLines[index] = line
    end

    if IRY_Browser.SetDimensionConstraints then
        IRY_Browser:SetDimensionConstraints(MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT)
    end

    IRY_BrowserTitle:SetText(IRY.title)
    IRY_BrowserTabPlayers:SetText(IRY.L.BTN_PLAYERS)
    IRY_BrowserTabPending:SetText(IRY.L.BTN_PENDING)
    IRY_BrowserHeadId:SetText(IRY.L.HEADER_ID)
    IRY_BrowserHeadName:SetText(IRY.L.HEADER_NAME)
    IRY_BrowserHeadMeta:SetText(IRY.L.HEADER_META)
    IRY_BrowserHeadSeen:SetText(IRY.L.HEADER_SEEN)
    IRY_BrowserRename:SetText(IRY.L.BTN_RENAME)
    IRY_BrowserReset:SetText(IRY.L.BTN_RESET)
    IRY_BrowserMerge:SetText(IRY.L.BTN_MERGE)
    IRY_BrowserUndo:SetText(IRY.L.BTN_UNDO)
    IRY_BrowserYes:SetText(IRY.L.BTN_YES)
    IRY_BrowserNo:SetText(IRY.L.BTN_NO)
    IRY_BrowserPurge:SetText(IRY.L.BTN_PURGE)
    IRY_BrowserDetail:SetText(IRY.L.BROWSER_SELECT)
    IRY_BrowserDetailPanelHint:SetText(IRY.L.DETAIL_HINT)
    IRY_BrowserDetailPanel:SetHidden(true)

    -- The browser is a read surface; it should not steal the mouse cursor
    -- until the user opens it on purpose.
    IRY_Browser:SetHidden(true)

    -- Registering as a top level window gives us the game's own UI mode and
    -- Escape handling: Escape hides the window before it opens the game menu.
    usesTopLevel = SCENE_MANAGER ~= nil and SCENE_MANAGER.RegisterTopLevel ~= nil
    if usesTopLevel then
        SCENE_MANAGER:RegisterTopLevel(IRY_Browser, false)
    end
end
