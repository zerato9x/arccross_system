# ARCCROSS Visual Direction

ARCCROSS uses a severe retro-tactical interface: dark fields, monospace
readouts, wireframe anatomy, and restrained high-contrast alerts. Presentation
should make systemic consequences legible without owning gameplay rules.

See [Combat UI Specification](COMBAT_UI_SPECIFICATION.md) for combat-specific
layout.

## Visual Language

- **Normal information:** amber / warm terminal (`HUDAssetLibrary` Amber Terminal
  default). Cyan Link remains an optional settings scheme.
- **Caution:** brighter amber / caution yellow.
- **Immediate danger:** crimson.
- **Red Mist or anomalous effects:** magenta.
- **Typography:** compact monospace labels with clear numeric hierarchy.
- **Motion:** short, local feedback tied to an event; avoid constant movement
  that competes with decision-making.
- **Texture:** scanlines, phosphor glow, fog, and distortion should remain subtle
  enough to preserve readability.

## Canonical Visual References

Live screenshots live under [`../Mockup/`](../Mockup/). Prefer those over the
historical plates in [`mockups/`](mockups/), which are obsolete layout sketches
only.

## Presentation Contract

HUDs display owner-produced snapshots and emit intent through stable command or
item IDs. Visual replacement must not require gameplay rewiring. The full rule
is defined in [System Architecture](../SYSTEM_ARCHITECTURE.md).

The official `CombatLaneHUD` uses turn action profiles, layered humanoid
animations, ItemCore weapon state, projectile/blood effects, and cinematic
camera profiles. Its command deck is the primary gameplay surface. It uses the
same `HUDAssetLibrary` semantic palette as the rest of the game, retains visible
frames behind top summaries, and keeps action controls separate from the combat
log at compact widths. At high resolutions it increases authored HUD density,
with a cap, instead of leaving 1080p-sized typography stranded in a giant
window. The battlefield may use a local readability tint for a dark source
plate; a global shader should not dim or recolor the tactical UI.
`RealtimeDuelHUD` remains the optional Settings presentation and uses
`RealtimeDuelRuntime` timeline events.

## Macro Map

![Macro map reference](../Mockup/Screenshot%202026-06-30%20000057.png)

Historical plate (obsolete layout): ![legacy macro_map](mockups/macro_map.png)

- Distinguish explored, visible, and unknown Hexes immediately.
- Use a restrained Red Mist overlay for fog of war.
- Movement feedback should communicate terrain cost and environmental danger.
- POIs require silhouettes that remain recognizable at map scale.
- Selected / hovered entities should surface an Innawoods paperdoll inspect when
  present on the hex.

## Exploration HUD

![Exploration HUD reference](../Mockup/Screenshot%202026-06-30%20000148.png)

Historical plate (obsolete layout): ![legacy gameplay_hud](mockups/gameplay_hud.png)

- Keep location, time, immediate biology, and available interactions visible.
- Always-on inventory preview hosts the Innawoods paperdoll plus key gear
  condition (weapons, armor, light, pack).
- Reserve full-screen flashes for severe trauma, collapse, or encounter
  transitions.
- Present warnings as specific conditions, not generic danger decoration.
- Collision / event screens use the opponent paperdoll as the face and place
  player + contact tokens on the lane field preview.

## Inventory

![Inventory reference](mockups/inventory.png)

- Separate equipped slots, backpack contents, and ground items.
- Show Capacity, Size Cost, Weight, and overflow risk without hiding the items.
- Use a body silhouette to make equipment location readable.
- Spill warnings must identify what changed and where displaced items went.

## Field Health HUD

Live host: `FieldHealthHUD` driven by `HealthHUDProfile` snapshots from
`MacroSnapshotBuilder`. Presentation does not reach live `HumanoidBody` or
WorldCore state. (Mockup `medical_monitor.png` is historical reference only.)

- Compact view: six vital tiles plus condition banner; detailed view adds
  systemic readouts and regional wound cards.
- Present local limb structure separately from systemic Blood, fatigue,
  temperature, hunger, and thirst.
- Color communicates severity; labels and values remain available without color.
- A damaged region may flash or shake briefly when updated.
- Crisis effects should identify bleeding, exhaustion, hypothermia, or Red Mist
  corruption rather than applying an undifferentiated vignette.
- Treatment tray uses carried medical items; unsupported care is labeled honestly.

## Loot And Encounters

- Item presentation should emphasize the properties relevant to survival:
  Capacity cost, Weight, protection, Threat, ammunition, and condition.
- Loot notifications should be brief and must not interrupt repeated transfers.
- Entity collisions may introduce a portrait, identity, and current disposition
  before TALK or AMBUSH choices.
- Negotiation feedback should clearly show the selected action and result.

## Asset Policy

- Placeholder and generated assets are acceptable for the demo.
- Store references inside the repository; do not link to local tool caches.
- Prefer a small coherent asset set over many unrelated styles.
- Presentation assets must remain replaceable without changing domain logic.
