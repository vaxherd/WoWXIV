local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

local tinsert = tinsert

---------------------------------------------------------------------------

local AdventureMapQuestChoiceDialogHandler = class(MenuCursor.AddOnMenuFrame)
AdventureMapQuestChoiceDialogHandler.ADDON_NAME = "Blizzard_AdventureMap"
MenuCursor.Cursor.RegisterFrameHandler(AdventureMapQuestChoiceDialogHandler)

function AdventureMapQuestChoiceDialogHandler:__constructor()
    __super(self, AdventureMapQuestChoiceDialog, MenuCursor.MenuFrame.MODAL)
    self.cancel_func = nil
    self.cancel_button = AdventureMapQuestChoiceDialog.DeclineButton
end

function AdventureMapQuestChoiceDialogHandler:SetTargets()
    local dialog = self.frame
    self.targets = {
        [dialog.AcceptButton] = {can_activate = true, lock_highlight = true,
                                 is_default = true},
        [dialog.DeclineButton] = {can_activate = true, lock_highlight = true},
    }
end
