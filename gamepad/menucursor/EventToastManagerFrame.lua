local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

---------------------------------------------------------------------------

local EventToastManagerFrameHandler = class(MenuCursor.CoreMenuFrame)
MenuCursor.Cursor.RegisterFrameHandler(EventToastManagerFrameHandler)

function EventToastManagerFrameHandler:__constructor()
    self:__super(EventToastManagerFrame)
    self.cancel_func = nil
    self.cancel_button = self.frame.HideButton
    hooksecurefunc(self.frame, "Reset", function() self:OnHide() end)
end

function EventToastManagerFrameHandler:OnShow()
    if not self.frame.HideButton:IsShown() then return end
    local toast = self.frame.currentDisplayingToast
    assert(toast)
    if toast.uiTextureKit == "jailerstower-score" then
        self.mode = "Torghast"
    else
        return
    end
    MenuCursor.CoreMenuFrame.OnShow(self)
end

local function ClickToast(toast)
    local OnClick = toast:GetScript("OnClick")
    assert(OnClick)
    OnClick(toast, "LeftButton", true)
end

function EventToastManagerFrameHandler:SetTargets()
    local HideButton = self.frame.HideButton
    local hide_x, hide_y, _, hide_h = HideButton:GetRect()
    local text_x, text_y, _, text_h = HideButton.Text:GetRect()
    hide_y = hide_y + hide_h/2
    text_y = text_y + text_h/2
    self.targets = {
        [HideButton] = {
            can_activate = true, lock_highlight = true, is_default = true,
            -- Immediately hide cursor when clicking the Close button.
            on_click = function() self:Disable() end,
            x_offset = text_x - hide_x, y_offset = text_y - hide_y,
            up = false, down = false, left = false, right = false},
    }
    

    if self.mode == "Torghast" then
        local toast = self.frame.currentDisplayingToast
        local desc = toast.Description
        self.targets[desc] = {
            on_click = function() ClickToast(toast) end,
            up = HideButton, down = HideButton,
            x_offset = (desc:GetWidth() - desc:GetStringWidth()) / 2}
        self.targets[HideButton].up = desc
        self.targets[HideButton].down = desc
    end
end
