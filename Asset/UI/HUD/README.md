# Supplemental HUD Assets

`Asset/UI/revampedHUD/POCKET INVENTORY (MAIN)/` is the canonical visual source
for Arccross HUD work. The shared `PocketInventoryTheme.tres` supplies native
Godot `StyleBoxFlat` panel, button, and bar frames so UI scales cleanly without
stretching bitmap borders.

This folder is deliberately supplemental. Its medical anatomy and condition
plates remain available where they communicate gameplay more clearly than a
generic icon, but it no longer owns the primary HUD frame language.

Do not add new `frames/` textures or use texture-stretched panel shells here.
Use the Godot Theme and the Pocket Inventory palette instead.
