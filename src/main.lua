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

public.host = nil
local store
local session
internal.standaloneUi = nil

local loader = reload.auto_single()

local function init()
    import_as_fallback(rom.game)
    import("data.lua")
    import("logic.lua")
    import("ui.lua")

    store, session = lib.createStore(config, public.definition, dataDefaults)
    internal.store = store

    if internal.RegisterHooks then
        internal.RegisterHooks()
    end
    if internal.RegisterPublicApi then
        internal.RegisterPublicApi()
    end

    public.host = lib.createModuleHost({
        definition = public.definition,
        store = store,
        session = session,
        drawTab = internal.DrawTab,
        -- drawQuickContent = internal.DrawQuickContent,
    })
    internal.standaloneUi = lib.standaloneHost(public.host)
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
