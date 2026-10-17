# Spell Organizer GUI — Noita GUI research and rules

**Status:** research baseline, 2026-10-17  
**Purpose:** stop blind GUI iteration and define a reproducible Noita GUI workflow.

## 1. What the engine actually gives us

Noita exposes an immediate-mode GUI API. A `Gui` object is stateful across frames, but widgets are submitted again every frame. The shipped API documents:

- `GuiCreate`, `GuiDestroy`;
- exactly one `GuiStartFrame(gui)` per persistent GUI per update;
- `GuiOptionsAdd`, `GuiOptionsRemove`, `GuiOptionsClear`;
- `GuiOptionsAddForNextWidget`;
- `GuiZSet`, `GuiZSetForNextWidget`;
- `GuiIdPush`, `GuiIdPushString`, `GuiIdPop`;
- `GuiGetPreviousWidgetInfo`;
- layout layers and scroll containers;
- `GuiTooltip`, auto-box helpers, and image/button widgets.

The GUI is not a DOM and not PHP-style request rendering. A file edit does not hot-reload running Lua. A game restart is required to test Lua changes.

## 2. The one-frame lifecycle rule

For every persistent `Gui` object:

```lua
function update()
    GuiStartFrame(gui) -- exactly once, before any early return
    if not visible then return end
    -- submit all widgets for this frame
end
```

Do not return before `GuiStartFrame`: the previous frame can leave interactive widgets capturing clicks invisibly. This caused the production fire-click bug.

Do not call `GuiStartFrame` twice in one update to fix layering. In Spell Organizer, a second frame reset widget/ID/tooltip state and broke Absorb and clicks.

If multiple GUI objects are used, each gets one frame start per update. Separate GUI objects do not guarantee independent renderer dimming; this must be proven in a minimal harness.

## 3. IDs are identity, not coordinates

Use a namespace for each logical panel:

```lua
GuiIdPushString(gui, "SPELL_ORGANIZER_GUI")
-- all widget IDs in this panel
GuiIdPop(gui)
```

For repeated dynamic cells, use a stable logical key, not the visible array index:

```lua
GuiIdPushString(gui, "SPELL_CELL_" .. action_id)
-- fixed local IDs inside the cell
GuiIdPop(gui)
```

Do not use `base_id + index` as the identity of a live item when the list can shrink, sort, filter, or regroup. Removing one spell shifts indices and can transfer hover/tooltip animation state to a different spell.

Do not randomly change numeric ID ranges. `GuiIdPushString` is the documented collision mechanism; ID collision and visual dimming are separate problems.

## 4. Layout rules

### Use layout inside scroll containers

The Spell Lab `do_scroll_table` pattern is the proven baseline:

```lua
GuiBeginScrollContainer(gui, scroll_id, x, y, width, height)
GuiLayoutBeginVertical(gui, 0, 0)
    GuiLayoutBeginHorizontal(gui, 0, 0)
        -- cell widgets use local coordinates 0,0
    GuiLayoutEnd(gui)
GuiLayoutEnd(gui)
GuiEndScrollContainer(gui)
```

A scroll container is not just a clipping rectangle for arbitrary absolute coordinates. Our absolute-coordinate grid rendered counts/hitboxes but not images reliably. Use layout-managed rows and cells first.

### One cell, one layout occupant

Do not submit hitbox, icon, and count as three sequential layout widgets. They will stand beside one another and their position/height will depend on intrinsic sprite dimensions.

For overlays:

1. submit exactly one widget that owns the cell geometry;
2. call `GuiGetPreviousWidgetInfo` immediately;
3. draw count/overlay in `GuiLayoutBeginLayer` with `Layout_NoLayouting`;
4. end the layer before ending the cell layout.

### Fixed geometry

When a cell must be fixed-size, use a known fixed hitbox/image size and keep the overlay inside those coordinates. Do not derive neighboring layout from arbitrary action sprite dimensions.

