# ARCCROSS World State / Simulation Reconciliation Audit

Status: implemented and focused runtime-verified, 2026-08-18
Branch: `alpha-release-baseline`
Scope: WorldCore disposable state, node runtime, world actions, projections, and save boundaries

## Baseline and constraints

This audit was written before the World State reconciliation. The checkout was
already intentionally dirty: 68 tracked files were modified and the completed
System / Integration reconciliation introduced additional untracked records,
services, tests, and its audit. Those changes are part of the baseline and must
not be reset, stashed, overwritten, or folded into an unrelated cleanup.

The following contracts are fixed:

- `RuntimeStateStore` remains the run-save and cross-scene authority established
  by the System / Integration reconciliation.
- Production combat remains turn-based `squad_7x5`, with at most six actors and
  no retired posture/reaction mechanics.
- Generator output, Route 1 layout, world art, BiologicalCore formulas, ItemCore
  gameplay, and UI design are not being redesigned.
- Save version 13 is the input format for this pass. The reconciled result will
  write version 14 and migrate version 13 while retaining world-generation
  version 3.

## Current data flow

```text
MacroZoneGenerator cache ----+
                             +--> MacroActiveZoneService --> HexWorldGenerator cache
RuntimeStateStore hexes ------+                |                       |
                                              +--> set_hex_record() <--+

World action resolver --> WorldActionReceipt --> MacroReceiptApplicationService
                                                   |  |  |  |  |
                                                   |  |  |  |  +--> presentation
                                                   |  |  |  +-----> live HumanoidCore
                                                   |  |  +--------> live hex cache
                                                   |  +-----------> world time/signals
                                                   +--------------> RuntimeStateStore
```

The comments frequently call the caches projections, but production callers can
mutate them and then replace canonical records. A mutable dictionary does not
become a projection because a comment asks nicely.

## Writer inventory

### Hex and world-object state

Direct `RuntimeStateStore.set_hex_record()` callers currently include:

- `MacroActiveZoneService`, `MacroPersistenceBridge`, `MacroProgressController`
- `HexWorldGenerator`, `MacroZoneGenerator`, and `MacroZonePersistenceAdapter`
- `MacroGameManager`, `MacroMovementService`, and `MacroVisibilityService`
- `MacroReceiptApplicationService` and `MacroWorldActionExecutionService`
- SEARCH, CAMP, shelter, population, NPC runtime, NPC perception, and resource
  services

Several of those services first mutate a `MacroHexData` instance obtained from
`HexWorldGenerator.world_hex_cache`, then replace the store record. Consequently
the same hex can be represented by a generator cache, a live facade cache, a
store record, and a node snapshot at the same time.

`RuntimeStateStore.set_hex_record()` accepts a live `HexRecord` without copying,
returns no success result, performs no revision comparison, and is therefore a
migration/bootstrap primitive masquerading as a general mutation API.

### Entity, player, inventory, and flags

- Entity mutation is partly routed through store patch/update APIs, but
  `MacroGameManager` and services still read or write public store dictionaries
  and `run_flags` directly.
- Player survival for world receipts is applied to the live player token's
  `HumanoidCore`, then captured back into the store. This reverses the intended
  projection direction.
- NPC macro survival is advanced independently by `MacroNpcRuntimeService` and
  then patched into entity records.
- SEARCH, CAMP, repair material, and tool wear cross store, live
  `InventorySystem`, legacy flat `inventory_items`, and item ownership-ledger
  paths. The ownership ledger now provides the correct neutral boundary, but
  not every world action commits through one transaction.

### Actions, signals, and time

- `active_world_actions` is an untyped `Dictionary` with independent
  reserve/update/release calls.
- `WorldActionRequest` carries expected actor and target revisions, but
  `WorldActionReceipt` does not preserve those expectations or node/hex identity.
- Direct action IDs are derived only from actor, verb, and target. Repeating a
  legal action can therefore produce the same ID.
- Multi-cycle work reuses one action ID, so idempotence requires a separate
  per-attempt receipt identity.
- `MacroReceiptApplicationService.commit()` applies signals, hex state, time,
  live survival, tool wear, player/NPC runtime, and presentation sequentially.
  Failure after an early step leaves a partial commit.
- Signal records exist both in the run-global signal dictionary and copied into
  hex records/caches, allowing drift and duplicate application.

### Node runtime and persistence

- `RuntimeStateStore.capture_node_runtime()`, candidate restoration, integrity
  validation, and rollback-safe restore are already the strongest boundary.
- `MacroProgressController` nevertheless clears active state before destination
  generation and updates graph/active-node fields separately from restoration.
  A failed destination build can therefore strand the transition between
  authorities.
- `MacroZoneGenerator` generates baselines while writing them to the store.
  `MacroActiveZoneService` then injects the same cache into
  `HexWorldGenerator` and writes every hex again.
- `MacroPersistenceBridge` captures player state, rewrites every cached hex,
  updates graph fields, captures the active node, and separately computes
  permanent patches.
- `MetaProgressionStore` correctly keys permanent patches by node and coordinate.
  `WorldMutationStore` remains an older coordinate-only cross-run profile for
  authored-map play and must never participate in directional node worlds.

### Presentation and cross-domain snapshots

- `MacroSnapshotBuilder` directly accepts `HumanoidBody` and inventory objects
  and preloads `BiologicalCore/default_wound_treatments.tres`.
