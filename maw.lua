local WoWXIV = WoWXIV
WoWXIV.JailerEyeUI = {}

-- Blizzard UI reference: Blizzard_UIWidgetTemplateDiscreteProgressSteps.lua

-- Retrieve the current Eye of the Jailer state.  Returns table with fields:
--    numSteps: number of discrete steps (5)
--    progressMax: maximum number of points (5000)
--    progressMin: initial number of points (0)
--    progressVal: current number of points (only valid when UI visible)
--    shownState: 1 if shown, 0 if hidden
--    tooltip: tooltip text (use GameTooltip:SetText(...,NORMAL_FONT_COLOR))
-- plus various others not relevant to us.  Unknown whether this always
-- returns a value or if it can return nil in some cases.
local function GetJailerEyeState()
    -- 2885 is the widget ID of the Eye of the Jailer UI (presumably a
    -- C-side rather than Lua-side constant since it doesn't show up in
    -- the Blizzard UI code anywhere).
    return C_UIWidgetManager.GetDiscreteProgressStepsVisualizationInfo(2885)
end

local STEP_COLORS = {
    {0.1, 0.1, 1},  -- level 0: blue (no threat)
    {0.1, 0.3, 1},  -- level 1: sky blue (soulseeker aggro)
    {0.3, 1, 1},    -- level 2: cyan (bombardment)
    {1, 1, 0.1},    -- level 3: yellow (assassins)
    {1, 0.5, 0},    -- level 4: orange (abductors)
    {1, 0, 0},      -- level 5: red (extermination)
}

------------------------------------------------------------------------

local JailerEye = {}
JailerEye.__index = JailerEye

function JailerEye:New()
    local new = {}
    setmetatable(new, self)
    new.__index = self

    self.shown = false

    local f = CreateFrame("Frame", "WoWXIV_JailerEye", UIParent)
    new.frame = f
    f:Hide()
    f:SetSize(200, 44)
    f:SetPoint("BOTTOM", UIParent, "BOTTOM", 500, 20)

    local title = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    title:SetTextScale(1.5)
    title:SetText("Eye of the Jailer")

    local gauge = WoWXIV.UI.Gauge:New(f, f:GetWidth())
    new.gauge = gauge
    gauge:SetPoint("TOP", f, "TOP", 0, -15)
    gauge:SetBoxColor(1, 1, 1)
    gauge:SetBarBackgroundColor(0, 0, 0)

    local level = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    new.level = level
    level:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    level:SetTextScale(1.2)

    local points = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    new.points = points
    points:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    points:SetTextScale(1.1)

    f:SetScript("OnEnter", function() new:OnEnter() end)
    f:SetScript("OnLeave", function() new:OnLeave() end)
    -- It's unclear whether there's a specific event that fires when you
    -- gain Eye threat, so instead we take the lazy route and just check
    -- every frame while in the Maw.  (UPDATE_UI_WIDGET might work?)
    f:RegisterEvent("ZONE_CHANGED")
    f:SetScript("OnEvent", function(self, event, arg1, ...)
        new:OnUpdate()
        local state = GetJailerEyeState()
        if state and state.shownState == 1 then
            f:SetScript("OnUpdate", function() new:OnUpdate() end)
        else
            f:SetScript("OnUpdate", nil)
        end
    end)
    new:OnUpdate()
end

function JailerEye:OnEnter()
    if GameTooltip:IsForbidden() then return end
    if not self.frame:IsVisible() then return end
    GameTooltip:SetOwner(self.frame, self.tooltip_anchor)
    self:UpdateTooltip(true)
end

function JailerEye:OnLeave()
    if GameTooltip:IsForbidden() then return end
    GameTooltip:Hide()
end

function JailerEye:UpdateTooltip(tooltip, show_now)
    if GameTooltip:IsForbidden() then return end
    if GameTooltip:GetOwner() == self.frame then
        if show_now and self.shown then
            GameTooltip:Show()
        end
        if GameTooltip:IsShown() then
            if self.shown and tooltip then
                GameTooltip:SetText(tooltip, NORMAL_FONT_COLOR:GetRGB())
            else
                GameTooltip:Hide()
            end
        end
    end
end

function JailerEye:OnUpdate()
    local state = GetJailerEyeState()
    if not (state and state.shownState == 1) then
        self.frame:Hide()
        self.shown = false
        self:UpdateTooltip(nil)
        return
    end

    local steps = state.numSteps
    local min = state.progressMin
    local max = state.progressMax
    local cur = state.progressVal
    -- Sanity checks
    if max <= min then
        self.gauge:Update(1, 0, 0)
        return
    end
    if cur < min then cur = min end
    if cur > max then cur = max end

    local level, level_max, level_cur
    if cur == max then
        level = steps
        level_max = max - math.floor((max - min) * (steps-1) / steps)
        level_cur = level_max
    else
        level = math.floor(steps * (cur - min) / (max - min))
        local level_base = math.floor((max - min) * level / steps)
        level_max = math.floor((max - min) * (level+1) / steps) - level_base
        level_cur = cur - level_base
    end
    self.gauge:SetBarColor(unpack(STEP_COLORS[level+1]))
    self.gauge:Update(level_max, level_cur)
    self.level:SetText(string.format("Level %d", level))
    self.points:SetText(string.format("%d/%d", level_cur, level_max))

    if not self.shown then
        self.frame:Show()
        self.shown = true
    end
    self:UpdateTooltip(state.tooltip)
end

------------------------------------------------------------------------

function WoWXIV.JailerEyeUI.Create()
    WoWXIV.JailerEyeUI.ui = JailerEye:New()
    -- We can't use WoWXIV.HideBlizzardFrame() because this frame is
    -- used for multiple purposes, and (for now) we only want to hide
    -- it when it's used for the Eye of the Jailer UI.
    local frame = UIWidgetTopCenterContainerFrame
    local state = GetJailerEyeState()
    if state and state.shownState == 1 then
        frame:Hide()
    end
    hooksecurefunc(frame, "Show", function(frame)
        local state = GetJailerEyeState()
        if state and state.shownState == 1 then
            frame:Hide()
        end
    end)
    hooksecurefunc(frame, "SetShown", function(frame, shown)
        local state = GetJailerEyeState()
        if state and state.shownState == 1 then
            if shown then frame:Hide() end
        end
    end)
end
