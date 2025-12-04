local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

local floor = math.floor
local min = math.min
local tinsert = tinsert

assert(WoWXIV.UI.ContextMenu)  -- Ensure proper load order.

---------------------------------------------------------------------------

local CollectionsJournalHandler = class(MenuCursor.MenuFrame)
MenuCursor.Cursor.RegisterFrameHandler(CollectionsJournalHandler)
local MountJournalHandler = class(MenuCursor.StandardMenuFrame)
local PetJournalHandler = class(MenuCursor.StandardMenuFrame)
local PetSpellSelectHandler = class(MenuCursor.StandardMenuFrame)
local ToyBoxHandler = class(MenuCursor.StandardMenuFrame)
local HeirloomsJournalHandler = class(MenuCursor.StandardMenuFrame)
local WardrobeItemsFrameHandler = class(MenuCursor.StandardMenuFrame)
local WardrobeSetsFrameHandler = class(MenuCursor.StandardMenuFrame)
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
    class.instance_WardrobeItemsFrame = WardrobeItemsFrameHandler()
    class.instance_WardrobeSetsFrame = WardrobeSetsFrameHandler()
    class.instance_WarbandSceneJournal = WarbandSceneJournalHandler()
    class.panel_instances = {class.instance_MountJournal,
                             class.instance_PetJournal,
                             class.instance_ToyBox,
                             class.instance_HeirloomsJournal,
                             class.instance_WardrobeItemsFrame,
                             class.instance_WardrobeSetsFrame,
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
            local parent = panel_instance.frame:GetParent()
            if parent ~= WardrobeCollectionFrame or parent:IsShown() then
                panel_instance:OnShow()
                return
            end
        end
    end
end

function CollectionsJournalHandler:OnHide()
    for _, panel_instance in ipairs(self.panel_instances) do
        if panel_instance.frame:IsShown() then
            local parent = panel_instance.frame:GetParent()
            if parent ~= WardrobeCollectionFrame or parent:IsShown() then
                panel_instance:OnHide()
                return
            end
        end
    end
end

function CollectionsJournalHandler:OnTabCycle(direction)
    if WardrobeCollectionFrame:IsShown() then
        -- Include the Items and Sets sub-tabs in the overall cycle.
        if direction > 0 and WardrobeCollectionFrame.selectedTab == 1 then
            WardrobeCollectionFrame:SetTab(2)
            return
        end
        if direction < 0 and WardrobeCollectionFrame.selectedTab == 2 then
            WardrobeCollectionFrame:SetTab(1)
            return
        end
    end
    local new_index =
        (PanelTemplates_GetSelectedTab(self.frame) or 0) + direction
    if new_index < 1 then
        new_index = self.frame.numTabs
    elseif new_index > self.frame.numTabs then
        new_index = 1
    end
    local tab = self.frame.Tabs[new_index]
    tab:GetScript("OnClick")(tab, "LeftButton", true)
    if WardrobeCollectionFrame:IsShown() then
        -- We just tabbed onto Appearances, so select the proper sub-tab.
        WardrobeCollectionFrame:SetTab(direction>0 and 1 or 2)
    end
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
        f.ScrollBox, function(data)
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
        target_frame:Click("LeftButton")
        self.context_menu:Open(target_frame.DragButton, target_frame)
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

function MountContextMenu:Configure(drag_button, button)
    self.mount_button = button

    local id = button.mountID
    local index = button.index
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

    if C_MountJournal.GetIsFavorite(index) then
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
            f.ScrollBox, function(data)
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
    -- See note in button loop below.
    local function OnEnterToyButton(button)
        self:OnEnterToyButton(button)
    end
    local function OnLeaveToyButton(button)
        self:OnLeaveToyButton(button)
    end

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
        -- Toy button OnEnter behavior has two issues:
        -- (1) If we blindly set send_enter_leave, we get a GameTooltip
        --     error on open because apparently button.itemID is not set
        --     until later.
        -- (2) If we use send_enter_leave at all, we taint the button in
        --     a way that blocks toys from working.  (As a corollary, we
        --     can't clear the new-toy fanfare by moving the menu cursor
        --     to it.)
        self.targets[button] = {can_activate = true, lock_highlight = true,
                                on_enter = OnEnterToyButton,
                                on_leave = OnLeaveToyButton,
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
        -- Must have been a button which is no longer displayed.
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

function ToyBoxHandler:OnEnterToyButton(button)
    if button.itemID then
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        if GameTooltip:SetToyByItemID(button.itemID) then
            button.UpdateTooltip = function(...) self:OnEnterToyButton(...) end
        else
            button.UpdateTooltip = nil
        end
    end
end

function ToyBoxHandler:OnLeaveToyButton(button)
    GameTooltip:Hide()
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
    self.has_Button4 = true  -- Does nothing (placeholder for context menu).
    hooksecurefunc(self.frame, "RefreshView",
                   function() self:RefreshTargets() end)
end

function HeirloomsJournalHandler:RefreshTargets()
    local old_target = self:GetTarget()
    self:SetTarget(nil)
    self:SetTarget(self:SetTargets(old_target))
end

function HeirloomsJournalHandler:SetTargets(old_target)
    local old_row = old_target and self.targets[old_target].row
    local old_col = old_target and self.targets[old_target].col

    local f = self.frame
    local PrevPageButton = f.PagingFrame.PrevPageButton
    local NextPageButton = f.PagingFrame.NextPageButton
    self.targets = {
        [PrevPageButton] = {can_activate = true, lock_highlight = true,
                            left = NextPageButton, right = NextPageButton},
        [NextPageButton] = {can_activate = true, lock_highlight = true,
                            left = PrevPageButton, right = PrevPageButton},
    }

    --[[
        Heirloom buttons use the same 3x6 layout as the toy box, but
        perhaps because there are also section headers interspersed,
        the buttons don't have any explicit position notation, and we
        have to derive the positions ourselves.  We work from the
        following assumptions (true as of 11.2.0):

        - Icons are allocated from HeirloomsJournal.heirloomEntryFrames
          in display order (rows top-to-bottom, icons left-to-right).

        - Once a frame is created in HeirloomsJournal.heirloomEntryFrames,
          it will never be changed (removed, moved around in the array, etc).

        - Vertical padding between adjacent rows (when there is no header
          line between them) is less than the size of an icon.
    ]]--

    local buttons = {}
    local row, col, last_y
    for i, button in ipairs(self.frame.heirloomEntryFrames) do
        if not button:IsShown() then break end
        local y = button:GetTop()
        if not row then
            row, col, last_y = 1, 1, y
        elseif y == last_y then
            col = col+1
        else
            if last_y - y > button:GetHeight()*2 then
                row = row+2
            else
                row = row+1
            end
            col, last_y = 1, y
        end
        tinsert(buttons, {button, row, col})
    end
    for i, entry in ipairs(buttons) do
        local button, row, col = unpack(entry)
        self.targets[button] = {row = row, col = col,  -- For internal use.
                                can_activate = true, lock_highlight = true,
                                send_enter_leave = true,
                                left = buttons[i==1 and #buttons or i-1][1],
                                right = buttons[i==#buttons and 1 or i+1][1]}
        if col == 3 then
            self.targets[button].down = NextPageButton
            self.targets[NextPageButton].up = button
        else
            self.targets[button].down = PrevPageButton
            self.targets[PrevPageButton].up = button
        end
        local up
        for j = i-1, 1, -1 do
            if buttons[j][2] < row and buttons[j][3] == col then
                up = buttons[j][1]
                break
            end
        end
        if up then
            self.targets[button].up = up
            self.targets[up].down = button
        elseif col == 3 then
            self.targets[button].up = NextPageButton
            self.targets[NextPageButton].down = button
        else
            self.targets[button].up = PrevPageButton
            self.targets[PrevPageButton].down = button
            self.targets[NextPageButton].down = button
        end
    end

    if old_row then
        -- Look for the closest button to the position of the previous
        -- target.  Note that we can't shortcut this by checking whether
        -- the previous target was seen, because it may now be in a
        -- different position!  We want to preserve cursor position, not
        -- icon index.  When there's nothing at the previous cursor
        -- position, we take the rather simplistic approach of moving the
        -- cursor to the previous icon in display order (there will always
        -- be such an icon, since the top row is never empty).
        local best
        for _, entry in ipairs(buttons) do
            local button, row, col = unpack(entry)
            if row > old_row then
                break  -- Passed the previous position, so we're done.
            end
            best = button
            if row == old_row and col == old_col then
                break  -- Exact match, we're done.
            end
        end
        assert(best)
        old_target = best
    end
    return old_target or (buttons[1] and buttons[1][1])
end

function HeirloomsJournalHandler:OnAction(button)
    assert(button == "Button4")
    -- There's nothing to put on a context menu for heirloom icons
    -- (except maybe "Use", but we already have the regular confirm
    -- button for that), but we consume Button4 presses anyway to avoid
    -- unintentionally opening the map (which would close this frame).
end

---------------------------------------------------------------------------

local cache_WardrobeItemDropdown = {}

local WardrobeItemContextMenu = class(WoWXIV.UI.ContextMenu)

function WardrobeItemsFrameHandler:__constructor()
    -- Appearance to select (see ToyBoxHandler for logic).
    self.find_appearance = nil

    __super(self, WardrobeCollectionFrame.ItemsCollectionFrame)
    self.cancel_func = CollectionsJournalHandler.CancelMenu
    self.tab_handler = CollectionsJournalHandler.instance.tab_handler
    self.on_prev_page = self.frame.PagingFrame.PrevPageButton
    self.on_next_page = self.frame.PagingFrame.NextPageButton
    self.has_Button3 = true  -- Used to cycle equipment types.
    self.has_Button4 = true  -- Used to open context menu.
    hooksecurefunc(self.frame, "UpdateItems",
                   function() self:MaybeRefreshTargets() end)

    self.context_menu = WardrobeItemContextMenu()
    self.context_menu_handler = MenuCursor.ContextMenuHandler(self.context_menu)
end

function WardrobeItemsFrameHandler:OnShow()
    self.find_appearance = nil
    __super(self)
end

function WardrobeItemsFrameHandler:OnFocus()
    if self.find_appearance then
        -- The appearance list doesn't have a FindPageFor() function like
        -- the toy box does, so we have to look up the page ourselves.
        -- Logic follows WardrobeItemsCollectionMixin:ResetPage().
        local f = self.frame
        local visuals = f:GetFilteredVisualsList()
        for i, visual in ipairs(visuals) do
            if visual.visualID == self.find_appearance then
                local page = CollectionWardrobeUtil.GetPage(i, f.PAGE_SIZE)
                f.PagingFrame:SetCurrentPage(page)
                f:UpdateItems()
                break
            end
        end
    end
end

function WardrobeItemsFrameHandler:MaybeRefreshTargets()
    -- Changing categories transiently clears all item buttons.  If we
    -- blindly RefreshTargets() at that point, we lose the current cursor
    -- position, so make sure at least one item button is shown.
    if not self.frame.ModelR1C1:IsShown() then return end
    return self:RefreshTargets()
end

function WardrobeItemsFrameHandler:RefreshTargets()
    local old_target = self:GetTarget()
    self:SetTarget(nil)
    self:SetTarget(self:SetTargets(old_target))
end

function WardrobeItemsFrameHandler:SetTargets(old_target)
    local old_row = old_target and self.targets[old_target].row
    local old_col = old_target and self.targets[old_target].col

    local f = self.frame
    local ClassDropdown = WardrobeCollectionFrame.ClassDropdown

    self.targets = {}
    local initial
    if not old_row then
        initial = old_target
    end

    local top_row = {ClassDropdown}
    for _, button in ipairs(f.SlotsFrame.Buttons) do
        -- Have to check IsShown() here because the shoulder slot has a
        -- dummy button which is always hidden.
        if button:IsShown() then
            tinsert(top_row, button)
        end
    end
    self.targets[ClassDropdown] =
        {on_click = function() self:OnClickDropdown(ClassDropdown) end,
         lock_highlight = true, left = top_row[#top_row], right = top_row[2],
         up = f.PagingFrame.PrevPageButton}
    for i = 2, #top_row do
        local slot = top_row[i]
        self.targets[slot] = {can_activate = true, lock_highlight = true,
                              send_enter_leave = true, left = top_row[i-1],
                              right = top_row[i==#top_row and 1 or i+1],
                              up = f.PagingFrame.PrevPageButton}
    end

    local items = {}
    for i = 1, 3*6 do
        local row = floor((i-1)/6) + 1
        local col = (i-1)%6 + 1
        local item = f["ModelR"..row.."C"..col]
        if not item:IsShown() then break end
        self.targets[item] = {row = row, col = col,  -- For internal use.
                              lock_highlight = true, send_enter_leave = true}
        tinsert(items, item)
        if row == old_row and col == old_col then
            initial = item
        end
        if item.visualInfo.visualID == self.find_appearance then
            initial = item
            old_target, old_row, old_col = nil, nil, nil
            self.find_appearance = nil
        end
    end
    for i, item in ipairs(items) do
        self.targets[item].left = items[i==1 and #items or i-1]
        self.targets[item].right = items[i==#items and 1 or i+1]
        if i > 6 then
            self.targets[item].up = items[i-6]
        end
        if i <= #items-6 then
            self.targets[item].down = items[i+6]
        end
    end
    if #items > 0 then
        -- Mapping from top row button to item column.
        local movement_map = {1, 2,2,3,3,3,4,4, 5,5,5,6, 6,6,6,6}
        assert(#movement_map == #top_row)
        for i, item_index in ipairs(movement_map) do
            local item = items[min(item_index, #items)]
            self.targets[top_row[i]].down = item
            if not self.targets[item].up then
                self.targets[item].up = top_row[i]
            end
        end
    end 

    if f.WeaponDropdown:IsShown() then
        self.targets[f.WeaponDropdown] =
            {on_click = function() self:OnClickDropdown(f.WeaponDropdown) end,
             lock_highlight = true, left = false, right = false,
             up = top_row[-4], down = items[min(6, #items)]}
        for i = 1, min(6, #items) do
            self.targets[items[i]].up = f.WeaponDropdown
        end
    end

    self.targets[f.PagingFrame.PrevPageButton] =
        {can_activate = true, lock_highlight = true,
         up = items[min(16, #items)], down = ClassDropdown,
         left = f.PagingFrame.NextPageButton,
         right = f.PagingFrame.NextPageButton}
    self.targets[f.PagingFrame.NextPageButton] =
        {can_activate = true, lock_highlight = true,
         up = items[min(16, #items)], down = ClassDropdown,
         left = f.PagingFrame.PrevPageButton,
         right = f.PagingFrame.PrevPageButton}

    if old_row and not initial then  -- Changed to a truncated final page.
        initial = items[#items]
    end
    if initial and not initial:IsShown() then  -- For WeaponDropdown.
        initial = nil
    end
    return initial or items[1]
end

function WardrobeItemsFrameHandler:EnterTarget(target)
    -- HACK: avoid nil deref when this subframe was previously open and the
    -- collections frame is opened
    if target.GetParent and target:GetParent() == self.frame then
        if not self.frame.transmogLocation then return end
    end
    __super(self, target)
    if target.visualInfo then
        self.cur_item = target.visualInfo.visualID
    end
end

function WardrobeItemsFrameHandler:OnClickDropdown(dropdown)
    dropdown:SetMenuOpen(not dropdown:IsMenuOpen())
    if dropdown:IsMenuOpen() then
        -- FIXME: we could probably use this logic to avoid having to pass
        -- a getIndex() function; need to verify that it works everywhere
        local order = {}
        local index = 1
        MenuUtil.TraverseMenu(dropdown:GetMenuDescription(), function(desc)
            order[desc] = index
            index = index + 1
        end)
        local menu, initial_target = self.SetupDropdownMenu(
            dropdown, cache_WardrobeItemDropdown,
            function(selection) return order[selection] end,
            function() self:RefreshTargets() end)
        menu:Enable(initial_target)
    end
end

function WardrobeItemsFrameHandler:OnAction(button)
    local target = self:GetTarget()
    if button == "Button3" then
        local buttons = self.frame.SlotsFrame.Buttons
        local next = 1
        for i, button in ipairs(buttons) do
            if button.SelectedTexture:IsShown() then
                next = (i==#buttons and 1 or i+1)
                if not buttons[next]:IsShown() then  -- shoulder button garbo
                    next = next+1
                end
                break
            end
        end
        buttons[next]:Click("LeftButton")
    else
        assert(button == "Button4")
        self.find_appearance = target.visualInfo.visualID
        self.context_menu:Open(target, target.visualInfo.visualID)
    end
end


function WardrobeItemContextMenu:__constructor()
    __super(self)

    self.menuitem_set_favorite = self:CreateButton("Set favorite",
        function() self:DoSetFavorite(self.appearance_id, true) end)

    self.menuitem_remove_favorite = self:CreateButton("Remove favorite",
        function() self:DoSetFavorite(self.appearance_id, false) end)
end

function WardrobeItemContextMenu:Configure(button, appearance_id)
    self.appearance_id = appearance_id

    if C_TransmogCollection.GetIsAppearanceFavorite(appearance_id) then
        self:AppendButton(self.menuitem_remove_favorite)
    else
        self:AppendButton(self.menuitem_set_favorite)
    end
end

function WardrobeItemContextMenu:DoSetFavorite(button, favorite)
    C_TransmogCollection.SetIsAppearanceFavorite(self.appearance_id, favorite)
end

---------------------------------------------------------------------------

local cache_VariantSetsDropdown = {}

local WardrobeSetContextMenu = class(WoWXIV.UI.ContextMenu)

function WardrobeSetsFrameHandler:__constructor()
    -- Currently selected appearance set.
    self.cur_set = nil
    -- Is the cursor currently on the details pane?
    self.in_details = false

    __super(self, WardrobeCollectionFrame.SetsCollectionFrame)
    self.cancel_func = self.CancelFrame
    self.tab_handler = CollectionsJournalHandler.instance.tab_handler
    self.has_Button3 = true  -- Used to switch between left and right panes.
    self.has_Button4 = true  -- Used to open context menu.

    self.context_menu = WardrobeSetContextMenu()
    self.context_menu_handler = MenuCursor.ContextMenuHandler(self.context_menu)
end

function WardrobeSetsFrameHandler:CancelFrame()
    if self.in_details then
        self.in_details = false
        self:RefreshTargets()
    else
        CollectionsJournalHandler.CancelMenu()
    end
end

function WardrobeSetsFrameHandler:OnShow()
    self.in_details = false
    __super(self)
end

function WardrobeSetsFrameHandler:RefreshTargets()
    self:SetTarget(nil)
    self:SetTarget(self:SetTargets())
end

function WardrobeSetsFrameHandler:SetTargets()
    local f = self.frame
    self.targets = {}
    if self.in_details then
        local dropdown = f.DetailsFrame.VariantSetsDropdown
        self.targets[dropdown] =
            {on_click = function() self:OnClickDropdown() end,
             lock_highlight = true}
        local items = {}
        for item in f.DetailsFrame.itemFramesPool:EnumerateActive() do
            tinsert(items, item)
        end
        table.sort(items, function(a,b) return a:GetLeft() < b:GetLeft() end)
        for i, item in ipairs(items) do
            self.targets[item] = {send_enter_leave = true,
                                  up = dropdown, down = dropdown,
                                  left = items[i==1 and #items or i-1],
                                  right = items[i==#items and 1 or i+1]}
        end
        return items[1] or dropdown
    else
        local function ClickSet(target)
            self:GetTargetFrame(target):Click("LeftButton")
            self.in_details = true
            self:RefreshTargets()
        end
        local top, bottom, initial = self:AddScrollBoxTargets(
            f.ListContainer.ScrollBox, function(data)
                -- Set the cursor offset to point to the icon, as for mounts.
                local params = {on_click = ClickSet, lock_highlight = true,
                                x_offset = -42}
                return params, data.setID == self.cur_set
            end)
        return initial or top
    end
end

function WardrobeSetsFrameHandler:EnterTarget(target)
    __super(self, target)
    if not self.in_details then
        self.cur_set = self:GetTargetFrame(target).setID
    end
end

function WardrobeSetsFrameHandler:OnClickDropdown()
    local f = self.frame
    local dropdown = f.DetailsFrame.VariantSetsDropdown
    dropdown:SetMenuOpen(not dropdown:IsMenuOpen())
    if dropdown:IsMenuOpen() then
        local order = {}
        local index = 1
        MenuUtil.TraverseMenu(dropdown:GetMenuDescription(), function(desc)
            order[desc] = index
            index = index + 1
        end)
        local menu, initial_target = self.SetupDropdownMenu(
            dropdown, cache_VariantSetsDropdown,
            function(selection) return order[selection] end,
            function() self:RefreshTargets() end)
        menu:Enable(initial_target)
    end
end

function WardrobeSetsFrameHandler:OnAction(button)
    local target = self:GetTarget()
    local target_frame = self:GetTargetFrame(target)
    if button == "Button3" then
        self.in_details = not self.in_details
        self:RefreshTargets()
    else
        assert(button == "Button4")
        target_frame:Click("LeftButton")
        self.context_menu:Open(target_frame, self.frame.selectedSetID)
    end
end


function WardrobeSetContextMenu:__constructor()
    __super(self)

    self.menuitem_set_favorite = self:CreateButton("Set favorite",
        function() self:DoSetFavorite(self.set_id, true) end)

    self.menuitem_remove_favorite = self:CreateButton("Remove favorite",
        function() self:DoSetFavorite(self.set_id, false) end)
end

function WardrobeSetContextMenu:Configure(button, set_id)
    self.set_id = set_id

    if C_TransmogSets.GetIsFavorite(set_id) then
        self:AppendButton(self.menuitem_remove_favorite)
    else
        self:AppendButton(self.menuitem_set_favorite)
    end
end

function WardrobeSetContextMenu:DoSetFavorite(button, favorite)
    C_TransmogSets.SetIsFavorite(self.set_id, favorite)
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