## 5. Widget roles

Separate these roles explicitly:

- **interactive owner:** one widget that receives click/hover;
- **visible sprite:** may be a noninteractive image or an action button, but do not accidentally create two interactive owners;
- **overlay:** count, selected frame, or tooltip text; normally `NonInteractive`;
- **tooltip:** separate diagnostic layer only after basic rendering is proven.

Spell Lab uses multiple patterns, not one universal rule:

- `do_action_button`: an interactive action button plus a decorative frame/image;
- `do_fake_action_button`: transparent interactive button, custom tooltip, and a separate visual action sprite marked `NonInteractive`.

Port the complete pattern, not isolated calls. The pattern depends on layout, previous-widget info, ID generation, z handling, and custom tooltip helpers together.

`GUI_OPTION.NonInteractive` means the widget should not own input; it does not magically fix z-order, clipping, asset paths, or prior-widget dimming.

## 6. Hover and dimming

`GuiTooltip` is not a harmless text helper. In this build it can dim earlier widgets, and the dimmed set depends on widget order, hover owner, and current GUI state. Symptoms changed after Alt+Tab and when dynamic lists changed.

Rules:

- Do not use standard `GuiTooltip` in the first render harness.
- First prove static sprite + count + click with no tooltip.
- Then add custom tooltip text in a separate layer or GUI.
- Mark tooltip text `NonInteractive`.
- Test tooltip with fixed widgets before dynamic lists.
- Test vanilla tooltip overlap separately from custom tooltip overlap.
- A second `Gui` object may isolate IDs/layout but is not assumed to isolate renderer-wide dimming until proven.

`DrawNoHoverAnimation` is useful for the interactive owner when hover animation itself is the source of visual changes. It is not a general cure for tooltip dimming.

## 7. Z-order

The shipped API says larger z values are deeper. Compatible community GUI code documents the practical rule as lower z drawing in front. Treat z as an experiment that must be verified with a three-widget harness; do not infer it from comments in a different wrapper.

Spell Lab wraps `GuiZSet`/`GuiZSetForNextWidget` with an accumulated z helper. Copying its numeric z values without its wrapper changes semantics. Either port the wrapper completely or use raw API consistently.

Never mix:

- raw `GuiZSet` values from Spell Lab;
- Spell Lab's accumulated-z wrapper;
- absolute coordinates from our panel;

in one rendering path without a test.

## 8. Tooltip architecture target

The desired final architecture is:

```text
organizer_gui
    opaque panel
    category buttons
    scroll grid
    one interactive owner per spell cell
    count overlays
    Absorb all
    Search

tooltip_gui or custom tooltip layer
    only when hovered
    noninteractive text
    no standard GuiTooltip
    no auto-box until text-only behavior is proven
```

However, a separate GUI is a hypothesis, not a guarantee of renderer isolation. Prove it with a harness before adopting it as a final claim.

## 9. Minimal GUI harness protocol

Before changing the production organizer UI, build a temporary harness with:

1. one fixed local PNG sprite;
2. one vanilla action sprite;
3. one interactive hitbox;
4. one count text;
5. one category button above;
6. one Absorb-like button below;
7. no scroll, then scroll;
8. no tooltip, then custom tooltip;
9. no dynamic list, then remove the middle item;
10. Alt+Tab between each phase.

Record for each phase:

- visible sprite;
- count position;
- hovered widget;
- which earlier widgets dim;
- click result;
- whether the result changes after removing an item.

Only after this harness is stable should the pattern be applied to live spell groups.

## 10. Known failed approaches in this project

