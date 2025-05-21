--[[

Extends class() from _class.lua to work with WoW Frame instances.

This file implements class()-style classes for the WoW "Frame" type and
certain derived types, allowing custom classes to inherit from them in
the same way they would for any class defined with  class().  Instances
of Frame-derived classes can be passed to WoW API functions just like
ordinary frames.


Create a native-frame-derived class by passing the appropriate type name
to class(), for example:

    local class = module.class
    local Frame = module.Frame
    MyFrame = class(Frame)

Instances of the derived class can then be created as usual:

    instance = MyFrame(...)

Note, however, that because the Lua table representing the instance must
be created with the CreateFrame() API function, additional arguments to
CreateFrame() cannot be passed through the usual __super() interface.
If any such arguments are required, the class must define an
__allocator() method and pass those arguments to the base class's
__allocator() method, using the returned value as the created instance.
When doing this, the base __allocator() should be called as a _static_
method rather than as a class method, passing as the first argument
(ordinarily the class object itself) the name of the relevant native
frame type:

    MyButton = class(Button)
    function MyButton.__allocator(thisclass)
        return Button.__allocator("Button", nil, UIParent,
                                  "UIPanelButtonTemplate")
    end

While a bit awkward structurally, this allows classes which do not need
additional CreateFrame() arguments to skip the __allocator() definition
even when the constructor accepts arguments.  Without this workaround,
constructor arguments would be passed to CreateFrame(), probably
resulting in incorrect behavior.


The following native frame types are supported:
   - Button
   - Frame

--]]

local _, module = ...
assert(module.class, "_class.lua must be loaded first")


local SUPPORTED_CLASSES = {"Button", "Frame"}

for _, frame_type in ipairs(SUPPORTED_CLASSES) do
    local frame_class = module.class()
    local class_metatable = getmetatable(frame_class)  -- Always non-nil.

    -- This is required because we override the class index.
    class_metatable.__newindex = nil

    -- It's not ideal to create a dummy frame just to get the index,
    -- since WoW frames stick around in memory forever, but this seems
    -- to be the simplest option without any way to look up the index
    -- table directly from the type name.
    local frame_index = getmetatable(CreateFrame(frame_type)).__index
    class_metatable.__index = frame_index

    frame_class.__allocator = function(arg1, ...)
        local instance
        if arg1 == frame_class then
            instance = CreateFrame(frame_type)
        else
            assert(arg1 == frame_type)
            instance = CreateFrame(frame_type, ...)
        end
        local instance_metatable = getmetatable(instance)
        assert(instance_metatable.__index == frame_index)
        -- Suppress the frame's default metatable so we can use normal
        -- inheritance-based lookup.
        return setmetatable(instance, nil)
    end

    module[frame_type] = frame_class
end
