# Hex Dressing Templates

Visual generation language for radius-12 local zones.
Gameplay authority stays on hex records, markers, and sockets — not props.

**Parent contracts:** [Central Core Campaign Overhaul](CENTRAL_CORE_CAMPAIGN_OVERHAUL.md)
(Act 1 build / asset sort) · [Macro World Overhaul](MACRO_WORLD_OVERHAUL.md)
(Node Web lore alignment)

**World tone:** [Canonical World Specification](../CANONICAL_WORLD_SPECIFICATION.md)

---

## Goal

Generate hexes that look **authored** while remaining **seed-random**.

Rule:

> **Layout stays. Contents swap.**

FRAME anchors (shrubs, crates, lamps, poles) keep fixed offsets.
CORE masses (buildings, rock fields, ponds, rubble, hub kits) roll from tagged
pools.

---

## Why scatter is not enough

`MacroZoneGenerator` cluster scatter varies offsets freely. That creates clutter,
not readable silhouettes (tower hex, pond hex, rubble hex, hub hex).

Dressing templates preserve silhouette language across the **469** cells while
still varying interiors.

---

## Schema

### HexDressingTemplate

| Field | Meaning |
| --- | --- |
| `template_id` | Stable id, e.g. `plains_landmark_tower_v1` |
| `role` | `HUB`, `TOWER`, `WAREHOUSE`, `ADMIN`, `ROCKS`, `PEAKS`, `POND`, `RUBBLE`, `SCRUB`, `EMPTY`, `ROAD_EDGE`, `LANDMARK_*` |
| `biome_tags` / dialect tags | `plains`, `central`, `north`, … |
| `weight` | Selection weight inside a role |
| `base_terrain` | Terrain-only preference (no baked props) |
| `slots[]` | Anchored fill slots |

### Slot

| Field | Meaning |
| --- | --- |
| `slot_id` | `core`, `frame_a`, … |
| `kind` | `CORE` \| `FRAME` \| `ACCENT` \| `OVERLAY` |
| `anchor` | Offset from hex center (**author-fixed**) |
| `pool_tags` | Which asset pools may fill this slot |
| `lock_position` | Always true for FRAME / ACCENT |
| `required` / `allow_empty` | CORE usually required; ACCENT may empty |
| `scale` / jitter | Small range only |
| `flip_h_chance` | Optional |

**CORE** — the thing that changes.  
**FRAME** — shrubs/crates/lamps; same places every time.  
**OVERLAY** — future roads (edge stubs); not baked into grass hexes.

---

## Per-hex resolve

Deterministic: `hash(zone_seed + coords + template_id)`.

1. Composition plan assigns **role** (budgets + adjacency).
2. Pick weighted template for role + dialect.
3. Fill slots CORE → FRAME → ACCENT → OVERLAY from pools.
4. Emit decoration records compatible with `HexMapVisualizer` /
   `zone_decorations` (`sprite_path`, fixed `offset`, scale, flip, layer).

Templated hexes do **not** receive random-offset scatter on the same slots.

---

## Zone composition (coherence across 469 cells)

| Axis | Rule |
| --- | --- |
| Ring bands | Core dense; mid quiet; rim = gates/trails |
| Wedges | Dialect bias via `WorldSectorCatalog` / profile |
| Trails | Spine; `ROAD_EDGE` / cleared roles |
| Budgets | Hard caps so towers stay rare |
| Adjacency | Compatible neighbors; cluster rubble/rocks; space tall silhouettes |
| Palette | One shrub/crate/tank family per zone seed |

Central Act 1: ring recipes for hub silhouette (multi-hex HUB / TOWER /
WAREHOUSE stamps), then remnant scrub outward.

---

## Asset contract

1. Base hex = terrain only for templated content.
2. CORE assets declare footprint class (`1x1_center`, `tall`, `wide`, …).
3. FRAME anchors live in the same offset space as current decor props.
4. Pools are tagged path lists — not one-off generator ifs.
5. Infrastructure roads that only cover two iso axes are vignette-only until
   hex-edge OVERLAY pieces exist.

---

## Runtime fit

Reuse decoration dicts; optionally store `dressing_template_id` /
`dressing_role` on debug or hex metadata for smoke tests.

Sockets (`HexMapSocket`) remain **gameplay hooks**. Dressing is visual only.
Bind via `profile_tags` (e.g. farmstead socket → `WAREHOUSE` / homestead role).

Exploration (`SiteCatalog`) can later mirror the same idea: fixed fixture
anchors, swapping search tables — separate from map dressing.

---

## Ship order

See [Hex World Asset Overhaul](HEX_WORLD_ASSET_OVERHAUL.md) Phases B–F.

1. Six to eight templates covering Central + north homestead + north cold mid.
2. Wire planner into `MacroZoneGenerator` after trails/landmarks (profile mix).
3. Central ring recipe pass.
4. North dialect pools (`north` + `default_era8`).
5. Road OVERLAY + single-hex exploration templates (Phase F).

---

## Success criteria

- Same seed → same dressing.
- Same template → FRAME positions stable; CORE (and allowed ACCENT empties) vary.
- Hub and north approaches read as places, not shrub lottery.
- Props never author blockers, travel cost, or POI authority.
