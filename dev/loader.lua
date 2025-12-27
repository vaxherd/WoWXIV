local module_args = {...}

local strfind = string.find
local strmatch = string.match
local strstr = function(s1,s2,pos) return strfind(s1,s2,pos,true) end
local strsub = string.sub

-- List of scripts to load, in load order.  On installation, this table is
-- populated with the actual list of scripts from the .toc file.
local LOAD_ORDER = {
--@LOAD_ORDER@--
}

-- File content to expose via the filesystem interface.  On installation,
-- this table is populated with the actual file data.
local FS_DATA = {
--@FS_DATA@--
}

-- Flag indicating whether the filesystem data is compressed.  On
-- installation, this is replaced with an appropriate initializer.
local FS_COMPRESSED --@FS_COMPRESSED@--

-- File overlay data table.  This is a MemFS data store, but we access it
-- directly to avoid external dependencies from the loader.  This will be
-- persisted via WoW's SavedVariables mechanism.
WoWXIV_initfs_overlay = WoWXIV_initfs_overlay or {}


-- Reimplementation of ResolvePath() -> MemFS:Lookup().  Returns the inode
-- of the object, or nil if the path does not exist.
local function ResolvePathForMemFS(store, path)
    local ROOT_INODE = 1  -- As in memfs.lua.
    local inode = ROOT_INODE
    if not store[inode] then
        return nil  -- No data in the overlay filesystem.
    end
    local index = 1
    while index <= #path do
        local slash = strstr(path, "/", index) or #path+1
        local name = strsub(path, index, slash-1)
        local next = store[inode][name]
        if not next then
            return nil
        end
        inode = next
        index = slash+1
    end
    return inode
end

-- Helper function to find a file in the filesystem.
local function GetFile(path)
    local file
    local overlay_inode = ResolvePathForMemFS(WoWXIV_initfs_overlay, path)
    if overlay_inode then
        file = WoWXIV_initfs_overlay[overlay_inode]
    else
        local node = FS_DATA
        local index = 1
        while index <= #path do
            local slash = strstr(path, "/", index) or #path+1
            local name = strsub(path, index, slash-1)
            local next = node[name]
            assert(next)
            node = next
            index = slash+1
        end
        file = node
        if FS_COMPRESSED then
            assert(type(file) == "string")
            local ok, result = pcall(C_EncodingUtil.DecompressString,
                                     file, Enum.CompressionMethod.Zlib)
            if ok then
                file = result
            else
                print("Error decompressing "..path.." (size "..tostring(#file)..")")
                error(result)
            end
        end
    end
    assert(type(file) == "string")
    return file
end


-- Load all scripts.
for _, script in ipairs(LOAD_ORDER) do
    local code, err = loadstring(GetFile(script), script)
    if not code then
        error(err)
    end
    code(unpack(module_args))
end

-- Expose the filesystem data to the module for later mounting.
local module = module_args[2]
module._loader_FS_DATA = FS_DATA
module._loader_FS_COMPRESSED = FS_COMPRESSED
