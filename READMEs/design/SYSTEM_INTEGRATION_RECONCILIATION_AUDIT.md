# ARCCROSS System / Integration Core Reconciliation Audit

Status: implementation gate - complete in current working tree
Target branch: `alpha-release-baseline`
Verification date: 2026-08-18
Production combat contract: `squad_7x5`, turn-based, maximum six participants

## Authority and conflict policy

This audit applies the project authority order below. A lower source may clarify an
unresolved detail, but it may not silently overwrite a higher source.

1. `WORLD_TIMELINE_CODEX.md`
2. `CANONICAL_WORLD_SPECIFICATION.md`
3. `CENTRAL_CORE_CAMPAIGN_OVERHAUL.md`
4. `MACRO_WORLD_OVERHAUL.md`
5. Focused subsystem specifications and audits
6. `GLOSSARY.md`

The attached reconciliation brief is the implementation contract for this pass.
It explicitly overrides older notes that labelled `duel_12x1` as production.
`duel_12x1` and `skirmish_6x3` remain Combat Lab and compatibility profiles;
normal runtime handoff always selects `squad_7x5`.

## Current architecture and dependency map

```text
UI / Presentation
    consumes snapshots and emits intent
                |
                v
WorldCore ---- GameDirector / SystemCore ---- CombatCore
   |                    |                         |
   |                    v                         |
   +------------ RuntimeStateStore <--------------+
                        |
             +----------+----------+
             v                     v
       BiologicalCore          ItemCore
       wounds/vitals            inventory/items
```

- `RuntimeStateStore` is the run-scoped persistence and cross-scene record owner.
- `EntityFactory` is the only supported neutral-record-to-`HumanoidCore` fabrication
  boundary.
- WorldCore owns macro rules, encounter assembly, node navigation, and disposable
  projections. It must not own a second copy of persistent actor state.
- CombatCore owns tactical legality, turn flow, AI, AP, relationships during an
  encounter, and the production arena. It returns neutral records only.
- BiologicalCore owns wounds, anatomy, vitals, incapacitation, and death.
- ItemCore owns live item instances, inventory/equipment rules, and firearm state.
- `GameDirector` owns scene orchestration. It must not independently reinterpret an
  assembled combat roster or become a second persistence repository.
- `GameEventBus` is transient presentation/event transport, never persistent state.

## Ownership table

| State | Authoritative owner | Mutation boundary | Persistent representation |
| --- | --- | --- | --- |
| Player identity, definition, runtime, coordinates | `RuntimeStateStore.player_record` | Player projection commit | `EntityRecord` |
| Live player biology/inventory | BiologicalCore and ItemCore while hydrated | `MacroPlayer` capture/restore | `EntityRecord.runtime` |
| NPC identity and macro location | `RuntimeStateStore.entity_records` | Store entity mutations | `EntityRecord` |
| Alive coordinate occupancy | `RuntimeStateStore` | Rebuilt/validated coordinate index | Derived index, not saved authority |
| Wounds, blood, consciousness | BiologicalCore | `HumanoidCore.capture_runtime_state()` | Nested biological runtime |
| Per-actor inventory and firearm state | ItemCore | Inventory runtime codec | Nested inventory runtime |
| Cross-owner item location | `RuntimeStateStore` ownership ledger | Atomic transfer receipt | Item runtime state plus owner/location |
| Pairwise relations and trust | `RuntimeStateStore` | `CombatRelationshipLedger` state | Run-global relationship state |
| Encounter roster and origins | WorldCore assembly service | Combat handoff record | Active neutral handoff |
| Tactical state | CombatCore | `TacticalCombatScene` | Encounter-local only |
| Combat outcome | SystemCore result application boundary | `CombatResultRecord` | Applied receipt and world records |
| Bodies/incapacitated/surrendered locations | `HexRecord.combat_site_state` | Combat result application | Hex runtime state |
| Ground items | `RuntimeStateStore.ground_item_records` | Atomic item transfer | Item runtime states by macro coordinates |
| Node-local entities/hexes/items | `RuntimeStateStore.node_runtime_snapshots` | Store capture/clear/restore | Neutral node snapshot |
| Campaign graph and active node | `RuntimeStateStore` | Macro progression commit | Run save |
| Permanent cross-run progression | `MetaProgressionStore` | Meta progression API | Separate profile save |

