--[[

Extends class() from _class.lua to work with WoW Frame instances.

This file replaces class() with a version allowing custom classes to
inherit from Frame and other WoW native frame classes in the same way they
would for any class defined with class().  Instances of Frame-derived
classes can be passed to WoW API functions just like ordinary frames.


Create a native-frame-derived class by passing the appropriate type name
as a string to class(), for example:

    MyFrame = class("Frame")

Instances of the derived class can then be created as usual:

    instance = MyFrame(...)

Note, however, that because the Lua table representing the instance must
be created with the CreateFrame() API function, additional arguments to
CreateFrame() cannot be passed through the usual __super() interface.
If any such arguments are required, they must be constant for all
instances, and must be provided as additional arguments to the class()
call which creates the class.  For example:

    MyButton = class("Button", nil, UIParent, "UIPanelButtonTemplate")

Naturally, global names cannot be set for such frames unless the class is
intended to be a singleton.


The following native frame classes are supported:
   - Button
   - Frame
Other Frame-derived classes will be rejected with an error.

--]]

local _, module = ...
assert(module.class, "_class.lua must be loaded first")


local SUPPORTED_CLASSES = {
    Button = true,
    Frame = true,
}

local real_class = module.class

function module.class(...)
    local parent = ...
    if not SUPPORTED_CLASSES[parent] then return real_class(...) end

    -- This table serves as a class object stub in which we can record the
    -- native frame type's __index table once we know it.  (We don't want
    -- to create a dummy native frame to look it up, because WoW never
    -- frees frames even after they are no longer referenced.)
    local parent_metatable = {}
    local parent_class = setmetatable({}, parent_metatable)

    local classdef = real_class(parent_class)

    -- Pretend the native frame class has an empty constructor (since
    -- our stub class objects don't have any class infrastructure set up).
    classdef.__super = function() end

    -- Replace the instance generator with a CreateFrame() call.
    local class_metatable = getmetatable(classdef)
    local instance_metatable = getmetatable(classdef())
    -- Note that we have to preserve our own varargs here because the
    -- varargs to __call() will overwrite them!
    local CreateFrame_args = {...}
    class_metatable.__call = function(thisclass, ...)
        local instance = CreateFrame(unpack(CreateFrame_args))
        local native_index = getmetatable(instance).__index
        assert(native_index)
        assert(not parent_metatable.__index
               or parent_metatable.__index == native_index)
        parent_metatable.__index = native_index
        setmetatable(instance, instance_metatable)
        instance:__constructor(...)
        return instance
    end

    return classdef
end
