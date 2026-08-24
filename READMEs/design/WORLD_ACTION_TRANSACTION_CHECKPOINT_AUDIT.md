# ARCCROSS World Action Transaction Checkpoint Audit

Status: implementation checkpoint, focused runtime-verified
Audit date: 2026-08-25
Branch: `alpha-release-baseline`
Baseline commit: `cc816d4` (`WIP checkpoint: combat and macro systems`)
Scope: medical treatment, terminal biology, inventory, POI gear, CAMP,
movement, SEARCH, NPC work, item ownership, and their world-action boundaries

## Executive result

This checkpoint materially improves correctness, but it does not declare the
health, inventory, macro-world, or presentation tracks finished.

`RuntimeStateStore` remains the canonical run authority. The player token,
NPC records passed into policy services, generator Hexes, HUDs, and inventory
panels are projections or intent sources. The repaired actions now submit
semantic receipt mutations, reconstruct detached canonical state inside the
application boundary, and either commit all affected records or restore the
pre-action reconciliation snapshot.

The main result is boring in the best possible way: a successful action applies
once, consumes once, advances time once, advances revisions once, and can be
replayed without doing any of those things again. Invalid or stale actions leave
the captured world snapshot unchanged.

## Audit method

The audit used current code and runtime evidence rather than roadmap labels:

- inspected every tracked and untracked file in the checkpoint diff;
- traced production callers from `MacroGameManager` and extracted WorldCore
  services into `WorldActionApplicationService` and `RuntimeStateStore`;
- searched production code for full `actor_state`, `replace_actor_runtime`,
  `replace_hex_state`, permissive `set_hex_record()`, and post-commit mutation;
- compared authority comments and generated architecture inventory with the
  actual implementation;
- retained compatibility serialization where deleting it would create an
  unrelated save or receipt migration;
- ran Godot 4.7.1 editor import and focused transaction, shipping-path,
  integrity, persistence, and integration smokes.

## Implemented slices

| Slice | Previous failure mode | Current authority path | Evidence |
| --- | --- | --- | --- |
| Medical treatment | Live player healed first, canonical state then restored the old wound/item, and a later projection could overwrite the commit | UI validates only; receipt carries one `medical_application`; a detached canonical `HumanoidCore` applies treatment and owns consumption inside the transaction | `MedicalWorldActionTransactionSmoke`, `MacroMedicalDragSmoke`, `FieldHealthHUDSmoke`, `WoundItemOverhaulSmoke` |
| Terminal biology | Destroyed vital anatomy could be reconstructed with positive structural HP or without terminal death reconciliation | `BodyState` persists destroyed limbs; `HumanoidBody` restores the destroyed state; `HumanoidCore` reconciles vital destruction before capture | `VitalLimbDeathTransactionSmoke`, save/load and integration smokes |
| Inventory actions | UI/live inventory and ground state could mutate independently, duplicate an item, or lose it after rejection | `HumanoidInventoryActionService` owns domain rules; `WorldActionInventoryTransactionService` stages against canonical player/ground state; the ownership ledger commits the runtime/ground delta atomically | `InventoryWorldActionTransactionSmoke`, `InventoryInteractionSmoke`, runtime-integrity smokes |
| POI gear and traps | Camp gear, sleep gear, traps, player inventory, and overflow ground items were changed through several live callbacks | `MacroPoiSelectionActionService` creates semantic intent; `WorldActionPoiSelectionTransactionService` stages player and Hex copies together and returns displaced overflow through the item boundary | `PoiSelectionWorldActionTransactionSmoke`, `ExplorationHereHudSmoke` |
| CAMP cycle | Recovery and camp counters were calculated or applied on live projections before the receipt finished | Receipt carries deterministic recovery values; `WorldActionCampTransactionService` applies them to detached canonical biology and Hex state before elapsed survival processing | `CampWorldActionTransactionSmoke`, `ExplorationHereHudSmoke` |
| Movement | Live token movement and full actor snapshots could race canonical coordinates, Hex traces, time, and revisions | `WorldActionMovementTransactionService` validates source/destination and commits canonical runtime plus coordinates before projection | `MovementWorldActionTransactionSmoke`, `MacroMovementSmoke` |
| Player SEARCH | Search depletion was represented by a caller-built replacement Hex, allowing stale projection state to become authority | Receipt carries `search_application`; `WorldActionSearchTransactionService` stages the outcome from the canonical Hex and rejects stale or exhausted searches | `SearchWorldActionTransactionSmoke`, `ExplorationHereHudSmoke` |
| NPC work progress | `MacroNpcWorkService` built and submitted a replacement actor runtime while material consumption and tool wear were separately rebased | Receipt carries `npc_work_application`; canonical NPC progress, material consumption, tool wear, revisions, time, reservation continuation, and replay are staged together | `NpcWorkWorldActionTransactionSmoke`, `MacroNpcWorkSmoke` |

## Cross-cutting changes

### Canonical transaction boundary

`WorldActionApplicationService` now delegates specialized validation and staging
to inventory, POI-selection, CAMP, movement, SEARCH, and NPC-work transaction
services. The application service retains the single reconciliation snapshot,
commit ordering, receipt identity, revision checks, world-time commit, signal
fanout, item-integrity validation, and rollback boundary.

This is deliberate central coordination, not permission for it to absorb every
domain rule. New action families must arrive as semantic mutations and a small
specialized staging service.

### Item ownership

`RuntimeItemOwnershipLedger` can commit one actor-runtime and ground-item delta
as a single ownership operation. Inventory actions and POI deployment use that
path, while medical treatment and NPC repair mark receipts as ownership-sensitive
so the final integrity check runs after consumption.

