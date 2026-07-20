from __future__ import annotations

from pathlib import Path
from typing import Callable

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "Asset" / "UI" / "HUD"

# Keep in sync with PresentationCore/HUDAssetLibrary.gd amber scheme (default).
# Cyan scheme remains selectable at runtime via GameSettings.hud_scheme.
PALETTE = {
    "transparent": (0, 0, 0, 0),
    "back": (11, 13, 11, 214),
    "back_dark": (21, 23, 17, 236),
    "grid": (90, 74, 40, 90),
    "teal": (214, 154, 67, 255),  # #d69a43 amber info/normal
    "teal_dim": (138, 96, 34, 255),
    "teal_ghost": (214, 154, 67, 76),
    "white": (232, 220, 192, 255),  # #e8dcc0 text
    "white_dim": (142, 139, 120, 255),  # #8e8b78 muted
    "amber": (224, 178, 74, 255),  # #e0b24a caution
    "amber_dim": (138, 96, 34, 255),
    "crimson": (185, 73, 62, 255),  # #b9493e critical
    "crimson_dim": (126, 28, 38, 255),
    "magenta": (179, 91, 184, 255),  # #b35bb8 anomaly
    "black": (0, 0, 0, 255),
}


def canvas(size: tuple[int, int]) -> Image.Image:
    return Image.new("RGBA", size, PALETTE["transparent"])


def save(img: Image.Image, path: str) -> None:
    target = OUT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    img.save(target)


def draw_grid(draw: ImageDraw.ImageDraw, size: tuple[int, int], color: tuple[int, int, int, int]) -> None:
    width, height = size
    for x in range(8, width, 8):
        draw.line((x, 0, x, height), fill=color, width=1)
    for y in range(8, height, 8):
        draw.line((0, y, width, y), fill=color, width=1)


def draw_corner_brackets(draw: ImageDraw.ImageDraw, size: tuple[int, int], color: tuple[int, int, int, int]) -> None:
    width, height = size
    length = min(width, height) // 4
    margin = 3
    points = [
        ((margin, margin), (margin + length, margin)),
        ((margin, margin), (margin, margin + length)),
        ((width - margin - 1, margin), (width - margin - length - 1, margin)),
        ((width - margin - 1, margin), (width - margin - 1, margin + length)),
        ((margin, height - margin - 1), (margin + length, height - margin - 1)),
        ((margin, height - margin - 1), (margin, height - margin - length - 1)),
        ((width - margin - 1, height - margin - 1), (width - margin - length - 1, height - margin - 1)),
        ((width - margin - 1, height - margin - 1), (width - margin - 1, height - margin - length - 1)),
    ]
    for start, end in points:
        draw.line((*start, *end), fill=color, width=2)


def panel(path: str, accent: tuple[int, int, int, int], size: tuple[int, int] = (64, 64)) -> None:
    """Solid cyber plate: dark teal fill, faint grid, crisp border + brackets."""
    img = canvas(size)
    draw = ImageDraw.Draw(img)
    width, height = size
    # Solid plate fill — faint grid stays local to the 64px asset (sprites),
    # not something we nine-slice across fullscreen inventory shells.
    draw.rectangle((5, 5, width - 6, height - 6), fill=(4, 10, 12, 245), outline=accent, width=2)
    draw_grid(draw, size, (30, 72, 76, 40))
    draw.rectangle((9, 9, width - 10, height - 10), outline=(*accent[:3], 70), width=1)
    draw_corner_brackets(draw, size, accent)
    save(img, path)


def button(path: str, accent: tuple[int, int, int, int], fill: tuple[int, int, int, int], disabled: bool = False) -> None:
    img = canvas((64, 24))
    draw = ImageDraw.Draw(img)
    color = PALETTE["white_dim"] if disabled else accent
    draw.rectangle((1, 1, 62, 22), fill=fill, outline=PALETTE["back_dark"], width=1)
    draw.line((5, 3, 58, 3), fill=color, width=1)
    draw.line((5, 20, 58, 20), fill=(*color[:3], 120), width=1)
    draw.polygon([(1, 1), (10, 1), (1, 10)], fill=(*color[:3], 70))
    draw.polygon([(62, 22), (53, 22), (62, 13)], fill=(*color[:3], 70))
    save(img, path)


