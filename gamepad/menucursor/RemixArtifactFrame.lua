local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

local tinsert = tinsert

---------------------------------------------------------------------------

local RemixArtifactFrameHandler = class(MenuCursor.AddOnMenuFrame)
RemixArtifactFrameHandler.ADDON_NAME = "Blizzard_RemixArtifactUI"
MenuCursor.Cursor.RegisterFrameHandler(RemixArtifactFrameHandler)

function RemixArtifactFrameHandler:__constructor()
    __super(self, RemixArtifactFrame)
    self.has_Button3 = true  -- Used to move the cursor to the commit button.
    self.has_Button4 = true  -- Used to refund a trait.

    -- For handling selection-type trait buttons.
    hooksecurefunc(self.frame, "ShowSelections",
                   function(frame,...) self:OnShowSelections(...) end)
    hooksecurefunc(self.frame, "HideSelections",
                   function() self:OnHideSelections() end)

    -- We receive our first call during the show event, so wait a frame to
    -- let the initial button layout take place.
    EventRegistry:RegisterCallback(
        "RemixArtifactFrame.SetTreeID",
        function() RunNextFrame(function() self:RefreshTargets() end) end)
end

-- Rather than configuring initial targets in SetTargets(), we wait for
-- the first RefreshAllData() call.  This typically happens before the
-- frame is actually shown, so we make sure to clear previous targets when
-- hiding the frame.
function RemixArtifactFrameHandler:RefreshTargets()
    local controls = self.frame.CommitConfigControls
    self.tree_id = self.frame.talentTreeID

    local old_target = self:GetTarget()
    self:SetTarget(nil)
    self.targets = {
        [controls.CommitButton] =
            {can_activate = true, lock_highlight = true,
             send_enter_leave = true, down = nil, left = controls.UndoButton,
             right = controls.UndoButton},
        [controls.UndoButton] =
            {can_activate = true, lock_highlight = true,
             send_enter_leave = true, down = nil, left = controls.CommitButton,
             right = controls.CommitButton},
    }

    local cur_target = self.targets[old_target] and old_target
    local buttons = {}  -- Indexed by node ID.
    local leftmost, rightmost
    for button in self.frame.talentButtonCollection:EnumerateActive() do
        assert(button.nodeID, "Node ID missing from trait button")
        local id = button.nodeID
        assert(not buttons[id])
        buttons[id] = button
        self.targets[button] = {can_activate = true, send_enter_leave = true,
                                has_Button4 = true}  -- for OnAction()
        if not cur_target and id == self.cur_node then
            cur_target = button
        end
        local x = button:GetLeft()
        if not leftmost or x < leftmost:GetLeft() then
            leftmost = button
        end
        if not rightmost or x > rightmost:GetRight() then
            rightmost = button
        end
    end
    self.buttons = buttons
    self.targets[leftmost].left = rightmost
    self.targets[rightmost].right = leftmost

    local target = cur_target
    if not target then
        target = leftmost
    end
    self:SetTarget(target)
end

function RemixArtifactFrameHandler:OnShowSelections(button, options)
    assert(self.targets[button])
    local left = self:NextTarget(button, "left")
    local right = self:NextTarget(button, "right")
    local children = self.frame.SelectionChoiceFrame.selectionFrameArray
    assert(children)
    assert(#children > 0)
    local function PostClickSelectionButton()
        self:SetTarget(button)
    end
    for i, child in ipairs(children) do
        self.targets[child] = {selection_parent = button,
                               can_activate = true, send_enter_leave = true,
                               on_click = PostClickSelectionButton,
                               up = false, down = button,
                               left = children[i==1 and #children or i-1],
                               right = children[i==#children and 1 or i+1]}
    end
    self.targets[button].up = children[1]
    self.targets[button].left = left
    self.targets[button].right = right
    self.targets[button].has_selections = true
end

function RemixArtifactFrameHandler:OnHideSelections()
    for target, params in pairs(self.targets) do
        if params.selection_parent then
            if self:GetTarget() == target then
                self:SetTarget(params.selection_parent)
            end
            self.targets[target] = nil
        elseif params.has_selection then
            self.targets[target].has_selection = false
            self.targets[target].up = nil
            self.targets[target].left = nil
            self.targets[target].right = nil
        end
    end
end

function RemixArtifactFrameHandler:OnMove(old_target, new_target)
    __super(self, old_target, new_target)
    if old_target and self.targets[old_target].has_selections then
        if not (new_target
                and self.targets[new_target].selection_parent == old_target)
        then
            old_target:ClearSelections()
        end
    end
    self.node_id = new_target and new_target.nodeID
end

function RemixArtifactFrameHandler:OnAction(button)
    if button == "Button3" then
        self:SetTarget(self.frame.CommitConfigControls.CommitButton)
    else
        assert(button == "Button4")
        local target = self:GetTarget()
        if target and self.targets[target].has_Button4 then
            target:GetScript("OnClick")(target, "RightButton", true)
        end
    end
end
