local module_name, WoWXIV = ...
local STANDALONE  -- for tests (only included when run standalone)
if not WoWXIV then
    STANDALONE = true
    WoWXIV = {class = require("_class").class, set = require("_set").set}
    assert(not Enum)
    Enum =
        {InventoryType = setmetatable({}, {__index = function() return 0 end})}
end

local class = WoWXIV.class
local set = WoWXIV.set

local max = math.max
local strfind = string.find
local strlen = string.len
local strstr = function(s1,s2,pos) return strfind(s1,s2,pos,true) end
local tinsert = table.insert
local tremove = table.remove

local FCT = function(...)
    FCT = WoWXIV.FormatColoredText
    return FCT(...)
end
local function Red(s)    return FCT(s, RED_FONT_COLOR:GetRGB())    end
local function Yellow(s) return FCT(s, YELLOW_FONT_COLOR:GetRGB()) end

-- Currently set conditions for each bag.
local bag_conditions = {}

-- Currently running sort operation (BagSorter instance), nil if none.
local running_sort = nil

-- Default conditions for isort_execute() if none are given by the caller.
-- These more or less mimic what WoW's own "clean up bags" does.  Note that
-- WoW's default is either unstable or poorly defined, since e.g. reagents
-- within a single category/expansion can end up unordered with respect to
-- quality and item ID.
local DEFAULT_SORT_CONDITIONS = {
    {"id", "descending"},
    {"quality", "descending"},
    {"expansion", "descending"},
    {"itemlevel", "descending"},
    {"category", "ascending"},
}

--------------------------------------------------------------------------
-- Item comparators
--------------------------------------------------------------------------

-- Table of item comparators, indexed by sort type.  Each comparator is
-- passed a pair of tables containing the following keys:
--     id: Item ID
--     stack: Stack count (1 for non-stackable items)
--     expansion: Expansion ID (LE_EXPANSION_*)
--     class: Item class ID (Enum.ItemClass)
--     subclass: Item subclass ID (Enum.Item*Subclass)
--     equiploc: Item equipment location (Enum.InventoryType)
--     quality: Item quality ID (Enum.ItemQuality)
--     craftquality: Crafted item / reagent quality (1-5, 0 if not applicable)
--     itemlevel: Item level (0 if not applicable)
-- and should return -1 if the first item compares less than, 0 if equal to,
-- and 1 if greater than the second (like C strcmp()).

local ITEM_COMPARATORS = {}

function ITEM_COMPARATORS.id(a, b)
    return a.id < b.id and -1 or a.id > b.id and 1 or 0
end

function ITEM_COMPARATORS.stack(a, b)
    return a.stack < b.stack and -1 or a.stack > b.stack and 1 or 0
end

function ITEM_COMPARATORS.expansion(a, b)
    return a.expansion < b.expansion and -1 or
           a.expansion > b.expansion and 1 or 0
end

-- Sort armor equipment location by character frame slot position.
local EQUIPLOC_ORDER = {
    [Enum.InventoryType.IndexHeadType] = 1,
    [Enum.InventoryType.IndexNeckType] = 2,
    [Enum.InventoryType.IndexShoulderType] = 3,
    [Enum.InventoryType.IndexCloakType] = 4,
    [Enum.InventoryType.IndexChestType] = 5,
    [Enum.InventoryType.IndexBodyType] = 6,
    [Enum.InventoryType.IndexTabardType] = 7,
    [Enum.InventoryType.IndexWristType] = 8,
    [Enum.InventoryType.IndexHandType] = 9,
    [Enum.InventoryType.IndexWaistType] = 10,
    [Enum.InventoryType.IndexLegsType] = 11,
    [Enum.InventoryType.IndexFeetType] = 12,
    [Enum.InventoryType.IndexFingerType] = 13,
    [Enum.InventoryType.IndexTrinketType] = 14,
    [Enum.InventoryType.IndexWeaponType] = 15,
    [Enum.InventoryType.IndexWeaponmainhandType] = 16,
    [Enum.InventoryType.Index2HweaponType] = 17,
    [Enum.InventoryType.IndexWeaponoffhandType] = 18,
    [Enum.InventoryType.IndexHoldableType] = 19,
    [Enum.InventoryType.IndexShieldType] = 20,
    [Enum.InventoryType.IndexProfessionToolType] = 21,
    [Enum.InventoryType.IndexProfessionGearType] = 22,
}
function ITEM_COMPARATORS.category(a, b)
    if a.class < b.class then return -1 end
    if a.class > b.class then return 1 end
    if a.class == Enum.ItemClass.Armor then
        -- Sort armor equip location over armor subtype.
        local a_equip = EQUIPLOC_ORDER[a.equiploc] or 999
        local b_equip = EQUIPLOC_ORDER[b.equiploc] or 999
        if a_equip < b_equip then return -1 end
        if a_equip > b_equip then return 1 end
    elseif a.class == Enum.ItemClass.Tradegoods then
        -- Sort crafting reagent subcategories in reverse order to match
        -- native sort behavior.
        return a.subclass > b.subclass and -1 or
               a.subclass < b.subclass and 1 or 0
    end
    return a.subclass < b.subclass and -1 or a.subclass > b.subclass and 1 or 0
end

function ITEM_COMPARATORS.quality(a, b)
    return a.quality < b.quality and -1 or a.quality > b.quality and 1 or 0
