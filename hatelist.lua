local WoWXIV = WoWXIV
WoWXIV.HateList = {}

--------------------------------------------------------------------------

local Gauge = {}
Gauge.__index = Gauge

function Gauge:New(parent)
    local new = {}
    setmetatable(new, self)
    new.__index = self

    new.max = 1
    new.cur = 1
    new.shield = 0

    new.frame = CreateFrame("Frame", nil, parent)
    local f = new.frame
    f:SetWidth(62)
    f:SetHeight(30)

    local box = f:CreateTexture(nil, "BORDER")
    box:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -3)
    box:SetWidth(96)
    box:SetHeight(13)
    box:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    box:SetTexCoord(0/256.0, 96/256.0, 12/256.0, 25/256.0)

    new.shieldbar = f:CreateTexture(nil, "ARTWORK")  -- goes under main bar
    new.shieldbar:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -7)
    new.shieldbar:SetWidth(86)
    new.shieldbar:SetHeight(5)
    new.shieldbar:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    new.shieldbar:SetTexCoord(5/256.0, 91/256.0, 35/256.0, 40/256.0)

    new.bar = f:CreateTexture(nil, "OVERLAY")
    new.bar:SetPoint("TOPLEFT", f, "TOPLEFT", 5, -7)
    new.bar:SetWidth(86)
    new.bar:SetHeight(5)
    new.bar:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    new.bar:SetTexCoord(5/256.0, 91/256.0, 27/256.0, 32/256.0)

    new.overshield_l = f:CreateTexture(nil, "OVERLAY")
    new.overshield_l:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    new.overshield_l:SetWidth(5)
    new.overshield_l:SetHeight(7)
    new.overshield_l:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    new.overshield_l:SetTexCoord(0/256.0, 5/256.0, 43/256.0, 50/256.0)
    new.overshield_c = f:CreateTexture(nil, "OVERLAY")
    new.overshield_c:SetPoint("TOPLEFT", f, "TOPLEFT", 5, 0)
    new.overshield_c:SetWidth(86)
    new.overshield_c:SetHeight(7)
    new.overshield_c:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    new.overshield_c:SetTexCoord(5/256.0, 91/256.0, 43/256.0, 50/256.0)
    new.overshield_r = f:CreateTexture(nil, "OVERLAY")
    new.overshield_r:SetPoint("TOPLEFT", f, "TOPLEFT", 91, 0)
    new.overshield_r:SetWidth(5)
    new.overshield_r:SetHeight(7)
    new.overshield_r:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    new.overshield_r:SetTexCoord(91/256.0, 96/256.0, 43/256.0, 50/256.0)

    new.value = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    new.value:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -13)
    new.value:SetTextScale(1.3)
    new.value:SetText("1")

    return new
end

function Gauge:Update(max, cur, shield)
    self.max = max
    self.cur = cur
    self.shield = shield

    local bar_rel = cur / max
    local shield_rel = (cur + shield) / max
    local overshield_rel
    if shield_rel > 1 then
        overshield_rel = shield_rel - 1
        shield_rel = 1
    else
        overshield_rel = 0
    end

    local SIZE = 88
    local bar_w = bar_rel * SIZE
    local shield_w = shield_rel * SIZE
    local overshield_w = overshield_rel * SIZE

    self.bar:SetWidth(bar_w)
    self.bar:SetTexCoord(4/256.0, (4+bar_w)/256.0, 27/256.0, 32/256.0)

    if shield_w > bar_w then
        self.shieldbar:Show()
        self.shieldbar:SetTexCoord(4/256.0, (4+shield_w)/256.0, 35/256.0, 40/256.0)
    else
        self.shieldbar:Hide()
    end

    if overshield_w > 0 then
        self.overshield_l:Show()
        self.overshield_c:Show()
        self.overshield_c:SetWidth(overshield_w)
        self.overshield_c:SetTexCoord(4/256.0, (4+overshield_w)/256.0, 43/256.0, 50/256.0)
        self.overshield_r:Show()
    else
        self.overshield_l:Hide()
        self.overshield_c:Hide()
        self.overshield_r:Hide()
    end

    self.value:SetText(cur)
end

--------------------------------------------------------------------------

local Enemy = {}
Enemy.__index = Enemy

-- See note on Update() for why we need rel_id
function Enemy:New(parent, unit, rel_id)
    local new = {}
    setmetatable(new, self)
    new.__index = self

    new.unit = unit

    new.frame = CreateFrame("Frame", nil, parent)
    local f = new.frame
    f:SetWidth(256)
    f:SetHeight(30)

    new.hate_icon = f:CreateTexture(nil, "ARTWORK")
    new.hate_icon:SetPoint("TOPLEFT", f, "TOPLEFT")
    new.hate_icon:SetWidth(19)
    new.hate_icon:SetHeight(19)
    new.hate_icon:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")

    new.name = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    new.name:SetPoint("TOPLEFT", f, "TOPLEFT", 23, -1)
    new.name:SetTextScale(1.1)
    new.name:SetText(select(1, UnitName(rel_id)))

    local box = f:CreateTexture(nil, "BORDER")
    box:SetPoint("TOPLEFT", f, "TOPLEFT", 19, -13)
    box:SetWidth(62)
    box:SetHeight(13)
    box:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    box:SetTexCoord(0/256.0, 62/256.0, 54/256.0, 67/256.0)

    new.shieldbar = f:CreateTexture(nil, "ARTWORK")  -- goes under main bar
    new.shieldbar:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -17)
    new.shieldbar:SetWidth(52)
    new.shieldbar:SetHeight(5)
    new.shieldbar:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    new.shieldbar:SetTexCoord(5/256.0, 57/256.0, 35/256.0, 40/256.0)

    new.bar = f:CreateTexture(nil, "OVERLAY")
    new.bar:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -17)
    new.bar:SetWidth(52)
    new.bar:SetHeight(5)
    new.bar:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    new.bar:SetTexCoord(5/256.0, 57/256.0, 27/256.0, 32/256.0)

    new:Update(rel_id, false)
    return new
