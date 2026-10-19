dofile_once("data/scripts/lib/utilities.lua")
dofile_once("data/scripts/gun/gun_enums.lua")

-- Rebuild the live spell deck after Noita's spell-refresh pickup.
ModLuaFileAppend("data/scripts/items/spell_refresh.lua", "mods/spell_organizer/files/spell_refresh_append.lua")

local BRAND_NAME = "Spell Organizer"

-- Organizer is visible only alongside vanilla inventory.
local STORAGE_NAME = "spell_organizer_storage"

local organizer_gui = GuiCreate()
local organizer_open = false
local inventory_was_open = false
local PANEL_W = 154
local PANEL_H = 154
local GRID_W = PANEL_W - 20
local GRID_H = 80
local GRID_COLUMNS = 6
local CELL_W = 20
local CELL_H = 22
local CELL_GAP = 1

local SEARCH_X_OFFSET = 8
local SEARCH_Y_OFFSET = 8
local SEARCH_W = 78
local SEARCH_H = 14
local PICKUP_RADIUS = 24
local stored_search = ""
local SEARCH_INPUT_ACTIVE = false
local SEARCH_INPUT_ID = 9137200

local function freeze_player_controls()
    for _, player in ipairs(EntityGetWithTag("player_unit") or {}) do
        local disabler = EntityCreateNew("spell_organizer_controls_disabler")
        EntityAddTag(disabler, "spell_organizer_controls_disabler")
        EntityAddTag(disabler, "spell_organizer_non_toxic_status")
        EntityAddChild(player, disabler)
        EntityAddComponent2(disabler, "InheritTransformComponent")
        EntityAddComponent2(disabler, "GameEffectComponent", {
            frames = -1,
            disable_movement = true,
            effect = "FROZEN",
        })
    end
end

local function unfreeze_player_controls()
    for _, disabler in ipairs(EntityGetWithTag("spell_organizer_controls_disabler") or {}) do
        local effect = EntityGetFirstComponentIncludingDisabled(disabler, "GameEffectComponent")
        if effect ~= nil then
            ComponentSetValue2(effect, "frames", 1)
        end
    end
end

local function set_search_focus(active)
    if SEARCH_INPUT_ACTIVE == active then return end
    SEARCH_INPUT_ACTIVE = active
    if active then
        freeze_player_controls()
    else
        unfreeze_player_controls()
    end
end

local selected_type = nil -- nil means all action categories
local ACTION_TYPES = {
    { "P", "$inventory_actiontype_projectile", ACTION_TYPE_PROJECTILE },
    { "S", "$inventory_actiontype_staticprojectile", ACTION_TYPE_STATIC_PROJECTILE },
    { "M", "$inventory_actiontype_modifier", ACTION_TYPE_MODIFIER },
    { "D", "$inventory_actiontype_drawmany", ACTION_TYPE_DRAW_MANY },
    { "T", "$inventory_actiontype_material", ACTION_TYPE_MATERIAL },
    { "U", "$inventory_actiontype_utility", ACTION_TYPE_UTILITY },
    { "O", "$inventory_actiontype_other", ACTION_TYPE_OTHER },
    { "V", "$inventory_actiontype_passive", ACTION_TYPE_PASSIVE },
}

local action_metadata = {}
local action_metadata_loaded = false
local function get_action_metadata(action_id)
    if not action_metadata_loaded then
        -- The vanilla table also includes actions appended by enabled mods.
        dofile_once("data/scripts/gun/gun_actions.lua")
        if actions ~= nil then
            for _, action in ipairs(actions) do
                if action.id ~= nil then action_metadata[action.id] = action end
            end
        end
        action_metadata_loaded = true
    end
    return action_metadata[action_id] -- Unknown cards remain in All.
end

local function update_search_focus_from_widget(input_clicked, input_hovered)
    local clicked = input_clicked == true or input_clicked == 1
    local hovered = input_hovered == true or input_hovered == 1
    if clicked then
        set_search_focus(true)
    elseif InputIsMouseButtonJustDown(1) and not hovered then
        set_search_focus(false)
    end
end

local function search_input_is_active()
    return SEARCH_INPUT_ACTIVE
end

local function spell_display_name(action_id)
    local action = get_action_metadata(action_id)
    if action ~= nil and action.name ~= nil then
        return GameTextGetTranslatedOrNot(action.name)
    end
    return action_id
