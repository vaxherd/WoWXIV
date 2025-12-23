--[[

This module implements a simple virtual filesystem for data storage.  It
supports the usual filesystem operations (open/read/write file,
create/scan directory, etc.) as well as mounting of other filesystems,
allowing "layering" of data trees or pseudo-filesystems like the Linux
/proc filesystem.

The external filesystem is a set of functions provided in the module's
Dev.FS namespace; see the function documentation in this file for
details.

Pathnames follow the Unix/POSIX style of a tree anchored at the root
directory "/" and pathname components (directory and file names)
separated by the "/" character, with the special names "." and ".."
referring to the current and parent directories, respectively.  In
particular, ".." in a pathname will always refer to the directory
previously resolved in that lookup operation, exactly equivalent to
the pathname transformation "/foo/../" -> "/".

The virtual filesystem has no concept of a "current directory"; all
pathnames must be absolute (that is, they must start with a "/").


Internally, a "filesystem" is an object (ultimately a Lua table) with a
set of methods providing access to the data it contains.  Most of these
methods take or return a "fileref": a value which uniquely identifies a
data object within that filesystem.  This virtual filesystem layer
treats the fileref value as opaque; it may be a number (like inode
numbers on Unix filesystems), a table, or whatever is convenient for the
particular filesystem implementation.  Filerefs are only considered to
be valid within the context of the particular virtual filesystem
operation which obtained them, except after an explicit call to Ref()
on the fileref.

The virtual filesystem handles parsing "." and ".." path components on
its own; filesystem implementations do not need to worry about resolving
those names.  (Conversely, filesystems cannot give any meaning to those
names other than the standard "current directory" and "parent directory"
usage.)

Filesystem objects must provide the following methods.  For all methods,
the caller guarantees that any fileref argument is a value previously
returned from another method called on the same filesystem and that any
"name" argument is a non-empty string which is not "." or "..".  All
methods except Root() may return nil if an operation fails for some
filesystem-specific reason.

    Root() -> ref
        Returns a fileref corresponding to the root directory of the
        filesystem.

    Lookup(dir_ref, name) -> ref
        Looks up the object named |name| in the directory referenced by
        the fileref |dir_ref| and returns a fileref for that object, or
        nil if |dir_ref| is invalid or does not reference a directory or
        if there is no object by that name.

    Ref(ref) -> nil
        Acquires a reference to |ref|.  The corresponding filesystem
        object must remain valid until the reference is released with
        Unref() (although the name associated with it may be deleted
        with Remove(), in which case the object should be deleted once
        all references have been released).

    Unref(ref) -> nil
        Releases a fileref previously referenced through Ref().  This
        constitutes a promise that the caller will no longer use |ref|,
        and the filesystem is free to dispose of the associated object
        if it is not otherwise referenced.

    Stat(ref) -> {["is_dir"] = boolean, ["size"] = number}
        Returns a table containing information about object referenced
        by the given fileref, or nil if |ref| is invalid.  The fields in
        the returned table have the following values:
            is_dir: True if the object is a directory (that is, it can
                be used as the |dir_ref| argument to a Lookup() call),
                false otherwise.
            size: Size of the object in bytes; that is, the length of
                the Lua string that would be returned by a Read() call
                of unlimited length.  If the object is a directory, the
                value is unspecified (it must be a number, but the
                number may be anything).

    Mkdir(dir_ref, name) -> ref
        Creates a new directory object named |name| inside directory
        |dir_ref|.  Returns a fileref for the created object, or nil if
        |dir_ref| or |name| are invalid, |dir_ref| does not refer to a
        directory object, or |name| already exists in the referenced
        directory.

    Create(dir_ref, name) -> ref
        Creates a new file object named |name| inside directory
        |dir_ref|.  Returns a fileref for the created object, or nil if
        |dir_ref| or |name| are invalid, |dir_ref| does not refer to a
        directory object, or |name| already exists in the referenced
        directory.

    Remove(dir_ref, name) -> true
        Removes the object named |name| in directory |dir_ref|.  Returns
        true on success.  Fails (and returns nil) in any of the
        following cases: |dir_ref| or |name| are invalid, |dir_ref| does
        not refer to a directory object, or the object named |name| is a
        directory and it is not empty.

    Scan(dir_ref) -> array of string
        Returns an array (a Lua table with sequentially numbered indices
        starting from 1) containing the names of all objects in the
        directory referenced by |dir_ref|.  The order of the returned
        names is unspecified.  Returns nil if |dir_ref| is invalid or
        does not refer to a directory object.

    Read(file_ref [, start [, length] ]) -> string
        Returns a string containing the data in the file object
        referenced by |file_ref|, starting from offset |start| and
        continuing for |length| bytes.  |start| and |length| are
        guaranteed to be either integral numbers or nil (omitted).  The
        region specified by |start| and |length| is implicitly clamped
        to the range [0,Stat(file_ref).size].  If |length| is omitted,
        all data from |start| to the end of the file is returned; if
        |start| is also omitted, the entire file is returned.  Returns
        nil if |file_ref| is invalid or does not refer to a file object.

    Write(file_ref, offset, data) -> true
        Stores the content of the string |data| into the file object
        referenced by |file_ref| at byte offset |offset|.  |offset| is
        guaranteed to be an integral number, and |data| is guaranteed to
        be a possibly empty string consisting only of bytes (characters
        of value 0 through 255).  If |offset| is negative, it is treated
        as the current end of the file (making the write an "append"
        operation).  Returns true, or nil if |file_ref| is invalid or
        does not refer to a file object.

    Truncate(file_ref, size) -> true
        Sets the size of the file object referenced by |file_ref| to
        |size|, which is guaranteed to be a nonnegative integer.  If
        |size| is greater than the current file size, the intervening
        space is filled with null (\000) bytes.

On initialization, the filesystem tree consists of a single memory-based
filesystem which stores files in memory, persisting them via the WoW
SavedVariables functionality (the filesystem content is saved at the
account level, not per character).

]]--