def bar_frame(path: str, size: tuple[int, int]) -> None:
    img = canvas(size)
    draw = ImageDraw.Draw(img)
    width, height = size
    draw.rectangle((0, 0, width - 1, height - 1), fill=PALETTE["back_dark"], outline=PALETTE["teal_dim"])
    draw.rectangle((3, 3, width - 4, height - 4), fill=(0, 0, 0, 0), outline=(60, 110, 112, 160))
    for x in range(12, width - 6, 12):
        draw.line((x, 3, x, height - 4), fill=(70, 110, 110, 90), width=1)
    save(img, path)


def bar_fill(path: str, color: tuple[int, int, int, int], size: tuple[int, int] = (96, 8)) -> None:
    img = canvas(size)
    draw = ImageDraw.Draw(img)
    width, height = size
    draw.rectangle((0, 0, width - 1, height - 1), fill=(*color[:3], 218))
    draw.line((0, 0, width - 1, 0), fill=(*color[:3], 255), width=1)
    draw.line((0, height - 1, width - 1, height - 1), fill=(*color[:3], 110), width=1)
    for x in range(7, width, 8):
        draw.line((x, 1, x, height - 2), fill=(0, 0, 0, 58), width=1)
    save(img, path)


def icon_base() -> tuple[Image.Image, ImageDraw.ImageDraw]:
    img = canvas((32, 32))
    draw = ImageDraw.Draw(img)
    draw.rectangle((1, 1, 30, 30), fill=(2, 7, 8, 188), outline=(32, 122, 130, 170), width=1)
    return img, draw


def icon(path: str, draw_fn: Callable[[ImageDraw.ImageDraw], None], color: tuple[int, int, int, int] = PALETTE["teal"]) -> None:
    img, draw = icon_base()
    draw_fn(draw)
    draw_corner_brackets(draw, (32, 32), (*color[:3], 165))
    save(img, path)


def draw_drop(draw: ImageDraw.ImageDraw, color: tuple[int, int, int, int]) -> None:
    draw.polygon([(16, 5), (24, 17), (21, 25), (16, 28), (11, 25), (8, 17)], fill=(*color[:3], 70), outline=color)
    draw.line((14, 12, 19, 22), fill=(*color[:3], 180), width=1)


def draw_flame(draw: ImageDraw.ImageDraw, color: tuple[int, int, int, int]) -> None:
    draw.polygon([(17, 4), (23, 14), (21, 25), (16, 28), (10, 25), (8, 17), (13, 11), (14, 17)], outline=color, fill=(*color[:3], 70))
    draw.polygon([(16, 13), (20, 20), (16, 25), (12, 20)], outline=PALETTE["amber"], fill=(244, 181, 64, 80))


def draw_bone(draw: ImageDraw.ImageDraw, color: tuple[int, int, int, int]) -> None:
    draw.line((9, 22, 22, 9), fill=color, width=3)
    draw.ellipse((5, 19, 12, 26), outline=color, width=2)
    draw.ellipse((20, 6, 27, 13), outline=color, width=2)
    draw.line((13, 16, 19, 22), fill=PALETTE["crimson"], width=1)


def draw_crosshair(draw: ImageDraw.ImageDraw, color: tuple[int, int, int, int]) -> None:
    draw.ellipse((8, 8, 23, 23), outline=color, width=2)
    draw.line((16, 5, 16, 12), fill=color, width=1)
    draw.line((16, 20, 16, 27), fill=color, width=1)
    draw.line((5, 16, 12, 16), fill=color, width=1)
    draw.line((20, 16, 27, 16), fill=color, width=1)


def draw_arrow(draw: ImageDraw.ImageDraw, color: tuple[int, int, int, int], reverse: bool = False) -> None:
    if reverse:
        draw.line((22, 8, 11, 19), fill=color, width=3)
        draw.polygon([(10, 20), (10, 13), (17, 20)], fill=color)
    else:
        draw.line((10, 22, 21, 11), fill=color, width=3)
        draw.polygon([(22, 10), (22, 17), (15, 10)], fill=color)


