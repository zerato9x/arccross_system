# Combat Reconciliation Audit

Audit date: 2026-08-17
Repository: alpha-release-baseline at 7a9457f8
Scope: repository-wide combat reconnaissance against the locked combat brief supplied with this task.

Sections 1 through 18 preserve the pre-implementation audit and locked work order. Implementation was subsequently authorized and completed on 2026-08-14; Sections 19 through 21 record the implementation, remediation, and terminal handoff correction. Historical findings remain intact so the migration can be reviewed without pretending the repository was always this tidy.

## Current status (2026-08-17)

The current production contract is implemented and is owned by
[TURN_BASED_COMBAT_OVERHAUL.md](TURN_BASED_COMBAT_OVERHAUL.md),
[COMBAT_UI_SPECIFICATION.md](COMBAT_UI_SPECIFICATION.md),
[SYSTEM_ARCHITECTURE.md](../SYSTEM_ARCHITECTURE.md), and
[GLOSSARY.md](../GLOSSARY.md). Production enters `squad_7x5`; `duel_12x1` and
`skirmish_6x3` are Lab/compatibility fixtures only. The historical findings in
Sections 1 through 18 are not remaining defects.

The latest correction preserves incapacitated actors in a neutral handoff layer
after active occupancy removal. `Strip` and `Execute` may use that projected
sector, and `Execute` transfers the actor into the persistent body layer. The
current verification is `109/109` executable capital-`Tests` SceneTree smokes
passed with `FAILED=0` under Godot `4.7.1.stable.official.a13da4feb`; the two
`Control` preview scripts were excluded as non-self-quitting visual surfaces.
The sweep uses the ignored workspace-local `.godot/test-appdata`,
`.godot/test-localappdata`, and `.godot/test-logs` directories so persistence
smokes own their setup. Live MCP boot and combat-family diagnostics are clean;
physical pointer input and subjective weapon/audio acceptance remain separate
human acceptance claims.

> **Current checkpoint rule:** Sections 1–18, including the documentation drift
> table, test-gap table, open risks, and work order, are historical pre-gate
> evidence. They are retained for audit provenance and are not a live defect
> list. Sections 19–23 and the focused authority documents are the current
> implementation record.

## 1. Historical Executive Summary (pre-implementation)

At the pre-implementation audit point, the production handoff was already
pointed at the canonical tactical scene and already forced the canonical
`squad_7x5` topology. The main problem was not that the repository had one
mysterious “Codex combat mode” hiding in a closet. It had several generations
of combat contracts cohabiting the same codebase:

1. The live production path is the six-actor, orthogonal squad_7x5 arena with pairwise relationships, per-actor AP, autonomous NPC turns, and LEAVE BATTLE terminal logic.
2. duel_12x1, skirmish_6x3, and CombatModeComparison are legitimate lab/debug material, but duel-era labels and tests still call the 12x1 lane “production.”
3. Retired mechanics are partly removed from canonical visibility and partly still represented as live-looking data, compatibility fields, dead resolver branches, UI nodes, serialized snapshot keys, and tests. The repository is doing the software equivalent of leaving old wiring behind the wall and then naming the wall “clean.”

The highest-risk findings are:

- At that audit point, TURN_BASED_COMBAT_OVERHAUL.md, the root README.md,
  COMBAT_UI_SPECIFICATION.md, SYSTEM_ARCHITECTURE.md, GLOSSARY.md, and the top
  of CHANGELOG.md still contained duel-lane, reaction, AP-reserve, posture,
  guard/block/parry, and/or realtime assumptions that did not describe the
  locked baseline.
- Reserved reaction AP, reaction prompts, opportunity strikes, Block/Dodge, and brace are mostly compatibility/dead paths. TacticalTurnManager._action_reserved_ap is different: it is a transient transaction reservation used to protect one action commit and must not be deleted as if it were the retired between-turn AP reserve.
- Posture and facing are not merely dead compatibility vocabulary. CombatActionController, CombatActionQuoteService, CombatBoard, movement cost, snapshots, HUD labels, and tests still treat them as state. CombatBoard.attack_arc_from() also still returns rear/side accuracy and reaction modifiers, although no caller was found and CombatResolutionEngine explicitly forecasts a direct arc. Cover currently calls set_facing(), so removing facing without first replacing cover-edge selection is unsafe.
- The RMB path discards the original pointer position in TacticalArenaView._gui_input(). TacticalCombatHUD._position_context_menu() therefore anchors above CommandDock and clamps there. This is deterministic but not pointer-relative.
- Hands/Quick item buttons load presentation.icon_path; target-item and ground-item buttons render text only. CombatActionController._item_snapshot() already places icon/sprite paths into the ground-item snapshot, so ground icons are omitted by the renderer, not by the data contract.
- The weapon card duration is currently CombatPresentationSequence.total_duration() because TacticalCombatHUD.show_presentation_action() calls CombatItemCard.play_turn_action(sequence.action_id, sequence.total_duration()). The card only pulses its image; it does not traverse firearm frames. Firearm sheet frames are drawn by CombatTokenOverlay over normalized sequence progress. Weapon-sheet duration, body-animation duration, cue duration, sequence duration, and gameplay resolution duration are not currently separate contracts.
- Successful combat damage can produce two HumanInjured sounds: HumanoidBody.apply_targeted_hit() emits GameEventBus.humanoid_injured, and TacticalPresentationPlayer._play_audio_cue() emits combat_damage_sfx at impact. Both reach SfxConductor._play_combat_injury(). The presentation SFX payload also drops actor and victim identity even though combat resolution events preserve both IDs.

The recommended implementation sequence was to reconcile the
topology/docs/test vocabulary, remove retired rule authority as one coordinated
migration, fix item/context presentation, separate timeline clocks, and collapse
combat SFX to one authoritative injury route. The completion records below are
the outcome of that sequence.

## 2. Current Production Combat Path

### 2.1 Macro-to-tactical handoff

    MacroGameManager._request_pending_combat()
      -> MacroGameManager._build_combat_encounter_record()
      -> MacroCombatEncounterService.build()
      -> MacroGameManager.combat_requested
      -> GameDirector._on_combat_requested()
      -> PresentationSceneRegistry.TACTICAL_COMBAT_SCENE
      -> TacticalCombatScene.setup_encounter()
      -> TacticalEncounterBuilder.build()
      -> CombatBoard.configure_from_encounter()
      -> CombatActionController.configure()
      -> TacticalCombatHUD + TacticalCombatAI

Relevant live ownership:

- WorldCore/MacroGameManager.gd::_request_pending_combat() builds the request and delegates record construction to _build_combat_encounter_record().
- WorldCore/MacroCombatEncounterService.gd::build() creates the CombatEncounterRecord, copies encounter ground items, resolves the topology for trap coordinates, and applies the authored six-actor assembly profile with late reinforcements disabled.
- SystemCore/GameDirector.gd::_on_combat_requested() loads PresentationSceneRegistry.TACTICAL_COMBAT_SCENE, instantiates it, hydrates CombatEncounterRecord, and explicitly sets encounter.topology_id = "squad_7x5" before setup. This explicit assignment is the final production topology authority.
- PresentationCore/PresentationSceneRegistry.gd names res://CombatCore/Tactical/TacticalCombatScene.tscn as the tactical combat scene.
- CombatCore/Tactical/TacticalCombatScene.gd::setup_encounter() rejects rosters over six, freezes late reinforcements, requires one direct player and at least one autonomous actor, fabricates runtime actors, builds the board, configures the action controller, loads ground items, and instantiates one TacticalCombatAI per enemy actor.
- CombatCore/Tactical/TacticalEncounterBuilder.gd::build() loads encounter.topology_id, deploys actors through that profile, applies relations, and initializes the turn manager.
- CombatCore/Tactical/CombatBoard.gd::_initialize_empty_arena() defaults an unconfigured board through CombatTopologyCatalog.DEFAULT_ID.

### 2.2 Live action and presentation path

    HUD input
      -> TacticalCombatInteractionCoordinator / CombatInteractionState
      -> TacticalCombatScene request construction
      -> CombatActionController.request_action()
      -> pure quote + transaction reservation
      -> resolver / CombatResolutionEngine
      -> authoritative state mutation and outcome events
      -> CombatPresentationProfile.build_sequence()
      -> action_committed + presentation_requested
      -> TacticalCombatScene._on_presentation_requested()
      -> TacticalPresentationPlayer.play()
      -> TacticalArenaView cue execution + GameEventBus scene audio
      -> HUD.finish_presentation()
      -> CombatActionController.acknowledge_presentation()

The important authority boundary is sound in principle:

- CombatActionController owns quote, legality, AP transaction, resolver dispatch, state revision, and the presentation barrier.
- CombatResolutionEngine owns weapon/wound resolution after a legal quote. damage_resolved and shot_resolved events retain attacker_id and victim_id.
- CombatPresentationProfile authors timing and cue data; TacticalPresentationPlayer executes it; TacticalArenaView renders it.
- TacticalCombatSnapshotPresenter, CombatActorPresentationProjection, CombatInventorySnapshotPresenter, and the other snapshot presenters form the neutral presentation projection layer.
- CombatCore does not need to import res://UI/ to render the tactical scene. That boundary should remain intact during cleanup.

Gameplay resolves before the presentation sequence is requested. The action controller then waits on presentation_acknowledged, so presentation is a transaction barrier, not the authority that decides whether a hit happened.

## 3. Locked Contract vs Live Implementation

The locked brief supplied with this audit supersedes older repository prose. The comparison below distinguishes alignment from compatibility residue and from a genuinely unresolved contract.

