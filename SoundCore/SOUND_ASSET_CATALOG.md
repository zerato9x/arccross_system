# ARCCROSS Sound Asset Catalog

Snapshot date: 2026-08-22
Scope: `SoundCore/Sound/**`, current audio references, and the live routing in
`SoundCore/audio_conductor.gd` and `SoundCore/sfx_conductor.gd`.

This is an audit catalog. It does not rename assets or change playback code.

## Inventory

There are 216 playable assets under `SoundCore/Sound`: 209 WAV and 7 MP3.
There are 204 SFX assets and 12 soundtrack assets. Every playable asset has a
matching `.import` file.

| Folder | Total | Directly referenced | Not directly referenced |
|---|---:|---:|---:|
| `soundtrack_1/` | 12 | 8 | 4 |
| `sfx/` root vendor files | 7 | 0 | 7 |
| `sfx/Clothing/` | 6 | 0 | 6 |
| `sfx/Combat/` | 12 | 4 | 8 |
| `sfx/Destruction/` | 16 | 0 | 16 |
| `sfx/Environment/` | 32 | 5 | 27 |
| `sfx/Equipment/` | 33 | 8 | 25 |
| `sfx/Food/` | 14 | 0 | 14 |
| `sfx/Footsteps/` | 20 | 20 | 0 |
| `sfx/guns/` | 33 | 13 | 20 |
| `sfx/Human/` | 11 | 9 | 2 |
| `sfx/Medicine/` | 6 | 2 | 4 |
| `sfx/Tools/` | 14 | 0 | 14 |
| **Total** | **216** | **69** | **147** |

“Directly referenced” means that a project source file contains the asset
path. It does not prove that a live event can reach the reference.

## Complete asset list

### Soundtrack

`Sound/soundtrack_1/`

- `Assault - angry - tension - battle.wav`
- `Assault(loop) - angry - tension - battle.wav`
- `Battlefield(loop).wav`
- `Dawn - slow - scary.wav`
- `Hunt.wav`
- `Hunted.wav`
- `Outlaws - violent - nervousness.wav`
- `Storm - dark - heavy - lurking.wav`
- `Storm(loop) - dark - heavy - lurking.wav`
- `Survivor - ending - lonely - sad - strings.wav`
- `Waiting_game(loop).wav`
- `War(loop).wav`

### SFX

`Sound/sfx/` root:

- `universfield-blade-piercing-body-352462.mp3`
- `universfield-body-hitting-ground-250958.mp3`
- `universfield-falling-game-character-352287.mp3`
- `universfield-fast-body-fall-impact-352725.mp3`
- `universfield-fatal-body-fall-thud-352716.mp3`
- `universfield-ground-impact-352053.mp3`
- `universfield-heavy-body-fall-impact-352728.mp3`

`Sound/sfx/Clothing/`:

- `ClothesRubberMovement1.wav`, `ClothesRubberMovement2.wav`, `ClothesRubberMovement3.wav`
- `ClothesSyntheticfabric1.wav`, `ClothesSyntheticfabric2.wav`, `ClothesSyntheticfabric3.wav`

`Sound/sfx/Combat/`:

- `DesignedGunshot_Pistol1.wav` through `DesignedGunshot_Pistol4.wav`
- `DesignedGunshot_Pistol1_Reverb.wav` through `DesignedGunshot_Pistol4_Reverb.wav`
- `DesignedPunch1.wav` through `DesignedPunch4.wav`

`Sound/sfx/Destruction/`:

- `CardboardBoxRip1.wav`, `CardboardBoxRip2.wav`
- `ClothRip1.wav`, `ClothRip2.wav`, `ClothRip3.wav`
- `DesignedCarCrash1.wav`, `DesignedCarCrash2.wav`
- `LargeGlassMirrorCrunch1.wav`, `LargeGlassMirrorCrunch2.wav`
- `LargeGlassMirrorSmash1.wav`, `LargeGlassMirrorSmash2.wav`
- `WoodSnap1.wav` through `WoodSnap5.wav`

`Sound/sfx/Environment/`:

