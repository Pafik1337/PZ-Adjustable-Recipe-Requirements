-- Adjustable Recipe Requirements - hand crafting time and XP
require "AdjustableRecipeRequirements/ARR_Core"
require "Entity/TimedActions/ISHandcraftAction"

if not ISHandcraftAction then return end

local orig_getDuration = ISHandcraftAction.getDuration
function ISHandcraftAction:getDuration()
    local duration = orig_getDuration(self)
    if not self.craftRecipe or not self.character or self.character:isTimedActionInstant() then
        return duration
    end
    return ARR.scaleDuration(duration, self.craftRecipe, self.character)
end

local orig_performRecipe = ISHandcraftAction.performRecipe
function ISHandcraftAction:performRecipe()
    local snap = ARR.snapshotXp(self.craftRecipe, self.character)
    orig_performRecipe(self)
    ARR.grantBonusXp(self.character, snap)
end
