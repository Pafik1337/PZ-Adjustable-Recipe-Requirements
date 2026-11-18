-- Adjustable Recipe Requirements - core logic (Build 42)
-- Shared: runs in single player, on the client and on a dedicated server.

ARR = ARR or {}
ARR.NS = "AdjustableRecipeRequirements"

local DEFAULTS = {
    RemoveSkillRequirements = true,
    KnowAllRecipes = true,
    SkillTimeScaling = true,
    TimePercentPerLevel = 15,
    MaxTimeMultiplier = 5,
    MinTimeMultiplier = 0.5,
    UnderskilledXpBonus = true,
    XpPercentPerLevel = 10,
    MaxXpMultiplier = 3,
    ShowTimeModifier = true,
}

function ARR.opt(key)
    local sv = SandboxVars and SandboxVars[ARR.NS]
    local v = sv and sv[key]
    if v == nil then return DEFAULTS[key] end
    return v
end

---------------------------------------------------------------------------
-- Original skill requirements
---------------------------------------------------------------------------
-- The game only knows a recipe's requirements until we clear them, so we keep
-- a copy keyed by recipe name. A non-empty live list is always authoritative
-- (only this mod empties them), so script reloads are picked up correctly.

ARR.originals = ARR.originals or {}

local function recipeKey(recipe, legacy)
    if legacy then
        return "legacy:" .. tostring(recipe:getName())
    end
    return recipe:getName()
end

local function readSkills(recipe)
    local skills = {}
    for i = 0, recipe:getRequiredSkillCount() - 1 do
        local rs = recipe:getRequiredSkill(i)
        if rs and rs:getPerk() then
            table.insert(skills, { perk = rs:getPerk(), level = rs:getLevel() })
        end
    end
    return skills
end

local function processList(list, legacy, remove)
    if not list then return 0 end
    local changed = 0
    for i = 0, list:size() - 1 do
        local recipe = list:get(i)
        if recipe then
            local key = recipeKey(recipe, legacy)
            local count = recipe:getRequiredSkillCount()
            if count > 0 then
                ARR.originals[key] = readSkills(recipe)
            end
            local orig = ARR.originals[key]
            if remove then
                if count > 0 then
                    recipe:clearRequiredSkills()
                    changed = changed + 1
                end
            elseif count == 0 and orig and #orig > 0 then
                for _, s in ipairs(orig) do
                    recipe:addRequiredSkill(s.perk, s.level)
                end
                changed = changed + 1
            end
        end
    end
    return changed
end

function ARR.applyRequirements()
    local sm = getScriptManager()
    if not sm then return end
    local remove = ARR.opt("RemoveSkillRequirements") and true or false
    local n = 0
    n = n + processList(sm:getAllCraftRecipes(), false, remove)
    n = n + processList(sm:getAllBuildableRecipes(), false, remove)
    if sm.getAllRecipes then
        n = n + processList(sm:getAllRecipes(), true, remove)
    end
    if n > 0 then
        print("[AdjustableRecipeRequirements] " .. (remove and "Removed" or "Restored")
            .. " skill requirements on " .. n .. " recipes")
    end
end

-- Original requirements of a craft recipe: { {perk=, level=}, ... }
function ARR.getOriginalSkills(recipe)
    if not recipe then return {} end
    local orig = ARR.originals[recipe:getName()]
    if orig then return orig end
    return readSkills(recipe)
end

---------------------------------------------------------------------------
-- Time
---------------------------------------------------------------------------

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- Average over required skills of (1 + pct)^(required - level), optional clamp.
local function compoundingAverage(skills, character, pct, onlyDeficit)
    local sum = 0
    for _, s in ipairs(skills) do
        local delta = s.level - character:getPerkLevel(s.perk)
        if onlyDeficit and delta < 0 then delta = 0 end
        sum = sum + (1 + pct) ^ delta
    end
    return sum / #skills
end

-- Vanilla CraftRecipe.getTime(character), but measured against the original
-- requirement instead of the (possibly cleared) live one.
local function vanillaTime(recipe, character, skills)
    local base = recipe:getTime()
    local highest = 0
    for _, s in ipairs(skills) do
        if s.level > highest then highest = s.level end
    end
    local relevant = recipe:getHighestRelevantSkillLevel(character)
    if relevant <= highest then return base end
    return base - (relevant - highest) * math.floor(base / 20)
end

