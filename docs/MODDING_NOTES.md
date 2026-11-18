# Project Zomboid B42 modding notes

Findings gathered while building this mod against **Build 42.22.2** (revision `3d39148846`, Java 25).
Things marked *(verified)* were read from the game's Lua or decompiled from `projectzomboid.jar`. Re-check them after a big game update — see [Updating after a game patch](#updating-after-a-game-patch).

## 1. Paths

| What | Where |
|---|---|
| Game install | `C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid\` |
| Game Lua (reference) | `<game>\media\lua\{shared,client,server}\` |
| Game scripts (recipes, items) | `<game>\media\scripts\` — B42 recipes live in `scripts\generated\entities\**\craftRecipes\*.txt` and others |
| Game Java | `<game>\projectzomboid.jar` |
| Game version | `%USERPROFILE%\Zomboid\version.txt` |
| Local mods | `%USERPROFILE%\Zomboid\mods\<ModFolder>\` |
| Log (prints, Lua errors) | `%USERPROFILE%\Zomboid\console.txt` |
| Workshop mods (good real-world examples) | `<steam>\steamapps\workshop\content\108600\<id>\mods\` |

## 2. B42 mod structure

```
<ModFolder>/
  42/                      version folder (can also be e.g. 42.20.1/ for version-specific overrides)
    mod.info
    poster.png
    media/
      sandbox-options.txt
      lua/{shared,client,server}/...
  common/                  shared across versions; must exist (can be empty)
    media/lua/shared/Translate/EN/*.json
```

`mod.info` keys used: `name`, `id`, `poster`, `description` (repeatable line by line), `versionMin`. Other seen keys: `author`, `icon`, `require=\ModA,\ModB,`, `incompatible=ModX,`.
The **`id`** is what saves and server configs reference — changing it later disables the mod in existing saves. The folder name does not matter.

### Lua load order
`shared` → `client` → `server`. In single player **all three** load; a dedicated server loads `shared` + `server`; an MP client loads `shared` + `client` (+ `server` files are also present on client in practice, but don't rely on server-only logic running there).
`require "Some/Path"` resolves relative to any of the three roots (no `.lua`). Use it to make sure the vanilla file you patch is loaded before your patch.

### Translations (B42 = JSON)
Files are JSON objects in `Translate/<LANG>/<Category>.json`, e.g. `Sandbox.json`, `IG_UI.json`. Key prefixes matter:
- `Sandbox_<translation>` / `Sandbox_<translation>_tooltip` for sandbox options, `Sandbox_<page>` for the page title.
- `IGUI_...` for UI. `getText("Key", arg1, ...)` substitutes `%1`, `%2`. Tooltips accept `<br>`.

### Sandbox options (per save, synced to MP clients)
`media/sandbox-options.txt`:
```
VERSION = 1,
option MyNamespace.MyOption
{type = boolean, default = true, page = MyNamespace, translation = MyOption,}
option MyNamespace.Percent
{type = double, min = 0, max = 100, default = 15, page = MyNamespace, translation = Percent,}
```
Types: `boolean`, `integer`, `double` (`min`/`max`/`default`), also `enum`/`string` exist. Read in Lua as `SandboxVars.MyNamespace.MyOption`. Values are **not** available at `OnGameBoot`; they are by `OnInitGlobalModData` / `OnGameStart`. Always keep Lua-side defaults.

**Changing sandbox options while a single-player game runs** *(verified)*:
- `getSandboxOptions():set("NS.Option", value)` changes the live value, but does **not** refresh the Lua `SandboxVars` table — call `getSandboxOptions():toLua()` afterwards.
- The world save (`GameWindow`, same method that fires `OnSave`) writes `SandboxOptions.instance` to `map_sand.bin`, so the change persists with the save.
- Vanilla UI for this: `ISServerSandboxOptionsUI` (`client/ISUI/AdminPanel/`), opened from the debug menu (SP) or admin panel (MP). Its page list comes from `ServerSettingsScreen.getSandboxSettingsTable()` (mod pages: `{name = "Sandbox_<page>" translated, settings = {{name = "NS.Option"}, ...}}`; entry `[1]` gets replaced by the Presets page). `settingsFromUI` calls `getSandboxOptions():set` when `not isClient()`; MP uses `options:sendToServer()`. This mod derives `ARR_SettingsUI` from it and filters the table to its own page.

The alternative, `PZAPI.ModOptions` (`media/lua/client/PZAPI/ModOptions.lua`), is client-only, global across saves, and not synced — fine for UI preferences, not for gameplay balance. API: `local o = PZAPI.ModOptions:create(id, title)`, then `o:addTickBox(id, name, value, tooltip)`, `addSlider(id, name, min, max, step, value, tooltip)`, `addComboBox`, `addTextEntry`, `addKeyBind`, `addButton(id, name, tooltip, onclick, target, ...)`, `addDescription(text)`, `addTitle`, `addSeparator`; read with `o:getOption(id):getValue()`. Values persist in `Zomboid/ModOptions.ini`. `require "PZAPI/ModOptions"` first — client files load alphabetically, so a mod folder starting with A-O loads before `PZAPI/`.

### UI gotchas
- `ISLabel:setName(text)` snaps a left-aligned label back to the x it was **created** at (`originalX`) whenever the text changes; layouts that move labels with `setX` lose that position. Use `setNameWithoutMoving(text)` and re-run the parent's layout if the width changed.
- `OnFillWorldObjectContextMenu(playerNum, context, worldObjects, test)` — return early when `test` is true; `context:addOption(text, target, func, ...)`.

## 3. Crafting system (B42)

### Recipe scripts
`craftRecipe` blocks. Relevant keys: `time`, `SkillRequired = Woodwork:3;MetalWelding:3`, `NeedToBeLearn = true`, `AutoLearnAll/AutoLearnAny = Skill:N`, `xpAward = Skill:N`, `MetaRecipe`, `category`, `Tags = ...;CanBeDoneWhileWalking`.
Legacy B41 `recipe` blocks: none in vanilla 42.22 (`getAllRecipes()` is empty), but old mods may still add them.

### Java: `zombie.scripting.entity.components.crafting.CraftRecipe` *(verified)*
Callable from Lua (all public):
- `getName()`, `getTime()` (raw script time), `getTime(character)`, `needToBeLearn()`, `getCategory()`, `getTags()`
- `getRequiredSkillCount()`, `getRequiredSkill(i)` → `RequiredSkill{getPerk(), getLevel()}`
- `clearRequiredSkills()`, `addRequiredSkill(Perk, int)` — mutate the shared script object (affects everyone, until scripts reload)
- `getXPAwardCount()`, `getXPAward(i)` → `XpAward{getPerk(), getAmount()}`
- `getHighestSkillRequirement()`, `getHighestRelevantSkillLevel(character)`
- `getAutoLearnAnySkillCount()/getAutoLearnAllSkillCount()`, `getMetaRecipe()`, `isInHandCraftCraft()`, `isAnySurfaceCraft()`, `canBeDoneInDark()`, `isCanWalk()`
- There is **no** setter for `needToBeLearn` (private field).

**Vanilla time formula** — `getTime(character)` *(verified from bytecode)*:
```
if highestRelevantSkillLevel(char) <= highestSkillRequirement: return time
else: return time - (relevant - highest) * (time / 20)     // integer division → -5% per level above
```
Clearing requirements makes `highest = 0`, so every level becomes a 5% bonus — this mod divides that out (`ARR.scaleDuration`).

**XP** — `CraftRecipe.addXP(character)` is called from `CraftRecipeData.perform()` after outputs are created *(verified)*. Server: `GameServer.addXp(player, perk, amount, ...)`; SP: `character:getXp():AddXP(perk, amount, ...)`. It's Java, so to add bonus XP measure the XP delta around the call (`getXp():getXP(perk)` before/after) and add with the Lua global `addXpNoMultiplier(player, perk, amount)` (works in SP and on the server, no-op on an MP client).

### Java: `ScriptManager` (`getScriptManager()`) *(verified)*
`getAllCraftRecipes()`, `getAllBuildableRecipes()`, `getCraftRecipe(name)`, `getBuildableRecipe(name)`, `getAllRecipes()` (legacy). All return `ArrayList` → iterate `for i=0,list:size()-1 do list:get(i)`.

### Skill check
`CraftRecipeManager.validateHasRequiredSkill` / `hasPlayerRequiredSkill` loop over `getRequiredSkillCount()` — so emptying the list removes the gate everywhere (handcraft, build, workstations). UI lists in `ISRecipeScrollingListBox`, `ISCraftRecipeInfoBox`, `ISWidgetTitleHeader`, `ISBuildIsoEntity` read the same list.

### Known recipes — `IsoGameCharacter` *(verified)*
- `isRecipeKnown(craftRecipe)` returns true if: sandbox `SeeNotLearntRecipe` is on, **or** `isKnowAllRecipes()`, **or** not `needToBeLearn()`, **or** `getKnownRecipes()` contains its name / MetaRecipe / translation name.
- `setKnowAllRecipes(bool)` — same flag as the admin power "know all recipes". Reversible, so prefer it over `learnRecipe(name)` (permanent; can't be told apart from legit learning).
- `learnRecipe(name)`, `isRecipeActuallyKnown(recipe)`, `forgetRecipes()`, `getKnownRecipes()`.

### Timed actions and where time is used *(verified)*
| Activity | Lua | Time source |
|---|---|---|
| Hand crafting (incl. at benches) | `shared/Entity/TimedActions/ISHandcraftAction.lua` | `getDuration()` = `craftRecipe:getTime(character) * 5`; `maxTime` set in `new()`. Recipe performed in `performRecipe()` (SP: `perform()`, MP: server `complete()`). |
| Building entities (carpentry, masonry...) | `server/BuildingObjects/ISBuildIsoEntity.lua` (a cursor, not an action) | `new()` sets `o.maxTime = craftRecipe:getTime()` (no skill!). `ISBuildingObject:tryBuild` passes `self.maxTime` to `ISBuildAction` (Handy trait −50). Recipe performed in `create()` via `buildPanelLogic:performCurrentRecipe()`. |
| Workstation machines | Java `CraftLogic` + `ISWidgetCraftLogicInputControl` | Handled in Java; not patched. `ISCraftAnimAction` is marked deprecated. |

### Crafting UI time display *(verified)*
| Widget | File | What it shows |
|---|---|---|
| Info box (tooltip/details) | `client/Entity/ISUI/CraftRecipe/ISCraftRecipeInfoBox.lua` → `createDynamicChildren()` | `round(getTime(player)/10, 2)` seconds as an info pair keyed `IGUI_CraftingWindow_CraftTime`; rows in `self.infoPairs` (`keyLabel`, `valueLabel`); call `xuiRecalculateLayout()` after changes. |
| Header clock icon | `client/Entity/ISUI/Controls/ISWidgetTitleHeader.lua` → `createChildren()` | `self.timeIcon.mouseovertext` |
| Hand craft panel | `client/Entity/ISUI/CraftRecipe/ISWidgetHandCraftControl.lua` → `prerender()` | `self.durationLabel` "Time required %02dm %02ds" (uses `getTime(player)` as seconds — vanilla is inconsistent between widgets) |

`ISLabel:setName(text)` updates text and width. Colors: `getCore():getBadHighlitedColor()` / `getGoodHighlitedColor()` → `{r,g,b,a}` tables for `textColor`.

## 4. Patterns used

- **Wrap, don't copy.** Save the original function and call it, then adjust the result:
  ```lua
  local orig = ISHandcraftAction.getDuration
  function ISHandcraftAction:getDuration()
      local d = orig(self)
      return ARR.scaleDuration(d, self.craftRecipe, self.character)  -- d * ours / vanilla
  end
  ```
  Scaling the returned value (instead of replacing it) keeps other mods' changes to the same function.
- **Cache originals before mutating shared script objects**, keyed by recipe name. Treat a non-empty live list as authoritative so script reloads (mod set changes between saves) are picked up, and restore from cache when the feature is switched off.
- **Apply on several events**: `OnGameBoot` (scripts ready, sandbox not), `OnInitGlobalModData` + `OnGameStart` (sandbox ready), `OnServerStarted` (dedicated server), `OnCreatePlayer` (per player).
- **Player flags**: remember in `player:getModData()` what *you* turned on, and only undo that.

## 5. Investigating the game code

- Lua is plain text in `<game>\media\lua` — grep it first.
- Java: a JDK `javap` (JDK 21 works on these Java 25 classes for `-p`/`-c`):
  ```bash
  mkdir jar && cd jar
  unzip -q "<game>/projectzomboid.jar" -x 'META-INF/*'        # ~24k classes
  javap -p  zombie/scripting/entity/components/crafting/CraftRecipe.class   # members
  javap -c -p zombie/.../CraftRecipe.class > cr.txt                         # bytecode, read logic
  grep -rl -a "someName" --include=*.class zombie                          # who uses a field/method
  ```
  Note: `unzip jar 'zombie/*'` only extracts part of the tree — extract everything.
- Lua globals backed by Java live in `zombie.Lua.LuaManager$GlobalObject` (e.g. `addXp`, `addXpNoMultiplier`, `getScriptManager`, `instanceof`).
- `print()` output goes to `console.txt`.

## 6. Updating after a game patch

1. Check `%USERPROFILE%\Zomboid\version.txt`.
2. Diff the vanilla files this mod wraps (functions named in §3) — if a function was renamed or moved, update the `require` paths and wrappers.
3. Re-run `javap -p` on `CraftRecipe`, `IsoGameCharacter`, `ScriptManager` and confirm the methods in §3 still exist; re-read `getTime(IsoGameCharacter)` bytecode in case the vanilla time formula changed (then update `vanillaTime` in `ARR_Core.lua`).
4. Start a game, check `console.txt` for `[AdjustableRecipeRequirements]` and Lua errors, open the crafting window and the build menu.
5. If a new version needs different code, add a version folder (e.g. `42.30/`) next to `42/` with just the changed files.
