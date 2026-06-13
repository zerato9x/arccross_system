import os

tscn_path = r"c:\Users\Zerato\OneDrive\Documents\arccross_system\UI\Inventory\InventoryUI.tscn"

# Adjusted positions to look like a human shape
eq_data = [
    {"slot": 1, "pos": (150, 20), "tex": "head.png"},       # Head
    {"slot": 2, "pos": (80, 20), "tex": "eyes.png"},        # Eyes
    {"slot": 3, "pos": (220, 20), "tex": "mask.png"},       # Face
    {"slot": 4, "pos": (150, 90), "tex": ""},               # Neck
    {"slot": 5, "pos": (80, 170), "tex": "armor.png"},      # Outer Torso
    {"slot": 6, "pos": (150, 170), "tex": "clothing.png"},  # Inner Torso
    {"slot": 7, "pos": (220, 170), "tex": "webbing.png"},   # Vest
    {"slot": 8, "pos": (290, 170), "tex": "backpack.png"},  # Backpack
    {"slot": 9, "pos": (10, 170), "tex": "sidepouch.png"},  # Arms
    {"slot": 10, "pos": (10, 320), "tex": "pocket_front.png"},# Hands
    {"slot": 11, "pos": (150, 250), "tex": "belt.png"},     # Belt
    {"slot": 12, "pos": (360, 170), "tex": "weapon_2h.png"},# Sling
    {"slot": 13, "pos": (150, 340), "tex": "pocket.png"},   # Legs
    {"slot": 14, "pos": (150, 450), "tex": ""},             # Feet
]

tex_paths = set([d["tex"] for d in eq_data if d["tex"]])

lines = []
lines.append('[gd_scene load_steps=2 format=3 uid="uid://b72xqqy5yyt02"]')
lines.append('')
lines.append('[ext_resource type="Script" path="res://UI/Inventory/InventoryUI.gd" id="1_uigd"]')
lines.append('[ext_resource type="PackedScene" uid="uid://c83pdxx4xxt01" path="res://UI/Inventory/InventorySlot.tscn" id="slot_scene"]')

tex_mapping = {}
idx = 100
for tex in sorted(list(tex_paths)):
    res_id = f"tex_{idx}"
    lines.append(f'[ext_resource type="Texture2D" path="res://Asset/UI/{tex}" id="{res_id}"]')
    tex_mapping[tex] = res_id
    idx += 1

lines.append('')
lines.append('[node name="InventoryUI" type="Control"]')
lines.append('layout_mode = 3')
lines.append('anchors_preset = 15')
lines.append('anchor_right = 1.0')
lines.append('anchor_bottom = 1.0')
lines.append('grow_horizontal = 2')
lines.append('grow_vertical = 2')
lines.append('script = ExtResource("1_uigd")')
lines.append('')
lines.append('[node name="PanelContainer" type="PanelContainer" parent="."]')
lines.append('layout_mode = 1')
lines.append('anchors_preset = 15')
lines.append('anchor_right = 1.0')
lines.append('anchor_bottom = 1.0')
lines.append('grow_horizontal = 2')
lines.append('grow_vertical = 2')
lines.append('')
lines.append('[node name="MarginContainer" type="MarginContainer" parent="PanelContainer"]')
lines.append('layout_mode = 2')
lines.append('theme_override_constants/margin_left = 24')
lines.append('theme_override_constants/margin_top = 20')
lines.append('theme_override_constants/margin_right = 24')
lines.append('theme_override_constants/margin_bottom = 20')
lines.append('')
lines.append('[node name="HubTabs" type="TabContainer" parent="PanelContainer/MarginContainer"]')
lines.append('unique_name_in_owner = true')
lines.append('layout_mode = 2')
lines.append('')
lines.append('[node name="Inventory" type="HBoxContainer" parent="PanelContainer/MarginContainer/HubTabs"]')
lines.append('layout_mode = 2')
lines.append('theme_override_constants/separation = 40')
lines.append('')
lines.append('[node name="PaperDollContainer" type="Control" parent="PanelContainer/MarginContainer/HubTabs/Inventory"]')
lines.append('unique_name_in_owner = true')
lines.append('custom_minimum_size = Vector2(430, 650)')
lines.append('layout_mode = 2')
lines.append('size_flags_horizontal = 0')
lines.append('size_flags_vertical = 4')
lines.append('')
lines.append('[node name="EquipmentSlots" type="Control" parent="PanelContainer/MarginContainer/HubTabs/Inventory/PaperDollContainer"]')
lines.append('unique_name_in_owner = true')
lines.append('anchors_preset = 0')
lines.append('')

for d in eq_data:
    lines.append(f'[node name="Slot_{d["slot"]}" parent="PanelContainer/MarginContainer/HubTabs/Inventory/PaperDollContainer/EquipmentSlots" instance=ExtResource("slot_scene")]')
    lines.append('layout_mode = 0')
    lines.append(f'offset_left = {d["pos"][0]}.0')
    lines.append(f'offset_top = {d["pos"][1]}.0')
    lines.append(f'offset_right = {d["pos"][0] + 64}.0')
    lines.append(f'offset_bottom = {d["pos"][1] + 64}.0')
    lines.append(f'equipment_slot = {d["slot"]}')
    if d["tex"]:
        lines.append(f'empty_texture = ExtResource("{tex_mapping[d["tex"]]}")')
    lines.append('')