| Locked contract | Live implementation | Status | Reconciliation note |
|---|---|---|---|
| Production arena is squad_7x5, 7 columns x 5 rows | CombatTopologyCatalog.DEFAULT_ID, CombatEncounterRecord, CombatArenaState, CombatBoard, and GameDirector._on_combat_requested() all default/force squad_7x5 | Aligned in production | Duel remains loadable for lab fixtures; documentation and some tests still call it production. |
| Orthogonal movement | squad_7x5.tres and skirmish_6x3.tres use ORTHOGONAL; duel_12x1.tres uses LINEAR_NO_PASS | Mixed by profile | Correct for production; duel-specific linear behavior must remain explicitly lab-only. |
| At most six active participants; no late entry | CombatEncounterAssemblyProfile sets the cap; TacticalCombatScene.setup_encounter() rejects more than six and disables late reinforcements | Aligned | Keep the assembly receipt and roster handoff tests. |
| Player controls only the direct player actor; NPCs act autonomously | HUD requests are constructed for the player; enemies receive TacticalCombatAI; controller remains generic so AI and player share the same legality/resolution seam | Mostly aligned | Preserve shared authority. Add a regression asserting the production HUD cannot stage an NPC request. |
| Pairwise mutable relations; neutral attack requires confirmation | CombatRelationshipLedger, CombatBoard.relation_between(), CombatActionQuoteService, and CombatNeutralAttackSmoke implement this | Aligned | Do not replace pairwise relations with team-name inference. |
| Encounter continues while any active player-hostile actor exists | CombatActionController._validate_specific() and _resolve_leave_battle() call CombatBoard.has_active_player_hostile() | Aligned | CombatLeaveBattleSmoke covers the complementary NPC-vs-NPC conflict case. |
| LEAVE BATTLE is legal when no player-hostile actor remains, even if NPCs remain hostile to each other | CombatBoard.has_active_hostile_conflict() preserves the NPC conflict; CombatLeaveBattleSmoke verifies the player can leave | Aligned | Keep this separate from victory/defeat evaluation. |
| Every actor receives a normal AP pool; end turn discards AP | TacticalTurnManager._start_turn() assigns current_ap_pool; pass_turn() clears it | Aligned | Existing reserved_ap snapshot key is compatibility residue, not live contract. |
| No reserved AP between turns | TacticalTurnManager.reserved_ap is documented as deprecated and kept empty; old reaction methods return inert values | Mostly aligned | Remove after save/replay/snapshot migration. Do not remove _action_reserved_ap, which protects one in-flight AP transaction. |
| No reaction prompts/windows or opportunity strikes | Turn manager signals/methods, HUD panel, catalog definitions, reaction resolver, quote fields, and dead resolver branches remain | Not aligned structurally | Remove gameplay authority and compatibility vocabulary in one migration. A visual cue named reaction is a separate presentation question. |
| No Block/Dodge action or reaction economy | Catalog hides them, controller denies them as reaction_only, and _request_reaction() returns empty; dead _resolve_block()/_resolve_dodge() remain | Runtime mostly inert, source not clean | Preserve equipment protection through resolve_protection_event(); remove defensive-action paths only after confirming no replay consumer. |
| No Stand/Crouch/posture mechanic | Catalog hides stand/crouch, but CombatActionController, CombatBoard, CombatActionQuoteService, movement cost, HUD, token idle animation, and TacticalCombatRulesSmoke still use posture | Not aligned | This is live rule state, not a harmless string cleanup. Migrate posture effects before deleting fields. |
| No Brace | No default brace definition; the catalog smoke rejects its presence; resolution comments identify it as retired | Mostly aligned | Remove stale comments/aliases after the retired-action contract test is replaced. |
| No directional facing/rear/flank authority | Quote derives final_facing; controller commits it; board snapshots facings; cover calls set_facing(); attack_arc_from() still returns rear/side modifiers; no caller was found for attack_arc* | Not aligned structurally; modifier path appears orphaned | Replace persistent actor facing with presentation direction and/or cover-edge selection before deleting. Keep geometric cover queries if the locked defense contract still uses cover. |
| Defense comes from wounds, Stance, equipment, cover, range, and observable conditions | Resolution uses wounds/body state, protection, cover, range, and stance/balance; it also retains dead reaction and arc branches | Mixed | The non-retired defense inputs are the safe core. Remove only the extra reaction/posture/facing modifiers. |
| Only AI-only reserve-replacement behavior is allowed when an ally is shoved out of Engagement | No complete current path was identified that clearly implements this exact exception | Unknown | Treat as an explicit AI rule to verify before deleting every reserve-shaped term. Add a focused AI smoke if still required. |
| Production presentation uses the tactical HUD and the neutral snapshot/intent seam | TacticalCombatScene.tscn, TacticalCombatHUD.tscn, TacticalArenaView, presenters, coordinator, and player are wired as described | Aligned | Preserve this ownership while reducing HUD size. |

The most important semantic distinction is therefore: “hidden from the player catalog” is not the same as “removed from authority.” The repository currently relies on the former in several places while the locked brief requires the latter.

## 4. Stale Mechanics Matrix

| Mechanic or term | Authority / compatibility evidence | UI / data / test residue | Disposition |
|---|---|---|---|
| Reserved AP between turns | CombatCore/Tactical/TacticalTurnManager.gd: reserved_ap is an empty compatibility projection; open_reaction_window(), resolve_reaction(), decline_reaction(), and try_spend_reserved_ap() are inert. CombatActionController._reserved_snapshot() still serializes it. | TacticalCombatHUD and fixtures accept reserved_ap; TURN_BASED_COMBAT_OVERHAUL.md, root README.md, GLOSSARY.md, and changelog history describe AP banking/reserve reactions. | Migrate snapshot/save/test schema and remove the public compatibility field. Keep _action_reserved_ap or rename it to an explicit transaction-pending-cost field; it is not the retired economy. |
| Reaction prompts/windows | TacticalCombatScene._on_reaction_window_opened() returns before its old UI path; turn-manager reaction methods are inert. | TacticalCombatHUD.tscn still contains ReactionPanel; HUD has show_reaction()/hide_reaction() and reaction styling; CombatPresentationCue.MARKERS contains reaction; old docs say reaction windows remain authoritative. | Delete gameplay prompt APIs and panel after callers/tests migrate. Decide separately whether the visual reaction marker should become response/settle or remain as a non-interactive readable beat. |
| Opportunity strike | CombatActionCatalog.RETIRED_PLAYER_ACTIONS hides it; CombatReactionResolver.steps_for_path() still derives threat IDs from CombatBoard.reaction_threats(); controller compatibility methods return without resolving. | Default action resource still defines opportunity_strike; CombatActionQuoteService.MELEE_ACTIONS/FACING_ACTIONS still include it; quote has reaction_threat_ids and ordered_reaction_steps. | Remove from canonical action definitions, quote schema, reaction resolver, board threat discovery, and tests after replay compatibility is addressed. |
| Block/Dodge actions | Catalog hides them; controller denies them as reaction_only; CombatResolutionEngine._request_reaction() always returns empty, so _resolve_block() and _resolve_dodge() are unreachable through the canonical attack path. | Default catalog still contains Action_block and Action_dodge; attacks retain blockable/dodgeable reaction tags; old docs and changelog describe guard/block/parry. | Remove as actions and reaction metadata. Preserve ordinary equipment/armor protection through InventorySystem.resolve_protection_event() and do not confuse it with a player Block verb. |
| Stand/Crouch/posture | CombatActionController resolves posture; CombatBoard.posture()/set_posture() stores it; CombatActionQuoteService checks required postures; CombatMovementResolver adds AP for crouching; CombatActionController._control_score() uses it. | HUD shows posture_chip, ActorStatus, TargetPosture; TacticalArenaView selects CrouchIdle; default catalog resources and TacticalCombatRulesSmoke exercise both actions. | Coordinated gameplay migration required. Remove posture from rule state and action catalog, then decide whether any visual crouch animation is retained as an action presentation rather than persistent posture. |
| Brace | No default definition; the catalog smoke rejects its presence; resolution comments say it was retired. | CombatActionCatalogSmoke includes it in a retired list; stale references/comments remain. | Low-risk cleanup after the retired-action contract is made authoritative. |
| Disengage | Catalog hides it as retired, but quote/controller/presentation still treat it as movement and the default resource contains it. | Old movement/opportunity-strike language remains in docs and action descriptions. | Treat as a legacy movement alias. Decide whether it maps to ordinary movement or is removed; do not silently reintroduce reaction semantics. |
| Aimed strike/fire | Catalog marks aimed_strike and aimed_fire as retired player actions, while definitions, resolvers, presentation profiles, and TacticalCombatRulesSmoke still use them. | HUD has aimed targeting; CombatExperienceRebuildSmoke and AI parity include aimed actions. The locked brief does not explicitly retire aimed attacks. | Product decision required. Keep as compatibility/live candidate until the brief explicitly resolves it; do not delete based on the catalog map alone. |
| Directional facing | CombatActionQuoteService owns FACINGS, derives final_facing, and CombatActionController.request_action() commits it with board.set_facing(). Board snapshots it and TacticalArenaView consumes it. | CombatActionQuote, CombatPresentationCue, HUD actor status, fixtures, and CombatExperienceRebuildSmoke assert facing. | Remove as persistent gameplay authority. If tokens still need to turn for readability, create presentation-only direction derived from the action/cue. |
| Rear/side arc | CombatBoard.attack_arc_from() returns front/side/rear, accuracy, and reaction_penalty, but no caller was found. CombatResolutionEngine explicitly sets forecast arc to direct. | CombatForecastRecord.attack_arc defaults to front; old docs distinguish rear/flank. | Delete the orphaned modifier path after a source-contract test proves no consumer. Retain only a non-authoritative visual direction or cover-edge geometry. |
| Flank | NPC profiles retain flank_weight; default action move has flank in ai_tags; GameEnums calls opportunist a flank scorer. | No current attack-arc caller uses it; it is still an AI planning vocabulary. | Remove or reframe as a generic positioning preference only if the locked brief permits it. It must not become a hidden rear-attack modifier. |
| Reaction tags | CombatActionDefinition exposes reaction_tags; default attacks carry blockable/dodgeable, movement carries provokes_control_zone. | Catalog/resource data and quote fields preserve old metadata even though canonical reaction resolution is inert. | Delete tags after action definitions and AI/test consumers are migrated. |
| Generic reservation | TacticalTurnManager._action_reserved_ap protects a single action transaction; other code uses reservation-like wording for projected costs. | Search results can look like retired AP reserve even when they are transaction guards. | Keep the behavior, rename for clarity, and document the distinction. Do not blanket-delete every reserved token. |

## 5. TacticalCombatHUD Responsibility Map

CombatCore/Tactical/TacticalCombatHUD.gd is 2,423 lines and TacticalCombatHUD.tscn is a large composition scene. It is a renderer/interaction bridge, but it currently carries enough independent surfaces that extraction is justified. The extraction should be incremental; moving the whole HUD in one heroic gesture would mostly create a second monolith with better furniture.

