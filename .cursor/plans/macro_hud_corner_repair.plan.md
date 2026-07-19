---
name: Macro HUD Corner Repair
overview: "STALE — do not execute as written. Contradicts macro_hud_clean_remake; references deleted MacroStatusPanel/MedicalMonitor. FieldHealthHUD and MacroHudShell are live. Rewrite against current shell before any chrome work."
todos:
  - id: repair-01-freeze-design
    content: "Lock visual rule: HUDAssetLibrary frames outside, RevampedHUDAtlas widgets inside only"
    status: cancelled
  - id: repair-02-shell-layout
    content: "Rebuild MacroHudShell.tscn with editor-placed anchors matching old offsets (not runtime-only math)"
    status: cancelled
  - id: repair-03-health-corner
    content: "Replace MacroHealthCornerPanel preview with MacroStatusPanel.tscn instance + expand slot for MedicalMonitor"
    status: cancelled
  - id: repair-04-hex-corner
    content: "Replace MacroHexCornerPanel preview with MacroHexPreviewPanel.tscn + dock MacroExplorationWindow on expand"
    status: cancelled
  - id: repair-05-inventory-corner
    content: "Fix inventory: compact preview strip; expanded panel hosts InventoryUI without double-framing"
    status: cancelled
  - id: repair-06-world-status
    content: "World status: old frame + PocketClockDisplay + time-of-day icon; remove script/scene offset conflict"
    status: cancelled
  - id: repair-07-atlas-cleanup
    content: "RevampedHUDAtlas: remove apply_revamped_panel from runtime paths; document widget-only API"
    status: cancelled
  - id: repair-08-wiring
    content: "Rewire MacroHudController + MacroGameManager; delete dead corner programmatic UI"
    status: cancelled
  - id: repair-09-camera-insets
    content: "Validate viewport inset math against real panel rects at 2548×1368 and 1920×1080"
    status: cancelled
  - id: repair-10-tests
    content: "Add visual smoke checklist + MacroHudLayoutSmoke fixes; run via game_director boot"
    status: cancelled
isProject: false
---

# Macro HUD Corner Repair Plan (STALE)

> **July 19, 2026:** Historical only. Health corner no longer uses
> `MacroStatusPanel` / `MedicalMonitor`. Do not resume these todos; write a
> fresh plan against `MacroHudShell` + `FieldHealthHUD` if chrome work resumes.

## Problem summary

The corner HUD remake is visually and structurally broken because it **replaced working editor-authored panels with runtime-built corner shells** and **used revamped atlas textures as full panel backgrounds**. The result:

- Huge stretched `UI.png` grid blocks (especially bottom-left inventory expand)
- Wrong corner positions vs the old HUD
- Lost content from `MacroStatusPanel` (location, time, fatigue, temperature, INV/SET)
- Duplicate parallel implementations (`MacroStatusPanel` vs `MacroHealthCornerPanel`)
- Editor scene desync (in-memory `MacroHudShell` diverged from disk)
- World status panel fights between script offsets and `.tscn` offsets

**User intent (correct):** Keep the **old dark pixel frames** (`HUDAssetLibrary`). Add **new inner elements only** — segmented bars, stat icons, flip-clock digits, time-of-day squares (`RevampedHUDAtlas`).

---

## Root causes

| Issue | What went wrong | Symptom |
|-------|-----------------|---------|
| Frame misuse | `RevampedHUDAtlas.apply_revamped_panel()` on `PanelContainer` | Blue/beige atlas grid stretched across screen |
| Wrong base | New `MacroCornerPanel` builds UI in `_build_preview_ui()` at runtime | Layout not tunable in editor; sizes drift |
| Ignored proven scenes | `MacroStatusPanel.tscn` / `MacroHexPreviewPanel.tscn` abandoned | Regressed layout and missing fields |
| Expand model | 32%×50% expand on same `PanelContainer` that holds preview chrome | Expanded inventory/health panels look like broken wallpaper |
| Split responsibilities | Health lost world time/location; world status reimplemented separately | Duplicate clocks, wrong corner ownership |
| Offset sources | `MacroCornerPanel._set_corner_anchors()` + per-script offsets + `.tscn` anchors | Panels float at inconsistent margins |
| Inventory embed | `InventoryUI` reparented into `%ExpandedRoot` inside framed corner | Double panel + wrong scale |

---

## Design rules (non-negotiable)

