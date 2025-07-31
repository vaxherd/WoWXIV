local _, WoWXIV = ...
assert(WoWXIV.Gamepad.MenuCursor)
local MenuCursor = WoWXIV.Gamepad.MenuCursor

local class = WoWXIV.class

---------------------------------------------------------------------------

local ItemSocketingFrameHandler = class(MenuCursor.AddOnMenuFrame)
ItemSocketingFrameHandler.ADDON_NAME = "Blizzard_ItemSocketingUI"
MenuCursor.Cursor.RegisterFrameHandler(ItemSocketingFrameHandler)

function ItemSocketingFrameHandler:__constructor()
    __super(self, ItemSocketingFrame)
    self.cursor_show_item = true
end

function ItemSocketingFrameHandler:SetTargets()
    local f = self.frame
    self.targets = {
        [f.Sockets[1]] =
            {can_activate = true,  -- Gem removal is a protected function.
             lock_highlight = true, is_default = true,
             up = ItemSocketingSocketButton, down = ItemSocketingSocketButton,
             left = f.Sockets[1], right = f.Sockets[1]},
        [ItemSocketingSocketButton] =  -- the "Apply" button
            {can_activate = true, lock_highlight = true,
             up = f.Sockets[1], down = f.Sockets[1],
             left = false, right = false}
    }
    for i = 2, 3 do
        socket = f.Sockets[i]
        if socket:IsShown() then
            self.targets[socket] =
                {can_activate = true, lock_highlight = true,
                 up = ItemSocketingSocketButton,
                 down = ItemSocketingSocketButton,
                 left = f.Sockets[i-1], right = f.Sockets[1]}
            self.targets[f.Sockets[1]].left = socket
            self.targets[f.Sockets[i-1]].right = socket
            self.targets[ItemSocketingSocketButton].up = socket
            self.targets[ItemSocketingSocketButton].down = socket
        end
    end
end

function ItemSocketingFrameHandler:OnMove(old_target, new_target)
    for i = 1, 3 do
        local socket = self.frame.Sockets[i]
        if new_target == socket then
            self.targets[ItemSocketingSocketButton].up = socket
            self.targets[ItemSocketingSocketButton].down = socket
            return
        end
    end
end