| Responsibility | Current functions/nodes | Correct authority | Recommendation |
|---|---|---|---|
| Snapshot/projection orchestration | show_snapshot(), show_quotes(), show_quote(), _SnapshotPresenter, _presentation_actor(); nodes TacticalArenaView, TopStrip, PlayerCard, CommandDock, HexPanel, Right | CombatActionController snapshot and TacticalCombatSnapshotPresenter | Keep the HUD as composition root. Do not let it derive legality, AP, relation, injury, or target selection rules. |
| Interaction phase bridge | _select_interaction(), _set_phase(), _cancel_selection(), _unhandled_input(), selected_context(); TacticalCombatInteractionCoordinator and CombatInteractionState own phase/request state | Coordinator/state own typed interaction state; controller owns legality | Keep signal wiring in HUD for now, but stop adding gameplay state to it. Pointer anchor can live in presentation-only state or HUD-local state. |
| Responsive layout and viewport clamping | _layout_corner_panels(), _layout_corner_panel(), _queue_corner_layout(), _position_context_menu() | Presentation/layout only | A later TacticalCombatLayoutController is worthwhile only after item/context extraction. It is not a reason to touch CombatCore authority. |
| Persistent player card | _render_player_card(), _render_gear_row(), _render_player_wounds(), vital setters; PlayerCard, PaperDollModel, CombatItemCard, GearRow | Snapshot projection | Extract TacticalCombatPlayerCard when the posture/facing cleanup settles. It owns a coherent surface and will reduce HUD coupling without changing authority. |
| Weapon card and maintenance actions | _render_weapon_actions(), show_presentation_action(), finish_presentation(); ActiveWeaponCard, WeaponActions | Action catalog/presentation sequence supplies data; HUD only displays | Keep the card component, but give it an explicit presentation duration/view model rather than passing the entire sequence duration by accident. |
| Actor/sector inspection | _render_actor_inspector(), _render_sector_inspector(), _render_wounds(), _render_target_items(), _render_ground_items(); Right, HexPanel, CombatBodyTargetView | Relationship-aware projection; board snapshot for sector facts | Extract a shared TacticalCombatInspectionPanel only if actor/sector surfaces are changed together. It should consume projection dictionaries, not actors. |
| Hands/Quick, target, and ground item rows | _render_items(), _render_target_items(), _render_ground_items(), _render_gear_row() | CombatInventorySnapshotPresenter and item presentation descriptors | This is the most material extraction: create one presentational item-row/list helper with explicit icon_path, redaction, access, quantity, and selection callbacks. It fixes the icon inconsistency and reduces duplicate row logic. |
| Context menu and action branches | _render_context_actions(), _add_context_branch(), _add_action_button(), _position_context_menu(); ContextMenu, ContextActions, ContextScroll | Quotes come from controller; state transitions from coordinator | Extract TacticalCombatContextMenu after pointer anchoring is specified. It should receive selected context, visible quotes, and a global anchor; it must never quote or commit actions itself. |
| Aim/targeting surface | show_aim_targeter(), _confirm_aim_targeting(), _cancel_aim_targeting(); AimTargetPanel, CombatBodyTargetView | Controller quote/target-region request | Keep coupled to the HUD until aimed-action policy is resolved. Do not delete it merely because the catalog currently hides aimed actions. |
| Result feed and consequence display | show_result_events(), push_consequence(), _result_feed; dynamic ConsequenceFeed | Outcome/presentation projection | Keep visual-only. Remove reaction/opportunity labels from the feed once the outcome schema is migrated. |
| Reaction panel | show_reaction(), hide_reaction(), reaction_panel nodes and styling | No canonical owner; prompt is retired | Remove after turn-manager/scene callers and compatibility tests are gone. A timeline response beat is not a reason to retain an interactive panel. |
| Arena rendering/input | Child TacticalArenaView; HUD only connects signals and toggles mouse filter during presentation | TacticalArenaView rendering, coordinator interaction, controller authority | Preserve the split. TacticalArenaView should emit pointer data but should not construct action requests or mutate combat state. |

Material extraction order: shared item rows, then context menu, then player/inspection surfaces. Leave CombatActionMenuSnapshotPresenter, CombatActorPresentationProjection, CombatInventorySnapshotPresenter, and the coordinator as neutral seams rather than folding them into a new UI authority.

## 6. Context Menu Trace

### 6.1 Current RMB path

1. CombatCore/Tactical/TacticalArenaView.gd::_gui_input(event) receives the right mouse button.
2. It converts event.position to a sector with _coords_at(event.position), selects the sector, and resolves the token with _actor_id_at_position(coords, event.position).
3. It emits context_requested(coords, actor_id). The pointer position is not included in the signal.
4. TacticalCombatHUD._ready() connects that signal to _on_arena_context_requested().
5. TacticalCombatHUD._on_arena_context_requested(coords, actor_id) calls _on_arena_inspect_requested(), clears staged action, updates the relationship-neutral inspection workspace, asks TacticalCombatInteractionCoordinator.open_root_menu(), emits the HUD-level context_requested(coords), and calls _render_context_actions().
6. TacticalCombatScene._on_context_requested(coords) receives the HUD signal, ignores it while resolving, verifies the sector, and calls _refresh_context_quotes(). It does not position the menu.
7. _render_context_actions() creates the visible action/communication buttons from already-projected quotes and schedules _position_context_menu() with call_deferred() after minimum sizes are known.
8. _position_context_menu() reads CommandDock.get_global_rect(), clamps menu dimensions, defines HUD bounds from global_position + Vector2(12, 46), and sets the desired position immediately above the dock with an eight-pixel gap.

### 6.2 Why it is dock-relative

The current signal carries only sector and actor identity. By the time the HUD positions the menu, it has no pointer coordinate. The dock is therefore the stable presentation anchor. This is a deliberate fallback, not evidence that the arena input never had the pointer; TacticalArenaView._gui_input() has event.position at the moment the signal is emitted.

### 6.3 Smallest safe pointer-relative change

Use a presentation-only pointer anchor:

- Extend the arena context signal to carry either event.position plus a local-space contract or, preferably, to_global(event.position) as anchor_global.
- Update _on_arena_context_requested() and the HUD context_requested signal/call sites, including synthetic HUD tests that call the handler directly.
- Store the anchor in HUD-local state or CombatInteractionState as a presentation field; do not put it in CombatActionRequest, CombatActionQuote, or combat snapshots.
- Make _position_context_menu(anchor_global) prefer anchor_global + Vector2(12, 12) and retain the current dock-above position as the fallback for keyboard/context-menu invocations without a pointer.
- Clamp against the HUD global rect after the menu minimum size is known. Preserve the current viewport margins and defer call.

This is the smallest change that fixes pointer-relative placement without changing gameplay authority. Do not route the pointer through GameDirector, CombatActionController, or CombatResolutionEngine.

## 7. Item Presentation Trace

### 7.1 Data path

The ground-item descriptor already carries presentation data:

    MacroCombatEncounterService.build()
      -> CombatEncounterRecord.ground_items
      -> TacticalCombatScene._load_encounter_ground_items()
      -> CombatActionController.ground_items[instance_id] = ItemData
      -> CombatActionController.refresh_snapshot()
      -> _item_snapshot(item, "ground")
      -> sector["ground_items"]
      -> TacticalCombatSnapshotPresenter / CombatInventorySnapshotPresenter
      -> TacticalCombatHUD._render_sector_inspector()

CombatActionController._item_snapshot() includes all of the following for ground and actor item descriptors:

- inventory_sprite_path
- equipped_sprite_path
- equipped_sprite_paths
- sprite_path
- presentation.icon_path
- presentation.sprite_path
- presentation.label

CombatInventorySnapshotPresenter.build() preserves ground_items and filters actor items into accessible_items_by_actor by hands/quick access tier. CombatActorPresentationProjection keeps exact carried items for self/friendly views and redacts hostile/neutral carried inventory as required by the relationship projection.

### 7.2 Current visual behavior

| Surface | Renderer | Icon behavior | Finding |
|---|---|---|---|
| Hands / Quick | TacticalCombatHUD._render_items() | Reads presentation.icon_path, falls back to inventory_sprite_path/sprite_path, and assigns button.icon | Correctly attempts an icon. |
| Equipped gear | _render_gear_row() | Reads sprite_path/inventory_sprite_path, creates a TextureRect child, and preserves a small label | Correctly attempts an icon. |
| Target items | _render_target_items() | Creates a text-only Button; never reads presentation, icon_path, or sprite_path | Friendly/exact target items can have an icon in the snapshot but it is omitted. Hostile/neutral item redaction is still correct. |
| Ground items | _render_ground_items() | Creates a text-only Button; never reads presentation, icon_path, or sprite_path | Confirmed: ground icons are omitted by the HUD even when the snapshot already contains the path. |
| Active weapon card | CombatItemCard.show_descriptor() | Loads sprite_path/inventory_sprite_path into weapon_image | Static card image plus pulse; not a source-sheet animator. |

The answer to the specific ground-icon question is therefore yes: the path exists in the snapshot, and _render_ground_items() drops it. The same omission exists for target-item rows when target items are present. The omission is not caused by CombatInventorySnapshotPresenter or ItemData.from_runtime_state().

### 7.3 Recommended presentation change

Create a shared presentation-only item row/list component or helper consumed by _render_items(), _render_target_items(), _render_ground_items(), and optionally _render_gear_row(). It should accept a descriptor and an explicit mode (hands_quick, target, ground, gear), resolve the icon path using the same fallback order, preserve relationship redaction, and bind the correct selection callback. Add a headless UI test with a non-empty presentation.icon_path for hands, friendly target, and ground descriptors; assert that the corresponding buttons receive textures while hostile/neutral redaction remains empty.

## 8. Weapon Animation Timeline Trace

### 8.1 Request-to-cue sequence

