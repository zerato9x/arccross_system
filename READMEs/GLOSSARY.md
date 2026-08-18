# ARCCROSS Project Glossary

This file defines project language. It is not a source-code dependency and does
not imply that every term belongs in `GameEnums`.

Unmarked terms are established. Terms still in motion are labeled
**prototype**, **planned**, or **legacy**.

## Foundations

- **ARCCROSS:** A lethal survival game centered on constrained bodies,
  equipment dependence, persistent consequences, and tactical desperation.
- **Base-12:** The project's shared scale and threshold language. Authored
  abstract meters use `0` to `12`; immutable Pillars use `1` to `12`. Fractions
  are valid. Physical measurements retain meaningful units.
- **Make Do Philosophy** *(planned):* The player adapts to the generated body
  through gear, knowledge, positioning, and risk management instead of raising
  its genetic Pillars.
- **Gear Progression:** Equipment is the primary source of practical progression
  during a run.
- **Run:** One disposable survival attempt, including its world,
  body, inventory, injuries, and local consequences.
- **Meta-progression:** Cross-run changes to permanent nodes, gateway state,
  Meta Events, and core reconstruction. It never preserves a dead character or
  increases that character's Pillars.
- **Permanent Meta Node:** A stable Node Web location whose authored identity,
  structural mutations, and Meta Event state survive disposable runs.
- **Seeded Random Node:** A stable Node Web slot whose arm, tier, and content
  profile remain recognizable while its local radius-12 zone regenerates from
  each run seed.
- **Authored Zone Preset:** A baked `AuthoredWorldMap` containing the painted
  469-cell baseline, gameplay layers, decorations, markers, and placement
  sockets for one reusable local-zone layout.
- **Map Socket:** An authored placement contract identified by a stable ID,
  coordinate, kind, direction, and profile tags. Sockets reserve locations for
  POIs, encounters, quest objects, arrivals, or exits; they are not decorative
  sprites and do not own runtime content.
- **Directional Rim Travel:** Leaving a local zone through one of eight screen-
  space sectors (cardinals plus corners) restricts travel to matching graph
  edges; arrival occurs on the opposite rim of the destination zone.
- **Route Preview Ring:** The non-playable radius-13 band outside a local zone.
  Hovering it shows the eligible destination for that boundary sector; clicking
  it from an adjacent radius-12 rim cell opens directional travel.
- **Eviction (Era 9):** Canonical opening beat where Central triage casts the
  player out for insufficient resources. After eviction, Central stays locked
  for that character until all four regional Cores are reassembled (endgame).
  See [Canonical World Specification](CANONICAL_WORLD_SPECIFICATION.md) and
  [Central Core Campaign Overhaul](design/CENTRAL_CORE_CAMPAIGN_OVERHAUL.md).
- **The Glitch (Era 9):** Playable-era condition where fragments of past eras
  appear in the present (places, objects, documents, institutions, anomalies).
  Not a default player-facing UI label. See
  [World Timeline Codex](WORLD_TIMELINE_CODEX.md).
- **The Transcendence:** Classified Primal species event. Primal Consciousness
  refuses, builds Arccross, survives the following Red Mist wipe. Pre-Arccross
  begins after. Never UI exposition. See Codex.
- **The Passing:** Corridor between the North and the rest of the Arms.
  Deliberately collapsed by Central during the Era III northern catastrophe;
  progressively rebuilt through Warden infrastructure; resealed at the end of
  Era VI after Delta’s unintended northern cascade.
- **Orin Vey:** Human prison warden/Handler conscripted for the Final March;
  gathers mixed survivors after the Coldest Night and founds the Wardens through
  routes, shelters, communication, and mutual survival.
- **Patch:** One of the scattered survivable northern communities around the
  perpetual storm's outer edges after Era III.
- **No Man's Land:** Vast perpetual-blizzard interior separating northern
  Patches and Crystal Valley; crossing depends on Warden infrastructure.
- **Barican:** Northern sovereignty movement named for late King Baric. Rejects
  imposed Handle authority and centers Free Mark; settles Crystal Valley late
  Era IV.
