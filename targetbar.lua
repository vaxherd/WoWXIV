local WoWXIV = WoWXIV
WoWXIV.TargetBar = {}

------------------------------------------------------------------------

local ARROW_X, ARROW1_Y, ARROW2_Y = 391, -4, -9

local TargetBar = {}
TargetBar.__index = TargetBar

function TargetBar:New(is_focus)
    local new = {}
    setmetatable(new, self)
    new.__index = self

    new.unit = is_focus and "focus" or "target"
    new.hostile = 0  -- enemies: +1 if aggro, 0 if no aggro. -1 if not an enemy

    local f = CreateFrame("Frame",
                          is_focus and "WoWXIV_FocusBar" or "WoWXIV_TargetBar",
                          UIParent)
    new.frame = f
    if is_focus then
        f:SetSize(144, 80)
        f:SetPoint("TOP", UIParent, "TOP", -400, -20)
    else
        f:SetSize(384, 80)
        f:SetPoint("TOP", UIParent, "TOP", 0, -20)
    end

    local name = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    new.name = name
    name:SetTextScale(is_focus and 1.0 or 1.1)
    name:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    new.name_maxwidth = f:GetWidth()

    local hp = WoWXIV.UI.Gauge:New(f, f:GetWidth())
    new.hp = hp
    if not is_focus then
        hp:SetShowValue(true, true)
        -- Minor hack to measure text width.
        hp.value:SetText("0000000000")
        new.name_maxwidth = new.name_maxwidth - hp.value:GetWidth()
    end
    hp:SetPoint("TOP", f, "TOP", 0, -8)

    local auras = WoWXIV.UI.AuraBar:New(
        "ALL", "TOPLEFT", is_focus and 6 or 16, is_focus and 1 or 5,
        new.frame, 0, -22)
    new.auras = auras

    if not is_focus then
        new.target_id = nil
        new.target_arrow_start = 0

        local target_arrow1 = f:CreateTexture(nil, "ARTWORK")
        new.target_arrow1 = target_arrow1
        target_arrow1:SetPoint("TOPLEFT", f, "TOPLEFT", ARROW_X, ARROW1_Y)
        target_arrow1:SetSize(28, 28)
        target_arrow1:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
        target_arrow1:SetTexCoord(224/256.0, 252/256.0, 16/256.0, 44/256.0)
        target_arrow1:Hide()

        local target_arrow2 = f:CreateTexture(nil, "ARTWORK")
        new.target_arrow2 = target_arrow2
        target_arrow2:SetPoint("TOPLEFT", f, "TOPLEFT", ARROW_X, ARROW2_Y)
        target_arrow2:SetSize(22, 18)
        target_arrow2:SetTexture("Interface\\Addons\\WowXIV\\textures\\ui.png")
        target_arrow2:SetTexCoord(224/256.0, 246/256.0, 45/256.0, 63/256.0)
        target_arrow2:Hide()

        local target_name = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        new.target_name = target_name
        target_name:SetTextScale(1.1)
        target_name:SetPoint("TOPLEFT", f, "TOPLEFT", 436, 0)
        target_name:Hide()

        local target_hp = WoWXIV.UI.Gauge:New(f, 128)
        new.target_hp = target_hp
        target_hp:SetPoint("TOPLEFT", f, "TOPLEFT", 432, -8)
        target_hp:Hide()
    end

    f:RegisterEvent("PLAYER_LEAVING_WORLD")
    f:RegisterEvent(is_focus and "PLAYER_FOCUS_CHANGED" or "PLAYER_TARGET_CHANGED")
    local unit_events = {"UNIT_ABSORB_AMOUNT_CHANGED",
                         "UNIT_CLASSIFICATION_CHANGED", "UNIT_HEALTH",
                         "UNIT_HEAL_ABSORB_AMOUNT_CHANGED",
                         "UNIT_LEVEL", "UNIT_MAXHEALTH",
                         "UNIT_THREAT_LIST_UPDATE"}
    local units = is_focus and {"focus"} or {"target", "targettarget"}
    for _, event in ipairs(unit_events) do
        new.frame:RegisterUnitEvent(event, unpack(units))
    end
    if not is_focus then
        new.frame:RegisterUnitEvent("UNIT_TARGET", "target")
    end
    f:SetScript("OnEvent", function(self, event, ...)
        if event == "PLAYER_ENTERING_WORLD" then  -- on every zone change
            new:RefreshUnit()  -- clear anything from previous zone
        elseif (event == "PLAYER_FOCUS_CHANGED" or
                event == "PLAYER_TARGET_CHANGED" or
                event == "UNIT_CLASSIFICATION_CHANGED" or
                event == "UNIT_THREAT_LIST_UPDATE") then
            new:RefreshUnit()
        else
            new:Update()
        end
    end)

    f:Hide()
    return new
