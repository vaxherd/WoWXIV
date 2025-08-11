local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

---------------------------------------------------------------------------

local cache_DelvesDifficultyDropdown = {}

local DelvesDifficultyPickerFrameHandler = class(MenuCursor.AddOnMenuFrame)
DelvesDifficultyPickerFrameHandler.ADDON_NAME = "Blizzard_DelvesDifficultyPicker"
MenuCursor.Cursor.RegisterFrameHandler(DelvesDifficultyPickerFrameHandler)

function DelvesDifficultyPickerFrameHandler:__constructor()
    __super(self, DelvesDifficultyPickerFrame)
end

function DelvesDifficultyPickerFrameHandler:OnShow()
    assert(DelvesDifficultyPickerFrame:IsShown())
    self.targets = {}
    self:Enable()
    self:RefreshTargets()
end

local cache_DelvesDifficultyDropdown = {}
function DelvesDifficultyPickerFrameHandler:ToggleDropdown()
    local ddpf = DelvesDifficultyPickerFrame
    local dropdown = ddpf.Dropdown

    dropdown:SetMenuOpen(not dropdown:IsMenuOpen())
    if dropdown:IsMenuOpen() then
        local menu, initial_target = self.SetupDropdownMenu(
            dropdown, cache_DelvesDifficultyDropdown,
            function(selection)
                return selection.data and selection.data.orderIndex + 1
            end,
            function() self:RefreshTargets() end)
        menu:Enable(initial_target)
    end
end

function DelvesDifficultyPickerFrameHandler:RefreshTargets()
    local ddpf = DelvesDifficultyPickerFrame
    local Dropdown = ddpf.Dropdown
    local EnterDelveButton = ddpf.EnterDelveButton

    self.targets = {
        [Dropdown] = {
            on_click = function() self:ToggleDropdown() end,
            send_enter_leave = true,
            left = false, right = false, up = EnterDelveButton},
        [EnterDelveButton] = {
            can_activate = true, send_enter_leave = true,
            left = false, right = false, down = Dropdown},
    }

    local first_rewards, last_reward
    if ddpf.DelveRewardsContainerFrame:IsShown() then
        first_reward, last_reward = self:AddScrollBoxTargets(
            ddpf.DelveRewardsContainerFrame.ScrollBox,
            function(data)
                return {send_enter_leave = true, right = false}
            end)
        self.targets[Dropdown].right = first_reward
        self.targets[EnterDelveButton].right = last_reward
    else
        -- Either no difficulty selected or rewards have not been loaded yet.
        local function TryRewards()
            if ddpf.DelveRewardsContainerFrame:IsShown() then
                self:RefreshTargets()
            else
                RunNextFrame(TryRewards)
            end
        end
        RunNextFrame(TryRewards)
    end

    local dmwc = ddpf.DelveModifiersWidgetContainer
    if dmwc:IsShown() then
        self:AddWidgetTargets(dmwc, {"Spell"}, Dropdown, EnterDelveButton,
                              false, first_reward or false)
    end

    if not initial_target then
        initial_target = (EnterDelveButton:IsEnabled() and EnterDelveButton
                          or Dropdown)
    end
    self:SetTarget(initial_target)
end
