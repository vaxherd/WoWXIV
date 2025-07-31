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

and manipulated as usual for Lua instances:

    instance.instance_variable = instance.CLASS_CONSTANT
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

Methods defined in a class (whether static, class, or instance methods)
which override methods in a parent class may use __super() to call the
overridden method without having to name it explicitly.  In the example
above, SubClass:SetY() could also have been written:

    function SubClass:SetY(arg)
        __super(self, arg)
        self.y = self.y + 1
    end

Note that __super() assumes that methods are defined statically, as in
the examples above.  __super() may not work correctly in other cases
such as dynamically-generated or dynamically-modified methods.


A constructor may be provided in the class definition by declaring a
method named "__constructor":

    MyClass = class()
    function MyClass:__constructor(arg)
        self.value = arg
    end

    instance = MyClass(123)
    print(instance.value)  -- prints "123"

If the class has a parent class and the subclass does not define a
constructor, it inherits the parent's constructor (if any).  If the
subclass does define a constructor, it is responsible for calling the
parent class's constructor, typically with "__super(self, [args])".


Additionally, classes may provide a class method named "__allocator"
which creates the initial table for an instance:

    MyClass = class()
    MyClass.singleton = {}
    function MyClass.__allocator(class)
        return class.singleton
    end

    instance = MyClass()
    print(instance == MyClass.singleton)  -- prints "true"

This can be useful for wrapping external objects in classes where the
instance must use an externally provided table, such as Frame objects
in the game World of Warcraft.  If any constructor arguments are passed
to the instance creation call, they will be passed to the allocator
method as well.

The allocator must return a table value (it is not allowed to fail).
The method should raise an error under any condition which would prevent
it from creating a new instance.

Any metatable set on the returned instance will be preserved.  If no
metatable is set, a new one will be created.  Note that If the allocator
sets an instance metatable which includes an __index field, the value of
that field will replace the normal __index which redirects to the class
definition; this will prevent ordinary use of the table as a class
instance unless special care is taken, and should normally not be done.

As usual for class methods, when inheriting a base class's __allocator()
method, the inherited method receives the subclass as its implicit
argument, not the base class.

]]--

------------------------------------------------------------------------
-- Implementation
------------------------------------------------------------------------

local _, module = ...
module = module or {} -- so the file can also be loaded with a simple require()

-- Localize some commonly called functions to reduce lookup cost.
local getmetatable = getmetatable
local rawget = rawget
local rawset = rawset
local setmetatable = setmetatable
local type = type

-- Error messages are defined as constants for testing convenience.
local PARENT_TYPE_ERROR_MSG = "Parent class must be a table"
local SUPER_NO_PARENT_ERROR_MSG = "__super() called from class with no parent"
local SUPER_NO_METHOD_ERROR_MSG = "No overridden method to call"
local ALLOC_RESULT_ERROR_MSG = "__allocator() must return a table"

local function make_super(parent, name)
    if parent then
        -- We have a choice to make here: we can either look up the
        -- overridden function now, saving a lookup and test per call,
        -- or look it up at call time, allowing more flexibility in the
        -- order of class/method definition.  We choose flexibility and
        -- perform the lookup at call time.
        return function(...)
            local f = parent[name]
            if f then
                return f(...)
            else
                error(SUPER_NO_METHOD_ERROR_MSG)
            end
        end
    else
        return function() error(SUPER_NO_PARENT_ERROR_MSG) end
    end
end