## Lifecycle traces

### Player

New run definition -> `MacroPlayer` hydration -> live BiologicalCore/ItemCore
mutations -> one projection commit to `player_record` -> encounter snapshot -> tactical
clone -> result runtime -> biological elapsed-time application -> one store commit ->
macro projection restore -> save/load -> `MacroPlayer` hydration.

The player token is a disposable projection. `player_record.coords` is canonical;
the legacy `player_coords` field is a compatibility accessor only.

### NPC

Definition/spawn -> stable `EntityRecord.entity_id` -> macro token projection ->
encounter assembly snapshot -> tactical clone -> result update -> store lifecycle and
coordinate commit -> optional macro token projection -> node snapshot/save/load.

Loading or unloading a macro token must not change life state, inventory, or identity.

### Wounded / incapacitated / dead

BiologicalCore creates wounds and derives vital failure/incapacitation. CombatCore
projects those facts and reports participant status. SystemCore applies the returned
runtime without inventing biology:

- wounded: alive record with persistent wound-led runtime;
- incapacitated: alive record with `is_comatose`/combat handoff state and a persistent
  incapacitated site location;
- dead: dead record removed from the alive coordinate index, with a persistent body
  location and carried-item disposition;
- surrendered/escaped: alive record with an explicit world-status/return policy.

### Item and firearm

`ItemData.instance_id` remains stable through definition materialization, inventory,
equipment, firearm mutation, drop/pickup/trade/strip, combat ground state, node
snapshot, and save/load. A committed transfer must have exactly one source and one
destination. Magazine contents, cycling, condition, jams, attachments, and charges
travel with the same runtime instance.

### Encounter and result

WorldCore builds one immutable `CombatEncounterRecord` and one active handoff receipt.
`GameDirector` validates and forwards the exact actor list. CombatCore emits one
`CombatResultRecord`. SystemCore validates the encounter identity and actor set,
applies the result atomically and idempotently, records the applied encounter, then
allows presentation teardown and macro restoration.

## Historical duplicate or unsafe authority seams

These defects were confirmed at the start of the reconciliation pass. Their current
resolution status is recorded in the completion reconciliation below; the list is
retained as an audit trail rather than presented as a current defect list.

### Blocker

1. Encounter participants are assembled in `MacroCombatEncounterService`, then
   filtered/rebuilt again in `GameDirector`. The comments claim verbatim preservation,
   but the code still owns a second actor-selection path and a fallback roster.
2. Combat results are manually fanned into player, NPC, hex, item, relationship, time,
   and token state inside `GameDirector`. There is no validated, idempotent application
   transaction.
3. Ground pickup removes the source before destination acceptance. NPC pickup and
   player pickup rely on ad-hoc rollback; trade mutates live and stored inventories in
   separate steps. A failure can lose, duplicate, or temporarily fork an instance.

### High

1. Player state is split among `player_record`, `player_coords`, and the live token.
   Multiple services update the store directly after mutating the live core.
2. `register_entity()` can overwrite an existing ID or coordinate index entry without
   rejecting the collision. Runtime and lifecycle mutations do not consistently bump
   record revisions.
3. `RuntimeItemOwnershipLedger.transfer_item_to_entity()` writes only the legacy
   `inventory_items` shape and removes every discovered copy before destination
   validation. Removal does not consistently revise touched records.
4. Pairwise relationship state exists in encounters and actor runtime aliases, but the
   returned combat ledger is not persisted as one run-global authority.
5. Node transitions clear store dictionaries directly, bypassing store invariants and
   any future ownership indexes.

### Medium

1. Save version 12 restores records without a post-load identity, occupancy, or item
   integrity check and writes directly to the final path.
2. `EntityFactory` bridges nested inventory and legacy `inventory_items`; the bridge is
   necessary compatibility, but it can become an accidental second inventory owner if
   callers write both shapes.
