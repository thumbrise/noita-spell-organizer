-- Prototype controls: B opens/closes the organizer while it is selected;
-- Escape closes the panel. This milestone only proves GUI lifecycle.
local ORGANIZER_GIVEN_KEY = "NOITAINVENTORY_ORGANIZER_GIVEN"
local OPEN_KEY_CODE = 5 -- SDL keycode for B, see data/scripts/debug/keycodes.lua
local ESCAPE_KEY_CODE = 41
local organizer_gui = GuiCreate()
local organizer_open = false
local target_wand = nil

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

local function get_player()
    local players = EntityGetWithTag("player_unit")
    if players == nil or #players == 0 then
        return nil
    end
    return players[1]
end

local function get_active_item(player)
    local inventory = EntityGetFirstComponentIncludingDisabled(player, "Inventory2Component")
    if inventory == nil then
        return nil
    end
    local active_item = ComponentGetValue2(inventory, "mActiveItem")
    if active_item == nil or active_item == 0 then
        return nil
    end
    return active_item
end

local function active_item_is_organizer(player)
    local active_item = get_active_item(player)
    if active_item == nil then
        return false
    end
    return EntityGetFilename(active_item) == "mods/noita_inventory/files/entities/spell_organizer.xml"
end

local function get_quick_inventory(player)
    local children = EntityGetAllChildren(player)
    if children == nil then
        return nil
    end

    for _, child in ipairs(children) do
        if EntityGetName(child) == "inventory_quick" then
            return child
        end
    end

    return nil
end

local function get_entity_spells(container)
    local result = {}
    local children = EntityGetAllChildren(container)
    if children == nil then
        return result
    end

    for _, spell in ipairs(children) do
        local action_component = EntityGetFirstComponentIncludingDisabled(spell, "ItemActionComponent")
        if action_component ~= nil then
            local action_id = ComponentGetValue2(action_component, "action_id")
            if action_id ~= nil and action_id ~= "" then
                table.insert(result, { entity = spell, action_id = action_id })
            end
        end
    end

    return result
end

local function move_one_spell(spell, destination)
    if spell == nil or destination == nil then
        return false
    end

    EntityRemoveFromParent(spell)
    EntityAddChild(destination, spell)
    return true
end

local function get_inventory_spells(player)
    local result = {}
    local quick_inventory = get_quick_inventory(player)
    if quick_inventory == nil then
        return result
    end

    local wands = EntityGetAllChildren(quick_inventory)
    if wands == nil then
        return result
    end

    -- Noita stores spell cards as children of wand entities, not as direct
    -- children of inventory_quick. This remains read-only until a transfer is clicked.
    for _, wand in ipairs(wands) do
        if EntityHasTag(wand, "wand") then
            for _, spell in ipairs(get_entity_spells(wand)) do
                result[spell.action_id] = (result[spell.action_id] or 0) + 1
            end
        end
    end

    return result
end

function OnWorldPostUpdate()
    local player = get_player()
    if player == nil then
        return
    end

    local current_item = get_active_item(player)
    if not organizer_open and current_item ~= nil and EntityHasTag(current_item, "wand") then
        target_wand = current_item
    end

    -- The organizer is a contextual modal: switching away from the book
    -- immediately closes it instead of leaving an input-blocking overlay.
    if organizer_open and not active_item_is_organizer(player) then
        organizer_open = false
        print("[NoitaInventory] organizer panel closed: organizer is no longer active")
    end

    if InputIsKeyJustDown(OPEN_KEY_CODE) and active_item_is_organizer(player) then
        organizer_open = not organizer_open
        print("[NoitaInventory] organizer panel " .. (organizer_open and "opened" or "closed"))
    elseif InputIsKeyJustDown(ESCAPE_KEY_CODE) and organizer_open then
        organizer_open = false
        print("[NoitaInventory] organizer panel closed")
    end

    if not organizer_open then
        return
    end

    local organizer = get_active_item(player)
    local wand_spells = {}
    if target_wand ~= nil and EntityGetIsAlive(target_wand) then
        wand_spells = get_entity_spells(target_wand)
    end
    local organizer_spells = get_entity_spells(organizer)

    GuiStartFrame(organizer_gui)
    local screen_width, screen_height = GuiGetScreenDimensions(organizer_gui)
    local panel_x = screen_width * 0.5 - 180
    local panel_y = screen_height * 0.5 - 90

    GuiText(organizer_gui, panel_x, panel_y, "SPELL ORGANIZER")
    GuiText(organizer_gui, panel_x, panel_y + 15, "One card per transfer")
    GuiText(organizer_gui, panel_x, panel_y + 38, "Current wand")

    local row = 0
    for index, spell in ipairs(wand_spells) do
        local clicked = GuiButton(organizer_gui, 1000 + index, panel_x, panel_y + 55 + row * 16, "Store " .. spell.action_id)
        if clicked then
            move_one_spell(spell.entity, organizer)
            print("[NoitaInventory] stored one spell: " .. spell.action_id)
        end
        row = row + 1
    end

    if row == 0 then
        GuiText(organizer_gui, panel_x, panel_y + 55, "No cards in target wand")
        row = 1
    end

    local storage_x = panel_x + 190
    GuiText(organizer_gui, storage_x, panel_y + 38, "Organizer")
    local storage_row = 0
    for index, spell in ipairs(organizer_spells) do
        local clicked = GuiButton(organizer_gui, 2000 + index, storage_x, panel_y + 55 + storage_row * 16, "Return " .. spell.action_id)
        if clicked then
            if target_wand ~= nil and EntityGetIsAlive(target_wand) then
                move_one_spell(spell.entity, target_wand)
                print("[NoitaInventory] returned one spell: " .. spell.action_id)
            else
                GamePrint("NoitaInventory: target wand is unavailable")
            end
        end
        storage_row = storage_row + 1
    end

    if storage_row == 0 then
        GuiText(organizer_gui, storage_x, panel_y + 55, "Empty")
        storage_row = 1
    end

    local close_y = panel_y + 75 + math.max(row, storage_row) * 16
    local close_clicked = GuiButton(organizer_gui, 1, panel_x, close_y, "Close")
    if close_clicked then
        organizer_open = false
    end
end

