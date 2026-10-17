# TODO — следующий заход

## Текущий блокер: UI-порт Spell Lab Shugged

### Наблюдение пользователя

- Последний UI-тест: счётчик теперь виден без tooltip, но все spell icons выглядят disabled; это UI-layering/regression, не доказательство отключения entity.
- При вводе в Search персонаж продолжает ходить. Нужен keyboard-focus/controls-freezing паттерн Spell Lab Shugged.
- Общая компоновка приемлема, но текущая custom-сетка остаётся менее надёжной, чем проверенный picker Spell Lab Shugged.
- Пользователь выбрал перенос picker-логики Spell Lab Shugged с вырезанием нечестной функциональности, а не дальнейшее изобретение собственного UI.
- Пользователь подтвердил: vanilla wand tooltip больше не отключает organizer UI.
- После запуска с category icons logger показал `Text - no translation for key '$inventory_actiontype_all'`. Это была наша ошибочная ссылка на несуществующий translation key для фильтра All; заменено на literal `All stored spells`. В логе также есть старое предупреждение `mods/spell_lab_shugged/files/lib/shortcut_setting.lua` от отдельного Spell Lab Workshop-мода; Spell Organizer этот путь не вызывает и это не причина ошибки нашего фильтра.
- Последний пользовательский тест: selected category работает; поиск теперь принимает буквы, а `FROZEN` effect проверен пользователем и работает. Осталась визуальная проблема: Search label/input иногда получают чужой tooltip disabled/flicker state.
- Ресерч подтвердил причину overlay при Return: `EntityAddChild(inventory_full, spell)` не распределяет entity по свободному слоту. Позиция хранится в `ItemComponent.inventory_slot` (vec2), а `Inventory2Component.full_inventory_slots_x/y` задаёт размер сетки. Старый код проверял только `#children < capacity`, поэтому несколько карт могли сохранить один и тот же старый/default slot и накладываться. Новый код строит occupancy-map по `inventory_slot`, выбирает первый свободный `(x,y)` row-major, записывает его до `EntityAddChild`, а при отказе восстанавливает parent и старый slot. В игре ещё не проверено.
- Критический баг после игровой проверки: невидимый закрытый organizer иногда продолжал перехватывать fire-click в местах старых spell widgets. Причина: `OnWorldPostUpdate` возвращался до `GuiStartFrame`, поэтому старый GUI frame не сбрасывался. Исправлено: `GuiStartFrame(organizer_gui)` теперь вызывается в начале каждого `OnWorldPostUpdate`, включая скрытое состояние; видимые widgets рисуются только после этого. В игре ещё не проверено.

### Наблюдение пользователя (исторический transfer-блокер)


- Органайзер корректно видит только spell-карты, находящиеся в обычном инвентаре.
- Spell-карты внутри посохов больше не показываются — это правильное поведение для текущего inner loop.
- Перенос `Inventory → Organizer` работает.
- User-confirmed diagnostic: `inventory_quick` child count = 5; `inventory_full` child count = 1; `GameGetAllInventoryItems` count = 6. Quick contains two wands, potion, organizer and one other quick item; full holds one RUBBER_BALL card. Thus overall count 6 is not evidence that full inventory is full.
- Return attempt left the card unchanged under the Organizer (`parent` unchanged) and did not add it to `inventory_full`.
- Transfer implementation now targets the named `inventory_full` entity directly, checks its child count against `full_inventory_slots_x * full_inventory_slots_y`, and rolls back to the Organizer if the parent change fails. This implementation is **not yet user-tested**.

### Текущий упрощённый контракт

```text
Открыть Spell Organizer
    ↓
Inventory: только карты из обычного инвентаря
Organizer: карты, уже помещённые туда
    ↓
Store: ровно один экземпляр Inventory → Organizer
Return: ровно один экземпляр Organizer → обычный Inventory
```

Прямой Organizer → Wand и запоминание конкретного посоха временно исключены.

## Что сейчас в коде

Файл:

```text
mod/spell_organizer/init.lua
```

Текущая логика обнаружения карт:

- вызывает `GameGetAllInventoryItems(player)`;
- проверяет `ItemActionComponent.action_id`;
- исключает карты, чей непосредственный parent имеет tag `wand`;
- группирует одинаковые экземпляры по `action_id` только для отображения;
- кнопка переносит только `group.entities[1]`.

Текущий возврат:

```lua
local x, y = EntityGetTransform(player)
EntitySetTransform(spell, x, y)
GamePickUpInventoryItem(player, spell, false)

if inventory_contains_item(player, spell) then
    return true
end

return false, "inventory_full"
```

