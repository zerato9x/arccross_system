# ARCCROSS Project Glossary

This document defines the language used to discuss ARCCROSS. It is descriptive
documentation, not a source-code dependency.

`GameEnums` is not the glossary. It contains only closed categories that must be
interpreted across system boundaries. Most glossary terms are concepts, numeric
properties, resources, records, or design principles and therefore do not
belong in `GameEnums`.

## Status Labels

- **Established**: Present in the current implementation and safe to use as
  canonical project language.
- **Prototype**: Implemented for testing, but its design or vocabulary is still
  subject to replacement.
- **Planned**: Part of the agreed direction, but not implemented yet.
- **Legacy name**: An informal or older label. Prefer the canonical code term in
  technical discussion.

## Naming Rules

- A **term** explains an idea. It does not automatically require an enum.
- An **enum** represents a finite set of mutually exclusive values.
- A **stat** is a measurable number, such as Threat, Weight, or Insulation.
- A **derived stat** is calculated from authoritative state rather than stored
  as a category.
- A **content ID** identifies extensible authored content such as an occupation,
  trait, flaw, recipe, or POI. Adding content should not require editing
  `GameEnums`.
- In prose, use title case for named mechanics such as **Kinetic Burden**. Use
  code formatting for identifiers such as `total_burden` or
  `GameEnums.KineticTier`.

## Foundations

### ARCCROSS

**Status:** Established

The game and simulation framework. ARCCROSS is a lethal survival game centered
on physical consequence, constrained bodies, equipment dependence, and tactical
desperation.

### Base-12

**Status:** Established

The project's primary mechanical scale and threshold language. Pillars, Action
Points, and Stance use twelve as a defining reference.

Base-12 is not a universal datatype. Blood Level and Red Mist Corruption use
normalized values, limb health can have other ranges, and authored modifiers
may be fractional.

### Make Do Philosophy

**Status:** Planned design principle

The player adapts to the body generated for a run instead of leveling that body
into an ideal build. Weaknesses are compensated for through gear, knowledge,
positioning, and risk management.

### Gear Progression

**Status:** Planned design principle; partially established mechanically

Equipment is the primary source of practical progression during a run. Gear
expands what a body can survive or accomplish; it does not permanently increase
the body's Pillars.

### Run

**Status:** Planned

One disposable survival attempt, including its generated world, player body,
inventory, injuries, and local consequences.

### Meta-progression

**Status:** Planned

Progress retained between runs, primarily expressed as unlocked content IDs.
Meta-progression should broaden future choices rather than increase a Pillar
during the current run.

## Character Identity

### Pillar

**Status:** Established

One of four immutable genetic axes represented by `GameEnums.Pillar`. A Pillar
is a foundational input to other rules, not a complete list of everything an
entity can do.

### Brawn

**Status:** Established

Physical leverage and carrying potential. It currently establishes base
inventory capacity and contributes to force-based actions.

Do not confuse Brawn with **Capacity**, which can be modified by equipment.

### Finesse

**Status:** Established

Coordination, precision, reflex, and physical control. It contributes to
initiative, weapon handling, evasion, and other dexterity-based checks.

### Fortitude

**Status:** Established

The body's structural durability. It contributes to how much physical trauma
limbs can withstand.

### Will

**Status:** Established

Psychological endurance. It establishes starting Morale and contributes to
resistance against intimidation and breaking.

Do not confuse Will with **Morale**. Will is foundational; Morale changes during
play.

### Entity Definition

**Status:** Established

The authored biological blueprint represented by `EntityDefinition`. It
contains Pillars, faction, Agenda, Combat Tactic, Arc properties, and an initial
loadout. Active entities use a duplicated copy so runtime changes do not mutate
the source resource.

### Occupation

**Status:** Planned

A player-selected background that grants capability IDs, starting knowledge,
and a spawn loadout. An occupation does not add a fifth Pillar and should be
authored as data, not added to `GameEnums`.

### Skill

**Status:** Planned

A learned capability or permission, such as Medic, Hiding, Trapping, or
Mechanic. Skills can unlock information, options, or rule modifiers without
changing genetic Pillars.

