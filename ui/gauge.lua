local _, WoWXIV = ...
WoWXIV.UI = WoWXIV.UI or {}
local UI = WoWXIV.UI

local class = WoWXIV.class
UI.Gauge = class()

local floor = math.floor
local strlen = string.len
local strsub = string.sub

------------------------------------------------------------------------

-- Formatting mode values for FormatNumber().
local VALUE_FORMAT_NONE = 0  -- Nothing special, just a string of digits.
local VALUE_FORMAT_ABBR = 1  -- Abbreviate to 3 significant figures.
local VALUE_FORMAT_SEP  = 2  -- Insert thousands separators.
local VALUE_FORMAT_FADE = 3  -- Fade low-order thousands groups.

-- Format a number into a string in the given mode (VALUE_FORMAT_*).
-- color is required for FADE mode and should be an RGB triple giving
-- the base text color.
local function FormatNumber(n, mode, color)
    local s = tostring(n)
    if mode == VALUE_FORMAT_NONE then
        -- Leave as is.
    elseif mode == VALUE_FORMAT_ABBR then
        local decimal = 0
        local unit = ""
        if strlen(s) >= 13 then
            decimal = 12
            unit = "T"
        elseif strlen(s) >= 10 then
            decimal = 9
            unit = "B"  -- More common than "G".
        elseif strlen(s) >= 7 then
            decimal = 6
            unit = "M"
        elseif strlen(s) >= 4 then
            decimal = 3
            unit = "K"
        end
        if decimal > 0 then
            local rem = strsub(s, -decimal)
            s = strsub(s, 1, -(decimal+1))
            if strlen(s) < 3 then
                s = s .. "." .. strsub(rem, 1, 3-strlen(s))
            end
            s = s .. unit
        end
    elseif mode == VALUE_FORMAT_SEP then
        for i = strlen(s)-3, 1, -3 do
            s = strsub(s, 1, i) .. "," .. strsub(s, i+1)
        end
    elseif mode == VALUE_FORMAT_FADE then
        local this_color = {}
        for i = strlen(s)-3, 1, -3 do
            local group_index = floor((i+2)/3)
            local scale = 1
            for j = 1, group_index do
                scale = scale * 0.8
            end
            this_color[1] = color[1] * scale
            this_color[2] = color[2] * scale
            this_color[3] = color[3] * scale
            s = (strsub(s, 1, i)
                 .. WoWXIV.FormatColoredText(strsub(s, i+1, i+3), this_color)
                 .. strsub(s, i+4))
        end
    end
    return s
end

------------------------------------------------------------------------

local Gauge = UI.Gauge

