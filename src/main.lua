-- =============================================================================
-- BOILERPLATE (do not modify)
-- =============================================================================

local mods = rom.mods
mods['SGG_Modding-ENVY'].auto()

---@diagnostic disable: lowercase-global
rom = rom
_PLUGIN = _PLUGIN
game = rom.game
modutil = mods['SGG_Modding-ModUtil']
chalk = mods['SGG_Modding-Chalk']
reload = mods['SGG_Modding-ReLoad']

config = chalk.auto('config.lua')
public.config = config

local NIL = {}
local backups = {}

local function backup(tbl, key)
    if not backups[tbl] then backups[tbl] = {} end
    if backups[tbl][key] == nil then
        local v = tbl[key]
        backups[tbl][key] = v == nil and NIL or (type(v) == "table" and DeepCopyTable(v) or v)
    end
end

local function restore()
    for tbl, keys in pairs(backups) do
        for key, v in pairs(keys) do
            tbl[key] = v == NIL and nil or (type(v) == "table" and DeepCopyTable(v) or v)
        end
    end
end

local function isEnabled()
    return config.Enabled
end

-- =============================================================================
-- MODULE DEFINITION
-- =============================================================================

public.definition = {
    id       = "SpeedrunTimer",
    name     = "Speedrun Timer",
    category = "QoLSettings",
    group    = "QoL",
    tooltip  = "Displays RTA and load-removed timers on screen during runs.",
    default  = false,
}

-- =============================================================================
-- TIMER IMPORTS
-- =============================================================================

import 'timer/RtaTimer.lua'
import 'timer/LrtTimer.lua'
import 'timer/IgtTimer.lua'

-- =============================================================================
-- SPEEDRUN TIMER (orchestrator)
-- =============================================================================

local SpeedrunTimer = {}

function SpeedrunTimer:new()
    local o = {}
    o.Running = false
    o.RtaTimer = RtaTimer:new()
    o.LrtTimer = LrtTimer:new({ withRtaTimer = o.RtaTimer })
    o.IgtTimer = IgtTimer:new()
    setmetatable(o, self)
    self.__index = self
    return o
end

function SpeedrunTimer:start()
    self.Running = true
    self.RtaTimer:start()
    self.LrtTimer:start()
end

function SpeedrunTimer:stop()
    self.Running = false
    self.RtaTimer:stop()
    self.LrtTimer:stop()
end

function SpeedrunTimer:reset()
    self.Running = false
    self.RtaTimer:reset()
    self.LrtTimer:reset()
end

function SpeedrunTimer:update()
    self.RtaTimer:update()
    self.LrtTimer:update()
end

function SpeedrunTimer:getRealTime()
    return self.RtaTimer:getTime()
end

function SpeedrunTimer:getLoadRemovedTime()
    return self.LrtTimer:getTime()
end

function SpeedrunTimer:getInGameTime()
    return self.IgtTimer:getTime()
end

-- =============================================================================
-- DISPLAY UTILITIES
-- =============================================================================

local ANCHOR_PREFIX = "adamant_SpeedrunTimer:"

local function FormatTimestamp(timestamp)
    if not timestamp then return "00:00.00" end
    local centiseconds = (timestamp % 1) * 100
    local seconds = timestamp % 60
    local minutes = 0
    local hours = 0

    if timestamp > 60 then
        minutes = math.floor((timestamp % 3600) / 60)
    end
    if timestamp > 3600 then
        hours = math.floor(timestamp / 3600)
    end

    if hours == 0 then
        return string.format("%02d:%02d.%02d", minutes, seconds, centiseconds)
    end
    return string.format("%02d:%02d:%02d.%02d", hours, minutes, seconds, centiseconds)
end

local function CreateOverlayLine(anchorName, text, kwargs)
    local textFormat = DeepCopyTable(UIData.CurrentRunDepth.TextFormat)
    local x_pos = kwargs.x_pos or 500
    local y_pos = kwargs.y_pos or 500

    textFormat.Font = kwargs.font or textFormat.Font
    textFormat.FontSize = kwargs.font_size or textFormat.FontSize
    textFormat.Color = kwargs.color or textFormat.Color
    textFormat.Justification = kwargs.justification or textFormat.Justification
    textFormat.ShadowColor = kwargs.shadow_color or { 0, 0, 0, 0 }

    if ScreenAnchors[anchorName] ~= nil then
        ModifyTextBox({
            Id = ScreenAnchors[anchorName],
            Text = text,
            Color = kwargs.color or textFormat.Color,
        })
    else
        ScreenAnchors[anchorName] = CreateScreenObstacle({
            Name = "BlankObstacle",
            X = x_pos, Y = y_pos,
            Group = "Combat_Menu_TraitTray_Overlay",
        })
        CreateTextBox(MergeTables(textFormat, {
            Id = ScreenAnchors[anchorName],
            Text = text,
        }))
        ModifyTextBox({
            Id = ScreenAnchors[anchorName],
            FadeTarget = 1, FadeDuration = 0.0,
        })
    end
end

local function DestroyAnchor(anchorName)
    if ScreenAnchors[anchorName] ~= nil then
        Destroy({ Id = ScreenAnchors[anchorName] })
        ScreenAnchors[anchorName] = nil
    end
end