-- Returns a table:
--   time       final crafting time in recipe units (same unit as getTime())
--   base       the recipe's base time
--   multiplier time / base
--   scaled     true when the mod's skill formula was applied
--   capped     "max" / "min" when the multiplier hit a limit
function ARR.getTimeInfo(recipe, character)
    local base = recipe:getTime()
    local skills = ARR.getOriginalSkills(recipe)
    local info = { base = base, time = base, multiplier = 1, scaled = false }
    if base <= 0 or not character then return info end

    if not ARR.opt("SkillTimeScaling") or #skills == 0 then
        info.time = vanillaTime(recipe, character, skills)
    else
        local pct = (ARR.opt("TimePercentPerLevel") or 0) / 100
        local lo = ARR.opt("MinTimeMultiplier")
        local hi = ARR.opt("MaxTimeMultiplier")
        local m = compoundingAverage(skills, character, pct, false)
        if m >= hi then info.capped = "max" elseif m <= lo then info.capped = "min" end
        m = clamp(m, lo, hi)
        info.time = math.max(1, math.floor(base * m + 0.5))
        info.scaled = true
    end
    info.multiplier = info.time / base
    return info
end

function ARR.getTime(recipe, character)
    return ARR.getTimeInfo(recipe, character).time
end

-- Scale a duration that the game (or another mod) computed from the vanilla
-- getTime(character), so other mods' changes to the duration are kept.
function ARR.scaleDuration(duration, recipe, character)
    if not duration or duration <= 1 or not recipe or not character then return duration end
    local vanilla = recipe:getTime(character)
    if not vanilla or vanilla <= 0 then return duration end
    local ours = ARR.getTime(recipe, character)
    return math.max(1, math.floor(duration * ours / vanilla + 0.5))
end

---------------------------------------------------------------------------
-- XP
---------------------------------------------------------------------------

function ARR.getXpMultiplier(recipe, character)
    if not ARR.opt("UnderskilledXpBonus") or not recipe or not character then return 1 end
    local skills = ARR.getOriginalSkills(recipe)
    if #skills == 0 then return 1 end
    local pct = (ARR.opt("XpPercentPerLevel") or 0) / 100
    local m = compoundingAverage(skills, character, pct, true)
    return clamp(m, 1, ARR.opt("MaxXpMultiplier"))
end

-- Call before the recipe is performed; returns nil when no bonus applies.
function ARR.snapshotXp(recipe, character)
    if not recipe or not character or not instanceof(character, "IsoPlayer") then return nil end
    if recipe:getXPAwardCount() == 0 then return nil end
    local mult = ARR.getXpMultiplier(recipe, character)
    if mult <= 1 then return nil end
    local snap = { mult = mult, perks = {} }
    local xp = character:getXp()
    for i = 0, recipe:getXPAwardCount() - 1 do
        local award = recipe:getXPAward(i)
        local perk = award and award:getPerk()
        if perk then
            table.insert(snap.perks, { perk = perk, before = xp:getXP(perk) })
        end
    end
    return snap
end

-- Call after the recipe is performed: adds (mult - 1) x the XP vanilla just gave.
function ARR.grantBonusXp(character, snap)
    if not snap then return end
    local xp = character:getXp()
    for _, p in ipairs(snap.perks) do
        local gained = xp:getXP(p.perk) - p.before
        if gained > 0 then
            addXpNoMultiplier(character, p.perk, gained * (snap.mult - 1))
        end
    end
end

---------------------------------------------------------------------------
-- Known recipes
---------------------------------------------------------------------------

function ARR.applyPlayer(player)
    if not player then return end
    local md = player:getModData()
    if ARR.opt("KnowAllRecipes") then
        player:setKnowAllRecipes(true)
        md.ARR_KnowAll = true
    elseif md.ARR_KnowAll then
        -- Only undo what this mod turned on.
        player:setKnowAllRecipes(false)
        md.ARR_KnowAll = nil
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

Events.OnGameBoot.Add(ARR.applyRequirements)
Events.OnInitGlobalModData.Add(ARR.applyRequirements) -- save's sandbox settings are loaded by now
Events.OnGameStart.Add(ARR.applyRequirements)
if Events.OnServerStarted then
    Events.OnServerStarted.Add(ARR.applyRequirements)
end
Events.OnCreatePlayer.Add(function(_, player)
    ARR.applyRequirements()
    ARR.applyPlayer(player)
end)

return ARR
