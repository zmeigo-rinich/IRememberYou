--[[
    I remember you! -- optional marker above the reticle.

    ESO does not expose the world position of a player who is not in the group,
    so a 3D icon cannot be anchored above the reticle target. The crosshair,
    however, always sits in the middle of the screen, and the unit under it is
    `reticleover`. A screen-space texture near the centre therefore looks like a
    marker over the target and works for every player.

    It is only a UI picture: it does not follow the distance to the target and it
    sits above everything the world draws. Both are accepted trade-offs of the
    approach, and they are why the marker can be dragged: while it is unlocked,
    the picture is shown even in the menu, ignores IsReticleHidden() and uses a
    green-arrow placeholder when there is no target, so it can always be found
    and placed. Locking it stores the position and returns to the normal rules.

    Every refresh runs inside pcall: a single failing call must not leave the
    user without a picture and without a reason. The error is printed once and
    kept for `/pa marker`, which also reports the control state and the icon the
    game resolves for `reticleover`.
]]

local Marker = {}
IRY.ReticleMarker = Marker

local NAME = "IRY_ReticleMarker"
local TEST_SIZE = 128

local function settings()
    return (IRY.Store and IRY.Store:GetSettings()) or {}
end

local function clamp(value, low, high)
    if low > high then
        low, high = high, low
    end
    return math.max(low, math.min(high, value))
end

local function markerSize(s)
    local size = tonumber(s.reticleMarkerSize) or IRY.ICON.markerDefault
    return clamp(size, IRY.ICON.markerMin, IRY.ICON.markerMax)
end

local function markerX(s)
    return tonumber(s.reticleMarkerX) or 0
end

local function markerY(s)
    return tonumber(s.reticleMarkerY) or IRY.SettingsDefaults.reticleMarkerY
end

-- Test mode is a plain "draw it now" switch used by `/pa marker test`: it
-- bypasses every setting and every display rule, so it tells apart "the texture
-- does not render" from "a condition hides it".
function Marker:IsUnlocked()
    return Marker.testMode == true or settings().reticleMarkerLocked == false
end

local function leftButton(button)
    return button == (MOUSE_BUTTON_INDEX_LEFT or 1)
end

local function isPvPWorld()
    if type(IsActiveWorldBattleground) == "function" and IsActiveWorldBattleground() then
        return true
    end
    if type(IsPlayerInAvAWorld) == "function" and IsPlayerInAvAWorld() then
        return true
    end
    return false
end

-- Normal display rules. While the marker is unlocked these are skipped on
-- purpose: the user must be able to grab it in the menu and without a target.
local function shouldDisplay(s, path)
    if not path then
        return false
    end
    if type(IsReticleHidden) == "function" and IsReticleHidden() then
        return false
    end
    if s.markerSkipDead and type(IsUnitDead) == "function" and IsUnitDead("reticleover") then
        return false
    end
    if s.markerHostileOnly and type(IsUnitAttackable) == "function"
        and not IsUnitAttackable("reticleover") then
        return false
    end
    if s.markerPvPOnly and not isPvPWorld() then
        return false
    end
    return true
end

-- After a drag the control's anchors are whatever StartMoving left behind.
-- Convert the position back to offsets from the screen centre, clamp it so the
-- picture cannot be lost off-screen, store it and re-anchor cleanly.
function Marker:SavePosition()
    local control = Marker.control
    if not control then
        return
    end

    local size = control:GetWidth() or 0
    local left, top = control:GetLeft(), control:GetTop()
    if not left or not top then
        return
    end

    local halfWidth = GuiRoot:GetWidth() / 2
    local halfHeight = GuiRoot:GetHeight() / 2
    local margin = size / 2 + 4

    local x = math.floor(clamp(left + size / 2 - halfWidth,
        -halfWidth + margin, halfWidth - margin) + 0.5)
    local y = math.floor(clamp(top + size / 2 - halfHeight,
        -halfHeight + margin, halfHeight - margin) + 0.5)

    local s = settings()
    s.reticleMarkerX = x
    s.reticleMarkerY = y

    control:ClearAnchors()
    control:SetAnchor(CENTER, GuiRoot, CENTER, x, y)
end

-- End a drag exactly once. OnMouseUp alone is not enough: ESO can finish the
-- move through the mover itself (OnMoveStop), and in that case OnMouseUp may
-- never arrive. Both handlers call this; the dragging flag makes it
-- idempotent, which also matters because StopMovingOrResizing can fire
-- OnMoveStop synchronously.
local function finishDrag(control)
    if not control or not control.dragging then
        return
    end

    control.dragging = false
    if control.StopMovingOrResizing then
        control:StopMovingOrResizing()
    end
    control:SetMovable(false)

    Marker:SavePosition()
    Marker:Refresh()