def draw_medical_limb(path: str, kind: str, accent: tuple[int, int, int, int]) -> None:
    img = canvas((64, 64))
    draw = ImageDraw.Draw(img)
    draw.rectangle((2, 2, 61, 61), fill=(3, 8, 10, 178), outline=(*accent[:3], 120), width=1)
    draw_grid(draw, (64, 64), (30, 72, 76, 64))
    if kind == "head":
        draw.ellipse((22, 9, 42, 30), outline=accent, width=2)
        draw.line((27, 31, 37, 31), fill=accent, width=2)
        draw.line((30, 33, 34, 44), fill=accent, width=2)
    elif kind == "upper_torso":
        draw.polygon([(22, 12), (42, 12), (48, 38), (16, 38)], outline=accent, fill=(*accent[:3], 42))
        draw.line((32, 13, 32, 38), fill=(*accent[:3], 180), width=1)
    elif kind == "lower_torso":
        draw.polygon([(20, 23), (44, 23), (40, 48), (24, 48)], outline=accent, fill=(*accent[:3], 42))
        draw.line((25, 34, 39, 34), fill=(*accent[:3], 180), width=1)
    elif kind == "left_arm":
        draw.polygon([(39, 12), (48, 15), (34, 52), (25, 49)], outline=accent, fill=(*accent[:3], 42))
        draw.line((36, 27, 28, 49), fill=(*accent[:3], 180), width=1)
    elif kind == "right_arm":
        draw.polygon([(25, 12), (16, 15), (30, 52), (39, 49)], outline=accent, fill=(*accent[:3], 42))
        draw.line((28, 27, 36, 49), fill=(*accent[:3], 180), width=1)
    elif kind == "left_leg":
        draw.polygon([(35, 12), (45, 13), (42, 56), (31, 56)], outline=accent, fill=(*accent[:3], 42))
        draw.line((38, 24, 35, 55), fill=(*accent[:3], 180), width=1)
    elif kind == "right_leg":
        draw.polygon([(29, 12), (19, 13), (22, 56), (33, 56)], outline=accent, fill=(*accent[:3], 42))
        draw.line((26, 24, 29, 55), fill=(*accent[:3], 180), width=1)
    draw_corner_brackets(draw, (64, 64), (*accent[:3], 165))
    save(img, path)


def draw_state_badge(path: str, accent: tuple[int, int, int, int], mark: str) -> None:
    img = canvas((32, 32))
    draw = ImageDraw.Draw(img)
    draw.rectangle((2, 2, 29, 29), fill=(2, 7, 8, 206), outline=accent, width=2)
    if mark == "stable":
        draw.line((8, 17, 14, 23, 24, 9), fill=accent, width=3)
    elif mark == "damaged":
        draw.line((8, 22, 24, 8), fill=accent, width=3)
        draw.line((16, 8, 16, 24), fill=accent, width=2)
    elif mark == "critical":
        draw.polygon([(16, 5), (27, 26), (5, 26)], outline=accent, fill=(*accent[:3], 62))
        draw.line((16, 12, 16, 19), fill=accent, width=2)
        draw.point((16, 23), fill=accent)
    elif mark == "destroyed":
        draw.line((9, 9, 23, 23), fill=accent, width=3)
        draw.line((23, 9, 9, 23), fill=accent, width=3)
    save(img, path)


def controls() -> None:
    for name, on, accent in [
        ("toggle_off", False, PALETTE["white_dim"]),
        ("toggle_on", True, PALETTE["teal"]),
    ]:
        img = canvas((48, 24))
        draw = ImageDraw.Draw(img)
        draw.rectangle((2, 5, 45, 18), fill=PALETTE["back_dark"], outline=accent, width=2)
        knob_x = 29 if on else 5
        draw.rectangle((knob_x, 7, knob_x + 12, 16), fill=accent)
        save(img, f"menus/{name}_48x24.png")

    for name, checked in [("checkbox_off", False), ("checkbox_on", True)]:
        img = canvas((24, 24))
        draw = ImageDraw.Draw(img)
        draw.rectangle((3, 3, 20, 20), fill=PALETTE["back_dark"], outline=PALETTE["teal"], width=2)
        if checked:
            draw.line((7, 12, 11, 16, 18, 7), fill=PALETTE["teal"], width=3)
        save(img, f"menus/{name}_24.png")

    img = canvas((96, 12))
    draw = ImageDraw.Draw(img)
    draw.rectangle((2, 4, 93, 7), fill=PALETTE["back_dark"], outline=PALETTE["teal_dim"], width=1)
    draw.line((2, 5, 93, 5), fill=PALETTE["teal_ghost"], width=1)
    save(img, "menus/slider_track_96x12.png")

    img = canvas((16, 16))
    draw = ImageDraw.Draw(img)
    draw.rectangle((3, 2, 12, 13), fill=PALETTE["teal"], outline=PALETTE["white"], width=1)
    save(img, "menus/slider_knob_16.png")

    for name, active in [("tab_idle", False), ("tab_active", True)]:
        img = canvas((64, 24))
        draw = ImageDraw.Draw(img)
        accent = PALETTE["teal"] if active else PALETTE["teal_dim"]
        fill = (4, 12, 14, 226) if active else (2, 7, 8, 186)
        draw.polygon([(3, 22), (3, 6), (9, 2), (61, 2), (61, 22)], fill=fill, outline=accent)
        draw.line((8, 21, 58, 21), fill=(*accent[:3], 180), width=1)
        save(img, f"menus/{name}_64x24.png")

    img = canvas((16, 16))
    draw = ImageDraw.Draw(img)
    draw.polygon([(4, 6), (12, 6), (8, 11)], fill=PALETTE["teal"])
    save(img, "menus/dropdown_arrow_16.png")