### Trait

**Status:** Planned

A selectable rule modifier representing an unusual advantage. Traits should be
stable content IDs or resources.

### Flaw

**Status:** Planned

A selectable rule modifier representing a disadvantage, often used to fund
Traits during character creation. Flaws should be stable content IDs or
resources.

### Agenda

**Status:** Established

An entity's self-preservation policy, represented by `GameEnums.Agenda`.
Survivalist, Belligerent, Zealot, and Mindless describe when an entity flees or
ignores danger.

Do not confuse Agenda with **Combat Tactic**. Agenda answers "should I keep
fighting?"; Combat Tactic answers "how do I fight?"

### Faction

**Status:** Established

A broad allegiance represented by `GameEnums.Faction`. Current values are
Unaligned, Scavenger Cell, Arcborn Resistance, and Craven Hive.

Faction is identity, not current hostility. It must not be used as a substitute
for relationship or disposition state.

## Biology

### Humanoid Core

**Status:** Established

The authoritative active-organism aggregate represented by `HumanoidCore`. It
coordinates body state, inventory, Morale, Stance, Kinetic Burden, and derived
capabilities.

### Humanoid Body

**Status:** Established

The anatomy and vital-state owner represented by `HumanoidBody`. It processes
limbs, blood, hunger, thirst, fatigue, temperature, and biological ticks.

### Limb Region

**Status:** Established

A closed anatomical target group represented by `GameEnums.LimbRegion`: head,
upper torso, lower torso, left/right arm, and left/right leg.

### Structural Integrity

**Status:** Established

The remaining physical health of a limb. Loss of structural integrity can cause
persistent Trauma and reduce the body's effective capabilities.

### Trauma

**Status:** Established

A persistent biological consequence represented by `GameEnums.TraumaType`,
such as Bleeding, Shattered Limb, Organ Failure, or Burnt.

Do not confuse Trauma with **Damage Type**. Damage Type describes the attack
vector; Trauma describes a resulting condition.

### Blood Level

**Status:** Established

The body's systemic blood volume, stored as a normalized runtime value. Blood
loss affects survival and Motor Efficiency.

### Metabolic Condition

**Status:** Established

A critical survival state represented by `GameEnums.MetabolicCondition`:
Starving, Dehydrated, Exhausted, or Hypothermia.

### Motor Efficiency

**Status:** Established

A derived measure of mobility calculated from leg integrity and Blood Level. It
feeds Kinetic Burden rather than existing as an enum.

### Morale

**Status:** Established

The entity's dynamic psychological reserve. It begins from Will and falls in
response to injury and danger. Agenda determines how low Morale can fall before
the entity attempts to flee.

### Red Mist

**Status:** Established

An anomalous environmental hazard that can corrupt exposed organisms.

### Red Mist Corruption

**Status:** Established

The active entity's accumulated Red Mist exposure, stored from `0.0` to `1.0`.
It is runtime state, not a Pillar.

### Red Mist Resistance

**Status:** Established

An entity-definition property that reduces corruption gained from Red Mist
exposure.

### Arc

**Status:** Established, mechanically early

The project's anomalous or metaphysical capability system. Entity definitions
currently carry Arc Tier and Arc Energy, but the broader rules remain in early
development.

### Arcborn Tier

**Status:** Established

A closed Arc classification represented by `GameEnums.ArcbornTier`.

## Items And Inventory

### Item Definition

**Status:** Established

An immutable authored `.tres` resource described by `ItemData`. It specifies
what an item is and its default mechanical properties.

### Runtime Item Instance

**Status:** Established

A unique mutable copy of an Item Definition. It has a stable `instance_id` and
can carry state such as magazine contents and cycling requirements.

### Item Type

**Status:** Established

A broad functional category represented by `GameEnums.ItemType`: Junk, Weapon,
Armor, Consumable, or Tool.

### Equipment Slot

**Status:** Established

A closed Paper Doll location represented by `GameEnums.EquipmentSlot`.

### Paper Doll

**Status:** Established

The equipped-item portion of `InventorySystem`, organized by Equipment Slot.

### Backpack Contents

**Status:** Established

