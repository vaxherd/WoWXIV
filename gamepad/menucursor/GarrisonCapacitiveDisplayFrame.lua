local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

---------------------------------------------------------------------------

local GarrisonCapacitiveDisplayFrameHandler = class(MenuCursor.AddOnMenuFrame)
GarrisonCapacitiveDisplayFrameHandler.ADDON_NAME = "Blizzard_GarrisonUI"
MenuCursor.Cursor.RegisterFrameHandler(GarrisonCapacitiveDisplayFrameHandler)

function GarrisonCapacitiveDisplayFrameHandler:__constructor()
    self:__super(GarrisonCapacitiveDisplayFrame)
    self.targets = {
        [GarrisonCapacitiveDisplayFrame.CreateAllWorkOrdersButton] =
            {can_activate = true, lock_highlight = true},
        [GarrisonCapacitiveDisplayFrame.DecrementButton] =
            {on_click = GarrisonCapacitiveDisplayFrameDecrement_OnClick,
             lock_highlight = true},
        [GarrisonCapacitiveDisplayFrame.IncrementButton] =
            {on_click = GarrisonCapacitiveDisplayFrameIncrement_OnClick,
             lock_highlight = true},
        [GarrisonCapacitiveDisplayFrame.StartWorkOrderButton] =
            {can_activate = true, lock_highlight = true,
             is_default = true},
    }
end
