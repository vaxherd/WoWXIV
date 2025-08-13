local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

local tinsert = tinsert

---------------------------------------------------------------------------

-- The wrapper frame doesn't have any input elements of its own other than
-- the tabs.  We use this class to hold the tab switch handler and to pass
-- down show/hide events from the wrapper frame to the initially active tab.
-- We also set up a PVETab subclass of StandardMenuFrame which includes
-- common behaviors for all subframes.

local PVEFrameHandler = class(MenuCursor.CoreMenuFrame)
local PVETab = class(MenuCursor.StandardMenuFrame)
local GroupFinderFrameHandler = class(PVETab)
local PVPUIFrameHandler = class(PVETab)
local ChallengesFrameHandler = class(PVETab)
local DelvesDashboardFrameHandler = class(PVETab)
MenuCursor.Cursor.RegisterFrameHandler(PVEFrameHandler)
MenuCursor.Cursor.RegisterFrameHandler(GroupFinderFrameHandler)
MenuCursor.Cursor.RegisterFrameHandler(PVPUIFrameHandler)
MenuCursor.Cursor.RegisterFrameHandler(ChallengesFrameHandler)
MenuCursor.Cursor.RegisterFrameHandler(DelvesDashboardFrameHandler)

function PVEFrameHandler:__constructor()
    __super(self, PVEFrame)
    self.tabs = {{PVEFrameTab1, GroupFinderFrameHandler},
                 {PVEFrameTab2, PVPUIFrameHandler},
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
    __super(self, frame)
    self.cancel_func = function() HideUIPanel(PVEFrame) end
    self.tab_handler =
        function(direction) PVEFrameHandler.instance:OnTabCycle(direction) end
end

---------------------------------------------------------------------------


-------- Group finder tab

function GroupFinderFrameHandler:__constructor()
    __super(self, GroupFinderFrame)
end


-------- PVP tab

PVPUIFrameHandler.ADDON_NAME = "Blizzard_PVPUI"
function PVPUIFrameHandler:__constructor()
    __super(self, PVPUIFrame)
end


-------- Mythic dungeon tab

ChallengesFrameHandler.ADDON_NAME = "Blizzard_ChallengesUI"
function ChallengesFrameHandler:__constructor()
    __super(self, ChallengesFrame)
end


-------- Delves tab

DelvesDashboardFrameHandler.ADDON_NAME = "Blizzard_DelvesDashboardUI"
function DelvesDashboardFrameHandler:__constructor()
    __super(self, DelvesDashboardFrame)
end

function DelvesDashboardFrameHandler:SetTargets()
    local f = self.frame
    local bar = f.ThresholdBar
    local configure = (f.ButtonPanelLayoutFrame
                       .CompanionConfigButtonPanel.CompanionConfigButton)
    local rewards = (f.ButtonPanelLayoutFrame
                     .GreatVaultButtonPanel.GreatVaultButton)
    self.targets = {
        [bar] = {on_enter = self.OnEnterThresholdBar,
                 on_leave = self.OnLeaveThresholdBar,
                 is_default = true,
                 up = configure, down = configure},
        [configure] = {can_activate = true, lock_highlight = true,
                       up = bar, down = bar, left = rewards, right = rewards},
        [rewards] = {on_click = self.OnClickWeeklyRewards,
                     on_enter = self.OnEnterWeeklyRewards,
                     on_leave = self.OnLeaveWeeklyRewards,
                     up = bar, down = bar,
                     left = configure, right = configure},
    }
    local function ThresholdReward(n)
        local threshold = bar["Threshold"..n]
        return threshold and threshold.Reward
    end
    for i = 1, 10 do
        local reward = ThresholdReward(i)
        local left = i==1 and bar or ThresholdReward(i-1)
        local right = i==10 and bar or ThresholdReward(i+1)
        self.targets[reward] = {send_enter_leave = true,
                                up = configure, down = configure,
                                left = left, right = right}
    end
    self.targets[bar].left = ThresholdReward(10)
    self.targets[bar].right = ThresholdReward(1)
end

-- The threshold bar uses an ANCHOR_CURSOR_RIGHT tooltip, so we have to
-- override that.
function DelvesDashboardFrameHandler.OnEnterThresholdBar()
    local bar = DelvesDashboardFrame.ThresholdBar
    -- Since GameTooltip doesn't have a way to just change the anchor
    -- and SetOwner() will clear the contents, we have to intercept
    -- the tooltip calls.  Thankfully, all references to GameTooltip
    -- are directly in OnEnter(), so we can just call it with a custom
    -- environment.
    local GameTooltip = GameTooltip
    local wrapped_GameTooltip = {
        SetOwner = function(self, owner, anchor)
            -- Place it above the season label.
            local offset = (owner:GetParent().ReputationBarTitle:GetTop()
                            - owner:GetTop())
            GameTooltip:SetOwner(owner, "ANCHOR_TOPLEFT", 0, offset)
        end,
    }
    for _, funcname in ipairs({"SetMinimumWidth", "AddLine", "Show"}) do
        wrapped_GameTooltip[funcname] = function(self, ...)
            GameTooltip[funcname](GameTooltip, ...)
        end
    end
    local env = {GameTooltip = wrapped_GameTooltip}
    WoWXIV.envcall(WoWXIV.makefenv(env), bar.OnEnter, bar)
end

function DelvesDashboardFrameHandler.OnLeaveThresholdBar()
    local bar = DelvesDashboardFrame.ThresholdBar
    bar:OnLeave()
end

-- The Great Vault button isn't a standard button, so we have to
-- manage its highlight and send clicks manually.
function DelvesDashboardFrameHandler.OnEnterWeeklyRewards()
    local rewards = (DelvesDashboardFrame.ButtonPanelLayoutFrame
                     .GreatVaultButtonPanel.GreatVaultButton)
    rewards:OnEnter()
    rewards:LockHighlight()
end

function DelvesDashboardFrameHandler.OnLeaveWeeklyRewards()
    local rewards = (DelvesDashboardFrame.ButtonPanelLayoutFrame
                     .GreatVaultButtonPanel.GreatVaultButton)
    rewards:UnlockHighlight()
    rewards:OnLeave()
end

function DelvesDashboardFrameHandler.OnClickWeeklyRewards()
    local rewards = (DelvesDashboardFrame.ButtonPanelLayoutFrame
                     .GreatVaultButtonPanel.GreatVaultButton)
    rewards:OnMouseUp("LeftButton", true)
end
