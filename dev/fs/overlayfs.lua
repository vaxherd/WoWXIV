--[[

"Overlay" filesystem implementation, providing a writable transparent
overlay on top of a second (presumed read-only) filesystem.

This filesystem does not implement any storage on its own; instead, it
delegates operations to an "upper" and a "lower" filesystem.  Writes to
files on the lower filesystem are stored to the upper filesystem, and
reads from files use the data from the upper filesystem if it is present
(thus effectively implementing copy-on-write semantics for the lower
filesystem's files).

The directory structure of the lower filesystem is assumed to remain
static.  In particular, if a file is removed from the lower filesystem
but remains present in the upper filesystem, it will remain visible,
being treated as a new file rather than a modification of an existing
file.  Any process which modifies the lower filesystem is responsible
for updating the upper filesystem appropriately.

Specific operations behave as follows:

- Lookup() returns success for any name present in either the upper or
  the lower filesystem under a particular directory.  Scan() similarly
  returns a list of all names present in the directory on either
  filesystem.

- Stat() and Read() operate on the upper filesystem if the target path
  is present there, otherwise on the lower filesystem.

- Mkdir() and Create() create objects on the upper filesystem and fail if
  the target path is present on either the upper or the lower filesystem.

- Remove() fails for any object present on the lower filesystem,
  regardless of whether it exists in the upper filesystem.

- Write() and Truncate() write data only to the upper filesystem.  When
  modifying a file which is only present on the lower filesystem, the
  operation first copies that file to the upper filesystem (creating
  parent directories as needed), then performs the write on that copied
  file.  If an error occurs while copying the file, the operation returns
  failure.  On success, if the result of the write leaves an
  upper-filesystem file identical to that on the lower filesystem, the
  upper-filesystem copy may be deleted.

Internally, filerefs are a 3-tuple containing the upper filesystem fileref
(if any), the lower filesystem fileref (if any), the refcount, and the
pathname as resolved via Lookup() (for creating/removing the overlay file).

]]--

local _, WoWXIV = ...
WoWXIV.Dev = WoWXIV.Dev or {}
local Dev = WoWXIV.Dev
Dev.FS = Dev.FS or {}
local FS = Dev.FS

local class = WoWXIV.class
local list = WoWXIV.list
local set = WoWXIV.set

local strfind = string.find
local strstr = function(s1,s2,pos) return strfind(s1,s2,pos,true) end
local strsub = string.sub


---------------------------------------------------------------------------
-- Internal routines
---------------------------------------------------------------------------

local OverlayFS = class()
FS.OverlayFS = OverlayFS

-- Fsck() helper to validate an upper filesystem directory tree.
function OverlayFS:_FsckTree(path, upper_ref, lower_ref)
    local entries = self.upper:Scan(upper_ref)
    for _, name in ipairs(entries) do
        local lower_nameref = self.lower:Lookup(lower_ref, name)
        if nameref_lower then
            local st_lower = self.lower:Stat(lower_nameref)
            assert(st_lower)
            local upper_nameref = self.upper:Lookup(upper_ref, name)
            assert(upper_nameref)
            local st_upper = self.upper:Stat(upper_nameref)
            assert(st_upper)
            if st_upper.is_dir ~= st_lower.is_dir then
                error("Entry type mismatch on "..path..name)
            end
            if st_upper.is_dir then
                self:_FsckTree(path..name.."/", upper_nameref, lower_nameref)
            end
        end
    end
end

-- Write()/Truncate() helper to copy a file from lower to upper filesystem
-- on first write.  If the file is copied, the passed-in fileref is updated
-- with the new upper-filesystem fileref.
function OverlayFS:_CopyOnWrite(ref)
    local upper_ref, lower_ref, refcount, path = unpack(ref)
    if upper_ref then
        return ref  -- We already have an upper ref, nothing to do.
    end
    assert(lower_ref)
    local st = self.lower:Stat(lower_ref)
    if st.is_dir then
        return ref  -- Not a file, can't be written to.
    end
    assert(strsub(path, 1, 1) == "/")
    local index = 2
    local upper_dir = self.upper:Root()
    while true do
        local slash = strstr(path, "/", index)
        if not slash then break end
        local name = strsub(path, index, slash-1)
        upper_dir = (self.upper:Lookup(upper_dir, name) or
                     self.upper:Mkdir(upper_dir, name))
        if not upper_dir then
            return nil
        end
        index = slash+1
    end
    local name = strsub(path, index)
    -- We expect this file to not exist because otherwise it would have
    -- been picked up in the initial Lookup(), but it's possible a
    -- concurrent caller also triggered a copy-on-write after our initial
    -- lookup, so make sure not to try to re-create the file in that case.
    local upper_file = (self.upper:Lookup(upper_dir, name) or
                        self.upper:Create(upper_dir, name))
    for i = 1, refcount do
        self.upper:Ref(upper_file)
    end
    ref[1] = upper_file
    return ref
end

-- Unref() helper to delete an overlay file which is now identical to its
-- lower-filesystem counterpart.  The object is assumed to be a file.
function OverlayFS:_RemoveIfIdentical(upper_ref, lower_ref, path)
    local upper_data = self.upper:Read(upper_ref)
    local lower_data = self.lower:Read(lower_ref)
    if not (upper_data and upper_data == lower_data) then
        return
    end
    -- The files are identical, so remove the overlay copy, along with any
    -- now-empty parent directories.  If we get any errors along the way,
    -- we just ignore them as at worst they will only leave extra data on
    -- the upper filesystem.  (This approach also lets us not worry about
    -- whether the intervening directories are in fact empty; if not,
    -- Remove() will fail without any further complications.)
    local tree = list()  -- List of directory refs and names down to the file.
    assert(strsub(path, 1, 1) == "/")
    local index = 2
    local dir_ref = self.upper:Root()
    while true do
        local slash = strstr(path, "/", index)
        local name = strsub(path, index, slash and slash-1)
        tree:append({dir_ref, name})
        if not slash then
            break
        end
        dir_ref = self.upper:Lookup(dir_ref, name)
        if not dir_ref then
            return  -- Something went seriously wrong, so just give up.
        end
        index = slash+1
    end
    while #tree > 0 do
        local dir_ref, name = unpack(tree:pop())
        self.upper:Remove(dir_ref, name)
    end
end

---------------------------------------------------------------------------
-- External interface
---------------------------------------------------------------------------

-- Create a new overlay filesystem using the given upper and lower
-- filesystems.
function OverlayFS:__constructor(upper, lower)
    self.upper = upper
    self.lower = lower
end

-- Validate the state of the filesystem.  Raises an error if any
-- inconsistency is found.
function OverlayFS:Fsck()
    self:_FsckTree("/", self.upper:Root(), self.lower:Root())
end

-- Return the filesystem root fileref.
function OverlayFS:Root()
    -- Set root path to the empty string to help path generation in Lookup().
    return {self.upper:Root(), self.lower:Root(), 0, ""}
end

-- Look up the given name in the given directory and return its fileref.
function OverlayFS:Lookup(dir_ref, name)
    local upper_dir, lower_dir, _, path = unpack(dir_ref)
    local upper_ref = upper_dir and self.upper:Lookup(upper_dir, name)
    local lower_ref = lower_dir and self.lower:Lookup(lower_dir, name)
    if not upper_ref and not lower_ref then
        return nil
    end
    return {upper_ref, lower_ref, 0, path.."/"..name}
end

-- Increment the reference count for the given fileref.
function OverlayFS:Ref(ref)
    local upper_ref, lower_ref, refcount = unpack(ref)
    if upper_ref then
        self.upper:Ref(upper_ref)
    end
    if lower_ref then
        self.lower:Ref(lower_ref)
    end
    ref[3] = refcount+1
end

-- Decrement the reference count for the given fileref.
function OverlayFS:Unref(ref)
    local upper_ref, lower_ref, refcount, path = unpack(ref)
    if upper_ref then
        self.upper:Unref(upper_ref)
    end
    if lower_ref then
        self.lower:Unref(lower_ref)
    end
    refcount = refcount-1
    ref[3] = refcount
    -- FIXME: refcount==0 here isn't enough to protect against concurrent
    -- access (we'd need to ensure all users of the object get the same
    -- table instance as their fileref) - but we don't currently do any
    -- concurrent file access, so we don't worry about that for now.
    if refcount == 0 and upper_ref and lower_ref then
        local st = self.upper:Stat(upper_ref)
        if st and not st.is_dir then
            self:_RemoveIfIdentical(upper_ref, lower_ref, path)
        end
    end
end

-- Return information about the given fileref.
function OverlayFS:Stat(ref)
    local upper_ref, lower_ref = unpack(ref)
    return upper_ref and self.upper:Stat(upper_ref)
                     or self.lower:Stat(lower_ref)
end

-- Create a new directory with the given name in the given directory.
function OverlayFS:Mkdir(dir_ref, name)
    if self:Lookup(dir_ref, name) then
        return nil
    end
    local upper_ref = self.upper:Mkdir(dir_ref[1], name)
    if not upper_ref then
        return nil
    end
    return {upper_ref, nil, 0, dir_ref[3].."/"..name}
end

-- Create a new file with the given name in the given directory.
function OverlayFS:Create(dir_ref, name)
    if self:Lookup(dir_ref, name) then
        return nil
    end
    local upper_ref = self.upper:Create(dir_ref[1], name)
    if not upper_ref then
        return nil
    end
    return {upper_ref, nil, 0, dir_ref[3].."/"..name}
end

-- Remove the named object in the given directory.
function OverlayFS:Remove(dir_ref, name)
    local upper_dir, lower_dir = unpack(dir_ref)
    if self.lower:Lookup(lower_dir, name) then
        return nil  -- Can't delete objects which exist on the lower FS.
    end
    return self.upper:Remove(upper_dir, name)
end

-- Return a list of names of all objects in the given directory.
function OverlayFS:Scan(dir_ref)
    local upper_dir, lower_dir = unpack(dir_ref)
    local result
    if upper_dir then
        local names = self.upper:Scan(upper_dir)
        if names then
            result = result or set()
            for _, name in ipairs(names) do
                result:add(name)
            end
        end
    end
    if lower_dir then
        local names = self.lower:Scan(lower_dir)
        if names then
            result = result or set()
            for _, name in ipairs(names) do
                result:add(name)
            end
        end
    end
    return result and result:elements()
end

-- Read the given range of bytes from the given file.
function OverlayFS:Read(file_ref, start, length)
    local upper_ref, lower_ref = unpack(file_ref)
    if upper_ref then
        return self.upper:Read(upper_ref, start, length)
    else
        assert(lower_ref)
        return self.lower:Read(lower_ref, start, length)
    end
end

-- Write the given data to the given file at the given position.
function OverlayFS:Write(file_ref, offset, data)
    if not self:_CopyOnWrite(file_ref) then
        return nil
    end
    local upper_ref, lower_ref = unpack(file_ref)
    assert(upper_ref)
    return self.upper:Write(upper_ref, offset, data)
end

-- Set the given file's size.
function OverlayFS:Truncate(file_ref, size)
    if not self:_CopyOnWrite(file_ref) then
        return nil
    end
    local upper_ref = file_ref[1]
    assert(upper_ref)
    return self.upper:Truncate(upper_ref, size)
end
