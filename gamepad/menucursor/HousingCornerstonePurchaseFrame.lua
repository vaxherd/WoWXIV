local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

---------------------------------------------------------------------------

local HousingCornerstonePurchaseFrameHandler = class(MenuCursor.AddOnMenuFrame)
HousingCornerstonePurchaseFrameHandler.ADDON_NAME = "Blizzard_HousingCornerstone"
MenuCursor.Cursor.RegisterFrameHandler(HousingCornerstonePurchaseFrameHandler)

function HousingCornerstonePurchaseFrameHandler:__constructor()
    __super(self, HousingCornerstonePurchaseFrame)
    local f = self.frame
    self.targets = {
        [f.BuyButton] = {can_activate = true, lock_highlight = true,
                         is_default = true},
    }
end
