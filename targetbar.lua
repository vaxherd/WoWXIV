local WoWXIV = WoWXIV
WoWXIV.TargetBar = {}

------------------------------------------------------------------------

local TargetBar = {}
TargetBar.__index = TargetBar

function TargetBar:New(is_focus)
    local new = {}
    setmetatable(new, self)
    new.__index = self

    new.unit = is_focus and "focus" or "target"
    new.hostility = 0  -- enemies: +1 if aggro, 0 if no aggro. -1 if not an enemy

    local f = CreateFrame("Frame",
                          is_focus and "WoWXIV_FocusBar" or "WoWXIV_TargetBar",
                          UIParent)
    new.frame = f
    if is_focus then
        f:SetSize(192, 80)
        f:SetPoint("TOP", UIParent, "TOP", -400, -20)
    else
        f:SetSize(480, 80)
        f:SetPoint("TOP", UIParent, "TOP", 0, -20)
    end

    local name = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    new.name = name
    name:SetTextScale(1.1)
    name:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    new.name_maxwidth = f:GetWidth()

    local hp = WoWXIV.UI.Gauge:New(f, f:GetWidth())
    new.hp = hp
    if not is_focus then
        hp:SetShowValue(true, true)
        -- Minor hack to measure text width
        hp.value:SetText("0000000000")
        new.name_maxwidth = new.name_maxwidth - hp.value:GetWidth()
    end
    hp:SetPoint("TOP", f, "TOP", 0, -8)

    local auras = WoWXIV.UI.AuraBar:New(
        "ALL", "TOPLEFT", is_focus and 8 or 20, is_focus and 1 or 4,
        new.frame, 0, -22)
    new.auras = auras

    f:RegisterEvent("PLAYER_LEAVING_WORLD")
    f:RegisterEvent(is_focus and "PLAYER_FOCUS_CHANGED" or "PLAYER_TARGET_CHANGED")
    local unit_events = {"UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_HEALTH",
                         "UNIT_LEVEL", "UNIT_MAXHEALTH"}
    for _, event in ipairs(unit_events) do
        new.frame:RegisterUnitEvent(event, new.unit)
    end
    f:SetScript("OnEvent", function(self, event, ...)
        if event == "PLAYER_ENTERING_WORLD" then  -- on every zone change
            new:RefreshUnit()  -- clear anything from previous zone
        elseif event == "PLAYER_FOCUS_CHANGED" or event == "PLAYER_TARGET_CHANGED" then
            new:RefreshUnit()
        else
            new:Update()
        end
    end)

    f:Hide()
    return new
end

function TargetBar:RefreshUnit()
    -- Work around native target frame sometimes not staying hidden
    -- (presumably due to racing with the in-combat flag)
    if not InCombatLockdown then TargetFrame:Hide() end

    if not UnitGUID(self.unit) then
        self.auras:SetUnit(nil)
        self.frame:Hide()
        return
    end

    self.auras:SetUnit(self.unit)
    self.frame:Show()

    self.frame:SetAlpha(1)
    if UnitIsDeadOrGhost(self.unit) then
        self.hostile = -1
        self.hp:SetBoxColor(0.3, 0.3, 0.3)
        self.hp:SetBarBackgroundColor(0, 0, 0)
        self.hp:SetBarColor(0.7, 0.7, 0.7)
        self.name:SetTextColor(0.7, 0.7, 0.7)
    elseif UnitIsPlayer(self.unit) then
        self.hostile = -1
        self.hp:SetBoxColor(0.416, 0.725, 0.890)
        self.hp:SetBarBackgroundColor(0.027, 0.161, 0.306)
        self.hp:SetBarColor(1, 1, 1)
        self.name:SetTextColor(1, 1, 1)
        if not UnitIsConnected(self.unit) then
            self.frame:SetAlpha(0.5)
        end
    elseif UnitIsFriend("player", self.unit) then
        self.hostile = -1
        self.hp:SetBoxColor(0.749, 0.918, 0.604)
        self.hp:SetBarBackgroundColor(0.149, 0.212, 0.094)
        self.hp:SetBarColor(0.929, 1, 0.906)
        self.name:SetTextColor(0.929, 1, 0.906)
    elseif UnitAffectingCombat(self.unit) then
        self.hostile = 1
        self.is_hostile = true
        self.hp:SetBoxColor(1, 0.604, 0.604)
        self.hp:SetBarBackgroundColor(0.302, 0.094, 0.094)
        self.hp:SetBarColor(1, 0.753, 0.761)
        self.name:SetTextColor(1, 0.753, 0.761)
    else
        self.hostile = 0
        self.hp:SetBoxColor(0.925, 0.851, 0.557)
        self.hp:SetBarBackgroundColor(0.188, 0.165, 0.075)
        self.hp:SetBarColor(1, 0.973, 0.706)
        self.name:SetTextColor(1, 0.973, 0.706)
    end

    self:Update()
end

local typenames = {rare = "(Rare) ",
                   elite = "(Elite) ",
                   rareelite = "(Rare/Elite) ",
                   worldboss = "(World Boss) "}
function TargetBar:Update()
    if not UnitGUID(self.unit) then
        self.auras:SetUnit(nil)
        self.frame:Hide()
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
    self.name:SetText(name_str)
    while self.name:GetWidth() > self.name_maxwidth do
        name_str = string.sub(name_str, 1, -5) .. "..."
        self.name:SetText(name_str)
    end

    self.hp:Update(hpmax, hp, UnitGetTotalAbsorbs(self.unit))
end

---------------------------------------------------------------------------

-- Create the global target bar instance, and hide the native target frame
-- if desired.
function WoWXIV.TargetBar.Create()
    WoWXIV.TargetBar.target_bar = TargetBar:New(false)
    WoWXIV.TargetBar.focus_bar = TargetBar:New(true)
    if WoWXIV_config["targetbar_hide_native"] then
        WoWXIV.HideBlizzardFrame(TargetFrame)
        WoWXIV.HideBlizzardFrame(FocusFrame)
    end
end
