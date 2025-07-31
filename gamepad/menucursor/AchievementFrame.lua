local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

---------------------------------------------------------------------------

local AchievementFrameHandler = class(MenuCursor.AddOnMenuFrame)
AchievementFrameHandler.ADDON_NAME = "Blizzard_AchievementUI"
MenuCursor.Cursor.RegisterFrameHandler(AchievementFrameHandler)


function AchievementFrameHandler:__constructor()
    __super(self, AchievementFrame)
    self.tab_handler = function(direction) self:OnTabCycle(direction) end
end

function AchievementFrameHandler.CancelMenu()  -- Static method.
    HideUIPanel(AchievementFrame)
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
