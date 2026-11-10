# Global Inventory

A global inventory and suit builder plugin for the AC:Unreal client. When the plugin is enabled, it will read and appraise all items on the character and save them to a database. Items from each character can then be filtered, searched or added to a suit building tool. The categories, filters and columns follow Oracle of Dereth's Inventory window. Using the included HTML tool, you can convert your existing Virindi Global Inventory database found at VirindiPlugins\VirindiGlobalInventory\_Server.db

<img width="1253" height="899" alt="image" src="https://github.com/user-attachments/assets/904125b0-b154-4aa4-92f4-3249513b0ef0" />
<img width="803" height="269" alt="gi_new1" src="https://github.com/user-attachments/assets/80059cc9-96ba-4f11-9c44-334d1e8f9335" />
<img width="623" height="515" alt="gi_new5" src="https://github.com/user-attachments/assets/11c4233d-4566-4289-b895-8bd6582db8ce" />
<img width="613" height="531" alt="gi_new6" src="https://github.com/user-attachments/assets/a6ba81c5-3e0b-409b-b07d-54dc72cde397" />
<img width="450" height="659" alt="gi_new2" src="https://github.com/user-attachments/assets/75a8e0ef-22db-4867-82ba-38730f4bea9a" />
<img width="458" height="288" alt="gi_new3" src="https://github.com/user-attachments/assets/558aed3f-7270-46c2-a4db-b690f8f4348c" />
<img width="457" height="360" alt="gi_new4" src="https://github.com/user-attachments/assets/85959884-9997-4007-9191-97b76f98f013" />

## Requirements

- AC:Unreal client v146 or newer.

## Install

1. Unzip into `ACUnreal\Saved\ClientPlugins\Installed`. The path ends in `Installed\Global_Inventory\plugin.json`.
2. Open the plugin menu, press **Refresh**, then **Enable** Global Inventory.
3. Log in each character once with the plugin enabled and wait until all items are appraised and the characters database is saved.
4. Alternately, you can import your existing Virindi Global Inventory database.

## Update

Replace the files in `Installed\Global_Inventory` and press **Refresh**. Saved items, suits and settings are kept.

## Global Inventory

- Columns: Character, Item Name, Type, Effect, Info and Details. Click a header to sort. With weapons listed, the Info header cycles OD, attack, melee defense and workmanship.
- Categories: Weapons, Armor, Clothing, Jewelry, Cloaks, Summons, Aetheria, Salvage and Others. Only one selection can be made at a time, with exception of Doubles. The ticked category shows its sub-filters (armor slots and sets, weapon types and elements, aetheria colors and surges, and so on).
- **Doubles**: items with two or more cantrips of their highest tier.
- **Worn**: shows worn items (hidden while unticked).
- Filter box: every word must appear; "quoted phrase"; `word*2` means at least twice.
- Click a row to show the item's description in chat. An item on the logged-in character is also selected. Hover a cell for its full text.
- **Export JSON** writes the items listed to `Profiles\global_inventory\Library\Export`.
- **Add to suit**: select an item, pick a slot in the list, press the Add button.
- Select an item and manually add it to a suit by using the drop down tailoring menu.
- The filter, ticked boxes and sort are shared by all characters.

## Suit Builder

The suit builder page is a tool where you can build and save different suits using items from the global inventory, it can also automatically fill empty slots using a set of constraint rules. Filling of the empty slots is based on the Primary and Secondary set type selections and CD/CDR filters, along with the characters missing cantrips. Missing cantrips are determined by reading the characters specialized and trained skills, and comparing them against active cantrip spells and the cantrip priority table. Triple and double rated pieces that fit the missing cantrips will always be considered first, and in cases where they do not fit, a list of missed opportunity items will be displayed (future). This is followed by rated single legendary pieces and then finally non-rated single legendary pieces. The reading will always start with Legendary, but the same order will follow with Epic, Major, etc. if available.

