local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor
local StandardMenuFrame = MenuCursor.StandardMenuFrame

local class = WoWXIV.class

local tinsert = tinsert

---------------------------------------------------------------------------

-- The wrapper frame doesn't have any input elements of its own other than
-- the tabs.  We use this class to hold the tab switch handler and to pass
-- down show/hide events from the wrapper frame to the initially active tab.
-- We also set up a PVETab subclass of StandardMenuFrame which includes
-- common behaviors for all subframes.

local PVEFrameHandler = class(MenuCursor.CoreMenuFrame)
local PVETab = class(StandardMenuFrame)
local GroupFinderFrameHandler = class(PVETab)
local PVPQueueFrameHandler = class(PVETab)
local ChallengesFrameHandler = class(PVETab)
local DelvesDashboardFrameHandler = class(PVETab)
MenuCursor.Cursor.RegisterFrameHandler(PVEFrameHandler)
MenuCursor.Cursor.RegisterFrameHandler(GroupFinderFrameHandler)
MenuCursor.Cursor.RegisterFrameHandler(PVPQueueFrameHandler)
MenuCursor.Cursor.RegisterFrameHandler(ChallengesFrameHandler)
MenuCursor.Cursor.RegisterFrameHandler(DelvesDashboardFrameHandler)

function PVEFrameHandler:__constructor()
    self:__super(PVEFrame)
    self.tabs = {{PVEFrameTab1, GroupFinderFrameHandler},
                 {PVEFrameTab2, PVPQueueFrameHandler},
                 {PVEFrameTab3, ChallengesFrameHandler},
                 {PVEFrameTab4, DelvesDashboardFrameHandler}}
end

function PVEFrameHandler:OnShow()
    local tab_index = PVEFrame.activeTabIndex
    if not tab_index then return end  -- Not initialized on first open.
    assert(tab_index and tab_index >= 1 and tab_index <= #self.tabs)
    local tab = self.tabs[tab_index][2].instance
    assert(tab:GetFrame():IsShown())
    tab:OnShow()
end

function PVEFrameHandler:OnHide()
    local tab_index = PVEFrame.activeTabIndex
    assert(tab_index and tab_index >= 1 and tab_index <= #self.tabs)
    local tab = self.tabs[tab_index][2].instance
    assert(tab:GetFrame():IsShown())
    tab:OnHide()
end

function PVEFrameHandler:OnTabCycle(direction)
    local new_index = (PVEFrame.activeTabIndex or 0) + direction
    if new_index < 1 then
        new_index = #self.tabs
    elseif new_index > #self.tabs then
        new_index = 1
    end
    PVEFrame_TabOnClick(self.tabs[new_index][1])
end


-- Annoyingly, some (but not all!) of the subframes are managed by their
-- own modules which are demand-loaded when the relevant tab is first
-- clicked - so we have to conditionally reimplement AddOnMenuFrame's
-- initializer here.
function PVETab.Initialize(class, cursor)
    class.cursor = cursor
    if class.ADDON_NAME then
        class:RegisterAddOnWatch(class.ADDON_NAME)
    else
        class:OnAddOnLoaded()
    end
end

function PVETab.OnAddOnLoaded(class)
    class.instance = class()
end

function PVETab:__constructor(frame)
    self:__super(frame)
    self.cancel_func = function() HideUIPanel(PVEFrame) end
    self.tab_handler =
        function(direction) PVEFrameHandler.instance:OnTabCycle(direction) end
end

function PVETab:OnShow()
    if not self.frame:IsVisible() then return end
    StandardMenuFrame.OnShow(self)
end

---------------------------------------------------------------------------


-------- Group finder tab

function GroupFinderFrameHandler:__constructor()
    self:__super(GroupFinderFrame)
end


-------- PVP tab

PVPQueueFrameHandler.ADDON_NAME = "Blizzard_PVPUI"
function PVPQueueFrameHandler:__constructor()
    self:__super(PVPQueueFrame)
end


-------- Mythic dungeon tab

ChallengesFrameHandler.ADDON_NAME = "Blizzard_ChallengesUI"
function ChallengesFrameHandler:__constructor()
    self:__super(ChallengesFrame)
end


-------- Delves tab

DelvesDashboardFrameHandler.ADDON_NAME = "Blizzard_DelvesDashboardUI"
function DelvesDashboardFrameHandler:__constructor()
    self:__super(DelvesDashboardFrame)
    local configure = (DelvesDashboardFrame.ButtonPanelLayoutFrame
                       .CompanionConfigButtonPanel.CompanionConfigButton)
    local rewards = (DelvesDashboardFrame.ButtonPanelLayoutFrame
                     .GreatVaultButtonPanel.GreatVaultButton)
    self.targets = {
        [configure] = {can_activate = true, lock_highlight = true,
                       is_default = true, up = false, down = false,
                       left = rewards, right = rewards},
        [rewards] = {on_click = self.OnClickRewards,
                     on_enter = self.OnEnterRewards,
                     on_leave = self.OnLeaveRewards,
                     up = false, down = false,
                     left = configure, right = configure},
    }
end

function DelvesDashboardFrameHandler.OnEnterRewards()
    local rewards = (DelvesDashboardFrame.ButtonPanelLayoutFrame
                     .GreatVaultButtonPanel.GreatVaultButton)
    rewards:OnEnter()
    rewards:LockHighlight()
end

function DelvesDashboardFrameHandler.OnLeaveRewards()
    local rewards = (DelvesDashboardFrame.ButtonPanelLayoutFrame
                     .GreatVaultButtonPanel.GreatVaultButton)
    rewards:UnlockHighlight()
    rewards:OnLeave()
end

function DelvesDashboardFrameHandler.OnClickRewards()
    local rewards = (DelvesDashboardFrame.ButtonPanelLayoutFrame
                     .GreatVaultButtonPanel.GreatVaultButton)
    rewards:OnMouseUp("LeftButton", true)
end