3. `EntityFactory.humanoid_core_to_record()` always labels the result as a player even
   though the helper is nominally generic.
4. Combat reservation metadata is stored inside NPC runtime and only cleared on the
   successful result path. Setup rejection or abort can leave stale reservation keys.

### Low / documentation

1. Older duel-production notes conflict with the current fixed combat contract.
2. `ItemInstance` is not the active live inventory representation; it is a neutral
   compatibility/future boundary while `ItemData` runtime state remains operational.
3. Some architectural comments describe desired ownership more strongly than current
   mutation paths enforce it.

## Reconciliation order

1. Add store integrity/index APIs, run-global relationship state, item transaction
   validation, and node clear/restore boundaries.
2. Add typed combat handoff and application records with rejection and idempotency.
3. Make encounter assembly register the handoff and remove runtime reservation keys as
   authority.
4. Make `GameDirector` forward the exact roster and delegate record mutations to the
   result application service.
5. Route player/NPC pickup, trade, combat drops, and body inventory disposition through
   the ownership transaction boundary.
6. Add save version 13 migration, integrity gating, and recoverable atomic writes.
7. Add state-focused unit and full round-trip tests, then update architecture indexes.

## Deferred systems and safe boundaries

- Combat mechanics, balance, AI tactics, HUD layout, and presentation remain owned by
  the existing combat workstream.
- Biological formulas, anatomy, survival balance, and medical gameplay are unchanged.
- Inventory capacity/equipment/firearm gameplay is unchanged; this pass only makes
  cross-owner transfers and serialization safe.
- Macro generation, Node Web design, campaign content, narrative, and world art are
  deferred. Node transitions only gain an explicit state-store boundary.
- UI remains snapshot-and-intent only. No UI redesign is authorized.
- Legacy duel/skirmish Lab assets and legacy inventory readers remain available; they
  are marked compatibility paths and may not drive production authority.

## Acceptance criteria

- Every entity and item instance has one stable identity and one authoritative
  location after every committed transition.
- World -> Encounter -> Combat -> World and Save -> Load preserve player and NPC
  wounds, inventory, firearm state, terminal state, body/ground locations,
  relationships, time, node progression, and world mutations.
- Reapplying a combat result cannot double time, items, relationships, or lifecycle
  changes.
- A malformed result, duplicate entity coordinate, duplicate item, or invalid save
  fails explicitly without partially mutating authoritative state.
- Production combat remains `squad_7x5` and the retired mechanics remain absent.

## Implemented disposition - August 17-18, 2026

- `RuntimeStateStore` now owns the canonical player coordinate, rebuilt occupancy
  index, revisioned lifecycle/runtime mutations, pairwise relationships, active
  combat handoff, bounded applied-encounter history, and integrity-gated v14 save.
- `RuntimeItemOwnershipLedger` now preflights source/destination ownership and applies
  ground/inventory transfers without remove-first loss. Legacy `inventory_items`
  remains a migration bridge; `ItemData.to_runtime_state()` is the neutral boundary.
- `MacroCombatEncounterService` is the sole roster assembler. `GameDirector` validates
  and forwards its exact `squad_7x5` actor list; fallback roster discovery and combat
  reservation metadata were rejected and removed.
- `CombatResultApplicationService` validates encounter identity, actor set, revisions,
  participant/location identities, and ground identities; it applies biology snapshots,
  death/incapacitation/surrender, body/site state, item disposition, relationships, and
  world time once, with rollback before commit and a persisted idempotence receipt.
- Macro hexes and tokens remain projections. After result application the director only
  refreshes projections and handles presentation, restore placement, camera, retreat,
  audio, and defeat flow.
- Save format 14 migrates v12/v13 inputs, rejects older saves, reconstructs and
  validates a candidate store before activation, and uses temporary-file
  replacement. An invalid in-memory store cannot overwrite the prior valid file.

### Rejected conflicts

- No duel topology, realtime production mode, reaction AP, posture/facing, Block,
  Dodge, or opportunity-attack authority was reintroduced.