Runtime item instances carried but not equipped.

### Capacity

**Status:** Established

The maximum Size Cost an inventory can carry. Base Capacity currently equals
Brawn, while equipped containers can add bonuses.

### Size Cost

**Status:** Established

How much inventory Capacity an item occupies.

Do not confuse Size Cost with **Weight**. Size Cost governs storage; Weight
contributes to physical burden.

### Weight

**Status:** Established

An item stat representing carried physical mass. Equipped Weight contributes to
Kinetic Burden.

### Bulk

**Status:** Established

An equipped-item stat representing cumbersome protective mass. Combat currently
uses positive Bulk as part of defense calculations.

### Threat

**Status:** Established

A numeric projection of how dangerous or intimidating equipped gear appears.
Threat is summed from equipment and interpreted by negotiation and AI rules.

Threat is not a Pillar, skill, faction, or enum.

### Effective Threat

**Status:** Established

Threat after biological context is applied. An entity that is not Planted
currently projects zero Effective Threat.

### Insulation

**Status:** Established

An equipped-item stat that reduces environmental temperature pressure. It is a
numeric property, not a category.

### Protection

**Status:** Established

Numeric resistance supplied by equipment against Blunt, Sharp, or Ballistic
Damage Types.

### Weapon Class

**Status:** Established

A weapon's broad handling and equipment classification, represented by
`GameEnums.WeaponClass`.

Do not confuse Weapon Class with **Damage Type**. A weapon class describes the
tool; Damage Type describes the physical vector of a hit.

### Loadout

**Status:** Established

A collection of item definitions used to create new Runtime Item Instances for
an entity. An initial loadout is superseded by a restored runtime inventory
snapshot.

### Spill

**Status:** Established

The removal of carried items when Capacity falls below current Size Cost.
Spilled items become ground-item records rather than being silently deleted.

## Combat

### Combat Encounter

**Status:** Established

A temporary tactical simulation constructed from persistent entity records.
CombatCore owns its lane, turns, action legality, AI, and resolution.

### Combat Lane

**Status:** Established

The twelve-slot linear tactical space used by a Combat Encounter.

### Encounter Context

**Status:** Established

The reason and deployment condition for a Combat Encounter, represented by
`GameEnums.EncounterContext`: neutral meeting, player ambush, enemy ambush, or
dialogue breakdown.

### Collider

**Status:** Established

The entity that deliberately moved into the other entity on the macro map. The
collider receives opening initiative when the Combat Encounter begins.

### Ambush Position

**Status:** Prototype

The player's requested deployment band for an ambush: Far, Standard, or Close.
CombatCore translates the request into actual lane indices.

### Action Point

**Status:** Established

A spendable combat resource abbreviated AP. Action costs are affected by
Kinetic Tier.

### Kinetic Burden

**Status:** Established

A derived total of physical restrictions, including trauma, encumbrance,
equipped Weight, and survival crises.

### Kinetic Tier

**Status:** Established

A closed cost bracket represented by `GameEnums.KineticTier`: Fluid, Labored,
or Agonizing. Kinetic Tier translates Kinetic Burden into action-cost pressure.

### Stance Points

**Status:** Established

A `0` to `12` measure of physical equilibrium. Stance damage reduces these
points without necessarily damaging flesh.

### Stance State

**Status:** Established

A closed bracket represented by `GameEnums.StanceState`:

- Planted: 7 to 12 Stance Points.
- Stumbling: 1 to 6 Stance Points.
- Felled: 0 Stance Points.

### Melee Lock

**Status:** Established

A derived combat situation in which hostile combatants occupy the same lane
slot. It is not a persistent entity state and does not require its own global
enum.

### Action Type

**Status:** Established

A cross-system combat command represented by `GameEnums.ActionType`. It names
the action requested or resolved, not its AP cost or legality context.

### Action Category

**Status:** Established, CombatCore-private

A cost class owned by `CombatRules`: Quick, Minor, Major, Heavy, Free, or All
AP. Other cores should not depend on this enum.

### Action Group

**Status:** Established, CombatCore-private

