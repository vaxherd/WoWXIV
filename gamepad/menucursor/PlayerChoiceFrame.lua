local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor
local Cursor = MenuCursor.Cursor

local class = WoWXIV.class

local GameTooltip = GameTooltip

---------------------------------------------------------------------------

local PlayerChoiceFrameHandler = class(MenuCursor.AddOnMenuFrame)
local GenericPlayerChoiceToggleButtonHandler = class(MenuCursor.StandardMenuFrame)

PlayerChoiceFrameHandler.ADDON_NAME = "Blizzard_PlayerChoice"
MenuCursor.Cursor.RegisterFrameHandler(PlayerChoiceFrameHandler)

function PlayerChoiceFrameHandler.OnAddOnLoaded(class)
    MenuCursor.AddOnMenuFrame.OnAddOnLoaded(class)
    class.instance_ToggleButton = GenericPlayerChoiceToggleButtonHandler()
end


function PlayerChoiceFrameHandler:__constructor()
    self:__super(PlayerChoiceFrame)
end

function PlayerChoiceFrameHandler:SetTargets()
    local KNOWN_FORMATS = {  -- Only handle formats we've explicitly verified.
        -- Weekly quest choice, etc.
        PlayerChoiceNormalOptionTemplate = true,
        -- Cobalt anima powers, Superbloom dreamfruit, etc.
        PlayerChoiceGenericPowerChoiceOptionTemplate = true,
        -- Torghast anima powers
        PlayerChoiceTorghastOptionTemplate = true,
    }
    if not KNOWN_FORMATS[PlayerChoiceFrame.optionFrameTemplate] then
        return false
    end

    self.targets = {}
    local leftmost = nil
    for option in PlayerChoiceFrame.optionPools:EnumerateActiveByTemplate(PlayerChoiceFrame.optionFrameTemplate) do
        for button in option.OptionButtonsContainer.buttonPool:EnumerateActive() do
            self.targets[button] = {can_activate = true,
                                    lock_highlight = true}
            if PlayerChoiceFrame.optionFrameTemplate == "PlayerChoiceTorghastOptionTemplate" then
                self.targets[button].on_enter = function()
                    if not GameTooltip:IsForbidden() then
                        if option.OptionText:IsTruncated() then
                            option:OnEnter()
                        end
                    end
                end
                self.targets[button].on_leave = MenuCursor.MenuFrame.HideTooltip
            else
                self.targets[button].send_enter_leave = true
            end
            if not leftmost or button:GetLeft() < leftmost:GetLeft() then
                leftmost = button
            end
            if option.WidgetContainer:IsShown() then
                self:AddWidgetTargets(option.WidgetContainer, {"Spell","Bar"},
                                      button, button, false, false)
            end
        end
    end
    return leftmost or false  -- Ignore frame if no buttons found.
end


function GenericPlayerChoiceToggleButtonHandler:__constructor()
    self:__super(GenericPlayerChoiceToggleButton)
    self.cancel_func = function()
        -- Leave the button active so we can select it again later.
        self:Unfocus()
    end
    self.targets = {
        [self.frame] = {can_activate = true, is_default = true,
                        send_enter_leave = true}
    }
end

function GenericPlayerChoiceToggleButtonHandler:OnShow()
    MenuCursor.StandardMenuFrame.OnShow(self)
    if PlayerChoiceFrame:IsShown() then
        PlayerChoiceFrameHandler.instance:Focus()
    end
end
