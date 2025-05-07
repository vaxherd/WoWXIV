local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor
local CoreMenuFrame = MenuCursor.CoreMenuFrame

local class = WoWXIV.class

local function clamp(x, l, h)
    if x < l then return l elseif x > h then return h else return x end
end

---------------------------------------------------------------------------

local WorldMapFrameHandler = class(CoreMenuFrame)
MenuCursor.Cursor.RegisterFrameHandler(WorldMapFrameHandler)


function WorldMapFrameHandler:__constructor()
    self.cursor_x = 0.5
    self.cursor_y = 0.5
    self.cursor_highlight = nil --Highlight pin currently under cursor, if any.

    self:__super(WorldMapFrame)
    self.has_Button3 = true

    -- Dummy frame we use to provide a target for the map cursor.
    self.cursor_frame =
        CreateFrame("Frame", nil, WorldMapFrame.ScrollContainer.Child)
    self.cursor_frame:SetSize(1, 1)
    self.targets =
        {[self.cursor_frame] = {cursor_type = "static", is_default = true,
                                on_click = function() self:OnClickMap() end}}
end

function WorldMapFrameHandler:OnShow()
    self.cursor_x = 0.5
    self.cursor_y = 0.5
    self.cursor_highlight = nil
    self:UpdateCursorTarget()
    CoreMenuFrame.OnShow(self)
end

function WorldMapFrameHandler:OnUpdate()
    -- If the map is faded out for player movement, also hide the cursor.
    -- Note that the map frame's alpha animator doesn't go all the way to
    -- the target value, so we have to allow a bit of leeway in the check.
    if self.frame:GetAlpha() < 0.95 then
        self:SetTarget(nil)
        return
    end
    self:SetTarget(self.cursor_frame)
end

function WorldMapFrameHandler:OnAction(button)
    assert(button == "Button3")
    local last_map = WorldMapFrame.mapID
    WorldMapFrame:NavigateToParentMap()
    if WorldMapFrame.mapID == last_map then return end  -- Already at top map.
    self:PutCursorAtMapLinkOrCenter(last_map)
    self:UpdateCursorTarget()
end

function WorldMapFrameHandler:OnClickMap()
    local current_map = self.frame.mapID
    local info = C_Map.GetMapInfoAtPosition(
        current_map, self.cursor_x, self.cursor_y)
    if info then
        self.frame:SetMapID(info.mapID)
        self:PutCursorAtMapLinkOrCenter(current_map)
        self:UpdateCursorTarget()
    end
end

-- Looks for a link from the current map to |link_map| and places the
-- cursor there if found, or at the center of the map if not.  If there
-- are multiple such links, it is unspecified which one is used.
function WorldMapFrameHandler:PutCursorAtMapLinkOrCenter(link_map)
    self.cursor_highlight = nil
    for _, info in ipairs(C_Map.GetMapLinksForMap(self.frame.mapID)) do
        if info.linkedUiMapID == link_map then
            self.cursor_x = info.position.x
            self.cursor_y = info.position.y
            return
        end
    end
    -- No link found, default to center.
    self.cursor_x = 0.5
    self.cursor_y = 0.5
end

function WorldMapFrameHandler:UpdateCursorTarget()
    local cf = self.cursor_frame
    local x, y, w, h = WorldMapFrame.ScrollContainer.Child:GetRect()
    cf:ClearAllPoints()
    cf:SetPoint("TOPLEFT", w*self.cursor_x, (-h)*self.cursor_y)
end

-------- External interface functions called by camera stick input handler:

-- Return whether the map is currently focused.  We don't currently support
-- any UI elements on the map frame other than the map itself, but we hide
-- the cursor while the map is faded for player movement (see above).
function WorldMapFrameHandler:IsMapFocused()
    return self:GetTarget() == self.cursor_frame
end

-- Apply analog stick input to the map cursor position.
function WorldMapFrameHandler:HandleStickInput(x, y, dt)
    local speed = 1.5
    local move = dt * speed
    self.cursor_x = clamp(self.cursor_x + x*move, 0, 1)
    self.cursor_y = clamp(self.cursor_y - y*move, 0, 1)
    self:UpdateCursorTarget()
end
