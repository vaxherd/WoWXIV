WoWXIV - Final Fantasy XIV-style UI tweaks for World of Warcraft
================================================================

Author: vaxherd  
Source: https://github.com/vaxherd/WoWXIV  
License: Public domain


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
  all item storage (even when not at a bank or void storage NPC) and
  `/?` to display help text for a specific command (also with an API for
  external addons to register their own help text)

- Various improvements to gamepad support, including right-stick zoom
  and a menu cursor


Installation
------------
Just copy the source tree into a `WoWXIV` (or otherwise appropriately
named) folder under `Interface/AddOns` in your World of Warcraft
installation.  WoWXIV has no external dependencies.


Configuration
-------------
WoWXIV includes a standard settings panel which can be accessed either
from the AddOns tab of the WoW settings window, or directly with the
`/wowxiv` (or just `/xiv`) text command.  The individual configuration
settings should be self-explanatory.


Caveats
-------
WoWXIV was developed with an intended audience of one, namely me.  I've
put it online in case anyone else finds it useful, but many things I
would not consider changing are hardcoded (as mentioned above), and in
particular, UI element layout and sizing is designed around my specific
windowing setup (2560x1440 with UI scaling disabled), so the layout will
probably break at different resolutions or UI scale factors.  I'll try
to respond to feature requests or bug reports as time permits, but if
you're interested in significantly expanding this addon, you'll probably
have more luck forking it and improving it yourself.
