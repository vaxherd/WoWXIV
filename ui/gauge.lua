local _, WoWXIV = ...
WoWXIV.UI = WoWXIV.UI or {}
local UI = WoWXIV.UI

local class = WoWXIV.class
UI.Gauge = class()

------------------------------------------------------------------------

local Gauge = UI.Gauge

function Gauge:__constructor(parent, width)
    self.width = width
    self.show_value = false
    self.show_overshield = false

    self.max = 1
    self.cur = 1
    self.shield = 0

    local f = CreateFrame("Frame", nil, parent)
    self.frame = f
    f:SetSize(width+10, 30)

    local box_l = f:CreateTexture(nil, "BORDER")
    self.box_l = box_l
    box_l:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -2)
    box_l:SetSize(6, 15)
    box_l:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    box_l:SetTexCoord(0/256.0, 6/256.0, 11/256.0, 26/256.0)
    local box_c = f:CreateTexture(nil, "BORDER")
    self.box_c = box_c
    box_c:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -2)
    box_c:SetSize(width-2, 15)
    box_c:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    box_c:SetTexCoord(6/256.0, 90/256.0, 11/256.0, 26/256.0)
    local box_r = f:CreateTexture(nil, "BORDER")
    self.box_r = box_r
    box_r:SetPoint("TOPLEFT", f, "TOPLEFT", width+4, -2)
    box_r:SetSize(6, 15)
    box_r:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    box_r:SetTexCoord(90/256.0, 96/256.0, 11/256.0, 26/256.0)

    local bar_bg = f:CreateTexture(nil, "BORDER")
    self.bar_bg = bar_bg
    bar_bg:SetPoint("TOPLEFT", f, "TOPLEFT", 5, -7)
    bar_bg:SetSize(width, 5)
    bar_bg:SetColorTexture(0, 0, 0)

    local bar = f:CreateTexture(nil, "ARTWORK", nil, 0)
    self.bar = bar
    bar:SetPoint("TOPLEFT", f, "TOPLEFT", 5, -7)
    bar:SetSize(width, 5)
    bar:SetColorTexture(1, 1, 1)

    local absorbbar = f:CreateTexture(nil, "ARTWORK", nil, -1)
    self.absorbbar = absorbbar
    absorbbar:SetPoint("TOPLEFT", f, "TOPLEFT", 5, -7)
    absorbbar:SetSize(width, 5)
    absorbbar:SetColorTexture(0.5, 0.5, 0.5)

    local shieldbar = f:CreateTexture(nil, "ARTWORK", nil, -2)
    self.shieldbar = shieldbar
    shieldbar:SetPoint("TOPLEFT", f, "TOPLEFT", 5, -7)
    shieldbar:SetSize(width, 5)
    shieldbar:SetColorTexture(1, 0.82, 0)

    local overshield_l = f:CreateTexture(nil, "OVERLAY")
    self.overshield_l = overshield_l
    overshield_l:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    overshield_l:SetSize(5, 7)
    overshield_l:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    overshield_l:SetTexCoord(0/256.0, 5/256.0, 28/256.0, 35/256.0)
    local overshield_c = f:CreateTexture(nil, "OVERLAY")
    self.overshield_c = overshield_c
    overshield_c:SetPoint("TOPLEFT", overshield_l, "TOPRIGHT")
    overshield_c:SetSize(width, 7)
    overshield_c:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    overshield_c:SetTexCoord(5/256.0, 91/256.0, 28/256.0, 35/256.0)
    local overshield_r = f:CreateTexture(nil, "OVERLAY")
    self.overshield_r = overshield_r
    overshield_r:SetPoint("TOPLEFT", overshield_c, "TOPRIGHT")
    overshield_r:SetSize(5, 7)
    overshield_r:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    overshield_r:SetTexCoord(91/256.0, 96/256.0, 28/256.0, 35/256.0)

    self.value = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.value:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -14)
    self.value:SetTextScale(1.3)
    if not self.show_value then
        self.value:Hide()
    end
end

function Gauge:Show()
    self.frame:Show()
end

function Gauge:Hide()
    self.frame:Hide()
end

function Gauge:SetAlpha(alpha)
    self.frame:SetAlpha(alpha)
end

function Gauge:SetPoint(...)
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

function Gauge:SetShowValue(show, on_top)
    self.show_value = show
    if show then
        self.value:ClearAllPoints()
        if on_top then
            self.value:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -3, 10)
        else
            self.value:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -3, -14)
        end
        self.value:Show()
    else
        self.value:Hide()
    end
end

function Gauge:SetValueScale(scale)
    self.value:SetTextScale(scale)
end

function Gauge:Update(max, cur, shield, heal_absorb)
    shield = shield or 0
    heal_absorb = heal_absorb or 0

    self.max = max
    self.cur = cur
    self.shield = shield
    self.heal_absorb = heal_absorb

    local bar_rel, absorb_rel, shield_rel, overshield_rel
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
    else
        bar_rel = 0
        shield_rel = 0
        overshield_rel = 0
        absorb_rel = 0
    end
    if not self.show_overshield then
        overshield_rel = 0
    end

    local width = self.width
    local bar_w = bar_rel * width
    local absorb_w = absorb_rel * width
    local shield_w = shield_rel * width
    local overshield_w = overshield_rel * width
    if overshield_w > width then overshield_w = width end

    if bar_w > 0 then
        self.bar:Show()
        self.bar:SetWidth(bar_w)
    else
        self.bar:Hide()
    end

    if absorb_w > bar_w then
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

    self.value:SetText(cur)
end