17 slots: 9 armor, shirt, pants, necklace, trinket, 2 bracelets and 2 rings. Slots are initially filled with your worn suit.

- Columns: D, DR, CD, CDR, V, HB, MD, Work, Tinks and Cantrips. The last row totals D to MD.
- Click an item's icon to remove it. **Clear Armor** removes the 9 armor pieces.
- Saved suits: pick one in the dropdown, or type a name and **Save**. **Delete** removes the one shown.
- **Primary** and **Secondary**: Primary must be No Set or one of the 18 loot armor sets. With only the primary set selected, all 9 slots will be filled with the selection; With both, the primary selection gets 5 pieces and the secondary 4. **CD** or **CDR** picks the rating to prefer and do not need to be selected.
- **Fill Armor** fills the empty armor slots one piece at a time: pieces adding the most missing legendary cantrips first, then epic, major and lower.
- **Best Fill** checks combinations for the suit that fills the most slots and covers the most missing cantrips, in priority order. It stops at the time limit in Settings and keeps the best suit found.
- Multi-slot loot armor can go in any slot a reduction tool can be used on.
- Not used: attuned items on other characters and items saved in suits, unless "Fill armor from existing suits" is ticked in the settings below.
- Missing cantrips: legendary cantrips for attributes, wards and trained skills that no item covers, in priority order.
- Double cantrips: the same cantrip at the same level on two items, for example `Legendary Strength (2)`.
- "Include Aetheria and Cloak stats" and "Include weapon + shield stats" add stats from those items to the totals.

## Character Summary

A list of cantrips and set bonuses active on the character. Duplicate cantrips are displayed with a `(2)`.

## Characters

Each saved character with its item count and last update. **Remove** deletes a character's saved items. **Import** reads files made by `VGI_Import.html`.

### Import from Virindi Global Inventory

1. Open `VGI_Import.html` (in the plugin folder) in a browser. It works offline and the database isn't sent anywhere.
2. Choose the database, for example `VirindiPlugins\VirindiGlobalInventory\_Conquest.db`, and save the file it makes.
3. Move the file to `Saved\ClientPlugins\Profiles\global_inventory\Library\Import`.
4. Open Characters and click **Import**.

Characters already saved, and the character logged in, are skipped. Imported items show as Virindi last saved them until that character logs in with the plugin enabled.

## Settings

- **Appraise items automatically**: one item per second, only items not saved yet.
- **Best Fill time limit**: 30 s, 1 min, 2 min or 5 min.
- **Cantrip priority**: the order Fill Armor and Best Fill add missing cantrips in. Click a line, then **Up**, **Down**, **Bottom** or **Disable**. A disabled cantrip isn't missing and isn't filled. Tinkering, Salvaging, Loyalty and Leadership are disabled at first. **Reset** restores the default. Saved per character.

## Limits

- A character's items are updated only when that character logs in.
- Packs and worn equipment only; not house storage or chests. At most 1,024 items per character (client limit).
- OD is not shown for worn weapons (their values include active buffs).
- Gems don't show "Unlimited use" (the client doesn't send it).

## Files

Under `Saved\ClientPlugins\Profiles\global_inventory\Library`:

- `Chars`, `Items`, `Props`: each character's item count, rows and item properties.
- `Settings\Search.json`: the shared filter and sort.
- `Export`: the JSON export.
- `Import`: files made by `VGI_Import.html`.

## Permissions

| Permission | Used for |
|---|---|
| data | the character's inventory, skills, level and active spells |
| identify | background appraisals |
| ui | the window, selecting items, item descriptions in chat |
| state | settings, saved suits and seen item levels |
| profiles | saving and reading items, the shared search and the export |

## Credits

- Item columns, categories, filters, weapon values, the cantrip table and the Character Summary from Oracle of Dereth (by Advis).
- Set spells, rating spells and spell icons from the client's spell table (portal.dat). Reduction tool rules from ACE.
- AC:Unreal client and plugin framework by Thwargle.
