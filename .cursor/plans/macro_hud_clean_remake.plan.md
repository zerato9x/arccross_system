---
name: Macro HUD Clean Remake
overview: "Scrap the layered-on-old-system approach. Delete legacy HUD DNA, rebuild four independent corner panels from the macromap target layout using revamped UI.png assets only. Preview → click → 32%×50% expand. World status stays compact. Camera recenters in remaining viewport."
todos:
  - id: remake-00-delete-legacy
    content: "Delete WorldHUD.tscn, revamped_HUD.tscn, MacroStatusPanel DetailedView subtree, and any orphan references"
    status: pending
  - id: remake-01-atlas-contract
    content: "Finalize RevampedHUDAtlas as single styling source — frames, bars, buttons, slots from UI.png; document all regions"
    status: pending
  - id: remake-02-shell-scaffold
    content: "Rebuild MacroHudShell with four corner anchors only — no side pillars, no floating MED/INV/MENU bar"
    status: pending
  - id: remake-03-corner-host
    content: "Rewrite MacroCornerPanel — fixed preview chip + sibling expand overlay at exactly 32%×50%"
    status: pending
  - id: remake-04-health
    content: "Health top-left preview + MedicalMonitor expand with Condition icons and emergency flash"
    status: pending
  - id: remake-05-inventory
    content: "Inventory bottom-left preview + InventoryUI expand restyled to UI.png"
    status: pending
  - id: remake-06-hex
    content: "Hex top-right preview + MacroExplorationWindow docked expand"
    status: pending
  - id: remake-07-world-status
    content: "World status bottom-right — PocketClock + 6 time squares + calendar; never expands"
    status: pending
  - id: remake-08-cross-panel
    content: "Drag/drop and RMB context menu between health, inventory, hex panels"
    status: pending
  - id: remake-09-camera
    content: "Implement MacroCamera.set_viewport_insets — center player in playable rect when panels open"
    status: pending
  - id: remake-10-verify
    content: "Visual pass vs macromap_mockup — must NOT show side pillars or top-center sky widget"
    status: pending
isProject: false
---

# Macro HUD — Clean Remake Plan

## What went wrong (and why you're right)

Previous work **patched** the old macro HUD instead of replacing it. Evidence:

| Your spec | Current reality |
|-----------|-----------------|
| Four **corner** panels, separated | `macromap_mockup_png.png` still shows **full-height side pillars** (medical monitor left, stat tower right), top-center sky dial, INV/MED/MENU/SET strip |
| All chrome from **UI.png** revamped atlas | Mixed `HUDAssetLibrary` (old dark pixel) + `RevampedHUDAtlas` (widget-only rule) |
| Expand = **32% width × 50% height** | Inventory uses **36% × 48%**; expand **resizes the whole corner node** instead of overlay |
| World status = **small bottom-right only** | Partially done, but clock/time still duplicated in `MacroStatusPanel` header |
| Camera centers player in **remaining space** | `MacroCamera.set_viewport_insets()` is a **no-op stub** |
| Clean separation, preview → full view | `MacroStatusPanel` still has internal `DetailedView` + nested `MedicalMonitor` (second expand path) |
| Old elements gone | `WorldHUD.tscn` still on disk with inline status panel + root `MedicalMonitor` |

**Verdict:** The shell name changed (`MacroHudShell`) but the **visual language and architecture** still trace back to the pillar HUD. That is not your plan.

---

## Target layout (non-negotiable)

```
┌─────────────────────────────────────────────────────────────┐
│ [HEALTH preview]              [HEX preview]                 │
│                                                             │
│                    PLAYABLE MAP AREA                        │
│              (camera centers here when panels open)         │
│                                                             │
│ [INVENTORY preview]           [WORLD STATUS — compact only] │
└─────────────────────────────────────────────────────────────┘

Click preview or action button → expand overlay at same corner:
  width  = 32% of viewport
  height = 50% of viewport
  max 3 expanded at once (FIFO collapse oldest)
```

**NOT allowed:** side pillars, top-center widgets, floating button strips, full-screen medical frame outside a corner.

Reference mockup to **avoid**: `Asset/UI/revampedHUD/macromap_mockup_png.png` (old design).

---

## Design rules

