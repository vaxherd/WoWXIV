local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

---------------------------------------------------------------------------

local VoidStoragePurchaseFrameHandler = class(MenuCursor.AddOnMenuFrame)
VoidStoragePurchaseFrameHandler.ADDON_NAME = "Blizzard_VoidStorageUI"
MenuCursor.Cursor.RegisterFrameHandler(VoidStoragePurchaseFrameHandler)

function VoidStoragePurchaseFrameHandler:__constructor()
    __super(self, VoidStoragePurchaseFrame)
    self.cancel_func = function() HideUIPanel(VoidStorageFrame) end
    self.targets = {
        [VoidStoragePurchaseButton] = {
            can_activate = true, lock_highlight = true, is_default = true,
            up = false, down = false, left = false, right = false},
    }
end
