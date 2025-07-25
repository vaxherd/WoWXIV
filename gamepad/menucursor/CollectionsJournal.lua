local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

---------------------------------------------------------------------------

local CollectionsJournalHandler = class(MenuCursor.MenuFrame)
MenuCursor.Cursor.RegisterFrameHandler(CollectionsJournalHandler)
local MountJournalHandler = class(MenuCursor.StandardMenuFrame)
local PetJournalHandler = class(MenuCursor.StandardMenuFrame)
local ToyBoxHandler = class(MenuCursor.StandardMenuFrame)
local HeirloomsJournalHandler = class(MenuCursor.StandardMenuFrame)
local WardrobeCollectionFrameHandler = class(MenuCursor.StandardMenuFrame)
local WarbandSceneJournalHandler = class(MenuCursor.StandardMenuFrame)


function CollectionsJournalHandler.Initialize(class, cursor)
    class.cursor = cursor
    class:RegisterAddOnWatch("Blizzard_Collections")
end

function CollectionsJournalHandler.OnAddOnLoaded(class, cursor)
    class.instance = class()
    class.instance_MountJournal = MountJournalHandler()
    class.instance_PetJournal = PetJournalHandler()
    class.instance_ToyBox = ToyBoxHandler()
    class.instance_HeirloomsJournal = HeirloomsJournalHandler()
    class.instance_WardrobeCollectionFrame = WardrobeCollectionFrameHandler()
    class.instance_WarbandSceneJournal = WarbandSceneJournalHandler()
    class.panel_instances = {class.instance_MountJournal,
                             class.instance_PetJournal,
                             class.instance_ToyBox,
                             class.instance_HeirloomsJournal,
                             class.instance_WardrobeCollectionFrame,
                             class.instance_WarbandSceneJournal}
end

function CollectionsJournalHandler:__constructor()
    -- Same pattern as e.g. CharacterFrame.
    self:__super(CollectionsJournal)
    self:HookShow(CollectionsJournal)
    self.tab_handler = function(direction) self:OnTabCycle(direction) end
end

function CollectionsJournalHandler.CancelMenu()  -- Static method.
    HideUIPanel(CollectionsJournal)
end

function CollectionsJournalHandler:OnShow()
    for _, panel_instance in ipairs(self.panel_instances) do
        if panel_instance.frame:IsShown() then
            panel_instance:OnShow()
            return
        end
    end
end

function CollectionsJournalHandler:OnHide()
    for _, panel_instance in ipairs(self.panel_instances) do
        if panel_instance.frame:IsShown() then
            panel_instance:OnHide()
            return
        end
    end
end

function CollectionsJournalHandler:OnTabCycle(direction)
    local new_index =
        (PanelTemplates_GetSelectedTab(self.frame) or 0) + direction
    if new_index < 1 then
        new_index = self.frame.numTabs
    elseif new_index > self.frame.numTabs then
        new_index = 1
    end
    local tab = self.frame.Tabs[new_index]
    tab:GetScript("OnClick")(tab, "LeftButton", true)
end


function MountJournalHandler:__constructor()
    self:__super(MountJournal)
    self.cancel_func = CollectionsJournalHandler.CancelMenu
    self.tab_handler = CollectionsJournalHandler.instance.tab_handler
end


function PetJournalHandler:__constructor()
    self:__super(PetJournal)
    self.cancel_func = CollectionsJournalHandler.CancelMenu
    self.tab_handler = CollectionsJournalHandler.instance.tab_handler
end


function ToyBoxHandler:__constructor()
    self:__super(ToyBox)
    self.cancel_func = CollectionsJournalHandler.CancelMenu
    self.tab_handler = CollectionsJournalHandler.instance.tab_handler
    self.on_prev_page = self.frame.PagingFrame.PrevPageButton
    self.on_next_page = self.frame.PagingFrame.NextPageButton
end


function HeirloomsJournalHandler:__constructor()
    self:__super(HeirloomsJournal)
    self.cancel_func = CollectionsJournalHandler.CancelMenu
    self.tab_handler = CollectionsJournalHandler.instance.tab_handler
    self.on_prev_page = self.frame.PagingFrame.PrevPageButton
    self.on_next_page = self.frame.PagingFrame.NextPageButton
end


function WardrobeCollectionFrameHandler:__constructor()
    self:__super(WardrobeCollectionFrame)
    self.cancel_func = CollectionsJournalHandler.CancelMenu
    self.tab_handler = CollectionsJournalHandler.instance.tab_handler
    self.on_prev_page =
        self.frame.ItemsCollectionFrame.PagingFrame.PrevPageButton
    self.on_next_page =
        self.frame.ItemsCollectionFrame.PagingFrame.NextPageButton
end


function WarbandSceneJournalHandler:__constructor()
    self:__super(WarbandSceneJournal)
    self.cancel_func = CollectionsJournalHandler.CancelMenu
    self.tab_handler = CollectionsJournalHandler.instance.tab_handler
    local PagingControls = self.frame.IconsFrame.Icons.Controls.PagingControls
    self.on_prev_page = PagingControls.PrevPageButton
    self.on_next_page = PagingControls.NextPageButton
end
