local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

local envcall = WoWXIV.envcall
local makefenv = WoWXIV.makefenv
local min = math.min
local tinsert = tinsert

---------------------------------------------------------------------------

local TorghastLevelPickerFrameHandler = class(MenuCursor.AddOnMenuFrame)
TorghastLevelPickerFrameHandler.ADDON_NAME = "Blizzard_TorghastLevelPicker"
MenuCursor.Cursor.RegisterFrameHandler(TorghastLevelPickerFrameHandler)

function TorghastLevelPickerFrameHandler:__constructor()
    self.top_row = {}     -- Ordered list of level buttons in the top row.
    self.bottom_row = {}  -- Ordered list of level buttons in the bottom row.

    __super(self, TorghastLevelPickerFrame)
    self.cancel_func = nil
    self.cancel_button = self.frame.CloseButton
    self.on_prev_page = self.frame.Pager.PreviousPage
    self.on_next_page = self.frame.Pager.NextPage
    self.has_Button3 = true  -- Used as a shortcut for the Climb button.
    hooksecurefunc(self.frame, "SetupOptionsByStartingIndex",
                   function() self:RefreshTargets() end)
end

function TorghastLevelPickerFrameHandler:RefreshTargets()
    local last_target = self:GetTarget()
    self:SetTarget(nil)
    self:SetTarget(self:SetTargets(last_target))
end

function TorghastLevelPickerFrameHandler:SetTargets(last_target)
    local f = self.frame
    local ClimbButton = f.OpenPortalButton

    self.targets = {
        [ClimbButton] = {
            can_activate = true, lock_highlight = true,
            left = false, right = false},
    }
    local was_level_target = (last_target and not self.targets[last_target])

    local levels = {}
    local y_top, y_bottom
    for button in f.gossipOptionsPool:EnumerateActive() do
        if button:IsShown() then
            tinsert(levels, button)
            local y = button:GetTop()
            if not y_top or y > y_top then y_top = y end
            if not y_bottom or y < y_bottom then y_bottom = y end
            -- Work around a bug in Blizzard code: one level beyond the
            -- maximum unlocked level is enabled, due to an off-by-one
            -- error in looking up the button associated with the maximum
            -- unlocked level (Blizzard_TorghastLevelPicker.lua line 177
            -- in retail 11.1.7 build 61609, comparing 0-based layer.index
            -- and 1-based highestAvailableLayerIndex).
            if button:IsEnabled() and button.optionInfo and button.optionInfo.status == Enum.GossipOptionStatus.Locked then
                local correct_index = button.index - 1
                self.frame.highestAvailableLayerIndex = correct_index
                button:SetState(Enum.GossipOptionStatus.Locked)
                for b2 in f.gossipOptionsPool:EnumerateActive() do
                    if b2.index == correct_index then
                        self.frame:SelectLevel(b2)
                        break
                    end
                end
            end
        end
    end
    local top_row, bottom_row = {}, {}
    local function OnEnterLevel(level) self:OnEnterLevel(level) end
    local function OnLeaveLevel(level) self:OnLeaveLevel(level) end
    for _, button in ipairs(levels) do
        self.targets[button] = {can_activate = true, lock_highlight = true,
                                on_enter = OnEnterLevel,
                                on_leave = OnLeaveLevel}
        -- On first call (no previous target), default to the button set
        -- as the initial selection.
        if not last_target and self.frame.currentSelectedButton == button then
            last_target = button
        end
        local y = button:GetTop()
        if y == y_top then
            tinsert(top_row, button)
        else
            assert(y == y_bottom)
            tinsert(bottom_row, button)
        end
    end
    table.sort(top_row, function(a,b) return a:GetLeft() < b:GetLeft() end)
    table.sort(bottom_row, function(a,b) return a:GetLeft() < b:GetLeft() end)
    local last_row = #bottom_row > 0 and bottom_row or top_row
    for i, button in ipairs(top_row) do
        self.targets[button].left = i>1 and top_row[i-1] or last_row[#last_row]
        self.targets[button].right = i<#top_row and top_row[i+1] or last_row[1]
        self.targets[button].up = ClimbButton
        if #bottom_row == 0 then
            self.targets[button].down = ClimbButton
        else
            self.targets[button].down = bottom_row[min(i, #bottom_row)]
        end
        if i == 1 then
            self.targets[ClimbButton].up = button
        end
    end
    for i, button in ipairs(bottom_row) do
        self.targets[button].left =
            i>1 and bottom_row[i-1] or top_row[#top_row]
        self.targets[button].right =
            i<#bottom_row and bottom_row[i+1] or top_row[1]
        self.targets[button].up = top_row[i]
        self.targets[button].down = ClimbButton
        if i == 1 then
            self.targets[ClimbButton].up = button
        end
    end
    self.targets[ClimbButton].down = top_row[1]
    self.top_row = top_row
    self.bottom_row = bottom_row

    -- If this is the first call and no button is active, we probably have
    -- all levels unlocked, so default to the last button (highest level).
    return (was_level_target and top_row[1])
        or last_target
        or last_row[#last_row]
end

function TorghastLevelPickerFrameHandler:OnEnterLevel(level)
    local reward = level.RewardBanner.Reward

    -- Annoyingly, both level and reward buttons explicitly check
    -- IsMouseOver() or equivalent, so we have to override those.
    local level_env = {
        RegionUtil = {
            IsAnyDescendantOfOrSame = function() return true end
        }
    }
    envcall(makefenv(level_env), level.RefreshTooltip, level)

    if reward:IsVisible() then
        local reward_oldmeta = getmetatable(reward)
        reward_newmeta = {__index = setmetatable(
            {IsMouseOver = function() return true end},
            {__index = reward_oldmeta.__index})}
        setmetatable(reward, reward_newmeta)
        reward:RefreshTooltip()
        setmetatable(reward, reward_oldmeta)
        if EmbeddedItemTooltip:IsVisible() then
            EmbeddedItemTooltip:ClearAllPoints()
            EmbeddedItemTooltip:SetPoint("TOP", GameTooltip, "BOTTOM")
        end
    end
end

function TorghastLevelPickerFrameHandler:OnLeaveLevel(level)
    local reward = level.RewardBanner.Reward
    level:OnLeave()
    reward:OnLeave()
end

function TorghastLevelPickerFrameHandler:OnMove(old_target, new_target)
    __super(self, old_target, new_target)
    local f = self.frame
    for i = 1, 3 do
        if self.top_row[i]==new_target or self.bottom_row[i]==new_target then
            local last_row =
                #self.bottom_row > 0 and self.bottom_row or self.top_row
            self.targets[f.OpenPortalButton].up = last_row[i]
            self.targets[f.OpenPortalButton].down = self.top_row[i]
            break
        end
    end
end

function TorghastLevelPickerFrameHandler:OnAction(button)
    assert(button == "Button3")
    local ClimbButton = self.frame.OpenPortalButton
    if ClimbButton:IsEnabled() then
        ClimbButton:Click()
    end
end