end

local function matches_search(action_id)
    if stored_search == "" then return true end
    local needle = string.lower(stored_search)
    return string.find(string.lower(action_id), needle, 1, true) ~= nil
        or string.find(string.lower(spell_display_name(action_id)), needle, 1, true) ~= nil
end



local function filter_groups(groups)
    local result = {}
    for _, group in ipairs(groups) do
        local action = get_action_metadata(group.action_id)
        if matches_search(group.action_id)
            and (selected_type == nil or (action ~= nil and action.type == selected_type)) then
            table.insert(result, group)
        end
    end
    return result
end


local function set_card_sprite_state(spell)
    -- These are acquired cards. The vanilla card archetype has the normal
    -- icon enabled and the '?' fallback disabled by default. Do not infer
    -- discovery from ItemComponent.is_identified: Noita's action discovery
    -- state is not represented reliably by that serialized field.
    EntitySetComponentsWithTagEnabled(spell, "item_identified", true)
    EntitySetComponentsWithTagEnabled(spell, "item_unidentified", false)
end

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

local function absorb_one(spell, source, organizer)
    if not EntityGetIsAlive(spell) or EntityGetParent(spell) ~= source then
        return false
    end
    if source == 0 then
        EntitySetComponentsWithTagEnabled(spell, "enabled_in_world", false)
    end
    EntityRemoveFromParent(spell)
    EntityAddChild(organizer, spell)
    if EntityGetParent(spell) == organizer then
        return true
    end
    EntityRemoveFromParent(spell)
    if source ~= 0 then
        EntityAddChild(source, spell)
    else
        EntitySetComponentsWithTagEnabled(spell, "enabled_in_world", true)
    end
    print("[SpellOrganizer] absorb failed: " .. tostring(spell))
    return false
end

local function absorb_available_spells(player, organizer)
    local count = 0
    local full_inventory = nil
    for _, child in ipairs(EntityGetAllChildren(player) or {}) do
        if EntityGetName(child) == "inventory_full" then
            full_inventory = child
            break
        end
    end
    if full_inventory ~= nil then
        for _, spell in ipairs(EntityGetAllChildren(full_inventory) or {}) do
            -- Direct children of inventory_full are already owned by the player;
            -- a historical shop cost must not block a legitimately purchased card.
            local action = EntityGetFirstComponentIncludingDisabled(spell, "ItemActionComponent")
            local action_id = action and ComponentGetValue2(action, "action_id")
            if EntityHasTag(spell, "card_action") and action_id ~= nil and action_id ~= "" then
                if absorb_one(spell, full_inventory, organizer) then
                    count = count + 1
                end
            end
        end
    end
    local x, y = EntityGetTransform(player)
    for _, spell in ipairs(EntityGetInRadiusWithTag(x, y, PICKUP_RADIUS, "card_action") or {}) do
        if is_world_spell_candidate(spell, player) then
            local action = EntityGetFirstComponentIncludingDisabled(spell, "ItemActionComponent")
            local action_id = ComponentGetValue2(action, "action_id")
            if action_id ~= nil and action_id ~= "" and absorb_one(spell, 0, organizer) then
                count = count + 1
            end
        end
    end
    if count > 0 then
        GamePlaySound("data/audio/Desktop/misc.bank", "misc/chest_dark_open", x, y)
    end
    return count
end

local function find_full_inventory(player)
    for _, child in ipairs(EntityGetAllChildren(player) or {}) do
        if EntityGetName(child) == "inventory_full" then
            return child
        end
    end
    return nil
end