def overlays() -> None:
    img = canvas((16, 16))
    draw = ImageDraw.Draw(img)
    draw.line((0, 0, 15, 0), fill=(255, 255, 255, 24), width=1)
    draw.line((0, 8, 15, 8), fill=(0, 0, 0, 42), width=1)
    save(img, "overlays/scanline_tile_16.png")

    for name, accent in [
        ("warning_vignette_128x72", PALETTE["amber"]),
        ("critical_vignette_128x72", PALETTE["crimson"]),
        ("anomaly_vignette_128x72", PALETTE["magenta"]),
    ]:
        img = canvas((128, 72))
        draw = ImageDraw.Draw(img)
        for i in range(0, 24):
            alpha = max(0, 72 - i * 3)
            draw.rectangle((i, i, 127 - i, 71 - i), outline=(*accent[:3], alpha), width=1)
        draw_corner_brackets(draw, (128, 72), (*accent[:3], 190))
        save(img, f"overlays/{name}.png")


def preview() -> None:
    icons = sorted((OUT / "icons").rglob("*.png"))[:48]
    img = Image.new("RGBA", (512, 384), (3, 8, 10, 255))
    draw = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype(str(ROOT / "Asset" / "VCR_OSD_MONO_1.001.ttf"), 12)
    except OSError:
        font = ImageFont.load_default()
    draw.text((16, 12), "ARCCROSS HUD CORE ASSET PACK", fill=PALETTE["teal"], font=font)
    draw.text((16, 30), "frames / bars / status / combat / medical / menus", fill=PALETTE["white_dim"], font=font)
    samples = [
        "frames/panel_neutral_64.png",
        "frames/panel_warning_64.png",
        "frames/panel_critical_64.png",
        "frames/panel_anomaly_64.png",
        "bars/bar_frame_96x12.png",
        "bars/bar_fill_health_96x8.png",
        "bars/bar_fill_blood_96x8.png",
        "menus/toggle_on_48x24.png",
        "menus/checkbox_on_24.png",
        "medical/limb_head_64.png",
        "medical/limb_upper_torso_64.png",
        "medical/limb_left_arm_64.png",
        "medical/limb_right_leg_64.png",
    ]
    x = 16
    y = 56
    for item in samples:
        sample = Image.open(OUT / item).convert("RGBA")
        img.alpha_composite(sample, (x, y))
        x += sample.width + 12
        if x > 430:
            x = 16
            y += 76
    y = 224
    x = 16
    for path in icons:
        icon_img = Image.open(path).convert("RGBA")
        img.alpha_composite(icon_img, (x, y))
        x += 40
        if x > 464:
            x = 16
            y += 40
    save(img, "hud_asset_preview.png")


