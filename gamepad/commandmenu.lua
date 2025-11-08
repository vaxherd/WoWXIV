local _, WoWXIV = ...
WoWXIV.Gamepad = WoWXIV.Gamepad or {}
local Gamepad = WoWXIV.Gamepad

local class = WoWXIV.class
local list = WoWXIV.list
local Button = WoWXIV.Button
local Frame = WoWXIV.Frame

local max = math.max
local min = math.min


-- Colors for text and icons.
local COLOR_NORMAL_TEXT = {0.8, 1, 1}
local COLOR_NORMAL_BORDER = {0.9, 1, 1}
local COLOR_ACTIVE_TEXT = {1, 1, 0.85}
local COLOR_ACTIVE_BORDER = {1, 1, 0.85}
local COLOR_DISABLED_TEXT = {0.5, 0.5, 0.425}
local COLOR_HELP = {1, 1, 0.9}

-- Offset of menu header when opened.
local HEADER_OFFSET = 17
-- Time to animate header position change, in seconds.
local HEADER_OFFSET_ANIM_TIME = 0.1

-- Spacing between menu items when fully expanded.
local ITEM_SPACING = 7
-- Spacing between menu items when first opened.
local ITEM_SPACING_INITIAL = 3
-- Time to animate menu spacing change, in seconds.
local ITEM_SPACING_ANIM_TIME = 0.15

-- Time to scroll between menu items, in seconds.
local ITEM_SCROLL_TIME = 0.1

-- Time to fade menu items when closed, in seconds.
local ITEM_FADE_TIME = 0.2


-- Frame levels relative to CommandMenu:
-- (+1) CommandMenuColumn (column title)
-- (+0) CommandMenu / CommandMenuColumn.highlight (selected item highlight)
-- (-1) CommandMenuColumn.menu (menu item list)
-- (-2) CommandMenu.bg_frame (background fader)

---------------------------------------------------------------------------
-- Class for menu items
---------------------------------------------------------------------------

local CommandMenuItem = class(Button)

function CommandMenuItem:__allocator(parent, text, func)
    return __super("Button", nil, parent)
end

function CommandMenuItem:__constructor(parent, text, func)
    self:SetFrameLevel(parent:GetFrameLevel())

    -- Explicitly wrap the function so the button isn't passed as an argument.
    if func then
        self:SetScript("OnClick", function() func() end)
    end

    local label = self:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    self.label = label
    label:SetTextColor(unpack(COLOR_ACTIVE_TEXT))
    label:SetText(text)
    self:SetSize(label:GetUnboundedStringWidth(), label:GetFontHeight())
    label:SetAllPoints()
end

function CommandMenuItem:SetEnabled(enabled)
    __super(self, enabled)
    self.label:SetTextColor(unpack(enabled and COLOR_ACTIVE_TEXT
                                            or COLOR_DISABLED_TEXT))
end

---------------------------------------------------------------------------
-- Base class for menu columns
---------------------------------------------------------------------------

local CommandMenuColumn = class(Frame)

function CommandMenuColumn:__allocator(parent, title)
    return __super("Frame", nil, parent)
end

