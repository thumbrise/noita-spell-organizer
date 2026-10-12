dofile_once("data/scripts/lib/utilities.lua")

-- Prototype controls: B opens/closes the organizer while it is selected;
-- Escape closes the panel. This milestone only proves GUI lifecycle.
local ORGANIZER_GIVEN_KEY = "NOITAINVENTORY_ORGANIZER_GIVEN"
local OPEN_KEY_CODE = 5 -- SDL keycode for B, see data/scripts/debug/keycodes.lua
local ESCAPE_KEY_CODE = 41
local organizer_gui = GuiCreate()
local organizer_open = false
local PANEL_W = 108
local PANEL_H = 180
local CELL_SIZE = 28
local CELL_GAP = 3
local PICKUP_RADIUS = 24
local PICKUP_COOLDOWN_FRAMES = 8
local pickup_cooldown = 0

local function is_world_spell_candidate(entity, player)
    if entity == nil or entity == 0 or entity == player or not EntityGetIsAlive(entity) then
        return false
    end

    if not EntityHasTag(entity, "card_action") then
        return false
    end
    if EntityHasTag(entity, "item_shop") or EntityHasTag(entity, "shop_cost") then
        return false
    end
    if EntityGetFirstComponentIncludingDisabled(entity, "ItemCostComponent") ~= nil then
        return false
    end
    if EntityGetParent(entity) ~= nil and EntityGetParent(entity) ~= 0 then
        return false
    end
    return EntityGetFirstComponentIncludingDisabled(entity, "ItemActionComponent") ~= nil
end

local function try_pickup_world_spell(player, organizer)
    if pickup_cooldown > 0 then
        return false
    end
    local x, y = EntityGetTransform(player)

    local candidates = EntityGetInRadiusWithTag(x, y, PICKUP_RADIUS, "card_action") or {}
    for _, entity in ipairs(candidates) do
        if is_world_spell_candidate(entity, player) then
            local action = EntityGetFirstComponentIncludingDisabled(entity, "ItemActionComponent")
            local action_id = ComponentGetValue2(action, "action_id")
            -- Disable world-active physics before reparenting the exact card,
            -- otherwise its old world presentation can persist until reequip.
            EntitySetComponentsWithTagEnabled(entity, "enabled_in_world", false)
            EntityRemoveFromParent(entity)
            EntityAddChild(organizer, entity)
            if EntityGetParent(entity) == organizer then
                pickup_cooldown = PICKUP_COOLDOWN_FRAMES
                GamePlaySound("data/audio/Desktop/misc.bank", "misc/chest_dark_open", x, y)
                print("[NoitaInventory] absorbed world spell: " .. tostring(action_id))
                return true
            end
            EntitySetComponentsWithTagEnabled(entity, "enabled_in_world", true)
        end
    end
    return false
end

local function tick_pickup_cooldown()
    if pickup_cooldown > 0 then
        pickup_cooldown = pickup_cooldown - 1
    end
end

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

local function action_sprite(action_id)
    return "data/ui_gfx/gun_actions/" .. string.lower(action_id) .. ".png"
end

local function draw_spell_grid(groups, x, y, widget_prefix)
    local cells = {}
    local columns = 3
    for index, group in ipairs(groups) do
        local column = (index - 1) % columns
        local row = math.floor((index - 1) / columns)
        local cell_x = x + column * (CELL_SIZE + CELL_GAP)
        local cell_y = y + row * (CELL_SIZE + CELL_GAP)
        GuiOptionsAdd(organizer_gui, GUI_OPTION.DrawAlwaysVisible)
        GuiZSet(organizer_gui, -100)
        GuiImage(organizer_gui, 9137000 + index, cell_x, cell_y, action_sprite(group.action_id), 1, CELL_SIZE / 16, 0, 0, GUI_RECT_ANIMATION_PLAYBACK.PlayToEndAndPause)
        GuiText(organizer_gui, cell_x + 21, cell_y + 20, tostring(#group.entities))
        table.insert(cells, { x = cell_x, y = cell_y, group = group })
    end
    return cells
end



function OnWorldPostUpdate()
    local player = get_player()
    if player == nil then
        return
    end

    tick_pickup_cooldown()

    if GameIsInventoryOpen() then
        organizer_open = false
    end

    if active_item_is_organizer(player) then
        try_pickup_world_spell(player, get_active_item(player))
    end

    -- The organizer is tied to the selected book. Switching to a wand or
    -- another item must close the modal before the next frame is drawn.
    if organizer_open and not active_item_is_organizer(player) then
        organizer_open = false
        print("[NoitaInventory] organizer panel closed: organizer is no longer active")
    end

    -- The organizer opens only from the active book when vanilla inventory is shut.
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
    local organizer_spells = get_entity_spells(organizer)
    local organizer_groups = sort_groups(group_spells(organizer_spells))

    GuiStartFrame(organizer_gui)
    GuiOptionsAdd(organizer_gui, GUI_OPTION.DrawAlwaysVisible)
    GuiZSet(organizer_gui, -100)
    local screen_width, screen_height = GuiGetScreenDimensions(organizer_gui)
    local modal_x = screen_width * 0.5 - PANEL_W * 0.5
    local modal_y = screen_height * 0.5 - PANEL_H * 0.5
    local grid_x = modal_x + 12
    local grid_y = modal_y + 32

    GuiImageNinePiece(organizer_gui, 10, modal_x, modal_y, PANEL_W, PANEL_H, 1, "data/ui_gfx/decorations/9piece0_gray.png", "data/ui_gfx/decorations/9piece0_gray.png")
    GuiText(organizer_gui, modal_x + 10, modal_y + 8, "SPELL ORGANIZER")
    GuiText(organizer_gui, grid_x, modal_y + 20, "Stored spells")

    draw_spell_grid(organizer_groups, grid_x, grid_y, 2000)
end

