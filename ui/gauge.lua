local WoWXIV = WoWXIV
WoWXIV.UI = WoWXIV.UI or {}
local UI = WoWXIV.UI
UI.Gauge = {}

-- FIXME: color notes
--    hp: 6ab9e3/15577b/07294e bar=ffffff text=ffffff
--    shield: b26d00 bar=ffd100
--    enemy: 888888/202020 bar=ffffff
--    target_enemy: ff9a9a/744159/4d1818 bar=ffc0c2 text=ffc0c2
--    target_neutral: ecd98e/524820/302a13 bar=fff8b4 text=fff8b4
--    target_ally: bfea9a/577b3a/263618 bar=edffe7 text=edffe7
--    target_player: 95daff/306294/152a3f bar=e9fffe text=e9fffe
--    target_object: 8e8e8e/1d1f1e bar=ffffff text=ffffff
--    cast: f8aa00/76590d bar=ffffff text=ffffff

------------------------------------------------------------------------

local Gauge = UI.Gauge
Gauge.__index = Gauge

function Gauge:New(parent, width)
    local new = {}
    setmetatable(new, self)
    new.__index = self

    new.width = width
    new.show_value = false
    new.show_overshield = false

    new.max = 1
    new.cur = 1
    new.shield = 0

    local f = CreateFrame("Frame", nil, parent)
    new.frame = f
    f:SetSize(width+10, 30)

    local box_l = f:CreateTexture(nil, "BORDER")
    new.box_l = box_l
    box_l:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -2)
    box_l:SetSize(6, 15)
    box_l:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    box_l:SetTexCoord(0/256.0, 6/256.0, 11/256.0, 26/256.0)
    local box_c = f:CreateTexture(nil, "BORDER")
    new.box_c = box_c
    box_c:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -2)
    box_c:SetSize(width-2, 15)
    box_c:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    box_c:SetTexCoord(6/256.0, 90/256.0, 11/256.0, 26/256.0)
    local box_r = f:CreateTexture(nil, "BORDER")
    new.box_r = box_r
    box_r:SetPoint("TOPLEFT", f, "TOPLEFT", width+4, -2)
    box_r:SetSize(6, 15)
    box_r:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    box_r:SetTexCoord(90/256.0, 96/256.0, 11/256.0, 26/256.0)

    local bar_bg = f:CreateTexture(nil, "BORDER")
    new.bar_bg = bar_bg
    bar_bg:SetPoint("TOPLEFT", f, "TOPLEFT", 5, -7)
    bar_bg:SetSize(width, 5)
    bar_bg:SetColorTexture(0, 0, 0)

    local shieldbar = f:CreateTexture(nil, "ARTWORK")  -- goes under main bar
    new.shieldbar = shieldbar
    shieldbar:SetPoint("TOPLEFT", f, "TOPLEFT", 5, -7)
    shieldbar:SetSize(width, 5)
    shieldbar:SetColorTexture(1, 0.82, 0)

    local bar = f:CreateTexture(nil, "OVERLAY")
    new.bar = bar
    bar:SetPoint("TOPLEFT", f, "TOPLEFT", 5, -7)
    bar:SetSize(width, 5)
    bar:SetColorTexture(1, 1, 1)

    local overshield_l = f:CreateTexture(nil, "OVERLAY")
    new.overshield_l = overshield_l
    overshield_l:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    overshield_l:SetSize(5, 7)
    overshield_l:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    overshield_l:SetTexCoord(0/256.0, 5/256.0, 43/256.0, 50/256.0)
    local overshield_c = f:CreateTexture(nil, "OVERLAY")
    new.overshield_c = overshield_c
    overshield_c:SetPoint("TOPLEFT", f, "TOPLEFT", 5, 0)
    overshield_c:SetSize(width, 7)
    overshield_c:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    overshield_c:SetTexCoord(5/256.0, 91/256.0, 43/256.0, 50/256.0)
    local overshield_r = f:CreateTexture(nil, "OVERLAY")
    new.overshield_r = overshield_r
    overshield_r:SetPoint("TOPLEFT", f, "TOPLEFT", 91, 0)
    overshield_r:SetSize(5, 7)
    overshield_r:SetHeight(7)
    overshield_r:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    overshield_r:SetTexCoord(91/256.0, 96/256.0, 43/256.0, 50/256.0)

    new.value = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    new.value:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -13)
    new.value:SetText("1")
    if not self.show_value then
        new.value:Hide()
    end

    return new
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
    self.value:SetTextColor(r, g, b)
end

function Gauge:SetShowOvershield(show)
     self.show_overshield = show
end

function Gauge:SetShowValue(show)
    self.show_value = show
    if show then
        self.value:Show()
    else
        self.value:Hide()
    end
end

function Gauge:SetValueScale(scale)
    self.value:SetTextScale(scale)
end

function Gauge:Update(max, cur, shield)
    self.max = max
    self.cur = cur
    self.shield = shield

    local bar_rel, shield_rel, overshield_rel
    if max > 0 then
        bar_rel = cur / max
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
    end
    if not self.show_overshield then
        overshield_rel = 0
    end

    local width = self.width
    local bar_w = bar_rel * width
    if bar_w == 0 then bar_w = 0.001 end  --  WoW can't deal with 0 width
    local shield_w = shield_rel * width
    local overshield_w = overshield_rel * width
    if overshield_w > 1 then overshield_w = 1 end

    self.bar:SetWidth(bar_w)

    if shield_w > bar_w then
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
