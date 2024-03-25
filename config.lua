local WoWXIV = WoWXIV
WoWXIV.Config = {}

------------------------------------------------------------------------

local config_default = {}

-- Fly text: enable?
config_default["flytext_enable"] = true

-- Party list: use role colors in background?
config_default["partylist_role_bg"] = false

-- Target bar: hide the native target and focus frames?
config_default["targetbar_hide_native"] = true
-- Target bar: show only own debuffs on target bar?
config_default["targetbar_target_own_debuffs_only"] = false
-- Target bar: show only own debuffs on focus bar?
config_default["targetbar_focus_own_debuffs_only"] = false

------------------------------------------------------------------------

local function AddHeader(f, x, y, text)
    local label = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
    label:SetPoint("TOPLEFT", x, y)
    label:SetTextScale(1.2)
    label:SetText(text)
    return label
end

local function AddCheckButton(f, x, y, text)
    local button = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    button:SetPoint("TOPLEFT", x, y)
    button.text:SetTextScale(1.25)
    button.text:SetText(text)
    return button
end

local function AddRadioButton(f, x, y, text)
    local button = CreateFrame("CheckButton", nil, f, "UIRadioButtonTemplate")
    button:SetPoint("TOPLEFT", x, y)
    button.text:SetTextScale(1.25)
    button.text:SetText(text)
    return button
end

-- Initialize configuration data and create the configuration window.
function WoWXIV.Config.Create()
    for k, v in pairs(config_default) do
        if WoWXIV_config[k] == nil then
            WoWXIV_config[k] = v
        end
    end

    local f = WoWXIV.CreateEventFrame("WoWXIV_Config")
    WoWXIV.Config.frame = f

    local y = 10

    y = y - 20
    AddHeader(f, 10, y, "Fly text settings")
    y = y - 30

    f.button_flytext_enable = AddCheckButton(f, 20, y, "Enable fly text (player only)")
    f.button_flytext_enable:SetChecked(WoWXIV_config["flytext_enable"])
    f.button_flytext_enable:SetScript("OnClick", function(self)
        self:GetParent():SetFlyTextEnable(not WoWXIV_config["flytext_enable"])
    end)
    y = y - 30

    y = y - 20
    AddHeader(f, 10, y, "Party list settings")
    y = y - 30

    f.button_partylist_role_bg = AddCheckButton(f, 20, y, "Use role color in list background")
    f.button_partylist_role_bg:SetChecked(WoWXIV_config["partylist_role_bg"])
    f.button_partylist_role_bg:SetScript("OnClick", function(self)
        self:GetParent():SetPartyListRoleBG(not WoWXIV_config["partylist_role_bg"])
    end)
    y = y - 30

    y = y - 20
    AddHeader(f, 10, y, "Target bar settings")
    y = y - 30

    f.button_targetbar_hide_native = AddCheckButton(f, 20, y, "Hide native target frame (requires reload)")
    f.button_targetbar_hide_native:SetChecked(WoWXIV_config["targetbar_hide_native"])
    f.button_targetbar_hide_native:SetScript("OnClick", function(self)
        self:GetParent():SetTargetBarHideNative(not WoWXIV_config["targetbar_hide_native"])
    end)
    y = y - 30

    f.button_targetbar_target_own_debuffs_only = AddCheckButton(f, 20, y, "Show only own debuffs on target bar")
    f.button_targetbar_target_own_debuffs_only:SetChecked(WoWXIV_config["targetbar_target_own_debuffs_only"])
    f.button_targetbar_target_own_debuffs_only:SetScript("OnClick", function(self)
        self:GetParent():SetTargetBarTargetOwnDebuffsOnly(not WoWXIV_config["targetbar_target_own_debuffs_only"])
    end)
    y = y - 30

    f.button_targetbar_focus_own_debuffs_only = AddCheckButton(f, 20, y, "Show only own debuffs on focus bar")
    f.button_targetbar_focus_own_debuffs_only:SetChecked(WoWXIV_config["targetbar_focus_own_debuffs_only"])
    f.button_targetbar_focus_own_debuffs_only:SetScript("OnClick", function(self)
        self:GetParent():SetTargetBarFocusOwnDebuffsOnly(not WoWXIV_config["targetbar_focus_own_debuffs_only"])
    end)
    y = y - 30

    -- Required by the settings API:
    function f:OnCommit()
    end
    function f:OnDefault()
        f:SetTargetBarHideNative(true)
        f:SetTargetBarShowFocus(false)
        f:SetFlyTextEnable(true)
    end
    function f:OnRefresh()
    end

    function f:SetFlyTextEnable(enable)
        self.button_flytext_enable:SetChecked(enable)
        WoWXIV_config["flytext_enable"] = enable
        WoWXIV.FlyText.Enable(enable)
    end

    function f:SetPartyListRoleBG(enable)
        self.button_partylist_role_bg:SetChecked(enable)
        WoWXIV_config["partylist_role_bg"] = enable
        WoWXIV.PartyList.Refresh()
    end

    function f:SetTargetBarHideNative(hide)
        self.button_targetbar_hide_native:SetChecked(hide)
        WoWXIV_config["targetbar_hide_native"] = hide
    end

    function f:SetTargetBarTargetOwnDebuffsOnly(enable)
        self.button_targetbar_target_own_debuffs_only:SetChecked(enable)
        WoWXIV_config["targetbar_target_own_debuffs_only"] = enable
        WoWXIV.TargetBar.Refresh()
    end

    function f:SetTargetBarFocusOwnDebuffsOnly(enable)
        self.button_targetbar_focus_own_debuffs_only:SetChecked(enable)
        WoWXIV_config["targetbar_focus_own_debuffs_only"] = enable
        WoWXIV.TargetBar.Refresh()
    end

    local category = Settings.RegisterCanvasLayoutCategory(f, "WoWXIV")
    WoWXIV.Config.category = category
    category.ID = "WoWXIV"
    Settings.RegisterAddOnCategory(category)
end

-- Open the addon configuration window.
function WoWXIV.Config.Open()
    InterfaceOptionsFrame_OpenToCategory(WoWXIV.Config.category)
end

------------------------------------------------------------------------
