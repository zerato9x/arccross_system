# Hex World V2 Git LFS Audit

Audit date: 2026-07-29

## Result

Git LFS is available, but this repository currently has no LFS-tracked files and `.gitattributes` contains only line-ending normalization. The Generator V2 runtime subset is therefore currently stored as ordinary Git blobs.

The promoted subset consists of 54 green terrain HEX textures, 44 fitted
infrastructure sprites, 128 generated road overlays (64 paved and 64 dirt), two
generated road material sources, and the existing North settlement backdrop.
These assets are required at runtime and correctly live under `res://`; no
build reads from `S:`.

## Recommendation

Adopt Git LFS as a deliberate repository-wide asset policy before converting
these paths. A targeted conversion should cover PNGs under
`Asset/HexTiles/_OVERLAYS`, road material swatches under
`Asset/HexTiles/_SOURCE/roads`, the promoted plains
`HEX/grass_tiles/grass_default` directory, `Infrastructure/MoreInfras`, and
`Asset/EventBackgrounds`. Do not rewrite existing Git history as part of the
generator change.