function Gauge:__constructor(parent, width)
    self.width = width
    self.show_value = false
    self.value_format = VALUE_FORMAT_NONE
    self.show_shield_value = false
    self.show_overshield = false

    local f = CreateFrame("Frame", nil, parent)
    self.frame = f
    f:SetSize(width+10, 30)

    local box_l = f:CreateTexture(nil, "BORDER")
    self.box_l = box_l
    box_l:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -2)
    box_l:SetSize(6, 15)
    WoWXIV.SetUITexture(box_l, 0, 6, 11, 26)
    local box_c = f:CreateTexture(nil, "BORDER")
    self.box_c = box_c
    box_c:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -2)
    box_c:SetSize(width-2, 15)
    WoWXIV.SetUITexture(box_c, 6, 90, 11, 26)
    local box_r = f:CreateTexture(nil, "BORDER")
    self.box_r = box_r
    box_r:SetPoint("TOPLEFT", f, "TOPLEFT", width+4, -2)
    box_r:SetSize(6, 15)
    WoWXIV.SetUITexture(box_r, 90, 96, 11, 26)

    local bar_bg = f:CreateTexture(nil, "BORDER")
    self.bar_bg = bar_bg
    bar_bg:SetPoint("TOPLEFT", f, "TOPLEFT", 5, -7)
    bar_bg:SetSize(width, 5)
    bar_bg:SetColorTexture(0, 0, 0)

    local lossbar = f:CreateTexture(nil, "ARTWORK", nil, -1)
    self.lossbar = lossbar
    lossbar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -7)
    lossbar:SetSize(width, 5)
    lossbar:SetColorTexture(1, 0, 0)

    local bar = f:CreateTexture(nil, "ARTWORK", nil, -2)
    self.bar = bar
    bar:SetPoint("TOPLEFT", f, "TOPLEFT", 5, -7)
    bar:SetSize(width, 5)
    bar:SetColorTexture(1, 1, 1)

    local addbar = f:CreateTexture(nil, "ARTWORK", nil, -3)
    self.addbar = addbar
    addbar:SetPoint("TOPLEFT", f, "TOPLEFT", 5, -7)
    addbar:SetSize(width, 5)
    addbar:SetColorTexture(0.25, 1, 0.25)

    local absorbbar = f:CreateTexture(nil, "ARTWORK", nil, -4)
    self.absorbbar = absorbbar
    absorbbar:SetPoint("TOPLEFT", f, "TOPLEFT", 5, -7)
    absorbbar:SetSize(width, 5)
    absorbbar:SetColorTexture(0.5, 0.5, 0.5)

    local shieldbar = f:CreateTexture(nil, "ARTWORK", nil, -5)
    self.shieldbar = shieldbar
    shieldbar:SetPoint("TOPLEFT", f, "TOPLEFT", 5, -7)
    shieldbar:SetSize(width, 5)
    shieldbar:SetColorTexture(1, 0.82, 0)

    local overshield_l = f:CreateTexture(nil, "OVERLAY")
    self.overshield_l = overshield_l
    overshield_l:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    overshield_l:SetSize(5, 7)
    WoWXIV.SetUITexture(overshield_l, 0, 5, 28, 35)
    local overshield_c = f:CreateTexture(nil, "OVERLAY")
    self.overshield_c = overshield_c
    overshield_c:SetPoint("TOPLEFT", overshield_l, "TOPRIGHT")
    overshield_c:SetSize(width, 7)
    WoWXIV.SetUITexture(overshield_c, 5, 91, 28, 35)
    local overshield_r = f:CreateTexture(nil, "OVERLAY")
    self.overshield_r = overshield_r
    overshield_r:SetPoint("TOPLEFT", overshield_c, "TOPRIGHT")
    overshield_r:SetSize(5, 7)
    WoWXIV.SetUITexture(overshield_r, 91, 96, 28, 35)

    self.value = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.value:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -13.5)
    self.value:SetTextScale(1.25)
    if not self.show_value then
        self.value:Hide()
    end
end

-- For use by cast bar interruptible effect.
function Gauge:GetBoxTexture()
    return self.box_c
end

-- For use by target bar (for auto-setting name width)
function Gauge:GetValueObject()
    return self.value
end

function Gauge:Show()
    self.frame:Show()
end

function Gauge:Hide()
    self.frame:Hide()
end

function Gauge:SetShown(shown)
    self.frame:SetShown(shown)
end

function Gauge:GetFrameLevel()
    return self.frame:GetFrameLevel()
end

function Gauge:SetFrameLevel(level)
    self.frame:SetFrameLevel(level)
end

function Gauge:SetAlpha(alpha)
    self.frame:SetAlpha(alpha)
end

function Gauge:SetSinglePoint(...)
    self.frame:ClearAllPoints()
    self.frame:SetPoint(...)
end

function Gauge:SetBoxColor(r, g, b)
    self.box_l:SetVertexColor(r, g, b)
    self.box_c:SetVertexColor(r, g, b)
    self.box_r:SetVertexColor(r, g, b)
end

function Gauge:SetBarBackgroundColor(r, g, b)
    self.bar_bg:SetColorTexture(r, g, b)
end

function Gauge:SetBarColor(r, g, b)
    self.bar:SetColorTexture(r, g, b)
    self.absorbbar:SetColorTexture(r/2, g/2, b/2)
    self.value:SetTextColor(r, g, b)
end

function Gauge:SetShowOvershield(show)
     self.show_overshield = show
end

