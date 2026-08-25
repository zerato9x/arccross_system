# ARCCROSS World Action Transaction Checkpoint Audit

Status: stabilization implemented and runtime-verified
Audit date: 2026-08-25
Branch: `alpha-release-baseline`
Baseline commit: `96bf593`
Scope: medical treatment, terminal biology, inventory, POI gear, CAMP,
movement, SEARCH, NPC work, negotiation, item ownership, and their world-action
boundaries

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
- retired actor-snapshot receipt compatibility through an explicit save-v15
  migration for v12-v14 inputs;
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
| Completed NPC SEARCH | Depletion and salvage occurred as independent post-receipt mutations, allowing partial completion | The completed `npc_work_application` carries canonical resource expectations and deterministic salvage; actor, knowledge, target/Hex, trace, ownership, time, revisions, reservation, and receipt identity commit together | `NpcSearchCompletionShippingSmoke`, adversarial cases in `NpcWorkWorldActionTransactionSmoke` |
| Negotiation | TALK committed player/time first, then independently patched target attempts, memory, status, relationship, loadout, and dropped gear | Receipt carries one `negotiation_application`; canonical target staging and `RuntimeStateStore.commit_negotiation_outcome()` join player, target, relationship, created ground ownership, time, reservation, and replay under the same reconciliation snapshot | `NegotiationWorldActionTransactionSmoke`, `ArchitectureContractSmoke`, `MacroInteractionSmoke` |

## Cross-cutting changes

### Canonical transaction boundary

`WorldActionApplicationService` delegates generic/payload validation to
`WorldActionReceiptValidationService` and detached actor dispatch to
`WorldActionActorStagingService`. Inventory, POI-selection, CAMP, movement,
SEARCH, NPC-work, and negotiation transaction services retain their specialized
semantic rules. The application service retains the single reconciliation snapshot,
commit ordering, receipt identity, world-time commit, signal fanout,
reservation lifecycle, item-integrity validation, and rollback boundary.

This is deliberate central coordination, not permission for it to absorb every
domain rule. New action families must arrive as semantic mutations and a small
specialized staging service.

### Item ownership

`RuntimeItemOwnershipLedger` can commit one actor-runtime and ground-item delta
as a single ownership operation. Inventory actions and POI deployment use that
path, while medical treatment and NPC repair mark receipts as ownership-sensitive
so the final integrity check runs after consumption.

Completed NPC SEARCH uses the ledger's created-item commit: the deterministic
salvage identity must have no previous owner, appear exactly once in the staged
NPC runtime, and name that NPC as its inventory owner. Failure restores the
complete reconciliation snapshot.

Threat surrender likewise rejects any pre-owned or duplicate identity before
commit. Its item IDs derive from world seed, target, negotiation attempt, and
loadout position, while the store applies target withdrawal/loadout,
relationship neutrality, and newly-created ground ownership as one nested
canonical operation inside the outer world-action rollback boundary.

### Biological persistence

Destroyed-limb identity is now part of `BodyState`. Runtime restoration does not
quietly regrow a destroyed limb, and detached world-action staging explicitly
reconciles terminal biology before capturing canonical runtime.

### God-object reduction

- `MacroInventoryResolver` was removed and replaced by domain/action services.
- Live POI mutation helpers were removed from `MacroPoiController`.
- `MacroGameManager` lost direct inventory, POI, CAMP, SEARCH-replacement, and
  unused NPC-work mutation facades.
- `WorldActionApplicationService` was reduced from 739 to 317 lines by extracting
  validation and detached staging; canonical commit/rollback ownership remains
  singular.

This is progress, not sainthood. `MacroGameManager` remains a large scene-facing
orchestrator. The application boundary remains intentionally centralized for
commit ordering, but its validation and staging seams are now explicit and
contract-tested.

## Closed follow-up findings

### P0 - Completed NPC SEARCH atomicity: closed