- **Free Mark:** Self-directed Mark specialization and the political/economic
  antithesis of Knell's Handle-control business.
- **Arc Automations:** Era I hive machines clearing Core paths. Ended in Era I.
  Not the same threat as Red Mist / Gaps / Cravens.
- **Cravens:** Humans corrupted by Red Mist into mindless hostiles. Distinct
  from Automations. Zeta Corps founded (Era V end) partly to fight them.
- **World Timeline Codex:** Official era chronology. Supersedes older Alpha /
  README era lists.
- **Starter Ring:** The four open Central-adjacent Route 1 nodes and their
  inner-ring links. Each owns a fixed Central-facing-to-outward arterial, but
  the ring contains only one inhabited starter settlement.
- **North Spine (alpha):** The first implemented deep campaign highway —
  `north_random_1..3`, north gateway, and north arm core. All four Route 1 nodes
  are available as starter-ring locations. East/South/West depth is temporarily
  locked by content readiness; long-term Core order is non-linear.
- **Alpha Content Lock:** Temporary travel refusal for unfinished deep
  East/South/West routes. It does not block the four-node starter ring and must
  not be interpreted as lore or mandatory Core order. Detail:
  [Central Core Campaign Overhaul](design/CENTRAL_CORE_CAMPAIGN_OVERHAUL.md).
- **Fixed Logistics Skeleton:** Seed-invariant paved arterial and dirt service
  spur authored for a main node. It is oriented by the node's arm and cannot be
  rerouted by terrain noise, player arrival, or discovery order.
- **Generated Zone Plan:** Transient Generator V2 composition containing the
  469 cell roles, road masks, settlement stamp, rubble, traces, and validation
  results before authoritative hex records are finalized.
- **Zone Composition Plan:** Deterministic pass that assigns budgeted gameplay
  and visual roles across a 469-cell zone before dressing fill.
- **Hex Dressing Template:** Per-hex visual recipe with locked FRAME anchors and
  swappable CORE pools so silhouettes stay coherent while interiors vary.
- **Starter Settlement:** The only inhabited POI in the four-node starter ring.
  The alpha locks it to `north_random_1`; it owns the sole stationary
  wayfinder. Future seed selection must still choose exactly one arm.
- **Road Mask:** Six-bit reciprocal connectivity record for one hex. Each bit
  corresponds to one axial neighbor socket and resolves to a surface-specific
  512×512 overlay without changing terrain authority.
- **Regional Dialect:** Arm- or profile-specific art, landmark, and environmental
  copy bias (Central admin remnant, North frontier scraps, East war debris,
  South Guild logistics, West mining/steel) without cosmic exposition.
- **Core Stabilization:** Permanent Meta transition that resolves an Arm from
  ambiguous Glitch ruins into its authentic historical ruin dialect. It is not
  time travel or pristine restoration.
- **Core Simulation Layer:** Global system direction introduced by a restored
  regional Core: North network/logistics, East people/community/identity, West
  industry/fabrication, South economy/commerce. Combination mechanics remain
  design direction until implemented.
- **SAP:** **Special Arcborn Platoon**; Central Council-controlled Arcborn civil
  protection units paired with Handler Units across Central/East/West/South.
  North is Warden jurisdiction. SAP peacekeeps, rescues, and contains; it does
  not wage wars.
- **Xander Team:** Era VI five-Arcborn Handle super-unit: Alpha offense, Beta
  defense, Charlie support, Delta specialist, Echo recon. Nine teams exist;
  Xander is not yet mecha in Era VI.
- **Crux:** Merchant Guild headquarters and Great Exchange by the Great Sea;
  peak civilization's finance/logistics/technology center and Era VIII last-
  empire megahub.
- **Master Trader:** One of hundreds of Merchant Guild principals. They
  cooperate in Crux but are not politically unified.

## Character Identity

- **Pillar:** One of four immutable genetic axes represented by
  `GameEnums.Pillar`.
- **Brawn:** Physical leverage and natural carrying potential.
- **Finesse:** Coordination, precision, reflex, and physical control.
- **Fortitude:** Structural durability and resistance to physical trauma.
- **Will:** Foundational psychological endurance. Will is not Morale; Morale
  changes during play.
