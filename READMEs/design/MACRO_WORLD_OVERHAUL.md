# Macro World Overhaul

Supporting lore alignment for the live Directional Node Web.
Does not replace [System Architecture](../SYSTEM_ARCHITECTURE.md) ownership
rules.

**Active Act 1 build bible:** [Central Core Campaign Overhaul](CENTRAL_CORE_CAMPAIGN_OVERHAUL.md)
— eviction → North tutorial, travel seals, asset sort, phased IDE checklist.
Where Act 1 soft language here conflicts with that file, **Central Core wins**.

**World bible:** [Canonical World Specification](../CANONICAL_WORLD_SPECIFICATION.md)  
**Era chronology:** [World Timeline Codex](../WORLD_TIMELINE_CODEX.md)

**Visual generation detail:** [Hex Dressing Templates](HEX_DRESSING_TEMPLATES.md)  
**Asset packs → dialects / alpha homestead ramp:**
[Hex World Asset Overhaul](HEX_WORLD_ASSET_OVERHAUL.md)

**Generated local-zone contract:**
[Hex World Generator V2](HEX_WORLD_GENERATOR_V2.md)

---

## Current opening topology (supersedes older Act 1 soft-seal text below)

- New Game performs resource-backed identity selection and guided eviction,
  then deploys directly to the player's choice of North, East, South, or West
  Route 1. It does not bootstrap through `central_core`.
- The four Route 1 nodes form an open traversable inner ring.
- North Route 1 -> 2 -> 3 is open; East/South/West Route 2/3, gateways, and
  regional Cores are visible but locked.
- Central remains visible and locked until the data-defined milestone observes
  all four persistent regional Core states as restored.
- North Route 2/3 contain deterministic clustered interior nodes. Hidden nodes
  and their stable-ID edges are excluded from the map until their declarative
  discovery rules reveal them.
- Every playable node, including cluster interiors, continues to use the same
  bounded radius-12 local-zone runtime and snapshot lifecycle.
- All four `*_random_1` nodes share the `starter_route_1` ecology and logistics
  contract: 469 cells, a low-hazard fixed paved arterial from the
  Central-facing rim to the outward rim, a short dirt service spur, poor
  exhaustible rubble, and seed-varying surroundings.
- The starter ring contains exactly one inhabited settlement. The alpha locks
  it and the single stationary wayfinder to `north_random_1`; East, South, and
  West have no settlement stamp, inhabited POI, or resident wayfinder.
- The logistics skeleton is invariant across seeds and entry directions.
  Player arrival selects the spawn rim but never generates or reroutes roads.
- North Route 1 remains a cold Central fringe rather than a snow biome: it uses
  plains/mud terrain, a denser corrugated homestead footprint, infrastructure
  clutter, and sparse frost-covered rock accents. Continuous snow starts on
  North Route 2 and intensifies toward the gateway and Core.

The live topology contract is authored in
[`WorldCore/campaign_graph.tres`](../../WorldCore/campaign_graph.tres), not in a
UI controller. References below to 22 fixed nodes, a Central-fringe spawn,
closed Route 1 ring links, or a North-only selectable start are historical and
must not be used as current implementation guidance.

---

## Architecture decision (locked)

Keep the July 16 **Directional Node Web**:

- 22 campaign nodes (Central + four arms + Meta fetch branch)
- True axial **radius-12** local zones (**469** playable cells)
- `PERMANENT_META` vs `SEEDED_RANDOM` persistence split
- Rim travel + Node Map; authored presets as long-term look; seeded composition
  as fallback

Do **not** return to infinite hub+wedge as the campaign model.

---

## Lore alignment (Five Cores → Node Web)

| Lore | Live node class | Shipping note |
| --- | --- | --- |
| Central Core | `central_core` | Build fully first; eviction locks return until endgame |
| North / East / South / West Cores | `*_gateway` + `*_core` | Permanent Meta; restore = terraform hook |
| Approaches / wastes | `*_random_1..3` | Seeded zones; Act 1 fills **north** densely |
| Meta component work | fetch branch (re-home to north spine for Act 1) | North Regulator remains the first restore loop |

Regional dialects (art, landmarks, SiteCatalog copy) must match Era 9
**Glitch** scraps (past-era wreckage, not live rival capitals):

- **Central** — administrative remnant, overcrowding, bureaucracy
- **North** — sealed-Passing aftermath, sparse sacred / Warden-frontier scraps
- **East** — civil-war / oppression debris (Era VII East Core fall)
- **South** — Guild logistics leftovers; rare carbon as scarce, not default
- **West** — mining / steel / Man-Eater / Zeta scrap

Never explain Marks, Primal Civilization, The Transcendence, or full Core
purpose in UI text. Chronology:
[World Timeline Codex](../WORLD_TIMELINE_CODEX.md).

---

## First scenario — Eviction (Act framing)

Canonical beat (from the world bible):

1. Central houses the last Core and its population; capacity is maxed.
2. Player is **evicted** by resource triage (ordinary resident, not hero).
3. **Central is locked** for that character until **all four regional Cores**
   are reassembled.
4. Re-entry to Central is the **main endgame**, implemented later.

