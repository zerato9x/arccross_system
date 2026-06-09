# ARCCROSS Combat UI Design Specifications

This document outlines the visual layout, game feel feedback, control mechanics, and presentation rules for the **Tactical Combat UI Overhaul** aligned during our design interview.

---

## 1. Grid Presentation: Monospace Receding Corridor
- **Visual Style:** Rather than a flat horizontal line, the 12-slot lane is rendered as a **monospace pseudo-3D receding wireframe corridor** (reminiscent of vector vector-graphics wireframe designs).
- **Receding Perspective:** The distant slots (0 and 11) are clustered tightly near the top center, with horizontal grid lines receding and widening down toward the active foreground slots in a trapezoidal projection.
- **Markers:** 
  * `[P]` (Player) is highlighted in bright cyan.
  * `[E]` (Enemy) is highlighted in tomato red.
  * Background terrain features are shown with custom monospace icons (e.g., `░` for Mud, `▲` for Cover).

---

## 2. Melee Lock Presentation: Front-View Duel Overlay
- **Trigger:** Initiated when both the Player and the Enemy occupy the exact same lane slot (Melee Lock).
- **Visual Transition:** The perspective corridor is temporarily hidden from the center HUD.
- **Visual Presentation:** A **holographic front-view wireframe overlay** displays the two combatants locked in close-quarters struggle/grapple in the mud.
- **Lock Resolution:** When the lock is broken (via Disengage, Push Stay, or Pull Stay), the close-up overlay slides away, restoring the standard receding corridor perspective.

### Example Melee Lock Overlay Mockup:
![Melee Lock Overlay Mockup](C:/Users/Zerato/.gemini/antigravity-ide/brain/8f351f59-30d4-4952-8957-db6147ea6705/melee_lock_mockup_1781034787677.png)

---

## 3. Combat Controls: Hybrid Buttons & Hotkeys
- **Layout:** A clean control dock anchored at the bottom 25% of the screen.
- **Dynamic Action Menu:** Buttons are dynamically generated, listing only legal actions (and their exact AP costs) based on the player's current stance, distance, and combat state.
- **Shortcut Integration:** Every action button is fully bound to corresponding keyboard shortcuts (e.g., keys `1-9` or custom shortcuts) to enable rapid, mouse-free play.

---

## 4. Impact Feedback: High-Vibrancy screenshake
- **Trauma Screen Shake:** When damage is dealt or an entity falls, the entire `DebugLog` UI container shakes violently via rapid position/offset tweens.
- **Visual Log Flashing:** Text lines reporting hits flash bright white, then fade into a deep red color block.
- **Biometric doll Rumble:** The anatomical wireframe doll on the medical monitor vibrates independently when hits connect to its matching structural regions.

---

## 5. Reaction Windows: Time-Stop Overlays
- **Trigger:** Emitted when the opponent triggers a strike/shot and the player has enough reserved AP to react (Block or Dodge).
- **Visual Transition:** The combat screen dims slightly, and active turn flows freeze.
- **Reaction HUD:** A high-priority, blinking alert frame overlays the screen:
  ```text
  [!] REACTION WINDOW - INCOMING ATTACK [!]
  [ DODGE (%d AP) ]   [ BLOCK (%d AP) ]   [ PASS (0 AP) ]
  ```
- **Resolution:** Selecting an option resolves the strike and closes the alert, resuming normal combat flow.
