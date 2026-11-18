-- Adjustable Recipe Requirements - building (carpentry, masonry, etc.) time and XP
require "AdjustableRecipeRequirements/ARR_Core"
require "BuildingObjects/ISBuildIsoEntity"

if not ISBuildIsoEntity then return end

-- Vanilla building time ignores skill entirely: maxTime = craftRecipe:getTime().
local orig_new = ISBuildIsoEntity.new
function ISBuildIsoEntity.new(self, character, ...)
    local o = orig_new(self, character, ...)
    if o and o.craftRecipe and o.maxTime and character then
        local base = o.craftRecipe:getTime()
        if base and base > 0 and o.maxTime > 1 then
            local ours = ARR.getTime(o.craftRecipe, character)
            o.maxTime = math.max(1, math.floor(o.maxTime * ours / base + 0.5))
        end
    end
    return o
end

local orig_create = ISBuildIsoEntity.create
function ISBuildIsoEntity:create(...)
    local snap = self.craftRecipe and ARR.snapshotXp(self.craftRecipe, self.character) or nil
    local result = orig_create(self, ...)
    ARR.grantBonusXp(self.character, snap)
    return result
end
