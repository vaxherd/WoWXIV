local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

local floor = math.floor

assert(WoWXIV.UI.ContextMenu)  -- Ensure proper load order.

---------------------------------------------------------------------------

local CollectionsJournalHandler = class(MenuCursor.MenuFrame)
MenuCursor.Cursor.RegisterFrameHandler(CollectionsJournalHandler)
local MountJournalHandler = class(MenuCursor.StandardMenuFrame)
local PetJournalHandler = class(MenuCursor.StandardMenuFrame)
local PetSpellSelectHandler = class(MenuCursor.StandardMenuFrame)
local ToyBoxHandler = class(MenuCursor.StandardMenuFrame)
local HeirloomsJournalHandler = class(MenuCursor.StandardMenuFrame)
local WardrobeCollectionFrameHandler = class(MenuCursor.StandardMenuFrame)
local WarbandSceneJournalHandler = class(MenuCursor.StandardMenuFrame)


function CollectionsJournalHandler.Initialize(class, cursor)
    class.cursor = cursor
    class:RegisterAddOnWatch("Blizzard_Collections")
end

function CollectionsJournalHandler.OnAddOnLoaded(class, cursor)
    class.instance = class()
    class.instance_MountJournal = MountJournalHandler()
    class.instance_PetJournal = PetJournalHandler()
    class.instance_PetSpellSelect = PetSpellSelectHandler()
    class.instance_ToyBox = ToyBoxHandler()
    class.instance_HeirloomsJournal = HeirloomsJournalHandler()
    class.instance_WardrobeCollectionFrame = WardrobeCollectionFrameHandler()
    class.instance_WarbandSceneJournal = WarbandSceneJournalHandler()
    class.panel_instances = {class.instance_MountJournal,
                             class.instance_PetJournal,
                             class.instance_ToyBox,
                             class.instance_HeirloomsJournal,
                             class.instance_WardrobeCollectionFrame,
                             class.instance_WarbandSceneJournal}
end

function CollectionsJournalHandler:__constructor()
    -- Same pattern as e.g. CharacterFrame.
    __super(self, CollectionsJournal)
    self:HookShow(CollectionsJournal)
    self.tab_handler = function(direction) self:OnTabCycle(direction) end
end

function CollectionsJournalHandler.CancelMenu()  -- Static method.
    HideUIPanel(CollectionsJournal)
end

function CollectionsJournalHandler:OnShow()
    for _, panel_instance in ipairs(self.panel_instances) do
        if panel_instance.frame:IsShown() then
            panel_instance:OnShow()
            return
        end
    end
end

function CollectionsJournalHandler:OnHide()
    for _, panel_instance in ipairs(self.panel_instances) do
        if panel_instance.frame:IsShown() then
            panel_instance:OnHide()
            return
        end
    end
end

function CollectionsJournalHandler:OnTabCycle(direction)
    local new_index =
        (PanelTemplates_GetSelectedTab(self.frame) or 0) + direction
    if new_index < 1 then
        new_index = self.frame.numTabs
    elseif new_index > self.frame.numTabs then
        new_index = 1
    end
    local tab = self.frame.Tabs[new_index]
    tab:GetScript("OnClick")(tab, "LeftButton", true)
end

---------------------------------------------------------------------------

local MountContextMenu = class(WoWXIV.UI.ContextMenu)

function MountJournalHandler:__constructor()
    self.cur_mount = nil  -- ID of currently selected mount.

    __super(self, MountJournal)
    self.cancel_func = CollectionsJournalHandler.CancelMenu
    self.tab_handler = CollectionsJournalHandler.instance.tab_handler
    self.has_Button3 = true  -- Used to mount/dismount or unwrap new mount.
    self.has_Button4 = true  -- Used to open context menu.
    hooksecurefunc("MountJournal_UpdateMountList",
                   function() self:RefreshTargets() end)

    -- Mount context menu and associated cursor handler.
    self.context_menu = MountContextMenu()
    self.context_menu_handler = MenuCursor.ContextMenuHandler(self.context_menu)
    self.context_menu_handler.has_Button3 = true
    self.context_menu_handler.OnAction = function(inner_self, button)
        assert(button == "Button3")
        inner_self.frame:Close()
        return self:OnAction(button)
    end
end

