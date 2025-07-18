local _, WoWXIV = ...
WoWXIV.Gamepad = WoWXIV.Gamepad or {}
local Gamepad = WoWXIV.Gamepad

assert(Gamepad.GamepadBoundButton)  -- Ensure proper load order.

local class = WoWXIV.class

local GameTooltip = GameTooltip
local GetItemCount = C_Item.GetItemCount
local GetItemInfo = C_Item.GetItemInfo
local IsHarmfulItem = C_Item.IsHarmfulItem
local IsHelpfulItem = C_Item.IsHelpfulItem

------------------------------------------------------------------------

-- FIXME: The required target for quest items varies, and is not always
-- obvious from the item data available via the API; for example, Azure
-- Span sidequest "Setting the Defense" (ID 66489) has a quest item
-- "Arch Instructor's Wand" (ID 192471) intended to be used on a targeted
-- friendly NPC, but is neither "helpful" nor "harmful", while Rusziona's
-- Whistle (202293) from Little Scales Daycare quest "What's a Duck?"
-- (72459) is marked "helpful" but requires the player to be targeted in
-- order to fire.  Yet other items explicitly require a target of "none",
-- notably those which use the ground target cursor.  Ideally we would
-- just call UseQuestLogSpecialItem(log_index), but that's a protected
-- function and there's no secure action wrapper for it (as of 11.0.2),
-- so for the meantime we record specific items whose required targets we
-- know and use fallback logic for others.
local ITEM_TARGET = {
    [ 24221] = "none",    -- Bundle of Dragon Bones (9689: Razormaw)
    [ 29482] = "none",    -- Ethereum Essence (10385: Potential for Brain Damage = High)
    [ 29618] = "none",    -- Protectorate Disruptor (10408: Nexus-King Salhadaar)
    [ 34833] = "none",    -- Unlit Torches (11657: Torch Catching)
    [ 35237] = "none",    -- Orb of the Crawler (11891: An Innocent Disguise)
    [ 35828] = "none",    -- Totemic Beacon (11886: Unusual Activity)
    [ 71964] = "none",    -- Iron Stock (29508: Baby Needs Two Pair of Shoes)
    [ 71967] = "none",    -- Horseshoe (29508: Baby Needs Two Pair of Shoes)
    [ 71977] = "none",    -- Darkmoon Craftsman's Kit (29517: Eyes on the Prizes)
    [ 72018] = "none",    -- Discarded Weapon (29510: Putting Trash to Good Use)
    [ 72048] = "none",    -- Darkmoon Banner Kit (29520: Banners, Banners Everywhere!)
    [ 72049] = "none",    -- Darkmoon Banner (29520: Banners, Banners Everywhere!)
    [ 72056] = "none",    -- Plump Frogs (29509: Putting the Crunch in the Frog)
    [ 72057] = "none",    -- Breaded Frog (29509: Putting the Crunch in the Frog)
    [118330] = "none",    -- Pile of Weapons (37565: The Right Weapon for the Job)
    [120960] = "skip",    -- Tidestone Vault Key (37469: The Tidestone: Shattered)  -- Using it doesn't do anything (despite the in-game description "Use: Open the Tidestone Vault Door"); having it in your inventory lets you open the door by interacting with it (the door).
    [122100] = "none",    -- Soul Gem (37653: Demon Souls)
    [127030] = "target",  -- Granny's Flare Grenades (38646: A Sight For Sore Eyes)
    [127295] = "none",    -- Blazing Torch (39060: Combustible Contagion)
    [127988] = "none",    -- Bug Sprayer (39277: Spray and Prey)
    [128687] = "none",    -- Royal Summons (38035: A Royal Summons)
    [128772] = "target",  -- Branch of the Runewood (39791: Lay Them to Rest)
    [129161] = "none",    -- Stormforged Horn (40003: Stem the Tide)
    [130260] = "target",  -- Thaedris's Elixir (40321: Feathersong's Redemption)
    [130944] = "none",    -- Needle Coral (40364: Bubble Trouble)
    [131931] = "none",    -- Khadgar's Wand (39987: Trail of Echoes)
    [132120] = "skip",    -- Stormwind Portal Stone (40519: Legion: The Legion Returns)
    [132883] = "none",    -- First Arcanist's Token (40011: Oculeth's Workshop)
    [133756] = "none",    -- Fresh Mound of Flesh (40901: Grimwing the Devourer)
    [133882] = "none",    -- Trap Rune (40965: Lay Waste, Lay Mines)
    [133897] = "none",    -- Telemancy Beacon (40956: Survey Says...)
    [133925] = "target",  -- Fel Lash (40919: Fel Bent for Leather)
    [133999] = "target",  -- Inert Crystal (40971: Overwhelming Distraction)
    [135534] = "none",    -- Heavy Torch (41467: The Only Choice We Can Make)
    [136410] = "none",    -- Kalec's Image Crystal (41626: A New Threat)
    [136600] = "none",    -- Enchanted Party Mask (41834: The Masks We Wear)
    [136605] = "target",  -- Solendra's Compassion (41485: Moonwhisper Rescue)
    [136970] = "none",    -- Mask of Mirror Image (42079: Masquerade)
    [137120] = "target",  -- Stack Of Vellums (39877: In the Loop)
    [137189] = "none",    -- Satyr Horn (41464: Not Here, Not Now, Not Ever)
    [137299] = "target",  -- Nightborne Spellblade (40947: Special Delivery / 42962: Secret Correspondence)
    [139463] = "target",  -- Felbat Toxin Salve (43376: Problem Salver)
    [139882] = "target",  -- Vial of Hippogryph Pheromones (40963: Take Them in Claw)
    [140257] = "none",    -- Advanced Telemancy Beacon (43565: Bring Home the Beacon)
    [140319] = "none",    -- Khadgar's Beacon (44004: Bringer of the Light)  -- This is a teleport item we'd normally skip, but it's only granted during a scenario in order to exit the scenario, so we make it available on the button.
    [140916] = "target",  -- Satchel of Locklimb Powder (42090: Skittering Subjects)
    [141253] = "target",  -- Nightblade Pendant (44067: Consolidating Power)
    [141652] = "skip",    -- Mana Divining Stone (44672: Ancient Mana)  -- This has effect by being in the inventory rather than being used.
    [141878] = "none",    -- Arcane-Infused Vial (44684: Corruption Runs Deep)
    [142065] = "target",  -- Dusk Lily Sigil (44723: More Like Me)
    [142118] = "none",    -- Telemancy Orbs (44719: Breaching the Sanctum)
    [142208] = "none",    -- Essence of Wyrmtongue (44733: The Power of Corruption)
    [142213] = "none",    -- Empowered Arcane Ward (44685: Reclaiming the Ramparts)
    [142216] = "none",    -- Nightborne Armaments (44769: Arming the Populace)
    [142260] = "target",  -- Arcane Nullifier (44842: Shield, Meet Spell)
    [142375] = "none",    -- Dispelling Crystal (44928: Something's Not Quite Right...)
    [142399] = "none",    -- Experimental Targeting Orb (45063: The Felsoul Experiments)
    [142400] = "none",    -- Advanced Targeting Orb (45062: Resisting Arrest)
    [142405] = "none",    -- Advanced Telemancy Beacon (45065: Survey the City)
    [142446] = "none",    -- Leysight Spectacles (44813: Ley Line Interference)
    [142491] = "none",    -- Experimental Telemancy Orb (45064: Felborne No More)
    [142509] = "none",    -- Withered Targeting Orb (44816: Continued Exposure)
    [143597] = "target",  -- Fruit of the Arcan'dor (45260: One Day at a Time / 45261: Continuing the Cure / 45262: A Message From Ly'leth / 45263: Eating Before the Meeting / 45265: Feeding the Rebellion / 45266: A United Front / 45267: Before the Siege / 45268: The Advisor and the Arcanist / 45269: A Taste of Freedom)
    [143718] = "target",  -- Corpse Collector (45346: Shambling Specimens)
    [143773] = "target",  -- Contagion Counteragent (45342: Administering Aid)
    [143863] = "target",  -- Fel Exfoliator (45726: The Tainted Marsh)
    [151563] = "target",  -- Hallowed Prayer Effigy (47180: The Pulsing Madness)
    [151570] = "target",  -- Lightbound Crystal (47844: Recurring Madness)
    [151624] = "target",  -- Y'mera's Arcanocrystal (47882: Conservation of Magic)
    [152110] = "none",    -- Talisman of the Prophet (47987: Preventive Measures)
    [152408] = "none",    -- Stolen Pylon Core (46818: Defenseless and Afraid)
    [152472] = "target",  -- Chieftain's Salve (48483: A Stranger's Plea)
    [152593] = "none",    -- Essence of Light (48559: An Offering of Light)
    [152657] = "target",  -- Target Designator (48640: The Immortal Squadron)
    [152971] = "target",  -- Talisman of the Prophet (48691: Soul Chain)
    [157540] = "none",    -- Battered S.E.L.F.I.E. Camera (51092: Picturesque Boralus)
    [167231] = "none",    -- Delormi's Synchronous Thread (53807: A Stitch in Time)
    [168035] = "none",    -- Mawrat Harness (Torghast)
    [168482] = "none",    -- Benthic Sealant (56160: Plug the Geysers)
    [170498] = "none",    -- Deadsoul Hound Harness (Torghast)
    [170499] = "none",    -- Maw Seeker Harness (Torghast)
    [170540] = "target",  -- Ravenous Anima Cell (Torghast)
    [173373] = "skip",    -- Faol's Hearthstone (40705: Priestly Matters)
    [173379] = "target",  -- Purify Stone (41966: House Call)
    [173430] = "skip",    -- Nexus Teleport Scroll (41628: Eyes of the Dragon)
    [173523] = "skip",    -- Tirisfal Camp Scroll (40710: Blade in Twilight)
    [173691] = "target",  -- Anima Drainer (57932: Resource Drain)
    [173692] = "target",  -- Nemea's Javelin (58040: With Lance and Larion)
    [174043] = "none",    -- Phylactery of Arin'gore (61708: Drawing Out the Poison)
    [174197] = "target",  -- Loremaster's Notebook (58471: Aggressive Notation)
    [175055] = "none",    -- H'partho's Whistle (58830: Aqir Instincts)
    [175827] = "player",  -- Ani-Matter Orb (57245: Ani-Matter Animator)
    [177836] = "target",  -- Wingpierce Javelin (59771: History of Corruption)
    [177880] = "player",  -- Primordial Muck (59808: Muck It Up)
    [178464] = "player",  -- Discarded Harp (60188: Go Beyond! [Lonely Matriarch])
    [178791] = "none",    -- Carved Cloudfeather Call (60366: WANTED: Darkwing)
    [180008] = "none",    -- Resonating Anima Core (60609: Who Devours the Devourers?)
    [180009] = "none",    -- Resonating Anima Mote (60609: Who Devours the Devourers?)
    [180249] = "none",    -- Stone Fiend Tracker (60655: A Stolen Stone Fiend)
    [180274] = "none",    -- Torch (60770: Squish and Burn)
    [180607] = "none",    -- Cypher of Blinding (61075: A Spark of Light)
    [180876] = "player",  -- Aqueous Material Accumulator (61189: Further Gelatinous Research)
    [181284] = "none",    -- Gormling in a Bag (61394: Gormling Toss: Tranquil Pools)
    [182189] = "player",  -- Fae Flute (61717: Gormling Piper: Tranquil Pools)
    [182303] = "player",  -- Assassin's Soulcloak (61765: Words of Warding)
    [182457] = "none",    -- Mirror Fragment (61967: Remedial Lessons)
    [182600] = "none",    -- Gormling in a Bag (62051: Gormling Toss: Spirit Glen)
    [182611] = "player",  -- Fae Flute (62068: Gormling Piper: Crumbled Ridge)
    [183725] = "none",    -- Moth Net (62459: Go Beyond! [Selenia Moth])
    [184513] = "none",    -- Containment Orb (63040: Guaranteed Delivery)
    [184876] = "none",    -- Cohesion Crystal (63455: Dead On Their Feet)
    [185949] = "target",  -- Korayn's Spear (63841: The Skyhunt)
    [186089] = "target",  -- Niya's Staff (63840: They Grow Up So Quickly)
    [186097] = "none",    -- Heirmir's Runeblade (63945: The Soul Blade)
    [186199] = "target",  -- Lady Moonberry's Wand (63971: Snail Stomping)
    [186448] = "target",  -- Mikanikos' Restorative Contraption (64043: We Need a Healer - You!)
    [186474] = "target",  -- Korayn's Javelin (64080: Down to Earth)
    [186569] = "target",  -- Angry Needler Nest (63974: That's Going to Sting)
    [186695] = "target",  -- Lovely Pet Bandage (64196: Pet Up)
    [187012] = "none",    -- Unbalanced Riftstone (63951: A Shady Place)
    [187128] = "none",    -- Find-A-Spy (64167: Pets Detective)
    [187186] = "target",  -- Orb of Deception (Torghast)
    [187516] = "none",    -- Firim's Forge-Tap (64579: Hollow Efforts)
    [187816] = "target",  -- Irresistible Goop (64960: Feed the Annelids)
    [187820] = "none",    -- Piece of Goop (64960: Feed the Annelids)
    [187908] = "none",    -- Firim's Spare Forge-Tap (Zereth Mortis)
    [187941] = "none",    -- Depleted Automa Core (64761: Core Competency)
    [187999] = "none",    -- Fishing Portal (65102: Fish Eyes)
    [188134] = "player",  -- Bronze Timepiece (65118: How to Glide with Your Dragon)
    [188139] = "player",  -- Bronze Timepiece (65120: How to Dive with Your Dragon)
    [188169] = "player",  -- Bronze Timepiece (65133: How to Use Momentum with Your Dragon)
    [188788] = "none",    -- Zephyreal Generator (65268: Bzzzzt!)
    [189384] = "target",  -- Ornithological Medical Kit (66071: Flying Rocs)
    [189454] = "target",  -- Feather-Plucker 3300 (65374: It's Plucking Time)
    [189554] = "none",    -- Proto Wrangler Rope (65264: Operation: Relocation)
    [190188] = "player",  -- The Chirpsnide Auto-Excre-Collector (65490: Explosive Excrement)
    [191160] = "none",    -- Sweetsuckle Bloom (66020: Omens and Incense)
    [191681] = "player",  -- Im-PECK-able Screechflight Disguise (65778: Screechflight Potluck)
    [191763] = "player",  -- Im-PECK-able Screechflight Disguise v2 (66299: The Awaited Egg-splosion)
    [191928] = "player",  -- Brena's Totem (65845: Echoes of the Fallen)
    [191952] = "none",    -- Ley Scepter (65709: Arcane Pruning)
    [191953] = "none",    -- Bag of Helpful Goods (65709: Arcane Pruning)
    [191978] = "none",    -- Bag of Helpful Goods (65852: Straight to the Top)
    [192191] = "none",    -- Tuskarr Fishing Net (66411: Troubled Waters)
    [192436] = "target",  -- Ruby Spear (66122: Proto-Fight)
    [192465] = "none",    -- Wulferd's Award-Winning Camera (66524: Amateur Photography / 66525: Competitive Photography / 66527: Professional Photography / 66529: A Thousand Words)
    [192467] = "target",  -- Bandages (66030: Resistance Isn't Futile)
    [192471] = "target",  -- Arch Instructor's Wand (66489: Setting the Defense)
    [192475] = "none",    -- R.A.D.D.E.R.E.R. (66428: Friendship For Granted)
    [192479] = "none",    -- Elemental Focus (65958: Primal Power)
    [192545] = "none",    -- Primal Flame Fragment (66439: Rapid Fire Plans)
    [192555] = "player",  -- Borrowed Breath (66180: Wake the Ancients)
    [192743] = "target",  -- Wild Bushfruit (65907: Favorite Fruit)
    [192749] = "none",    -- Chrono Crystal (66029: Temporal Tuning / 72519: Temporal Two-ning)
    [193064] = "target",  -- Smoke Diffuser (66734: Leave Bee Alone)
    [193212] = "none",    -- Marmoni Rescue Pack (66833: Marmoni in Distress)
    [193569] = "player",  -- Water Testing Flask (66840: Water Safety)
    [193826] = "none",    -- Trusty Dragonkin Rake (66827: Flowers of our Labor / 72991: Warm Dragonfruit Pie)
    [193892] = "target",  -- Wish's Whistle (66680: Counting Sheep)
    [193917] = "target",  -- Rejuvenating Draught (65996: Veteran Reinforcements)
    [193918] = "none",    -- Jar of Fireflies (66830: Hornswoggled!)
    [194434] = "target",  -- Pungent Salve (66893: Beaky Reclamation)
    [194441] = "none",    -- Bottled Water Elemental (66998: Fighting Fire with... Water)
    [194447] = "target",  -- Totem of Respite (66656: Definitely Eternal Slumber)
    [194891] = "target",  -- Arcane Hook (65752: Arcane Annoyances)
    [197805] = "target",  -- Suspicious Persons Scanner (69888: Unusual Suspects)
    [198855] = "none",    -- Throw Net (70438: Flying Fish [and other fish restock dailies])
    [198859] = "none",    -- Revealing Dragon's Eye (66163: Nowhere to Hide)
    [199928] = "none",    -- Flamethrower Torch (70856: Kill it with Fire)
    [200153] = "target",  -- Aylaag Skinning Shear (70990: If There's Wool There's a Way)
    [200526] = "none",    -- Steria's Charm of Invisibility (70338: They Took the Kits)
    [200747] = "none",    -- Zikkori's Water Siphoning Device (70994: Drainage Solutions)
    [202271] = "target",  -- Pouch of Gold Coins (72530: Anyway, I Started Bribing)
    [202293] = "player",  -- Rusziona's Whistle (72459: What's a Duck?)
    [202409] = "none",    -- Zalethgos's Whistle (73007: New Lenses)
    [202642] = "target",  -- Proto-Killing Spear (73194: Up Close and Personal)
    [202714] = "target",  -- M.U.S.T (73221: A Clear State of Mind)
    [202874] = "target",  -- Healing Draught (73398: Too Far Forward)
    [203013] = "player",  -- Niffen Incense (73408: Sniffen 'em Out!)
    [203182] = "none",    -- Fish Food (72651: Carp Care)
    [203621] = "none",    -- Posidriss's Whistle (73014: A Green Who Can't Sleep?)
    [203706] = "target",  -- Hurricane Scepter (74352: Whirling Zephyr)
    [203731] = "target",  -- Enchanted Bandage (74570: Aid Our Wounded / 75374: To Defend the Span)
    [204271] = "none",    -- Blacktalon Napalm (74522: Remnants)
    [204343] = "none",    -- Trusty Dragonkin Rake (66989: Helpful Harvest)
    [204344] = "player",  -- Conductive Lodestone (74988: If You Can't Take the Heat)
    [204365] = "player",  -- Bundle of Ebon Spears (74991: We Have Returned)
    [204698] = "none",    -- Cataloging Camera (73044: Cataloging Horror)
    [205980] = "target",  -- Snail Lasso (72878: Slime Time Live)
    [206369] = "none",    -- Time Trap (76143: Chro-me?)
    [206586] = "none",    -- Epoch Extractor (76142: On Borrowed Time)
    [207084] = "target",  -- Auebry's Marker Pistol (76600: Right Between the Gyro-Optics)
    [208124] = "target",  -- The Dreamer's Essence (76328: A New Brute)
    [208181] = "skip",    -- Shandris's Scouting Report (76317: Call of the Dream)
    [208182] = "player",  -- Bronze Timepiece (77345: The Need For Higher Velocities)
    [208184] = "none",    -- Dreamy Dust (76330: Disarm Specialist)
    [208206] = "none",    -- Teleportation Crystal (77408: Prophecy Stirs)
    [208447] = "none",    -- Purifying Tangle (76518: Root Security)
    [208544] = "none",    -- Frozenheart's Wrath (76386: A Clash of Ice and Fire)
    [208752] = "none",    -- Horn of Cenarius (76389: The Age of Mortals)
    [208841] = "none",    -- True Sight (76550: True Sight)
    [208947] = "none",    -- Enchanted Watering Can (77910: Enchanted Shrubbery)
    [208983] = "none",    -- Yvelyn's Assistance (76520: A Shared Dream)
    [210014] = "none",    -- Mysterious Ageless Seeds (77209: Seed Legacy)
    [210016] = "none",    -- Somnowl's Shroud (76329: In and Out Scout)
    [210227] = "target",  -- Q'onzu's Faerie Feather (76992: Fickle Judgment)
    [210454] = "skip",    -- Spare Hologem (78068: An Artificer's Appeal / 78070: Pressing Deadlines / 78075: Moving Past / 78081: Pain Recedes)
    [211073] = "none",    -- Sentry Flare (78657: The Midnight Sentry)
    [211302] = "target",  -- Slumberfruit (76993: Turtle Power)
    [211435] = "none",    -- Explosive Sticks (78747: The Great Collapse)
    [211483] = "none",    -- Frenzied Sand Globule (78755: Playing in the Mud)
    [211484] = "none",    -- Frenzied Water Globule (78755: Playing in the Mud)
    [211535] = "target",  -- Scroll of Shattering (78532: Erratic Artifacts)
    [211872] = "none",    -- Patrol Torch (76997: Lost in Shadows)
    [211942] = "skip",    -- Water Hose (78656: Hose It Down)  -- Not needed because we get a duty action for it.
    [211945] = "none",    -- Torch of Holy Flame (78688: Cage, Match)
    [212334] = "none",    -- Anti-Fungal Fire Bomb (79356: Antifungal Firestarter)
    [212602] = "target",  -- Titan Emitter (79213: The Anachronism)
    [213271] = "none",    -- Work Orders (78538: Group Effort)
    [213392] = "none",    -- Scent Grenade (79120: Beetle in a Haystack)
    [213539] = "target",  -- Nebb's Poultice (79370: A Poultice for Poison)
    [213629] = "target",  -- Debugger Hat (79539: Electrifying!)
    [215142] = "target",  -- Freydrin's Shillelagh (78574: Boss of the Bosk)
    [215158] = "target",  -- Freydrin's Shillelagh (78573: Keeper's Aid)
    [215467] = "none",    -- Dirt-Cracker Pick (79469: Lurking Below)
    [216664] = "none",    -- Threadling Lure (79960: Taking it To Go)
    [217309] = "none",    -- Arathi Warhorn (78943: Steel and Flames)
    [219198] = "none",    -- Attica's Cave Torch (76169: Glow in the Dark)
    [219284] = "none",    -- Explosive Sticks (81621: Tunnels Be Gone!)
    [219323] = "target",  -- Gelatinous Unguent (81482: Testing Formulae: Gelatinous Unguent)
    [219324] = "target",  -- Roiling Elixir (81501: Testing Formulae: Roiling Elixir)
    [219469] = "target",  -- Fog Beast Tracker (81557: Fog Tags)
    [219525] = "target",  -- Globe of Nourishment (81675: Water the Sheep)
    [219943] = "none",    -- Lamplighter Firearm (80677: Torching Lights)
    [219960] = "none",    -- Honey Drone Vac (81869: Can Catch More Fires with Honey)
    [220483] = "none",    -- Tuning Wand (78718: Strengthen the Wards)
    [222976] = "target",  -- Flame-Tempered Harpoon (82220: Eagle Eye, Eagle Die)
    [223220] = "target",  -- Kaheti All-Purpose Cleaner (82266: Tower Washing Simulator)
    [223322] = "target",  -- Hannan's Scythe (80568: Leave No Trace)
    [223515] = "none",    -- Breastplate and Tinderbox (82284: Remembrance for the Fallen)
    [223988] = "skip",    -- Dalaran Hearthstone (79009: The Harbinger)
    [224104] = "none",    -- Flashfile Thurible (80213: Holy Fire in Rambleshire)
    [224292] = "none",    -- Radiant Fuel Shard (81691: Special Assignment: Shadows Below)
    [224799] = "target",  -- Nizrek's potion (83177: Socialized Medicine)
    [225555] = "none",    -- Periapt of Pure Flame (82585: With Great Pyre)
    [226157] = "target",  -- Semi-Deluxe Noggenfogger Elixirs (83116: Potion Commotion)
    [226217] = "none",    -- Lime (83199: Been Savin' This One)
    [226261] = "none",    -- Sonic Scrambler (83827: Silence the Song)
    [226356] = "player",  -- Spare Venture Co. Uniform (83119: It's Worth a Shot)
    [226823] = "target",  -- Bilgewater Auto-Grappler (84122: Cut the Cameras)
    [227405] = "none",    -- Research Journal (83932: Historical Documents)
    [227551] = "none",    -- Note from Rexxar (84278: Tracking Quest)
    [227664] = "none",    -- Spirit's Whistle (84296: The Trail's Gone Cold)
    [227669] = "skip",    -- Teleportation Scroll (81930: The War Within)
    [228196] = "none",    -- Anti-Darkfuse Pamphlets (83195: Rally the People)
    [228582] = "none",    -- Streamlined Relic (84520: Ancient Curiosity: Utility)
    [228614] = "none",    -- Comprehend Rat Language Potion (83484: Oh, Rats!)
    [228617] = "none",    -- Benatauk's Clue Book (84521: Thoughtful Pursuits)
    [228948] = "target",  -- Jazz's Shrink Ray (84303: Experimental Application / 84304: A Gem-Splitting Headache)
    [228984] = "none",    -- Unbreakable Iron Idol (84519: Ancient Curiosity: Combat)
    [228988] = "none",    -- Rock Reviver (84680: Rock 'n Stone Revival)
    [229424] = "none",    -- Anima Vacuum (85080: An Un-Bee-lievable Solution)
    [230210] = "target",  -- Tranquilizing Dart (85079: Such a Sleebee-head / 85255: Tranquila-Bee)
    [230729] = "none",    -- Appropriated Azerothian Camera (85083: Photogra-Bee / 85261: Bee Roll)
    [230731] = "target",  -- Pitz's Masterwork Invention (84675: Showdown in the Attic)
    [230795] = "none",    -- Experimental Go-Pack (84252: Peak Precision)
    [231164] = "target",  -- Goblin Grapnel (85396: Heaps o' Scrap)
    [231900] = "none",    -- Sample Potion (85515: Free Samples!)
    [232464] = "none",    -- Crumpled Paystub (83123: A Miner Mistake)
    [232466] = "none",    -- Leave the Storm (85113: Special Assignment: Storm's a Brewin)
    [232644] = "none",    -- Broker Disguise Pin (85432: Confuse Their Contacts)
    [232987] = "player",  -- Blood-B-Gone (85945: Side Gig: Blood-B-Gone)
    [233028] = "none",    -- Flamethrower (86201: Watch me Make These Bugs Expire)
    [233222] = "skip",    -- Nullbomb (84865: Divide and Conquer)  -- Provided as a duty action.
    [236641] = "none",    -- Watering Jug (87339: Ongoing Activities)
    [239074] = "none",    -- Void Lure (86786: The Void Hunter)

    -- The following are scenario action spells:
    [-314955] = "none",   -- Sanity Restoration Orb (N'Zoth's Horrific Visions)
    [-357857] = "none",   -- Activate Empowerment (Torghast)
    [-469853] = "none",   -- Drop Candle (Delve: Kriegval's Rest, 11.0 only)
    [-469854] = "none",   -- Drop Air Totem (Delve: Earthen Waterworks, 11.0 only)
}

-- Special cases for quests which don't have items assigned but really should.
local QUEST_ITEM = {
    -- Midsummer Fire Festival quest: An Innocent Disguise
    -- This quest has two items, but only one can be assigned as the
    -- "quest item" in the quest log, so we have to implement the second
    -- manually.
    [11891] = {
        map = 63,  -- Ashenvale
        items = {
            35237,  -- Orb of the Crawler
            35828,  -- Totemic Beacon
        }
    },
    -- Marasmius daily quest: Go Beyond! [Lonely Matriarch]
    [60188] = {
        map = 1565,  -- Ardenweald
        items = {
            178464,  -- Discarded Harp
        }
    },
    -- Ardenweald world quest: Who Devours the Devourers?
    [60609] = {
        map = 1565,  -- Ardenweald
        items = {
            180008,       -- Resonating Anima Core
            {180009, 5},  -- Resonating Anima Mote
        }
    },
    -- Zereth Mortis world quest: Feed the Annelids
    -- The quest properly switches its item as you progress, but we
    -- add this entry to provide a count requirement for Piece of Goop.
    [64960] = {
        map = 1970,  -- Zereth Mortis
        items = {
            187816,       -- Irresistible Goop
            {187820, 6},  -- Piece of Goop
        }
    },
    -- Waking Shores sidequest: Rapid Fire Plans
    [66439] = {
        map = 2022,  -- Waking Shores
        items = {
            {192545, 8},  -- Primal Flame Fragment
        }
    },
    -- Isle of Dorn sidequest: Playing in the Mud
    [78755] = {
        map = 2248,  -- Isle of Dorn
        items = {
            211483,  -- Frenzied Sand Globule
            -- Could also be 211484, Frenzied Water Globule
        }
    },
    -- Ringing Deeps world quest: Special Assignment: Shadows Below
    [81691] = {
        map = 2214,  -- Ringing Deeps
        items = {
            {224292, 3},  -- Radiant Fuel Shard
        }
    },
    -- Undermine sidequest: Garbage Day
    [84672] = {
        map = 2346,  -- Undermine
        items = {
            229805,  -- Last Week's Undermine Inquirer
            229824,  -- Banana Peel
            229825,  -- Dented Can of Kaja'Cola
        }
    },
}

-- Special cases for zone-specific items we always want to have available
-- when in that zone.
local ZONE_ITEM = {
    ["Torghast"] = {  -- Special case because Torghast has so many maps.
        168035,  -- Mawrat Harness
        170498,  -- Deadsoul Hound Harness
        170499,  -- Maw Seeker Harness
        170540,  -- Ravenous Anima Cell
        187186,  -- Orb of Deception
    },
    [1970] = {  -- Zereth Mortis
        187908,  -- Firim's Spare Forge-Tap
    },
}

------------------------------------------------------------------------

-- Helper to get an item or spell icon.
local function GetItemOrSpellIcon(item)
    local icon
    if item < 0 then  -- spell
        local info = C_Spell.GetSpellInfo(-item)
        icon = info and info.iconID
    else
        icon = select(10, GetItemInfo(item))
    end
    return icon
end

-- Custom button used to securely activate quest items.
Gamepad.QuestItemButton = class(Gamepad.GamepadBoundButton)
local QuestItemButton = Gamepad.QuestItemButton

function QuestItemButton:__allocator()
    return Gamepad.GamepadBoundButton:__allocator(
        "WoWXIV_QuestItemButton",
        "SecureActionButtonTemplate, FadeableFrameTemplate")
end

function QuestItemButton:__constructor()
    self:__super("gamepad_use_quest_item",
                 "CLICK WoWXIV_QuestItemButton:LeftButton",
                 "gamepad_select_quest_item",
                 "CLICK WoWXIV_QuestItemButton:RightButton")

    self.item = nil
    self.selected_index = 1  -- Index of item to show if more than 1 available.
    self.selected_item = nil  -- ID of selected item, in case index changes.
    self.pending_update = false
    self.last_update = 0

    -- Place the button between the chat box and action bar.  (This size
    -- just fits with the default UI scale at resolution 2560x1440.)
    self:SetPoint("BOTTOM", -470, 10)
    self:SetSize(224, 112)
    self:SetAlpha(0)
    local holder = self:CreateTexture(nil, "ARTWORK")
    self.holder = holder
    holder:SetAllPoints()
    holder:SetTexture("Interface/ExtraButton/Default")
    local icon = self:CreateTexture(nil, "BACKGROUND")
    self.icon = icon
    icon:SetPoint("CENTER", 0, -1.5)
    icon:SetSize(42, 42)
    local cooldown = CreateFrame("Cooldown", "WoWXIV_QuestItemButtonCooldown",
                                 self, "CooldownFrameTemplate")
    self.cooldown = cooldown
    cooldown:SetAllPoints(icon)

    self:SetAttribute("*type1", "item")
    self:SetAttribute("item", nil)
    self:SetAttribute("spell", nil)
    self:SetAttribute("unit", nil)
    self:RegisterForClicks("LeftButtonDown", "RightButtonDown")
    self:SetScript("OnMouseDown", self.OnMouseDown)
    self:SetScript("OnEnter", self.OnEnter)
    self:SetScript("OnLeave", self.OnLeave)
    self:SetScript("OnEvent", self.OnEvent)

    self:RegisterUnitEvent("UNIT_QUEST_LOG_CHANGED", "player")
    self:RegisterEvent("BAG_UPDATE")  -- for QUEST_ITEM quests
    self:RegisterEvent("BAG_UPDATE_COOLDOWN")
    self:RegisterEvent("PLAYER_TARGET_CHANGED")
    -- We could theoretically dissect ZoneAbilityFrame and work out exactly
    -- which events trigger show/hide of the frame, but the frame itself
    -- makes for a convenient proxy.
    for _, name in ipairs({"Show", "Hide", "SetShown"}) do
        hooksecurefunc(ZoneAbilityFrame, name,
                       function() self:UpdateQuestItem(true) end)
    end

    self:UpdateQuestItem()
end

function QuestItemButton:OnMouseDown(button)
    if button == "RightButton" then
        local _, n = self:IterateQuestItems()
        if self.selected_index >= n then
            self.selected_index = 1
        else
            self.selected_index = self.selected_index + 1
        end
        self.selected_item = nil
        self:UpdateQuestItem(true)
        self.selected_item = item
    end
end

function QuestItemButton:OnEnter()
    if GameTooltip:IsForbidden() then return end
    if not self:IsVisible() then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    self:UpdateTooltip()
end

function QuestItemButton:OnLeave()
    if GameTooltip:IsForbidden() then return end
    GameTooltip:Hide()
end

function QuestItemButton:OnEvent(event)
    if event == "PLAYER_TARGET_CHANGED" then
        self:UpdateItemTarget()
    else
        -- Always update immediately on inventory change, since using one
        -- quest item to create another (e.g. combining Resonating Anima Mote
        -- into Resonating Anima Core) has a short delay before the created
        -- item appears in the inventory.
        local force = (event == "BAG_UPDATE")
        self:UpdateQuestItem(force)
    end
end

function QuestItemButton:UpdateTooltip()
    if GameTooltip:IsForbidden() or GameTooltip:GetOwner() ~= self then
        return
    end
    if self.item then
        GameTooltip:SetItemByID(self.item)
        GameTooltip:Show()
    else
        GameTooltip:Hide()
    end
end

-- If |force| is false, calls will be throttled to no more than 1/second.
-- (Throttled calls will be delayed and rerun in the background.)
function QuestItemButton:UpdateQuestItem(force)
    if self.pending_update and not force then return end
    local now = GetTime()
    if InCombatLockdown() or (not force and now - self.last_update < 1) then
        if not self.pending_update then
            self.pending_update = true
            C_Timer.After(1, function()
                self.pending_update = false
                self:UpdateQuestItem(force)
            end)
        end
        return
    end
    self.last_update = now

    local index = 0
    local function MaybeChooseItem(this_item)  -- Predicate for iteration.
        index = index + 1
        if self.selected_item then
            if this_item == self.selected_item then
                self.selected_index = index
                return true
            else
                return false
            end
        else
            return index == self.selected_index
        end
    end
    local item, _, enable = self:IterateQuestItems(MaybeChooseItem)
    if not item then
        -- Either no quest items are available at all, or selected_index was
        -- out of range or selected_item was not found (perhaps because a
        -- quest was just completed).  Reset to the first item in all cases.
        self.selected_item = nil
        self.selected_index = 1
        index = 0
        item, _, enable = self:IterateQuestItems(MaybeChooseItem)
    end
    self.selected_item = item

    if item then
        if item < 0 then
            self:SetAttribute("*type1", "spell")
            self:SetAttribute("spell", -item)
        else
            self:SetAttribute("*type1", "item")
            -- Note that we have to use the "item:" format rather than just
            -- the numeric item ID, because the latter would be treated as an
            -- inventory index instead.  We can't use the item name because
            -- that fails when multiple items have the same name, such as the
            -- quest items for the various gormling world quests in Ardenweald.
            self:SetAttribute("item", "item:"..item)
        end
        self:UpdateItemTarget()
        self:SetEnabled(enable)
        local icon_id = (GetItemOrSpellIcon(item)
                         or "Interface/ICONS/INV_Misc_QuestionMark")
        self.icon:SetTexture(icon_id)
        local brightness = enable and 1.0 or 0.5
        self.icon:SetVertexColor(brightness, brightness, brightness)
        if self:GetAlpha() < 1 and (self.fadeout:IsPlaying() or not self.fadein:IsPlaying()) then
            self.fadeout:Stop()
            self.fadein:Play()
        end
        local start, duration, rate
        if item < 0 then
            local cooldown = C_Spell.GetSpellCooldown(-item)
            if cooldown and cooldown.isEnabled then
                start = cooldown.startTime
                duration = cooldown.duration
                rate = cooldown.modRate
            else
                start, duration = 0, 0, 1
            end
        else
            local enable
            start, duration, enable = C_Item.GetItemCooldown(item)
            rate = 1
            if not enable then
                start, duration = 0, 0
            end
        end
        self.cooldown:SetCooldown(start, duration, rate)
    else
        self:SetAttribute("item", nil)
        self:SetAttribute("spell", nil)
        if self:GetAlpha() > 0 and (self.fadein:IsPlaying() or not self.fadeout:IsPlaying()) then
            self.fadein:Stop()
            self.fadeout:Play()
        end
    end

    self.item = item
    self:UpdateTooltip()
end

function QuestItemButton:UpdateItemTarget()
    if InCombatLockdown() then return end
    local item = self.selected_item
    if not item then return end
    local target = ITEM_TARGET[item]
    if not target then
        -- We should never hit this point for spells (item < 0), but
        -- default to "target" for them.
        if item < 0 or IsHelpfulItem(item) or IsHarmfulItem(item) then
            target = "target"
        else
            target = "player"
        end
    end
    if target == "target" and not UnitExists("target") then
        target = "none"  -- Fall back to right-stick targeting.
    end
    if #target > 0 then
       self:SetAttribute("unit", target)
    else
       self:SetAttribute("unit", nil)
    end
end

-- Returns a tuple (item, n, enable), where |item| is the ID of the first
-- item for which the predicate returned true, |n| is the index of that
-- item in the overall quest item list, and |enable| is a flag indicating
-- whether the quest item button should be enabled (true) or visible but
-- disabled (false).  If no item is found (or no predicate is given),
-- |item| is nil, |n| is the number of available quest items, and |enable|
-- is false.  The predicate function should accept a single argument, which
-- is the item ID.  When a scenario action is selected, the "item ID" is a
-- negative number whose arithmetic inverse is the spell ID.
function QuestItemButton:IterateQuestItems(predicate)
    local index = 0
    local player_map = C_Map.GetBestMapForUnit("player")

    if WoWXIV_config["questitem_scenario_action"] and ScenarioObjectiveTracker:IsShown() then
        for _, ability in ipairs(C_ZoneAbility.GetActiveAbilities()) do
            index = index + 1
            if predicate and predicate(-ability.spellID) then
                return -ability.spellID, index, true
            end
        end
        for frame in ScenarioObjectiveTracker.spellFramePool:EnumerateActive() do
            index = index + 1
            -- The spell button doesn't have a getter equivalent to SetSpell(),
            -- so we have to break encapsulation here.
            local spell_id = frame.SpellButton.spellID
            if predicate and predicate(-spell_id) then
                return -spell_id, index, true
            end
        end
    end

    for map, items in pairs(ZONE_ITEM) do
        local on_map
        if zone == "Torghast" then
            -- Torghast items are deleted when leaving, so we can
            -- unconditionally include them when in the inventory.
            on_map = true
        else
            on_map = (player_map == map)
        end
        if on_map then
            for _, item in ipairs(items) do
                if GetItemCount(item) > 0 then
                    index = index + 1
                    if predicate and predicate(item) then
                        return item, index, true
                    end
                end
            end
        end
    end

    for quest, info in pairs(QUEST_ITEM) do
        if C_QuestLog.IsOnQuest(quest) then
            if player_map == info.map then
                for _, quest_item in ipairs(info.items) do
                    local amount = 1
                    if type(quest_item) == "table" then
                        quest_item, amount = unpack(quest_item)
                    end
                    local owned = GetItemCount(quest_item)
                    if owned > 0 then
                        index = index + 1
                        if predicate and predicate(quest_item) then
                            return quest_item, index, owned >= amount
                        end
                    end
                end
            end
        end
    end

    for quest_index = 1, C_QuestLog.GetNumQuestLogEntries() do
        local link, icon, charges, show_when_complete =
            GetQuestLogSpecialItemInfo(quest_index)
        if link then
            -- GetItemInfoFromHyperlink() is defined in Blizzard's
            -- SharedXML/LinkUtil.lua
            local item = GetItemInfoFromHyperlink(link)
            -- Explicitly exclude certain items from the button
            -- (generally items we don't want to use by accident,
            -- like warp items for scenario starting quests)
            if ITEM_TARGET[item] ~= "skip" then
                index = index + 1
                if predicate and predicate(item) then
                    return item, index, true
                end
            end
        end
    end

    return nil, index, false
end
