local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor
local Cursor = MenuCursor.Cursor

local class = WoWXIV.class

local tinsert = tinsert

---------------------------------------------------------------------------

-- Constants for garrison talent trees.  These don't seem to be defined
-- anywhere except as local constants in Blizzard_OrderHallTalents.lua.
local TALENTTREE_BFA_MOTHER = 271           -- MOTHER's Research
local TALENTTREE_SL_TORGHAST = 461          -- Torghast Box of Many Things
local TALENTTREE_SL_CYPHER = 474            -- Zereth Mortis cypher buffs
local TALENTTREE_DF_DRAGONSCALE = 489       -- Dragonscale Expedition buffs
local TALENTTREE_DF_SHIKAAR_COMPANION = 486 -- Shikaar hunting companion color
local TALENTTREE_DF_SHIKAAR_SKILLS = 491    -- Shikaar hunting companion skills
local TALENTTREE_DF_COBALT_ASSEMBLY = 493   -- Cobalt Assembly buffs


local OrderHallTalentFrameHandler = class(MenuCursor.AddOnMenuFrame)
OrderHallTalentFrameHandler.ADDON_NAME = "Blizzard_OrderHallUI"
MenuCursor.Cursor.RegisterFrameHandler(OrderHallTalentFrameHandler)

function OrderHallTalentFrameHandler:__constructor()
    __super(self, OrderHallTalentFrame)
    -- The frame uses various events and actions to refresh its display,
    -- using a release/recreate strategy which can change the mapping from
    -- tree icon to backing frame, so we need to hook the refresh function
    -- to make sure we catch every such change.
    hooksecurefunc(OrderHallTalentFrame, "RefreshAllData",
                   function(frame)
                       -- self.refreshing true indicates that RefreshAllData()
                       -- was called while a previous refresh was in progress,
                       -- so don't do anything in that case.
                       if frame.refreshing then return end
                       self:RefreshTargets()
                   end)
end

function OrderHallTalentFrameHandler:OnHide()
    __super(self)
    -- Clear target info in preparation for the next show event (see notes
    -- in RefreshTargets()).
    self.targets = {}
    self.talent_tree_id = nil
    self.cur_tier = nil
    self.cur_index = nil
end

