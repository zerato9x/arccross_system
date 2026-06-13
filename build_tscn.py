import re

tscn_path = r"c:\Users\Zerato\OneDrive\Documents\arccross_system\UI\Inventory\InventoryUI.tscn"

with open(tscn_path, "r", encoding="utf-8") as f:
    content = f.read()

# We need to add the ExtResource for InventorySlot.tscn
# Find the last ext_resource
ext_resources = re.findall(r'\[ext_resource.*?\]', content)
last_ext = ext_resources[-1] if ext_resources else ""
new_ext = '[ext_resource type="PackedScene" uid="uid://c83pdxx4xxt01" path="res://UI/Inventory/InventorySlot.tscn" id="slot_scene"]\n'
content = content.replace(last_ext, last_ext + "\n" + new_ext)

# Find where the PaperDollContainer's BodySilhouette ends and the buttons start
body_sil_end = content.find('[node name="Slot_EYES"')

# Find where the RightPanel starts, which is right after the last slot button
right_panel_start = content.find('[node name="RightPanel"')

if body_sil_end == -1 or right_panel_start == -1:
    print("Could not find bounds.")
    exit(1)

eq_data = [
    {"slot": 1, "pos": (25, 105), "tex": "head.png"},
    {"slot": 2, "pos": (25, 25), "tex": "eyes.png"},
    {"slot": 3, "pos": (105, 25), "tex": "mask.png"},
    {"slot": 4, "pos": (185, 25), "tex": ""},
    {"slot": 5, "pos": (25, 185), "tex": "armor.png"},
    {"slot": 6, "pos": (25, 265), "tex": "clothing.png"},
    {"slot": 7, "pos": (280, 25), "tex": "webbing.png"},
    {"slot": 8, "pos": (280, 105), "tex": "backpack.png"},
    {"slot": 9, "pos": (265, 25), "tex": "sidepouch.png"},
    {"slot": 10, "pos": (115, 555), "tex": "pocket_front.png"},
    {"slot": 11, "pos": (355, 500), "tex": "belt.png"},
    {"slot": 12, "pos": (40, 435), "tex": "weapon_2h.png"},
    {"slot": 13, "pos": (25, 345), "tex": "pocket.png"},
    {"slot": 14, "pos": (265, 345), "tex": ""},
]

backpack_positions = [
    (355, 25), (435, 25), (515, 25), (595, 25),
    (355, 105), (460, 105), (560, 105),
    (280, 185), (355, 185), (460, 185), (560, 185),
    (355, 265), (435, 265), (515, 265), (595, 265),
    (355, 345), (435, 345), (515, 345), (595, 345),
    (355, 425), (435, 425), (515, 425), (595, 425)
]

new_nodes = []

new_nodes.append('[node name="EquipmentSlots" type="Control" parent="PanelContainer/MarginContainer/HubTabs/Inventory/PaperDollContainer"]')
new_nodes.append('unique_name_in_owner = true')
new_nodes.append('anchors_preset = 0\n')

# We need to load external textures if they exist. Wait, in .tscn, textures need an ext_resource or sub_resource.
# To make it simple, we can just assign the empty_texture property using ext_resource.
# This means we need to add an ext_resource for every texture!
# Let's generate them.
tex_paths = set([d["tex"] for d in eq_data if d["tex"]])
tex_paths.add("backpack_item_slot.png")

tex_resources = ""
tex_mapping = {}
idx = 100
for tex in tex_paths:
    res_id = f"tex_{idx}"
    tex_resources += f'[ext_resource type="Texture2D" path="res://Asset/UI/{tex}" id="{res_id}"]\n'
    tex_mapping[tex] = res_id
    idx += 1

# Insert tex_resources
content = content.replace(new_ext, new_ext + tex_resources)

for d in eq_data:
    new_nodes.append(f'[node name="Slot_{d["slot"]}" parent="PanelContainer/MarginContainer/HubTabs/Inventory/PaperDollContainer/EquipmentSlots" instance=ExtResource("slot_scene")]')
    new_nodes.append(f'layout_mode = 0')
    new_nodes.append(f'offset_left = {d["pos"][0]}.0')
    new_nodes.append(f'offset_top = {d["pos"][1]}.0')
    new_nodes.append(f'offset_right = {d["pos"][0] + 64}.0')
    new_nodes.append(f'offset_bottom = {d["pos"][1] + 64}.0')
    new_nodes.append(f'equipment_slot = {d["slot"]}')
    if d["tex"]:
        new_nodes.append(f'empty_texture = ExtResource("{tex_mapping[d["tex"]]}")')
    new_nodes.append('')

new_nodes.append('[node name="BackpackSlots" type="Control" parent="PanelContainer/MarginContainer/HubTabs/Inventory/PaperDollContainer"]')
new_nodes.append('unique_name_in_owner = true')
new_nodes.append('anchors_preset = 0\n')

bp_tex_id = tex_mapping["backpack_item_slot.png"]
for i, pos in enumerate(backpack_positions):
    new_nodes.append(f'[node name="BackpackSlot_{i}" parent="PanelContainer/MarginContainer/HubTabs/Inventory/PaperDollContainer/BackpackSlots" instance=ExtResource("slot_scene")]')
    new_nodes.append(f'layout_mode = 0')
    new_nodes.append(f'offset_left = {pos[0]}.0')
    new_nodes.append(f'offset_top = {pos[1]}.0')
    new_nodes.append(f'offset_right = {pos[0] + 64}.0')
    new_nodes.append(f'offset_bottom = {pos[1] + 64}.0')
    new_nodes.append(f'equipment_slot = 0')
    new_nodes.append(f'empty_texture = ExtResource("{bp_tex_id}")')
    new_nodes.append('')

replacement = "\n".join(new_nodes)
final_content = content[:body_sil_end] + replacement + content[right_panel_start:]

with open(tscn_path, "w", encoding="utf-8") as f:
    f.write(final_content)

print("TSCN updated successfully via Python.")