- **Entity Definition:** An authored biological blueprint containing Pillars,
  identity, behavior settings, anomalous properties, and initial loadout.
- **Occupation** *(planned):* A selected background that grants capability IDs,
  knowledge, and starting equipment without changing Pillars.
- **Skill** *(planned):* A learned capability or permission such as Medic,
  Hiding, Trapping, or Mechanic.
- **Trait** *(planned):* A selectable advantageous rule modifier stored as
  extensible content.
- **Flaw** *(planned):* A selectable disadvantage, potentially used to fund
  Traits during character creation.
- **Agenda:** An entity's self-preservation policy: when it continues fighting,
  flees, or ignores danger.
- **Combat Tactic:** An AI scoring profile describing how an entity fights.
- **Faction:** Broad allegiance. Faction is identity, not current hostility or
  relationship state.

## Biology

- **Humanoid Core:** The active-organism aggregate coordinating body state,
  inventory, Morale, Stance, burden, and derived capabilities.
- **Humanoid Body:** The anatomy and vital-state owner for limbs, blood, hunger,
  thirst, fatigue, temperature, and biological ticks.
- **Limb Region:** A closed anatomical target group such as head, torso, arm, or
  leg.
- **Structural Integrity:** The remaining physical condition of a limb.
- **Trauma:** A persistent biological consequence such as bleeding, a shattered
  limb, organ failure, or burns.
- **Blood Level:** Systemic blood volume on the `0` to `12` scale.
- **Metabolic Condition:** A critical survival state such as starvation,
  dehydration, exhaustion, or hypothermia.
- **Motor Efficiency:** A derived mobility measure based on leg integrity and
  Blood Level.
- **Morale:** Dynamic psychological reserve derived initially from Will and
  reduced by danger or injury.
- **Red Mist:** An anomalous environmental hazard that corrupts exposed
  organisms.
- **Red Mist Corruption:** Accumulated Red Mist exposure on the `0` to `12`
  scale.
- **Red Mist Resistance:** A `0` to `12` definition property that reduces
  corruption gain.
- **Arc** *(early):* The anomalous capability system.
- **Arcborn Tier:** A closed Arc classification.

Damage Type describes an attack vector. Trauma describes a resulting condition.

## Items And Inventory

- **Item Definition:** Immutable authored data describing an item and its default
  properties.
- **Runtime Item Instance:** A unique mutable item copy with a stable
  `instance_id` and instance-specific state.
- **Item Type:** A broad functional category such as weapon, armor, consumable,
  tool, ammunition, or junk.
- **Equipment Slot:** A closed Paper Doll location.
- **Paper Doll:** The equipped-item portion of an inventory.
- **Backpack Contents:** Carried Runtime Item Instances that are not equipped.
- **Capacity:** Maximum total Size Cost an inventory can carry. Containers may
  modify it.
- **Size Cost:** Storage space consumed by an item.
- **Weight:** Physical mass contributing to burden.
- **Bulk:** Cumbersome protective mass used by equipment and combat rules.
- **Threat:** Numeric danger or intimidation projected by equipped gear.
- **Effective Threat:** Threat after current biological or stance context is
  applied.
- **Insulation:** Numeric protection against environmental temperature pressure.
- **Protection:** Numeric resistance to a Damage Type.
- **Weapon Class:** A weapon's broad handling and equipment classification.
- **One-Handed Weapon:** A weapon that does not require both hands. It generally
  has lower Weight and Bulk but less Accuracy than a comparable two-handed
  weapon.
- **Two-Handed Weapon:** A weapon that requires both hands. It generally trades
  greater Weight and Bulk for better Accuracy.
- **Accuracy Rating:** A weapon's authored contribution to ranged or melee hit
  resolution. It combines with the wielder and encounter context.
- **Effective Range:** The farthest tactical-grid distance at which a ranged
  weapon may attempt a shot.
- **Optimal Range:** The distance through which a ranged weapon retains full
  authored damage before any configured falloff.
- **Firearm Feed:** The exact loose-ammunition ID and optional magazine, clip,
  or speedloader ID accepted by a firearm.
