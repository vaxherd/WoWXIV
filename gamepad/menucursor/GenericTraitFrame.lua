local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor
local Cursor = MenuCursor.Cursor

local class = WoWXIV.class

---------------------------------------------------------------------------

-- Constants for trait trees.  These don't seem to be defined anywhere.
local TREEID_TWW_VISIONS = 1057  -- Horrific Visions Revisited

local SUPPORTED_TRAIT_TREES = {
    [TREEID_TWW_VISIONS] = 1,
}


local GenericTraitFrameHandler = class(MenuCursor.AddOnMenuFrame)
GenericTraitFrameHandler.ADDON_NAME = "Blizzard_GenericTraitUI"
MenuCursor.Cursor.RegisterFrameHandler(GenericTraitFrameHandler)

function GenericTraitFrameHandler:__constructor()
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
    -- the default movement rules.
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

    -- If we had no previous target or didn't find it, default to the first
    -- button in the talent.
    local target = cur_target
    if not target then
        local nodes = C_Traits.GetTreeNodes(self.tree_id)
        assert(nodes)
        assert(nodes[1])
        assert(buttons[nodes[1]])
        target = buttons[nodes[1]]
    end
    self:SetTarget(target)
    -- We also need to set the is_default flag because our first call comes
    -- during the show event.
    self.targets[target].is_default = true
end

function GenericTraitFrameHandler:OnMove(old_target, new_target)
    MenuCursor.AddOnMenuFrame.OnMove(self, old_target, new_target)
    self.node_id = new_target and new_target.nodeID
end

function GenericTraitFrameHandler:OnAction(button)
    assert(button == "Button4")
    local target = self:GetTarget()
    if target and self.targets[target].has_Button4 then
        target:GetScript("OnClick")(target, "RightButton", true)
    end
end
