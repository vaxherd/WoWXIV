local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

---------------------------------------------------------------------------

local AchievementFrameHandler = class(MenuCursor.AddOnMenuFrame)
AchievementFrameHandler.ADDON_NAME = "Blizzard_AchievementUI"
MenuCursor.Cursor.RegisterFrameHandler(AchievementFrameHandler)


function AchievementFrameHandler:__constructor()
    self.on_category = true  -- Is the cursor on the category list?
    self.cur_category = nil  -- ID of currently selected category
    self.cur_achievement = nil  -- ID of currently selected achievement

    __super(self, AchievementFrame)
    self.cancel_func = function() self:OnCancel() end
    self.tab_handler = function(direction) self:OnTabCycle(direction) end
    self.has_Button3 = true  -- Used to toggle between list subframes.
    self.has_Button4 = true  -- Used to toggle achievement tracking.
    hooksecurefunc("AchievementFrameCategories_UpdateDataProvider",
                   function() self:RefreshTargets() end)
    hooksecurefunc("AchievementFrameAchievements_UpdateDataProvider",
                   function() self:RefreshTargets() end)
end

function AchievementFrameHandler:OnCancel()
    if not self.on_category then
        self.on_category = true
        self:RefreshTargets()
    else
        HideUIPanel(AchievementFrame)
    end
end

function AchievementFrameHandler:OnTabCycle(direction)
    local new_index =
        (PanelTemplates_GetSelectedTab(self.frame) or 0) + direction
    if new_index < 1 then
        new_index = self.frame.numTabs
    elseif new_index > self.frame.numTabs then
        new_index = 1
    end
    -- AchievementFrame uses an even more outdated tab management style
    -- than PanelTemplates itself.
    --local tab = self.frame.Tabs[new_index]
    local tab = _G["AchievementFrameTab"..new_index]
    tab:GetScript("OnClick")(tab, "LeftButton", true)
end

function AchievementFrameHandler:ClickCategory(target)
    local button = self:GetTargetFrame(target)
    button.Button:Click("LeftButton", true)
    local data = button:GetElementData()
    if data.isChild then
        self:OnAction("Button3")  -- Move to achievement list.
    end
end

function AchievementFrameHandler:ClickAchievement(target)
    local button = self:GetTargetFrame(target)
    -- Clicking the achievement closed also clears the highlight, so do an
    -- explicit LeaveTarget/EnterTarget around the click.
    assert(target == self:GetTarget())
    self:LeaveTarget(target)
    button:Click("LeftButton", true)
    self:ScrollToTarget(target)  -- Might have expanded outside the frame.
    self:EnterTarget(target)
end

function AchievementFrameHandler:RefreshTargets()
    self:SetTarget(nil)
    self:SetTarget(self:SetTargets())
end

function AchievementFrameHandler:SetTargets()
    self.targets = {}
    local top, bottom, initial
    if self.on_category then
        local function ClickCategory(target)
            self:ClickCategory(target)
        end
        top, bottom, initial = self:AddScrollBoxTargets(
            AchievementFrameCategories.ScrollBox,
            function(data)
                local params = {on_click = ClickCategory,
                                send_enter_leave = true, lock_highlight = true}
                return params, data.id == self.cur_category
            end)
    else
        local function ClickAchievement(target)
            self:ClickAchievement(target)
        end
        top, bottom, initial = self:AddScrollBoxTargets(
            AchievementFrameAchievements.ScrollBox,
            function(data)
                local params = {on_click = ClickAchievement,
                                send_enter_leave = true}
                return params, data.id == self.cur_achievement
            end)
    end
    return initial or top
end

function AchievementFrameHandler:EnterTarget(target)
    __super(self, target)
    local f = self:GetTargetFrame(target)
    if self.on_category then
        self.cur_category = f.categoryID
    else
        self.cur_achievement = f.id
    end
end

function AchievementFrameHandler:OnAction(button)
    if button == "Button3" then
        self.on_category =
            AchievementFrameSummary:IsShown() or not self.on_category
        self:RefreshTargets()
    else
        assert(button == "Button4")
        if not self.on_category then
            local f = self:GetTargetFrame(self:GetTarget())
            if f.Tracked:IsVisible() then
                f.Tracked:Click("LeftButton", true)
            end
        end
    end
end
