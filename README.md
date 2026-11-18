# Adjustable Recipe Requirements

Project Zomboid **Build 42** mod (written against 42.22.2).

- Removes skill level requirements from crafting and building recipes.
- Optionally makes every recipe known (no magazines/journals needed).
- Crafting time depends on your skill compared with the recipe's *original* requirement — slower below it, faster above it.
- Optional extra XP when crafting above your level.
- Shows the real time and the modifier ("Under-skilled: x2.31 time") in the crafting menu.

Every feature is a per-save setting: **Sandbox Options → Adjustable Recipe Requirements**.

## Install (local)

Copy or keep this folder at `%USERPROFILE%\Zomboid\mods\AdjustableRecipeRequirements\`, then enable it in the main menu **Mods** screen (or per save via Load → More → Mods).

## Adding to or removing from an existing save

- **Adding mid-game: safe.** The mod adds no items, objects or map data. Enable it via Load → More → Mods. Requirements are removed on load, recipes become known when the character loads, and time/XP changes apply to the next craft. Existing saves start with the default settings — change them in-game (below).
- **Removing mid-game: safe.** Skill requirements and crafting time return to vanilla immediately. "Know all recipes" uses the game's own know-all flag, which may be stored with the character — to be sure it's cleared, set `KnowAllRecipes` to off and load the save once before removing the mod.
- Back up the save folder (`%USERPROFILE%\Zomboid\Saves\<mode>\<save>\`) before changing mods on a save you care about.

## Changing settings mid-game

- **Single player:** Esc → Options → Mods → Adjustable Recipe Requirements → **Recipe requirement settings...**. A window with only this mod's settings opens; **Apply** takes effect immediately and is stored in the save the next time the game saves.
- **Multiplayer:** server admins use Admin Panel → Sandbox Options (or edit the server's `*_SandboxVars.lua`).

## Settings

| Option (SandboxVars.AdjustableRecipeRequirements.*) | Default | Meaning |
|---|---|---|
| `RemoveSkillRequirements` | true | Recipes have no skill level gate. Turning it off restores the original requirements. |
| `KnowAllRecipes` | true | Every recipe is known. Off = vanilla learning (magazines, journals, auto-learn). |
| `SkillTimeScaling` | true | Skill-based time for hand crafting and building. |
| `TimePercentPerLevel` | 15 | Compounding % per level of difference. |
| `MaxTimeMultiplier` | 5 | Upper cap of the time multiplier. |
| `MinTimeMultiplier` | 0.5 | Lower cap of the time multiplier. |
| `UnderskilledXpBonus` | true | Extra XP when below the requirement. |
| `XpPercentPerLevel` | 10 | Compounding XP % per missing level. |
| `MaxXpMultiplier` | 3 | Cap of the XP multiplier. |
| `ShowTimeModifier` | true | Show the modifier line in the crafting menu. |

## Formulas

For each original required skill *i*: `delta_i = requiredLevel_i - playerLevel_i`

- **Time:** `multiplier = average_i( (1 + TimePercentPerLevel/100) ^ delta_i )`, clamped to `[MinTimeMultiplier, MaxTimeMultiplier]`; `time = round(base × multiplier)`.
- **XP:** `multiplier = average_i( (1 + XpPercentPerLevel/100) ^ max(0, delta_i) )`, clamped to `[1, MaxXpMultiplier]`. The bonus `(multiplier − 1) × XP vanilla just gave` is added without XP multipliers (vanilla's gain already includes them).
- Recipes with **no** skill requirement, or with `SkillTimeScaling` off, use the vanilla formula (−5% per level above the *original* requirement).

Example, requirement 8, 15%/level: level 0 → ×3.06, 2 → ×2.31, 6 → ×1.32, 10 → ×0.76.

## Scope and limitations

- Affects hand crafting (incl. at crafting benches) and building. **Not** automatic workstations (kilns, furnaces, etc. — `CraftLogic`).
- Mods whose recipes check skills in their own Lua (`OnTest` etc.) keep that gate.
- Mainly tested design for single player. Multiplayer: requirement removal and XP run server-side too, but `KnowAllRecipes` is set on the client player only.

## Layout

```
42/
  mod.info
  poster.png
  media/
    sandbox-options.txt                       per-save settings
    lua/shared/AdjustableRecipeRequirements/
      ARR_Core.lua                            settings, requirement caching/removal, formulas, XP, events
      ARR_HandcraftPatch.lua                  ISHandcraftAction duration + XP
    lua/server/AdjustableRecipeRequirements/
      ARR_BuildPatch.lua                      ISBuildIsoEntity duration + XP
    lua/client/AdjustableRecipeRequirements/
      ARR_UIPatch.lua                         crafting menu time display
      ARR_SettingsUI.lua                      in-game settings window (SP), opened from Mod Options
common/
  media/lua/shared/Translate/EN/
    Sandbox.json                              settings texts
    IG_UI.json                                UI texts
```

See [docs/MODDING_NOTES.md](docs/MODDING_NOTES.md) for the engine findings behind this mod and how to update it after a game patch.
