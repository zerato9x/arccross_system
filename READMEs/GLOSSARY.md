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
- **Run** *(planned):* One disposable survival attempt, including its world,
  body, inventory, injuries, and local consequences.
- **Meta-progression** *(planned):* Cross-run unlocks that broaden future choices
  without increasing Pillars during the current run.

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
- **Effective Range:** The farthest Combat Lane distance at which a ranged
  weapon may attempt a shot.
- **Optimal Range:** The distance through which a ranged weapon retains full
  authored damage before any configured falloff.
- **Firearm Feed:** The exact loose-ammunition ID and optional magazine, clip,
  or speedloader ID accepted by a firearm.
- **Cycle State:** Runtime firearm state indicating that its action must be
  cycled before another shot.
- **Attachment Compatibility:** Authored weapon IDs to which an attachment may
  be fitted. Compatibility metadata does not itself implement the granted
  action.
- **Loadout:** Item definitions used to create initial Runtime Item Instances.
- **Spill:** Capacity overflow converted into persistent ground items instead of
  deleted inventory.
- **Inventory Interface** *(prototype):* A replaceable UI projection that
  displays neutral inventory snapshots and emits item commands.

Size Cost governs storage; Weight contributes to physical burden. Weapon Class
describes a tool; Damage Type describes a hit.

## Combat

- **Combat Encounter:** A temporary tactical simulation built from persistent
  entity records.
- **Combat Lane:** The twelve-slot linear tactical space.
- **Encounter Context:** The reason and deployment condition for combat.
- **Collider:** The entity that deliberately moved into the other entity and
  therefore receives opening initiative.
- **Ambush Position** *(prototype):* A requested deployment band translated by
  CombatCore into lane indices.
- **Action Point (AP):** A spendable combat resource.
- **Kinetic Burden:** Derived physical restriction from trauma, encumbrance,
  equipment, and survival crises.
- **Kinetic Tier:** The Fluid, Labored, or Agonizing bracket that converts
  Kinetic Burden into action-cost pressure.
- **Stance Points:** Encounter-local physical equilibrium on the `0` to `12`
  scale. It resets at combat boundaries; wounds and systemic vitals do not.
- **Stance State:** A Stance bracket: Planted (`7-12`), Stumbling (`1-6`), or
  Felled (`0`). A Felled combatant must spend a HEAVY action to GET UP.
- **Recovery Guard:** A one-cycle Stance floor applied after a combatant spends
  a turn recovering from Felled. Incoming pressure may reduce them to `1`
  Stance but cannot Fell them again before their next usable active turn.
- **Melee Lock:** The derived situation in which hostile combatants occupy the
  same lane slot.
- **Action Type:** A shared combat command name, independent of AP cost or
  current legality.
- **Action Category:** A CombatCore-private AP cost class.
- **Action Group:** A command grouping attached to owner-validated action
  descriptors so the UI can present firearm, movement, melee, field, item, and
  reaction choices without recalculating legality.
- **Combat Command Adapter:** The CombatCore boundary that creates snapshots,
  validates player intent, spends AP, and routes accepted commands.
- **Combat Interface:** The replaceable UI projection — currently
  `CombatLaneHUD` — that displays legal actions and emits player intent.
- **Bottom Command Deck:** The bottom-screen combat command
  surface that combines action groups, weapon status, target choices, and
  feedback.
- **Weapon Card:** A combat HUD panel for the active weapon
  sprite, rounds, capacity, range, and readiness state.
- **Gun Animation Catalog:** A presentation-only resolver
  that maps ranged weapon IDs to `Asset/Guns_Animation/` shoot, reload, empty,
  cycle, casing, shell, and muzzle-flash textures.
- **Reserved AP:** AP retained for eligible off-turn reactions.
- **Guard:** The visible pass/reserve combat action. It ends the active turn and
  banks remaining AP as Reserved AP for eligible reactions.
- **Reaction Window:** A bounded opportunity to answer an action with a legal
  reaction.
- **Combat Outcome:** The shared result emitted when combat ends.
- **Damage Type:** The physical vector of an attack: Blunt, Sharp, or Ballistic.
- **Flesh Damage:** Damage to anatomy and biological health.
- **Stance Damage:** Damage to equilibrium that can create openings without
  directly causing a wound. Ordinary pressure floors at `1`; only explicit
  takedown-capable effects may reduce Stance to `0`.
- **Ballistic Hit:** A firearm impact that applies authored Flesh Damage to one
  Limb Region and deals `0` Stance Damage.
