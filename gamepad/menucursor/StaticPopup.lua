local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor
local Cursor = MenuCursor.Cursor
local MenuFrame = MenuCursor.MenuFrame
local CoreMenuFrame = MenuCursor.CoreMenuFrame
local AddOnMenuFrame = MenuCursor.AddOnMenuFrame

local class = WoWXIV.class

local tinsert = tinsert

---------------------------------------------------------------------------

local StaticPopupHandler = class(MenuFrame)
Cursor.RegisterFrameHandler(StaticPopupHandler)

function StaticPopupHandler.Initialize(class, cursor)
    class.instances = {}
    for i = 1, STATICPOPUP_NUMDIALOGS do
        local frame_name = "StaticPopup" .. i
        local frame = _G[frame_name]
        assert(frame)
        local instance = StaticPopupHandler(frame, MenuFrame.MODAL)
        class.instances[i] = instance
        instance:HookShow(frame)
    end
end

function StaticPopupHandler:OnShow()
    if self:HasFocus() then return end  -- Sanity check.
    self:SetTargets()
    self:Enable(nil)
end

function StaticPopupHandler:OnHide()
    self:Disable()
end

function StaticPopupHandler:SetTargets()
    local frame = self.frame
    self.targets = {}
    local leftmost = nil
    for i = 1, 5 do
        local name = i==5 and "extraButton" or "button"..i
        local button = frame[name]
        assert(button)
        if button:IsShown() then
            self.targets[button] = {can_activate = true,
                                    lock_highlight = true}
            if not leftmost or button:GetLeft() < leftmost:GetLeft() then
                leftmost = button
            end
        end
    end
    if leftmost then  -- i.e., if we found any buttons
        self.targets[leftmost].is_default = true
        if frame.button2:IsShown() then
            self.cancel_button = frame.button2
        end
    end
    -- Special cases for extra elements like item icons in specific popups.
    if frame.which == "CONFIRM_SELECT_WEEKLY_REWARD" then
        assert(frame.insertedFrame)
        local ItemFrame = frame.insertedFrame.ItemFrame
        assert(ItemFrame)
        assert(ItemFrame:IsShown())
        self.targets[ItemFrame] = {send_enter_leave = true,
                                   left = false, right = false}
        local AlsoItemsFrame = frame.insertedFrame.AlsoItemsFrame
        assert(AlsoItemsFrame)
        if AlsoItemsFrame:IsShown() then
            local row = {}
            for subframe in AlsoItemsFrame.pool:EnumerateActive() do
                self.targets[subframe] =
                    {send_enter_leave = true, up = ItemFrame, down = leftmost}
                tinsert(row, {subframe:GetLeft(), subframe})
            end
            table.sort(row, function(a,b) return a[1] < b[1] end)
            local first = row[1][2]
            local last = row[#row][2]
            for i = 1, #row do
                local target = row[i][2]
                self.targets[target].left = i==1 and last or row[i-1][2]
                self.targets[target].right = i==#row and first or row[i+1][2]
            end
            self.targets[ItemFrame].up = leftmost
            self.targets[ItemFrame].down = first
            self.targets[leftmost].up = first
            self.targets[leftmost].down = ItemFrame
        end
    end
end