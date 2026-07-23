# Official Turn-Based Combat Overhaul

Status updated on **July 23, 2026**.

Turn-based combat is ARCCROSS's official/default combat authority. Real-time
combat remains available as an optional setting. Both modes consume the same
canonical entity, anatomy, wound, inventory, ammunition, condition,
malfunction, armor, shield, and persistence data. They do **not** share cadence,
AI scoring, action costs, timing, or mode-specific balance modifiers.

## Runtime contract

- `GameSettingsStore.DEFAULT_COMBAT_MODE` is `turn_based`.
- `GameDirector` routes combat entry to one authority; it never runs both
  authorities in production.
- `CombatTurnManager` treats every accepted action as a transaction. AP can be
  committed immediately, but the turn cannot advance until rules resolution and
  queued presentation complete.
- `CombatAIEvaluator` awaits each action, observes the same transaction barrier,
  limits decisions per turn, reserves defensive AP when appropriate, and treats
  aimed shots as deliberate finishers rather than the universal best button.
- `TurnBasedCombatBalance` owns turn-only presentation cadence and cue markers.
  Realtime `DuelWeaponProfile` resources remain independent.
- `CombatLaneView`, projectile presentation, impact feedback, and the firearm
  card consume the same turn action profile. Actor windup reaches its cue before
  projectile/damage presentation begins.
- `RealtimeWeaponCard` is a shared item presentation component despite its
  historical name; `play_turn_action()` maps turn commands onto the firearm
  sheets and stretches the complete sheet across the authored action duration.
- Firearm atlas regions use integer row/column coordinates. Fractional row
  sampling is forbidden because it slices between frames even on a one-row
  source sheet.
- The combat stage owns a local readability tint. Live inspection found no
  shader, material, briefing shade, or non-white inherited modulation causing
  the dim view; the plains source plate itself is dark.
- `CombatLaneHUD` consumes the shared `HUDAssetLibrary` semantic palette. Its
  top summaries and weapon cards retain visible frames, and the compact command
  deck must not overlap its combat log.
- Viewport-density scaling grows authored HUD content up to `1.45x` above the
  1920x1080 reference while preserving logical card and label coordinates.
- Projectile trails, bullets, and blood sprites unregister and free themselves
  at the end of presentation; the active VFX registry must return to zero.

## Current acceptance evidence

- Godot **4.7.1 Steam** imports and runs the turn-based scene.
- Live MCP evaluation observed an active revolver action with the turn
  transaction locked, `Attack1` playing, and all 10 firearm-sheet frames mapped
  to the same `0.72s` action profile.
- A second live MCP pass observed revolver frame `3/10` and actor `Attack1`
  frame `1` active on the same turn timeline after the atlas-row correction.
- The live stage carried no CanvasItem material and used white inherited
  modulation before the explicit readability tint.
- The lock released only after the projectile/presentation queue drained.
- At the live 2860x1734 viewport the HUD selected `1.45x` density, produced
  182.7px top and 312.12px bottom panels, and kept the command regions separate.
- A live hit created two registered projectile nodes during flight, played one
  impact sound, drained the presentation queue, and returned the VFX registry
  to zero.
- A full AI turn completed three sequential decisions without overlapping
  transactions or leaving the HUD queue busy.
- `Tests/TurnBasedCombatOverhaulSmoke.gd` covers the official default, timing
  profiles, transaction barrier, and turn firearm-card playback.
- `Tests/CombatLaneHUDSmoke.gd` covers high-resolution density and both miss and
  hit VFX cleanup.

## Next combat work

1. Continue presentation polish with weapon-specific cue overrides where source
   sheets place muzzle flash or mechanical contact outside the generic shoot
   cue.
2. Expand enemy weapon-card animation beyond the current player command card
   and actor animation.
3. Run repeated archetype-versus-archetype simulations and tune turn-only action
   costs, reaction reserve policy, and tactic weights **only when the deferred
   AI overhaul resumes**.
4. Audit every July 20 bulk-authored combat item against its focused mechanic
   smoke; the shield rewrite already proved that a prettier catalog entry can
   quietly amputate functional fields.
5. Keep cross-mode tests focused on shared state invariants. Do not require
   identical combat outcomes from different clocks and balance layers.

## Campaign dependency

The Central Core campaign implementation is paused until the complete
categorized asset folder is available to pull from. Its design contract remains
authoritative, but campaign scene/profile implementation must not invent a
temporary asset taxonomy that will be thrown away on import.
