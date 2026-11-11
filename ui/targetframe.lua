--[[
    I remember you! -- stable name in the reticle target frame.

    Variant 2: only reticleover / reticleovertarget are touched. Group frames,
    nameplates and every other unit frame keep the game's own naming.

    The hooks are post-hooks, so the game computes everything first (including
    the difficulty icon and the target marker). We then replace just the name
    text, rebuilding the same icon wrappers around our stable name.
]]

local TargetFrame = {}
IRY.TargetFrame = TargetFrame

local TARGET_TAGS = {
    reticleover = true,
    reticleovertarget = true,
}

local function settings()
    return IRY.Store:GetSettings() or {}
end

local function stableName(unitTag)
    local id = IRY.Resolver:ForUnit(unitTag)
    if not id then
        return nil
    end
    return IRY.Resolver:DisplayName(id)
end

local function withDifficultyIcon(unitTag, text)
    if not GetUnitOverlandDifficulty then
        return text
    end

    local difficulty = GetUnitOverlandDifficulty(unitTag) or 0
    if difficulty <= OVERLAND_DIFFICULTY_TYPE_BASEGAME then
        return text
    end
    if GetOverlandDifficultyDisabledReason() ~= OVERLAND_DIFFICULTY_DISABLED_REASON_NONE then
        return text
    end

    local iconPath = ZO_CHALLENGE_DIFFICULTY_ICONS_GAMEPAD[difficulty]
    if not iconPath then
        return text
    end

    return zo_iconTextFormatNoSpaceAlignedRight(iconPath, "115%", "115%", text)
end

local function withTargetMarker(frame, unitTag, text)
    local markerType = GetUnitTargetMarkerType(unitTag)
    if markerType == TARGET_MARKER_TYPE_NONE then
        return text
    end

    local iconPath = ZO_GetPlatformTargetMarkerIcon(markerType)
    if not iconPath then
        return text
    end

    if frame.style == TARGET_UNIT_FRAME then
        return zo_iconTextFormatNoSpaceAlignedRight(iconPath, "100%", "100%", text)
    end
    return zo_iconTextFormatNoSpace(iconPath, "100%", "100%", text)
end

local function unitTagOf(frame)
    local unitTag = frame.unitTag or (frame.GetUnitTag and frame:GetUnitTag())
    if not unitTag or not TARGET_TAGS[unitTag] then
        return nil
    end
    if not DoesUnitExist(unitTag) or not IsUnitPlayer(unitTag) then
        return nil
    end
    return unitTag
end

function TargetFrame:ApplyName(frame)
    if not settings().replaceTargetName then
        return
    end

    local unitTag = unitTagOf(frame)
    if not unitTag then
        return
    end

    local name = stableName(unitTag)
    if not name or name == "" then
        return
    end

    local label = frame.nameLabel
    if not label then
        return
    end

    local text = withDifficultyIcon(unitTag, name)
    text = withTargetMarker(frame, unitTag, text)

    label:SetText(text)
end

function TargetFrame:ApplyCaption(frame)
    local unitTag = unitTagOf(frame)
    if not unitTag then
        return
    end

    local label = frame.captionLabel
    if not label then
        return
    end

    local current = settings()

    if current.hideTargetCaption then
        label:SetHidden(true)
        label:SetText("")
        return
    end

    if not current.replaceTargetCaption then
        return
    end

    -- Character name plus title, and nothing else: the @account already
    -- appears in the name line in its stable form.
    local character = GetUnitName(unitTag)
    if not character or character == "" then
        return
    end

    local title = GetUnitTitle and GetUnitTitle(unitTag) or ""
    local caption

    if title ~= "" then
        caption = zo_strformat(SI_PLAYER_NAME_WITH_TITLE_FORMAT,
            ZO_FormatUserFacingCharacterName(character), title)
    else
        caption = ZO_FormatUserFacingCharacterName(character)
    end

    label:SetHidden(caption == "")
    label:SetText(caption)
end

-- Called after the store changed (rename, merge, undo). The game would refresh
-- on its next target change anyway; this just makes it immediate.
function TargetFrame:Refresh()
    if not ZO_UnitFrames_UpdateWindow or not UnitFrames then
        return
    end

    ZO_UnitFrames_UpdateWindow("reticleover", true)

    if DoesUnitExist("reticleovertarget") then
        ZO_UnitFrames_UpdateWindow("reticleovertarget", true)
    end
end

local function safeApply(fn, frame)
    local ok, err = pcall(fn, TargetFrame, frame)
    if not ok then
        IRY:Debug("target frame hook: " .. tostring(err))
    end
end

function TargetFrame:Initialize()
    ZO_PostHook(ZO_UnitFrameObject, "UpdateName", function(frame)
        safeApply(TargetFrame.ApplyName, frame)
    end)

    ZO_PostHook(ZO_UnitFrameObject, "UpdateCaption", function(frame)
        safeApply(TargetFrame.ApplyCaption, frame)
    end)
end