- **Cycle State:** Runtime firearm state indicating that the weapon is jammed
  and needs the production CYCLE action to clear that jam. Ordinary
  chamber, bolt, and pump cycling is resolved by Fire or Reload rather than
  a separate player-visible prerequisite.
- **Attachment Compatibility:** Authored weapon IDs to which an attachment may
  be fitted. Compatibility metadata does not itself implement the granted
  action.
- **Loadout:** Item definitions used to create initial Runtime Item Instances.
- **Spill:** Capacity overflow converted into persistent ground items instead of
  deleted inventory.
- **Inventory Interface:** The replaceable UI projection (`InventoryUI`, macro
  inventory corner, exploration session strip) that displays neutral inventory
  snapshots and emits item commands. Pocket-device chrome remains deferred.

Size Cost governs storage; Weight contributes to physical burden. Weapon Class
describes a tool; Damage Type describes a hit.

## Combat

- **Combat Encounter:** A temporary tactical simulation built from persistent
  entity records. Production uses one frozen, aware roster with at most six
  actors and no late entry.
- **Squad Grid:** The production seven-column, five-row orthogonal tactical
  board identified by `squad_7x5`.
- **Legacy Lab Topology:** `duel_12x1` or `skirmish_6x3`; a loadable test/Lab
  profile, not production combat authority.
- **Encounter Context:** The reason and deployment condition for combat.
- **Collider:** The entity that deliberately moved into the other entity and
  therefore supplies encounter context and deployment pressure.
- **Ambush Position:** A requested deployment band (FAR / STANDARD / CLOSE)
  translated by CombatCore into authored grid deployment sectors.
- **Direct Player:** The sole encounter actor whose tactical actions come from
  player input. Every other participant is autonomous.
- **Pairwise Relation:** The current friendly, neutral, or hostile relation
  between two actor IDs. Faction or team names do not replace this authority.
- **Action Point (AP):** The normal spendable turn pool capped at `12`. There is
  no reserved reaction AP or second defensive pool.
- **Pending Action Cost:** AP held transactionally between accepted quote and
  commit. It is not a player-controlled reserve and is returned on denial.
- **Burden State:** The Fluid, Labored, or Agonizing physical restriction band
  derived from trauma, equipment, and survival state.
- **Stance:** Encounter-local physical equilibrium on the `0` to `12` scale.
  Stance resets at combat boundaries; wounds and systemic vitals do not.
- **Engagement:** Hostile same-sector occupancy. It is a geometry/relationship
  state, not a facing, posture, or reaction window.
- **Geometry Cover:** Protection authored on the threatened edge of a sector.
  It does not depend on persistent actor facing or rear/flank arcs.
- **Combat Defense:** The allowed composition of wounds, Stance, equipment,
  geometry cover, weapon range, and observable conditions. Block, Dodge,
  posture, facing, and opportunity attacks are retired.
- **Action Quote:** The owner's read-only legality, AP, path, targeting, and
  forecast result for one request. It does not advance RNG or mutate state.
- **Action Timeline:** A committed presentation sequence with independent cue
  marker, body-animation, map-weapon, release-marker, and card-pulse clocks.
- **Combat Interface:** A replaceable presentation boundary.
  `TacticalCombatHUD` is the production turn-command interface.
- **Context Menu Anchor:** The global RMB pointer position forwarded by the
  arena for near-pointer placement. Pointerless input uses the command dock.
- **Combat Outcome:** The shared result emitted when combat ends.
- **Damage Type:** The physical vector of an attack: Blunt, Sharp, or Ballistic.
- **Flesh Damage:** Damage to anatomy and biological health.
- **Stance Damage:** Damage to equilibrium that can create openings without
  directly causing a wound.
- **Ballistic Hit:** A firearm impact that applies authored Flesh Damage to one
  Limb Region and deals `0` Stance Damage.
- **Strike:** The canonical default attack derived for BLUNT and BLADE weapons.
- **Fire:** The canonical default attack derived for PISTOL, RIFLE, and SHOTGUN
  weapons.
- **Specialized Weapon Action:** An additional deterministic action ID authored
  by a weapon and validated against the combat catalog.