function CommandMenuColumn:__constructor(parent, title)
    local title_label =
        self:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    self.title_label = title_label
    local height = title_label:GetFontHeight()
    self:SetHeight(height*2)
    title_label:SetPoint("CENTER")
    title_label:SetHeight(height)
    title_label:SetText(title)

    local oval_l = self:CreateTexture(nil, "ARTWORK")
    local oval_c = self:CreateTexture(nil, "ARTWORK")
    local oval_r = self:CreateTexture(nil, "ARTWORK")
    self.oval_l, self.oval_c, self.oval_r = oval_l, oval_c, oval_r
    WoWXIV.SetUITexture(oval_l, 160, 186, 64, 112)
    WoWXIV.SetUITexture(oval_c, 186, 190, 64, 112)
    WoWXIV.SetUITexture(oval_r, 190, 216, 64, 112)
    local oval_h = height*2
    oval_c:SetPoint("TOPLEFT", title_label, "LEFT", 0, oval_h/2)
    oval_c:SetPoint("BOTTOMRIGHT", title_label, "RIGHT", 0, -oval_h/2)
    oval_l:SetPoint("RIGHT", oval_c, "LEFT")
    oval_l:SetSize(oval_h*26/48, oval_h)
    oval_r:SetPoint("LEFT", oval_c, "RIGHT")
    oval_r:SetSize(oval_h*26/48, oval_h)

    local menu = CreateFrame("Frame", nil, self)
    self.menu = menu
    menu:SetFrameLevel(self:GetFrameLevel() - 2)
    menu:Hide()

    local highlight = CreateFrame("Frame", nil, self)
    self.highlight = highlight
    highlight:SetFrameLevel(self:GetFrameLevel() - 1)
    local highlight_tex = highlight:CreateTexture(nil, "ARTWORK")
    self.highlight.texture = highlight_tex
    highlight_tex:SetPoint("TOPLEFT", -12, 3)
    highlight_tex:SetPoint("BOTTOMRIGHT", 0, -3)
    WoWXIV.SetUITexture(highlight_tex, 0, 256, 0, 11)
    -- Deliberately stretch the right side out.
    highlight_tex:SetTextureSliceMargins(0, 4, 64, 4)
    highlight_tex:SetVertexColor(0.9, 0.5, 0)
    highlight_tex:SetAlpha(0.4)
    highlight:Hide()

    self.items = list()
    self.default_item = 1
    self.position = 1
    self:Close()
end

-- Interface for implementations.
function CommandMenuColumn:AddItem(name, help, func, is_default)
    local index = #self.items + 1
    self.items[index] = {button = CommandMenuItem(self.menu, name, func),
                         name = name, help = help}
    if index > 1 then
        -- Spacing will be adjusted by OnUpdate().
        self.items[index].button:SetPoint(
            "TOPLEFT", self.items[index-1].button, "BOTTOMLEFT")
    else
        self.items[index].button:SetPoint("TOPLEFT")
    end
    if is_default then
        self.default_item = index
    end
    return index
end

function CommandMenuColumn:SetItemEnabled(name, enabled, disabled_reason)
    for item in self.items do
        if item.name == name then
            item.button:SetEnabled(enabled)
            item.help_suffix = not enabled and disabled_reason or nil
            return
        end
    end
    error("Item not found: "..name)
end

function CommandMenuColumn:IsItemEnabled(name)
    for item in self.items do
        if item.name == name then
            return item.button:IsEnabled()
        end
    end
    error("Item not found: "..name)
end

function CommandMenuColumn:SetItemSecureAction(name, action)
    for item in self.items do
        if item.name == name then
            item.secure_action = action
            return
        end
    end
    error("Item not found: "..name)
end

-- Interface for CommandMenu.
function CommandMenuColumn:GetTitleWidth()
    return self.title_label:GetUnboundedStringWidth()
end

function CommandMenuColumn:GetFullWidth(title_width)
    local oval_w = self.oval_l:GetWidth()
    return oval_w*2 + title_width
end

function CommandMenuColumn:Configure(title_width, highlight_offset)
    self.title_label:SetWidth(title_width)
    local oval_w = self.oval_l:GetWidth()
    self:SetWidth(oval_w*2 + title_width)
    self.highlight:ClearAllPoints()
    self.highlight:SetPoint("TOPLEFT", self, "LEFT",
                            oval_w, highlight_offset)
    self.highlight:SetPoint("TOPRIGHT", self, "RIGHT",
                            -oval_w, highlight_offset)
    self.highlight:SetHeight(self.items[1].button:GetHeight())
    self.menu:SetWidth(self.highlight:GetWidth())
end

function CommandMenuColumn:Open()
    self.title_label:SetTextColor(unpack(COLOR_ACTIVE_TEXT))
    self.oval_l:SetVertexColor(unpack(COLOR_ACTIVE_BORDER))
    self.oval_c:SetVertexColor(unpack(COLOR_ACTIVE_BORDER))
    self.oval_r:SetVertexColor(unpack(COLOR_ACTIVE_BORDER))
    self.highlight:Show()
    self.menu:SetAlpha(1)
    self.menu:Show()
    self.position = self.default_item
    self.menu_offset = nil  -- Will be calculated in OnUpdate() call below.
    self.open_time = GetTime()
    self.close_time = nil
    self.scroll_time = nil
    self:OnUpdate()
    self:SetScript("OnUpdate", self.OnUpdate)