- `world_status` was not promoted into pairwise relationship authority.
- Live macro tokens, combat nodes, and UI snapshots were not made persistence owners.
- `ItemInstance` was not substituted for the operational `ItemData` runtime contract.
- Biology formulas, inventory gameplay/capacity, combat rules, HUD, content, and macro
  generation were not redesigned under the respectable-sounding excuse of
  “integration cleanup.”

### Verification evidence

- Godot 4.7.1 headless editor import: exit 0.
- New passing smokes: `RuntimeStateIntegritySmoke`, `NodeRuntimeBoundarySmoke`,
  `CombatResultApplicationSmoke`, `SaveV12MigrationSmoke`, and
  `SystemIntegrationRoundTripSmoke`.
- Preserved passing smokes: `CombatEncounterAssemblySmoke`,
  `CombatRuntimeHandoffSmoke`, `TacticalCombatResultHandoffSmoke`,
  `CombatTerminalHandoffSmoke`, `RuntimeSnapshotBoundarySmoke`, `SaveLoadSmoke`,
  `GeneratorV2PersistenceSmoke`, `SaveVersionRejectionSmoke`, and
  `CombatSchemaRejectionSmoke`.
- Restricted-sandbox standalone execution still reproduces the known Godot `signal 11`;
  the same focused tests pass with normal Godot user/cache directory access. Godot's
  shutdown leak diagnostics are emitted, but they are not assertion failures.

## Completion reconciliation - August 18, 2026

Status: complete in the current working tree. No commit or publish handoff was
requested or performed.

The remaining authority defects from the historical list are closed:

- `RuntimeStateStore` rejects duplicate entity identities, coordinate/lifecycle/raw
  revision patches, malformed player/entity payloads, and malformed node restores
  without clearing the active state. Rejected player/entity registration is rolled
  back before the candidate becomes visible.
- `RuntimeItemOwnershipLedger` recursively indexes inventory, equipment, fitted
  magazines/attachments, ground items, and world objects. Zero-source transfers,
  nested duplicate identities, NPC pickup, player pickup, and player drop now cross
  validated transaction boundaries.
- Generic entity patches now reject unknown fields and malformed runtime payloads;
  ordinary player/NPC runtime updates validate and roll back, while the combat result
  transaction explicitly defers intermediate cross-actor validation until its final
  atomic check.
- Trade commits through the revision-checked store transaction for both actual NPC
  inventory and authored-loadout fallback items; direct coordinator patching is gone.
- NPC work rebases staged progress and tool wear on the receipt-advanced revision
  before persisting, preventing consumed time and salvage from disappearing behind a
  stale detached snapshot.
- HUD and proximity purpose/scoring projections now operate on copied records. A
  presentation refresh can no longer normalize live NPC purpose fields as an
  accidental simulation write.
- `CombatResultApplicationService` validates actor/item/ground payload identities and
  relationship schema before idempotent acceptance, consumes initial ground copies
  inside the transaction, and retains rollback behavior.
- `EntityFactory.humanoid_core_to_record()` infers NPC kind for non-player IDs while
  retaining an explicit kind override for callers that need it.

New adversarial coverage is provided by `RuntimeAuthorityAdversarialSmoke` and
`TradeOwnershipBoundarySmoke`; `RuntimeSnapshotBoundarySmoke` now covers projection
isolation, and `MacroNpcWorkSmoke`, `NodeRuntimeBoundarySmoke`, and
`CombatResultApplicationSmoke` cover detached-revision, malformed snapshot, and
malformed result rejection. The focused and broader normal-access Godot runs passed,
including the final system round trip after the second-pass fixes. Restricted
standalone execution still reproduces the environment's signal 11, and shutdown
leak output remains follow-up technical debt rather than evidence of a failed
assertion run.

Residual scope is deliberate: `get_entity()` and `get_all_entity_records()` remain
legacy live-resource accessors for compatibility, while production application and
projection paths audited here use snapshots or store mutation APIs. `set_hex_record()`
remains a high-frequency projection replacement; global ownership validation occurs
at item transactions, node restore, combat result, save, and registration boundaries
instead of on every map refresh.
