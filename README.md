# ARCCROSS: A Base-12 Survival Engine

Project terminology is defined in [ARCCROSS_GLOSSARY.md](ARCCROSS_GLOSSARY.md).
System ownership and dependency rules are defined in
[SYSTEM_ARCHITECTURE.md](SYSTEM_ARCHITECTURE.md).

Overview

Welcome to the Arccross Engine. This is not a standard RPG. There are no 1-100 percentage scales, no heroic health pools, and no forgiving mechanics. This is a mathematically pure, highly lethal survival simulator built on a strict Base-12 biological and environmental logic. Set against the desolate, anomalous backdrop of Arccross, this engine is designed to simulate physical trauma, psychological breaking points, and tactical desperation.
Core Philosophy: The Meat and The Math

ARCCROSS authors its abstract gameplay meters on a 0-to-12 scale. Pillars use 1-to-12, while depletable conditions such as Blood and Stance can reach zero. Physical measurements retain meaningful units, but their gameplay thresholds are tied back to explicit Base-12 rules. You do not lose one generic health pool: systemic blood loss and local structural damage independently crush motor efficiency and Action Point (AP) generation.
System Architecture
1. The Macro-World (The Hex Crawler)

    The Cartographer (HexWorldGenerator.gd): Procedurally generates a vast wasteland using FastNoiseLite (Perlin noise) to cluster biomes realistically, with backdoor hooks for bespoke narrative Points of Interest.

    The Puppet Master (GameDirector.gd): The overarching god-node. A master state-machine that silently tracks axial coordinates, handles input routing, and listens for biological collisions.

2. The Micro-World (The Meat-Grinder)

When a collision occurs on the overworld, the macro map is suspended, and entities are dragged into a claustrophobic 12x1 tactical hex lane.

    Dynamic Instantiation: The engine programmatically builds combatants from raw .tres genetic files, assembling their anatomical matrices and inventory systems entirely from scratch.

    Utility AI (CombatAIEvaluator.gd): AI does not follow static scripts. Actions are dynamically scored (0.0 to 1.0) based on AP limits, distance, weapon ballistics, and psychological state.

3. The Biological Core

Entities are not sprites; they are simulated organisms governed by four core genetics (Brawn, Finesse, Fortitude, Will).

    The Black Knight Rule: A fully simulated trauma system. If an entity loses an arm, the engine forcefully unequips two-handed weapons and applies massive systemic shock.

    The Coward’s Algorithm: If structural damage causes an entity's Morale to drop below their genetic breaking point, tactical logic terminates. They abandon all self-preservation protocols and desperately sprint for the map edge.

    The Vault System: Inventory capacity scales exactly 1:1 with the Brawn attribute. Over-encumbrance actively destroys initiative and AP regeneration.

Current Development State

    [COMPLETED] Macro-map procedural generation, axial math, and token snapping.

    [COMPLETED] Director interception logic and async scene-transition state machine.

    [COMPLETED] Base-12 biological data structures, .tres resource architecture, and trauma tracking.