end

-- The settings button can lock the marker while the drag is still active (for
-- example when the user releases the mouse outside the picture). Public so the
-- lock path can settle the position first.
function Marker:FinishDrag()
    finishDrag(Marker.control)
end

local function ensureControl()
    if Marker.control then
        return Marker.control
    end

    -- A top-level window, not a bare child of GuiRoot: that is the container
    -- independent addon UI uses, and it is the one the settings panel itself
    -- proves renders above the world.
    local control = WINDOW_MANAGER:CreateTopLevelWindow(NAME)
    if not control then
        return nil
    end

    -- Both constants are documented, but a nil would abort every refresh and
    -- take the marker down with it, so they are applied only when present.
    if DL_OVERLAY then
        pcall(control.SetDrawLayer, control, DL_OVERLAY)
    end
    if DT_HIGH then
        pcall(control.SetDrawTier, control, DT_HIGH)
    end

    control:SetAnchor(CENTER, GuiRoot, CENTER, 0, 0)
    control:SetDimensions(IRY.ICON.markerDefault, IRY.ICON.markerDefault)
    control:SetClampedToScreen(true)
    control:SetHidden(true)
    control:SetMouseEnabled(false)
    control:SetMovable(false)

    -- The picture is a texture child of the window, the same construction the
    -- settings panel uses for its backgrounds. The texture never takes the
    -- mouse; the window does.
    local texture = WINDOW_MANAGER:CreateControl(NAME .. "Texture", control, CT_TEXTURE)
    if texture then
        if DL_OVERLAY then
            pcall(texture.SetDrawLayer, texture, DL_OVERLAY)
        end
        if DT_HIGH then
            pcall(texture.SetDrawTier, texture, DT_HIGH)
        end
        texture:SetAnchor(CENTER, control, CENTER, 0, 0)
        texture:SetMouseEnabled(false)
    end
    control.texture = texture

    -- A visible hint is the only thing that tells the user the marker is in
    -- move mode: the picture itself looks exactly the same. The label is wider
    -- than the marker and sits above it; ESO does not clip children by default.
    local hint = WINDOW_MANAGER:CreateControl(NAME .. "Hint", control, CT_LABEL)
    if hint then
        if hint.SetFont then
            pcall(hint.SetFont, hint, "ZoFontGame")
        end
        if hint.SetHorizontalAlignment and TEXT_ALIGN_CENTER then
            pcall(hint.SetHorizontalAlignment, hint, TEXT_ALIGN_CENTER)
        end
        if hint.SetColor then
            pcall(hint.SetColor, hint, 1, 0.85, 0.3, 1)
        end
        hint:SetAnchor(BOTTOM, control, TOP, 0, 4)
        hint:SetDimensions(460, 24)
        hint:SetMouseEnabled(false)
        hint:SetHidden(true)
    end
    control.hint = hint

    control:SetHandler("OnMouseDown", function(self, button)
        if not leftButton(button) or not Marker:IsUnlocked() then
            return
        end

        Marker.dragDownCount = (Marker.dragDownCount or 0) + 1
        if self.dragging then
            return
        end

        self.dragging = true
        -- Movable only for the duration of a left-button drag. Leaving it on
        -- all the time lets ESO's built-in moving code react to the right
        -- mouse button as well, which is not what the user expects.
        self:SetMovable(true)
        if self.StartMoving then
            self:StartMoving()
        end
    end)

    control:SetHandler("OnMouseUp", function(self, button)
        if not leftButton(button) then
            return
        end
        Marker.dragUpCount = (Marker.dragUpCount or 0) + 1
        finishDrag(self)
    end)

    control:SetHandler("OnMoveStart", function()
        Marker.moveStartCount = (Marker.moveStartCount or 0) + 1
    end)

    control:SetHandler("OnMoveStop", function(self)
        Marker.moveStopCount = (Marker.moveStopCount or 0) + 1
        finishDrag(self)
    end)

    Marker.control = control
    return control
end

local function hide()
    if Marker.control then
        Marker.control:SetHidden(true)
    end
end

-- Test mode draws two extra pictures in one diagnostic window: the same icon as
-- inline `|t` markup in a label (the way the target frame draws it) and a
-- texture that ships with the game. The real marker above is the third picture.
-- Which of the three is visible names the broken part: addon path, label markup
-- or texture/container.
local GAME_TEXTURE = "EsoUI/Art/Miscellaneous/help_icon.dds"

