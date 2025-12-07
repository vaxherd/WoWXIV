local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

---------------------------------------------------------------------------

local HousingControlsFrameHandler = class(MenuCursor.AddOnMenuFrame)
HousingControlsFrameHandler.ADDON_NAME = "Blizzard_HousingControls"
MenuCursor.Cursor.RegisterFrameHandler(HousingControlsFrameHandler)

function HousingControlsFrameHandler:__constructor()
    __super(self, HousingControlsFrame)
    self.cancel_func = function() self:Unfocus() end
end

function HousingControlsFrameHandler:OnShow()
    -- We don't take input focus when first shown (but we do accept it
    -- when closing another frame).
    if not self:IsEnabled() then
        self:EnableBackground(self:SetTargets())
    end
end

function HousingControlsFrameHandler:SetTargets()
    if self.frame.VisitorControlFrame:IsShown() then
        local f = self.frame.VisitorControlFrame
        self.targets = {
            [f.InspectorButton] =
                {can_activate = true, lock_highlight = true,
                 send_enter_leave = true, up = false, down = false,
                 left = f.ExitButton},
            [f.VisitorHouseInfoButton] =
                {can_activate = true, lock_highlight = true, is_default = true,
                 send_enter_leave = true, up = false, down = false},
            [f.ExitButton] =
                {can_activate = true, lock_highlight = true,
                 send_enter_leave = true, up = false, down = false,
                 right = f.InspectorButton},
        }
    else
        local f = self.frame.OwnerControlFrame
        assert(f:IsShown())
        self.targets = {
            [f.InspectorButton] =
                {can_activate = true, lock_highlight = true,
                 send_enter_leave = true, up = false, down = false,
                 left = f.ExitButton},
            [f.HouseInfoButton] =
                {can_activate = true, lock_highlight = true,
                 send_enter_leave = true, up = false, down = false},
            [f.HouseEditorButton] =
                {can_activate = true, lock_highlight = true, is_default = true,
                 send_enter_leave = true, up = false, down = false},
            [f.SettingsButton] =
                {can_activate = true, lock_highlight = true,
                 send_enter_leave = true, up = false, down = false},
            [f.ExitButton] =
                {can_activate = true, lock_highlight = true,
                 send_enter_leave = true, up = false, down = false,
                 right = f.InspectorButton},
        }
    end
    return self:GetDefaultTarget()
end
