local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

local GameTooltip = GameTooltip

---------------------------------------------------------------------------

local PlayerChoiceFrameHandler = class(MenuCursor.AddOnMenuFrame)
local PlayerChoiceToggleButtonHandler = class(MenuCursor.StandardMenuFrame)
local TorghastPlayerChoiceToggleButtonHandler = class(MenuCursor.StandardMenuFrame)
local CypherPlayerChoiceToggleButtonHandler = class(MenuCursor.StandardMenuFrame)

PlayerChoiceFrameHandler.ADDON_NAME = "Blizzard_PlayerChoice"
MenuCursor.Cursor.RegisterFrameHandler(PlayerChoiceFrameHandler)

function PlayerChoiceFrameHandler.OnAddOnLoaded(class)
    __super(class)
    class.instance_ToggleButton = PlayerChoiceToggleButtonHandler(GenericPlayerChoiceToggleButton)
    class.instance_TorghastToggleButton = PlayerChoiceToggleButtonHandler(TorghastPlayerChoiceToggleButton)
    class.instance_CypherToggleButton = PlayerChoiceToggleButtonHandler(CypherPlayerChoiceToggleButton)
end


function PlayerChoiceFrameHandler:__constructor()
    __super(self, PlayerChoiceFrame)
    self.has_Button3 = false  -- Used to select Reroll button in Torghast.
    self:RegisterEvent("PLAYER_CHOICE_UPDATE")
    self.current_option = nil  -- ID of currently selected option
end

-- Returns the numeric ID associated with a choice button.
-- The proper table and field varies with dialog type.
function PlayerChoiceFrameHandler:ButtonID(button)
    if self.frame.optionFrameTemplate == "PlayerChoiceTorghastOptionTemplate" then
        return button:GetParent():GetParent():GetParent().layoutIndex
    else
        return button.optionID
    end
end

function PlayerChoiceFrameHandler:PLAYER_CHOICE_UPDATE()
    if self.frame:IsShown() then
        self:ClearTarget()
        self:SetTarget(self:SetTargets(self.current_option))
    end
end

function PlayerChoiceFrameHandler:OnShow()
    self.current_option = nil
    __super(self)
end