end

function ITEM_COMPARATORS.craftquality(a, b)
    return a.craftquality < b.craftquality and -1 or
           a.craftquality > b.craftquality and 1 or 0
end

function ITEM_COMPARATORS.itemlevel(a, b)
    return a.itemlevel < b.itemlevel and -1 or
           a.itemlevel > b.itemlevel and 1 or 0
end

--------------------------------------------------------------------------
-- Helper routines
--------------------------------------------------------------------------

-- Return data for the item at the given bag and slot suitable for passing
-- to item comparators, or nil if there is no item at that location.
local function GetItemData(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info then return nil end
    local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
    local iteminfo = {C_Item.GetItemInfo(info.itemID)}
    local craftquality =
        C_TradeSkillUI.GetItemReagentQualityByItemInfo(info.itemID) or 0
    return {id = info.itemID,
            name = info.itemName,
            stack = info.stackCount,
            expansion = iteminfo[15],
            class = iteminfo[12],
            subclass = iteminfo[13],
            equiploc = C_Item.GetItemInventoryTypeByID(info.itemID),
            quality = info.quality,
            craftquality = craftquality,
            itemlevel = C_Item.GetCurrentItemLevel(loc) or 0}
end

-- Generate a function to compare items using the given comparator function
-- (one of ITEM_COMPARATORS.*) and direction (1 = ascending, -1 = descending).
-- Returns a comparator function for table.sort().
local function CompareItems(comparator, direction)
    -- table.sort() expects a comparator implementing the "less-than"
    -- operation, which will be true if our comparator's result is the
    -- opposite sign of the sort direction.
    local ndir = -direction
    return function(a, b)
        local result = comparator(a, b)
        if result == ndir then
            return true
        elseif result ~= 0 then
            return false
        else  -- Items compare equal, preserve current order.
            return a.index < b.index
        end
    end
end

-- Return a comparator/direction pair for the given condition/direction
-- keywords, or (nil, nil) and an error message for invalid input.
local function ParseCondition(condition, direction)
    local comparator = ITEM_COMPARATORS[condition]
    if not comparator then
        return nil, nil, "Invalid condition word"
    end
    if strsub("ascending", 1, strlen(direction)) == direction then
        direction = 1
    elseif strsub("descending", 1, strlen(direction)) == direction then
        direction = -1
    else
        return nil, nil, "Invalid sort direction"
    end
    return comparator, direction
end

--------------------------------------------------------------------------
-- Core logic
--------------------------------------------------------------------------

-- Tail-recursive implementation of FindMoves().
-- slot_map maps slots to their target positions; slot_map[i]==j means
-- "the item currently in slot |i| needs to move to slot |j|".  Nil values
-- indicate currently empty slots.
local function FindMovesImpl(size, slot_map, moves)
    --[[
    Our ultimate goal is to to select a sequence of moves (swaps of bag
    slot pairs) which will transform the current bag order into the
    desired final order in minimal time.  Under WoW's system, this is not
    necessarily the smallest number of individual moves: we can perform
    swaps of independent slots more or less simultaneously, but we have to
    wait for one operation on any given slot to complete (that is, for the
    server to report to the client that the slot is unlocked and available
    for use) before we can perform another operation on that slot.  So
    effectively, we want to find the smallest number of _batches_ of moves
    we can make to complete the desired transformation.

    If there are empty slots in the bag to be sorted, we can make use of
    those to reduce the number of move batches.  For example, given a bag
    of five items A,B,C,D,E which we want to sort as B,C,D,E,A, if we have
    only those five slots to work with, we need a minimum of three batches
    to solve the transformation, such as:
       (1) A/B, C/D (-> B,A,D,C,E)
       (2) A/E      (-> B,E,D,C,A)
       (3) C/E      (-> B,C,D,E,A)
    But if we also have five empty slots (A,B,C,D,E,_,_,_,_,_), we can
    trivially solve in two batches, which will be faster(*) despite using
    2.5x the number of individual moves:
       (1) A/6, B/7, C/8, D/9, E/10 (_,_,_,_,_,A,B,C,D,E)
       (2) B/1, C/2, D/3, E/4, A/5  (B,C,D,E,A,_,_,_,_,_)
    (*) This may not be perfectly true in practice due to server load; for
    example, a large set of moves in a single batch may end up "smeared"
    across a longer timespan rather than executed all at once.  But it
    seems to be mostly true most of the time, so we accept it as a
    simplifying assumption.

    Because WoW does not fundamentally place any restriction on moving
    items between bags, we could potentially even make use of empty slots
    in other bags, but as a design choice we restrict ourselves to working
    within the specified bag so that if the operation is interrupted, all
    items originally in the bag can still be found in that bag.

    We start out by pruning trivial transformations:
       (A) Any slot whose target is itself requires no move. (A -> A)
       (B) Any slot whose target's target is itself is solved by a swap
           with its target. (A,B -> B,A)
       (C) Any slot whose target is an empty slot and which itself is
           empty in the final bag order is solved by a swap with that
           empty slot. (A,_ -> _,A)

    If this pruning leaves only empty slots, the transformation is
    complete, and we return the set of moves generated by rules (B) and
    (C), if any.  Otherwise, we take all remaining (non-empty) slots and
    build a directed graph from current to final slot positions.  This
    graph will contain one or more disjoint subgraphs in which no node has
    an edge to itself (eliminated by case (A) above) and no two nodes have
    two edges between them (cases (B) and (C)).  Note that this graph is
    not necessarily complete in the sense of including all required slot
    movements, since it does not include resolution of slots which change
    from filled to empty; we leave those for later, to allow flexibility
    in the choice of source slot (since all empty slots are equivalent).

    Next, we distribute the bag's "empty slot pool" (empty slots to which
    case (C) did not apply) to the sets of slots corresponding to each
    subgraph.  We have to be careful here, though: injudicious use of free
    slots can actually increase the batch count!  Consider the case of a
    7-slot bag with 4 slots in a cycle and 3 empty slots: "B,C,D,A,_,_,_"
    with a target of "A,B,C,D,_,_,_".  It may seem tempting to move three
    of the items to the free slots in the first pass, giving something
    like "_,_,_,A,B,C,D".  But this is a trap: at least one item (either
    "D" or "A" in this case) will collide with another move operation and
    thus not be able to move to its target slot in the next pass,
    requiring a third pass to reach the target state.  We could have
    instead completed this transformation in just two passes without using
    any free slots: "B,C,D,A" -> "C,B,A,D" -> "A,B,C,D".

    There are three cases in which use of free slots will reduce batch
    count:

    (D) When the subgraph's log-2 order (the base-2 logarithm of the
        number of nodes in the subgraph, rounded up) is greater than 2,
        thus implying it will take more than 2 passes to resolve, and we
        can move _every_ item in the subgraph to an empty slot (whether a
        free slot or the empty slot ending an acyclic chain), as in the
        example described above.  Doing this eliminates the subgraph
        completely and converts every item in the subgraph to a trivial
        case (C) in the next pass.

    (E) When the subgraph's chain is not a cycle, its log-2 order is
        greater than 2, and we have enough free slots to reduce the log-2
        order to the next integer boundary.  A minimal example is a 6-slot
        bag "_,A,B,C,D,_" with target order "A,B,C,D,_,_" (every item
        moving one slot to the left), which has a single subgraph of 5
        nodes (log-2 order 3) and one free slot.  A log-2 order 3 chain
        ordinarily requires 3 passes to resolve, but by inserting a move
        of B to the free slot, we break A out of the chain, effectively
        converting it to a trivial case (C) and leaving a 4-node chain
        "_,B,C,D".  This state can be resolved in 2 passes: "_,A,B,C,D,_"
        -> "A,_,_,D,C,B" -> "A,B,C,D,_,_".  The free slot substitutes for
        A's original slot during this first pass when considering B's
        target slot, thus avoiding the slot collision discussed above.

    (F) When the subgraph's chain _is_ a cycle, its log-2 order is greater
        than 3, and we have at least 4 more slots than needed to reduce
        the log-2 order to the next integer boundary.  This case is
        significantly more restrictive in its requirements because to
        break the cycle, we must insert an extra node into the chain,
        adding more work for the next cycle, and we need enough free slots
        to recover that added work.  A minimum applicable example would be
        a 14-slot bag "B,C,D,E,F,G,H,I,A,_,_,_,_,_", with a 9-slot cycle
        (log-2 order 4) and 5 free slots.  By moving 5 items into the free
        slots and swapping the two pairs that remain, we get
        "_,_,_,_,_,H,G,A,I,B,C,D,E,F", with 2 trivial case (A) items (G
        and I), 4 trivial case (C) items (B through E), and the 4-slot
        (log-2 order 2) chain "_,A,H,F" which can be resolved in 2 more
        cycles.  By contrast, if we had one fewer slot available, the
        next pass would have a 5-slot chain, requiring 3 more passes to
        complete and not saving any time over a straightforward
        resolution of the original 9-slot cycle.

    We loop over all subgraphs, determining which (if any) of the above
    cases apply and how many free slots are required, then assign slots
    from the empty slot pool to satisfy those requirements to the degree
    possible.

    Once empty slots have been assigned, we generate moves to transform
    each subgraph into a state closer to its desired target, depending
    on which of the cases above applied:

    - For case (D), all items are moved to the allocated free slots, and
      no further work is needed.

    - For case (E), the item targeting the empty slot at the end of the
      chain is moved to its target, and starting from that item's parent
      (the item targeting its own slot), items are moved to allocated free
      slots until the free slots are exhausted.  All items moved are
      removed from the subgraph, and remaining items are swapped pairwise
      as for the default case below.

    - For case (F), an arbitrary item and its parents are moved to
      allocated free slots until the free slots are exhausted, and
      removed from the subgraph.  Remaining items are swapped pairwise as
      for the default case below.

    - For all other cases, starting from the empty slot at the end of an
      acyclic chain or an arbitrary slot in a cycle, each slot is swapped
      with its parent and both nodes are removed from the chain, until
      fewer than two nodes remain.

    We now have a set of moves which brings the bag closer to its desired
    target state; progress per pass will vary, especially when free slots
    are used, but on average, at least half of the unresolved slots are
    resolved in each pass.  We apply all moves generated during this
    iteration of the algorithm to the current state, run the algorithm
    again with that updated state, and return the concatenation of this
    iteration's moves with the result of the next iteration (which may
    invoke yet another iteration, and so on until all slots have reached
    their target positions).
    ]]--

    -- Save the position of the first move we'll generate, so we can
    -- apply generated moves to slot_map if we need further passes.
    local first_move = #moves + 1

    -- Generate an inverse mapping from targets to sources.
    -- We could potentially update this on the fly along with slot_map,
    -- but it's probably not worth the added complexity compared to
    -- just regenerating it on each pass.
    local inverse_map = {}
    for from, to in pairs(slot_map) do
        assert(not inverse_map[to])
        inverse_map[to] = from
    end

    -- Prune trivial transformations, and record whether non-pruned slots
    -- are filled or empty.
    local seen, empty, left = set(), set(), set()
    for i = 1, size do
        if seen:has(i) then
            -- Already resolved.
        elseif not slot_map[i] then
            -- Empty slot, record for later.
            empty:add(i)
        elseif slot_map[i] == i then
            -- Case (A), nothing to do.
        elseif slot_map[slot_map[i]] == i then
            -- Case (B), swap with slot_map.
            tinsert(moves, {i, slot_map[i]})
            seen:add(slot_map[i])  -- Don't try to swap twice!
            left:discard(slot_map[i])  -- In case we already saw it.
        elseif not slot_map[slot_map[i]] and not inverse_map[i] then
            -- Case (C), swap with empty slot.
            tinsert(moves, {i, slot_map[i]})
            seen:add(slot_map[i])
            empty:discard(slot_map[i])
        else
            -- Nontrivial case, set aside for later.
            left:add(i)
        end
    end
    if left:len() == 0 then
        return moves  -- All done!
    end

    -- Collect disjoint subgraphs of remaining slots.  Each entry here is
    -- a table with the following fields:
    --     slot_set: Set containing all filled slots in the subgraph.
    --     chain_start: Beginning of this subgraph's chain.
    --     chain_end: End of this subgraph's chain; if the subgraph has
    --         an empty slot, chain_end is that empty slot.
    --     empty_type: Empty slot resolution type; one of "D", "E", or "F"
    --         as documented above.  (For convenience, we record type (D)
    --         as "D_cycle" or "D_chain" depending on the subgraph type.)
    --     empty_set: Set containing slots from the bag's empty slot pool
    --         (thus not including any empty slot which is part of the
    --         subgraph itself) which can be freely used as move targets.
    local subgraphs = {}
    for source in left do
        local target = slot_map[source]
        -- There are four possibilities here:
        -- (1) Neither source nor target slot have been seen yet.
        --     We create a new subgraph and add both to it.
        -- (2) Target has already been seen as a source, source is unknown.
        --     We add the source slot to the target's subgraph and set the
        --     subgraph's |chain_start| to the source slot.
        -- (3) Source has already been seen as a target, target is unknown.
        --     We add the target slot to the source's subgraph and set the
        --     subgraph's |chain_end| to the target slot.
        -- (4) Target seen as a source, source also seen as a target.
        --     We merge the source's subgraph into the target's, unless
        --     both are the same, in which case this edge completes a cycle.
        local source_sg, target_sg, source_sg_index
        for i, sg in ipairs(subgraphs) do
            if sg.slot_set:has(source) then
                source_sg_index, source_sg = i, sg
            end
            if sg.slot_set:has(target) then
                target_sg = sg
            end
        end
        if not source_sg and not target_sg then  -- case 1
            local sg = {slot_set = set(source), empty_set = set(),
                        chain_start = source, chain_end = target}
            sg.slot_set:add(target)
            if not slot_map[target] then
                empty:remove(target)
            end
            tinsert(subgraphs, sg)
        elseif not source_sg then  -- case 2
            target_sg.slot_set:add(source)
            target_sg.chain_start = source
        elseif not target_sg then  -- case 3
            source_sg.slot_set:add(target)
            if not slot_map[target] then
                empty:remove(target)
            end
            source_sg.chain_end = target
        else  -- case 4
            -- If this edge completes a cycle, we leave the subgraph's
            -- chain endpoints alone to give us a starting point for
            -- move generation below.
            if source_sg ~= target_sg then
                target_sg.slot_set:update(source_sg.slot_set)
                target_sg.chain_start = source_sg.chain_start
                tremove(subgraphs, source_sg_index)
            end
        end
    end
    assert(#subgraphs > 0)  -- Must be true if we had any unresolved slots.

    -- Distribute available empty slots to subgraphs.  For simplicity, we
    -- start from the largest subgraph and assign as many free slots as
    -- possible, then progress to smaller subgraphs until either we run out
    -- of free slots or there's nowhere else to use them.  This may miss
    -- some possible optimizations, but should be reasonable for most cases.
    for _, sg in ipairs(subgraphs) do
        sg.empty_set = set()
        sg.size = sg.slot_set:len()
    end
    table.sort(subgraphs, function(a, b) return a.size > b.size end)
    for _, sg in ipairs(subgraphs) do
        if sg.size <= 4 then
            break  -- Everything else is log-2 order 2 or less, so we're done.
        end
        local needed = {}  -- Possible configurations in order of preference.
        if slot_map[sg.chain_end] then  -- Cycle, can be case (D) or (F).
            tinsert(needed, {"D_cycle", sg.size})
            local target = 8
            while sg.size > target do
                tinsert(needed, {"F", sg.size - target + 4})
                target = target*2
            end
        else  -- Acyclic chain ending in an empty slot, can be case (D) or (E).
            -- For type (D) we can save 3 slots in total over the cycle logic:
            --    - 1 because the end of the chain is an empty slot.
            --    - 1 because the last item in the chain will move to that
            --          empty slot.
            --    - 1 because the first item in the chain is already in a
            --          free slot (one which will become empty later).
            tinsert(needed, {"D_chain", sg.size - 3})
            local target = 4
            while sg.size > target do
                tinsert(needed, {"E", sg.size - target})
                target = target*2
            end
        end
        for _, entry in ipairs(needed) do
            local type, num = unpack(entry)
            if empty:len() >= num then
                sg.empty_type = type
                for i = 1, num do
                    sg.empty_set:add(empty:pop())
                end
                break
            end
        end
    end

    -- Generate moves to free slots for each subgraph based on its free
    -- slot usage type.
    for _, sg in ipairs(subgraphs) do
        if sg.empty_type == "D_cycle" or sg.empty_type == "D_chain" then
            if sg.empty_type == "D_chain" then
                -- Make sure the parent of the empty slot goes to the
                -- right place.
                local empty_slot = sg.chain_end
                local empty_parent = inverse_map[empty_slot]
                tinsert(moves, {empty_parent, empty_slot})
                sg.slot_set:remove(empty_slot, empty_parent)
                -- Drop the first item in the chain since it's already
                -- in an effectively free slot.
                assert(not inverse_map[sg.chain_start])
                sg.slot_set:remove(sg.chain_start)
            end
            for slot in sg.slot_set do
                tinsert(moves, {slot, sg.empty_set:pop()})
            end
            assert(sg.empty_set:len() == 0)
            sg.slot_set:clear()
        elseif sg.empty_type == "E" then
            local empty_slot = sg.chain_end
            local empty_parent = inverse_map[empty_slot]
            tinsert(moves, {empty_parent, empty_slot})
            sg.slot_set:remove(empty_slot, empty_parent)
            local slot = inverse_map[empty_parent]
            while sg.empty_set:len() > 0 do
                tinsert(moves, {slot, sg.empty_set:pop()})
                sg.slot_set:remove(slot)
                slot = inverse_map[slot]
            end
            sg.chain_end = slot
        elseif sg.empty_type == "F" then
            local slot = sg.chain_start
            tinsert(moves, {slot, sg.empty_set:pop()})
            slot = inverse_map[slot]
            assert(slot == sg.chain_end)
            while sg.empty_set:len() > 0 do
                tinsert(moves, {slot, sg.empty_set:pop()})
                sg.slot_set:remove(slot)
                slot = inverse_map[slot]
            end
            sg.chain_end = slot
        else
            assert(sg.empty_set:len() == 0)
        end
    end

    -- Generate moves for all remaining pairs in each subgraph.
    for _, sg in ipairs(subgraphs) do
        while sg.slot_set:len() >= 2 do
            -- Make sure we record a swap with an empty slot as "from" the
            -- item "to" the empty slot, since we can't pick up an empty slot.
            local target = sg.chain_end
            local source = inverse_map[target] -- Must exist by loop condition.
            sg.chain_end = inverse_map[source]
            sg.slot_set:remove(source, target)
            tinsert(moves, {source, target})
        end
    end

    -- Verify that we've done some work, to ensure that we don't get stuck
    -- in an infinite loop.  (This check should never fail because even if
    -- there are no trivial moves, each individual subgraph will have a
    -- minimum of three slots and we should thus generate at least one move
    -- for it.)
    assert(#moves >= first_move)

    -- Apply all moves from this pass to slot_map and repeat from the
    -- beginning on the updated map.
    for i = first_move, #moves do
        local source, target = unpack(moves[i])
        slot_map[target], slot_map[source] = slot_map[source], slot_map[target]
    end
    -- Tail call to avoid deepening the call stack.
    return FindMovesImpl(size, slot_map, moves)
end

-- Return an array of {from, to} pairs indicating bag slot exchange
-- operations which rearranges the items in |items| from their original
-- slots to their order in that list.  Each entry in |items| is expected
-- to have a "slot" field holding the item's original bag slot.
--
-- The returned array is guaranteed to consist of no more than
-- ceil(log2(#items)) batches of mutually independent moves, though it
-- may not be the theoretical minimum number of moves or batches required
-- for the requested transformation.
local function FindMoves(items, bag_size)
    local slot_map = {}
    for i, item in ipairs(items) do
        slot_map[item.slot] = i
    end
    return FindMovesImpl(bag_size, slot_map, {})
end

-- Class implementing a bag sort operation, returned from StartBagSort().
-- The class supports two operations, intended for calling from a
-- coroutine:
--    - Run(): Performs as much work as possible for the current frame.
--          Returns true if the operation is complete, false if work
--          remains to be done.
--    - Abort(): Aborts the operation.  No more moves will be performed,
--          but Run() will continue to return false until all locked
--          slots become unlocked.
-- Note that Run() may raise an error if it encounters a situation from
-- which it cannot proceed; the caller should wrap it (such as with
-- pcall()) if desired.
local BagSorter = class()
    function BagSorter:__constructor(bag, moves)
        self.bag = bag
        self.moves = moves
        self.move_index = 1
        self.busy_slots = set()
    end

    function BagSorter:Error(msg)
        -- Ensure that a subsequent Run() doesn't try to do more work.
        self:Abort()
        self.busy_slots:clear()
        error(msg, 2)
    end

    function BagSorter:CheckBusy(slot)
        if self.busy_slots:has(slot) then
            local info = C_Container.GetContainerItemInfo(self.bag, slot)
            if info and info.isLocked then
                return true
            end
            self.busy_slots:remove(slot)
        end
        return false
    end

    -- Returns true if move succeeded, false to try again later.
    function BagSorter:TryMove(source, target)
        if self:CheckBusy(source) or self:CheckBusy(target) then
            return false
        end
        if GetCursorInfo() then
            -- We start with the cursor cleared and make sure it's
            -- cleared after each move, so if something is on the
            -- cursor here, either it came from player action or the
            -- client is confused; either way, abort immediately to
            -- try and avoid potential disaster.
            self:Error("Item sort interrupted by user action.")
        end
        C_Container.PickupContainerItem(self.bag, source)
        -- Immediately record the slot as potentially busy.  If it's
        -- not in fact locked, we'll detect that next cycle.
        self.busy_slots:add(source)
        -- If the cursor now has an item, we assume it's the correct
        -- one.  If it doesn't, we assume we got throttled by the
        -- game and stop processing for this cycle.
        local info = GetCursorInfo()
        if not info then
            -- Nothing on the cursor can also mean there was nothing to
            -- pick up in the first place, either because the move itself
            -- was incorrectly specified or the player (or server)
            -- manipulated the bag during the operation.  In that case,
            -- we'd stall here forever, so check that the slot is in fact
            -- occupied.
            if not C_Container.GetContainerItemInfo(self.bag, source) then
                self:Error("Item sort aborted due to inventory consistency error.")
            end
            return false
        elseif info ~= "item" then  -- should be impossible
            self:Error("Item sort interrupted by cursor error.")
        end
        C_Container.PickupContainerItem(self.bag, target)
        self.busy_slots:add(target)
        -- The cursor should now be empty, indicating that the item was
        -- successfully dropped in the target slot.  If not, we again
        -- assume we're being throttled, and we make sure the cursor is
        -- clear for the next attempt.
        if GetCursorInfo() then
            ClearCursor()
            assert(not GetCursorInfo())
            return false
        end
        return true
    end

    function BagSorter:Run()
        while self.move_index <= #self.moves do
            local source, target = unpack(self.moves[self.move_index])
            if not self:TryMove(source, target) then
                return false
            end
            self.move_index = self.move_index + 1
        end
        for slot in self.busy_slots do
            if self:CheckBusy(slot) then
                return false
            end
        end
        return true
    end

    function BagSorter:Abort()
        self.move_index = #self.moves + 1
    end
-- end class BagSorter

-- Start a sort operation for the given bag using the given list of
-- {comparator, direction} pairs.  Returns a BagSorter instance which will
-- execute the sort operation.
--
-- Clears anything held by the game cursor (ClearCursor()) as a side effect.
local function StartBagSort(bag, bag_size, conditions)
    local items = {}
    for i = 1, bag_size do
        local item = GetItemData(bag, i)
        if item then
            item.slot = i
            tinsert(items, item)
        end
    end
    for _, entry in ipairs(conditions or {}) do
        local comparator, direction = unpack(entry)
        for i, item in ipairs(items) do
            item.index = i
        end
        table.sort(items, CompareItems(comparator, direction))
    end

    local moves = FindMoves(items, bag_size)

    ClearCursor()
    return BagSorter(bag, moves)
end

-- Perform as much work as possible on the currently running sort operation,
-- running_sort will be cleared if the operation completes (or fails);
-- otherwise, the function will schedule itself to be called next frame
-- to continue the operation.
local function RunBagSort()
    assert(running_sort)
    local success, status = pcall(running_sort.Run, running_sort)
    if success and not status then
        RunNextFrame(RunBagSort)
        return
    end
    running_sort = nil
    if success then
        print(Yellow("Item sort completed."))
    else
        print(Red(status))
    end
end

--------------------------------------------------------------------------
-- /itemsort implementation
--------------------------------------------------------------------------

function WoWXIV.isort(arg)
    local args = {}
    for word in arg:gmatch("[%w_]+") do
        tinsert(args, word)
    end
    local bag, subcommand, condition, direction, junk = unpack(args)
    if not subcommand or junk or (subcommand ~= "condition" and condition) then
        print(Red("Incorrect syntax. Try \"/? itemsort\" for help."))
        return
    end

    if tonumber(bag) then
        bag = tonumber(bag)
    elseif Enum.BagIndex[bag] then
        bag = Enum.BagIndex[bag]
    else
        print(Red("Unknown bag identifier. Try \"/? itemsort\" for help."))
        return
    end

    if subcommand == "clear" then
        bag_conditions[bag] = nil

    elseif subcommand == "condition" then
        local comparator, dir_val, errmsg = ParseCondition(condition, direction)
        if comparator then
            bag_conditions[bag] = bag_conditions[bag] or {}
            tinsert(bag_conditions[bag], {comparator, dir_val})
        else
            print(Red(errmsg..". Try \"/? itemsort\" for help."))
        end

    elseif subcommand == "execute" then
        local conditions = bag_conditions[bag]
        bag_conditions[bag] = nil  -- Clear regardless of success/failure.
        if running_sort then
            print(Red("A sort operation is already in progress."))
            return
        end
        local bag_size = C_Container.GetContainerNumSlots(bag) or 0
        if bag_size == 0 then
            print(Red("Selected bag is unavailable."))
            return
        end
        running_sort = StartBagSort(bag, bag_size, conditions)
        RunBagSort()

    else
        print(Red("Unknown subcommand. Try \"/? itemsort\" for help."))
        return
    end
end

-- External callers can use this function to start a bag sort operation.
-- |conditions| should be a list of {condition, direction} entries,
-- specified as for the /itemsort command (e.g. {"category", "ascending"}),
-- or nil for a "reasonable" default set of conditions.
-- The caller is responsible for running the returned BagSorter instance.
function WoWXIV.isort_execute(bag, conditions)
    local comparators = {}
    for _, entry in ipairs(conditions or DEFAULT_SORT_CONDITIONS) do
        local comparator, dir_val, errmsg = ParseCondition(unpack(entry))
        if not comparator then
            error(errmsg)
        end
        tinsert(comparators, {comparator, dir_val})
    end
    local bag_size = C_Container.GetContainerNumSlots(bag) or 0
    if bag_size == 0 then
        error("Bag is unavailable")
    end
    return StartBagSort(bag, bag_size, comparators)
end

--------------------------------------------------------------------------
-- Sorting algorithm tests (run with: lua -e 'require("isort").isortTests()')
--------------------------------------------------------------------------

if STANDALONE then  -- to end of file

local strformat = string.format

local function mapt(func, table)  -- copied from util.lua for standalone use
    local result = {}
    for k, v in pairs(table) do
        result[k] = func(v)
    end
    return result
end
local function maptn(func, range, ...)
    local startval, endval = range, ...
    if not endval then
        startval, endval = 1, range
    end
    local result = {}
    for i = startval, endval do
        result[i] = func(i)
    end
    return result
end

local function SlotToString(slot)
    return slot==0 and "-" or tostring(slot)
end

local function SlotMapToString(slot_map)
    local s = SlotToString(slot_map[1])
    for i = 2, #slot_map do
        s = s..(i%10==1 and ", " or ",")..SlotToString(slot_map[i])
    end
    return s
end

local function ValidateMoves(slot_map, moves)
    slot_map = mapt(function(x) return x end, slot_map)  -- make a local copy
    local size = #slot_map
    local batches = #moves==0 and 0 or 1
    local busy = set()
    for i, move in ipairs(moves) do
        local source, target = unpack(move)
        if source < 1 or source > size then
            error(strformat("Move %d: Source slot %d out of range", i, source))
        end
        if target < 1 or target > size then
            error(strformat("Move %d: Target slot %d out of range", i, target))
        end
        if busy:has(source) or busy:has(target) then
            -- For batch counting, we make the simplifying assumption that
            -- all moves in a batch complete simultaneously (on which the
            -- algorithm itself also relies).
            busy:clear()
            batches = batches + 1
        end
        busy:add(source, target)
        slot_map[source], slot_map[target] = slot_map[target], slot_map[source]
    end
    for i = 1, size do
        if slot_map[i] ~= i and slot_map[i] ~= 0 then
            error("Wrong state after moves: "..SlotMapToString(slot_map))
        end
    end
    return batches
end

local function RunMoveTest(slots, expected_batches)
    local size = #slots
    local slot_map = mapt(function(x) return x>0 and x or nil end, slots)
    local moves = FindMovesImpl(size, slot_map, {})
    local batches = ValidateMoves(slots, moves)
    if expected_batches and batches ~= expected_batches then
        error(strformat("Wrong number of batches (%d, expected %s)",
                        batches, expected_batches))
    end
    return batches
end

local function MakeMoveTest(slots, expected_batches)
    return {slots, expected_batches,
            debug and debug.getinfo(2,"l").currentline or 0}
end

local tests = {

    -------- Generic behavior tests.

    Empty = MakeMoveTest({0, 0, 0, 0, 0, 0, 0, 0, 0, 0}, 0),

    Identity = MakeMoveTest({1, 0, 0, 0, 0, 0, 0, 0, 0, 0}, 0),
    IdentityFull = MakeMoveTest({1, 2, 3, 4, 5, 6, 7, 8, 9, 10}, 0),

    MoveSingle = MakeMoveTest({0, 1, 0, 0, 0, 0, 0, 0, 0, 0}, 1),
    MoveMultiple = MakeMoveTest({0, 1, 0, 3, 0, 5, 0, 7, 0, 9}, 1),

    SwapSingle = MakeMoveTest({2, 1, 0, 0, 0, 0, 0, 0, 0, 0}, 1),
    SwapMultiple = MakeMoveTest({2, 1, 4, 3, 6, 5, 8, 7, 10, 9}, 1),

    CycleThrees = MakeMoveTest({2, 3, 1, 5, 6, 4, 8, 9, 7}, 2),
    CycleThreesEmpty = MakeMoveTest({2, 0, 1, 5, 0, 4, 8, 0, 7}, 2),
    CycleSome = MakeMoveTest({2, 3, 4, 5, 1, 0, 0, 0, 0, 0}, 2),
    CycleMost = MakeMoveTest({2, 3, 4, 5, 6, 7, 8, 9, 1, 0}, 4),
    CycleAll = MakeMoveTest({2, 3, 4, 5, 6, 7, 8, 9, 10, 1}, 4),

    MoveSome = MakeMoveTest({0, 1, 2, 3, 4, 5, 0, 0, 0, 0}, 2),
    MoveMost = MakeMoveTest({0, 1, 2, 3, 4, 5, 6, 7, 8, 9}, 4),

    -------- Test O(log2(N)) batching.

    Chain4 = MakeMoveTest(maptn(function(x) return x-1 end, 4), 2),
    Chain8 = MakeMoveTest(maptn(function(x) return x-1 end, 8), 3),
    Chain16 = MakeMoveTest(maptn(function(x) return x-1 end, 16), 4),
    Chain32 = MakeMoveTest(maptn(function(x) return x-1 end, 32), 5),
    Chain64 = MakeMoveTest(maptn(function(x) return x-1 end, 64), 6),
    Chain128 = MakeMoveTest(maptn(function(x) return x-1 end, 128), 7),

    Cycle4 = MakeMoveTest(maptn(function(x) return x==1 and 4 or x-1 end, 4), 2),
    Cycle8 = MakeMoveTest(maptn(function(x) return x==1 and 8 or x-1 end, 8), 3),
    Cycle16 = MakeMoveTest(maptn(function(x) return x==1 and 16 or x-1 end, 16), 4),
    Cycle32 = MakeMoveTest(maptn(function(x) return x==1 and 32 or x-1 end, 32), 5),
    Cycle64 = MakeMoveTest(maptn(function(x) return x==1 and 64 or x-1 end, 64), 6),
    Cycle128 = MakeMoveTest(maptn(function(x) return x==1 and 128 or x-1 end, 128), 7),

    -------- Check edge cases around use of free slots, both cases in which
    -------- using free slots will save batches and cases in which using
    -------- them will add extra batches.

    FreeSlotDChain = MakeMoveTest({0, 1, 2, 3, 4, 0, 0}, 2),

    FreeSlotE5Save1 = MakeMoveTest({0, 1, 2, 3, 4, 0}, 2),
    FreeSlotE9Save1 = MakeMoveTest({0, 1, 2, 3, 4, 5, 6, 7, 8, 0}, 3),
    FreeSlotE9Save2 = MakeMoveTest({0, 1, 2, 3, 4, 5, 6, 7, 8, 0, 0,
                                    0, 0, 0}, 2),

    FreeSlotF9Save1 = MakeMoveTest({9, 1, 2, 3, 4, 5, 6, 7, 8, 0,
                                    0, 0, 0, 0}, 3),

    BadFreeSlotCycle4 = MakeMoveTest({2, 3, 4, 1, 0}, 2),
    BadFreeSlotChain4 = MakeMoveTest({0, 1, 2, 3, 0}, 2),
    BadFreeSlotE6 = MakeMoveTest({0, 1, 2, 3, 4, 5, 0}, 3),
    BadFreeSlotF9 = MakeMoveTest({9, 1, 2, 3, 4, 5, 6, 7, 8, 0,
                                  0, 0, 0}, 4),

    -------- Fuzz the algorithm with random input to try and find
    -------- obscure bugs.  This isn't a "smart" fuzzer that tries to
    -------- find edge cases, just a simple random bag generator, but
    -------- it's better than nothing.

    RandomInput = function()
        local time = time or os.time
        math.randomseed(time())
        local random = math.random
        local NUM_TESTS = 10000
        local MAX_SIZE = 100  -- Maximum bag size to test.
        for i = 1, NUM_TESTS do
            -- Select uniformly from all {size,fill} combinations.
            local r = random(0, MAX_SIZE*(MAX_SIZE+1)/2-1)
            local size = 1
            while r >= size do
                r = r-size
                size = size+1
            end
            local fill = 1+r
            local bag = maptn(function(x) return x end, size)
            local slots = maptn(function(x) return 0 end, size)
            for j = 1, fill do
                local index = random(1, #bag)
                local slot = bag[index]
                tremove(bag, index)
                assert(slots[slot] == 0)
                slots[slot] = j
            end
            local success, result = pcall(RunMoveTest, slots)
            if success then
                local batches = result
                -- We should be able to complete any transformation within
                -- log2(size) batches.
                local expected = 1
                while 2^expected < size do
                    expected = expected+1
                end
                if batches > expected then
                    success = false
                    result = strformat("Too many batches (%d, expected <=%d)",
                                       batches, expected)
                end
            end
            if not success then
                error(strformat("Failed with {%s}: %s",
                                SlotMapToString(slots), result))
            end
        end
    end,
}

function WoWXIV.isortTests(verbose)
    local fail = 0
    local sorted = {}
    local tinsert = table.insert
    for name, test in pairs(tests) do
        local entry = {name, test}
        if type(test) == "table" then
            tinsert(entry, test[3])
        else
            tinsert(entry, debug.getinfo(entry[2],"S").linedefined or 0)
        end
        tinsert(sorted, entry)
    end
    table.sort(sorted, function(a,b) return a[3] < b[3] end)
    for _, entry in ipairs(sorted) do
        local name, test = unpack(entry)
        if verbose then
            io.write(name..": ")
        end
        local success, errmsg
        if type(test) == "table" then
            success, errmsg = pcall(RunMoveTest, test[1], test[2])
        else
            success, errmsg = pcall(test)
        end
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

return WoWXIV  -- for running standalone tests

end  -- if STANDALONE
