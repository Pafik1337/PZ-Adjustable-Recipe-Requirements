-- Adjustable Recipe Requirements - change this save's settings while playing (single player)
--
-- Reuses the vanilla sandbox settings window (the one in the debug menu / admin panel),
-- limited to this mod's page. Values are written to the live SandboxOptions, which the
-- game stores in the save (map_sand.bin) every time the world is saved.
-- Multiplayer: admins use Admin Panel > Sandbox Options instead.

require "AdjustableRecipeRequirements/ARR_Core"
require "ISUI/AdminPanel/ISServerSandboxOptionsUI"
require "OptionScreens/ServerSettingsScreen"
require "PZAPI/ModOptions"

if not ISServerSandboxOptionsUI then return end

local PAGE_PREFIX = ARR.NS .. "."

ARR_SettingsUI = ISServerSandboxOptionsUI:derive("ARR_SettingsUI")

local function isOurPage(page)
    if not page or not page.settings then return false end
    for _, setting in ipairs(page.settings) do
        if setting.name and string.sub(setting.name, 1, #PAGE_PREFIX) == PAGE_PREFIX then
            return true
        end
    end
    return false
end

function ARR_SettingsUI:createChildren()
    -- Show only this mod's page: vanilla replaces entry [1] with the Presets page,
    -- so keep a placeholder there and remove the Presets item afterwards.
    local origGetTable = ServerSettingsScreen.getSandboxSettingsTable
    ServerSettingsScreen.getSandboxSettingsTable = function()
        local result = { {} }
        for _, page in ipairs(origGetTable()) do
            if isOurPage(page) then table.insert(result, page) end
        end
        return result
    end
    local ok, err = pcall(ISServerSandboxOptionsUI.createChildren, self)
    ServerSettingsScreen.getSandboxSettingsTable = origGetTable
    if not ok then error(err) end

    local items = self.listbox.items
    for i = #items, 1, -1 do
        local entry = items[i].item
        if entry and entry.page and entry.page.customui then
            self.listbox:removeItemByIndex(i)
        end
    end
    if #self.listbox.items > 0 then
        self.listbox.selected = 1
        self:onMouseDownListbox(self.listbox.items[1].item)
    end
end

function ARR_SettingsUI:onButtonApply()
    self:settingsFromUI(self.options)
    getSandboxOptions():toLua() -- refresh SandboxVars from the live options
    ARR.refresh()
    self:destroy()
end

function ARR_SettingsUI:destroy()
    ISServerSandboxOptionsUI.destroy(self)
    if ARR.settingsUI == self then ARR.settingsUI = nil end
    if ISServerSandboxOptionsUI.instance == self then ISServerSandboxOptionsUI.instance = nil end
end

function ARR.canEditSettingsInGame()
    return not isClient() and getPlayer() ~= nil
end

function ARR.openSettings()
    if not ARR.canEditSettingsInGame() then return end
    if ARR.settingsUI then
        ARR.settingsUI:destroy()
    end
    local w, h = 800, 600
    local ui = ARR_SettingsUI:new((getCore():getScreenWidth() - w) / 2, (getCore():getScreenHeight() - h) / 2, w, h)
    ARR.settingsUI = ui
    ui:initialise()
    ui:addToUIManager()
    ui:bringToTop()
end

-- Esc > Options > Mods page
if PZAPI and PZAPI.ModOptions then
    local options = PZAPI.ModOptions:create(ARR.NS, getText("Sandbox_AdjustableRecipeRequirements"))
    options:addDescription(getText("IGUI_ARR_ModOptionsDesc"))
    options:addButton("openSettings", "IGUI_ARR_OpenSettings", "IGUI_ARR_OpenSettings_tooltip", function()
        ARR.openSettings()
    end)
end
