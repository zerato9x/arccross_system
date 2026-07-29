"""Bake native-resolution six-neighbor road overlay families.

The source materials are high-resolution authored swatches. Geometry is baked
at 4x resolution and downsampled into the project's 512px pointy hex, keeping
all six edge sockets pixel-stable without the blocky procedural look of V1.
"""

from __future__ import annotations

import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = PROJECT_ROOT / "Asset" / "HexTiles" / "_SOURCE" / "roads"
SOURCES = {
    "paved": SOURCE_ROOT / "road_material_asphalt_v2.png",
    "dirt": SOURCE_ROOT / "road_material_dirt_v2.png",
}
OUTPUT_ROOT = PROJECT_ROOT / "Asset" / "HexTiles" / "_OVERLAYS" / "roads"
SIZE = 512
SUPERSAMPLE = 4
WORK_SIZE = SIZE * SUPERSAMPLE
CENTER = (WORK_SIZE // 2, WORK_SIZE // 2)
SOCKETS = [
    (WORK_SIZE, WORK_SIZE // 2),
    (WORK_SIZE * 3 // 4, WORK_SIZE // 8),
    (WORK_SIZE // 4, WORK_SIZE // 8),
    (0, WORK_SIZE // 2),
    (WORK_SIZE // 4, WORK_SIZE * 7 // 8),
    (WORK_SIZE * 3 // 4, WORK_SIZE * 7 // 8),
]
HEX_POLYGON = [
    (WORK_SIZE // 2, 0),
    (WORK_SIZE, WORK_SIZE // 4),
    (WORK_SIZE, WORK_SIZE * 3 // 4),
    (WORK_SIZE // 2, WORK_SIZE),
    (0, WORK_SIZE * 3 // 4),
    (0, WORK_SIZE // 4),
]


def _material(path: Path, contrast: float, brightness: float) -> Image.Image:
    source = Image.open(path).convert("RGB")
    side = min(source.size)
    left = (source.width - side) // 2
    top = (source.height - side) // 2
    source = source.crop((left, top, left + side, top + side))
    source = ImageEnhance.Contrast(source).enhance(contrast)
    source = ImageEnhance.Brightness(source).enhance(brightness)
    return source.resize((WORK_SIZE, WORK_SIZE), Image.Resampling.LANCZOS).convert("RGBA")


def _hex_clip() -> Image.Image:
    clip = Image.new("L", (WORK_SIZE, WORK_SIZE), 0)
    ImageDraw.Draw(clip).polygon(HEX_POLYGON, fill=255)
    return clip


def _network_mask(mask_value: int, width: int, center_radius: int | None = None) -> Image.Image:
    mask = Image.new("L", (WORK_SIZE, WORK_SIZE), 0)
    if mask_value == 0:
        return mask
    draw = ImageDraw.Draw(mask)
    for index, socket in enumerate(SOCKETS):
        if mask_value & (1 << index):
            draw.line([CENTER, socket], fill=255, width=width * SUPERSAMPLE)
    radius = (center_radius if center_radius is not None else width // 2) * SUPERSAMPLE
    draw.ellipse(
        (CENTER[0] - radius, CENTER[1] - radius, CENTER[0] + radius, CENTER[1] + radius),
        fill=255,
    )
    return Image.composite(mask, Image.new("L", mask.size, 0), _hex_clip())


def _solid_layer(color: tuple[int, int, int, int], mask: Image.Image) -> Image.Image:
    return Image.composite(
        Image.new("RGBA", (WORK_SIZE, WORK_SIZE), color),
        Image.new("RGBA", (WORK_SIZE, WORK_SIZE), (0, 0, 0, 0)),
        mask,
    )


def _textured_layer(texture: Image.Image, mask: Image.Image) -> Image.Image:
    return Image.composite(
        texture,
        Image.new("RGBA", (WORK_SIZE, WORK_SIZE), (0, 0, 0, 0)),
        mask,
    )


def _weathering(mask_value: int, surface_mask: Image.Image, family: str) -> Image.Image:
    layer = Image.new("RGBA", (WORK_SIZE, WORK_SIZE), (0, 0, 0, 0))
    if mask_value == 0:
        return layer
    draw = ImageDraw.Draw(layer)
    rng = random.Random(f"road-v2:{family}:{mask_value}")
    count = 11 if family == "paved" else 7
    for _ in range(count):
        x = rng.randrange(150, 363) * SUPERSAMPLE
        y = rng.randrange(145, 368) * SUPERSAMPLE
        points = [(x, y)]
        for _segment in range(rng.randrange(2, 5)):
            x += rng.randrange(-14, 15) * SUPERSAMPLE
            y += rng.randrange(5, 17) * SUPERSAMPLE
            points.append((x, y))
        color = (23, 20, 17, 80) if family == "paved" else (45, 35, 25, 48)
        draw.line(points, fill=color, width=SUPERSAMPLE * (2 if family == "paved" else 1))
    alpha = Image.composite(layer.getchannel("A"), Image.new("L", layer.size, 0), surface_mask)
    layer.putalpha(alpha)
    return layer


def _build_paved(mask_value: int, asphalt: Image.Image) -> Image.Image:
    shoulder = _network_mask(mask_value, 176, 88)
    curb = _network_mask(mask_value, 154, 77)
    surface = _network_mask(mask_value, 136, 68)
    output = Image.new("RGBA", (WORK_SIZE, WORK_SIZE), (0, 0, 0, 0))
    output.alpha_composite(_solid_layer((72, 65, 53, 150), shoulder))
    output.alpha_composite(_solid_layer((137, 128, 112, 238), curb))
    output.alpha_composite(_textured_layer(asphalt, surface))
    output.alpha_composite(_weathering(mask_value, surface, "paved"))
    return output.resize((SIZE, SIZE), Image.Resampling.LANCZOS)


def _build_dirt(mask_value: int, dirt: Image.Image) -> Image.Image:
    shoulder = _network_mask(mask_value, 154, 77)
    surface = _network_mask(mask_value, 132, 66)
    output = Image.new("RGBA", (WORK_SIZE, WORK_SIZE), (0, 0, 0, 0))
    output.alpha_composite(_solid_layer((83, 72, 50, 105), shoulder))
    output.alpha_composite(_textured_layer(dirt, surface))
    output.alpha_composite(_weathering(mask_value, surface, "dirt"))
    return output.resize((SIZE, SIZE), Image.Resampling.LANCZOS)


def main() -> int:
    missing = [str(path) for path in SOURCES.values() if not path.exists()]
    if missing:
        raise SystemExit("Missing road material source(s): " + ", ".join(missing))
    asphalt = _material(SOURCES["paved"], 0.82, 0.82)
    dirt = _material(SOURCES["dirt"], 0.82, 0.78)
    paved_output = OUTPUT_ROOT
    dirt_output = OUTPUT_ROOT / "dirt"
    paved_output.mkdir(parents=True, exist_ok=True)
    dirt_output.mkdir(parents=True, exist_ok=True)
    for mask_value in range(64):
        _build_paved(mask_value, asphalt).save(
            paved_output / f"road_mask_{mask_value:02d}.png", optimize=True
        )
        _build_dirt(mask_value, dirt).save(
            dirt_output / f"dirt_road_mask_{mask_value:02d}.png", optimize=True
        )
    print(
        "[RoadHexOverlayBuilder] Wrote 128 supersampled 512x512 overlays "
        f"to {OUTPUT_ROOT}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