def main() -> None:
    panel("frames/panel_neutral_64.png", PALETTE["teal"])
    panel("frames/panel_warning_64.png", PALETTE["amber"])
    panel("frames/panel_critical_64.png", PALETTE["crimson"])
    panel("frames/panel_anomaly_64.png", PALETTE["magenta"])
    button("frames/button_idle_64x24.png", PALETTE["teal_dim"], (3, 10, 12, 220))
    button("frames/button_hover_64x24.png", PALETTE["teal"], (4, 18, 20, 230))
    button("frames/button_active_64x24.png", PALETTE["amber"], (24, 17, 8, 230))
    button("frames/button_disabled_64x24.png", PALETTE["white_dim"], (4, 6, 7, 172), disabled=True)

    bar_frame("bars/bar_frame_96x12.png", (96, 12))
    bar_frame("bars/bar_frame_thin_96x8.png", (96, 8))
    bar_fill("bars/bar_fill_health_96x8.png", PALETTE["teal"])
    bar_fill("bars/bar_fill_blood_96x8.png", PALETTE["crimson"])
    bar_fill("bars/bar_fill_ap_96x8.png", PALETTE["amber"])
    bar_fill("bars/bar_fill_stance_96x8.png", PALETTE["white"])
    bar_fill("bars/bar_fill_warning_96x8.png", PALETTE["amber"])
    bar_fill("bars/bar_fill_critical_96x8.png", PALETTE["crimson"])
    bar_fill("bars/bar_fill_anomaly_96x8.png", PALETTE["magenta"])

    status_icons: dict[str, tuple[tuple[int, int, int, int], Callable[[ImageDraw.ImageDraw], None]]] = {
        "ap": (PALETTE["amber"], lambda d: (d.line((9, 21, 16, 6, 23, 21), fill=PALETTE["amber"], width=3), d.line((12, 16, 20, 16), fill=PALETTE["amber"], width=2))),
        "blood": (PALETTE["crimson"], lambda d: draw_drop(d, PALETTE["crimson"])),
        "hunger": (PALETTE["amber"], lambda d: (d.arc((7, 7, 24, 24), 20, 330, fill=PALETTE["amber"], width=3), d.line((22, 6, 22, 26), fill=PALETTE["amber"], width=2), d.line((25, 6, 25, 26), fill=PALETTE["amber"], width=2))),
        "thirst": (PALETTE["teal"], lambda d: draw_drop(d, PALETTE["teal"])),
        "fatigue": (PALETTE["white_dim"], lambda d: (d.line((7, 20, 13, 13, 19, 20, 25, 13), fill=PALETTE["white_dim"], width=2), d.line((8, 25, 24, 25), fill=PALETTE["white_dim"], width=2))),
        "temperature": (PALETTE["teal"], lambda d: (d.rounded_rectangle((13, 5, 19, 23), radius=3, outline=PALETTE["teal"], width=2), d.ellipse((10, 20, 22, 28), outline=PALETTE["teal"], width=2))),
        "morale": (PALETTE["white"], lambda d: (d.ellipse((9, 8, 23, 22), outline=PALETTE["white"], width=2), d.line((10, 24, 22, 24), fill=PALETTE["white"], width=2))),
        "stance": (PALETTE["teal"], lambda d: (d.line((16, 6, 16, 25), fill=PALETTE["teal"], width=3), d.line((9, 14, 23, 14), fill=PALETTE["teal"], width=3), d.line((10, 26, 22, 26), fill=PALETTE["teal"], width=2))),
        "kinetic": (PALETTE["amber"], lambda d: (d.arc((7, 9, 25, 27), 190, 350, fill=PALETTE["amber"], width=2), d.polygon([(24, 18), (28, 14), (27, 21)], fill=PALETTE["amber"]))),
        "time": (PALETTE["teal"], lambda d: (d.ellipse((7, 7, 25, 25), outline=PALETTE["teal"], width=2), d.line((16, 16, 16, 9), fill=PALETTE["teal"], width=2), d.line((16, 16, 22, 19), fill=PALETTE["teal"], width=2))),
        "location": (PALETTE["teal"], lambda d: (d.polygon([(16, 5), (25, 13), (16, 28), (7, 13)], outline=PALETTE["teal"], fill=(72, 222, 220, 45)), d.ellipse((13, 11, 19, 17), outline=PALETTE["teal"], width=2))),
        "warning": (PALETTE["amber"], lambda d: (d.polygon([(16, 5), (27, 26), (5, 26)], outline=PALETTE["amber"], fill=(244, 181, 64, 58)), d.line((16, 12, 16, 20), fill=PALETTE["amber"], width=2))),
        "bleeding": (PALETTE["crimson"], lambda d: (draw_drop(d, PALETTE["crimson"]), d.line((21, 8, 25, 5), fill=PALETTE["crimson"], width=2))),
        "fracture": (PALETTE["white"], lambda d: draw_bone(d, PALETTE["white"])),
        "burn": (PALETTE["amber"], lambda d: draw_flame(d, PALETTE["amber"])),
        "organ": (PALETTE["crimson"], lambda d: (d.ellipse((8, 10, 17, 23), outline=PALETTE["crimson"], width=2), d.ellipse((15, 8, 24, 25), outline=PALETTE["crimson"], width=2), d.line((16, 9, 16, 24), fill=PALETTE["crimson"], width=1))),
        "infection": (PALETTE["magenta"], lambda d: (d.ellipse((9, 9, 23, 23), outline=PALETTE["magenta"], width=2), d.line((16, 5, 16, 27), fill=PALETTE["magenta"], width=1), d.line((5, 16, 27, 16), fill=PALETTE["magenta"], width=1), d.line((9, 9, 23, 23), fill=PALETTE["magenta"], width=1), d.line((23, 9, 9, 23), fill=PALETTE["magenta"], width=1))),
        "anomaly": (PALETTE["magenta"], lambda d: (d.arc((6, 6, 26, 26), 30, 310, fill=PALETTE["magenta"], width=2), d.arc((10, 10, 22, 22), 210, 120, fill=PALETTE["magenta"], width=2))),
    }
    for name, (color, draw_fn) in status_icons.items():
        icon(f"icons/status/{name}_32.png", draw_fn, color)

    action_icons: dict[str, tuple[tuple[int, int, int, int], Callable[[ImageDraw.ImageDraw], None]]] = {
        "search": (PALETTE["teal"], lambda d: (d.ellipse((8, 8, 19, 19), outline=PALETTE["teal"], width=2), d.line((18, 18, 25, 25), fill=PALETTE["teal"], width=3))),
        "interact": (PALETTE["teal"], lambda d: (d.rectangle((8, 8, 22, 18), outline=PALETTE["teal"], width=2), d.line((15, 18, 15, 25), fill=PALETTE["teal"], width=2), d.line((10, 25, 20, 25), fill=PALETTE["teal"], width=2))),
        "inventory": (PALETTE["teal"], lambda d: (d.rectangle((8, 9, 24, 24), outline=PALETTE["teal"], width=2), d.line((11, 13, 21, 13), fill=PALETTE["teal"], width=1), d.line((11, 18, 21, 18), fill=PALETTE["teal"], width=1))),
        "map": (PALETTE["teal"], lambda d: (d.line((8, 8, 8, 24), fill=PALETTE["teal"], width=2), d.line((16, 6, 16, 22), fill=PALETTE["teal"], width=2), d.line((24, 8, 24, 24), fill=PALETTE["teal"], width=2), d.polygon([(8, 8), (16, 6), (24, 8), (24, 24), (16, 22), (8, 24)], outline=PALETTE["teal"]))),
        "camp": (PALETTE["amber"], lambda d: (d.polygon([(16, 6), (26, 25), (6, 25)], outline=PALETTE["amber"], fill=(244, 181, 64, 45)), d.line((16, 6, 16, 25), fill=PALETTE["amber"], width=1))),
        "talk": (PALETTE["white"], lambda d: (d.rectangle((7, 8, 24, 20), outline=PALETTE["white"], width=2), d.polygon([(12, 20), (11, 26), (17, 20)], fill=PALETTE["white"]))),
        "rest": (PALETTE["white_dim"], lambda d: (d.line((8, 22, 25, 22), fill=PALETTE["white_dim"], width=3), d.rectangle((8, 14, 16, 20), outline=PALETTE["white_dim"], width=2), d.line((16, 18, 25, 18), fill=PALETTE["white_dim"], width=2))),
        "settings": (PALETTE["teal"], lambda d: (d.ellipse((10, 10, 22, 22), outline=PALETTE["teal"], width=2), d.line((16, 5, 16, 10), fill=PALETTE["teal"], width=2), d.line((16, 22, 16, 27), fill=PALETTE["teal"], width=2), d.line((5, 16, 10, 16), fill=PALETTE["teal"], width=2), d.line((22, 16, 27, 16), fill=PALETTE["teal"], width=2))),
        "save": (PALETTE["teal"], lambda d: (d.rectangle((8, 7, 24, 25), outline=PALETTE["teal"], width=2), d.rectangle((11, 9, 21, 14), outline=PALETTE["teal"], width=1), d.rectangle((12, 19, 20, 25), fill=(72, 222, 220, 65)))),
        "load": (PALETTE["teal"], lambda d: (d.rectangle((8, 7, 24, 25), outline=PALETTE["teal"], width=2), d.line((16, 10, 16, 21), fill=PALETTE["teal"], width=2), d.polygon([(11, 16), (21, 16), (16, 22)], fill=PALETTE["teal"]))),
    }
    for name, (color, draw_fn) in action_icons.items():
        icon(f"icons/actions/{name}_32.png", draw_fn, color)

    combat_icons: dict[str, tuple[tuple[int, int, int, int], Callable[[ImageDraw.ImageDraw], None]]] = {
        "shoot": (PALETTE["amber"], lambda d: draw_crosshair(d, PALETTE["amber"])),
        "melee": (PALETTE["white"], lambda d: (d.line((9, 23, 23, 9), fill=PALETTE["white"], width=3), d.rectangle((7, 22, 12, 26), fill=PALETTE["white"]), d.line((19, 7, 25, 13), fill=PALETTE["white"], width=2))),
        "reload": (PALETTE["amber"], lambda d: (d.arc((8, 7, 25, 24), 30, 300, fill=PALETTE["amber"], width=2), d.polygon([(24, 9), (28, 8), (26, 14)], fill=PALETTE["amber"]), d.rectangle((12, 13, 19, 25), outline=PALETTE["amber"], width=2))),
        "cycle": (PALETTE["amber"], lambda d: (draw_arrow(d, PALETTE["amber"], False), draw_arrow(d, PALETTE["amber"], True))),
        "block": (PALETTE["teal"], lambda d: (d.polygon([(16, 5), (25, 10), (23, 23), (16, 28), (9, 23), (7, 10)], outline=PALETTE["teal"], fill=(72, 222, 220, 52)), d.line((16, 8, 16, 25), fill=PALETTE["teal"], width=1))),
        "dodge": (PALETTE["teal"], lambda d: (d.line((8, 22, 19, 11), fill=PALETTE["teal"], width=3), d.polygon([(21, 9), (21, 16), (27, 10)], fill=PALETTE["teal"]), d.line((8, 11, 13, 11), fill=PALETTE["teal_dim"], width=1), d.line((6, 16, 12, 16), fill=PALETTE["teal_dim"], width=1))),
        "grapple": (PALETTE["white"], lambda d: (d.ellipse((8, 8, 15, 15), outline=PALETTE["white"], width=2), d.ellipse((17, 17, 24, 24), outline=PALETTE["white"], width=2), d.line((14, 14, 18, 18), fill=PALETTE["white"], width=2))),
        "break_guard": (PALETTE["crimson"], lambda d: (d.polygon([(16, 5), (25, 10), (23, 24), (16, 28), (9, 24), (7, 10)], outline=PALETTE["crimson"], fill=(230, 58, 70, 42)), d.line((12, 8, 19, 18, 14, 18, 20, 27), fill=PALETTE["crimson"], width=2))),
        "cover": (PALETTE["teal"], lambda d: (d.rectangle((8, 14, 24, 25), outline=PALETTE["teal"], width=2), d.line((10, 12, 22, 6), fill=PALETTE["teal"], width=2), d.line((22, 6, 25, 14), fill=PALETTE["teal"], width=2))),
        "reaction": (PALETTE["magenta"], lambda d: (d.arc((7, 7, 25, 25), 220, 80, fill=PALETTE["magenta"], width=2), d.polygon([(25, 10), (27, 17), (20, 14)], fill=PALETTE["magenta"]), d.line((16, 11, 16, 21), fill=PALETTE["magenta"], width=2))),
        "pass": (PALETTE["white_dim"], lambda d: (d.line((9, 16, 23, 16), fill=PALETTE["white_dim"], width=3), d.line((19, 12, 23, 16, 19, 20), fill=PALETTE["white_dim"], width=2))),
        "execute": (PALETTE["crimson"], lambda d: (d.line((9, 8, 23, 22), fill=PALETTE["crimson"], width=3), d.line((23, 8, 9, 22), fill=PALETTE["crimson"], width=3), d.ellipse((11, 11, 21, 21), outline=PALETTE["crimson"], width=1))),
    }
    for name, (color, draw_fn) in combat_icons.items():
        icon(f"icons/combat/{name}_32.png", draw_fn, color)

    for kind in ["head", "upper_torso", "lower_torso", "left_arm", "right_arm", "left_leg", "right_leg"]:
        draw_medical_limb(f"medical/limb_{kind}_64.png", kind, PALETTE["teal"])
    draw_state_badge("medical/state_stable_32.png", PALETTE["teal"], "stable")
    draw_state_badge("medical/state_damaged_32.png", PALETTE["amber"], "damaged")
    draw_state_badge("medical/state_critical_32.png", PALETTE["crimson"], "critical")
    draw_state_badge("medical/state_destroyed_32.png", PALETTE["magenta"], "destroyed")
    icon("medical/trauma_bleeding_32.png", lambda d: draw_drop(d, PALETTE["crimson"]), PALETTE["crimson"])
    icon("medical/trauma_fracture_32.png", lambda d: draw_bone(d, PALETTE["white"]), PALETTE["white"])
    icon("medical/trauma_burn_32.png", lambda d: draw_flame(d, PALETTE["amber"]), PALETTE["amber"])

    controls()
    overlays()
    anim_assets()
    preview()


