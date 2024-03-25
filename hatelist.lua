local WoWXIV = WoWXIV
WoWXIV.HateList = {}

--------------------------------------------------------------------------

local Enemy = {}
Enemy.__index = Enemy

-- See note on Update() for why we need rel_id
function Enemy:New(parent, unit, rel_id)
    local new = {}
    setmetatable(new, self)
    new.__index = self

    new.unit = unit

    local f = CreateFrame("Frame", nil, parent)
    new.frame = f
    f:SetSize(256, 30)

    new.hate_icon = f:CreateTexture(nil, "ARTWORK")
    new.hate_icon:SetPoint("TOPLEFT", f, "TOPLEFT")
    new.hate_icon:SetSize(19, 19)
    new.hate_icon:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")

    new.name = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    new.name:SetPoint("TOPLEFT", f, "TOPLEFT", 23, -1)
    new.name:SetTextScale(1.1)
    new.name:SetText(select(1, UnitName(rel_id)))

    local hp = WoWXIV.UI.Gauge:New(f, 52)
    new.hp = hp
    hp:SetBoxColor(0.533, 0.533, 0.533)
    hp:SetBarBackgroundColor(0.118, 0.118, 0.118)
    hp:SetBarColor(1, 1, 1)
    hp:SetPoint("TOPLEFT", f, "TOPLEFT", 19, -13)

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
                               38/256.0, 57/256.0)

    self.hp:Update(UnitHealth(rel_id), UnitHealthMax(rel_id),
                   UnitGetTotalAbsorbs(rel_id))
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
    f:SetSize(200, 30)

    f.units = {}

    f.bg_t = f:CreateTexture(nil, "BACKGROUND")
    f.bg_t:SetPoint("TOP", f)
    f.bg_t:SetSize(f:GetWidth(), 4)
    f.bg_t:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    f.bg_t:SetTexCoord(0, 1, 0/256.0, 4/256.0)
    f.bg_c = f:CreateTexture(nil, "BACKGROUND")
    f.bg_c:SetPoint("CENTER", f)
    f.bg_c:SetSize(f:GetWidth(), f:GetHeight()-8)
    f.bg_c:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
    f.bg_c:SetTexCoord(0, 1, 4/256.0, 7/256.0)
    f.bg_b = f:CreateTexture(nil, "BACKGROUND")
    f.bg_b:SetPoint("BOTTOM", f)
    f.bg_b:SetSize(f:GetWidth(), 4)
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
