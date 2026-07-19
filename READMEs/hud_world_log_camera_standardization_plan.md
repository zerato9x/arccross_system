# HUD Standardization, World Log Expansion, and Camera Stabilization

## Summary

Preserve the existing severe retro-terminal direction while standardizing every
gameplay HUD: macro corners, World Log, Node Map, inventory, medical,
exploration/event UI, and both combat HUDs. Main menu and debug UI receive only
the shared resolution policy.

### Confirmed defects

- World zoom leaks through fullscreen inventory and non-graph portions of the
  Node Map.
- The Node Map fits at its 420x280 minimum size, then expands without refitting,
  leaving the graph stranded in the upper-left.
- The macro camera has effectively infinite limits and visibly exposes off-map
  background near zone rims.
- Rapid travel can stack camera timers, allowing an older timer to cancel the
  newest look-ahead.
- No logical design resolution exists; raw-window rendering makes HUD text
  microscopic and camera framing resolution-dependent.
- "HUD Scale" affects only macro corner panels and settings. Scaled layout
  constraints can overlap or over-constrain panels.
- The scanline option produces no effect because its texture resolves to null.
- Most `_last_macro_event` updates never reach the World Log. Combat,
  objectives, events, search/rest, treatment, loot, and escape outcomes are
  commonly lost.
- Log history is panel-local, limited to 12 entries, lost on save/load, forcibly
  auto-scrolls, drops consecutive repeated messages, and guesses categories
  from wording.
- Inventory, combat, medical, and Node Map still contain separate
  palette/font/effect constants. Node Map custom drawing bypasses the project
  font.
- Existing smokes validate 1280x720 existence but omit modal input isolation,
  late-resize fitting, saved log history, and ultrawide camera bounds.

## Presentation Foundation

- Establish a 1280x720 logical canvas using `canvas_items` scaling with aspect
  expansion. Anchor every HUD to safe margins and clamp the world camera against
  the resulting logical viewport.
- Extend `HUDAssetLibrary` into the canonical source for semantic colors,
  typography roles, spacing, button sizes, panel styles, and motion timings.
- Separate optional decorative chrome from required icons and overlays so asset
  requests cannot silently become null.
- Apply the existing `hud_scale` setting to every gameplay surface through
  standardized scale roots and `GameSettings.settings_changed`. Keep the
  current saved range of 0.85-1.25.
- Migrate duplicated inventory, combat, and medical colors and undersized fonts
  to shared roles. Preserve layout-specific accents: amber interaction, cyan
  navigation, crimson trauma, and magenta anomaly.
- Standardize local effects around 0.12-second response, 0.18-second feedback,
  and 0.24-second panel-entry timing. Routine events receive local highlights;
  fullscreen flashes remain restricted to severe trauma, collapse, encounter
  transitions, and explicit anomaly events.
- Restore the scanline overlay through required asset loading, subtle opacity,
  and consistent application across gameplay scenes.

## Persistent World Log

- Introduce a serializable `WorldLogEntry` contract containing `sequence`,
  `world_minutes`, `channel`, `severity`, `message`, `context`, `repeat_count`,
  and `routine`.
- Support channels `world`, `travel`, `discovery`, `objective`, `combat`,
  `survival`, `loot`, `interaction`, and `system`. Color is controlled
  separately by `info`, `success`, `warning`, `danger`, or `anomaly` severity.
- Store the newest 100 entries in run state. Add the save field as optional so
  older saves load with an empty history.
- Replace scattered `_last_macro_event` assignments with one owner-facing
  recording API. Route travel, discoveries, objectives, event choices/results,
  combat outcomes, wounds/treatment, item acquisition, search/rest, escape, and
  important NPC threats through it.
- Keep routine NPC turns and debug notices hidden by default.
- Aggregate identical consecutive entries occurring in the same world minute by
  incrementing `repeat_count`. Repeated events at later times remain distinct.
- Keep the current panel as the live tail and add an expanded history state with
  channel filters.
- Preserve the reader's scroll position when they leave the tail and display a
  new-entry affordance instead of forcibly snapping downward.
- Drive row color and effects from typed severity rather than message keyword
  classification. Retain the classifier only as a temporary compatibility
  fallback.

## Camera and Input Ownership

- Remove wheel handling from `MacroCamera._unhandled_input()`. Make
  `MacroGameManager` the sole world-input router and expose explicit camera zoom
  methods.
- Permit world zoom only while the active input context is `WORLD` and the
  pointer is not over a consuming HUD control.
- Inventory, Node Map, settings, medical, event UI, expanded World Log, and
  combat block macro-camera input completely.
- Keep Node Map wheel and pan local to its graph. Defer initial fit until final
  geometry exists, refit on resize while still in auto-fit mode, and preserve
  deliberate user pan/zoom during snapshot refreshes.
- Derive camera bounds from the authored radius-12 zone. Account for viewport
  size and current zoom so the camera never reveals off-map background; raise
  the effective minimum zoom when the viewport would otherwise exceed the zone.
- Replace travel timeout stacking with a cancellable serial or tween. Reset
  look-ahead safely on zone changes, combat handoff/return, teleport, and
  interrupted movement.
- Keep player-centered world zoom and the existing restrained travel
  look-ahead. Opening HUD surfaces must not reframe the world.

## Interfaces and Compatibility

- Add `record_world_event(channel, severity, message, context, routine)` to the
  world/runtime owner and include `world_log` in the HUD snapshot.
- Add explicit `zoom_in()`, `zoom_out()`, `set_zone_bounds()`, and
  `cancel_travel_guidance()` methods to `MacroCamera`.
- Add `blocks_world_input()` to HUD/modal owners so isolation is state-based
  rather than dependent on scene-tree dispatch order.
- Extend the saved-run schema with optional World Log history while preserving
  existing saves and combat/domain boundaries.
- Author scene, theme, and layout changes through the live Godot editor
  integration. UI scripts remain presentation-only and do not acquire gameplay
  legality.

## Test Plan

- Add an input-isolation smoke covering wheel events over Node Map
  graph/inspector, inventory, settings, medical, events, expanded World Log, and
  normal world space. Verify world zoom changes exactly once and only in world
  context.
- Add Node Map resize coverage proving the graph is centered and occupies a
  useful portion of 1280x720, 1920x1080, and 2860x1734 viewports.
- Add camera-bound tests at every radius-12 rim direction and min/max zoom,
  confirming no viewport corner leaves authored map bounds.
- Add travel-interruption tests proving stale timers cannot cancel the latest
  camera guidance.
- Add World Log tests for every channel, typed severity, same-minute
  aggregation, filters, tail-follow behavior, the 100-entry cap, and save/load
  compatibility.
- Add a HUD contract test covering shared theme usage, minimum readable fonts,
  non-null required effects, and global HUD scaling.
- Re-run macro layout, exploration, inventory, Node Map, World Status, realtime
  HUD, combat interface, and camera-focused regressions.
- Finish with live editor screenshots and interaction probes at 1280x720 and
  2860x1734. Use editor-backed validation when the known Godot 4.6.3 standalone
  `signal 11` path appears.

## Scope Defaults

- Cover all gameplay HUDs.
- Persist World Log history for the current run and across save/load.
- Use a curated default feed with category filters.
- Do not restyle main menu, save/load, or debug tools in this pass.
- Preserve existing layouts and the World Log's current visual identity. This
  is a coherent consolidation and bug-fix pass, not another ceremonial UI
  reboot.