function module.class(parent)
    if parent and type(parent) ~= "table" then
        error(PARENT_TYPE_ERROR_MSG)
    end

    local classdef = {}
    local instance_metatable = {__index = classdef}
    local class_metatable = {}
    setmetatable(classdef, class_metatable)

    class_metatable.__call = function(thisclass, ...)
        local instance = thisclass.__allocator(thisclass, ...)
        assert(type(instance) == "table", ALLOC_RESULT_ERROR_MSG)
        local metatable = getmetatable(instance)
        if metatable then
            if metatable.__index == nil then
                -- Avoid directly referencing classdef for consistency and
                -- minimization of closure context.
                metatable.__index = instance_metatable.__index
            end
        else
            metatable = instance_metatable
        end
        setmetatable(instance, metatable)
        instance:__constructor(...)
        return instance
    end

    -- We can't put methods directly into the class table (a la rawset())
    -- because then we can't catch if the method is later redefined, such
    -- as will always occur for constructors (since we define a default
    -- constructor below).  Instead, we create a separate nametable for
    -- methods and look them up manually via the __index metamethod.
    local methods = {}
    -- We technically don't need to save this anywhere since we only
    -- reference it as an upvalue, but hidden values are unkind to users.
    class_metatable.methods = methods

    local method_metatable = {__index = _G, __newindex = _G}
    class_metatable.__newindex = function(t, k, v)
        if type(v) == "function" then
            -- Define __super() for this specific function.  We need a
            -- separate environment for each function because this is the
            -- only place we'll see the name being associated with it.
            local method_env = setmetatable({__super = make_super(parent, k)},
                                            method_metatable)
            rawset(methods, k, setfenv(v, method_env))
        else
            rawset(t, k, v)
        end
    end

    class_metatable.__index = function(t, k)
        return methods[k] or (parent and parent[k])
    end

    -- Define a default allocator and constructor so the "new" operation
    -- doesn't need to check for their presence.
    if parent then
        -- Since we set the metatable above, __super() is available here.
        classdef.__allocator = function(...) return __super(...) end
        classdef.__constructor = function(...) __super(...) end
    else
        classdef.__allocator = function() return {} end
        classdef.__constructor = function() end
    end

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

    InstanceMethodReturn = function()
        local Class = class()
        function Class:InstanceMethod()
            return self.x + 1
        end
        local instance = Class()
        instance.x = 65
        assert(instance:InstanceMethod() == 66)
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

    Allocator = function()
        local Class = class()
        local fixed_instance = {}
        function Class.__allocator(thisclass)
            assert(thisclass == Class)
            return fixed_instance
        end
        local instance = Class()
        assert(instance == fixed_instance)
        local instance2 = Class()
        assert(instance2 == fixed_instance)
    end,

    AllocatorArgs = function()
        local Class = class()
        function Class.__allocator(thisclass, t)
            assert(thisclass == Class)
            return t
        end
        local fixed_instance = {}
        local instance = Class(fixed_instance)
        assert(instance == fixed_instance)
    end,

    AllocatorAndConstructorArgs = function()
        local Class = class()
        function Class.__allocator(thisclass, t)
            assert(thisclass == Class)
            return t
        end
        function Class:__constructor(_, x)
            self.x = x
        end
        local fixed_instance = {}
        local instance = Class(fixed_instance, 71)
        assert(instance == fixed_instance)
        assert(instance.x == 71)
    end,

    AllocatorMetatable = function()
        local Class = class()
        function Class.__allocator(thisclass)
            assert(thisclass == Class)
            return setmetatable({}, {foo = 72})
        end
        local instance = Class()
        assert(getmetatable(instance).foo == 72)
        assert(instance.__allocator == Class.__allocator)
    end,

    AllocatorMetatableIndex = function()
        local Class = class()
        function Class.__allocator(thisclass)
            assert(thisclass == Class)
            return setmetatable({}, {
                __index = {foo = 73, __constructor = function() end}})
        end
        local instance = Class()
        assert(instance.foo == 73)
        assert(instance.__allocator == nil)
    end,

    AllocatorInvalidResult = function()
        local Class = class()
        function Class.__allocator(thisclass)
            assert(thisclass == Class)
            return true
        end
        local function f() return Class() end
        local result, errmsg = pcall(f)
        assert(result == false)
        assert(errmsg:find(ALLOC_RESULT_ERROR_MSG, 1, true), errmsg)
    end,

    InvalidParentType = function()
        local function f() return class("foo") end
        local result, errmsg = pcall(f)
        assert(result == false)
        assert(errmsg:find(PARENT_TYPE_ERROR_MSG, 1, true), errmsg)
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
            Class.InstanceMethod(self)
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

    InstanceMethodCallParentReturn = function()
        local Class = class()
        function Class:InstanceMethod()
            return self.x+1
        end
        local SubClass = class(Class)
        function SubClass:InstanceMethod()
            return Class.InstanceMethod(self) + 2
        end
        local instance = SubClass()
        instance.x = 150
        assert(instance:InstanceMethod() == 153)
        local instance2 = Class()
        instance2.x = 155
        assert(instance2:InstanceMethod() == 156)
    end,

    InstanceMethodCallParentReturnMultiple = function()
        local Class = class()
        function Class:InstanceMethod()
            return self.x+1, self.x-1, self.x*2
        end
        local SubClass = class(Class)
        function SubClass:InstanceMethod()
            local a, b, c = Class.InstanceMethod(self)
            return a+2, b-2, c*3
        end
        local instance = SubClass()
        instance.x = 160
        local a, b, c = instance:InstanceMethod()
        assert(a == 163)
        assert(b == 157)
        assert(c == 960)
        local instance2 = Class()
        instance2.x = 165
        local d, e, f = instance2:InstanceMethod()
        assert(d == 166)
        assert(e == 164)
        assert(f == 330)
    end,

    InstanceMethodCallSuper = function()
        local Class = class()
        function Class:InstanceMethod()
            self.x = 170
        end
        local SubClass = class(Class)
        function SubClass:InstanceMethod()
            __super(self)
            self.x = self.x+2
            self.y = 171
        end
        local instance = SubClass()
        instance:InstanceMethod()
        assert(instance.x == 172)
        assert(instance.y == 171)
        local instance2 = Class()
        instance2:InstanceMethod()
        assert(instance2.x == 170)
        assert(instance2.y == nil)
    end,

    InstanceMethodCallSuperReturn = function()
        local Class = class()
        function Class:InstanceMethod()
            return self.x + 1
        end
        local SubClass = class(Class)
        function SubClass:InstanceMethod()
            return __super(self) + 2
        end
        local instance = SubClass()
        instance.x = 180
        assert(instance:InstanceMethod() == 183)
        local instance2 = Class()
        instance2.x = 185
        assert(instance2:InstanceMethod() == 186)
    end,

    InstanceMethodCallSuperReturnMultiple = function()
        local Class = class()
        function Class:InstanceMethod()
            return self.x+1, self.x-1, self.x*2
        end
        local SubClass = class(Class)
        function SubClass:InstanceMethod()
            local a, b, c = __super(self)
            return a+2, b-2, c*3
        end
        local instance = SubClass()
        instance.x = 190
        local a, b, c = instance:InstanceMethod()
        assert(a == 193)
        assert(b == 187)
        assert(c == 1140)
        local instance2 = Class()
        instance2.x = 195
        local d, e, f = instance2:InstanceMethod()
        assert(d == 196)
        assert(e == 194)
        assert(f == 390)
    end,

    InstanceMethodCallSuperReturnNone = function()
        local Class = class()
        function Class:InstanceMethod()
            self.x = 200
        end
        local SubClass = class(Class)
        function SubClass:InstanceMethod()
            local n = select("#", __super(self))
            self.x = self.x + 1 + n
        end
        local instance = SubClass()
        instance:InstanceMethod()
        assert(instance.x == 201)
    end,

    InstanceMethodCallSuperNoParent = function()
        local Class = class()
        function Class:InstanceMethod()
            __super(self)
        end
        local instance = Class()
        local result, errmsg = pcall(instance.InstanceMethod, instance)
        assert(result == false)
        assert(errmsg:find(SUPER_NO_PARENT_ERROR_MSG, 1, true), errmsg)
    end,

    InstanceMethodCallSuperNoOverride = function()
        local Class = class()
        function Class:InstanceMethod()
            self.x = 200
        end
        local SubClass = class(Class)
        function SubClass:InstanceMethod2()
            __super(self)
            self.x = self.x+2
            self.y = 201
        end
        local instance = SubClass()
        local result, errmsg = pcall(instance.InstanceMethod2, instance)
        assert(result == false)
        assert(errmsg:find(SUPER_NO_METHOD_ERROR_MSG, 1, true), errmsg)
    end,

    InheritConstructor = function()
        local Class = class()
        function Class:__constructor()
            self.x = 210
        end
        local SubClass = class(Class)
        local instance = SubClass()
        assert(instance.x == 210)
    end,

    OverrideConstructor = function()
        local Class = class()
        function Class:__constructor()
            self.x = 220
        end
        local SubClass = class(Class)
        function SubClass:__constructor()
            self.y = 221
        end
        local instance = SubClass()
        assert(instance.x == nil)
        assert(instance.y == 221)
        local instance2 = Class()
        assert(instance2.x == 220)
        assert(instance2.y == nil)
    end,

    ConstructorCallParent = function()
        local Class = class()
        function Class:__constructor()
            self.x = 230
        end
        local SubClass = class(Class)
        function SubClass:__constructor()
            Class.__constructor(self)
            self.y = 231
        end
        local instance = SubClass()
        assert(instance.x == 230)
        assert(instance.y == 231)
        local instance2 = Class()
        assert(instance2.x == 230)
        assert(instance2.y == nil)
    end,

    ConstructorCallParentArgs = function()
        local Class = class()
        function Class:__constructor(a, b, c)
            self.x = a*100 + b*10 + c
        end
        local SubClass = class(Class)
        function SubClass:__constructor(n)
            Class.__constructor(self, n+2, n+3, n+5)
        end
        local instance = SubClass(1)
        assert(instance.x == 346)
    end,

    ConstructorCallParentSuper = function()
        local Class = class()
        function Class:__constructor()
            self.x = 240
        end
        local SubClass = class(Class)
        function SubClass:__constructor()
            __super(self)
            self.y = 241
        end
        local instance = SubClass()
        assert(instance.x == 240)
        assert(instance.y == 241)
        local instance2 = Class()
        assert(instance2.x == 240)
        assert(instance2.y == nil)
    end,

    ConstructorCallParentSuperArgs = function()
        local Class = class()
        function Class:__constructor(a, b, c)
            self.x = a*100 + b*10 + c
        end
        local SubClass = class(Class)
        function SubClass:__constructor(n)
            __super(self, n+2, n+3, n+5)
        end
        local instance = SubClass(2)
        assert(instance.x == 457)
    end,

    ConstructorCallSuperNoParentConstructor = function()
        local Class = class()
        local SubClass = class(Class)
        function SubClass:__constructor()
            __super(self)
            self.y = 250
        end
        local instance = SubClass()
        assert(instance.y == 250)
        local instance2 = Class()
        assert(instance2.y == nil)
    end,

    ConstructorCallSuperNoParent = function()
        local Class = class()
        function Class:__constructor()
            __super(self)
        end
        local function f() return Class() end
        local result, errmsg = pcall(f)
        assert(result == false)
        assert(errmsg:find(SUPER_NO_PARENT_ERROR_MSG, 1, true), errmsg)
    end,

    InheritAllocator = function()
        local Class = class()
        local fixed_instance = {}
        local SubClass
        function Class.__allocator(thisclass)
            assert(thisclass == SubClass)
            return fixed_instance
        end
        SubClass = class(Class)  -- Declared local above.
        local instance = SubClass()
        assert(instance == fixed_instance)
    end,

    OverrideAllocator = function()
        local Class = class()
        local fixed_instance = {}
        function Class.__allocator(thisclass)
            assert(thisclass == Class)
            return fixed_instance
        end
        local SubClass = class(Class)
        local fixed_instance2 = {}
        function SubClass.__allocator(thisclass)
            assert(thisclass == SubClass)
            return fixed_instance2
        end
        local instance = SubClass()
        assert(instance == fixed_instance2)
        local instance2 = Class()
        assert(instance2 == fixed_instance)
    end,

    AllocatorCallParent = function()
        local Class = class()
        local fixed_instance = {}
        function Class.__allocator(thisclass)
            fixed_instance.a = thisclass
            return fixed_instance
        end
        local SubClass = class(Class)
        function SubClass.__allocator(thisclass)
            local instance = Class.__allocator(thisclass)
            instance.b = thisclass
            return instance
        end
        local instance = SubClass()
        assert(instance == fixed_instance)
        assert(instance.a == SubClass)
        assert(instance.b == SubClass)
        local instance2 = Class()
        assert(instance2 == fixed_instance)
        assert(instance2.a == Class)
        assert(instance2.b == SubClass)
    end,

    AllocatorCallSuper = function()
        local Class = class()
        local fixed_instance = {}
        function Class.__allocator(thisclass)
            fixed_instance.a = thisclass
            return fixed_instance
        end
        local SubClass = class(Class)
        function SubClass.__allocator(thisclass)
            assert(thisclass == SubClass)
            local instance = __super(thisclass)
            instance.b = (instance.b or 0) + 1
            return instance
        end
        local instance = SubClass()
        assert(instance == fixed_instance)
        assert(instance.a == SubClass)
        assert(instance.b == 1)
        local instance2 = Class()
        assert(instance2 == fixed_instance)
        assert(instance2.a == Class)
        assert(instance2.b == 1)
    end,

    NestedInherit = function()
        local Class = class()
        Class.CONSTANT = 260
        local SubClass = class(Class)
        SubClass.SUBCONSTANT = 261
        local SubSubClass = class(SubClass)
        SubSubClass.SUBSUBCONSTANT = 262
        assert(SubSubClass.CONSTANT == 260)
        assert(SubSubClass.SUBCONSTANT == 261)
        assert(SubSubClass.SUBSUBCONSTANT == 262)
    end,

    NestedOverride = function()
        local Class = class()
        Class.CONSTANT = 270
        local SubClass = class(Class)
        local SubSubClass = class(SubClass)
        SubSubClass.CONSTANT = 271
        assert(SubSubClass.CONSTANT == 271)
        assert(SubClass.CONSTANT == 270)
        assert(Class.CONSTANT == 270)
    end,

    NestedInheritConstructor = function()
        local Class = class()
        function Class:__constructor()
            self.x = 280
        end
        local SubClass = class(Class)
        local SubSubClass = class(SubClass)
        local instance = SubSubClass()
        assert(instance.x == 280)
    end,

    NestedOverrideConstructor = function()
        local Class = class()
        function Class:__constructor()
            self.x = 290
        end
        local SubClass = class(Class)
        local SubSubClass = class(SubClass)
        function SubSubClass:__constructor()
            self.y = 291
        end
        local instance = SubSubClass()
        assert(instance.x == nil)
        assert(instance.y == 291)
        local instance2 = SubClass()
        assert(instance2.x == 290)
        assert(instance2.y == nil)
        local instance3 = Class()
        assert(instance3.x == 290)
        assert(instance3.y == nil)
    end,

    NestedCallParentConstructor = function()
        local Class = class()
        function Class:__constructor()
            self.x = 300
        end
        local SubClass = class(Class)
        local SubSubClass = class(SubClass)
        function SubSubClass:__constructor()
            __super(self)
            self.y = 301
        end
        local instance = SubSubClass()
        assert(instance.x == 300)
        assert(instance.y == 301)
        local instance2 = SubClass()
        assert(instance2.x == 300)
        assert(instance2.y == nil)
        local instance3 = Class()
        assert(instance3.x == 300)
        assert(instance3.y == nil)
    end,

    NestedSuperCall = function()
        local Class = class()
        function Class:__constructor()
            self.x = 310
        end
        local SubClass = class(Class)
        function SubClass:__constructor()
            __super(self)
            self.y = 311
        end
        local SubSubClass = class(SubClass)
        function SubSubClass:__constructor()
            __super(self)
            self.z = 312
        end
        local instance = SubSubClass()
        assert(instance.x == 310)
        assert(instance.y == 311)
        assert(instance.z == 312)
        local instance2 = SubClass()
        assert(instance2.x == 310)
        assert(instance2.y == 311)
        assert(instance2.z == nil)
        local instance3 = Class()
        assert(instance3.x == 310)
        assert(instance3.y == nil)
        assert(instance3.z == nil)
    end,

    NestedInheritAllocator = function()
        local Class = class()
        local fixed_instance = {}
        local SubSubClass
        function Class.__allocator(thisclass)
            assert(thisclass == SubSubClass)
            return fixed_instance
        end
        local SubClass = class(Class)
        SubSubClass = class(SubClass)  -- Declared local above.
        local instance = SubSubClass()
        assert(instance == fixed_instance)
    end,

    NestedOverrideAllocator = function()
        local Class = class()
        local fixed_instance = {}
        local SubClass
        function Class.__allocator(thisclass)
            fixed_instance.a = thisclass
            return fixed_instance
        end
        local SubClass = class(Class)
        local SubSubClass = class(SubClass)
        local fixed_instance2 = {}
        function SubSubClass.__allocator(thisclass)
            assert(thisclass == SubSubClass)
            return fixed_instance2
        end
        local instance = SubSubClass()
        assert(instance == fixed_instance2)
        local instance2 = SubClass()
        assert(instance2 == fixed_instance)
        assert(instance2.a == SubClass)
        local instance3 = Class()
        assert(instance3 == fixed_instance)
        assert(instance3.a == Class)
    end,

    NestedCallParentAllocator = function()
        local Class = class()
        local fixed_instance = {}
        function Class.__allocator(thisclass)
            fixed_instance.a = thisclass
            return fixed_instance
        end
        local SubClass = class(Class)
        local SubSubClass = class(SubClass)
        function SubSubClass.__allocator(thisclass)
            assert(thisclass == SubSubClass)
            local instance = __super(thisclass)
            instance.b = (instance.b or 0) + 1
            return instance
        end
        local instance = SubSubClass()
        assert(instance == fixed_instance)
        assert(instance.a == SubSubClass)
        assert(instance.b == 1)
        local instance2 = SubClass()
        assert(instance2 == fixed_instance)
        assert(instance2.a == SubClass)
        assert(instance2.b == 1)
        local instance3 = Class()
        assert(instance3 == fixed_instance)
        assert(instance3.a == Class)
        assert(instance3.b == 1)
    end,

    DeclareSuperMemberAfterSubclass = function()
        local Class = class()
        local SubClass = class(Class)
        Class.x = 320
        local instance = SubClass()
        assert(instance.x == 320)
    end,

    DeclareSuperMemberAfterSubclassInstantiation = function()
        local Class = class()
        local SubClass = class(Class)
        local instance = SubClass()
        Class.x = 330
        assert(instance.x == 330)
    end,

    DeclareParentConstructorAfterSubclass = function()
        local Class = class()
        local SubClass = class(Class)
        function Class:__constructor()
            self.x = 340
        end
        local instance = SubClass()
        assert(instance.x == 340)
    end,

    DeclareParentConstructorAfterSubclassConstructor = function()
        local Class = class()
        local SubClass = class(Class)
        function SubClass:__constructor()
            __super(self)
            self.y = 351
        end
        function Class:__constructor()
            self.x = 350
        end
        local instance = SubClass()
        assert(instance.x == 350)
        assert(instance.y == 351)
    end,

    DeclareSuperAllocatorAfterSubclass = function()
        local Class = class()
        local SubClass = class(Class)
        local fixed_instance = {}
        function Class.__allocator(thisclass)
            assert(thisclass == SubClass)
            return fixed_instance
        end
        local instance = SubClass()
        assert(instance == fixed_instance)
    end,

    DeclareSuperAllocatorAfterSubclassAllocator = function()
        local Class = class()
        local SubClass = class(Class)
        local fixed_instance = {}
        local fixed_instance2 = {}
        function SubClass.__allocator(thisclass)
            assert(thisclass == SubClass)
            return fixed_instance2
        end
        function Class.__allocator(thisclass)
            assert(thisclass == Class)
            return fixed_instance
        end
        local instance = Class()
        assert(instance == fixed_instance)
        local instance2 = SubClass()
        assert(instance2 == fixed_instance2)
    end,
}

function module.classTests(verbose)
    local fail = 0
    local sorted = {}
    local tinsert = table.insert
    for name, test in pairs(tests) do
        local entry = {name, test}
        tinsert(sorted, entry)
    end
    if debug then
        for _, entry in ipairs(sorted) do
            tinsert(entry, debug.getinfo(entry[2], "S").linedefined)
        end
        table.sort(sorted, function(a,b) return a[3] < b[3] end)
    end
    for _, entry in ipairs(sorted) do
        local name, test = unpack(entry)
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
