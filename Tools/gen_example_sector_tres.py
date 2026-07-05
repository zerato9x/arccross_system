#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "WorldCore" / "Maps" / "example_sector.tres"

PATHS = {
    114: "res://Asset/HexTiles/_BIOMES/biome_plains/HEX/grass_tiles/grass_default/Grassland - Painted - V2 Green - Old Riverbed_hex_19.png",
    116: "res://Asset/HexTiles/_BIOMES/biome_plains/HEX/grass_tiles/grass_default/Grassland - Painted - V2 Green - Old Riverbed_hex_5.png",
    117: "res://Asset/HexTiles/_BIOMES/biome_plains/HEX/grass_tiles/grass_default/Grassland - Painted - V2 Green - Old Riverbed_hex_6.png",
    118: "res://Asset/HexTiles/_BIOMES/biome_plains/HEX/grass_tiles/grass_default/Grassland - Painted - V2 Green - Old Riverbed_hex_7.png",
    119: "res://Asset/HexTiles/_BIOMES/biome_plains/HEX/grass_tiles/grass_default/Grassland - Painted - V2 Green - Old Riverbed_hex_8.png",
    120: "res://Asset/HexTiles/_BIOMES/biome_plains/HEX/grass_tiles/grass_default/Grassland - Painted - V2 Green - Old Riverbed_hex_9.png",
    121: "res://Asset/HexTiles/_BIOMES/biome_plains/HEX/grass_tiles/grass_default/Grassland - Painted - green_hex_38.png",
    122: "res://Asset/HexTiles/_BIOMES/biome_plains/HEX/grass_tiles/grass_default/Grassland - Painted - green_hex_39.png",
    123: "res://Asset/HexTiles/_BIOMES/biome_plains/HEX/grass_tiles/grass_default/Grassland - Painted - green_hex_40.png",
}
TERRAIN = {
    (0, 0): 122,
    (1, 0): 121,
    (-1, 0): 120,
    (0, 1): 119,
    (0, -1): 118,
    (1, -1): 117,
    (-1, 1): 116,
    (2, 0): 123,
    (-2, 0): 114,
}
FLORA = {
    (0, 1): "res://Asset/HexTiles/_BIOMES/biome_plains/flora/Shrub A.png",
    (-1, 1): "res://Asset/HexTiles/_BIOMES/biome_plains/flora/Shrub C.png",
}
ROCK = {
    (-1, 0): "res://Asset/HexTiles/_BIOMES/biome_plains/Rocks/Rocky Hill X1A.png",
}
STRUCTURE = {
    (1, 0): "res://Asset/HexTiles/_BIOMES/biome_plains/Structures/Homestead Building Size 2 - A.png",
}
POI = {
    (1, 0): ("example_homestead", "Example Homestead"),
}


def make_entry(coords):
    x, y = coords
    impassable = coords in ROCK
    lines = [
        "{",
        f'"coords": Vector2i({x}, {y}),',
        f'"terrain_sprite_path": "{PATHS[TERRAIN[coords]]}",',
        '"terrain_tile": 0,',
        '"biome": 0,',
        '"biome_pack": "plains",',
        f'"flora_layer": {2 if coords in FLORA else 0},',
        f'"flora_sprite_path": "{FLORA.get(coords, "")}",',
        f'"rock_layer": {2 if coords in ROCK else 0},',
        f'"rock_sprite_path": "{ROCK.get(coords, "")}",',
        f'"structure_layer": {2 if coords in STRUCTURE else 0},',
        f'"structure_sprite_path": "{STRUCTURE.get(coords, "")}",',
        f'"is_poi": {"true" if coords in POI else "false"},',
    ]
    if coords in POI:
        pid, pname = POI[coords]
        lines.extend(
            [
                f'"poi_id": "{pid}",',
                f'"poi_name": "{pname}",',
                '"zone_id": "example_sector",',
                '"hazard_level": 0.5,',
            ]
        )
    else:
        lines.extend(['"poi_id": "",', '"poi_name": "",'])
    lines.extend(
        [
            '"region": 0,',
            '"arm_direction": 0,',
            '"landmark_id": "",',
            '"sleep_anchor": "ground",',
            f'"impassable": {"true" if impassable else "false"},',
            "}",
        ]
    )
    return "\n".join(lines)


DECORATIONS = [
    {
        "coords": "Vector2i(0, 0)",
        "sprite_path": "res://Asset/HexTiles/_BIOMES/biome_plains/flora/Shrub H.png",
        "scale": "Vector2(0.14, 0.14)",
        "offset": "Vector2(72, -28)",
        "layer": 0,
    },
    {
        "coords": "Vector2i(-1, 1)",
        "sprite_path": "res://Asset/HexTiles/_BIOMES/biome_plains/flora/Shrub H.png",
        "scale": "Vector2(0.22, 0.22)",
        "offset": "Vector2(-48, 36)",
        "layer": 0,
    },
    {
        "coords": "Vector2i(2, 0)",
        "sprite_path": "res://Asset/HexTiles/_BIOMES/biome_plains/Infrastructure/Homestead Crates Size1.png",
        "scale": "Vector2(0.16, 0.16)",
        "offset": "Vector2(-64, 18)",
        "layer": 3,
    },
    {
        "coords": "Vector2i(0, -1)",
        "sprite_path": "res://Asset/HexTiles/_BIOMES/biome_plains/flora/Shrub G.png",
        "scale": "Vector2(0.19, 0.19)",
        "offset": "Vector2(0, -148)",
        "layer": 0,
    },
]


def make_decor(item):
    return "\n".join(
        [
            "{",
            f'"coords": {item["coords"]},',
            f'"sprite_path": "{item["sprite_path"]}",',
            f'"scale": {item["scale"]},',
            f'"offset": {item["offset"]},',
            f'"layer": {item["layer"]}',
            "}",
        ]
    )


entries = ",\n".join(make_entry(c) for c in sorted(TERRAIN.keys(), key=lambda t: (t[1], t[0])))
decors = ",\n".join(make_decor(d) for d in DECORATIONS)
content = f"""[gd_resource type="Resource" script_class="AuthoredWorldMap" load_steps=2 format=3]

[ext_resource type="Script" path="res://WorldCore/AuthoredWorldMap.gd" id="1"]

[resource]
script = ExtResource("1")
map_id = "example_sector"
display_name = "Example Sector"
playable_arm = 2
start_coords = Vector2i(0, 0)
core_coords = Vector2i(0, 0)
entries = Array[Dictionary]([{entries}])
decorations = Array[Dictionary]([{decors}])
"""
OUT.write_text(content, encoding="utf-8")
print(f"Wrote {OUT}")
