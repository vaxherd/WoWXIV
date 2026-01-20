WoWXIV - Final Fantasy XIV-style UI tweaks for World of Warcraft
================================================================

Author: vaxherd  
Source: https://github.com/vaxherd/WoWXIV  
License: Public domain (with exceptions, see below)


End-of-life notice
------------------
WoWXIV is no longer being developed due to restrictions introduced in
WoW patch 12.0 (Midnight) which prevent most features of the addon from
working.  Blizzard has explicitly stated an intent to prevent addons
from adding features not in the base UI, and I have no desire to try and
see what pieces of it might still function in that environment.


Overview
--------
WoWXIV is a World of Warcraft addon which applies various tweaks to the
WoW user interface to provide a visual and gamepad experience closer to
that of Final Fantasy XIV.  Specific features include:

- FFXIV-style party and enmity lists, including a condensed party list
  display more suitable for raids

- FFXIV-style top-of-screen health/aura/cast bars for target and focus
  (with an option to move other top-of-screen widgets out of the way)

- FFXIV-style "flying text" showing damage, healing, buffs/debuffs, and
  obtained items

- Coordinate display on the minimap and world map

- An FFXIV-style chat window and combat log

- Additional FFXIV-style text commands, notably `/itemsearch` to search
  all item storage (even when not at a bank) and `/?` to display help
  text for a specific command (also with an API for external addons to
  register their own help text)

- Various improvements to gamepad support, including right-stick zoom
  and a menu cursor

WoWXIV also includes a rudimentary development environment with a text
editor and Lua interaction frame, which can be used to edit the addon's
source code within the game.


Installation
------------
Just copy the source tree into a `WoWXIV` folder under `Interface/AddOns`
in your World of Warcraft installation.  WoWXIV has no external
dependencies.

Alternatively, to make use of the in-game development environment to
edit the addon inside WoW, place this source tree outside the World of
Warcraft installation and run the Python script `tools/overlay-ctl.py`
to install it to the AddOns folder.  This builds a copy of the addon
source code into the addon itself so that the data is available in the
game environment.  The same Python script can be used to extract changes
made to that data back to the host PC.  See the documentation at the top
of the script for details.


Configuration
-------------
WoWXIV includes a standard settings panel which can be accessed either
from the AddOns tab of the WoW settings window, or directly with the
`/wowxiv` (or just `/xiv`) text command.  The individual configuration
settings should be self-explanatory.

While not configurable from the GUI, some in-game fonts (notably the
font used for flying text) can be changed by manually adding relevant
entries to the addon's configuration data.  See the documentation for
the `WoWXIV.SetFont()` function in `util.lua` for details.


In-game development environment
-------------------------------
The in-game text editor can be opened with the `/xivedit` (`/xe`) chat
command or by pressing Ctrl-Alt-E; pass a filename (see below) after the
command to load that file into the editor.  An empty editor frame in Lua
interaction mode, allowing Lua code to be executed within the editor
buffer, can be opened with `/xivlua` (`/xl`) or Ctrl-Alt-L.

The editor is designed in the style of the Emacs text editor found on
Unix systems; for example, text is cut ("killed") with Ctrl-W and pasted
("yanked") with Ctrl-Y.  Each editor frame has its own independent text
buffer.

The environment also includes a persistent filesystem into which editor
files can be saved (Ctrl-X Ctrl-S to save, Ctrl-X Ctrl-W "write file" to
save under a new name) and from which they can be loaded (Ctrl-X Ctrl-F
"find file" to load a new file, Ctrl-X I "insert file" to insert a file
into the current buffer).  Pathnames follow the Unix style, starting
with a slash (e.g. `/dir/file.lua`), and are case-sensitive.  The
command `/xivfs` (`/xf`) can be used to perform some basic filesystem
operations; see the help (`/? xivfs`) for a list of supported
subcommands.

If installed with the addon code built in (see Installation above), the
addon code is available under the `/wowxiv` path: `/wowxiv/WoWXIV.lua`
and so forth.  Saving over any of these files will store the updated
data in a persistent data store which will be read the next time the
addon is loaded.

Note that this was mostly a "fun project" to occupy my spare time and
see what was possible within WoW's addon framework.  It was not intended
to be a serious attempt at creating an IDE within the game, and it
should not be taken as such.

See the source code under `dev/` for details.


Caveats
-------
WoWXIV was developed with an intended audience of one, namely me.  I've
put it online in case anyone else finds it useful, but many things I
would not consider changing are hardcoded (as mentioned above), and in
particular, UI element layout and sizing is designed around my specific
windowing setup (2560x1440 with default UI scaling), so the layout will
probably break at different resolutions or UI scale factors.


License details
---------------
This addon is released into the public domain; you can change or copy it
as you like, though I would appreciate credit if you find any parts of
the addon useful in other projects.

As an exception to the above, the font file `fonts/VeraMono.ttf` is
distributed under its own license, which may be found in
`fonts/COPYRIGHT.TXT`.  This license also allows free-of-charge
redistribution, subject to certain limitations; see the license for
details.
