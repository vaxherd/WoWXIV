local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor
local Cursor = MenuCursor.Cursor

local class = WoWXIV.class

-- FIXME: would be nice to merge this with OrderHallTalentFrame

---------------------------------------------------------------------------

-- Constants for trait trees.  These don't seem to be defined anywhere.
local TREEID_TWW_VISIONS     = 1057  -- Horrific Visions Revisited
local TREEID_TWW_OVERCHARGED = 1061  -- Overcharged Delves
local TREEID_TWW_RESHII      = 1115  -- Reshii Wraps

local SUPPORTED_TRAIT_TREES = {
    [TREEID_TWW_VISIONS] = 1,
    [TREEID_TWW_OVERCHARGED] = 1,
    [TREEID_TWW_RESHII] = 1,
}


local GenericTraitFrameHandler = class(MenuCursor.AddOnMenuFrame)
GenericTraitFrameHandler.ADDON_NAME = "Blizzard_GenericTraitUI"
MenuCursor.Cursor.RegisterFrameHandler(GenericTraitFrameHandler)

function GenericTraitFrameHandler:__constructor()
    self.tree_id = nil
    self.tree = nil     -- Manually defined tree if needed for movement.
    self.buttons = nil  -- Mapping from talent node ID to button frame.

    self:__super(GenericTraitFrame)
    self.has_Button4 = true
    -- The frame uses various events and actions to refresh its display,
    -- using a release/recreate strategy which can change the mapping from
    -- tree icon to backing frame, so we need to hook the refresh function
    -- to make sure we catch every such change.
    hooksecurefunc(GenericTraitFrame, "LoadTalentTreeInternal",
                   function(frame) self:RefreshTargets() end)
end

function GenericTraitFrameHandler:OnShow()
    if not self.tree_id or not SUPPORTED_TRAIT_TREES[self.tree_id] then
        return
    end
    return MenuCursor.AddOnMenuFrame.OnShow(self)
end

function GenericTraitFrameHandler:OnHide()
    MenuCursor.AddOnMenuFrame.OnHide(self)
    -- Clear target info in preparation for the next show event (see notes
    -- in RefreshTargets()).
    self.targets = {}
    self.tree_id = nil
    self.cur_node = nil
end

-- Rather than configuring initial targets in SetTargets(), we wait for
-- the first MarkTreeDirty() call.  This typically happens before the
-- frame is actually shown, so we make sure to clear previous targets when
-- hiding the frame.
function GenericTraitFrameHandler:RefreshTargets()
    self:SetTarget(nil)
    self.targets = {}

    -- Look up the currently displayed trait tree ID.  If it's not a
    -- supported one, just abort.
    self.tree_id = self.frame.traitTreeID
    if not SUPPORTED_TRAIT_TREES[self.tree_id] then return end

    -- Add all trait buttons to the target list.
    -- C_Traits doesn't seem to give us as convenient structure info as
    -- C_GarrisonUI does for OrderHallTalentFrame, so for now we just use
    -- the default movement rules and augment as needed for specific trees.
    local buttons = {}  -- Indexed by node ID.
    local cur_target
    for button in self.frame.talentButtonCollection:EnumerateActive() do
        assert(button.nodeID, "Node ID missing from trait button")
        local id = button.nodeID
        assert(not buttons[id])
        buttons[id] = button
        self.targets[button] = {can_activate = true, send_enter_leave = true,
                                has_Button4 = true}  -- for OnAction()
        if id == self.cur_node then
            cur_target = button
        end
    end
    self.buttons = buttons
    if self.tree_id == TREEID_TWW_OVERCHARGED then
        local TREE = {
            {105816, 105980},
            {104109},
            {104105},
            {106018, 106794},
            {106795},
            {106648, 104106},
            {105979},
        }
        self.tree = TREE
        for i, row in ipairs(TREE) do
            local up_row = i>1 and TREE[i-1] or TREE[#TREE]
            local down_row = i<#TREE and TREE[i+1] or TREE[1]
            for j, node in ipairs(row) do
                assert(buttons[node])
                local params = self.targets[buttons[node]]
                local left = #row>1 and (j>1 and row[j-1] or row[#row])
                local left_button = left and self.buttons[left]
                assert(left_button ~= nil)
                params.left = left_button
                local right = #row>1 and (j<#row and row[j+1] or row[1])
                local right_button = right and self.buttons[right]
                assert(right_button ~= nil)
                params.right = right_button
                local up_button = self.buttons[up_row[1]]
                assert(up_button)
                params.up = up_button
                local down_button = self.buttons[down_row[1]]
                assert(down_button)
                params.down = down_button
            end
        end
    end

    -- If we had no previous target or didn't find it, default to the first
    -- button in the talent.
    local target = cur_target
    if not target then
        if self.tree then
            target = buttons[self.tree[1][1]]
        else
            for _, button in pairs(buttons) do
                if not target or button:GetTop() > target:GetTop() then
                    target = button
                end
            end
        end
    end
    self:SetTarget(target)
    -- We also need to set the is_default flag because our first call comes
    -- during the show event.
    self.targets[target].is_default = true
end

function GenericTraitFrameHandler:OnMove(old_target, new_target)
    MenuCursor.AddOnMenuFrame.OnMove(self, old_target, new_target)
    self.node_id = new_target and new_target.nodeID
    if not new_target or new_target == old_target then return end

    if self.tree_id == TREEID_TWW_OVERCHARGED then
        local old_node = old_target and old_target.nodeID
        local old_row, new_row, new_col
        for i, row in ipairs(self.tree) do
            for j, node in ipairs(row) do
                if node == old_node then
                    old_row = i
                end
                if node == self.node_id then
                    new_row = i
                    new_col = j
                end
            end
        end
        if new_row and new_row == old_row then
            -- Update links from single-node rows to preserve column.
            for i, row in ipairs(self.tree) do
                if #row == 1 then
                    local params = self.targets[self.buttons[row[1]]]
                    local up_row = i>1 and self.tree[i-1] or self.tree[#self.tree]
                    local down_row = i<#self.tree and self.tree[i+1] or self.tree[1]
                    if #up_row == 2 then
                        local up_button = self.buttons[up_row[new_col]]
                        assert(up_button)
                        params.up = up_button
                    end
                    if #down_row == 2 then
                        local down_button = self.buttons[down_row[new_col]]
                        assert(down_button)
                        params.down = down_button
                    end
                end
            end
        end
    end
end

function GenericTraitFrameHandler:OnAction(button)
    assert(button == "Button4")
    local target = self:GetTarget()
    if target and self.targets[target].has_Button4 then
        target:GetScript("OnClick")(target, "RightButton", true)
    end
end