### Design / build order

Implementation order lives in
[Central Core Campaign Overhaul](CENTRAL_CORE_CAMPAIGN_OVERHAUL.md). Summary:

1. Author Central as a finished place (hub stamp + districts) even though the
   player loses free access after eviction.
2. Ship Act 1 on Central fringe + **North spine** with **North Pointer Tutorial**.
3. **Hard-seal E/S/W** (rim + Node Map grey/non-traversable). No thin E/S/W
   wander loops in Act 1.
4. Defer four-Core Central re-entry endgame until later acts.

### Tone rules

- Eviction reads as paperwork and scarcity, not destiny.
- Logs and NPCs talk rations, quotas, sealed gates — not cosmology.

---

## Act 1 scope — Central + North spine

### Playable

| Area | Nodes | Job |
| --- | --- | --- |
| Central (pre-lock / authoring) | `central_core` | Dense hub; eviction staging; Meta install desk |
| North approaches | `north_random_1..3` | Full activity highway |
| North seal | `north_gateway` | Locked until Meta |
| North climax | `north_core` | First Core restore / terraform hook |
| Meta fetch | re-homed onto north spine (or single north-adjacent spur) | Regulator / component beat |

### Soft freedom (anti-boredom without hollow continents)

- **Fat local wander:** 469-cell zones stay wide; side POIs and dressing variety
  inside Central/north satisfy most “I want to roam” urge.
- **North side spurs:** optional caches / encounters off Route 1–3 (same arm).
- **Sealed arm teases:** E/S/W visible on Node Map / rim preview as grey locked
  approaches; travel disabled. Other `*_random_1` nodes are visible-but-sealed.

### Hard seals (Act 1)

- E/S/W **gateways, arm cores, and Route travel** are non-traversable.
- Central→E/S/W edges refuse travel after eviction.
- Do not open unfinished arms to “fix” boredom; deepen north + hub instead.
- Detail and Meta flags:
  [Central Core Campaign Overhaul](CENTRAL_CORE_CAMPAIGN_OVERHAUL.md).

---

## Zone composition (all 469 cells)

Generator V2 composes authoritative logistics separately from seeded
surroundings:

1. Resolve node/profile, world seed, actual arrival, and fixed arm directions.
2. Generate terrain, moisture, drainage, vegetation, and human-pressure fields.
3. Apply the rotated Central-rim → outward-rim paved arterial.
4. Apply the North-only settlement stamp and a short dirt service spur.
5. Grow rubble, forests, scrub, rocks, traces, and quiet terrain from seeded
   adjacency-aware rules.
6. Assign gameplay authority and reciprocal road masks.
7. Fill fitted dressing recipes; use light scatter only on quiet cells.
8. Validate budgets, reachability, sockets, seams, assets, and overflow.

At least 60% of each starter zone stays free of POIs, structures, and
searchable fixtures so roads, the sole settlement, and terrain masses remain
readable. Profiles own budgets and palettes; generated plans own composition;
props remain presentation-only.

Details: [Hex World Generator V2](HEX_WORLD_GENERATOR_V2.md) and
[Hex Dressing Templates](HEX_DRESSING_TEMPLATES.md).

---

## Meta Core restore

**Shipped reference:** North Core Regulator — fetch → return/install context →
unseal `gateway_north_unsealed`.

**Act 1:** keep one clear north restore loop; move fetch off a disabled east arm
if E travel is sealed.

**Later endgame:** four restores unlock Central re-entry (eviction contract).
Visual terraform = permanent Meta structural / dialect patches on that arm’s
permanent nodes — spoken as infrastructure recovery, not miracle lore.

---

## Authored vs seeded

| Node class | Approach |
| --- | --- |
| Permanent Meta (Central, gateways, arm cores, fetch) | Authored presets first when ready |
| Seeded north routes | Composition + dressing; optional presets later |
| E/S/W seeded | Stub profiles only until those acts |

---

## Implementation phases

Phased IDE checklist (0–9) lives only in
[Central Core Campaign Overhaul](CENTRAL_CORE_CAMPAIGN_OVERHAUL.md).

Supporting docs (this file + bible + dressing) are landed. **Phase 0** of
[Central Core Campaign Overhaul](CENTRAL_CORE_CAMPAIGN_OVERHAUL.md) is complete.
Runtime phases start at asset sort and Act 1 seals.

---

## Non-goals

- Rewriting Node Web radius or persistence ownership
- Player-facing cosmic exposition
- Baking roads into terrain hex PNGs
- Shipping four full arms in Act 1
- Treating Central as an always-on midgame home after eviction
- Optional thin E/S/W wander in Act 1

---

## Success criteria (Act 1)

See [Central Core Campaign Overhaul](CENTRAL_CORE_CAMPAIGN_OVERHAUL.md) success
criteria. Short form:

- Central reads as an overcrowded administrative seat; hub stamp authoritative
- North Route 1→3 is the only open campaign highway after eviction
- E/S/W cannot be traversed; Node Map shows them grey
- Eviction → Central lock → four-Core return is documented; lock systems trail
  content only as listed in the Central Core phases
- Same seed → stable zone composition / dressing
