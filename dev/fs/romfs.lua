--[[

Read-only static filesystem implementation.  This filesystem provides
access to a predefined set of files, and is primarily intended to make
the addon's own files available to the in-game editor.

Filerefs are a {directory,name} pair, where the directory is the table
in romfs_files corresponding to the entry's containing directory and
the name is the entry name as a string, or nil for a fileref to the
directory itself.

]]--

local _, WoWXIV = ...
WoWXIV.Dev = WoWXIV.Dev or {}
local Dev = WoWXIV.Dev
Dev.FS = Dev.FS or {}
local FS = Dev.FS

local class = WoWXIV.class

local strsub = string.sub
local tinsert = table.insert


---------------------------------------------------------------------------
-- Static filesystem data
---------------------------------------------------------------------------

-- Files to be provided by the filesystem.  This is a simple hierarchical
-- map, with files represented by string values containing their data and
-- directories represented by tables of their constituent entries, both
-- keyed by the entry name.

---------------------------------------------------------------------------
-- External interface
---------------------------------------------------------------------------

local RomFS = class()
FS.RomFS = RomFS

-- Create a new instance of the filesystem.  Pass in the file tree to be
-- exposed through the filesystem.  |tree| should be a table whose keys
-- are the entries (names) in the root directory and whose values are
-- either strings (files) or tables (subdirectories constructed in the
-- same way).
function RomFS:__constructor(tree)
    self.root = tree
end

-- Validate the state of the filesystem.
function RomFS:Fsck()
    -- Nothing to do.
end

-- Return the filesystem root fileref.
function RomFS:Root()
    return {self.root}
end

-- Look up the given name in the given directory and return its fileref.
function RomFS:Lookup(dir_ref, name)
    local dir, ref_name = unpack(dir_ref)
    if ref_name then
        return nil  -- Must be a file.
    end
    local object = dir[name]
    if type(object) == "table" then
        return {object, nil}
    elseif object then
        return {dir, name}
    else
        return nil
    end
end

-- Increment the reference count for the given fileref.
function RomFS:Ref(ref)
    -- Nothing to do.
end

-- Decrement the reference count for the given fileref.
function RomFS:Unref(ref)
    -- Nothing to do.
end

-- Return information about the given fileref.
function RomFS:Stat(ref)
    local dir, name = unpack(ref)
    if name then
        local object = dir[name]
        assert(type(object) == "string")
        return {is_dir = false, size = #object}
    else
        return {is_dir = true, size = 0}
    end
end

-- Create a new directory with the given name in the given directory.
function RomFS:Mkdir(dir_ref, name)
    return nil  -- Not supported.
end

-- Create a new file with the given name in the given directory.
function RomFS:Create(dir_ref, name)
    return nil  -- Not supported.
end

-- Remove the named object in the given directory.
function RomFS:Remove(dir_ref, name)
    return nil  -- Not supported.
end

-- Return a list of names of all objects in the given directory.
function RomFS:Scan(dir_ref)
    local dir, name = unpack(dir_ref)
    if name then
        return nil
    end
    local result = {}
    for k in pairs(dir) do
        tinsert(result, k)
    end
    return result
end

-- Read the given range of bytes from the given file.
function RomFS:Read(file_ref, start, length)
    local dir, name = unpack(file_ref)
    local file = dir[name]
    if type(file) ~= "string" then
        return nil
    end
    return strsub(file, start or 1, length)
end

-- Write the given data to the given file at the given position.
function RomFS:Write(file_ref, offset, data)
    return nil  -- Not supported.
end

-- Set the given file's size.
function RomFS:Truncate(file_ref, size)
    return nil  -- Not supported.
end