local function ensureProbe()
    if Marker.probeWindow then
        return Marker.probeWindow
    end

    local window = WINDOW_MANAGER:CreateTopLevelWindow(NAME .. "ProbeWindow")
    if not window then
        return nil
    end
    if DL_OVERLAY then
        pcall(window.SetDrawLayer, window, DL_OVERLAY)
    end
    if DT_HIGH then
        pcall(window.SetDrawTier, window, DT_HIGH)
    end
    window:SetAnchor(CENTER, GuiRoot, CENTER, 0, 0)
    -- Tall enough that the lower test picture is inside its parent, so a
    -- clipping parent cannot hide the very thing the probe checks.
    window:SetDimensions(400, 700)
    window:SetHidden(true)

    local label = WINDOW_MANAGER:CreateControl(NAME .. "ProbeLabel", window, CT_LABEL)
    if label then
        if label.SetFont then
            pcall(label.SetFont, label, "ZoFontGame")
        end
        if DL_OVERLAY then
            pcall(label.SetDrawLayer, label, DL_OVERLAY)
        end
        if DT_HIGH then
            pcall(label.SetDrawTier, label, DT_HIGH)
        end
        label:SetAnchor(CENTER, window, CENTER, 0, 120)
        label:SetMouseEnabled(false)
    end
    Marker.probe = label

    local texture = WINDOW_MANAGER:CreateControl(NAME .. "ProbeTexture", window, CT_TEXTURE)
    if texture then
        if DL_OVERLAY then
            pcall(texture.SetDrawLayer, texture, DL_OVERLAY)
        end
        if DT_HIGH then
            pcall(texture.SetDrawTier, texture, DT_HIGH)
        end
        texture:SetAnchor(CENTER, window, CENTER, 0, 260)
        texture:SetDimensions(TEST_SIZE, TEST_SIZE)
        texture:SetTexture(GAME_TEXTURE)
        texture:SetMouseEnabled(false)
    end
    Marker.probeTexture = texture

    Marker.probeWindow = window
    return window
end

local function showProbe(path)
    local window = ensureProbe()
    if not window then
        return
    end

    if Marker.probe then
        Marker.probe:SetText(string.format("|t%d:%d:%s|t", TEST_SIZE, TEST_SIZE, path))
    end
    window:SetHidden(false)
end

local function hideProbe()
    if Marker.probeWindow then
        Marker.probeWindow:SetHidden(true)
    end
end

local function apply()
    Marker.refreshCount = (Marker.refreshCount or 0) + 1

    local s = settings()
    local test = Marker.testMode == true

    if not test then
        pcall(hideProbe)
    end

    if not test and (s.showIcons == false or s.reticleMarker ~= true) then
        hide()
        return
    end

    local control = ensureControl()
    if not control then
        hide()
        return
    end

    -- A running drag owns the anchors and the size; the one-second refresh
    -- must not snap the picture back or resize it under the cursor.
    if control.dragging then
        return
    end

    local unlocked = Marker:IsUnlocked()
    local size = test and TEST_SIZE or markerSize(s)

    local path = IRY.Icons and IRY.Icons:ForUnit("reticleover")

    if not path and (unlocked or test) then
        -- A placeholder keeps the marker visible and draggable with no target.
        path = IRY.ICON.markerPlaceholder or IRY.ICON.blacklistDefault
    end
    if not path then
        hide()
        return
    end
    if not unlocked and not shouldDisplay(s, path) then
        hide()
        return
    end

    Marker.lastPath = path
    Marker.lastSize = size

    control:SetDimensions(size, size)
    control:SetMouseEnabled(unlocked)
    -- Only OnMouseDown turns this on, and only for the left button. Keeping it
    -- on while unlocked would also make the right button move the marker.
    control:SetMovable(false)
    control:SetAlpha(1)

    if control.texture then
        control.texture:SetDimensions(size, size)
        control.texture:SetTexture(path)
    end

    if control.hint then
        if unlocked and IRY.L.MARKER_HINT then
            control.hint:SetText(IRY.L.MARKER_HINT)
            control.hint:SetHidden(false)
        else
            control.hint:SetHidden(true)
        end
    end

    control:ClearAnchors()
    control:SetAnchor(CENTER, GuiRoot, CENTER, markerX(s), markerY(s))

    control:SetHidden(false)

    -- See ensureProbe: the extra copies are diagnostic only and must never break
    -- the real marker, hence the pcall and the "after the control is shown" spot.
    if test then
        pcall(showProbe, path)
    end
end

function Marker:Refresh()
    local ok, err = pcall(apply)

    if ok then
        Marker.lastError = nil
        return
    end

    err = tostring(err)
    if err ~= Marker.lastError then
        Marker.lastError = err
        IRY:Print(string.format(IRY.L.MARKER_ERROR, err))
    end
end

-- `/pa marker test`: show the marker at a fixed size no matter what the settings
-- and the reticle say. A second call turns it off again.
function Marker:Test()
    Marker.testMode = not Marker.testMode

    Marker:Refresh()

    if Marker.testMode then
        IRY:Print(IRY.L.MARKER_TEST_ON)
    else
        IRY:Print(IRY.L.MARKER_TEST_OFF)
    end

    -- Print the state that was just drawn, so one command answers "is it on
    -- screen" and "what does the control look like" at the same time.
    IRY:PrintLines(Marker:Describe())