`inventory_contains_item` проверяет `GameGetAllInventoryItems(player)`.

Это пока не доказанный рабочий путь. Не считать его исправленным.

## Важное состояние Git

Последний опубликованный commit:

```text
8525592 docs: capture inventory return blocker and current flow
```

Локальная ветка чистая и синхронизирована с `origin/main`.

## Что уже проверено пользователем

- Hello Mod загружается.
- Spell Organizer выдаётся один раз на забег.
- Органайзер не дублируется после save/load.
- Книга открывает временную GUI-панель по B.
- Escape, кнопка Close и переключение с книги закрывают модалку.
- Карты обнаруживались в посохах, затем это поведение намеренно убрано из текущего inner loop.
- Grouping одинаковых карт с `xN` работает.
- Перенос посох → органайзер и обратно в старом прототипе работал.
- Защита от переполнения посоха работала в старом прямом wand-flow.
- Новый flow должен тестироваться заново после восстановления возврата в обычный инвентарь.

## Следующее расследование

Добавлен временный диагностический режим для одной операции `Return`. Первый тест прошёл, но `logger.txt` содержит только стандартные строки запуска — никаких `RETURN_DIAG` там нет. Поэтому `print()` из Lua не является сейчас надёжным каналом наблюдения.

Диагностика теперь показывается прямо в окне органайзера отдельными короткими строками (GamePrint оказался мелким/слишком многословным на экране):

- `Spell before/after`: ID, parent ID, alive, action_id, filename;
- `Inv before/after`: количество и первые 8 ID/name;
- `Result`: успех либо `pickup not in inventory`.

На скриншоте видно `GameGetAllInventoryItems(player) count=4`, хотя пользователь сообщает, что обычный full inventory пуст, а четыре предмета находятся в quick slots (два посоха, бутылка, органайзер). В `player.xml` действительно два отдельных контейнера: `inventory_quick` и `inventory_full`; `Inventory2Component` задаёт quick slots отдельно от full grid. Поэтому вероятно, что общий счётчик/API не отражает свободные слоты full inventory.

Новая диагностическая версия отдельно перечисляет children и count для `inventory_quick` и `inventory_full` до/после Return, сохраняя общий `GameGetAllInventoryItems` для сравнения. Не менять transfer destination, пока значения не увидены в игре.


## Гипотезы для проверки

1. `GamePickUpInventoryItem` не принимает entity, пока она является дочерней сущностью органайзера, даже после `EntityRemoveFromParent`.
2. Spell-карта требует корректного набора enabled/disabled компонентов при выходе из контейнера.
3. `GameGetAllInventoryItems(player)` не является надёжной проверкой размещения карты в quick/full inventory.
4. `ItemComponent`/`InventoryItemComponent` содержит состояние, которое нужно переключить ванильной функцией, а простой `GamePickUpInventoryItem` не обслуживает такой кастомный контейнер.
5. Кастомный органайзер на базе книги не является полноценным inventory container для ванильного pickup flow.
6. В текущем тесте карта физически остаётся дочерней органайзеру, а сообщение `inventory_full` — наша собственная диагностическая классификация, не сообщение движка.

## Безопасный план следующего захода

1. Сохранить и запушить текущий контекст.
2. Добавить временный debug-log только для одной операции Return.
3. Не менять одновременно GUI, entity XML и storage model.
4. Нажать Return на одной карте в пустом инвентаре.
5. Снять фактический lifecycle entity по кадрам.
6. Выбрать решение на основе логов:
   - либо найти корректный vanilla transfer API;
   - либо временно использовать безопасный промежуточный world-item flow;
   - либо сделать собственный inventory adapter с явной проверкой свободного места.
7. После успешного возврата проверить полный инвентарь и отсутствие потери/дублирования.
8. Только потом добавлять drag-and-drop и UI-панели.

## UX-направление

Целевая компоновка:

```text
[панель выбора слота в руке]
[панель посохов]              [панель обычного инвентаря]
                               [панель Spell Organizer]
```

Центральная панель — временный диагностический прототип. Не считать её финальным UX.

## Ограничения проекта

- Один клик/drag-and-drop переносит один физический экземпляр.
- Стаки — только отображение количества.
- Не показывать незнакомые/неприобретённые заклинания.
- Не хранить посохи.
- Не возвращать карту напрямую в конкретный посох на текущем этапе.
- Не использовать unsafe API, FFI, DLL или внешнюю базу.
- Не заявлять, что возврат работает, пока пользователь не подтвердит реальный перенос в пустой инвентарь.