local function find_free_full_inventory_slot(player)
    local full_inventory = find_full_inventory(player)
    if full_inventory == nil then
        return nil, nil, nil
    end

    local inventory_component = EntityGetFirstComponentIncludingDisabled(player, "Inventory2Component")
    if inventory_component == nil then
        return nil, nil, full_inventory
    end
    local slots_x = ComponentGetValue2(inventory_component, "full_inventory_slots_x") or 0
    local slots_y = ComponentGetValue2(inventory_component, "full_inventory_slots_y") or 0
    if slots_x <= 0 or slots_y <= 0 then
        return nil, nil, full_inventory
    end

    local occupied = {}
    for _, item in ipairs(EntityGetAllChildren(full_inventory) or {}) do
        local item_component = EntityGetFirstComponentIncludingDisabled(item, "ItemComponent")
        if item_component ~= nil then
            local slot_x, slot_y = ComponentGetValue2(item_component, "inventory_slot")
            if slot_x ~= nil and slot_y ~= nil and slot_x >= 0 and slot_y >= 0 then
                occupied[tostring(slot_x) .. ":" .. tostring(slot_y)] = true
            end
        end
    end

    for slot_y = 0, slots_y - 1 do
        for slot_x = 0, slots_x - 1 do
            if not occupied[tostring(slot_x) .. ":" .. tostring(slot_y)] then
                return slot_x, slot_y, full_inventory
            end
        end
    end
    return nil, nil, full_inventory
end

local function drop_one_spell_from_organizer(spell, player)
    if spell == nil or player == nil then
        return false
    end

    local full_inventory = find_full_inventory(player)
    if full_inventory == nil then
        print("[SpellOrganizer] return failed: inventory_full not found")
        return false
    end

    local slot_x, slot_y, full_inventory = find_free_full_inventory_slot(player)
    if full_inventory == nil or slot_x == nil or slot_y == nil then
        GamePrint("Spell Organizer: full inventory is full")
        return false
    end

    local item_component = EntityGetFirstComponentIncludingDisabled(spell, "ItemComponent")
    if item_component == nil then
        return false
    end
    local old_slot_x, old_slot_y = ComponentGetValue2(item_component, "inventory_slot")

    -- EntityAddChild does not allocate a free inventory slot. Set the exact
    -- free ItemComponent.inventory_slot first, otherwise cards retain the
    -- storage/default slot and visually overlap in the vanilla grid.
    ComponentSetValue2(item_component, "inventory_slot", slot_x, slot_y)
    EntityRemoveFromParent(spell)
    EntityAddChild(full_inventory, spell)
    if EntityGetParent(spell) ~= full_inventory then
        EntityRemoveFromParent(spell)
        if old_slot_x ~= nil and old_slot_y ~= nil then
            ComponentSetValue2(item_component, "inventory_slot", old_slot_x, old_slot_y)
        end
        EntityAddChild(get_storage(player), spell)
        return false
    end
    EntitySetComponentsWithTagEnabled(spell, "enabled_in_world", false)
    return true
end

local function get_storage(player)
    for _, child in ipairs(EntityGetAllChildren(player) or {}) do
        if EntityGetName(child) == STORAGE_NAME then
            return child
        end
    end
    local storage = EntityCreateNew(STORAGE_NAME)
    if storage == nil or storage == 0 then
        return nil
    end
    EntityAddChild(player, storage)
    if EntityGetParent(storage) ~= player then
        EntityKill(storage)
        return nil
    end
    return storage
end

-- Called by the spell-refresh pickup append. The engine helper accepts a
-- container and rebuilds ItemAction state for every stored card.
function SpellOrganizerRefreshStoredSpells(player)
    local storage = get_storage(player)
    if storage ~= nil then
        GameRegenItemActionsInContainer(storage)
    end
end

local function migrate_legacy_book(player, storage)
    for _, inventory in ipairs(EntityGetAllChildren(player) or {}) do
        if EntityGetName(inventory) == "inventory_quick" then
            for _, item in ipairs(EntityGetAllChildren(inventory) or {}) do
                if EntityGetFilename(item) == "mods/spell_organizer/files/entities/spell_organizer.xml" then
                    local failed = false
                    for _, card in ipairs(EntityGetAllChildren(item) or {}) do
                        EntityRemoveFromParent(card)
                        EntityAddChild(storage, card)
                        if EntityGetParent(card) ~= storage then
                            EntityRemoveFromParent(card)
                            EntityAddChild(item, card)
                            failed = true
                            print("[SpellOrganizer] migration failed for card: " .. tostring(card))
                        end
                    end
                    if not failed and #(EntityGetAllChildren(item) or {}) == 0 then
                        EntityKill(item)
                        print("[SpellOrganizer] migrated legacy organizer")
                    end
                end
            end
        end
    end
end

function OnModInit()
    print("[SpellOrganizer] loaded")
end

function OnPlayerSpawned(player_entity)
    local storage = get_storage(player_entity)
    if storage ~= nil then
        migrate_legacy_book(player_entity, storage)
    end