-- Rather than configuring initial targets in SetTargets(), we wait for
-- the first RefreshAllData() call.  This typically happens before the
-- frame is actually shown, so we make sure to clear previous targets when
-- hiding the frame.
function OrderHallTalentFrameHandler:RefreshTargets()
    self:SetTarget(nil)
    self.targets = {}

    -- Look up the currently displayed talent tree ID.  (This logic is
    -- embedded in OrderHallTalentFrame:RefreshAllData() and not exported
    -- as a separate function, so we have to reimplement it ourselves.)
    local tree_id = C_Garrison.GetCurrentGarrTalentTreeID()
    if tree_id == nil or tree_id == 0 then  -- As in RefreshAllData().
        local ids = C_Garrison.GetTalentTreeIDsByClassID(
            self.frame.garrisonType, select(3, UnitClass("player")))
        if ids and #ids > 0 then
            tree_id = ids[1]
        end
    end
    self.talent_tree_id = tree_id

    -- Find all talent icons and group them by tier.
    local tiers = {}    -- Talent IDs sorted by tier and index.
    local talents = {}  -- Reverse mapping from talent ID to {tier,index}.
    local talent_info = tree_id and C_Garrison.GetTalentTreeInfo(tree_id)
    if talent_info and talent_info.talents then
        for _, talent in ipairs(talent_info.talents) do
            -- ignoreTalent seems only to be used for empty spaces in the
            -- Zereth Mortis Cypher Research Console UI.
            if not talent.ignoreTalent then
                -- The Cypher Research Console's blank line between the
                -- base skill and additional skills is implemented as a
                -- row of empty icons for talent.tier==1, so skip that row
                -- in our indexing.
                local tier = talent.tier + 1
                if tree_id == TALENTTREE_SL_CYPHER and tier >= 3 then
                    tier = tier - 1
                end
                local index = talent.uiOrder + 1
                tiers[tier] = tiers[tier] or {}
                assert(not tiers[tier][index])
                tiers[tier][index] = talent.id
                talents[talent.id] = {tier, index}
            end
        end
    end
    -- Fill in empty spaces in specific trees (needed to avoid nil entries
    -- which would break ipairs() iteration).
    if tree_id == TALENTTREE_BFA_MOTHER then
        for tier = 1, 6 do
            for index = 1, 5 do
                tiers[tier][index] = tiers[tier][index] or 0
            end
        end
    elseif tree_id == TALENTTREE_SL_CYPHER then
        tiers[6][1] = 0
        tiers[6][4] = 0
    elseif tree_id == TALENTTREE_DF_DRAGONSCALE then
        for tier = 1, 6 do
            for index = 1, 3 do
                tiers[tier][index] = tiers[tier][index] or 0
            end
        end
    elseif tree_id == TALENTTREE_DF_COBALT_ASSEMBLY then
        for tier = 1, 4 do
            for index = 1, 3 do
                tiers[tier][index] = tiers[tier][index] or 0
            end
        end
    end
    self.tiers = tiers
    self.talents = talents

    -- Add all talent buttons to the target list.
    local buttons = {}  -- Keyed by talent ID.
    local cur_target
    for button in self.frame.buttonPool:EnumerateActive() do
        assert(button.talent, "Talent missing from talent button")
        local id = button.talent.id
        local order = talents[id]
        assert(order, "Talent ID missing from order map")
        local tier, index = unpack(order)
        buttons[id] = button
        self.targets[button] = {can_activate = true, send_enter_leave = true}
        if (tier == self.cur_tier and index == self.cur_index) then
            cur_target = button
        end
    end
    self.buttons = buttons

    -- Add directional links.  For standard 1-or-2-button-per-tier trees,
    -- when moving from a 1-button to a 2-button tier, we default to moving
    -- to the left button for consistency, but we update as appropriate in
    -- OnMove() to maintain the current column on a 2->1->2 movement.
    -- We have tree-specific logic for similar cases in other-format trees.
    local prev_tier = tiers[#tiers]
    for i_tier, tier in ipairs(tiers) do
        local next_tier = tiers[i_tier==#tiers and 1 or i_tier+1]
        local prev_id = tier[#tier]
        for i_id, id in ipairs(tier) do
            if id ~= 0 then
                local next_id = tier[i_id==#tier and 1 or i_id+1]
                local button = buttons[id]
                assert(button, "Button missing from tier mapping")
                local up_id = prev_tier[i_id] or prev_tier[#prev_tier]
                local down_id = next_tier[i_id] or next_tier[#next_tier]
                if tree_id == TALENTTREE_BFA_MOTHER then
                    -- Deal with unique shape (row sizes 1/4/1/1/2/1).
                    -- Single-button rows use index 3 (centered); other
                    -- rows use indexes [1]/2/4/[5], such that the space
                    -- between 2 and 4 is centered:
                    --       3
                    --    1 2 4 5
                    --       3
                    --       3
                    --      2 4
                    --       3
                    if i_id == 3 then  -- Single-button row.
                        prev_id = id
                        next_id = id
                        if prev_tier[3] ~= 0 then
                            up_id = prev_tier[3]
                        else
                            up_id = prev_tier[2]
                        end
                        if next_tier[3] ~= 0 then
                            down_id = next_tier[3]
                        else
                            down_id = next_tier[2]
                        end
                    else  -- Multi-button row.
                        if i_id == 2 then
                            next_id = tier[4]
                            if tier[1] == 0 then prev_id = next_id end
                        end
                        if i_id == 4 then
                            prev_id = tier[2]
                            if tier[5] == 0 then next_id = prev_id end
                        end
                        -- The only multi-button rows are not adjacent, so
                        -- we know both up and down tiers are single-button.
                        up_id = prev_tier[3]
                        down_id = next_tier[3]
                    end
                elseif tree_id == TALENTTREE_SL_CYPHER then
                    -- Deal with empty spaces at the bottom of columns 1/4.
                    if (i_id == 1 or i_id == 4) and i_tier == 1 then
                        up_id = tiers[5][i_id]
                    elseif (i_id == 1 or i_id == 4) and i_tier == 5 then
                        down_id = tiers[1][i_id]
                    elseif i_id == 2 and i_tier == 6 then
                        prev_id = tiers[5][1]
                    elseif i_id == 3 and i_tier == 6 then
                        next_id = tiers[5][4]
                    end
                elseif tree_id == TALENTTREE_DF_DRAGONSCALE then
                    -- All buttons are aligned but some empty spaces.
                    if up_id == 0 then
                        up_id = prev_tier[2]
                    end
                    if down_id == 0 then
                        down_id = next_tier[2]
                    end
                    if prev_id == 0 then
                        prev_id = tier[3]
                        if prev_id == 0 then
                            prev_id = tier[2]
                        end
                    end
                    if next_id == 0 then
                        next_id = tier[2]
                    end
                elseif tree_id == TALENTTREE_DF_COBALT_ASSEMBLY then
                    -- 3x3 grid (corners empty) with a row of 2 underneath.
                    -- The bottom row is implemented as indexes 0 and 2.
                    if i_tier == 4 then
                        if i_id == 1 then
                            prev_id = tier[3]
                            next_id = tier[3]
                        else
                            assert(i_id == 3)
                            prev_id = tier[1]
                            next_id = tier[1]
                        end
                        up_id = prev_tier[2]
                        down_id = next_tier[2]
                    else
                        if up_id == 0 then
                            up_id = prev_tier[i_id==2 and 1 or 2]
                        end
                        if down_id == 0 then
                            down_id = next_tier[i_id==2 and 1 or 2]
                        end
                        if prev_id == 0 then
                            prev_id = id
                            next_id = id
                        end
                    end
                end
                assert(buttons[up_id])
                assert(buttons[down_id])
                assert(buttons[prev_id])
                assert(buttons[next_id])
                self.targets[button].up = buttons[up_id]
                self.targets[button].down = buttons[down_id]
                self.targets[button].left = buttons[prev_id]
                self.targets[button].right = buttons[next_id]
                prev_id = id
            end
        end
        prev_tier = tier
    end

    -- If we had no previous target or didn't find it, default to the first
    -- button.
    local target = cur_target
    if not target then
        if tree_id == TALENTTREE_BFA_MOTHER then
            target = buttons[tiers[1][3]]
        elseif tree_id == TALENTTREE_DF_COBALT_ASSEMBLY then
            target = buttons[tiers[1][2]]
        else
            target = buttons[tiers[1][1]]
        end
        assert(target)
    end
    self:SetTarget(target)
    -- We also need to set the is_default flag because our first call comes
    -- during the show event.
    self.targets[target].is_default = true
end

function OrderHallTalentFrameHandler:OnMove(old_target, new_target)
    __super(self, old_target, new_target)
    if not old_target or not new_target then return end

    local old_order = self.talents[old_target.talent.id]
    local old_tier, old_index = unpack(old_order)
    local new_order = self.talents[new_target.talent.id]
    local new_tier, new_index = unpack(new_order)

    -- Save the current button's index so we can restore it across a
    -- RefreshAllData() call.
    self.cur_tier = new_tier
    self.cur_index = new_index

    -- When moving left or right, update all up/down links on 1-button
    -- tiers to move to the new button index.  This ensures that if the
    -- player moves from a 2-button tier across a 1-button tier onto
    -- another 2-button tier, the cursor stays on the same side (left or
    -- right) even though the 1-button tier only has a single button and
    -- thus a single up/down link.
    -- For Torghast, which uses rows of 3 and 2 instead of 2 and 1, we use
    -- similar logic for the single row of 2 at the bottom.
    if not (old_tier == new_tier and old_index ~= new_index) then return end
    local targets = self.targets
    local tiers = self.tiers
    local buttons = self.buttons
    local is_torghast = (self.talent_tree_id == TALENTTREE_SL_TORGHAST)
    local is_shikaar = (self.talent_tree_id == TALENTTREE_DF_SHIKAAR_SKILLS)
    local small_row_size = (is_torghast or is_shikaar) and 2 or 1
    if self.talent_tree_id == TALENTTREE_BFA_MOTHER then
        assert(new_tier == 2 or new_tier == 5)
        local index_5 = new_index==1 and 2 or new_index==5 and 4 or new_index
        targets[buttons[tiers[1][3]]].down = buttons[tiers[2][new_index]]
        targets[buttons[tiers[3][3]]].up = buttons[tiers[2][new_index]]
        targets[buttons[tiers[4][3]]].down = buttons[tiers[5][index_5]]
        targets[buttons[tiers[6][3]]].up = buttons[tiers[5][index_5]]
    elseif self.talent_tree_id == TALENTTREE_DF_COBALT_ASSEMBLY then
        targets[buttons[tiers[1][2]]].down = buttons[tiers[2][new_index]]
        targets[buttons[tiers[3][2]]].up = buttons[tiers[2][new_index]]
        if new_index ~= 2 then
            targets[buttons[tiers[3][2]]].down = buttons[tiers[4][new_index]]
            targets[buttons[tiers[1][2]]].up = buttons[tiers[4][new_index]]
        end
    elseif #tiers[new_tier] > small_row_size then
        local prev_tier = tiers[#tiers]
        for i_tier, tier in ipairs(tiers) do
            local next_tier = tiers[i_tier==#tiers and 1 or i_tier+1]
            if #tier == 1 then
                local button = buttons[tier[1]]
                assert(button)
                if #prev_tier >= new_index then
                    local up_button = buttons[prev_tier[new_index]]
                    assert(up_button)
                    targets[button].up = up_button
                end
                if #next_tier >= new_index then
                    local down_button = buttons[next_tier[new_index]]
                    assert(down_button)
                    targets[button].down = down_button
                end
            elseif small_row_size == 2 and #tier == 2 then
                local button1 = buttons[tier[1]]
                assert(button1)
                local button2 = buttons[tier[2]]
                assert(button2)
                if #prev_tier == 3 then
                    local up_button = buttons[prev_tier[new_index]]
                    assert(up_button)
                    if new_index > 1 then
                        targets[up_button].down = button2
                        targets[button2].up = up_button
                    end
                    if new_index < 3 then
                        targets[up_button].down = button1
                        targets[button1].up = up_button
                    end
                end
                if #next_tier == 3 then
                    local down_button = buttons[next_tier[new_index]]
                    assert(down_button)
                    if new_index > 1 then
                        targets[button2].down = down_button
                        targets[down_button].up = button2
                    end
                    if new_index < 3 then
                        targets[button1].down = down_button
                        targets[down_button].up = button1
                    end
                end
            end
            prev_tier = tier
        end
    elseif small_row_size == 2 and #tiers[new_tier] == 2 then
        -- If moving within small rows on 2/3-format trees, reset the
        -- up/down links to shift left.
        local prev_tier = tiers[#tiers]
        for i_tier, tier in ipairs(tiers) do
            local next_tier = tiers[i_tier==#tiers and 1 or i_tier+1]
            for i = 1, 2 do
                local prev_button = buttons[prev_tier[i]]
                assert(prev_button)
                local this_button = buttons[tier[i]]
                assert(this_button)
                local next_button = buttons[next_tier[i]]
                assert(next_button)
                targets[prev_button].down = this_button
                targets[this_button].up = prev_button
                targets[this_button].down = next_button
                targets[next_button].up = this_button
            end
            prev_tier = tier
        end
    end
end