- `BeeBuzz.wav`
- `BirdsCrowsDistantAmbienceLoop.wav`
- `CoastalWavesOnRocksLoop.wav`
- `FastWaterfallStreamLoop.wav`
- `GateWoodChain1.wav`, `GateWoodChain2.wav`, `GateWoodChain3.wav`
- `GrassRip1.wav`, `GrassRip2.wav`
- `Gravelfall1.wav`, `Gravelfall2.wav`, `Gravelfall3.wav`
- `MetalCabinet1.wav`
- `OldDoorClose.wav`, `OldDoorCreak.wav`, `OldDoorOpen.wav`, `OldDoorOpenAndClose.wav`
- `OverflowingWaterPipeLoop.wav`
- `Rockfall1.wav`, `Rockfall2.wav`, `Rockfall3.wav`
- `SwitchButton1_Off.wav`, `SwitchButton1_On.wav`
- `SwitchButton2_Off.wav`, `SwitchButton2_On.wav`
- `SwitchButton3_Off.wav`, `SwitchButton3_On.wav`
- `WaterSplash1.wav`, `WaterSplash2.wav`
- `WoodLogHandling1.wav`, `WoodLogHandling2.wav`, `WoodLogHandling3.wav`

`Sound/sfx/Equipment/`:

- `DesignedGunSoundHandling1.wav` through `DesignedGunSoundHandling4.wav`
- `DesignedGunSoundReload1.wav` through `DesignedGunSoundReload4.wav`
- `FirelighterPackaging1.wav`, `FirelighterPackaging2.wav`
- `LargeBagHandling1.wav`, `LargeBagHandling2.wav`, `LargeBagHandling3.wav`
- `LargeBagZip1.wav`, `LargeBagZip2.wav`
- `LighterFluid1.wav`, `LighterFluid2.wav`, `LighterFluid3.wav`
- `MatchHandling1.wav`, `MatchHandling2.wav`
- `MatchLight1.wav`, `MatchLight2.wav`
- `MatchStrike1.wav`, `MatchStrike2.wav`, `MatchStrike3.wav`
- `PaperDocument1.wav`, `PaperDocument2.wav`, `PaperDocument3.wav`
- `PlasticBagHandling1.wav`, `PlasticBagHandling2.wav`, `PlasticBagHandling3.wav`
- `PlasticBox1.wav`, `PlasticBox2.wav`

`Sound/sfx/Food/`:

- `EatingFood1.wav`, `EatingFood2.wav`, `EatingFood3.wav`
- `FoodPackagingDriedSoupBox1.wav`, `FoodPackagingDriedSoupBox2.wav`
- `FoodPackagingNoodles1.wav` through `FoodPackagingNoodles4.wav`
- `FoodPackagingWaterBottle1.wav`, `FoodPackagingWaterBottle2.wav`, `FoodPackagingWaterBottle3.wav`
- `SmallGlassBottles1.wav`, `SmallGlassBottles2.wav`

`Sound/sfx/Footsteps/`:

- `FootstepsConcrete1.wav` through `FootstepsConcrete4.wav`
- `FootstepsDryBeachTwigs1.wav` through `FootstepsDryBeachTwigs4.wav`
- `FootstepsSlushSnow1.wav` through `FootstepsSlushSnow4.wav`
- `FootstepsStoneDirt1.wav` through `FootstepsStoneDirt4.wav`
- `FootstepsWetGravelStones1.wav` through `FootstepsWetGravelStones4.wav`

`Sound/sfx/guns/ak47/`:

- `762x39 Burst Isolated WAV.wav`, `762x39 Single Isolated WAV.wav`
- `AK Rack WAV.wav`, `AK Reload Full WAV.wav`, `AK Reload Part 1 WAV.wav`, `AK Reload Part 2 WAV.wav`

`Sound/sfx/guns/pistols/`:

- `9mm Double Tap Isolated.wav`
- `9mm Pistol Rack Full.wav`, `9mm Pistol Reload 1.wav`, `9mm Pistol Reload 2.wav`
- `9mm Single Isolated.wav`, `9mm Single.wav`

`Sound/sfx/guns/revolver/`:

- `308 Double Tap Isolated.wav`, `308 Single Isolated.wav`, `308 Single.wav`
- `44 Magnum Close Cylinder.wav`, `44 Magnum Open Cylinder.wav`, `44 Magnum Single Load.wav`

`Sound/sfx/guns/rifle_carbon/`:

- `556 Double Tap Isolated WAV.wav`, `556 Single Isolated WAV.wav`
- `AR Bolt Release WAV.wav`, `AR Charging Handle WAV.wav`
- `AR Reload Full WAV.wav`, `AR Reload Part 1 WAV.wav`, `AR Reload Part 2 WAV.wav`

`Sound/sfx/guns/rifle_service/`:

- `762x54r Single Isolated WAV.wav`
- `Lever Cycle WAV.wav`, `Lever Reload WAV.wav`, `Mosin Top Load.wav`

`Sound/sfx/guns/shotgun/`:

- `20 Gauge Single Isolated.wav`, `20 Gauge Single.wav`
- `Pump Reload Full WAV.wav`, `Single Shotgun Load.wav`

`Sound/sfx/Human/`:

- `HumanBreathingOut1.wav` through `HumanBreathingOut4.wav`
- `HumanCough1.wav`, `HumanExhausted1.wav`
- `HumanInjured1.wav` through `HumanInjured5.wav`

`Sound/sfx/Medicine/`:

- `Bandage1.wav`
- `BlisterPack1.wav`, `BlisterPack2.wav`, `BlisterPack3.wav`
- `PillsBox1.wav`, `PillsBox2.wav`

`Sound/sfx/Tools/`:

- `CrowbarDrag1.wav`
- `DesignedAxe1.wav` through `DesignedAxe4.wav`
- `DesignedPickaxe1.wav` through `DesignedPickaxe4.wav`
- `Hammer1.wav`, `Hammer2.wav`, `Hammer3.wav`, `HammerNail1.wav`
- `WoodMovement1.wav`

## Current runtime routing

### Music

| Scene/event | Current key | Current asset |
|---|---|---|
| Macro day | `Dawn` | `soundtrack_1/Dawn - slow - scary.wav` |
| Macro night | `Storm` | `soundtrack_1/Storm(loop) - dark - heavy - lurking.wav` |
| Standard combat | random `Outlaws` or `Assault` | `Outlaws - violent - nervousness.wav` or `Assault(loop) - angry - tension - battle.wav` |
| Critical overlay | `Battlefield` | `Battlefield(loop).wav` |
| Special combat before first strike | `Waiting_game` | `Waiting_game(loop).wav` |
| Special combat after first strike | `War` | `War(loop).wav` |
| Game over | `Survivor` | `Survivor - ending - lonely - sad - strings.wav` |
| Main menu scene-local player | none | `Survivor - ending - lonely - sad - strings.wav` with `autoplay = true` |

The five soundtrack files whose names contain `(loop)` all have
`edit/loop_mode=0` in their import metadata. The conductor currently repeats
tracks from `_on_music_finished()`, so the filename marker and the import
setting do not express the same contract.

### Combat weapon mapping

The runtime receives gameplay IDs such as `service_pistol` and
`unique_modifiedrifle`, but the audio files are keyed by caliber/platform.
`_gunshot_pool_for_id()` uses exact string matches and silently returns the
pistol pool for every unknown ID.

| Gameplay weapon ID | Weapon class | Current fire pool | Current reload pool | Current cycle pool |
|---|---|---|---|---|
| `service_pistol` | pistol | `guns/pistols/9mm Single Isolated.wav` via fallback | generic Equipment reload 1–4 | generic Equipment handling 1–4 |
| `carbon_pistol` | pistol | `guns/pistols/9mm Single Isolated.wav` via fallback | generic Equipment reload 1–4 | generic Equipment handling 1–4 |
| `unique_theoperator` | pistol | `guns/pistols/9mm Single Isolated.wav` via fallback | generic Equipment reload 1–4 | generic Equipment handling 1–4 |
| `revolver` | pistol class | `guns/revolver/308 Single Isolated.wav` | generic Equipment reload 1–4 | generic Equipment handling 1–4 |
| `ak47` | rifle | `guns/ak47/762x39 Single Isolated WAV.wav` | `guns/ak47/AK Reload Full WAV.wav` | `guns/ak47/AK Rack WAV.wav` |
| `carbon_rifle` | rifle | `guns/rifle_carbon/556 Single Isolated WAV.wav` | `guns/rifle_carbon/AR Reload Full WAV.wav` | AR charging-handle/bolt-release pool |
| `service_rifle` | rifle | `guns/rifle_service/762x54r Single Isolated WAV.wav` | `guns/rifle_service/Mosin Top Load.wav` | `guns/rifle_service/Lever Cycle WAV.wav` |
| `unique_modifiedrifle` | rifle | **pistol fallback** | generic Equipment reload 1–4 | generic Equipment handling 1–4 |
| `unique_railgun` | rifle | **pistol fallback** | generic Equipment reload 1–4 | generic Equipment handling 1–4 |
| `unique_arcbornblaster` | rifle | **pistol fallback** | generic Equipment reload 1–4 | generic Equipment handling 1–4 |
| `shotgun` | shotgun | `guns/shotgun/20 Gauge Single Isolated.wav` | generic Equipment reload 1–2 | generic Equipment handling 1–4 |