- **CYCLE:** Clear an active firearm jam. Ordinary chamber, bolt, and pump
  cycling is resolved by Fire or Reload; production CYCLE is not a post-fire
  or manual-loading action.
- **RELOAD:** Load a firearm through its exact compatible magazine, clip, or
  speedloader.
- **Shove Replan:** Exactly one AI-only plan refresh queued after presentation
  when shove moves an autonomous actor out of hostile Engagement. It grants no
  AP or turn and opens no player prompt.
- **Handoff Layer:** The neutral tactical projection for an actor removed from
  active occupancy but still addressable at its original sector, currently used
  for incapacitated bodies and the `Strip` / `Execute` legality path.
- **Body Layer:** Persistent tactical sector membership for an executed or
  otherwise dead actor. Body projection does not make the actor an active combat
  participant or create ground loot by itself.
- **LEAVE BATTLE:** Neutral terminal action legal when no living actor remains
  hostile to the player. NPC-versus-NPC hostility may continue.
- **Response Marker:** Target presentation timing after impact. It is not a
  gameplay reaction window.
- **HumanInjured Authority:** The event emitted when `HumanoidBody` creates an
  actual Wound. Presentation impact audio is contact only.
- **Retired Combat Actions:** `aimed_strike`, `aimed_fire`, `power_strike`,
  `stand`, `crouch`, `disengage`, `clear_malfunction`, `block`, `dodge`, and
  `opportunity_strike`. Historical documents may mention them but they are not
  catalog authority.

## Macro World

- **Macro World:** The persistent hex-based exploration layer.
- **Hex:** A macro cell identified by axial coordinates.
- **Axial Coordinates:** The `Vector2i(q, r)` coordinate system used for hexes.
- **Biome:** A broad environmental category.
- **Point Of Interest (POI):** An authored or generated location identified by a
  stable content ID.
- **World Seed:** Stable input for repeatable procedural generation.
- **Deterministic Generation:** Generation where the same seed and location
  produce the same initial result.
- **World Map Editor:** The Godot authoring workspace for painted terrain,
  water, flora, rocks, structures, freeform decorations, metadata markers, and
  sockets. `AuthoredWorldMapBaker` converts it into neutral runtime data.
- **Proximity Loading:** Creating and removing nearby presentation nodes without
  changing represented entity state.
- **Active Radius:** Distance within which entity projections are loaded.
- **Unload Radius:** Wider distance beyond which projections are removed.
- **Generation Radius:** Distance within which unexplored encounter records are
  generated.
- **Hysteresis:** The gap between load and unload thresholds that prevents
  boundary thrashing.
- **Entity Projection:** A temporary visual representation of a persistent
  entity. Macro-world tokens, tactical-arena tokens, and the Innawoods Paper Doll
  all project the same Runtime State instead of owning identity or gameplay
  data.
- **Innawoods Paper Doll:** The static inventory portrait projection built from
  authored Innawoods equipment layers.
- **Ground Item Record:** A Runtime Item Instance snapshot stored at a macro
  coordinate.
- **World Time:** Authoritative elapsed run time shared by movement, SEARCH,
  CAMP, combat, and biological processing.
- **Core Restore:** Meta work that reseats a regional Core / unseals its gateway
  and may apply permanent stabilization/dialect patches to that Arm. Spoken as
  infrastructure recovery, not time travel. Four restores in any order gate
  Central re-entry after eviction.

## Architecture

- **Domain Core:** A major ownership boundary: SystemCore, WorldCore,
  CombatCore, BiologicalCore, SoundCore, or ItemCore.
- **SystemCore:** Orchestration, factories, authoritative runtime records, and
  translation between domains.
- **WorldCore:** Hexes, movement, world presentation, proximity loading, and
  macro interactions.
- **CombatCore:** Encounters, tactical grids, turns, AI, action rules,
  resolution, and combat presentation sequencing.
- **BiologicalCore:** Anatomy, vitals, Morale, Stance, Trauma, and biological
  snapshots.
- **SoundCore:** Audio routing, SFX synchronization, and dynamic music timeline management (Audio Conductor).
- **ItemCore:** Item definitions, Runtime Item Instances, inventory rules, and
  equipment calculations.