end

-- Helper function to set colors and return hostile and inactive state.
local function SetColorsForUnit(unit, hp, name)
    local hostile, inactive = alse
    if UnitIsDeadOrGhost(unit) then
        hostile = -1
        hp:SetBoxColor(0.3, 0.3, 0.3)
        hp:SetBarBackgroundColor(0, 0, 0)
        hp:SetBarColor(0.7, 0.7, 0.7)
        name:SetTextColor(0.7, 0.7, 0.7)
    elseif UnitIsPlayer(unit) then
        hostile = -1
        hp:SetBoxColor(0.416, 0.725, 0.890)
        hp:SetBarBackgroundColor(0.027, 0.161, 0.306)
        hp:SetBarColor(0.790, 0.931, 0.970)
        name:SetTextColor(0.790, 0.931, 0.970)
        if not UnitIsConnected(unit) then
            inactive = true
        end
    elseif UnitIsFriend("player", unit) then
        hostile = -1
        hp:SetBoxColor(0.749, 0.918, 0.604)
        hp:SetBarBackgroundColor(0.149, 0.212, 0.094)
        hp:SetBarColor(0.929, 1, 0.906)
        name:SetTextColor(0.929, 1, 0.906)
    elseif UnitAffectingCombat(unit) then
        hostile = 1
        hp:SetBoxColor(1, 0.604, 0.604)
        hp:SetBarBackgroundColor(0.302, 0.094, 0.094)
        hp:SetBarColor(1, 0.753, 0.761)
        name:SetTextColor(1, 0.753, 0.761)
    else
        hostile = 0
        hp:SetBoxColor(0.925, 0.851, 0.557)
        hp:SetBarBackgroundColor(0.188, 0.165, 0.075)
        hp:SetBarColor(1, 0.973, 0.706)
        name:SetTextColor(1, 0.973, 0.706)
    end
    return hostile
end

-- Internal helper.
function TargetBar:SetNoUnit()
    self.auras:SetUnit(nil)
    self.frame:Hide()
    if self.unit == "target" then
        self.target_id = nil
        self.target_arrow1:Hide()
        self.target_arrow2:Hide()
        self.target_name:Hide()
        self.target_hp:Hide()
        self.frame:SetScript("OnUpdate", nil)
    end
end

function TargetBar:RefreshUnit()
    -- Work around native target frame sometimes not staying hidden
    -- (presumably due to racing with the in-combat flag)
    if not InCombatLockdown then TargetFrame:Hide() end

    if not UnitGUID(self.unit) then
        self:SetNoUnit()
        return
    end

    local own_only = (self.unit == "focus"
                      and WoWXIV_config["targetbar_focus_own_debuffs_only"]
                      or WoWXIV_config["targetbar_target_own_debuffs_only"])
    self.auras:SetOwnDebuffsOnly(own_only)
    self.auras:SetUnit(self.unit)
    self.frame:Show()

    local inactive
    self.hostile, inactive = SetColorsForUnit(self.unit, self.hp, self.name)
    self.frame:SetAlpha(inactive and 0.5 or 1)

    self:Update()
end

local typenames = {rare = "(Rare) ",
                   elite = "(Elite) ",
                   rareelite = "(Rare/Elite) ",
                   worldboss = "(World Boss) "}
