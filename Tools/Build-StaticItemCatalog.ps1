param(
    [switch]$Rebuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$AssetRoot = Join-Path $ProjectRoot 'Asset\Innawoods_Asset'
$OutputRoot = Join-Path $ProjectRoot 'ItemCore\Items'
$ItemScriptPath = 'res://ItemCore/ItemData.gd'

$ItemType = @{
    Junk = 0; Weapon = 1; Armor = 2; Consumable = 3
    Tool = 4; Ammunition = 5; Material = 6; Attachment = 7
}
$Category = @{
    Misc = 0; Camping = 1; Electronics = 2; Materials = 3
    Medicine = 4; Nutrition = 5; Tools = 6; Traps = 7
    Ammunition = 8; MeleeWeapon = 9; Firearm = 10; Armor = 11
    Backpack = 12; ChestRig = 13; Eyewear = 14; Facewear = 15
    Footwear = 16; Headwear = 17; InnerTorso = 18; Legwear = 19
    Neckwear = 20; OuterTorso = 21; Attachment = 22
}
$Slot = @{
    None = 0; InnerTorso = 1; OuterTorso = 2; Hands = 3; Legs = 4
    Feet = 5; Backpack = 6; Sling = 7; Belt = 8; Vest = 9
    Head = 10; Eyes = 11; Face = 12; Neck = 13; Arms = 14
}
$WeaponClass = @{ None = 0; Blunt = 1; Blade = 2; Pistol = 3; Rifle = 4; Shotgun = 5 }
$DamageType = @{ Blunt = 0; Sharp = 1; Ballistic = 2 }
$ConsumableEffect = @{ Hunger = 0; Thirst = 1; Fatigue = 2; Bleeding = 3; Blood = 4 }
$InteractionRole = @{ Search = 1; Camp = 2 }

function Convert-ToId([string]$Value) {
    return $Value.ToLowerInvariant().Replace('-', '_').Replace(' ', '_')
}

function Convert-ToDisplayName([string]$Id) {
    $words = $Id.Split('_')
    for ($index = 0; $index -lt $words.Count; $index++) {
        switch ($words[$index]) {
            'ak47' { $words[$index] = 'AK-47' }
            'mre' { $words[$index] = 'MRE' }
            'pda' { $words[$index] = 'PDA' }
            default {
                $word = $words[$index]
                if ($word.Length -gt 0) {
                    $words[$index] = $word.Substring(0, 1).ToUpperInvariant() + $word.Substring(1)
                }
            }
        }
    }
    return $words -join ' '
}

function Convert-ToResourcePath([string]$FullPath) {
    $relative = $FullPath.Substring($ProjectRoot.Length + 1).Replace('\', '/')
    return "res://$relative"
}

function New-Item([string]$Id, [string]$SpritePath) {
    return [ordered]@{
        id = $Id
        display_name = Convert-ToDisplayName $Id
        lore_description = "Field catalog entry for $(Convert-ToDisplayName $Id)."
        item_type = $ItemType.Junk
        catalog_category = $Category.Misc
        tags = @()
        size_cost = 1
        target_slot = $Slot.None
        inventory_sprite_path = $SpritePath
        weight = 0.2
    }
}

function Set-Values([System.Collections.IDictionary]$Item, [System.Collections.IDictionary]$Values) {
    foreach ($key in $Values.Keys) {
        $Item[$key] = $Values[$key]
    }
}

function Test-OverlayName([string]$Stem) {
    return (
        $Stem.StartsWith('equip') -or
        $Stem.Contains('_equip_') -or
        $Stem.EndsWith('_equip')
    )
}

function Get-MatchingOverlays(
    [System.IO.FileInfo]$InventoryFile,
    [System.IO.FileInfo[]]$AllFiles,
    [string]$ItemId
) {
    $baseStem = $InventoryFile.BaseName
    if ($baseStem.EndsWith('_loaded')) {
        $baseStem = $baseStem.Substring(0, $baseStem.Length - 7)
    }

    $matches = [System.Collections.Generic.List[string]]::new()
    foreach ($candidate in $AllFiles) {
        if ($candidate.DirectoryName -ne $InventoryFile.DirectoryName) { continue }
        $stem = $candidate.BaseName
        if (-not (Test-OverlayName $stem)) { continue }
        if (
            $stem.StartsWith("equip_$baseStem") -or
            $stem.StartsWith("${baseStem}_equip") -or
            ($stem.StartsWith('equip') -and $stem.EndsWith("_$baseStem"))
        ) {
            $matches.Add((Convert-ToResourcePath $candidate.FullName))
        }
    }

    $explicit = @{
        armor_arcborn = @('Equipments/Armour/euip.png')
        jeans_2 = @('Equipments/Leg/equip_jeans_1.png')
        carbon_pistol = @('Weapons/Pistol/pistol_equip.png')
        service_pistol = @('Weapons/Pistol/pistol_equip.png')
        revolver = @('Weapons/Pistol/pistol_equip.png')
        unique_theoperator = @('Weapons/Pistol/unique_theoperator_equip.png')
        bat_1 = @('Weapons/Melee_Blunt/equip_bat.png')
        bat_2 = @('Weapons/Melee_Blunt/equip_bat.png')
        bat_spiked = @('Weapons/Melee_Blunt/equip_bat.png')
        sledgehammer = @('Weapons/Melee_Blunt/equip_ledgehammer.png')
        axe_makeshift = @('Weapons/Melee_Sharp/1H/equip_axe.png')
        knife_carbon = @('Weapons/Melee_Sharp/1H/equip_knife1.png')
        knife_service = @('Weapons/Melee_Sharp/1H/equip_knife2.png')
        knife_makeshift = @('Weapons/Melee_Sharp/1H/equip_knife3.png')
    }
    if ($explicit.ContainsKey($ItemId)) {
        foreach ($relative in $explicit[$ItemId]) {
            $matches.Add("res://Asset/Innawoods_Asset/$relative")
        }
    }
    return @($matches | Sort-Object -Unique)
}

$CoreOverrides = @{
    water_bottle = @{
        display_name = 'Clean Water Bottle'; item_type = $ItemType.Consumable
        consumable_effect = $ConsumableEffect.Thirst; consumable_potency = 7.0
        size_cost = 1; weight = 0.5
    }
    mre = @{
        display_name = 'Field MRE'; item_type = $ItemType.Consumable
        consumable_effect = $ConsumableEffect.Hunger; consumable_potency = 7.0
        size_cost = 1; weight = 0.6
    }
    bloodbag = @{
        id = 'blood_bag'; display_name = 'Salvaged Blood Bag'
        item_type = $ItemType.Consumable; consumable_effect = $ConsumableEffect.Blood
        consumable_potency = 5.0; size_cost = 1; weight = 0.5
    }
    life_booster = @{
        display_name = 'Life Booster'; item_type = $ItemType.Consumable
        consumable_effect = $ConsumableEffect.Fatigue; consumable_potency = 10.0
    }
    life_booster_makeshift = @{
        display_name = 'Makeshift Life Booster'; item_type = $ItemType.Consumable
        consumable_effect = $ConsumableEffect.Fatigue; consumable_potency = 6.0
    }
    bandage = @{
        item_type = $ItemType.Consumable
        consumable_effect = $ConsumableEffect.Bleeding; consumable_potency = 3.0
    }
    dressingpack = @{
        display_name = 'Dressing Pack'; item_type = $ItemType.Consumable
        consumable_effect = $ConsumableEffect.Bleeding; consumable_potency = 6.0
    }
    tourniquet = @{
        item_type = $ItemType.Consumable
        consumable_effect = $ConsumableEffect.Bleeding; consumable_potency = 9.0
    }
    sleeping_bag = @{
        interaction_roles = @($InteractionRole.Camp); camp_sleep_bonus = 4.0
        camp_healing_bonus = 1.0; camp_concealment_bonus = -1.0
    }
    tentkit = @{
        display_name = 'Tent Kit'; interaction_roles = @($InteractionRole.Camp)
        camp_sleep_bonus = 2.0; camp_shelter_bonus = 6.0
        camp_healing_bonus = 1.0; camp_concealment_bonus = -1.0
    }
    blanket = @{ interaction_roles = @($InteractionRole.Camp); camp_sleep_bonus = 2.0 }
    portable_heater = @{
        interaction_roles = @($InteractionRole.Camp); camp_shelter_bonus = 3.0
        camp_healing_bonus = 2.0
    }
    multitool = @{
        display_name = 'Multitool'; interaction_roles = @($InteractionRole.Search)
        search_loot_bonus = 4.0; search_sneak_bonus = 1.0
    }
    shovel = @{
        interaction_roles = @($InteractionRole.Search)
        search_loot_bonus = 3.0; search_safety_bonus = 1.0
    }
    binoculars = @{
        interaction_roles = @($InteractionRole.Search)
        search_safety_bonus = 3.0; search_sneak_bonus = 2.0
    }
    flashlight = @{
        interaction_roles = @($InteractionRole.Search)
        search_safety_bonus = 2.0; search_sneak_bonus = -1.0
    }
    trap_makeshift = @{
        interaction_roles = @($InteractionRole.Camp)
        camp_alertness_bonus = 5.0; camp_concealment_bonus = 1.0
    }
    trap_heavy = @{
        interaction_roles = @($InteractionRole.Camp)
        camp_alertness_bonus = 7.0; camp_concealment_bonus = -1.0
    }
    backpack_service_big = @{
        display_name = 'Large Service Backpack'; capacity_bonus = 12
        bulk = 2.0; weight = 1.5
    }
    backpack_service = @{
        display_name = 'Service Backpack'; capacity_bonus = 8
        bulk = 1.5; weight = 1.0
    }
    backpack_survivalist = @{
        display_name = 'Survivalist Backpack'; capacity_bonus = 10
        bulk = 1.5; weight = 1.2
    }
    coat_leather = @{
        display_name = 'Scavenger Leather Coat'; capacity_bonus = 4
        protection_blunt = 2.0; protection_sharp = 4.0
        protection_ballistic = 1.0; bulk = 2.0; weight = 2.0
        threat = 1.0; insulation = 7.0
    }
    pants_cargo = @{
        display_name = 'Cargo Pants'; capacity_bonus = 2
        protection_blunt = 1.0; protection_sharp = 1.0
        bulk = 0.5; weight = 0.8; insulation = 2.0
    }
    pants_carbon = @{
        display_name = 'Carbon Combat Pants'; capacity_bonus = 2
        protection_blunt = 2.0; protection_sharp = 3.0
        protection_ballistic = 1.0; bulk = 1.0; weight = 1.2
        insulation = 2.0
    }
    boot_service = @{
        display_name = 'Service Boots'; protection_blunt = 1.0
        protection_sharp = 1.0; bulk = 1.0; weight = 1.5
    }
    shirt_thermo = @{
        display_name = 'Thermal Undershirt'; protection_blunt = 0.5
        protection_sharp = 0.5; bulk = 0.5; weight = 0.5; insulation = 10.0
    }
    armor_arcborn = @{
        display_name = 'Arcborn Armor'; protection_blunt = 4.0
        protection_sharp = 6.0; protection_ballistic = 5.0
        bulk = 3.0; weight = 3.5; threat = 5.0
    }
}

$FirearmOverrides = @{
    carbon_pistol = @{
        display_name = 'Carbon Pistol'; flesh_damage = 7.5; armor_penetration = 6.5
        accuracy_rating = 9.0; effective_range = 6; optimal_range = 5
        bulk = 0.5; weight = 0.9; threat = 7.0; max_magazine = 16
        starting_magazine = 16; ammunition_id = 'pistol_round'
        magazine_id = 'carbon_pistol_magazine'
    }
    service_pistol = @{
        display_name = 'Service Pistol'; flesh_damage = 7.0; armor_penetration = 6.0
        accuracy_rating = 7.0; effective_range = 6; optimal_range = 4
        bulk = 0.6; weight = 1.1; threat = 6.0; max_magazine = 8
        starting_magazine = 8; ammunition_id = 'pistol_round'
        magazine_id = 'service_pistol_magazine'
    }
    revolver = @{
        display_name = 'Service Revolver'; flesh_damage = 7.0; armor_penetration = 6.0
        accuracy_rating = 6.0; effective_range = 6; optimal_range = 4
        bulk = 0.7; weight = 1.2; threat = 6.0; max_magazine = 6
        starting_magazine = 6; ammunition_id = 'pistol_round'
        reload_aid_id = 'revolver_speedloader'; cycle_loads_one_round = $true
    }
    carbon_rifle = @{
        display_name = 'Carbon Rifle'; flesh_damage = 10.5; armor_penetration = 9.0
        accuracy_rating = 10.0; effective_range = 11; optimal_range = 8
        bulk = 2.2; weight = 3.5; threat = 10.0; max_magazine = 31
        starting_magazine = 31; ammunition_id = 'rifle_round'
        magazine_id = 'carbon_rifle_magazine'
    }
    ak47 = @{
        display_name = 'AK-47'; flesh_damage = 11.5; armor_penetration = 8.5
        accuracy_rating = 7.0; effective_range = 11; optimal_range = 7
        bulk = 3.0; weight = 4.3; threat = 11.0; max_magazine = 31
        starting_magazine = 31; ammunition_id = 'rifle_round'
        magazine_id = 'ak47_magazine'
    }
    service_rifle = @{
        display_name = 'Service Rifle'; flesh_damage = 10.5; armor_penetration = 9.0
        accuracy_rating = 8.5; effective_range = 11; optimal_range = 9
        bulk = 2.8; weight = 4.0; threat = 10.0; max_magazine = 5
        starting_magazine = 5; ammunition_id = 'rifle_round'
        reload_aid_id = 'service_rifle_clip'; requires_cycle_after_shot = $true
        cycle_loads_one_round = $true
    }
    shotgun = @{
        display_name = 'Combat Shotgun'; weapon_type = $WeaponClass.Shotgun
        flesh_damage = 12.0; armor_penetration = 4.0; accuracy_rating = 8.0
        effective_range = 4; optimal_range = 2; minimum_damage_multiplier = 0.35
        bulk = 3.0; weight = 3.5; threat = 10.0; max_magazine = 6
        starting_magazine = 6; ammunition_id = 'shotgun_shell'
        requires_cycle_after_shot = $true; cycle_loads_one_round = $true
    }
}

$MeleeOverrides = @{
    crowbar = @{
        display_name = 'Salvage Crowbar'; flesh_damage = 1.0; stance_damage = 4.0
        armor_penetration = 1.0; accuracy_rating = 5.0; bulk = 0.5
        weight = 1.5; threat = 1.0; interaction_roles = @($InteractionRole.Search)
        search_loot_bonus = 3.0; search_safety_bonus = -1.0
        search_sneak_bonus = -2.0
    }
    rebar = @{
        display_name = 'Scrap Rebar'; flesh_damage = 1.5; stance_damage = 6.0
        accuracy_rating = 7.0; bulk = 1.5; weight = 3.0; threat = 2.0
    }
}

function Add-GeneralDefaults([System.Collections.IDictionary]$Item, [string]$Folder) {
    switch ($Folder.ToLowerInvariant()) {
        'camping' {
            Set-Values $Item @{ item_type = $ItemType.Tool; catalog_category = $Category.Camping }
        }
        'electronics' {
            Set-Values $Item @{ item_type = $ItemType.Tool; catalog_category = $Category.Electronics }
        }
        'materials' {
            Set-Values $Item @{ item_type = $ItemType.Material; catalog_category = $Category.Materials }
        }
        'medicines' {
            Set-Values $Item @{
                item_type = $ItemType.Consumable; catalog_category = $Category.Medicine
                consumable_effect = $ConsumableEffect.Bleeding; consumable_potency = 2.0
            }
        }
        'nutrition' {
            Set-Values $Item @{
                item_type = $ItemType.Consumable; catalog_category = $Category.Nutrition
                consumable_effect = $ConsumableEffect.Hunger; consumable_potency = 3.0
            }
        }
        'tools' {
            Set-Values $Item @{ item_type = $ItemType.Tool; catalog_category = $Category.Tools }
        }
        'traps' {
            Set-Values $Item @{ item_type = $ItemType.Tool; catalog_category = $Category.Traps }
        }
    }
}

function Add-EquipmentDefaults(
    [System.Collections.IDictionary]$Item,
    [System.IO.FileInfo]$File
) {
    Set-Values $Item @{ item_type = $ItemType.Armor; weight = 0.5; tags = @('equipment') }
    switch ($File.Directory.Name.ToLowerInvariant()) {
        'armour' {
            Set-Values $Item @{ catalog_category = $Category.Armor; target_slot = $Slot.OuterTorso }
        }
        'back' {
            Set-Values $Item @{
                catalog_category = $Category.Backpack; target_slot = $Slot.Backpack
                capacity_bonus = 6
            }
        }
        'chest' {
            Set-Values $Item @{
                catalog_category = $Category.ChestRig; target_slot = $Slot.Vest
                capacity_bonus = 2
            }
        }
        'eyes' {
            Set-Values $Item @{ catalog_category = $Category.Eyewear; target_slot = $Slot.Eyes }
        }
        { $_ -in @('face', 'mask') } {
            Set-Values $Item @{ catalog_category = $Category.Facewear; target_slot = $Slot.Face }
        }
        'foot' {
            Set-Values $Item @{ catalog_category = $Category.Footwear; target_slot = $Slot.Feet }
        }
        { $_ -in @('head', 'helmet') } {
            Set-Values $Item @{ catalog_category = $Category.Headwear; target_slot = $Slot.Head }
        }
        'inner_torso' {
            Set-Values $Item @{ catalog_category = $Category.InnerTorso; target_slot = $Slot.InnerTorso }
        }
        'leg' {
            Set-Values $Item @{ catalog_category = $Category.Legwear; target_slot = $Slot.Legs }
        }
        'neck' {
            Set-Values $Item @{ catalog_category = $Category.Neckwear; target_slot = $Slot.Neck }
        }
        'outer_torso' {
            Set-Values $Item @{ catalog_category = $Category.OuterTorso; target_slot = $Slot.OuterTorso }
        }
        default {
            if ($Item.id -like 'armour_arms*') {
                Set-Values $Item @{ catalog_category = $Category.Armor; target_slot = $Slot.Arms }
            }
            elseif ($Item.id -like 'armour_greaves*') {
                Set-Values $Item @{ catalog_category = $Category.Armor; target_slot = $Slot.Legs }
            }
        }
    }
}

function Test-LoadingAid([string]$Id) {
    return (
        $Id.EndsWith('_magazine') -or
        $Id.EndsWith('_clip') -or
        $Id.EndsWith('_speedloader')
    )
}

function Add-DefaultFirearm(
    [System.Collections.IDictionary]$Item,
    [int]$Class,
    [bool]$TwoHanded
) {
    Set-Values $Item @{
        item_type = $ItemType.Weapon; catalog_category = $Category.Firearm
        weapon_type = $Class; damage_type = $DamageType.Ballistic
        flesh_damage = $(if ($TwoHanded) { 10.0 } else { 8.0 })
        stance_damage = 0.0
        armor_penetration = $(if ($TwoHanded) { 8.0 } else { 6.0 })
        accuracy_rating = 6.0
        effective_range = $(if ($TwoHanded) { 10 } else { 6 })
        optimal_range = $(if ($TwoHanded) { 7 } else { 4 })
        target_slot = $(if ($TwoHanded) { $Slot.Sling } else { $Slot.Belt })
        requires_two_hands = $TwoHanded
        size_cost = $(if ($TwoHanded) { 4 } else { 2 })
        threat = $(if ($TwoHanded) { 9.0 } else { 6.0 })
        ammunition_id = $(if ($TwoHanded) { 'rifle_round' } else { 'pistol_round' })
        max_magazine = 8; starting_magazine = 8
    }
}

function Add-WeaponDefaults(
    [System.Collections.IDictionary]$Item,
    [System.IO.FileInfo]$File
) {
    $normalizedPath = $File.FullName.Replace('\', '/').ToLowerInvariant()
    if ($normalizedPath.Contains('/ammo/') -or (Test-LoadingAid $Item.id)) {
        Set-Values $Item @{
            item_type = $ItemType.Ammunition
            catalog_category = $Category.Ammunition
            target_slot = $Slot.Vest; size_cost = 0
        }
        return
    }
    if ($Item.id -eq 'service_rifle_scope') {
        Set-Values $Item @{
            item_type = $ItemType.Attachment
            catalog_category = $Category.Attachment
        }
        return
    }
    if ($Item.id.Contains('shield')) {
        Set-Values $Item @{
            item_type = $ItemType.Armor; catalog_category = $Category.Armor
            target_slot = $Slot.Hands; size_cost = 3; requires_two_hands = $true
        }
        return
    }

    Set-Values $Item @{
        item_type = $ItemType.Weapon; catalog_category = $Category.MeleeWeapon
        weapon_type = $WeaponClass.Blunt; damage_type = $DamageType.Blunt
        target_slot = $Slot.Belt; size_cost = 2; flesh_damage = 2.0
        stance_damage = 4.0; accuracy_rating = 6.0; threat = 2.0
    }
    if ($normalizedPath.Contains('/melee_sharp/')) {
        Set-Values $Item @{
            weapon_type = $WeaponClass.Blade; damage_type = $DamageType.Sharp
            flesh_damage = 5.0; stance_damage = 0.0; armor_penetration = 3.0
        }
        if ($normalizedPath.Contains('/2h/')) {
            Set-Values $Item @{
                target_slot = $Slot.Sling; requires_two_hands = $true; size_cost = 4
            }
        }
    }
    elseif ($normalizedPath.Contains('/melee_blunt/')) {
        if ($Item.id -in @('sledgehammer', 'warhammer')) {
            Set-Values $Item @{
                target_slot = $Slot.Sling; requires_two_hands = $true; size_cost = 4
            }
        }
    }
    elseif ($normalizedPath.Contains('/pistol/')) {
        Add-DefaultFirearm $Item $WeaponClass.Pistol $false
    }
    elseif ($normalizedPath.Contains('/rifle/')) {
        Add-DefaultFirearm $Item $WeaponClass.Rifle $true
    }
    elseif ($normalizedPath.Contains('/special/')) {
        Add-DefaultFirearm $Item $WeaponClass.Rifle $true
    }
}

function Get-WeaponId([string]$Stem) {
    switch ($Stem) {
        'carbon_pistol_loaded' { return 'carbon_pistol' }
        'service_pistol_loaded' { return 'service_pistol' }
        'ak47_loaded' { return 'ak47' }
        'carbon_rifle_loaded' { return 'carbon_rifle' }
        'pistol_ammo' { return 'pistol_round' }
        'rifle_ammo' { return 'rifle_round' }
        'carbon_rifle_ammo' { return 'carbon_rifle_round' }
        'shell' { return 'shotgun_shell' }
        'service_rifle_noscope' { return 'service_rifle' }
        'service_rifle_scopeattachment' { return 'service_rifle_scope' }
        default { return Convert-ToId $Stem }
    }
}

function Add-SpecialWeaponValues([System.Collections.IDictionary]$Item) {
    switch ($Item.id) {
        'pistol_round' { Set-Values $Item @{ display_name = 'Pistol Round'; weight = 0.02 } }
        'rifle_round' { Set-Values $Item @{ display_name = 'Rifle Round'; weight = 0.025 } }
        'carbon_rifle_round' { Set-Values $Item @{ display_name = 'Carbon Rifle Round'; weight = 0.02 } }
        'shotgun_shell' { Set-Values $Item @{ display_name = 'Shotgun Shell'; weight = 0.05 } }
        'service_rifle_scope' {
            Set-Values $Item @{
                item_type = $ItemType.Attachment; catalog_category = $Category.Attachment
                compatible_weapon_ids = @('service_rifle')
                grants_snipe = $true; macro_snipe_range = 2
            }
        }
        'revolver_speedloader' {
            Set-Values $Item @{
                display_name = 'Revolver Speedloader'
                accepted_ammunition_id = 'pistol_round'; magazine_capacity = 6
            }
        }
        'service_pistol_magazine' {
            Set-Values $Item @{ accepted_ammunition_id = 'pistol_round'; magazine_capacity = 8 }
        }
        'carbon_pistol_magazine' {
            Set-Values $Item @{ accepted_ammunition_id = 'pistol_round'; magazine_capacity = 16 }
        }
        'unique_theoperator_magazine' {
            Set-Values $Item @{ accepted_ammunition_id = 'pistol_round'; magazine_capacity = 8 }
        }
        'carbon_rifle_magazine' {
            Set-Values $Item @{ accepted_ammunition_id = 'rifle_round'; magazine_capacity = 31 }
        }
        'ak47_magazine' {
            Set-Values $Item @{ accepted_ammunition_id = 'rifle_round'; magazine_capacity = 31 }
        }
        'service_rifle_clip' {
            Set-Values $Item @{ accepted_ammunition_id = 'rifle_round'; magazine_capacity = 5 }
        }
    }
}

function Convert-ToGodotValue([string]$Key, $Value) {
    if ($Value -is [bool]) {
        return $Value.ToString().ToLowerInvariant()
    }
    if ($Value -is [string]) {
        return '"' + $Value.Replace('\', '\\').Replace('"', '\"') + '"'
    }
    if ($Value -is [System.Array]) {
        $serialized = @($Value | ForEach-Object {
            if ($_ -is [string]) {
                '"' + $_.Replace('\', '\\').Replace('"', '\"') + '"'
            }
            else {
                [Convert]::ToString($_, [Globalization.CultureInfo]::InvariantCulture)
            }
        }) -join ', '
        if ($Key -in @('tags', 'equipped_sprite_paths', 'compatible_weapon_ids')) {
            return "Array[String]([$serialized])"
        }
        return "Array[int]([$serialized])"
    }
    if ($Value -is [double] -or $Value -is [single] -or $Value -is [decimal]) {
        $text = [Convert]::ToString($Value, [Globalization.CultureInfo]::InvariantCulture)
        if (-not $text.Contains('.')) { $text += '.0' }
        return $text
    }
    return [Convert]::ToString($Value, [Globalization.CultureInfo]::InvariantCulture)
}

function Convert-ToTres([System.Collections.IDictionary]$Item) {
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('[gd_resource type="Resource" script_class="ItemData" load_steps=2 format=3]')
    $lines.Add('')
    $lines.Add("[ext_resource type=`"Script`" path=`"$ItemScriptPath`" id=`"1_itemdata`"]")
    $lines.Add('')
    $lines.Add('[resource]')
    $lines.Add('script = ExtResource("1_itemdata")')
    foreach ($key in $Item.Keys) {
        $lines.Add("$key = $(Convert-ToGodotValue $key $Item[$key])")
    }
    $lines.Add('')
    return $lines -join "`n"
}

$definitions = [System.Collections.Generic.List[object]]::new()

$generalRoot = Join-Path $AssetRoot 'Items'
foreach ($file in Get-ChildItem -LiteralPath $generalRoot -Recurse -File -Filter '*.png' | Sort-Object FullName) {
    if ($file.FullName.Contains('Weapon_parts(wip)')) { continue }
    $id = Convert-ToId $file.BaseName
    $item = New-Item $id (Convert-ToResourcePath $file.FullName)
    $item.tags = @($file.Directory.Name.ToLowerInvariant())
    Add-GeneralDefaults $item $file.Directory.Name
    if ($CoreOverrides.ContainsKey($id)) { Set-Values $item $CoreOverrides[$id] }
    $definitions.Add($item)
}

$equipmentRoot = Join-Path $AssetRoot 'Equipments'
$equipmentFiles = @(Get-ChildItem -LiteralPath $equipmentRoot -Recurse -File -Filter '*.png' | Sort-Object FullName)
foreach ($file in $equipmentFiles) {
    if (
        $file.Name -in @('pants_navy.png', 'euip.png') -or
        $file.FullName.Contains('\Special\') -or
        (Test-OverlayName $file.BaseName)
    ) { continue }
    $id = Convert-ToId $file.BaseName
    $item = New-Item $id (Convert-ToResourcePath $file.FullName)
    Add-EquipmentDefaults $item $file
    $overlays = @(Get-MatchingOverlays $file $equipmentFiles $id)
    if ($overlays.Count -gt 0) { $item.equipped_sprite_paths = $overlays }
    if ($CoreOverrides.ContainsKey($id)) { Set-Values $item $CoreOverrides[$id] }
    $definitions.Add($item)
}

$weaponRoot = Join-Path $AssetRoot 'Weapons'
$weaponFiles = @(Get-ChildItem -LiteralPath $weaponRoot -Recurse -File -Filter '*.png' | Sort-Object FullName)
foreach ($file in $weaponFiles) {
    if (
        (Test-OverlayName $file.BaseName) -or
        $file.BaseName.EndsWith('_unloaded') -or
        $file.BaseName -eq 'service_rifle_scope'
    ) { continue }
    $id = Get-WeaponId $file.BaseName
    $item = New-Item $id (Convert-ToResourcePath $file.FullName)
    $item.tags = @('weapon')
    Add-WeaponDefaults $item $file
    if ($file.BaseName.EndsWith('_loaded')) {
        $unloadedName = $file.BaseName.Substring(0, $file.BaseName.Length - 7) + '_unloaded.png'
        $unloadedPath = Join-Path $file.DirectoryName $unloadedName
        if (Test-Path -LiteralPath $unloadedPath) {
            $item.unloaded_sprite_path = Convert-ToResourcePath $unloadedPath
        }
    }
    $overlays = @(Get-MatchingOverlays $file $weaponFiles $id)
    if ($id -eq 'shotgun' -and $overlays.Count -eq 0) {
        $overlays = @($item.inventory_sprite_path)
    }
    if ($overlays.Count -gt 0) { $item.equipped_sprite_paths = $overlays }
    if ($FirearmOverrides.ContainsKey($id)) { Set-Values $item $FirearmOverrides[$id] }
    if ($MeleeOverrides.ContainsKey($id)) { Set-Values $item $MeleeOverrides[$id] }
    Add-SpecialWeaponValues $item
    $definitions.Add($item)
}

$byId = @{}
foreach ($item in $definitions) {
    if ($byId.ContainsKey($item.id)) {
        throw "Duplicate generated item ID: $($item.id)"
    }
    $byId[$item.id] = $item
}
if ($definitions.Count -lt 120) {
    throw "Catalog generation produced only $($definitions.Count) definitions."
}

$resolvedOutput = [IO.Path]::GetFullPath($OutputRoot)
if (-not $resolvedOutput.StartsWith($ProjectRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to write outside the project workspace: $resolvedOutput"
}
[IO.Directory]::CreateDirectory($resolvedOutput) | Out-Null

if ($Rebuild) {
    Get-ChildItem -LiteralPath $resolvedOutput -File -Filter '*.tres' | ForEach-Object {
        Remove-Item -LiteralPath $_.FullName -Force
    }
}

$encoding = [Text.UTF8Encoding]::new($false)
$createdCount = 0
$preservedCount = 0
foreach ($item in $definitions) {
    $path = Join-Path $resolvedOutput "$($item.id).tres"
    if (-not $Rebuild -and (Test-Path -LiteralPath $path)) {
        $preservedCount++
        continue
    }
    [IO.File]::WriteAllText($path, (Convert-ToTres $item), $encoding)
    $createdCount++
}

Write-Output "Catalog scan found $($definitions.Count) definitions. Created $createdCount and preserved $preservedCount in $resolvedOutput"
