local mods = rom.mods
mods['SGG_Modding-ENVY'].auto()

lib = mods['adamant-ModpackLib']
modutil = mods['SGG_Modding-ModUtil']
local chalk = mods['SGG_Modding-Chalk']
local reload = mods['SGG_Modding-ReLoad']
local dataDefaults = import("config.lua")
local config = chalk.auto('config.lua')

SpeedrunTimerInternal = SpeedrunTimerInternal or {}
local internal = SpeedrunTimerInternal

public.definition = {
    id             = "SpeedrunTimer",
    name           = "Speedrun Timer",
    tooltip        = "Displays RTA and load-removed timers on screen during runs.",
    default        = dataDefaults.Enabled,
    affectsRunData = false,
    modpack        = "speedrun",
}

public.store = nil
store = nil
internal.standaloneUi = nil

local function registerHooks()
    if internal.RegisterHooks then
        internal.RegisterHooks()
    end
    if internal.RegisterPublicApi then
        internal.RegisterPublicApi()
    end
    public.DrawTab = internal.DrawTab
    -- public.DrawQuickContent = internal.DrawQuickContent
end

local loader = reload.auto_single()

local function init()
    import_as_fallback(rom.game)
    import("data.lua")
    import("ui.lua")
    public.store = lib.store.create(config, public.definition, dataDefaults)
    store = public.store
    registerHooks()
    internal.standaloneUi = lib.host.standaloneUI(
        public.definition,
        store,
        store.uiState,
        {
            getDrawTab = function()
                return public.DrawTab
            end,
        }
    )
end

modutil.once_loaded.game(function()
    loader.load(init, init)
end)

---@diagnostic disable-next-line: redundant-parameter
rom.gui.add_imgui(function()
    if internal.standaloneUi and internal.standaloneUi.renderWindow then
        internal.standaloneUi.renderWindow()
    end
end)

---@diagnostic disable-next-line: redundant-parameter
rom.gui.add_to_menu_bar(function()
    if internal.standaloneUi and internal.standaloneUi.addMenuBar then
        internal.standaloneUi.addMenuBar()
    end
end)
