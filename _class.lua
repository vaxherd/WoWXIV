--[[

Syntactic sugar for class declarations in Lua.

This file declares the symbol "class" in the module table provided as
the second argument when loading the file (as is done by the WoW API).
If no second argument is provided, one is created locally and returned
from the module, for use with Lua require().  Module sources using
this syntax are assumed to import the "class" identifier locally with
"local class = module.class" or similar.


Define a class using the following syntax:

    MyClass = class()
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


Optionally, a parent class may be passed to class() to provide the
usual inheritance semantics:

    ParentClass = class()
    function ParentClass:SetX(arg)
        self.x = arg
    end
    function ParentClass:SetY(arg)
        self.y = arg
    end

    SubClass = class(ParentClass)
    function SubClass:SetY(arg)
        ParentClass.SetY(self, arg)
        self.y = self.y + 1
    end

    instance = SubClass()
    instance:SetX(12)  -- calls ParentClass.SetX()
    instance:SetY(34)  -- calls SubClass.SetY()
    print(instance.x, instance.y)  -- prints 12 and 35

Multiple inheritance is not supported.


A constructor may be provided in the class definition by declaring a
method named "__constructor":

    MyClass = class({
        __constructor = function(self, arg)
            self.value = arg
        end
    })

    instance = MyClass(123)
    print(instance.value)  -- prints "123"

If the class has a parent class and the subclass does not define a
constructor, it inherits the parent's constructor (if any).  If the
subclass does define a constructor, it is responsible for calling the
parent class's constructor; this may be done by calling "self:__super()",
passing arguments to the constructor as usual.  If the parent class has
no constructor, __super() is a no-op.  (If the class has no parent class,
__super() raises an error.)

Note that __super() is _only_ valid in constructors; instance methods
must explicitly name the parent class when calling overridden methods.

]]

------------------------------------------------------------------------
-- Implementation
------------------------------------------------------------------------

local _, module = ...
module = module or {} -- so the file can also be loaded with a simple require()

local super_error_msg = "__super() called from class with no superclass"
local function super_error()
    error(super_error_msg)
end

function module.class(parent)
    local classdef = {}
    local instance_metatable = {__index = classdef}
    local class_metatable = {
        __call = function(thisclass, ...)
            local instance = setmetatable({}, instance_metatable)
            instance:__constructor(...)
            return instance
        end
    }
    if parent then
        classdef.__super = function(...) parent.__constructor(...) end
        class_metatable.__index = parent
    else
        classdef.__super = super_error
        -- Define a default constructor for base classes so the "new"
        -- operation doesn't need to check for its presence.
        classdef.__constructor = function() end
    end
    setmetatable(classdef, class_metatable)
    return classdef
end

------------------------------------------------------------------------
-- Test routines (can be run with: lua -e 'require("_class").classTests()')
------------------------------------------------------------------------

local class = module.class
local self = "error"  -- to ensure self is always set when appropriate