-- Set whether the numeric value of the gauge is is shown.
--
-- Parameters:
--     show: True to show the value, false to not show it.  If false, all
--         other parameters are ignored.
--     on_top: True to show the value on top of the bar, false to show the
--         value below the bar.
--     format_mode: One of the following formatting mode codes:
--         - "none" (or nil): No formatting, just display a string of digits.
--         - "abbr": Abbreviate the value to 3 significant digits and a
--               scale unit (K/M/B/T).  Truncated digits are rounded down.
--         - "sep": Insert comma separators between thousands groups.
--         - "fade": Fade out low-order thousands groups.
function Gauge:SetShowValue(show, on_top, format_mode)
    self.show_value = show
    if not format_mode or format_mode == "none" then
        self.value_format = VALUE_FORMAT_NONE
    elseif format_mode == "abbr" then
        self.value_format = VALUE_FORMAT_ABBR
    elseif format_mode == "sep" then
        self.value_format = VALUE_FORMAT_SEP
    elseif format_mode == "fade" then
        self.value_format = VALUE_FORMAT_FADE
    else
        error("Invalid formatting mode: " .. format_mode)
    end
    if show then
        self.value:ClearAllPoints()
        if on_top then
            self.value:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -3, 8.5)
        else
            self.value:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -3, -13.5)
        end
        self.value:Show()
    else
        self.value:Hide()
    end
end

function Gauge:SetShowShieldValue(show)
    self.show_shield_value = show
end

function Gauge:SetValueScale(scale)
    self.value:SetTextScale(scale)
end

function Gauge:Update(max, cur, true_max, shield, heal_absorb)
    true_max = (true_max and true_max > 0) and true_max or max
    shield = shield or 0
    heal_absorb = heal_absorb or 0

    local bar_rel, add_rel, absorb_rel, loss_rel, shield_rel, overshield_rel
    if max > 0 then
        bar_rel = (cur - heal_absorb) / max
        if bar_rel < 0 then bar_rel = 0 end
        absorb_rel = cur / max
        shield_rel = (cur + shield) / max
        if shield_rel > 1 then
            overshield_rel = shield_rel - 1
            shield_rel = 1
        else
            overshield_rel = 0
        end
        if cur - heal_absorb > true_max then
            add_rel = bar_rel
            bar_rel = true_max / max
        else
            add_rel = 0
        end
        if max < true_max then
            loss_rel = 1 - (max / true_max)
            if loss_rel > 0.95 then loss_rel = 0.95 end
            local max_scale = 1 - loss_rel
            bar_rel = bar_rel * max_scale
            absorb_rel = absorb_rel * max_scale
            shield_rel = shield_rel * max_scale
        else
            loss_rel = 0
        end
    else
        loss_rel = 0
        bar_rel = 0
        add_rel = 0
        absorb_rel = 0
        shield_rel = 0
        overshield_rel = 0
    end
    if not self.show_overshield then
        overshield_rel = 0
    end

    local width = self.width
    local bar_w = bar_rel * width
    local add_w = add_rel * width
    local absorb_w = absorb_rel * width
    local loss_w = loss_rel * width
    local shield_w = shield_rel * width
    local overshield_w = overshield_rel * width
    if overshield_w > width then overshield_w = width end

    if loss_w > 0 then
        self.lossbar:Show()
        self.lossbar:SetWidth(loss_w)
    else
        self.lossbar:Hide()
    end

    if bar_w > 0 then
        self.bar:Show()
        self.bar:SetWidth(bar_w)
    else
        self.bar:Hide()
    end

    if add_w > bar_w then
        self.addbar:Show()
        self.addbar:SetWidth(add_w)
    else
        self.addbar:Hide()
    end

    if absorb_w > add_w then
        self.absorbbar:Show()
        self.absorbbar:SetWidth(absorb_w)
    else
        self.absorbbar:Hide()
    end

    if shield_w > absorb_w then
        self.shieldbar:Show()
        self.shieldbar:SetWidth(shield_w)
    else
        self.shieldbar:Hide()
    end

    if overshield_w > 0 then
        self.overshield_l:Show()
        self.overshield_c:Show()
        self.overshield_c:SetWidth(overshield_w)
        self.overshield_c:SetTexCoord(5/256.0, (5+overshield_w)/256.0, 28/256.0, 35/256.0)
        self.overshield_r:Show()
    else
        self.overshield_l:Hide()
        self.overshield_c:Hide()
        self.overshield_r:Hide()
    end

    local format = self.value_format
    local color = {self.value:GetTextColor()}
    local value_text = FormatNumber(cur, format, color)
    if self.show_shield_value and shield > 0 then
        value_text = value_text .. "+" .. FormatNumber(shield, format, color)
    end
    self.value:SetText(value_text)
end
