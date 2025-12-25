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

-- Helper function to find a file in the filesystem.
local function GetFile(path)
    local dir = FS_DATA
    path = strmatch(path, "^/*(.*)")
    while strstr(path, "/") do
        local parent
        parent, path = strmatch(path, "^([^/]+)/(.*)")
        local next = dir[parent]
        assert(next)
        dir = next
    end
    local file = dir[path]
    assert(file)
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
