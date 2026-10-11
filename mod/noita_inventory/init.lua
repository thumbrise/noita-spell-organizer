local MOD_NAME = "NoitaInventory"
local ORGANIZER_GIVEN_KEY = "NOITAINVENTORY_ORGANIZER_GIVEN"
local ORGANIZER_ENTITY = "mods/noita_inventory/files/entities/spell_organizer.xml"

function OnModInit()
    print("[" .. MOD_NAME .. "] loaded")
end

function OnPlayerSpawned(player_entity)
    if GlobalsGetValue(ORGANIZER_GIVEN_KEY, "0") == "1" then
        return
    end

    local x, y = EntityGetTransform(player_entity)
    local organizer = EntityLoad(ORGANIZER_ENTITY, x, y)

    if organizer == nil then
        print("[" .. MOD_NAME .. "] failed to create Spell Organizer")
        return
    end

    GamePickUpInventoryItem(player_entity, organizer, false)
    GlobalsSetValue(ORGANIZER_GIVEN_KEY, "1")
    GamePrint("NoitaInventory: Spell Organizer added")
    print("[" .. MOD_NAME .. "] organizer given: " .. tostring(organizer))
end