An action-legality context owned by `CombatRules`: Non-duel, Duel-locked, Prone
Window, or Reaction.

### Reaction Window

**Status:** Established

A bounded off-turn opportunity to answer an action with a legal reaction, using
reserved AP where required.

### Combat Tactic

**Status:** Established

An AI action-scoring profile represented by `GameEnums.CombatTactic`: Marksman,
Brute, Opportunist, or Defender.

### Combat Outcome

**Status:** Established

The cross-system result emitted by CombatCore, represented by
`GameEnums.CombatOutcome`.

### Damage Type

**Status:** Established

The physical vector of an attack, represented by `GameEnums.DamageType`: Blunt,
Sharp, or Ballistic.

### Flesh Damage

**Status:** Established

Damage applied to anatomical structure and biological health.

### Stance Damage

**Status:** Established

Damage applied to equilibrium through Stance Points. It can create tactical
openings without directly causing a wound.

## Macro World

### Macro World

**Status:** Established

The persistent hex-based exploration layer owned by WorldCore.

### Hex

**Status:** Established

A macro-world cell identified by axial coordinates and described by a Hex
Record.

### Axial Coordinates

**Status:** Established

The `Vector2i(q, r)` coordinate system used to identify macro-world hexes.

### Biome

**Status:** Established

A broad environmental category represented by `GameEnums.GridBiome`. Current
values are Plains, Forest, Hills, Mud, and Swamp.

### Point Of Interest

**Status:** Established as a world concept; content model still early

An authored or generated location attached to a Hex. POIs should be extensible
content identified by stable IDs, not enum members.

### World Seed

**Status:** Established

The stable input used to make procedural world and encounter generation
repeatable.

### Deterministic Generation

**Status:** Established

Generation in which the same seed and location produce the same initial result.
Resolved runtime consequences are then stored in authoritative records.

### Proximity Loading

**Status:** Established

Creation and removal of presentation nodes around the player according to
distance. Loading and unloading do not create, kill, or erase the represented
entity.

### Active Radius

**Status:** Established configuration

The distance within which entity presentation tokens are loaded. The current
default is four hexes.

### Unload Radius

**Status:** Established configuration

The wider distance beyond which loaded tokens are removed. The current default
is six hexes.

### Generation Radius

**Status:** Established configuration

The distance within which unexplored encounter records are generated. The
current default is five hexes.

### Hysteresis

**Status:** Established

The gap between Active Radius and Unload Radius that prevents tokens from
rapidly loading and unloading at one boundary.

### Token Projection

**Status:** Established

A lightweight WorldCore node, such as `MacroEnemy`, that presents an entity
record. The token is not the entity's authoritative state.

### Ground Item Record

**Status:** Established

A runtime item snapshot stored at a macro coordinate after an item is dropped,
spilled, or surrendered.

## Architecture

### Domain Core

**Status:** Established

One of the major ownership boundaries: SystemCore, WorldCore, CombatCore,
BiologicalCore, or ItemCore.

### SystemCore

**Status:** Established

The orchestration domain. It owns factories, authoritative runtime records, and
translation between other cores.

### WorldCore

**Status:** Established

The macro-world domain. It owns hex generation, movement, world presentation,
proximity loading, and macro interaction flow.

### CombatCore

**Status:** Established

The tactical domain. It owns Combat Encounters, lane state, turns, AI, action
rules, and combat resolution.

### BiologicalCore

**Status:** Established

The organism domain. It owns anatomy, vitals, Morale, Stance, Trauma, and
biological snapshots.

### ItemCore

**Status:** Established

The equipment domain. It owns item definitions, Runtime Item Instances,
loadouts, inventory rules, and equipment calculations.

### GameEnums

**Status:** Established

The shared closed vocabulary used when multiple cores must interpret the same
finite values. It is a cross-system contract, not a glossary, content database,
stat sheet, or rule table.

An entry belongs in `GameEnums` only when:

1. The value set is closed.
2. More than one core must interpret it, or it appears in a neutral record.
3. The values represent categories rather than measurable quantities.

### CombatRules

**Status:** Established

The owner of CombatCore-private categories and tuning tables. Its enums are not
part of the cross-system contract.