# Right area: Item Grids and Ground list
lines.append('[node name="RightPanel" type="VBoxContainer" parent="PanelContainer/MarginContainer/HubTabs/Inventory"]')
lines.append('layout_mode = 2')
lines.append('size_flags_horizontal = 3')
lines.append('theme_override_constants/separation = 10')
lines.append('')
lines.append('[node name="HeaderBox" type="HBoxContainer" parent="PanelContainer/MarginContainer/HubTabs/Inventory/RightPanel"]')
lines.append('layout_mode = 2')
lines.append('theme_override_constants/separation = 20')
lines.append('')
lines.append('[node name="TitleLabel" type="Label" parent="PanelContainer/MarginContainer/HubTabs/Inventory/RightPanel/HeaderBox"]')
lines.append('layout_mode = 2')
lines.append('theme_override_font_sizes/font_size = 24')
lines.append('text = "INVENTORY"')
lines.append('')
lines.append('[node name="StatsLabel" type="Label" parent="PanelContainer/MarginContainer/HubTabs/Inventory/RightPanel/HeaderBox"]')
lines.append('unique_name_in_owner = true')
lines.append('layout_mode = 2')
lines.append('size_flags_horizontal = 3')
lines.append('text = "Capacity: 0 / 0"')
lines.append('horizontal_alignment = 2')
lines.append('')
lines.append('[node name="SpillWarningLabel" type="Label" parent="PanelContainer/MarginContainer/HubTabs/Inventory/RightPanel"]')
lines.append('unique_name_in_owner = true')
lines.append('visible = false')
lines.append('layout_mode = 2')
lines.append('theme_override_colors/font_color = Color(0.85, 0.2, 0.2, 1)')
lines.append('text = "WARNING: Inventory Full. Excess items will spill to ground!"')
lines.append('horizontal_alignment = 1')
lines.append('')
lines.append('[node name="HSeparator" type="HSeparator" parent="PanelContainer/MarginContainer/HubTabs/Inventory/RightPanel"]')
lines.append('layout_mode = 2')
lines.append('')
lines.append('[node name="Splits" type="HBoxContainer" parent="PanelContainer/MarginContainer/HubTabs/Inventory/RightPanel"]')
lines.append('layout_mode = 2')
lines.append('size_flags_vertical = 3')
lines.append('theme_override_constants/separation = 20')
lines.append('')
lines.append('[node name="CapacityScroll" type="ScrollContainer" parent="PanelContainer/MarginContainer/HubTabs/Inventory/RightPanel/Splits"]')
lines.append('layout_mode = 2')
lines.append('size_flags_horizontal = 3')
lines.append('size_flags_stretch_ratio = 1.5')
lines.append('')
lines.append('[node name="DynamicCapacityGrids" type="VBoxContainer" parent="PanelContainer/MarginContainer/HubTabs/Inventory/RightPanel/Splits/CapacityScroll"]')
lines.append('unique_name_in_owner = true')
lines.append('layout_mode = 2')
lines.append('size_flags_horizontal = 3')
lines.append('size_flags_vertical = 3')
lines.append('theme_override_constants/separation = 4')
lines.append('')
lines.append('[node name="GroundScroll" type="ScrollContainer" parent="PanelContainer/MarginContainer/HubTabs/Inventory/RightPanel/Splits"]')
lines.append('layout_mode = 2')
lines.append('size_flags_horizontal = 3')
lines.append('')
lines.append('[node name="ListsVBox" type="VBoxContainer" parent="PanelContainer/MarginContainer/HubTabs/Inventory/RightPanel/Splits/GroundScroll"]')
lines.append('layout_mode = 2')
lines.append('size_flags_horizontal = 3')
lines.append('size_flags_vertical = 3')
lines.append('theme_override_constants/separation = 14')
lines.append('')
lines.append('[node name="GroundHeader" type="Label" parent="PanelContainer/MarginContainer/HubTabs/Inventory/RightPanel/Splits/GroundScroll/ListsVBox"]')
lines.append('layout_mode = 2')
lines.append('theme_override_colors/font_color = Color(0, 1, 1, 1)')
lines.append('theme_override_font_sizes/font_size = 18')
lines.append('text = "GROUND"')
lines.append('')
lines.append('[node name="GroundList" type="VBoxContainer" parent="PanelContainer/MarginContainer/HubTabs/Inventory/RightPanel/Splits/GroundScroll/ListsVBox"]')
lines.append('unique_name_in_owner = true')
lines.append('layout_mode = 2')
lines.append('theme_override_constants/separation = 6')
lines.append('')
lines.append('[node name="CloseButton" type="Button" parent="PanelContainer/MarginContainer/HubTabs/Inventory/RightPanel"]')
lines.append('unique_name_in_owner = true')
lines.append('custom_minimum_size = Vector2(0, 40)')
lines.append('layout_mode = 2')
lines.append('text = "CLOSE"')
lines.append('')

with open(tscn_path, "w", encoding="utf-8") as f:
    f.write("\n".join(lines))

print("TSCN fully generated successfully via Python.")