end

-- FIXME: We have to pass a relative unit name here because some (all?) of
-- the unit functions don't work with GUIDs.
function Enemy:Update(rel_id, updateName)
    if updateName then
        self.name.setText(UnitName(rel_unit))
    end

    local is_target, _, _, hate = UnitDetailedThreatSituation("player", rel_id)
    if not hate then hate = 0 end
    local hate_level
    if is_target then
        hate_level = 3
    elseif hate >= 100 then
        hate_level = 2
    elseif hate >= 50 then
        hate_level = 1
    else
        hate_level = 0
    end
    self.hate_icon:SetTexCoord((hate_level*20)/256.0, (hate_level*20+19)/256.0,
                               68/256.0, 87/256.0)

    local hp = UnitHealth(rel_id)
    local hpmax = UnitHealthMax(rel_id)
    local shield = UnitGetTotalAbsorbs(rel_id)
    local hp_rel = hp / hpmax
    local shield_rel = (hp + shield) / hpmax
    local SIZE = 52
    local bar_w = hp_rel * SIZE
    if bar_w == 0 then bar_w = 0.001 end  --  WoW can't deal with 0 width
    local shield_w = shield_rel * SIZE
    if shield_w > 1 then
        shield_w = 1
    end
    self.bar:SetWidth(bar_w)
    self.bar:SetTexCoord(4/256.0, (4+bar_w)/256.0, 27/256.0, 32/256.0)
    if shield_w > bar_w then
        self.shieldbar:Show()
        self.shieldbar:SetTexCoord(5/256.0, (5+shield_w)/256.0, 35/256.0, 40/256.0)
    else
        self.shieldbar:Hide()
    end
end

function Enemy:Delete()
    WoWXIV.DestroyFrame(self.frame)
end

---------------------------------------------------------------------------

-- Create the global hate list object.
function WoWXIV.HateList.Create()
    local f = WoWXIV.CreateEventFrame("WoWXIV_HateList", UIParent)
    f:Hide()
    f:SetPoint("TOPLEFT", 30, -720)
    f:SetWidth(200)
    f:SetHeight(30)
    
    f.units = {}
    
    f.bg_t = f:CreateTexture(nil, "BACKGROUND")
    f.bg_t:SetPoint("TOP", f)
    f.bg_t:SetWidth(f:GetWidth())
    f.bg_t:SetHeight(4)
    f.bg_t:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    f.bg_t:SetTexCoord(0, 1, 0/256.0, 4/256.0)
    f.bg_c = f:CreateTexture(nil, "BACKGROUND")
    f.bg_c:SetPoint("CENTER", f)
    f.bg_c:SetWidth(f:GetWidth())
    f.bg_c:SetHeight(f:GetHeight()-8)
    f.bg_c:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    f.bg_c:SetTexCoord(0, 1, 4/256.0, 7/256.0)
    f.bg_b = f:CreateTexture(nil, "BACKGROUND")
    f.bg_b:SetPoint("BOTTOM", f)
    f.bg_b:SetWidth(f:GetWidth())
    f.bg_b:SetHeight(4)
    f.bg_b:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    f.bg_b:SetTexCoord(0, 1, 7/256.0, 11/256.0)
    
    f:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")
    function f:UNIT_ABSORB_AMOUNT_CHANGED(unit)
        f:Update(unit, false)
    end
    
    f:RegisterEvent("UNIT_HEALTH")
    function f:UNIT_HEALTH(unit)
        f:Update(unit, false)
    end
    
    f:RegisterEvent("UNIT_NAME_UPDATE")
    function f:UNIT_NAME_UPDATE(unit)
        f:Update(unit, true)
    end
    
    f:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
    function f:UNIT_THREAT_LIST_UPDATE(unit)
        f:Update(unit)
    end
    
    function f:Update(unit, updateName)
        local unit_id = UnitGUID(unit)
        local is_enemy = UnitIsEnemy("player", unit)
        if not is_enemy then
            -- UnitIsEnemy() seems to return false for factionally neutral
            -- characters even if they currently have threat on you, so we
            -- need to explicitly check threat as well.
            -- Also note that UnitDetailedThreatSituation() only seems to work
            -- with relative names ("target", "nameplateN") and not GUIDs.
            local threat = select(5, UnitDetailedThreatSituation("player", unit))
            if threat and threat > 0 then
                is_enemy = true
            end
        end
        if not unit_id or not is_enemy then
            return
        end
    
        local resize_list = false
        local index = 0
        for i, enemy in ipairs(self.units) do
            if enemy.unit == unit_id then
                index = i
                break
            end
        end
        if index == 0 then
            if UnitIsDead(unit) then
                return
            end
            table.insert(self.units, Enemy:New(f, unit_id, unit))
            index = #self.units
            resize_list = true
        end
    
        if UnitIsDead(unit) then
            self.units[index]:Delete()
            table.remove(self.units, index)
            resize_list = true
        else
            self.units[index]:Update(unit, updateName)
        end
    
        if resize_list then
            local count = #self.units
            if count == 0 then
                f:Hide()
            else
                f:SetHeight(30*count + 2)
                f.bg_c:SetHeight(30*count - 6)
                local y = -2
                for _, enemy in ipairs(self.units) do
                    if enemy then
                        enemy.frame:ClearAllPoints()
                        enemy.frame:SetPoint("TOPLEFT", f, "TOPLEFT", 0, y)
                        y = y - 30
                     end
                end
                f:Show()
            end
        end
    end
end
