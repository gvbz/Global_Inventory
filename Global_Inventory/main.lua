-- Global Inventory 1.6.2 (AC:Unreal API 2 companion, client v146 or newer).
--
-- Saves every character's items and searches the items of all your characters
-- on this server, like Oracle of Dereth's Inventory window (with Virindi Global
-- Inventory). Column texts, categories and filters follow Oracle of Dereth 2.5.0.
--
-- Collecting: while a character is logged in, its packs and worn items come
-- from the client's inventory ("snapshot_fields"). Items that carry details
-- only after an appraisal are appraised in the background, one per second
-- (Settings: "Appraise items automatically"); salvage, components, food and
-- similar items need none. An item saved earlier with the same name and
-- appearance is not appraised again. Each character's items are saved to
-- Profiles/global_inventory/Library/Items/<server>_<character>_<part>.json,
-- listed in Library/Chars/<server>_<character>.json.
--
-- Searching: every saved character of this server is read when the plugin
-- starts. Categories (none ticked: all), the sub-filters of the last ticked
-- category, Doubles and the text box narrow the list. Text: every word must
-- appear; "quoted phrases"; word*2 (at least twice); "Legendary X" is kept as a
-- phrase. Columns: Character, Item Name, Type, Effect, Info, Details; click a
-- header to sort (Info with weapons listed: OD, attack, melee defense, workmanship). Clicking a row puts
-- its description in chat and selects the item when this character has it.
--
-- Saved items are the base set: shown at login, updated as the client reports
-- them, dropped only after 30 s without inventory changes once their pack has
-- items. Item properties are saved too (Library/Props), so rows of an older
-- format are made again without appraising. The search (filter, boxes, sort) is
-- shared by all characters (Library/Settings/Search). Settings: Export to JSON.
--
-- Lightweight: the inventory is only looked at when its revision changes, rows
-- are only rebuilt for items that changed, and the window is sent only when it
-- changes.