function MountJournalHandler:RefreshTargets()
    self:SetTarget(nil)
    self:SetTarget(self:SetTargets())
end

function MountJournalHandler:SetTargets()
    local f = self.frame
    local TogglePlayer = f.MountDisplay.ModelScene.TogglePlayer
    self.targets = {
        [TogglePlayer] = {can_activate = true, lock_highlight = true,
                          up = false, down = false}
    }
    local top, bottom, initial = self:AddScrollBoxTargets(
        self.frame.ScrollBox, function(data)
            -- Set the cursor offset to point to the icon, which is not
            -- part of the button itself; we don't have direct access to
            -- the button frame here, so we have to hardcode this value.
            -- The offset comes from the MountListButtonTemplate.icon
            -- anchor definition in Blizzard_MountCollection.xml.
            local params = {can_activate = true, lock_highlight = true,
                            x_offset = -42}
            return params, data.mountID == self.cur_mount
        end)
    return initial or top
end

function MountJournalHandler:EnterTarget(target)
    __super(self, target)
    local TogglePlayer = self.frame.MountDisplay.ModelScene.TogglePlayer
    if target ~= TogglePlayer then
        self.cur_mount = self:GetTargetFrame(target):GetElementData().mountID
        self.targets[target].left = TogglePlayer
        self.targets[target].right = TogglePlayer
        self.targets[TogglePlayer].left = target
        self.targets[TogglePlayer].right = target
    end
end

function MountJournalHandler:OnAction(button)
    local target = self:GetTarget()
    if target == self.frame.MountDisplay.ModelScene.TogglePlayer then
        return  -- No special actions here.
    end
    local target_frame = self:GetTargetFrame(target)
    if button == "Button3" then
        -- MountButton acts on the selected mount, not the highlighted one,
        -- so make sure we select it first.
        target_frame:Click("LeftButton", true)
        self.frame.MountButton:Click("LeftButton", true)
    else
        assert(button == "Button4")
        self.context_menu:Open(target_frame)
    end
end


function MountContextMenu:__constructor()
    __super(self)

    -- This is a "do whatever the Mount button does" option, needed because
    -- the actual mount operation is protected.  We relabel it as appropriate
    -- in Configure().
    self.menuitem_mount = self:CreateButton("Mount", function()
        -- MountButton acts on the selected mount, not the highlighted one,
        -- but Configure() ensures that the current button is selected.
        MountJournal.MountButton:Click("LeftButton", true)
    end)

    self.menuitem_set_favorite = self:CreateButton("Set favorite",
        function() self:DoSetFavorite(self.mount_button, true) end)

    self.menuitem_remove_favorite = self:CreateButton("Remove favorite",
        function() self:DoSetFavorite(self.mount_button, false) end)
end

function MountContextMenu:Configure(button)
    self.mount_button = button
    button:Click("LeftButton", true)

    if not button.owned then return end

    local id = button.mountID
    local needs_unwrap = C_MountJournal.NeedsFanfare(id)

    local mount_text
    if needs_unwrap then
        mount_text = "Unwrap"
    elseif select(4, C_MountJournal.GetMountInfoByID(id)) then
        mount_text = "Dismount"
    else
        mount_text = "Mount"
    end
    self.menuitem_mount:SetText(
        mount_text.." "..GetBindingText(WoWXIV.Config.GamePadMenuButton3()))
    self:AppendButton(self.menuitem_mount)
    if needs_unwrap then
        return  -- No other options when mount is not unwrapped.
    end

    if C_MountJournal.GetIsFavorite(button.index) then
        self:AppendButton(self.menuitem_remove_favorite)
    else
        self:AppendButton(self.menuitem_set_favorite)
    end
end

function MountContextMenu:DoSetFavorite(button, favorite)
    C_MountJournal.SetIsFavorite(button.index, favorite)
end

---------------------------------------------------------------------------

local MAXPETS = 3  -- There doesn't seem to be a global constant for this.

-- Return whether the given pet battle slot (1..MAXPETS) is locked (i.e.,
-- has not yet been unlocked by progressing pet battle intro quests).
local function IsPetBattleSlotLocked(index)
    return select(5, C_PetJournal.GetPetLoadOutInfo(index))
end

local PetContextMenu = class(WoWXIV.UI.ContextMenu)