- Absolute-coordinate image widgets inside a scroll container: counts/hitboxes worked while images did not reliably render.
- Two sequential layout widgets for one cell: hitbox, icon, and count stood beside one another.
- Standard `GuiTooltip` on spell cells: tabs, Search, Absorb, and tooltip text dimmed unpredictably.
- Auto-box tooltip: tooltip text and unrelated controls dimmed.
- Second `GuiStartFrame` in the same update: empty tooltips and broken Absorb/clicks.
- Index-based widget IDs: removing a spell shifted state to another spell.
- Treating `NonInteractive` as a universal visual fix: it only addresses input ownership.
- Treating a working tooltip as proof that the sprite rendered: tooltip proves a widget/hitbox exists, not that its image layer is visible.
- Guessing that a vanilla action path is wrong before testing a local PNG in the same exact widget context.

## 11. Production change gate

For every GUI change:

```text
read shipped API and reference implementation
→ change one GUI mechanism
→ run git diff --check
→ deploy and compare source/deployed bytes
→ restart noita_dev
→ run one focused harness/in-game test
→ record user-observed result
→ only then continue
```

Do not change storage, transfer, layout, tooltip, and input capture in one iteration. Do not claim a GUI fix from static checks.

## 12. External research findings

The community wiki confirms the shipped model: Noita uses Lua 5.1, the current documented modding API is version 12, `GuiStartFrame` clears GUI options for the next frame, and the public widget functions include `GuiImage`, `GuiImageButton`, `GuiTooltip`, layout layers, scroll containers, and `GuiGetPreviousWidgetInfo`. See the community API reference: https://noita.wiki.gg/wiki/Modding:_Lua_API

The official Nolla modding wiki is useful for mod lifecycle, but its Lua-scripting page is currently only a TODO pointing to `tools_modding/lua_api_documentation.txt`; the shipped files remain the stronger signature source: https://github.com/NollaGames/noita-modding-wiki/blob/master/Lua-scripting.md

Spell Lab Shugged's source is public and confirms the correct reference implementation to study: `files/gui/gui_elements.lua`, `files/gui/gui_utils.lua`, `files/gui/pickers/spell_picker.lua`, and `files/gui/keyboard_focus.lua`. It is not a drop-in library: its helpers rely on shared globals such as `gui`, `next_id`, `previous_data`, z wrappers, custom tooltip helpers, and focus state. Source: https://github.com/shoozzzh/Spell-Lab-Shugged

There are reusable GUI frameworks, but they are not automatically safer for this progression-preserving mod. EZGUI provides an XML/Lua box-model abstraction, while GUSGUI is archived and explicitly recommends built-in GUI functions or Dear ImGui for unsafe mods. Sources: https://github.com/TheHorscht/EZGUI and https://github.com/gustovafing/gusgui

Dear ImGui bindings provide a more conventional retained-immediate UI abstraction and generated signatures, but they require the separate unsafe NoitaDearImGui dependency. It is a possible future tooling choice, not an acceptable silent dependency for the current safe Workshop mod. Source: https://github.com/dextercd/Noita-Dear-ImGui

A current tooltip research example confirms that native item/spell tooltip panels are rendered by a C++ path and that replacing them requires an unsafe, build-locked hook. We must not use that for Spell Organizer; our custom tooltip must remain a normal safe GUI overlay. Source: https://github.com/vitaminmoo/noita-tooltip-example

A Spell Lab community report documents GUI corruption when special menus are open, especially with complex/trigger-heavy wands, and reports panels shifting off-screen. This is evidence that even a mature reference mod has renderer/layout edge cases; it reinforces the harness-first rule rather than proving our exact cause. Source: https://steamcommunity.com/workshop/filedetails/discussion/2297568811/5260782129621919490

## 13. Research conclusion

The next implementation should not be another hand-tuned patch. Build a standalone fixed-widget harness using the shipped API, then port the smallest complete Spell Lab helper contract into a namespaced library. Keep the live-entity organizer data and transfer callbacks outside that presentation library. Do not introduce EZGUI, GUSGUI, Dear ImGui, unsafe hooks, or native tooltip detours unless we explicitly change the Workshop/safety scope.
