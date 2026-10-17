dofile("data/scripts/lib/mod_settings.lua")

local mod_id = "spell_organizer"
mod_settings_version = 1

local keys = {}
for code = string.byte("A"), string.byte("Z") do
    local letter = string.char(code)
    keys[#keys + 1] = { letter, letter }
end

mod_settings = {
    {
        id = "open_key",
        ui_name = "Open Spell Organizer",
        ui_description = "Spell Organizer opens beside vanilla inventory (Q fallback currently disabled).",
        value_default = "Q",
        values = keys,
        scope = MOD_SETTING_SCOPE_RUNTIME,
    },
}

function ModSettingsUpdate(init_scope)
    mod_settings_update(mod_id, mod_settings, init_scope)
end

function ModSettingsGuiCount()
    return mod_settings_gui_count(mod_id, mod_settings)
end

function ModSettingsGui(gui, in_main_menu)
    mod_settings_gui(mod_id, mod_settings, gui, in_main_menu)
end
