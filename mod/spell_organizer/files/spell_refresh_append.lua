-- Spell Organizer extension of Noita's spell-refresh pickup.
-- Preserve vanilla refresh behavior, then refresh the hidden organizer container.
function item_pickup(entity_item, entity_who_picked, name)
    local x, y = EntityGetTransform(entity_item)
    EntityLoad("data/entities/particles/image_emitters/spell_refresh_effect.xml", x, y - 12)
    GamePrintImportant("$itemtitle_spell_refresh", "$itemdesc_spell_refresh")

    GameRegenItemActionsInPlayer(entity_who_picked)
    if SpellOrganizerRefreshStoredSpells ~= nil then
        SpellOrganizerRefreshStoredSpells(entity_who_picked)
    end

    EntityKill(entity_item)
end
