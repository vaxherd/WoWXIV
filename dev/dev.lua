local _, WoWXIV = ...
WoWXIV.Dev = WoWXIV.Dev or {}
local Dev = WoWXIV.Dev

local class = WoWXIV.class
local Button = WoWXIV.Button
local set = WoWXIV.set

---------------------------------------------------------------------------
-- Invisible button instance for shortcut keys
---------------------------------------------------------------------------

-- We can't bind keys to arbitrary functions, so we create invisible
-- buttons for each shortcut we implement.

local ShortcutButton = class(Button)

function ShortcutButton:__allocator(name, key)
    name = "WoWXIV_DevShortcut_"..name
    return __super("Button", name)
end

function ShortcutButton:__constructor(name, key)
    name = self:GetName()
    key = "ALT-CTRL-"..key
    self.key = key
    SetOverrideBindingClick(self, false, key, name)
    self:SetScript("OnClick", self.OnClick)
end

function ShortcutButton:OnClick()
    -- Override in derived classes.
end

-- Convenience wrapper to create a derived class with the given name and key.
function ShortcutButton.Subclass(name, key)
    local subclass = class(ShortcutButton)
    function subclass:__allocator()
        return __super(self, name, key)
    end
    function subclass:__constructor()
        return __super(self, name, key)
    end
    return subclass
end


local EditorShortcutButton = ShortcutButton.Subclass("Editor", "E")
function EditorShortcutButton:OnClick()
    Dev.Editor.New()
end

local LuaIntShortcutButton = ShortcutButton.Subclass("LuaInteraction", "L")
function LuaIntShortcutButton:OnClick()
    Dev.Editor.NewLuaInteraction()
end

---------------------------------------------------------------------------
-- Top-level interface for the development environment
---------------------------------------------------------------------------

-- Shortcut frame instances.
local shortcut_frames = set()

-- Initialize the development environment.  Should be called at startup time.
function Dev.Init()
    Dev.Editor.Init()
    Dev.FS.Init()
    Dev.FS.CreateDirectory("/wowxiv")  -- Assume success or already existing.
local romfs_files = {  -- FIXME: temp for testing
    dir = {
        test1 = "test_one\n",
        subdir = {
            test2 = "Test\nTwo\n",
        },
    },
    file = "I am a pen",
}
    assert(Dev.FS.Mount(Dev.FS.RomFS(romfs_files), "/wowxiv"))

    shortcut_frames:add(EditorShortcutButton())
    shortcut_frames:add(LuaIntShortcutButton())
end

-- Trigger a shortcut for the given key if one exists.  Returns true if a
-- shortcut was triggered, false if not.  Provided for use by frames which
-- consume keyboard input (like editor frames).
function Dev.RunShortcut(key)
    for shortcut in shortcut_frames do
        if shortcut.key == key then
            shortcut:Click()
            return true
        end
    end
    return false
end