local tests = {
    CreateClass = function()
       local Class = class()
       assert(Class)
       assert(type(Class) == "table")
    end,

    ClassConstant = function()
        local Class = class()
        Class.CONSTANT = 10
        assert(Class.CONSTANT == 10)
    end,

    StaticMethod = function()
        local Class = class()
        function Class.StaticMethod()
            return 20
        end
        assert(Class.StaticMethod() == 20)
    end,

    CreateInstance = function()
        local Class = class()
        local instance = Class()
        assert(instance)
        assert(type(instance) == "table")
    end,

    InstanceVariable = function()
        local Class = class()
        local instance = Class()
        instance.x = 30
        assert(instance.x == 30)
        assert(Class.x == nil)
    end,

    ClassConstantViaInstance = function()
        local Class = class()
        Class.CONSTANT = 40
        local instance = Class()
        assert(instance.CONSTANT == 40)
    end,

    StaticMethodViaInstance = function()
        local Class = class()
        function Class.StaticMethod()
            return 50
        end
        local instance = Class()
        assert(instance.StaticMethod() == 50)
    end,

    InstanceMethod = function()
        local Class = class()
        function Class:InstanceMethod()
            self.x = 60
        end
        local instance = Class()
        instance:InstanceMethod()
        assert(instance.x == 60)
    end,

    Constructor = function()
        local Class = class()
        function Class:__constructor()
            self.x = 70
        end
        local instance = Class()
        assert(instance.x == 70)
    end,

    ConstructorArgs = function()
        local Class = class()
        function Class:__constructor(a, b, c)
            self.x = a*100 + b*10 + c
        end
        local instance = Class(1, 2, 3)
        assert(instance.x == 123)
    end,

    InheritConstant = function()
        local Class = class()
        Class.CONSTANT = 80
        local SubClass = class(Class)
        SubClass.SUBCONSTANT = 81
        assert(SubClass.CONSTANT == 80)
        assert(SubClass.SUBCONSTANT == 81)
    end,

    OverrideConstant = function()
        local Class = class()
        Class.CONSTANT = 90
        local SubClass = class(Class)
        SubClass.CONSTANT = 91
        assert(SubClass.CONSTANT == 91)
        assert(Class.CONSTANT == 90)
    end,

    InheritStaticMethod = function()
        local Class = class()
        function Class.StaticMethod()
            return 100
        end
        local SubClass = class(Class)
        assert(SubClass.StaticMethod() == 100)
    end,

    OverrideStaticMethod = function()
        local Class = class()
        function Class.StaticMethod()
            return 110
        end
        local SubClass = class(Class)
        function SubClass.StaticMethod()
            return 111
        end
        assert(SubClass.StaticMethod() == 111)
        assert(Class.StaticMethod() == 110)
    end,

    InheritInstanceMethod = function()
        local Class = class()
        function Class:InstanceMethod()
            self.x = 120
        end
        local SubClass = class(Class)
        local instance = SubClass()
        instance:InstanceMethod()
        assert(instance.x == 120)
    end,

    OverrideInstanceMethod = function()
        local Class = class()
        function Class:InstanceMethod()
            self.x = 130
        end
        local SubClass = class(Class)
        function SubClass:InstanceMethod()
            self.y = 131
        end
        local instance = SubClass()
        instance:InstanceMethod()
        assert(instance.x == nil)
        assert(instance.y == 131)
        local instance2 = Class()
        instance2:InstanceMethod()
        assert(instance2.x == 130)
        assert(instance2.y == nil)
    end,

    InstanceMethodCallParent = function()
        local Class = class()
        function Class:InstanceMethod()
            self.x = 140
        end
        local SubClass = class(Class)
        function SubClass:InstanceMethod()
            Class:InstanceMethod(self)
            self.x = self.x+2
            self.y = 141
        end
        local instance = SubClass()
        instance:InstanceMethod()
        assert(instance.x == 142)
        assert(instance.y == 141)
        local instance2 = Class()
        instance2:InstanceMethod()
        assert(instance2.x == 140)
        assert(instance2.y == nil)
    end,

    InheritConstructor = function()
        local Class = class()
        function Class:__constructor()
            self.x = 150
        end
        local SubClass = class(Class)
        local instance = SubClass()
        assert(instance.x == 150)
    end,

    OverrideConstructor = function()
        local Class = class()
        function Class:__constructor()
            self.x = 160
        end
        local SubClass = class(Class)
        function SubClass:__constructor()
            self.y = 161
        end
        local instance = SubClass()
        assert(instance.x == nil)
        assert(instance.y == 161)
        local instance2 = Class()
        assert(instance2.x == 160)
        assert(instance2.y == nil)
    end,

    CallSuperConstructor = function()
        local Class = class()
        function Class:__constructor()
            self.x = 170
        end
        local SubClass = class(Class)
        function SubClass:__constructor()
            self:__super()
            self.y = 171
        end
        local instance = SubClass()
        assert(instance.x == 170)
        assert(instance.y == 171)
        local instance2 = Class()
        assert(instance2.x == 170)
        assert(instance2.y == nil)
    end,

    CallSuperConstructorArgs = function()
        local Class = class()
        function Class:__constructor(a, b, c)
            self.x = a*100 + b*10 + c
        end
        local SubClass = class(Class)
        function SubClass:__constructor(n)
            self:__super(n+2, n+3, n+5)
        end
        local instance = SubClass(1)
        assert(instance.x == 346)
    end,

    CallSuperNoConstructor = function()
        local Class = class()
        local SubClass = class(Class)
        function SubClass:__constructor()
            self:__super()
            self.y = 180
        end
        local instance = SubClass()
        assert(instance.y == 180)
        local instance2 = Class()
        assert(instance2.y == nil)
    end,

    CallSuperNoParent = function()
        local Class = class()
        function Class:__constructor()
            self:__super()
        end
        local function f() return Class() end
        local result, errmsg = pcall(f)
        assert(result == false)
        assert(errmsg:find(super_error_msg, 1, true))
    end,

    NestedInherit = function()
        local Class = class()
        Class.CONSTANT = 190
        local SubClass = class(Class)
        SubClass.SUBCONSTANT = 191
        local SubSubClass = class(SubClass)
        SubSubClass.SUBSUBCONSTANT = 192
        assert(SubSubClass.CONSTANT == 190)
        assert(SubSubClass.SUBCONSTANT == 191)
        assert(SubSubClass.SUBSUBCONSTANT == 192)
    end,

    NestedOverride = function()
        local Class = class()
        Class.CONSTANT = 200
        local SubClass = class(Class)
        local SubSubClass = class(SubClass)
        SubSubClass.CONSTANT = 201
        assert(SubSubClass.CONSTANT == 201)
        assert(SubClass.CONSTANT == 200)
        assert(Class.CONSTANT == 200)
    end,

    NestedInheritConstructor = function()
        local Class = class()
        function Class:__constructor()
            self.x = 210
        end
        local SubClass = class(Class)
        local SubSubClass = class(SubClass)
        local instance = SubSubClass()
        assert(instance.x == 210)
    end,

    NestedOverrideConstructor = function()
        local Class = class()
        function Class:__constructor()
            self.x = 220
        end
        local SubClass = class(Class)
        local SubSubClass = class(SubClass)
        function SubSubClass:__constructor()
            self.y = 221
        end
        local instance = SubSubClass()
        assert(instance.x == nil)
        assert(instance.y == 221)
        local instance2 = SubClass()
        assert(instance2.x == 220)
        assert(instance2.y == nil)
        local instance3 = Class()
        assert(instance3.x == 220)
        assert(instance3.y == nil)
    end,

    NestedCallSuperConstructor = function()
        local Class = class()
        function Class:__constructor()
            self.x = 230
        end
        local SubClass = class(Class)
        local SubSubClass = class(SubClass)
        function SubSubClass:__constructor()
            self:__super()
            self.y = 231
        end
        local instance = SubSubClass()
        assert(instance.x == 230)
        assert(instance.y == 231)
        local instance2 = SubClass()
        assert(instance2.x == 230)
        assert(instance2.y == nil)
        local instance3 = Class()
        assert(instance3.x == 230)
        assert(instance3.y == nil)
    end,
}

function module.classTests(verbose)
    local fail = 0
    for name, test in pairs(tests) do
        if verbose then
            io.write(name..": ")
        end
        local _, err = pcall(test)
        if err then fail = fail+1 end
        if verbose then
            if err then
                print("FAIL: "..err)
            else
                print("pass")
            end
        elseif err then
            print("FAIL: "..name..": "..err)
        end
    end
    if fail > 0 then
        print(("%d test%s failed."):format(fail, fail==1 and "" or "s"))
        return false
    else
        print("All tests passed.")
        return true
    end
end

------------------------------------------------------------------------

return module