local SIZE, SMALL = 15, 12
local PAGE_ROWS = 20
local RESULT_LIMIT = 5000
local PART_ROWS = 200           -- rows per saved part (each read returns at most 256 KiB)
local BUILD_PER_TICK = 12       -- rows built per update
local SEARCH_USER = 175000      -- searching and sorting per update for a filter or sort you changed (about Lua steps)
local SEARCH_WORK = 100000      -- the same for updates when the items changed
local SEARCH_SHARED = 40000     -- the same while items are built, imported or read
-- what each part costs, about (Lua steps)
-- (measured in the client's sandbox: a search of 4,900 items by category or text is 100k to 170k)
local COST = {row = 22, word = 6, sub = 25, full = 30, text = 60,   -- a row tested; each text word; each sub-filter box; the full check (word*2); its search text made
  key = 25, newkey = 75, put = 16, scan = 6}                       -- a sort key used; made; a row put in order (and its category's list); descending: finding the groups
local PREP_PER_TICK = 1500      -- rows given their search text per idle update
local ID_TIMEOUT = 6            -- s to wait for an appraisal before trying another item
local ID_TRIES = 3
local SAVE_DELAY = 10           -- s without changes before saving
local SAVE_GAP = 30             -- s between saves
local SAVE_MAX_WAIT = 60        -- s: save at least this often while items keep changing (appraisals)
local PROP_ROWS = 100           -- items per saved properties part
local FORMAT = 3                -- how rows are written; rows of another format are made again from their properties
local QUIET = 30                -- s without inventory changes before a saved item that hasn't appeared is dropped
local REBUILD_PER_TICK = 12      -- like BUILD_PER_TICK
local SEL_COLOR, STUB_COLOR, NOTE_COLOR = "#FFA040", "#969696", "#00FFFF"
local SHADE = "#FFFFFF12"

local SKILL = {[1] = "Axe", [2] = "Bow", [3] = "Crossbow", [4] = "Dagger", [5] = "Mace", [6] = "Melee Defense", [7] = "Missile Defense", [8] = "Sling", [9] = "Spear", [10] = "Staff", [11] = "Sword", [12] = "Thrown Weapons", [13] = "Unarmed Combat", [14] = "Arcane Lore", [15] = "Magic Defense", [16] = "Mana Conversion", [18] = "Item Tinkering", [19] = "Assess Person", [20] = "Deception", [21] = "Healing", [22] = "Jump", [23] = "Lockpick", [24] = "Run", [27] = "Assess Creature", [28] = "Weapon Tinkering", [29] = "Armor Tinkering", [30] = "Magic Item Tinkering", [31] = "Creature Enchantment", [32] = "Item Enchantment", [33] = "Life Magic", [34] = "War Magic", [35] = "Leadership", [36] = "Loyalty", [37] = "Fletching", [38] = "Alchemy", [39] = "Cooking", [40] = "Salvaging", [41] = "Two Handed Combat", [42] = "Gearcraft", [43] = "Void", [44] = "Heavy Weapons", [45] = "Light Weapons", [46] = "Finesse Weapons", [47] = "Missile Weapons", [48] = "Shield", [49] = "Dual Wield", [50] = "Recklessness", [51] = "Sneak Attack", [52] = "Dirty Fighting", [53] = "Challenge", [54] = "Summoning"}
local MASTERY = {[1] = "Unarmed Weapon", [2] = "Sword", [3] = "Axe", [4] = "Mace", [5] = "Spear", [6] = "Dagger", [7] = "Staff", [8] = "Bow", [9] = "Crossbow", [10] = "Thrown", [11] = "Two Handed Combat"}
local SLAYERSPECIES = {[1] = "Olthoi", [2] = "Banderling", [3] = "Drudge", [4] = "Mosswart", [5] = "Lugian", [6] = "Tumerok", [7] = "Mite", [8] = "Tusker", [9] = "Phyntos Wasp", [10] = "Rat", [11] = "Auroch", [12] = "Cow", [13] = "Golem", [14] = "Undead", [15] = "Gromnie", [16] = "Reedshark", [17] = "Armoredillo", [18] = "Fae", [19] = "Virindi", [20] = "Wisp", [21] = "Knathtead", [22] = "Shadow", [23] = "Mattekar", [24] = "Mumiyah", [25] = "Rabbit", [26] = "Sclavus", [27] = "Shallows Shark", [28] = "Monouga", [29] = "Zefir", [30] = "Skeleton", [31] = "Human", [32] = "Shreth", [33] = "Chittick", [34] = "Moarsman", [35] = "Olthoi Larvae", [36] = "Slithis", [37] = "Deru", [38] = "Fire Elemental", [39] = "Snowman", [40] = "Unknown", [41] = "Bunny", [42] = "Lightning Elemental", [43] = "Rockslide", [44] = "Grievver", [45] = "Niffis", [46] = "Ursuin", [47] = "Crystal", [48] = "Hollow Minion", [49] = "Scarecrow", [50] = "Idol", [51] = "Empyrean", [52] = "Hopeslayer", [53] = "Doll", [54] = "Marionette", [55] = "Carenzi", [56] = "Siraluun", [57] = "Aun Tumerok", [58] = "Hea Tumerok", [59] = "Simulacrum", [60] = "Acid Elemental", [61] = "Frost Elemental", [62] = "Elemental", [63] = "Statue", [64] = "Wall", [65] = "Altered Human", [66] = "Device", [67] = "Harbinger", [68] = "Dark Sarcophagus", [69] = "Chicken", [70] = "Gotrok Lugian", [71] = "Margul", [72] = "Bleached Rabbit", [73] = "Nasty Rabbit", [74] = "Grimacing Rabbit", [75] = "Burun", [76] = "Target", [77] = "Ghost", [78] = "Fiun", [79] = "Eater", [80] = "Penguin", [81] = "Ruschk", [82] = "Thrungus", [83] = "Viamontian Knight", [84] = "Remoran", [85] = "Swarm", [86] = "Moar", [87] = "Enchanted Arms", [88] = "Sleech", [89] = "Mukkir", [90] = "Merwart", [91] = "Food", [92] = "Paradox Olthoi", [93] = "Harvest", [94] = "Energy", [95] = "Apparition", [96] = "Aerbax", [97] = "Touched", [98] = "Blighted Moarsman", [99] = "Gear Knight", [100] = "Gurog", [101] = "Anekshay"}
local SET_FULL = {[2] = "Test", [4] = "Carraida's Benediction", [5] = "Noble Relic Set", [6] = "Ancient Relic Set", [7] = "Relic Alduressa Set", [8] = "Shou-jen Set", [9] = "Empyrean Rings Set", [10] = "Arm, Mind, Heart Set", [11] = "Coat of the Perfect Light Set", [12] = "Leggings of Perfect Light Set", [13] = "Soldier's Set", [14] = "Adept's Set", [15] = "Archer's Set", [16] = "Defender's Set", [17] = "Tinker's Set", [18] = "Crafter's Set", [19] = "Hearty Set", [20] = "Dexterous Set", [21] = "Wise Set", [22] = "Swift Set", [23] = "Hardened Set", [24] = "Reinforced Set", [25] = "Interlocking Set", [26] = "Flame Proof Set", [27] = "Acid Proof Set", [28] = "Cold Proof Set", [29] = "Lightning Proof Set", [30] = "Dedication Set", [31] = "Gladiatorial Clothing Set", [32] = "Ceremonial Clothing", [33] = "Protective Clothing", [34] = "Noobie Armor", [35] = "Sigil of Defense", [36] = "Sigil of Destruction", [37] = "Sigil of Fury", [38] = "Sigil of Growth", [39] = "Sigil of Vigor", [40] = "Heroic Protector Set", [41] = "Heroic Destroyer Set", [42] = "Olthoi Armor D Red", [43] = "Olthoi Armor C Rat", [44] = "Olthoi Armor C Red", [45] = "Olthoi Armor D Rat", [46] = "Upgraded Relic Alduressa Set", [47] = "Upgraded Ancient Relic Set", [48] = "Upgraded Noble Relic Set", [49] = "Weave of Alchemy", [50] = "Weave of Arcane Lore", [51] = "Weave of Armor Tinkering", [52] = "Weave of Assess Person", [53] = "Weave of Light Weapons", [54] = "Weave of Missile Weapons", [55] = "Weave of Cooking", [56] = "Weave of Creature Enchantment", [57] = "Weave of Missile Weapons", [58] = "Weave of Finesse", [59] = "Weave of Deception", [60] = "Weave of Fletching", [61] = "Weave of Healing", [62] = "Weave of Item Enchantment", [63] = "Weave of Item Tinkering", [64] = "Weave of Leadership", [65] = "Weave of Life Magic", [66] = "Weave of Loyalty", [67] = "Weave of Light Weapons", [68] = "Weave of Magic Defense", [69] = "Weave of Magic Item Tinkering", [70] = "Weave of Mana Conversion", [71] = "Weave of Melee Defense", [72] = "Weave of Missile Defense", [73] = "Weave of Salvaging", [74] = "Weave of Light Weapons", [75] = "Weave of Light Weapons", [76] = "Weave of Heavy Weapons", [77] = "Weave of Missile Weapons", [78] = "Weave of Two Handed Combat", [79] = "Weave of Light Weapons", [80] = "Weave of Void Magic", [81] = "Weave of War Magic", [82] = "Weave of Weapon Tinkering", [83] = "Weave of Assess Creature", [84] = "Weave of Dirty Fighting", [85] = "Weave of Dual Wield", [86] = "Weave of Recklessness", [87] = "Weave of Shield", [88] = "Weave of Sneak Attack", [89] = "Ninja_New", [90] = "Weave of Summoning", [91] = "Shrouded Soul", [92] = "Darkened Mind", [93] = "Clouded Spirit", [94] = "Minor Stinging Shrouded Soul", [95] = "Minor Sparking Shrouded Soul", [96] = "Minor Smoldering Shrouded Soul", [97] = "Minor Shivering Shrouded Soul", [98] = "Minor Stinging Darkened Mind", [99] = "Minor Sparking Darkened Mind", [100] = "Minor Smoldering Darkened Mind", [101] = "Minor Shivering Darkened Mind", [102] = "Minor Stinging Clouded Spirit", [103] = "Minor Sparking Clouded Spirit", [104] = "Minor Smoldering Clouded Spirit", [105] = "Minor Shivering Clouded Spirit", [106] = "Major Stinging Shrouded Soul", [107] = "Major Sparking Shrouded Soul", [108] = "Major Smoldering Shrouded Soul", [109] = "Major Shivering Shrouded Soul", [110] = "Major Stinging Darkened Mind", [111] = "Major Sparking Darkened Mind", [112] = "Major Smoldering Darkened Mind", [113] = "Major Shivering Darkened Mind", [114] = "Major Stinging Clouded Spirit", [115] = "Major Sparking Clouded Spirit", [116] = "Major Smoldering Clouded Spirit", [117] = "Major Shivering Clouded Spirit", [118] = "Blackfire Stinging Shrouded Soul", [119] = "Blackfire Sparking Shrouded Soul", [120] = "Blackfire Smoldering Shrouded Soul", [121] = "Blackfire Shivering Shrouded Soul", [122] = "Blackfire Stinging Darkened Mind", [123] = "Blackfire Sparking Darkened Mind", [124] = "Blackfire Smoldering Darkened Mind", [125] = "Blackfire Shivering Darkened Mind", [126] = "Blackfire Stinging Clouded Spirit", [127] = "Blackfire Sparking Clouded Spirit", [128] = "Blackfire Smoldering Clouded Spirit", [129] = "Blackfire Shivering Clouded Spirit", [130] = "Shimmering Shadows", [131] = "Brown Society Locket", [132] = "Yellow Society Locket", [133] = "Red Society Band", [134] = "Green Society Band", [135] = "Purple Society Band", [136] = "Blue Society Band", [137] = "Gauntlet Garb"}
local MATERIAL = {[1] = "Ceramic", [2] = "Porcelain", [4] = "Linen", [5] = "Satin", [6] = "Silk", [7] = "Velvet", [8] = "Wool", [10] = "Agate", [11] = "Amber", [12] = "Amethyst", [13] = "Aquamarine", [14] = "Azurite", [15] = "Black Garnet", [16] = "Black Opal", [17] = "Bloodstone", [18] = "Carnelian", [19] = "Citrine", [20] = "Diamond", [21] = "Emerald", [22] = "Fire Opal", [23] = "Green Garnet", [24] = "Green Jade", [25] = "Hematite", [26] = "Imperial Topaz", [27] = "Jet", [28] = "Lapis Lazuli", [29] = "Lavender Jade", [30] = "Malachite", [31] = "Moonstone", [32] = "Onyx", [33] = "Opal", [34] = "Peridot", [35] = "Red Garnet", [36] = "Red Jade", [37] = "Rose Quartz", [38] = "Ruby", [39] = "Sapphire", [40] = "Smokey Quartz", [41] = "Sunstone", [42] = "Tiger Eye", [43] = "Tourmaline", [44] = "Turquoise", [45] = "White Jade", [46] = "White Quartz", [47] = "White Sapphire", [48] = "Yellow Garnet", [49] = "Yellow Topaz", [50] = "Zircon", [51] = "Ivory", [52] = "Leather", [53] = "Armoredillo Hide", [54] = "Gromnie Hide", [55] = "Reed Shark Hide", [57] = "Brass", [58] = "Bronze", [59] = "Copper", [60] = "Gold", [61] = "Iron", [62] = "Pyreal", [63] = "Silver", [64] = "Steel", [66] = "Alabaster", [67] = "Granite", [68] = "Marble", [69] = "Obsidian", [70] = "Sandstone", [71] = "Serpentine", [73] = "Ebony", [74] = "Mahogany", [75] = "Oak", [76] = "Pine", [77] = "Teak"}
local SALVAGEDESCRIPTION = {[1] = "Increases Armor's Fire Protection by 0.4", [2] = "Changes heritage requirement to Sho", [4] = "Reduces the item's burden by 25%", [5] = "Changes heritage requirement to Viamontian", [6] = "Removes the rank activation requirement", [7] = "Increases the weapon's attack skill bonus by 1%", [8] = "Increases Armor's Cold Protection by 0.4", [10] = "Imbues the target with Minor Focus", [11] = "Imbues the target with Augmented Stamina", [12] = "No Apparent Use", [13] = "Imbues the target with Cold Rending", [14] = "Imbues the target with Wizard's Intellect", [15] = "Imbues the target with Pierce Rending", [16] = "Imbues the target with Critical Strike", [17] = "Imbues the target with Minor Endurance", [18] = "Imbues the target with Minor Strength", [19] = "Imbues the target with Minor Stamina Gain", [20] = "Imbues the target with Augmented Damage", [21] = "Imbues the target with Acid Rending", [22] = "Imbues the target with Crippling Blow", [23] = "Improves a wand's PvM and PvP damage modifier by 1%", [24] = "No Apparent Use", [25] = "Imbues the target with Warrior's Vitality", [26] = "Imbues the target with Slash Rending", [27] = "Imbues the target with Lightning Rending", [28] = "Imbues the target with Minor Willpower", [29] = "Imbues the target with Minor Mana Gain", [30] = "Imbues the target with Warrior's Vigor", [31] = "Increases the item's Maximum Mana by 500", [32] = "Imbues the target with Nether Rending", [33] = "Increases the item's Mana Conversion bonus by 1%", [34] = "Imbues the target with a +1 bonus to Melee Defense", [35] = "Imbues the target with Fire Rending", [36] = "Imbues the target with Minor Health Gain", [37] = "Imbues the target with Minor Quickness", [38] = "Imbues the target with Augmented Health", [39] = "Imbues the target with Augmented Mana", [40] = "Imbues the target with Minor Coordination", [41] = "Imbues the target with Armor Rending", [42] = "No Apparent Use", [43] = "No Apparent Use", [44] = "No Apparent Use", [45] = "No Apparent Use", [46] = "Imbues the target with Melee Cleaving/Split Arrow", [47] = "Imbues the target with Bludgeon Rending", [48] = "No Apparent Use", [49] = "Imbues the target with a +1 bonus to Missile Defense", [50] = "Imbues the target with a +1 bonus to Magic Defense", [51] = "Unattunes certain quest items from your soul", [52] = "Renders an item Retained", [53] = "Increases Armor's Acid Protection by 0.4", [54] = "Imbues the target with Damage Reduction +dr", [55] = "Increases Armor's Lightning Protection by 0.4", [57] = "Increases a weapon's melee defense bonus by 1%", [58] = "Increases Armor's Slashing Protection by 0.2", [59] = "Changes Missile Defense requirement to Melee Defense requirement", [60] = "Raises a treasure-generated item's value by 25%", [61] = "Increases the weapon's maximum damage by 1", [62] = "Imbues the target with Augmented Understanding", [63] = "Changes Melee Defense requirement to Missile Defense requirement", [64] = "Increases Armor's Armor Level by +20", [66] = "Increases Armor's Piercing Protection by 0.2", [67] = "Improves a melee weapon's variance by 20%", [68] = "Increases Armor's Bludgeon Protection by 0.2", [69] = "No Apparent Use", [70] = "Removes a treasure-generated item's Retained status", [71] = "No Apparent Use", [73] = "Changes heritage requirement to Gharu'ndim", [74] = "Increases a missile weapon's damage modifier by 4%", [75] = "Decreases the weapon's speed by 50", [76] = "Reduces the item's value by 25%", [77] = "Changes heritage requirement to Aluvian"}
local SALVAGETINKERSKILL = {[1] = "Armor Tink", [2] = "Item Tink", [4] = "Item Tink", [5] = "Item Tink", [6] = "Special Tink", [7] = "Weapon Tink", [8] = "Armor Tink", [10] = "Magic Item Tink", [11] = "Item Tink", [12] = "", [13] = "Weapon Tink", [14] = "Magic Item Tink", [15] = "Weapon Tink", [16] = "Magic Item Tink", [17] = "Magic Item Tink", [18] = "Magic Item Tink", [19] = "Magic Item Tink", [20] = "Item Tink", [21] = "Weapon Tink", [22] = "Magic Item Tink", [23] = "Magic Item Tink", [24] = "", [25] = "Magic Item Tink", [26] = "Weapon Tink", [27] = "Weapon Tink", [28] = "Magic Item Tink", [29] = "Magic Item Tink", [30] = "Magic Item Tink", [31] = "Item Tink", [32] = "Weapon Tink", [33] = "Magic Item Tink", [34] = "Armor Tink", [35] = "Weapon Tink", [36] = "Magic Item Tink", [37] = "Magic Item Tink", [38] = "Item Tink", [39] = "Item Tink", [40] = "Magic Item Tink", [41] = "Magic Item Tink", [42] = "", [43] = "", [44] = "", [45] = "", [46] = "Weapon Tink", [47] = "Weapon Tink", [48] = "", [49] = "Armor Tink", [50] = "Armor Tink", [51] = "Special Tink", [52] = "Special Tink", [53] = "Armor Tink", [54] = "Item Tink", [55] = "Armor Tink", [57] = "Weapon Tink", [58] = "Armor Tink", [59] = "Item Tink", [60] = "Item Tink", [61] = "Weapon Tink", [62] = "Item Tink", [63] = "Item Tink", [64] = "Armor Tink", [66] = "Armor Tink", [67] = "Weapon Tink", [68] = "Armor Tink", [69] = "", [70] = "Special Tink", [71] = "", [73] = "Item Tink", [74] = "Weapon Tink", [75] = "Weapon Tink", [76] = "Item Tink", [77] = "Item Tink"}
local WEAPON_MAX = {{44,3,0,74,0,0,0}, {44,6,0,71,0,0,0}, {44,6,1,38,0,0,0}, {44,4,0,69,0,0,0}, {44,5,0,72,0,0,0}, {44,2,0,71,0,0,0}, {44,2,1,38,0,0,0}, {44,7,0,70,0,0,0}, {44,1,0,59,0,0,0}, {45,3,0,61,0,0,0}, {45,6,0,58,0,0,0}, {45,6,1,28,0,0,0}, {45,4,0,57,0,0,0}, {45,5,0,60,0,0,0}, {45,2,0,58,0,0,0}, {45,2,1,28,0,0,0}, {45,7,0,57,0,0,0}, {45,1,0,48,0,0,0}, {46,3,0,61,0,0,0}, {46,6,0,58,0,0,0}, {46,6,1,28,0,0,0}, {46,4,0,57,0,0,0}, {46,5,0,60,0,0,0}, {46,2,0,58,0,0,0}, {46,2,1,28,0,0,0}, {46,7,0,57,0,0,0}, {46,1,0,48,0,0,0}, {41,11,1,45,0,0,0}, {41,11,0,48,0,0,0}, {47,8,0,0,140,22,0}, {47,9,0,0,165,22,0}, {47,10,0,0,160,22,0}, {34,0,0,0,0,0,1.18}, {43,0,0,0,0,0,1.18}, {43,12,0,0,0,0,1.18}}  -- skill, mastery, multi, max damage, damage mod, elem bonus, elem vs monsters
local SET_SHORT = {[2] = "Test", [4] = "Carraida Benediction", [5] = "Noble Relic", [6] = "Ancient Relic", [7] = "Relic Alduressa", [8] = "Shou-jen", [9] = "Empyrean Rings", [10] = "Arm, Mind, Heart", [11] = "Perfect Light", [12] = "Perfect Light", [13] = "Soldier", [14] = "Adept", [15] = "Archer", [16] = "Defender", [17] = "Tinker", [18] = "Crafter", [19] = "Hearty", [20] = "Dexterous", [21] = "Wise", [22] = "Swift", [23] = "Hardened", [24] = "Reinforced", [25] = "Interlocking", [26] = "Flame Proof", [27] = "Acid Proof", [28] = "Cold Proof", [29] = "Lightning Proof", [30] = "Dedication", [31] = "Gladiatorial Clothing", [32] = "Ceremonial Clothing", [33] = "Protective Clothing", [34] = "Noobie Armor", [35] = "Defense", [36] = "Destruction", [37] = "Fury", [38] = "Growth", [39] = "Vigor", [40] = "Heroic Protector", [41] = "Heroic Destroyer", [42] = "Olthoi Armor D Red", [43] = "Olthoi Armor C Rat", [44] = "Olthoi Armor C Red", [45] = "Olthoi Armor D Rat", [46] = "Upgraded Relic Alduressa", [47] = "Upgraded Ancient Relic", [48] = "Upgraded Noble Relic", [49] = "Weave of Alchemy", [50] = "Weave of Arcane Lore", [51] = "Weave of Armor Tinkering", [52] = "Weave of Assess Person", [53] = "Weave of Light Weapons", [54] = "Weave of Missile Weapons", [55] = "Weave of Cooking", [56] = "Weave of Creature Enchantment", [57] = "Weave of Missile Weapons", [58] = "Weave of Finesse", [59] = "Weave of Deception", [60] = "Weave of Fletching", [61] = "Weave of Healing", [62] = "Weave of Item Enchantment", [63] = "Weave of Item Tinkering", [64] = "Weave of Leadership", [65] = "Weave of Life Magic", [66] = "Weave of Loyalty", [67] = "Weave of Light Weapons", [68] = "Weave of Magic Defense", [69] = "Weave of Magic Item Tinkering", [70] = "Weave of Mana Conversion", [71] = "Weave of Melee Defense", [72] = "Weave of Missile Defense", [73] = "Weave of Salvaging", [74] = "Weave of Light Weapons", [75] = "Weave of Light Weapons", [76] = "Weave of Heavy Weapons", [77] = "Weave of Missile Weapons", [78] = "Weave of Two Handed Combat", [79] = "Weave of Light Weapons", [80] = "Weave of Void Magic", [81] = "Weave of War Magic", [82] = "Weave of Weapon Tinkering", [83] = "Weave of Assess Creature", [84] = "Weave of Dirty Fighting", [85] = "Weave of Dual Wield", [86] = "Weave of Recklessness", [87] = "Weave of Shield", [88] = "Weave of Sneak Attack", [89] = "Ninja_New", [90] = "Weave of Summoning", [91] = "Shrouded Soul", [92] = "Darkened Mind", [93] = "Clouded Spirit", [94] = "Minor Stinging Shrouded Soul", [95] = "Minor Sparking Shrouded Soul", [96] = "Minor Smoldering Shrouded Soul", [97] = "Minor Shivering Shrouded Soul", [98] = "Minor Stinging Darkened Mind", [99] = "Minor Sparking Darkened Mind", [100] = "Minor Smoldering Darkened Mind", [101] = "Minor Shivering Darkened Mind", [102] = "Minor Stinging Clouded Spirit", [103] = "Minor Sparking Clouded Spirit", [104] = "Minor Smoldering Clouded Spirit", [105] = "Minor Shivering Clouded Spirit", [106] = "Major Stinging Shrouded Soul", [107] = "Major Sparking Shrouded Soul", [108] = "Major Smoldering Shrouded Soul", [109] = "Major Shivering Shrouded Soul", [110] = "Major Stinging Darkened Mind", [111] = "Major Sparking Darkened Mind", [112] = "Major Smoldering Darkened Mind", [113] = "Major Shivering Darkened Mind", [114] = "Major Stinging Clouded Spirit", [115] = "Major Sparking Clouded Spirit", [116] = "Major Smoldering Clouded Spirit", [117] = "Major Shivering Clouded Spirit", [118] = "Blackfire Stinging Shrouded Soul", [119] = "Blackfire Sparking Shrouded Soul", [120] = "Blackfire Smoldering Shrouded Soul", [121] = "Blackfire Shivering Shrouded Soul", [122] = "Blackfire Stinging Darkened Mind", [123] = "Blackfire Sparking Darkened Mind", [124] = "Blackfire Smoldering Darkened Mind", [125] = "Blackfire Shivering Darkened Mind", [126] = "Blackfire Stinging Clouded Spirit", [127] = "Blackfire Sparking Clouded Spirit", [128] = "Blackfire Smoldering Clouded Spirit", [129] = "Blackfire Shivering Clouded Spirit", [130] = "Shimmering Shadows", [131] = "Brown Society Locket", [132] = "Yellow Society Locket", [133] = "Red Society Band", [134] = "Green Society Band", [135] = "Purple Society Band", [136] = "Blue Society Band", [137] = "Gauntlet Garb"}
local OC_NAME = {[0] = "Unknown", [1] = "MeleeWeapon", [2] = "Armor", [3] = "Clothing", [4] = "Jewelry", [5] = "Monster", [6] = "Food", [7] = "Money", [8] = "Misc", [9] = "MissileWeapon", [10] = "Container", [11] = "Gem", [12] = "SpellComponent", [13] = "Key", [14] = "Portal", [15] = "TradeNote", [16] = "ManaStone", [17] = "Plant", [18] = "BaseCooking", [19] = "BaseAlchemy", [20] = "BaseFletching", [21] = "CraftedCooking", [22] = "CraftedAlchemy", [23] = "CraftedFletching", [24] = "Player", [25] = "Vendor", [26] = "Door", [27] = "Corpse", [28] = "Lifestone", [29] = "HealingKit", [30] = "Lockpick", [31] = "WandStaffOrb", [32] = "Bundle", [33] = "Book", [34] = "Journal", [35] = "Sign", [36] = "Housing", [37] = "Npc", [38] = "Foci", [39] = "Salvage", [40] = "Ust", [41] = "Services", [42] = "Scroll", [43] = "NumObjectClasses"}
-- Spell data for the Suit Builder and the Set Bonus Summary.
local SD = {}
-- Generated from the client spell table (portal.dat 0x0E00000E).
-- Rating spells: spell id -> {column, value, stacking category}. Spells of one category do not stack.
SD.RATING_SPELL = {
  [5138] = {"D", 1, 610}, [5139] = {"D", 2, 610}, [5140] = {"D", 3, 610}, [5141] = {"DR", 1, 611}, [5142] = {"DR", 2, 611}, [5143] = {"DR", 3, 611},
  [5184] = {"D", 7, 633}, [5185] = {"D", 8, 633}, [5186] = {"D", 9, 633}, [5187] = {"D", 10, 633}, [5188] = {"DR", 1, 634}, [5189] = {"DR", 2, 634},
  [5190] = {"DR", 3, 634}, [5191] = {"DR", 4, 634}, [5192] = {"DR", 5, 634}, [5193] = {"DR", 5, 634}, [5194] = {"DR", 5, 634}, [5195] = {"DR", 5, 634},
  [5196] = {"DR", 5, 634}, [5197] = {"DR", 5, 634}, [5198] = {"D", 1, 633}, [5199] = {"D", 2, 633}, [5200] = {"D", 3, 633}, [5201] = {"D", 4, 633},
  [5202] = {"D", 5, 633}, [5203] = {"D", 6, 633}, [5209] = {"CD", 1, 626}, [5210] = {"CD", 2, 626}, [5211] = {"CD", 3, 626}, [5212] = {"CD", 4, 626},
  [5213] = {"CD", 5, 626}, [5214] = {"CD", 6, 626}, [5215] = {"CD", 7, 626}, [5216] = {"CD", 8, 626}, [5217] = {"CD", 9, 626}, [5218] = {"CD", 10, 626},
  [5219] = {"CD", 11, 626}, [5220] = {"CD", 12, 626}, [5221] = {"CD", 13, 626}, [5222] = {"CD", 14, 626}, [5223] = {"CD", 15, 626}, [5224] = {"D", 1, 620},
  [5225] = {"D", 2, 620}, [5226] = {"D", 3, 620}, [5227] = {"D", 4, 620}, [5228] = {"D", 5, 620}, [5229] = {"D", 6, 620}, [5230] = {"D", 7, 620},
  [5231] = {"D", 8, 620}, [5232] = {"D", 9, 620}, [5233] = {"D", 10, 620}, [5234] = {"D", 11, 620}, [5235] = {"D", 12, 620}, [5236] = {"D", 13, 620},
  [5237] = {"D", 14, 620}, [5238] = {"D", 15, 620}, [5239] = {"DR", 1, 621}, [5240] = {"DR", 2, 621}, [5241] = {"DR", 3, 621}, [5242] = {"DR", 4, 621},
  [5243] = {"DR", 5, 621}, [5244] = {"DR", 6, 621}, [5245] = {"DR", 7, 621}, [5246] = {"DR", 8, 621}, [5247] = {"DR", 9, 621}, [5248] = {"DR", 10, 621},
  [5249] = {"DR", 11, 621}, [5250] = {"DR", 12, 621}, [5251] = {"DR", 13, 621}, [5252] = {"DR", 14, 621}, [5253] = {"DR", 15, 621}, [5254] = {"HB", 1, 627},
  [5255] = {"HB", 2, 627}, [5256] = {"HB", 3, 627}, [5257] = {"HB", 4, 627}, [5258] = {"HB", 5, 627}, [5259] = {"HB", 6, 627}, [5260] = {"HB", 7, 627},
  [5261] = {"HB", 8, 627}, [5262] = {"HB", 9, 627}, [5263] = {"HB", 10, 627}, [5264] = {"HB", 11, 627}, [5265] = {"HB", 12, 627}, [5266] = {"HB", 13, 627},
  [5267] = {"HB", 14, 627}, [5268] = {"HB", 15, 627}, [5269] = {"V", 1, 623}, [5270] = {"V", 2, 623}, [5271] = {"V", 3, 623}, [5272] = {"V", 4, 623},
  [5273] = {"V", 5, 623}, [5274] = {"V", 6, 623}, [5275] = {"V", 7, 623}, [5276] = {"V", 8, 623}, [5277] = {"V", 9, 623}, [5278] = {"V", 10, 623},
  [5279] = {"V", 11, 623}, [5280] = {"V", 12, 623}, [5281] = {"V", 13, 623}, [5282] = {"V", 14, 623}, [5283] = {"V", 15, 623}, [5477] = {"CD", 2, 626},
  [5478] = {"CD", 4, 626}, [5479] = {"CD", 6, 626}, [5480] = {"CD", 8, 626}, [5481] = {"CD", 10, 626}, [5482] = {"CD", 12, 626}, [5483] = {"CD", 14, 626},
  [5484] = {"CD", 16, 626}, [5485] = {"CD", 20, 626}, [5486] = {"CD", 24, 626}, [5487] = {"CD", 30, 626}, [5489] = {"CDR", 2, 653}, [5490] = {"CDR", 4, 653},
  [5491] = {"CDR", 6, 653}, [5492] = {"CDR", 8, 653}, [5493] = {"CDR", 10, 653}, [5494] = {"CDR", 12, 653}, [5495] = {"CDR", 14, 653}, [5496] = {"CDR", 16, 653},
  [5497] = {"CDR", 20, 653}, [5498] = {"CDR", 24, 653}, [5499] = {"CDR", 30, 653}, [5500] = {"D", 1, 620}, [5501] = {"D", 2, 620}, [5502] = {"D", 3, 620},
  [5503] = {"D", 4, 620}, [5504] = {"D", 5, 620}, [5505] = {"D", 6, 620}, [5506] = {"D", 7, 620}, [5507] = {"D", 8, 620}, [5508] = {"D", 10, 620},
  [5509] = {"D", 12, 620}, [5510] = {"D", 15, 620}, [5511] = {"DR", 1, 621}, [5512] = {"DR", 2, 621}, [5513] = {"DR", 3, 621}, [5514] = {"DR", 4, 621},
  [5515] = {"DR", 5, 621}, [5516] = {"DR", 6, 621}, [5517] = {"DR", 7, 621}, [5518] = {"DR", 8, 621}, [5519] = {"DR", 10, 621}, [5520] = {"DR", 12, 621},
  [5521] = {"DR", 15, 621}, [5974] = {"D", 1, 694}, [5975] = {"D", 2, 694}, [5976] = {"D", 3, 694}, [5977] = {"D", 4, 694}, [5978] = {"D", 5, 694},
  [6291] = {"CD", 1, 713}, [6292] = {"CD", 2, 713}, [6293] = {"CD", 3, 713}, [6294] = {"CD", 4, 713}, [6295] = {"CD", 5, 713}, [6296] = {"CDR", 1, 714},
  [6297] = {"CDR", 2, 714}, [6298] = {"CDR", 3, 714}, [6299] = {"CDR", 4, 714}, [6300] = {"CDR", 5, 714}, [6301] = {"D", 1, 711}, [6302] = {"D", 2, 711},
  [6303] = {"D", 3, 711}, [6304] = {"D", 4, 711}, [6305] = {"D", 5, 711}, [6306] = {"DR", 1, 712}, [6307] = {"DR", 2, 712}, [6308] = {"DR", 3, 712},
  [6309] = {"DR", 4, 712}, [6310] = {"DR", 5, 712}, [6328] = {"CD", 1, 732}, [6329] = {"CD", 2, 732}, [6330] = {"D", 1, 729}, [6331] = {"D", 2, 729},
  [6332] = {"DR", 1, 728}, [6333] = {"DR", 2, 728}, [6334] = {"CDR", 1, 733}, [6335] = {"CDR", 2, 733}, [6336] = {"HB", 1, 730}, [6337] = {"HB", 2, 730},
  [6338] = {"V", 1, 731}, [6339] = {"V", 2, 731}, [6340] = {"V", 3, 731},
}
-- Sets whose spells follow item level (society bands and lockets, heroic sets, aetheria sigils):
-- set id -> {{level, {spell ids}}, ...}, only cantrips and rating spells, listed where they change.
SD.LEVEL_SETS = {
  [35] = {{1, {5239}}, {2, {5240}}, {3, {5241}}, {4, {5242}}, {5, {5243}}, {6, {5244}}, {8, {5245}}, {10, {5246}}, {12, {5247}}, {15, {5248}}},
  [36] = {{1, {5224}}, {2, {5225}}, {3, {5226}}, {4, {5227}}, {5, {5228}}, {6, {5229}}, {8, {5230}}, {10, {5231}}, {12, {5232}}, {15, {5233}}},
  [37] = {{1, {5209}}, {2, {5210}}, {3, {5211}}, {4, {5212}}, {5, {5213}}, {6, {5214}}, {8, {5215}}, {10, {5216}}, {12, {5217}}, {15, {5218}}},
  [38] = {{1, {5254}}, {2, {5255}}, {3, {5256}}, {4, {5257}}, {5, {5258}}, {6, {5259}}, {8, {5260}}, {10, {5261}}, {12, {5262}}, {15, {5263}}},
  [39] = {{1, {5269}}, {2, {5270}}, {3, {5271}}, {4, {5272}}, {5, {5273}}, {6, {5274}}, {8, {5275}}, {10, {5276}}, {12, {5277}}, {15, {5278}}},
  [40] = {{1, {}}, {4, {4750}}, {5, {4750, 5188}}, {10, {4750, 5189}}, {13, {4751, 5189}}, {15, {4751, 5190}}, {20, {4751, 5191}}, {22, {4752, 5191}}, {25, {4752, 5192}}, {30, {4752, 5192, 5974}}, {31, {4753, 5192, 5974}}, {35, {4753, 5192, 5975}}, {40, {4753, 5192, 5976}}, {45, {4753, 5192, 5977}}, {50, {4753, 5192, 5978}}},
  [41] = {{1, {4730}}, {5, {4730, 5198}}, {7, {4730, 4746, 5198}}, {10, {4731, 4746, 5199}}, {15, {4731, 4746, 5200}}, {16, {4731, 4747, 5200}}, {19, {4732, 4747, 5200}}, {20, {4732, 4747, 5201}}, {25, {4732, 4748, 5202}}, {28, {4733, 4748, 5202}}, {30, {4733, 4748, 5203}}, {34, {4733, 4749, 5203}}, {35, {4733, 4749, 5184}}, {40, {4733, 4749, 5185}}, {45, {4733, 4749, 5186}}, {50, {4733, 4749, 5187}}},
  [131] = {{1, {}}, {3, {6332}}, {6, {6333}}, {7, {2004, 6333}}, {8, {2004, 6330, 6333}}, {9, {2004, 6331, 6333}}, {10, {2004, 6331, 6333, 6337}}},
  [132] = {{1, {}}, {3, {6332}}, {6, {6333}}, {7, {2004, 6333}}, {8, {2004, 6330, 6333}}, {9, {2004, 6331, 6333}}, {10, {2004, 6331, 6333, 6337}}},
  [133] = {{1, {}}, {3, {6338}}, {4, {6104, 6338}}, {5, {6077, 6104, 6338}}, {6, {6077, 6104, 6339}}, {7, {2003, 6077, 6104, 6339}}, {8, {2003, 6077, 6104, 6340}}, {9, {2003, 6077, 6104, 6336, 6340}}, {10, {2003, 6077, 6104, 6337, 6340}}},
  [134] = {{1, {}}, {3, {6330}}, {4, {6043, 6044, 6047, 6072, 6330}}, {5, {6043, 6044, 6047, 6072, 6076, 6330}}, {6, {6043, 6044, 6047, 6072, 6076, 6331}}, {8, {6043, 6044, 6047, 6072, 6076, 6328, 6331}}, {9, {6043, 6044, 6047, 6072, 6076, 6329, 6331}}, {10, {6043, 6044, 6047, 6072, 6076, 6329, 6331, 6337}}},
  [135] = {{1, {}}, {3, {6332}}, {4, {6054, 6332}}, {6, {6054, 6333}}, {7, {6054, 6063, 6333}}, {8, {6054, 6063, 6333, 6334}}, {9, {6054, 6063, 6333, 6335}}, {10, {6054, 6063, 6333, 6335, 6337}}},
  [136] = {{1, {}}, {3, {6330}}, {4, {6074, 6075, 6330}}, {5, {6074, 6075, 6078, 6330}}, {6, {6074, 6075, 6078, 6331}}, {8, {6074, 6075, 6078, 6328, 6331}}, {9, {6074, 6075, 6078, 6329, 6331}}, {10, {6074, 6075, 6078, 6329, 6331, 6337}}},
}
-- Spell icons (DAT) for the cantrip rows, by row name.
SD.CANTRIP_ICON = {["Strength"] = 100668300, ["Endurance"] = 100668273, ["Coordination"] = 100668268, ["Quickness"] = 100668294, ["Focus"] = 100668277, ["Willpower"] = 100668296, ["Armor"] = 100668293, ["Bludgeoning Ward"] = 100668345, ["Piercing Ward"] = 100668347, ["Slashing Ward"] = 100668348, ["Acid Ward"] = 100668344, ["Flame Ward"] = 100668291, ["Frost Ward"] = 100668292, ["Storm Ward"] = 100668346, ["Finesse Weapons"] = 100692225, ["Heavy Weapons"] = 100692226, ["Light Weapons"] = 100692224, ["Two Handed Combat"] = 100690646, ["Missile Weapons"] = 100668266, ["Void Magic"] = 100691575, ["War Magic"] = 100668272, ["Summoning Prowess"] = 100693007, ["Magic Defense (Resistance)"] = 100668330, ["Melee Defense (Invulnerability)"] = 100668331, ["Missile Defense (Impregnability)"] = 100669126, ["Armor Tinkering"] = 100668352, ["Item Tinkering"] = 100668264, ["Magic Item Tinkering"] = 100668354, ["Weapon Tinkering"] = 100668357, ["Alchemy"] = 100670578, ["Arcane Lore"] = 100668285, ["Assess Creature"] = 100668353, ["Assess Person"] = 100668355, ["Cooking"] = 100670579, ["Creature Enchantment"] = 100668358, ["Deception"] = 100668296, ["Dirty Fighting"] = 100692227, ["Dual Wield"] = 100692228, ["Fletching"] = 100670580, ["Healing"] = 100668279, ["Item Enchantment"] = 100668272, ["Jumping"] = 100668264, ["Leadership"] = 100668283, ["Life Magic"] = 100668337, ["Lockpick"] = 100668284, ["Loyalty"] = 100668286, ["Mana Conversion"] = 100668288, ["Recklessness"] = 100668265, ["Run (Sprint)"] = 100668295, ["Salvaging"] = 100673210, ["Shield"] = 100692229, ["Sneak Attack"] = 100692230, ["Essence"] = 100670841, ["Warrior's Vitality"] = 100670972, ["Acid Proof Set"] = 100668344, ["Adept's Set"] = 100668272, ["Archer's Set"] = 100668266, ["Cold Proof Set"] = 100668292, ["Crafter's Set"] = 100670578, ["Dedication Set"] = 100670995, ["Defender's Set"] = 100669126, ["Dexterous Set"] = 100668268, ["Flame Proof Set"] = 100668291, ["Hardened Set"] = 100668348, ["Hearty Set"] = 100668300, ["Interlocking Set"] = 100668347, ["Lightning Proof Set"] = 100668346, ["Reinforced Set"] = 100668345, ["Soldier's Set"] = 100668302, ["Swift Set"] = 100668282, ["Tinker's Set"] = 100668352, ["Wise Set"] = 100668296, ["Health Gain"] = 100668279, ["Stamina Gain"] = 100668299, ["Mana Gain"] = 100668288}
-- Names of the spells above (for the Cantrips column).
SD.SPELL_NAME = {
  [1997] = "Life Giver", [2003] = "Warrior's Lesser Vitality", [2004] = "Warrior's Vitality", [2005] = "Warrior's Greater Vitality", [2006] = "Warrior's Ultimate Vitality",
  [2665] = "Essence Sluice", [2666] = "Essence Glutton", [2667] = "Essence Spike", [2969] = "Mother's Blessing", [4730] = "Novice Duelist's Coordination",
  [4731] = "Apprentice Duelist's Coordination", [4732] = "Journeyman Duelist's Coordination", [4733] = "Master Duelist's Coordination", [4746] = "Novice Brute's Strength", [4747] = "Apprentice Brute's Strength",
  [4748] = "Journeyman Brute's Strength", [4749] = "Master Brute's Strength", [4750] = "Novice Adherent's Willpower", [4751] = "Apprentice Adherent's Willpower", [4752] = "Journeyman Adherent's Willpower",
  [4753] = "Master Adherent's Willpower", [4760] = "Incidental Acid Resistance", [4761] = "Crude Acid Resistance", [4762] = "Effective Acid Resistance", [4763] = "Masterwork Acid Resistance",
  [4764] = "Incidental Bludgeoning Resistance", [4765] = "Crude Bludgeoning Resistance", [4766] = "Effective Bludgeoning Resistance", [4767] = "Masterwork Bludgeoning Resistance", [4768] = "Incidental Flame Resistance",
  [4769] = "Crude Flame Resistance", [4770] = "Effective Flame Resistance", [4771] = "Masterwork Flame Resistance", [4772] = "Incidental Frost Resistance", [4773] = "Crude Frost Resistance",
  [4774] = "Effective Frost Resistance", [4775] = "Masterwork Frost Resistance", [4776] = "Incidental Lightning Resistance", [4777] = "Crude Lightning Resistance", [4778] = "Effective Lightning Resistance",
  [4779] = "Masterwork Lightning Resistance", [4780] = "Incidental Piercing Resistance", [4781] = "Crude Piercing Resistance", [4782] = "Effective Piercing Resistance", [4783] = "Masterwork Piercing Resistance",
  [4784] = "Incidental Slashing Resistance", [4785] = "Crude Slashing Resistance", [4786] = "Effective Slashing Resistance", [4787] = "Masterwork Slashing Resistance", [4788] = "Novice Concoctor's Alchemy Aptitude",
  [4789] = "Apprentice Concoctor's Alchemy Aptitude", [4790] = "Journeyman Concoctor's Alchemy Aptitude", [4791] = "Master Concoctor's Alchemy Aptitude", [4792] = "Novice Armorer's Armor Tinkering Aptitude", [4793] = "Apprentice Armorer's Armor Tinkering Aptitude",
  [4794] = "Journeyman Armorer's Armor Tinkering Aptitude", [4795] = "Master Armorer's Armor Tinkering Aptitude", [4800] = "Novice Archer's Missile Weapon Aptitude", [4801] = "Apprentice Archer's Missile Weapon Aptitude", [4802] = "Journeyman Archer's Missile Weapon Aptitude",
  [4803] = "Master Archer's Missile Weapon Aptitude", [4824] = "Novice Artifex's Item Aptitude", [4825] = "Apprentice Artifex's Item Aptitude", [4826] = "Journeyman Artifex's Item Aptitude", [4827] = "Master Artifex's Item Aptitude",
  [4832] = "Novice Leaper's Jumping Aptitude", [4833] = "Apprentice Leaper's Jumping Aptitude", [4834] = "Journeyman Leaper's Jumping Aptitude", [4835] = "Master Leaper's Jumping Aptitude", [4862] = "Novice Wayfarer's Impregnability",
  [4863] = "Apprentice Wayfarer's Impregnability", [4864] = "Journeyman Wayfarer's Impregnability", [4865] = "Master Wayfarer's Impregnability", [4880] = "Novice Soldier's Heavy Weapon Aptitude", [4881] = "Apprentice Soldier's Heavy Weapon Aptitude",
  [4882] = "Journeyman Soldier's Heavy Weapon Aptitude", [4883] = "Master Soldier's Heavy Weapon Aptitude", [4900] = "Society Initiate's Blessing", [4901] = "Society Adept's Blessing", [4902] = "Society Knight's Blessing",
  [4903] = "Society Lord's Blessing", [4904] = "Society Master's Blessing", [5184] = "Rare Damage Boost VII", [5185] = "Rare Damage Boost VIII", [5186] = "Rare Damage Boost IX",
  [5187] = "Rare Damage Boost X", [5188] = "Rare Damage Reduction I", [5189] = "Rare Damage Reduction II", [5190] = "Rare Damage Reduction III", [5191] = "Rare Damage Reduction IV",
  [5192] = "Rare Damage Reduction V", [5198] = "Rare Damage Boost I", [5199] = "Rare Damage Boost II", [5200] = "Rare Damage Boost III", [5201] = "Rare Damage Boost IV",
  [5202] = "Rare Damage Boost V", [5203] = "Rare Damage Boost VI", [5209] = "Sigil of Fury I (Critical Damage)", [5210] = "Sigil of Fury II (Critical Damage)", [5211] = "Sigil of Fury III (Critical Damage)",
  [5212] = "Sigil of Fury IV (Critical Damage)", [5213] = "Sigil of Fury V (Critical Damage)", [5214] = "Sigil of Fury VI (Critical Damage)", [5215] = "Sigil of Fury VII (Critical Damage)", [5216] = "Sigil of Fury VIII (Critical Damage)",
  [5217] = "Sigil of Fury IX (Critical Damage)", [5218] = "Sigil of Fury X (Critical Damage)", [5224] = "Sigil of Destruction I", [5225] = "Sigil of Destruction II", [5226] = "Sigil of Destruction III",
  [5227] = "Sigil of Destruction IV", [5228] = "Sigil of Destruction V", [5229] = "Sigil of Destruction VI", [5230] = "Sigil of Destruction VII", [5231] = "Sigil of Destruction VIII",
  [5232] = "Sigil of Destruction IX", [5233] = "Sigil of Destruction X", [5239] = "Sigil of Defense I", [5240] = "Sigil of Defense II", [5241] = "Sigil of Defense III",
  [5242] = "Sigil of Defense IV", [5243] = "Sigil of Defense V", [5244] = "Sigil of Defense VI", [5245] = "Sigil of Defense VII", [5246] = "Sigil of Defense VIII",
  [5247] = "Sigil of Defense IX", [5248] = "Sigil of Defense X", [5254] = "Sigil of Growth I", [5255] = "Sigil of Growth II", [5256] = "Sigil of Growth III",
  [5257] = "Sigil of Growth IV", [5258] = "Sigil of Growth V", [5259] = "Sigil of Growth VI", [5260] = "Sigil of Growth VII", [5261] = "Sigil of Growth VIII",
  [5262] = "Sigil of Growth IX", [5263] = "Sigil of Growth X", [5269] = "Sigil of Vigor I (Health)", [5270] = "Sigil of Vigor II (Health)", [5271] = "Sigil of Vigor III (Health)",
  [5272] = "Sigil of Vigor IV (Health)", [5273] = "Sigil of Vigor V (Health)", [5274] = "Sigil of Vigor VI (Health)", [5275] = "Sigil of Vigor VII (Health)", [5276] = "Sigil of Vigor VIII (Health)",
  [5277] = "Sigil of Vigor IX (Health)", [5278] = "Sigil of Vigor X (Health)", [5974] = "Rare Armor Damage Boost I", [5975] = "Rare Armor Damage Boost II", [5976] = "Rare Armor Damage Boost III",
  [5977] = "Rare Armor Damage Boost IV", [5978] = "Rare Armor Damage Boost V", [6043] = "Legendary Light Weapon Aptitude", [6044] = "Legendary Missile Weapon Aptitude", [6047] = "Legendary Finesse Weapon Aptitude",
  [6054] = "Legendary Impregnability", [6063] = "Legendary Magic Resistance", [6072] = "Legendary Heavy Weapon Aptitude", [6074] = "Legendary Void Magic Aptitude", [6075] = "Legendary War Magic Aptitude",
  [6076] = "Legendary Stamina Gain", [6077] = "Legendary Health Gain", [6078] = "Legendary Mana Gain", [6104] = "Legendary Endurance", [6328] = "Gauntlet Critical Damage Boost I",
  [6329] = "Gauntlet Critical Damage Boost II", [6330] = "Gauntlet Damage Boost I", [6331] = "Gauntlet Damage Boost II", [6332] = "Gauntlet Damage Reduction I", [6333] = "Gauntlet Damage Reduction II",
  [6334] = "Gauntlet Critical Damage Reduction I", [6335] = "Gauntlet Critical Damage Reduction II", [6336] = "Gauntlet Healing Boost I", [6337] = "Gauntlet Healing Boost II", [6338] = "Gauntlet Vitality I",
  [6339] = "Gauntlet Vitality II", [6340] = "Gauntlet Vitality III",
}
-- Each cantrip row's legendary spell name.
SD.LEGENDARY_NAME = {["Strength"] = "Legendary Strength", ["Endurance"] = "Legendary Endurance", ["Coordination"] = "Legendary Coordination", ["Quickness"] = "Legendary Quickness", ["Focus"] = "Legendary Focus", ["Willpower"] = "Legendary Willpower", ["Armor"] = "Legendary Armor", ["Bludgeoning Ward"] = "Legendary Bludgeoning Ward", ["Piercing Ward"] = "Legendary Piercing Ward", ["Slashing Ward"] = "Legendary Slashing Ward", ["Acid Ward"] = "Legendary Acid Ward", ["Flame Ward"] = "Legendary Flame Ward", ["Frost Ward"] = "Legendary Frost Ward", ["Storm Ward"] = "Legendary Storm Ward", ["Finesse Weapons"] = "Legendary Finesse Weapon Aptitude", ["Heavy Weapons"] = "Legendary Heavy Weapon Aptitude", ["Light Weapons"] = "Legendary Light Weapon Aptitude", ["Two Handed Combat"] = "Legendary Two Handed Combat Aptitude", ["Missile Weapons"] = "Legendary Missile Weapon Aptitude", ["Void Magic"] = "Legendary Void Magic Aptitude", ["War Magic"] = "Legendary War Magic Aptitude", ["Summoning Prowess"] = "Legendary Summoning Prowess", ["Magic Defense (Resistance)"] = "Legendary Magic Resistance", ["Melee Defense (Invulnerability)"] = "Legendary Invulnerability", ["Missile Defense (Impregnability)"] = "Legendary Impregnability", ["Armor Tinkering"] = "Legendary Armor Tinkering Expertise", ["Item Tinkering"] = "Legendary Item Tinkering Expertise", ["Magic Item Tinkering"] = "Legendary Magic Item Tinkering Expertise", ["Weapon Tinkering"] = "Legendary Weapon Tinkering Expertise", ["Alchemy"] = "Legendary Alchemical Prowess", ["Arcane Lore"] = "Legendary Arcane Prowess", ["Assess Creature"] = "Legendary Monster Attunement", ["Assess Person"] = "Legendary Person Attunement", ["Cooking"] = "Legendary Cooking Prowess", ["Creature Enchantment"] = "Legendary Creature Enchantment Aptitude", ["Deception"] = "Legendary Deception Prowess", ["Dirty Fighting"] = "Legendary Dirty Fighting Prowess", ["Dual Wield"] = "Legendary Dual Wield Aptitude", ["Fletching"] = "Legendary Fletching Prowess", ["Healing"] = "Legendary Healing Prowess", ["Item Enchantment"] = "Legendary Item Enchantment Aptitude", ["Jumping"] = "Legendary Jumping Prowess", ["Leadership"] = "Legendary Leadership", ["Life Magic"] = "Legendary Life Magic Aptitude", ["Lockpick"] = "Legendary Lockpick Prowess", ["Loyalty"] = "Legendary Fealty", ["Mana Conversion"] = "Legendary Mana Conversion Prowess", ["Recklessness"] = "Legendary Recklessness Prowess", ["Run (Sprint)"] = "Legendary Sprint", ["Salvaging"] = "Legendary Salvaging Aptitude", ["Shield"] = "Legendary Shield Aptitude", ["Sneak Attack"] = "Legendary Sneak Attack Prowess", ["Essence"] = "Essence Glutton", ["Warrior's Vitality"] = "Warrior's Ultimate Vitality", ["Acid Proof Set"] = "Masterwork Acid Resistance", ["Adept's Set"] = "Master Artifex's Item Aptitude", ["Archer's Set"] = "Master Archer's Missile Weapon Aptitude", ["Cold Proof Set"] = "Masterwork Frost Resistance", ["Crafter's Set"] = "Master Concoctor's Alchemy Aptitude", ["Dedication Set"] = "Society Master's Blessing", ["Defender's Set"] = "Master Wayfarer's Impregnability", ["Dexterous Set"] = "Master Duelist's Coordination", ["Flame Proof Set"] = "Masterwork Flame Resistance", ["Hardened Set"] = "Masterwork Slashing Resistance", ["Hearty Set"] = "Master Brute's Strength", ["Interlocking Set"] = "Masterwork Piercing Resistance", ["Lightning Proof Set"] = "Masterwork Lightning Resistance", ["Reinforced Set"] = "Masterwork Bludgeoning Resistance", ["Soldier's Set"] = "Master Soldier's Heavy Weapon Aptitude", ["Swift Set"] = "Master Leaper's Jumping Aptitude", ["Tinker's Set"] = "Master Armorer's Armor Tinkering Aptitude", ["Wise Set"] = "Master Adherent's Willpower", ["Health Gain"] = "Legendary Health Gain", ["Stamina Gain"] = "Legendary Stamina Gain", ["Mana Gain"] = "Legendary Mana Gain"}
-- Other spells that raise a skill or attribute (Character Summary): id -> {amount, what (ITEM_BONUS_OF)}.
SD.ITEM_BONUS_OF = {"Alchemy", "Arcane Lore", "Armor", "Armor Tinkering", "Assess Creature", "Assess Person", "Cooking", "Coordination", "Creature Enchantment", "Deception", "Dirty Fighting", "Dual Wield", "Endurance", "Finesse Weapons", "Fletching", "Focus", "Healing", "Health", "Heavy Weapons", "Item Enchantment", "Item Tinkering", "Jump", "Leadership", "Life Magic", "Light Weapons", "Lockpick", "Loyalty", "Magic Defense", "Magic Item Tinkering", "Mana Conversion", "Melee Defense", "Missile Defense", "Missile Weapons", "Quickness", "Recklessness", "Run", "Salvaging", "Shield", "Sneak Attack", "Strength", "Summoning", "Sword", "Two Handed Combat", "Void Magic", "War Magic", "Weapon Tinkering", "Willpower"}
SD.ITEM_BONUS = {
  [2052]={225,3}, [2058]={40,8}, [2060]={40,13}, [2066]={40,16}, [2080]={40,34}, [2086]={40,40}, [2090]={40,47}, [2190]={40,1}, [2194]={40,2}, [2196]={40,4},
  [2210]={40,7}, [2214]={40,9}, [2226]={40,10}, [2232]={40,27}, [2236]={40,15}, [2240]={40,17}, [2242]={40,32}, [2244]={40,31}, [2248]={40,20}, [2250]={40,21},
  [2256]={40,22}, [2262]={40,23}, [2266]={40,24}, [2270]={40,26}, [2276]={40,29}, [2280]={40,28}, [2286]={40,30}, [2288]={40,5}, [2292]={40,6}, [2300]={40,36},
  [2322]={40,45}, [2324]={40,46}, [2348]={50,16}, [2357]={60,5}, [2376]={5,45}, [2377]={10,45}, [2378]={10,9}, [2379]={5,9}, [2380]={10,20}, [2381]={5,20},
  [2387]={10,16}, [2388]={10,8}, [2389]={10,13}, [2390]={10,34}, [2391]={10,40}, [2392]={10,47}, [2403]={35,40}, [2412]={35,8}, [2413]={35,16}, [2417]={10,23},
  [2420]={200,3}, [2424]={50,16}, [2427]={50,8}, [2428]={10,28}, [2429]={30,3}, [2430]={10,34}, [2436]={25,17}, [2440]={15,31}, [2441]={8,31}, [2442]={12,31},
  [2443]={15,40}, [2444]={8,40}, [2445]={12,40}, [2449]={15,8}, [2450]={8,8}, [2451]={12,8}, [2455]={15,25}, [2456]={8,25}, [2457]={12,25}, [2458]={15,14},
  [2459]={8,14}, [2460]={12,14}, [2461]={15,25}, [2462]={8,25}, [2463]={12,25}, [2464]={15,25}, [2465]={8,25}, [2466]={12,25}, [2467]={15,25}, [2468]={8,25},
  [2469]={12,25}, [2470]={15,13}, [2471]={8,13}, [2472]={12,13}, [2473]={15,34}, [2474]={8,34}, [2475]={12,34}, [2508]={15,33}, [2517]={15,21}, [2522]={15,25},
  [2528]={15,25}, [2530]={15,25}, [2532]={15,33}, [2533]={15,25}, [2543]={5,33}, [2552]={5,21}, [2557]={5,25}, [2563]={5,25}, [2565]={5,25}, [2567]={5,33},
  [2568]={5,25}, [2638]={20,47}, [2653]={3,47}, [2654]={3,13}, [2655]={3,16}, [2656]={15,34}, [2657]={3,40}, [2658]={3,8}, [2668]={5,28}, [2669]={15,28},
  [2670]={10,28}, [2675]={3,25}, [2676]={3,33}, [2677]={3,33}, [2678]={3,14}, [2679]={3,25}, [2680]={3,30}, [2681]={3,25}, [2682]={3,25}, [2683]={3,19},
  [2684]={3,33}, [2685]={3,25}, [2688]={10,33}, [2690]={10,25}, [2692]={10,25}, [2693]={10,25}, [2695]={10,33}, [2696]={10,25}, [2928]={200,3}, [2958]={5,24},
  [2959]={10,24}, [2993]={2,8}, [2995]={2,40}, [2997]={2,16}, [2999]={2,13}, [3002]={2,47}, [3008]={8,8}, [3009]={8,40}, [3010]={8,13}, [3011]={8,33},
  [3012]={8,33}, [3016]={8,33}, [3034]={7,18}, [3035]={3,20}, [3044]={3,18}, [3045]={1,20}, [3046]={195,3}, [3048]={5,18}, [3049]={2,20}, [3050]={205,3},
  [3052]={230,3}, [3205]={10,31}, [3207]={10,28}, [3209]={10,32}, [3217]={12,33}, [3218]={15,33}, [3219]={8,33}, [3220]={12,33}, [3221]={15,33}, [3222]={8,33},
  [3223]={12,30}, [3224]={15,30}, [3225]={8,30}, [3226]={12,19}, [3227]={15,19}, [3228]={8,19}, [3229]={12,25}, [3230]={15,25}, [3231]={8,25}, [3232]={12,33},
  [3233]={15,33}, [3234]={8,33}, [3362]={8,28}, [3363]={8,31}, [3364]={8,32}, [3506]={10,37}, [3507]={15,37}, [3508]={20,37}, [3509]={25,37}, [3510]={30,37},
  [3511]={35,37}, [3512]={40,37}, [3520]={10,37}, [3521]={15,37}, [3522]={20,37}, [3523]={25,37}, [3524]={30,37}, [3525]={35,37}, [3526]={40,37}, [3530]={50,16},
  [3532]={25,16}, [3567]={15,36}, [3568]={10,30}, [3636]={2,25}, [3637]={2,33}, [3638]={2,33}, [3639]={2,33}, [3640]={2,9}, [3641]={2,45}, [3642]={2,14},
  [3643]={2,24}, [3644]={2,25}, [3645]={2,25}, [3646]={2,25}, [3647]={2,25}, [3648]={2,19}, [3751]={45,7}, [3752]={45,7}, [3753]={45,15}, [3754]={45,15},
  [3755]={45,26}, [3756]={45,26}, [3761]={5,28}, [3801]={3,31}, [3802]={3,45}, [3803]={3,33}, [3804]={3,33}, [3809]={5,37}, [3855]={40,17}, [3860]={100,36},
  [4015]={10,3}, [4016]={25,17}, [4017]={800,33}, [4027]={30,36}, [4047]={30,1}, [4048]={30,7}, [4049]={30,15}, [4050]={30,26}, [4051]={20,1}, [4052]={20,7},
  [4053]={20,15}, [4054]={20,26}, [4055]={10,1}, [4056]={10,7}, [4057]={10,15}, [4058]={10,26}, [4076]={60,2}, [4077]={45,30}, [4086]={100,3}, [4090]={260,3},
  [4099]={45,40}, [4280]={15,8}, [4281]={15,16}, [4500]={45,37}, [4502]={45,37}, [4690]={25,33}, [4698]={25,21}, [4702]={25,25}, [4709]={25,25}, [4711]={25,25},
  [4713]={25,33}, [4714]={25,25}, [4734]={3,13}, [4735]={5,13}, [4736]={10,13}, [4737]={20,13}, [4738]={3,16}, [4739]={5,16}, [4740]={10,16}, [4741]={20,16},
  [4742]={3,34}, [4743]={5,34}, [4744]={10,34}, [4745]={20,34}, [4796]={3,25}, [4797]={5,25}, [4798]={10,25}, [4799]={20,25}, [4804]={3,7}, [4805]={5,7},
  [4806]={10,7}, [4807]={20,7}, [4808]={3,9}, [4809]={5,9}, [4810]={10,9}, [4811]={20,9}, [4812]={3,33}, [4813]={5,33}, [4814]={10,33}, [4815]={20,33},
  [4816]={3,14}, [4817]={5,14}, [4818]={10,14}, [4819]={20,14}, [4820]={3,15}, [4821]={5,15}, [4822]={10,15}, [4823]={20,15}, [4828]={3,21}, [4829]={5,21},
  [4830]={10,21}, [4831]={20,21}, [4836]={3,24}, [4837]={5,24}, [4838]={10,24}, [4839]={20,24}, [4840]={3,26}, [4841]={5,26}, [4842]={10,26}, [4843]={20,26},
  [4844]={3,27}, [4845]={5,27}, [4846]={3,25}, [4847]={5,25}, [4848]={10,25}, [4849]={20,25}, [4850]={3,28}, [4851]={5,28}, [4852]={10,28}, [4853]={20,28},
  [4854]={3,29}, [4855]={5,29}, [4856]={10,29}, [4857]={20,29}, [4858]={3,31}, [4859]={5,31}, [4860]={10,31}, [4861]={20,31}, [4866]={3,37}, [4867]={5,37},
  [4868]={3,25}, [4869]={5,25}, [4870]={10,25}, [4871]={20,25}, [4872]={3,36}, [4873]={5,36}, [4874]={10,36}, [4875]={20,36}, [4876]={3,25}, [4877]={5,25},
  [4878]={10,25}, [4879]={20,25}, [4884]={3,33}, [4885]={5,33}, [4886]={10,33}, [4887]={20,33}, [4888]={3,25}, [4889]={5,25}, [4890]={10,25}, [4891]={20,25},
  [4892]={3,45}, [4893]={5,45}, [4894]={10,45}, [4895]={20,45}, [4896]={3,46}, [4897]={5,46}, [4898]={10,46}, [4899]={20,46}, [4958]={55,33}, [4959]={45,33},
  [4960]={45,33}, [4961]={45,33}, [4962]={50,33}, [4963]={50,33}, [4964]={50,33}, [4965]={55,33}, [4966]={55,33}, [4968]={15,33}, [4969]={15,33}, [4970]={15,33},
  [4971]={15,9}, [4972]={15,45}, [4973]={15,14}, [4974]={15,24}, [4975]={15,25}, [4976]={15,25}, [4977]={15,25}, [4978]={15,25}, [4979]={15,19}, [4980]={15,25},
  [4982]={5,26}, [4984]={5,7}, [4985]={5,15}, [5027]={15,43}, [5028]={8,43}, [5029]={12,43}, [5030]={2,43}, [5031]={15,43}, [5035]={3,42}, [5036]={3,43},
  [5059]={40,21}, [5097]={40,43}, [5106]={20,21}, [5107]={3,43}, [5108]={5,43}, [5109]={10,43}, [5110]={20,43}, [5111]={3,21}, [5112]={5,21}, [5113]={10,21},
  [5155]={32,2}, [5156]={40,2}, [5157]={8,2}, [5158]={16,2}, [5159]={24,2}, [5431]={3,44}, [5432]={5,44}, [5433]={10,44}, [5434]={20,44}, [5437]={2,44},
  [5438]={15,44}, [5452]={45,47}, [5453]={250,3}, [5454]={45,8}, [5455]={45,13}, [5456]={45,16}, [5457]={45,34}, [5458]={45,40}, [5471]={45,28}, [5472]={45,30},
  [5474]={45,36}, [5475]={45,25}, [5476]={45,45}, [5583]={2,1}, [5584]={4,1}, [5585]={6,1}, [5586]={8,1}, [5587]={10,1}, [5588]={2,2}, [5589]={4,2},
  [5590]={6,2}, [5591]={8,2}, [5592]={10,2}, [5593]={2,4}, [5594]={4,4}, [5595]={6,4}, [5596]={8,4}, [5597]={10,4}, [5598]={2,6}, [5599]={4,6},
  [5600]={6,6}, [5601]={8,6}, [5602]={10,6}, [5603]={2,25}, [5604]={4,25}, [5605]={6,25}, [5606]={8,25}, [5607]={10,25}, [5608]={2,33}, [5609]={4,33},
  [5610]={6,33}, [5611]={8,33}, [5612]={10,33}, [5613]={2,7}, [5614]={4,7}, [5615]={6,7}, [5616]={8,7}, [5617]={10,7}, [5618]={2,9}, [5619]={4,9},
  [5620]={6,9}, [5621]={8,9}, [5622]={10,9}, [5623]={2,33}, [5624]={4,33}, [5625]={6,33}, [5626]={8,33}, [5627]={10,33}, [5628]={2,14}, [5629]={4,14},
  [5630]={6,14}, [5631]={8,14}, [5632]={10,14}, [5633]={2,10}, [5634]={4,10}, [5635]={6,10}, [5636]={8,10}, [5637]={10,10}, [5638]={2,15}, [5639]={4,15},
  [5640]={6,15}, [5641]={8,15}, [5642]={10,15}, [5643]={2,17}, [5644]={4,17}, [5645]={6,17}, [5646]={8,17}, [5647]={10,17}, [5648]={2,20}, [5649]={4,20},
  [5650]={6,20}, [5651]={8,20}, [5652]={10,20}, [5653]={2,21}, [5654]={4,21}, [5655]={6,21}, [5656]={8,21}, [5657]={10,21}, [5658]={2,23}, [5659]={4,23},
  [5660]={6,23}, [5661]={8,23}, [5662]={10,23}, [5663]={2,24}, [5664]={4,24}, [5665]={6,24}, [5666]={8,24}, [5667]={10,24}, [5668]={2,27}, [5669]={4,27},
  [5670]={6,27}, [5671]={8,27}, [5672]={10,27}, [5673]={2,25}, [5674]={4,25}, [5675]={6,25}, [5676]={8,25}, [5677]={10,25}, [5678]={2,28}, [5679]={4,28},
  [5680]={6,28}, [5681]={8,28}, [5682]={10,28}, [5683]={2,29}, [5684]={4,29}, [5685]={6,29}, [5686]={8,29}, [5687]={10,29}, [5688]={2,30}, [5689]={4,30},
  [5690]={6,30}, [5691]={8,30}, [5692]={10,30}, [5693]={2,31}, [5694]={4,31}, [5695]={6,31}, [5696]={8,31}, [5697]={10,31}, [5698]={2,32}, [5699]={4,32},
  [5700]={6,32}, [5701]={8,32}, [5702]={10,32}, [5703]={2,37}, [5704]={4,37}, [5705]={6,37}, [5706]={8,37}, [5707]={10,37}, [5708]={2,25}, [5709]={4,25},
  [5710]={6,25}, [5711]={8,25}, [5712]={10,25}, [5713]={2,25}, [5714]={4,25}, [5715]={6,25}, [5716]={8,25}, [5717]={10,25}, [5718]={2,19}, [5719]={4,19},
  [5720]={6,19}, [5721]={8,19}, [5722]={10,19}, [5723]={2,33}, [5724]={4,33}, [5725]={6,33}, [5726]={8,33}, [5727]={10,33}, [5728]={2,43}, [5729]={4,43},
  [5730]={6,43}, [5731]={8,43}, [5732]={10,43}, [5733]={2,25}, [5734]={4,25}, [5735]={6,25}, [5736]={8,25}, [5737]={10,25}, [5738]={2,44}, [5739]={4,44},
  [5740]={6,44}, [5741]={8,44}, [5742]={10,44}, [5743]={2,45}, [5744]={4,45}, [5745]={6,45}, [5746]={8,45}, [5747]={10,45}, [5748]={2,46}, [5749]={4,46},
  [5750]={6,46}, [5751]={8,46}, [5752]={10,46}, [5757]={6,5}, [5758]={8,5}, [5759]={10,5}, [5760]={2,5}, [5761]={4,5}, [5913]={2,11}, [5914]={4,11},
  [5915]={6,11}, [5916]={8,11}, [5917]={10,11}, [5918]={2,12}, [5919]={4,12}, [5920]={6,12}, [5921]={8,12}, [5922]={10,12}, [5923]={2,35}, [5924]={4,35},
  [5925]={6,35}, [5926]={8,35}, [5927]={10,35}, [5928]={2,38}, [5929]={4,38}, [5930]={6,38}, [5931]={8,38}, [5932]={10,38}, [5933]={2,39}, [5934]={4,39},
  [5935]={6,39}, [5936]={8,39}, [5937]={10,39}, [5946]={3,11}, [5947]={5,11}, [5948]={10,11}, [5949]={20,11}, [5950]={3,12}, [5951]={5,12}, [5952]={10,12},
  [5953]={20,12}, [5954]={3,35}, [5955]={5,35}, [5956]={10,35}, [5957]={20,35}, [5958]={3,38}, [5959]={5,38}, [5960]={10,38}, [5961]={20,38}, [5962]={3,39},
  [5963]={5,39}, [5964]={10,39}, [5965]={20,39}, [6137]={4,41}, [6138]={6,41}, [6139]={8,41}, [6140]={10,41}, [6141]={2,41}, [6142]={3,41}, [6143]={5,41},
  [6144]={10,41}, [6145]={20,41},
}


local OC = {MeleeWeapon = 1, Armor = 2, Clothing = 3, Jewelry = 4, Food = 6, Money = 7, Misc = 8, MissileWeapon = 9,
  Container = 10, Gem = 11, SpellComponent = 12, Key = 13, TradeNote = 15, ManaStone = 16, Plant = 17, BaseCooking = 18,
  BaseAlchemy = 19, CraftedCooking = 21, CraftedAlchemy = 22, CraftedFletching = 23, HealingKit = 29, Lockpick = 30,
  WandStaffOrb = 31, Bundle = 32, Foci = 38, Salvage = 39, Ust = 40}

-- Helpers -------------------------------------------------------------------------
local contains, lower, sub = string.contains, string.lower, string.sub
local function starts(s, p) return sub(s, 1, #p) == p end
local function ends(s, p) return #s >= #p and sub(s, -#p) == p end
local function round(x) return math.floor(x + 0.5) end
local function g1(v)   -- like C#'s default number text for values rounded to 1 decimal
  if v == math.floor(v) then return string.format("%d", v) end
  return string.format("%.1f", v)
end
local function commas(n)
  local s = string.format("%d", n)
  local out, k = {}, 0
  for i = #s, 1, -1 do
    local c = sub(s, i, i)
    if k > 0 and k % 3 == 0 and c ~= "-" then out[#out + 1] = "," end
    out[#out + 1] = c; k = k + 1
  end
  local r = {}
  for i = #out, 1, -1 do r[#r + 1] = out[i] end
  return table.concat(r)
end
local function join(parts, sep) return table.concat(parts, sep) end
local function rx(text, pattern) return regexmatch(text, pattern) ~= nil end
local function safe(s)
  local out = {}
  for i = 1, math.min(#(s or ""), 28) do
    local c = sub(s, i, i); local b = string.byte(c)
    if (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or (b >= 48 and b <= 57) or c == "-" or c == "_" then out[#out + 1] = c
    elseif c == " " or c == "'" then out[#out + 1] = "_" end
  end
  return table.concat(out)
end

-- Item formatting (ItemInfo, ItemListRow), in its own block: Lua allows 200
-- locals in one scope, and only these few are needed outside it.
local B = {}
do
-- Item properties (Decal keys, as the client sends them) ------------------------
-- Whole numbers as integers (the client may send 1.0), so they read "CDR1", not "CDR1.0".
local function int(n) return math.tointeger(n) or n end
local function I(it, k, d) local v = it.ip[k]; if v == nil then return d or 0 end v = tonumber(v); if v == nil then return d or 0 end return int(v) end
local function F(it, k, d) local v = it.fp[k]; if v == nil then return d or 0 end return tonumber(v) or d or 0 end
local function S(it, k) local v = it.sp[k]; return type(v) == "string" and v or "" end
local function item_of(rec)
  local ip = type(rec.int_properties) == "table" and rec.int_properties or {}
  return {rec = rec, ip = ip, fp = type(rec.float_properties) == "table" and rec.float_properties or {},
    sp = type(rec.string_properties) == "table" and rec.string_properties or {},
    oc = tonumber(rec.object_class) or 0, name = type(rec.name) == "string" and rec.name or "",
    idd = rec.identified == true, names = type(rec.spell_names) == "table" and rec.spell_names or {},
    ids = type(rec.spell_ids) == "table" and rec.spell_ids or {}}
end
local SLOTS, COVER, OVERLAY, UNDERLAY, STACK, STACKMAX = "218103822", "218103821", "218103849", "218103850", "218103814", "218103815"

-- Classification (ItemInfo) ------------------------------------------------------
local function is_weapon(it) return it.oc == OC.MeleeWeapon or it.oc == OC.MissileWeapon or it.oc == OC.WandStaffOrb end
local function is_cloak(it) return it.oc == OC.Clothing and I(it, SLOTS) == 0x8000000 end
local function is_armor_clothing(it) return (it.oc == OC.Armor or it.oc == OC.Clothing) and not is_cloak(it) end
local function is_jewelry(it) return it.oc == OC.Jewelry end
local function is_summon(it) return it.oc == OC.Misc and I(it, "91") == 50 and (ends(it.name, "Essence") or contains(it.name, "Essence (")) end
-- Aetheria: plain "Aetheria" or named ones (Dragon's Rage Aetheria), recognised by the sigil slots.
local function is_aetheria(it) return it.name == "Aetheria" or (I(it, SLOTS) & 0x70000000) ~= 0 end
local function is_rare(it) return I(it, UNDERLAY) == 23308 end
local function is_salvage(it) return it.oc == OC.Salvage end
local function is_foolproof(it) return ends(it.name, " Foolproof") end
local function is_clothing(it)
  return it.oc == OC.Clothing and not is_cloak(it) and I(it, "28") == 0 and (I(it, SLOTS) & (0x02 | 0x40)) ~= 0
end
local function is_ammo(it) return it.oc == OC.MissileWeapon and I(it, STACKMAX) > 0 end
local NO_APPRAISAL = {[OC.Salvage] = true, [OC.SpellComponent] = true, [OC.Food] = true, [OC.Money] = true, [OC.TradeNote] = true,
  [OC.Plant] = true, [OC.Ust] = true, [OC.Foci] = true, [OC.Bundle] = true, [OC.Container] = true}
local function needs_no_appraisal(it)
  if is_aetheria(it) or is_rare(it) then return false end
  return NO_APPRAISAL[it.oc] == true
end

local function material(it)
  local m = I(it, "131")
  if m <= 0 then return "" end
  return MATERIAL[m] or ("Unknown Material " .. m)
end
local function full_name(it)
  local m = material(it)
  if m ~= "" and not starts(it.name, m .. " ") then return m .. " " .. it.name end
  return it.name
end
local function with_count(it, name)
  local n = I(it, STACK, tonumber(it.rec.count) or 1)
  return n > 1 and (name .. " (" .. string.format("%d", n) .. ")") or name
end

local function weapon_max(skill, mastery, multi, field)
  for _, e in ipairs(WEAPON_MAX) do if e[1] == skill and e[2] == mastery and e[3] == multi then return e[field] end end
  return 0
end
local function weapon_skill(it)
  local s = I(it, "159")
  if s ~= 0 then return s end
  local mastery = I(it, "353")
  if it.oc == OC.MeleeWeapon then
    if mastery == 11 then return 41 end
    if weapon_max(45, mastery, 0, 4) > 0 then return 45 end
    if weapon_max(44, mastery, 0, 4) > 0 then return 44 end
  elseif it.oc == OC.MissileWeapon then
    if weapon_max(47, mastery, 0, 5) > 0 then return 47 end
  elseif it.oc == OC.WandStaffOrb then
    if weapon_max(34, mastery, 0, 7) > 0 then return 34 end
    if weapon_max(43, mastery, 0, 7) > 0 then return 43 end
  end
  return 0
end
local RX_NETHER = "(?i)\\b(Nether|Corrupted)\\b"
local RX_HEAVY = "(?i)\\b(Silifi|Lugian|War Axe|Battle|Dirk|Stiletto|Jambiya|Mazule|Mace|Morning|Glaive|Trident|Partizan|Nabut|Stick|Takuba|Flamberge|Ken|Long|Tachi|Schlager|Nekode|Cestus)\\b"
local RX_FINESSE = "(?i)\\b(Hatchet|Shou-ono|Tungi|Hammer|Poniard|Knife|Lancet|Board|Tofun|Dabus|Naginata|Budiaq|Jo|Bastone|Scimitar|Yaoji|Short|Sabra|Simi|Rapier|Claw|Wraps)\\b"
local RX_LIGHT = "(?i)\\b(Dolabra|Ono|Hand|War Hammer|Khanjar|Dagger|Club|Kasrullah|Spear|Yari|Quarter|Broad|Shamshir|Epee|Katar|Knuckles)\\b"
local RX_XBOW, RX_THROWN = "(?i)\\b(Crossbow|Arbalest)\\b", "(?i)\\b(Atlatl|Slingshot)\\b"
local function guess_weapon_type(it)
  local n = it.name
  if it.oc == OC.WandStaffOrb then return rx(n, RX_NETHER) and "Nether" or "War" end
  if it.oc == OC.MeleeWeapon then
    if (I(it, SLOTS) & 0x02000000) ~= 0 then return "Two Hand" end
    if rx(n, RX_HEAVY) then return "Heavy" end
    if rx(n, RX_FINESSE) then return "Finesse" end
    if rx(n, RX_LIGHT) then return "Light" end
    return "Melee"
  end
  if it.oc == OC.MissileWeapon then
    if rx(n, RX_XBOW) then return "Crossbow" end
    if rx(n, RX_THROWN) then return "Thrown" end
    return "Bow"
  end
  return ""
end
local function caster_school(it)
  if I(it, "158") == 2 then
    local a = I(it, "159")
    if a == 34 then return "War" elseif a == 33 then return "Life" elseif a == 43 then return "Nether" end
  end
  if (I(it, "45") & 1024) ~= 0 then return "Nether" end
  if it.idd then return "No Wield" end
  return guess_weapon_type(it)
end
local function weapon_type(it)
  if it.oc == OC.WandStaffOrb then return caster_school(it) end
  local s = weapon_skill(it)
  if s == 44 then return "Heavy" elseif s == 45 then return "Light" elseif s == 46 then return "Finesse" elseif s == 41 then return "Two Hand" end
  return guess_weapon_type(it)
end

-- Armor slots: Head 1, Chest 2, Abdomen 4, Upper Arms 8, Lower Arms 16, Hands 32, Upper Legs 64, Lower Legs 128, Feet 256.
local function armor_slots(it)
  local s, c, r = I(it, SLOTS), I(it, COVER), 0
  if (s & 0x01) ~= 0 or (c & 0x4000) ~= 0 then r = r | 1 end
  if (s & 0x200) ~= 0 or (s & 0x02) ~= 0 or (c & 0x08) ~= 0 or (c & 0x400) ~= 0 then r = r | 2 end
  if (s & 0x400) ~= 0 or (s & 0x04) ~= 0 or (c & 0x10) ~= 0 or (c & 0x800) ~= 0 then r = r | 4 end
  if (s & 0x800) ~= 0 or (s & 0x08) ~= 0 or (c & 0x20) ~= 0 or (c & 0x1000) ~= 0 then r = r | 8 end
  if (s & 0x1000) ~= 0 or (s & 0x10) ~= 0 or (c & 0x40) ~= 0 or (c & 0x2000) ~= 0 then r = r | 16 end
  if (s & 0x20) ~= 0 or (c & 0x8000) ~= 0 then r = r | 32 end
  if (s & 0x2000) ~= 0 or (s & 0x40) ~= 0 or (c & 0x02) ~= 0 or (c & 0x100) ~= 0 then r = r | 64 end
  if (s & 0x4000) ~= 0 or (s & 0x80) ~= 0 or (c & 0x04) ~= 0 or (c & 0x200) ~= 0 then r = r | 128 end
  if (s & 0x100) ~= 0 or (c & 0x10000) ~= 0 then r = r | 256 end
  return r
end
local SLOT_NAMES = {{1, "Head"}, {2, "Chest"}, {4, "Abdomen"}, {8, "Upper Arms"}, {16, "Lower Arms"}, {32, "Hands"},
  {64, "Upper Legs"}, {128, "Lower Legs"}, {256, "Feet"}}
local function slot_coverage(it)
  local m = armor_slots(it)
  local function has(b) return (m & b) ~= 0 end
  local covered = {}
  for _, p in ipairs(SLOT_NAMES) do if has(p[1]) then covered[#covered + 1] = p[2] end end
  if has(2) and has(4) and has(8) and has(16) and has(64) and has(128) then return "Robe" end
  if #covered == 0 then return "" end
  if #covered == 1 then return covered[1] end
  if has(256) and has(128) and #covered == 2 then return "Feet" end
  if #covered >= 3 then
    local gname = ""
    if has(4) and has(64) and has(128) and not has(2) and not has(8) and not has(16) then gname = "Leggings"
    elseif has(2) and has(4) and has(8) and not has(16) and not has(64) and not has(128) then gname = "Chest"
    elseif has(2) and has(4) and has(8) and has(16) and not has(64) and not has(128) then gname = "Chest" end
    if gname ~= "" then return gname .. " " .. #covered .. "-slot" end
  end
  -- "Upper Arms Lower Arms" reads "Upper Lower Arms" (same for legs)
  local out, i = {}, 1
  while i <= #covered do
    local a, b = covered[i], covered[i + 1]
    if a == "Upper Arms" and b == "Lower Arms" then out[#out + 1] = "Upper Lower Arms"; i = i + 2
    elseif a == "Upper Legs" and b == "Lower Legs" then out[#out + 1] = "Upper Lower Legs"; i = i + 2
    else out[#out + 1] = a; i = i + 1 end
  end
  return join(out, " ")
end
local function slot_name(it)
  local s = I(it, SLOTS)
  if it.oc == OC.Clothing and I(it, "28") == 0 then
    if (s & 0x02) ~= 0 then return "Shirt" end
    if (s & 0x40) ~= 0 then return "Pants" end
  end
  if it.oc == OC.Jewelry then
    if (s & 0xC0000) ~= 0 then return "Ring" end
    if (s & 0x30000) ~= 0 then return "Bracelet" end
    if (s & 0x8000) ~= 0 then return "Necklace" end
    if (s & 0x4000000) ~= 0 then return "Trinket" end
    local n = lower(it.name)
    if contains(n, "ring") or contains(n, "band") or contains(n, "signet") then return "Ring" end
    if contains(n, "bracelet") then return "Bracelet" end
    for _, w in ipairs({"necklace", "gorget", "amulet", "pendant", "choker", "locket"}) do if contains(n, w) then return "Necklace" end end
    for _, w in ipairs({"trinket", "compass", "pocket", "goggles", "puzzle box", " top", "scarab"}) do if contains(n, w) then return "Trinket" end end
    return "Jewelry"
  end
  if (s & 0x200000) ~= 0 then return "Shield" end
  return slot_coverage(it)
end

local function aetheria_color(it)
  local s = I(it, SLOTS)
  if (s & 0x10000000) ~= 0 then return "Blue" end
  if (s & 0x20000000) ~= 0 then return "Yellow" end
  if (s & 0x40000000) ~= 0 then return "Red" end
  return ""
end
local function overlay_level(it) local o = I(it, OVERLAY); if o == 0 then return 0 end return o - 27700 + 1 end
local function set_full(it) local s = I(it, "265"); if s == 0 then return "" end return SET_FULL[s] or "Unknown Set" end
local function set_short(it) local s = I(it, "265"); return s ~= 0 and SET_SHORT[s] or "" end

local function item_slot_name(it)
  if is_weapon(it) then return weapon_type(it) end
  if is_armor_clothing(it) or is_jewelry(it) then return slot_name(it) end
  if is_aetheria(it) then local c = aetheria_color(it); return c ~= "" and ("Aetheria " .. c) or "Aetheria" end
  if is_cloak(it) then return "Cloak" end
  if is_summon(it) then return "Summon" end
  if is_rare(it) then return "Rare" end
  if is_foolproof(it) then return "Foolproof" end
  if it.oc == OC.SpellComponent then return "Component" end
  if it.oc == OC.CraftedFletching then return "Fletching" end
  if it.oc == OC.CraftedAlchemy then return "Alchemy" end
  if it.oc == OC.CraftedCooking or it.oc == OC.BaseCooking then return "Cooking" end
  return OC_NAME[it.oc] or "Unknown"
end
local function element_name(it)
  if not is_weapon(it) then return "" end
  local dt = it.oc == OC.WandStaffOrb and I(it, "45") or I(it, "218103841")
  if (dt & 1) ~= 0 then return "Slash" end
  if (dt & 2) ~= 0 then return "Pierce" end
  if (dt & 4) ~= 0 then return "Bludgeon" end
  if (dt & 8) ~= 0 then return "Cold" end
  if (dt & 16) ~= 0 then return "Fire" end
  if (dt & 32) ~= 0 then return "Acid" end
  if (dt & 64) ~= 0 then return "Lightning" end
  if (dt & 1024) ~= 0 then return "Nether" end
  return ""
end
local function summon_spec(it)
  if not is_summon(it) then return "" end
  if rx(it.name, "(?i)Moar|Grievver|Phyntos") then return "Naturalist" end
  if rx(it.name, "(?i)Zombie|Spectre|Skeleton|Maiden") then return "Necromancer" end
  if rx(it.name, "(?i)Elemental|Child|Wisp|Knight|K'nath") then return "Primalist" end
  return "Generic"
end

-- Ratings, imbues, spells ---------------------------------------------------------
local function ratings(it)
  local d, dr, c, cr, cd, cdr, hb, v = I(it, "370"), I(it, "371"), I(it, "372"), I(it, "373"), I(it, "374"), I(it, "375"), I(it, "376"), I(it, "379")
  if d + dr + c + cr + cd + cdr + hb + v <= 0 then return "" end
  local p = {}
  if d > 0 then p[#p + 1] = "D" .. d end
  if dr > 0 then p[#p + 1] = "DR" .. dr end
  if c > 0 then p[#p + 1] = "C" .. c end
  if cd > 0 then p[#p + 1] = "CD" .. cd end
  if cr > 0 then p[#p + 1] = "CR" .. cr end
  if cdr > 0 then p[#p + 1] = "CDR" .. cdr end
  if hb > 0 then p[#p + 1] = "HB" .. hb end
  if v > 0 then p[#p + 1] = "V" .. v end
  return join(p, " ")
end
local function is_imbued(it)
  return I(it, "179") ~= 0 or I(it, "303") ~= 0 or I(it, "304") ~= 0 or I(it, "305") ~= 0 or I(it, "306") ~= 0
end
local IMBUE_BITS = {{1, "CS"}, {2, "CB"}, {4, "AR"}, {8, "SR"}, {16, "PR"}, {32, "BR"}, {64, "AcR"},
  {128, "CR"}, {256, "LR"}, {512, "FR"}, {1024, "MeleeImbue"}, {4096, "MagicImbue"}, {8192, "Hematited"},
  {0x4000, "NR"}, {536870912, "Absorb"}}
local CLEAVE = {[1] = "SlashCleave", [2] = "PierceCleave", [4] = "BludgeCleave", [8] = "ColdCleave", [16] = "FireCleave", [32] = "AcidCleave", [64] = "LightCleave"}
local function imbues(it)
  local p, m = {}, I(it, "179")
  if m > 0 then for _, b in ipairs(IMBUE_BITS) do if (m & b[1]) ~= 0 then p[#p + 1] = b[2] end end end
  local cl = CLEAVE[I(it, "263")]
  if cl then p[#p + 1] = cl end
  if F(it, "136") > 1 then p[#p + 1] = "CB" end
  if F(it, "147") > 0 then p[#p + 1] = "BS" end
  return join(p, " ")
end
local TIERS = {"Legendary ", "Epic ", "Major ", "Moderate ", "Minor "}
local function tier(n) for i, t in ipairs(TIERS) do if starts(n, t) then return i - 1 end end return 5 end
local function base_name(n) local t = tier(n); if t < 5 then return sub(n, #TIERS[t + 1] + 1) end return n end
local function distinct(list)
  local out, seen = {}, {}
  for _, n in ipairs(list) do local k = lower(n); if not seen[k] then seen[k] = true; out[#out + 1] = n end end
  return out
end
local LOW_RANKS = {" I", " II", " III", " IV", " V", " VI"}
local function show_spell(n, loot, unench)
  if not loot then return true end
  local bane = contains(n, " Bane") or starts(n, "Brogard")
  if bane and not unench then return false end
  local impen = false
  for _, t in ipairs(TIERS) do if contains(n, t .. "Impenetrability") then impen = true end end
  if not impen and not bane and not contains(n, "Augmented") then
    for _, r in ipairs(LOW_RANKS) do if ends(n, r) then return false end end
  end
  return true
end
-- Spell names with their ids (the client sends a name for each id it knows).
local function spell_list(it)
  local out = {}
  if #it.names == #it.ids then for i = 1, #it.ids do out[i] = {tonumber(it.ids[i]) or 0, it.names[i]} end
  else for i = 1, #it.names do out[i] = {0, it.names[i]} end end
  return out
end
local function spells_string(it)
  if #it.names == 0 then return "" end
  local list = spell_list(it)
  table.sort(list, function(a, b) return a[1] > b[1] end)
  local loot, unench = I(it, "131") ~= 0, I(it, "36") ~= 0
  local cantrips, others = {}, {}
  for _, p in ipairs(list) do
    local n = p[2]
    if show_spell(n, loot, unench) then if tier(n) < 5 then cantrips[#cantrips + 1] = n else others[#others + 1] = n end end
  end
  table.sort(cantrips, function(a, b)
    local ta, tb = tier(a), tier(b)
    if ta ~= tb then return ta < tb end
    return lower(base_name(a)) < lower(base_name(b))
  end)
  for _, n in ipairs(others) do cantrips[#cantrips + 1] = n end
  return join(distinct(cantrips), ", ")
end
local function cantrips_string(it)
  local p = {}
  for _, n in ipairs(it.names) do if not ends(n, " Bane") and tier(n) < 5 then p[#p + 1] = n end end
  table.sort(p, function(a, b) return tier(a) < tier(b) end)
  return join(distinct(p), ", ")
end
local CLOAK_PROCS = {{"Cloaked in Skill", "CiS"}, {"Shroud of Darkness (Melee)", "Melee Shroud"}, {"Shroud of Darkness (Missile)", "Missile Shroud"},
  {"Shroud of Darkness (Magic)", "Magic Shroud"}, {"Shroud of Darkness", "Shroud"}, {"Horizon's Blades", "Blade Ring"},
  {"Tectonic Rifts", "Bludgeon Ring"}, {"Nuhmudira's Spines", "Piercing Ring"}, {"Searing Disc", "Acid Ring"},
  {"Cassius' Ring of Fire", "Fire Ring"}, {"Halo of Frost", "Frost Ring"}, {"Eye of the Storm", "Lightning Ring"},
  {"Clouded Soul", "Void Ring"}, {"Major Melee", "Melee Ring"}, {"Major Magic", "Magic Ring"}}
local function cloak_proc(it)
  local n = it.names[1]
  if n then
    for _, p in ipairs(CLOAK_PROCS) do if contains(n, p[1]) then return p[2] end end
    return n
  end
  if I(it, "352") ~= 0 then return "-200 Damage" end
  return ""
end
local function aetheria_surge(it)
  for _, n in ipairs(it.names) do
    for _, w in ipairs({"Destruction", "Protection", "Regeneration", "Affliction", "Festering", "Mana"}) do if contains(n, w) then return w end end
  end
  return ""
end

-- Requirements and numbers --------------------------------------------------------
local function wield_name(it)
  if I(it, "160") > 0 then
    if I(it, "158") == 7 and I(it, "159") == 1 then return "Wield Lvl" end
    return SKILL[I(it, "159")] or ("Unknown Skill " .. I(it, "159"))
  end
  if I(it, "369") > 0 then return "Wield Lvl" end
  if I(it, "366") > 0 and SKILL[I(it, "366")] then return SKILL[I(it, "366")] end
  return ""
end
local function wield_level(it)
  if I(it, "160") > 0 then return I(it, "160") end
  if I(it, "369") > 0 then return I(it, "369") end
  if I(it, "367") > 0 then return I(it, "367") end
  return 0
end
local function wield_string(it) local n = wield_name(it); if n == "" then return "" end return n .. " " .. wield_level(it) end
local function tinks_string(it) local t = I(it, "171"); return t > 0 and ("Tinks " .. t) or "" end
local function slayer_string(it)
  local s = I(it, "166")
  if s <= 0 then return "" end
  return (SLAYERSPECIES[s] or "Unknown") .. " Slayer"
end
local function weapon_extras(it)
  local p = {}
  local msl = math.floor((F(it, "149", 1) - 1) * 1000 + 0.5) / 10
  if msl ~= 0 then p[#p + 1] = g1(msl) .. "%msl.d" end
  local mgc = math.floor((F(it, "150", 1) - 1) * 1000 + 0.5) / 10
  if mgc ~= 0 then p[#p + 1] = g1(mgc) .. "%mgc.d" end
  return join(p, ", ")
end
local function summon_scores(it)
  local D, C, CD, DR, CR, CDR = I(it, "370"), I(it, "372"), I(it, "374"), I(it, "371"), I(it, "373"), I(it, "375")
  local dmg = round(((0.625 * (1 + D / 100) * (0.9 - C / 100) + 2 * (1 + (D + CD) / 100) * (0.1 + C / 100)) - 0.7625) * 165.9751)
  local def = round((0.7625 - (0.625 * (1 - DR / 100) * (0.9 + CR / 1000) + 2 * (1 - (DR + CDR) / 100) * (0.1 - CR / 1000))) / 0.002065)
  return "DMG " .. string.format("%d", dmg) .. "% | DEF " .. string.format("%d", def) .. "%"
end
local function healing_kit_string(it)
  local p = {}
  local skill = I(it, "90")
  if skill ~= 0 then p[#p + 1] = (skill > 0 and "+" or "") .. skill .. " Skill" end
  local restore = F(it, "100")
  if restore > 0 then p[#p + 1] = "+" .. string.format("%d", round(restore * 100)) .. "% Bonus" end
  return join(p, " | ")
end
local function mana_stone_string(it)
  local p = {}
  local e = F(it, "87")
  if e > 0 then p[#p + 1] = g1(math.floor(e * 1000 + 0.5) / 10) .. "% Efficient" end
  local d = F(it, "137")
  if d > 0 then p[#p + 1] = g1(math.floor(d * 1000 + 0.5) / 10) .. "% Chance" end
  return join(p, " | ")
end
local function salvage_work(it) return F(it, "167772169") end
local function damage_string(it)
  local p, high, var = {}, I(it, "218103842"), F(it, "167772171")
  if high ~= 0 and var ~= 0 then p[#p + 1] = string.format("%.2f", high - high * var) .. "-" .. high
  elseif high ~= 0 then p[#p + 1] = tostring(high) end
  if I(it, "204") ~= 0 then p[#p + 1] = "+" .. I(it, "204") end
  local pct = round((F(it, "167772174", 1) - 1) * 100)
  if pct ~= 0 then p[#p + 1] = "+" .. pct .. "%" end
  local vs = round((F(it, "152", 1) - 1) * 100)
  if vs ~= 0 then p[#p + 1] = "+" .. vs .. "%vs. Monsters" end
  return join(p, ", ")
end
local function bonuses_string(it)
  local p = {}
  local a = round((F(it, "167772172", 1) - 1) * 100)
  if a ~= 0 then p[#p + 1] = "+" .. a .. "%a" end
  local md = round((F(it, "29", 1) - 1) * 100)
  if md ~= 0 then p[#p + 1] = md .. "%md" end
  local mg = math.floor((F(it, "150", 1) - 1) * 1000 + 0.5) / 10
  if mg ~= 0 then p[#p + 1] = g1(mg) .. "%mgc.d" end
  local ms = math.floor((F(it, "149", 1) - 1) * 1000 + 0.5) / 10
  if ms ~= 0 then p[#p + 1] = g1(ms) .. "%msl.d" end
  local mc = round(F(it, "144") * 100)
  if mc ~= 0 then p[#p + 1] = mc .. "%mc" end
  return join(p, ", ")
end
local function summon_reqs(it)
  local p = {}
  if I(it, "369") > 0 then p[#p + 1] = "Lvl " .. I(it, "369") end
  if I(it, "115") > 0 and (I(it, "159") ~= I(it, "176") or I(it, "160") < I(it, "115")) then
    p[#p + 1] = (SKILL[I(it, "176")] or ("Unknown Skill " .. I(it, "176"))) .. " " .. I(it, "115") .. " to Activate"
  end
  if I(it, "366") > 0 and I(it, "367") > 0 then p[#p + 1] = (SKILL[I(it, "366")] or ("Unknown Skill " .. I(it, "366"))) .. " " .. I(it, "367") end
  if I(it, "368") > 0 and I(it, "367") > 0 then p[#p + 1] = "Spec " .. (SKILL[I(it, "368")] or ("Unknown Skill " .. I(it, "368"))) .. " " .. I(it, "367") end
  return join(p, ", ")
end
local function protections(it)
  if it.oc ~= OC.Armor or I(it, "36") == 0 then return "" end
  local p = {}
  for k = 167772160, 167772166 do p[#p + 1] = string.format("%.1f", F(it, tostring(k))) end
  -- Decal order Slash/Pierce/Bludgeon/Acid/Lightning/Fire/Cold; OOD prints Slash/Pierce/Bludgeon/Cold/Fire/Acid/Lightning
  return "[" .. join({p[1], p[2], p[3], p[7], p[6], p[4], p[5]}, "/") .. "]"
end

-- Columns (ItemListRow) -------------------------------------------------------------
local CAT_ORDER = {W = 0, A = 1, J = 2, K = 3, S = 4, E = 5, V = 6, C = 7, O = 9}
local function category(it)
  if is_weapon(it) and not is_ammo(it) then return "W" end
  if is_clothing(it) then return "C" end
  if is_armor_clothing(it) then return "A" end
  if is_jewelry(it) then return "J" end
  if is_cloak(it) then return "K" end
  if is_summon(it) then return "S" end
  if is_aetheria(it) then return "E" end
  if is_salvage(it) or is_foolproof(it) then return "V" end
  return "O"
end
local function col1(it)
  local t = item_slot_name(it)
  if is_weapon(it) then
    local e = element_name(it)
    if e ~= "" and e ~= t then t = t .. " " .. e end
  elseif is_summon(it) then t = summon_spec(it) end
  return t
end
local function col2(it)
  if is_weapon(it) then return imbues(it) end
  if is_cloak(it) then return cloak_proc(it) end
  if is_armor_clothing(it) or is_jewelry(it) then return set_short(it) end
  if is_salvage(it) then return SALVAGETINKERSKILL[I(it, "131")] or "Unknown Tink" end
  return ""
end

-- Weapon OD, attack and melee-defense values (Oracle of Dereth ItemInfo: WeaponMaxTable,
-- the max attack/defense tables and the cantrip effects; values without the item's cantrips).
local WEAPON_MAX = {}   -- "skill|mastery|multi" -> {dmg, dmg_mod, elem, vs_mon}
for _, e in ipairs({
  {44, 3, 0, 74}, {44, 6, 0, 71}, {44, 6, 1, 38}, {44, 4, 0, 69}, {44, 5, 0, 72}, {44, 2, 0, 71}, {44, 2, 1, 38}, {44, 7, 0, 70}, {44, 1, 0, 59},
  {45, 3, 0, 61}, {45, 6, 0, 58}, {45, 6, 1, 28}, {45, 4, 0, 57}, {45, 5, 0, 60}, {45, 2, 0, 58}, {45, 2, 1, 28}, {45, 7, 0, 57}, {45, 1, 0, 48},
  {46, 3, 0, 61}, {46, 6, 0, 58}, {46, 6, 1, 28}, {46, 4, 0, 57}, {46, 5, 0, 60}, {46, 2, 0, 58}, {46, 2, 1, 28}, {46, 7, 0, 57}, {46, 1, 0, 48},
  {41, 11, 1, 45}, {41, 11, 0, 48},
  {47, 8, 0, 0, 140, 22}, {47, 9, 0, 0, 165, 22}, {47, 10, 0, 0, 160, 22},
  {34, 0, 0, 0, 0, 0, 1.18}, {43, 0, 0, 0, 0, 0, 1.18}, {43, 12, 0, 0, 0, 0, 1.18}}) do
  WEAPON_MAX[e[1] .. "|" .. e[2] .. "|" .. e[3]] = {dmg = e[4] or 0, mod = e[5] or 0, elem = e[6] or 0, vs = e[7] or 0}
end
local function wmax(skill, mastery, multi, f) local e = WEAPON_MAX[skill .. "|" .. mastery .. "|" .. multi]; return e and e[f] or 0 end
local MAX_DEF = {[1] = 20, [2] = 20, [3] = 18, [4] = 22, [5] = 15, [6] = 20, [7] = 25}
local MAX_ATK = {[1] = 20, [2] = 20, [3] = 22, [4] = 18, [5] = 25, [6] = 20, [7] = 15}
local K_MAXDMG, K_ATK, K_DEF, K_VSMON, K_DMGMOD = "218103842", "167772172", "29", "152", "167772174"
-- cantrips: spell id -> {key, bonus}
local INT_CANTRIP = {[2598] = {K_MAXDMG, 2}, [2586] = {K_MAXDMG, 4}, [4661] = {K_MAXDMG, 7}, [6089] = {K_MAXDMG, 10}}
local DBL_CANTRIP = {[3251] = {K_VSMON, .01}, [3250] = {K_VSMON, .03}, [4670] = {K_VSMON, .05}, [6098] = {K_VSMON, .07},
  [2603] = {K_ATK, .03}, [2591] = {K_ATK, .05}, [4666] = {K_ATK, .07}, [6094] = {K_ATK, .09},
  [2600] = {K_DEF, .03}, [3985] = {K_DEF, .04}, [2588] = {K_DEF, .05}, [4663] = {K_DEF, .07}, [6091] = {K_DEF, .09}}
local function has(t, k) return t[k] ~= nil end
local function buffed_int(it, key)
  local v = I(it, key)
  for _, sp in ipairs(it.ids) do local c = INT_CANTRIP[math.tointeger(tonumber(sp)) or 0]; if c and c[1] == key then v = v + c[2] end end
  return v
end
local function buffed_dbl(it, key, d)
  if not has(it.fp, key) then return d or 0 end
  local v = F(it, key)
  for _, sp in ipairs(it.ids) do local c = DBL_CANTRIP[math.tointeger(tonumber(sp)) or 0]; if c and c[1] == key then v = v + c[2] end end
  return v
end
local function round(x) return x >= 0 and math.floor(x + 0.5) or -math.floor(-x + 0.5) end
local function two_hand_spear(it)
  local n = lower(it.name)
  for _, w in ipairs({"spear", "pike", "assagai", "yari", "naginata", "trident"}) do if contains(n, w) then return true end end
  return false
end
local function w_mastery(it)
  local m = I(it, "353"); if m ~= 0 then return m end
  local sk = I(it, "159"); if sk == 41 then return 11 end
  return 0
end
local function w_skill(it)
  local sk = I(it, "159"); if sk ~= 0 then return sk end
  local m = I(it, "353")
  if it.oc == OC.MeleeWeapon then
    if m == 11 then return 41 end
    if wmax(45, m, 0, "dmg") > 0 then return 45 end
    if wmax(44, m, 0, "dmg") > 0 then return 44 end
  elseif it.oc == OC.MissileWeapon then if wmax(47, m, 0, "mod") > 0 then return 47 end
  elseif it.oc == OC.WandStaffOrb then
    if wmax(34, m, 0, "vs") > 0 then return 34 end
    if wmax(43, m, 0, "vs") > 0 then return 43 end
  end
  return 0
end
local function multi_strike(it)
  local cu, m = I(it, "47"), I(it, "353")
  return cu == 160 or cu == 166 or cu == 486 or (cu == 4 and m == 11 and not two_hand_spear(it))
end
local function weapon_od(it)
  if it.rec.equipped == true then return nil end   -- worn: the values include active buffs
  local r
  if it.oc == OC.MeleeWeapon then
    if not has(it.ip, K_MAXDMG) then return nil end
    local mx = wmax(w_skill(it), w_mastery(it), multi_strike(it) and 1 or 0, "dmg")
    if mx <= 0 then return nil end
    r = round(buffed_int(it, K_MAXDMG) - mx)
  elseif it.oc == OC.MissileWeapon then
    local m = w_mastery(it)
    local arrow = m == 8 and 40 or m == 9 and 53 or m == 10 and 42 or nil
    if not arrow then return nil end
    local sk = w_skill(it)
    local mod, elem = wmax(sk, m, 0, "mod"), wmax(sk, m, 0, "elem")
    if elem <= 0 then elem = 22 end
    local dmod = round((F(it, K_DMGMOD, 1) - 1) * 100)
    local tinks, left = I(it, "171"), 10
    if F(it, "167772169", -1) >= 0 then
      if tinks > 0 then left = left - tinks; if I(it, "179") == 0 then left = left - 1 end else left = left - 1 end
    else left = 0 end
    local maxmod = (mod + 100 + 4 * left) / 100
    if maxmod <= 0 then return nil end
    local dmg = buffed_int(it, K_MAXDMG)
    if dmg <= 10 then dmg = dmg + 24 end
    local calc = (1 + (dmod + 4 * left) / 100) * (I(it, "204") + dmg + arrow) / maxmod
    r = round(calc - (elem + 24 + arrow))
  elseif it.oc == OC.WandStaffOrb then
    local vs = wmax(w_skill(it), w_mastery(it), 0, "vs")
    if vs <= 0 then vs = 1.18 end
    r = round((buffed_dbl(it, K_VSMON) - 1) * 100 - (vs - 1) * 100)
  end
  if r == nil or r < -15 or r > 30 then return nil end
  return r
end
local function weapon_attack(it) return round((buffed_dbl(it, K_ATK, 1) - 1) * 100) end
local function weapon_melee(it) return round((buffed_dbl(it, K_DEF, 1) - 1) * 100) end
-- Info for weapons: "OD +5 | 18% | 20% | w8"
local function weapon_info(it)
  local p = {}
  local od = weapon_od(it)
  if od then p[#p + 1] = "OD " .. (od >= 0 and "+" or "") .. od end
  local a, m = weapon_attack(it), weapon_melee(it)
  if a ~= 0 then p[#p + 1] = a .. "%" end
  if m ~= 0 then p[#p + 1] = m .. "%" end
  local w = I(it, "105"); if w > 0 then p[#p + 1] = "w" .. w end
  return join(p, " | ")
end
local function col3(it)
  if is_weapon(it) then return weapon_info(it) end
  if is_salvage(it) then local w = salvage_work(it); return w > 0 and ("Work " .. string.format("%.2f", w)) or "" end
  if it.oc == OC.HealingKit then return healing_kit_string(it) end
  if it.oc == OC.ManaStone then return mana_stone_string(it) end
  if is_cloak(it) or is_aetheria(it) then return ratings(it) end
  if is_summon(it) then return summon_scores(it) end
  if is_armor_clothing(it) or is_jewelry(it) then return ratings(it) end
  return ""
end
local function col4(it)
  local c = ""
  if is_weapon(it) then c = cantrips_string(it)
  elseif is_cloak(it) then c = "Level " .. overlay_level(it) .. ", " .. set_full(it)
  elseif is_aetheria(it) then
    local p = {}
    if overlay_level(it) > 0 then p[#p + 1] = "Level " .. overlay_level(it) end
    if set_short(it) ~= "" then p[#p + 1] = set_short(it) end
    local s = aetheria_surge(it)
    if s ~= "" then p[#p + 1] = s end
    c = join(p, ", ")
  elseif is_armor_clothing(it) or is_jewelry(it) or is_rare(it) then c = spells_string(it)
  elseif is_salvage(it) then c = SALVAGEDESCRIPTION[I(it, "131")] or ""
  else c = S(it, "16") end
  local parts = {}
  if is_weapon(it) then local sl = slayer_string(it); if sl ~= "" then parts[#parts + 1] = sl end end
  if c ~= "" then parts[#parts + 1] = c end
  local w = wield_string(it)
  if w ~= "" and (is_summon(it) or wield_name(it) ~= "Wield Lvl") then parts[#parts + 1] = w end
  local t = tinks_string(it)
  if t ~= "" then parts[#parts + 1] = t end
  if is_weapon(it) then local x = weapon_extras(it); if x ~= "" then parts[#parts + 1] = x end end
  return join(parts, ", ")
end
-- Full description (ItemInfo.ToString), without the weapon OD values.
local function description(it)
  local p = {}
  local function add(v) if v ~= "" then p[#p + 1] = v end end
  add(full_name(it))
  local m = I(it, "353"); if m > 0 then add(MASTERY[m] or ("Unknown Mastery " .. m)) end
  if is_summon(it) then add(summon_scores(it)) end
  add(set_full(it))
  local r = ratings(it); if r ~= "" then add("[" .. r .. "]") end
  if I(it, "28") > 0 then add("AL " .. I(it, "28")) end
  add(imbues(it)); add(tinks_string(it)); add(damage_string(it)); add(bonuses_string(it)); add(spells_string(it))
  add(wield_string(it)); add(summon_reqs(it))
  if I(it, "109") > 0 then add("Diff " .. I(it, "109")) end
  if is_salvage(it) then local w = salvage_work(it); if w > 0 then add("Work " .. string.format("%.2f", w)) end
  elseif I(it, "105") > 0 and I(it, "171") ~= 10 then add("Craft " .. I(it, "105")) end
  add(protections(it))
  if I(it, "19") > 0 then add("Value " .. commas(I(it, "19"))) end
  if I(it, "5") > 0 then add("BU " .. I(it, "5")) end
  if it.oc == OC.Misc and contains(it.name, "Keyring") then add("Keys: " .. I(it, "193") .. ", Uses: " .. I(it, "92")) end
  return join(p, ", ")
end

-- Sub-filter tags --------------------------------------------------------------------
local WT_TAG = {Heavy = "HW", Finesse = "FW", Light = "LW", ["Two Hand"] = "2H", War = "War", Nether = "Void", Thrown = "TW", Bow = "Bow", Crossbow = "XBow"}
local SALVAGE_TAG = {Iron = "Iron", Granite = "Granite", Mahogany = "Mahogany", ["Green Garnet"] = "Green Garnet", Velvet = "Velvet",
  Brass = "Brass", Steel = "Steel"}
for _, m in ipairs({"Red Garnet", "Jet", "Imperial Topaz", "Emerald", "Black Garnet", "Aquamarine", "White Sapphire", "Sunstone", "Onyx"}) do SALVAGE_TAG[m] = "Rends" end
for _, m in ipairs({"Yellow Topaz", "Zircon", "Peridot", "Hematite", "Fire Opal", "Black Opal", "Diamond", "Ruby", "Gromnie Hide", "Pyreal"}) do SALVAGE_TAG[m] = "Imbues" end
local OTHER_TAG = {[OC.BaseAlchemy] = "Alchemy", [OC.CraftedAlchemy] = "Alchemy", [OC.SpellComponent] = "Component", [OC.BaseCooking] = "Cooking",
  [OC.CraftedCooking] = "Cooking", [OC.Food] = "Food", [OC.Gem] = "Gem", [OC.HealingKit] = "HealingKit", [OC.Key] = "Key",
  [OC.Lockpick] = "Lockpick", [OC.ManaStone] = "ManaStone", [OC.Misc] = "Misc"}
local CLOAK_PROC_TAG = {["-200 Damage"] = "-200", CiS = "CiS", ["Melee Shroud"] = "Melee", ["Missile Shroud"] = "Missile", ["Magic Shroud"] = "Magic"}
for _, n in ipairs({"Blade Ring", "Bludgeon Ring", "Piercing Ring", "Acid Ring", "Fire Ring", "Frost Ring", "Lightning Ring", "Void Ring", "Melee Ring", "Magic Ring"}) do CLOAK_PROC_TAG[n] = "AoE" end
-- Set tags as saved in rows ("Dextrous" is the saved tag; the box reads "Dexterous").
local SET_TAG = {[0] = "No Set", [14] = "Adept", [16] = "Defender", [20] = "Dextrous", [19] = "Hearty", [21] = "Wise"}
local function tags(it, cat, c1, c2)
  local t = {}
  local function add(g, v) t[#t + 1] = g .. ":" .. v end
  if cat == "W" then
    add("wt", WT_TAG[weapon_type(it)] or "Other")
    local l = lower(c1)
    for _, e in ipairs({{"Bludge", "bludge"}, {"Pierce", "pierce"}, {"Slash", "slash"}, {"Lightning", "lightning", "storm"}, {"Acid", "acid"},
      {"Fire", "fire", "flame"}, {"Cold", "cold", "frost"}, {"Nether", "nether", "void"}}) do
      if contains(l, e[2]) or (e[3] and contains(l, e[3])) then add("el", e[1]) end
    end
  elseif cat == "A" then
    local m = armor_slots(it)
    for _, p in ipairs({{1, "Head"}, {2, "Chest"}, {4, "Abdomen"}, {8, "UArm"}, {16, "LArm"}, {32, "Hands"}, {64, "ULeg"}, {128, "LLeg"}, {256, "Feet"}}) do
      if (m & p[1]) ~= 0 then add("as", p[2]) end
    end
    if it.ip["265"] ~= nil or it.idd then add("st", SET_TAG[I(it, "265")] or "Other") end
  elseif cat == "C" then
    local gname = slot_name(it)
    if gname == "Shirt" or gname == "Pants" then
      add("cl", gname)
      local need = gname == "Shirt" and (2 | 8 | 16) or (4 | 64 | 128)
      add("cv", (armor_slots(it) & need) == need and "Full coverage" or "Partial coverage")
    end
  elseif cat == "J" then
    local imb = is_imbued(it)
    if imb then add("ji", "Imbued") elseif it.idd then add("ji", "Not Imbued") end
    local s = slot_name(it)
    if s == "Necklace" or s == "Trinket" or s == "Bracelet" or s == "Ring" then add("js", s) end
  elseif cat == "K" then
    local lv = overlay_level(it)
    add("kl", (lv >= 1 and lv <= 5) and tostring(lv) or "Other")
    add("kp", CLOAK_PROC_TAG[c2] or "Other")
  elseif cat == "V" then
    add("sv", SALVAGE_TAG[material(it)] or "Other")
  elseif cat == "O" then
    add("oc", is_rare(it) and "Rare" or OTHER_TAG[it.oc] or "Other")
  elseif cat == "S" then
    local s = summon_spec(it)
    add("sm", (s == "Naturalist" or s == "Necromancer" or s == "Primalist") and s or "Other")
  elseif cat == "E" then
    local lv = overlay_level(it)
    if lv >= 1 and lv <= 5 then add("al", tostring(lv)) end
    local c = aetheria_color(it); if c ~= "" then add("ac", c) end
    local s = set_short(it); if s ~= "" then add("ag", s) end
    local u = aetheria_surge(it); if u ~= "" then add("au", u) end
  end
  return "|" .. join(t, "|") .. "|"
end
local function spell_names_of(c4)
  -- the comma-separated entries of a Details text
  local out, start = {}, 1
  for i = 1, #c4 + 1 do
    if i > #c4 or sub(c4, i, i) == "," then
      local e = sub(c4, start, i - 1)
      local a, b = 1, #e
      while a <= b and sub(e, a, a) == " " do a = a + 1 end
      out[#out + 1] = sub(e, a, b); start = i + 1
    end
  end
  return out
end

-- Doubles: two or more cantrips of the highest tier.
local function count_word(hay, w)
  local n, i, lw = 0, 1, #w
  while true do
    local found = nil
    for j = i, #hay - lw + 1 do if sub(hay, j, j + lw - 1) == w then found = j break end end
    if not found then return n end
    n = n + 1; i = found + lw
  end
end
local function doubles(cat, c4, combined)
  if cat == "W" then
    local leg, epic = 0, 0
    for _, n in ipairs(spell_names_of(c4)) do
      local l, e = starts(n, "Legendary "), starts(n, "Epic ")
      if l or e then
        local b = lower(sub(n, l and 11 or 6))
        if b == "blood thirst" or b == "defender" or b == "heart seeker" or b == "spirit drinker" then
          if l then leg = leg + 1 else epic = epic + 1 end
        end
      end
    end
    if leg > 0 then return leg >= 2 end
    return epic >= 2
  end
  local l = lower(combined)
  local leg = contains(l, "legendary") and count_word(l, "legendary") or 0
  if leg >= 2 then return true end
  if leg > 0 then return false end
  local epic = contains(l, "epic") and count_word(l, "epic") or 0
  if epic >= 2 then return true end
  if epic > 0 then return false end
  return contains(l, "major") and count_word(l, "major") >= 2
end
-- A row: what the window shows and searches (also what is saved).
local function whole(v) v = tonumber(v); return tostring(v and (math.tointeger(v) or v)) end
local function base_sig(it, rec)
  return it.name .. "|" .. whole(I(it, STACK, tonumber(rec.count) or 1)) .. "|" .. whole(I(it, "131")) .. "|" .. whole(rec.icon) .. "|" ..
    whole(rec.icon_overlay) .. "|" .. whole(rec.icon_underlay)
end
-- An item's properties as saved (Props files), and a record made from them again.
local function props_of(rec)
  return {n = rec.name, o = rec.object_class, c = rec.count, ip = rec.int_properties, fp = rec.float_properties, sp = rec.string_properties,
    sn = rec.spell_names, si = rec.spell_ids, d = rec.identified == true or nil}
end
local function rec_of(p, row)
  return {id = row.i, name = p.n, object_class = p.o, count = p.c, int_properties = type(p.ip) == "table" and p.ip or {},
    float_properties = type(p.fp) == "table" and p.fp or {}, string_properties = type(p.sp) == "table" and p.sp or {},
    spell_names = type(p.sn) == "table" and p.sn or {}, spell_ids = type(p.si) == "table" and p.si or {}, identified = p.d == true,
    icon = row.ic, type = row.ty, icon_overlay = row.ov, icon_underlay = row.un, ui_effects = row.ef, equipped = row.e == 1, container = row.p}
end
local function icon_fields(row, rec)
  row.ic, row.ty, row.ov, row.un, row.ef = tonumber(rec.icon) or 0, tonumber(rec.type) or 0, tonumber(rec.icon_overlay) or 0,
    tonumber(rec.icon_underlay) or 0, tonumber(rec.ui_effects) or 0
  row.e = rec.equipped == true and 1 or nil   -- worn
  row.p = tonumber(rec.container)              -- pack (or the character)
  row.ws = rec.equipped == true and tonumber(rec.equipped_slot) or nil   -- the slot it is worn in
end
local function build_row(rec, it, complete)
  local cat = category(it)
  local row = {i = tonumber(rec.id) or 0, k = cat, s = base_sig(it, rec)}
  icon_fields(row, rec)
  if not complete then
    row.n = with_count(it, it.name); row.a = col1(it); row.b, row.c, row.d = "", "", ""
    row.z = it.name .. " (details unavailable)"; row.x = 1; row.g = tags(it, cat, row.a, "")
    return row
  end
  row.n = with_count(it, full_name(it))
  row.a, row.b, row.c, row.d = col1(it), col2(it), col3(it), col4(it)
  row.g = tags(it, cat, row.a, row.b)
  if is_salvage(it) then
    local w = math.floor(salvage_work(it) * 100 + 0.5); row.w, row.o, row.oa, row.om = w, w, w, w
  else
    row.w = I(it, "105")
    if is_weapon(it) then row.o, row.oa, row.om = weapon_od(it), weapon_attack(it), weapon_melee(it) end
  end
  if doubles(cat, row.d, row.n .. " " .. row.a .. " " .. row.b .. " " .. row.c .. " " .. row.d) then row.q = 1 end
  row.z = description(it)
  return row
end

-- Which items are listed (ItemList.AddAll): not packs, not stackable ammo;
-- an unappraised Misc item only when it is a summon, aetheria or foolproof.
local function listing(it)
  if it.oc == OC.Container then return nil end
  if needs_no_appraisal(it) then return "full" end
  if is_ammo(it) then return nil end
  if it.idd then return "full" end
  if it.oc == OC.Misc and not (is_summon(it) or is_aetheria(it) or is_foolproof(it)) then return nil end
  return "stub"
end

B.build_row, B.listing, B.item_of, B.base_sig, B.icon_fields, B.CAT_ORDER = build_row, listing, item_of, base_sig, icon_fields, CAT_ORDER
B.props_of, B.rec_of = props_of, rec_of
end
local build_row, listing, item_of, base_sig, icon_fields, CAT_ORDER = B.build_row, B.listing, B.item_of, B.base_sig, B.icon_fields, B.CAT_ORDER
local props_of, rec_of = B.props_of, B.rec_of

-- Filters ------------------------------------------------------------------------------
local CATS = {{"W", "Weapons"}, {"A", "Armor"}, {"C", "Clothing"}, {"J", "Jewelry"}, {"K", "Cloaks"}, {"S", "Summons"},
  {"E", "Aetheria"}, {"V", "Salvage"}, {"O", "Others"}}
local function L(g, list) local out = {}; for _, v in ipairs(list) do out[#out + 1] = {g, v[1], v[2] or v[1]} end return out end
local SUBS = {
  W = {L("wt", {{"HW"}, {"FW"}, {"LW"}, {"2H"}, {"Bow"}, {"XBow"}, {"TW"}, {"War"}, {"Void"}, {"Other"}}),
       L("el", {{"Bludge"}, {"Pierce"}, {"Slash"}, {"Lightning"}, {"Acid"}, {"Fire"}, {"Cold"}, {"Nether"}})},
  A = {L("as", {{"Head"}, {"Chest"}, {"Abdomen"}, {"UArm"}, {"LArm"}, {"Hands"}, {"ULeg"}, {"LLeg"}, {"Feet"}}),
       L("st", {{"No Set"}, {"Adept"}, {"Defender"}, {"Dextrous", "Dexterous"}, {"Hearty"}, {"Wise"}, {"Other"}})},
  C = {L("cl", {{"Shirt"}, {"Pants"}}), L("cv", {{"Full coverage"}, {"Partial coverage"}})},
  J = {L("js", {{"Necklace"}, {"Trinket"}, {"Bracelet"}, {"Ring"}}), L("ji", {{"Imbued"}, {"Not Imbued"}})},
  K = {L("kl", {{"1"}, {"2"}, {"3"}, {"4"}, {"5"}, {"Other"}}), L("kp", {{"-200"}, {"CiS"}, {"Melee"}, {"Missile"}, {"Magic"}, {"AoE"}, {"Other"}})},
  V = {L("sv", {{"Iron"}, {"Granite"}, {"Mahogany"}, {"Green Garnet"}, {"Velvet"}, {"Brass"}, {"Steel"}, {"Rends"}, {"Imbues"}, {"Other"}})},
  O = {L("oc", {{"Alchemy"}, {"Component"}, {"Cooking"}, {"Food"}, {"Gem"}, {"HealingKit"}, {"Key"}, {"Lockpick"}, {"ManaStone"}, {"Misc"}, {"Rare"}, {"Other"}})},
  S = {L("sm", {{"Naturalist"}, {"Necromancer"}, {"Primalist"}, {"Other"}})},
  E = {L("al", {{"1"}, {"2"}, {"3"}, {"4"}, {"5"}}), L("ac", {{"Blue"}, {"Yellow"}, {"Red"}}),
       L("ag", {{"Defense"}, {"Destruction"}, {"Fury"}, {"Growth"}, {"Vigor"}}),
       L("au", {{"Affliction"}, {"Destruction", "Destruction Surge"}, {"Festering"}, {"Protection"}, {"Regeneration"}})},
}

-- State ------------------------------------------------------------------------------------
local st                          -- saved per character: {auto_off, flt = {text, cats, subs, order, dbl}, sort}
local dirty_state = false
local me, server, prefix = "", "", ""
local others = {}                 -- character -> {rows = {}, saved, count}
local live = {}                   -- id -> row (this character)
local live_sig = {}               -- id -> base sig .. identified
local pending_build = {}          -- id -> rec
local stored = {}                 -- id -> row saved earlier for this character
local own_props = {}              -- id -> properties of this character's items (saved with the rows)
local needs_props = {}            -- id -> true: a saved row without properties (appraised again once)
local player_id = nil
local inv_changed_at, seen_cont = -1e9, nil   -- last inventory change; packs that have items in the last check
local rebuild = {}                -- {row, props, ch} waiting to be made again in the current format
local resave = {}                 -- character -> true: rows made again, save its files
local shared = {read = false, touched = false, due = nil}   -- the search shared by all characters
local reconciled = nil
local skills, skills_sig = nil, nil     -- the character's skills (snapshot), and its trained ones as text
local skills_at = 0                     -- when they were last read (every 5 s)
local flt_ver = 0                       -- changes with the filter boxes and text (the window shows them)
local shown_result, shown_sig, shown_page = nil, "", 0   -- the result last looked at, and the rows of its page as text
local export = nil                -- {parts}
local export_all                  -- defined with the saving code
local top_row                     -- defined with the window
local SB                          -- the Suit Builder and Character Summary (defined with the window)
local own_loaded = false
local inv_rev, app_rev = nil, nil
local queue, tries = {}, {}       -- ids waiting for an appraisal, tries per id
local asking = nil                -- {id, at}
local asked_at = -1e9
local live_changed_at, saved_at, save_due = nil, -1e9, false
local own_parts = 0
local reqs, rid = {}, 0
local loading = {list = false, waiting = 0}
local view = "search"
local main_view = "search"        -- the page Characters and Settings go back to
local page = 1
local selected = nil              -- {ch, i}
local notes = {search = "", suit = "", sum = "", chars = "", settings = "", all = ""}   -- messages, each shown on its own page ("all": every page)
local data_ver, search_ver = 0, -1
local search = nil                -- running search job
local asked_search = nil          -- when a filter or sort was changed (the window waits for that update's search)
local result = {rows = {}, matches = 0, total = 0}
local ui_key = nil
local prep_ver = -1               -- data version whose rows all have their search text
local now = 0

-- Filters saved with several categories ticked (before 1.2.1): keep the last one ticked.
local function one_category(f)
  local n, last = 0, nil
  for _ in pairs(f.cats) do n = n + 1 end
  if n <= 1 then return end
  for _, k in ipairs(f.order) do if f.cats[k] then last = k end end
  if not last then last = next(f.cats) end
  f.cats, f.order = {[last] = true}, {last}
end
local function request(r) rid = rid + 1; r.id = r.id or ("r" .. rid); reqs[#reqs + 1] = r end
local inflight, last_batch = {}, -1e9   -- requests sent, by id (sent again after a rate-limit result)
local function flt() return st.flt end

-- Searching ------------------------------------------------------------------------------
local function parse_text(text)
  local phrases, terms = {}, {}
  local unq, i = {}, 1
  while i <= #text do
    local c = sub(text, i, i)
    if c == '"' then
      local j = i + 1
      while j <= #text and sub(text, j, j) ~= '"' do j = j + 1 end
      if j > #text then return nil, "Close the quoted search phrase." end
      local ph = lower(sub(text, i + 1, j - 1))
      if ph ~= "" then phrases[#phrases + 1] = ph end
      unq[#unq + 1] = "\0"; i = j + 1
    else unq[#unq + 1] = c; i = i + 1 end
  end
  local q = table.concat(unq)
  -- split on spaces and the phrase boundaries
  local words, cur = {}, {}
  local function flush() if #cur > 0 then words[#words + 1] = lower(table.concat(cur)); cur = {} end end
  for k = 1, #q do
    local c = sub(q, k, k)
    if c == " " or c == "\t" then flush() elseif c == "\0" then flush(); words[#words + 1] = "\0" else cur[#cur + 1] = c end
  end
  flush()
  local k = 1
  while k <= #words do
    local w = words[k]
    if w ~= "\0" then
      local nx = words[k + 1]
      if nx and nx ~= "\0" and (w == "legendary" or w == "epic" or w == "major" or w == "minor") then
        phrases[#phrases + 1] = w .. " " .. nx; k = k + 1
      else
        local star = nil
        for p = #w, 2, -1 do if sub(w, p, p) == "*" then star = p break end end
        local n = star and tonumber(sub(w, star + 1)) or nil
        if star and n and n > 0 and n == math.floor(n) then terms[#terms + 1] = {sub(w, 1, star - 1), n}
        else terms[#terms + 1] = {w, 1} end
      end
    end
    k = k + 1
  end
  return {phrases = phrases, terms = terms}
end
local SPECIAL = {}
for _, c in ipairs({"\\", "^", "$", ".", "|", "?", "*", "+", "(", ")", "[", "]", "{", "}"}) do SPECIAL[c] = true end
local function esc(t)
  local out = {}
  for i = 1, #t do local c = sub(t, i, i); out[#out + 1] = SPECIAL[c] and ("\\" .. c) or c end
  return table.concat(out)
end
-- Lower-case texts, made when first needed: names for sorting, columns for
-- column sorts and phrases, the combined text for words.
local LCH = {}                     -- character -> lower-case name
local function names(r)
  if not r.ln then
    r.ln = lower(r.n)
    local l = LCH[r.ch]; if not l then l = lower(r.ch); LCH[r.ch] = l end
    r.lch = l
  end
  return r
end
local function cols(r) if not r.la then names(r); r.la, r.lb, r.lc, r.ld = lower(r.a), lower(r.b), lower(r.c), lower(r.d) end return r end
-- the searched text: name, Type, Details, Effect, Info and character, lower case
local function low(r) if not r.h then r.h = lower(r.n .. " " .. r.a .. " " .. r.d .. " " .. r.b .. " " .. r.c .. " " .. r.ch) end return r end
-- The active sub-filters, per ticked category: {cat = {group = {tag = true}}}
local function active_subs()
  local f, out = flt(), {}
  for _, c in ipairs(CATS) do
    local k = c[1]
    if f.cats[k] and SUBS[k] then
      for _, grp in ipairs(SUBS[k]) do
        local set = nil
        for _, d in ipairs(grp) do
          local tag = d[1] .. ":" .. d[2]
          if f.subs[tag] then set = set or {}; set[#set + 1] = "|" .. tag .. "|" end
        end
        if set then out[k] = out[k] or {}; out[k][#out[k] + 1] = set end
      end
    end
  end
  return out
end
local function any_cat(f) for _, c in ipairs(CATS) do if f.cats[c[1]] then return true end end return false end
local function matches(r, j)
  if j.anycat and not j.cats[r.k] then return false end
  local sg = j.subs[r.k]
  if sg then
    for _, set in ipairs(sg) do
      local ok = false
      for _, tag in ipairs(set) do if contains(r.g or "", tag) then ok = true break end end
      if not ok then return false end
    end
  end
  if j.dbl and r.q ~= 1 then return false end
  if r.e == 1 and not j.worn then return false end   -- worn items only with Worn ticked
  local q = j.q
  if j.plain then return true end
  local h = r.h or low(r).h
  for _, ph in ipairs(q.phrases) do if not contains(h, ph) then return false end end
  for _, t in ipairs(q.terms) do
    if not contains(r.h, t[1]) then return false end
    if t[2] > 1 and not rx(r.h, "(?:" .. esc(t[1]) .. ".*){" .. t[2] .. "}") then return false end
  end
  return true
end
local function pad(n) return string.format("%09d", math.max(0, math.min(999999999, n))) end
-- Sort keys: group (empty last, category) + text + character and item (so each key is different); runs of a
-- group are reversed for descending. Both directions of a column use the same keys (not the numeric ones).
local KIND = {}
local function kind(sort)
  local k = KIND[sort]
  if not k then
    k = (sort == "cur" or sort == "co-" or sort == "ca-" or sort == "cm-" or sort == "cw-") and sort or sub(sort, 1, -2)
    KIND[sort] = k
  end
  return k
end
-- (kept: the key for the first sort, "cur", and the last other one)
local function sort_key(r, sort)
  local kd = kind(sort)
  if kd == "cur" then if r.skc then return r.skc end
  elseif r.skt == kd then return r.skv end
  if sort == "cur" or sort == "ch+" or sort == "ch-" or sort == "n+" or sort == "n-" then names(r) else cols(r) end
  local grp, key
  if sort == "cur" then grp = (r.ch == me and "0" or "1") .. "0"; key = r.lch .. "\1" .. r.ln
  elseif sort == "ch+" or sort == "ch-" then grp = "00"; key = r.lch .. "\1" .. r.ln
  elseif sort == "n+" or sort == "n-" then grp = "00"; key = r.ln
  elseif sort == "a+" or sort == "a-" then grp = (r.a == "" and "1" or "0") .. "0"; key = r.la .. "\1" .. r.ln
  else
    local col = sub(sort, 1, 1)
    local v = col == "b" and r.lb or col == "c" and r.lc or r.ld
    grp = (v == "" and "1" or "0") .. (CAT_ORDER[r.k] or 9)
    if col == "c" and (sort == "co-" or sort == "ca-" or sort == "cm-" or sort == "cw-") then
      local x = sort == "co-" and r.o or sort == "ca-" and r.oa or sort == "cm-" and r.om or r.w
      key = pad((tonumber(x) or -1000) + 1000) .. "\1" .. v .. "\1" .. r.ln
    else key = v .. "\1" .. r.ln end
  end
  local v = grp .. "\2" .. key .. "\1" .. r.lch .. "\1" .. tostring(r.i)
  if kd == "cur" then r.skc = v else r.skt, r.skv = kd, v end
  return v
end
-- Every row in the order of the current sort, rebuilt in the background when the data or the sort changes.
-- A filter change is then one pass over this order (no sorting), usually in the update that gets the click.
local order = {rows = nil, sort = nil, ver = -1, at = -1e9}
local ojob = nil
local live_list, live_list_ver = {}, -1
local function start_order()
  if live_list_ver ~= data_ver then
    live_list = {}
    for _, r in pairs(live) do live_list[#live_list + 1] = r end
    live_list_ver = data_ver
  end
  -- other characters' saved rows, then this character's
  local src = {}
  for ch, o in pairs(others) do if ch ~= me then src[#src + 1] = o.rows end end
  src[#src + 1] = live_list
  ojob = {src = src, si = 1, i = 1, n = 0, keys = {}, rowof = {}, sort = st.sort or "cur", ver = data_ver,
    desc = sub(st.sort or "cur", -1) == "-"}
end
-- Sort keys, the sort itself,
-- then the rows in order: ascending as sorted; descending: groups (empty last, by category) stay in order,
-- each group reversed. Returns the work used.
local function step_order(budget)
  local j, work = ojob, 0
  local keys, rowof = j.keys, j.rowof
  if not j.out then
    local sort, kd = j.sort, kind(j.sort)
    while j.si <= #j.src do
      if work >= budget or not workavailable() then return work end
      local list = j.src[j.si]
      local stop = math.min(#list, j.i + 199)
      local cur = kd == "cur"
      for k = j.i, stop do
        local r = list[k]
        local key
        if cur then key = r.skc elseif r.skt == kd then key = r.skv end
        if not key then key = sort_key(r, sort); work = work + COST.newkey end
        local n = j.n + 1; j.n = n
        if rowof[key] then key = key .. "\1" .. n end   -- (the same item twice)
        keys[n] = key; rowof[key] = r
      end
      work = work + (stop - j.i + 1) * COST.key
      if stop >= #list then j.si, j.i = j.si + 1, 1 else j.i = stop + 1 end
    end
    table.sort(keys)
    j.out, j.a, j.gs, j.by = {}, 1, 1, {}
  end
  -- (each category's rows are listed in the same order, so a category search only looks at its own rows)
  local out, n, by = j.out, #keys, j.by
  if not j.desc then
    while j.a <= n do
      if work >= budget or not workavailable() then return work end
      local stop = math.min(n, j.a + 499)
      for k = j.a, stop do
        local r = rowof[keys[k]]; out[k] = r
        local c = r.k or ""; local l = by[c]; if not l then l = {}; by[c] = l end; l[#l + 1] = r
      end
      work = work + (stop - j.a + 1) * COST.put; j.a = stop + 1
    end
  else
    while j.gs <= n do
      if work >= budget or not workavailable() then return work end
      if not j.ge then
        -- find where the group starting at gs ends (500 rows at a time)
        local g, p = sub(keys[j.gs], 1, 2), j.p or j.gs
        local from, lim = p, math.min(n, p + 500)
        while p < lim and sub(keys[p + 1], 1, 2) == g do p = p + 1 end
        work = work + (p - from + 1) * COST.scan
        if p < lim or p == n then j.ge, j.c, j.p = p, p, nil else j.p = p end
      else
        local stop = math.max(j.gs, j.c - 499)
        for k = j.c, stop, -1 do
          local r = rowof[keys[k]]; out[#out + 1] = r
          local c = r.k or ""; local l = by[c]; if not l then l = {}; by[c] = l end; l[#l + 1] = r
        end
        work = work + (j.c - stop + 1) * COST.put
        if stop == j.gs then j.gs, j.ge = j.ge + 1, nil else j.c = stop - 1 end
      end
    end
  end
  order = {rows = out, by = by, sort = j.sort, ver = j.ver, at = now}
  ojob = nil
  return work
end
local function start_search(user)
  local f = flt()
  local q, err = parse_text(f.text or "")
  -- one category ticked: only its rows
  local rows, cat, nc = order.rows, nil, 0
  for k in pairs(f.cats) do cat = k; nc = nc + 1 end
  if nc == 1 then rows = order.by[cat] or {} end
  search = {rows = rows, total = #order.rows, ver = order.ver, i = 1, n = 0, hits = {}, q = q, err = err, anycat = any_cat(f), subs = active_subs(),
    dbl = f.dbl, worn = f.worn, cats = f.cats, at = now, user = user, plain = q ~= nil and #q.phrases == 0 and #q.terms == 0}
end
-- One pass over the sorted rows. Returns the work used.
local function step_search(budget)
  local j, work = search, 0
  local rows = j.rows
  if j.err or not j.q then
    result = {rows = {}, matches = 0, total = j.total, err = j.err}; search = nil; search_ver = j.ver
    return 0
  end
  -- the quick checks first, then the text words (plain), then the full check only when needed
  -- (sub-filters, or a word*2)
  local words, full = j.words, j.full
  if not words then
    words, full = {}, false
    if not j.plain then
      for _, ph in ipairs(j.q.phrases) do words[#words + 1] = ph end
      for _, t in ipairs(j.q.terms) do words[#words + 1] = t[1]; if t[2] > 1 then full = true end end
    end
    j.words, j.full = words, full
  end
  local nw = #words
  local hits, anycat, cats, dbl, worn, subs = j.hits, j.anycat, j.cats, j.dbl, j.worn, j.subs
  local nsub = 0
  for _, sets in pairs(subs) do for _, set in ipairs(sets) do nsub = nsub + #set end end
  local per = COST.row + nw * COST.word + nsub * COST.sub + (full and COST.full or 0)
  local step = math.max(20, math.floor(6000 / per))
  while j.i <= #rows do
    if work >= budget or not workavailable() then
      -- a search you started shows the rows found so far
      if j.user and j.n > 0 then result = {rows = hits, matches = j.n, total = j.total, partial = true} end
      return work
    end
    local stop = math.min(#rows, j.i + step - 1)
    for k = j.i, stop do
      local r = rows[k]
      if (worn or r.e ~= 1) and (not dbl or r.q == 1) and (not anycat or cats[r.k]) then
        local ok = true
        local sg = nsub > 0 and subs[r.k]
        if sg then
          -- each sub-filter group: one of its ticked boxes
          local g = r.g or ""
          for a = 1, #sg do
            local set, any = sg[a], false
            for b = 1, #set do if contains(g, set[b]) then any = true break end end
            if not any then ok = false break end
          end
        end
        if ok and nw > 0 then
          local h = r.h
          if not h then h = low(r).h; work = work + COST.text end
          for t = 1, nw do if not contains(h, words[t]) then ok = false break end end
        end
        if ok and full then ok = matches(r, j) end
        if ok then local c = j.n + 1; j.n = c; if c <= RESULT_LIMIT then hits[c] = r end end
      end
    end
    work = work + (stop - j.i + 1) * per
    j.i = stop + 1
  end
  result = {rows = hits, matches = j.n, total = j.total}
  search = nil; search_ver = j.ver
  return work
end

-- Files ----------------------------------------------------------------------------------
local function own_name() return prefix .. safe(me) end
local function row_out(r)
  return {i = r.i, n = r.n, k = r.k, a = r.a, b = r.b, c = r.c, d = r.d, g = r.g, w = r.w, o = r.o, oa = r.oa, om = r.om, q = r.q, x = r.x, z = r.z,
    s = r.s, ic = r.ic, ty = r.ty, ov = r.ov, un = r.un, ef = r.ef, e = r.e, p = r.p}
end
-- One character's rows: Items/<server>_<character>_<part>, PART_ROWS rows each.
local function save_rows(ch, list)
  local parts = math.max(1, math.ceil(#list / PART_ROWS))
  for p = 1, parts do
    local rows = {}
    for k = (p - 1) * PART_ROWS + 1, math.min(#list, p * PART_ROWS) do rows[#rows + 1] = row_out(list[k]) end
    request({id = "sv_" .. p, service = "profiles", operation = "save", group = "Items", name = safe(server) .. "_" .. safe(ch) .. "_" .. p,
      data = {v = 2, f = FORMAT, server = server, character = ch, part = p, rows = rows}})
  end
  return parts
end
-- Saving this character: a few parts per update (a large inventory is too much for one update).
local save_job = nil
local function save_own()
  if save_job then return end
  local ids = {}
  for id in pairs(live) do ids[#ids + 1] = id end
  table.sort(ids)
  save_job = {ids = ids, parts = math.max(1, math.ceil(#ids / PART_ROWS)), pp = math.max(1, math.ceil(#ids / PROP_ROWS)), p = 1, q = 1}
  saved_at, save_due = now, false
end
local function save_step()
  local j = save_job
  local ids, budget = j.ids, 2
  while budget > 0 and j.p <= j.parts do
    local rows = {}
    for k = (j.p - 1) * PART_ROWS + 1, math.min(#ids, j.p * PART_ROWS) do local r = live[ids[k]]; if r then rows[#rows + 1] = row_out(r) end end
    request({id = "sv_" .. j.p, service = "profiles", operation = "save", group = "Items", name = own_name() .. "_" .. j.p,
      data = {v = 2, f = FORMAT, server = server, character = me, part = j.p, rows = rows}})
    j.p, budget = j.p + 1, budget - 1
  end
  while budget > 0 and j.q <= j.pp do
    local items = {}
    for k = (j.q - 1) * PROP_ROWS + 1, math.min(#ids, j.q * PROP_ROWS) do
      local pr = own_props[ids[k]]
      if pr then local x = {i = ids[k]}; for key, v in pairs(pr) do x[key] = v end; items[#items + 1] = x end
    end
    request({id = "sp_" .. j.q, service = "profiles", operation = "save", group = "Props", name = own_name() .. "_" .. j.q,
      data = {v = 2, server = server, character = me, part = j.q, items = items}})
    j.q, budget = j.q + 1, budget - 1
  end
  if j.p > j.parts and j.q > j.pp then
    for p = j.parts + 1, own_parts do request({service = "profiles", operation = "delete", group = "Items", name = own_name() .. "_" .. p}) end
    own_parts = j.parts
    for p = j.pp + 1, (others[me] and others[me].pp or 0) do request({service = "profiles", operation = "delete", group = "Props", name = own_name() .. "_" .. p}) end
    others[me] = others[me] or {rows = {}, saved = 0, count = 0, parts = j.parts}
    others[me].pp = j.pp
    local stubs = 0
    for _, id in ipairs(ids) do local r = live[id]; if r and r.x then stubs = stubs + 1 end end
    request({id = "sv_idx", service = "profiles", operation = "save", group = "Chars", name = own_name(),
      data = {v = 2, server = server, character = me, saved = math.floor(now), count = #ids, parts = j.parts, pp = j.pp, unappraised = stubs}})
    save_job = nil
  end
end
-- Another character's rows after they were made again in the current format.
local function save_other(ch)
  local o = others[ch]
  if not o then return end
  local parts = save_rows(ch, o.rows)
  request({service = "profiles", operation = "save", group = "Chars", name = safe(server) .. "_" .. safe(ch),
    data = {v = 2, server = server, character = ch, saved = o.saved, count = #o.rows, parts = parts, pp = o.pp or 0, unappraised = o.unap or 0}})
  o.parts = parts
end
local function load_all()
  others, loading = {}, {list = true, waiting = 1}
  request({id = "ls", service = "profiles", operation = "list", group = "Chars"})
  if not shared.read then request({id = "ss", service = "profiles", operation = "read", group = "Settings", name = "Search"}) end
end

-- Import: Virindi Global Inventory databases, converted by VGI_Import.html to Library/Import/<server>_VGI_<n>.json:
-- {index = {server, saved, parts = {{key, character, count}}}, p1 = {character, items}, ...}. Each part is read
-- on its own (a read returns at most 256 KiB). Characters already saved are skipped. Rows are built with the
-- same code as appraised items, a few per update, then each character is saved like any other.
local IMPORT_PER_TICK = 30
local IMPORT_SHARED = 8           -- in updates that also build this character's rows
local IM = (function()
  local M = {}
  local job = nil   -- {files, f, parts, k, todo, ti, chars, order, skipped, saved}
  function M.busy() return job ~= nil end
  function M.start()
    if job then return end
    if loading.list or loading.waiting > 0 then notes.chars = "Wait until the saved characters are read"; return end
    job = {files = {}, f = 0, parts = {}, k = 0, chars = {}, order = {}, skipped = {}}
    request({id = "im_ls", service = "profiles", operation = "list", group = "Import"})
    notes.chars = "Reading Library\\Import..."
  end
  local function next_read()
    -- the next part (parts of characters already saved aren't read), else the next file's index
    while job.parts[job.k + 1] do
      job.k = job.k + 1
      local p = job.parts[job.k]
      local ch = p.character
      if ch == me or (others[ch] and not job.chars[ch]) then job.skipped[ch] = true
      else request({id = "im_p|" .. job.k, service = "profiles", operation = "read", group = "Import", name = p.file, field = p.key}); return end
    end
    job.f = job.f + 1
    local name = job.files[job.f]
    if name then request({id = "im_ix", service = "profiles", operation = "read", group = "Import", name = name, field = "index"}); return end
    -- done: each character is saved in its own update (see M.step)
    job.saving = {}
    for _, ch in ipairs(job.order) do if #job.chars[ch].rows > 0 and not others[ch] then job.saving[#job.saving + 1] = ch end end
  end
  -- One character's files, two per update (rows, then properties), then its index.
  local function save_char()
    local sv = job.sv
    local c, ch, budget = sv.c, sv.ch, 2
    while budget > 0 and sv.p <= sv.parts do
      local rows = {}
      for k = (sv.p - 1) * PART_ROWS + 1, math.min(#c.rows, sv.p * PART_ROWS) do rows[#rows + 1] = row_out(c.rows[k]) end
      request({service = "profiles", operation = "save", group = "Items", name = safe(server) .. "_" .. safe(ch) .. "_" .. sv.p,
        data = {v = 2, f = FORMAT, server = server, character = ch, part = sv.p, rows = rows}})
      sv.p, budget = sv.p + 1, budget - 1
    end
    while budget > 0 and sv.q <= sv.pp do
      local list = {}
      for k = (sv.q - 1) * PROP_ROWS + 1, math.min(#c.props, sv.q * PROP_ROWS) do list[#list + 1] = c.props[k] end
      request({service = "profiles", operation = "save", group = "Props", name = safe(server) .. "_" .. safe(ch) .. "_" .. sv.q,
        data = {v = 2, server = server, character = ch, part = sv.q, items = list}})
      sv.q, budget = sv.q + 1, budget - 1
    end
    if sv.p > sv.parts and sv.q > sv.pp then
      request({service = "profiles", operation = "save", group = "Chars", name = safe(server) .. "_" .. safe(ch),
        data = {v = 2, server = server, character = ch, saved = c.saved, count = #c.rows, parts = sv.parts, pp = sv.pp, unappraised = 0}})
      others[ch] = {rows = c.rows, saved = c.saved, count = #c.rows, parts = sv.parts, pp = sv.pp, unap = 0, left = 0}
      SB.cache(ch, c.props)
      job.done, job.items = (job.done or 0) + 1, (job.items or 0) + #c.rows
      job.chars[ch], job.sv = nil, nil
      data_ver = data_ver + 1
    end
  end
  local function finish()
    local sk = {}
    for ch in pairs(job.skipped) do sk[#sk + 1] = ch end
    table.sort(sk)
    local n = job.done or 0
    if #job.files == 0 then notes.chars = "No files for " .. server .. " in Library\\Import"
    else
      notes.chars = "Imported " .. n .. (n == 1 and " character (" or " characters (") .. commas(job.items or 0) .. " items)"
      if #sk > 0 then notes.chars = notes.chars .. ". Already saved: " .. join(sk, ", ") end
      if job.failed then notes.chars = notes.chars .. ". Parts not read: " .. job.failed end
    end
    job = nil
  end
  function M.result(e, id)
    if id ~= "im_ls" and id ~= "im_ix" and sub(id, 1, 5) ~= "im_p|" then return false end
    if not job then return true end
    local d = e.ok and type(e.data) == "table" and e.data or nil
    if id == "im_ls" then
      for _, name in ipairs(type(e.names) == "table" and e.names or {}) do
        if type(name) == "string" and starts(name, prefix .. "VGI_") then job.files[#job.files + 1] = name end
      end
      table.sort(job.files)
    elseif id == "im_ix" then
      if d and type(d.parts) == "table" then
        for _, p in ipairs(d.parts) do
          if type(p) == "table" and type(p.key) == "string" and type(p.character) == "string" then
            job.parts[#job.parts + 1] = {file = job.files[job.f], key = p.key, character = p.character, saved = tonumber(d.saved) or now}
          end
        end
      end
    else
      local p = job.parts[job.k]
      local ch = p and p.character
      if not (d and type(d.items) == "table") then job.failed = (job.failed or 0) + 1
      elseif ch then
        if not job.chars[ch] then job.chars[ch] = {rows = {}, props = {}, saved = p.saved}; job.order[#job.order + 1] = ch end
        job.todo, job.ti, job.cur = d.items, 1, ch
        return true
      end
    end
    next_read()
    return true
  end
  -- Rows for the part read last, a few per update.
  function M.step(max)
    if not job then return end
    if job.saving then
      -- a character at a time, two files a update (the saves wait while many requests are queued)
      if not job.sv then
        local ch = table.remove(job.saving, 1)
        if not ch then finish(); return end
        local c = job.chars[ch]
        job.sv = {ch = ch, c = c, p = 1, q = 1, parts = math.max(1, math.ceil(#c.rows / PART_ROWS)), pp = math.ceil(#c.props / PROP_ROWS)}
      end
      if #reqs < 8 then notes.chars = "Saving " .. job.sv.ch; save_char() end
      return
    end
    if not job.todo then return end
    local c, list, n = job.chars[job.cur], job.todo, 0
    while job.ti <= #list and n < max do
      local x = list[job.ti]; job.ti = job.ti + 1
      local xid = type(x) == "table" and tonumber(x.i) or nil
      if xid and type(x.n) == "string" then
        x.d = true
        local rec = rec_of(x, {i = xid, ic = x.ic, ty = x.ty, ov = x.ov, un = x.un, ef = x.ef, e = x.e, p = x.p})
        local it = item_of(rec)
        if listing(it) then
          local row = build_row(rec, it, true)
          row.ch = job.cur
          c.rows[#c.rows + 1] = row
          local pr = props_of(rec); pr.i = xid
          c.props[#c.props + 1] = pr
          n = n + #it.names / 3
        end
      end
      n = n + 1
    end
    notes.chars = "Importing " .. job.cur .. ": " .. commas(#c.rows) .. " items"
    if job.ti > #list then job.todo = nil; next_read() end
  end
  return M
end)()

-- Collecting (this character) ----------------------------------------------------------------
local skip = {}                   -- id -> quick sig of an item that isn't listed
local coll = nil                  -- inventory check in progress: {inv, i, seen}
local coll_next = nil             -- the newest inventory, checked when the current check ends
local build_turn = false          -- building and checking take turns
local COLLECT_PER_TICK = 300
local function collect_step()
  local c = coll
  local stop = math.min(#c.inv, c.i + COLLECT_PER_TICK - 1)
  while c.i <= stop do
    local rec = c.inv[c.i]; c.i = c.i + 1
    local id = type(rec) == "table" and tonumber(rec.id) or nil
    if id then
      -- quick check on the record's own fields; the item is only looked at when they changed
      -- (the client drops worn items' appraisals after some actions and appraises them again: an item whose
      -- row is complete counts as appraised, so it isn't built again)
      local idd = rec.identified == true
      if not idd then local lr = live[id]; if lr and not lr.x and live_sig[id] then idd = true end end
      local q = tostring(rec.name) .. "|" .. tostring(rec.count) .. "|" .. tostring(idd) .. "|" .. tostring(rec.icon) .. "|" ..
        tostring(rec.icon_overlay) .. "|" .. tostring(rec.icon_underlay) .. "|" .. tostring(rec.material) .. "|" .. tostring(rec.equipped)
      if live_sig[id] == q or (pending_build[id] and pending_build[id].sig == q) then c.seen[id] = true
      elseif skip[id] ~= q then
        local it = item_of(rec)
        local how = listing(it)
        if how then c.seen[id] = true; pending_build[id] = {rec = rec, it = it, how = how, sig = q}
        else skip[id] = q end
      end
      local pc = tonumber(rec.container)
      if pc and c.seen[id] then c.cont[pc] = true end
    end
  end
  if c.i > #c.inv then
    -- an item seen this session that is gone now has left the inventory; saved items that haven't
    -- appeared yet are kept (see reconcile)
    for id in pairs(live) do
      if not c.seen[id] and live_sig[id] then
        live[id], live_sig[id], own_props[id], needs_props[id] = nil, nil, nil, nil
        data_ver = data_ver + 1; live_changed_at = now; save_due = true
      end
    end
    seen_cont = c.cont
    for id in pairs(pending_build) do if not c.seen[id] then pending_build[id] = nil end end
    coll = nil
  end
end
-- Rows that show and save the same (the client sends some items again without a change)
local SAME_FIELDS = {"n", "k", "a", "b", "c", "d", "g", "w", "o", "oa", "om", "q", "x", "z", "s", "ic", "ty", "ov", "un", "ef", "e", "p", "ws"}
local function same_row(a, b)
  for _, f in ipairs(SAME_FIELDS) do if a[f] ~= b[f] then return false end end
  return true
end
local function build_some()
  local n = 0
  for id, p in pairs(pending_build) do
    if n >= BUILD_PER_TICK then break end
    pending_build[id] = nil
    local it, rec, row = p.it, p.rec, nil
    local old = stored[id]
    if p.how == "full" or it.idd then
      row = build_row(rec, it, true); n = n + 1 + #it.names / 3   -- spells make a row slower to build
      own_props[id], needs_props[id] = props_of(rec), nil
    elseif old and not old.x and old.s == base_sig(it, rec) then
      row = old; icon_fields(row, rec); n = n + 0.2   -- saved earlier: cheap
      if not own_props[id] then needs_props[id] = true end   -- saved before 1.1: appraised once more for its properties
      if needs_props[id] and (tries[id] or 0) < ID_TRIES then
        local q = false
        for _, x in ipairs(queue) do if x == id then q = true break end end
        if not q then queue[#queue + 1] = id end
      end
    else
      own_props[id] = props_of(rec)
      row = build_row(rec, it, false); n = n + 1
      if (tries[id] or 0) < ID_TRIES then
        local q = false
        for _, x in ipairs(queue) do if x == id then q = true break end end
        if not q then queue[#queue + 1] = id end
      end
    end
    row.ch = me
    live_sig[id] = p.sig
    local cur = live[id]
    if not (cur and (cur == row or same_row(cur, row))) then
      live[id] = row
      data_ver = data_ver + 1; live_changed_at = now; save_due = true
    end
  end
end
local function next_appraisal()
  if st.auto_off or not own_loaded or now - asked_at < 1 then return nil end
  if asking and now - asking.at < ID_TIMEOUT and live[asking.id] and live[asking.id].x then return nil end
  asking = nil
  -- worn items first (Suit Builder)
  for k, qid in ipairs(queue) do if live[qid] and live[qid].e == 1 then table.remove(queue, k); table.insert(queue, 1, qid) break end end
  while #queue > 0 do
    local id = table.remove(queue, 1)
    local r = live[id]
    if r and (r.x or needs_props[id]) and live_sig[id] and (tries[id] or 0) < ID_TRIES then
      tries[id] = (tries[id] or 0) + 1
      asking, asked_at = {id = id, at = now}, now
      return id
    end
  end
  return nil
end

-- Window -----------------------------------------------------------------------------------
local unap_key, unap_n = nil, 0
local function unappraised()
  local key = data_ver .. ":" .. asked_at
  if key == unap_key then return unap_n end
  local n = 0
  for id, r in pairs(live) do if live_sig[id] and (r.x or needs_props[id]) and (tries[id] or 0) < ID_TRIES then n = n + 1 end end
  unap_key, unap_n = key, n
  return n
end
local shown_u, shown_u_at = 0, -1e9
local slow_ver, slow_at = -1, -1e9
local function status_text()
  if result.err then return result.err end
  local s = "Showing " .. commas(#result.rows) .. " of " .. commas(result.matches) .. " matches (" .. commas(result.total) .. " items)"
  if result.matches > RESULT_LIMIT then s = s .. " - narrow your filters" end
  -- the count of items left to appraise changes about once a second: shown every 5 s (at once when it starts or ends)
  local u = unappraised()
  if u ~= shown_u and (u == 0 or shown_u == 0 or now - shown_u_at >= 5) then shown_u, shown_u_at = u, now end
  u = shown_u
  if u > 0 then s = s .. (st.auto_off and (" - " .. u .. " not appraised") or (" - appraising " .. u)) end
  if loading.list or loading.waiting > 0 then s = s .. " - reading saved characters..." end
  if search_ver == -1 then s = "Searching..." end   -- a search you started that takes more than one update
  return s
end
local W = {icon = 24, ch = 150, n = 300, a = 150, b = 200, c = 140}
local function header(id, text, width)
  return {id = id, type = "text", size = SIZE, text = text, width = width, wrap = false, padding = 0, clickable = true, tooltip = "Sort"}
end
-- The top of the window: the pages, Characters and Settings; under them the status (left) and this page's
-- message (right, yellow).
local PAGES = {{"search", "v_search", "Global Inventory"}, {"suit", "v_suit", "Suit Builder"}, {"sum", "v_sum", "Character Summary"}}
local TOP_W = 165                 -- every top button the same width
local function page_note()
  local a, b = notes[view] or "", notes.all or ""
  if a ~= "" and b ~= "" then return a .. " - " .. b end
  return a ~= "" and a or b
end
function top_row(text, cur)
  local c = {}
  for _, p in ipairs(PAGES) do
    c[#c + 1] = {id = p[2], type = "button", size = SIZE, text = p[3], width = TOP_W, hide_when_pinned = true,
      color = p[1] == cur and "yellow" or nil, bold = p[1] == cur or nil}
  end
  c[#c + 1] = {id = "v_chars", type = "button", size = SIZE, text = "Characters", width = TOP_W, hide_when_pinned = true,
    color = cur == "chars" and "yellow" or nil, bold = cur == "chars" or nil}
  c[#c + 1] = {id = "v_set", type = "button", size = SIZE, text = "Settings", width = TOP_W, hide_when_pinned = true,
    color = cur == "settings" and "yellow" or nil, bold = cur == "settings" or nil}
  local n = page_note()
  local line = {{id = "status", type = "text", size = SIZE, text = text, wrap = false, auto_width = true}}
  if n ~= "" then line[2] = {id = "note", type = "text", size = SIZE, text = n, color = "yellow", wrap = false, align = "right"} end
  -- two rows; the window puts them first (no column around them, so rows below line up with the buttons)
  return {id = "top", type = "column", children = {{id = "top_b", type = "row", children = c}, {id = "top_s", type = "row", children = line}}}
end
-- (the message is part of the top now)
local function note_row() return nil end
local function build_search()
  local f, ui = flt(), {}
  local pin = true
  ui[#ui + 1] = top_row(status_text(), "search")
  ui[#ui + 1] = note_row()
  -- lined up with the top buttons: Filter under the first two, Reset to Add to suit under the next two, the slot under Settings
  local add_b, add_s = SB.add_controls()
  add_b.padding = 0; add_s.padding = 1
  ui[#ui + 1] = {id = "frow", type = "row", children = {
    {id = "f_text", type = "input", size = SIZE, placeholder = "Filter", value = f.text or "", live = true, width = 2 * TOP_W + 10,
      tooltip = "Words must all appear. \"Quoted phrase\". word*2: at least twice."},
    {id = "f_mid", type = "row", padding = 0, width = 2 * TOP_W + 15, children = {
      {id = "f_reset", type = "button", size = SIZE, text = "Reset", auto_width = true, padding = 0},
      {id = "x_json", type = "button", size = SIZE, text = "Export JSON", auto_width = true,
        tooltip = "Writes the items listed below to Profiles\\global_inventory\\Library\\Export"},
      {id = "f_gap", type = "text", size = SIZE, text = ""},
      add_b}},
    add_s}}
  local cats = {}
  for _, c in ipairs(CATS) do cats[#cats + 1] = {id = "cat|" .. c[1], type = "checkbox", size = SIZE, text = c[2], value = f.cats[c[1]] == true, auto_width = true} end
  cats[#cats + 1] = {id = "f_dbl", type = "checkbox", size = SIZE, text = "Doubles", value = f.dbl == true, auto_width = true,
    tooltip = "Two or more cantrips of the highest tier"}
  cats[#cats + 1] = {id = "f_worn", type = "checkbox", size = SIZE, text = "Worn", value = f.worn == true, auto_width = true}
  ui[#ui + 1] = {id = "crow", type = "row", children = cats}
  -- sub-filters of the last ticked category
  local active = nil
  for k = #f.order, 1, -1 do if f.cats[f.order[k]] then active = f.order[k] break end end
  if active and SUBS[active] then
    local subs = {}
    for _, grp in ipairs(SUBS[active]) do
      for _, d in ipairs(grp) do
        local tag = d[1] .. ":" .. d[2]
        subs[#subs + 1] = {id = "sub|" .. tag, type = "checkbox", size = SIZE, text = d[3], value = f.subs[tag] == true, auto_width = true}
      end
    end
    ui[#ui + 1] = {id = "srow|" .. active, type = "row", children = subs}
  end
  ui[#ui + 1] = {id = "hdr", type = "row", padding = 0, children = {
    {id = "h_icon", type = "text", size = SIZE, text = "", width = W.icon, padding = 0},
    header("h|ch", "Character", W.ch), header("h|n", "Item Name", W.n), header("h|a", "Type", W.a),
    header("h|b", "Effect", W.b), header("h|c", "Info", W.c),
    {id = "h|d", type = "text", size = SIZE, text = "Details", wrap = false, padding = 0, clickable = true, tooltip = "Sort"}}}
  local rows = result.rows
  local pages = math.max(1, math.ceil(#rows / PAGE_ROWS))
  if page > pages then page = pages end
  for k = (page - 1) * PAGE_ROWS + 1, math.min(#rows, page * PAGE_ROWS) do
    local r = rows[k]
    local sel = selected and selected.ch == r.ch and selected.i == r.i
    local color = sel and SEL_COLOR or (r.x and STUB_COLOR or nil)
    local own = r.ch == me
    local function cell(id, text, width)
      return {id = id, type = "text", size = SIZE, text = text, width = width, wrap = false, padding = 0, color = color, tooltip = text ~= "" and text or nil}
    end
    local row = {id = "r|" .. k, type = "row", clickable = true, padding = 0, children = {
      {id = "ri|" .. k, type = "item_icon", size = 24, icon = r.ic, item_type = r.ty, overlay = r.ov, underlay = r.un, effects = r.ef, width = W.icon, padding = 0,
        tooltip = r.z},
      cell("rc|" .. k, r.ch .. (r.e and " (worn)" or ""), W.ch), cell("rn|" .. k, r.n, W.n), cell("ra|" .. k, r.a, W.a), cell("rb|" .. k, r.b, W.b),
      cell("rx|" .. k, r.c, W.c), cell("rd|" .. k, r.d .. (SB.flag(r.i) and ((r.d ~= "" and ", " or "") .. SB.flag(r.i)) or ""))}}
    if own then row.action, row.target = "select", r.i end
    if k % 2 == 0 then   -- a faint shade behind every other row
      row = {id = "ro|" .. k, type = "overlay", padding = 0, children = {{id = "rf|" .. k, type = "frame", color = SHADE, padding = 0}, row}}
    end
    ui[#ui + 1] = row
  end
  if pages > 1 then
    ui[#ui + 1] = {id = "pg", type = "row", compact = true, children = {
      {id = "pg_prev", type = "button", size = SMALL, text = "<", auto_width = true, enabled = page > 1},
      {id = "pg_n", type = "text", size = SMALL, text = page .. " / " .. pages, wrap = false},
      {id = "pg_next", type = "button", size = SMALL, text = ">", auto_width = true, enabled = page < pages}}}
  end
  return ui
end
local function age(t)
  local d = math.max(0, now - (t or 0))
  if d < 120 then return "now" end
  if d < 7200 then return math.floor(d / 60) .. " min ago" end
  if d < 172800 then return math.floor(d / 3600) .. " h ago" end
  return math.floor(d / 86400) .. " days ago"
end
-- Cantrips (Oracle of Dereth Resources/cantrips.csv): name, skill id (0: attribute or other;
-- negative: sets and item auras), spell ids for Minor, Moderate, Major, Epic, Legendary.
local CANTRIPS = {
  {"Strength", 0, {2583, 2663, 2576, 3965, 6107}},
  {"Endurance", 0, {2580, 2660, 2573, 4226, 6104}},
  {"Coordination", 0, {2579, 2659, 2572, 3963, 6103}},
  {"Quickness", 0, {2582, 2662, 2575, 4019, 6106}},
  {"Focus", 0, {2581, 2661, 2574, 3964, 6105}},
  {"Willpower", 0, {2584, 2664, 2577, 4227, 6101}},
  {"Armor", 0, {2578, 0, 2571, 4911, 6102}},
  {"Bludgeoning Ward", 0, {2617, 0, 2610, 4674, 6081}},
  {"Piercing Ward", 0, {2620, 0, 2613, 4677, 6084}},
  {"Slashing Ward", 0, {2621, 0, 2614, 4678, 6085}},
  {"Acid Ward", 0, {2616, 0, 2609, 4673, 6080}},
  {"Flame Ward", 0, {2618, 0, 2611, 4675, 6082}},
  {"Frost Ward", 0, {2619, 0, 2612, 4676, 6083}},
  {"Storm Ward", 0, {2622, 0, 2615, 4679, 6079}},
  {"Finesse Weapons", 46, {2544, 2689, 2509, 4691, 6047}},
  {"Heavy Weapons", 44, {2566, 2694, 2531, 4712, 6072}},
  {"Light Weapons", 45, {2539, 2686, 2504, 4686, 6043}},
  {"Two Handed Combat", 41, {5072, 5074, 5070, 5034, 6073}},
  {"Missile Weapons", 47, {2540, 2687, 2505, 4687, 6044}},
  {"Void Magic", 43, {5427, 5430, 5428, 5429, 6074}},
  {"War Magic", 34, {2569, 2812, 2534, 4715, 6075}},
  {"Summoning Prowess", 54, {6127, 6128, 6126, 6124, 6125}},
  {"Magic Defense (Resistance)", 15, {2559, 2811, 2524, 4704, 6063}},
  {"Melee Defense (Invulnerability)", 6, {2550, 2938, 2515, 4696, 6055}},
  {"Missile Defense (Impregnability)", 7, {2549, 2937, 2514, 4695, 6054}},
  {"Armor Tinkering", 29, {2538, 0, 2503, 4685, 6042}},
  {"Item Tinkering", 18, {5071, 5073, 5069, 5033, 6057}},
  {"Magic Item Tinkering", 30, {2558, 0, 2523, 4703, 6062}},
  {"Weapon Tinkering", 28, {2570, 0, 2535, 4912, 6039}},
  {"Alchemy", 38, {2536, 0, 2501, 4683, 6040}},
  {"Arcane Lore", 14, {2537, 2809, 2502, 4684, 6041}},
  {"Assess Creature", 27, {2561, 0, 2526, 4706, 6065}},
  {"Assess Person", 19, {2562, 0, 2527, 4707, 6066}},
  {"Cooking", 39, {2541, 0, 2506, 4688, 6045}},
  {"Creature Enchantment", 31, {2542, 2946, 2507, 4689, 6046}},
  {"Deception", 20, {2545, 0, 2510, 4020, 6048}},
  {"Dirty Fighting", 52, {5883, 5898, 5888, 5893, 6049}},
  {"Dual Wield", 49, {5884, 5899, 5889, 5894, 6050}},
  {"Fletching", 37, {2547, 0, 2512, 4693, 6052}},
  {"Healing", 21, {2548, 0, 2513, 4694, 6053}},
  {"Item Enchantment", 32, {2551, 2975, 2516, 4697, 6056}},
  {"Jumping", 22, {2553, 0, 2518, 4699, 6058}},
  {"Leadership", 35, {2554, 0, 2519, 4232, 6059}},
  {"Life Magic", 33, {2555, 2810, 2520, 4700, 6060}},
  {"Lockpick", 23, {2556, 0, 2521, 4701, 6061}},
  {"Loyalty", 36, {2546, 0, 2511, 4692, 6051}},
  {"Mana Conversion", 16, {2560, 2691, 2525, 4705, 6064}},
  {"Recklessness", 50, {5885, 5900, 5890, 5895, 6067}},
  {"Run (Sprint)", 24, {2564, 0, 2529, 4710, 6071}},
  {"Salvaging", 40, {3833, 0, 3834, 4708, 6068}},
  {"Shield", 48, {5886, 5901, 5891, 5896, 6069}},
  {"Sneak Attack", 51, {5887, 5902, 5892, 5897, 6070}},
  {"Essence", -3, {1997, 2667, 2969, 2665, 2666}},
  {"Warrior's Vitality", -4, {0, 2003, 2004, 2005, 2006}},
  {"Acid Proof Set", -1, {0, 4760, 4761, 4762, 4763}},
  {"Adept's Set", -1, {0, 4824, 4825, 4826, 4827}},
  {"Archer's Set", -1, {0, 4800, 4801, 4802, 4803}},
  {"Cold Proof Set", -1, {0, 4772, 4773, 4774, 4775}},
  {"Crafter's Set", -1, {0, 4788, 4789, 4790, 4791}},
  {"Dedication Set", -2, {4900, 4901, 4902, 4903, 4904}},
  {"Defender's Set", -1, {0, 4862, 4863, 4864, 4865}},
  {"Dexterous Set", -1, {0, 4730, 4731, 4732, 4733}},
  {"Flame Proof Set", -1, {0, 4768, 4769, 4770, 4771}},
  {"Hardened Set", -1, {0, 4784, 4785, 4786, 4787}},
  {"Hearty Set", -1, {0, 4746, 4747, 4748, 4749}},
  {"Interlocking Set", -1, {0, 4780, 4781, 4782, 4783}},
  {"Lightning Proof Set", -1, {0, 4776, 4777, 4778, 4779}},
  {"Reinforced Set", -1, {0, 4764, 4765, 4766, 4767}},
  {"Soldier's Set", -1, {0, 4880, 4881, 4882, 4883}},
  {"Swift Set", -1, {0, 4832, 4833, 4834, 4835}},
  {"Tinker's Set", -1, {0, 4792, 4793, 4794, 4795}},
  {"Wise Set", -1, {0, 4750, 4751, 4752, 4753}},
  {"Health Gain", 0, {2626, 0, 2623, 4680, 6077}},
  {"Stamina Gain", 0, {2628, 0, 2625, 4682, 6076}},
  {"Mana Gain", 0, {2627, 0, 2624, 4681, 6078}},
}

-- Suit Builder and Character Summary ----------------------------------------------------------
-- In a function of its own (its own set of local names); the window, the events and the callback use SB.
SB = (function()
local M = {}

-- Suit Builder: 17 slots on one page: 9 armor, 2 clothes, 6 jewelry (worn slot masks). Cloak, aetheria,
-- weapon and shield are kept with the suit and only added to the totals when their box is ticked.
-- Laid out in columns (one control per cell) to fit the 256-control limit.
local SUIT_SLOTS = {{"Head", 0x1}, {"Chest", 0x200}, {"Abdomen", 0x400}, {"Upper Arms", 0x800}, {"Lower Arms", 0x1000},
  {"Hands", 0x20}, {"Upper Legs", 0x2000}, {"Lower Legs", 0x4000}, {"Feet", 0x100}, {"Shirt", 0x1A}, {"Pants", 0xC4},
  {"Necklace", 0x8000}, {"Trinket", 0x4000000}, {"Left Bracelet", 0x10000}, {"Right Bracelet", 0x20000},
  {"Left Ring", 0x40000}, {"Right Ring", 0x80000}}
local ARMOR_N = 9
local AUX_CLOAK = 0x78000000      -- cloak and the three aetheria slots
local AUX_WEAPON = 0x3700000      -- melee, missile, two-handed, held, shield
local CH, AB, UA, LA, UL, LL, FT = 0x200, 0x400, 0x800, 0x1000, 0x2000, 0x4000, 0x100
-- heading, property, tooltip, totaled
local SUIT_COLS = {{"D", "370", "Damage", true}, {"DR", "371", "Damage Reduction", true}, {"CD", "374", "Critical Damage", true},
  {"CDR", "375", "Critical Damage Reduction", true}, {"V", "379", "Vitality", true}, {"HB", "376", "Healing Bonus", true},
  {"MD", nil, "Magic Defense", true}, {"Work", "105", "Workmanship", false}, {"Tinks", "171", "Tinkers", false}}
-- No Set, then the loot armor sets (13-30) by name
local SETS = {{0, "No Set"}}
do
  local l = {}
  for id = 13, 30 do l[#l + 1] = {id, SET_SHORT[id]} end
  table.sort(l, function(p, q) return p[2] < q[2] end)
  for _, x in ipairs(l) do SETS[#SETS + 1] = x end
end
local SW = {icon = 44, num = 46, h = 26}
-- Best Fill time limit (Settings): how long the combinations are checked before the best suit found is kept
local BEST_LIMITS = {{"30 s", 30}, {"1 min", 60}, {"2 min", 120}, {"5 min", 300}}
local function best_choice()
  local v = st and st.best_limit
  for _, b in ipairs(BEST_LIMITS) do if b[1] == v then return b end end
  return BEST_LIMITS[1]
end
local function best_limit() return best_choice()[2] end
local function best_label() return best_choice()[1] end

local CANTRIP_OF = {}             -- spell id -> {row of CANTRIPS, tier 1-5} (attributes, wards, skills, gains)
local SUMMARY_OF = {}             -- the same for every row, essence, warrior's vitality and sets included
for _, c in ipairs(CANTRIPS) do
  for t, sid in ipairs(c[3]) do if sid > 0 then SUMMARY_OF[sid] = {c, t}; if c[2] >= 0 then CANTRIP_OF[sid] = {c, t} end end end
end
-- Missing cantrips, in this order (the default of Settings: Cantrip priority). A position keeps the weight of
-- its group (the first 8 places count most, then the next 6, 12, 3, 4, 2, 1 and the rest).
local PRIO_GROUPS = {
  {"Bludgeoning Ward", "Piercing Ward", "Slashing Ward", "Acid Ward", "Flame Ward", "Frost Ward", "Storm Ward", "Armor"},
  {"Strength", "Endurance", "Coordination", "Quickness", "Focus", "Willpower"},
  {"Finesse Weapons", "Heavy Weapons", "Light Weapons", "Two Handed Combat", "Missile Weapons", "War Magic", "Void Magic",
    "Melee Defense (Invulnerability)", "Magic Defense (Resistance)", "Sneak Attack", "Recklessness", "Dirty Fighting"},
  {"Dual Wield", "Item Enchantment", "Life Magic"},
  {"Creature Enchantment", "Mana Conversion", "Missile Defense (Impregnability)", "Summoning Prowess"},
  {"Run (Sprint)", "Jumping"},
  {"Shield"},
  {"Arcane Lore", "Alchemy", "Assess Creature", "Assess Person", "Cooking", "Deception", "Fletching", "Healing", "Lockpick",
    "Armor Tinkering", "Item Tinkering", "Magic Item Tinkering", "Weapon Tinkering", "Salvaging", "Loyalty", "Leadership"}}
-- disabled at first (a disabled cantrip isn't missing and isn't filled)
local OFF_DEFAULT = {"Armor Tinkering", "Item Tinkering", "Magic Item Tinkering", "Weapon Tinkering", "Salvaging", "Loyalty", "Leadership"}
local PRIO_DEFAULT, BAND, IN_PRIO, WARD = {}, {}, {}, {}
for g, list in ipairs(PRIO_GROUPS) do
  for _, n in ipairs(list) do PRIO_DEFAULT[#PRIO_DEFAULT + 1] = n; BAND[#PRIO_DEFAULT] = g; IN_PRIO[n] = true; if g == 1 then WARD[n] = true end end
end
local PRIO = {}
-- the saved order: known names once each, any missing ones after them in the default order
local function prio_list()
  local out, seen = {}, {}
  local saved = st and type(st.prio) == "table" and st.prio or {}
  for _, n in ipairs(saved) do if type(n) == "string" and IN_PRIO[n] and not seen[n] then seen[n] = true; out[#out + 1] = n end end
  for _, n in ipairs(PRIO_DEFAULT) do if not seen[n] then out[#out + 1] = n end end
  return out
end
-- the disabled ones: saved once changed, otherwise OFF_DEFAULT
local function prio_off()
  local out = {}
  local list = st and type(st.prio_off) == "table" and st.prio_off or OFF_DEFAULT
  for _, n in ipairs(list) do if type(n) == "string" and IN_PRIO[n] then out[n] = true end end
  return out
end
local function apply_prio()
  local p, off = {}, prio_off()
  for k, n in ipairs(prio_list()) do if not off[n] then p[n] = BAND[k] * 100 + k end end
  PRIO = p
end
apply_prio()
local function weight(c) return 1 << (8 - PRIO[c[1]] // 100) end   -- a higher group counts more

local function toint(v) return math.tointeger(tonumber(v) or 0) or 0 end
local function num(v) v = tonumber(v) or 0; return math.tointeger(v) or v end

-- Item properties for the suit: a few properties, cantrips and rating spells -------------------------
local SK = {"218103822", "265", "105", "171", "370", "371", "374", "375", "376", "379", "179", "114", "158", "160"}
local function compact(p)
  if type(p) ~= "table" then return nil end
  local ip = type(p.ip) == "table" and p.ip or {}
  local c = {ip = {}, sp = {}, sn = {}}
  for _, k in ipairs(SK) do local v = tonumber(ip[k]); if v and v ~= 0 then c.ip[k] = math.tointeger(v) or v end end
  if type(p.si) == "table" then
    for x, sid in ipairs(p.si) do
      sid = toint(sid)
      if SUMMARY_OF[sid] or SD.RATING_SPELL[sid] or SD.ITEM_BONUS[sid] then
        c.sp[#c.sp + 1] = sid
        c.sn[#c.sp] = type(p.sn) == "table" and type(p.sn[x]) == "string" and p.sn[x] or SD.SPELL_NAME[sid] or ""
      end
    end
  end
  return c
end
local sprops = {}                 -- id -> compact properties of another character's item
local SUIT_K = {A = true, C = true, J = true, K = true, E = true, W = true}
local own_c, own_c_ver = {}, -1
local function cprops(r)
  if not r then return nil end
  if r.ch == me then
    if own_c_ver ~= data_ver then own_c, own_c_ver = {}, data_ver end
    local c = own_c[r.i]
    if c == nil then c = compact(own_props[r.i]) or false; own_c[r.i] = c end
    return c or nil
  end
  return sprops[r.i]
end
local idx, idx_ver = {}, -1
local function row_of(id)
  if idx_ver ~= data_ver then
    idx, idx_ver = {}, data_ver
    for ch, o in pairs(others) do if ch ~= me then for _, r in ipairs(o.rows) do idx[tonumber(r.i)] = r end end end
    for lid, r in pairs(live) do idx[lid] = r end
  end
  return idx[id]
end

-- Spells of item-level sets (society bands and lockets, heroic sets, sigils): the level seen on this
-- character (from the spells active on it while worn), otherwise the full level.
local function set_spells(set)
  local L = SD.LEVEL_SETS[set]
  if not L then return nil end
  local lv = st.slv[tostring(set)] or L[#L][1]
  local out = L[1][2]
  for _, t in ipairs(L) do if t[1] <= lv then out = t[2] end end
  return out
end
-- {spell id, name, from the set}: the item's own cantrips and rating spells, then its set's
local function item_spells(c)
  local list, seen = {}, {}
  for x, sid in ipairs(c.sp) do if not seen[sid] then seen[sid] = true; list[#list + 1] = {sid, c.sn[x]} end end
  local ss = set_spells(c.ip["265"] or 0)
  -- aetheria (sigil sets) that already have rating properties don't get their set's rating spells as well
  local rated = false
  local set = c.ip["265"] or 0
  if set >= 35 and set <= 39 then for _, k in ipairs({"370", "371", "374", "375", "376", "379"}) do if c.ip[k] then rated = true end end end
  if ss then
    for _, sid in ipairs(ss) do
      if not seen[sid] and not (rated and SD.RATING_SPELL[sid]) then seen[sid] = true; list[#list + 1] = {sid, SD.SPELL_NAME[sid] or "", true} end
    end
  end
  return list
end
-- An item's value in a column: its property plus its rating spells (one per stacking category)
local function item_val(c, col, spells)
  if col[1] == "MD" then return ((toint(c.ip["179"])) & 0x1000) ~= 0 and 1 or 0 end
  local v = num(c.ip[col[2]])
  if col[4] then
    local best = {}
    for _, s in ipairs(spells) do
      local rs = SD.RATING_SPELL[s[1]]
      if rs and rs[1] == col[1] and (best[rs[3]] or 0) < rs[2] then best[rs[3]] = rs[2] end
    end
    for _, b in pairs(best) do v = v + b end
  end
  return v
end

-- Attributes, wards and trained or specialized skills, in priority order.
local function wanted_rows()
  local w = {}
  for _, c in ipairs(CANTRIPS) do
    if PRIO[c[1]] then
      local ok = c[2] == 0
      if c[2] > 0 then local sk = type(skills) == "table" and skills[tostring(c[2])]; ok = type(sk) == "table" and (tonumber(sk.training) or 0) >= 2 end
      if ok then w[#w + 1] = c end
    end
  end
  table.sort(w, function(a, b) return PRIO[a[1]] < PRIO[b[1]] end)
  return w
end

-- The suit shown ---------------------------------------------------------------------------------
-- {name, worn, mod, ver, s = {[slot] = entry}, x = {aux entries}}; entry {i, ch, t (needs tailoring), m (aux slots)}.
-- A multi-slot piece is one entry in every slot it covers.
local suit = nil
local suit_name = ""              -- the name entry
local fill = nil                  -- running Fill Armor / Best Fill
local add_slot, add_for = nil, nil  -- slot picked for Add to suit, and the item it was picked for
local my_level = 0
local active, ench_sig, observed_at = nil, "", -1e9
local suits_ver, flags, flags_ver = 0, {}, -1
local edits = 0                   -- changes to the suit shown (the window is sent again)
function M.edited() edits = edits + 1 end
-- Cantrip priority (Settings): the list, the disabled ones, a move (up, down, bottom), Disable/Enable and Reset
function M.prio_names() return prio_list() end
local PRIO_LABEL = {["Run (Sprint)"] = "Run", Jumping = "Jump", ["Summoning Prowess"] = "Summoning",
  ["Melee Defense (Invulnerability)"] = "Melee Defense", ["Magic Defense (Resistance)"] = "Magic Defense",
  ["Missile Defense (Impregnability)"] = "Missile Defense"}
function M.prio_label(n) return PRIO_LABEL[n] or n end
M.prio_off = prio_off
function M.prio_toggle(n)
  if not IN_PRIO[n] then return end
  local off = prio_off()
  off[n] = not off[n] or nil
  local list = {}
  for _, x in ipairs(PRIO_DEFAULT) do if off[x] then list[#list + 1] = x end end
  st.prio_off = list; dirty_state = true; apply_prio(); edits = edits + 1
end
function M.prio_move(n, how)
  local list = prio_list()
  local k
  for i, x in ipairs(list) do if x == n then k = i end end
  if not k then return end
  if how == "up" and k > 1 then list[k], list[k - 1] = list[k - 1], n
  elseif how == "down" and k < #list then list[k], list[k + 1] = list[k + 1], n
  elseif how == "bottom" and k < #list then table.remove(list, k); list[#list + 1] = n end
  st.prio = list; dirty_state = true; apply_prio(); edits = edits + 1
end
function M.prio_reset() st.prio = nil; st.prio_off = nil; dirty_state = true; apply_prio(); edits = edits + 1 end
M.apply_prio = apply_prio
M.BEST_LIMITS, M.best_label = BEST_LIMITS, best_label
local pq = {others = nil, list = nil, left = 0, done = false}

local function sbs() return st.sb end
-- the primary set id (No Set when none was picked) and the secondary (nil: none)
function M.set_pair()
  local b = sbs()
  local p1 = b.sets[1] and (b.prim or b.sets[1]) or 0
  local p2 = nil
  for _, x in ipairs(b.sets) do if x ~= p1 then p2 = x end end
  return p1, p2
end
local function set_name(id)
  if id == nil then return "-" end
  for _, x in ipairs(SETS) do if x[1] == id then return x[2] end end
  return "-"
end
local function worn_suit()
  local su = {s = {}, x = {}, worn = true, ver = data_ver}
  local ids = {}
  for id in pairs(live) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local r = live[id]
    if r.e == 1 then
      local m = toint(r.ws)
      local c = cprops(r)
      if m == 0 and c then m = toint(c.ip["218103822"]) end
      local ent, put = {i = id, ch = me}, false
      for k, sl in ipairs(SUIT_SLOTS) do
        if (m & sl[2]) ~= 0 and not su.s[k] then su.s[k] = ent; put = true; if k > ARMOR_N then break end end
      end
      if not put and (m & (AUX_CLOAK | AUX_WEAPON)) ~= 0 then ent.m = m; su.x[#su.x + 1] = ent end
    end
  end
  return su
end
local function cur_suit()
  if not suit or (suit.worn and not suit.mod and suit.ver ~= data_ver) then suit = worn_suit() end
  return suit
end
local function first_slot(su, e) for k = 1, #SUIT_SLOTS do if su.s[k] == e then return k end end end
local function remove_ent(su, e) for k = 1, #SUIT_SLOTS do if su.s[k] == e then su.s[k] = nil end end; su.mod = true end
local function saved_form(su)
  local s = {}
  for k = 1, #SUIT_SLOTS do local e = su.s[k]; if e then s[tostring(k)] = {i = e.i, ch = e.ch, t = e.t or nil} end end
  local x = {}
  for _, e in ipairs(su.x) do x[#x + 1] = {i = e.i, ch = e.ch, m = e.m} end
  return {s = s, x = x}
end
local function from_saved(name, d)
  local su = {name = name, s = {}, x = {}}
  local by = {}
  for k = 1, #SUIT_SLOTS do
    local e = type(d.s) == "table" and d.s[tostring(k)]
    if type(e) == "table" and tonumber(e.i) then
      local id = tonumber(e.i)
      local ent = by[id] or {i = id, ch = tostring(e.ch or ""), t = e.t == true or nil}
      by[id] = ent; su.s[k] = ent
    end
  end
  for _, e in ipairs(type(d.x) == "table" and d.x or {}) do
    if type(e) == "table" and tonumber(e.i) then su.x[#su.x + 1] = {i = tonumber(e.i), ch = tostring(e.ch or ""), m = toint(e.m)} end
  end
  return su
end
-- Items in saved suits: id -> "Suit: A, B" (shown in Details on the Global Inventory page)
function M.flag(id)
  if flags_ver ~= suits_ver then
    flags, flags_ver = {}, suits_ver
    local names = {}
    for n in pairs(st.suits) do names[#names + 1] = n end
    table.sort(names)
    for _, n in ipairs(names) do
      local d = st.suits[n]
      local seen = {}
      local function mark(e)
        local id = type(e) == "table" and tonumber(e.i)
        if id and not seen[id] then seen[id] = true; flags[id] = flags[id] and (flags[id] .. ", " .. n) or ("Suit: " .. n) end
      end
      for _, e in pairs(type(d.s) == "table" and d.s or {}) do mark(e) end
      for _, e in ipairs(type(d.x) == "table" and d.x or {}) do mark(e) end
    end
  end
  return flags[id]
end

-- Analysis: the items counted (shown slots and ticked aux), their totals, legendary cantrips, doubles.
local function counted(su)
  local seen, list, b = {}, {}, sbs()
  for k = 1, #SUIT_SLOTS do local e = su.s[k]; if e and not seen[e] then seen[e] = true; list[#list + 1] = e end end
  for _, e in ipairs(su.x) do
    local m = e.m or 0
    if ((m & AUX_CLOAK) ~= 0 and b.aux) or ((m & AUX_WEAPON) ~= 0 and b.wep) then list[#list + 1] = e end
  end
  return list
end
local function analyze(su)
  local a = {leg = {}, tier = {}, count = {}, name = {}, tot = {}}
  local best, bcol, sets = {}, {}, {}
  for _, e in ipairs(counted(su)) do
    local c = cprops(row_of(e.i))
    if c then
      local set = c.ip["265"] or 0
      local skip_set = sets[set]
      sets[set] = true
      local rows = {}
      for _, s in ipairs(item_spells(c)) do
        if not (s[3] and skip_set) then
          local co = CANTRIP_OF[s[1]]
          if co then
            -- (counted by spell, so a double is the same cantrip at the same level: two legendary, two epic)
            if not rows[s[1]] then rows[s[1]] = true; a.count[s[1]] = (a.count[s[1]] or 0) + 1; a.name[s[1]] = s[2] ~= "" and s[2] or nil end
            if co[2] == 5 then a.leg[co[1]] = true end
            if co[2] > (a.tier[co[1]] or 0) then a.tier[co[1]] = co[2] end
          end
          local rs = SD.RATING_SPELL[s[1]]
          if rs and (best[rs[3]] or 0) < rs[2] then best[rs[3]] = rs[2]; bcol[rs[3]] = rs[1] end
        end
      end
      for _, col in ipairs(SUIT_COLS) do
        if col[4] then a.tot[col[1]] = (a.tot[col[1]] or 0) + (col[2] and num(c.ip[col[2]]) or item_val(c, col, {})) end
      end
    end
  end
  for key, v in pairs(best) do a.tot[bcol[key]] = (a.tot[bcol[key]] or 0) + v end
  return a
end

-- Slots an item can go in: armor in its own slot, or (loot armor covering several slots) the slots
-- the reduction tools can make it (ACE Tailoring); clothes and jewelry in the slots they fit.
local function reduce_slots(vl)
  local r, seen = {}, {}
  local function add(m) for k = 1, ARMOR_N do if SUIT_SLOTS[k][2] == m and not seen[k] then seen[k] = true; r[#r + 1] = k end end end
  if (vl & CH) ~= 0 then add(CH) elseif (vl & UA) ~= 0 then add(UA) elseif (vl & AB) ~= 0 then add(AB) end   -- main tool
  if (vl & CH) == 0 then                                                                                       -- lower tool
    if (vl & UA) ~= 0 then add(LA) elseif (vl & UL) ~= 0 then add(LL) elseif (vl & (LL | FT)) == (LL | FT) then add(FT) end
  end
  if (vl & UL) ~= 0 then add(UL) end                                                                          -- middle tool
  table.sort(r)
  return r
end
-- {{slot, needs tailoring}} for the armor slots
local function armor_targets(c)
  local vl = toint(c.ip["218103822"])
  local own = {}
  for k = 1, ARMOR_N do if (vl & SUIT_SLOTS[k][2]) ~= 0 then own[#own + 1] = k end end
  if #own == 1 then return {{own[1], false}} end
  local out = {}
  if #own > 1 and toint(c.ip["105"]) > 0 then for _, k in ipairs(reduce_slots(vl)) do out[#out + 1] = {k, true} end end
  return out
end
local function slot_options(c)
  local out = armor_targets(c)
  local vl = toint(c.ip["218103822"])
  for k = ARMOR_N + 1, #SUIT_SLOTS do if (vl & SUIT_SLOTS[k][2]) ~= 0 then out[#out + 1] = {k, false} end end
  return out
end
local function option_text(o) return SUIT_SLOTS[o[1]][1] .. (o[2] and " (tailor)" or "") end
local function add_item(su, r, k, t)
  for kk = 1, #SUIT_SLOTS do local e = su.s[kk]; if e and e.i == r.i then remove_ent(su, e) end end
  local old = su.s[k]
  if old then remove_ent(su, old) end
  su.s[k] = {i = r.i, ch = r.ch, t = t or nil}; su.mod = true
end

-- Fill Armor and Best Fill ---------------------------------------------------------------------------
-- Candidates: armor pieces from every saved character for the empty armor slots, of a ticked set with
-- pieces still needed. Each candidate lists the wanted cantrips it improves: {row, tier} where its tier is
-- higher than the best already in the suit.
-- Fill Armor picks one piece at a time: pieces adding 2 or 3 missing legendary cantrips, then 1 with the
-- ticked CD/CDR, then 1; when no legendary helps, the same for epic, then major, moderate and minor;
-- then the higher-priority cantrip, more of the ticked rating, lower workmanship.
-- Best Fill then searches every combination for a better suit: more slots filled, more missing legendary
-- cantrips covered, higher-priority ones, then more covered at epic or better, major or better and so on,
-- more CD/CDR, lower workmanship.
local function cand_key(cd, cov)
  local n5, r5, low, nl, rl = 0, 9999, 0, 0, 9999
  for _, x in ipairs(cd.rows) do
    local c, t = x[1], x[2]
    if t > (cov[c] or 0) then
      local p = PRIO[c[1]]
      if t == 5 then n5 = n5 + 1; if p < r5 then r5 = p end
      elseif t > low then low, nl, rl = t, 1, p
      elseif t == low then nl = nl + 1; if p < rl then rl = p end end
    end
  end
  if n5 >= 2 then return 1, n5, r5 end
  if n5 == 1 then return cd.crit > 0 and 2 or 3, 1, r5 end
  if low > 0 then return 8 - low, nl, rl end          -- epic 4, major 5, moderate 6, minor 7
  return 9, 0, 9999
end
-- A candidate: {r, c, k (slot), t (tailor), set, rows, crit, wk}. Ties: name, slot and id, so the choice never varies.
local function cand_better(a, b, cov)
  local ta, na, ra = cand_key(a, cov)
  local tb, nb, rb = cand_key(b, cov)
  if ta ~= tb then return ta < tb end
  if na ~= nb then return na > nb end
  if ra ~= rb then return ra < rb end
  if a.crit ~= b.crit then return a.crit > b.crit end
  if a.wk ~= b.wk then return a.wk < b.wk end
  if a.r.n ~= b.r.n then return a.r.n < b.r.n end
  if a.k ~= b.k then return a.k < b.k end
  return a.r.i < b.r.i
end
-- One candidate per slot, set and cantrip combination is enough: the one with more of the ticked
-- rating, then lower workmanship (any other is never chosen before it).
local function keeps(a, b)
  if a.crit ~= b.crit then return a.crit > b.crit end
  if a.wk ~= b.wk then return a.wk < b.wk end
  if a.r.n ~= b.r.n then return a.r.n < b.r.n end
  return a.r.i < b.r.i
end
local function start_fill(best)
  local b, su = sbs(), cur_suit()
  local quota = {}
  if #b.sets <= 1 then quota[b.sets[1] or 0] = ARMOR_N
  else
    local p = b.prim or b.sets[1]
    for _, s in ipairs(b.sets) do quota[s] = s == p and 5 or 4 end
  end
  local cov, used = {}, {}
  local a = analyze(su)
  for c, t in pairs(a.tier) do cov[c] = t end      -- the best tier of each cantrip already in the suit
  local seen = {}
  for k = 1, #SUIT_SLOTS do
    local e = su.s[k]
    if e then
      used[e.i] = true
      if k <= ARMOR_N and not seen[e] then
        seen[e] = true
        local c = cprops(row_of(e.i))
        local set = c and (c.ip["265"] or 0) or -1
        if quota[set] then quota[set] = quota[set] - 1 end
      end
    end
  end
  for _, e in ipairs(su.x) do used[e.i] = true end
  local excl = {}
  if not b.from then
    for n, d in pairs(st.suits) do
      if n ~= su.name then
        for _, e in pairs(type(d.s) == "table" and d.s or {}) do if type(e) == "table" and tonumber(e.i) then excl[tonumber(e.i)] = true end end
        for _, e in ipairs(type(d.x) == "table" and d.x or {}) do if type(e) == "table" and tonumber(e.i) then excl[tonumber(e.i)] = true end end
      end
    end
  end
  local empty = {}
  for k = 1, ARMOR_N do if not su.s[k] then empty[k] = true end end
  if not next(empty) then notes.suit = "No empty armor slots"; return end
  local rows = {}
  for ch, o in pairs(others) do if ch ~= me then for _, r in ipairs(o.rows) do if r.k == "A" then rows[#rows + 1] = r end end end end
  for _, r in pairs(live) do if r.k == "A" then rows[#rows + 1] = r end end
  fill = {best = best, phase = pq.done and "gather" or "wait", rows = rows, pos = 1, quota = quota, cov = cov, used = used, excl = excl,
    empty = empty, keep = {}, cands = {}, wanted = {}, started = now, crit = b.crit, picks = {}}
  for _, c in ipairs(wanted_rows()) do fill.wanted[c] = true end
  for k in pairs(empty) do fill.keep[k] = {}; fill.cands[k] = {} end
  notes.suit = pq.done and "" or "Reading saved items..."
end
local GATHER_PER_TICK = 1800      -- work per update: 1 for a row passed over, 10 for a candidate
local CRIT_COL = {}
for _, col in ipairs(SUIT_COLS) do CRIT_COL[col[1]] = col end
local function gather_step()
  local f = fill
  local n = 0
  while f.pos <= #f.rows and n < GATHER_PER_TICK and workavailable() do
    local r = f.rows[f.pos]; f.pos = f.pos + 1; n = n + 1
    local c = cprops(r)
    local set = c and (c.ip["265"] or 0)
    if c and (f.quota[set] or 0) > 0 and not f.used[r.i] and not f.excl[r.i]
      and not (r.ch ~= me and toint(c.ip["114"]) > 0)                                                -- attuned
      and not (my_level > 0 and toint(c.ip["158"]) == 7 and toint(c.ip["160"]) > my_level) then     -- wield level
      n = n + 10
      local targets = armor_targets(c)
      local any = false
      for _, t in ipairs(targets) do if f.empty[t[1]] then any = true end end
      if any then
        local sp = item_spells(c)
        local best = {}
        for _, s in ipairs(sp) do
          local co = CANTRIP_OF[s[1]]
          if co and f.wanted[co[1]] and co[2] > (f.cov[co[1]] or 0) and co[2] > (best[co[1]] or 0) then best[co[1]] = co[2] end
        end
        local rows, keys = {}, {}
        for c2, t in pairs(best) do rows[#rows + 1] = {c2, t}; keys[#keys + 1] = PRIO[c2[1]] * 10 + t end
        table.sort(keys)
        local key = set .. "|" .. table.concat(keys, ",")
        local crit = f.crit and item_val(c, CRIT_COL[f.crit], sp) or 0
        local wk = num(c.ip["105"])
        for _, t in ipairs(targets) do
          if f.empty[t[1]] then
            local cd = {r = r, c = c, k = t[1], t = t[2], set = set, rows = rows, crit = crit, wk = wk}
            local keep = f.keep[t[1]]
            if not keep[key] or keeps(cd, keep[key]) then keep[key] = cd end
          end
        end
      end
    end
  end
  if f.pos <= #f.rows then return false end
  for k, keep in pairs(f.keep) do local list = f.cands[k]; for _, cd in pairs(keep) do list[#list + 1] = cd end end
  return true
end
-- Fill Armor: one pick after comparing every candidate (spread over updates); false when nothing more fits
local GREEDY_PER_TICK = 1500      -- candidates compared per update
local function greedy_step(f)
  local g = f.g
  if not g.slots then
    g.slots = {}
    for k in pairs(g.empty) do g.slots[#g.slots + 1] = k end
    table.sort(g.slots)
    g.si, g.ci, g.best = 1, 1, nil
  end
  local n = 0
  while g.si <= #g.slots do
    local list = f.cands[g.slots[g.si]]
    while g.ci <= #list do
      if n >= GREEDY_PER_TICK or not workavailable() then return nil end
      local cd = list[g.ci]; g.ci = g.ci + 1; n = n + 1
      if not g.used[cd.r.i] and (g.quota[cd.set] or 0) > 0 and (not g.best or cand_better(cd, g.best, g.cov)) then g.best = cd end
    end
    g.si, g.ci = g.si + 1, 1
  end
  local best = g.best
  g.slots = nil
  if not best then return false end
  f.picks[#f.picks + 1] = best
  g.empty[best.k] = nil; g.used[best.r.i] = true; g.quota[best.set] = g.quota[best.set] - 1
  for _, x in ipairs(best.rows) do if x[2] > (g.cov[x[1]] or 0) then g.cov[x[1]] = x[2] end end
  return true
end
-- Suit score: {filled, legendary added, their priority weight, epic or better, major or better,
-- moderate or better, minor or better, CD/CDR, -workmanship}; index of "tier k or better" for k = 5..1
local LIFT = {[5] = 2, [4] = 4, [3] = 5, [2] = 6, [1] = 7}
local NS = 9
local function better(a, b) for x = 1, NS do if a[x] ~= b[x] then return a[x] > b[x] end end return false end
local function score_of(picks, base)
  local cov, s = {}, {#picks, 0, 0, 0, 0, 0, 0, 0, 0}
  for c, t in pairs(base) do cov[c] = t end
  for _, cd in ipairs(picks) do
    for _, x in ipairs(cd.rows) do
      local before = cov[x[1]] or 0
      if x[2] > before then
        for k = before + 1, x[2] do s[LIFT[k]] = s[LIFT[k]] + 1; if k == 5 then s[3] = s[3] + weight(x[1]) end end
        cov[x[1]] = x[2]
      end
    end
    s[8] = s[8] + cd.crit; s[9] = s[9] - cd.wk
  end
  return s
end
-- Best Fill: slots with fewer candidates first; each slot's candidates in Fill Armor order (one slot sorted per update).
local function sort_key(cd, cov)
  local tier, n, rank = cand_key(cd, cov)
  return tier * 1e12 + (9 - n) * 1e11 + rank * 1e7 + (999 - math.min(cd.crit, 999)) * 1e4 + math.min(cd.wk, 9999)
end
local PREP_CANDS = 1500           -- candidates sorted per update when Best Fill prepares its search
local function search_prep(f)
  if not f.prep then
    f.prep = {}
    for k in pairs(f.empty) do f.prep[#f.prep + 1] = k end
    table.sort(f.prep)
    f.slots = {}
    return false
  end
  -- slots sorted a few at a time (PREP_CANDS candidates per update)
  local done = 0
  while f.prep[1] and done < PREP_CANDS and workavailable() do
    local k = table.remove(f.prep, 1)
    local list = f.cands[k]
    for _, cd in ipairs(list) do cd.sk = sort_key(cd, f.cov) end
    table.sort(list, function(x, y) if x.sk ~= y.sk then return x.sk < y.sk end return x.r.i < y.r.i end)
    f.slots[#f.slots + 1] = {k = k, list = list}
    done = done + #list + 10
  end
  if f.prep[1] or done > 0 then return false end
  local slots = f.slots
  table.sort(slots, function(x, y) if #x.list ~= #y.list then return #x.list < #y.list end return x.k < y.k end)
  -- bounds for the slots still to choose (from depth d on): each part at most the best one candidate gives
  local n = #slots
  local sb = {}
  sb[n + 1] = {0, 0, 0, 0, 0, 0, 0, 0}
  for d = n, 1, -1 do
    local m = {0, 0, 0, 0, 0, 0, 0, 0}
    for _, cd in ipairs(slots[d].list) do
      local v = {1, 0, 0, 0, 0, 0, 0, cd.crit}
      for _, x in ipairs(cd.rows) do
        local base = f.cov[x[1]] or 0
        for k = base + 1, x[2] do v[LIFT[k]] = v[LIFT[k]] + 1; if k == 5 then v[3] = v[3] + weight(x[1]) end end
      end
      for i = 1, 8 do if v[i] > m[i] then m[i] = v[i] end end
    end
    local nx, cur = sb[d + 1], {}
    for i = 1, 8 do cur[i] = nx[i] + m[i] end
    sb[d] = cur
  end
  f.s = {slots = slots, bound = sb, d = 1, choice = {0}, chosen = {}, cnt = {}, cur = {0, 0, 0, 0, 0, 0, 0, 0, 0}, used = {}, quota = {}}
  for id, v in pairs(f.used) do f.s.used[id] = v end
  for set, v in pairs(f.quota) do f.s.quota[set] = v end
  f.best_score = score_of(f.picks, f.cov)
  f.best_picks = f.picks
  return true
end
-- best tier of a cantrip with the chosen pieces: the suit's own, or the highest a chosen piece gives
local function best_tier(f, c)
  local cnt = f.s.cnt[c]
  if cnt then for t = 5, 1, -1 do if (cnt[t] or 0) > 0 then return math.max(t, f.cov[c] or 0) end end end
  return f.cov[c] or 0
end
local function apply(f, cd, sign)
  local s = f.s
  local cur = s.cur
  cur[1] = cur[1] + sign
  for _, x in ipairs(cd.rows) do
    local c, t = x[1], x[2]
    local before = best_tier(f, c)
    local cnt = s.cnt[c]
    if not cnt then cnt = {}; s.cnt[c] = cnt end
    cnt[t] = (cnt[t] or 0) + sign
    local after = best_tier(f, c)
    if after > before then
      for k = before + 1, after do cur[LIFT[k]] = cur[LIFT[k]] + 1; if k == 5 then cur[3] = cur[3] + weight(c) end end
    elseif after < before then
      for k = after + 1, before do cur[LIFT[k]] = cur[LIFT[k]] - 1; if k == 5 then cur[3] = cur[3] - weight(c) end end
    end
  end
  cur[8] = cur[8] + sign * cd.crit; cur[9] = cur[9] - sign * cd.wk
  s.quota[cd.set] = s.quota[cd.set] - sign
  s.used[cd.r.i] = sign == 1 or nil
end
local SEARCH_PER_TICK = 450       -- search steps per update
local function search_step(f)
  local s = f.s
  local n = 0
  while n < SEARCH_PER_TICK and workavailable() do
    n = n + 1
    f.steps = (f.steps or 0) + 1
    local d = s.d
    if d == 0 then return true end
    if d > #s.slots then
      if better(s.cur, f.best_score) then
        local copy = {}
        for i = 1, NS do copy[i] = s.cur[i] end
        f.best_score = copy
        local picks = {}
        for x = 1, #s.slots do if s.chosen[x] then picks[#picks + 1] = s.chosen[x] end end
        f.best_picks = picks
      end
      s.d = d - 1
      if s.chosen[s.d] then apply(f, s.chosen[s.d], -1); s.chosen[s.d] = nil end
    else
      local list = s.slots[d].list
      local x = s.choice[d] + 1
      while x <= #list and (s.used[list[x].r.i] or (s.quota[list[x].set] or 0) <= 0) do x = x + 1; n = n + 1 end
      s.choice[d] = x
      if x > #list + 1 then
        s.d = d - 1
        if s.d > 0 and s.chosen[s.d] then apply(f, s.chosen[s.d], -1); s.chosen[s.d] = nil end
      else
        local cd = list[x]          -- nil: leave this slot empty
        if cd then apply(f, cd, 1) end
        -- can the rest of the slots still beat the best suit found? (each part of the score at most its bound)
        local b, cur, bs = s.bound[d + 1], s.cur, f.best_score
        local go = false
        for i = 1, NS do
          local u = cur[i] + (b[i] or 0)
          if u ~= bs[i] then go = u > bs[i]; break end
        end
        if go then
          s.chosen[d] = cd; s.d = d + 1; s.choice[d + 1] = 0
        elseif cd then apply(f, cd, -1) end
      end
    end
  end
  return false
end
local function finish_fill(f, picks, text)
  local su = cur_suit()
  for _, cd in ipairs(picks) do if not su.s[cd.k] then su.s[cd.k] = {i = cd.r.i, ch = cd.r.ch, t = cd.t or nil}; su.mod = true end end
  local empty = 0
  for k = 1, ARMOR_N do if not su.s[k] then empty = empty + 1 end end
  notes.suit = text .. ": " .. #picks .. " " .. (#picks == 1 and "piece" or "pieces") .. " added" ..
    (empty > 0 and (", " .. empty .. (empty == 1 and " armor slot" or " armor slots") .. " still empty") or "")
  fill = nil; edits = edits + 1
end
local function fill_step()
  local f = fill
  if f.phase == "wait" then if pq.done then f.phase = "gather"; notes.suit = "" else return end end
  if f.phase == "gather" then if gather_step() then f.phase = "greedy"; f.g = {cov = {}, quota = {}, used = {}, empty = {}} for k, v in pairs(f.cov) do f.g.cov[k] = v end for k, v in pairs(f.quota) do f.g.quota[k] = v end for k, v in pairs(f.used) do f.g.used[k] = v end for k, v in pairs(f.empty) do f.g.empty[k] = v end end return end
  if f.phase == "greedy" then
    local r = greedy_step(f)
    if r == false then
      if f.best then f.phase = "prep" else finish_fill(f, f.picks, "Fill Armor") end
    end
    return
  end
  if f.phase == "prep" then if search_prep(f) then f.phase = "search"; f.search_at = now end; return end
  if f.phase == "search" then
    if search_step(f) then M.fill_steps = f.steps; finish_fill(f, f.best_picks, "Best Fill: every combination checked")
    elseif now - f.search_at >= best_limit() then
      M.fill_steps = f.steps; finish_fill(f, f.best_picks, "Best Fill: stopped after " .. best_label() .. ", best suit found")
    end
  end
end

-- Window: Suit Builder -------------------------------------------------------------------------------
local function cell(id, text, width, extra)
  local c = {id = id, type = "text", size = SIZE, text = text, width = width, height = SW.h, wrap = false, padding = 0}
  for k, v in pairs(extra or {}) do c[k] = v end
  return c
end
function M.status()
  local su = cur_suit()
  return me .. ": " .. (su.name or "Worn suit") .. (fill and (fill.phase == "search" and " - Best Fill searching..." or " - Filling...") or "")
end
function M.build_suit(top)
  local su, b = cur_suit(), sbs()
  local a = analyze(su)
  local ui = {top, note_row()}
  local names = {"Worn"}
  local sn = {}
  for n in pairs(st.suits) do sn[#sn + 1] = n end
  table.sort(sn)
  for _, n in ipairs(sn) do names[#names + 1] = n end
  -- lined up with the top buttons like the filter row: suit list and name under the first two,
  -- Save to Clear Armor under the next two, Fill Armor and Best Fill under Settings
  ui[#ui + 1] = {id = "sbrow", type = "row", children = {
    {id = "sb_pick", type = "select", size = SIZE, options = names, value = su.name or "Worn", width = TOP_W},
    {id = "sb_name", type = "input", size = SIZE, placeholder = "Suit name", value = suit_name, live = true, width = TOP_W},
    {id = "sb_mid", type = "row", padding = 0, width = 2 * TOP_W + 15, children = {
      {id = "sb_save", type = "button", size = SIZE, text = "Save", auto_width = true, padding = 0},
      {id = "sb_del", type = "button", size = SIZE, text = "Delete", auto_width = true, enabled = su.name ~= nil},
      {id = "sb_gap", type = "text", size = SIZE, text = ""},
      {id = "sb_clear", type = "button", size = SIZE, text = "Clear Armor", auto_width = true, padding = 0}}},
    {id = "sb_fill", type = "button", size = SIZE, text = "Fill Armor", width = 87, padding = 1, enabled = fill == nil,
      tooltip = "Fills the empty armor slots one at a time (quick)"},
    {id = "sb_best", type = "button", size = SIZE, text = "Best Fill", width = TOP_W - 96, enabled = fill == nil,
      tooltip = "Tries combinations for the best armor suit (up to " .. best_label() .. ")"}}}
  -- sets: the primary set (5 pieces when there are two) and a second set (4 pieces)
  local set_opts, opts2 = {}, {"-"}
  for _, x in ipairs(SETS) do set_opts[#set_opts + 1] = x[2]; opts2[#opts2 + 1] = x[2] end
  local p1, p2 = M.set_pair()
  ui[#ui + 1] = {id = "sbsets", type = "row", compact = true, children = {
    {id = "sbs_t1", type = "text", size = SIZE, text = "Primary", wrap = false},
    {id = "sb_set1", type = "select", size = SIZE, options = set_opts, value = set_name(p1), width = 150},
    {id = "sbs_t2", type = "text", size = SIZE, text = "Secondary", wrap = false},
    {id = "sb_set2", type = "select", size = SIZE, options = opts2, value = set_name(p2), width = 150}}}
  do
    ui[#ui + 1] = {id = "sbcrit", type = "row", compact = true, children = {
      {id = "sbc|CD", type = "checkbox", size = SIZE, text = "CD", value = b.crit == "CD", tooltip = "Critical Damage"},
      {id = "sbc|CDR", type = "checkbox", size = SIZE, text = "CDR", value = b.crit == "CDR", tooltip = "Critical Damage Reduction"}}}
  end

  -- the grid: icon, numbers, cantrips; one row per slot
  local rowinfo = {}
  for k = 1, #SUIT_SLOTS do
    local e = su.s[k]
    if e then
      local r = row_of(e.i)
      local c = cprops(r)
      rowinfo[k] = {e = e, r = r, c = c, first = first_slot(su, e) == k, sp = c and item_spells(c) or {}}
    end
  end
  local col = {cell("sh_i", "", SW.icon)}
  for k = 1, #SUIT_SLOTS do
    local x = rowinfo[k]
    if x and x.first and x.r then
      local r = x.r
      col[#col + 1] = {id = "si|" .. k, type = "item_icon", size = 24, icon = r.ic, item_type = r.ty, overlay = r.ov, underlay = r.un, effects = r.ef,
        width = SW.icon, height = SW.h, padding = 0, clickable = true, tooltip = (r.z or r.n) .. "\nClick icon to remove"}
    elseif x and x.first then
      col[#col + 1] = cell("si|" .. k, "?", SW.icon, {clickable = true, tooltip = "Click icon to remove"})
    else col[#col + 1] = cell("si|" .. k, "", SW.icon) end
  end
  col[#col + 1] = cell("st_i", "Total", SW.icon, {bold = true})
  local cols = {{id = "sc_i", type = "column", width = SW.icon, padding = 0, children = col}}
  for _, c in ipairs(SUIT_COLS) do
    local cc = {cell("sh_" .. c[1], c[1], SW.num, {tooltip = c[3]})}
    for k = 1, #SUIT_SLOTS do
      local x = rowinfo[k]
      local v = (x and x.first and x.c) and item_val(x.c, c, x.sp) or 0
      cc[#cc + 1] = cell("sv|" .. k .. "|" .. c[1], v ~= 0 and tostring(v) or "", SW.num, v ~= 0 and {tooltip = c[3]} or nil)
    end
    local t = c[4] and (a.tot[c[1]] or 0) or 0
    cc[#cc + 1] = cell("st_" .. c[1], t ~= 0 and tostring(t) or "", SW.num, {bold = true, tooltip = t ~= 0 and c[3] or nil})
    cols[#cols + 1] = {id = "sc_" .. c[1], type = "column", width = SW.num, padding = 0, children = cc}
  end
  local cn = {cell("sh_c", "Cantrips")}
  for k = 1, #SUIT_SLOTS do
    local x = rowinfo[k]
    local text
    if not x then text = SUIT_SLOTS[k][1] .. ": empty"
    elseif not x.first then text = SUIT_SLOTS[k][1] .. ": covered by " .. (x.r and x.r.n or "?")
    elseif not x.r then text = SUIT_SLOTS[k][1] .. ": item not found"
    else
      local list = {}
      for _, s in ipairs(x.sp) do
        local co = CANTRIP_OF[s[1]]
        if co then list[#list + 1] = {co[2], PRIO[co[1][1]] or 999, (s[2] ~= "" and s[2] or co[1][1]) .. ((a.count[s[1]] or 0) > 1 and (" (" .. a.count[s[1]] .. ")") or "")} end
      end
      table.sort(list, function(p, q) if p[1] ~= q[1] then return p[1] > q[1] end if p[2] ~= q[2] then return p[2] < q[2] end return p[3] < q[3] end)
      local parts = {}
      for _, v in ipairs(list) do parts[#parts + 1] = v[3] end
      text = (x.r.ch ~= me and ("(" .. x.r.ch .. ") ") or "") .. (x.e.t and "(tailor) " or "") ..
        (x.c and join(parts, ", ") or (x.r.n .. " (not appraised yet)"))
    end
    cn[#cn + 1] = cell("sc|" .. k, text, nil, {tooltip = text ~= "" and text or nil})
  end
  cn[#cn + 1] = cell("st_c", "")
  cols[#cols + 1] = {id = "sc_c", type = "column", padding = 0, children = cn}
  ui[#ui + 1] = {id = "sgrid", type = "row", padding = 0, children = cols}

  -- missing legendary cantrips (priority order) and cantrips on two or more items
  local missing, doubles = {}, {}
  for _, c in ipairs(wanted_rows()) do if not a.leg[c] then missing[#missing + 1] = SD.LEGENDARY_NAME[c[1]] or ("Legendary " .. c[1]) end end
  for _, c in ipairs(CANTRIPS) do
    for t = 5, 1, -1 do
      local sid = c[3][t]
      if sid > 0 and (a.count[sid] or 0) > 1 then doubles[#doubles + 1] = (a.name[sid] or c[1]) .. " (" .. a.count[sid] .. ")" end
    end
  end
  local text = "Missing cantrips: " .. (#missing > 0 and join(missing, ", ") or "none") ..
    (type(skills) ~= "table" and " (skills not available yet)" or "") .. "\n" ..
    "Double cantrips: " .. (#doubles > 0 and join(doubles, ", ") or "none")
  ui[#ui + 1] = {id = "s_miss", type = "text", size = SIZE, text = text, color = (#missing > 0 or #doubles > 0) and "yellow" or "green", wrap = true}
  ui[#ui + 1] = {id = "sbo|aux", type = "checkbox", size = SIZE, text = "Include Aetheria and Cloak stats", value = b.aux == true}
  ui[#ui + 1] = {id = "sbo|wep", type = "checkbox", size = SIZE, text = "Include weapon + shield stats", value = b.wep == true}
  ui[#ui + 1] = {id = "sbo|from", type = "checkbox", size = SIZE, text = "Fill armor from existing suits", value = b.from == true}
  return ui
end

-- Window: Character Summary (Oracle of Dereth, Character > Cantrips) --------------------------------
local TIER = {"Minor", "Moderate", "Major", "Epic", "Legendary"}
-- the icon of the cantrip row for a skill or attribute ("Run" -> "Run (Sprint)")
local BONUS_ICON = {Jump = "Jumping", Summoning = "Summoning Prowess", Health = "Health Gain"}
local function bonus_icon(what)
  local n = BONUS_ICON[what] or what
  if SD.CANTRIP_ICON[n] then return SD.CANTRIP_ICON[n] end
  for k, v in pairs(SD.CANTRIP_ICON) do if starts(k, n .. " (") then return v end end
  return 0
end
function M.build_sum(top, char_ints)
  local act = active or {}
  -- spell id -> {items giving it, first item's name}: worn items' own spells and their sets' spells
  local src = {}
  local ids = {}
  for id, r in pairs(live) do if r.e == 1 then ids[#ids + 1] = id end end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local r = live[id]
    local c = cprops(r)
    if c then for _, s in ipairs(item_spells(c)) do local x = src[s[1]]; if x then x[1] = x[1] + 1 else src[s[1]] = {1, r.n} end end end
  end
  local function tier_of(c) for t = 5, 1, -1 do local sid = c[3][t]; if sid and sid > 0 and act[sid] then return t end end return 0 end
  -- sections: attributes; armor and wards; specialized skills; trained skills; essence and vitality; active sets; gains
  local function trained(c, lvl) local sk = type(skills) == "table" and skills[tostring(c[2])]; return type(sk) == "table" and toint(sk.training) == lvl end
  local sections = {{}, {}, {}, {}, {}, {}, {}}
  for _, c in ipairs(CANTRIPS) do
    local n = c[1]
    if n ~= "Blank" then
      if c[2] == 0 and (n == "Health Gain" or n == "Stamina Gain" or n == "Mana Gain") then sections[7][#sections[7] + 1] = c
      elseif c[2] == 0 and WARD[n] then sections[2][#sections[2] + 1] = c
      elseif c[2] == 0 then sections[1][#sections[1] + 1] = c
      elseif c[2] > 0 and trained(c, 3) then sections[3][#sections[3] + 1] = c
      elseif c[2] > 0 and trained(c, 2) then sections[4][#sections[4] + 1] = c
      elseif c[2] == -3 or c[2] == -4 then sections[5][#sections[5] + 1] = c
      elseif (c[2] == -1 or c[2] == -2) and tier_of(c) > 0 then sections[6][#sections[6] + 1] = c end
    end
  end
  for x = 3, 4 do table.sort(sections[x], function(p, q) return lower(p[1]) < lower(q[1]) end) end
  local function level(c, t)
    if t == 0 then return "-" end
    if c[2] == -2 then return ({"2 pieces", "4 pieces", "6 pieces", "8 pieces", "9 pieces"})[t] end
    if c[2] == -1 then return ({"", "2 pieces", "3 pieces", "4 pieces", "5 pieces"})[t] end
    if c[2] == -3 then return ({"+15 health", "+20 health", "+25 health", "+25 health", "+30 health"})[t] end
    if c[2] == -4 then return ({"", "+5 health", "+10 health", "+15 health", "+20 health"})[t] end
    local x = src[c[3][t]]
    return TIER[t] .. ((x and x[1] > 1) and (" (" .. x[1] .. ")") or "")
  end
  -- other spells of worn items that raise a skill or attribute (quest items, rare jewelry): spell, amount, item
  local other, oseen = {}, {}
  for _, id in ipairs(ids) do
    local r = live[id]
    local c = cprops(r)
    if c then
      for _, sp in ipairs(item_spells(c)) do
        local b = SD.ITEM_BONUS[sp[1]]
        if b and not SUMMARY_OF[sp[1]] and not oseen[sp[1]] then
          oseen[sp[1]] = true
          other[#other + 1] = {sp[2] ~= "" and sp[2] or ("Spell " .. sp[1]), b[1], SD.ITEM_BONUS_OF[b[2]] or "", r.n}
        end
      end
    end
  end
  table.sort(other, function(p, q) if p[3] ~= q[3] then return p[3] < q[3] end return p[2] > q[2] end)
  local H, GAP = 22, 10
  local ci, cn, cl, cs = {}, {}, {}, {}
  local rows = 0
  local limit = 60                -- 4 controls a row (icon, name, level, item)
  for si, list in ipairs(sections) do
    for x, c in ipairs(list) do
      if rows < limit then
        rows = rows + 1
        local h = (x == 1 and si > 1 and rows > 1) and (H + GAP) or H
        local t = tier_of(c)
        local srcx = t > 0 and src[c[3][t]]
        local k = tostring(rows)
        ci[#ci + 1] = {id = "bi|" .. k, type = "icon", icon = SD.CANTRIP_ICON[c[1]] or 0, size = 20, width = 26, height = h, padding = 0}
        local name = c[1]
        if (c[2] == -3 or c[2] == -4) and t > 0 then name = SD.SPELL_NAME[c[3][t]] or name end
        cn[#cn + 1] = {id = "bn|" .. k, type = "text", size = SIZE, text = name, height = h, wrap = false, padding = 0}
        cl[#cl + 1] = {id = "bl|" .. k, type = "text", size = SIZE, text = level(c, t), width = 130, height = h, wrap = false, padding = 0}
        cs[#cs + 1] = {id = "bs|" .. k, type = "text", size = SIZE, text = srcx and srcx[2] or "", height = h, wrap = false, padding = 0,
          tooltip = srcx and srcx[2] or nil}
      end
    end
  end
  for x, o in ipairs(other) do
    if rows < limit then
      rows = rows + 1
      local h = (x == 1 and rows > 1) and (H + GAP) or H
      local k = tostring(rows)
      ci[#ci + 1] = {id = "bi|" .. k, type = "icon", icon = bonus_icon(o[3]), size = 20, width = 26, height = h, padding = 0}
      cn[#cn + 1] = {id = "bn|" .. k, type = "text", size = SIZE, text = o[1], height = h, wrap = false, padding = 0, tooltip = o[1]}
      cl[#cl + 1] = {id = "bl|" .. k, type = "text", size = SIZE, text = "+" .. o[2] .. " " .. o[3], width = 130, height = h, wrap = false, padding = 0}
      cs[#cs + 1] = {id = "bs|" .. k, type = "text", size = SIZE, text = o[4], height = h, wrap = false, padding = 0, tooltip = o[4]}
    end
  end
  local ui = {top, note_row()}
  local ci2 = type(char_ints) == "table" and char_ints or {}
  local function q(k) return toint(ci2[tostring(k)]) end
  local parts = {}
  if q(307) ~= 0 or q(314) ~= 0 then parts[#parts + 1] = "Dam: " .. q(307) .. "/" .. q(314) end
  if q(308) ~= 0 or q(316) ~= 0 then parts[#parts + 1] = "Def: " .. q(308) .. "/" .. q(316) end
  if q(379) ~= 0 then parts[#parts + 1] = "Vit: " .. q(379) end
  ui[#ui + 1] = {id = "b_rate", type = "text", size = SIZE, text = #parts > 0 and join(parts, ", ") or "-", wrap = false}
  if not active then ui[#ui + 1] = {id = "b_wait", type = "text", size = SMALL, text = "Active spells not available yet", color = "yellow", wrap = false} end
  ui[#ui + 1] = {id = "bgrid", type = "row", padding = 0, children = {
    {id = "bc_i", type = "column", width = 26, padding = 0, children = ci},
    {id = "bc_n", type = "column", width = 260, padding = 0, children = cn},
    {id = "bc_l", type = "column", width = 130, padding = 0, children = cl},
    {id = "bc_s", type = "column", padding = 0, children = cs}}}
  return ui
end

-- Global Inventory page: Add to suit for the selected item --------------------------------------------
local function add_choices()
  local r = selected and row_of(selected.i)
  local c = r and cprops(r)
  if not c then return r, {} end
  return r, slot_options(c)
end
function M.add_controls()
  local _, opts = add_choices()
  local names = {}
  for _, o in ipairs(opts) do names[#names + 1] = option_text(o) end
  -- blank until a slot is picked for the selected item
  local val = ""
  if selected and add_for == selected.i then for _, n in ipairs(names) do if n == add_slot then val = n end end end
  return {id = "x_add", type = "button", size = SIZE, text = "Add to suit", auto_width = true, enabled = val ~= ""},
    {id = "x_slot", type = "select", size = SIZE, options = #names > 0 and names or {""}, value = val, width = TOP_W, enabled = #names > 0}
end

-- Events -----------------------------------------------------------------------------------------------
-- a set dropdown changed: the primary always has a set (or No Set); secondary "-" is none, and the
-- primary's set there clears it
local function set_pick(which, name)
  local p1, p2 = M.set_pair()
  local id = nil
  for _, x in ipairs(SETS) do if x[2] == name then id = x[1] end end
  if which == 1 then if id then p1 = id end else p2 = id end
  if p2 == p1 then p2 = nil end
  local b = sbs()
  b.sets = {p1}
  if p2 then b.sets[2] = p2 end
  b.prim = p2 and p1 or nil
end
local handle_
function M.handle(e) local ok = handle_(e); if ok then M.edited() end; return ok end
handle_ = function(e)
  local id = type(e.id) == "string" and e.id or ""
  local b = st.sb
  if e.type == "change" then
    if id == "sb_pick" then
      local v = tostring(e.value or "")
      if v == "Worn" or not st.suits[v] then suit = worn_suit() else suit = from_saved(v, st.suits[v]); suit_name = v end
    elseif id == "sb_name" then suit_name = sub(tostring(e.value or ""), 1, 40)
    elseif id == "sb_set1" or id == "sb_set2" then set_pick(id == "sb_set1" and 1 or 2, tostring(e.value or "")); dirty_state = true
    elseif sub(id, 1, 4) == "sbc|" then b.crit = e.value == true and sub(id, 5) or nil; dirty_state = true
    elseif id == "sbo|aux" then b.aux = e.value == true or nil; dirty_state = true
    elseif id == "sbo|wep" then b.wep = e.value == true or nil; dirty_state = true
    elseif id == "sbo|from" then b.from = e.value == true or nil; dirty_state = true
    elseif id == "x_slot" then add_slot, add_for = tostring(e.value or ""), selected and selected.i
    else return false end
    return true
  elseif e.type == "click" then
    local su = cur_suit()
    if id == "sb_save" then
      local a, z = 1, #suit_name
      while a <= z and string.byte(suit_name, a) <= 32 do a = a + 1 end
      while z >= a and string.byte(suit_name, z) <= 32 do z = z - 1 end
      local n = sub(suit_name, a, z)
      if n == "" then n = su.name or "" end
      if n == "" then notes.suit = "Enter a suit name"
      elseif n == "Worn" then notes.suit = "Choose another name"
      else
        local count = 0
        for _ in pairs(st.suits) do count = count + 1 end
        if not st.suits[n] and count >= 30 then notes.suit = "30 suits saved: delete one first"
        else
          st.suits[n] = saved_form(su); su.name, su.worn, su.mod = n, nil, false; suit_name = n
          suits_ver = suits_ver + 1; dirty_state = true; notes.suit = "Saved " .. n
        end
      end
    elseif id == "sb_del" then
      if su.name and st.suits[su.name] then
        st.suits[su.name] = nil; suits_ver = suits_ver + 1; dirty_state = true; notes.suit = "Deleted " .. su.name
        suit = worn_suit(); suit_name = ""
      end
    elseif id == "sb_clear" then
      for k = 1, ARMOR_N do if su.s[k] then remove_ent(su, su.s[k]) end end
    elseif sub(id, 1, 3) == "si|" then
      local k = tonumber(sub(id, 4))
      local x = k and su.s[k]
      if x then remove_ent(su, x) end
    elseif id == "sb_fill" or id == "sb_best" then if not fill then notes.suit = ""; start_fill(id == "sb_best") end
    elseif id == "x_add" then
      local r, opts = add_choices()
      local pick = nil
      if selected and add_for == selected.i then for _, o in ipairs(opts) do if option_text(o) == add_slot then pick = o end end end
      if r and pick then add_item(su, r, pick[1], pick[2]); notes.search = "Added to suit: " .. option_text(pick) end
    else return false end
    return true
  end
  return false
end

-- Requests: other characters' item properties (read once, in the background) ---------------------------------
local pend = {}                   -- {character, items, next}: properties read, made compact a few per update
function M.cache(ch, items)
  if others[ch] and ch ~= me and type(items) == "table" then pend[#pend + 1] = {ch, items, 1} end
end
local CACHE_PER_TICK = 150
local function cache_step()
  local n = 0
  while #pend > 0 and n < CACHE_PER_TICK and workavailable() do
    local j = pend[1]
    local o = others[j[1]]
    if not o then table.remove(pend, 1)
    else
      if not o.kmap then o.kmap = {}; for _, r in ipairs(o.rows) do o.kmap[tonumber(r.i)] = r.k end; n = n + 20 end
      local x = j[2][j[3]]
      j[3] = j[3] + 1
      if j[3] > #j[2] then table.remove(pend, 1) end
      local xid = type(x) == "table" and tonumber(x.i)
      if xid and SUIT_K[o.kmap[xid] or ""] then sprops[xid] = compact(x) end
      n = n + 1
    end
  end
end
function M.result(e, id)
  if sub(id, 1, 3) ~= "pq|" then return false end
  local ch = nil
  for x = 4, #id do if sub(id, x, x) == "|" then ch = sub(id, x + 1); break end end
  pq.left = pq.left - 1
  if ch and e.ok and type(e.data) == "table" then M.cache(ch, e.data.items) end
  return true
end

-- Each update ------------------------------------------------------------------------------------------------
function M.tick(s, own_ready, reqs_n, push)
  my_level = toint(s.level) > 0 and toint(s.level) or my_level
  -- active spells (for item-level sets and the summary), every 2 s
  if type(s.enchantments) == "table" and now - observed_at >= 5 then
    observed_at = now
    local act, sig = {}, 0
    for _, en in ipairs(s.enchantments) do local sid = toint(type(en) == "table" and en.id); if sid > 0 then act[sid] = true; sig = sig + sid end end
    active = act
    ench_sig = #s.enchantments .. ":" .. sig
    for _, r in pairs(live) do
      if r.e == 1 then
        local c = cprops(r)
        local set = c and c.ip["265"]
        local L = set and SD.LEVEL_SETS[set]
        if L then
          local lv = L[1][1]
          for _, t in ipairs(L) do
            local all = true
            for _, sid in ipairs(t[2]) do if not act[sid] then all = false; break end end
            if all then lv = t[1] end
          end
          if st.slv[tostring(set)] ~= lv then st.slv[tostring(set)] = lv; dirty_state = true; edits = edits + 1 end
        end
      end
    end
  end
  -- other characters' properties: after the saved characters are read; 2 reads at a time when idle
  if pq.others ~= others then pq.others, pq.list, pq.left, pq.done = others, nil, 0, false; sprops = {}; pend = {} end
  if own_ready and not pq.list then
    pq.list = {}
    for ch, o in pairs(others) do if ch ~= me and not o.old then for q = 1, o.pp or 0 do pq.list[#pq.list + 1] = {q, ch} end end end
  end
  if pq.list and #pq.list > 0 and reqs_n == 0 then
    for _ = 1, 2 do
      local j = table.remove(pq.list, 1)
      if not j then break end
      pq.left = pq.left + 1
      push({id = "pq|" .. j[1] .. "|" .. j[2], service = "profiles", operation = "read", group = "Props", name = safe(server) .. "_" .. safe(j[2]) .. "_" .. j[1]})
    end
  end
  if #pend > 0 then cache_step() end
  if pq.list and #pq.list == 0 and pq.left <= 0 and #pend == 0 then pq.done = true end
  if fill then fill_step() end
end
function M.key(v)
  local b = st.sb
  return table.concat({suits_ver, tostring(suit), edits, tostring(fill and fill.phase), v == "sum" and ench_sig or "", tostring(add_slot), tostring(add_for), suit_name,
    tostring(pq.done), join(b.sets, ","), tostring(b.prim), tostring(b.crit), tostring(b.aux), tostring(b.wep), tostring(b.from)}, "#")
end
function M.busy() return fill ~= nil end

return M
end)()

local function build_chars()
  local ui = {top_row("Saved characters on " .. server, "chars"), {id = "ctop", type = "row", compact = true, children = {
    {id = "c_reload", type = "button", size = SIZE, text = "Reload", auto_width = true, tooltip = "Read the saved characters again"},
    {id = "c_import", type = "button", size = SIZE, text = "Import", auto_width = true, enabled = not IM.busy(),
      tooltip = "Adds the characters in Library\\Import (made with VGI_Import.html) that aren't saved yet"}}}}
  local names = {}
  for ch in pairs(others) do names[#names + 1] = ch end
  if not others[me] then names[#names + 1] = me end
  table.sort(names)
  for k, ch in ipairs(names) do
    local o = others[ch]
    local count = ch == me and 0 or (o and o.count or 0)
    if ch == me then for _ in pairs(live) do count = count + 1 end end
    local when = ch == me and "now" or age(o and o.saved)
    ui[#ui + 1] = {id = "cr|" .. k, type = "row", children = {
      {id = "cn|" .. k, type = "text", size = SMALL, text = ch, width = 160, wrap = false},
      {id = "cc|" .. k, type = "text", size = SMALL, text = commas(count) .. " items", width = 90, wrap = false},
      {id = "cw|" .. k, type = "text", size = SMALL, text = "updated " .. when, width = 140, wrap = false},
      {id = "c_rm|" .. ch, type = "button", size = SMALL, text = "Remove", auto_width = true, enabled = ch ~= me,
        tooltip = ch == me and "This character is saved while you play it" or "Remove this character's saved items"}}}
  end
  return ui
end
local function best_options() local o = {}; for _, b in ipairs(SB.BEST_LIMITS) do o[#o + 1] = b[1] end; return o end
local prio_sel = nil                -- the cantrip priority line clicked (Settings)
local function build_settings()
  -- Cantrip priority: the order missing cantrips are filled in (Suit Builder), one line each; click a line,
  -- then the buttons move or disable it
  local names, off = SB.prio_names(), SB.prio_off()
  local k_sel = nil
  for k, n in ipairs(names) do if n == prio_sel then k_sel = k end end
  if not k_sel then prio_sel = nil end
  local list = {{id = "pr_b", type = "row", compact = true, children = {
    {id = "prio_reset", type = "button", size = SIZE, text = "Reset", auto_width = true},
    {id = "prio_up", type = "button", size = SIZE, text = "Up", auto_width = true, enabled = k_sel ~= nil and k_sel > 1},
    {id = "prio_down", type = "button", size = SIZE, text = "Down", auto_width = true, enabled = k_sel ~= nil and k_sel < #names},
    {id = "prio_bottom", type = "button", size = SIZE, text = "Bottom", auto_width = true, enabled = k_sel ~= nil and k_sel < #names},
    {id = "prio_off", type = "button", size = SIZE, text = (k_sel and off[prio_sel]) and "Enable" or "Disable", auto_width = true,
      enabled = k_sel ~= nil}}}}
  for k, n in ipairs(names) do
    list[#list + 1] = {id = "pn|" .. k, type = "text", size = SIZE, text = k .. ". " .. SB.prio_label(n) .. (off[n] and " (disabled)" or ""), wrap = false,
      clickable = true, color = k == k_sel and "yellow" or nil, bold = k == k_sel or nil}
  end
  return {
    top_row(me .. ": Settings", "settings"),
    {id = "opt|auto", type = "checkbox", size = SIZE, text = "Appraise items automatically", value = not st.auto_off,
      tooltip = "One item per second, only items that aren't saved yet"},
    {id = "opt|best", type = "row", compact = true, children = {
      {id = "opt|best_t", type = "text", size = SIZE, text = "Best Fill time limit", wrap = false},
      {id = "opt|best_v", type = "select", size = SIZE, options = best_options(), value = SB.best_label(), auto_width = true}}},
    {id = "prio", type = "section", size = SIZE, text = "Cantrip priority", expanded = false, children = list},
  }
end

-- Events ------------------------------------------------------------------------------------
local function changed_filter() search_ver = -1; search = nil; asked_search = now; flt_ver = flt_ver + 1; page = 1; dirty_state = true; shared.touched, shared.due = true, now end
local function handle(e)
  if SB.handle(e) then return end
  local id = type(e.id) == "string" and e.id or ""
  local f = flt()
  if e.type == "change" then
    if id == "f_text" then f.text = sub(tostring(e.value or ""), 1, 100); changed_filter()
    elseif sub(id, 1, 4) == "cat|" then
      -- one category at a time; its sub-filters may be combined
      local k = sub(id, 5)
      if e.value == true then f.cats, f.order, f.subs = {[k] = true}, {k}, {}
      else f.cats, f.order, f.subs = {}, {}, {} end
      changed_filter()
    elseif sub(id, 1, 4) == "sub|" then f.subs[sub(id, 5)] = e.value == true or nil; changed_filter()
    elseif id == "f_dbl" then f.dbl = e.value == true or nil; changed_filter()
    elseif id == "f_worn" then f.worn = e.value == true or nil; changed_filter()
    elseif id == "opt|auto" then st.auto_off = e.value ~= true or nil; dirty_state = true
    elseif id == "opt|best_v" then st.best_limit = tostring(e.value or ""); dirty_state = true; SB.edited()
    end
  elseif e.type == "click" then
    if id == "f_reset" then st.flt = {text = "", cats = {}, subs = {}, order = {}}; st.sort = "cur"; changed_filter()
    elseif sub(id, 1, 2) == "h|" then
      local col = sub(id, 3)
      local s = st.sort or "cur"
      if col == "ch" then st.sort = s == "ch+" and "ch-" or "ch+"
      elseif col == "c" then
        -- Info: with weapons listed, OD, attack, melee defense, workmanship (each high to low);
        -- otherwise the Info text, A-Z and Z-A
        local weapons = false
        for _, r in ipairs(result.rows) do if r.k == "W" then weapons = true break end end
        if weapons then st.sort = s == "co-" and "ca-" or s == "ca-" and "cm-" or s == "cm-" and "cw-" or "co-"
        else st.sort = s == "c+" and "c-" or "c+" end
      else st.sort = s == col .. "+" and (col .. "-") or (col .. "+") end
      search_ver = -1; search = nil; asked_search = now; dirty_state = true; shared.touched, shared.due = true, now
    elseif id == "pg_prev" then page = math.max(1, page - 1)
    elseif id == "pg_next" then page = page + 1
    elseif sub(id, 1, 2) == "r|" then
      local r = result.rows[tonumber(sub(id, 3)) or 0]
      if r then
        selected = {ch = r.ch, i = r.i}
        -- the full description in chat, split at ", " into lines of at most 480 characters (3 lines at most)
        local text = r.z .. (r.ch ~= me and (" (Last on " .. r.ch .. ")") or "")
        local n = 0
        while text ~= "" and n < 3 do
          local part = text
          if #part > 480 then
            local cut = 0
            for j = 480, 2, -1 do if sub(text, j - 1, j) == ", " then cut = j break end end
            if cut > 0 then part, text = sub(text, 1, cut - 2), sub(text, cut + 1)
            else part, text = sub(text, 1, 480), sub(text, 481) end
          else text = "" end
          n = n + 1
          request({service = "notice", operation = "show", text = part, color = NOTE_COLOR})
        end
      end
    elseif id == "v_chars" or id == "v_suit" or id == "v_sum" or id == "v_set" or id == "v_back" or id == "v_search" then
      -- leaving Characters or Settings clears its message (not during an import)
      local to = id == "v_chars" and "chars" or id == "v_set" and "settings" or id == "v_suit" and "suit" or id == "v_sum" and "sum"
        or id == "v_search" and "search" or main_view
      if to ~= view and (view == "settings" or (view == "chars" and not IM.busy())) then notes[view] = "" end
      view = to
      if to == "search" or to == "suit" or to == "sum" then main_view = to end
    elseif id == "x_json" then export_all()
    elseif id == "c_reload" then if not IM.busy() then load_all(); notes.chars = "" end
    elseif id == "c_import" then IM.start()
    elseif id == "prio_reset" then SB.prio_reset()
    elseif sub(id, 1, 3) == "pn|" then prio_sel = SB.prio_names()[tonumber(sub(id, 4)) or 0]
    elseif (id == "prio_up" or id == "prio_down" or id == "prio_bottom") and prio_sel then SB.prio_move(prio_sel, sub(id, 6))
    elseif id == "prio_off" and prio_sel then SB.prio_toggle(prio_sel)
    elseif sub(id, 1, 5) == "c_rm|" then
      local ch = sub(id, 6)
      local o = others[ch]
      if o and ch ~= me then
        local base = prefix .. safe(ch)
        request({service = "profiles", operation = "delete", group = "Chars", name = base})
        for p = 1, math.max(1, o.parts or 1) do request({service = "profiles", operation = "delete", group = "Items", name = base .. "_" .. p}) end
        others[ch] = nil; data_ver = data_ver + 1; notes.chars = "Removed " .. ch
      end
    end
  end
end

-- Weapon rows saved earlier: short rend names; a slayer in Effect ("X S." or "X Slayer", 1.0.3 and 1.1.0)
-- goes back to the front of Details as "X Slayer".
local REND_SHORT = {SlashRend = "SR", PierceRend = "PR", BludgeRend = "BR", AcidRend = "AcR", ColdRend = "CR", LightRend = "LR", FireRend = "FR", NetherRend = "NR"}
local function upgrade_weapon_row(r)
  local words, cur, changed = {}, {}, false
  for k = 1, #r.b + 1 do
    local c = sub(r.b, k, k)
    if c == " " or c == "" then
      if #cur > 0 then local w = table.concat(cur); if REND_SHORT[w] then w = REND_SHORT[w]; changed = true end words[#words + 1] = w; cur = {} end
    else cur[#cur + 1] = c end
  end
  if changed then r.b = join(words, " ") end
  local first, rest = r.b, ""
  for k = 1, #r.b - 1 do if sub(r.b, k, k + 1) == ", " then first, rest = sub(r.b, 1, k - 1), sub(r.b, k + 2) break end end
  local species = nil
  if #first > 7 and sub(first, -7) == " Slayer" then species = sub(first, 1, #first - 7)
  elseif #first > 3 and sub(first, -3) == " S." then species = sub(first, 1, #first - 3) end
  if species then
    r.b = rest
    local sl = species .. " Slayer"
    if not starts(r.d, sl) then r.d = r.d ~= "" and (sl .. ", " .. r.d) or sl end
  end
end

-- Results of requests (saved files) ------------------------------------------------------------
-- "a|b|rest" -> a, b, rest
local function split3(id)
  local p, out, start = 1, {}, 1
  for k = 1, #id do
    if sub(id, k, k) == "|" and #out < 2 then out[#out + 1] = sub(id, start, k - 1); start = k + 1 end
  end
  out[#out + 1] = sub(id, start)
  return out[1], out[2], out[3]
end
-- "x.0" whole numbers in signatures saved before 1.1
local function norm_sig(sg)
  if type(sg) ~= "string" then return sg end
  local out, k = {}, 1
  while k <= #sg do
    if sub(sg, k, k + 1) == ".0" and (k + 2 > #sg or sub(sg, k + 2, k + 2) == "|") and k > 1 and sub(sg, k - 1, k - 1) ~= "|" then k = k + 2
    else out[#out + 1] = sub(sg, k, k); k = k + 1 end
  end
  return table.concat(out)
end
local function char_loaded(ch)
  local o = others[ch]
  if not o then return end
  if o.pp and o.pp > 0 and (ch == me or o.old) then
    for q = 1, o.pp do
      loading.waiting = loading.waiting + 1
      request({id = "pp|" .. q .. "|" .. ch, service = "profiles", operation = "read", group = "Props", name = safe(server) .. "_" .. safe(ch) .. "_" .. q})
    end
  end
end
local function result_event(e)
  local id = tostring(e.id)
  local sent = inflight[id]; inflight[id] = nil
  if e.ok == false and sent and contains(lower(tostring(e.error or "")), "rate limit") then
    table.insert(reqs, 1, sent); inflight[id] = nil   -- sent again in the next batch
    return
  end
  if SB.result(e, id) then return end
  if IM.result(e, id) then return end
  if id == "ls" then
    loading.list, loading.waiting = false, loading.waiting - 1
    for _, name in ipairs(type(e.names) == "table" and e.names or {}) do
      if type(name) == "string" and starts(name, prefix) then
        loading.waiting = loading.waiting + 1
        request({id = "ix|" .. name, service = "profiles", operation = "read", group = "Chars", name = name})
      end
    end
  elseif sub(id, 1, 3) == "ix|" then
    loading.waiting = loading.waiting - 1
    local d = e.ok and type(e.data) == "table" and e.data or nil
    if d and type(d.character) == "string" then
      local ch = d.character
      local o = {rows = {}, saved = tonumber(d.saved) or 0, count = tonumber(d.count) or 0, parts = tonumber(d.parts) or 1,
        pp = tonumber(d.pp) or 0, unap = tonumber(d.unappraised) or 0, left = 0}
      others[ch] = o
      if ch == me then own_parts = o.parts end
      for p = 1, o.parts do
        loading.waiting = loading.waiting + 1; o.left = o.left + 1
        request({id = "it|" .. p .. "|" .. ch, service = "profiles", operation = "read", group = "Items", name = sub(id, 4) .. "_" .. p})
      end
    end
  elseif sub(id, 1, 3) == "it|" then
    loading.waiting = loading.waiting - 1
    local _, _, ch = split3(id)
    local o = others[ch]
    local d = e.ok and type(e.data) == "table" and e.data or nil
    if o and d and type(d.rows) == "table" then
      local v2 = tonumber(d.v) == 2
      if v2 and tonumber(d.f) ~= FORMAT then o.old = true end   -- made again from the properties
      for _, r in ipairs(d.rows) do
        if type(r) == "table" and r.i and type(r.n) == "string" and type(r.a) == "string" and type(r.d) == "string" then
          r.ch, r.s = ch, norm_sig(r.s)
          if r.k == "W" and type(r.b) == "string" then upgrade_weapon_row(r) end
          if ch == me then stored[tonumber(r.i)] = r else o.rows[#o.rows + 1] = r end
        end
      end
      data_ver = data_ver + 1
    end
    if o then o.left = o.left - 1; if o.left == 0 then char_loaded(ch) end end
  elseif sub(id, 1, 3) == "pp|" then
    loading.waiting = loading.waiting - 1
    local _, _, ch = split3(id)
    local o = others[ch]
    local d = e.ok and type(e.data) == "table" and e.data or nil
    if o and d and type(d.items) == "table" then
      SB.cache(ch, d.items)
      local byid = nil
      if o.old then
        byid = {}
        if ch == me then for rid, r in pairs(stored) do byid[rid] = r end else for _, r in ipairs(o.rows) do byid[tonumber(r.i)] = r end end
      end
      for _, x in ipairs(d.items) do
        local xid = type(x) == "table" and tonumber(x.i) or nil
        if xid then
          x.i = nil
          if ch == me and not own_props[xid] then own_props[xid] = x end
          if byid and byid[xid] then rebuild[#rebuild + 1] = {row = byid[xid], props = x, ch = ch} end
        end
      end
    end
  elseif id == "ss" then
    local d = e.ok and type(e.data) == "table" and e.data or nil
    shared.read = true
    if d and not shared.touched and type(d.flt) == "table" then
      local f = d.flt
      st.flt = {text = type(f.text) == "string" and f.text or "", cats = type(f.cats) == "table" and f.cats or {},
        subs = type(f.subs) == "table" and f.subs or {}, order = type(f.order) == "table" and f.order or {}, dbl = f.dbl == true or nil,
        worn = f.worn == true or nil}
      if type(d.sort) == "string" then st.sort = d.sort end
      one_category(st.flt)
      search_ver = -1; search = nil; flt_ver = flt_ver + 1
    end
  elseif id == "ex_ls" and export then
    for _, name in ipairs(type(e.names) == "table" and e.names or {}) do
      if type(name) == "string" and starts(name, prefix) then
        local n = tonumber(sub(name, #prefix + 1))
        if n and n > export.parts then request({service = "profiles", operation = "delete", group = "Export", name = name}) end
      end
    end
    export = nil
  elseif id == "sv_idx" then
    if e.ok == false then notes.all = "Could not save: " .. sub(tostring(e.error or ""), 1, 100)
    elseif starts(notes.all, "Could not save") then notes.all = "" end
  end
  if loading.waiting <= 0 and not loading.list and not own_loaded then
    own_loaded = true
    -- the saved items are the base set: shown at once, updated as the client reports them
    for sid, r in pairs(stored) do if not live[sid] then live[sid] = r; r.ch = me end end
    data_ver = data_ver + 1
  end
  if own_loaded then
    -- items saved earlier: rebuild against them once
    for lid, r in pairs(live) do if r.x and stored[lid] and not stored[lid].x and stored[lid].s == r.s then live[lid] = stored[lid]; stored[lid].ch = me; data_ver = data_ver + 1 end end
  end
end

-- Rows of an older format, made again from their saved properties (a few per update).
local ROW_FIELDS = {"n", "k", "a", "b", "c", "d", "g", "w", "o", "oa", "om", "q", "x", "z", "s"}
local function rebuild_some()
  local n = 0
  while #rebuild > 0 and n < REBUILD_PER_TICK do
    local job = table.remove(rebuild)
    local row = job.row
    local rec = rec_of(job.props, row)
    local fresh = build_row(rec, item_of(rec), row.x == nil)
    for _, k in ipairs(ROW_FIELDS) do row[k] = fresh[k] end
    n = n + #rec.spell_names / 3
    row.ln, row.lch, row.la, row.lb, row.lc, row.ld, row.h, row.skt, row.skv, row.skc = nil, nil, nil, nil, nil, nil, nil, nil, nil, nil
    resave[job.ch] = true
    n = n + 1
  end
  if n > 0 then data_ver = data_ver + 1 end
  if #rebuild == 0 and next(resave) then
    for ch in pairs(resave) do
      local o = others[ch]
      if o then o.old = nil end
      if ch == me then save_due = true; live_changed_at = now else save_other(ch) end
    end
    resave = {}
  end
end

-- JSON export: the items listed (the current filter and sort), Export/<server>_<n> (200 items
-- each) and Export/<server>. Written a part per update.
function export_all()
  if export then return end
  local list = {}
  for k, r in ipairs(result.rows) do list[k] = r end
  export = {chars = {{"", list}}, ci = 1, ri = 1, parts = 0, count = 0}
  notes.search = "Exporting..."
end
local function export_step()
  local x = export
  if x.done then return end
  local items = {}
  while #items < PART_ROWS and x.ci <= #x.chars do
    local rows = x.chars[x.ci][2]
    local stop = math.min(#rows, x.ri + PART_ROWS - #items - 1)
    for k = x.ri, stop do
      local r = rows[k]
      items[#items + 1] = {character = r.ch, worn = r.e == 1, name = r.n, type = r.a, effect = r.b, info = r.c, details = r.d, description = r.z}
    end
    if stop >= #rows then x.ci, x.ri = x.ci + 1, 1 else x.ri = stop + 1 end
  end
  if #items > 0 then
    x.parts, x.count = x.parts + 1, x.count + #items
    request({service = "profiles", operation = "save", group = "Export", name = prefix .. x.parts, data = {server = server, part = x.parts, items = items}})
  end
  if x.ci > #x.chars then
    x.done = true
    request({service = "profiles", operation = "save", group = "Export", name = safe(server),
      data = {server = server, saved = math.floor(now), count = x.count, parts = x.parts}})
    request({id = "ex_ls", service = "profiles", operation = "list", group = "Export"})
    notes.search = "Exported " .. commas(x.count) .. " items to Profiles\\global_inventory\\Library\\Export"
  end
end

-- Callback -------------------------------------------------------------------------------------
return function(s, p)
  local out = {}
  now = tonumber(s.unix_time) or tonumber(s.time) or 0

  if not st then
    local saved = type(s.state) == "table" and s.state or {}
    st = {auto_off = saved.auto_off == true or nil, sort = type(saved.sort) == "string" and saved.sort or "cur",
      best_limit = type(saved.best_limit) == "string" and saved.best_limit or nil}
    local f = type(saved.flt) == "table" and saved.flt or {}
    st.flt = {text = type(f.text) == "string" and f.text or "", cats = type(f.cats) == "table" and f.cats or {},
      subs = type(f.subs) == "table" and f.subs or {}, order = type(f.order) == "table" and f.order or {}, dbl = f.dbl == true or nil,
        worn = f.worn == true or nil}
    one_category(st.flt)
    st.suits = type(saved.suits) == "table" and saved.suits or {}
    local b = type(saved.sb) == "table" and saved.sb or {}
    local sets = {}
    for _, v in ipairs(type(b.sets) == "table" and b.sets or {}) do if tonumber(v) and #sets < 2 then sets[#sets + 1] = math.tointeger(tonumber(v)) or 0 end end
    st.sb = {sets = sets, prim = tonumber(b.prim) and (math.tointeger(tonumber(b.prim)) or nil) or nil, crit = (b.crit == "CD" or b.crit == "CDR") and b.crit or nil,
      aux = b.aux == true or nil, wep = b.wep == true or nil, from = b.from == true or nil}
    st.slv = type(saved.slv) == "table" and saved.slv or {}
    st.prio = type(saved.prio) == "table" and saved.prio or nil
    st.prio_off = type(saved.prio_off) == "table" and saved.prio_off or nil
    SB.apply_prio()
  end
  if me == "" and type(s.character_name) == "string" and s.character_name ~= "" and type(s.server) == "string" and s.server ~= "" then
    me, server = s.character_name, s.server
    prefix = safe(server) .. "_"
    load_all()
  end

  for _, e in ipairs(s.events or {}) do
    if e.type == "result" then result_event(e) else handle(e) end
  end

  -- This character's items: only when the inventory or an appraisal changed.
  if me ~= "" and type(s.inventory) == "table" then
    local ir, ar = tonumber(s.inventory_revision), tonumber(s.appraisal_revision)
    if ir ~= inv_rev then inv_changed_at = now end
    if ir ~= inv_rev or ar ~= app_rev then
      inv_rev, app_rev = ir, ar
      -- A check in progress finishes first: the appraisal revision can change every update (nearby
      -- monsters being assessed), and restarting each time never reached the end of a large inventory.
      -- (a small inventory is checked in one update, so it simply starts again)
      if coll and #s.inventory > COLLECT_PER_TICK then coll_next = s.inventory else coll = {inv = s.inventory, i = 1, seen = {}, cont = {}}; coll_next = nil end
    end
    if not coll and coll_next then coll = {inv = coll_next, i = 1, seen = {}, cont = {}}; coll_next = nil end
  end
  player_id = tonumber(s.player) or player_id
  if type(s.skills) == "table" and (not skills or now - skills_at >= 5) then
    skills, skills_at = s.skills, now
    local t = {}
    for sid, sk in pairs(skills) do if type(sk) == "table" and (tonumber(sk.training) or 0) >= 2 then t[#t + 1] = tostring(sid) end end
    table.sort(t); skills_sig = table.concat(t, ",")
  end
  SB.tick(s, own_loaded and loading.waiting <= 0 and not loading.list, #reqs, request)
  -- checking and building take turns, so items are built while checks keep coming
  local both = coll and next(pending_build) and own_loaded
  -- (this character's items are checked once the saved characters are read: they can't be built before)
  local built = false
  if coll and own_loaded and not (both and build_turn) then collect_step() elseif next(pending_build) and own_loaded then build_some(); built = true
  elseif #rebuild > 0 or next(resave) then rebuild_some(); built = true end
  if both then build_turn = not build_turn end
  -- Import runs every update (checks can come every update near monsters), with fewer rows when rows were built
  local importing = IM.busy()
  if importing then IM.step(built and IMPORT_SHARED or IMPORT_PER_TICK) end

  -- Saved items that never appeared: dropped once the inventory has been quiet for QUIET seconds
  -- and their pack has items (a pack the client hasn't filled yet keeps its saved items).
  if own_loaded and seen_cont and not coll and not next(pending_build) and now - inv_changed_at >= QUIET and reconciled ~= inv_rev then
    reconciled = inv_rev
    for id, r in pairs(live) do
      if not live_sig[id] then
        local pc = r.p
        if pc == nil or pc == 0 or pc == player_id or seen_cont[pc] then
          live[id], own_props[id], needs_props[id] = nil, nil, nil
          data_ver = data_ver + 1; live_changed_at = now; save_due = true
        end
      end
    end
  end

  -- One background appraisal per second.
  local target = next_appraisal()
  if target then out.action, out.target = "identify", target end

  -- Save after changes settle.
  if save_due and own_loaded and not next(pending_build) and live_changed_at and now - saved_at >= SAVE_GAP
    and (now - live_changed_at >= SAVE_DELAY or now - saved_at >= SAVE_MAX_WAIT) then
    save_own()
  end
  -- The search (filter, boxes, sort), shared by all characters: saved 2 s after a change.
  if shared.due and now - shared.due >= 2 then
    shared.due = nil
    request({service = "profiles", operation = "save", group = "Settings", name = "Search", data = {flt = st.flt, sort = st.sort}})
  end

  -- Search. The sorted order is rebuilt when the sort changed (at once) or the data changed (lists under 1,000
  -- items at once; otherwise every 2 s while data changes, every 5 s while items are still being built, every 3 s
  -- while saved characters are read). A filter change searches the order there is at once; a new order is
  -- searched again when it's ready.
  local sort = st.sort or "cur"
  local gap = next(pending_build) and 5 or 2
  if loading.waiting > 0 or loading.list then gap = 3 end
  if order.rows and #order.rows < 1000 then gap = 0.5 end
  if ojob and ojob.sort ~= sort then ojob = nil end
  if not ojob and (order.sort ~= sort or (order.ver ~= data_ver and now - order.at >= gap)) then start_order() end
  if not search and order.rows and order.sort == sort and search_ver ~= order.ver then start_search(search_ver == -1) end
  local busy = built or importing or loading.list or loading.waiting > 0 or next(pending_build) ~= nil or SB.busy()
  local budget = busy and SEARCH_SHARED or (search_ver == -1 and view == "search") and SEARCH_USER or SEARCH_WORK
  if search then budget = budget - step_search(budget) end
  if ojob and budget > 0 then
    budget = budget - step_order(budget)
    -- (a sort change: the new order is searched in the same update when there's room)
    if not ojob and not search and search_ver == -1 and budget > 0 and workavailable() then start_search(true); step_search(budget) end
  end
  if not search and not ojob and not coll and not next(pending_build) and prep_ver ~= data_ver then
    -- idle: give rows their search text, so the first text search is quick (until every row has it)
    local n = 0
    for _, o in pairs(others) do
      for _, r in ipairs(o.rows) do if not r.h then low(r); n = n + 1; if n >= PREP_PER_TICK then break end end end
      if n >= PREP_PER_TICK then break end
    end
    if n < PREP_PER_TICK then prep_ver = data_ver end
  end

  if save_job and #reqs < 8 then save_step() end
  if export and #reqs < 8 then export_step() end

  -- at most 4 requests per update, batches at least 0.5 s apart (the client's service limit)
  local clock = tonumber(s.time) or now
  if #reqs > 0 and clock - last_batch >= 0.5 then
    local batch = {}
    -- at most one large save and one large read (Items, Props or Export) a batch: the client limits the whole
    -- requests output to 32,768 values and 256 KiB of text, and a read's rows are handled in the update it arrives
    local saves, reads = 0, 0
    while #reqs > 0 and #batch < 4 do
      local r = reqs[1]
      local large = r.service == "profiles" and (r.group == "Items" or r.group == "Props" or r.group == "Export" or r.group == "Import")
      if large and r.operation == "save" then if saves >= 1 then break end saves = saves + 1
      elseif large and r.operation == "read" then if reads >= 1 then break end reads = reads + 1 end
      table.remove(reqs, 1); batch[#batch + 1] = r; inflight[r.id] = r
    end
    out.requests, last_batch = batch, clock
  end

  -- Window: only when what it shows changed.
  local err = type(s.error) == "string" and s.error or ""
  if err ~= "" then notes.all = sub(err, 1, 160) end
  -- (a search that finds the same rows doesn't send the window again: the page's rows are compared, not the result)
  if view == "search" and (shown_result ~= result or shown_page ~= page) then
    shown_result, shown_page = result, page
    local p = {}
    for k = (page - 1) * PAGE_ROWS + 1, math.min(#result.rows, page * PAGE_ROWS) do
      local r = result.rows[k]
      p[#p + 1] = r.ch .. "|" .. tostring(r.i) .. "|" .. r.n .. "|" .. r.a .. "|" .. r.b .. "|" .. r.c .. "|" .. r.d .. "|" .. tostring(r.x) .. "|" ..
        tostring(r.ic) .. "|" .. tostring(r.ov) .. "|" .. tostring(r.un) .. "|" .. tostring(r.e) .. "|" .. tostring(r.z)
    end
    shown_sig = #result.rows .. "\1" .. table.concat(p, "\1")
  end
  local key = table.concat({view, page, tostring(selected and selected.i), tostring(selected and selected.ch), page_note(), status_text(),
    view == "search" and shown_sig or tostring(result), flt_ver, st.sort or "", tostring(st.auto_off), view == "chars" and math.floor(now / 60) or 0}, "#")
  key = key .. "#" .. SB.key(view) .. (view == "settings" and ("#" .. tostring(prio_sel)) or "")
  -- (these pages follow item changes at most every 5 s; their own clicks show at once)
  if data_ver ~= slow_ver and now - slow_at >= 5 then slow_ver, slow_at = data_ver, now end
  if view == "chars" or view == "suit" or view == "sum" then key = key .. "#" .. slow_ver .. "#" .. tostring(skills_sig) end
  -- (a filter or sort change: the window is sent with the results, unless the search takes more than this update)
  local hold = view == "search" and search_ver == -1 and asked_search == now and ui_key ~= nil
  -- (and not when this update's Lua steps are nearly used up: it's sent in the next update)
  if key ~= ui_key and not hold and workavailable() then
    if not ui_key then out.status = "" end
    out.ui = view == "chars" and build_chars() or view == "suit" and SB.build_suit(top_row(SB.status(), "suit"))
      or view == "sum" and SB.build_sum(top_row(me .. ": Character Summary", "sum"), s.char_ints)
      or view == "settings" and build_settings() or build_search()
    if out.ui[1] and out.ui[1].id == "top" then local t = out.ui[1].children; out.ui[1] = t[2]; table.insert(out.ui, 1, t[1]) end
    ui_key = key
  end

  if dirty_state then out.state = {auto_off = st.auto_off, sort = st.sort, flt = st.flt, suits = st.suits, sb = st.sb, slv = st.slv, prio = st.prio, prio_off = st.prio_off, best_limit = st.best_limit}; dirty_state = false end
  return out
end