local _, WoWXIV = ...
WoWXIV.Dev = WoWXIV.Dev or {}
local Dev = WoWXIV.Dev
Dev.FS = Dev.FS or {}
local FS = Dev.FS

local class = WoWXIV.class
local list = WoWXIV.list
local set = WoWXIV.set

local floor = math.floor
local strfind = string.find
local strformat = string.format
local strmatch = string.match
local strstr = function(s1,s2,pos) return strfind(s1,s2,pos,true) end
local strsub = string.sub


---------------------------------------------------------------------------
-- Internal filesystem state and utility routines
---------------------------------------------------------------------------

-- Root filesystem content (this is stored to SavedVariables).
WoWXIV_rootfs = {}

-- Root filesystem reference (created by FS.Init()).
local root = nil

-- Mount table.  Each entry is a 4-tuple: {parent_fs, dir_ref, name, child_fs}
-- meaning "when looking up entry |name| in fileref |dir_ref| from filesystem
-- |parent_fs|, the result is the root of |child_fs| rather than whatever
-- might be at that name in the referenced directory".
local mounts = {}

-- File descriptor table.  Maps numbers to Filehandle instances, to hide
-- the Filehandle objects from callers.
local fd_table = {}


-- Return the filesystem mounted at {fs, dir_ref, name}, or nil if none.
local function GetMount(fs, dir_ref, name)
    -- Simple linear scan should be good enough for our purposes.
    for _, mount in ipairs(mounts) do
        if fs == mount[1] and dir_ref == mount[2] and name == mount[3] then
            return mount[4]
        end
    end
    return nil
end

-- Find the object at the given absolute path.  Returns a
-- {filesystem,fileref} pair, or nil if no object is found.
local function ResolvePath(path)
    assert(strsub(path, 1, 1) == "/")
    local fs = root
    local ref = fs:Root()
    local parents = list()
    path = strsub(path, 2)
    while path ~= "" do
        local slash = strstr(path, "/")
        local name = slash and strsub(path, 1, slash-1) or path
        path = slash and strsub(path, slash+1) or ""
        if name == "" then
            -- Multiple sequential slashes, treat as a single slash.
        elseif name == "." then
            -- Current directory, no change in fileref.
        elseif name == ".." then
            if #parents > 0 then
                fs, ref = unpack(parents:pop())
            end
        else
            parents:append({fs, ref})
            local child_fs = GetMount(fs, ref, name)
            if child_fs then
                fs = child_fs
                ref = fs:Root()
                assert(ref)  -- Guaranteed by contract.
            else
                ref = fs:Lookup(ref, name)
                if not ref then
                    return nil
                end
            end
        end
    end
    return fs, ref