- **GameEnums:** Shared closed categories interpreted across domain boundaries.
  It is not a glossary, content database, stat sheet, or tuning table.
- **CombatRules:** CombatCore-private categories and tuning tables.
- **Stable ID:** A string identifier that survives node destruction,
  reconstruction, saving, and system transitions.
- **Definition:** Immutable authored starting data.
- **Runtime State:** Mutable authoritative current data.
- **Projection:** A temporary node or UI representation of Runtime State.
- **Snapshot:** Data sufficient to transfer, store, or reconstruct state without
  exposing the owning node.
- **Neutral Record:** A cross-system contract built from engine primitives,
  stable IDs, shared enum values, dictionaries, and arrays.
- **RuntimeStateStore:** The authoritative owner of player, entity, hex,
  world-time, and ground-item records, including their versioned disk save.
- **SaveLoadMenu:** The three-slot save/load UI showing day and timestamp
  metadata. Accessible from the main menu and defeat flow; complements in-game
  `F5` / `F9` quick save and load.
- **GameTimeRules:** Shared action-duration rules and clock-snapshot conversion.
- **Loot Profile:** ItemCore-authored weighted item content and depletion limits.
- **Loot Catalog:** The translation service that exposes neutral item and loot
  descriptors without transferring resource ownership.
- **Presentation Boundary:** UI displays owner-produced snapshots and emits
  intent; it does not resolve gameplay.
- **MetaProgressionStore:** The separate versioned profile owner for completed
  Meta Events, gateway/core state, node-profile mutations, and node-scoped
  structural patches. It never owns characters or ordinary run state.
- **GameDirector:** The SystemCore orchestrator translating records and signals
  between the macro world and combat.

See [System Architecture](SYSTEM_ARCHITECTURE.md) for dependency and ownership
rules.

## Macro Interactions

Live presentation hosts: `MacroExplorationStage` (events, collision sessions,
travel beats) and `MacroExplorationWindow` (SEARCH/CAMP). Domain validation
stays in WorldCore resolvers.

- **Macro Interaction:** A world-layer decision triggered by a landmark POI or
  entity collision.
- **SEARCH:** A POI action using Loot, Safety, Sneak, selected tools, a Loot
  Profile, and persistent depletion.
- **CAMP:** A POI action using Sleep, Shelter, Healing, Concealment, Alertness,
  installed gear (including traps), and elapsed biological time.
- **Loot:** Expected ability to find useful items.
- **Safety:** Expected protection from environmental injury.
- **Sneak:** Expected ability to avoid attracting attention.
- **Sleep:** Expected rest quality.
- **Shelter:** Protection from weather and exposure.
- **Healing:** Recovery support.
- **Concealment:** Protection from discovery.
- **Alertness:** Ability to detect an approaching entity.
- **TALK:** An entity-collision branch offering Threat or Ceasefire. Threat
  success drops non-clothes loot and flees; Ceasefire success opens Ask / Trade
  (Trade remains a placeholder pending economy). ROB is retired.
- **AMBUSH:** An entity-collision branch offering deployment choice with
  opponent summary and combat-grid preview while preserving collider initiative.
- **Entity World Status:** The current combined hostility and presence category
  (including CEASEFIRE for peaceful sessions). Further splits can wait until
  economy / faction work needs them.
- **Field Health HUD:** Authored macro survival presentation driven by
  `HealthHUDProfile` and neutral health snapshots; not a second medical rules
  engine.

SEARCH and CAMP metric names originated in the NEO Scavenger reference and are
not final ARCCROSS terminology.

## Legacy Names

- **The Meat And The Math:** Informal shorthand for biological consequence plus
  explicit mechanical rules.
- **Black Knight Rule:** Prefer **limb-dependent equipment restriction**.
- **Coward's Algorithm:** Prefer **flight response**.
- **Vault System:** Prefer **InventorySystem**, **Capacity**, and **Spill**.
- **Cartographer:** Informal name for `HexWorldGenerator`.
- **Puppet Master:** Prefer `GameDirector` or the specific owning system.
