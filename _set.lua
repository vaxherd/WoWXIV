--[[

Implementation of a set type in Lua.

This file declares the symbol "set" in the module table provided as the
second argument when loading the file (as is done by the WoW API).  If
no second argument is provided, one is created locally and returned from
the module, for use with Lua require().  Module sources using this
syntax are assumed to import the "set" identifier locally with
"local set = module.set" or similar.

This implementation makes use of the related "list" type, which should
be either pre-imported into the module table or available via
require("_list").


A set is an unordered collection of values; in Lua terms, it is similar
to a table with only keys and no values.  Sets are useful in algorithms
for which the presence or absence of a value is itself meaningful.

Sets may contain any type of value other than nil, and may even contain
values of differing types.  Attempting to add nil to a set will raise an
error; other element operations passed a value of nil will behave as
usual when given a value not in the set (for example, has(nil) will
return false without raising an error).

The interface defined here draws largely from Python.  Notable
differences from Python syntax and usage are documented below.


A set instance can be created by calling the set() function:

    s = set()  -- Creates an empty set.

Optionally, the set can be prepopulated with values:

    s = set(2, 3, 5, 7)  -- Creates a set with four elements.

Note that unlike Python, initial set elements are specified directly as
arguments to set(), not in an iterable.


Set instances support the usual operations on elements:

    s:add(x)  -- Add x to s if not already present
    s:has(x)  -- True if x is an element of s (Python "x in s")
    s:len()  -- Length of (number of elements in) s
    s:remove(x)  -- Remove x from s; error if not present
    s:discard(x)  -- Remove x from s if present (else do nothing)
    s:pop()  -- Remove and return an arbitrary element; error if empty
    s:clear()  -- Remove all elements

and other sets:

    s1:union(s2)  -- Set containing all elements in s1 or s2 (or both)
    s1:update(s2)  -- Add all elements in s2 to s1
    s1:difference(s2)  -- Set containing elements in s1 but not s2
    s1:difference_update(s2)  -- Remove all elements in s2 from s1
    s1:intersection(s2)  -- Set containing elements in both s1 and s2
    s1:intersection_update(s2)  -- Remove all elements not in s2 from s1
    s1:symmetric_difference(s2)  -- Set of elements in s1 or s2 but not both
    s1:symmetric_difference_update(s2) --Keep elements in s1 or s2 but not both
    s1:issubset(s2)  -- True if every element in s1 is in s2
    s1:issuperset(s2)  -- True if every element in s2 is in s1
    s1:isequal(s2)  -- True if every element in s1 is in s2 and vice versa
    s1:isdisjoint(s2)  -- True if s1 and s2 have no elements in common

Note that due to Lua limitations, "#s" is _not_ equivalent to "s:len()";
the explicit method call is required.


Most methods which take one argument can also take multiple arguments:

    s:add(x, y, ...)
    s:has(x, y, ...)  -- True if all of x, y, ... are in s
    s:remove(x, y, ...)  -- Error if any of x, y, ... are not in s
    s:discard(x, y, ...)
    s1:union(s2, s3, ...)
    s1:update(s2, s3, ...)
    s1:difference(s2, s3, ...)
    s1:difference_update(s2, s3, ...)
    s1:intersection(s2, s3, ...)
    s1:intersection_update(s2, s3, ...)

or no arguments:

    s:add()  -- No-op
    s:has()  -- No-op, returns true ("all zero arguments are in s")
    s:remove()  -- No-op
    s:discard()  -- No-op
    s1:union()  -- No-op, returns a copy of s1
    s1:update()  -- No-op
    s1:difference()  -- No-op, returns a copy of s1
    s1:difference_update()  -- No-op
    s1:intersection()  -- No-op, returns a copy of s1
    s1:intersection_update()  -- No-op


Sets also support set-to-set operations using standard binary operators:

    s1 + s2  -- s1:union(s2) (Python: "s1 | s2")
    s1 - s2  -- s1:difference(s2)
    s1 * s2  -- s1:intersection(s2) (Python: "s1 & s2")
    s1 ^ s2  -- s1:symmetric_difference(s2)
    s1 <= s2  -- s1:issubset(s2)
    s1 < s2  -- s1:issubset(s2) and not s1:isequal(s2) ("proper subset")

Note that unlike Python, we do not override the == operator, because Lua
doesn't provide any other way to test whether two object references
refer to the same object.


All set methods which do not return an explicit value (specifically:
add, remove, discard, clear, and the three update methods) return the
set instance on which they operated, allowing chaining:

    s1:update(s2):difference_update(s3)  -- s1 = (s1 + s2) - s3


A shallow copy of a set (a new set instance containing the same
elements, but not new copies of the elements themselves) can be created
with the copy() method:

    s2 = s1:copy()
    assert(s2 ~= s1)
    assert(s2:isequal(s1))
    s2.add(element_not_in_s1)
    assert(not s2:isequal(s1))

The same can be accomplished by invoking set operator methods like
union() with no arguments; copy() is provided for semantic clarity.


A set is its own iterator:

    for elem in s do
        print(elem, "is an element of s")
    end

The order of iteration is undefined and may change from one loop to the
next, though each individual loop is guaranteed to see each element of
the set exactly once.  See sorted() below for iterating over elements in
a specified order.

The caveat to Lua next() and pairs() about modifying the table argument
(adding a key to the table causes undefined behavior) applies here as
well: behavior is undefined if an element is added to s inside the loop,
but elements may be safely removed without affecting iteration.  (If an
element which has not yet been visited during a loop is removed, it will
not be seen by that loop.)

Note that because this iteration is implemented in Lua, it executes
somewhat more slowly than the native pairs().  This set type is designed
to prefer convenience and code conciseness over performance; where
performance is critical, a native Lua table with set values as table
keys and arbitrary constants as table values may be a better choice.


The elements in the set can be returned as an unsorted array:

    local array = s:elements()
    for i, elem in ipairs(array) do ... end

or sorted:

    local array = s:sorted()
    for i = 2, #array do assert(array[i] >= array[i-1]) end

and the sort can use an arbitrary comparator function like table.sort():

    local function Compare(a, b) return a.value < b.value end
    local sorted_elements = s:sorted(Compare)

The arrays returned by elements() and sorted() are _iterable arrays_,
in that they can be used directly in a "for ... in" construct (in fact,
they are instances of the list type; see the list() documentation for
details).  Thus, the following four statements are equivalent:

    for x in s do ... end
    for x in s:elements() do ... end
    local array = s:elements(); for x in array do ... end
    for _, x in ipairs(s:elements()) do ... end

except that the latter three create an extra copy of the element list.
Similarly, the construct:

    for x in s:sorted() do ... end

will iterate over all elements of s in ascending order.

As for set iteration, this array iteration is somewhat slower than
ipairs(), and ipairs() should be preferred if performance is important;
the iteration operator is provided for convenience.


When using object (table or userdata) references as set elements, the
reference itself is taken as the element, not the content of the
referenced object.  Consider this code:

    local a = {1, 2, 3}   -- Create two distinct table objects.
    local b = {1, 2, 3}
    s:add(a)              -- |s| is assumed to be a set instance.
    assert(not s:has(b))  -- The table referenced by |b| is not in the set.

Even though both tables have exactly the same set of elements, the table
referenced by variable |b| is considered not an element of set |s|
because it is a distinct table object from table |a| which was added to
the set.  Conversely, strings in Lua are pure values, not objects, and
thus all instances of the same string data are treated as equal:

    local a = "1 2 3"
    local b = "1 2 3"
    s:add(a)
    assert(s:has(b))

]]--