end

function CommandMenuColumn:Close()
    self.title_label:SetTextColor(unpack(COLOR_NORMAL_TEXT))
    self.oval_l:SetVertexColor(unpack(COLOR_NORMAL_BORDER))
    self.oval_c:SetVertexColor(unpack(COLOR_NORMAL_BORDER))
    self.oval_r:SetVertexColor(unpack(COLOR_NORMAL_BORDER))
    self.highlight:Hide()
    self.close_time = GetTime()
end

function CommandMenuColumn:Scroll(direction, is_repeat)
    local target = self.position + direction
    if target < 1 then
        if is_repeat then return end
        target = #self.items
    elseif target > #self.items then
        if is_repeat then return end
        target = 1
    end
    self.position = target
    self.scroll_from_offset = self.menu_offset
    self.scroll_time = GetTime()
end

function CommandMenuColumn:GetCommandButton()
    return self.items[self.position].button
end

function CommandMenuColumn:GetCommandHelp()
    local text = self.items[self.position].help
    if self.items[self.position].help_suffix then
        text = text .. " " .. RED_FONT_COLOR:WrapTextInColorCode(self.items[self.position].help_suffix)
    end
    return text
end

function CommandMenuColumn:GetCommandSecureAction()
    return self.items[self.position].secure_action
end

function CommandMenuColumn:RunCommand()
    local button = self.items[self.position].button
    assert(button:IsEnabled())
    local func = button:GetScript("OnClick")
    if func then
        func("LeftButton")
    end
end

-- Internal update routine.
function CommandMenuColumn:OnUpdate()
    local now = GetTime()
    if self.close_time then
        local dt = now - self.close_time
        local header_factor = 1 - (min(dt / HEADER_OFFSET_ANIM_TIME, 1) ^ 0.5)
        local alpha = 1 - min(dt / ITEM_FADE_TIME, 1)  -- Linear interpolation.
        self.title_label:ClearPointsOffset()
        self.title_label:AdjustPointsOffset(0, HEADER_OFFSET * header_factor)
        if alpha > 0 then
            self.menu:SetAlpha(alpha)
        else
            self.menu:Hide()
            assert(header_factor == 0)
            self:SetScript("OnUpdate", nil)
        end
    else  -- not closing
        -- Updating all this every frame even after animations complete
        -- is a bit wasteful, but since this is effectively a modal UI,
        -- we should be able to spare the processing time.
        local dt = now - self.open_time
        local header_factor = min(dt / HEADER_OFFSET_ANIM_TIME, 1) ^ 0.5
        local spacing_factor = min(dt / ITEM_SPACING_ANIM_TIME, 1) ^ 0.5
        self.title_label:ClearPointsOffset()
        self.title_label:AdjustPointsOffset(0, HEADER_OFFSET * header_factor)
        local spacing = ITEM_SPACING_INITIAL
            + (ITEM_SPACING - ITEM_SPACING_INITIAL) * spacing_factor
        for i = 2, #self.items do
            self.items[i].button:ClearPointsOffset()
            self.items[i].button:AdjustPointsOffset(0, -spacing)
        end
        local row_size = self.items[1].button:GetHeight() + spacing
        local menu_size = row_size * #self.items - spacing
        self.menu:SetHeight(menu_size)
        self.menu_offset = row_size * (self.position - 1)
        if self.scroll_time then
            local scroll_dt = now - self.scroll_time
            local scroll_factor = min(scroll_dt / ITEM_SCROLL_TIME, 1) ^ 0.5
            if scroll_factor < 1 then
                self.menu_offset = self.scroll_from_offset
                    + (self.menu_offset - self.scroll_from_offset) * scroll_factor
            else
                self.scroll_time = nil
            end
        end
        self.menu:ClearAllPoints()
        self.menu:SetPoint("TOPLEFT", self.highlight, "TOPLEFT",
                           0, self.menu_offset)
        for item in self.items do
            local above = max(item.button:GetTop() - self.highlight:GetTop(), 0)
            item.button:SetAlpha(1 - 0.6 * min(above/40, 1))
        end
    end
end

---------------------------------------------------------------------------
-- Individual menu column implementations
---------------------------------------------------------------------------

local CharacterColumn = class(CommandMenuColumn)