def _digit_glyph(digit: int) -> list[str]:
    glyphs = {
        0: ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
        1: ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
        2: ["01110", "10001", "00001", "00110", "01000", "10000", "11111"],
        3: ["01110", "10001", "00001", "00110", "00001", "10001", "01110"],
        4: ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
        5: ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
        6: ["01110", "10000", "11110", "10001", "10001", "10001", "01110"],
        7: ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
        8: ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
        9: ["01110", "10001", "10001", "01111", "00001", "00001", "01110"],
    }
    return glyphs[digit]


def clock_digit(path: str, digit: int, color: tuple[int, int, int, int] = PALETTE["teal"]) -> None:
    img = canvas((12, 16))
    draw = ImageDraw.Draw(img)
    draw.rectangle((0, 0, 11, 15), fill=(2, 7, 8, 160), outline=(*color[:3], 90), width=1)
    glyph = _digit_glyph(digit)
    for row, pattern in enumerate(glyph):
        for col, bit in enumerate(pattern):
            if bit == "1":
                x = 3 + col
                y = 4 + row
                draw.point((x, y), fill=color)
                draw.point((x, y + 1), fill=(*color[:3], 120))
    save(img, path)


def clock_colon(path: str, color: tuple[int, int, int, int] = PALETTE["teal"]) -> None:
    img = canvas((6, 16))
    draw = ImageDraw.Draw(img)
    draw.rectangle((2, 5, 3, 6), fill=color)
    draw.rectangle((2, 10, 3, 11), fill=color)
    save(img, path)


