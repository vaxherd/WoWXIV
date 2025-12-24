local _, WoWXIV = ...
WoWXIV.Dev = WoWXIV.Dev or {}
local Dev = WoWXIV.Dev
Dev.Editor = Dev.Editor or {}
local Editor = Dev.Editor
Dev.FS = Dev.FS or {}
local FS = Dev.FS

local class = WoWXIV.class
local FramePool = WoWXIV.FramePool
local list = WoWXIV.list
local set = WoWXIV.set

local floor = math.floor
local strsub = string.sub


---------------------------------------------------------------------------
-- Editor frame manager
---------------------------------------------------------------------------

-- Global editor manager instance.
local manager

local EditorManager = class()

function EditorManager:__constructor()
    -- Pool of managed editor frames.
    self.framepool = FramePool(Editor.EditorFrame)

    -- Base frame level for editor frames.  This is also defined in
    -- frame.xml, but there doesn't seem to be a way to retrieve that
    -- value from Lua.
    self.flev_base = 9000
    -- Maximum frame level for editor frames.  We reserve the entire
    -- top end of the frame stratum for ourselves.
    self.flev_max = 10000
    -- Frame level interval for depthwise frame stacking.
    self.flev_interval = 10  -- Leave room for UI components within a frame.
    -- Maximum number of frames to manage: arbitrarily 50, but capped at
    -- however many can fit in our reserved frame level space.
    self.max_frames =
        min(50, floor((self.flev_max - self.flev_base) / self.flev_interval))

    -- Bounds for editor frame stacking (normalized UIParent() coordinates).
    -- Stacking starts from the top-left corner, and when a frame's right or
    -- bottom edge would exceed the right or bottom bound, that coordinate
    -- reverts to the left or top, respectively.
    self.stack_bound_left = 0.05
    self.stack_bound_top = 0.9
    self.stack_bound_right = 0.85
    self.stack_bound_bottom = 0.2
    -- Position for next editor frame (normalized).
    self.next_frame_x = self.stack_bound_left
    self.next_frame_y = self.stack_bound_top
    -- Stacking offset for successive editor frames (normalized).
    self.stack_offset_x = 0.02
    self.stack_offset_y = (self.stack_offset_x
                           * UIParent:GetWidth() / UIParent:GetHeight())
end

-- Create the global editor manager instance.
function EditorManager.Init()
    manager = EditorManager()
end

-- Return the global editor manager instance.
function EditorManager.Get()
    return manager
end

-- Open and return a new frame for the given file path (nil to not
-- associate a path with the frame).  If the pathname is relative, it is
-- taken to be relative to the addon root.
function EditorManager:OpenFrame(path)
    assert(path == nil or type(path) == "string")

    if self.framepool:NumAcquired() >= self.max_frames then
        error("Too many frames open")
    end
    local f = self.framepool:Acquire()

    local x, y = self.next_frame_x, self.next_frame_y
    if x + f:GetWidth()/UIParent:GetWidth() > self.stack_bound_right then
        x = self.stack_bound_left
    end
    if y - f:GetHeight()/UIParent:GetHeight() < self.stack_bound_bottom then
        y = self.stack_bound_top
    end
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT",
               x * UIParent:GetWidth(), (y-1) * UIParent:GetHeight())
    self.next_frame_x = x + self.stack_offset_x
    self.next_frame_y = y - self.stack_offset_y

    self:RaiseFrame(f)

    f:Init(self)
    if path then
        if strsub(path, 1, 1) ~= "/" then
            path = "/wowxiv/"..path
        end
        f:LoadFile(path)
    end

    return f
end

-- If a frame is already open for the given file path (which must not be
-- nil), focus that frame and return it; otherwise, open and return a new
-- frame for the path.
function EditorManager:FindOrOpenFrame(path)
    assert(type(path) == "string")
    if strsub(path, 1, 1) ~= "/" then
        path = "/wowxiv/"..path
    end
    for f in self.framepool do
        if f:GetFilePath() == path then
            f:Focus()
            return f
        end
    end
    return self:OpenFrame(path)
end

-- Close the given editor frame.  Typically called back from the frame.
-- Note that this function does not check for unsaved changes in the
-- frame's buffer.
function EditorManager:CloseFrame(frame)
    self.framepool:Release(frame)
end

-- Display the given frame on top of all others.
function EditorManager:RaiseFrame(frame)
    local frames = list()
    for f in self.framepool do
        if f ~= frame then
            frames:append(f)
        end
    end
    frames:sort(function(a,b) return a:GetFrameLevel() < b:GetFrameLevel() end)
    frames:append(frame)
    local level = self.flev_base
    for f in frames do
        assert(level + self.flev_interval <= self.flev_max)
        f:SetFrameLevel(level)
        level = level + self.flev_interval
    end
end


---------------------------------------------------------------------------
-- Top-level editor interface
---------------------------------------------------------------------------

-- Initialize the editor system.
function Editor.Init()
    EditorManager.Init()
end

-- Open a new, empty editor frame.
function Editor.New()
    manager:OpenFrame(nil)
end

-- Open an editor frame with the file at the given path loaded.  If no file
-- exists at the given path, an empty editor frame will be loaded with its
-- associated pathname set to the given path (so that a save command will
-- create that file).
function Editor.Open(path)
    assert(path, "path is required")
    manager:FindOrOpenFrame(path)
end

-- Open a new, empty editor frame for Lua interaction.
function Editor.NewLuaInteraction()
    Editor.LuaInt.InitFrame(manager:OpenFrame(nil))
end
