--[[

Memory-based filesystem implementation.  This implementation is fairly
straightforward; objects (files and directories) are stored in a flat
data store table using arbitrary integers ("inode numbers") as keys,
and directories are tables mapping object names to inode numbers.

Stored data can be persisted across sessions by passing a table to the
constructor and saving a reference to the table; an atomic deep copy of
that table (such as on process shutdown) can then be passed back to the
constructor to restore the filesystem to its state at that time.

]]--

local _, WoWXIV = ...
WoWXIV.Dev = WoWXIV.Dev or {}
local Dev = WoWXIV.Dev
Dev.FS = Dev.FS or {}
local FS = Dev.FS

local class = WoWXIV.class
local set = WoWXIV.set

local strformat = string.format
local strsub = string.sub
local tinsert = table.insert


-- Inode number for the root directory.
local ROOT_INODE = 1


---------------------------------------------------------------------------
-- Internal routines
---------------------------------------------------------------------------

local MemFS = class()
FS.MemFS = MemFS

-- Allocate and return an inode for a new object.  Always succeeds.
function MemFS:GetInode()
    -- Lua defines the "#" operator on a table to return an index N
    -- such that table[N] exists (is not nil) but table[N] does not exist
    -- (is nil).  While problematic for some patterns, this behavior is
    -- convenient for us because it means we can get a guaranteed unused
    -- table index for "free" (i.e., only the cost of the # operator).
    local inode = #self.store + 1
    assert(self.store[inode] == nil)
    -- We assume a single-threaded environment, so we don't need to reserve
    -- the entry in the data store before returning the inode.
    return inode
end

---------------------------------------------------------------------------
-- External interface
---------------------------------------------------------------------------

-- Create a new memory filesystem.  If a table is provided, that table will
-- be used for data storage; otherwise, an anonymous data store will be
-- created for the filesystem.
function MemFS:__constructor(store)
    assert(store == nil or type(store) == "table")
    self.store = store or {}
    self.store[ROOT_INODE] = self.store[ROOT_INODE] or {}

    -- Map from inode to number of users.  We don't attempt to validate
    -- individual callers to Unref() and simply keep a refcount.
    self.open_refs = {}
    -- Set of inodes whose directory entries were deleted but which are
    -- still referenced in open_fefs.
    self.pending_deletion = set()
end

-- Validate the state of the filesystem ("FileSystem ChecK").  This checks
-- that all directory entries point to existing inodes and every inode is
-- referenced by exactly one directory entry.  Raises an error if any
-- inconsistency is found.
function MemFS:Fsck()
    local store = self.store
    local inode_map = {[ROOT_INODE] = "/"}
    local function ScanDir(dir, base_path)
        for name, inode in pairs(dir) do
            local path = base_path .. "/" .. name
            local object = store[inode]
            if not object then
                error(strformat("%s: references unused inode %d", path, inode))
            end
            if inode_map[inode] then
                error(strformat("%s: inode %d multiply referenced (with %s)",
                                path, inode, inode_map[inode]))
            end
            inode_map[inode] = path
            if type(object) == "table" then
                ScanDir(object, path)
            end
        end
    end
    local root = store[ROOT_INODE]
    if type(root) ~= "table" then
        error(strformat("Root inode (%d) missing or invalid", ROOT_INODE))
    end
    ScanDir(root, "")
    for inode in pairs(store) do
        if not inode_map[inode] then
            error(strformat("Inode %d: in use but not referenced", inode))
        end
    end
end

-- Return the filesystem root fileref.
function MemFS:Root()
    return ROOT_INODE
end

-- Look up the given name in the given directory and return its fileref.
function MemFS:Lookup(dir_ref, name)
    local dir = self.store[dir_ref]
    if type(dir) ~= "table" then
        return nil  -- Nonexistent object or not a directory.
    end
    return dir[name]
end

-- Increment the reference count for the given fileref.
function MemFS:Ref(ref)
    self.open_refs[ref] = (self.open_refs[ref] or 0) + 1
end

-- Decrement the reference count for the given fileref.
function MemFS:Unref(ref)
    local refcount = self.open_refs[ref]
    assert(refcount)
    if refcount > 1 then
        self.open_refs[ref] = refcount - 1
    else
        self.open_refs[ref] = nil
        if self.pending_deletion:has(ref) then
            self.pending_deletion:remove(ref)
            self.store[ref] = nil
        end
    end
end

-- Return information about the given fileref.
function MemFS:Stat(ref)
    local object = self.store[ref]
    if not object then
        return nil
    end
    return {is_dir = (type(object) == "table"),
            size = (type(object) == "string") and #object or 0}
end

-- Create a new directory with the given name in the given directory.
function MemFS:Mkdir(dir_ref, name)
    local dir = self.store[dir_ref]
    if type(dir) ~= "table" or dir[name] then
        return nil
    end
    local inode = self:GetInode()
    self.store[inode] = {}
    dir[name] = inode
    return inode
end

-- Create a new file with the given name in the given directory.
function MemFS:Create(dir_ref, name)
    local dir = self.store[dir_ref]
    if type(dir) ~= "table" or dir[name] then
        return nil
    end
    local inode = self:GetInode()
    self.store[inode] = ""
    dir[name] = inode
    return inode
end

-- Remove the named object in the given directory.
function MemFS:Remove(dir_ref, name)
    local dir = self.store[dir_ref]
    if type(dir) ~= "table" then
        return nil  -- dir_ref does not exist or is not a directory.
    end
    local inode = dir[name]
    if not inode then
        return nil  -- name does not exist in dir_ref.
    end
    local object = self.store[inode]
    if type(object) == "table" and next(object) then
        return nil  -- name is a non-empty directory.
    end
    dir[name] = nil
    if self.open_refs[inode] then
        self.pending_deletion[inode] = true
    else
        self.store[inode] = nil
    end
    return true
end

-- Return a list of names of all objects in the given directory.
function MemFS:Scan(dir_ref)
    local dir = self.store[dir_ref]
    if type(dir) ~= "table" then
        return nil
    end
    local result = {}
    for k in pairs(dir) do
        tinsert(result, k)
    end
    return result
end

-- Read the given range of bytes from the given file.
function MemFS:Read(file_ref, start, length)
    local file = self.store[file_ref]
    if type(file) ~= "string" then
        return nil
    end
    return strsub(file, start or 1, length)
end

-- Write the given data to the given file at the given position.
function MemFS:Write(file_ref, offset, data)
    local file = self.store[file_ref]
    if type(file) ~= "string" then
        return nil
    end
    if offset >= 0 then
        self.store[file_ref] = (strsub(file, 1, offset) .. data
                                .. strsub(file, (offset+1) + #data))
    else
        self.store[file_ref] = file .. data
    end
    return true
end

-- Set the given file's size.
function MemFS:Truncate(file_ref, size)
    local file = self.store[file_ref]
    if type(file) ~= "string" then
        return nil
    end
    if #file > size then
        self.store[file_ref] = strsub(file, 1, size)
    elseif #file < size then
        self.store[file_ref] = file .. string.rep("\0", size - #file)
    end
end