1. **Single asset source for chrome:** `UI Assets pack_v.1_st/UI.png` via `RevampedHUDAtlas` — frames, bars, buttons, inventory slots. Retire `HUDAssetLibrary` from all macro HUD scenes (settings modal can migrate last).
2. **Scene-first:** Every preview is a `.tscn` edited in Godot. No `_build_preview_ui()` spawning nodes in `_ready()`.
3. **Two-layer corner model:**
   - `PreviewChip` — fixed size, always at corner anchor, never grows.
   - `ExpandOverlay` — sibling `Control`, hidden by default, sized to 32%×50%, anchored to same corner.
4. **One expand owner:** Only `MacroCornerPanel` (or thin subclass) toggles preview/expand. Child scenes emit signals; they never self-expand.
5. **World status never expands.** Excluded from inset math except as a fixed bottom-right occlusion rect (~236×118).
6. **Cross-panel interaction:** drag/drop + RMB context menu on health ↔ inventory ↔ hex (treatment items, gear, POI tools).

---

## Asset mapping

### UI.png (`RevampedHUDAtlas` — extend, document, use everywhere)

| Element | Atlas region (current) | Used on |
|---------|------------------------|---------|
| Panel frame (9-slice) | 16,16 32×32 corners + 48,48 fill | All four preview chips + expand overlays |
| Segmented progress bar | 769,18 46×12 | Health preview vitals |
| Plain progress bar | 866,19 44×10 | Secondary stats |
| Heart / shield / lightning / droplet icons | 145–257, 17–18 | Vital row icons |
| Inventory slot | 1056,16 32×32 | Inventory preview gear strip |
| Button idle/hover | 288,16 / 352,17 | BODY SCAN, OPEN INVENTORY, EXPLORE, SET |

**Action:** Run atlas measurement pass; add missing regions (vertical bars, tab headers, scroll handles) to `RevampedHUDAtlas` constants. Grep and remove `HUDAssetLibrary.apply_*` from `UI/HUD/Macro/**`.

### Clock (`POCKET INVENTORY (MAIN)/Sprites/Content/Clock/`)

| Asset | Role |
|-------|------|
| `0.png` | Flip-clock frame (`PocketClockDisplay` — already wired) |
| `Clock Digits/{slot}/{digit}.png` | Animated HHMM digits |

### Time of day (`UI assets pack 2/Time & weather.png`)

**Only the 6 square TIME icons** (2×3 grid, top-right of sheet):

| Index | Phase | Grid cell |
|-------|-------|-----------|
| 0 | dawn | col 0, row 0 |
| 1 | morning | col 1, row 0 |
| 2 | midday | col 0, row 1 |
| 3 | afternoon | col 1, row 1 |
| 4 | dusk | col 0, row 2 |
| 5 | night | col 1, row 2 |

Already mapped in `RevampedHUDAtlas.TIME_SQUARE_*` — verify cell size against source PNG.

### Condition HUD (`Asset/UI/revampedHUD/Condition/`)

| File | Use |
|------|-----|
| `ConditionFine.png` | Stable bio-signal |
| `ConditionDanger.png` | Bleeding / critical |
| `ConditionPrecautionO.png` | Hunger / thirst warnings |
| `ConditionPrecautionY.png` | Fatigue / stance |
| `ConditionInfected.png` | Infection |
| `ConditionHealing.png` | Active treatment |

Preview: flashing condition icon on emergencies.  
Expand (`MedicalMonitor`): limb map + wound markers using condition art.

---

## Per-corner specification

### 1. Health — Top Left

**Preview chip (~398×220)**
- Top: location label (hex coords / sector name)
- Middle: 4–6 vital `ProgressBar` rows (blood, stance, hunger, thirst, fatigue, temp) with UI.png bars + icons
- Condition icon from `Condition/` — **flashes** when `emergencies` array non-empty; red tint pulses over entire preview chip
- Bottom: `BODY SCAN` button only (no INV/SET here — those live in inventory preview or world status SET)

**Expand (32%×50%, top-left anchored)**
- `MedicalMonitor` full limb health + wounds
- Drag health items from inventory onto limbs (`LimbDropTarget`)
- RMB on limb → treatment context menu
- Close: X button or Esc

**Delete from health path:** `MacroStatusPanel.DetailedView`, internal `toggle_body_scan()`, hidden time row, INV/SET buttons when in corner mode.

### 2. Inventory — Bottom Left

**Preview chip (~320×128)**
- Equipped gear icons (HEAD/PACK/ARMOR/HAND/OFF) in UI.png slots
- Capacity label
- `OPEN INVENTORY` button

