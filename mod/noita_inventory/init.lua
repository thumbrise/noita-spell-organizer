dofile_once("data/scripts/lib/utilities.lua")

-- Press O (configurable in mod settings) to open the player-bound organizer.
local STORAGE_NAME = "noita_inventory_storage"
local OPEN_SETTING_ID = "noita_inventory.open_key"
local ESCAPE_KEY_CODE = 41
local open_key_label = nil
local open_key_code = 18 -- O; see data/scripts/debug/keycodes.lua

local organizer_gui = GuiCreate()
local organizer_open = false
local PANEL_W = 108
local PANEL_H = 180
local CELL_SIZE = 28
local CELL_GAP = 3
local PICKUP_RADIUS = 24


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
    print("[NoitaInventory] absorb failed: " .. tostring(spell))
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

local function drop_one_spell_from_organizer(spell, player)
    if spell == nil or player == nil then
        return false
    end
    local x, y = EntityGetTransform(player)
    EntityRemoveFromParent(spell)
    if EntityGetParent(spell) ~= 0 then
        return false
    end
    EntitySetTransform(spell, x, y + 12)
    -- Experimental vanilla-path probe: put the real card through the
    -- player's inventory pickup/drop ownership path instead of assigning a
    -- custom velocity. The actual GUI throw remains engine-owned.
    GamePickUpInventoryItem(player, spell, false)
    if EntityGetParent(spell) == 0 then
        EntitySetComponentsWithTagEnabled(spell, "enabled_in_world", true)
        set_card_sprite_state(spell)
        return true
    end
    print("[NoitaInventory] vanilla drop probe: pickup path retained card")
    EntityRemoveFromParent(spell)
    EntitySetTransform(spell, x, y + 12)
    EntitySetComponentsWithTagEnabled(spell, "enabled_in_world", true)
    set_card_sprite_state(spell)
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

local function migrate_legacy_book(player, storage)
    for _, inventory in ipairs(EntityGetAllChildren(player) or {}) do
        if EntityGetName(inventory) == "inventory_quick" then
            for _, item in ipairs(EntityGetAllChildren(inventory) or {}) do
                if EntityGetFilename(item) == "mods/noita_inventory/files/entities/spell_organizer.xml" then
                    local failed = false
                    for _, card in ipairs(EntityGetAllChildren(item) or {}) do
                        EntityRemoveFromParent(card)
                        EntityAddChild(storage, card)
                        if EntityGetParent(card) ~= storage then
                            EntityRemoveFromParent(card)
                            EntityAddChild(item, card)
                            failed = true
                            print("[NoitaInventory] migration failed for card: " .. tostring(card))
                        end
                    end
                    if not failed and #(EntityGetAllChildren(item) or {}) == 0 then
                        EntityKill(item)
                        print("[NoitaInventory] migrated legacy organizer")
                    end
                end
            end
        end
    end
end

function OnModInit()
    print("[NoitaInventory] loaded")
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

local function get_open_key_code()
    local label = ModSettingGet(OPEN_SETTING_ID)
    if type(label) ~= "string" or not string.match(label, "^[A-Z]$") then
        label = "O"
    end
    if label ~= open_key_label then
        open_key_label = label
        open_key_code = string.byte(label) - string.byte("A") + 4
    end
    return open_key_code
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
        GuiOptionsAddForNextWidget(organizer_gui, GUI_OPTION.DrawNoHoverAnimation)
        local clicked = GuiImageButton(organizer_gui, 9137000 + index, cell_x, cell_y, "", action_sprite(group.action_id))
        GuiText(organizer_gui, cell_x + 21, cell_y + 20, tostring(#group.entities))
        table.insert(cells, { group = group, clicked = clicked })
    end
    return cells
end



local function handle_organizer_clicks(cells, player)
    for _, cell in ipairs(cells) do
        if cell.clicked then
            if drop_one_spell_from_organizer(cell.group.entities[1], player) then
                print("[NoitaInventory] dropped one spell: " .. cell.group.action_id)
            end
            return
        end
    end
end

function OnWorldPostUpdate()
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

    if GameIsInventoryOpen() then
        organizer_open = false
    end

    if InputIsKeyJustDown(get_open_key_code()) and not GameIsInventoryOpen() then
        organizer_open = not organizer_open
        print("[NoitaInventory] organizer panel " .. (organizer_open and "opened" or "closed"))
    elseif InputIsKeyJustDown(ESCAPE_KEY_CODE) and organizer_open then
        organizer_open = false
        print("[NoitaInventory] organizer panel closed")
    end

    if not organizer_open then
        return
    end

    local organizer_spells = get_entity_spells(storage)
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

    local organizer_cells = draw_spell_grid(organizer_groups, grid_x, grid_y, 2000)
    handle_organizer_clicks(organizer_cells, player)
    GuiOptionsAddForNextWidget(organizer_gui, GUI_OPTION.DrawNoHoverAnimation)
    if GuiButton(organizer_gui, 9137999, modal_x + 10, modal_y + PANEL_H - 22, "Absorb all") then
        local count = absorb_available_spells(player, storage)
        GamePrint("Spell Organizer: absorbed " .. tostring(count))
    end
end

