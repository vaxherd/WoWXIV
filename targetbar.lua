local _, WoWXIV = ...
WoWXIV.TargetBar = {}

local class = WoWXIV.class

------------------------------------------------------------------------

local ARROW_X, ARROW1_Y, ARROW2_Y = 391, -29, -34

local TargetBar = class()

function TargetBar:__constructor(is_focus)
    self.unit = is_focus and "focus" or "target"
    self.hostile = 0  -- enemies: +1 if aggro, 0 if no aggro. -1 if not an enemy

    local f = CreateFrame("Frame",
                          is_focus and "WoWXIV_FocusBar" or "WoWXIV_TargetBar",
                          UIParent)
    self.frame = f
    local name_size, icon_size, cast_text_scale, hp_yofs
    if is_focus then
        f:SetSize(144, 80)
        f:SetPoint("TOP", -400, -14)
        name_size = 1.0
        icon_size = 17
        cast_text_scale = 1
        hp_yofs = 27
    else
        f:SetSize(384, 80)
        f:SetPoint("TOP", 0, -8)
        name_size = 1.1
        icon_size = 20
        cast_text_scale = 1.4
        hp_yofs = 33
    end
    self.hp_yofs = hp_yofs

    local class_icon = f:CreateTexture(nil, "ARTWORK")
    self.class_icon = class_icon
    class_icon:SetPoint("TOPRIGHT", f, "TOPLEFT", -3, -26)
    class_icon:SetSize(icon_size, icon_size)
    class_icon:Hide()

    local name = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    self.name = name
    name:SetTextScale(name_size)
    name:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, -(hp_yofs+5))
    name:SetWordWrap(false)
    name:SetJustifyH("LEFT")

    local hp = WoWXIV.UI.Gauge(f, f:GetWidth())
    self.hp = hp
    hp:SetSinglePoint("TOP", 0, -hp_yofs)
    if is_focus then
        name:SetWidth(f:GetWidth())
    else
        hp:SetShowValue(true, true)
        local SPACING = 10
        -- This anchoring is technically overspecified because we're
        -- giving two different values for the bottom Y coordinate, but
        -- it seems to do what we want (anchor to BOTTOMLEFT and adjust
        -- the width automatically) as of 11.0.2.
        name:SetPoint("BOTTOMRIGHT",
                       hp:GetValueObject(), "BOTTOMLEFT", -SPACING, 0)
    end

    local power = WoWXIV.UI.Gauge(f, f:GetWidth())
    self.power = power
    power:SetBoxColor(0.9, 0.9, 0.9)
    power:SetBarBackgroundColor(0, 0, 0)
    power:SetBarColor(0.05, 0.45, 0.95)
    power:SetSinglePoint("TOP", 0, -(hp_yofs+7))

    local auras = WoWXIV.UI.AuraBar(
        "ALL", "TOPLEFT", is_focus and 6 or 16, is_focus and 1 or 5,
        f, 0, -(hp_yofs+14))
    self.auras = auras

    local cast_bar = WoWXIV.UI.CastBar(f, f:GetWidth(), not is_focus)
    self.cast_bar = cast_bar
    cast_bar:SetSinglePoint("TOP")
    cast_bar:SetBoxColor(0.88, 0.62, 0.17)
    cast_bar:SetBarColor(1, 1, 0.94)
    cast_bar:SetTextScale(cast_text_scale)

    if not is_focus then
        self.target_id = nil
        self.target_arrow_start = 0

        local target_arrow1 = f:CreateTexture(nil, "ARTWORK")
        self.target_arrow1 = target_arrow1
        target_arrow1:SetPoint("TOPLEFT", ARROW_X, ARROW1_Y)
        target_arrow1:SetSize(28, 28)
        WoWXIV.SetUITexture(target_arrow1, 224, 252, 16, 44)
        target_arrow1:Hide()

        local target_arrow2 = f:CreateTexture(nil, "ARTWORK")
        self.target_arrow2 = target_arrow2
        target_arrow2:SetPoint("TOPLEFT", ARROW_X, ARROW2_Y)
        target_arrow2:SetSize(22, 18)
        WoWXIV.SetUITexture(target_arrow2, 224, 246, 45, 63)
        target_arrow2:Hide()

        local target_name = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        self.target_name = target_name
        target_name:SetTextScale(1.1)
        target_name:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 436, -(hp_yofs+5))
        target_name:Hide()

        local target_hp = WoWXIV.UI.Gauge(f, 128)
        self.target_hp = target_hp
        target_hp:SetSinglePoint("TOPLEFT", 432, -hp_yofs)
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
        self.frame:RegisterUnitEvent(event, unpack(units))
    end
    if not is_focus then
        self.frame:RegisterUnitEvent("UNIT_TARGET", "target")
    end
    f:SetScript("OnEvent", function(frame, event, ...)
        if event == "PLAYER_ENTERING_WORLD" then  -- on every zone change
            self:RefreshUnit()  -- clear anything from previous zone
        elseif (event == "PLAYER_FOCUS_CHANGED" or
                event == "PLAYER_TARGET_CHANGED" or
                event == "UNIT_CLASSIFICATION_CHANGED" or
                event == "UNIT_THREAT_LIST_UPDATE") then
            self:RefreshUnit()
        else
            self:Update()
        end
    end)

    f:Hide()
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
    local unit = self.unit
    if not UnitGUID(unit) then
        self:SetNoUnit()
        return
    end

    local f = self.frame
    local opt_prefix = "targetbar_"..unit

    local auras = self.auras
    local all_debuffs_option = opt_prefix.."_all_debuffs"
    local all_debuffs_raid_option = opt_prefix.."_all_debuffs_not_raid"
    local all_debuffs = (WoWXIV_config[all_debuffs_option]
                         and not (WoWXIV_config[all_debuffs_option]
                                  and UnitInRaid("player")))
    auras:SetOwnDebuffsOnly(not all_debuffs)
    auras:SetUnit(unit)

    local cast_bar = self.cast_bar
    if WoWXIV_config[opt_prefix.."_cast_bar"] then
        cast_bar:SetUnit(unit)
        cast_bar:Show()
    else
        cast_bar:SetUnit(nil)
        cast_bar:Show(hide)
    end

    f:Show()

    local inactive
    self.hostile, inactive = SetColorsForUnit(unit, self.hp, self.name)
    f:SetAlpha(inactive and 0.5 or 1)

    local class_atlas = WoWXIV.UnitClassificationIcon(unit)
    if class_atlas then
        self.class_icon:SetAtlas(class_atlas)
        self.class_icon:Show()
    else
        self.class_icon:Hide()
    end

    self.hp:SetShowShieldValue(WoWXIV_config["targetbar_show_shield_value"])

    local power = self.power
    local show = (WoWXIV_config["targetbar_power"]
                  and (not WoWXIV_config["targetbar_power_boss_only"]
                       or UnitIsBossMob(unit)))
    if show then
        power:Show()
        auras:SetRelPosition(0, -(self.hp_yofs+21))
    else
        power:Hide()
        auras:SetRelPosition(0, -(self.hp_yofs+14))
    end

    self:Update()