**Expand (32%×50%, bottom-left anchored)**
- Existing `InventoryUI` paperdoll + backpack — **restyle shell** to UI.png frames (no double `PanelContainer` wrap)
- Drag items to health panel limbs when health expand is open
- RMB → use/equip/drop context menu

**Fix:** `expand_width_ratio` / `expand_height_ratio` → **0.32 / 0.50** (currently 0.36 / 0.48).

### 3. Hex Exploration — Top Right

**Preview chip (~326×360)**
- Keep `MacroHexPreviewPanel` content: terrain, structures, hazards, POI thumb, EXPLORE/TRAVEL
- Remove baked top-right offsets inside preview scene — positioning owned by shell only

**Expand (32%×50%, top-right anchored)**
- `MacroExplorationWindow` docked into `ExpandOverlay`
- Keep current POI session flow via `MacroGameManager.dock_hex_session()`

### 4. World Status — Bottom Right

**Always compact (~236×118) — NO expand**

Layout (left → right):
1. `PocketClockDisplay` (HHMM flip digits)
2. Time-of-day square icon (6-square TIME set only)
3. `DAY ###` + `MON YYYY` calendar text
4. Small `SET` → settings modal

Remove duplicate time from health preview entirely.

---

## Architecture (after remake)

```
MacroHudShell (MacroHudController)
├── PreviewLayer
│   ├── HealthPreviewChip      [TL, 398×220]
│   ├── InventoryPreviewChip   [BL, 320×128]
│   ├── HexPreviewChip         [TR, 326×360]
│   └── WorldStatusChip        [BR, 236×118, never expands]
├── ExpandLayer (siblings, not children of preview)
│   ├── HealthExpandOverlay    [TL, 32%×50%]
│   ├── InventoryExpandOverlay [BL, 32%×50%]
│   └── HexExpandOverlay       [TR, 32%×50%]
├── CrossPanelDragLayer        (drop targets spanning panels)
└── SettingsModal / SaveLoad   (centered, unchanged behavior)
```

`MacroCornerPanel` becomes a thin coordinator:
- Owns `PreviewChip` + `ExpandOverlay` node refs
- `expand()` / `collapse()` toggles overlay visibility only — **preview chip stays put**
- `get_occupied_rect()` returns expand overlay global rect

`MacroHudLayoutManager`:
- Track up to 3 expanded overlays
- `compute_viewport_insets()` → left/top/right/bottom pixel margins
- Include world status chip as permanent `bottom` + `right` inset (not expandable)

`MacroCamera.set_viewport_insets(insets)`:
- Define playable `Rect2` = viewport minus insets
- Center camera on player within playable rect
- Recompute on panel expand/collapse and viewport resize

---

## DELETE list (do this first)

| Item | Reason |
|------|--------|
| `UI/HUD/WorldHUD.tscn` | Orphan pillar HUD |
| `UI/HUD/revamped_HUD.tscn` | Empty shell |
| `UI/HUD/PocketInventoryTheme.tres` | Unused |
| `MacroStatusPanel.tscn` → `DetailedView` + nested `MedicalMonitor` | Duplicate expand path |
| `MacroStatusPanel.gd` → `Mode.DETAILED`, `toggle_body_scan()`, `_set_mode()` | Internal expand logic |
| `MacroStatusPanel` time header row (`TimeIcon`, `TimeLabel`) | Clock lives on world status only |
| `MacroStatusPanel` INV/SET buttons in corner context | Wrong corner ownership |
| `MacroHexPreviewPanel.tscn` baked position offsets | Shell owns placement |
| Duplicate `KEY_I`/`KEY_TAB` in `MacroGameManager` | Single handler in controller |
| Any `HUDAssetLibrary.apply_*` under `UI/HUD/Macro/**` | Replaced by UI.png atlas |

---

## KEEP (behavior + data, re-skin + re-host)

| Item | Role after remake |
|------|-------------------|
| `MacroHudController.gd` | Orchestration, hotkeys, snapshot fan-out |
| `MacroHudLayoutManager.gd` | Expand limit + inset math (fix world-status occlusion) |
| `MacroSnapshotBuilder.gd` / `MacroGameManager` wiring | Data pipeline |
| `MedicalMonitor` | Health expand content |
| `InventoryUI` + embed API | Inventory expand content |
| `MacroExplorationWindow` + dock API | Hex expand content |
| `MacroHexPreviewPanel` | Hex preview content |
| `MacroInventoryPreview` | Inventory preview content |
| `PocketClockDisplay` | World status clock |
| `LimbDropTarget` | Medical drag-drop |
| `RevampedHUDAtlas.gd` | **Primary** styling API (promote `apply_revamped_panel` to standard) |