function PetJournalHandler:__constructor()
    -- Current target set, one of:
    --     LIST (pet list)
    --     TOP (top buttons: achievements, summon random, heal all)
    --     DETAIL (pet details)
    --     BATTLE (battle pet slots)
    --     ASSIGN (assign pet to battle slot)
    self.state = "LIST"

    -- Instance or species ID of currently selected pet.  See notes in
    -- EnterTarget() for details.
    self.cur_pet = nil

    -- Current cursor position in the battle slot list.
    self.battle_slot = 1

    __super(self, PetJournal)
    self.cancel_func = self.OnCancel
    self.tab_handler = CollectionsJournalHandler.instance.tab_handler
    self.has_Button3 = true  -- Used to cycle through target sets.
    self.has_Button4 = true  -- Used to open context menu.
    hooksecurefunc("PetJournal_UpdatePetList",
                   function()
                       if self.state == "LIST" then self:RefreshTargets() end
                   end)

    -- Pet context menu and associated cursor handler.
    self.context_menu = PetContextMenu()
    self.context_menu_handler = MenuCursor.ContextMenuHandler(self.context_menu)
end

function PetJournalHandler:OnCancel()
    if self.state == "ASSIGN" then
        ClearCursor()
        self:SetState("LIST")
    elseif self.state == "DETAIL" or self.state == "BATTLE" then
        self:SetState("LIST")
    else
        CollectionsJournalHandler.CancelMenu()
    end
end

function PetJournalHandler:OnShow()
    self.state = "LIST"
    self.cur_pet = self.frame.PetCard.petID or self.frame.PetCard.speciesID
    self.battle_slot = 1
    __super(self)
end

function PetJournalHandler:SetState(state)
    if self.state == "ASSIGN" then
        for i = 1, MAXPETS do
            local slot = PetJournal.Loadout["Pet"..i]
            slot.setButton:Hide()
        end
    end
    self.state = state
    self.cursor_show_item = (state == "ASSIGN")
    self:RefreshTargets()
end

function PetJournalHandler:RefreshTargets()
    self:SetTarget(nil)
    self:SetTarget(self:SetTargets())
end