function CharacterColumn:__constructor(parent)
    __super(self, parent, "Character")
    self:AddItem("Currency",
                 "View your owned tokens and other currencies.",
                 function() ToggleCharacter("TokenFrame") end)
    self:AddItem("Reputation",
                 "View your reputation with various factions.",
                 function() ToggleCharacter("ReputationFrame") end)
    self:AddItem("Character Info",
                 "Manage your character's equipment and title.",
                 function() ToggleCharacter("PaperDollFrame") end,
                 true)
    self:AddItem("Inventory",
                 "Manage your inventory.",
                 OpenAllBags)
    self:AddItem("Professions",
                 "View your professions or craft items.",
                 ToggleProfessionsBook)
    self:AddItem("Spellbook",
                 "View your known spells.",
                 PlayerSpellsUtil.ToggleSpellBookFrame)
    self:AddItem("Talents",
                 "View your class talent tree or change talents.",
                 PlayerSpellsUtil.OpenToClassTalentsTab)
    self:AddItem("Specialization",
                 "Change your class specialization.",
                 PlayerSpellsUtil.OpenToClassSpecializationsTab)
    self:AddItem("Achievements",
                 "View your earned achievements.",
                 ToggleAchievementFrame)
end


local ContentColumn = class(CommandMenuColumn)

function ContentColumn:__constructor(parent)
    __super(self, parent, "Content")
    self:AddItem("Adventure Guide",
                 "Open the adventure guide.",
                 ToggleEncounterJournal,
                 true)
    self:AddItem("Group Finder",
                 "Look for groups of players to play specific content with.",
                 ToggleLFDParentFrame)
    self:AddItem("Raid Info",
                 "View your raid and dungeon instance locks.",
                 -- RaidInfoFrame is parented to the Raid tab on FriendsFrame,
                 -- so we have to open that as well.
                 function()
                     ToggleFriendsFrame(FRIEND_TAB_RAID)
                     RaidInfoFrame:Show()
                 end)
    self:AddItem("Delves Dashboard",
                 "Check the status of your delve companion or your Great Vault rewards.",
                 function() PVEFrame_ShowFrame("DelvesDashboardFrame") end)
end

function ContentColumn:Open()
    -- Same check as in RaidFrame_OnShow().
    self:SetItemEnabled("Raid Info",
                        GetNumSavedInstances() + GetNumSavedWorldBosses() > 0,
                        "(You do not have any saved instances.)")
    __super(self)
end


local CollectionsColumn = class(CommandMenuColumn)

function CollectionsColumn:__constructor(parent)
    __super(self, parent, "Collections")
    self:AddItem("Mounts",
                 "View the list of mounts you've collected.",
                 function() ToggleCollectionsJournal(COLLECTIONS_JOURNAL_TAB_INDEX_MOUNTS) end,
                 true)
    self:AddItem("Pets",
                 "View your battle and companion pets.",
                 function() ToggleCollectionsJournal(COLLECTIONS_JOURNAL_TAB_INDEX_PETS) end)
    self:AddItem("Toys",
                 "View the list of toys you've collected.",
                 function() ToggleCollectionsJournal(COLLECTIONS_JOURNAL_TAB_INDEX_TOYS) end)
    self:AddItem("Heirlooms",
                 "View your heirloom items.",
                 function() ToggleCollectionsJournal(COLLECTIONS_JOURNAL_TAB_INDEX_HEIRLOOMS) end)
    self:AddItem("Appearances",
                 "View your collected transmog items and sets.",
                 function() ToggleCollectionsJournal(COLLECTIONS_JOURNAL_TAB_INDEX_APPEARANCES) end)
    self:AddItem("Campsites",
                 "View the warband campsites you've unlocked.",
                 function() ToggleCollectionsJournal(COLLECTIONS_JOURNAL_TAB_INDEX_WARBAND_SCENES) end)
end


local CommunicationColumn = class(CommandMenuColumn)

function CommunicationColumn:__constructor(parent)
    __super(self, parent, "Communication")
    self:AddItem("Guild & Communities",
                 "View your current guild, or look for guilds or communities to join.",
                 ToggleGuildFrame,
                 true)
    self:AddItem("Friends",
                 "Open the friends list.",
                 ToggleFriendsFrame)
end