1. TacticalCombatScene._execute_pending_action() takes the pending request from the interaction coordinator and awaits CombatActionController.request_action(request).
2. CombatActionController.request_action() normalizes the request, obtains the authoritative quote, begins the turn-manager action transaction, dispatches the resolver, commits AP, appends resolution presentation events, and calls definition.presentation_profile.build_sequence(request, action_quote, outcome).
3. CombatPresentationProfile.build_sequence() creates CombatPresentationSequence, computes marker durations, assigns CombatPresentationCue records, and writes total_duration_seconds, release marker, impact marker, action/target IDs, weapon metadata, animation IDs, VFX, SFX, and normalized sequence progress.
4. The controller emits action_committed, then presentation_requested, and awaits presentation_acknowledged.
5. TacticalCombatScene._on_presentation_requested() calls hud.show_presentation_action(sequence), awaits TacticalPresentationPlayer.play(sequence), calls hud.finish_presentation(), and acknowledges the exact timeline_id.
6. TacticalPresentationPlayer._play_sequence() waits each cue’s scheduled gap, calls _play_audio_cue(cue), calls TacticalArenaView.begin_cue(cue), tweens update_cue() from 0 to 1 for cue.duration_seconds, and ends the cue.
7. TacticalArenaView.begin_sequence() selects the first weapon cue and gives it to CombatTokenOverlay. update_cue() maps each cue’s local progress into cue.sequence_progress_start/end, causing the overlay to traverse the normalized sequence timeline. CombatTokenOverlay._draw_weapon() converts that normalized progress into an integer source-sheet frame and adjusts the release frame with weapon_release_sequence_progress.

### 8.2 Exact clocks currently in play

| Clock | Current source | Current consumer | Assessment |
|---|---|---|---|
| Gameplay resolution duration | No separate authoritative duration was found. Damage/ammo/relations mutate during request_action() before presentation; the controller then holds a transaction barrier while presentation plays. | CombatActionController busy/presentation barrier | Correctly separate conceptually, but the contract should say “resolution is immediate; presentation is queued” rather than implying a gameplay animation clock. |
| Sequence duration | CombatPresentationSequence.total_duration() sums the latest cue end time; CombatPresentationProfile writes total_duration_seconds | TacticalPresentationPlayer queue completion and TacticalCombatHUD.show_presentation_action() | Authoritative for the presentation barrier. |
| Cue duration | CombatPresentationCue.duration_seconds from profile marker fields | TacticalPresentationPlayer tween and TacticalArenaView cue execution | Correct per-marker clock. |
| Body animation duration | CombatPresentationProfile._authored_animation_duration() uses HumanoidVisualCatalog.animation_frames()/animation_fps(); stored as sequence.authored_animation_duration_seconds and cue field | Profile pads actor anticipation/release/recovery; token one-shot target animation uses cue flags | This is the humanoid body-track duration, not firearm source-sheet duration. |
| Firearm source-sheet duration | CombatWeaponPresentationDefinition.duration_for_action() computes frame count / FPS | Profile reads it as weapon_duration, but only uses it to extend travel for reload, cycle, and clear_malfunction; firearm fire does not use it to set the sequence clock | The authored sheet duration is not the card duration and does not independently drive fire. |
| Firearm overlay progress | TacticalArenaView.update_cue() maps each cue into normalized sequence progress; CombatTokenOverlay._draw_weapon() maps that to sheet frames and release progress | Overhead weapon sheet | The firearm sheet is traversed over the sequence timeline, not over its own authored duration. |
| Active weapon card duration | TacticalCombatHUD.show_presentation_action() calls active_weapon_card.play_turn_action(sequence.action_id, sequence.total_duration()) | CombatItemCard._pulse_remaining and image modulation | Exact current answer: the complete sequence duration drives the card pulse. The card does not animate the firearm source sheet. |

For the authored ranged profile, ranged_presentation_profile.tres sets wind_up_seconds = 0.38, transit_seconds = 0.26, contact_seconds = 0.14, reaction_seconds = 0.44, impact_seconds = 0.24, settle_seconds = 0.24, actor_animation_id = Attack1, target_animation_id = TakeDamage, sfx_id = weapon_fire, vfx_id = projectile, and projectile = true. Those marker values form the sequence clock. They do not establish a separate firearm-card clock.

### 8.3 Contract mismatch and safe target design

COMBAT_UI_SPECIFICATION.md says the firearm card must traverse the full source sheet over an authored duration and that action duration/cue fraction drive actor windup and weapon-card playback. The current implementation does not do that: CombatItemCard only pulses a static weapon_image, while CombatTokenOverlay animates the source sheet over normalized full-sequence progress.

Before editing code, define these separate fields explicitly:

1. resolution_committed: a gameplay fact, with no presentation duration.
2. sequence_duration_seconds: the full queued presentation barrier.
3. cue.duration_seconds: one marker’s duration.
4. body_animation_duration_seconds: the humanoid sheet track duration.
5. weapon_sheet_duration_seconds: the weapon source sheet duration for the specific action and weapon.
6. weapon_release_progress: the authored release point, expressed relative to the weapon sheet.
7. weapon_card_effect_duration_seconds: the card’s pulse or source-sheet playback duration, explicitly selected by the presentation policy.

Then decide whether the card is meant to be a static status card with a pulse or a true source-sheet player. Do not let sequence.total_duration() silently serve all of those roles. Add a timeline smoke that checks each value independently and verifies release occurs before impact without requiring one clock to equal another.

## 9. Combat SFX Event Trace

### 9.1 Resolution-side injury path

The resolution path is:

CombatResolutionEngine._execute_shot() or the melee equivalent -> _apply_weapon_damage() / _apply_unarmed_damage() -> victim.body.apply_targeted_hit() -> HumanoidBody emits GameEventBus.humanoid_injured(self, wound_type).

SoundCore/sfx_conductor.gd connects to GameEventBus.humanoid_injured and routes it to the HumanInjured1-5 pool. The same resolution path also emits damage_applied and damage_resolved records with attacker and victim identity while CombatActionController records the result during the busy action transaction.

This is the generic biological injury route. It is the only route that is naturally tied to an actual wound and it works for firearm, melee, and any other damage source that calls HumanoidBody.apply_targeted_hit().

### 9.2 Presentation-side action and impact path

TacticalPresentationPlayer._play_audio_cue() emits scene_audio_requested("combat_action_sfx", payload) when a cue has an sfx_id. The payload currently contains action_id, weapon_class, and weapon_id. SfxConductor._on_scene_audio_requested() forwards that to _on_combat_action(), which maps fire and aimed_fire to the gun pool, reload/cycle to the weapon handling pool, and strike/power/aimed/shove/block to the punch pool.

For an impact cue, TacticalPresentationPlayer also emits scene_audio_requested("combat_damage_sfx", result) unless the outcome tag is miss, dodge, neutral, or malfunction. SfxConductor routes that event to _play_combat_injury(). The impact route therefore plays a HumanInjured sound even when the resolution did not create a wound. Its exclusion list does not explicitly exclude cover or block-like outcomes.

### 9.3 Duplication and identity findings

On a successful wound, both paths can fire:

1. HumanoidBody.apply_targeted_hit() emits humanoid_injured, and SfxConductor plays a HumanInjured sound.
2. The impact cue emits combat_damage_sfx, and SfxConductor plays another HumanInjured sound.

That is a likely duplicate injury sound. It is not proven for every presentation branch because the live audio bus is not covered by a direct test, but the two independent call paths are present.

Resolution and CombatPresentationCue retain actor_id and target_id. The scene_audio_requested payload drops those identities, and humanoid_injured carries only the body entity and wound type. The conductor therefore cannot currently correlate an action sound, impact sound, and injury sound by encounter, action, attacker, victim, region, or source item. CombatResolutionEngine._emit_shot() also hardcodes action_id = fire, so aimed_fire loses its action identity on that event route.

Recommended target: keep HumanoidBody as the generic wound authority, but make combat impact audio a typed presentation/contact event rather than a second generic injury event. If a damage sound needs combat context, carry encounter_id, action_id, attacker_id, victim_id, region, source_item_id, damage_type, and outcome_tag in one typed payload. Choose one conductor route for the HumanInjured pool and test that one successful wound produces one injury cue.

## 10. Documentation Drift

> Historical record only. The document rows and gap descriptions below describe
> the pre-implementation repository. Do not use them as current authority; the
> current production contract and remaining acceptance boundary are recorded in
> Section 23.

The repository contains a historical combat design that still describes duel_12x1 as production, reserved AP reactions, posture controls, and reaction prompts. The supplied reconciliation brief is the newer locked baseline. The conflict must be resolved by updating the focused combat documents, not by silently treating every old paragraph as current.

| Document | Drift | Reconciliation |
|---|---|---|
| README.md | Describes 1v1 lane duels, 12 x 1 as the concise production mode, AP banking for reactions, and larger grids as future scaffolding. | State squad_7x5, orthogonal movement, six-actor cap, player-only control, pairwise hostility, LEAVE BATTLE, and no reserved AP/reaction prompt. |
| READMEs/design/TURN_BASED_COMBAT_OVERHAUL.md | Says GameDirector always launches duel_12x1 and makes reaction windows and transaction barriers authoritative. | Replace the production route with the current GameDirector -> TacticalCombatScene handoff; retain duel resources only as explicitly named Lab fixtures. |
| READMEs/design/COMBAT_UI_SPECIFICATION.md | Mixes the current snapshot/intent boundary with stance/posture, Kinetic Burden, CP wording, reaction prompt, twelve-slot lane, Block/Parry controls, Melee Lock hints, and full-sheet firearm wording. | Rewrite the live interaction contract around the locked HUD, relationship-aware inspection, context menu, item projections, and the separate presentation clocks. Preserve visual principles that remain valid. |
| READMEs/SYSTEM_ARCHITECTURE.md | Describes the old TurnBasedDuelScene and realtime lane as the main CombatCore split, while also containing newer presentation-boundary guidance. | Update production topology and scene ownership; keep the neutral snapshot/intent boundary and CombatCore prohibition on res://UI imports. |
| READMEs/GLOSSARY.md | Defines the twelve-slot Combat Lane, AP banking, Guard/Parry, Melee Lock, reaction terms, and old posture/lock actions as live vocabulary. | Mark historical terms retired or Lab-only and define squad topology, player-hostile relation, NPC-NPC continuation, and LEAVE BATTLE. Retain Stance only with its locked meaning. |
| READMEs/CHANGELOG.md | Records historical transitions through reserved reactions, Dodge, Crouch, and duel production. | Do not rewrite history. Add a dated reconciliation entry only after the implementation migration lands. |
| READMEs/design/VISUAL_DIRECTION.md | Uses CombatLaneHUD and realtime-lane naming in an otherwise useful snapshot/presentation section. | Rename only the stale current-system references; preserve the visual direction and readability principles. |
| CHATGPT_PROJECT_PACK/PROJECT_INSTRUCTIONS.md | Its authority order is useful, but its baseline summary still points readers toward older combat documents. | Update only the combat authority pointer and baseline summary after the focused documents are reconciled. |