def signal_strength(path: str, level: int, color: tuple[int, int, int, int] = PALETTE["teal"]) -> None:
    img = canvas((24, 16))
    draw = ImageDraw.Draw(img)
    draw.rectangle((0, 0, 23, 15), fill=(2, 7, 8, 140), outline=(*color[:3], 70), width=1)
    heights = [4, 7, 10, 13]
    for index, height in enumerate(heights):
        x0 = 3 + index * 5
        y0 = 14 - height
        active = index < level
        fill = color if active else (*color[:3], 40)
        outline = color if active else (*color[:3], 70)
        draw.rectangle((x0, y0, x0 + 3, 13), fill=fill, outline=outline, width=1)
    save(img, path)


def anim_icon_frames(name: str, frame_count: int, drawer: Callable[[ImageDraw.ImageDraw, int], None], color: tuple[int, int, int, int]) -> None:
    for frame in range(frame_count):
        img, draw = icon_base()
        drawer(draw, frame)
        draw_corner_brackets(draw, (32, 32), (*color[:3], 165))
        save(img, f"anim/icons/{name}_{frame}.png")


def anim_assets() -> None:
    for digit in range(10):
        clock_digit(f"anim/clock/digit_{digit}.png", digit)
    clock_colon("anim/clock/colon.png")
    for level in range(5):
        signal_strength(f"anim/signal/signal_{level}.png", level)
        signal_strength(f"anim/signal/signal_warn_{level}.png", level, PALETTE["amber"])
        signal_strength(f"anim/signal/signal_danger_{level}.png", level, PALETTE["crimson"])
        signal_strength(f"anim/signal/signal_anomaly_{level}.png", level, PALETTE["magenta"])

    def bleed_drawer(draw: ImageDraw.ImageDraw, frame: int) -> None:
        offset = frame * 2
        draw_drop(draw, PALETTE["crimson"])
        draw.ellipse((14, 22 + offset, 18, 26 + offset), fill=(*PALETTE["crimson"][:3], 160))

    def heartbeat_drawer(draw: ImageDraw.ImageDraw, frame: int) -> None:
        y_mid = 16
        amp = [0, -3, 4, -2, 0][frame % 5]
        points = [(5, y_mid), (10, y_mid), (13, y_mid + amp), (16, y_mid - amp * 2), (19, y_mid + amp), (22, y_mid), (27, y_mid)]
        draw.line(points, fill=PALETTE["crimson"], width=2)

    def anomaly_drawer(draw: ImageDraw.ImageDraw, frame: int) -> None:
        shift = frame * 2
        draw.arc((6 + shift % 3, 6, 26 - shift % 2, 26), 30, 310, fill=PALETTE["magenta"], width=2)
        draw.arc((10, 10 + shift % 2, 22, 22), 210, 120, fill=PALETTE["magenta"], width=2)

    anim_icon_frames("bleeding", 3, bleed_drawer, PALETTE["crimson"])
    anim_icon_frames("heartbeat", 5, heartbeat_drawer, PALETTE["crimson"])
    anim_icon_frames("anomaly", 4, anomaly_drawer, PALETTE["magenta"])


if __name__ == "__main__":
    main()
