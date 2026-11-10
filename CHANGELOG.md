# Changelog

## 1.6.2

- Suit Builder: the set lists are **Primary** (always a set, or No Set) and **Secondary** ("-" for none).
- Cantrip priority: the default order changed; shorter names (Run, Jump, Summoning, Melee Defense, Magic Defense, Missile Defense).

## 1.6.1

- Cantrip priority (Settings) lists every skill. Click a line, then Up, Down, Bottom or Disable. A disabled cantrip isn't missing and isn't filled. Tinkering, Salvaging, Loyalty and Leadership are disabled at first.
- Suit Builder: set lists with No Set and all 18 loot armor sets (in place of the set boxes).
- Suit Builder: a double is the same cantrip at the same level (two legendary or two epic); one legendary and one epic is no longer counted as a double.

## 1.6.0

- Faster filters and searches. All items are kept in the current sort order, so a filter, box or text change is one quick check of the items, without sorting again. With a category ticked, only that category's items are checked.
- A filter or text change usually shows its results in the update that gets the click, and the window is sent once, with the results. A search that takes longer shows "Searching..." and the items found so far.
- A new sort is made in the background and shown when ready. Going back to the first sort, or changing a column between A-Z and Z-A, is quicker.
- Updates every 0.5 s (was 1 s).

## 1.5.6