local SystemColumn = class(CommandMenuColumn)

function SystemColumn:__constructor(parent)
    __super(self, parent, "System")
    self:AddItem("Support",
                 "Read support articles or ask for help.",
                 ToggleHelpFrame)
    self:AddItem("What's New",
                 "Show what's new in the most recent update.",
                 function() C_SplashScreen.RequestLatestSplashScreen(true) end)
    self:AddItem("Settings",
                 "Open the game settings menu.",
                 function() SettingsPanel:Open() end,
                 true)
    self:AddItem("Macros",
                 "Create or edit macro commands.",
                 ShowMacroFrame)
    self:AddItem("Addons",
                 "Open the addon list.",
                 function() ShowUIPanel(AddonList) end)
    self:AddItem("Edit Mode",
                 "Enable Edit Mode to adjust the user interface layout.",
                 function() ShowUIPanel(EditModeManagerFrame) end)
    self:AddItem("Shop",
                 "Visit the World of Warcraft online shop.")
    self:AddItem("Log Out",
                 "Log out from your character and return to the character list.")
    self:AddItem("Exit Game",
                 "Log out from your character and close World of Warcraft.")
end

function SystemColumn:Open()
    -- These checks mirror the ones found in GameMenuFrameMixin:InitButtons().
    -- We skip the Kiosk.IsEnabled() test because we could never run in that
    -- environment anyway.
    self:SetItemEnabled("What's New", (C_SplashScreen.CanViewSplashScreen()
                                       and not IsCharacterNewlyBoosted()))
    self:SetItemEnabled("Edit Mode", EditModeManagerFrame:CanEnterEditMode())
    local shop_reason
    if not C_StorePublic.IsEnabled() then
        shop_reason = "(Not available in this version.)"
    elseif C_StorePublic.IsDisabledByParentalControls() then
        shop_reason = "("..BLIZZARD_STORE_ERROR_PARENTAL_CONTROLS..")"
    end
    self:SetItemEnabled("Shop", not shop_reason, shop_reason)
    local exit_disabled = (StaticPopup_Visible("CAMP") or
                           StaticPopup_Visible("PLUNDERSTORM_LEAVE") or
                           StaticPopup_Visible("QUIT"))
    self:SetItemEnabled("Log Out", not exit_disabled)
    self:SetItemEnabled("Exit Game", not exit_disabled)

    -- Look up GameMenuFrame buttons for secure actions.  (These are
    -- recreated every time the menu is opened, so we have to look these
    -- up at least every time CommandMenu is opened.)
    local game_menu_buttons = {}
    for button in GameMenuFrame.buttonPool:EnumerateActive() do
        game_menu_buttons[button:GetText()] = button
    end
    for name, text in pairs({["Shop"] = BLIZZARD_STORE, ["Log Out"] = LOG_OUT,
                             ["Exit Game"] = EXIT_GAME}) do
        if self:IsItemEnabled(name) then
            local button = game_menu_buttons[text]
            if button then
                self:SetItemSecureAction(
                    name, {type = "click", clickbutton = button})
            else
                self:SetItemEnabled(
                    name, false, "(Open the main menu to enable this option.)")
            end
        end
    end

    __super(self)
end

---------------------------------------------------------------------------
-- Top-level menu implementation
---------------------------------------------------------------------------

Gamepad.CommandMenu = class(Button)
local CommandMenu = Gamepad.CommandMenu

function CommandMenu:__allocator()
    -- Implemented as a SecureActionButton to allow indirectly clicking
    -- GameMenuFrame buttons.
    return __super("Button", "WoWXIV_CommandMenu", UIParent,
                   "SecureActionButtonTemplate")
end