---

## Implementation phases

### Phase 0 — Stop the bleeding (1–2 hours)
- Delete files in DELETE list
- Grep: zero references to `WorldHUD`, `DetailedView`, `toggle_body_scan`
- Fix inventory expand ratios to 0.32 / 0.50

### Phase 1 — Corner host rewrite (half day)
- Refactor `MacroCornerPanel.tscn`: split `PreviewChip` + `ExpandOverlay` siblings
- Preview chip never changes size on expand
- Update `MacroHudShell.tscn` anchors (use table below)
- Update `MacroHudLayoutSmoke.gd` for new node paths

### Phase 2 — Asset unification (half day)
- Extend `RevampedHUDAtlas` with full UI.png region table
- Migrate all macro HUD scenes from `HUDAssetLibrary` → `RevampedHUDAtlas`
- Remove widget-only restriction comment — UI.png **is** the macro HUD art pack

### Phase 3 — Four corners content (1 day)
- **Health:** New `MacroHealthPreview.tscn` (or slim `MacroStatusPanel` compact-only) + `MedicalMonitor` in expand overlay
- **Inventory:** Restyle `InventoryUI` embedded shell
- **Hex:** Neutralize preview offsets, dock exploration window
- **World status:** Verify clock + 6 squares + calendar layout

### Phase 4 — Cross-panel interaction (half day)
- Shared `MacroHudDragBroker` or extend existing drop targets
- RMB `PopupMenu` on inventory items → send to focused limb / hex action
- Health expand + inventory expand open → enable cross-drop

### Phase 5 — Camera + polish (half day)
- Implement `MacroCamera.set_viewport_insets()`
- Emergency flash tween on health preview chip
- Esc collapses all expands
- HUD scale slider applies to `PreviewLayer` + `ExpandLayer` together

### Phase 6 — Verification
Manual checklist — **fail if any item matches old mockup pillars:**

```
[ ] No full-height left/right panels
[ ] No top-center sky widget
[ ] No INV/MED/MENU floating strip (actions live inside corner previews)
[ ] Four corners match authored sizes
[ ] Each expand is exactly 32%×50% at its corner
[ ] World status stays compact; clock digits animate; time square changes with hour
[ ] BODY SCAN opens limb monitor in top-left expand, not a side pillar
[ ] OPEN INVENTORY opens paperdoll in bottom-left expand
[ ] EXPLORE opens hex window in top-right expand
[ ] With 3 panels open, map camera centers player in middle gap
[ ] All frames/bars/buttons use UI.png — no old dark pixel chrome
```

---

## Anchor reference (author in `MacroHudShell.tscn`)

| Node | Anchor | Offsets (L,T,R,B) | Size |
|------|--------|-------------------|------|
| Health preview | top-left | 14, 14, 412, 234 | 398×220 |
| Inventory preview | bottom-left | 14, −142, 334, −14 | 320×128 |
| Hex preview | top-right | −340, 14, −14, 374 | 326×360 |
| World status | bottom-right | −250, −132, −14, −14 | 236×118 |
| Health expand | top-left | 14, 14, 14+32%vw, 14+50%vh | overlay |
| Inventory expand | bottom-left | 14, −50%vh, 14+32%vw, −14 | overlay |
| Hex expand | top-right | −32%vw, 14, −14, 14+50%vh | overlay |

---

## What the previous "repair plan" got wrong

The `macro_hud_corner_repair.plan.md` said **keep old `HUDAssetLibrary` frames**. Your spec says **UI.png for everything**. That compromise preserved the old visual language and is why it still looks like fresh paint on the pillar HUD.

This plan **supersedes** the repair plan.

---

## Success criteria

The remake is done when a screenshot of macro world mode:

1. Shows **only four corner chips** + map in the center (like your written spec, **not** like `macromap_mockup_png.png`).
2. Uses **revamped UI.png** chrome throughout.
3. Clock + 6 time squares + calendar work on bottom-right.
4. Expand/collapse, POI dock, inventory embed, limb treatment, and camera insets all work.
5. Zero legacy files or dual expand paths remain in the macro HUD path.
