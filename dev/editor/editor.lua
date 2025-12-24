local _, WoWXIV = ...
WoWXIV.Dev = WoWXIV.Dev or {}
local Dev = WoWXIV.Dev
Dev.Editor = Dev.Editor or {}
local Editor = Dev.Editor
Dev.FS = Dev.FS or {}
local FS = Dev.FS

local class = WoWXIV.class
local FramePool = WoWXIV.FramePool
local set = WoWXIV.set

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
    local f = self.framepool:Acquire()
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
