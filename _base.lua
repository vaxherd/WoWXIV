--[[

Syntactic sugar for class declarations in Lua.

This file declares the symbol "class" in the module table provided as
the second argument when loading the file (as is done by the WoW API).
Module sources using this syntax are assumed to import the "class"
identifier locally with "local class = module.class" or similar.


Define a class using the following syntax:

    MyClass = class {
        CLASS_CONSTANT = 42,
        StaticMethod = function(arg1, arg2, ...)
            -- ...
        end,
        InstanceMethod = function(self, arg1, arg2, ...)
            -- ...
        end,
    }

Note that the "self" parameter must be explicitly listed for instance
methods, as in Python, and every declaration (including methods) must
be followed by a colon.  If desired, this alternate, more Lua-like
syntax may be used:

    MyClass = class{}  -- "class()" also works
    MyClass.CLASS_CONSTANT = 42
    function MyClass.StaticMethod(arg1, arg2, ...)
        -- ...
    end
    function MyClass:InstanceMethod(arg1, arg2, ...)
        -- ...
    end


Instances of the class can then be created with:

    instance = MyClass()

and called as usual for Lua instances:

    instance.StaticMethod(...)
    instance:InstanceMethod(...)


A constructor may be provided in the class definition by declaring a
method named "__constructor":

    MyClass = class({
        __constructor = function(self, arg)
            self.value = arg
        end
    })

    instance = MyClass(123)
    print(instance.value)  -- prints "123"

]]

------------------------------------------------------------------------

local _, module = ...

function module.class(classdef)
    classdef = classdef or {}
    -- Define a default constructor so the new operation doesn't need
    -- to check for its presence.
    if not classdef.__constructor then
        classdef.__constructor = function(self) end
    end
    setmetatable(classdef, {
        __call = function(thisclass, ...)
            local instance = setmetatable({}, {__index = thisclass})
            instance:__constructor(...)
            return instance
        end
    })
    return classdef
end
