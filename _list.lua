--[[

Implementation of a list type in Lua.

This file declares the symbol "list" in the module table provided as the
second argument when loading the file (as is done by the WoW API).  If
no second argument is provided, one is created locally and returned from
the module, for use with Lua require().  Module sources using this
syntax are assumed to import the "list" identifier locally with
"local list = module.list" or similar.


A list is an ordered collection of values.  Lua already provides basic
support for lists in the form of tables with integer-valued keys, but
this type provides additional conveniences for working with lists.

Lists may contain any type of value other than nil, and may even contain
values of differing types.  Attempting to add nil to a list will raise
an error; other element operations passed a value of nil will behave as
usual when given a value not in the list (for example, has(nil) will
return false without raising an error).

The interface defined here draws largely from Python.  Notable
differences from Python syntax and usage are documented below.


A list instance can be created by calling the list() function:

    l = list()  -- Creates an empty list.

Optionally, the list can be prepopulated with values:

    l = list(2, 3, 5, 7)  -- Creates a list with four elements.

Note that passing a list (or a list-like table) as an argument to list()
adds that list instance itself as an element.  To create a new list with
the elements of another list, use the Lua unpack() function:

    t = {2, 3, 5, 7}
    l = list(unpack(t))

However, list operations which accept a list argument also accept a
list-like table, so there is typically no need to explicitly convert a
table to a list instance.  As an exception, at least one list operand to
the "+" operator and the single list operand to the "*" operator must be
an actual list instance in order for the operator to be resolved
correctly.


List instances support the standard Lua operations on list-like tables:

    first = l[1]  -- Extracts the first element of the list.
    penult = l[#l-1]  -- Extracts the second-last element of the list.
    table.insert(l, "word")  -- Appends "word" to the list.
    last = table.remove(l)  -- Removes and returns the last element.

Note that element indices are 1-based like Lua tables, not 0-based like
Python sequences, and Python-style negative indexing (for example, using
-1 to mean "the last element in the list") is not supported.

Unlike Python, this list type _does_ support implicit appending to the
list by assigning to an index one past the end of the list, to match
Lua table behavior.  Attempting to assign to any other index outside
the valid index range (integers 1 through the list length) will raise
an error.


List instances also support a number of convenience operations:

    l:append(x)  -- Append x to l (equivalent to "table.insert(l,x)")
    l:clear() -- Remove all elements from l
    l:copy()  -- Return a shallow copy of l (equivalent to "l + {}")
    l:count(x)  -- Number of occurrences of x in l
    l:discard(x)  -- Remove all instances of x in l
    l:extend(l2)  -- Append all elements in l2 to l
    l:has(x)  -- True if l contains the value x (Python "x in l")
    l:index(x)  -- Index of first occurrence of x in l; nil if not found
    l:insert(i,x)  -- Insert x in l at index i (like "table.insert(l,i,x)");
                   -- error if i is not in [1,#l+1]
    l:len()  -- Number of elements in l (equivalent to "#l")
    l:pop(i)  -- Remove and return the element of l at index i (default "#l");
              -- error if l is empty or i is out of range
    l:remove(x)  -- Remove the first instance of x in l; error if not found
    l:replace(i,j,k,l2)  -- Replace l:slice(i,j,k) with the contents of l2,
                         -- possibly resizing the list if k is 1 or omitted
                         -- (Python "l[i:j+1:k] = l2")
    l:reverse()  -- Reverse elements of l in place
    l:slice(i,j,k)  -- Extract a sublist (Python "l[i:j+1:k]")
    l:sort(compare)  -- Sort l, optionally with a comparator function
    l1 + l2  -- Create a new list containing l1's and l2's elements
             -- (equivalent to "l1:copy():extend(l2)")
    l * n  -- Create a new list containing max(0,n) copies of l's elements
           -- (operands can also be reversed: "n * l")

Unlike Python, index() does not raise an error if its argument is not
found in the list, instead returning nil.  This is done as a convenience
because catching errors in Lua is not as straightforward as in Python.
Similarly, discard() is provided as a non-error-raising alternative to
remove() for cases when the argument is not known to already be in the
list (and for parallelism with the set type).

Unlike Lua's table.insert(), insert() requires an index to be specified.
Use append() to append elements to the end of the list.  (insert() with
an explicit index of #l+1, one more than the list length, will still
append an element as expected.)

Passing a list to its own extend() or replace() method (for example,
"l:extend(l)") is safe; the argument will be treated as a list
containing the elements present in l at the time of the call.  For
replace(), this requires making an extra copy of the list.

For replace() and slice():
   - The end-of-range argument j is inclusive to match other Lua
     interfaces, rather than exclusive as in Python; for example,
     l:slice(2,4) returns a 3-element list consisting of the second,
     third, and fourth elements of the input list.  To specify a
     zero-length range, such as for replace(), pass j = i-1.
   - All range specification arguments (i, j, k) are optional as in
     Python, and default to the beginning of the list (1), the end of
     the list (#l), and 1, respectively; thus, l:slice() with no
     arguments has the same effect as l:copy() (but is slightly less
     efficient).  An argument value of nil for any of these parameters
     is treated the same as an omitted argument.
   - If specified, the start-of-range argument i must be a valid index
     for insertion, i.e. an integer in the range [1,#l+1], or the method
     will raise an error.  The end-of-range index j is silently clamped
     to [0,#l].  i=#l+1 or j=0 (after clamping) will always result in an
     empty slice.
   - replace() with k > 1 requires the replacement list l2 to have the
     same length as the number of replaced elements, also as in Python.
     Note that this is the number of replaced _elements_, not _indices_!
     Passing j > #l may result in fewer replaced elements than a simple
     calculation of floor((j-i)/k)+1 would suggest.
   - Reverse stepping (k < 0) is not supported.  If a reverse slice is
     needed, use l:reverse():slice(...).

The comparator for sort() should be defined as for table.sort(),
returning true if its first argument is strictly less than its second.
Lua does not support stable sorting, and elements which are equal by the
comparison function may be randomly rearranged; if a stable sort is
desired, it is the caller's responsibility to ensure that no two
elements compare equal (perhaps by replacing each element with an
{index,element} pair which can always be ordered).

To non-destructively sort a list, call sort() on a copy of the list:
    sorted_l = l:copy():sort(...)


Some methods which take one argument can also take multiple arguments:

    l:append(x, y, ...)
    l:count(x, y, ...)  -- Number of elements equal to any of x, y, ...
    l:discard(x, y, ...)
    l:extend(l2, l3, ...)
    l:has(x, y, ...)  -- True if all of x, y, ... are in l
    l:remove(x, y, ...)  -- Error if any of x, y, ... are not in l

or no arguments:

    l:add()  -- No-op
    l:count()  -- No-op, returns zero (nothing to count)
    l:discard()  -- No-op
    l:extend()  -- No-op
    l:has()  -- No-op, returns true ("all zero arguments are in l")
    l:remove()  -- No-op

For methods which modify the list in place (append, discard, extend,
remove), if the method is passed multiple arguments and one of those
arguments causes an error (other than a runtime error like "out of
memory") to be raised, it is unspecified how many of the remaining
arguments are processed; however, the state of the list when the error
is raised will be consistent with some number of valid arguments having
been completely processed.


All list methods which do not return an explicit value (specifically:
append, clear, discard, extend, insert, remove, replace, reverse, and
sort) return the list instance on which they operated, allowing
chaining:

    l1:extend(l2):remove(x)  -- l1 = (l1 + l2):remove(x)


A list is its own iterator:

    print("Contents of l:")
    for elem in l do
        print(elem)
    end

This is effectively identical to "for _,elem in ipairs(l)" but avoids
the need for an explicit ipairs() call or placeholder variable, at a
moderate cost in execution time (because the iteration is implemented in
Lua rather than native code).  Where performance is critical, explicit
use of ipairs() may be a better choice.


When using object (table or userdata) references as list elements, the
reference itself is taken as the element, not the content of the
referenced object.  Consider this code:

    local a = {1, 2, 3}   -- Create two distinct table objects.
    local b = {1, 2, 3}
    l:append(a)           -- |l| is assumed to be a list instance.
    assert(not l:has(b))  -- The table referenced by |b| is not in the list.

Even though both tables have exactly the same set of elements, the table
referenced by variable |b| is considered not an element of list |l|
because it is a distinct table object from table |a| which was added to
the list.  Conversely, strings in Lua are pure values, not objects, and
thus all instances of the same string data are treated as equal:

    local a = "1 2 3"
    local b = "1 2 3"
    l:append(a)
    assert(l:has(b))

]]--

------------------------------------------------------------------------
-- Implementation
------------------------------------------------------------------------

local _, module = ...
module = module or {} -- so the file can also be loaded with a simple require()

-- Localize some commonly called functions to reduce lookup cost.
local floor = math.floor
local getmetatable = getmetatable
local max = math.max
local min = math.min
local setmetatable = setmetatable
local strsub = string.sub
local tinsert = table.insert
local tostring = tostring
local tremove = table.remove

-- Error messages are defined as constants for testing convenience.
local ADD_NIL_MSG = "Cannot add nil to a list"
local NOT_FOUND_MSG = "Element not found in list"
local EMPTY_LIST_MSG = "List is empty"
local BAD_INDEX_MSG = "List index out of range"
local BAD_INDEX_TYPE_MSG = "Invalid list index"
local NOT_LIST_MSG = "Operand is not a list"
local REPLACE_SIZE_MSG = "Wrong size list for replacement"
local BAD_MUL_MSG = "List multiplication operand is not a number"
local BAD_ARGUMENT_MSG = "Invalid argument"

local list_new  -- Declared below.


function module.list(...)
    return list_new():append(...)
end

local list = module.list


-- Helper to build a set of values from varargs.  Returns the set and a
-- flag indicating whether any arguments were nil.  Note that we can't use
-- our set type here because it would cause a circular dependency.
local function make_values(...)
    local values = {}
    local any_nil = false
    for i = 1, select("#", ...) do
        local x = select(i, ...)
        if x ~= nil then
            values[x] = true
        else
            any_nil = true
        end
    end
    return values, any_nil
end

local list_methods = {
    append = function(l, ...)
        local n = #l
        for i = 1, select("#", ...) do
            local x = select(i, ...)
            if x == nil then
                error(ADD_NIL_MSG, 2)
            end
            rawset(l, n+i, x)
        end
        return l
    end,

    clear = function(l)
        -- The behavior of the "#" operator is undefined when a list-type table
        -- has holes, so we have to clear all indices, not just the first.
        for i = 1, #l do
            rawset(l, i, nil)
        end
        return l
    end,

    copy = function(l)
        return list():extend(l)
    end,

    count = function(l, ...)
        local values = make_values(...)
        local n = 0
        for _, elem in ipairs(l) do
            if values[elem] then
                n = n + 1
            end
        end
        return n
    end,

    discard = function(l, ...)
        local values = make_values(...)
        local out = 1
        for index, elem in ipairs(l) do
            if not values[elem] then
                if out ~= index then
                    rawset(l, out, elem)
                end
                out = out + 1
            end
        end
        for i = out, #l do  -- See note at clear().
            rawset(l, i, nil)
        end
        return l
    end,

    extend = function(l, ...)
        local n0 = #l  -- In case we find l in the arguments.
        for i = 1, select("#", ...) do
            local l2 = select(i, ...)
            if type(l2) ~= "table" then
                error(NOT_LIST_MSG, 2)
            end
            local n = #l
            if l2 ~= l then
                for j, x in ipairs(l2) do
                    rawset(l, n+j, x)
                end
            else
                for j = 1, n0 do
                    rawset(l, n+j, l[j])
                end
            end
        end
        return l
    end,

    has = function(l, ...)
        local values, any_nil = make_values(...)
        if any_nil then
            return false
        end
        for _, elem in ipairs(l) do
            if values[elem] then
                values[elem] = nil
            end
        end
        return next(values) == nil
    end,

    index = function(l, x)
        for i, elem in ipairs(l) do
            if elem == x then
                return i
            end
        end
        error(NOT_FOUND_MSG, 2)
    end,

    insert = function(l, i, x)
        if type(i) ~= "number" or i ~= floor(i) then
            error(BAD_INDEX_TYPE_MSG, 2)
        end
        if i < 1 or i > #l+1 then
            error(BAD_INDEX_MSG, 2)
        end
        if x == nil then
            error(ADD_NIL_MSG, 2)
        end
        tinsert(l, i, x)
        return l
    end,

    len = function(l) return #l end,

    pop = function(l, ...)
        local n = #l
        if n == 0 then
            error(EMPTY_LIST_MSG, 2)
        end
        local i
        if select("#", ...) > 0 then
            i = ...
            if type(i) ~= "number" or i ~= floor(i) then
                error(BAD_INDEX_TYPE_MSG, 2)
            end
            if i < 1 or i > n then
                error(BAD_INDEX_MSG, 2)
            end
        else
            i = n
        end
        return tremove(l, i)
    end,

    remove = function(l, ...)
        for i = 1, select("#", ...) do
            local x = select(i, ...)
            local ok, j = pcall(l.index, l, x)
            if not ok then
                error(NOT_FOUND_MSG, 2)
            end
            tremove(l, j)
        end
        return l
    end,

    replace = function(l, ...)
        local n = #l
        local nargs = select("#", ...)
        local i, j, k, l2
        if nargs >= 4 then
            i, j, k, l2 = ...
        elseif nargs == 3 then
            i, j, l2 = ...
        elseif nargs == 2 then
            i, l2 = ...
        else
            l2 = ...
        end
        if i == nil then
            i = 1
        elseif type(i) ~= "number" or floor(i) ~= i then
            error(BAD_INDEX_TYPE_MSG, 2)
        elseif i < 1 or i > n+1 then
            error(BAD_INDEX_MSG, 2)
        end
        if j == nil then
            j = n
        elseif type(j) ~= "number" or floor(j) ~= j then
            error(BAD_INDEX_TYPE_MSG, 2)
        else
            j = min(max(j, i-1), n)
        end
        if k == nil then
            k = 1
        elseif type(k) ~= "number" or floor(k) ~= k or k < 1 then
            error(BAD_ARGUMENT_MSG, 2)
        end
        if type(l2) ~= "table" then
            error(NOT_LIST_MSG, 2)
        end
        local n2 = #l2
        if l2 == l then
            l2 = l:copy()  -- So we can safely modify l.
        end
        if k == 1 then
            local count = (j+1) - i
            local delta = n2 - count
            if delta > 0 then
                for index = n, j+1, -1 do
                    rawset(l, index+delta, l[index])
                end
            elseif delta < 0 then
                for index = j+1, n do
                    rawset(l, index+delta, l[index])
                end
                for index = (n+1)+delta, n do  -- See note at clear().
                    rawset(l, index, nil)
                end
            end
            i = i-1
            for index = 1, n2 do
                rawset(l, i+index, l2[index])
            end
        else  -- k > 1
            local count = floor((j-i)/k)+1
            if count ~= n2 then
                error(REPLACE_SIZE_MSG, 2)
            end
            local source = 1
            for index = i, j, k do
                if source > n2 then
                    error(REPLACE_SIZE_MSG, 2)
                end
                rawset(l, index, l2[source])
                source = source + 1
            end
            assert(source == n2+1)
        end
        return l
    end,

    reverse = function(l)
        local n = #l
        local nplus1 = n+1
        for i = 1, floor(n/2) do
            l[i], l[nplus1 - i] = l[nplus1 - i], l[i]
        end
        return l
    end,

    slice = function(l, i, j, k)
        local n = #l
        if i == nil then
            i = 1
        elseif type(i) ~= "number" or floor(i) ~= i then
            error(BAD_INDEX_TYPE_MSG, 2)
        elseif i < 1 or i > n+1 then
            error(BAD_INDEX_MSG, 2)
        end
        if j == nil then
            j = n
        elseif type(j) ~= "number" or floor(j) ~= j then
            error(BAD_INDEX_TYPE_MSG, 2)
        else
            j = min(max(j, i-1), n)
        end
        if k == nil then
            k = 1
        elseif type(k) ~= "number" or floor(k) ~= k or k < 1 then
            error(BAD_ARGUMENT_MSG, 2)
        end
        local result = list()
        local out = 1
        for index = i, j, k do
            rawset(result, out, l[index])
            out = out+1
        end
        return result
    end,

    sort = function(l, compare)
        if compare ~= nil and type(compare) ~= "function" then
            error(BAD_ARGUMENT_MSG, 2)
        end
        table.sort(l, compare)
        return l
    end,
}


local function list_add(l1, l2)
    return list():extend(l1, l2)
end

local function list_mul(a, b)
    local l, n
    if type(a) == "table" and getmetatable(a) and getmetatable(a).__mul == list_mul then
        l, n = a, b
    else
        assert(type(b) == "table" and getmetatable(b) and getmetatable(b).__mul == list_mul)
        l, n = b, a
    end
    if type(n) ~= "number" then
        error(BAD_MUL_MSG, 2)
    end
    local result = list()
    for i = 1, n do
        result:extend(l)
    end
    return result
end

local function list_newindex(l, k, v)
    if type(k) ~= "number" or k ~= floor(k) then
        error(BAD_INDEX_TYPE_MSG, 2)
    end
    if k ~= #l+1 then
        error(BAD_INDEX_MSG, 2)
    end
    rawset(l, k, v)
end

local list_metatable = {
    __add = list_add,
    __mul = list_mul,
    __index = list_methods,
    __newindex = list_newindex,
    __tostring = function(l) return getmetatable(l).tostring end,
}


--[[local]] function list_new()
    local l = {}

    local mt = {}
    for k, v in pairs(list_metatable) do mt[k] = v end

    --[[
        Lua doesn't let us strformat("%p") to get the address of a table,
        so we rely on the default "table: %p" format to create a slightly
        more informative value for tostring().  We save the value in the
        metatable so that users who call pairs() on the list don't get an
        unexpected key in the iteration.  We need a separate metatable
        instance per list anyway for iteration (see below), so this
        doesn't add any further overhead.
    ]]--
    local str = tostring(l)
    assert(strsub(str, 1, 5) == "table")
    mt.tostring = "list" .. strsub(str, 6)

    --[[
        Generic "for" expects a function taking two arguments, but
        since we give it a callable table, the table itself is
        prepended as a |self| argument.  The first ("state") argument
        to the iterator will always be nil when using our documented
        iteration syntax, but we have |self|, so there's no need for
        a separate state argument.

        In order to avoid leaking the iterator index to the caller
        and thus allow straightforward iteration as documented, we
        use the previous-value argument as a flag: if it is nil, this
        must be the first call, so we reset the index in that case.
    ]]--
    local i
    mt.__call = function(self, _, prev)
        if prev == nil then i = 0 end
        if i < #self then
            i = i+1
            return self[i]
        else
            return nil
        end
    end

    return setmetatable(l, mt)
end

------------------------------------------------------------------------
-- Test routines (can be run with: lua -e 'require("_list").listTests()')
------------------------------------------------------------------------

local tests = {

    -------- Instance creation (and basic Lua operator interaction)

    NewInstance = function()
        local l = list()
        assert(type(l) == "table")
        assert(next(l) == nil)
        assert(strsub(tostring(l), 1, 5) == "list:")
    end,

    NewInstanceArgs = function()
        local l = list(10, 20, 30)
        assert(type(l) == "table")
        assert(#l == 3)
        assert(l[1] == 10)
        assert(l[2] == 20)
        assert(l[3] == 30)
        assert(l[4] == nil)
        local found = {}
        local key = nil
        for i = 1, 3 do
            key = next(l, key)
            assert(key ~= nil)
            assert(not found[key])
            found[key] = true
        end
        assert(next(l, key) == nil)
        assert(found[1])
        assert(found[2])
        assert(found[3])
    end,

    -------- Indexed assignment

    IndexedAssign = function()
        local l = list(10, 20, 30)
        l[2] = 40
        assert(#l == 3)
        assert(l[1] == 10)
        assert(l[2] == 40)
        assert(l[3] == 30)
    end,

    IndexedAssignAppend = function()
        local l = list(10, 20, 30)
        l[4] = 40
        assert(#l == 4)
        assert(l[1] == 10)
        assert(l[2] == 20)
        assert(l[3] == 30)
        assert(l[4] == 40)
    end,

    IndexedAssignAppendToEmpty = function()
        local l = list()
        l[1] = 10
        assert(#l == 1)
        assert(l[1] == 10)
    end,

    IndexedAssignHole = function()
        local l = list(10, 20, 30)
        local result, errmsg = pcall(function() l[5] = 50 end)
        assert(result == false)
        assert(errmsg:find(BAD_INDEX_MSG, 1, true), errmsg)
        assert(#l == 3)
        assert(l[1] == 10)
        assert(l[2] == 20)
        assert(l[3] == 30)
    end,

    IndexedAssignZero = function()
        local l = list(10, 20, 30)
        local result, errmsg = pcall(function() l[0] = 50 end)
        assert(result == false)
        assert(errmsg:find(BAD_INDEX_MSG, 1, true), errmsg)
        assert(#l == 3)
        assert(l[1] == 10)
        assert(l[2] == 20)
        assert(l[3] == 30)
    end,

    IndexedAssignNegative = function()
        local l = list(10, 20, 30)
        local result, errmsg = pcall(function() l[-1] = 50 end)
        assert(result == false)
        assert(errmsg:find(BAD_INDEX_MSG, 1, true), errmsg)
        assert(#l == 3)
        assert(l[1] == 10)
        assert(l[2] == 20)
        assert(l[3] == 30)
    end,

    IndexedAssignFraction = function()
        local l = list(10, 20, 30)
        local result, errmsg = pcall(function() l[1.5] = 50 end)
        assert(result == false)
        assert(errmsg:find(BAD_INDEX_TYPE_MSG, 1, true), errmsg)
        assert(#l == 3)
        assert(l[1] == 10)
        assert(l[2] == 20)
        assert(l[3] == 30)
    end,

    IndexedAssignNonNumber = function()
        local l = list(10, 20, 30)
        local result, errmsg = pcall(function() l["one"] = 50 end)
        assert(result == false)
        assert(errmsg:find(BAD_INDEX_TYPE_MSG, 1, true), errmsg)
        assert(#l == 3)
        assert(l[1] == 10)
        assert(l[2] == 20)
        assert(l[3] == 30)
    end,

    IndexedAssignHoleInEmpty = function()
        local l = list()
        local result, errmsg = pcall(function() l[5] = 50 end)
        assert(result == false)
        assert(errmsg:find(BAD_INDEX_MSG, 1, true), errmsg)
        assert(next(l) == nil)
    end,

    IndexedAssignZeroInEmpty = function()
        local l = list()
        local result, errmsg = pcall(function() l[0] = 50 end)
        assert(result == false)
        assert(errmsg:find(BAD_INDEX_MSG, 1, true), errmsg)
        assert(next(l) == nil)
    end,

    IndexedAssignNegativeInEmpty = function()
        local l = list()
        local result, errmsg = pcall(function() l[-1] = 50 end)
        assert(result == false)
        assert(errmsg:find(BAD_INDEX_MSG, 1, true), errmsg)
        assert(next(l) == nil)
    end,

    -------- Modification via table.insert and table.remove

    TableInsertAppend = function()
        local l = list(10)
        table.insert(l, 20)
        assert(#l == 2)
        assert(l[1] == 10)
        assert(l[2] == 20)
    end,

    TableInsertAppendEmpty = function()
        local l = list()
        table.insert(l, 10)
        assert(#l == 1)
        assert(l[1] == 10)
    end,

    TableInsertAppendMultiple = function()
        local l = list()
        table.insert(l, 10)
        table.insert(l, 20)
        assert(#l == 2)
        assert(l[1] == 10)
        assert(l[2] == 20)
    end,

    TableInsertInsert = function()
        local l = list(10, 20, 30)
        table.insert(l, 2, 40)
        assert(#l == 4)
        assert(l[1] == 10)
        assert(l[2] == 40)
        assert(l[3] == 20)
        assert(l[4] == 30)
    end,

    TableRemoveLast = function()
        local l = list(10, 20, 30)
        assert(table.remove(l) == 30)
        assert(#l == 2)
        assert(l[1] == 10)
        assert(l[2] == 20)
    end,

    TableRemoveFirst = function()
        local l = list(10, 20, 30)
        assert(table.remove(l, 1) == 10)
        assert(#l == 2)
        assert(l[1] == 20)
        assert(l[2] == 30)
    end,

    TableRemoveOther = function()
        local l = list(10, 20, 30)
        assert(table.remove(l, 2) == 20)
        assert(#l == 2)
        assert(l[1] == 10)
        assert(l[2] == 30)
    end,

    -------- append()

    Append = function()
        local l = list()
        assert(l:append(10) == l)
        assert(#l == 1)
        assert(l[1] == 10)
    end,

    AppendSecond = function()
        local l = list()
        l:append(10)
        l:append(20)
        assert(#l == 2)
        assert(l[1] == 10)
        assert(l[2] == 20)
    end,

    AppendToInitialized = function()
        local l = list(10, 20, 30)
        l:append(40)
        assert(#l == 4)
        assert(l[1] == 10)
        assert(l[2] == 20)
        assert(l[3] == 30)
        assert(l[4] == 40)
    end,

    AppendSame = function()
        local l = list()
        l:append(10)
        l:append(10)
        assert(#l == 2)
        assert(l[1] == 10)
        assert(l[2] == 10)
    end,

    AppendMultiple = function()
        local l = list()
        l:append(10, 20, 30)
        assert(#l == 3)
        assert(l[1] == 10)
        assert(l[2] == 20)
        assert(l[3] == 30)
    end,

    AppendMultipleTypes = function()
        local l = list()
        local tval = {30}
        local fval = function() return 40 end
        l:append(10, "twenty", tval, fval)
        assert(#l == 4)
        assert(l[1] == 10)
        assert(l[2] == "twenty")
        assert(l[3] == tval)
        assert(l[4] == fval)
    end,

    AppendNil = function()
        local l = list()
        local result, errmsg = pcall(function() l:append(nil) end)
        assert(result == false)
        assert(errmsg:find(ADD_NIL_MSG, 1, true), errmsg)
        assert(#l == 0)
    end,

    AppendMultipleNil = function()
        local l = list()
        local result, errmsg = pcall(function() l:append(10, nil, 30) end)
        assert(result == false)
        assert(errmsg:find(ADD_NIL_MSG, 1, true), errmsg)
        assert(#l <= 1)
        assert(#l == 0 or l[1] == 10)
    end,

    -------- clear()

    Clear = function()
        local l = list(10)
        assert(l:clear() == l)
        assert(#l == 0)
    end,

    ClearMultiple = function()
        local l = list(10, 20, 30)
        l:clear()
        assert(#l == 0)
    end,

    ClearEmpty = function()
        local l = list()
        l:clear() -- No-op.
        assert(#l == 0)
    end,

    -------- copy()

    Copy = function()
        local l = list(10)
        local l2 = l:copy()
        assert(l2)
        assert(#l2 == 1)
        assert(l2[1] == 10)
        -- The two lists should be independent.
        assert(l2 ~= l)
        l2[1] = 15
        assert(l2[1] == 15)
        assert(l[1] == 10)
    end,

    CopyMultiple = function()
        local l = list(10, 20, 30)
        local l2 = l:copy()
        assert(l2)
        assert(#l2 == 3)
        assert(l2[1] == 10)
        assert(l2[2] == 20)
        assert(l2[3] == 30)
        assert(l2 ~= l)
        l2[1] = 15
        assert(l2[1] == 15)
        assert(l[1] == 10)
    end,

    CopyEmpty = function()
        local l = list()
        local l2 = l:copy()
        assert(#l2 == 0)
        assert(l2 ~= l)
        l2[1] = 10
        assert(#l2 == 1)
        assert(l2[1] == 10)
        assert(#l == 0)
    end,

    -------- count()

    Count = function()
        local l = list(10, 20, 30)
        assert(l:count(10) == 1)
        assert(l:count(20) == 1)
        assert(l:count(30) == 1)
    end,

    CountNonExistent = function()
        local l = list(10)
        assert(l:count(20) == 0)
    end,

    CountEmpty = function()
        local l = list()
        assert(l:count(10) == 0)
    end,

    CountNone = function()
        local l = list(10, 20, 30)
        assert(l:count() == 0)
    end,

    CountMultipleElements = function()
        local l = list(10, 10, 30)
        assert(l:count(10) == 2)
    end,

    CountMultipleElementsSeparated = function()
        local l = list(10, 10, 30, 10)
        assert(l:count(10) == 3)
    end,

    CountMultipleArguments = function()
        local l = list(10, 20, 30)
        assert(l:count(10, 30) == 2)
    end,

    CountMultipleArgumentsMissing = function()
        local l = list(10, 20, 30)
        assert(l:count(10, 40, 30) == 2)
    end,

    CountString = function()
        local l = list()
        local a = "abc"
        l:append(a)
        assert(l:count(a) == 1)
        local b = "abc"
        assert(l:count(b) == 1)  -- Because strings are not instanced.
    end,

    CountTable = function()
        local l = list()
        local t = {1, 2, 3}
        l:append(t)
        assert(l:count(t) == 1)
    end,

    CountIdenticalTable = function()
        local l = list()
        local t1 = {1, 2, 3}
        local t2 = {1, 2, 3}
        assert(t1 ~= t2)
        l:append(t1)
        assert(l:count(t2) == 0) -- Should be treated as a separate element.
    end,

    CountNil = function()
        local l = list(10)
        assert(l:count(nil) == 0)  -- nil can never be a list element.
    end,

    CountMultipleArgumentsNil = function()
        local l = list(10, 20, 30)
        assert(l:count(10, nil, 30) == 2)
    end,

    -------- discard()

    Discard = function()
        local l = list(10)
        assert(l:discard(10) == l)
        assert(#l == 0)
    end,

    DiscardNone = function()
        local l = list(10)
        assert(l:discard() == l)
        assert(#l == 1)
        assert(l[1] == 10)
    end,

    DiscardMultiple = function()
        local l = list(10, 20, 30, 40, 50)
        assert(l:discard(10, 30, 40) == l)
        assert(#l == 2)
        assert(l[1] == 20)
        assert(l[2] == 50)
    end,

    DiscardMultipleDifferentOrder = function()
        local l = list(10, 20, 30, 40, 50)
        assert(l:discard(40, 10, 30) == l)
        assert(#l == 2)
        assert(l[1] == 20)
        assert(l[2] == 50)
    end,

    DiscardAll = function()
        local l = list(10, 20, 30)
        assert(l:discard(10, 20, 30) == l)
        assert(#l == 0)
    end,

    DiscardAllReverse = function()
        local l = list(10, 20, 30)
        assert(l:discard(30, 20, 10) == l)
        assert(#l == 0)
    end,

    DiscardAllMixedORder = function()
        local l = list(10, 20, 30, 40, 50)
        assert(l:discard(20, 50, 30, 10, 40) == l)
        assert(#l == 0)
    end,

    DiscardNotFound = function()
        local l = list(10)
        assert(l:discard(20) == l)  -- Call should not error.
        assert(#l == 1)
        assert(l[1] == 10)
    end,

    DiscardEmpty = function()
        local l = list()
        assert(l:discard(10) == l)  -- Call should not error.
        assert(#l == 0)
    end,

    DiscardNil = function()
        local l = list(10)
        assert(l:discard(nil) == l)  -- Call should not error.
        assert(#l == 1)
        assert(l[1] == 10)
    end,

    DiscardMultipleNil = function()
        local l = list(10, 20, 30)
        assert(l:discard(10, nil, 30) == l)  -- Call should not error.
        assert(#l == 1)
        assert(l[1] == 20)
    end,

    -------- extend()

    Extend = function()
        local l1 = list(10)
        local l2 = list(20)
        assert(l1:extend(l2) == l1)
        assert(#l1 == 2)
        assert(l1[1] == 10)
        assert(l1[2] == 20)
        -- l2 should be unmodified.
        assert(#l2 == 1)
        assert(l2[1] == 20)
    end,

    ExtendFirstEmpty = function()
        local l1 = list()
        local l2 = list(20)
        assert(l1:extend(l2) == l1)
        assert(#l1 == 1)
        assert(l1[1] == 20)
        assert(#l2 == 1)
        assert(l2[1] == 20)
    end,

    ExtendSecondEmpty = function()
        local l1 = list(10)
        local l2 = list()
        assert(l1:extend(l2) == l1)
        assert(#l1 == 1)
        assert(l1[1] == 10)
        assert(#l2 == 0)
    end,

    ExtendNone = function()
        local l = list(10, 30)
        assert(l:extend() == l)
        assert(#l == 2)
        assert(l[1] == 10)
        assert(l[2] == 30)
    end,

    ExtendMultipleElements = function()
        local l = list(10, 30):extend(list(20, 40, 60))
        assert(#l == 5)
        assert(l[1] == 10)
        assert(l[2] == 30)
        assert(l[3] == 20)
        assert(l[4] == 40)
        assert(l[5] == 60)
    end,

    ExtendMultipleElementsRepeat = function()
        local l = list(10, 30):extend(list(20, 30, 40))
        assert(#l == 5)
        assert(l[1] == 10)
        assert(l[2] == 30)
        assert(l[3] == 20)
        assert(l[4] == 30)
        assert(l[5] == 40)
    end,

    ExtendPlainTable = function()
        local l = list(10, 30):extend({20, 40, 60})
        assert(#l == 5)
        assert(l[1] == 10)
        assert(l[2] == 30)
        assert(l[3] == 20)
        assert(l[4] == 40)
        assert(l[5] == 60)
    end,

    ExtendMultipleLists = function()
        local l = list(10, 30):extend(list(20), list(30), list(40))
        assert(#l == 5)
        assert(l[1] == 10)
        assert(l[2] == 30)
        assert(l[3] == 20)
        assert(l[4] == 30)
        assert(l[5] == 40)
    end,

    ExtendSelf = function()
        local l = list(10, 30)
        assert(l:extend(l) == l)
        assert(#l == 4)
        assert(l[1] == 10)
        assert(l[2] == 30)
        assert(l[3] == 10)
        assert(l[4] == 30)
    end,

    ExtendSelfWithOther = function()
        local l = list(10, 30)
        assert(l:extend(list(20), l, list(40)) == l)
        assert(#l == 6)
        assert(l[1] == 10)
        assert(l[2] == 30)
        assert(l[3] == 20)
        assert(l[4] == 10)
        assert(l[5] == 30)
        assert(l[6] == 40)
    end,

    ExtendSelfMultiple = function()
        local l = list(10, 30)
        assert(l:extend(list(20), l, list(40), l) == l)
        assert(#l == 8)
        assert(l[1] == 10)
        assert(l[2] == 30)
        assert(l[3] == 20)
        assert(l[4] == 10)
        assert(l[5] == 30)
        assert(l[6] == 40)
        assert(l[7] == 10)
        assert(l[8] == 30)
    end,

    -------- has()

    Has = function()
        local l = list(10, 20, 30)
        assert(l:has(10))
        assert(l:has(20))
        assert(l:has(30))
    end,

    HasNonExistent = function()
        local l = list(10)
        assert(not l:has(20))
    end,

    HasEmpty = function()
        local l = list()
        assert(not l:has(10))
    end,

    HasNone = function()
        local l = list()
        assert(l:has()) -- True: the list has all zero of the specified values.
    end,

    HasMultiple = function()
        local l = list(10, 20, 30)
        assert(l:has(10, 20, 30))
    end,

    HasMultipleMissing = function()
        local l = list(10, 20, 30)
        assert(not l:has(10, 40, 30))
    end,

    HasString = function()
        local l = list()
        local a = "abc"
        l:append(a)
        assert(l:has(a))
        local b = "abc"
        assert(l:has(b))  -- Because strings are not instanced.
    end,

    HasTable = function()
        local l = list()
        local t = {1, 2, 3}
        l:append(t)
        assert(l:has(t))
    end,

    HasIdenticalTable = function()
        local l = list()
        local t1 = {1, 2, 3}
        local t2 = {1, 2, 3}
        assert(t1 ~= t2)
        l:append(t1)
        assert(not l:has(t2)) -- Should be treated as a separate element.
    end,

    HasNil = function()
        local l = list(10)
        assert(not l:has(nil))  -- False: nil can never be a list element.
    end,

    HasMultipleNil = function()
        local l = list(10, 20, 30)
        assert(not l:has(10, nil, 30))
    end,

    -------- index()

    Index = function()
        local l = list(10, 20, 30)
        assert(l:index(10) == 1)
        assert(l:index(20) == 2)
        assert(l:index(30) == 3)
    end,

    IndexNotFound = function()
        local l = list(10)
        local result, errmsg = pcall(function() return l:index(20) end)
        assert(result == false)
        assert(errmsg:find(NOT_FOUND_MSG, 1, true), errmsg)
    end,

    IndexEmpty = function()
        local l = list()
        local result, errmsg = pcall(function() return l:index(10) end)
        assert(result == false)
        assert(errmsg:find(NOT_FOUND_MSG, 1, true), errmsg)
    end,

    IndexNil = function()
        local l = list(10)
        local result, errmsg = pcall(function() return l:index(nil) end)
        assert(result == false)
        assert(errmsg:find(NOT_FOUND_MSG, 1, true), errmsg)
    end,

    -------- insert()

    Insert = function()
        local l = list(10, 20, 30)
        assert(l:insert(2, 40) == l)
        assert(#l == 4)
        assert(l[1] == 10)
        assert(l[2] == 40)
        assert(l[3] == 20)
        assert(l[4] == 30)
    end,

    InsertInitial = function()
        local l = list(10, 20, 30)
        assert(l:insert(1, 40) == l)
        assert(#l == 4)
        assert(l[1] == 40)
        assert(l[2] == 10)
        assert(l[3] == 20)
        assert(l[4] == 30)
    end,

    InsertFinal = function()
        local l = list(10, 20, 30)
        assert(l:insert(3, 40) == l)
        assert(#l == 4)
        assert(l[1] == 10)
        assert(l[2] == 20)
        assert(l[3] == 40)
        assert(l[4] == 30)
    end,

    InsertAppend = function()
        local l = list(10, 20, 30)
        assert(l:insert(4, 40) == l)
        assert(#l == 4)
        assert(l[1] == 10)
        assert(l[2] == 20)
        assert(l[3] == 30)
        assert(l[4] == 40)
    end,

    InsertIndexOutOfRange = function()
        local l = list(10, 20, 30)
        local result, errmsg = pcall(function() l:insert(5, 40) end)
        assert(result == false)
        assert(errmsg:find(BAD_INDEX_MSG, 1, true), errmsg)
        assert(#l == 3)
        assert(l[1] == 10)
        assert(l[2] == 20)
        assert(l[3] == 30)
    end,

    InsertIndexZero = function()
        local l = list(10, 20, 30)
        local result, errmsg = pcall(function() l:insert(0, 40) end)
        assert(result == false)
        assert(errmsg:find(BAD_INDEX_MSG, 1, true), errmsg)
        assert(#l == 3)
        assert(l[1] == 10)
        assert(l[2] == 20)
        assert(l[3] == 30)
    end,

    InsertIndexNegative = function()
        local l = list(10, 20, 30)
        local result, errmsg = pcall(function() l:insert(-1, 40) end)
        assert(result == false)
        assert(errmsg:find(BAD_INDEX_MSG, 1, true), errmsg)
        assert(#l == 3)
        assert(l[1] == 10)
        assert(l[2] == 20)
        assert(l[3] == 30)
    end,

    InsertIndexFraction = function()
        local l = list(10, 20, 30)
        local result, errmsg = pcall(function() l:insert(1.5, 40) end)
        assert(result == false)
        assert(errmsg:find(BAD_INDEX_TYPE_MSG, 1, true), errmsg)
        assert(#l == 3)
        assert(l[1] == 10)
        assert(l[2] == 20)
        assert(l[3] == 30)
    end,

    InsertIndexNonNumber = function()
        local l = list(10, 20, 30)
        -- Use an element value which could be a valid index to ensure that
        -- the method doesn't try to be clever and invert the argument order.
        local result, errmsg = pcall(function() l:insert("one", 4) end)
        assert(result == false)
        assert(errmsg:find(BAD_INDEX_TYPE_MSG, 1, true), errmsg)
        assert(#l == 3)
        assert(l[1] == 10)
        assert(l[2] == 20)
        assert(l[3] == 30)
    end,

    InsertNil = function()
        local l = list(10, 20, 30)
        local result, errmsg = pcall(function() l:insert(2, nil) end)
        assert(result == false)
        assert(errmsg:find(ADD_NIL_MSG, 1, true), errmsg)
        assert(#l == 3)
        assert(l[1] == 10)
        assert(l[2] == 20)
        assert(l[3] == 30)
    end,

    InsertMissingArg = function()
        local l = list(10, 20, 30)
        -- Verify that insert() actually requires the second argument and
        -- doesn't treat a single-argument call like append().
        local result, errmsg = pcall(function() l:insert(2) end)
        assert(result == false)
        assert(errmsg:find(ADD_NIL_MSG, 1, true), errmsg)
        assert(#l == 3)
        assert(l[1] == 10)
        assert(l[2] == 20)
        assert(l[3] == 30)
    end,

    -------- len()

    LenEmpty = function()
        local l = list()
        assert(l:len() == 0)
    end,

    LenSingle = function()
        local l = list(10)
        assert(l:len() == 1)
    end,

    LenAppendSingle = function()
        local l = list()
        l:append(10)
        assert(l:len() == 1)
    end,

    LenAssignSingle = function()
        local l = list()
        l[1] = 10
        assert(l:len() == 1)
    end,

    LenMultiple = function()
        local l = list(10, 20, 30)
        assert(l:len() == 3)
    end,

    LenAppendMultiple = function()
        local l = list(10)
        l:append(20, 30)
        assert(l:len() == 3)
    end,

    -------- pop()

    Pop = function()
        local l = list(10)
        assert(l:pop() == 10)
        assert(#l == 0)
    end,

    PopFromMultiple = function()
        local l = list(10, 20, 30)
        assert(l:pop() == 30)
        assert(#l == 2)
        assert(l[1] == 10)
        assert(l[2] == 20)
    end,

    PopMultiple = function()
        local l = list(10, 20, 30)
        local x, y, z = l:pop(), l:pop(), l:pop()
        assert(x == 30)
        assert(y == 20)
        assert(z == 10)
        assert(#l == 0)
    end,

    PopSpecific = function()
        local l = list(10, 20, 30)
        assert(l:pop(2) == 20)
        assert(#l == 2)
        assert(l[1] == 10)
        assert(l[2] == 30)
    end,

    PopFirst = function()
        local l = list(10, 20, 30)
        assert(l:pop(1) == 10)
        assert(#l == 2)
        assert(l[1] == 20)
        assert(l[2] == 30)
    end,

    PopOnly = function()
        local l = list(10)
        assert(l:pop() == 10)
        assert(#l == 0)
    end,

    PopEmpty = function()
        local l = list()
        local result, errmsg = pcall(function() l:pop() end)
        assert(result == false)
        assert(errmsg:find(EMPTY_LIST_MSG, 1, true), errmsg)
        assert(#l == 0)
    end,

    PopOutOfRange = function()
        local l = list(10, 20, 30)
        local result, errmsg = pcall(function() l:pop(4) end)
        assert(result == false)
        assert(errmsg:find(BAD_INDEX_MSG, 1, true), errmsg)
        assert(#l == 3)
        assert(l[1] == 10)
        assert(l[2] == 20)
        assert(l[3] == 30)
    end,

    PopZero = function()
        local l = list(10, 20, 30)
        local result, errmsg = pcall(function() l:pop(0) end)
        assert(result == false)
        assert(errmsg:find(BAD_INDEX_MSG, 1, true), errmsg)
        assert(#l == 3)
        assert(l[1] == 10)
        assert(l[2] == 20)
        assert(l[3] == 30)
    end,

    PopNegative = function()
        local l = list(10, 20, 30)
        local result, errmsg = pcall(function() l:pop(-1) end)
        assert(result == false)
        assert(errmsg:find(BAD_INDEX_MSG, 1, true), errmsg)
        assert(#l == 3)
        assert(l[1] == 10)
        assert(l[2] == 20)
        assert(l[3] == 30)
    end,

    PopFraction = function()
        local l = list(10, 20, 30)
        local result, errmsg = pcall(function() l:pop(1.5) end)
        assert(result == false)
        assert(errmsg:find(BAD_INDEX_TYPE_MSG, 1, true), errmsg)
        assert(#l == 3)
        assert(l[1] == 10)
        assert(l[2] == 20)
        assert(l[3] == 30)
    end,

    PopNonNumber = function()
        local l = list(10, 20, 30)
        local result, errmsg = pcall(function() l:pop("one") end)
        assert(result == false)
        assert(errmsg:find(BAD_INDEX_TYPE_MSG, 1, true), errmsg)
        assert(#l == 3)
        assert(l[1] == 10)
        assert(l[2] == 20)
        assert(l[3] == 30)
    end,

    -------- remove()

    Remove = function()
        local l = list(10, 20, 30)
        assert(l:remove(20) == l)
        assert(#l == 2)
        assert(l[1] == 10)
        assert(l[2] == 30)
    end,

    RemoveFirst = function()
        local l = list(10, 20, 30)
        assert(l:remove(10) == l)
        assert(#l == 2)
        assert(l[1] == 20)
        assert(l[2] == 30)
    end,

    RemoveLast = function()
        local l = list(10, 20, 30)
        assert(l:remove(30) == l)
        assert(#l == 2)
        assert(l[1] == 10)
        assert(l[2] == 20)
    end,

    RemoveNone = function()
        local l = list(10)
        assert(l:remove() == l)
        assert(#l == 1)
        assert(l[1] == 10)
    end,

    RemoveMultiple = function()
        local l = list(10, 20, 30, 40, 50)
        assert(l:remove(10, 30, 40) == l)
        assert(#l == 2)
        assert(l[1] == 20)
        assert(l[2] == 50)
    end,

    RemoveMultipleOutOfOrder = function()
        local l = list(10, 20, 30, 40, 50)
        assert(l:remove(40, 10, 50, 30) == l)
        assert(#l == 1)
        assert(l[1] == 20)
    end,

    RemoveNotFound = function()
        local l = list(10)
        local result, errmsg = pcall(function() l:remove(20) end)
        assert(result == false)
        assert(errmsg:find(NOT_FOUND_MSG, 1, true), errmsg)
        assert(#l == 1)
        assert(l[1] == 10)
    end,

    RemoveEmpty = function()
        local l = list()
        local result, errmsg = pcall(function() l:remove(10) end)
        assert(result == false)
        assert(errmsg:find(NOT_FOUND_MSG, 1, true), errmsg)
        assert(#l == 0)
    end,

    RemoveNil = function()
        local l = list(10)
        local result, errmsg = pcall(function() l:remove(nil) end)
        assert(result == false)
        assert(errmsg:find(NOT_FOUND_MSG, 1, true), errmsg)
        assert(#l == 1)
        assert(l[1] == 10)
    end,

    -------- replace()

    Replace = function()
        local l = list(10, 20, 30, 40, 50)
        assert(l:replace(2, 4, 1, list(60, 70, 80)) == l)
        assert(#l == 5)
        assert(l[1] == 10)
        assert(l[2] == 60)
        assert(l[3] == 70)
        assert(l[4] == 80)
        assert(l[5] == 50)
    end,

    ReplaceWholeList = function()
        local l = list(10, 20, 30, 40, 50)
        -- We should get the same instance back even when replacing everything.
        assert(l:replace(1, 5, 1, list(60, 70, 80, 90, 100)) == l)
        assert(#l == 5)
        assert(l[1] == 60)
        assert(l[2] == 70)
        assert(l[3] == 80)
        assert(l[4] == 90)
        assert(l[5] == 100)
    end,

    ReplaceSingleElement = function()
        local l = list(10, 20, 30):replace(2, 2, 1, list(60))
        assert(#l == 3)
        assert(l[1] == 10)
        assert(l[2] == 60)
        assert(l[3] == 30)
    end,

    ReplaceEmpty = function()
        local l = list(10, 20, 30):replace(2, 1, 1, list())
        assert(l[1] == 10)
        assert(l[2] == 20)
        assert(l[3] == 30)
    end,

    ReplacePlainTable = function()
        local l = list(10, 20, 30, 40, 50)
        assert(l:replace(2, 4, 1, {60, 70, 80}) == l)
        assert(#l == 5)
        assert(l[1] == 10)
        assert(l[2] == 60)
        assert(l[3] == 70)
        assert(l[4] == 80)
        assert(l[5] == 50)
    end,

    ReplaceNilStep = function()
        local l = list(10, 20, 30, 40, 50):replace(2, 4, nil, {60, 70, 80})
        assert(#l == 5)
        assert(l[1] == 10)
        assert(l[2] == 60)
        assert(l[3] == 70)
        assert(l[4] == 80)
        assert(l[5] == 50)
    end,

    ReplaceOmitStep = function()
        local l = list(10, 20, 30, 40, 50):replace(2, 4, {60, 70, 80})
        assert(#l == 5)
        assert(l[1] == 10)
        assert(l[2] == 60)
        assert(l[3] == 70)
        assert(l[4] == 80)
        assert(l[5] == 50)
    end,

    ReplaceNilEnd = function()
        local l = list(10, 20, 30, 40, 50):replace(2, nil, 1, {60, 70, 80, 90})
        assert(#l == 5)
        assert(l[1] == 10)
        assert(l[2] == 60)
        assert(l[3] == 70)
        assert(l[4] == 80)
        assert(l[5] == 90)
    end,

    ReplaceOmitEnd = function()
        local l = list(10, 20, 30, 40, 50):replace(2, {60, 70, 80, 90})
        assert(#l == 5)
        assert(l[1] == 10)
        assert(l[2] == 60)
        assert(l[3] == 70)
        assert(l[4] == 80)
        assert(l[5] == 90)
    end,

    ReplaceNilStart = function()
        local l = list(10, 20, 30, 40, 50):replace(nil, 4, 1, {60, 70, 80, 90})
        assert(#l == 5)
        assert(l[1] == 60)
        assert(l[2] == 70)
        assert(l[3] == 80)
        assert(l[4] == 90)
        assert(l[5] == 50)
    end,

    ReplaceOmitStart = function()
        local l = list(10, 20, 30, 40, 50)
        assert(l:replace({60, 70, 80, 90, 100}) == l)
        assert(#l == 5)
        assert(l[1] == 60)
        assert(l[2] == 70)
        assert(l[3] == 80)
        assert(l[4] == 90)
        assert(l[5] == 100)
    end,

    ReplaceGrowList = function()
        local l = list(10, 20, 30):replace(2, 2, {60, 70, 80})
        assert(#l == 5)
        assert(l[1] == 10)
        assert(l[2] == 60)
        assert(l[3] == 70)
        assert(l[4] == 80)
        assert(l[5] == 30)
    end,

    ReplaceShrinkList = function()
        local l = list(10, 20, 30, 40, 50):replace(2, 4, {60})
        assert(#l == 3)
        assert(l[1] == 10)
        assert(l[2] == 60)
        assert(l[3] == 50)
    end,

    ReplaceInsertElements = function()
        local l = list(10, 20, 30):replace(2, 1, {60, 70})
        assert(#l == 5)
        assert(l[1] == 10)
        assert(l[2] == 60)
        assert(l[3] == 70)
        assert(l[4] == 20)
        assert(l[5] == 30)
    end,

    ReplaceDeleteElements = function()
        local l = list(10, 20, 30, 40, 50):replace(2, 4, {})
        assert(#l == 2)
        assert(l[1] == 10)
        assert(l[2] == 50)
    end,

    DearAuntLetsSetSoDoubleTheKillerDeleteSelectAll = function()
        local l = list(10, 20, 30, 40, 50):replace({})
        assert(#l == 0)
    end,

    ReplaceEmptyBeginningOfList = function()
        local l = list(10, 20, 30):replace(1, 0, {})
        assert(#l == 3)
        assert(l[1] == 10)
        assert(l[2] == 20)
        assert(l[3] == 30)
    end,

    ReplaceInsertBeginningOfList = function()
        local l = list(10, 20, 30):replace(1, 0, {60, 70})
        assert(#l == 5)
        assert(l[1] == 60)
        assert(l[2] == 70)
        assert(l[3] == 10)
        assert(l[4] == 20)
        assert(l[5] == 30)
    end,

    ReplaceEmptyEndOfList = function()
        local l = list(10, 20, 30):replace(4, 3, {})
        assert(#l == 3)
        assert(l[1] == 10)
        assert(l[2] == 20)
        assert(l[3] == 30)
    end,

    ReplaceInsertEndOfList = function()
        local l = list(10, 20, 30):replace(4, 3, {60, 70})
        assert(#l == 5)
        assert(l[1] == 10)
        assert(l[2] == 20)
        assert(l[3] == 30)
        assert(l[4] == 60)
        assert(l[5] == 70)
    end,

    ReplaceClampEndToBeginning = function()
        local l = list(10, 20, 30):replace(2, -1, {60, 70})
        assert(#l == 5)
        assert(l[1] == 10)
        assert(l[2] == 60)
        assert(l[3] == 70)
        assert(l[4] == 20)
        assert(l[5] == 30)
    end,

    ReplaceClampEndToEnd = function()
        local l = list(10, 20, 30):replace(2, 99, {60, 70})
        assert(#l == 3)
        assert(l[1] == 10)
        assert(l[2] == 60)
        assert(l[3] == 70)
    end,

    ReplaceStepNonOne = function()
        local l = list(10, 20, 30, 40, 50):replace(2, 5, 3, {60, 70})
        assert(#l == 5)
        assert(l[1] == 10)
        assert(l[2] == 60)
        assert(l[3] == 30)
        assert(l[4] == 40)
        assert(l[5] == 70)
    end,

    ReplaceStepNonOneMisalignedEnd = function()
        local l = list(10, 20, 30, 40, 50):replace(2, 5, 2, {60, 70})
        assert(#l == 5)
        assert(l[1] == 10)
        assert(l[2] == 60)
        assert(l[3] == 30)
        assert(l[4] == 70)
        assert(l[5] == 50)
    end,

    ReplaceStepNonOneDefaultRange = function()
        local l = list(10, 20, 30, 40, 50):replace(nil, nil, 3, {60, 70})
        assert(#l == 5)
        assert(l[1] == 60)
        assert(l[2] == 20)
        assert(l[3] == 30)
        assert(l[4] == 70)
        assert(l[5] == 50)
    end,

    ReplaceStartOutOfRange = function()
        local l = list(10, 20, 30)
        local result, errmsg = pcall(function() return l:replace(5, 3, {}) end)
        assert(result == false)
        assert(errmsg:find(BAD_INDEX_MSG, 1, true), errmsg)
        assert(#l == 3)
        assert(l[1] == 10)
        assert(l[2] == 20)
        assert(l[3] == 30)
    end,

    ReplaceStartZero = function()
        local l = list(10, 20, 30)
        local result, errmsg = pcall(function() return l:replace(0, 1, {}) end)
        assert(result == false)
        assert(errmsg:find(BAD_INDEX_MSG, 1, true), errmsg)
        assert(#l == 3)
        assert(l[1] == 10)
        assert(l[2] == 20)
        assert(l[3] == 30)
    end,

    ReplaceStartNegative = function()
        local l = list(10, 20, 30)
        local result, errmsg = pcall(function() return l:replace(-1, 1, {}) end)
        assert(result == false)
        assert(errmsg:find(BAD_INDEX_MSG, 1, true), errmsg)
        assert(#l == 3)
        assert(l[1] == 10)
        assert(l[2] == 20)
        assert(l[3] == 30)
    end,

    ReplaceStartFraction = function()
        local l = list(10, 20, 30)
        local result, errmsg = pcall(function() return l:replace(1.5, 2, {}) end)
        assert(result == false)
        assert(errmsg:find(BAD_INDEX_TYPE_MSG, 1, true), errmsg)
        assert(#l == 3)
        assert(l[1] == 10)
        assert(l[2] == 20)
        assert(l[3] == 30)
    end,

    ReplaceStartNonNumber = function()
        local l = list(10, 20, 30)
        local result, errmsg = pcall(function() return l:replace("one", 2, {}) end)
        assert(result == false)
        assert(errmsg:find(BAD_INDEX_TYPE_MSG, 1, true), errmsg)
        assert(#l == 3)
        assert(l[1] == 10)
        assert(l[2] == 20)
        assert(l[3] == 30)
    end,

    ReplaceEndFraction = function()
        local l = list(10, 20, 30)
        local result, errmsg = pcall(function() return l:replace(1, 2.5, {}) end)
        assert(result == false)
        assert(errmsg:find(BAD_INDEX_TYPE_MSG, 1, true), errmsg)
        assert(#l == 3)
        assert(l[1] == 10)
        assert(l[2] == 20)
        assert(l[3] == 30)
    end,

    ReplaceEndNonNumber = function()
        local l = list(10, 20, 30)
        local result, errmsg = pcall(function() return l:replace(1, "two", {}) end)
        assert(result == false)
        assert(errmsg:find(BAD_INDEX_TYPE_MSG, 1, true), errmsg)
        assert(#l == 3)
        assert(l[1] == 10)
        assert(l[2] == 20)
        assert(l[3] == 30)
    end,

    ReplaceStepZero = function()
        local l = list(10, 20, 30)
        local result, errmsg = pcall(function() return l:replace(1, 3, 0, {}) end)
        assert(result == false)
        assert(errmsg:find(BAD_ARGUMENT_MSG, 1, true), errmsg)
        assert(#l == 3)
        assert(l[1] == 10)
        assert(l[2] == 20)
        assert(l[3] == 30)
    end,

    ReplaceStepNegative = function()
        local l = list(10, 20, 30)
        local result, errmsg = pcall(function() return l:replace(1, 3, -1, {}) end)
        assert(result == false)
        assert(errmsg:find(BAD_ARGUMENT_MSG, 1, true), errmsg)
        assert(#l == 3)
        assert(l[1] == 10)
        assert(l[2] == 20)
        assert(l[3] == 30)
    end,

    ReplaceStepFraction = function()
        local l = list(10, 20, 30)
        local result, errmsg = pcall(function() return l:replace(1, 3, 0.5, {}) end)
        assert(result == false)
        assert(errmsg:find(BAD_ARGUMENT_MSG, 1, true), errmsg)
        assert(#l == 3)
        assert(l[1] == 10)
        assert(l[2] == 20)
        assert(l[3] == 30)
    end,

    ReplaceStepNonNumber = function()
        local l = list(10, 20, 30)
        local result, errmsg = pcall(function() return l:replace(1, 3, "one", {}) end)
        assert(result == false)
        assert(errmsg:find(BAD_ARGUMENT_MSG, 1, true), errmsg)
        assert(#l == 3)
        assert(l[1] == 10)
        assert(l[2] == 20)
        assert(l[3] == 30)
    end,

    ReplaceListMissing = function()
        local l = list(10, 20, 30)
        local result, errmsg = pcall(function() return l:replace(1, 3, 1) end)
        assert(result == false)
        assert(errmsg:find(NOT_LIST_MSG, 1, true), errmsg)
        assert(#l == 3)
        assert(l[1] == 10)
        assert(l[2] == 20)
        assert(l[3] == 30)
    end,

    ReplaceListWrongType = function()
        local l = list(10, 20, 30)
        local result, errmsg = pcall(function() return l:replace(1, 3, 1, 99) end)
        assert(result == false)
        assert(errmsg:find(NOT_LIST_MSG, 1, true), errmsg)
        assert(#l == 3)
        assert(l[1] == 10)
        assert(l[2] == 20)
        assert(l[3] == 30)
    end,

    ReplaceStepNonOneListTooLong = function()
        local l = list(10, 20, 30, 40, 50)
        local result, errmsg = pcall(function() return l:replace(2, 5, 3, {60, 70, 80}) end)
        assert(result == false)
        assert(errmsg:find(REPLACE_SIZE_MSG, 1, true), errmsg)
        assert(#l == 5)
        assert(l[1] == 10)
        assert(l[2] == 20)
        assert(l[3] == 30)
        assert(l[4] == 40)
        assert(l[5] == 50)
    end,

    ReplaceStepNonOneListTooShort = function()
        local l = list(10, 20, 30, 40, 50)
        local result, errmsg = pcall(function() return l:replace(2, 5, 3, {60}) end)
        assert(result == false)
        assert(errmsg:find(REPLACE_SIZE_MSG, 1, true), errmsg)
        assert(#l == 5)
        assert(l[1] == 10)
        assert(l[2] == 20)
        assert(l[3] == 30)
        assert(l[4] == 40)
        assert(l[5] == 50)
    end,

    -------- reverse()

    ReverseOddLength = function()
        local l = list(30, 10, 20)
        assert(l:reverse() == l)
        assert(#l == 3)
        assert(l[1] == 20)
        assert(l[2] == 10)
        assert(l[3] == 30)
    end,

    ReverseEvenLength = function()
        local l = list(30, 10, 40, 20)
        assert(l:reverse() == l)
        assert(#l == 4)
        assert(l[1] == 20)
        assert(l[2] == 40)
        assert(l[3] == 10)
        assert(l[4] == 30)
    end,

    ReverseSingleElement = function()
        local l = list(10)
        assert(l:reverse() == l)
        assert(#l == 1)
        assert(l[1] == 10)
    end,

    ReverseEmpty = function()
        local l = list()
        assert(l:reverse() == l)
        assert(#l == 0)
    end,

    -------- slice()

    Slice = function()
        local l1 = list(10, 20, 30, 40, 50)
        local l2 = l1:slice(2, 4, 1)
        assert(#l2 == 3)
        assert(l2[1] == 20)
        assert(l2[2] == 30)
        assert(l2[3] == 40)
        -- l1 should be unmodified.
        assert(#l1 == 5)
        assert(l1[1] == 10)
        assert(l1[2] == 20)
        assert(l1[3] == 30)
        assert(l1[4] == 40)
        assert(l1[5] == 50)
    end,

    SliceWholeList = function()
        local l1 = list(10, 20, 30, 40, 50)
        local l2 = l1:slice(1, 5, 1)
        assert(l2 ~= l1)  -- It should still be a new copy.
        assert(#l2 == 5)
        assert(l2[1] == 10)
        assert(l2[2] == 20)
        assert(l2[3] == 30)
        assert(l2[4] == 40)
        assert(l2[5] == 50)
    end,

    SliceSingleElement = function()
        local l = list(10, 20, 30):slice(2, 2, 1)
        assert(#l == 1)
        assert(l[1] == 20)
    end,

    SliceEmpty = function()
        local l = list(10, 20, 30):slice(2, 1, 1)
        assert(#l == 0)
    end,

    SliceNilStep = function()
        local l1 = list(10, 20, 30, 40, 50)
        local l2 = l1:slice(2, 4, nil)
        assert(#l2 == 3)
        assert(l2[1] == 20)
        assert(l2[2] == 30)
        assert(l2[3] == 40)
    end,

    SliceOmitStep = function()
        local l1 = list(10, 20, 30, 40, 50)
        local l2 = l1:slice(2, 4)
        assert(#l2 == 3)
        assert(l2[1] == 20)
        assert(l2[2] == 30)
        assert(l2[3] == 40)
    end,

    SliceNilEnd = function()
        local l1 = list(10, 20, 30, 40, 50)
        local l2 = l1:slice(2, nil, 1)
        assert(#l2 == 4)
        assert(l2[1] == 20)
        assert(l2[2] == 30)
        assert(l2[3] == 40)
        assert(l2[4] == 50)
    end,

    SliceOmitEnd = function()
        local l1 = list(10, 20, 30, 40, 50)
        local l2 = l1:slice(2)
        assert(#l2 == 4)
        assert(l2[1] == 20)
        assert(l2[2] == 30)
        assert(l2[3] == 40)
        assert(l2[4] == 50)
    end,

    SliceNilStart = function()
        local l1 = list(10, 20, 30, 40, 50)
        local l2 = l1:slice(nil, 4, 1)
        assert(#l2 == 4)
        assert(l2[1] == 10)
        assert(l2[2] == 20)
        assert(l2[3] == 30)
        assert(l2[4] == 40)
    end,

    SliceOmitStart = function()
        local l1 = list(10, 20, 30, 40, 50)
        local l2 = l1:slice()
        assert(l2 ~= l1)  -- It should still be a new copy.
        assert(#l2 == 5)
        assert(l2[1] == 10)
        assert(l2[2] == 20)
        assert(l2[3] == 30)
        assert(l2[4] == 40)
        assert(l2[5] == 50)
    end,

    SliceEmptyBeginningOfList = function()
        local l = list(10, 20, 30):slice(1, 0)
        assert(#l == 0)
    end,

    SliceEmptyEndOfList = function()
        local l = list(10, 20, 30):slice(4, 3)
        assert(#l == 0)
    end,

    SliceClampEndToBeginning = function()
        local l = list(10, 20, 30):slice(2, -1)
        assert(#l == 0)
    end,

    SliceClampEndToEnd = function()
        local l = list(10, 20, 30):slice(2, 99)
        assert(#l == 2)
        assert(l[1] == 20)
        assert(l[2] == 30)
    end,

    SliceStepNonOne = function()
        local l = list(10, 20, 30, 40, 50):slice(2, 5, 3)
        assert(#l == 2)
        assert(l[1] == 20)
        assert(l[2] == 50)
    end,

    SliceStepNonOneMisalignedEnd = function()
        local l = list(10, 20, 30, 40, 50):slice(2, 5, 2)
        assert(#l == 2)
        assert(l[1] == 20)
        assert(l[2] == 40)
    end,

    SliceStepNonOneDefaultRange = function()
        local l = list(10, 20, 30, 40, 50):slice(nil, nil, 3)
        assert(#l == 2)
        assert(l[1] == 10)
        assert(l[2] == 40)
    end,

    SliceStartOutOfRange = function()
        local l = list(10, 20, 30)
        local result, errmsg = pcall(function() return l:slice(5, 3) end)
        assert(result == false)
        assert(errmsg:find(BAD_INDEX_MSG, 1, true), errmsg)
    end,

    SliceStartZero = function()
        local l = list(10, 20, 30)
        local result, errmsg = pcall(function() return l:slice(0, 1) end)
        assert(result == false)
        assert(errmsg:find(BAD_INDEX_MSG, 1, true), errmsg)
    end,

    SliceStartNegative = function()
        local l = list(10, 20, 30)
        local result, errmsg = pcall(function() return l:slice(-1, 1) end)
        assert(result == false)
        assert(errmsg:find(BAD_INDEX_MSG, 1, true), errmsg)
    end,

    SliceStartFraction = function()
        local l = list(10, 20, 30)
        local result, errmsg = pcall(function() return l:slice(1.5, 2) end)
        assert(result == false)
        assert(errmsg:find(BAD_INDEX_TYPE_MSG, 1, true), errmsg)
    end,

    SliceStartNonNumber = function()
        local l = list(10, 20, 30)
        local result, errmsg = pcall(function() return l:slice("one", 2) end)
        assert(result == false)
        assert(errmsg:find(BAD_INDEX_TYPE_MSG, 1, true), errmsg)
    end,

    SliceEndFraction = function()
        local l = list(10, 20, 30)
        local result, errmsg = pcall(function() return l:slice(1, 2.5) end)
        assert(result == false)
        assert(errmsg:find(BAD_INDEX_TYPE_MSG, 1, true), errmsg)
    end,

    SliceEndNonNumber = function()
        local l = list(10, 20, 30)
        local result, errmsg = pcall(function() return l:slice(1, "two") end)
        assert(result == false)
        assert(errmsg:find(BAD_INDEX_TYPE_MSG, 1, true), errmsg)
    end,

    SliceStepZero = function()
        local l = list(10, 20, 30)
        local result, errmsg = pcall(function() return l:slice(1, 3, 0) end)
        assert(result == false)
        assert(errmsg:find(BAD_ARGUMENT_MSG, 1, true), errmsg)
    end,

    SliceStepNegative = function()
        local l = list(10, 20, 30)
        local result, errmsg = pcall(function() return l:slice(1, 3, -1) end)
        assert(result == false)
        assert(errmsg:find(BAD_ARGUMENT_MSG, 1, true), errmsg)
    end,

    SliceStepFraction = function()
        local l = list(10, 20, 30)
        local result, errmsg = pcall(function() return l:slice(1, 3, 0.5) end)
        assert(result == false)
        assert(errmsg:find(BAD_ARGUMENT_MSG, 1, true), errmsg)
    end,

    SliceStepNonNumber = function()
        local l = list(10, 20, 30)
        local result, errmsg = pcall(function() return l:slice(1, 3, "one") end)
        assert(result == false)
        assert(errmsg:find(BAD_ARGUMENT_MSG, 1, true), errmsg)
    end,

    -------- sort()

    Sort = function()
        local l = list(30, 10, 20, 50, 40)
        assert(l:sort() == l)
        assert(#l == 5)
        assert(l[1] == 10)
        assert(l[2] == 20)
        assert(l[3] == 30)
        assert(l[4] == 40)
        assert(l[5] == 50)
    end,

    SortSingleElement = function()
        local l = list(10)
        assert(l:sort() == l)
        assert(#l == 1)
        assert(l[1] == 10)
    end,

    SortEmpty = function()
        local l = list()
        assert(l:sort() == l)
        assert(#l == 0)
    end,

    SortComparator = function()
        local l = list(30, 10, 20, 50, 40)
        local function gt(a, b) return a > b end
        assert(l:sort(gt) == l)
        assert(#l == 5)
        assert(l[1] == 50)
        assert(l[2] == 40)
        assert(l[3] == 30)
        assert(l[4] == 20)
        assert(l[5] == 10)
    end,

    SortExplicitDefaultComparator = function()
        local l = list(30, 10, 20, 50, 40)
        assert(l:sort(nil) == l)
        assert(#l == 5)
        assert(l[1] == 10)
        assert(l[2] == 20)
        assert(l[3] == 30)
        assert(l[4] == 40)
        assert(l[5] == 50)
    end,

    -------- + operator

    AddOperator = function()
        local l1 = list(10)
        local l2 = list(20)
        local l3 = l1 + l2
        assert(l3 ~= l1)
        assert(l3 ~= l2)
        assert(#l3 == 2)
        assert(l3[1] == 10)
        assert(l3[2] == 20)
        -- l1 and l2 should be unmodified.
        assert(#l1 == 1)
        assert(l1[1] == 10)
        assert(#l2 == 1)
        assert(l2[1] == 20)
    end,

    AddOperatorFirstEmpty = function()
        local l1 = list()
        local l2 = list(20)
        local l3 = l1 + l2
        assert(l3 ~= l1)
        assert(l3 ~= l2)
        assert(#l3 == 1)
        assert(l3[1] == 20)
        assert(#l1 == 0)
        assert(#l2 == 1)
        assert(l2[1] == 20)
    end,

    AddOperatorSecondEmpty = function()
        local l1 = list(10)
        local l2 = list()
        local l3 = l1 + l2
        assert(l3 ~= l1)
        assert(l3 ~= l2)
        assert(#l3 == 1)
        assert(l3[1] == 10)
        assert(#l1 == 1)
        assert(l1[1] == 10)
        assert(#l2 == 0)
    end,

    AddOperatorBothEmpty = function()
        local l1 = list()
        local l2 = list()
        local l3 = l1 + l2
        assert(l3 ~= l1)
        assert(l3 ~= l2)
        assert(#l3 == 0)
        assert(#l1 == 0)
        assert(#l2 == 0)
    end,

    AddOperatorMultipleElements = function()
        local l = list(10, 30) + list(20, 40, 60)
        assert(#l == 5)
        assert(l[1] == 10)
        assert(l[2] == 30)
        assert(l[3] == 20)
        assert(l[4] == 40)
        assert(l[5] == 60)
    end,

    AddOperatorFirstPlainTable = function()
        local l = {10, 30} + list(20, 40, 60)
        assert(#l == 5)
        assert(l[1] == 10)
        assert(l[2] == 30)
        assert(l[3] == 20)
        assert(l[4] == 40)
        assert(l[5] == 60)
    end,

    AddOperatorSecondPlainTable = function()
        local l = list(10, 30) + {20, 40, 60}
        assert(#l == 5)
        assert(l[1] == 10)
        assert(l[2] == 30)
        assert(l[3] == 20)
        assert(l[4] == 40)
        assert(l[5] == 60)
    end,

    -------- * operator

    MulOperator = function()
        local l1 = list(10, 20)
        local l2 = l1 * 3
        assert(l2 ~= l1)
        assert(#l2 == 6)
        assert(l2[1] == 10)
        assert(l2[2] == 20)
        assert(l2[3] == 10)
        assert(l2[4] == 20)
        assert(l2[5] == 10)
        assert(l2[6] == 20)
        -- l1 should be unmodified.
        assert(#l1 == 2)
        assert(l1[1] == 10)
        assert(l1[2] == 20)
    end,

    MulOperatorNumberFirst = function()
        local l1 = list(10, 20)
        local l2 = 3 * l1
        assert(l2 ~= l1)
        assert(#l2 == 6)
        assert(l2[1] == 10)
        assert(l2[2] == 20)
        assert(l2[3] == 10)
        assert(l2[4] == 20)
        assert(l2[5] == 10)
        assert(l2[6] == 20)
        assert(#l1 == 2)
        assert(l1[1] == 10)
        assert(l1[2] == 20)
    end,

    MulOperatorOne = function()
        local l1 = list(10, 20)
        local l2 = l1 * 1
        assert(l2 ~= l1)
        assert(#l2 == 2)
        assert(l2[1] == 10)
        assert(l2[2] == 20)
        assert(#l1 == 2)
        assert(l1[1] == 10)
        assert(l1[2] == 20)
    end,

    MulOperatorZero = function()
        local l1 = list(10, 20)
        local l2 = l1 * 0
        assert(l2 ~= l1)
        assert(#l2 == 0)
        assert(#l1 == 2)
        assert(l1[1] == 10)
        assert(l1[2] == 20)
    end,

    MulOperatorNegative = function()
        local l1 = list(10, 20)
        local l2 = l1 * -1
        assert(l2 ~= l1)
        assert(#l2 == 0)
        assert(#l1 == 2)
        assert(l1[1] == 10)
        assert(l1[2] == 20)
    end,

    MulOperatorFraction = function()
        local l1 = list(10, 20)
        local l2 = l1 * 2.9  -- Should be truncated to 2.
        assert(l2 ~= l1)
        assert(#l2 == 4)
        assert(l2[1] == 10)
        assert(l2[2] == 20)
        assert(l2[3] == 10)
        assert(l2[4] == 20)
        assert(#l1 == 2)
        assert(l1[1] == 10)
        assert(l1[2] == 20)
    end,

    MulOperatorNonNumber = function()
        local l1 = list(10, 20)
        local result, errmsg = pcall(function() return l1 * "two" end)
        assert(result == false)
        assert(errmsg:find(BAD_MUL_MSG, 1, true), errmsg)
        assert(#l1 == 2)
        assert(l1[1] == 10)
        assert(l1[2] == 20)
    end,

    MulOperatorTableElement = function()
        local t = {10, 20}
        local l1 = list(t)
        local l2 = l1 * 3
        assert(l2 ~= l1)
        assert(#l2 == 3)
        assert(l2[1] == t)
        assert(l2[2] == t)
        assert(l2[3] == t)
        -- They're all the same table instance, so modifying a value in one
        -- should be reflected in the others.
        t[2] = 40
        assert(l2[1][2] == 40)
        assert(l2[2][2] == 40)
        assert(l2[3][2] == 40)
    end,

    -------- Iteration

    Iterate = function()
        local l = list(10, 20, 30)
        local i = 0
        for x in l do
            i = i+1
            assert(x == l[i])
        end
        assert(i == 3)
    end,

    IterateSingle = function()
        local i = 0
        for x in list(10) do
            i = i+1
            assert(i == 1)
            assert(x == 10)
        end
        assert(i == 1)
    end,

    IterateEmpty = function()
        for x in list() do
            assert(false)
        end
    end,

}

function module.listTests(verbose)
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
