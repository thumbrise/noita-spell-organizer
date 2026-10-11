-- Open the organizer with the default B key during this prototype.
-- Only triggers while the organizer is the player's active item.
local ORGANIZER_GIVEN_KEY = "NOITAINVENTORY_ORGANIZER_GIVEN"
local OPEN_KEY_CODE = 5 -- SDL keycode for B, see data/scripts/debug/keycodes.lua

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

function OnWorldPostUpdate()
    if not InputIsKeyJustDown(OPEN_KEY_CODE) then
        return
    end

    local players = EntityGetWithTag("player_unit")
    if players == nil or #players == 0 then
        return
    end

    local player = players[1]
    local inventory = EntityGetFirstComponentIncludingDisabled(player, "Inventory2Component")
    if inventory == nil then
        return
    end

    local active_item = ComponentGetValue2(inventory, "mActiveItem")
    if active_item == nil or active_item == 0 then
        return
    end

    local filename = EntityGetFilename(active_item)
    if filename ~= "mods/noita_inventory/files/entities/spell_organizer.xml" then
        return
    end

    GamePrint("NoitaInventory: organizer activation detected")
    print("[NoitaInventory] organizer activation detected")
end
