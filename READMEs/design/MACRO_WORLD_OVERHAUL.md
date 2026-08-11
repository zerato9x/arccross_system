# Macro World Overhaul

Supporting lore alignment for the live Directional Node Web.
Does not replace [System Architecture](../SYSTEM_ARCHITECTURE.md) ownership
rules.

**Active implementation bible:** [Central Core Campaign Overhaul](CENTRAL_CORE_CAMPAIGN_OVERHAUL.md)
— eviction, current alpha boundaries, asset sort, and phased IDE checklist.
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
- Current alpha: North Route 1 -> 2 -> 3 is open; unfinished East/South/West
  Route 2/3, gateways, and regional Cores are visible but locked.
- Long-term canon: all four regional campaigns open and their Cores may be
  restored in any order. No regional Core is the mandatory first act.
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
UI controller. References below to a Central-fringe spawn, closed Route 1 ring
links, a North-only selectable start, or a mandatory North-first Core are
retired and must not be used as current implementation guidance.

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
| North / East / South / West Cores | `*_gateway` + `*_core` | Permanent Meta; restore order is player-chosen |
| Approaches / wastes | `*_random_1..3` | Seeded zones; alpha currently fills **north** deeply |
| Meta component work | fetch branches / regional beats | Each Core owns its layer; no mandatory first restore |

Regional dialects (art, landmarks, SiteCatalog copy) must match Era 9
**Glitch** scraps (past-era wreckage, not live rival capitals):

- **Central** — administrative remnant, overcrowding, bureaucracy
- **North** — sealed-Passing aftermath, sparse sacred / Warden-frontier scraps
- **East** — civil-war / oppression debris (Era VII East Core fall)
- **South** — Guild logistics leftovers; rare carbon as scarce, not default
- **West** — mining / steel / Man-Eater / Zeta scrap

Before restoration, Arms may intentionally read as ambiguous corrupted generic
post-apocalypse because Glitch and failed barriers obscure history. Restoration
does not time-travel or return pristine landscapes; it stabilizes each Arm into
its historically legible ruin dialect and may permanently change Red Mist,
barrier, and presentation state.

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
2. Preserve all four Route 1 deployment choices and starter-ring travel.
3. Ship the North spine first as the alpha's complete deep-content slice; label
   locked E/S/W depth as temporary content availability.
4. Complete all four regional campaigns as non-linear peers, then ship the
   all-four Central re-entry endgame.

### Tone rules

- Eviction reads as paperwork and scarcity, not destiny.
- Logs and NPCs talk rations, quotas, sealed gates — not cosmology.

---

## Current alpha scope — Central contract + North deep-content slice

### Playable

| Area | Nodes | Job |
| --- | --- | --- |
| Central (pre-lock / authoring) | `central_core` | Dense hub; eviction staging; Meta install desk |
| North approaches | `north_random_1..3` | Full activity highway |
| North seal | `north_gateway` | Locked until Meta |
| North climax | `north_core` | Implemented restore/stabilization hook; not canonically first |
| Meta fetch | re-homed onto north spine (or single north-adjacent spur) | Regulator / component beat |

### Playable breadth without hollow continents

- **Fat local wander:** 469-cell zones stay wide; side POIs and dressing variety
  inside Central/north satisfy most “I want to roam” urge.
- **North side spurs:** optional caches / encounters off Route 1–3 (same arm).
- **Starter ring:** all four `*_random_1` nodes and their inner links remain
  playable even while deep E/S/W content is unfinished.

### Temporary alpha locks

- E/S/W Route 2/3, gateways, and Cores remain non-traversable until their
  content is authored; Route 1 remains open.
- Locks are implementation state, not lore barriers or campaign order.
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

## Meta Core restore and simulation layers

**Shipped reference:** North Core Regulator — fetch → return/install context →
unseal `gateway_north_unsealed`. It is the first completed implementation, not
the canonically required first restore.

Four restores unlock Central re-entry. Each activation adds one global layer:

| Core | Simulation layer |
| --- | --- |
| North | Network / logistics: routes, relays, caravans, navigation, connections |
| East | People / community / identity: relationships, recruitment, factions, training |
| West | Industry / fabrication: workshops, refinement, production, construction |
| South | Economy / commerce: trade, contracts, pricing, credit, organizations |

Pairs and triples combine into supply chains, migration, trade routes,
professions, organizations, production, and settlement-scale systems. Exact
mechanics are design direction until implemented. Visual stabilization uses
permanent Meta structural/dialect patches; it reveals authentic ruins rather
than miraculously restoring the past.

---

## Authored vs seeded

| Node class | Approach |
| --- | --- |
| Permanent Meta (Central, gateways, arm cores, fetch) | Authored presets first when ready |
| Seeded north routes | Composition + dressing; optional presets later |
| E/S/W seeded | Alpha stub profiles; later peer regional campaigns |

---

## Implementation phases

Phased IDE checklist (0–9) lives only in
[Central Core Campaign Overhaul](CENTRAL_CORE_CAMPAIGN_OVERHAUL.md).

Supporting docs (this file + bible + dressing) are landed. **Phase 0** of
[Central Core Campaign Overhaul](CENTRAL_CORE_CAMPAIGN_OVERHAUL.md) is complete.
Runtime phases start at asset sort and starter-ring/alpha content legality.

---

## Non-goals

- Rewriting Node Web radius or persistence ownership
- Player-facing cosmic exposition
- Baking roads into terrain hex PNGs
- Shipping four full arms in the current alpha milestone
- Treating Central as an always-on midgame home after eviction
- Encoding the alpha's North-first delivery order as campaign canon

---

## Success criteria

See [Central Core Campaign Overhaul](CENTRAL_CORE_CAMPAIGN_OVERHAUL.md) success
criteria. Short form:

- Central reads as an overcrowded administrative seat; hub stamp authoritative
- All four Route 1 starts and inner-ring links work after eviction
- North Route 1→3 is the current alpha's only complete deep highway
- E/S/W depth shows temporary content locks without implying mandatory Core order
- Eviction → Central lock → four-Core return is documented; lock systems trail
  content only as listed in the Central Core phases
- Same seed → stable zone composition / dressing