`MacroNpcWorkService.try_work()` now submits semantic completion data in the
same receipt. `WorldActionNpcWorkTransactionService` stages canonical depletion,
target revision, trace, deterministic salvage, NPC purpose/knowledge, and Hex
state. `WorldActionApplicationService` commits those with ownership, time,
reservation release, and receipt identity or restores the complete snapshot.
The post-commit depletion callback and direct salvage patch are gone.

Coverage includes the real seeded `try_work()` continuation/completion path,
replay, save/load, ownership integrity, stale resource count, already-depleted
resource, and duplicate salvage identity.

### P1 - Legacy actor snapshot compatibility: closed

`WorldActionReceipt.actor_state` and `replace_actor_runtime` are removed from the
runtime contract. Save version 15 migrates v12-v14 data recursively, stripping
those fields/mutations from saved reservation/history structures while
preserving active progress. Dedicated v12, v13, and v14 migration smokes pass.

### P1 - Shipping-path NPC work coverage: closed

`NpcSearchCompletionShippingSmoke` invokes the real
`MacroNpcWorkService.try_work()` path through the production receipt adapter and
canonical target. `MacroNpcWorkSmoke` now verifies selection/context helpers
only; its obsolete direct material/tool mutators were deleted.

### P1 - Application-service concentration: closed for this checkpoint

Generic receipt validation and detached actor staging are separate services with
an architecture contract that forbids staging from owning snapshot, rollback,
time, receipt identity, or Hex commit operations. `MacroGameManager` remains a
large input/session/presentation orchestrator and is still a future
maintainability concern, not an unresolved transaction blocker.

## Confirmed residual risks

### P2 - Player-facing friction remains unaudited

The checkpoint proves state integrity, not that inventory, Field Health, CAMP,
SEARCH, and targeting feel good. Physical drag/drop, keyboard parity, error copy,
selection persistence, close/reopen behavior, save/reload visibility, and HUD
refresh timing still require a live player-facing pass after the remaining P0
transaction gap is closed.

### Full-suite result: closed

The repository previously recorded `109/109` executable SceneTree smokes. The
current tree contains 141 executable SceneTree scripts plus two Control preview
scripts. The current Godot 4.7.1 gate is `141/141`: 140 passed in the complete
bounded six-worker sweep; the sole failure was a stale fallback-recovery fixture
that had not injected an empty terrain catalog after default catalog precedence
was introduced. That fixture was corrected and passed in an immediate isolated
rerun. No production combat policy changed.

## Verification boundary

Approved engine:

`C:\Users\zerat\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe`

Checkpoint gate:

1. headless editor import;
2. all transaction smokes plus vital-limb death and completed NPC SEARCH;
3. shipping-adjacent medical, inventory, movement, exploration, and NPC-work
   smokes;
4. world-action application and runtime-integrity smokes;
5. save/load and both world/system integration round trips;
6. architecture contract and `git diff --check`;
7. full 141-script sweep before publication or closure labeling.

Result: headless editor import passes with exit `0`; transaction, shipping-path,
architecture, save-v12/v13/v14 migration, save-version rejection, and semantic
action smokes pass with exit `0`. The current SceneTree gate is `141/141` under
Godot 4.7.1 using the full sweep plus the corrected isolated recovery-fixture
rerun described above. The two authored-map scenes still report their existing
`MacroTileSet.tres` UID fallback during editor import. Headless runs also retain
the existing shutdown leak diagnostics described below.

Headless shutdown ObjectDB/RID/resource-leak diagnostics are recorded separately
from assertion and process-exit status. They remain cleanup debt, not permission
to ignore a non-zero test exit.

## Ordered steps ahead

1. Perform live editor/player QA for health, inventory, CAMP, SEARCH, projection
   reopen, and save/reload stability.
2. Fix presentation friction only after the corresponding canonical actions are
   trustworthy; polish is considerably less charming when it animates data loss.

## Non-claims

- Health and inventory are not declared feature-complete.
- No treatment potency, survival formula, item balance, or campaign content was
  redesigned.
- NPC treatment remains outside the medical transaction scope.
- The full 141-script suite is claimed; a physical player-input pass is not.
- No remote publication is part of this local checkpoint unless separately
  requested and verified.