### Stable ID

**Status:** Established

A string identifier that preserves identity across node destruction,
reconstruction, records, and system boundaries.

### Definition

**Status:** Established

Immutable or immutable-like authored data describing what something begins as.
A Definition is not the same as its active mutable state.

### Runtime State

**Status:** Established

Mutable authoritative data describing what something is currently like.

### Projection

**Status:** Established

A temporary node or UI representation of Runtime State. Destroying a Projection
must not destroy the represented record.

### Snapshot

**Status:** Established

A neutral dictionary or array containing enough Runtime State to transfer,
store, or reconstruct an object without exposing its owning node.

### Neutral Record

**Status:** Established

A data-only cross-system contract built from engine primitives, stable IDs,
`GameEnums` values, dictionaries, and arrays.

### RuntimeStateStore

**Status:** Established in memory

The authoritative owner of current world, entity, hex, player, and ground-item
records. Disk persistence and run deletion rules are not implemented yet.

### MetaProgressionStore

**Status:** Planned

A separate save owner for cross-run unlock IDs. It must not be coupled to the
disposable RuntimeStateStore.

### GameDirector

**Status:** Established

The SystemCore orchestrator that translates signals and records between the
macro world and combat. It should coordinate domains rather than own their
internal rules.

## Prototype Macro Interaction Vocabulary

These terms describe the current demo implementation. They are useful for
testing architecture but are not final ARCCROSS design language.

### Macro Interaction

**Status:** Prototype

A world-layer decision triggered by a POI or entity collision.

### Search

**Status:** Prototype

A POI action that resolves resource discovery using current Loot, Safety, and
Sneak metrics plus selected tool modifiers.

### Camp

**Status:** Prototype

A POI action that stores selected camp gear on a Hex and resolves rest using
current Sleep, Shelter, Healing, Concealment, and Alertness metrics.

### Search Metrics

**Status:** Prototype

- **Loot:** Expected ability to find useful items.
- **Safety:** Expected protection from environmental injury.
- **Sneak:** Expected ability to avoid attracting attention.

These names were adopted from the NEO Scavenger reference and should be
re-evaluated before becoming ARCCROSS canon.

### Camp Metrics

**Status:** Prototype

- **Sleep:** Expected rest quality.
- **Shelter:** Protection from weather and exposure.
- **Healing:** Recovery support.
- **Concealment:** Protection from being discovered.
- **Alertness:** Chance to detect an approaching entity.

These names were adopted from the NEO Scavenger reference and should be
re-evaluated before becoming ARCCROSS canon.

### Talk

**Status:** Prototype

An entity-collision branch that currently offers Threat, Rob, and Ceasefire
actions. Failure can produce a dialogue-breakdown Combat Encounter.

### Ambush

**Status:** Prototype

An entity-collision branch that grants deployment choice while preserving the
rule that the collider receives opening initiative.

### Entity World Status

**Status:** Established implementation; terminology requires redesign

The current `GameEnums.EntityWorldStatus` contains Hostile, Ceasefire, and
Withdrawn. These values mix disposition with physical presence. Future work
should split relationship state from world-presence state before expanding this
enum.

## Informal And Legacy Names

### The Meat And The Math

**Status:** Legacy name

An informal label for the combination of explicit biological consequence and
deterministic mechanical rules.

### Black Knight Rule

**Status:** Legacy name

The rule family in which limb loss invalidates physical capabilities, including
equipment requirements such as two functional arms.

Prefer **limb-dependent equipment restriction** in code and architecture
discussion.

### Coward's Algorithm

**Status:** Legacy name

The Morale and Agenda rules that determine flight behavior.

Prefer **flight response** in code and architecture discussion.

### Vault System

**Status:** Legacy name

The inventory Capacity and Spill rules.

Prefer **InventorySystem**, **Capacity**, and **Spill** in technical discussion.

### Cartographer

**Status:** Legacy name

An informal name for `HexWorldGenerator`.

### Puppet Master

**Status:** Legacy name

An older informal description of orchestration. Prefer `GameDirector` or the
specific owning system; avoid implying that one node owns every rule.
