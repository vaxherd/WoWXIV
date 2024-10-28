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

    MyClass = class()
    function MyClass:__constructor(arg)
        self.value = arg
    end

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

Any metatable set on the returned instance will be preserved, except
that the __index field will be set appropriately for class member lookup
as is done by the default allocator.  If no metatable is set, a new one
will be created.

If the allocator sets an instance metatable which includes an __index
field, the value of that field will replace the normal __index which
redirects to the class definition.  This will prevent ordinary use of
the table as a class instance unless special care is taken, and should
normally not be done.

__super() is not supported in allocators; an overriding allocator wishing
to call its base class's implementation must explicitly name the base
class:

    MyClass = class()
    function MyClass.__allocator(class, ...)
        local instance = {}
        -- ...
        return instance
    end
    MySubClass = class(MyClass)
    function MySubClass.__allocator(class, ...)
        local instance = MyClass:__allocator(...)
        -- ...
        return instance
    end

]]

------------------------------------------------------------------------
-- Implementation
------------------------------------------------------------------------

local _, module = ...
module = module or {} -- so the file can also be loaded with a simple require()

-- Error messages are defined as constants for testing convenience.
local parent_type_error_msg = "Parent class must be a table"
local super_error_msg = "__super() called from class with no superclass"
local constr_type_error_msg = "__constructor must be a function"
local alloc_result_error_msg = "__allocator() must return a table"

local function call_super(...)
    local super = getmetatable(getfenv(2)).parent
    if super then
        super.__constructor(...)
    else
        error(super_error_msg)
    end
end

function module.class(parent)
    if parent and type(parent) ~= "table" then
        error(parent_type_error_msg)
    end
    local classdef = {__super = call_super}
    local instance_metatable = {__index = classdef}
    local class_metatable = {}
    class_metatable.__call = function(thisclass, ...)
        local instance
        if thisclass.__allocator then
            instance = thisclass.__allocator(thisclass, ...)
            assert(type(instance) == "table", alloc_result_error_msg)
            local metatable = getmetatable(instance) or {}
            -- Avoid directly referencing classdef for consistency.
            metatable.__index = metatable.__index or instance_metatable.__index
            setmetatable(instance, metatable)
        else
            instance = setmetatable({}, instance_metatable)
        end
        instance:__constructor(...)
        return instance
    end
    -- Hide the constructor so we can attach the parent class to its
    -- definition when (if) it is later declared.
    class_metatable.__newindex = function(t, k, v)
        if k == "__constructor" then
            assert(t == classdef)
            if type(v) ~= "function" then
                error(constr_type_error_msg)
            end
            -- We need to attach the parent class to the function
            -- definition itself, since each constructor in an inheritance
            -- chain needs to know its own parent and we can only store a
            -- single parent in the instance table.  Rather than storing
            -- the parent in a function-local variable which could
            -- potentially interfere with the constructor code itself, we
            -- put it in a metatable entry which is much less likely to
            -- cause a conflict.
            setfenv(v, setmetatable({}, {__index=getfenv(v), parent=parent}))
            class_metatable.constructor = v
        else
            rawset(t, k, v)
        end
    end
    class_metatable.__index = function(t, k)
        if k == "__constructor" then
            return class_metatable.constructor
        else
            return parent and parent[k]
        end
    end
    setmetatable(classdef, class_metatable)
    -- Define a default constructor so the "new" operation doesn't need to
    -- check for its presence.
    if parent then
        classdef.__constructor = function(self,...) self:__super(...) end
    else
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

    Constructor = function()
        local Class = class()
        function Class:__constructor()
            self.x = 70
        end
        local instance = Class()
        assert(instance.x == 70)
    end,

    InvalidConstructorType = function()
        local Class = class()
        local function f()
            Class.__constructor = "foo"
        end
        local result, errmsg = pcall(f)
        assert(result == false)
        assert(errmsg:find(constr_type_error_msg, 1, true))
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
        assert(errmsg:find(alloc_result_error_msg, 1, true))
    end,

    InvalidParentType = function()
        local function f() return class("foo") end
        local result, errmsg = pcall(f)
        assert(result == false)
        assert(errmsg:find(parent_type_error_msg, 1, true))
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

    InheritAllocator = function()
        local Class = class()
        local fixed_instance = {}
        function Class:__allocator()
            return fixed_instance
        end
        local SubClass = class(Class)
        local instance = SubClass()
        assert(instance == fixed_instance)
    end,

    OverrideAllocator = function()
        local Class = class()
        local fixed_instance = {}
        function Class:__allocator()
            return fixed_instance
        end
        local SubClass = class(Class)
        local fixed_instance2 = {}
        function SubClass:__allocator()
            return fixed_instance2
        end
        local instance = SubClass()
        assert(instance == fixed_instance2)
        local instance2 = Class()
        assert(instance2 == fixed_instance)
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

    NestedSuperCall = function()
        local Class = class()
        function Class:__constructor()
            self.x = 240
        end
        local SubClass = class(Class)
        function SubClass:__constructor()
            self:__super()
            self.y = 241
        end
        local SubSubClass = class(SubClass)
        function SubSubClass:__constructor()
            self:__super()
            self.z = 242
        end
        local instance = SubSubClass()
        assert(instance.x == 240)
        assert(instance.y == 241)
        assert(instance.z == 242)
        local instance2 = SubClass()
        assert(instance2.x == 240)
        assert(instance2.y == 241)
        assert(instance2.z == nil)
        local instance3 = Class()
        assert(instance3.x == 240)
        assert(instance3.y == nil)
        assert(instance3.z == nil)
    end,

    NestedInheritAllocator = function()
        local Class = class()
        local fixed_instance = {}
        function Class:__allocator()
            return fixed_instance
        end
        local SubClass = class(Class)
        local SubSubClass = class(SubClass)
        local instance = SubSubClass()
        assert(instance == fixed_instance)
    end,

    NestedOverrideAllocator = function()
        local Class = class()
        local fixed_instance = {}
        function Class:__allocator()
            return fixed_instance
        end
        local SubClass = class(Class)
        local SubSubClass = class(Class)
        local fixed_instance2 = {}
        function SubSubClass:__allocator()
            return fixed_instance2
        end
        local instance = SubSubClass()
        assert(instance == fixed_instance2)
        local instance2 = SubClass()
        assert(instance2 == fixed_instance)
        local instance3 = Class()
        assert(instance3 == fixed_instance)
    end,

    DeclareSuperMemberAfterSubclass = function()
        local Class = class()
        local SubClass = class(Class)
        Class.x = 250
        local instance = SubClass()
        assert(instance.x == 250)
    end,

    DeclareSuperMemberAfterSubclassInstantiation = function()
        local Class = class()
        local SubClass = class(Class)
        local instance = SubClass()
        Class.x = 260
        assert(instance.x == 260)
    end,

    DeclareSuperConstructorAfterSubclass = function()
        local Class = class()
        local SubClass = class(Class)
        function Class:__constructor()
            self.x = 270
        end
        local instance = SubClass()
        assert(instance.x == 270)
    end,

    DeclareSuperConstructorAfterSubclassConstructor = function()
        local Class = class()
        local SubClass = class(Class)
        function SubClass:__constructor()
            self:__super()
            self.y = 281
        end
        function Class:__constructor()
            self.x = 280
        end
        local instance = SubClass()
        assert(instance.x == 280)
        assert(instance.y == 281)
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
