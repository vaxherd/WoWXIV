local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

---------------------------------------------------------------------------

local InboxFrameHandler = class(MenuCursor.CoreMenuFrame)
MenuCursor.Cursor.RegisterFrameHandler(InboxFrameHandler)

function InboxFrameHandler:__constructor()
    -- We could react to PLAYER_INTERACTION_MANAGER_FRAME_{SHOW,HIDE}
    -- with arg1 == Enum.PlayerInteractionType.MailInfo (17) for mailbox
    -- handling, but we don't currently have any support for the send UI,
    -- so we isolate our handling to the inbox frame.
    self:__super(InboxFrame)
    for i = 1, 7 do
        local frame_name = "MailItem" .. i .. "Button"
        local frame = _G[frame_name]
        assert(frame)
        self:HookShow(frame, self.OnShowMailItemButton,
                             self.OnHideMailItemButton)
    end
end

function InboxFrameHandler:OnShowMailItemButton(frame)
    self.targets[frame] = {can_activate = true, lock_highlight = true,
                           send_enter_leave = true}
    self:UpdateMovement()
end

function InboxFrameHandler:OnHideMailItemButton(frame)
    -- Avoid errors if called before the inbox frame has been properly set up.
    if not self.targets[frame] then return end

    if self:GetTarget() == frame then
        self:MoveCursor("down")
    end
    self.targets[frame] = nil
    self:UpdateMovement()
    -- Work around a Blizzard bug that shows an empty inbox even with
    -- mail available if it was previously closed after an "Open All"
    -- invocation on a page greater than the number of available pages.
    -- (For example, after pressing Open All on page 2, then later
    -- checking for mail with only 1 item available.)
    if (type(InboxFrame.pageNum) == "number"  -- be safe against changes
        and InboxFrame.pageNum > 1
        and not MailItem1Button:IsShown())
    then
        InboxPrevPage()
    end
end

function InboxFrameHandler:SetTargets()
    -- We specifically hook the inbox frame, so we need a custom handler
    -- to hide the proper frame on cancel.
    self.cancel_func = function(self)
        self:Disable()
        HideUIPanel(MailFrame)
    end
    self.on_prev_page = "InboxPrevPageButton"
    self.on_next_page = "InboxNextPageButton"
    self.targets = {
        [OpenAllMail] = {can_activate = true, lock_highlight = true,
                         is_default = true},
        [InboxPrevPageButton] = {can_activate = true, lock_highlight = true},
        [InboxNextPageButton] = {can_activate = true, lock_highlight = true},
    }
    for i = 1, 7 do
        local button = _G["MailItem"..i.."Button"]
        assert(button)
        if button:IsShown() then
            self:OnShowMailItemButton(button)
        end
    end
    self:UpdateMovement()
end

function InboxFrameHandler:UpdateMovement()
    -- Ensure "up" from all bottom-row buttons goes to the bottommost mail item
    -- (by default, OpenAll and NextPage will go to the top item due to a lower
    -- angle of movement).
    local first_item = false
    local last_item = false
    for i = 1, 7 do
        local button = _G["MailItem"..i.."Button"]
        if button:IsShown() then
            if not first_item or button:GetTop() > first_item:GetTop() then
                first_item = button
            end
            if not last_item or button:GetTop() < last_item:GetTop() then
                last_item = button
            end
        end
    end
    self.targets[OpenAllMail].up = last_item
    self.targets[InboxPrevPageButton].up = last_item
    self.targets[InboxNextPageButton].up = last_item
    self.targets[OpenAllMail].down = first_item
    self.targets[InboxPrevPageButton].down = first_item
    self.targets[InboxNextPageButton].down = first_item
    if first_item then
        -- Targets might not yet be set up when switching to the inbox tab.
        if self.targets[first_item] then
            self.targets[first_item].up = OpenAllMail
        end
        if self.targets[last_item] then
            self.targets[last_item].down = OpenAllMail
        end
    end
end