- The Suit Builder row lines up with the top buttons: the suit list under Global Inventory and the suit name under Suit Builder (same width as the buttons), Save and Delete beside the name, Clear Armor ending under Characters, and Fill Armor and Best Fill (a little wider) under Settings.
- The top buttons and status line sit a few pixels higher and further left (the page uses fewer controls, so the Suit Builder stays inside the client's 256-control limit).

## 1.5.5

- The filter row lines up with the top buttons: the Filter box under Global Inventory and Suit Builder, Reset to Add to suit under Character Summary and Characters, and the slot list under Settings (same width as the buttons).

## 1.5.4

- Inputs, buttons and drop downs keep fixed positions when the window is wider: the Filter box (420), the Suit Builder's suit list and suit name (230 each), and the page buttons under the list no longer stretch.

## 1.5.3

- The Add to suit slot list has a fixed width (170), blank until a slot is picked, so its list stays inside the window.
- The top buttons are on the left.

## 1.5.2

- Characters and Settings use the same top row as the other pages, with their button highlighted; the Back button is gone. Characters shows "Saved characters on <server>" in the status line, with Reload and Import under it; Settings shows "<character>: Settings".

## 1.5.1

- Best Fill: the time limit now counts from when it starts checking combinations. Before, gathering and sorting the candidates used most of the 30 s (at 1 s updates often all of it), so very few combinations were checked.
- Best Fill and Fill Armor do more work per update (gathering, the quick pass, sorting and the search), still well under the client's limit. In the tests Best Fill checks about 6 times as many combinations in its time.
- Settings: **Best Fill time limit** (30 s, 1 min, 2 min, 5 min), saved per character. The Best Fill tooltip shows the time chosen.

## 1.5.0

- Character Summary: other spells of worn items that raise a skill or attribute (quest items, rare jewelry), such as Apprentice Messenger's Sprint Aptitude on the Dragon Lord's Tunic, are listed at the bottom with the amount and the item.
- Settings: **Cantrip priority**, a list under a drop down with Up, Down and Bottom on each line and Reset. Fill Armor and Best Fill follow it. Saved per character; the default order fills as before.
- Global Inventory: **Worn** box after Doubles, unticked by default; worn items are hidden unless it is ticked.
- Tooltips for Fill Armor and Best Fill.
- The status line is under the top buttons, with the page's message on the right of the same line. Each message shows only on its own page (for example the Fill result only on Suit Builder).

## 1.4.3

- The list no longer searches again every few seconds when nothing visible changed. After some actions (casting, mana stones) the client drops the appraisals of worn items and appraises them again; a saved item is no longer rebuilt for that, and a rebuilt item that is the same doesn't count as a change.
- "Searching..." shows only for a search you started that takes more than a second, not for background updates.

## 1.4.2

- A filter or sort clicked while a search was still running was ignored. The search now starts again with the new filters.
- Searches of a few thousand items finish in the update after the click (they used to take several seconds above 1,000 items). Larger lists, and searches while items are built, imported or read, still take a few updates.
- The window is sent only when what it shows changed: a search that finds the same rows doesn't send it again, the "appraising" count updates every 5 s, and the Characters, Suit Builder and Character Summary pages follow item changes at most every 5 s (their own clicks show at once).
- Skills are read every 5 s instead of every update.
- Aetheria: the surge filter reads "Destruction Surge" (the set filter stays "Destruction").

## 1.4.1

- Import no longer waits for a quiet moment. Near monsters or players the inventory is checked every update, and Import never got a turn (it stayed on "Reading Library\Import..."). It now runs every update, with fewer rows in updates that also build items.

## 1.4.0

- **Import** (Characters page): adds characters from a Virindi Global Inventory database. `VGI_Import.html` converts the database to a file for `Library\Import`; Import builds the items with the same code as appraised items and saves them. Characters already saved, and the character logged in, are skipped. Each imported character is updated the next time it logs in.

## 1.3.5

- Fixed "Structured output exceeds depth/node limit" when saving a large, fully appraised inventory: one large file is saved at a time (the client limits what a plugin sends in one update).
- Fixed "plugin instruction budget exceeded" after a restart: one large file is read at a time, and the character's own items are checked once the saved characters are read.

## 1.3.4

- Characters with large inventories are read again near monsters. A check of the inventory now finishes before the next one starts (assessing nearby monsters changes the appraisal count every update, and each change used to start the check over, so it never reached the end of an inventory over 300 items).

## 1.3.3

- Add to suit: the slot list stays blank until a slot is picked for the selected item; the button works once a slot is picked.

## 1.3.2

- Set Bonus Summary is now Character Summary.
- Global Inventory: hover an item's icon for its full description.
- Fill Armor and Best Fill: when no legendary piece helps, they fill with epic, then major, moderate and minor cantrips.
- Updates once a second instead of twice (clicks still answer at once). Less work between updates: the appraisal count and the search text are only worked out again after changes, and active spells are read every 5 seconds.

## 1.3.1

- The top buttons are always the same, in the same order and width; the page shown is highlighted.
- Messages show under the top row, in the same text size.
- Suit Builder: Dedication set box; CD and CDR on their own row once a set is ticked; cantrips listed legendary first, then down the tiers.
- Society Band and Locket spells show in the numbers again (they were left out for items with a Vitality property).
- Set Bonus Summary: Essence and Warrior's Vitality show the active spell (for example Essence Glutton) and the item it comes from.
- The window is no longer sent again whenever the character's spells change (only the Set Bonus Summary uses them).

## 1.3.0

- Suit Builder: 17 fixed slots on one page (9 armor, 2 clothes, 6 jewelry). Cloak, aetheria, weapon and shield count only when "Include Aetheria and Cloak stats" or "Include weapon + shield stats" is ticked.
- Saved suits per character: list, name, Save and Delete. Items in a saved suit show "Suit: name" in Details.
- Click an item's icon to remove it. Clear Armor removes the armor pieces.
- Set and rating choices (No Set, Adept, Defender, Dexterous, Hearty, Wise; CD or CDR), Fill Armor and Best Fill.
- Add to suit on the Global Inventory page, with reduction tool slots for multi-slot loot armor.
- Missing cantrips: legendary only, in priority order; tinkering, salvaging, loyalty and leadership left out. "Doubles" is now "Double cantrips".
- Numbers and totals show their heading name when hovered. Rating spells count (Rare, Gauntlet, Paragon's and sigil spells).
- Society Band, Society Locket and Heroic set spells, by item level.
- Set Bonus Summary page.
- The top buttons use the same text size as Reset.
- "Dexterous" spelled correctly.

## 1.2.2

- Suit Builder: the headings line up (every column has a total cell).

## 1.2.1

- Export JSON is beside Reset and writes the items listed (current filter and sort).
- One category at a time (plus Doubles); sub-filters can still be combined.
- Suit Builder: the same top row as the first page (with a Global Inventory button), a filter box and Weapons, Armor, Jewelry and Aetheria boxes; heading tooltips; ordered helmet, armor, clothes, jewelry, cloak, aetheria, weapon; no totals for Work, Tinks and Cantrips; a Doubles line for cantrips worn more than once; 18 items on a page.

## 1.2.0

- Suit Builder: worn items with D, DR, CD, CDR, V, HB, MD, Work, Tinks and Cantrips, totals, duplicate cantrips marked, and the attributes and trained skills that no worn cantrip covers.
- Named aetheria (for example Dragon's Rage Aetheria) are listed. Aetheria ratings show in Info.
- Saves refused by the client's service rate limit are sent again, and the error no longer stays on screen.
- Worn items are appraised first.

## 1.1.1

- The Info header always reads "Info". With weapons listed it cycles the sort (OD, attack, melee defense, workmanship); otherwise it sorts by the Info text, A-Z and Z-A.
- The slayer is back in Details with the full word ("Ghost Slayer"). Items saved by 1.0.3 and 1.1.0 are shown the same way.

## 1.1.0

- Saved items are the base set: shown at login and updated as the client reports them. An item that doesn't appear is dropped after 30 seconds without inventory changes, once its pack has items.
- Saving happens at least once a minute during long appraisal runs.
- Saved items match again after a restart (whole numbers in the saved signature).
- Item properties are saved, so later versions can show items differently without appraising again. Items saved by 1.0 are appraised once more.
- Info for weapons: OD, attack and melee defense, and workmanship. The Info header cycles the sort.
- Acid Rend is AcR.
- The filter, ticked boxes and sort are shared by all characters.
- Settings: Export to JSON.

## 1.0.3

- Weapons: Slayer is first in Effect instead of in Details.
- Short rend names: NR, SR, PR, BR, CR, LR, FR. Items saved earlier are shown the same way.
- Effect column wider.

## 1.0.2

- Every other row has a faint shade.
- Clicking an item shows its full description in chat (any character's item).
- Each cell's tooltip shows only that cell's text.
- Worn items show "(worn)" beside the character name.

## 1.0.1

- Larger text (15) and item icons (24) in the item list, column headers, filter checkboxes and status line.
- Less padding around rows and cells.
- Wider columns for the larger text.

## 1.0.0

- First version: saves each character's items, background appraisal, and a search window for all saved characters on the server with Oracle of Dereth's columns, categories, sub-filters, Doubles and text search.