1. **Outer chrome** → `HUDAssetLibrary.apply_panel()` / `apply_button()` / `apply_label()` (same as pre-remake HUD).
2. **Inner widgets only** → `RevampedHUDAtlas` for:
   - `apply_revamped_progress_bar()` on existing `ProgressBar` nodes
   - `stat_icon()`, `clock_digit()`, `time_of_day_icon()`, `emergency_condition_icon()`
   - **Never** `apply_revamped_panel()` on corner shells or expanded hosts.
3. **Scene-first** → Preview UI lives in `.tscn` files edited in Godot, not spawned in `_ready()`.
4. **Expand = content swap** → Preview frame stays fixed size; expanded view is a **sibling overlay** or **reparented content layer**, not the same panel growing with atlas fill.
5. **Single source of truth for positions** → Anchor presets + offsets authored in `MacroHudShell.tscn` (see reference table below).

---

## Target architecture

```
MacroHudShell (MacroHudController)
├── MacroHealthCorner          [TOP-LEFT]
│   ├── PreviewHost  → instance MacroStatusPanel.tscn (compact only)
│   └── ExpandHost   → MedicalMonitor.tscn (hidden until BODY SCAN)
├── MacroInventoryCorner       [BOTTOM-LEFT]
│   ├── PreviewHost  → compact gear strip (new small .tscn, old frame)
│   └── ExpandHost   → InventoryUI embedded (no extra PanelContainer wrap)
├── MacroHexCorner             [TOP-RIGHT]
│   ├── PreviewHost  → instance MacroHexPreviewPanel.tscn
│   └── ExpandHost   → MacroExplorationWindow panel docked
├── MacroWorldStatusPanel      [BOTTOM-RIGHT, always compact]
│   └── old frame + PocketClockDisplay + day icon + calendar text + SET
└── MacroHudLayoutManager → viewport_insets → MacroCamera
```

**Key change:** `MacroCornerPanel` becomes a thin **layout coordinator** (preview/expand visibility, insets, signals). It does **not** build vitals/labels in code.

---

## Position reference (restore these)

Values from the last working HUD scenes. Author these in `MacroHudShell.tscn` (not only in script).

| Panel | Anchor | offset_left | offset_top | offset_right | offset_bottom | Size |
|-------|--------|-------------|------------|--------------|---------------|------|
| Health / Status | top-left | 14 | 14 | 412 | 234 | 398×220 |
| Hex preview | top-right | −340 | 14 | −14 | 374 | 326×360 |
| Inventory preview | bottom-left | 14 | −142 | 334 | −14 | 320×128 |
| World status | bottom-right | −250 | −132 | −14 | −14 | 236×118 |
| Health expanded | top-left | 14 | 14 | 32% vw | 50% vh | overlay |
| Inventory expanded | bottom-left | 14 | −50% vh | 32% vw | −14 | overlay |
| Hex expanded | top-right | −32% vw | 14 | −14 | 50% vh | overlay |

Use `%` ratios only for **expand hosts**, never for preview frames.

---

## Repair phases

### Phase 1 — Freeze styling contract

**Files:** `PresentationCore/RevampedHUDAtlas.gd`, `UI/HUD/Macro/MacroCornerPanel.gd`

- [ ] Add header comment: widget-only API; panel chrome forbidden.
- [ ] Grep project for `apply_revamped_panel` — remove from all HUD shells (keep settings panel on `HUDAssetLibrary`).
- [ ] Grep for `apply_revamped_button` on corner previews — revert to `HUDAssetLibrary.apply_button`.
- [ ] Confirm `panel_stylebox()` in RevampedHUDAtlas is **not** called at runtime (or delete if unused).

**Acceptance:** No corner `PanelContainer` uses `StyleBoxTexture` from `UI.png`.

---

### Phase 2 — Rebuild shell in editor (MCP `scene_open` + `node_create`)

**File:** `UI/HUD/Macro/MacroHudShell.tscn`

- [ ] Open shell in Godot; verify four corner nodes exist with `unique_name_in_owner`.
- [ ] Set explicit anchors/offsets per table above (do not rely on `_set_corner_anchors()` alone).
- [ ] Each corner node structure:
  ```
  MacroXCorner (Control or PanelContainer)
  ├── PreviewHost (Control, full rect of preview size)
  └── ExpandHost (Control, hidden, expand rect)
  ```
- [ ] Save scene; reopen `main_world.tscn` and confirm instance picks up changes.

**Acceptance:** Scene tree in editor matches disk; no orphan `MacroStatusPanel` / `MacroHexPreviewPanel` duplicates inside shell.

---

### Phase 3 — Health corner (reuse MacroStatusPanel)