function CommandMenu:__constructor()
    self.brm = WoWXIV.ButtonRepeatManager()

    self:Hide()

    self:SetFrameStrata("FULLSCREEN")
    self:SetFrameLevel(103)
    self:SetAllPoints()
    self:SetAttribute("useOnKeyDown", true)
    self:RegisterForClicks("AnyDown", "AnyUp")
    self:HookScript("OnClick", self.OnClick)
    self:SetScript("OnShow", self.OnShow)
    self:SetScript("OnHide", self.OnHide)
    self:SetScript("OnEvent", self.OnEvent)
    self:RegisterEvent("PLAYER_REGEN_DISABLED")
    self:UpdateBindings(false)

    local bg_frame = CreateFrame("Frame", nil, self)
    self.bg_frame = bg_frame
    bg_frame:SetFrameLevel(self:GetFrameLevel() - 2)
    bg_frame:SetAllPoints()
    local fader = bg_frame:CreateTexture(nil, "BACKGROUND")
    bg_frame.fader = fader
    fader:SetAllPoints()
    fader:SetColorTexture(0, 0, 0, 0.2)
    local bg_black = bg_frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    bg_frame.bg_black = bg_black
    local offset = UIParent:GetHeight()*0.3
    bg_black:SetPoint("LEFT", 0, offset)
    bg_black:SetPoint("RIGHT", 0, offset)
    bg_black:SetHeight(250)
    WoWXIV.SetUITexture(bg_black, 0,5, 256,5, 0,6, 256,6)
    bg_black:SetVertexColor(0, 0, 0)
    bg_black:SetAlpha(0.7)
    local background = bg_frame:CreateTexture(nil, "BACKGROUND", nil, 2)
    self.background = background
    background:SetPoint("LEFT", bg_black)
    background:SetPoint("RIGHT", bg_black)
    background:SetHeight(80)
    WoWXIV.SetUITexture(background, 252, 256, 64, 112)
    background:SetTextureSliceMargins(1, 16, 1, 16)

    local columns = list(CharacterColumn(self),
                         ContentColumn(self),
                         CollectionsColumn(self),
                         CommunicationColumn(self),
                         SystemColumn(self))
    self.columns = columns
    local title_width = 0
    for column in columns do
        local width = column:GetTitleWidth()
        title_width = max(title_width, width)
    end
    local SPACING = 10
    local total_width = (columns[1]:GetFullWidth(title_width) * #columns
                         + SPACING * (#columns-1))
    local highlight_offset = -(background:GetHeight() / 2)
    columns[1]:SetPoint("LEFT", background, "CENTER", -(total_width/2), 0)
    columns[1]:Configure(title_width, highlight_offset)
    for i = 2, #columns do
        columns[i]:SetPoint("LEFT", columns[i-1], "RIGHT", SPACING, 0)
        columns[i]:Configure(title_width, highlight_offset)
    end

    local help_label = self:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    self.help_label = help_label
    help_label:SetPoint("LEFT", columns[1], "LEFT", 66, 66)
    help_label:SetTextColor(unpack(COLOR_HELP))
    help_label:SetHeight(help_label:GetFontHeight())

    local help_icon = self:CreateTexture(nil, "ARTWORK")
    self.help_icon = help_icon
    help_icon:SetPoint("RIGHT", help_label, "LEFT", -3, 0)
    local help_icon_size = help_label:GetHeight() * 1.5
    help_icon:SetSize(help_icon_size, help_icon_size)
    WoWXIV.SetUITexture(help_icon, 216, 248, 64, 96)
    help_icon:SetVertexColor(unpack(COLOR_HELP))
end

-- Open the menu if it is not already open.
function CommandMenu:Open()
    if InCombatLockdown() then return end  -- Can't SetPropagate() in combat.
    if not self:IsShown() then
        CloseAllWindows()
        RequestRaidInfo()  -- For Raid Info command.
        self:Show()
    end
end

function CommandMenu:OnShow()
    self.cur_column = 1
    self.columns[self.cur_column]:Open()
    self:UpdateCommand()
    self:SetScript("OnUpdate", self.OnUpdate)
    self:UpdateBindings(true)
end

function CommandMenu:OnHide()
    self:UpdateBindings(false)
    self:SetScript("OnUpdate", nil)
    self.brm:StopRepeat()
    for column in self.columns do
        column:Close()
    end
end

function CommandMenu:OnEvent(event, ...)
    if event == "PLAYER_REGEN_DISABLED" then
        self:Hide()
    end
end

function CommandMenu:UpdateBindings(active)
    ClearOverrideBindings(self)
    SetOverrideBinding(self, true, WoWXIV_config["gamepad_open_menu"],
                       "CLICK WoWXIV_CommandMenu:RightButton")
    if active then
        SetOverrideBinding(self, true, WoWXIV.Config.GamePadConfirmButton(),
                           "CLICK WoWXIV_CommandMenu:LeftButton")
        SetOverrideBinding(self, true, "ENTER",
                           "CLICK WoWXIV_CommandMenu:LeftButton")
        SetOverrideBinding(self, true, WoWXIV.Config.GamePadCancelButton(),
                           "CLICK WoWXIV_CommandMenu:RightButton")
        SetOverrideBinding(self, true, "ESCAPE",
                           "CLICK WoWXIV_CommandMenu:RightButton")
        SetOverrideBinding(self, true, "PADDUP",
                           "CLICK WoWXIV_CommandMenu:DPadUp")
        SetOverrideBinding(self, true, "UP",
                           "CLICK WoWXIV_CommandMenu:DPadUp")
        SetOverrideBinding(self, true, "PADDDOWN",
                           "CLICK WoWXIV_CommandMenu:DPadDown")
        SetOverrideBinding(self, true, "DOWN",
                           "CLICK WoWXIV_CommandMenu:DPadDown")
        SetOverrideBinding(self, true, "PADDLEFT",
                           "CLICK WoWXIV_CommandMenu:DPadLeft")
        SetOverrideBinding(self, true, "LEFT",
                           "CLICK WoWXIV_CommandMenu:DPadLeft")
        SetOverrideBinding(self, true, "PADDRIGHT",
                           "CLICK WoWXIV_CommandMenu:DPadRight")
        SetOverrideBinding(self, true, "RIGHT",
                           "CLICK WoWXIV_CommandMenu:DPadRight")
    end
end

function CommandMenu:OnUpdate()
    self.brm:CheckRepeat(function(input) self:OnInputDown(input, true) end)
end

function CommandMenu:OnClick(input, down)
    if not self:IsShown() then
        assert(input == "RightButton")
        if down then
            self:Open()
        end
        return
    end

    if down then
        self:OnInputDown(input)
    else
        self:OnInputUp(input)
    end
end

function CommandMenu:OnInputDown(input, is_repeat)
    if input ~= self.brm:GetRepeatButton() then
        self.brm:StopRepeat()
    end

    if input == "RightButton" then
        self:Hide()
    elseif input == "LeftButton" then
        local column = self.columns[self.cur_column]
        local button = column:GetCommandButton()
        if button:IsEnabled() then
            self:Hide()
            if not column:GetCommandSecureAction() then
                column:RunCommand()
            end
        end
    elseif input == "DPadUp" then
        self.brm:StartRepeat(input)
        self:ScrollColumn(-1, is_repeat)
    elseif input == "DPadDown" then
        self.brm:StartRepeat(input)
        self:ScrollColumn(1, is_repeat)
    elseif input == "DPadLeft" then
        self.brm:StartRepeat(input)
        self:SwitchColumn(-1, is_repeat)
    elseif input == "DPadRight" then
        self.brm:StartRepeat(input)
        self:SwitchColumn(1, is_repeat)
    end
end

function CommandMenu:OnInputUp(input)
    -- See notes at MenuCursor.Cursor:OnClick() for why we don't check
    -- against self.brm:GetRepeatButton().
    self.brm:StopRepeat()
end

function CommandMenu:ScrollColumn(direction, is_repeat)
    self.columns[self.cur_column]:Scroll(direction, is_repeat)
    self:UpdateCommand()
end

function CommandMenu:SwitchColumn(direction, is_repeat)
    local new_column = self.cur_column + direction
    if new_column < 1 then
        if is_repeat then return end
        new_column = is_repeat and 1 or #self.columns
    elseif new_column > #self.columns then
        if is_repeat then return end
        new_column = is_repeat and #self.columns or 1
    end
    self.columns[self.cur_column]:Close()
    self.cur_column = new_column
    self.columns[self.cur_column]:Open()
    self:UpdateCommand()
end

function CommandMenu:UpdateCommand()
    local column = self.columns[self.cur_column]
    local help_label = self.help_label
    help_label:SetText(column:GetCommandHelp())
    help_label:SetWidth(help_label:GetUnboundedStringWidth())
    local action = column:GetCommandSecureAction()
    if action then
        for k, v in pairs(action) do
            self:SetAttribute(k.."1", v)
        end
    else
        self:SetAttribute("type1", nil)
    end
end
