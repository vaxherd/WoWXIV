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
    local f = self.frame.SocketingContainer
    local sockets = WoWXIV.maptn(function(i) return f["Socket"..i] end, 3)
    self.targets = {
        [sockets[1]] =
            {can_activate = true,  -- Gem removal is a protected function.
             lock_highlight = true, is_default = true,
             up = f.ApplySocketsButton, down = f.ApplySocketsButton,
             left = sockets[1], right = sockets[1]},
        [f.ApplySocketsButton] =  -- the "Apply" button
            {can_activate = true, lock_highlight = true,
             up = sockets[1], down = sockets[1],
             left = false, right = false}
    }
    for i = 2, 3 do
        socket = sockets[i]
        if socket:IsShown() then
            self.targets[socket] =
                {can_activate = true, lock_highlight = true,
                 up = f.ApplySocketsButton,
                 down = f.ApplySocketsButton,
                 left = sockets[i-1], right = sockets[1]}
            self.targets[sockets[1]].left = socket
            self.targets[sockets[i-1]].right = socket
            self.targets[f.ApplySocketsButton].up = socket
            self.targets[f.ApplySocketsButton].down = socket
        end
    end
end

function ItemSocketingFrameHandler:OnMove(old_target, new_target)
    local f = self.frame.SocketingContainer
    for i = 1, 3 do
        local socket = f["Socket"..i]
        if new_target == socket then
            self.targets[f.ApplySocketsButton].up = socket
            self.targets[f.ApplySocketsButton].down = socket
            return
        end
    end
end
