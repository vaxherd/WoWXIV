local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

local GameTooltip = GameTooltip

---------------------------------------------------------------------------

local OpenMailFrameHandler = class(MenuCursor.CoreMenuFrame)
MenuCursor.Cursor.RegisterFrameHandler(OpenMailFrameHandler)

function OpenMailFrameHandler:__constructor()
    self:__super(OpenMailFrame)
    -- Note that the Hide event appears to fire sporadically even when the
    -- frame isn't shown in the first place.  RemoveFrame() ignores frames
    -- not in the focus list, so this isn't a problem for us and we don't
    -- need to override OnHide().
    self.cancel_func = nil
    self.cancel_button = OpenMailCancelButton
    for i = 1, 16 do
        local frame_name = "OpenMailAttachmentButton" .. i
        local frame = _G[frame_name]
        assert(frame)
        self:HookShow(frame, self.OnShowAttachmentButton,
                             self.OnHideAttachmentButton)
    end
    self:HookShow(OpenMailMoneyButton, self.OnShowMoneyButton,
                                       self.OnHideMoneyButton)
    self:HookShow(OpenMailLetterButton, self.OnShowLetterButton,
                                        self.OnHideLetterButton)
end

function OpenMailFrameHandler:OnShowAttachmentButton(frame)
    self.targets[frame] = {can_activate = true, lock_highlight = true,
                           send_enter_leave = true}
end

function OpenMailFrameHandler:OnHideAttachmentButton(frame)
    if self:GetTarget() == frame then
        local new_target = nil
        local id = frame:GetID() - 1
        while id >= 1 and not new_target do
            local button = _G["OpenMailAttachmentButton"..id]
            if button:IsShown() then new_target = button end
            id = id - 1
        end
        if not new_target and OpenMailMoneyButton:IsShown() then
            new_target = OpenMailMoneyButton
        end
        if not new_target and OpenMailLetterButton:IsShown() then
            new_target = OpenMailLetterButton
        end
        id = frame:GetID() + 1
        while id <= 16 and not new_target do
            local button = _G["OpenMailAttachmentButton"..id]
            if button:IsShown() then new_target = button end
            id = id + 1
        end
        self:SetTarget(new_target or OpenMailDeleteButton)
    end
    self.targets[frame] = nil
end

function OpenMailFrameHandler:OnShowMoneyButton(frame)
    self.targets[frame] = {
        can_activate = true, lock_highlight = true,
        on_enter = function(f)  -- hardcoded in XML
            if OpenMailFrame.money then
                GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
                SetTooltipMoney(GameTooltip, OpenMailFrame.money)
                GameTooltip:Show()
            end
        end,
        on_leave = self.HideTooltip,
    }
end

function OpenMailFrameHandler:OnHideMoneyButton(frame)
    if self:GetTarget() == frame then
        local new_target = nil
        if OpenMailLetterButton:IsShown() then
            new_target = OpenMailLetterButton
        end
        local id = 1
        while id <= 16 and not new_target do
            local button = _G["OpenMailAttachmentButton"..id]
            if button:IsShown() then new_target = button end
            id = id + 1
        end
        self:SetTarget(new_target or OpenMailDeleteButton)
    end
    self.targets[frame] = nil
end

function OpenMailFrameHandler:OnShowLetterButton(frame)
    self.targets[frame] = {
        can_activate = true, lock_highlight = true,
        on_enter = function(f)  -- hardcoded in XML
            GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
            GameTooltip:SetText(MAIL_LETTER_TOOLTIP)
            GameTooltip:Show()
        end,
        on_leave = self.HideTooltip,
    }
end

function OpenMailFrameHandler:OnHideLetterButton(frame)
    if self:GetTarget() == frame then
        local new_target = nil
        if OpenMailMoneyButton:IsShown() then
            new_target = OpenMailMoneyButton
        end
        local id = 1
        while id <= 16 and not new_target do
            local button = _G["OpenMailAttachmentButton"..id]
            if button:IsShown() then new_target = button end
            id = id + 1
        end
        self:SetTarget(new_target or OpenMailDeleteButton)
    end
    self.targets[frame] = nil
end

function OpenMailFrameHandler:SetTargets()
    -- The cancel button is positioned slightly out of line with the other
    -- two, so we have to set explicit movement here to avoid unexpected
    -- behavior (e.g. up from "delete" moving to "close").
    self.targets = {
        [OpenMailReplyButton] = {can_activate = true, lock_highlight = true,
                                 up = false, down = false},
        [OpenMailDeleteButton] = {can_activate = true, lock_highlight = true,
                                  up = false, down = false},
        [OpenMailCancelButton] = {can_activate = true, lock_highlight = true,
                                  up = false, down = false, right = false}
    }
    if OpenMailReplyButton:IsShown() then
        self.targets[OpenMailReplyButton].left = false
    elseif OpenMailReplyButton:IsShown() then
        self.targets[OpenMailDeleteButton].left = false
    else
        self.targets[OpenMailCancelButton].left = false
    end
    local have_report_spam = OpenMailReportSpamButton:IsShown()
    if have_report_spam then
        self.targets[OpenMailReportSpamButton] =
            {can_activate = true, lock_highlight = true,
             up = OpenMailCancelButton, down = OpenMailCancelButton,
             left = false, right = false}
        self.targets[OpenMailReplyButton].up = OpenMailReportSpamButton
        self.targets[OpenMailReplyButton].down = OpenMailReportSpamButton
        self.targets[OpenMailDeleteButton].up = OpenMailReportSpamButton
        self.targets[OpenMailDeleteButton].down = OpenMailReportSpamButton
        self.targets[OpenMailCancelButton].up = OpenMailReportSpamButton
        self.targets[OpenMailCancelButton].down = OpenMailReportSpamButton
    end
    local first_attachment = nil
    if OpenMailLetterButton:IsShown() then
        self:OnShowLetterButton(OpenMailLetterButton)
        first_attachment = OpenMailLetterButton
    elseif OpenMailMoneyButton:IsShown() then
        self:OnShowMoneyButton(OpenMailMoneyButton)
        first_attachment = OpenMailMoneyButton
    end
    for i = 1, 16 do
        local button = _G["OpenMailAttachmentButton"..i]
        assert(button)
        if button:IsShown() then
            self:OnShowAttachmentButton(button)
            if not first_attachment then first_attachment = button end
        end
    end
    if first_attachment then
        self.targets[OpenMailReplyButton].up = first_attachment
        self.targets[OpenMailDeleteButton].up = first_attachment
        self.targets[OpenMailCancelButton].up = first_attachment
        if have_report_spam then
            self.targets[OpenMailReportSpamButton].down = first_attachment
        end
        return first_attachment
    else
        return OpenMailCancelButton
    end
end
