-- Adjustable Recipe Requirements - crafting menu time display
require "AdjustableRecipeRequirements/ARR_Core"
require "Entity/ISUI/CraftRecipe/ISCraftRecipeInfoBox"
require "Entity/ISUI/Controls/ISWidgetTitleHeader"
require "Entity/ISUI/CraftRecipe/ISWidgetHandCraftControl"

local function fmt(n)
    return string.format("%.2f", n)
end

-- "Under-skilled: x2.31 time" / "Skilled: x0.76 time", or nil when nothing to show.
local function modifierText(info)
    if not info.scaled or not ARR.opt("ShowTimeModifier") then return nil, nil end
    local m = info.multiplier
    if math.abs(m - 1) < 0.005 then return nil, nil end
    if m > 1 then
        return getText("IGUI_ARR_UnderSkilled", fmt(m)), "bad"
    end
    return getText("IGUI_ARR_Skilled", fmt(m)), "good"
end

local function colorTable(kind)
    local c = kind == "bad" and getCore():getBadHighlitedColor() or getCore():getGoodHighlitedColor()
    return { r = c:getR(), g = c:getG(), b = c:getB(), a = 1 }
end

---------------------------------------------------------------------------
-- Recipe info box (tooltip / details panel): fix the time and add a modifier row
---------------------------------------------------------------------------
if ISCraftRecipeInfoBox then
    local orig = ISCraftRecipeInfoBox.createDynamicChildren
    function ISCraftRecipeInfoBox:createDynamicChildren()
        orig(self)
        if not self.recipe or not self.player or not self.infoPairs then return end

        local info = ARR.getTimeInfo(self.recipe, self.player)
        local timeKey = getText("IGUI_CraftingWindow_CraftTime")
        for idx, pair in ipairs(self.infoPairs) do
            if pair.valueLabel and pair.keyLabel and pair.keyLabel.name == timeKey then
                pair.valueLabel:setName(tostring(round(info.time / 10, 2)) .. " " .. getText("IGUI_CraftingWindow_Seconds"))

                local text, kind = modifierText(info)
                if text then
                    text = text .. " (" .. getText("IGUI_ARR_BaseTime", tostring(round(info.base / 10, 2))) .. ")"
                    self:addInfoPair(getText("IGUI_ARR_SkillModifier"), text, colorTable(kind))
                    local row = table.remove(self.infoPairs)
                    table.insert(self.infoPairs, idx + 1, row)
                end
                self:xuiRecalculateLayout()
                break
            end
        end
    end
end

---------------------------------------------------------------------------
-- Recipe header clock icon tooltip (crafting window and build menu)
---------------------------------------------------------------------------
if ISWidgetTitleHeader then
    local orig = ISWidgetTitleHeader.createChildren
    function ISWidgetTitleHeader:createChildren()
        orig(self)
        if not self.timeIcon or not self.recipe or not self.player then return end
        -- Workstation machines (kilns, furnaces...) are not changed by this mod.
        if self.logic and instanceof(self.logic, "CraftLogic") then return end

        local info = ARR.getTimeInfo(self.recipe, self.player)
        local text = getText("IGUI_CraftingWindow_CraftTime") .. " " .. tostring(round(info.time / 10, 2))
            .. " " .. getText("IGUI_CraftingWindow_Seconds")
        local mod = modifierText(info)
        if mod then text = text .. " (" .. mod .. ")" end
        self.timeIcon.mouseovertext = text
    end
end

---------------------------------------------------------------------------
-- Hand craft panel "Time required" label
---------------------------------------------------------------------------
if ISWidgetHandCraftControl then
    -- Vanilla sets this label's text every frame with ISLabel:setName, which snaps a
    -- left-aligned label back to its creation x (0) whenever the text changes. So we
    -- hide the label from vanilla, set our text without moving it, and re-run the
    -- panel layout only when the text width changes (keeps the progress bar aligned).
    local orig = ISWidgetHandCraftControl.prerender
    function ISWidgetHandCraftControl:prerender()
        local label = self.durationLabel
        local recipe = label and self.logic and self.player and self.logic:getRecipe()
        if not recipe then
            orig(self)
            return
        end

        self.durationLabel = nil
        orig(self)
        self.durationLabel = label

        local info = ARR.getTimeInfo(recipe, self.player)
        local seconds = info.time
        local mm = math.floor(seconds / 60)
        local ss = math.floor(math.fmod(seconds, 60))
        local text = string.format(getText("IGUI_CraftingWindow_TimeRequired") .. " %02dm %02ds", mm, ss)
        if info.scaled and ARR.opt("ShowTimeModifier") and math.abs(info.multiplier - 1) >= 0.005 then
            text = text .. " (x" .. fmt(info.multiplier) .. ")"
        end

        if label.name ~= text then
            local oldWidth = label:getWidth()
            label:setNameWithoutMoving(text)
            if label:getWidth() ~= oldWidth and self.calculateLayout then
                self:calculateLayout(self.width, self.height)
            end
        end
    end
end
