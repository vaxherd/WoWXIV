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
    self:__super(DelvesDifficultyPickerFrame)
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
        local menu, initial_target = MenuCursor.MenuFrame.SetupDropdownMenu(
            dropdown, cache_DelvesDifficultyDropdown,
            function(selection)
                return selection.data and selection.data.orderIndex + 1
            end,
            function () self:RefreshTargets() end)
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

    local rewards = {ddpf.DelveRewardsContainerFrame:GetChildren()}
    if ddpf.DelveRewardsContainerFrame:IsShown() and rewards and #rewards>0 then
        local first_reward, last_reward
        for _, f in ipairs(rewards) do
            if f:IsVisible() then
                self.targets[f] = {send_enter_leave = true, right = false}
                if not first_reward or f:GetTop() > first_reward:GetTop() then
                    first_reward = f
                end
                if not last_reward or f:GetTop() < last_reward:GetTop() then
                    last_reward = f
                end
            end
        end
        self.targets[Dropdown].right = first_reward
        self.targets[EnterDelveButton].right = last_reward
    else
        -- Either no difficulty selected or rewards have not been loaded yet.
        local function TryRewards()
            local rewards = {ddpf.DelveRewardsContainerFrame:GetChildren()}
            if ddpf.DelveRewardsContainerFrame:IsShown() and rewards and #rewards>0 then
                self:RefreshTargets()
            else
                RunNextFrame(TryRewards)
            end
        end
        RunNextFrame(TryRewards)
    end

    local dmwc = ddpf.DelveModifiersWidgetContainer
    if dmwc:IsShown() then
        self:AddWidgetTargets(dmwc, {"Spell"},
                              Dropdown, EnterDelveButton, false, nil)
    end

    if not initial_target then
        initial_target = (EnterDelveButton:IsEnabled() and EnterDelveButton
                          or Dropdown)
    end
    self:SetTarget(initial_target)
end