The `sfx_id` value (`weapon_fire`, `weapon_reload`, `weapon_cycle`,
`melee_contact`, or `shove_contact`) is only used as a non-empty gate by the
presentation player. The SFX conductor selects from `action_id`,
`weapon_class`, and `weapon_id`; it does not resolve the `sfx_id` itself.

### Other SFX routes

| Event | Current selection | Catalog concern |
|---|---|---|
| `combat_impact_sfx` | `Combat/DesignedPunch1.wav` through `DesignedPunch4.wav` | Firearm impacts, blades, blunt weapons, and shoves all share the punch pool. The seven vendor body-impact MP3s are unused. |
| `humanoid_injured` | `Human/HumanInjured1.wav` through `HumanInjured5.wav` | The route is explicit, but the asset identity is generic vocal injury rather than wound/material-specific impact. |
| `humanoid_exhausted` | `HumanExhausted1.wav` plus `HumanBreathingOut1.wav`–`3.wav` | `HumanBreathingOut4.wav` is unused. |
| medicine `item_used` | `Medicine/PillsBox1.wav` or `PillsBox2.wav` | All non-medicine item use categories are silent; bandage/blister-pack assets are unused. |
| world contact | random `Environment/MetalCabinet1.wav`, `WoodLogHandling1.wav`, or `Gravelfall1.wav` | Seven distinct world actions share three unrelated generic sounds. |
| world miss/slip | `Environment/Gravelfall2.wav` or `OldDoorCreak.wav` | The selector does not distinguish the authored action or material. |
| footsteps `MUD` | wet gravel/stones plus slush/snow pools | `MUD` is mapped to two different material families. |
| footsteps `TREES` | dry beach twigs pool | Exact terrain/material contract is implicit in the string. |
| footsteps `DIRT` | stone/dirt pool | Exact terrain/material contract is implicit in the string. |
| any other footstep background | concrete pool | Unknown backgrounds silently become concrete. |

## Naming and authority findings

1. The asset names are not one naming scheme. The tree mixes PascalCase
   category names, lowercase firearm directories, spaces, parentheses,
   underscores, hyphenated vendor slugs, numeric variants, redundant `WAV`
   suffixes, and `(loop)` markers.
2. The files are not currently failing because of those names: all 216 imports
   exist, and all 69 unique direct references resolve to files on disk.
3. The highest-risk mismatch is the boundary between gameplay weapon IDs and
   audio asset identity. Unknown firearm IDs silently become the pistol pool.
4. The current conductor has broad semantic fallbacks for combat contact,
   world actions, and unknown footsteps. Those fallbacks explain “wrong sound”
   symptoms more strongly than the filename characters do.
5. The catalog contains substantial content that has no live route yet:
   clothing, destruction, food, tools, vendor body impacts, most gun handling
   variants, alternate gunshots, and alternate soundtrack files.
6. Music has two owners at the main menu: the autoload conductor and the
   scene-local `MainMenu/BGM` player. The latter autoplays `Survivor` while the
   menu asks the conductor for `silent`.

## Recommended next boundary

Before renaming files, freeze a canonical cue manifest keyed by gameplay-facing
IDs and material/event roles. Then map every existing asset into that manifest,
marking intentional reuse and genuinely missing cues explicitly. The next
implementation slice should be the manifest plus a focused routing test; mass
renaming can follow as a separate migration once no selector depends on raw
filenames.

Live/editor listening remains a separate acceptance gate from headless
reference/import checks.
