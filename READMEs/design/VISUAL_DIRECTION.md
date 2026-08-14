# ARCCROSS Visual Direction

ARCCROSS uses a severe retro-tactical interface: dark fields, monospace
readouts, wireframe anatomy, and restrained high-contrast alerts. Presentation
should make systemic consequences legible without owning gameplay rules.

The terminal language belongs to interface chrome, instrumentation, and system
readouts. It is not a substitute for environmental art or character staging.
Narrative events must show the place and the people involved when the scene
calls for them; they must not collapse into text-only terminal panels merely to
match the HUD.

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

## Narrative Event Staging

- Major story beats require an authored environmental backdrop and a visible
  character portrait or sprite when an NPC is speaking.
- Dialogue UI may use the terminal palette and typography as an overlay, but the
  scene art remains the visual focus.
- Backdrops, portraits, speaker identity, and dialogue copy are resource-owned
  presentation data. Event controllers select and stage them; controllers do
  not hard-code them.
- "Minimal assets" is not a project-wide art direction. Minimal treatment is
  appropriate only for explicitly abstract diagnostics and debug tools.

## Canonical Visual References

Live screenshots live under [`../Mockup/`](../Mockup/). Prefer those over the
historical plates in [`mockups/`](mockups/), which are obsolete layout sketches
only.

The Central eviction office and current alpha's North Route 1 fringe settlement
are the canonical environmental-art pair for the shipped slice: high-resolution grounded
pixel-art realism, dense worn industrial materials, cold blue-gray atmosphere,
restrained amber practical lights, and lived-in scarcity. New narrative
backdrops should extend this language rather than introduce glossy neon sci-fi,
clean utopian surfaces, or low-resolution retro caricature.

North Route 1 should match that backdrop through corrugated homesteads, crates,
machinery, muddy/plains ground, dead scrub, and sparse frost in sheltered edges.
It must not read as established snow country; continuous snow is reserved for
Route 2 onward so the North journey has a visible climatic escalation.

The settlement backdrop describes the sole current alpha starter settlement,
locked to North as an implementation choice. East, South, and West Route 1 share
the readable plains and logistics language but must not visually imply three
additional inhabited settlements. This does not make North the canonical first
Core campaign.

Starting Arm presentation may intentionally read as ambiguous, corrupted generic
post-apocalypse: Glitch and failed barrier/history state obscure the source era.
Core activation does not restore pristine history. It stabilizes an Arm into an
authentic ruin dialect, making Warden/Barican, House, Western industrial/Zeta,
or Guild/Crux/Xander remains historically legible. Red Mist, barrier remnants,
and environmental presentation may change permanently through Meta progression.

## Hex World Generator V2

- Terrain fills the complete hex silhouette. Edge shadows, black gutters, and
  bevels that reveal tile boundaries are forbidden.
- Use the full approved seamless green-plains family across each 469-cell
  starter zone; variation should read as one landscape rather than repeated
  isolated plates.
- Paved and dirt roads are crisp transparent 512×512 overlays. Curbs, cracks,
  aggregate, compacted soil, and weathering may provide material detail, but
  all six edge sockets must remain visually identical between masks.
- The paved arterial is a logistics landmark: it always joins the
  Central-facing rim to the outward arm rim. Seeded forest, rocks, rubble, and
  scrub frame it without obscuring its route.
- Rubble should be materially larger than shrubs and framed by scattered scrub.
  Tent cells should read as camps with multiple tents and utility details.
- Forests form readable masses; rocks establish strong terrain silhouettes;
  shrubs remain smaller and use off-center placements instead of clustering in
  the center of every hex.

The implementation contract and exact budgets live in
[Hex World Generator V2](HEX_WORLD_GENERATOR_V2.md).

## Presentation Contract

HUDs display owner-produced snapshots and emit intent through stable command or
item IDs. Visual replacement must not require gameplay rewiring. The full rule
is defined in [System Architecture](../SYSTEM_ARCHITECTURE.md).

The official `TacticalCombatHUD` presents the `squad_7x5` arena through catalog
action profiles, layered humanoid animations, ItemCore weapon state,
projectile/blood effects, and restrained camera profiles. Its command dock and
near-pointer context menu are the primary gameplay surfaces. It uses the
same `HUDAssetLibrary` semantic palette as the rest of the game, retains visible
frames behind top summaries, and keeps action controls separate from the combat
log at compact widths. At high resolutions it increases authored HUD density,
with a cap, instead of leaving 1080p-sized typography stranded in a giant
window. The battlefield may use a local readability tint for a dark source
plate; a global shader should not dim or recolor the tactical UI.
Legacy duel and real-time presentations remain Combat Lab/reference material;
they are not production authority.

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
