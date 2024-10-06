local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor
local Cursor = MenuCursor.Cursor
local MenuFrame = MenuCursor.MenuFrame
local CoreMenuFrame = MenuCursor.CoreMenuFrame
local AddOnMenuFrame = MenuCursor.AddOnMenuFrame

local class = WoWXIV.class

---------------------------------------------------------------------------

local ClassTrainerFrameHandler = class(AddOnMenuFrame)
ClassTrainerFrameHandler.ADDON_NAME = "Blizzard_TrainerUI"
Cursor.RegisterFrameHandler(ClassTrainerFrameHandler)

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