function TargetBar:Update()
    if not UnitGUID(self.unit) then
        self:SetNoUnit()
        return
    end

    if self.hostile == 0 and UnitAffectingCombat(self.unit) then
        self.hostile = 1
        self.hp:SetBoxColor(1, 0.604, 0.604)
        self.hp:SetBarBackgroundColor(0.302, 0.094, 0.094)
        self.hp:SetBarColor(1, 0.753, 0.761)
        self.name:SetTextColor(1, 0.753, 0.761)
    elseif self.hostile > 0 and not UnitAffectingCombat(self.unit) then
        self.hostile = 0
        self.hp:SetBoxColor(0.925, 0.851, 0.557)
        self.hp:SetBarBackgroundColor(0.188, 0.165, 0.075)
        self.hp:SetBarColor(1, 0.973, 0.706)
        self.name:SetTextColor(1, 0.973, 0.706)
    end

    local name = UnitName(self.unit)
    local lv = UnitLevel(self.unit)
    local hp = UnitHealth(self.unit)
    local hpmax = UnitHealthMax(self.unit)

    local type_str = (not self.is_focus) and typenames[UnitClassification(self.unit)] or ""
    local name_str = type_str .. name
    if hp < hpmax then
        local pct = math.floor(1000*hp/hpmax) / 10
        if hp > 0 and pct < 0.1 then
            pct = 0.1
        end
        name_str = string.format("%.1f%% %s", pct, name_str)
    elseif lv and lv > 0 then
        name_str = string.format("Lv%d %s", lv, name_str)
    end
    local name_label = self.name
    name_label:SetText(name_str)
    while name_label:GetWidth() > self.name_maxwidth do
        name_str = string.sub(name_str, 1, -5) .. "..."
        name_label:SetText(name_str)
    end

    self.hp:Update(hpmax, hp, UnitGetTotalAbsorbs(self.unit),
                   UnitGetTotalHealAbsorbs(self.unit))

    if self.unit == "target" then
        local target_id = UnitGUID("targettarget")
        local tname, thp, thpmax
        if target_id then
            tname = UnitName("targettarget")
            thp = UnitHealth("targettarget")
            thpmax = UnitHealthMax("targettarget")
        end

        if target_id ~= self.target_id then
            self.target_id = target_id
            if not target_id then
                self.target_arrow1:Hide()
                self.target_arrow2:Hide()
                self.target_name:Hide()
                self.target_hp:Hide()
                self.frame:SetScript("OnUpdate", nil)
            else
                self.target_arrow_start = GetTime()

                local target_arrow1 = self.target_arrow1
                target_arrow1:ClearAllPoints()
                target_arrow1:SetPoint("TOPLEFT", self.frame, "TOPLEFT",
                                       ARROW_X, ARROW1_Y)
                target_arrow1:Show()

                local target_arrow2 = self.target_arrow2
                target_arrow2:SetAlpha(0)
                target_arrow2:Show()

                local target_name = self.target_name
                target_name:SetText(tname)
                while target_name:GetWidth() > 128 do
                    tname = string.sub(tname, 1, -5) .. "..."
                    target_name:SetText(tname)
                end
                target_name:Show()

                local target_hp = self.target_hp
                target_hp:Show()

                local _, inactive = SetColorsForUnit("targettarget",
                                                     target_hp, target_name)
                target_name:SetAlpha(inactive and 0.5 or 1)
                target_hp:SetAlpha(inactive and 0.5 or 1)

                self.frame:SetScript("OnUpdate", function() self:OnUpdate() end)
            end
        end

        if target_id then
            self.target_hp:Update(thpmax, thp,
                                  UnitGetTotalAbsorbs("targettarget"),
                                  UnitGetTotalHealAbsorbs("targettarget"))
        end
    end
end

function TargetBar:OnUpdate()
    local dt = GetTime() - self.target_arrow_start
    while dt >= 1.6 do
        self.target_arrow_start = self.target_arrow_start + 1.6
        dt = dt - 1.6
    end
    local xofs = (dt >= 0.25) and 12 or 12*(dt/0.25)
    local alpha
    if dt < 0.2 then
        alpha = 0
    elseif dt < 0.45 then
        alpha = (dt-0.2)/0.25
    else
        alpha = 1
    end

    local target_arrow1 = self.target_arrow1
    target_arrow1:ClearAllPoints()
    target_arrow1:SetPoint("TOPLEFT", self.frame, "TOPLEFT",
                           ARROW_X+xofs, ARROW1_Y)
    self.target_arrow2:SetAlpha(alpha)
end

---------------------------------------------------------------------------

-- Create the global target and focus bar instances, and hide the native
-- target/focus frame if desired.
function WoWXIV.TargetBar.Create()
    WoWXIV.TargetBar.target_bar = TargetBar:New(false)
    WoWXIV.TargetBar.focus_bar = TargetBar:New(true)
    if WoWXIV_config["targetbar_hide_native"] then
        WoWXIV.HideBlizzardFrame(TargetFrame)
        WoWXIV.HideBlizzardFrame(FocusFrame)
    end
    if WoWXIV_config["targetbar_move_top_center"] then
        -- Put it about halfway between the hotbars and menu bar.
        local offset_x = UIParent:GetWidth() * 0.262
        UIWidgetTopCenterContainerFrame:ClearAllPoints()
        UIWidgetTopCenterContainerFrame:SetPoint("BOTTOM", UIParent, "BOTTOM",
                                                 offset_x, 15)
    end
end

-- Force a refresh of the target and focus bars, such as to pick up
-- changed configuration settings.
function WoWXIV.TargetBar.Refresh()
    if WoWXIV.TargetBar.target_bar then
        WoWXIV.TargetBar.target_bar:RefreshUnit()
        WoWXIV.TargetBar.focus_bar:RefreshUnit()
    end
end