end

-- Split a path into directory and name components.  Returns nil if the
-- path is not absolute or if it is exactly "/" (the root directory).
local function SplitPath(path)
    if strsub(path, 1, 1) ~= "/" then
        return nil  -- Must be an absolute path.
    end
    return strmatch(path, "^(.*/+)([^/]+)/*$")
end


---------------------------------------------------------------------------
-- Filehandle class
---------------------------------------------------------------------------

local Filehandle = class()

-- Local declaration of FS.OPEN_* constants.
local OPEN_READ     = 1
local OPEN_WRITE    = 2
local OPEN_TRUNCATE = 3
local OPEN_APPEND   = 4

-- Pass the fs/ref for the file and an OPEN_* mode constant.
function Filehandle:__constructor(fs, ref, mode)
    self.fs = fs
    self.ref = ref
    self.mode = mode
    self.pos = (mode == OPEN_APPEND) and -1 or 0
    fs:Ref(ref)
end

function Filehandle:Close()
    self.fs:Unref(self.ref)
end

function Filehandle:Seek(pos, relative)
    if self.mode == OPEN_APPEND then
        return nil
    end
    if relative then
        self.pos = max(0, self.pos + pos)
    else
        self.pos = max(0, pos)
    end
    return self.pos
end

function Filehandle:Read(length)
    if self.mode == OPEN_APPEND then
        return nil
    end
    local data = self.fs:Read(self.ref, self.pos, length)
    if not data then
        return nil
    end
    self.pos = self.pos + #data
    return data
end

function Filehandle:Write(data)
    if self.mode == OPEN_READ then
        return nil
    end
    if not self.fs:Write(self.ref, self.pos, data) then
        return nil
    end
    if self.mode ~= OPEN_APPEND then
        self.pos = self.pos + #data
    end
    return true
end


---------------------------------------------------------------------------
-- External filesystem interface
---------------------------------------------------------------------------

-- Constants for FS.Open().
FS.OPEN_READ     = OPEN_READ      -- Read only (writes will fail).
FS.OPEN_WRITE    = OPEN_WRITE     -- Read and write.
FS.OPEN_TRUNCATE = OPEN_TRUNCATE  -- Read and write; file truncated on open.
FS.OPEN_APPEND   = OPEN_APPEND    -- Writes always append; reads will fail.


-------- Core filesystem operations

-- Initialize the filesystem.  Must be called before any other filesystem
-- operations.  May be safely called multiple times (subsequent calls will
-- have no effect).
function FS.Init()
    if root then return end
    root = FS.MemFS(WoWXIV_rootfs)
end


-------- Standard file/directory operations

-- Return information about the object at the given path.  The return value
-- is a table with the following keys:
--     is_dir: True if the object is a directory, false otherwise.
--     size: Size of the object in bytes.  Unspecified for directories.
-- Returns nil on error.
function FS.Stat(path)
    if strsub(path, 1, 1) ~= "/" then
        return nil  -- Must be an absolute path.
    end
    local fs, ref = ResolvePath(path)
    return ref and fs:Stat(ref)
end

-- Create a directory at the given path.  Returns true on success, nil on
-- error.
function FS.CreateDirectory(path)
    local parent, name = SplitPath(path)
    if not name then
        return nil
    end
    local fs, ref = ResolvePath(parent)
    if not ref then
        return nil
    end
    return fs:Mkdir(ref, name) or nil
end

-- Return a list of all objects (files and directories) in the directory
-- at the given path.  Returns nil on error.
function FS.ListDirectory(path)
    if strsub(path, 1, 1) ~= "/" then
        return nil  -- Must be an absolute path.
    end
    local fs, ref = ResolvePath(path)
    if not ref then
        return nil
    end
    return fs:Scan(ref)
end