**Files:**
- `UI/HUD/Macro/MacroHealthCornerPanel.gd` (rewrite)
- `UI/HUD/Macro/MacroStatusPanel.gd` (extend for corner use)
- `UI/HUD/Macro/MacroStatusPanel.tscn`

**Steps:**

1. Instance `MacroStatusPanel.tscn` under `PreviewHost`.
2. Wire `BODY SCAN` → expand `ExpandHost` + `MedicalMonitor.open_monitor()`.
3. Wire `INV` → `MacroHudController.toggle_inventory_panel()` (not legacy fullscreen).
4. Wire `SET` → settings (move from world status if needed).
5. Swap **only** progress bar theme on existing `%BloodBar`, `%HungerBar`, etc.:
   ```gdscript
   RevampedHUDAtlas.apply_revamped_progress_bar(bar, "blood")
   ```
6. Optionally swap `%BloodIcon` etc. textures to `RevampedHUDAtlas.stat_icon()`.
7. Emergency flash: tint `PreviewHost` overlay `ColorRect`, not the outer atlas frame.

**Delete:** Programmatic `_build_preview_ui()` in `MacroHealthCornerPanel.gd`.

**Acceptance:** Top-left matches old status panel layout + revamped bars/icons; expand opens body scan at 32%×50% with old frame.

---

### Phase 4 — Hex corner (reuse MacroHexPreviewPanel)

**Files:**
- `UI/HUD/Macro/MacroHexCornerPanel.gd`
- `UI/HUD/Macro/MacroHexPreviewPanel.tscn`

1. Instance `MacroHexPreviewPanel.tscn` in `PreviewHost` (remove runtime-built labels).
2. Connect `expand_requested` / `travel_requested` to existing `MacroHudController` signals.
3. On expand: show `ExpandHost`, call `exploration_window.dock_into(expand_host)`.
4. On collapse: `exploration_window.undock()`, hide host.
5. Keep `HUDAssetLibrary` on hex preview (already correct in `MacroHexPreviewPanel.gd`).

**Acceptance:** Top-right preview identical to pre-remake; POI opens inside expand host, not floating layer.

---

### Phase 5 — Inventory corner

**Files:**
- `UI/HUD/Macro/MacroInventoryCornerPanel.gd`
- `UI/Inventory/InventoryUI.gd`
- New: `UI/HUD/Macro/MacroInventoryPreview.tscn` (small, editor-authored)

**Problems to fix:**
- Expanded panel shows atlas grid → caused by parent `MacroCornerPanel` frame + full-size embed.
- `InventoryUI` already uses `HUDAssetLibrary` — do not wrap it in another framed panel.

**Steps:**

1. Create `MacroInventoryPreview.tscn`: old frame, gear icon row, capacity label, `OPEN INVENTORY` button.
2. PreviewHost instances that scene only.
3. ExpandHost: **no** `PanelContainer` parent; `InventoryUI.open_embedded_panel(expand_host)` fills host rect.
4. Collapse: `inventory_ui.close_panel(false)` and hide ExpandHost.
5. Cap expand size: 32% width × 50% height, bottom-left anchored.

**Acceptance:** Preview is a small bottom-left strip; expand shows paperdoll inventory with single dark frame (inventory shell only).

---

### Phase 6 — World status corner

**Files:**
- `UI/HUD/Macro/MacroWorldStatusPanel.gd`
- `UI/HUD/Macro/MacroWorldStatusPanel.tscn` (create — stop building in code)

1. Convert to `.tscn` with `PanelContainer` + `HUDAssetLibrary` frame.
2. Children: `PocketClockDisplay`, time-of-day `TextureRect`, day/calendar labels, `SET` button.
3. Remove duplicate time display from `MacroStatusPanel` header **or** keep location on status and time only on world status (pick one — recommend: location on status, clock on bottom-right).
4. Delete offset logic from `_ready()`; use only `.tscn` anchors (−250, −132, −14, −14).
5. Labels/buttons: `HUDAssetLibrary`; clock/icons: `RevampedHUDAtlas`.

**Acceptance:** Bottom-right compact clock card; no offset fighting between script and scene.

---

### Phase 7 — MacroCornerPanel refactor

**File:** `UI/HUD/Macro/MacroCornerPanel.gd`

Slim down to:

- `preview_host` / `expand_host` exports or `%` nodes
- `expand()` / `collapse()` toggles visibility + size of expand host only
- `get_occupied_rect()` returns expand host global rect when expanded
- `HUDAssetLibrary.apply_panel()` **only if** corner root is a visible frame around preview (optional — prefer frame on child scenes)

Remove:

- `_build_preview_ui()` hooks in subclasses
- `RevampedHUDAtlas` imports from base class

---

### Phase 8 — Controller + game wiring

**Files:**
- `UI/HUD/Macro/MacroHudController.gd`
- `WorldCore/MacroGameManager.gd`
- `WorldCore/MacroSnapshotBuilder.gd`

- [ ] `refresh()` still fans snapshot to all four corners.
- [ ] Hotkeys: `M` health, `I`/`Tab` inventory, `Esc` collapse all.
- [ ] `open_inventory()` toggles inventory corner only.
- [ ] `dock_hex_session()` expands hex corner.
- [ ] Remove unused signals (`inventory_requested` on controller if dead).
- [ ] Delete or archive: dead programmatic UI helpers if fully replaced by `.tscn` instances.

---

### Phase 9 — Camera insets

**File:** `WorldCore/camera_2d.gd`

- [ ] Log inset rect when each panel expands (debug one line).
- [ ] Fix `MacroHudLayoutManager.compute_viewport_insets()` if bottom-right world status overlaps expand rect (world status is **not** expandable — exclude from insets).
- [ ] Test at 2548×1368 and 1920×1080: player stays centered in playable area.

---

### Phase 10 — Cleanup + tests

**Remove or deprecate after parity:**

| File | Action |
|------|--------|
| `UI/HUD/Macro/MacroHealthCornerPanel.gd` runtime UI | Replace with scene instance approach |
| Duplicate logic in `MacroHexCornerPanel.gd` | Delegate to `MacroHexPreviewPanel` |
| `UI/HUD/WorldHUD.*` | Already deleted — confirm no references |
| `Tools/measure_ui_atlas.py` | Keep for artist tuning |

**Tests:**

- [ ] `Tests/MacroHudLayoutSmoke.gd` — assert four `%` nodes, expand width ≈ 32% vp, insets non-zero.
- [ ] `Tests/MacroWorldExplorationSmoke.gd` — hex panel expanded on POI.
- [ ] `Tests/GameTimeRulesCalendarSmoke.gd` — calendar snapshot.
- [ ] Manual visual checklist (play macro world):

```
[ ] Top-left: old dark frame, 4–6 vitals with segmented bars, BODY SCAN / INV / SET
[ ] Top-right: hex preview at correct margin, EXPLORE opens docked window
[ ] Bottom-left: small preview; expand shows inventory paperdoll (no atlas grid)
[ ] Bottom-right: flip clock + day icon + calendar; no duplicate DAY line top-left
[ ] Esc collapses expanded panels; camera recenters
```

---

## What NOT to do

- Do **not** use `UI.png` `StyleBoxTexture` as a resizable panel background.
- Do **not** build corner preview UI entirely in `_ready()` with `VBoxContainer.new()`.
- Do **not** fork `MacroStatusPanel` layout into a second health-only panel.
- Do **not** edit `MacroHudShell` only on disk without opening/saving in Godot (causes desync).
- Do **not** embed `InventoryUI` inside a framed `MacroCornerPanel` **and** keep its own `_shell` panel without clearing parent styling.

---

## Suggested implementation order

1. Phase 1 (styling contract) — quick, stops the bleeding  
2. Phase 3 + 4 (health + hex) — highest visual impact, reuse existing scenes  
3. Phase 2 (shell anchors) — lock positions in editor  
4. Phase 5 + 6 (inventory + world status)  
5. Phase 7–9 (refactor, wiring, camera)  
6. Phase 10 (cleanup + tests)

Estimated effort: **1 focused session** for phases 1–4 (playable parity), **1 session** for 5–10 (polish + tests).

---

## MCP execution notes

When implementing, always:

1. `session_activate` → `project_manage(op="stop")` before scene edits  
2. `scene_open` → `node_create` / `node_set_property` → `scene_save`  
3. `script_patch` for `.gd` changes; verify with `logs_read(source="editor")`  
4. `project_run(mode="custom", scene="res://SystemCore/game_director.tscn")` or boot through main menu for visual check  
5. `game_manage(op="get_ui_elements")` after reaching macro world

---

## Success criteria

The repair is done when:

1. All four corners use **old `HUDAssetLibrary` frames** at the **documented offsets**.  
2. Revamped assets appear **only** as bars, icons, clock digits, and weather squares.  
3. No stretched atlas grid appears at any panel state.  
4. Expand/collapse, POI dock, inventory embed, and camera insets work without regression.  
5. `MacroStatusPanel` and `MacroHexPreviewPanel` are the preview source of truth again.
