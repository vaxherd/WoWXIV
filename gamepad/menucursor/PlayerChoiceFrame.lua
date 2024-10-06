local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor
local Cursor = MenuCursor.Cursor
local MenuFrame = MenuCursor.MenuFrame
local CoreMenuFrame = MenuCursor.CoreMenuFrame
local AddOnMenuFrame = MenuCursor.AddOnMenuFrame

local class = WoWXIV.class

local GameTooltip = GameTooltip

---------------------------------------------------------------------------

local PlayerChoiceFrameHandler = class(AddOnMenuFrame)
PlayerChoiceFrameHandler.ADDON_NAME = "Blizzard_PlayerChoice"
Cursor.RegisterFrameHandler(PlayerChoiceFrameHandler)

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
                self.targets[button].on_leave = MenuFrame.HideTooltip
            else
                self.targets[button].send_enter_leave = true
            end
            if not leftmost or button:GetLeft() < leftmost:GetLeft() then
                leftmost = button
            end
            if option.WidgetContainer:IsShown() then
                MenuFrame.AddWidgetTargets(option.WidgetContainer, {"Spell","Bar"},
                                           self.targets, button, button, false, false)
            end
        end
    end
    return leftmost or false  -- Ignore frame if no buttons found.
end