### Biological persistence

Destroyed-limb identity is now part of `BodyState`. Runtime restoration does not
quietly regrow a destroyed limb, and detached world-action staging explicitly
reconciles terminal biology before capturing canonical runtime.

### God-object reduction

- `MacroInventoryResolver` was removed and replaced by domain/action services.
- Live POI mutation helpers were removed from `MacroPoiController`.
- `MacroGameManager` lost direct inventory, POI, CAMP, SEARCH-replacement, and
  unused NPC-work mutation facades.
- `WorldActionApplicationService` grew as the shared atomic coordinator but
  delegates action-family rules instead of embedding them.

This is progress, not sainthood. `MacroGameManager` remains a large scene-facing
orchestrator, and `WorldActionApplicationService` is now the next concentration
point to watch.

## Confirmed residual risks

### P0 - NPC completed SEARCH is not fully atomic

After the NPC work receipt commits, `MacroNpcWorkService.try_work()` still calls
the manager's rubble-depletion callback and then `generate_salvage()` as separate
mutations. A failure between those calls can commit work/time/tool state without
matching depletion or salvage. This is the next transaction slice.

Required correction:

1. stage depletion and deterministic salvage from the canonical Hex;
2. include semantic search-completion data and ground additions in the same NPC
   work receipt;
3. commit actor, target, Hex, items, time, and reservation as one receipt;
4. remove the post-commit callback and direct salvage mutation;
5. add replay, rollback, stale-Hex, exhausted-rubble, and save/load coverage.

### P1 - Legacy actor snapshot compatibility remains

`WorldActionReceipt.actor_state` and the `replace_actor_runtime` mutation remain
serialized and accepted for compatibility fixtures. Production WorldCore no
longer assigns `receipt.actor_state`, and semantic transaction services reject
it, but the generic application fallback still exists.

Remove it only after migrating the remaining compatibility tests and confirming
that no loaded receipt/save fixture requires the field. Deleting the serializer
casually would turn architecture cleanup into save roulette.

### P1 - Shipping-path NPC work coverage is shallow

The focused NPC transaction smoke covers canonical staging thoroughly, while
`MacroNpcWorkSmoke` covers helper selection and wear. A dedicated smoke should
invoke the real `MacroNpcWorkService.try_work()` callback path through a seeded
canonical target, including continuation and completed SEARCH.

### P1 - Coordinator size and manager size

`MacroGameManager` still owns too much input/session/presentation orchestration.
`WorldActionApplicationService` coordinates every atomic world action and must
not become the replacement god object. Future extraction should split generic
receipt validation, detached staging dispatch, and commit coordination only
when each new boundary has an explicit invariant and focused smoke.

### P2 - Player-facing friction remains unaudited

The checkpoint proves state integrity, not that inventory, Field Health, CAMP,
SEARCH, and targeting feel good. Physical drag/drop, keyboard parity, error copy,
selection persistence, close/reopen behavior, save/reload visibility, and HUD
refresh timing still require a live player-facing pass after the remaining P0
transaction gap is closed.

### P2 - Full-suite result is historical

The repository previously recorded `109/109` executable SceneTree smokes. The
current tree contains 139 executable SceneTree scripts plus two Control preview
scripts. The historical result remains valid for its older tree, but it is not a
claim about this checkpoint. This checkpoint uses a focused authority suite;
run all 139 scripts before publication or release labeling.

## Verification boundary

Approved engine:

`C:\Users\zerat\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe`

Checkpoint gate:

1. headless editor import;
2. all seven new transaction smokes plus vital-limb death;
3. shipping-adjacent medical, inventory, movement, exploration, and NPC-work
   smokes;
4. world-action application and runtime-integrity smokes;
5. save/load and both world/system integration round trips;
6. architecture contract and `git diff --check`;
7. full 139-script sweep before publication, not necessarily before this local
   implementation checkpoint.

Checkpoint result: headless editor import passed with exit `0`; the 21 focused
transaction, shipping-path, health, inventory, integrity, persistence,
integration, and architecture scripts passed `21/21` with exit `0`. The two
authored-map scenes still report their existing `MacroTileSet.tres` UID fallback
during editor import. Headless runs also retain the existing shutdown leak
diagnostics described below.

Headless shutdown ObjectDB/RID/resource-leak diagnostics are recorded separately
from assertion and process-exit status. They remain cleanup debt, not permission
to ignore a non-zero test exit.

## Ordered steps ahead

1. Make NPC completed SEARCH depletion and salvage one atomic receipt.
2. Add a real `try_work()` shipping-path smoke for repair and SEARCH completion.
3. Migrate remaining compatibility tests away from `actor_state`, then decide
   whether receipt serialization needs a versioned retirement path.
4. Split generic world-action validation/staging/commit coordination only where
   it reduces authority concentration without duplicating rollback ownership.
5. Run the complete 139-script Godot 4.7.1 suite.
6. Perform live editor/player QA for health, inventory, CAMP, SEARCH, projection
   reopen, and save/reload stability.
7. Fix presentation friction only after the corresponding canonical actions are
   trustworthy; polish is considerably less charming when it animates data loss.

## Non-claims

- Health and inventory are not declared feature-complete.
- No treatment potency, survival formula, item balance, or campaign content was
  redesigned.
- NPC treatment remains outside the medical transaction scope.
- The full 139-script suite and physical player-input pass are not yet claimed.
- No remote publication is part of this local checkpoint unless separately
  requested and verified.
