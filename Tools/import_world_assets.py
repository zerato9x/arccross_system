"""Manifest-driven promotion from the external S: staging library.

Dry-run is the default. Pass --apply to copy approved files into the project.
The game never reads the external library at runtime.
"""

from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import re
import shutil
from pathlib import Path

from PIL import Image


PROJECT_ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = PROJECT_ROOT / "Tools" / "world_asset_manifest.json"
RUNTIME_MANIFEST_PATH = PROJECT_ROOT / "Asset" / "HexTiles" / "world_asset_runtime_manifest.json"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def edge_signatures(path: Path) -> list[list[int]]:
    """Six compact RGBA edge-band means in axial direction order."""
    with Image.open(path).convert("RGBA") as image:
        width, height = image.size
        points = [
            (width - 9, height // 2),
            (width * 3 // 4, 9),
            (width // 4, 9),
            (9, height // 2),
            (width // 4, height - 9),
            (width * 3 // 4, height - 9),
        ]
        result: list[list[int]] = []
        for x, y in points:
            band = image.crop((max(0, x - 5), max(0, y - 5), min(width, x + 6), min(height, y + 6)))
            pixels = list(band.get_flattened_data())
            result.append([sum(pixel[channel] for pixel in pixels) // len(pixels) for channel in range(4)])
        return result


def stable_id(family_id: str, path: Path) -> str:
    slug = re.sub(r"[^a-z0-9]+", ".", path.stem.lower()).strip(".")
    return f"{family_id}.{slug}"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true", help="copy approved assets")
    args = parser.parse_args()

    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    source_root = Path(manifest["external_source_root"])
    runtime_root = PROJECT_ROOT / manifest["runtime_root"].replace("res://", "")
    if not source_root.exists():
        raise SystemExit(f"External source root is unavailable: {source_root}")

    promoted: list[dict[str, object]] = []
    approved_destinations: set[Path] = set()
    prune_roots: set[Path] = set()
    for family in manifest.get("import_families", []):
        source_dir = source_root / family["source"]
        destination_dir = runtime_root / family["destination"]
        if family.get("prune_destination", False):
            prune_roots.add(destination_dir)
        pattern = family.get("glob", "*.png")
        approved_names = set(family.get("files", []))
        required_size = family.get("required_size")
        if not source_dir.exists():
            raise SystemExit(f"Missing source family: {source_dir}")
        for source in sorted(source_dir.rglob("*.png")):
            if approved_names and source.name not in approved_names:
                continue
            if not fnmatch.fnmatch(source.name, pattern):
                continue
            with Image.open(source) as image:
                size = [image.width, image.height]
            if required_size and size != required_size:
                raise SystemExit(
                    f"Rejected {source}: expected {required_size}, got {size}"
                )
            destination = destination_dir / source.relative_to(source_dir)
            approved_destinations.add(destination)
            promoted.append(
                {
                    "asset_id": stable_id(family["asset_id"], source),
                    "family_id": family["asset_id"],
                    "layer_kind": family["kind"],
                    "source": str(source),
                    "destination": "res://" + destination.relative_to(PROJECT_ROOT).as_posix(),
                    "tags": family.get("tags", []),
                    "dimensions": size,
                    "edge_signatures": edge_signatures(source) if family["kind"] in {"terrain_hex", "overlay_hex"} else [],
                    "footprint_class": family.get(
                        "footprint_class",
                        "full_hex" if family["kind"] in {"terrain_hex", "overlay_hex"} else "fitted_prop",
                    ),
                    "hash": sha256(source),
                }
            )
            if args.apply:
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, destination)

    if args.apply:
        removed: list[Path] = []
        for prune_root in sorted(prune_roots):
            if not prune_root.exists():
                continue
            for runtime_file in sorted(prune_root.rglob("*.png")):
                if runtime_file not in approved_destinations:
                    runtime_file.unlink()
                    removed.append(runtime_file)
        RUNTIME_MANIFEST_PATH.parent.mkdir(parents=True, exist_ok=True)
        RUNTIME_MANIFEST_PATH.write_text(
            json.dumps({"version": manifest["version"], "assets": promoted}, indent=2),
            encoding="utf-8",
        )
        if removed:
            print(f"[WorldAssetImporter] Removed {len(removed)} stale managed assets")

    mode = "APPLIED" if args.apply else "DRY RUN"
    print(f"[WorldAssetImporter] {mode}: {len(promoted)} approved assets")
    for kind in sorted({str(entry["layer_kind"]) for entry in promoted}):
        count = sum(1 for entry in promoted if entry["layer_kind"] == kind)
        print(f"  {kind}: {count}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