end

local function get_player()
    local players = EntityGetWithTag("player_unit")
    if players == nil or #players == 0 then
        return nil
    end
    return players[1]
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

local function action_group_can_return(group, player)
    return drop_one_spell_from_organizer(group.entities[1], player)
end



local TYPE_BACKGROUNDS = {
    [ACTION_TYPE_PROJECTILE] = "projectile",
    [ACTION_TYPE_STATIC_PROJECTILE] = "static_projectile",
    [ACTION_TYPE_MODIFIER] = "modifier",
    [ACTION_TYPE_DRAW_MANY] = "draw_many",
    [ACTION_TYPE_MATERIAL] = "material",
    [ACTION_TYPE_OTHER] = "other",
    [ACTION_TYPE_UTILITY] = "utility",
    [ACTION_TYPE_PASSIVE] = "passive",
}

local function action_background(action_type)
    return "data/ui_gfx/inventory/item_bg_" .. (TYPE_BACKGROUNDS[action_type] or "other") .. ".png"
end

local FILTER_STEP = 15

local function draw_type_filters(x, y)
    local filters = { { "All", "All stored spells", nil } }
    for _, entry in ipairs(ACTION_TYPES) do
        filters[#filters + 1] = entry
    end
    for i, entry in ipairs(filters) do
        local type_value = entry[3]
        local active = (i == 1 and selected_type == nil) or (i > 1 and selected_type == type_value)
        local icon = i == 1
            and "mods/spell_organizer/files/gui/buttons/type_filter_all.png"
            or ("mods/spell_organizer/files/gui/buttons/type_filter_" .. tostring(i - 2) .. ".png")
        if active then
            GuiZSetForNextWidget(organizer_gui, 1)
            GuiImage(organizer_gui, 9137450 + i, x + (i - 1) * FILTER_STEP, y, "mods/spell_organizer/files/gui/buttons/spell_box_0_active.png", 1, 0.8, 0)
        end
        GuiColorSetForNextWidget(organizer_gui, active and 1 or 0.72, active and 1 or 0.72, active and 0.5 or 0.72, 1)
        if GuiImageButton(organizer_gui, 9137400 + i, x + (i - 1) * FILTER_STEP, y, "", icon) then
            selected_type = type_value
        end
        GuiTooltip(organizer_gui, GameTextGetTranslatedOrNot(entry[2]), active and "Selected" or "")
    end
end

local function draw_spell_grid(groups, x, y)
    local cells = {}
    GuiBeginScrollContainer(organizer_gui, 9137500, x, y, GRID_W, GRID_H)
    for index, group in ipairs(groups) do
        local column = (index - 1) % GRID_COLUMNS
        local row = math.floor((index - 1) / GRID_COLUMNS)
        local cell_x = column * (CELL_W + CELL_GAP) + 2
        local cell_y = row * CELL_H + 2
        local action = get_action_metadata(group.action_id)
        local sprite = (action and action.sprite) or action_sprite(group.action_id)
        local clicked = GuiImageButton(organizer_gui, 9137000 + index, cell_x, cell_y, "", sprite)
        GuiTooltip(organizer_gui, spell_display_name(group.action_id) .. " x" .. tostring(#group.entities), group.action_id)
        GuiText(organizer_gui, cell_x + 13, cell_y + 12, tostring(#group.entities), 0.7)
        cells[#cells + 1] = { group = group, clicked = clicked }
    end
    if #groups == 0 then GuiText(organizer_gui, 2, 2, "No stored spells match") end
    GuiEndScrollContainer(organizer_gui)
    return cells
end

local function clear_gameplay_mouse_input(player)
    for _, component in ipairs(EntityGetComponentIncludingDisabled(player, "ControlsComponent") or {}) do
        ComponentSetValue2(component, "mButtonDownFire", false)
        ComponentSetValue2(component, "mButtonDownFire2", false)
        ComponentSetValue2(component, "mButtonDownThrow", false)
        ComponentSetValue2(component, "mButtonFrameFire", 0)
        ComponentSetValue2(component, "mButtonFrameFire2", 0)
        ComponentSetValue2(component, "mButtonFrameThrow", 0)
    end
end

local function mouse_inside_rect(x, y, width, height)
    local mouse_x, mouse_y = DEBUG_GetMouseWorld()
    local camera_x, camera_y, camera_w, camera_h = GameGetCameraBounds()
    local gui_w, gui_h = GuiGetScreenDimensions(organizer_gui)
    mouse_x = (mouse_x - camera_x) * gui_w / camera_w
    mouse_y = (mouse_y - camera_y) * gui_h / camera_h
    return mouse_x >= x and mouse_x <= x + width and mouse_y >= y and mouse_y <= y + height
end

function OnWorldPreUpdate()
    if not GameIsInventoryOpen() then return end
    local player = get_player()
    if player == nil then return end
    local width, height = GuiGetScreenDimensions(organizer_gui)
    local inventory_open = GameIsInventoryOpen()
    local x = width - PANEL_W - 6
    local y = height - PANEL_H - 6
    if mouse_inside_rect(x, y, PANEL_W, PANEL_H) then
        clear_gameplay_mouse_input(player)
    end
end

local function handle_organizer_clicks(cells, player)
    for _, cell in ipairs(cells) do
        if cell.clicked then
            if action_group_can_return(cell.group, player) then
                print("[SpellOrganizer] dropped one spell: " .. cell.group.action_id)
            end
            return
        end
    end
end

function OnWorldPostUpdate()
    GuiStartFrame(organizer_gui)
    local player = get_player()
    if player == nil then
        return
    end

    local storage = get_storage(player)
    if storage == nil then
        organizer_open = false
        return
    end
    migrate_legacy_book(player, storage)

    local inventory_open = GameIsInventoryOpen()
    if inventory_open ~= inventory_was_open then
        set_search_focus(false)
    end
    inventory_was_open = inventory_open
    organizer_open = inventory_open

    if not organizer_open then
        set_search_focus(false)
        return
    end

    GuiIdPushString(organizer_gui, "SPELL_ORGANIZER_GUI")
    GuiOptionsAdd(organizer_gui, GUI_OPTION.DrawAlwaysVisible)
    GuiOptionsAdd(organizer_gui, GUI_OPTION.NoPositionTween)
    GuiOptionsAdd(organizer_gui, GUI_OPTION.HandleDoubleClickAsClick)
    GuiOptionsAdd(organizer_gui, GUI_OPTION.ClickCancelsDoubleClick)
    GuiZSet(organizer_gui, -1000)
    local screen_width, screen_height = GuiGetScreenDimensions(organizer_gui)
    local modal_x = screen_width - PANEL_W - 6
    local modal_y = screen_height - PANEL_H - 6
    local grid_x = modal_x + 10
    local grid_y = modal_y + 54
    if organizer_open and mouse_inside_rect(modal_x, modal_y, PANEL_W, PANEL_H) then
        clear_gameplay_mouse_input(player)
    end
    GuiImageNinePiece(organizer_gui, 10, modal_x, modal_y, PANEL_W, PANEL_H, 1, "data/ui_gfx/decorations/9piece0_gray.png", "data/ui_gfx/decorations/9piece0_gray.png")
    GuiText(organizer_gui, modal_x + 8, modal_y + 8, "Search:")
    stored_search = GuiTextInput(organizer_gui, SEARCH_INPUT_ID, modal_x + SEARCH_X_OFFSET + 38, modal_y + SEARCH_Y_OFFSET, stored_search, SEARCH_W, SEARCH_H, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_0123456789") or stored_search
    local input_clicked, _, input_hovered = GuiGetPreviousWidgetInfo(organizer_gui)
    update_search_focus_from_widget(input_clicked, input_hovered)
    draw_type_filters(modal_x + 8, modal_y + 30)
    local organizer_groups = filter_groups(sort_groups(group_spells(get_entity_spells(storage))))
    local organizer_cells = draw_spell_grid(organizer_groups, grid_x, grid_y)
    handle_organizer_clicks(organizer_cells, player)
    GuiOptionsAddForNextWidget(organizer_gui, GUI_OPTION.DrawNoHoverAnimation)
    if GuiButton(organizer_gui, 9137999, modal_x + 4, modal_y + PANEL_H - 12, "Absorb") then
        local count = absorb_available_spells(player, storage)
        GamePrint("Spell Organizer: absorbed " .. tostring(count))
    end
    GuiIdPop(organizer_gui)
end