end

function TargetBar:Update()
    local unit = self.unit
    if not UnitGUID(unit) then
        self:SetNoUnit()
        return
    end

    if self.hostile == 0 and UnitAffectingCombat(unit) then
        self.hostile = 1
        self.hp:SetBoxColor(1, 0.604, 0.604)
        self.hp:SetBarBackgroundColor(0.302, 0.094, 0.094)
        self.hp:SetBarColor(1, 0.753, 0.761)
        self.name:SetTextColor(1, 0.753, 0.761)
    elseif self.hostile > 0 and not UnitAffectingCombat(unit) then
        self.hostile = 0
        self.hp:SetBoxColor(0.925, 0.851, 0.557)
        self.hp:SetBarBackgroundColor(0.188, 0.165, 0.075)
        self.hp:SetBarColor(1, 0.973, 0.706)
        self.name:SetTextColor(1, 0.973, 0.706)
    end

    local name = UnitName(unit)
    local lv = UnitLevel(unit)
    local hp = UnitHealth(unit)
    local hpmax = UnitHealthMax(unit)

    local name_str = name
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

    self.hp:Update(hpmax, hp, 0, UnitGetTotalAbsorbs(unit),
                   UnitGetTotalHealAbsorbs(unit))
    self.power:Update(UnitPowerMax(unit), UnitPower(unit))

    if unit == "target" then
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
                target_arrow1:SetPoint("TOPLEFT", ARROW_X, ARROW1_Y)
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
            self.target_hp:Update(thpmax, thp, 0,
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
    target_arrow1:SetPoint("TOPLEFT", ARROW_X+xofs, ARROW1_Y)
    self.target_arrow2:SetAlpha(alpha)
end

---------------------------------------------------------------------------

-- Create the global target and focus bar instances, and hide the native
-- target/focus frame if desired.
function WoWXIV.TargetBar.Create()
    WoWXIV.TargetBar.target_bar = TargetBar(false)
    WoWXIV.TargetBar.focus_bar = TargetBar(true)
    if WoWXIV_config["targetbar_hide_native"] then
        WoWXIV.HideBlizzardFrame(TargetFrame)
        WoWXIV.HideBlizzardFrame(FocusFrame)
        WoWXIV.HideBlizzardFrame(BossTargetFrameContainer)
    end
    if WoWXIV_config["targetbar_move_top_center"] then
        -- Put it about halfway between the hotbars and menu bar.
        -- FIXME: UIParent:GetWidth() returns the wrong value at startup/reload
        -- (why? is there a better time/way to do this?)
        --[[
        local offset_x = UIParent:GetWidth() * 0.262
        UIWidgetTopCenterContainerFrame:ClearAllPoints()
        UIWidgetTopCenterContainerFrame:SetPoint("BOTTOM", UIParent, "BOTTOM",
                                                 offset_x, 15)
        ]]--
        local f = CreateFrame("Frame")
        WoWXIV.TargetBar.tmtc_hack_frame = f
        f.saved_x = 0
        f:SetScript("OnUpdate", function(self)
            local offset_x = UIParent:GetWidth() * 0.262
            if offset_x ~= self.saved_x then
                self.saved_x = offset_x
                UIWidgetTopCenterContainerFrame:ClearAllPoints()
                UIWidgetTopCenterContainerFrame:SetPoint("BOTTOM", UIParent, "BOTTOM",
                                                         offset_x, 15)
            end
        end)
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