## 11. Tests Protecting Each Area

| Area | Existing protection | Gap or migration |
|---|---|---|
| Topology catalog and dimensions | CombatDuelTopologySmoke loads duel_12x1, skirmish_6x3, and squad_7x5. ResourceCatalogValidationSmoke checks catalog membership. CombatLabSquadSmoke covers a six-actor squad Lab shape. | CombatDuelTopologySmoke contains a production-duel error and a production-shaped fixture. Rewrite its label/assertion as legacy Lab coverage and add a squad production assertion. |
| Production handoff | CombatRuntimeHandoffSmoke, CombatOverlayHandoffSmoke, CombatTerminalHandoffSmoke, and related scene tests cover the tactical handoff. GameDirector explicitly forces squad_7x5. | Add a direct handoff assertion that a normal GameDirector request cannot select duel_12x1, while preserving an isolated Lab override test. |
| Death and lifecycle | TacticalCombatDeathLifecycleSmoke covers tactical death and currently sets duel_12x1. | Migrate the production-shaped fixture to squad_7x5; retain a separate topology fixture only if death behavior is intentionally topology-independent. |
| Multi-occupancy and collision | CombatMultiOccupancySmoke, CombatMultiOccupancyFireSmoke, CombatCrowdedCollateralSmoke, CombatArenaOverhaulSmoke, and TacticalCombatRulesSmoke cover occupied cells, collateral, and movement rules. | Keep these as core protection; add explicit seven-column/five-row deployment and no-late-entry assertions where missing. |
| LEAVE BATTLE and relations | CombatLeaveBattleSmoke and CombatTerminalHandoffSmoke cover the player-hostile gate. CombatNeutralAttackSmoke and CombatCommunicationSmoke cover neutral and NPC-NPC relationships. | Keep and add the exact “no player-hostile, NPC-NPC hostile remains” continuation case if not already asserted in the terminal smoke. |
| AI authority | TacticalCombatAI*, CombatAIArchitectureContractSmoke, CombatAIHardStateSmoke, CombatAIIntentSmoke, CombatAIMotiveSmoke, CombatAIPerceptionSmoke, CombatAIPlannerSmoke, CombatAIPrerequisiteAuthoritySmoke, CombatAIProblemSmoke, CombatAIQuoteAuthoritySmoke, CombatAIRequestProviderSmoke, CombatAIThreatSmoke, and CombatAIUtilitySmoke cover the current Lab/production AI seams. | Add the locked AI-only interrupt replacement case for an ally shoved out of Engagement; explicitly assert that no player reaction prompt or reserved AP is required. |
| HUD and layout | TacticalHUDLayoutSmoke covers 6x3/7x5 snapshots, but its sample snapshot still carries reserved_ap, posture, facing, and a 12x1-shaped setup. | Update the fixture to the locked snapshot and add a context-menu anchor/clamp assertion at each edge of the viewport. Physical mouse acceptance remains separate. |
| Interaction state | CombatInteractionStateSmoke covers keyboard/selection state. | Add pointer-anchor state only if the presentation layer owns it, test root-menu fallback without a pointer, and keep physical RMB testing distinct from headless tests. |
| Projection and item display | CombatUIPresentationProjectionSmoke covers redaction and projection; TacticalHUDLayoutSmoke covers rows and cards. | Add exact icon-path assertions for Hands/Quick, target, and ground items, including hostile redaction. The current target/ground rendering omission is not protected. |
| Retired actions and rules | CombatActionCatalogSmoke hides the retired action list. CombatExperienceRebuildSmoke checks no Brace and exercises move/shove/ranged presentation. TacticalCombatRulesSmoke still executes Crouch and Stand and expects posture costs. | Replace visibility-only checks with authority checks. Migrate or delete the contradictory posture test only after the locked replacement semantics are specified. |
| Weapon presentation | CombatExperienceRebuildSmoke checks ranged marker order, release before impact, cue identity, and overlay geometry. CombatProjectileAuthoritySmoke and CombatWeaponOverlayGeometrySmoke cover projectile and overlay behavior. | Split sequence, body, weapon-sheet, and card clocks in the smoke; verify the card does not silently use sequence.total_duration() as a firearm-sheet duration. |
| Sound | There is no direct SfxConductor/GameEventBus/HumanoidInjured test. CombatExperienceRebuildSmoke only checks cue.sfx_id = weapon_fire. | Add a presentation-only audio trace smoke that asserts one action sound, one impact/contact sound, one injury sound per wound, preserved identity, and no duplicate injury event. Follow with live audio verification. |

## 12. Recommended Implementation Order

1. Freeze the replacement contract in a short decision record: cover behavior without facing, the fate of aimed_strike/aimed_fire, the exact AI-only Engagement interrupt, and save/replay compatibility for old snapshots.
2. Reconcile topology names and production tests. Keep duel_12x1 and skirmish_6x3 as named Lab resources only where a test explicitly requires them; make squad_7x5 the only production assertion.
3. Remove retired reaction authority in one coordinated slice: action definitions and visibility, quote fields, controller validation, turn-manager inert API, reaction resolver, board threat/facing helpers, HUD reaction panel, and contradictory tests. Preserve the action transaction’s temporary AP reservation because it is not reserved reaction AP.
4. Repair item presentation: keep the snapshot/projection fields, add icons to target and ground rows if the design wants them, preserve hostile redaction, and add projection/render tests before styling changes.
5. Implement the smallest pointer fix: pass a global pointer anchor from TacticalArenaView through the presentation interaction path, place the context menu near it, clamp against the HUD viewport, and retain dock-relative fallback for keyboard or synthetic requests.
6. Separate presentation clocks and define whether CombatItemCard is a pulse card or a true weapon-sheet player. Update the sequence/profile/catalog only where that explicit policy requires it, then add clock and release-marker tests.
7. Make SFX routing single-source for injury, preserve typed combat identity through the audio event, correct the hardcoded fire action identity, and add the direct audio trace smoke.
8. Update focused documentation and add a dated changelog note. Run exact Godot 4.7.1 headless smokes with isolated app data, then perform live/editor/physical-input/audio verification at the requested resolutions.

## 13. Files Expected To Change

This list is a change map, not authorization to edit all of these files in this audit.

### Topology and test labels

- CombatCore/CombatModeComparison.gd and CombatCore/CombatModeComparison.tscn, if the Lab labels must stop calling duel production.
- Tests/CombatDuelTopologySmoke.gd, Tests/ResourceCatalogValidationSmoke.gd, Tests/TacticalCombatDeathLifecycleSmoke.gd, Tests/CombatRuntimeHandoffSmoke.gd, Tests/CombatOverlayHandoffSmoke.gd, and Tests/TacticalHUDLayoutSmoke.gd.
- Tests/CombatLabSquadSmoke.gd only if its assertions or labels still describe the old default.

### Retired rule authority

- CombatCore/Tactical/TacticalTurnManager.gd.
- CombatCore/Tactical/CombatActionCatalog.gd and CombatCore/Tactical/default_combat_action_catalog.tres.
- SystemCore/CombatActionDefinition.gd, SystemCore/CombatActionQuote.gd, CombatCore/Tactical/CombatActionQuoteService.gd, and any outcome/forecast record that only transports retired reaction or facing fields.
- CombatCore/Tactical/CombatActionController.gd, CombatCore/Tactical/TacticalCombatRulesState.gd, CombatCore/Tactical/CombatReactionResolver.gd, CombatCore/Tactical/CombatBoard.gd, and CombatCore/CombatResolutionEngine.gd.
- CombatCore/Tactical/TacticalCombatScene.gd, CombatCore/Tactical/TacticalCombatHUD.gd, CombatCore/Tactical/TacticalCombatHUD.tscn, CombatCore/Tactical/TacticalArenaView.gd, and CombatCore/Tactical/CombatActorPresentationProjection.gd.
- Tests/CombatActionCatalogSmoke.gd, Tests/TacticalCombatRulesSmoke.gd, Tests/CombatExperienceRebuildSmoke.gd, and any reaction/facing/posture tests discovered during the implementation slice.

### Item, pointer, and timeline presentation

- CombatCore/Tactical/TacticalArenaView.gd, CombatCore/Tactical/TacticalCombatHUD.gd, CombatCore/Tactical/CombatInteractionState.gd, and CombatCore/Tactical/TacticalCombatInteractionCoordinator.gd as needed for presentation-only state and layout.
- CombatCore/Tactical/CombatItemCard.gd and CombatCore/Tactical/CombatTokenOverlay.gd for the chosen card/sheet contract.
- CombatCore/Tactical/CombatPresentationProfile.gd, CombatCore/Tactical/CombatPresentationSequence.gd, CombatCore/Tactical/CombatPresentationCue.gd, CombatCore/Tactical/CombatWeaponPresentationCatalog.gd, CombatCore/Tactical/CombatWeaponPresentationDefinition.gd, and the ranged presentation resource only if the explicit clock policy changes.
- New or updated presentation tests for target/ground icons, pointer anchoring, and independent timeline clocks.

### SFX

- CombatCore/Tactical/TacticalPresentationPlayer.gd, SoundCore/sfx_conductor.gd, SystemCore/GameEventBus.gd if a typed payload is introduced, and CombatCore/CombatResolutionEngine.gd.
- BiologicalCore/HumanoidBody.gd only if the generic injury event needs a non-breaking combat context extension.
- A new direct sound/event trace smoke under Tests/.

### Documentation

- README.md.
- READMEs/design/TURN_BASED_COMBAT_OVERHAUL.md.
- READMEs/design/COMBAT_UI_SPECIFICATION.md.
- READMEs/SYSTEM_ARCHITECTURE.md.
- READMEs/GLOSSARY.md.
- READMEs/design/VISUAL_DIRECTION.md.
- READMEs/CHANGELOG.md, by adding a dated entry rather than rewriting history.
- CHATGPT_PROJECT_PACK/PROJECT_INSTRUCTIONS.md only for authority pointers after the focused documents are corrected.

## 14. Files That Should NOT Need To Change

