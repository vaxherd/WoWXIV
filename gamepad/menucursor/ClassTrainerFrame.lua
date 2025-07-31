local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

---------------------------------------------------------------------------

local ClassTrainerFrameHandler = class(MenuCursor.AddOnMenuFrame)
ClassTrainerFrameHandler.ADDON_NAME = "Blizzard_TrainerUI"
MenuCursor.Cursor.RegisterFrameHandler(ClassTrainerFrameHandler)

function ClassTrainerFrameHandler:__constructor()
    __super(self, ClassTrainerFrame)
    self:RegisterEvent("TRAINER_UPDATE")
end

function ClassTrainerFrameHandler:TRAINER_UPDATE()
    local target = self:GetTarget()
    self:SetTarget(nil)
    self:SetTargets()
    if target then
        if not self.targets[target] then
            target = ClassTrainerTrainButton
        end
        self:SetTarget(target)
    end
end

function ClassTrainerFrameHandler:SetTargets()
    self.targets = {
        [ClassTrainerTrainButton] = {
            can_activate = true, lock_highlight = true, is_default = true,
            up = false, down = false, left = false, right = false},
    }

    function OnClickRecipe(recipe)
        local button = self:GetTargetFrame(recipe)
        button:GetScript("OnClick")(button, "LeftButton", true)
        -- Immediately move to the "Train" button so the user doesn't have
        -- to scroll to the end of the list.
        self:SetTarget(ClassTrainerTrainButton)
    end
    local first, last =
        self:AddScrollBoxTargets(ClassTrainerFrame.ScrollBox, function(data)
            return {on_click = OnClickRecipe, lock_highlight = true,
                    send_enter_leave = true, left = false, right = false}
        end)
    if first and not self:GetTarget() then
        self.targets[first].up = ClassTrainerTrainButton
        self.targets[last].down = ClassTrainerTrainButton
        self.targets[ClassTrainerTrainButton].up = last
        self.targets[ClassTrainerTrainButton].down = first
        -- Immediately select the first item so we can just click "Train"
        -- to start learning recipes.
        ClassTrainerSkillButton_OnClick(self:GetTargetFrame(first),
                                        "LeftButton")
    end

    if ClassTrainerFrameSkillStepButton:IsShown() then
        self.targets[ClassTrainerFrameSkillStepButton] = {
            can_activate = true, lock_highlight = true,
            up = ClassTrainerTrainButton,
            down = first or ClassTrainerTrainButton,
            left = false, right = false}
        self.targets[ClassTrainerTrainButton].down =
            ClassTrainerFrameSkillStepButton
        self.targets[first or ClassTrainerTrainButton].up =
            ClassTrainerFrameSkillStepButton
    end
end
