# Macro World Overhaul

Supporting lore alignment for the live Directional Node Web.
Does not replace [System Architecture](../SYSTEM_ARCHITECTURE.md) ownership
rules.

**Active Act 1 build bible:** [Central Core Campaign Overhaul](CENTRAL_CORE_CAMPAIGN_OVERHAUL.md)
— eviction → North tutorial, travel seals, asset sort, phased IDE checklist.
Where Act 1 soft language here conflicts with that file, **Central Core wins**.

**World bible:** [Canonical World Specification](../CANONICAL_WORLD_SPECIFICATION.md)

**Visual generation detail:** [Hex Dressing Templates](HEX_DRESSING_TEMPLATES.md)

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

Regional dialects (art, landmarks, SiteCatalog copy) must match Era 9 scraps:

- **Central** — administrative remnant, overcrowding, bureaucracy
- **North** — isolation, sparse sacred aftermath, Warden-frontier scraps
- **East** — civil-war debris, oppression ruins
- **South** — Guild logistics leftovers
- **West** — mining / steel / Zetan scrap

Never explain Marks, Primal Civilization, or full Core purpose in UI text.

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

Composition plan runs **before** free decoration scatter:

1. Terrain / moisture noise (existing)
2. Ring bands + wedge tags
3. Trails + rim arrivals/exits
4. Budgeted roles + cluster growth
5. Hex dressing templates (locked FRAME, swap CORE)
6. Light scatter only on EMPTY / SCRUB

Majority of cells stay quiet so landmarks read.

Profiles (`zone_profile_id`) own budgets, palettes, and landmark pool filters.

Detail: [Hex Dressing Templates](HEX_DRESSING_TEMPLATES.md).

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

Supporting docs (this file + bible + dressing) are landed. Runtime phases start
at asset sort and Act 1 seals.

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
