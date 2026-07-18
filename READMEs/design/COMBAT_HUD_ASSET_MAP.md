# Combat HUD Asset Map

The June 29 command-deck work is retained here as an asset inventory, but its
turn menu is retired. The real-time HUD uses restrained panels and progress
rails around `CombatLaneView`; weapon and projectile assets remain reusable.

## Current Runtime Surface

- Main HUD owner: `CombatCore/Realtime/RealtimeDuelHUD.gd`
- Action/camera authority: `RealtimeDuelRuntime` timeline events
- Reusable asset facade: `UI/HUD/HUDAssetLibrary.gd`
- Runtime validation route: Godot MCP `filesystem_manage.reimport`, `script_manage.find_symbols`, `project_run`, and `editor_manage.game_eval`
- Headless fallback: `Godot --headless --editor --quit --path <project_root>`
- Known limitation: focused standalone combat HUD smoke can hit Godot 4.6 `signal 11`; use MCP live probes for visual/runtime confirmation when available.

## Official B&W HUD Pack

Root: `Asset/UI/revampedHUD/B&W_UI_ByAndrox_FREE/HUD/`

| Sheet | Size | Useful Elements | Current Use |
| --- | ---: | --- | --- |
| `menu_transparent.png` | 304x128 | small menu/buttons/key prompts | historical command-deck regions; not active |
| `charge_bars_transparent.png` | 468x230 | segmented meters, compact bars, circular pips | limb/body meter frames, combat log divider |
| `counters_transparent.png` | 208x224 | hearts, shields, warning/skull/droplet/lightning counters | health condition icons |
| `counters.png` | 208x224 | opaque counter variants | reserved for future manual HUD dressing |
| `inventory_transparent.png` | 160x96 | small slot grids and item holders | reserved for later manual asset insertion |
| `selection.png` / `selection_icons.png` | 96x96 | arrows, locks, plus/minus, selection glyphs | candidate for action-group icons and targeting indicators |

### Wired Atlas Regions

| Name | Sheet | Region | Use |
| --- | --- | --- | --- |
| `BW_BUTTON_IDLE_REGION` | `menu_transparent.png` | `Rect2(226, 13, 74, 17)` | idle action/group button frame |
| `BW_BUTTON_HOVER_REGION` | `menu_transparent.png` | `Rect2(226, 39, 74, 17)` | hover/pressed action/group button frame |
| `BW_SEGMENTED_METER_REGION` | `charge_bars_transparent.png` | `Rect2(176, 55, 48, 9)` | limb/body meter frame |
| `BW_COMPACT_METER_REGION` | `charge_bars_transparent.png` | `Rect2(416, 24, 32, 8)` | combat log header divider |
| `BW_ICON_HEART_REGION` | `counters_transparent.png` | `Rect2(146, 18, 12, 12)` | stable/fine condition |
| `BW_ICON_SHIELD_REGION` | `counters_transparent.png` | `Rect2(146, 67, 12, 14)` | warning condition |
| `BW_ICON_DROPLET_REGION` | `counters_transparent.png` | `Rect2(18, 145, 14, 15)` | bleeding condition |
| `BW_ICON_SKULL_REGION` | `counters_transparent.png` | `Rect2(17, 193, 14, 15)` | danger/infected condition |
| `BW_ICON_LIGHTNING_REGION` | `counters_transparent.png` | `Rect2(68, 193, 52, 15)` | guarded/recovery condition |

## Excluded HUD Assets

The combat HUD should not use `Asset/UI/revampedHUD/Condition/`, `POCKET INVENTORY (MAIN)`, or `2D Gore UI` as default HUD chrome. The Condition strips read as flicker in the health section, and the pocket-holder/UI-button art reads like keyboard prompts when stretched into frames. Keep the simple drawn GUI for structure until manual asset insertion is ready.

## Implementation Rules

- Do not stretch tiny atlas regions across full-screen panels.
- Do not use `menu_transparent.png` button/spacebar regions as structural frames.
- Use only `B&W_UI_ByAndrox_FREE` assets for combat HUD icons, button states, and meter ornamentation.
- Keep structure as simple drawn panels and progress bars; do not reintroduce pocket holder frames.
- Use stable counter icons for health conditions. Do not animate Condition strips in the combat HUD.
- Keep combat data readable: official frames decorate and clarify, they do not replace numeric AP, Blood, Stance, ammo, and limb values.
- Use MCP `game_eval` to prove atlas source paths and runtime layout dimensions after UI changes.
- Add smoke assertions for each official element actually wired into the
  real-time HUD; historical command-deck regions do not count as active use.
