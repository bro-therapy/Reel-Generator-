# Getting the assets onto your machine

**Short version:** the project runs fine without art. To get the art, download the
bundle and run one command.

```bash
./tools/fetch_assets.sh ~/Downloads/pzc-assets-YYYYMMDD.zip
godot --headless --path . --import
./tools/check_project.sh
```

## Why assets are not in git

`assets/` is gitignored. Two reasons, and neither is fixable from the build
environment:

1. **Git LFS upload is blocked here.** The batch API answers through the local git
   proxy, but the object upload itself redirects to `lfs.github.com` and returns
   Forbidden. Re-tested; still true.
2. **Committing 65 MB of PNGs as raw blobs is worse.** It defeats
   `.gitattributes`, and undoing it needs a history rewrite. This repo already hit
   556 MB of history that way once.

So the binaries travel as one verifiable archive instead.

## The permanent fix: a GitHub Release

This is the storage answer, and it is better than Drive for this job:

- **2 GB per file**, free, no LFS involved.
- **Not in git history** — so it can never bloat the repo.
- **A stable direct-download URL** that `curl` can fetch, which Drive does not
  give you without fighting its confirm-token redirect. That is very likely why
  Drive did not work.
- **Uploadable from a phone** — the Releases page takes a drag-and-drop.

One-time setup:

1. `github.com/bro-therapy/Reel-Generator-` → **Releases** → **Draft a new
   release**. Tag it `assets-v1`.
2. Attach `pzc-assets-YYYYMMDD.zip`. Publish.
3. Copy the asset's download URL and paste it into `ASSET_URL` at the top of
   `tools/fetch_assets.sh`. Commit that one line.

After that, forever, on any machine and in any future session:

```bash
./tools/fetch_assets.sh
```

No arguments, no LFS, no Drive. That is the part worth doing once.

## What is in the bundle

403 files, ~60 MB:

| | |
|---|---|
| 338 PNGs | actors, enemies, environment, UI, effect atlases |
| 64 WAVs | synthesised placeholder audio — 65 SFX slots and 3 music beds |
| 1 manifest | `ASSET_SHA256SUMS.txt`, one SHA256 per file |

`.import` files are excluded on purpose. Godot regenerates them, and a stale one
shipped over a fresh checkout is a real source of "works on your machine".

Every file is verified against the manifest on install. A download that reports
success is not proof it delivered the right bytes, and silently-corrupt art is far
harder to diagnose than a missing file.

## Making a new bundle

From any checkout that has `assets/`:

```bash
./tools/bundle_assets.sh
```

## Running without assets

Supported, and worth knowing since it is what a fresh clone does:

- The game **boots**, and every scene loads. Verified on a clean clone: 0 script
  errors.
- Godot logs 72 `Resource file not found` lines during import. Expected.
- Boot prints a short box naming what is missing and how to fix it, so an
  untextured game does not read as a broken one.
- `./tools/check_project.sh` passes, skipping the suites that need files.

The actors are invisible. Nothing else is wrong.

## Regenerating instead of downloading

Two parts of `assets/` are generated and need no download at all:

```bash
./tools/make_placeholder_audio.py      # all 64 audio files, ~3 s
./tools/vfx_from_video.py --sources <dir with the four clips>
```

The audio is fully reproducible from source — it is synthesised with numpy from a
fixed seed, so a rebuild is byte-identical. The effect sheets need the four
Higgsfield clips; their URLs and job ids are in `docs/VFX_SOURCES.json`.

The 338 package PNGs are the only part that must be downloaded, because they are
the one thing nothing in this repo can regenerate.

## If the bundle is ever lost

`docs/ASSET_MANIFEST.json` records the expected grid and dimensions of every
atlas, and `tools/install_sheet_package.py` verifies SHA256 sums against the
package it installs from. So a re-supplied package can be checked rather than
trusted. See `docs/ART_REQUIREMENTS.md` for what each sheet is supposed to contain.
