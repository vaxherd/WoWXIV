local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor
local Cursor = MenuCursor.Cursor

local class = WoWXIV.class

local GameTooltip = GameTooltip

---------------------------------------------------------------------------

local PlayerChoiceFrameHandler = class(MenuCursor.AddOnMenuFrame)
local GenericPlayerChoiceToggleButtonHandler = class(MenuCursor.StandardMenuFrame)
local CypherPlayerChoiceToggleButtonHandler = class(MenuCursor.StandardMenuFrame)

PlayerChoiceFrameHandler.ADDON_NAME = "Blizzard_PlayerChoice"
MenuCursor.Cursor.RegisterFrameHandler(PlayerChoiceFrameHandler)

function PlayerChoiceFrameHandler.OnAddOnLoaded(class)
    MenuCursor.AddOnMenuFrame.OnAddOnLoaded(class)
    class.instance_ToggleButton = GenericPlayerChoiceToggleButtonHandler()
    class.instance_CypherToggleButton = CypherPlayerChoiceToggleButtonHandler()
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
        -- Zereth Mortis cypher powers
        PlayerChoiceCypherOptionTemplate = true,
    }
    if not KNOWN_FORMATS[PlayerChoiceFrame.optionFrameTemplate] then
        return false
    end

    self.targets = {}
    local buttons = {}
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
                self.targets[button].on_leave = self.HideTooltip
            else
                self.targets[button].send_enter_leave = true
            end
            tinsert(buttons, button)
            if option.WidgetContainer:IsShown() then
                self:AddWidgetTargets(option.WidgetContainer, {"Spell","Bar"},
                                      button, button, false, false)
                -- FIXME: We don't currently support moving left/right
                -- between widgets from different choices.  This would
                -- probably require context-specific logic to get right,
                -- or just accepting the possibly-awkward default behavior
                -- by clearing left/right fields from widget targets.
            end
        end
    end
    if #buttons == 0 then return nil end  -- Ignore frame if no buttons found.
    table.sort(buttons, function(a,b) return a:GetLeft() < b:GetLeft() end)
    for i, button in ipairs(buttons) do
        self.targets[button].left = buttons[i==1 and #buttons or i-1]
        self.targets[button].right = buttons[i==#buttons and 1 or i+1]
    end
    return buttons[1]
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


function CypherPlayerChoiceToggleButtonHandler:__constructor()
    self:__super(CypherPlayerChoiceToggleButton)
    self.cancel_func = function()
        -- Leave the button active so we can select it again later.
        self:Unfocus()
    end
    self.targets = {
        [self.frame] = {can_activate = true, is_default = true,
                        send_enter_leave = true}
    }
end

function CypherPlayerChoiceToggleButtonHandler:OnShow()
    MenuCursor.StandardMenuFrame.OnShow(self)
    if PlayerChoiceFrame:IsShown() then
        PlayerChoiceFrameHandler.instance:Focus()
    end
end