function PetJournalHandler:SetTargets()
    local f = self.frame

    if self.state == "TOP" then
        local Achievements = f.AchievementStatus
        local SummonRandom = f.SummonRandomPetSpellFrame.Button
        local HealPets = f.HealPetSpellFrame.Button
        self.targets = {
            [Achievements] = {can_activate = true, send_enter_leave = true,
                              up = false, down = false,
                              left = HealPets, right = SummonRandom},
            [SummonRandom] = {can_activate = true, lock_highlight = true,
                              send_enter_leave = true,
                              up = false, down = false,
                              left = Achievements, right = HealPets},
            [HealPets] = {can_activate = true, lock_highlight = true,
                          send_enter_leave = true,
                          up = false, down = false,
                          left = SummonRandom, right = Achievements},
        }
        return HealPets

    elseif self.state == "DETAIL" then
        local card = f.PetCard
        self.targets = {
            [card.PetInfo] = {send_enter_leave = true,
                              up = card.spell4, down = card.spell1,
                              left = card.TypeInfo, right = card.TypeInfo},
            [card.TypeInfo] = {send_enter_leave = true,
                               up = card.spell5, down = card.spell2,
                               left = card.PetInfo, right = card.PetInfo,
                               -- Position cursor to the left of the type name.
                               x_offset = (card.TypeInfo.type:GetLeft()
                                           - card.TypeInfo:GetLeft())},
        }
        local spells = WoWXIV.maptn(function(n) return card["spell"..n] end, 6)
        for i = 1, 6 do
            self.targets[spells[i]] =
                {send_enter_leave = true,
                 up = (i==1 and card.PetInfo or
                       i<=3 and card.TypeInfo or spells[i-3]),
                 down = (i==4 and card.PetInfo or
                         i>=5 and card.TypeInfo or spells[i+3]),
                 left = (i%3==1 and spells[i+2] or spells[i-1]),
                 right = (i%3==0 and spells[i-2] or spells[i+1])}
        end
        return card.PetInfo

    elseif self.state == "BATTLE" then
        local slot_targets = {}  -- pet or lock info, [ability 1..3]
        local is_readonly = (C_PetBattles.GetPVPMatchmakingInfo()
                             or not C_PetJournal.IsJournalUnlocked())
        for i = 1, MAXPETS do
            local slot = f.Loadout["Pet"..i]
            if is_readonly then
                slot_targets[i] = {slot.ReadOnlyFrame}
            elseif IsPetBattleSlotLocked(i) then
                slot_targets[i] = {slot.requirement}
            else
                slot_targets[i] = {slot.dragButton,
                                   slot.spell1, slot.spell2, slot.spell3}
            end
        end
        self.targets = {}
        for i = 1, MAXPETS do
            local this = slot_targets[i]
            local up = slot_targets[i==1 and MAXPETS or i-1]
            local down = slot_targets[i==MAXPETS and 1 or i+1]
            for j, target in ipairs(this) do
                local left = #this>1 and this[j==1 and #this or j-1]
                local right = #this>1 and this[j==#this and 1 or j+1]
                self.targets[target] =
                    {battle_slot = i,  -- For internal use.
                    can_activate = (j > 1), lock_highlight = true,
                    send_enter_leave = true, left = left, right = right,
                    up = up[j] or up[1], down = down[j] or down[1]}
            end
        end
        if not self.battle_slot or not slot_targets[self.battle_slot] then
            self.battle_slot = 1
        end
        return slot_targets[self.battle_slot][1]

    elseif self.state == "ASSIGN" then
        self.targets = {}
        local is_readonly = (C_PetBattles.GetPVPMatchmakingInfo()
                             or not C_PetJournal.IsJournalUnlocked())
        assert(not is_readonly)  -- Checked by the context menu.
        local slots = {}
        for i = 1, MAXPETS do
            if IsPetBattleSlotLocked(i) then break end
            tinsert(slots, f.Loadout["Pet"..i].setButton)
        end
        -- setButton uses the entire slot's rect, so shift the cursor to
        -- point to the icon (dragButton).
        local slot1 = f.Loadout.Pet1
        local x1, y1, w1, h1 = f.Loadout.Pet1.setButton:GetRect()
        local x2, y2, w2, h2 = f.Loadout.Pet1.dragButton:GetRect()
        y1 = y1 + h1/2
        y2 = y2 + h2/2
        local xofs, yofs = x2-x1, y2-y1
        local function AssignSlot(target)
            target:GetScript("OnClick")(target, "LeftButton")
            self.battle_slot = target:GetParent():GetID()
            self:SetState("BATTLE")
        end
        for i, slot in ipairs(slots) do
            self.targets[slot] =
                {on_click = AssignSlot, x_offset = xofs, y_offset = yofs,
                 up = slots[i==1 and #slots or i-1],
                 down = slots[i==#slots and 1 or i+1]}
        end
        return slots[1]

    else  -- LIST
        self.targets = {}
        local function OnClickPet(target)
            self:GetTargetFrame(target):Click()
            self:SetState("DETAIL")
        end
        local top, bottom, initial = self:AddScrollBoxTargets(
            self.frame.ScrollBox, function(data)
                -- Set the cursor offset to point to the icon, as for mounts.
                local params = {on_click = OnClickPet, lock_highlight = true,
                                x_offset = -42}
                return params, (data.petID or data.speciesID) == self.cur_pet
            end)
        return initial or top
    end
end

function PetJournalHandler:EnterTarget(target)
    __super(self, target)
    if self.state == "LIST" then
        -- For uncollected pets, the button has a speciesID but no petID.
        -- Pet IDs are strings while species IDs are numbers, so we can
        -- distinguish between collected and uncollected without needing
        -- a separate flag.
        local target_frame = self:GetTargetFrame(target)
        self.cur_pet = target_frame.petID or target_frame.speciesID
    elseif self.state == "BATTLE" then
        self.battle_slot = self.targets[target].battle_slot
    end
end

function PetJournalHandler:OnFocus()
    --[[
        HACK: Work around two issues with the spell select popup:

        (1) The "ability being selected" outline doesn't disappear when the
            spell select popup is closed.  If we're receiving focus, the
            popup must be closed, so clear the outline.

        (2) Ability slots seem to get the wrong tooltip on change, possibly
            because SpellSelect gets hidden before the ability change is
            actually sent, so force a tooltip update next frame.
    ]]--
    local target = self:GetTarget()
    if self.state == "BATTLE" and target and target.abilityID then
        target.selected:Hide()
        RunNextFrame(function()
            if self:HasFocus() and self:GetTarget() == target then
                target:GetScript("OnEnter")(target)
            end
        end)
    end
end

function PetJournalHandler:OnAction(button)
    if self.state == "ASSIGN" then
        return  -- Suppress actions in this pseudo-modal state.
    end
    if button == "Button3" then
        if self.state == "LIST" then
            self:SetState("TOP")
        elseif self.state == "TOP" then
            self:SetState("DETAIL")
        elseif self.state == "DETAIL" then
            self:SetState("BATTLE")
        else
            self:SetState("LIST")
        end
    else
        assert(button == "Button4")
        local target = self:GetTarget()
        local target_frame = target and self:GetTargetFrame(target)
        if not target_frame then return end
        local button, pet_id
        if self.state == "LIST" then
            button = target_frame.icon
            pet_id = target_frame.petID
        elseif self.state == "DETAIL" then
            local card = self.frame.PetCard
            if target_frame == card.PetInfo then
                button = target_frame.icon
                pet_id = card.petID
            end
        elseif self.state == "BATTLE" then
            if target_frame.OnDragStart then  -- i.e., if it's the pet icon
                button = target_frame
                pet_id = target_frame:GetParent().petID
            end
        end
        if not pet_id then
            return  -- No special actions here.
        end
        self.context_menu:Open(button, pet_id)
    end
end


function PetContextMenu:__constructor()
    __super(self)

    -- This is a "do whatever the Summon button does" option, needed because
    -- the actual operation is protected.  We relabel it as appropriate in
    -- Configure().
    self.menuitem_summon = self:CreateButton("Summon", function()
        -- SummonButton acts on the selected pet, not the highlighted one,
        -- but Configure() ensures that the current button is selected.
        PetJournal.SummonButton:Click("LeftButton", true)
    end)

    self.menuitem_assign_slot = self:CreateButton("Assign slot", function()
        C_PetJournal.PickupPet(self.pet_id)
        if GetCursorInfo() == "battlepet" then  -- Make sure we picked it up.
            local pjh = CollectionsJournalHandler.instance_PetJournal
            pjh.state = "ASSIGN"
            pjh:RefreshTargets()
            -- Toggle the slot highlights on, as done by
            -- PetJournalDragButtonMixin:OnDragStart().  Note a bug in that
            -- function which pulls the locked flag from the _previous_
            -- slot (passing i-1 instead of i to GetPetLoadOutInfo()).
            for i = 1, MAXPETS do
                local slot = PetJournal.Loadout["Pet"..i]
                slot.setButton:SetShown(not IsPetBattleSlotLocked(i))
            end
        end
    end)

    self.menuitem_rename = self:CreateButton("Rename", function()
        local id = self.pet_id
        StaticPopup_Show("BATTLE_PET_RENAME", nil, nil, id)
    end)

    self.menuitem_set_favorite = self:CreateButton("Set favorite",
        function() self:DoSetFavorite(self.pet_id, true) end)

    self.menuitem_remove_favorite = self:CreateButton("Remove favorite",
        function() self:DoSetFavorite(self.pet_id, false) end)

    self.menuitem_release = self:CreateButton("Release", function()
        local id = self.pet_id
        local name = PetJournalUtil_GetDisplayName(id)
        StaticPopup_Show("BATTLE_PET_RELEASE", name, nil, id)
    end)

    self.menuitem_cage = self:CreateButton("Put in cage", function()
        local id = self.pet_id
        StaticPopup_Show("BATTLE_PET_PUT_IN_CAGE", nil, nil, id)
    end)
end

function PetContextMenu:Configure(button, pet_id)
    self.pet_id = pet_id
    PetJournal_ShowPetCardByID(pet_id)

    local needs_unwrap = C_PetJournal.PetNeedsFanfare(pet_id)
    local is_locked = (C_PetJournal.PetIsRevoked(pet_id)
                       or C_PetJournal.PetIsLockedForConvert(pet_id))

    local summon_text
    if is_locked then
        summon_text = "(Pet is locked)"
    elseif needs_unwrap then
        summon_text = "Unwrap"
    elseif C_PetJournal.GetSummonedPetGUID() == pet_id then
        summon_text = "Dismiss"
    else
        summon_text = "Summon"
    end
    self.menuitem_summon:SetText(summon_text)
    self.menuitem_summon:SetEnabled(not is_locked)
    self:AppendButton(self.menuitem_summon)
    if needs_unwrap or is_locked then
        return  -- No other options when pet is locked or not unwrapped.
    end

    local first_slot_locked = select(5, C_PetJournal.GetPetLoadOutInfo(1))
    local slots_readonly = (C_PetBattles.GetPVPMatchmakingInfo()
                            or not C_PetJournal.IsJournalUnlocked())
    self.menuitem_assign_slot:SetEnabled(
        not (first_slot_locked or slots_readonly))
    self:AppendButton(self.menuitem_assign_slot)

    self:AppendButton(self.menuitem_rename)

    local favorite_item
    if C_PetJournal.PetIsFavorite(pet_id) then
        favorite_item = self.menuitem_remove_favorite
    else
        favorite_item = self.menuitem_set_favorite
    end
    self:AppendButton(favorite_item)

    if C_PetJournal.PetCanBeReleased(pet_id) then
        self:AppendButton(self.menuitem_release)
    end

    if C_PetJournal.PetIsTradable(pet_id) then
        self.menuitem_cage:SetEnabled(not C_PetJournal.PetIsSlotted(pet_id)
                                      and not C_PetJournal.PetIsHurt(pet_id))
        self:AppendButton(self.menuitem_cage)
    end
end

function PetContextMenu:DoSetFavorite(pet_id, favorite)
    -- If we pass a bool as the second arg to SetFavorite(), it raises an
    -- error saying that it expects... a bool!  Weird.  (What it actually
    -- wants is a C bool, i.e. 1 or 0.)
    C_PetJournal.SetFavorite(pet_id, favorite and 1 or 0)
end


function PetSpellSelectHandler:__constructor()
    __super(self, PetJournal.SpellSelect, MenuCursor.MenuFrame.MODAL)
    self.cancel_func = self.CancelFrame
end

function PetSpellSelectHandler:SetTargets()
    local f = self.frame
    local active_ability =
        select(f.abilityIndex+1, C_PetJournal.GetPetLoadOutInfo(f.slotIndex))
    local initial
    self.targets = {}
    for i = 1, 2 do
        local spell = f["Spell"..i]
        local other = f["Spell"..(3-i)]
        self.targets[spell] =
            {can_activate = true, send_enter_leave = true,
             up = other, down = other, left = false, right = false}
        if spell.abilityID == active_ability then
            initial = spell
        end
    end
    -- We should always have a valid initial target, but include a fallback
    -- just in case.
    return initial or f.Spell1
end

---------------------------------------------------------------------------

-- Local constant defined in Blizzard_ToyBox.lua; doesn't seem to be
-- available anywhere else.
local TOYS_PER_PAGE = 18

local ToyContextMenu = class(WoWXIV.UI.ContextMenu)

function ToyBoxHandler:__constructor()
    -- ID of toy to select.  Used to move the cursor to the right place
    -- when a toy's favorite flag is toggled.  Note that the logic around
    -- this is a bit convoluted: we may transiently see the cursor at a
    -- different icon or on a different page right after a favorite flag
    -- toggle, and we don't want to overwrite the pending ID in that case,
    -- so we can't just save the current ID in an EnterTarget() override;
    -- instead, we have to explicitly record the ID, and then preserve it
    -- until the page with that toy pops up.
    self.find_toy = nil

    __super(self, ToyBox)
    self.cancel_func = CollectionsJournalHandler.CancelMenu
    self.tab_handler = CollectionsJournalHandler.instance.tab_handler
    self.on_prev_page = self.frame.PagingFrame.PrevPageButton
    self.on_next_page = self.frame.PagingFrame.NextPageButton
    self.has_Button4 = true  -- Used to open context menu.
    hooksecurefunc("ToyBox_UpdateButtons",
                   function() self:RefreshTargets() end)

    -- Toy context menu and associated cursor handler.
    self.context_menu = ToyContextMenu()
    self.context_menu_handler = MenuCursor.ContextMenuHandler(self.context_menu)
end

function ToyBoxHandler:OnShow()
    self.find_toy = nil
    __super(self)
end

function ToyBoxHandler:OnFocus()
    if self.find_toy then
        local page = ToyBox_FindPageForToyID(self.find_toy)
        if page then
            self.frame.PagingFrame:SetCurrentPage(page)
        end
    end
end

function ToyBoxHandler:RefreshTargets()
    local old_target = self:GetTarget()
    self:SetTarget(nil)
    self:SetTarget(self:SetTargets(old_target))
end

function ToyBoxHandler:SetTargets(old_target)
    local f = self.frame
    local PrevPageButton = f.PagingFrame.PrevPageButton
    local NextPageButton = f.PagingFrame.NextPageButton
    self.targets = {
        [PrevPageButton] = {can_activate = true, lock_highlight = true,
                            left = NextPageButton, right = NextPageButton},
        [NextPageButton] = {can_activate = true, lock_highlight = true,
                            left = PrevPageButton, right = PrevPageButton},
    }

    local buttons = {}
    for i = 1, TOYS_PER_PAGE do
        local button = f.iconsFrame["spellButton"..i]
        if not button or not button:IsShown() then break end
        tinsert(buttons, button)
    end
    for i, button in ipairs(buttons) do
        self.targets[button] = {can_activate = true, lock_highlight = true,
                                left = buttons[i==1 and #buttons or i-1],
                                right = buttons[i==#buttons and 1 or i+1]}
        if (i-1)%3 == 2 then
            self.targets[button].down = NextPageButton
            self.targets[NextPageButton].up = button
        else
            self.targets[button].down = PrevPageButton
            self.targets[PrevPageButton].up = button
        end
        if i >= 4 then
            self.targets[button].up = buttons[i-3]
            self.targets[buttons[i-3]].down = button
        elseif i == 3 then
            self.targets[button].up = NextPageButton
            self.targets[NextPageButton].down = button
        else
            self.targets[button].up = PrevPageButton
            self.targets[PrevPageButton].down = button
            self.targets[NextPageButton].down = button
        end
        if self.find_toy and button.itemID == self.find_toy then
            old_target = button
            self.find_toy = nil
        end
    end

    if old_target and not self.targets[old_target] then
        -- Must have been a toy button which is no longer displayed.
        old_target = buttons[#buttons]
    end
    return old_target or buttons[1]
end

function ToyBoxHandler:OnAction(button)
    assert(button == "Button4")
    local target = self:GetTarget()
    if target and target.itemID then
        self.find_toy = target.itemID
        self.context_menu:Open(target, target.itemID)
    end
end


function ToyContextMenu:__constructor()
    __super(self)

    self.menuitem_use = self:CreateSecureButton("Use", {type="toy"})

    self.menuitem_set_favorite = self:CreateButton("Set favorite",
        function() self:DoSetFavorite(self.toy_id, true) end)

    self.menuitem_remove_favorite = self:CreateButton("Remove favorite",
        function() self:DoSetFavorite(self.toy_id, false) end)
end

function ToyContextMenu:Configure(button, toy_id)
    self.toy_id = toy_id

    self.menuitem_use:SetAttribute("toy", toy_id)
    self:AppendButton(self.menuitem_use)

    local favorite_item
    if C_ToyBox.GetIsFavorite(toy_id) then
        favorite_item = self.menuitem_remove_favorite
    else
        favorite_item = self.menuitem_set_favorite
    end
    self:AppendButton(favorite_item)
end

function ToyContextMenu:DoSetFavorite(toy_id, favorite)
    C_ToyBox.SetIsFavorite(toy_id, favorite)
end

---------------------------------------------------------------------------

function HeirloomsJournalHandler:__constructor()
    __super(self, HeirloomsJournal)
    self.cancel_func = CollectionsJournalHandler.CancelMenu
    self.tab_handler = CollectionsJournalHandler.instance.tab_handler
    self.on_prev_page = self.frame.PagingFrame.PrevPageButton
    self.on_next_page = self.frame.PagingFrame.NextPageButton
end

---------------------------------------------------------------------------

function WardrobeCollectionFrameHandler:__constructor()
    __super(self, WardrobeCollectionFrame)
    self.cancel_func = CollectionsJournalHandler.CancelMenu
    self.tab_handler = CollectionsJournalHandler.instance.tab_handler
    self.on_prev_page =
        self.frame.ItemsCollectionFrame.PagingFrame.PrevPageButton
    self.on_next_page =
        self.frame.ItemsCollectionFrame.PagingFrame.NextPageButton
end

---------------------------------------------------------------------------

local WarbandSceneContextMenu = class(WoWXIV.UI.ContextMenu)

function WarbandSceneJournalHandler:__constructor()
    __super(self, WarbandSceneJournal)
    self.cancel_func = CollectionsJournalHandler.CancelMenu
    self.tab_handler = CollectionsJournalHandler.instance.tab_handler
    local PagingControls = self.frame.IconsFrame.Icons.Controls.PagingControls
    self.on_prev_page = PagingControls.PrevPageButton
    self.on_next_page = PagingControls.NextPageButton
    self.has_Button4 = true  -- Used to open context menu.
    hooksecurefunc(self.frame.IconsFrame.Icons, "DisplayViewsForCurrentPage",
                   function() self:RefreshTargets() end)

    -- Campsite context menu and associated cursor handler.
    self.context_menu = WarbandSceneContextMenu()
    self.context_menu_handler = MenuCursor.ContextMenuHandler(self.context_menu)
end

function WarbandSceneJournalHandler:RefreshTargets()
    local old_target = self:GetTarget()
    self:SetTarget(nil)
    self:SetTarget(self:SetTargets(old_target))
end

function WarbandSceneJournalHandler:SetTargets(old_target)
    local old_target_index = old_target and self.targets[old_target].icon_index

    local f = self.frame
    local Controls = f.IconsFrame.Icons.Controls
    local FilterCheck = Controls.ShowOwned.Checkbox
    local PrevPageButton = Controls.PagingControls.PrevPageButton
    local NextPageButton = Controls.PagingControls.NextPageButton
    self.targets = {
        [FilterCheck] = {can_activate = true, lock_highlight = true,
                         left = NextPageButton, right = PrevPageButton},
        [PrevPageButton] = {can_activate = true, lock_highlight = true,
                            left = FilterCheck, right = NextPageButton},
        [NextPageButton] = {can_activate = true, lock_highlight = true,
                            left = PrevPageButton, right = FilterCheck},
    }
    local bottom_row = {FilterCheck, PrevPageButton, NextPageButton}

    local icons = f.IconsFrame.Icons:GetFrames()
    local initial
    for i, icon in ipairs(icons) do
        local bottom = bottom_row[i>3 and i-3 or i]
        self.targets[icon] = {icon_index = i,  -- For internal use.
                              lock_highlight = true, send_enter_leave = true,
                              left = icons[i==1 and #icons or i-1],
                              right = icons[i==#icons and 1 or i+1],
                              down = bottom}
        self.targets[bottom].up = icon
        if i >= 4 then
            self.targets[icon].up = icons[i-3]
            self.targets[icons[i-3]].down = button
        else
            self.targets[icon].up = bottom
            self.targets[bottom].down = icon
        end
        if i == old_target_index then
            initial = icon
        end
    end

    if old_target_index and not initial then
        -- Must have been a campsite icon which is no longer displayed.
        -- (FIXME: we can't currently test this because there aren't yet
        -- enough campsites to overflow the first page)
        initial = icons[#icons]
    elseif old_target and not old_target_index then
        -- Must have been one of the filter/paging buttons.
        initial = old_target
    end
    return initial or icons[1]
end

function WarbandSceneJournalHandler:OnAction(button)
    assert(button == "Button4")
    local target = self:GetTarget()
    if target and self.targets[target].icon_index then
        self.context_menu:Open(target, target.elementData.warbandSceneID)
    end
end


function WarbandSceneContextMenu:__constructor()
    __super(self)

    self.menuitem_set_favorite = self:CreateButton("Set favorite",
        function() self:DoSetFavorite(self.scene_id, true) end)

    self.menuitem_remove_favorite = self:CreateButton("Remove favorite",
        function() self:DoSetFavorite(self.scene_id, false) end)
end

function WarbandSceneContextMenu:Configure(button, scene_id)
    self.scene_id = scene_id

    local favorite_item
    if C_WarbandScene.IsFavorite(scene_id) then
        favorite_item = self.menuitem_remove_favorite
    else
        favorite_item = self.menuitem_set_favorite
    end
    self:AppendButton(favorite_item)
end

function WarbandSceneContextMenu:DoSetFavorite(scene_id, favorite)
    C_WarbandScene.SetFavorite(scene_id, favorite)
end
