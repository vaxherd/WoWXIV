local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

---------------------------------------------------------------------------

local AbandonHouseConfirmationDialogHandler = class(MenuCursor.AddOnMenuFrame)
AbandonHouseConfirmationDialogHandler.ADDON_NAME = "Blizzard_HousingHouseSettings"
MenuCursor.Cursor.RegisterFrameHandler(AbandonHouseConfirmationDialogHandler)

function AbandonHouseConfirmationDialogHandler:__constructor()
    __super(self, AbandonHouseConfirmationDialog)
    local f = self.frame
    self.cancel_func = nil
    self.cancel_button = f.CancelButton
    self.targets = {
        [f.ConfirmButton] = {can_activate = true, lock_highlight = true,
                             left = f.CancelButton, right = f.CancelButton},
        [f.CancelButton] = {is_default = true,  -- Default to the safe choice.
                            can_activate = true, lock_highlight = true,
                            left = f.ConfirmButton, right = f.ConfirmButton},
    }
end
