--[[

Extends class() from _class.lua to work with WoW Frame instances.

This file implements class()-style classes for the WoW "Frame" type and
certain derived types, allowing custom classes to inherit from them in
the same way they would for any class defined with class().  Instances
of Frame-derived classes can be passed to WoW API functions just like
ordinary frames.

The following native frame types are currently supported:
   - Button
   - Frame
Other types can be added as needed by including them in the
SUPPORTED_CLASSES list below.


Create a native-frame-derived class by passing the appropriate type name
to class(), for example:

    local class = module.class
    local Frame = module.Frame
    MyFrame = class(Frame)

Instances of the derived class can then be created as usual:

    instance = MyFrame(...)

Note, however, that because the Lua table representing the instance must
be created with the CreateFrame() API function, additional arguments to
CreateFrame() cannot be passed through the usual constructor interface.
If any such arguments are required, the class must define an
__allocator() method and pass those arguments to the base class's
__allocator() method, using the returned value as the created instance.
When doing this, pass as the first argument to the base __allocator()
(ordinarily the class object itself) the name of the relevant native
frame type:

    MyButton = class(Button)
    function MyButton.__allocator(thisclass)
        return __super("Button", nil, UIParent, "UIPanelButtonTemplate")
    end

While a bit awkward structurally, this allows classes which do not need
additional CreateFrame() arguments to skip the __allocator() definition
even when the constructor accepts arguments.  Without this workaround,
constructor arguments would be passed to CreateFrame(), probably
resulting in incorrect behavior.


As a convenience, this file also provides a FramePool class which
provides functionality similar to the Blizzard CreateFramePool() API,
allowing a caller to dynamically acquire (allocate) and release (free)
frames from a common pool.  This functionality is needed because Frame
instances are never freed by the WoW engine once created, even if the
associated Lua object becomes unreferenced.

Create a frame pool by instantiating the FramePool class, passing a
reference to the Frame subclass to be managed:

    local class = module.class
    local Frame = module.Frame
    local FramePool = module.FramePool
    MyFrame = class(Frame)
    pool = FramePool(MyFrame)

Frames can then be acquired and released by calling the relevant methods
on the frame pool:

    instance = pool:Acquire()  -- calls Show() on the acquired frame
    pool:Release(instance)  -- calls Hide() on the released frame
    pool:ReleaseAll()  -- releases all currently acquired instances

If the managed class has methods named OnAcquire and OnRelease, they
will be called when an existing instance is returned from Acquire() and
when an instance is passed to Release() (or the instance is released
during a call to ReleaseAll()), respectively.  OnAcquire() is _not_
called when an instance is newly created in Acquire() because there are
no free instances in the pool; the managed class's constructor should
call OnAcquire() itself if this behavior is needed.

A FramePool instance can be used as an iterator in a generic "for"
statement to iterate over all acquired instances:

    for instance in pool do
        assert(instance:IsShown())
    end

As with other cases of iteration in Lua, behavior is undefined if a new
instance is acquired during such a loop, but releasing instances during
the loop is safe (and if an instance is released before it has been
iterated over, it will not be seen by the loop).

]]--

local _, module = ...
assert(module.class, "_class.lua must be loaded first")


-- HACK: Ugly workaround for WoW engine limitation.  util.lua is not
-- loaded at this point, so we have to redeclare this ourselves.
-- See makefenv() for details.
local makefenv_hack_names = {
    "ColorMixin",
    "ItemLocationMixin",
    "ItemTransmogInfoMixin",
    "PlayerLocationMixin",
    "TransmogLocationMixin",
    "TransmogPendingInfoMixin",
    "Vector2DMixin",
    "Vector3DMixin",
}
local wrapped_class = module.class
local ipairs = ipairs
local type = type
module.class = function(...)
    local classdef = wrapped_class(...)
    local classmeta = getmetatable(classdef)
    local methods = classmeta.methods
    local old_newindex = classmeta.__newindex
    classmeta.__newindex = function(t, k, v)
        old_newindex(t, k, v)
        if type(v) == "function" then
            local fenv = getfenv(v)
            for _, name in ipairs(makefenv_hack_names) do
                -- Must be rawset! (fenv has its own __newindex)
                rawset(fenv, name, _G[name])
            end
        end
    end
    return classdef
end
local class = module.class


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
        if type(arg1) == "table" then
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


local FramePool = class()
module.FramePool = FramePool

function FramePool:__constructor(managed_class)
    -- We don't localize this at file scope to avoid unnecessary
    -- load-order dependencies.
    local set = module.set

    self.managed_class = managed_class
    self.used = set()
    self.free = set()

    -- Wrap the self.used set iterator to use as our own iterator.
    -- This doesn't violate encapsulation because we're just making
    -- the same call that generic "for" would make on the set.
    local mt = getmetatable(self)
    mt.__call = function(s, _, i) return self.used(_, i) end
end

-- Acquire an instance of the managed class.  If a free instance is
-- available, it will be shown (with Show()) and its OnAcquire() method
-- (if any) will be called; otherwise, a new instance will be created
-- and returned.
function FramePool:Acquire()
    local instance
    if self.free:len() > 0 then
        instance = self.free:pop()
        instance:Show()
        if instance.OnAcquire then
            instance:OnAcquire()
        end
    else
        instance = self.managed_class()
    end
    self.used:add(instance)
    return instance
end

-- Release a previously acquired instance of the managed class.  The
-- instance's OnRelease() method (if any) will be called, and the frame
-- will be hidden (with Hide()).
function FramePool:Release(instance)
    -- Remove from self.used first so we error out immediately if the
    -- instance is not one of ours.
    self.used:remove(instance)
    if instance.OnRelease then
        instance:OnRelease()
    end
    instance:Hide()
    self.free:add(instance)
end

-- Release all currently acquired instances, as if Release() had been
-- called on each one.
function FramePool:ReleaseAll()
    for instance in self.used do
        if instance.OnRelease then
            instance:OnRelease()
        end
        instance:Hide()
        self.free:add(instance)
    end
    self.used:clear()
end