- CombatCore/Tactical/Topologies/squad_7x5.tres: it already represents the locked production topology.
- CombatCore/Tactical/Topologies/duel_12x1.tres and CombatCore/Tactical/Topologies/skirmish_6x3.tres: retain them as Lab/compatibility resources until the explicit migration decision says otherwise.
- CombatCore/Tactical/default_combat_topology_catalog.tres and SystemCore/CombatTopologyProfile.gd: their default/fallback already points to squad_7x5.
- SystemCore/CombatEncounterRecord.gd: its CP/squad_points compatibility fields are not reserved AP and should not be removed as part of this cleanup.
- WorldCore/GameDirector.gd, WorldCore/MacroGameManager.gd, WorldCore/MacroCombatEncounterService.gd, and the encounter assembly services: the current production handoff already forces squad_7x5; only add a test if the handoff contract needs stronger protection.
- EncounterBuilder, ArenaGenerator, CombatForecastService, RelationshipLedger, and CommunicationResolver unless the implementation phase finds a concrete contract violation.
- HumanoidToken, weapon art, sound assets, and other content resources: the audit found routing/authority problems, not an asset-retirement requirement.
- Any CombatCore -> res://UI import boundary: preserve the neutral combat-owned snapshot/projection seam.
- Codex files, attachment files, ignored logs, or unrelated worktree artifacts: they are outside this audit’s authorized scope and should not be deleted as part of combat reconciliation.

## 15. Deletion / Retirement Candidates

| Candidate | Why it is removable | Gate |
|---|---|---|
| TacticalCombatReactionResolver.gd | Its production role is inert if no reaction threats or prompts remain. | Remove only after all callers and Lab-only callers are classified. |
| TacticalTurnManager reaction signals and open/resolve/decline methods | They are compatibility shells returning empty/false. | Remove after callers and serialized test fixtures are migrated. |
| reserved_ap compatibility field and _reserved_snapshot exposure | The locked contract has no reserved reaction AP. | Remove after snapshot consumers and old replay/save fixtures are addressed. Keep action transaction reservation under a different name. |
| ReactionPanel in TacticalCombatHUD.tscn and show_reaction compatibility methods | The scene hides it and the reaction callback returns immediately. | Remove after no UI/test entry point expects the compatibility sink. |
| Stand, Crouch, Disengage, Block, Dodge, and Opportunity Strike definitions | They are hidden and/or explicitly retired, while several resources still carry their metadata. | Remove after posture/facing/cover replacement behavior is locked and tests are rewritten. Treat aimed_strike and aimed_fire as a separate product decision. |
| RETIRED_PLAYER_ACTIONS and reaction-only visibility branches | They become dead policy after retired definitions are removed. | Delete last, after catalog validation proves no serialized reference remains. |
| CombatActionQuote reaction_threat_ids, ordered_reaction_steps, and related fields | They transport no current production reaction resolution. | Remove only after quote consumers and old Lab fixtures are mapped. |
| CombatBoard.reaction_threats(), attack_arc(), and attack_arc_from() | They support the retired reaction/facing model; no production call site was found for the attack-arc methods. | Replace cover semantics first; preserve only if a current neutral consumer is identified. |
| Persistent actor facing/final_facing fields | The locked baseline has no directional facing authority. | Do not remove until cover, animation orientation, saves, and tests have an explicit replacement. |
| Duel production labels in CombatModeComparison and old documents | They are misleading, not necessarily code-dead. | Rename/rewrite; do not delete the duel Lab resource. |
| Cue marker named reaction | The current presentation marker is not the old player reaction window, but the name invites confusion. | Rename only after the presentation vocabulary is approved; it may mean target response timing rather than a gameplay reaction. |

## 16. Open Risks

1. Cover and facing are coupled in CombatBoard.take_cover(), movement quote generation, final-facing commits, snapshots, and presentation. Removing facing without defining replacement cover semantics can change resolution outcomes.
2. The focused documents disagree about the production topology and reaction contract. Until the locked baseline is applied to those documents, implementation review cannot reliably distinguish intentional compatibility from live authority.
3. Aimed_strike and aimed_fire are both retired in the catalog but still have presentation and resolution metadata. Removing them without deciding whether they are genuinely retired risks deleting intended player actions.
4. The AI-only interrupt replacement is described at the contract level but its exact trigger, state transition, and test fixture are not yet specified.
5. Save, replay, and serialized fixture compatibility for reserved_ap, posture, facing, and old topology IDs was not fully indexed by this audit. A destructive field removal could strand old runs.
6. TacticalCombatHUD currently combines projection rendering, selection, context-menu layout, presentation handoff, and compatibility sinks. A broad extraction would create more ownership ambiguity unless each seam is migrated one slice at a time.
7. Pointer-relative context-menu behavior needs physical mouse verification. Headless layout tests can prove clamp math but not engine input propagation or perceived placement.
8. Sequence, cue, body-animation, weapon-sheet, release-marker, and card-effect clocks are currently conflated in places. Changing one duration can alter perceived timing without changing gameplay resolution.
9. SFX has at least two paths to HumanInjured and an impact exclusion list that may misclassify cover/block results. The duplicate is structurally likely but needs an event-level test and live audio check.
10. Combat audio payloads lose actor identity between resolution/presentation and SfxConductor, making future per-actor mixing or debugging unreliable.
11. CombatResolutionEngine._emit_shot() hardcodes fire for a shot event, which can make aimed-fire telemetry/audio incorrect even before the broader cleanup.
12. Duel fixtures are useful for topology and compatibility coverage. Removing them wholesale would reduce confidence in catalog loading and old-run migration.
13. No direct sound test currently protects weapon, impact, or HumanInjured routing, so a green gameplay smoke suite would not prove audio correctness.
14. The worktree was clean at audit start and only this audit file is authorized to change. Any unrelated diff appearing before implementation should be treated as a blocker and investigated, not swept away.

Implementation is unsafe until the cover/facing replacement, aimed-action disposition, and compatibility policy for old serialized combat state are explicit. Once those three decisions are recorded, the remaining changes can be staged in the order above with focused tests at each gate.

## 17. Locked Decisions and Implementation Handoff

The audit findings above are the evidence base. The following decisions were made collaboratively after the audit and supersede the remaining product-decision wording in earlier sections.

### 17.1 Session configuration for the implementation agent

Use GPT-5.6 Sol (gpt-5.6-sol) with reasoning effort xhigh. Keep the connected MCP tools enabled and use them for the project/Godot capabilities they actually expose. If the client cannot honor the requested model or effort, report the effective configuration before implementation rather than silently substituting another model.

### 17.2 Locked combat and compatibility decisions

- Keep strike and fire as the canonical default attack IDs.
- Derive strike for BLUNT/BLADE weapons and fire for PISTOL/RIFLE/SHOTGUN weapons.
- Add an extensible weapon-authored specialized-action list to ItemData. The catalog remains authoritative for action behavior, costs, legality, effects, presentation, and AI metadata.
- Do not implement burst_shot in this cleanup. The schema must support it later.
- Retire aimed_strike, aimed_fire, and generic power_strike.
- Retire stand, crouch, disengage, clear_malfunction, block, dodge, and opportunity_strike.
- Keep cycle as the jam-clearing action. Do not retain a clear_malfunction alias.
- Keep shove, take_cover, engage, escape, leave_battle, incapacitate, execute, inventory actions, and communication actions unless implementation evidence finds a separate violation.
- Unknown weapon action IDs fail validation clearly with the weapon and action named.
- Cover is geometry-only. Remove persistent combat facing, rear/flank modifiers, and posture state; retain Stance, wounds, equipment, range, observable conditions, and cover.
- Old combat schemas are rejected with a clear error. Do not silently discard retired fields.
- A shove that moves an AI ally out of hostile Engagement queues one AI-only replan after the shove/presentation completes. It does not grant a bonus action, spend AP, alter turn order, or open a player prompt.
- The active weapon card in the player HUD remains static with an explicit pulse effect. Map presentation owns weapon animation.
- Ranged map presentation uses the existing authored firearm source sheets.
- Melee map presentation reuses existing static equipped-item sprites as animated hit cues; do not create a second melee asset set in this cleanup.
- HumanoidBody's actual wound event is the sole authority for HumanInjured audio. Presentation impact audio is contact/action audio, never a second injury sound.
- Implement in gated slices, update stale documentation in the final slice, and require headless plus live QA.

### 17.3 Implementation contract

The implementation should add a typed weapon-action projection with the following behavior:

- ItemData owns a specialized_action_ids collection, serializes it through definition/runtime state, and exposes the derived default plus specialized IDs in deterministic order without duplicates.
- CombatActionCatalog exposes the weapon-action projection and strict validation. Maintenance actions such as reload, cycle, and ready remain state-derived actions rather than specialized attack IDs.
- CombatActionDefinition gains explicit weapon-action family metadata so controller, quote, forecast, HUD, and AI code do not maintain growing action-ID lists.
- Generic melee/ranged resolution accepts the action definition and action ID, allowing future specialized actions to reuse family logic while changing effect, AP, targeting, presentation, or SFX data.
- CombatArenaState and related combat snapshot readers enforce the current combat schema instead of accepting arbitrary historical versions. The global world-save version changes only if the current save payload actually embeds tactical combat state.
- CombatPresentationCue/Sequence carry distinct body, cue, map-weapon, release-marker, and static-card-effect timing. CombatItemCard never becomes a source-sheet player.
- TacticalArenaView passes a global pointer anchor through the presentation interaction path; the HUD clamps pointer-relative menus and retains dock fallback for pointerless requests.
- Audio payloads preserve encounter/action/actor/target/weapon identity wherever the event is combat-specific, and shot events preserve the actual action ID.

### 17.4 Gated execution order

1. Contract gate: weapon action schema, catalog projection, strict validation, topology vocabulary, and combat schema rejection tests.
2. Rules gate: remove retired action/reaction authority, preserve only in-flight transaction-cost reservation, remove posture/facing/arc state, implement geometry-only cover, and add AI-only shove replanning.
3. Presentation gate: pointer-relative context menus, target/ground icons, static HUD card behavior, ranged overlay animation, and melee sprite animation.
4. Audio/timeline gate: independent clocks, single-source injury audio, typed contact events, identity preservation, and direct SFX tests.
5. Documentation gate: reconcile focused combat documents, update the audit decisions, add a dated changelog note, run the complete smoke suite, and perform live/editor/physical-input/audio QA.

## 18. Single-Copy/Paste New-Agent Work Order

Copy the prompt below into a new implementation chat after selecting the requested model and enabling the connected MCP tools.

~~~~text
You are the implementation agent for the ARCCROSS combat reconciliation cleanup.

SESSION CONFIGURATION

