local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

---------------------------------------------------------------------------

local ObjectiveTrackerFrameHandler = class(MenuCursor.CoreMenuFrame)
MenuCursor.Cursor.RegisterFrameHandler(ObjectiveTrackerFrameHandler)

function ObjectiveTrackerFrameHandler:__constructor()
    self:__super(ObjectiveTrackerFrame)
    self.cancel_func = function() self:Unfocus() end
    self.has_Button3 = true  -- Used to toggle quest tracking.
    self.has_Button4 = true  -- Used to open objective submenus.
    hooksecurefunc(self.frame, "Update", function() self:RefreshTargets() end)
    -- Watch for any bags being opened and disable ourselves while we're
    -- covered up.
    self.is_covered = false
    local function CheckContainerFrames() self:CheckContainerFrames() end
    EventRegistry:RegisterCallback("ContainerFrame.OpenBag",
                                   CheckContainerFrames)
    EventRegistry:RegisterCallback("ContainerFrame.CloseBag",
                                   CheckContainerFrames)
end

local BAGS = WoWXIV.maptn("ContainerFrame%n", 6)
function ObjectiveTrackerFrameHandler:CheckContainerFrames()
    local function IsShown(name) return _G[name]:IsShown() end
    self.is_covered = WoWXIV.any(IsShown, unpack(BAGS))
    if self.is_covered then
        self:Disable()
    elseif self.frame:IsShown() then
        if not self:IsEnabled() then
            self:OnShow()
        end
    end
end

function ObjectiveTrackerFrameHandler:OnShow()
    -- Deliberately IsShown() rather than IsVisible() to avoid edge cases
    -- when a cinematic or other fullscreen frame is hiding the tracker.
    if not self.frame:IsShown() or self.is_covered then return end
    if self:IsEnabled() then
        -- This must be a redundant Show() with the frame already visible,
        -- so don't change current state.
        -- (FIXME: we should probably handle this case at a lower level)
        return
    end
    -- We never take input focus on our own.
    self:EnableBackground(self:SetTargets())
end

function ObjectiveTrackerFrameHandler:OnFocus()
    -- Always reset to the top when receiving focus.
    self:SetTarget(self:GetDefaultTarget())
end

function ObjectiveTrackerFrameHandler:RefreshTargets()
    local target = self:GetTarget()
    self:SetTarget(nil)
    self:SetTarget(self:SetTargets(target))
end

function ObjectiveTrackerFrameHandler:SetTargets(old_target)
    self.targets = {}
    -- Modules are ObjectiveTrackerModuleTemplate instances,
    -- e.g. ScenarioObjectiveTracker.
    local first, last
    if not self.frame.modules then return end  -- work around Blizzard bug
    self.frame:ForEachModule(function(module)
        -- module:EnumerateActiveBlocks() is not useful because it doesn't
        -- give the blocks in order, so we iterate manually.
        local block = module.firstBlock
        while block do
            local params =
                {on_click = function(blk) blk:OnHeaderClick("LeftButton") end,
                 -- FIXME: we need to roll our own because this pops up in the middle of the screen
                 --on_button4 = function(blk) blk:OnHeaderClick("RightButton") end,
                 send_enter_leave = true,
                 up = last, left = false, right = false}
            self.targets[block] = params
            -- For quests, position the cursor at the PoI button
            -- rather than the middle of the block (which ends up
            -- being under the PoI button and a bit confusing).
            if block.poiButton and block.poiButton:IsShown() then
                params.on_button3 = function(blk)
                    blk.poiButton:GetScript("OnClick")(
                        blk.poiButton, "LeftButton", true)
                end
                local bx, by, _, bh = block:GetRect()
                local px, py, _, ph = block.poiButton:GetRect()
                by = by + bh/2
                py = py + ph/2
                params.x_offset = px - bx
                params.y_offset = py - by
            end
            -- If there's a quest item button, add it in as well, and
            -- save the reference for movement linking.
            if block.ItemButton then
                params.item = block.ItemButton
                params.left = block.ItemButton
                params.right = block.ItemButton
                self.targets[block.ItemButton] =
                    {can_activate = true, --lock_highlight = true,
                     send_enter_leave = true, left = block, right = block,
                     up = last and (self.targets[last].item or last)}
            end
            -- Quest popups in the objective tracker need their own
            -- button handling.
            if block.template == "AutoQuestPopUpBlockTemplate" then
                params.on_click =
                    function(blk) blk:OnMouseUp("LeftButton", true) end
                params.on_button4 = nil
            end
            -- Tweak cursor position for various block types.
            if module == QuestObjectiveTracker then
                if block.poiButton then
                    params.x_offset = params.x_offset - 4
                elseif block.template == "AutoQuestPopUpBlockTemplate" then
                    params.x_offset = 9
                end
            end
            if last then
                self.targets[last].down = block
                if self.targets[last].item then
                    self.targets[self.targets[last].item].down =
                        params.item or block
                end
            end
            first = first or block
            last = block
            block = block.nextBlock
        end  -- for each block
    end)  -- for each module
    if first then
        self.targets[last].down = first
        if self.targets[last].item then
            self.targets[self.targets[last].item].down =
                self.targets[first].item or first
        end
        self.targets[first].up = last
        if self.targets[first].item then
            self.targets[self.targets[first].item].up =
                self.targets[last].item or last
        end
        self.targets[first].is_default = true
    end
    if old_target and not self.targets[old_target] then
        old_target = nil
    end
    return old_target or first
end

function ObjectiveTrackerFrameHandler:OnAction(button)
    local target = self:GetTarget()
    assert(target)
    local handler = self.targets[target]["on_"..button:lower()]
    if handler then handler(target) end
end
