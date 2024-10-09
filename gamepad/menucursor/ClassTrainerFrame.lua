local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

---------------------------------------------------------------------------

local ClassTrainerFrameHandler = class(MenuCursor.AddOnMenuFrame)
ClassTrainerFrameHandler.ADDON_NAME = "Blizzard_TrainerUI"
MenuCursor.Cursor.RegisterFrameHandler(ClassTrainerFrameHandler)

function ClassTrainerFrameHandler:__constructor()
    self:__super(ClassTrainerFrame)
    self.targets = {
        [ClassTrainerFrameSkillStepButton] = {
            can_activate = true, lock_highlight = true,
            up = ClassTrainerTrainButton},
        [ClassTrainerTrainButton] = {
            can_activate = true, lock_highlight = true, is_default = true,
            down = ClassTrainerFrameSkillStepButton},
    }
end

function ClassTrainerFrameHandler:SetTargets()
    -- FIXME: also allow moving through list (ClassTrainerFrame.ScrollBox)
    -- (this temporary hack selects the first item so that we can still train)
    RunNextFrame(function()
        for _, frame in ClassTrainerFrame.ScrollBox:EnumerateFrames() do
            ClassTrainerSkillButton_OnClick(frame, "LeftButton")
            break
        end
    end)
end