-- Open a file at the given path using the given mode (an OPEN_*
-- constant), and return a file descriptor (an opaque value) for accessing
-- the file.  If no object exists at the specified path and the mode is not
-- OPEN_READ, a new file will be created at that path.  Returns nil on
-- error, including when the path specifies a directory rather than a file.
local VALID_MODES = set(OPEN_READ, OPEN_WRITE, OPEN_TRUNCATE, OPEN_APPEND)
function FS.Open(path, mode)
    if strsub(path, 1, 1) ~= "/" then
        return nil  -- Must be an absolute path.
    end
    if not VALID_MODES:has(mode) then
        return nil
    end
    local fs, ref = ResolvePath(path)
    local fh
    if ref then
        local stat = fs:Stat(ref)
        if stat and not stat.is_dir then
            fh = Filehandle(fs, ref)
            if mode == OPEN_TRUNCATE then
                fs:Truncate(ref, 0)
            end
        end
    elseif mode ~= OPEN_READ then
        local parent, name = SplitPath(path)
        assert(name)  -- If it was "/", we would have a ref above.
        local fs, ref = ResolvePath(parent)
        if ref and fs:Create(ref, name) then
            local file_ref = fs:Lookup(ref, name)
            assert(file_ref)
            local stat = fs:Stat(file_ref)
            assert(stat)
            assert(not stat.is_dir)
            fh = Filehandle(fs, file_ref)
        end
    end
    if not fh then
        return nil
    end
    local fd = #fd_table + 1  -- Guaranteed to be an unused key.
    fd_table[fd] = fh
    return fd
end

-- Close the given file descriptor.
function FS.Close(fd)
    local fh = (type(fd) == "number") and fd_table[fd] or nil
    if not fh then
        return
    end
    fh:Close()
    fd_table[fd] = nil
end

-- Set the given file descriptor's file position to the given byte offset.
-- If |relative| is true, the offset is from the current file position;
-- otherwise, it is from the beginning of the file.  Returns the resulting
-- file position, or nil on error.
function FS.Seek(fd, pos, relative)
    local fh = (type(fd) == "number") and fd_table[fd] or nil
    if not fh or type(pos) ~= "number" or pos ~= floor(pos) then
        return nil
    end
    return fh:Seek(pos, relative)
end

-- Return the given file descriptor's current file position.  Equivalent to
-- Seek(fd, 0, true).  Returns nil on error.
function FS.Tell(fd)
    local fh = (type(fd) == "number") and fd_table[fd] or nil
    if not fh then
        return nil
    end
    return fh:Seek(0, true)
end

-- Read and return the given number of bytes from the given file.  If
-- |length| is omitted (or nil), the entire remainder of the file starting
-- from the current file position is returned.  Returns nil on error.
function FS.Read(fd, length)
    local fh = (type(fd) == "number") and fd_table[fd] or nil
    if not fh then
        return nil
    end
    if length ~= nil then
        if type(length) ~= "number" or length ~= floor(length) then
            return nil
        end
    end
    return fh:Read(length)
end

-- Write the given data (string) to the given file.  The data must contain
-- only bytes (characters with value 0 through 255).  Returns true on
-- success, nil on error.
function FS.Write(fd, data)
    local fh = (type(fd) == "number") and fd_table[fd] or nil
    if not fh or type(data) ~= "string" then
        return nil
    end
    -- WoW's Lua version (5.1) only supports byte-valued characters, so
    -- we don't have to explicitly check for string validity.
    return fh:Write(data)
end


-------- Utility routines

-- Read and return the entire content of the given file, if it exists.
-- Returns nil on error.
function FS.ReadFile(path)
    local fd = FS.Open(path, OPEN_READ)
    local data
    if fd then
        data = FS.Read(fd)
        FS.Close(fd)
    end
    return data
end

-- Write the given data to the given file.  If the file does not exist,
-- it is created; if it does exist, it is truncated.  Returns true on
-- success, nil on error.
function FS.WriteFile(path, data)
    local fd = FS.Write(path, OPEN_TRUNCATE)
    local result
    if fd then
        result = FS.Write(fd, data)
        FS.Close(fd)
    end
    return result
end
