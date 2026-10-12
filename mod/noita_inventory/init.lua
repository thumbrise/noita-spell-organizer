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

local function group_spells(spells)
    local groups = {}
    local by_action = {}

    for _, spell in ipairs(spells) do
        local group = by_action[spell.action_id]
        if group == nil then
            group = { action_id = spell.action_id, entities = {} }
            by_action[spell.action_id] = group
            table.insert(groups, group)
        end
        table.insert(group.entities, spell.entity)
    end

    return groups
end

local function sort_groups(groups)
    table.sort(groups, function(left, right)
        return left.action_id < right.action_id
    end)
    return groups
end

local function move_one_spell(spell, destination)
    if spell == nil or destination == nil then
        return false, "invalid_item"
    end

    if EntityHasTag(destination, "wand") then
        local capacity = EntityGetWandCapacity(destination)
        local current_spells = get_entity_spells(destination)
        if capacity <= 0 or #current_spells >= capacity then
            return false, "wand_full"
        end
    end

    local previous_parent = EntityGetParent(spell)
    if previous_parent == nil or previous_parent == 0 then
        return false, "item_has_no_parent"
    end

    EntityRemoveFromParent(spell)
    EntityAddChild(destination, spell)

    if EntityGetParent(spell) ~= destination then
        EntityRemoveFromParent(spell)
        EntityAddChild(previous_parent, spell)
        return false, "transfer_failed"
    end

    return true
end

local function get_player_inventory_container(player, container_name)
    local children = EntityGetAllChildren(player)
    if children == nil then
        return nil
    end

    for _, child in ipairs(children) do
        if EntityGetName(child) == container_name then
            return child
        end
    end

    return nil
end

local function move_one_spell_to_inventory(spell, player)
    if spell == nil or player == nil then
        return false, "invalid_item"
    end

    local full_inventory = get_player_inventory_container(player, "inventory_full")
    if full_inventory == nil then
        return false, "inventory_unavailable"
    end

    local inventory2 = EntityGetFirstComponentIncludingDisabled(player, "Inventory2Component")
    if inventory2 == nil then
        return false, "inventory_unavailable"
    end

    local slots_x = ComponentGetValue2(inventory2, "full_inventory_slots_x") or 0
    local slots_y = ComponentGetValue2(inventory2, "full_inventory_slots_y") or 0
    local capacity = slots_x * slots_y
    local items = EntityGetAllChildren(full_inventory) or {}
    if capacity <= 0 or #items >= capacity then
        return false, "inventory_full"
    end

    local previous_parent = EntityGetParent(spell)
    if previous_parent == nil or previous_parent == 0 then
        return false, "item_has_no_parent"
    end

    -- Place the exact spell entity into Noita's dedicated full-inventory
    -- container. GameGetAllInventoryItems counts quick slots too, so it is not
    -- used as the free-space check for this destination.
    EntityRemoveFromParent(spell)
    EntityAddChild(full_inventory, spell)

    if EntityGetParent(spell) ~= full_inventory then
        EntityRemoveFromParent(spell)
        EntityAddChild(previous_parent, spell)
        return false, "transfer_failed"
    end

    return true
end

local function get_inventory_spells(player)
    local result = {}
    local items = GameGetAllInventoryItems(player)
    if items == nil then
        return result
    end

    for _, spell in ipairs(items) do
        local action_component = EntityGetFirstComponentIncludingDisabled(spell, "ItemActionComponent")
        local parent = EntityGetParent(spell)
        -- Current inner loop only exposes cards already in a player inventory
        -- container. Cards nested inside wands are intentionally excluded.
        if action_component ~= nil and parent ~= nil and parent ~= 0 and not EntityHasTag(parent, "wand") then
            local action_id = ComponentGetValue2(action_component, "action_id")
            if action_id ~= nil and action_id ~= "" then
                table.insert(result, { entity = spell, action_id = action_id })
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
    local player_spells = get_inventory_spells(player)
    local organizer_spells = get_entity_spells(organizer)
    local player_groups = sort_groups(group_spells(player_spells))
    local organizer_groups = sort_groups(group_spells(organizer_spells))

    GuiStartFrame(organizer_gui)
    local screen_width, screen_height = GuiGetScreenDimensions(organizer_gui)
    local panel_x = screen_width * 0.5 - 180
    local panel_y = screen_height * 0.5 - 90

    GuiText(organizer_gui, panel_x, panel_y, "SPELL ORGANIZER")
    GuiText(organizer_gui, panel_x, panel_y + 15, "One card per transfer")
    GuiText(organizer_gui, panel_x, panel_y + 38, "Inventory")

    local inventory_row = 0
    for index, group in ipairs(player_groups) do
        local count = #group.entities
        local clicked = GuiButton(organizer_gui, 1000 + index, panel_x, panel_y + 55 + inventory_row * 16, "Store " .. group.action_id .. " x" .. tostring(count))
        if clicked then
            local moved, reason = move_one_spell(group.entities[1], organizer)
            if moved then
                print("[NoitaInventory] stored one spell: " .. group.action_id)
            else
                GamePrint("NoitaInventory: transfer failed (" .. tostring(reason) .. ")")
            end
        end
        inventory_row = inventory_row + 1
    end
    if inventory_row == 0 then
        GuiText(organizer_gui, panel_x, panel_y + 55, "No spells in inventory")
        inventory_row = 1
    end

    local storage_x = panel_x + 190
    GuiText(organizer_gui, storage_x, panel_y + 38, "Organizer")
    local organizer_row = 0
    for index, group in ipairs(organizer_groups) do
        local count = #group.entities
        local clicked = GuiButton(organizer_gui, 2000 + index, storage_x, panel_y + 55 + organizer_row * 16, "Return " .. group.action_id .. " x" .. tostring(count))
        if clicked then
            local moved, reason = move_one_spell_to_inventory(group.entities[1], player)
            if moved then
                print("[NoitaInventory] returned one spell to inventory: " .. group.action_id)
            else
                GamePrint("NoitaInventory: transfer failed (" .. tostring(reason) .. ")")
            end
        end
        organizer_row = organizer_row + 1
    end
    if organizer_row == 0 then
        GuiText(organizer_gui, storage_x, panel_y + 55, "Empty")
        organizer_row = 1
    end

    local close_y = panel_y + 75 + math.max(inventory_row, organizer_row) * 16
    local close_clicked = GuiButton(organizer_gui, 1, panel_x, close_y, "Close")
    if close_clicked then
        organizer_open = false
    end
end

