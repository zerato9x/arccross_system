import re

def update_tscn(file_path):
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # 1. Remove all ext_resource pointing to forestPack
    content = re.sub(r'\[ext_resource[^\]]+path="res://Asset/forestPack/[^\]]+" id="[^"]+"\]\n', '', content)

    # 2. Remove all sub_resource of type TileSetAtlasSource
    content = re.sub(r'\[sub_resource type="TileSetAtlasSource" id="[^"]+"\]\ntexture = ExtResource\([^)]+\)\ntexture_region_size = Vector2i\(\d+, \d+\)\n\d+:\d+/\d+ = \d+\n\n', '', content)

    # 3. Remove the TileSet sub_resource
    content = re.sub(r'\[sub_resource type="TileSet" id="TileSet_3etub"\][\s\S]*?(?=\[node)', '', content)

    # 4. Remove tile_set = SubResource("TileSet_3etub") from HexMapVisualizer
    content = re.sub(r'tile_set = SubResource\("TileSet_3etub"\)\n', '', content)

    # 5. Add the overlay_layer property mapping in HexMapVisualizer
    # Find: script = ExtResource("3_whfra")\nworld_generator = NodePath("../HexWorldGenerator")\n
    hex_map_node = r'(script = ExtResource\("3_whfra"\)\nworld_generator = NodePath\("\.\./HexWorldGenerator"\))'
    content = re.sub(hex_map_node, r'\1\noverlay_layer = NodePath("../HexOverlayVisualizer")', content)

    # 6. Add the new HexOverlayVisualizer node right after HexMapVisualizer
    # We find where PlayerMacroToken starts and insert before it
    player_token_start = r'(\[node name="PlayerMacroToken")'
    overlay_node = '[node name="HexOverlayVisualizer" type="TileMapLayer" parent="."]\n'
    content = re.sub(player_token_start, overlay_node + r'\1', content)

    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(content)

    print("Updated main_world.tscn successfully.")

if __name__ == '__main__':
    update_tscn('WorldCore/main_world.tscn')
