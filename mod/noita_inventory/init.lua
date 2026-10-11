-- Prototype controls: B opens/closes the organizer while it is selected;
-- Escape closes the panel. This milestone only proves GUI lifecycle.
local ORGANIZER_GIVEN_KEY = "NOITAINVENTORY_ORGANIZER_GIVEN"
local OPEN_KEY_CODE = 5 -- SDL keycode for B, see data/scripts/debug/keycodes.lua
local ESCAPE_KEY_CODE = 41
local organizer_gui = GuiCreate()
local organizer_open = false

function OnModInit()
    print("[NoitaInventory] loaded")
end

function OnPlayerSpawned(player_entity)
    if GameHasFlagRun(ORGANIZER_GIVEN_KEY) then
        return
    end

    local x, y = EntityGetTransform(player_entity)
    local organizer = EntityLoad("mods/noita_inventory/files/entities/spell_organizer.xml", x, y)

    if organizer == nil or organizer == 0 then
        print("[NoitaInventory] failed to create Spell Organizer")
        return
    end

    GamePickUpInventoryItem(player_entity, organizer, false)
    GameAddFlagRun(ORGANIZER_GIVEN_KEY)
    GamePrint("NoitaInventory: Spell Organizer added")
    print("[NoitaInventory] organizer given: " .. tostring(organizer))
end

local function active_item_is_organizer()
    local players = EntityGetWithTag("player_unit")
    if players == nil or #players == 0 then
        return false
    end

    local inventory = EntityGetFirstComponentIncludingDisabled(players[1], "Inventory2Component")
    if inventory == nil then
        return false
    end

    local active_item = ComponentGetValue2(inventory, "mActiveItem")
    if active_item == nil or active_item == 0 then
        return false
    end

    return EntityGetFilename(active_item) == "mods/noita_inventory/files/entities/spell_organizer.xml"
end

function OnWorldPostUpdate()
    if InputIsKeyJustDown(OPEN_KEY_CODE) and active_item_is_organizer() then
        organizer_open = not organizer_open
        print("[NoitaInventory] organizer panel " .. (organizer_open and "opened" or "closed"))
    elseif InputIsKeyJustDown(ESCAPE_KEY_CODE) and organizer_open then
        organizer_open = false
        print("[NoitaInventory] organizer panel closed")
    end

    if not organizer_open then
        return
    end

    GuiStartFrame(organizer_gui)
    local screen_width, screen_height = GuiGetScreenDimensions(organizer_gui)
    local panel_x = screen_width * 0.5 - 100
    local panel_y = screen_height * 0.5 - 30

    GuiText(organizer_gui, panel_x, panel_y, "SPELL ORGANIZER")
    GuiText(organizer_gui, panel_x, panel_y + 15, "Prototype: empty storage")
    local close_clicked = GuiButton(organizer_gui, 1, panel_x, panel_y + 35, "Close")
    if close_clicked then
        organizer_open = false
    end
end

