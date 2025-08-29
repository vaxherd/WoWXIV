local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

assert(WoWXIV.UI.ContextMenu)  -- Ensure proper load order.

---------------------------------------------------------------------------

local CollectionsJournalHandler = class(MenuCursor.MenuFrame)
MenuCursor.Cursor.RegisterFrameHandler(CollectionsJournalHandler)
local MountJournalHandler = class(MenuCursor.StandardMenuFrame)
local PetJournalHandler = class(MenuCursor.StandardMenuFrame)
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
                          up = false, down = fasle}
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

    local mount_text
    if C_MountJournal.NeedsFanfare(button.mountID) then
        mount_text = "Unwrap"
    elseif select(4, C_MountJournal.GetMountInfoByID(button.mountID)) then
        mount_text = "Dismount"
    else
        mount_text = "Mount"
    end
    self.menuitem_mount:SetText(
        mount_text.." "..GetBindingText(WoWXIV.Config.GamePadMenuButton3()))
    self:AppendButton(self.menuitem_mount)

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

function PetJournalHandler:__constructor()
    __super(self, PetJournal)
    self.cancel_func = CollectionsJournalHandler.CancelMenu
    self.tab_handler = CollectionsJournalHandler.instance.tab_handler
end

---------------------------------------------------------------------------

function ToyBoxHandler:__constructor()
    __super(self, ToyBox)
    self.cancel_func = CollectionsJournalHandler.CancelMenu
    self.tab_handler = CollectionsJournalHandler.instance.tab_handler
    self.on_prev_page = self.frame.PagingFrame.PrevPageButton
    self.on_next_page = self.frame.PagingFrame.NextPageButton
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
    local TOYS_PER_PAGE = 18  -- local constant in Blizzard_ToyBox.lua
    for i = 1, TOYS_PER_PAGE do
        local button = f.iconsFrame["spellButton"..i]
        if not button or not button:IsShown() then break end
        tinsert(buttons, button)
    end
    for i, button in ipairs(buttons) do
        self.targets[button] = {can_activate = true, lock_highlight = true,
                                left = buttons[i==1 and #buttons or i-1],
                                right = buttons[i==#buttons and 1 or i+1],
                                down = ((i-1)%3==2 and NextPageButton
                                        or PrevPageButton)}
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
    end

    if old_target and not self.targets[old_target] then
        -- Must have been a toy button which is no longer displayed.
        old_target = buttons[#buttons]
    end
    return old_target or buttons[1]
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

function WarbandSceneJournalHandler:__constructor()
    __super(self, WarbandSceneJournal)
    self.cancel_func = CollectionsJournalHandler.CancelMenu
    self.tab_handler = CollectionsJournalHandler.instance.tab_handler
    local PagingControls = self.frame.IconsFrame.Icons.Controls.PagingControls
    self.on_prev_page = PagingControls.PrevPageButton
    self.on_next_page = PagingControls.NextPageButton
end
