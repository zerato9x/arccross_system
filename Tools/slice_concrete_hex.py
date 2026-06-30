#!/usr/bin/env python3
"""Slice colony concrete foundation sheets into 512x512 pointy-top hex tiles.

Matches the grass tile format under:
  Asset/HexTiles/_BIOMES/biome_plains/HEX/grass_tiles/

Usage:
  python Tools/slice_concrete_hex.py [image_path ...]

With no arguments, processes the central-core concrete foundation sheets and
writes slices to:
  Asset/HexTiles/_BIOMES/biome_centralcore/HEX/concrete_tiles/
"""

from __future__ import annotations

import os
import sys

try:
    from PIL import Image, ImageDraw
except ImportError:
    print("Pillow is not installed. Please run: pip install Pillow")
    sys.exit(1)

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
REFERENCE_TILE = os.path.join(
    REPO_ROOT,
    "Asset",
    "HexTiles",
    "_BIOMES",
    "biome_plains",
    "HEX",
    "grass_tiles",
    "grass_default",
    "Grassland - Painted - green_hex_40.png",
)
DEFAULT_OUTPUT_DIR = os.path.join(
    REPO_ROOT,
    "Asset",
    "HexTiles",
    "_BIOMES",
    "biome_centralcore",
    "HEX",
    "concrete_tiles",
)
DEFAULT_SOURCES = [
    os.path.join(
        REPO_ROOT,
        "Asset",
        "HexTiles",
        "_BIOMES",
        "biome_centralcore",
        "Colony Infrastructure",
        "Concrete Foundation A.png",
    ),
    os.path.join(
        REPO_ROOT,
        "Asset",
        "HexTiles",
        "_BIOMES",
        "biome_centralcore",
        "Colony Infrastructure",
        "Concrete Foundation B.png",
    ),
]


def tile_size_from_reference(reference_path: str) -> tuple[int, int]:
    if os.path.isfile(reference_path):
        with Image.open(reference_path) as ref:
            return ref.size
    return 512, 512


def create_hex_mask(width: int, height: int) -> Image.Image:
    mask = Image.new("L", (width, height), 0)
    draw = ImageDraw.Draw(mask)
    points = [
        (width / 2, 0),
        (width, height / 4),
        (width, height * 3 / 4),
        (width / 2, height),
        (0, height * 3 / 4),
        (0, height / 4),
    ]
    draw.polygon(points, fill=255)
    return mask


def slice_hex_grid(
    image_path: str,
    output_dir: str,
    tile_width: int,
    tile_height: int,
) -> int:
    img = Image.open(image_path).convert("RGBA")
    img_width, img_height = img.size
    base_name = os.path.splitext(os.path.basename(image_path))[0]
    safe_name = base_name.replace(" ", "_")

    col_spacing = tile_width
    row_spacing = tile_height * 0.75
    cols = int((img_width + (tile_width / 2)) // tile_width)
    rows = int((img_height - tile_height * 0.25) // row_spacing) + 1

    os.makedirs(output_dir, exist_ok=True)
    hex_mask = create_hex_mask(tile_width, tile_height)

    count = 0
    for row in range(rows):
        for col in range(cols):
            offset_x = (tile_width / 2) if (row % 2 != 0) else 0
            x = int(col * col_spacing + offset_x)
            y = int(row * row_spacing)
            if x >= img_width or y >= img_height:
                continue

            tile = img.crop((x, y, x + tile_width, y + tile_height))
            hex_tile = Image.new("RGBA", (tile_width, tile_height), (0, 0, 0, 0))
            hex_tile.paste(tile, (0, 0), mask=hex_mask)
            if not hex_tile.getbbox():
                continue

            out_name = f"{safe_name}_hex_{count}.png"
            hex_tile.save(os.path.join(output_dir, out_name))
            count += 1

    print(
        f"Saved {count} hex tiles from {image_path} "
        f"({img_width}x{img_height}) -> {output_dir}"
    )
    return count


def main(argv: list[str]) -> int:
    tile_width, tile_height = tile_size_from_reference(REFERENCE_TILE)
    print(f"Using reference tile size: {tile_width}x{tile_height}")

    sources = argv if argv else DEFAULT_SOURCES
    total = 0
    for image_path in sources:
        if not os.path.isfile(image_path):
            print(f"Skipping missing file: {image_path}")
            continue
        total += slice_hex_grid(
            image_path,
            DEFAULT_OUTPUT_DIR,
            tile_width,
            tile_height,
        )

    if total == 0:
        print("No tiles were produced.")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