------------------------------------------------------------------------
-- Implementation
------------------------------------------------------------------------

local _, module = ...
module = module or {} -- so the file can also be loaded with a simple require()

-- Import the list type if needed.
local list = module.list or require("_list").list or error("list() not found")

-- Localize some commonly called functions to reduce lookup cost.
local getmetatable = getmetatable
local setmetatable = setmetatable
local strsub = string.sub
local tostring = tostring

-- Error messages are defined as constants for testing convenience.
local ADD_NIL_MSG = "Cannot add nil to a set"
local NO_ELEMENT_MSG = "Element not found in set"
local EMPTY_SET_MSG = "Set is empty"
local BAD_NEWINDEX_MSG = "Use add() to add elements to a set"

local set_metatable  -- Declared below.


function module.set(...)
    local s = {__elements = {}, __len = 0}
    -- Lua doesn't let us strformat("%p") to get the address of a table,
    -- so we rely on the default "table: %p" format to create a slightly
    -- more informative value for tostring().
    local str = tostring(s)
    assert(strsub(str, 1, 5) == "table")
    s.__tostring = "set" .. strsub(str, 6)
    return setmetatable(s, set_metatable):add(...)
end

local set = module.set


local set_methods = {
    add = function(s, ...)
        local elements = s.__elements
        local len = s.__len
        for i = 1, select("#", ...) do
            local x = select(i, ...)
            if x == nil then
                error(ADD_NIL_MSG, 2)
            end
            if not elements[x] then
                elements[x] = true
                len = len+1
            end
        end
        s.__len = len
        return s
    end,

    has = function(s, ...)
        local elements = s.__elements
        for i = 1, select("#", ...) do
            local x = select(i, ...)
            if x == nil or not elements[x] then
                return false
            end
        end
        return true
    end,

    len = function(s) return s.__len end,

    remove = function(s, ...)
        local elements = s.__elements
        local len = s.__len
        for i = 1, select("#", ...) do
            local x = select(i, ...)
            if x == nil or not elements[x] then
                error(NO_ELEMENT_MSG, 2)
            end
            elements[x] = nil
            len = len-1
        end
        s.__len = len
        return s
    end,

    discard = function(s, ...)
        local elements = s.__elements
        local len = s.__len
        for i = 1, select("#", ...) do
            local x = select(i, ...)
            if x ~= nil and elements[x] then
                elements[x] = nil
                len = len-1
            end
        end
        s.__len = len
        return s
    end,

    pop = function(s)
        local elements = s.__elements
        local len = s.__len
        local x = next(elements)
        if x == nil then
            error(EMPTY_SET_MSG, 2)
        end
        elements[x] = nil
        s.__len = len-1
        return x
    end,

    clear = function(s)
        s.__elements = {}
        s.__len = 0
        return s
    end,

    union = function(...) return set():update(...) end,

    update = function(s1, ...)
        local elements = s1.__elements
        local len = s1.__len
        for i = 1, select("#", ...) do
            local s2 = select(i, ...)
            for x in s2 do
                if not elements[x] then
                    elements[x] = true
                    len = len+1
                end
            end
        end
        s1.__len = len
        return s1
    end,

    difference = function(s1, ...) return s1:copy():difference_update(...) end,

    difference_update = function(s1, ...)
        local elements = s1.__elements
        local len = s1.__len
        for i = 1, select("#", ...) do
            local s2 = select(i, ...)
            for x in s2 do
                if elements[x] then
                    elements[x] = nil
                    len = len-1
                end
            end
        end
        s1.__len = len
        return s1
    end,

    intersection = function(s1, ...)
        return s1:copy():intersection_update(...)
    end,

    intersection_update = function(s1, ...)
        local elements = s1.__elements
        local len = s1.__len
        for i = 1, select("#", ...) do
            local s2 = select(i, ...)
            local elements2 = s2.__elements
            for x in pairs(elements) do
                if not elements2[x] then
                    elements[x] = nil
                    len = len-1
                end
            end
        end
        s1.__len = len
        return s1
    end,

    symmetric_difference = function(s1, s2)
        return s1:copy():symmetric_difference_update(s2)
    end,

    symmetric_difference_update = function(s1, s2)
        local elements = s1.__elements
        local len = s1.__len
        for x in s2 do
            if elements[x] then
                elements[x] = nil
                len = len-1
            else
                elements[x] = true
                len = len+1
            end
        end
        s1.__len = len
        return s1
    end,

    issubset = function(s1, s2)
        local elements2 = s2.__elements
        for x in s1 do
            if not elements2[x] then return false end
        end
        return true
    end,

    issuperset = function(s1, s2)
        return s2:issubset(s1)
    end,

    isequal = function(s1, s2)
        return s1:issubset(s2) and s1:issuperset(s2)
    end,

    isdisjoint = function(s1, s2)
        local elements2 = s2.__elements
        for x in s1 do
            if elements2[x] then return false end
        end
        return true
    end,

    copy = function(s) return s:union() end,

    elements = function(s)
        local array = list()
        -- Extending the list using an explicit index is slightly faster
        -- than calling table.insert() because the latter is still a
        -- function call (it is not optimized out to a primitive), and
        -- naturally faster than calling list:append().  Similarly for
        -- omitting the iterator and assigning to array[#array+1],
        -- presumably because #array also performs a function call.
        local i = 0
        for x in s do
            i = i+1
            array[i] = x
        end
        return array
    end,

    sorted = function(s, ...)
        local array = s:elements()
        return array:sort(...)
    end,
}

--[[local]] set_metatable = {
    __add = set_methods.union,
    __sub = set_methods.difference,
    __mul = set_methods.intersection,
    __pow = set_methods.symmetric_difference,
    __le = set_methods.issubset,
    __lt = function(s1, s2) return (s1 <= s2) and not (s2 <= s1) end,
    __index = set_methods,
    __newindex = function() error(BAD_NEWINDEX_MSG, 2) end,
    __call = function(s, _, i) local x = next(s.__elements, i) return x end,
    __tostring = function(s) return s.__tostring end,
}

------------------------------------------------------------------------
-- Test routines (can be run with: lua -e 'require("_set").setTests()')
------------------------------------------------------------------------

local tests = {

    -------- add() (and basic has())

    Add = function()
        local s = set()
        assert(s:add(10) == s)
        assert(s:has(10))
    end,

    HasNonExistent = function()
        local s = set()
        s:add(10)
        assert(not s:has(20))
    end,

    HasEmpty = function()
        local s = set()
        assert(not s:has(10))
    end,

    AddSecond = function()
        local s = set()
        s:add(10)
        assert(s:has(10))
        assert(not s:has(20))
        s:add(20)
        assert(s:has(10))
        assert(s:has(20))
    end,

    AddSame = function()
        local s = set()
        s:add(10)
        assert(s:has(10))
        s:add(10)  -- Should do nothing.  We test length behavior later.
        assert(s:has(10))
    end,

    AddMultiple = function()
        local s = set()
        s:add(10, 20, 30)
        assert(s:has(10))
        assert(s:has(20))
        assert(s:has(30))
    end,

    AddMultipleTypes = function()
        local s = set()
        local tval = {30}
        local fval = function() return 40 end
        s:add(10, "twenty", tval, fval)
        assert(s:has(10))
        assert(s:has("twenty"))
        assert(s:has(tval))
        assert(s:has(fval))
        assert(not s:has({30})) -- Distinct table instance should not be in set.
    end,

    AddSameAndOthers = function()
        local s = set()
        s:add(20)
        assert(s:has(20))
        s:add(10, 20, 30)
        assert(s:has(10))
        assert(s:has(20))
        assert(s:has(30))
    end,

    AddByConstructor = function()
        local s = set()
        s:add(10)
        assert(s:has(10))
    end,

    AddMultipleByConstructor = function()
        local s = set()
        s:add(10, 20, 30)
        assert(s:has(10))
        assert(s:has(20))
        assert(s:has(30))
    end,

    AddSameAfterConstructor = function()
        local s = set(10)
        assert(s:has(10))
        s:add(10)
        assert(s:has(10))
    end,

    AddNil = function()
        local s = set()
        local result, errmsg = pcall(function() s:add(nil) end)
        assert(result == false)
        assert(errmsg:find(ADD_NIL_MSG, 1, true), errmsg)
    end,

    NoNewindex = function()
        local s = set()
        local result, errmsg = pcall(function() s[10] = true end)
        assert(result == false)
        assert(errmsg:find(BAD_NEWINDEX_MSG, 1, true), errmsg)
        assert(not s:has(10))
    end,

    NoNewindexExisting = function()
        local s = set()
        s:add(10)
        local result, errmsg = pcall(function() s[10] = false end)
        assert(result == false)
        assert(errmsg:find(BAD_NEWINDEX_MSG, 1, true), errmsg)
        assert(s:has(10))  -- Should not affect the existing element.
    end,

    -------- has()

    HasNone = function()
        local s = set()
        assert(s:has())  -- True: the set has all zero of the specified values.
    end,

    HasMultiple = function()
        local s = set()
        s:add(10, 20, 30)
        assert(s:has(10, 20, 30))
    end,

    HasMultipleMissing = function()
        local s = set()
        s:add(10, 20, 30)
        assert(not s:has(10, 40, 30))
    end,

    HasString = function()
        local s = set()
        local a = "abc"
        s:add(a)
        assert(s:has(a))
        local b = "abc"
        assert(s:has(b))  -- Because strings are not instanced.
    end,

    HasTable = function()
        local s = set()
        local t = {1, 2, 3}
        s:add(t)
        assert(s:has(t))
    end,

    HasIdenticalTable = function()
        local s = set()
        local t1 = {1, 2, 3}
        local t2 = {1, 2, 3}
        assert(t1 ~= t2)
        s:add(t1)
        assert(not s:has(t2)) -- Should be treated as a separate element.
    end,

    HasNil = function()
        local s = set(10)
        assert(not s:has(nil))  -- False: nil can never be a member of a set.
    end,

    HasMultipleNil = function()
        local s = set()
        s:add(10, 20, 30)
        assert(not s:has(10, nil, 30))
    end,

    -------- len()

    LenEmpty = function()
        local s = set()
        assert(s:len() == 0)
    end,

    LenSingle = function()
        local s = set(10)
        assert(s:len() == 1)
    end,

    LenAddSingle = function()
        local s = set()
        s:add(10)
        assert(s:len() == 1)
    end,

    LenMultiple = function()
        local s = set(10, 20, 30)
        assert(s:len() == 3)
    end,

    LenAddMultiple = function()
        local s = set(10)
        s:add(20, 30)
        assert(s:len() == 3)
    end,

    LenAddExisting = function()
        local s = set()
        s:add(10)
        s:add(10)
        assert(s:len() == 1)
    end,

    LenAddExistingAfterConstructor = function()
        local s = set(10)
        s:add(10)
        assert(s:len() == 1)
    end,

    LenAddExistingString = function()
        local s = set()
        s:add("abc")
        assert(s:len() == 1)
        s:add("abc")  -- Should do nothing (strings are not instanced).
        assert(s:len() == 1)
    end,

    LenAddExistingTable = function()
        local s = set()
        local t = {1, 2, 3}
        s:add(t)
        assert(s:len() == 1)
        s:add(t)  -- Should do nothing (this is the same table instance).
        assert(s:len() == 1)
    end,

    LenAddIdenticalTable = function()
        local s = set()
        local t1 = {1, 2, 3}
        local t2 = {1, 2, 3}
        assert(t1 ~= t2)
        s:add(t1)
        assert(s:len() == 1)
        s:add(t2)  -- Should be treated as a separate element.
        assert(s:len() == 2)
    end,

    -------- remove()

    Remove = function()
        local s = set(10)
        assert(s:remove(10) == s)
        assert(not s:has(10))
        assert(s:len() == 0)
    end,

    RemoveNone = function()
        local s = set(10)
        assert(s:remove() == s)
        assert(s:has(10))
        assert(s:len() == 1)
    end,

    RemoveMultiple = function()
        local s = set(10, 20, 30, 40, 50)
        assert(s:remove(10, 30, 40) == s)
        assert(not s:has(10))
        assert(s:has(20))
        assert(not s:has(30))
        assert(not s:has(40))
        assert(s:has(50))
        assert(s:len() == 2)
    end,

    RemoveNotFound = function()
        local s = set(10)
        local result, errmsg = pcall(function() s:remove(20) end)
        assert(result == false)
        assert(errmsg:find(NO_ELEMENT_MSG, 1, true), errmsg)
        assert(s:has(10))
        assert(not s:has(20))
        assert(s:len() == 1)
    end,

    RemoveEmpty = function()
        local s = set()
        local result, errmsg = pcall(function() s:remove(10) end)
        assert(result == false)
        assert(errmsg:find(NO_ELEMENT_MSG, 1, true), errmsg)
        assert(not s:has(10))
        assert(s:len() == 0)
    end,

    RemoveNil = function()
        local s = set(10)
        local result, errmsg = pcall(function() s:remove(nil) end)
        assert(result == false)
        assert(errmsg:find(NO_ELEMENT_MSG, 1, true), errmsg)
        assert(s:has(10))
        assert(s:len() == 1)
    end,

    RemoveMultipleNil = function()
        local s = set(10, 20, 30)
        local result, errmsg = pcall(function() s:remove(10, nil, 30) end)
        assert(result == false)
        assert(errmsg:find(NO_ELEMENT_MSG, 1, true), errmsg)
        assert(s:has(20))
        assert(s:len() >= 1)
    end,

    -------- discard()

    Discard = function()
        local s = set(10)
        assert(s:discard(10) == s)
        assert(not s:has(10))
        assert(s:len() == 0)
    end,

    DiscardNone = function()
        local s = set(10)
        assert(s:discard() == s)
        assert(s:has(10))
        assert(s:len() == 1)
    end,

    DiscardMultiple = function()
        local s = set(10, 20, 30, 40, 50)
        assert(s:discard(10, 30, 40) == s)
        assert(not s:has(10))
        assert(s:has(20))
        assert(not s:has(30))
        assert(not s:has(40))
        assert(s:has(50))
        assert(s:len() == 2)
    end,

    DiscardAll = function()
        local s = set(10, 20, 30)
        assert(s:discard(10, 20, 30) == s)
        assert(not s:has(10))
        assert(not s:has(20))
        assert(not s:has(30))
        assert(s:len() == 0)
    end,

    DiscardNotFound = function()
        local s = set(10)
        assert(s:discard(20) == s)  -- Call should not error.
        assert(s:has(10))
        assert(not s:has(20))
        assert(s:len() == 1)
    end,

    DiscardEmpty = function()
        local s = set()
        assert(s:discard(10) == s)  -- Call should not error.
        assert(not s:has(10))
        assert(s:len() == 0)
    end,

    DiscardNil = function()
        local s = set(10)
        assert(s:discard(nil) == s)  -- Call should not error.
        assert(s:has(10))
        assert(s:len() == 1)
    end,

    DiscardMultipleNil = function()
        local s = set(10, 20, 30, 40, 50)
        assert(s:discard(10, nil, 40) == s)  -- Call should not error.
        assert(not s:has(10))
        assert(s:has(20))
        assert(s:has(30))
        assert(not s:has(40))
        assert(s:has(50))
        assert(s:len() == 3)
    end,

    -------- pop()

    Pop = function()
        local s = set(10)
        local x = s:pop()
        assert(x == 10)
        assert(not s:has(10))
        assert(s:len() == 0)
    end,

    PopFromMultiple = function()
        local s = set(10, 20, 30)
        local x = s:pop()
        if x == 10 then
            assert(not s:has(10))
            assert(s:has(20))
            assert(s:has(30))
        elseif x == 20 then
            assert(s:has(10))
            assert(not s:has(20))
            assert(s:has(30))
        else
            assert(x == 30)
            assert(s:has(10))
            assert(s:has(20))
            assert(not s:has(30))
        end
        assert(s:len() == 2)
    end,

    PopMultiple = function()
        local s = set(1, 2, 4)
        local x, y, z = s:pop(), s:pop(), s:pop()
        assert(x + y + z == 7)
        assert(s:len() == 0)
    end,

    PopEmpty = function()
        local s = set()
        local result, errmsg = pcall(function() s:pop() end)
        assert(result == false)
        assert(errmsg:find(EMPTY_SET_MSG, 1, true), errmsg)
        assert(s:len() == 0)
    end,

    -------- clear()

    Clear = function()
        local s = set(10)
        assert(s:clear() == s)
        assert(not s:has(10))
        assert(s:len() == 0)
    end,

    ClearMultiple = function()
        local s = set(10, 20, 30)
        assert(s:clear() == s)
        assert(not s:has(10))
        assert(not s:has(20))
        assert(not s:has(30))
        assert(s:len() == 0)
    end,

    ClearEmpty = function()
        local s = set()
        assert(s:clear() == s) -- No-op.
        assert(not s:has(10))
        assert(s:len() == 0)
    end,

    -------- union() and + operator

    Union = function()
        local s1 = set(10)
        local s2 = set(20)
        local s3 = s1:union(s2)
        assert(s3 ~= s1)
        assert(s3 ~= s2)
        assert(s3:has(10))
        assert(s3:has(20))
        assert(s3:len() == 2)
        -- s1 and s2 should be unmodified.
        assert(s1:has(10))
        assert(not s1:has(20))
        assert(s1:len() == 1)
        assert(not s2:has(10))
        assert(s2:has(20))
        assert(s2:len() == 1)
    end,

    UnionFirstEmpty = function()
        local s1 = set()
        local s2 = set(20)
        local s3 = s1:union(s2)
        assert(s3 ~= s1)
        assert(s3 ~= s2)
        assert(s3:has(20))
        assert(s3:len() == 1)
        assert(not s1:has(20))
        assert(s1:len() == 0)
        assert(s2:has(20))
        assert(s2:len() == 1)
    end,

    UnionSecondEmpty = function()
        local s1 = set(10)
        local s2 = set()
        local s3 = s1:union(s2)
        assert(s3 ~= s1)
        assert(s3 ~= s2)
        assert(s3:has(10))
        assert(s3:len() == 1)
        assert(s1:has(10))
        assert(s1:len() == 1)
        assert(not s2:has(10))
        assert(s2:len() == 0)
    end,

    UnionMultipleElements = function()
        local s = set(10, 30):union(set(20, 40, 60))
        assert(s:has(10))
        assert(s:has(20))
        assert(s:has(30))
        assert(s:has(40))
        assert(s:has(60))
        assert(s:len() == 5)
    end,

    UnionMultipleElementsOverlap = function()
        local s = set(10, 30):union(set(20, 30, 40))
        assert(s:has(10))
        assert(s:has(20))
        assert(s:has(30))
        assert(s:has(40))
        assert(s:len() == 4)
    end,

    UnionMultipleSets = function()
        local s = set(10, 30):union(set(20), set(30), set(40))
        assert(s:has(10))
        assert(s:has(20))
        assert(s:has(30))
        assert(s:has(40))
        assert(s:len() == 4)
    end,

    UnionNone = function()
        local s = set(10, 30):union()
        assert(s:has(10))
        assert(s:has(30))
        assert(s:len() == 2)
    end,

    OperatorUnion = function()
        local s = set(10, 30) + set(20, 30, 40)
        assert(s:has(10))
        assert(s:has(20))
        assert(s:has(30))
        assert(s:has(40))
        assert(s:len() == 4)
    end,

    -------- update()

    Update = function()
        local s1 = set(10)
        local s2 = set(20)
        assert(s1:update(s2) == s1)
        assert(s1:has(10))
        assert(s1:has(20))
        assert(s1:len() == 2)
        -- s2 should be unmodified.
        assert(not s2:has(10))
        assert(s2:has(20))
        assert(s2:len() == 1)
    end,

    UpdateFirstEmpty = function()
        local s1 = set()
        local s2 = set(20)
        assert(s1:update(s2) == s1)
        assert(s1:has(20))
        assert(s1:len() == 1)
        assert(s2:has(20))
        assert(s2:len() == 1)
    end,

    UpdateSecondEmpty = function()
        local s1 = set(10)
        local s2 = set()
        assert(s1:update(s2) == s1)
        assert(s1:has(10))
        assert(s1:len() == 1)
        assert(not s2:has(10))
        assert(s2:len() == 0)
    end,

    UpdateMultipleElements = function()
        local s = set(10, 30):update(set(20, 40, 60))
        assert(s:has(10))
        assert(s:has(20))
        assert(s:has(30))
        assert(s:has(40))
        assert(s:has(60))
        assert(s:len() == 5)
    end,

    UpdateMultipleElementsOverlap = function()
        local s = set(10, 30):update(set(20, 30, 40))
        assert(s:has(10))
        assert(s:has(20))
        assert(s:has(30))
        assert(s:has(40))
        assert(s:len() == 4)
    end,

    UpdateMultipleSets = function()
        local s = set(10, 30):update(set(20), set(30), set(40))
        assert(s:has(10))
        assert(s:has(20))
        assert(s:has(30))
        assert(s:has(40))
        assert(s:len() == 4)
    end,

    UpdateSelf = function()
        local s = set(10, 30)
        assert(s:update(s) == s)
        assert(s:has(10))
        assert(s:has(30))
        assert(s:len() == 2)
    end,

    UpdateSelfMultiple = function()
        local s = set(10, 30)
        assert(s:update(set(20), s, set(40)) == s)
        assert(s:has(10))
        assert(s:has(20))
        assert(s:has(30))
        assert(s:has(40))
        assert(s:len() == 4)
    end,

    UpdateNone = function()
        local s = set(10, 30):update()
        assert(s:has(10))
        assert(s:has(30))
        assert(s:len() == 2)
    end,

    -------- difference() and - operator

    Difference = function()
        local s1 = set(10, 20, 30)
        local s2 = set(20)
        local s3 = s1:difference(s2)
        assert(s3 ~= s1)
        assert(s3 ~= s2)
        assert(s3:has(10))
        assert(not s3:has(20))
        assert(s3:has(30))
        assert(s3:len() == 2)
        -- s1 and s2 should be unmodified.
        assert(s1:has(10))
        assert(s1:has(20))
        assert(s1:has(30))
        assert(s1:len() == 3)
        assert(not s2:has(10))
        assert(s2:has(20))
        assert(not s2:has(30))
        assert(s2:len() == 1)
    end,

    DifferenceFirstEmpty = function()
        local s1 = set()
        local s2 = set(20)
        local s3 = s1:difference(s2)
        assert(s3 ~= s1)
        assert(s3 ~= s2)
        assert(not s3:has(20))
        assert(s3:len() == 0)
        assert(not s1:has(20))
        assert(s1:len() == 0)
        assert(s2:has(20))
        assert(s2:len() == 1)
    end,

    DifferenceSecondEmpty = function()
        local s1 = set(10)
        local s2 = set()
        local s3 = s1:difference(s2)
        assert(s3 ~= s1)
        assert(s3 ~= s2)
        assert(s3:has(10))
        assert(s3:len() == 1)
        assert(s1:has(10))
        assert(s1:len() == 1)
        assert(not s2:has(10))
        assert(s2:len() == 0)
    end,

    DifferenceElementNotInFirst = function()
        local s = set(10, 20, 30):difference(set(40))
        assert(s:has(10))
        assert(s:has(20))
        assert(s:has(30))
        assert(s:len() == 3)
    end,

    DifferenceMultipleElements = function()
        local s = set(10, 20, 30, 40, 50):difference(set(20, 40, 60))
        assert(s:has(10))
        assert(not s:has(20))
        assert(s:has(30))
        assert(not s:has(40))
        assert(s:has(50))
        assert(not s:has(60))
        assert(s:len() == 3)
    end,

    DifferenceMultipleSets = function()
        local s = set(10, 20, 30, 40, 50):difference(set(20), set(40), set(60))
        assert(s:has(10))
        assert(not s:has(20))
        assert(s:has(30))
        assert(not s:has(40))
        assert(s:has(50))
        assert(not s:has(60))
        assert(s:len() == 3)
    end,

    DifferenceNone = function()
        local s = set(10, 30):difference()
        assert(s:has(10))
        assert(s:has(30))
        assert(s:len() == 2)
    end,

    OperatorDifference = function()
        local s = set(10, 20, 30, 40, 50) - set(20, 40, 60)
        assert(s:has(10))
        assert(not s:has(20))
        assert(s:has(30))
        assert(not s:has(40))
        assert(s:has(50))
        assert(not s:has(60))
        assert(s:len() == 3)
    end,

    -------- difference_update()

    DifferenceUpdate = function()
        local s1 = set(10, 20, 30)
        local s2 = set(20)
        assert(s1:difference_update(s2) == s1)
        assert(s1:has(10))
        assert(not s1:has(20))
        assert(s1:has(30))
        assert(s1:len() == 2)
        -- s2 should be unmodified.
        assert(not s2:has(10))
        assert(s2:has(20))
        assert(not s2:has(30))
        assert(s2:len() == 1)
    end,

    DifferenceUpdateFirstEmpty = function()
        local s1 = set()
        local s2 = set(20)
        assert(s1:difference_update(s2) == s1)
        assert(not s1:has(20))
        assert(s1:len() == 0)
        assert(s2:has(20))
        assert(s2:len() == 1)
    end,

    DifferenceUpdateSecondEmpty = function()
        local s1 = set(10)
        local s2 = set()
        assert(s1:difference_update(s2) == s1)
        assert(s1:has(10))
        assert(s1:len() == 1)
        assert(not s2:has(10))
        assert(s2:len() == 0)
    end,

    DifferenceUpdateElementNotInFirst = function()
        local s = set(10, 20, 30):difference_update(set(40))
        assert(s:has(10))
        assert(s:has(20))
        assert(s:has(30))
        assert(s:len() == 3)
    end,

    DifferenceUpdateMultipleElements = function()
        local s = set(10, 20, 30, 40, 50):difference_update(set(20, 40, 60))
        assert(s:has(10))
        assert(not s:has(20))
        assert(s:has(30))
        assert(not s:has(40))
        assert(s:has(50))
        assert(not s:has(60))
        assert(s:len() == 3)
    end,

    DifferenceUpdateMultipleSets = function()
        local s = set(10, 20, 30, 40, 50)
            :difference_update(set(20), set(40), set(60))
        assert(s:has(10))
        assert(not s:has(20))
        assert(s:has(30))
        assert(not s:has(40))
        assert(s:has(50))
        assert(not s:has(60))
        assert(s:len() == 3)
    end,

    DifferenceUpdateSelf = function()
        local s = set(10, 20, 30, 40, 50)
        assert(s:difference_update(s) == s)
        assert(not s:has(10))
        assert(not s:has(20))
        assert(not s:has(30))
        assert(not s:has(40))
        assert(not s:has(50))
        assert(s:len() == 0)
    end,

    DifferenceUpdateSelfMultiple = function()
        local s = set(10, 20, 30, 40, 50)
        assert(s:difference_update(set(20), s, set(40)) == s)
        assert(not s:has(10))
        assert(not s:has(20))
        assert(not s:has(30))
        assert(not s:has(40))
        assert(not s:has(50))
        assert(s:len() == 0)
    end,

    DifferenceUpdateNone = function()
        local s = set(10, 30):difference_update()
        assert(s:has(10))
        assert(s:has(30))
        assert(s:len() == 2)
    end,

    -------- intersection() and * operator

    Intersection = function()
        local s1 = set(10, 20, 30)
        local s2 = set(20)
        local s3 = s1:intersection(s2)
        assert(s3 ~= s1)
        assert(s3 ~= s2)
        assert(not s3:has(10))
        assert(s3:has(20))
        assert(not s3:has(30))
        assert(s3:len() == 1)
        -- s1 and s2 should be unmodified.
        assert(s1:has(10))
        assert(s1:has(20))
        assert(s1:has(30))
        assert(s1:len() == 3)
        assert(not s2:has(10))
        assert(s2:has(20))
        assert(not s2:has(30))
        assert(s2:len() == 1)
    end,

    IntersectionFirstEmpty = function()
        local s1 = set()
        local s2 = set(20)
        local s3 = s1:intersection(s2)
        assert(s3 ~= s1)
        assert(s3 ~= s2)
        assert(not s3:has(20))
        assert(s3:len() == 0)
        assert(not s1:has(20))
        assert(s1:len() == 0)
        assert(s2:has(20))
        assert(s2:len() == 1)
    end,

    IntersectionSecondEmpty = function()
        local s1 = set(10)
        local s2 = set()
        local s3 = s1:intersection(s2)
        assert(s3 ~= s1)
        assert(s3 ~= s2)
        assert(not s3:has(10))
        assert(s3:len() == 0)
        assert(s1:has(10))
        assert(s1:len() == 1)
        assert(not s2:has(10))
        assert(s2:len() == 0)
    end,

    IntersectionElementNotInFirst = function()
        local s = set(10, 20, 30):intersection(set(40))
        assert(not s:has(10))
        assert(not s:has(20))
        assert(not s:has(30))
        assert(s:len() == 0)
    end,

    IntersectionMultipleElements = function()
        local s = set(10, 20, 30, 40, 50):intersection(set(20, 40, 60))
        assert(not s:has(10))
        assert(s:has(20))
        assert(not s:has(30))
        assert(s:has(40))
        assert(not s:has(50))
        assert(not s:has(60))
        assert(s:len() == 2)
    end,

    IntersectionMultipleSets = function()
        local s = set(10, 20, 30, 40, 50):intersection(set(20), set(40))
        assert(not s:has(10))
        assert(not s:has(20))
        assert(not s:has(30))
        assert(not s:has(40))
        assert(not s:has(50))
        assert(s:len() == 0)
    end,

    IntersectionNone = function()
        local s = set(10, 30):intersection()
        assert(s:has(10))
        assert(s:has(30))
        assert(s:len() == 2)
    end,

    OperatorIntersection = function()
        local s = set(10, 20, 30, 40, 50) * set(20, 40, 60)
        assert(not s:has(10))
        assert(s:has(20))
        assert(not s:has(30))
        assert(s:has(40))
        assert(not s:has(50))
        assert(not s:has(60))
        assert(s:len() == 2)
    end,

    -------- intersection_update()

    IntersectionUpdate = function()
        local s1 = set(10, 20, 30)
        local s2 = set(20)
        assert(s1:intersection_update(s2) == s1)
        assert(not s1:has(10))
        assert(s1:has(20))
        assert(not s1:has(30))
        assert(s1:len() == 1)
        -- s2 should be unmodified.
        assert(not s2:has(10))
        assert(s2:has(20))
        assert(not s2:has(30))
        assert(s2:len() == 1)
    end,

    IntersectionUpdateFirstEmpty = function()
        local s1 = set()
        local s2 = set(20)
        assert(s1:intersection_update(s2) == s1)
        assert(not s1:has(20))
        assert(s1:len() == 0)
        assert(s2:has(20))
        assert(s2:len() == 1)
    end,

    IntersectionUpdateSecondEmpty = function()
        local s1 = set(10)
        local s2 = set()
        assert(s1:intersection_update(s2) == s1)
        assert(not s1:has(10))
        assert(s1:len() == 0)
        assert(not s2:has(10))
        assert(s2:len() == 0)
    end,

    IntersectionUpdateElementNotInFirst = function()
        local s = set(10, 20, 30):intersection_update(set(40))
        assert(not s:has(10))
        assert(not s:has(20))
        assert(not s:has(30))
        assert(s:len() == 0)
    end,

    IntersectionUpdateMultipleElements = function()
        local s = set(10, 20, 30, 40, 50):intersection_update(set(20, 40, 60))
        assert(not s:has(10))
        assert(s:has(20))
        assert(not s:has(30))
        assert(s:has(40))
        assert(not s:has(50))
        assert(not s:has(60))
        assert(s:len() == 2)
    end,

    IntersectionUpdateMultipleSets = function()
        local s = set(10, 20, 30, 40, 50):intersection_update(set(20), set(40))
        assert(not s:has(10))
        assert(not s:has(20))
        assert(not s:has(30))
        assert(not s:has(40))
        assert(not s:has(50))
        assert(s:len() == 0)
    end,

    IntersectionUpdateSelf = function()
        local s = set(10, 20, 30, 40, 50)
        assert(s:intersection_update(s) == s)
        assert(s:has(10))
        assert(s:has(20))
        assert(s:has(30))
        assert(s:has(40))
        assert(s:has(50))
        assert(s:len() == 5)
    end,

    IntersectionUpdateSelfMultiple = function()
        local s = set(10, 20, 30, 40, 50)
        assert(s:intersection_update(set(20, 40), s, set(40)) == s)
        assert(not s:has(10))
        assert(not s:has(20))
        assert(not s:has(30))
        assert(s:has(40))
        assert(not s:has(50))
        assert(s:len() == 1)
    end,

    IntersectionUpdateNone = function()
        local s = set(10, 30):intersection_update()
        assert(s:has(10))
        assert(s:has(30))
        assert(s:len() == 2)
    end,

    -------- symmetric_difference() and ^ operator

    SymmetricDifference = function()
        local s1 = set(10, 20, 30)
        local s2 = set(20)
        local s3 = s1:symmetric_difference(s2)
        assert(s3 ~= s1)
        assert(s3 ~= s2)
        assert(s3:has(10))
        assert(not s3:has(20))
        assert(s3:has(30))
        assert(s3:len() == 2)
        -- s1 and s2 should be unmodified.
        assert(s1:has(10))
        assert(s1:has(20))
        assert(s1:has(30))
        assert(s1:len() == 3)
        assert(not s2:has(10))
        assert(s2:has(20))
        assert(not s2:has(30))
        assert(s2:len() == 1)
    end,

    SymmetricDifferenceFirstEmpty = function()
        local s1 = set()
        local s2 = set(20)
        local s3 = s1:symmetric_difference(s2)
        assert(s3 ~= s1)
        assert(s3 ~= s2)
        assert(s3:has(20))
        assert(s3:len() == 1)
        assert(not s1:has(20))
        assert(s1:len() == 0)
        assert(s2:has(20))
        assert(s2:len() == 1)
    end,

    SymmetricDifferenceSecondEmpty = function()
        local s1 = set(10)
        local s2 = set()
        local s3 = s1:symmetric_difference(s2)
        assert(s3 ~= s1)
        assert(s3 ~= s2)
        assert(s3:has(10))
        assert(s3:len() == 1)
        assert(s1:has(10))
        assert(s1:len() == 1)
        assert(not s2:has(10))
        assert(s2:len() == 0)
    end,

    SymmetricDifferenceElementNotInFirst = function()
        local s = set(10, 20, 30):symmetric_difference(set(40))
        assert(s:has(10))
        assert(s:has(20))
        assert(s:has(30))
        assert(s:has(40))
        assert(s:len() == 4)
    end,

    SymmetricDifferenceMultipleElements = function()
        local s = set(10, 20, 30, 40, 50):symmetric_difference(set(20, 40, 60))
        assert(s:has(10))
        assert(not s:has(20))
        assert(s:has(30))
        assert(not s:has(40))
        assert(s:has(50))
        assert(s:has(60))
        assert(s:len() == 4)
    end,

    OperatorSymmetricDifference = function()
        local s = set(10, 20, 30, 40, 50) ^ set(20, 40, 60)
        assert(s:has(10))
        assert(not s:has(20))
        assert(s:has(30))
        assert(not s:has(40))
        assert(s:has(50))
        assert(s:has(60))
        assert(s:len() == 4)
    end,

    -------- symmetric_difference_update()

    SymmetricDifferenceUpdate = function()
        local s1 = set(10, 20, 30)
        local s2 = set(20)
        assert(s1:symmetric_difference_update(s2) == s1)
        assert(s1:has(10))
        assert(not s1:has(20))
        assert(s1:has(30))
        assert(s1:len() == 2)
        -- s2 should be unmodified.
        assert(not s2:has(10))
        assert(s2:has(20))
        assert(not s2:has(30))
        assert(s2:len() == 1)
    end,

    SymmetricDifferenceUpdateFirstEmpty = function()
        local s1 = set()
        local s2 = set(20)
        assert(s1:symmetric_difference_update(s2) == s1)
        assert(s1:has(20))
        assert(s1:len() == 1)
        assert(s2:has(20))
        assert(s2:len() == 1)
    end,

    SymmetricDifferenceUpdateSecondEmpty = function()
        local s1 = set(10)
        local s2 = set()
        assert(s1:symmetric_difference_update(s2) == s1)
        assert(s1:has(10))
        assert(s1:len() == 1)
        assert(not s2:has(10))
        assert(s2:len() == 0)
    end,

    SymmetricDifferenceUpdateElementNotInFirst = function()
        local s = set(10, 20, 30):symmetric_difference_update(set(40))
        assert(s:has(10))
        assert(s:has(20))
        assert(s:has(30))
        assert(s:has(40))
        assert(s:len() == 4)
    end,

    SymmetricDifferenceUpdateMultipleElements = function()
        local s = set(10, 20, 30, 40, 50)
            :symmetric_difference_update(set(20, 40, 60))
        assert(s:has(10))
        assert(not s:has(20))
        assert(s:has(30))
        assert(not s:has(40))
        assert(s:has(50))
        assert(s:has(60))
        assert(s:len() == 4)
    end,

    SymmetricDifferenceUpdateSelf = function()
        local s = set(10, 20, 30)
        assert(s:symmetric_difference_update(s) == s)
        assert(not s:has(10))
        assert(not s:has(20))
        assert(not s:has(30))
        assert(s:len() == 0)
    end,

    -------- issubset() and <= operator

    IsSubset = function()
        local s1 = set(10)
        local s2 = set(10, 20)
        assert(s1:issubset(s2))
        -- s1 and s2 should be unmodified.  There's no reason for a
        -- read-only operation like issubset() to modify them, but we
        -- check anyway just for completeness.
        assert(s1:has(10))
        assert(not s1:has(20))
        assert(s1:len() == 1)
        assert(s2:has(10))
        assert(s2:has(20))
        assert(s2:len() == 2)
    end,

    IsSubsetEqualSets = function()
        local s1 = set(10, 20)
        assert(s1:issubset(set(10, 20)))
    end,

    IsSubsetMissingElement = function()
        local s1 = set(10, 20)
        assert(not s1:issubset(set(10, 30)))
    end,

    IsSubsetFirstEmpty = function()
        local s = set()
        assert(s:issubset(set(20)))
    end,

    IsSubsetSecondEmpty = function()
        local s = set(10)
        assert(not s:issubset(set()))
    end,

    IsSubsetBothEmpty = function()
        local s = set()
        assert(s:issubset(set()))
    end,

    OperatorIsSubset = function()
        assert(set(10) <= set(10, 20))
        assert(set(10, 20) <= set(10, 20))
        assert(not (set(10, 20) <= set(20)))
    end,

    -------- issuperset() and >= operator

    IsSuperset = function()
        local s1 = set(10, 20)
        local s2 = set(20)
        assert(s1:issuperset(s2))
        -- s1 and s2 should be unmodified.
        assert(s1:has(10))
        assert(s1:has(20))
        assert(s1:len() == 2)
        assert(not s2:has(10))
        assert(s2:has(20))
        assert(s2:len() == 1)
    end,

    IsSupersetEqualSets = function()
        local s1 = set(10, 20)
        assert(s1:issuperset(set(10, 20)))
    end,

    IsSupersetMissingElement = function()
        local s1 = set(10, 20)
        assert(not s1:issuperset(set(10, 30)))
    end,

    IsSupersetFirstEmpty = function()
        local s = set()
        assert(not s:issuperset(set(20)))
    end,

    IsSupersetSecondEmpty = function()
        local s = set(10)
        assert(s:issuperset(set()))
    end,

    IsSupersetBothEmpty = function()
        local s = set()
        assert(s:issuperset(set()))
    end,

    -- Lua doesn't have a __ge metamethod and implements "a >= b" as
    -- "__le(b, a)", so this test is somewhat redundant, but we include
    -- it for completeness and as a guard against future changes in Lua
    -- behavior.
    OperatorIsSuperset = function()
        assert(not (set(10) >= set(10, 20)))
        assert(set(10, 20) >= set(10, 20))
        assert(set(10, 20) >= set(20))
    end,

    -------- isequal()

    OperatorIsEqual = function()
        local s1 = set(10, 20)
        local s2 = set(10, 20)
        assert(s1:isequal(s2))
        -- s1 and s2 should be unmodified.
        assert(s1:has(10))
        assert(s1:has(20))
        assert(s1:len() == 2)
        assert(s2:has(10))
        assert(s2:has(20))
        assert(s2:len() == 2)
    end,

    OperatorIsEqualMissingInFirst = function()
        assert(not set(10):isequal(set(10, 20)))
    end,

    OperatorIsEqualMissingInSecond = function()
        assert(not set(10, 20):isequal(set(20)))
    end,

    OperatorIsEqualFirstEmpty = function()
        assert(not set():isequal(set(10, 20)))
    end,

    OperatorIsEqualSecondEmpty = function()
        assert(not set(10, 20):isequal(set()))
    end,

    OperatorIsEqualBothEmpty = function()
        assert(set():isequal(set()))
    end,

    -------- < and > operators

    OperatorIsProperSubset = function()
        local s1 = set(10)
        local s2 = set(10, 20)
        assert(s1 < s2)
        -- s1 and s2 should be unmodified.
        assert(s1:has(10))
        assert(not s1:has(20))
        assert(s1:len() == 1)
        assert(s2:has(10))
        assert(s2:has(20))
        assert(s2:len() == 2)
    end,

    OperatorIsProperSubsetEqualSets = function()
        assert(not (set(10, 20) < set(10, 20)))
    end,

    OperatorIsProperSubsetMissingElement = function()
        assert(not (set(10, 30) < set(10, 20)))
    end,

    OperatorIsProperSubsetFirstEmpty = function()
        assert(set() < set(10, 20))
    end,

    OperatorIsProperSubsetSecondEmpty = function()
        assert(not (set(10, 20) < set()))
    end,

    OperatorIsProperSubsetBothEmpty = function()
        assert(not (set() < set()))
    end,

    -- As with the >= test, this is currently redundant but we include it
    -- to guard against future changes in Lua behavior.
    OperatorIsProperSuperset = function()
        assert(not (set(10) > set(10, 20)))
        assert(not (set(10, 20) > set(10, 20)))
        assert(set(10, 20) > set(20))
    end,

    -------- isdisjoint()

    IsDisjoint = function()
        local s1 = set(10)
        local s2 = set(20)
        assert(s1:isdisjoint(s2))
        -- s1 and s2 should be unmodified.
        assert(s1:has(10))
        assert(not s1:has(20))
        assert(s1:len() == 1)
        assert(not s2:has(10))
        assert(s2:has(20))
        assert(s2:len() == 1)
    end,

    IsDisjointProperSubset = function()
        assert(not set(10):isdisjoint(set(10, 20)))
    end,

    IsDisjointProperSuperset = function()
        assert(not set(10, 20):isdisjoint(set(10)))
    end,

    IsDisjointSharedElement = function()
        assert(not set(10, 20):isdisjoint(set(10, 30)))
    end,

    IsDisjointFirstEmpty = function()
        assert(set():isdisjoint(set(10, 20)))
    end,

    IsDisjointSecondEmpty = function()
        assert(set(10, 20):isdisjoint(set()))
    end,

    IsDisjointBothEmpty = function()
        -- The intersection of two empty sets is the empty set, so
        -- the two sets are disjoint even though they are also equal.
        -- Set theory is fun!
        assert(set():isdisjoint(set()))
    end,

    -------- copy()

    Copy = function()
        local s = set(10)
        local s2 = s:copy()
        assert(s2)
        assert(s2:has(10))
        assert(s2:len() == 1)
        -- The two sets should be independent.
        assert(s2 ~= s)
        s2:add(20)
        assert(s2:has(20))
        assert(not s:has(20))
    end,

    CopyMultiple = function()
        local s = set(10, 20, 30)
        local s2 = s:copy()
        assert(s2)
        assert(s2:has(10))
        assert(s2:has(20))
        assert(s2:has(30))
        assert(s2:len() == 3)
        assert(s2 ~= s)
        s2:add(40)
        assert(s2:has(40))
        assert(not s:has(40))
    end,

    CopyEmpty = function()
        local s = set()
        local s2 = s:copy()
        assert(s2:len() == 0)
        assert(s2 ~= s)
        s2:add(10)
        assert(s2:has(10))
        assert(not s:has(10))
    end,

    -------- Iteration

    Iterator = function()
        local s = set(1, 2, 4)
        -- We don't know in what order the iterator will give us the
        -- elements, but we've chosen powers of 2 as element values so
        -- that if we iterate three times as expected, the values will
        -- sum to 7 if and only if we get each element once.
        local count, sum = 0, 0
        for elem in s do
            count = count + 1
            sum = sum + elem
        end
        assert(count == 3)
        assert(sum == 7)
        -- s should be unmodified.
        assert(s:has(1))
        assert(s:has(2))
        assert(s:has(4))
        assert(s:len() == 3)
    end,

    IteratorSingleElement = function()
        local x
        for elem in set(10) do
            assert(not x)
            x = elem
        end
        assert(x == 10)
    end,

    IteratorEmptySet = function()
        for elem in set() do
            assert(false)  -- Should not be reached.
        end
    end,

    IteratorRemoveCurrent = function()
        local s = set(1, 2, 4)
        local count, sum = 0, 0
        local x
        for elem in s do
            count = count + 1
            sum = sum + elem
            if count == 1 then
                x = elem
                s:remove(x)
            end
        end
        assert(count == 3)
        assert(sum == 7)
        assert(x == 1 or x == 2 or x == 4)
        assert(not s:has(x))
        assert(s:len() == 2)
    end,

    IteratorRemoveSeen = function()
        local s = set(1, 2, 4)
        local count, sum = 0, 0
        local x
        for elem in s do
            count = count + 1
            sum = sum + elem
            if count == 1 then
                x = elem
            elseif count == 2 then
                s:remove(x)
            end
        end
        assert(count == 3)
        assert(sum == 7)
        assert(x == 1 or x == 2 or x == 4)
        assert(not s:has(x))
        assert(s:len() == 2)
    end,

    IteratorRemoveUnseen = function()
        local s = set(1, 2, 4)
        local count, sum = 0, 0
        local x
        for elem in s do
            count = count + 1
            sum = sum + elem
            if count == 1 then
                x = elem==1 and 2 or 1
                s:remove(x)
            end
        end
        assert(count == 2)
        assert(sum == 7-x)
        assert(x == 1 or x == 2)
        assert(not s:has(x))
        assert(s:len() == 2)
    end,

    -------- elements()

    Elements = function()
        local s = set(1, 2, 4)
        local array = s:elements()
        assert(#array == 3)
        assert(array[1] + array[2] + array[3] == 7)
        -- Make sure there are no stray elements in the returned table.
        assert(next(array, next(array, next(array, next(array)))) == nil)
        -- s should be unmodified.
        assert(s:has(1))
        assert(s:has(2))
        assert(s:has(4))
        assert(s:len() == 3)
    end,

    ElementsIterate = function()
        local array = set(1, 2, 4):elements()
        local i = 0
        for x in array do
            i = i+1
            assert(x == array[i])
        end
        assert(i == 3)
    end,

    ElementsSingleElement = function()
        local array = set(10):elements()
        local i, x = next(array)
        assert(i == 1)
        assert(x == 10)
        assert(next(array, i) == nil)
    end,

    ElementsEmptySet = function()
        local array = set():elements()
        assert(next(array) == nil)
    end,

    -------- sorted()

    Sorted = function()
        local s = set(10, 20, 30)
        local array = s:sorted()
        assert(#array == 3)
        -- Since this array is sorted, we don't have to play games with
        -- summing the element values and can just check them directly.
        assert(array[1] == 10)
        assert(array[2] == 20)
        assert(array[3] == 30)
        -- Make sure there are no stray elements in the returned table.
        assert(next(array, next(array, next(array, next(array)))) == nil)
        -- s should be unmodified.
        assert(s:has(10))
        assert(s:has(20))
        assert(s:has(30))
        assert(s:len() == 3)
    end,

    SortedIterate = function()
        local array = set(10, 20, 30):sorted()
        local i = 0
        for x in array do
            i = i+1
            assert(x == array[i])
        end
        assert(i == 3)
    end,

    SortedComparator = function()
        local function gt(a, b) return a > b end
        local array = set(10, 20, 30):sorted(gt)
        assert(#array == 3)
        assert(array[1] == 30)
        assert(array[2] == 20)
        assert(array[3] == 10)
        assert(next(array, next(array, next(array, next(array)))) == nil)
    end,

    SortedSingleElement = function()
        local array = set(10):sorted()
        local i, x = next(array)
        assert(i == 1)
        assert(x == 10)
        assert(next(array, i) == nil)
    end,

    SortedEmptySet = function()
        local array = set():sorted()
        assert(next(array) == nil)
    end,

}

function module.setTests(verbose)
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
        local success, errmsg = pcall(test)
        if success then
            if verbose then print("pass") end
        else
            fail = fail+1
            print("FAIL: "..(verbose and "" or name..": ")..errmsg)
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