- **Strike:** A melee attack whose impact region is resolved randomly from all
  non-head Limb Regions.
- **BREAK STANCE:** A braced melee Stance attack costing MINOR AP. It may Fell an
  already-Stumbling target but ordinary use cannot knock a Planted target
  directly to `0`. Its low cost enables stance-erosion combos.
- **Grapple:** An opposed base-12 takedown check. Success fells the defender;
  failure costs the initiator Stance.
- **CYCLE:** Cycle a firearm action after firing, or hand-load one compatible
  loose round when that weapon supports manual loading.
- **RELOAD:** Load a firearm through its exact compatible magazine, clip, or
  speedloader.
- **GET UP:** Spend HEAVY AP to rise from Felled with `6`
  Stance and Recovery Guard. The remaining AP allows defensive actions
  or an immediate counter.
- **Push:** While Melee Locked, shove the opponent one lane away, stay in place,
  and break the lock.
- **Pull:** While Melee Locked, drag the opponent one lane toward the initiator's
  rear and follow into that lane, preserving the lock.
- **Deprecated Lock Actions:** `PUSH_FOLLOW`, `PULL_STAY`, and `DISENGAGE`
  remain backend compatibility enum values only. They are not legal
  player-facing actions.
- **Execute** *(planned trait action):* A finishing command reserved for a future
  trait unlock. It is disabled in the current demo rules.
- **Grounded Strike:** A Strike against a Felled target automatically targets
  the HEAD, prevents Dodge, and gives armed hits a severe damage multiplier.
- **Fumble Strike:** A free punishment hit triggered when an opponent fails a
  Grapple attempt. No reaction window is opened.

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
- **Proximity Loading:** Creating and removing nearby presentation nodes without
  changing represented entity state.
- **Active Radius:** Distance within which entity projections are loaded.
- **Unload Radius:** Wider distance beyond which projections are removed.
- **Generation Radius:** Distance within which unexplored encounter records are
  generated.
- **Hysteresis:** The gap between load and unload thresholds that prevents
  boundary thrashing.
- **Entity Projection:** A temporary visual representation of a persistent
  entity. Macro-world tokens, combat-lane tokens, and the Innawoods Paper Doll
  all project the same Runtime State instead of owning identity or gameplay
  data.
- **Innawoods Paper Doll:** The static inventory portrait projection built from
  authored Innawoods equipment layers.
- **Ground Item Record:** A Runtime Item Instance snapshot stored at a macro
  coordinate.
- **World Time:** Authoritative elapsed run time shared by movement, SEARCH,
  CAMP, combat, and biological processing.

## Architecture

- **Domain Core:** A major ownership boundary: SystemCore, WorldCore,
  CombatCore, BiologicalCore, SoundCore, or ItemCore.
- **SystemCore:** Orchestration, factories, authoritative runtime records, and
  translation between domains.
- **WorldCore:** Hexes, movement, world presentation, proximity loading, and
  macro interactions.
- **CombatCore:** Encounters, lanes, turns, AI, action rules, and resolution.
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
- **MetaProgressionStore** *(planned):* A separate save owner for cross-run
  unlock IDs.
- **GameDirector:** The SystemCore orchestrator translating records and signals
  between the macro world and combat.

See [System Architecture](SYSTEM_ARCHITECTURE.md) for dependency and ownership
rules.

## Prototype Macro Interactions

- **Macro Interaction** *(prototype):* A world-layer decision triggered by a POI
  or entity collision.
- **SEARCH** *(prototype):* A POI action using Loot, Safety, Sneak, selected
  tools, a Loot Profile, and persistent depletion.
- **CAMP** *(prototype):* A POI action using Sleep, Shelter, Healing,
  Concealment, Alertness, installed gear, and elapsed biological time.
- **Loot:** Expected ability to find useful items.
- **Safety:** Expected protection from environmental injury.
- **Sneak:** Expected ability to avoid attracting attention.
- **Sleep:** Expected rest quality.
- **Shelter:** Protection from weather and exposure.
- **Healing:** Recovery support.
- **Concealment:** Protection from discovery.
- **Alertness:** Ability to detect an approaching entity.
- **TALK** *(prototype):* An entity-collision branch offering Threat, Rob, and
  Ceasefire.
- **AMBUSH** *(prototype):* An entity-collision branch offering deployment
  choice while preserving collider initiative.
- **Entity World Status** *(prototype):* The current combined hostility and
  presence category. It should be split before expansion.

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