Use GPT-5.6 Sol, model ID gpt-5.6-sol, with reasoning effort xhigh. Keep all connected MCP tools enabled and use them when they provide relevant Godot, project, terminal, or validation capabilities. If the client exposes a different effective model/effort, report that first; do not silently substitute another model.

WORKSPACE

Repository:
C:\Users\Zerato\OneDrive\Documents\arccross_system

Current branch and baseline:
alpha-release-baseline at fdde567b

Primary handoff document:
READMEs/design/COMBAT_RECONCILIATION_AUDIT.md

Read that document completely before editing. It contains the repository evidence, exact paths/functions, the locked decisions, and this work order. Also read the focused authority documents in their project-defined order:

- CHATGPT_PROJECT_PACK/PROJECT_INSTRUCTIONS.md
- README.md
- READMEs/design/TURN_BASED_COMBAT_OVERHAUL.md
- READMEs/design/COMBAT_UI_SPECIFICATION.md
- READMEs/SYSTEM_ARCHITECTURE.md
- READMEs/GLOSSARY.md
- READMEs/design/VISUAL_DIRECTION.md
- READMEs/CHANGELOG.md

MISSION

Implement the complete locked reconciliation in the audit. This is an implementation task, not another reconnaissance report. Work through every gate, run the relevant tests after each gate, and continue until the authorized implementation and verification are complete.

Do not reset, checkout, blanket-clean, or delete unrelated user work. Preserve active implementation and investigate any unexpected pre-existing diff. The only cleanup scope is the combat reconciliation described in the audit. Do not delete Codex files, attachments, ignored logs, or unrelated WIP.

LOCKED PRODUCT DECISIONS

- Production combat is squad_7x5: seven columns by five rows, orthogonal movement, maximum six actors, player controls only the player actor, NPCs act autonomously, relationships are pairwise, and combat continues while any active actor is hostile to the player.
- LEAVE BATTLE is legal when no active actor remains hostile to the player, even if NPC-vs-NPC hostility remains.
- Every actor receives a normal AP pool. Ending a turn discards unused AP.
- There is no reserved AP economy, reaction prompt, reaction window, opportunity strike, Block, Dodge, Brace, Stand, Crouch, posture mode, persistent directional facing, rear attack, or flank modifier.
- Defense remains based on wounds, Stance, equipment, cover, range, and observable conditions.
- Keep strike and fire as canonical default attack IDs. BLUNT/BLADE derive strike; PISTOL/RIFLE/SHOTGUN derive fire.
- Add an extensible specialized_action_ids list to ItemData. The catalog owns behavior. Unknown IDs fail validation with the weapon and action named.
- Do not implement burst_shot yet. The extension point must be real and tested, but new specialized gameplay is future work.
- Retire aimed_strike, aimed_fire, power_strike, stand, crouch, disengage, clear_malfunction, block, dodge, and opportunity_strike. Do not retain aliases.
- Keep cycle as jam clearing. Keep shove, take_cover, engage, escape, leave_battle, incapacitate, execute, inventory actions, and communication actions.
- Cover is geometry-only. A selected cover edge may remain as cover state, but it must never be actor facing and must never create rear/side/reaction modifiers.
- Old combat schemas are rejected clearly. Do not silently drop retired fields.
- When a shove moves an AI ally out of hostile Engagement, queue exactly one AI-only replan after shove presentation completes. Do not grant a bonus action, spend AP, alter turn order, or show a player prompt.
- The active weapon card in the top-left player HUD remains a static item/status card with an explicit pulse effect.
- Ranged weapon animation occurs on the entity inside the map using existing authored firearm source sheets.
- Melee hit animation occurs on the entity inside the map by animating the existing static equipped-item sprite. Do not create another melee asset set.
- HumanoidBody wound events are the sole HumanInjured sound authority. Presentation impact events must never produce a second injury sound.
- Implement in gated slices. Documentation is the final slice. Completion requires exact Godot 4.7.1 headless validation plus live/editor/physical-input/audio QA.

REQUIRED GATES

GATE 0: BASELINE AND CONTRACT

1. Check git status, branch, HEAD, and tracking state. Do not alter unrelated changes.
2. Read the complete audit and authority documents.
3. Add ItemData specialized_action_ids serialization/hydration and deterministic default-action projection.
4. Add catalog projection and strict unknown-action validation.
5. Add explicit weapon-action family metadata and replace hard-coded action-ID classification where required.
6. Keep maintenance actions state-derived.
7. Add or update tests for default actions, specialized action selection, duplicate IDs, and unknown IDs.
8. Add strict combat schema/version rejection tests. Preserve the existing clear-error/backup pattern for incompatible run data.

GATE 1: RULE AUTHORITY

1. Remove retired action definitions and compatibility aliases from the default catalog.
2. Remove reaction signals, prompt paths, reaction resolver shells, public reserved_ap snapshot fields, and dead Block/Dodge/opportunity branches.
3. Preserve only the transient in-flight action-cost reservation, with a name that cannot be confused with reserved reaction AP.
4. Remove posture state and Stand/Crouch resolvers.
5. Remove persistent actor facing, final-facing quote commits, attack arcs, and rear/side modifiers.
6. Preserve geometric direction helpers for movement and shove displacement.
7. Implement geometry-only cover by comparing the incoming geometric edge, sector cover strength, and selected cover edge without mutating actor facing.
8. Remove aimed and generic power-strike branches from controller, forecast, quote, AI, presentation, HUD, and tests.
9. Keep cycle as the one jam-clearing action; remove clear_malfunction execution and aliases.
10. Add the AI-only shove-out-of-Engagement replan signal/queue. Verify it causes no out-of-turn action or AP mutation.

GATE 2: PRESENTATION

1. Extend TacticalArenaView context requests with the global pointer anchor.
2. Position and clamp the HUD context menu near the pointer, retaining dock fallback for pointerless requests.
3. Render target and ground item icons from the already-present snapshot presentation paths while preserving hostile redaction.
4. Keep CombatItemCard static in the top-left HUD and make its pulse duration explicit.
5. Make CombatTokenOverlay own map weapon animation.
6. Use existing firearm source-sheet animation for ranged actions.
7. Reuse existing static equipped-item sprites for melee hit animation.
8. Separate sequence duration, cue duration, body animation duration, map weapon-track duration, release marker, and HUD card pulse duration.
9. Do not generate or add a second melee asset set.

GATE 3: AUDIO AND TIMELINE

1. Keep HumanoidBody.humanoid_injured as the sole HumanInjured route.
2. Change presentation impact audio to typed contact/action audio that cannot trigger HumanInjured.
3. Preserve combat identity in action/contact payloads: encounter, action, actor, target, weapon, outcome, and damage type where available.
4. Correct any hardcoded fire action identity in resolution/event emission.
5. Add direct SFX/event tests proving one successful wound produces one injury sound and cover/block/contact does not create a false injury sound.
6. Add timeline tests proving release precedes impact and each clock is independently meaningful.

GATE 4: DOCUMENTATION AND RELEASE VALIDATION

1. Update README.md, TURN_BASED_COMBAT_OVERHAUL.md, COMBAT_UI_SPECIFICATION.md, SYSTEM_ARCHITECTURE.md, GLOSSARY.md, VISUAL_DIRECTION.md, and relevant authority pointers so they describe the locked squad topology and current combat contract.
2. Do not rewrite historical CHANGELOG entries. Add one dated reconciliation entry.
3. Update COMBAT_RECONCILIATION_AUDIT.md so the locked decisions and implementation status are accurate.
4. Run exact Godot 4.7.1 smokes from Tests/ using isolated app data. Treat process exit status as authoritative.
5. Run focused catalog, topology, schema, rules, multi-occupancy, leave-battle, neutral-relation, AI, HUD, interaction, item-projection, presentation, timeline, and SFX tests.
6. Perform live/editor/physical QA for RMB menu placement, supported resolutions, target/ground icons, ranged map animation, melee item-sprite animation, timeline feel, and audio.
7. Before reporting completion, verify the worktree contains only intended combat reconciliation changes. Run git diff --cached --check if anything is staged, but do not stage or commit unless explicitly requested.

ARCHITECTURE REQUIREMENTS

- Preserve the neutral snapshot/intent boundary.
- Keep CombatCore free of res://UI imports.
- Keep presentation-only state and pointer anchors out of gameplay authority.
- Make the action catalog, quote service, controller, forecast, AI provider, and HUD consume the same weapon-action projection.
- Do not solve stale documentation by silently merging contradictory rules. Record the locked contract explicitly.
- Headless tests do not prove live/editor/physical-input/audio acceptance. Report those verification classes separately.

REPORTING FORMAT

At each gate, report:

1. Files changed and why.
2. Tests run and exact pass/fail/exit status.
3. Any remaining compatibility or live-QA gap.
4. Whether the next gate is safe to begin.

At final handoff, report:

- the implementation result;
- the exact files changed;
- focused and full test results;
- separate live/editor/physical-input/audio results;
- any unresolved blocker;
- whether the worktree is clean apart from intentional changes.

Do not stop at a plan. Implement the authorized work, verify it, and only stop when the gates are complete or a concrete external blocker is documented.
~~~~

## 19. Implementation Completion Record

Status: **implemented and verified on 2026-08-14**.

### 19.1 Gate closure

- **Gate 0 - baseline and contract:** Added deterministic class-derived weapon
  actions plus `ItemData.specialized_action_ids`, strict catalog validation,
  explicit melee/ranged action families, and combat schema-version rejection.
- **Gate 1 - rule authority:** Removed retired action definitions, reaction and
  reserved-AP APIs, posture, persistent facing, attack arcs, and rear/flank
  authority. Kept only the in-flight pending action cost, geometry-only cover,
  and an exactly-once post-presentation AI shove replan.
- **Gate 2 - presentation:** Added real pointer anchors and viewport clamping,
  projected target/ground icons, a fixed 0.18-second weapon-card pulse,
  authored firearm sheet playback on map entities, and equipped-item sprite
  playback for melee without adding a second asset set.
- **Gate 3 - audio and timeline:** Made `HumanoidBody` wound creation the sole
  `HumanInjured` source, split action/contact audio, carried typed combat
  identity through the route, and separated sequence, cue, body, weapon,
  release, response, and card clocks.
- **Gate 4 - documentation and release validation:** Reconciled the current
  README, architecture, glossary, UI, visual, project-pack, asset-map, phase
  pointer, changelog, and generated architecture-index documents.

### 19.2 Verification evidence

