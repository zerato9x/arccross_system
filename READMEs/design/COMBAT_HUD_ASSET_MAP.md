# Combat HUD Asset Map

Canonical combat / macro chrome lives under `Asset/UI/HUD/` and is consumed
through `PresentationCore/HUDAssetLibrary.gd`. The old `revampedHUD` packs
(including B&W Androx, Pocket Inventory, Condition strips, and Gore UI) are
retired.

## Current Runtime Surface

- Official HUD owner: `CombatCore/Tactical/TacticalCombatHUD.gd`
- Official scene: `CombatCore/Tactical/TacticalCombatHUD.tscn`
- Snapshot boundary: `CombatCore/Tactical/TacticalCombatSnapshotPresenter.gd`
- Actor privacy projection: `CombatCore/Tactical/CombatActorPresentationProjection.gd`
- Body presentation: `CombatCore/Tactical/CombatBodyTargetView.gd`
- Optional HUD owner: `CombatCore/Realtime/RealtimeDuelHUD.gd`
- Action/camera authority: `CombatActionController`, `TacticalArenaView`, and
  authored presentation timeline events
- Reusable asset facade: `PresentationCore/HUDAssetLibrary.gd`
- Asset root: `Asset/UI/HUD/` (frames, bars, icons, medical, menus, overlays, anim)
- Manifest: `Asset/UI/HUD/hud_asset_manifest.json`
- Builder: `Tools/Build-HUDAssets.py`
- Runtime validation route: Godot MCP filesystem/editor/project tools plus the
  exact Godot 4.7.1 console for sequential smokes
- Headless fallback: `Godot --headless --editor --quit --path <project_root>`

## Official HUD Kit (Asset/UI/HUD)

| Group | Path | Use |
| --- | --- | --- |
| Frames | `frames/panel_*.png`, `frames/button_*.png` | Panel chrome, buttons |
| Bars | `bars/bar_frame*.png`, `bars/bar_fill_*.png` | Meters, combat log divider |
| Status icons | `icons/status/*_32.png` | Macro / inventory / combat status |
| Combat icons | `icons/combat/*_32.png` | Action affordances |
| Medical | `medical/state_*.png`, `medical/limb_*.png` | Condition tokens, limb plates |
| Clock / signal | `anim/clock/*`, `anim/signal/*` | World status widgets |

### Condition mapping (`HUDAssetLibrary.condition_icon`)

| Condition | Texture |
| --- | --- |
| `fine` / `stable` | `medical/state_stable_32.png` |
| `damaged` | `medical/state_damaged_32.png` |
| `danger` | `medical/state_critical_32.png` |
| `healing` | `icons/status/ap_32.png` |
| `infected` | `icons/status/infection_32.png` |
| `precaution_o` | `icons/status/blood_32.png` |
| `precaution_y` | `icons/status/warning_32.png` |

### Meter frames

| Kind | Texture |
| --- | --- |
| Segmented body meters | `bars/bar_frame_96x12.png` |
| Compact / log divider | `bars/bar_frame_thin_96x8.png` |

## Implementation Rules

- Do not reintroduce `Asset/UI/revampedHUD/**` as runtime chrome.
- Do not stretch tiny atlas regions across full-screen panels.
- Keep structure as simple drawn panels and progress bars; decorate with HUD kit textures via `HUDAssetLibrary`.
- Use stable medical/status icons for health conditions. Do not animate Condition strips in the combat HUD.
- Keep self/friendly data readable: official frames decorate and clarify, they
  do not replace exact player AP, Blood, Stance, ammo, or limb values.
- Treat neutral/hostile cards as knowledge projections: qualitative condition,
  observable wounds, intent, relation, posture, and weapon bands only.
- Use MCP live UI inspection/screenshots to prove runtime node paths and layout
  dimensions after UI changes; headless imports do not prove visual acceptance.
- Add smoke assertions for each official element actually wired into the
  turn-based HUD; keep separate optional realtime coverage.
- Main-menu parallax packs live under `Asset/UI/Event_bg/` via `MenuParallaxCatalog`; they are menu-only, not event/collision art.