local function DrawTimer(timerName, timer, yOffset)
    CreateOverlayLine(
        ANCHOR_PREFIX .. timerName,
        FormatTimestamp(timer:getTime()),
        {
            justification = "left",
            x_pos = 1820,
            y_pos = 180 + yOffset,
            font_size = 20,
        }
    )
end

local function CleanupDisplay()
    DestroyAnchor(ANCHOR_PREFIX .. "LRT")
    DestroyAnchor(ANCHOR_PREFIX .. "RTA")
end

-- =============================================================================
-- MODULE STATE
-- =============================================================================

local activeTimer = nil
local updateThreadActive = false

local function StopAndCleanup()
    if activeTimer then
        activeTimer:stop()
    end
    activeTimer = nil
    updateThreadActive = false
    CleanupDisplay()
end

-- =============================================================================
-- MODULE LOGIC
-- =============================================================================

local function apply()
end

local function disable()
    restore()
end

local function registerHooks()
    -- Start a fresh timer at the beginning of each run
    modutil.mod.Path.Wrap("StartNewRun", function(baseFunc, prevRun, args)
        if not isEnabled() then return baseFunc(prevRun, args) end
        if activeTimer then
            StopAndCleanup()
        end
        activeTimer = SpeedrunTimer:new()
        return baseFunc(prevRun, args)
    end)

    -- Start timing and spawn update thread when the player materializes
    modutil.mod.Path.Wrap("RoomEntranceMaterialize", function(baseFunc, ...)
        if not isEnabled() then return baseFunc(...) end
        local val = baseFunc(...)

        if activeTimer and not activeTimer.Running then
            activeTimer:start()
        end

        -- Spawn update thread if not already active
        if activeTimer and activeTimer.Running and not updateThreadActive then
            updateThreadActive = true
            thread(function()
                while activeTimer and activeTimer.Running do
                    if not isEnabled() then
                        StopAndCleanup()
                        return
                    end
                    activeTimer:update()
                    DrawTimer("LRT", activeTimer.LrtTimer, 30)
                    DrawTimer("RTA", activeTimer.RtaTimer, 50)
                    wait(0.016, "adamant_SpeedrunTimer", true)
                end
                updateThreadActive = false
            end)
        end

        return val
    end)

    -- Stop timer when Chronos is defeated (keep display visible)
    modutil.mod.Path.Wrap("ChronosKillPresentation", function(baseFunc, ...)
        if not isEnabled() then return baseFunc(...) end
        if activeTimer then
            activeTimer:stop()
        end
        return baseFunc(...)
    end)

    -- Track load screens for LRT calculation
    modutil.mod.Path.Wrap("AddTimerBlock", function(baseFunc, currRun, timerBlockName)
        local val = baseFunc(currRun, timerBlockName)
        if isEnabled() and timerBlockName == "MapLoad" and activeTimer and activeTimer.Running then
            activeTimer.LrtTimer:processLoadEvent(true)
        end
        return val
    end)

    modutil.mod.Path.Wrap("RemoveTimerBlock", function(baseFunc, currRun, timerBlockName)
        local val = baseFunc(currRun, timerBlockName)
        if isEnabled() and timerBlockName == "MapLoad" and activeTimer and activeTimer.Running then
            activeTimer.LrtTimer:processLoadEvent(false)
        end
        return val
    end)
end

-- =============================================================================
-- PUBLIC API (do not modify)
-- =============================================================================

public.definition.enable = function()
    apply()
end

public.definition.disable = function()
    disable()
end

-- Expose timer data for external consumers
public.getRealTime = function()
    if activeTimer then return FormatTimestamp(activeTimer:getRealTime()) end
    return "00:00.00"
end

public.getLoadRemovedTime = function()
    if activeTimer then return FormatTimestamp(activeTimer:getLoadRemovedTime()) end
    return "00:00.00"
end

public.getInGameTime = function()
    if activeTimer then return FormatTimestamp(activeTimer:getInGameTime()) end
    return "00:00.00"
end

-- =============================================================================
-- LIFECYCLE (do not modify)
-- =============================================================================

local loader = reload.auto_single()

modutil.once_loaded.game(function()
    loader.load(function()
        import_as_fallback(rom.game)
        registerHooks()
        if config.Enabled then apply() end
    end)
end)

-- =============================================================================
-- STANDALONE UI (do not modify)
-- =============================================================================
-- When adamant-core is NOT installed, renders a minimal ImGui toggle.
-- When adamant-core IS installed, the core handles UI — this is skipped.

local imgui = rom.ImGui

local showWindow = false

rom.gui.add_imgui(function()
    if mods['adamant-Core'] then return end
    if not showWindow then return end

    if imgui.Begin(public.definition.name, true) then
        local val, chg = imgui.Checkbox("Enabled", config.Enabled)
        if chg then
            config.Enabled = val
            if val then apply() else disable() end
        end
        if imgui.IsItemHovered() and public.definition.tooltip ~= "" then
            imgui.SetTooltip(public.definition.tooltip)
        end
        imgui.End()
    else
        showWindow = false
    end
end)

rom.gui.add_to_menu_bar(function()
    if mods['adamant-Core'] then return end
    if imgui.BeginMenu("adamant") then
        if imgui.MenuItem(public.definition.name) then
            showWindow = not showWindow
        end
        imgui.EndMenu()
    end
end)
