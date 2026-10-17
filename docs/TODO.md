## Current status

Q fallback code remains retained but disabled; companion mode is the current verified UX.

- `I` opens vanilla inventory and the compact companion organizer;
- closing vanilla inventory closes the companion;
- Search input and FROZEN focus behavior work;
- live spell icons and counts render;
- one click returns one real spell entity to the first free `inventory_full` slot;
- releasing a slot no longer produces the previously observed bomb hover flicker.

The only known cosmetic limitation is engine-owned material identification: when Noita shows the native material label over a world block, interactive spell widgets may appear dimmed. This does not change entity state or transfer behavior.

## Current GUI contract

- One persistent `organizer_gui`.
- Exactly one `GuiStartFrame(organizer_gui)` per update, including hidden frames.
- Q fallback code remains retained but disabled; companion mode is the current experimental UX.
- The compact panel is passive except for Search; categories, spell cells, and Absorb use manual screen-coordinate hit testing.
- Stored cards are grouped by exact `action_id`; groups are display-only.
- Spell cells and category/filter visuals are passive `GuiImage`/`GuiText`; the only interactive widget is Search `GuiTextInput`.
- Custom spell tooltip is same-GUI, post-grid, one per frame, and noninteractive.
- Native category tooltips remain disabled because they can dim earlier widgets.

## Current gameplay contract

```text
I → open vanilla inventory and companion organizer
closing inventory → close companion
Absorb all → move eligible real cards into hidden player-bound storage
stored group click → move exactly one real card to the first free inventory_full slot
```

Wand children, shop/container cards, unknown entities, and direct organizer↔wand transfer remain out of scope.

## Cleanup before release

- Keep `docs/GUI.md` as the research record; do not reintroduce the removed clone/harness notes.
- Keep only assets referenced by the production Lua path.
- Run `git diff --check`, deploy and byte-compare `init.lua`/`settings.lua`, then perform one final user gameplay smoke test.
- Commit and tag only after the smoke test; push only after explicit confirmation.

## Known follow-up

- The native material-tooltip dimming is cosmetic and engine-owned. A future companion mode would require passive rendering plus manual hit testing; it is not part of this release.
- Absorb all remains a separate gameplay test item if the final smoke test exposes a regression.
