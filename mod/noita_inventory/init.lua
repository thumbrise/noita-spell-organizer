local MOD_NAME = "NoitaInventory"

function OnModInit()
    print("[" .. MOD_NAME .. "] loaded")
end

function OnPlayerSpawned(player_entity)
    GamePrint("NoitaInventory: hello, mod loaded")
    print("[" .. MOD_NAME .. "] player spawned: " .. tostring(player_entity))
end
