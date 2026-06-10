# ARCCROSS Combat Character Rig

The combat character is a reusable 3/4-view black silhouette assembled from
fourteen authored body pieces:

- Head and torso.
- Near/far upper arms, lower arms, and hands.
- Near/far thighs, shins, and feet.

The runtime rig uses the files in
`Asset/Characters/CombatSilhouetteThreeQuarter/Parts`. The older root-level
character sprite sheets are not rig sources.

## Presentation Boundary

`ModularCombatRig` is presentation-only. It consumes combatant snapshots and
accepted `ActionType` events. It does not calculate legal actions, firearm
rules, hits, damage, AP, or stance outcomes.

CombatCore exposes only:

- Equipped weapon ID and existing `WeaponClass`.
- Current `StanceState`.
- Accepted action events.

Gun-family selection remains a visual mapping. It does not add shotgun,
assault-rifle, or sniper concepts to `GameEnums`.

## Gun And FX Layers

The rig supports the GUNS V1.00 pack as three aligned tracks:

1. Weapon animation.
2. Muzzle flash/fire/smoke.
3. Casing, shell, or reload prop.

Current visual profiles are `pistol`, `shotgun`, `assault`, and `kar98`.
Horizontal and vertical sprite strips are converted to Godot `SpriteFrames`
at runtime, preserving the authored alignment between weapon and FX frames.