- This keeps medical rules out of UI, but it still makes WorldCore the adapter
  for a BiologicalCore resource. The neutral snapshot should be captured at the
  biological boundary and merely rendered by WorldCore/UI.
- Tokens, the live player core, and `InventorySystem` are still occasionally
  captured as sources rather than synchronized projections.

## Authority decisions

| State | Authority winner | Valid projections / inputs |
|---|---|---|
| Active and saved run state | `RuntimeStateStore` | save codec, slots, debug snapshots |
| Active hex state | revisioned `HexRecord` in `RuntimeStateStore` | `MacroHexData`, visualizer, facade cache |
| Node-local entities/items/actions/signals | node snapshot owned by `RuntimeStateStore` | tokens and HUD snapshots |
| Deterministic node baseline | `MacroZoneGenerator` detached output | generated plan and diagnostics |
| Directional-node transition | atomic `RuntimeStateStore` transition | `MacroProgressController` intent/orchestration |
| World action decision | `WorldActionKernel` / resolver | previews and presentation metadata |
| World action application | `WorldActionApplicationService` transaction | application receipt and post-commit presentation |
| Runtime item location | `RuntimeItemOwnershipLedger` through store APIs | inventory and ground UI |
| Wounds and survival formulas | BiologicalCore | neutral runtime snapshots |
| Permanent node mutations | `MetaProgressionStore` | baseline patch input |
| Legacy authored-map profile | `WorldMutationStore` | explicit non-directional compatibility flow only |

## Required reconciliation

1. Add hex revisions, typed action reservations, unique receipt IDs, revision
   expectations, atomic application receipts, and bounded applied-receipt
   history.
2. Apply a world action against detached candidate records, validate all
   identities and item ownership, and commit or roll back as one unit.
3. Generate node baselines without store writes. Atomically capture the source,
   construct and validate the destination, then swap active state and graph
   metadata together.
4. Rebuild live generator/token/UI projections only from committed snapshots.
5. Remove production WorldCore calls to the permissive `set_hex_record()` and
   direct public store dictionaries. Retain those compatibility paths for
   migrations, fixtures, and explicitly legacy authored-map tooling.
6. Move biological treatment/survival capture behind neutral boundaries without
   changing formulas.
7. Migrate save v13 to v14, preserve temporary-file replacement, and reject
   invalid state before replacing the last valid save.

## Rejected conflicts and deferred work

- Rejected: merging `MacroZoneGenerator` and `HexWorldGenerator`. Their roles
  will be narrowed to baseline producer and projection facade instead.
- Rejected: changing deterministic generation, Route 1 terrain, landmarks,
  authored populations, or world-generation version 3.
- Rejected: implementing SNIPE, completing TRADE economy, expanding campaign
  content, rebuilding UI, or redesigning the Node Web.
- Rejected: moving BiologicalCore or ItemCore rules into WorldCore/SystemCore.
- Deferred: retiring legacy authored-map generation and `WorldMutationStore`
  after all tools and fixtures use directional node baselines.
- Deferred: wholesale decomposition of the large `MacroGameManager`; this pass
  removes mutation authority but preserves its scene-facing facade.

## Acceptance evidence

- Static authority checks prove production WorldCore no longer writes public
  store dictionaries or calls `set_hex_record()`; the check walks nested
  `WorldCore` directories and also covers the combat-result boundary.
- Focused tests prove stale-revision rejection, transaction rollback,
  idempotence, item deduplication, node isolation, projection isolation, and
  v13-to-v14 migration.
- Existing generation, world action, NPC work, shelter, node runtime, combat
  boundary, and integration smokes remain valid.
- Editor import and focused unrestricted runtime proof must pass. Sandboxed
  standalone launches may still hit the known environmental `signal 11` failure.

## Reconciliation result

- `HexRecord.revision`, typed reservations, per-attempt receipts, atomic action
  application, rollback, and bounded persisted idempotence history are live.
- `MacroZoneGenerator` produces detached baselines. `RuntimeStateStore` owns
  node capture/materialization/restoration/transition, while both generator
  caches rebuild as copies after committed state changes.
- Production WorldCore contains no `set_hex_record()` call and no direct access
  to the store's Hex/entity/item/action/signal/graph dictionaries. The method is
  retained for migration fixtures; legacy authored-map persistence remains
  explicitly isolated.
- Movement, fog exploration batches, SEARCH outcomes, CAMP cycles, inventory
  ground transfers, and NPC movement/work now enter revision-validated store
  transactions. Debug commands and domain-owned medical/camp-gear compatibility
  adapters remain explicit neutral-boundary callers rather than world-state
  authorities.
- Biological and inventory snapshot capture moved to domain-owned services;
  WorldCore composes neutral dictionaries and no longer loads treatment data.
- WorldCore run-flag reads use detached store snapshots, and combat-site result
  application copies the site record and commits it through the revision-checked
  `replace_hex_record()` API. Combat-site mutations therefore invalidate stale
  world receipts instead of silently retaining the pre-combat hex revision.
- Save format 14 migrates v12/v13, persists up to 256 applied world receipts,
  and rejects invalid candidates without replacing the last valid file.
- Headless editor import completes script registration without parse errors.
  Focused unrestricted runtime scripts pass for action application, node travel,
  migration/protection, and save/load restoration. Sandboxed standalone launches
  can still terminate in the pre-existing native `signal 11`, confirming that
  crash is environment-specific rather than a failed world-state transaction.
