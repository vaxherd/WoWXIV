local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

---------------------------------------------------------------------------

-- We handle cursor movement a bit unusually for this frame.  There's one
-- usefully targetable UI element, which is the "gear" button that brings
-- up a "Report" submenu, but if we default the cursor to that element, it
-- covers up part of the address.  So instead we default to having nothing
-- targeted (cursor hidden), and respond to any D-pad press by targeting
-- the gear button.  (We don't currently attempt to support the submenu
-- itself.)

local HousingCornerstoneHouseInfoFrameHandler = class(MenuCursor.AddOnMenuFrame)
HousingCornerstoneHouseInfoFrameHandler.ADDON_NAME = "Blizzard_HousingCornerstone"
MenuCursor.Cursor.RegisterFrameHandler(HousingCornerstoneHouseInfoFrameHandler)

function HousingCornerstoneHouseInfoFrameHandler:__constructor()
    __super(self, HousingCornerstoneHouseInfoFrame)
    self.cancel_func = self.OnCancel
    self.cancel_button = nil
end

function HousingCornerstoneHouseInfoFrameHandler:SetTargets()
    local function SendClick(button)
        -- Click forwarding doesn't work for this (the menu is opened via
        -- DropDownButton:OnMouseDown_Intrinsic()).
        button:SetMenuOpen(not button:IsMenuOpen())
    end
    self.targets = {
        [self.frame.GearDropdown] =
            {on_click = SendClick, lock_highlight = true},
    }
    return nil
end

function HousingCornerstoneHouseInfoFrameHandler:NextTarget(target, direction)
    return self.frame.GearDropdown
end

function HousingCornerstoneHouseInfoFrameHandler:OnCancel()
    if self:GetTarget() then
        self.frame.GearDropdown:CloseMenu()
        self:SetTarget(nil)
    else
        self:CancelUIFrame()
    end
end