end

-- `/pa marker`: a one-shot report for a live client. It answers three
-- questions at once: what the settings say, whether the control exists and what
-- the game resolves under the reticle.
function Marker:Describe()
    local s = settings()
    local lines = {}

    local function add(text)
        lines[#lines + 1] = text
    end

    add(string.format("showIcons=%s marker=%s locked=%s test=%s",
        tostring(s.showIcons), tostring(s.reticleMarker),
        tostring(s.reticleMarkerLocked), tostring(Marker.testMode == true)))
    add(string.format("x=%s y=%s size=%s dead=%s hostile=%s pvp=%s",
        tostring(s.reticleMarkerX), tostring(s.reticleMarkerY),
        tostring(s.reticleMarkerSize), tostring(s.markerSkipDead),
        tostring(s.markerHostileOnly), tostring(s.markerPvPOnly)))
    add(string.format("refresh calls=%d", Marker.refreshCount or 0))
    add(string.format("gui=%sx%s", tostring(GuiRoot:GetWidth()), tostring(GuiRoot:GetHeight())))

    local control = Marker.control
    if control then
        local texture
        local child = control.texture
        if child and child.GetTextureFileName then
            local ok, name = pcall(child.GetTextureFileName, child)
            texture = ok and name or nil
        end

        add(string.format("control: hidden=%s w=%s h=%s left=%s top=%s texture=%s",
            tostring(control:IsHidden()), tostring(control:GetWidth()),
            tostring(control:GetHeight()), tostring(control:GetLeft()),
            tostring(control:GetTop()), tostring(texture or Marker.lastPath)))
        add(string.format("drag: active=%s down=%d up=%d start=%d stop=%d",
            tostring(control.dragging == true),
            Marker.dragDownCount or 0, Marker.dragUpCount or 0,
            Marker.moveStartCount or 0, Marker.moveStopCount or 0))
    else
        add("control: not created")
    end

    local exists = DoesUnitExist("reticleover")
    local path = IRY.Icons and IRY.Icons:ForUnit("reticleover")
    local hidden = nil
    if type(IsReticleHidden) == "function" then
        hidden = IsReticleHidden() and true or false
    end

    add(string.format("reticleover: exists=%s player=%s name=%s reticleHidden=%s icon=%s",
        tostring(exists),
        tostring(exists and IsUnitPlayer("reticleover")),
        tostring(exists and GetUnitName("reticleover")),
        tostring(hidden), tostring(path)))

    if Marker.lastError then
        add("last error: " .. Marker.lastError)
    end

    local probeWindow = Marker.probeWindow
    add(string.format("probe window: %s",
        probeWindow and ("hidden=" .. tostring(probeWindow:IsHidden())) or "not created"))

    local probe = Marker.probe
    if probe then
        local len, markup = 0, false
        if probe.GetText then
            local ok, text = pcall(probe.GetText, probe)
            if ok and type(text) == "string" then
                len = #text
                markup = text:find("|t", 1, true) ~= nil
            end
        end
        add(string.format("probe label: len=%d markup=%s", len, tostring(markup)))
    else
        add("probe label: not created")
    end

    local probeTexture = Marker.probeTexture
    if probeTexture then
        add(string.format("probe texture: texture=%s", tostring(GAME_TEXTURE)))
    else
        add("probe texture: not created")
    end

    return lines
end

-- Not every client exposes every event; a nil constant would abort the whole
-- Initialize, so missing ones are skipped instead.
local function register(namespace, eventName, handler)
    if not eventName then
        return
    end

    EVENT_MANAGER:RegisterForEvent(namespace, eventName, handler)
end

function Marker:Initialize()
    local namespace = IRY.name .. "ReticleMarker"

    local function refresh()
        IRY.ReticleMarker:Refresh()
    end

    register(namespace, EVENT_RETICLE_TARGET_CHANGED, refresh)
    register(namespace, EVENT_RETICLE_HIDDEN_UPDATE, refresh)
    register(namespace, EVENT_UNIT_CHARACTER_NAME_CHANGED, function(_, unitTag)
        if unitTag == "reticleover" then
            refresh()
        end
    end)
    register(namespace, EVENT_PLAYER_ACTIVATED, refresh)

    -- A target can already be under the reticle when the addon loads, and some
    -- clients do not fire the reticle event for it; one cheap check per second
    -- also keeps the marker in sync when a name or icon changes elsewhere.
    EVENT_MANAGER:RegisterForUpdate(namespace, 1000, refresh)
end
