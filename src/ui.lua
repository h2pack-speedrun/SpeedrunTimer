local internal = SpeedrunTimerInternal

function internal.DrawTab(ui)
    lib.widgets.text(ui, "Speedrun Timer runs without configurable module settings.")
end

function internal.DrawQuickContent(ui)
    lib.widgets.text(ui, "Speedrun Timer has no quick controls.")
end

return internal
