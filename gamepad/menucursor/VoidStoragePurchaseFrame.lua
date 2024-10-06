local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor
local Cursor = MenuCursor.Cursor
local MenuFrame = MenuCursor.MenuFrame
local CoreMenuFrame = MenuCursor.CoreMenuFrame
local AddOnMenuFrame = MenuCursor.AddOnMenuFrame

local class = WoWXIV.class

---------------------------------------------------------------------------

local VoidStoragePurchaseFrameHandler = class(AddOnMenuFrame)
VoidStoragePurchaseFrameHandler.ADDON_NAME = "Blizzard_VoidStorageUI"
Cursor.RegisterFrameHandler(VoidStoragePurchaseFrameHandler)

function VoidStoragePurchaseFrameHandler:__constructor()
    self:__super(VoidStoragePurchaseFrame)
    self.cancel_func = function() HideUIPanel(VoidStorageFrame) end
    self.targets = {
        [VoidStoragePurchaseButton] = {
            can_activate = true, lock_highlight = true, is_default = true,
            up = false, down = false, left = false, right = false},
    }
end