function PlayerChoiceFrameHandler:SetTargets(initial_option)
    local KNOWN_FORMATS = {  -- Only handle formats we've explicitly verified.
        -- Weekly quest choice, etc.
        PlayerChoiceNormalOptionTemplate = true,
        -- Cobalt anima powers, Superbloom dreamfruit, etc.
        PlayerChoiceGenericPowerChoiceOptionTemplate = true,
        -- Torghast anima powers
        PlayerChoiceTorghastOptionTemplate = true,
        -- Zereth Mortis cypher powers
        PlayerChoiceCypherOptionTemplate = true,
    }
    if not KNOWN_FORMATS[PlayerChoiceFrame.optionFrameTemplate] then
        return false
    end

    self.targets = {}
    local buttons = {}
    local rewards = {}
    for option in PlayerChoiceFrame.optionPools:EnumerateActiveByTemplate(PlayerChoiceFrame.optionFrameTemplate) do
        for bframe in option.OptionButtonsContainer.buttonFramePool:EnumerateActive() do
            local button = bframe.Button
            -- The button order can change on confirmation (when the
            -- non-chosen buttons are hidden), so we add a post-click
            -- callback to hide the menu cursor immediately and prevent it
            -- from going to strange places.
            self.targets[button] = {can_activate = true, lock_highlight = true,
                                    on_click = function() self:Disable() end}
            if PlayerChoiceFrame.optionFrameTemplate == "PlayerChoiceTorghastOptionTemplate" then
                self.targets[button].on_enter = function()
                    if not GameTooltip:IsForbidden() then
                        if option.OptionText:IsTruncated() then
                            option:OnEnter()
                        end
                    end
                end
                self.targets[button].on_leave = self.HideTooltip
            else
                self.targets[button].send_enter_leave = true
            end
            tinsert(buttons, button)
            if option.WidgetContainer:IsShown() then
                self:AddWidgetTargets(option.WidgetContainer,
                                      {"Spell","Item","Bar"},
                                      button, button, false, false)
                -- FIXME: We don't currently support moving left/right
                -- between widgets from different choices.  This would
                -- probably require context-specific logic to get right,
                -- or just accepting the possibly-awkward default behavior
                -- by clearing left/right fields from widget targets.
            end
            -- This appears to only be used in the Vindicaar at the moment?
            if option.Rewards then
                for reward in option.Rewards.rewardsPool:EnumerateActive() do
                    assert(not rewards[button])
                    rewards[button] = reward
                    self.targets[reward] = {send_enter_leave = true,
                                            up = button}
                    self.targets[button].down = reward
                end
            end
        end
    end
    if #buttons == 0 then return false end -- Ignore frame if no buttons found.
    local initial_button
    table.sort(buttons, function(a,b) return a:GetLeft() < b:GetLeft() end)
    for i, button in ipairs(buttons) do
        self.targets[button].left = buttons[i==1 and #buttons or i-1]
        self.targets[button].right = buttons[i==#buttons and 1 or i+1]
        if rewards[button] then
            local reward = rewards[button]
            self.targets[reward].left = rewards[self.targets[button].left]
            self.targets[reward].right = rewards[self.targets[button].right]
        end
        if initial_option and self:ButtonID(button) == initial_option then
            initial_button = button
        end
    end

    local target = initial_button or buttons[1]
    self.current_option = self:ButtonID(target)

    self.has_Button3 = false
    if PlayerChoiceFrame.optionFrameTemplate == "PlayerChoiceTorghastOptionTemplate" then
        local reroll = TorghastPlayerChoiceToggleButton.RerollButton
        if reroll:IsShown() then
            self.has_Button3 = true
            local function CloseRerollTutorial()
                -- See PlayerChoiceRerollButtonMixin:OnShow().
                C_CVar.SetCVarBitfield("closedInfoFrames",
                                       LE_FRAME_TUTORIAL_TORGHAST_REROLL, true)
                HelpTip:HideAll(reroll)
            end
            self.targets[reroll] = {can_activate = true, lock_highlight = true,
                                    on_click = CloseRerollTutorial,
                                    x_offset = 95, up = target, down = target,
                                    left = false, right = false}
            for _, button in ipairs(buttons) do
                self.targets[button].up = reroll
                self.targets[button].down = reroll
            end
        end
    end

    return target
end

function PlayerChoiceFrameHandler:OnMove(old_target, new_target)
    local reroll = TorghastPlayerChoiceToggleButton.RerollButton
    if new_target == reroll then
        for button, _ in pairs(self.targets) do
            if button ~= reroll and self:ButtonID(button) == self.current_option then
                self.targets[reroll].up = button
                self.targets[reroll].down = button
                break
            end
        end
    else
        self.current_option = self:ButtonID(new_target)
    end
end

function PlayerChoiceFrameHandler:OnAction(action)
    assert(action == "Button3")
    local reroll = TorghastPlayerChoiceToggleButton.RerollButton
    assert(reroll:IsShown())
    assert(self.targets[reroll])
    self:OnMove(self:GetTarget(), reroll)
    self:SetTarget(reroll)
end


function PlayerChoiceToggleButtonHandler:__constructor(button)
    __super(self, button, MenuCursor.MenuFrame.NOAUTOFOCUS)
    self.cancel_func = function()
        -- Leave the button active so we can select it again later.
        self:Unfocus()
    end
    self.targets = {
        [self.frame] = {can_activate = true, is_default = true,
                        send_enter_leave = true},
    }
    hooksecurefunc(self.frame.Text, "SetText",
                   function() self:UpdateButtonOffset() end)
end

function PlayerChoiceToggleButtonHandler:UpdateButtonOffset()
    self.targets[self.frame].x_offset =
        self.frame.Text:GetLeft() - self.frame:GetLeft()
end

function PlayerChoiceToggleButtonHandler:OnShow()
    __super(self)
    if PlayerChoiceFrame:IsShown() then
        PlayerChoiceFrameHandler.instance:Focus()
    end
end