- Exact runtime: Godot `4.7.1.stable.official.a13da4feb`.
- Focused combat, catalog, topology, schema, rules, multi-occupancy,
  leave-battle, neutral-relation, AI, HUD, interaction, projection,
  presentation, timeline, and SFX smokes passed with process exit `0`.
- Full capital-`Tests` smoke sweep: `105/105` passed, `FAILED=0`, exit `0`,
  using isolated workspace-local `APPDATA` and `LOCALAPPDATA`.
- Live MCP captures returned fresh frames at all supported sizes: `1152x648`,
  `1280x720`, `1600x900`, `1920x1080`, `2560x1080`, and `2560x1440`.
- Physical Windows LMB inspected a sector; engine-level LMB inspected an actor.
  Physical Windows RMB opened the menu beside the pointer, with flip/clamp and
  pointerless fallback also covered at every supported size by layout tests.
- Live ranged playback showed the authored revolver sheet on the map entity
  while the player card remained static. Live melee playback reused the
  equipped baton sprite and completed with no game warnings.
- Live item projection produced icon-bearing friendly-target and ground-item
  rows; switching the same target hostile removed the target item row while
  preserving the observable ground item.
- Live ranged event capture observed one successful hit producing one action
  event, one contact event, and exactly one `HumanoidBody` injury event with
  encounter, action, attacker, victim, region, weapon, item, and result
  identity. `CombatAudioIdentitySmoke` independently protects the same route.

### 19.3 Release state

This subsection records the original reconciliation checkpoint. The post-verdict
remediation below supersedes its release state for the current branch.

There are no unresolved implementation blockers. Headless, live framebuffer,
physical-pointer, event/audio-route, and warning-free runtime checks are
recorded separately. Subjective human listening and feel remain normal release
acceptance, not an unimplemented code path. No files were staged, committed, or
pushed; the worktree contains the intentional reconciliation changes and the
originally untracked audit document only.

## 20. Post-verdict remediation record

Status: **remediated and verified on 2026-08-14**.

The verdict against the reconciliation checkpoint identified two release
blockers: the controller-to-quote migration had dropped action-specific legality,
and weapon presentation still mixed parentless geometry, duplicate equipment
layers, authored pivots, and incompatible timing clocks. This follow-up restores
the missing authority and adds regression coverage without changing the locked
combat topology or resurrecting retired mechanics.

### 20.1 Remediation scope

- `CombatRulesState` now projects ground items, item consumable facts, wounds,
  combat side/team identity, direct-player identity, escape edges, and sector
  ground-item membership into the frozen quote input.
- `CombatActionQuoteService` now owns the missing legality for Take Cover,
  Escape, Leave Battle, Incapacitate, Execute, Ready, Use, Treat, Pick Up,
  Drop, Rummage, Strip, and Interact. Ground pickup validates existence,
  sector membership, and adjacency before the controller mutates inventory.
- `CombatActionController` mirrors those checks defensively, including null-safe
  treatment, terminal-action, escape, strip, interaction, and ground-item
  resolution. Specialized weapon actions are catalog-rejected unless they use
  the canonical `weapon_attack` resolver.
- Weapon overlays are exercised under the production `HumanoidTokenView` hand
  anchor, explicit per-weapon shoot/reload/cycle pivots replace zero defaults,
  the physical equipment layer is suppressed while an animated weapon cue is
  active, and weapon playback uses its own normalized duration rather than
  warping against the action-sequence clock.
- The Shove copy now states the hostile co-occupancy rule. New regression smokes
  cover the restored legality matrix, canonical specialized-action resolver,
  production overlay parent/geometry, per-weapon pivots, normalized release
  progress, and single weapon-layer authority.

### 20.2 Verification evidence

- Exact runtime: Godot `4.7.1.stable.official.a13da4feb`.
- Focused legality, AI quote/planner, action-catalog, weapon-contract,
  overlay-geometry, projectile-authority, experience/timeline, audio-identity,
  interaction, terminal, and encounter smokes passed with process exit `0`.
- Full capital-`Tests` sweep: `107/107` executable `SceneTree` scripts passed,
  `FAILED=0`, exit `0`, using isolated `APPDATA` and `LOCALAPPDATA`. The two
  `Control` preview scripts in `Tests/` were not invoked as main scripts because
  they are visual preview surfaces, not self-quitting smoke tests.
- The connected Godot editor launched the current tactical scene through MCP;
  the game helper became live, a hostile token was inspected, and a right-click
  context surface rendered beside the pointer. The live run produced no game
  warnings or errors; the screenshot check showed no obvious duplicate weapon
  layer or gross HUD/layout failure.

### 20.3 Remaining acceptance boundary

The implementation and automated release checks are complete. Physical Windows
pointer input, subjective weapon-frame feel, and subjective audio listening were
not re-run in this remediation pass; the existing live evidence and
`CombatAudioIdentitySmoke` remain separate acceptance claims, not substitutes
for those human checks. The generated local Godot smoke save/log artifacts are
not source and are excluded from the remediation commit.

## 21. Terminal handoff-layer correction

Status: **remediated on 2026-08-14**.

The post-remediation review found one remaining high-severity contradiction:
Incapacitate correctly removed the target from active occupancy and preserved
its location in `incapacitated_entity_ids`, but the frozen actor projection and
the Execute/Strip paths still required `position_of(actor)` to be valid. The
result was that a body could be present in the handoff layer while both of the
actions authored to operate on it were unreachable.

### 21.1 Authority correction

- `CombatBoard` now exposes neutral handoff position/layer lookups independent
  of active occupancy. `mark_body()` also moves an executed incapacitated actor
  from `incapacitated_entity_ids` into `body_entity_ids` without losing the
  original sector.
- `CombatRulesState.from_board()` preserves both active-layer facts and the
  handoff projection (`handoff_sector_index`, `handoff_sector`, and
  `handoff_layer`). Sector facts also retain the three explicit handoff ID
  lists.
- `CombatActionQuoteService` keeps ordinary actor-target validation active, but
  permits only Execute and Strip to resolve an off-board actor through its
  valid handoff sector. Execute accepts a comatose target only when its
  incapacitated handoff fact is present; Strip uses the same projected sector
  for adjacency and item legality.
- `CombatActionController` mirrors the handoff checks defensively. Execute no
  longer rejects the `is_comatose` state created by Incapacitate, and Strip no
  longer queries active-board position for a removed body. The tactical scene
  records the resulting body location for combat-result persistence.

### 21.2 Verification evidence

- `CombatLegalityRegressionSmoke` passes with an off-board incapacitated actor
  projected at `(-1, -1)` and a valid handoff sector; Execute and Strip both
  reach their action-specific legality.
- `CombatTerminalHandoffSmoke` passes the production-shaped sequence
  Incapacitate -> Strip -> Execute, including item transfer and the transition
  from `incapacitated_entity_ids` to `body_entity_ids`.
- `TacticalCombatDeathLifecycleSmoke` and the focused AI, catalog, weapon,
  interaction, and runtime-handoff smokes pass under Godot
  `4.7.1.stable.official.a13da4feb`.
- The full capital-`Tests` sweep passes `107/107` executable `SceneTree`
  scripts with `FAILED=0`; the two `Control` preview scripts remain excluded
  as non-self-quitting visual surfaces.

### 21.3 Acceptance boundary

The correction is headless-verified at the quote, resolver, board-handoff, and
combat-result boundaries. It does not claim that a physical pointer or live
visual body-loot surface was re-tested in this narrow legality correction.

## 22. Documentation reconciliation record

Status: **updated on 2026-08-14** after commit `4d4835d0`.

- Current README/index, combat, architecture, glossary, visual, project-pack,
  phase-pointer, token, and asset documentation now points at the production
  `squad_7x5` contract and the corrected terminal handoff.
- Historical Phase 1/Phase 2 workstreams and changelog entries remain as dated
  provenance, but obsolete class names, test names, and retired combat rules are
  explicitly marked as historical rather than current implementation guidance.
- No gameplay code, test, asset, or resource was changed by this documentation
  reconciliation pass. The generated architecture index is refreshed from the
  current code tree separately.

## 23. Final combat reconciliation checkpoint

Status: **implemented, warning-clean in the combat family, and verified on 2026-08-17**.

### 23.1 Remaining implementation work closed

- `CombatActorState.from_runtime()` now rejects versionless, incompatible, and
  retired-field snapshots instead of silently upgrading them. Empty payloads
  remain valid only as fresh actor state. `CombatBoard`, `TacticalTurnManager`,
  and `EntityFactory` honor the rejection path.
- Failed `Strip` now preflights the destination inventory before removing the
  source item. This preserves equipped slots and nested backpack contents when
  the action is denied, with dedicated regression coverage.
- The full-scene result handoff now has a focused regression asserting that the
  executed body retains its original handoff sector in `body_locations`.
- The persistence smoke creates its ignored test-log directory itself, so a
  clean checkout no longer fails because the harness assumed a local folder.
- CombatCore, combat-facing SystemCore, and ItemCore warnings were resolved
  without changing the tactical authority: explicit integer math, enum casts,
  non-shadowing names, and unused compatibility parameters are now clean in
  the live Godot editor diagnostic filter.
- The local `Tools/Build-HexTileSet.ps1` helper and ignored client names now
  target the approved Godot 4.7.1 source. Remaining Godot 4.6.3 strings are
  dated Phase 1/legacy changelog provenance only, not executable tool choices.

### 23.2 Current verification

- Godot source of truth: `C:\Users\zerat\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe`.
- Branch and revision: `alpha-release-baseline` at `7a9457f8` in
  `C:\Stuffs\arccross_system`.
- Full capital-`Tests` sweep: `109/109` passed, `FAILED=0`, exit `0`.
- Focused schema, failed-Strip, persistence, result-handoff, contract, audio,
  HUD, and runtime-handoff smokes also passed with exit `0`.
- Connected Godot MCP editor launched the tactical scene under 4.7.1; the
  helper became live with no game errors, and the editor reported no warnings
  under the combat-family path filter. Remaining editor warnings are outside
  this reconciliation slice.

### 23.3 Explicit acceptance boundary

The combat code/test reconciliation is complete. Physical Windows pointer
input, subjective weapon-frame feel, and subjective audio listening are not
substituted by headless or MCP evidence and remain release acceptance checks.
No commit or push was made in this pass; all listed worktree changes are
intentional and await the normal Git handoff.
