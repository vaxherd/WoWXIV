local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor
local Cursor = MenuCursor.Cursor
local MenuFrame = MenuCursor.MenuFrame
local CoreMenuFrame = MenuCursor.CoreMenuFrame
local AddOnMenuFrame = MenuCursor.AddOnMenuFrame

local class = WoWXIV.class

---------------------------------------------------------------------------

local GarrisonCapacitiveDisplayFrameHandler = class(AddOnMenuFrame)
GarrisonCapacitiveDisplayFrameHandler.ADDON_NAME = "Blizzard_GarrisonUI"
Cursor.RegisterFrameHandler(GarrisonCapacitiveDisplayFrameHandler)

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
