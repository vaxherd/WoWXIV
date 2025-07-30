local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

---------------------------------------------------------------------------

local EncounterJournalHandler = class(MenuCursor.MenuFrame)
MenuCursor.Cursor.RegisterFrameHandler(EncounterJournalHandler)
local MonthlyActivitiesFrameHandler = class(MenuCursor.StandardMenuFrame)
local SuggestFrameHandler = class(MenuCursor.StandardMenuFrame)
local InstanceSelectHandler = class(MenuCursor.StandardMenuFrame)
local LootJournalItemsHandler = class(MenuCursor.StandardMenuFrame)


function EncounterJournalHandler.Initialize(class, cursor)
    class.cursor = cursor
    class:RegisterAddOnWatch("Blizzard_EncounterJournal")
end

function EncounterJournalHandler.OnAddOnLoaded(class, cursor)
    class.instance = class()
    class.instance_MonthlyActivitiesFrame = MonthlyActivitiesFrameHandler()
    class.instance_SuggestFrame = SuggestFrameHandler()
    class.instance_InstanceSelect = InstanceSelectHandler()
    class.instance_LootJournalItems = LootJournalItemsHandler()
    -- InstanceSelect is an odd one: it is used for both the Dungeons and
    -- Raids tabs, but more importantly it is left shown even when other
    -- tabs are active (the other tabs are just layered on top).  So we
    -- omit it from this list and add special handling in the various
    -- callbacks.
    class.panel_instances = {class.instance_MonthlyActivitiesFrame,
                             class.instance_SuggestFrame,
                             class.instance_LootJournalItems}
end

function EncounterJournalHandler:__constructor()
    -- Same pattern as e.g. CharacterFrame.
    self:__super(EncounterJournal)
    self:HookShow(EncounterJournal)
    self.tab_handler = function(direction) self:OnTabCycle(direction) end
end

function EncounterJournalHandler.CancelMenu()  -- Static method.
    HideUIPanel(EncounterJournal)
end

function EncounterJournalHandler:OnShow()
    for _, panel_instance in ipairs(self.panel_instances) do
        if panel_instance.frame:IsShown() then
            panel_instance:OnShow()
            return
        end
    end
    if EncounterJournalInstanceSelect:IsShown() then
        EncounterJournalHandler.instance_InstanceSelect:OnShow()
    -- FIXME: else showing dungeon/raid details
    end
end

function EncounterJournalHandler:OnHide()
    for _, panel_instance in ipairs(self.panel_instances) do
        if panel_instance.frame:IsShown() then
            panel_instance:OnHide()
            return
        end
    end
    if EncounterJournalInstanceSelect:IsShown() then
        EncounterJournalHandler.instance_InstanceSelect:OnHide()
    -- FIXME: else showing dungeon/raid details
    end
end

function EncounterJournalHandler:OnTabCycle(direction)
    local new_index =
        (PanelTemplates_GetSelectedTab(self.frame) or 0) + direction
    if new_index < 1 then
        new_index = self.frame.numTabs
    elseif new_index > self.frame.numTabs then
        new_index = 1
    end
    local tab = self.frame.Tabs[new_index]
    -- Normally we'd call the OnClick handler, but that calls down to
    -- C_EncounterJournal.SetTab() which is mysteriously a protected
    -- function, so we substitute the non-protected part.
    --tab:GetScript("OnClick")(tab, "LeftButton", true)
    EJ_ContentTab_Select(tab:GetID())
end


function MonthlyActivitiesFrameHandler:__constructor()
    self:__super(EncounterJournalMonthlyActivitiesFrame)
    self.cancel_func = EncounterJournalHandler.CancelMenu
    self.tab_handler = EncounterJournalHandler.instance.tab_handler
end

function MonthlyActivitiesFrameHandler:OnShow()
    -- InstanceSelect is always shown, so we have to send an OnHide() when
    -- we become active.
    EncounterJournalHandler.instance_InstanceSelect:OnHide()
    MenuCursor.StandardMenuFrame.OnShow(self)
end

function MonthlyActivitiesFrameHandler:OnHide()
    MenuCursor.StandardMenuFrame.OnHide(self)
    -- InstanceSelect is always shown, so it won't get an OnShow() call
    -- here; we have to send that manually.  (Since we send OnHide() in
    -- our own OnShow(), we shouldn't have to worry that it might already
    -- be enabled for input.)
    EncounterJournalHandler.instance_InstanceSelect:OnShow()
end


function SuggestFrameHandler:__constructor()
    self:__super(EncounterJournalSuggestFrame)
    self.cancel_func = EncounterJournalHandler.CancelMenu
    self.tab_handler = EncounterJournalHandler.instance.tab_handler
end

function SuggestFrameHandler:OnShow()
    EncounterJournalHandler.instance_InstanceSelect:OnHide()
    MenuCursor.StandardMenuFrame.OnShow(self)
end

function SuggestFrameHandler:OnHide()
    MenuCursor.StandardMenuFrame.OnHide(self)
    EncounterJournalHandler.instance_InstanceSelect:OnShow()
end


function InstanceSelectHandler:__constructor()
    self:__super(EncounterJournalInstanceSelect)
    self.cancel_func = EncounterJournalHandler.CancelMenu
    self.tab_handler = EncounterJournalHandler.instance.tab_handler
end


function LootJournalItemsHandler:__constructor()
    self:__super(EncounterJournal.LootJournalItems)
    self.cancel_func = EncounterJournalHandler.CancelMenu
    self.tab_handler = EncounterJournalHandler.instance.tab_handler
end

function LootJournalItemsHandler:OnShow()
    EncounterJournalHandler.instance_InstanceSelect:OnHide()
    MenuCursor.StandardMenuFrame.OnShow(self)
end

function LootJournalItemsHandler:OnHide()
    MenuCursor.StandardMenuFrame.OnHide(self)
    EncounterJournalHandler.instance_InstanceSelect:OnShow()
end
