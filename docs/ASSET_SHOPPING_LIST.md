# Free asset shopping list — vetted, license-checked, ready to apply

Researched 2026-07-30 by four parallel scouts + adversarial verifiers. Every
entry below had its LICENSE fetched and read, and its download tested from the
build environment. Direct sites (kenney.nl, itch.io, quaternius.com,
ambientcg.com, polyhaven.com, opengameart.org, freesound.org) are ALL blocked
from the build environment's network — every verified channel below is a
first-party GitHub repo or a pinned-commit mirror, fetched over git.

## Installed and wired (docs/FREE_ASSETS.json, tools/fetch_free_assets.sh)

| What | Pack | License | Where it shows up |
|---|---|---|---|
| Market stalls, cart, benches, lantern, hedges, trees, rocks | **Kenney Fantasy Town Kit 1.1** | CC0 | perimeter props in every non-travel room |
| Produce crates (buns/carrots/cheese/lettuce), storage jars | **KayKit Restaurant Bits 1.0** | CC0 | crates + jar "barrels" in combat/service rooms |
| Explore bed: *Market Day* — RandomMind | Stendhal's audited catalog | CC0 | replaces the synthesized explore loop |
| Combat bed: *Battle Ready* | FreePD catalog | CC0 | replaces the synthesized combat loop |
| Boss bed: *Epic Boss Battle* | FreePD catalog | CC0 | replaces the synthesized First Bell loop |

## Vetted, not yet applied (next passes)

### Textures (all CC0, verified at pinned commits)
- **PavingStones128** (ambientCG) — worn light pavers; floor upgrade.
  `https://raw.githubusercontent.com/Daruin02/Project-Evolvium/5299d8945de5f2594fa0809544638f45eefdc2df/textures/`
- **white_sandstone_blocks_02** (Poly Haven) — cream weathered sandstone; wall upgrade.
  `https://raw.githubusercontent.com/317gw/HYPERLUNATIC/1ffb8ba41a7437e9c2a0139375bac8df76c8e722/assets/maps/`
- **RoofingTiles014A** (ambientCG) — muted terracotta shingles.
- **Plaster001** (ambientCG) — cream stucco.
  The current package textures already read well, so these are held until a
  side-by-side comparison says they are better, not just newer.

### Pixel attack/magic effects — INSTALLED (second research round)
- **CodeManu / DavitMasia "Free Pixel Effects Pack"** — public domain, its own
  README ships with the PNGs. 4 of 20 sheets installed as 5 effect resources:
  `pixel_hit_friendly` / `pixel_hit_hostile` (one 97%-white sheet, two tints),
  `pixel_magic_impact`, `pixel_cast`, `pixel_phantom`. Fetched via a pinned
  GitHub mirror; opengameart.org is blocked from the build environment.
  **Gotcha found by measuring:** every sheet has an EMPTY cell at grid index 0,
  so the resources carry `first_frame = 1`. Playing from 0 puts a one-frame hole
  at the instant of impact.
- **Still available from the same pack, not yet wired:** 16 more sheets —
  `4_casting`, `19_freezing`, `12_nebula`, `18_midnight`, `3_bluefire` (cool /
  friendly); `11_fire`, `7_firespin`, `9_brightfire`, `16_sunburn`,
  `6_flamelash`, `13_vortex` (warm / hostile); `8_protectioncircle`,
  `15_loading`, `17_felspell`, `20_magicbubbles`, `2_magic8`.

### Rejected on license grounds (recorded so nobody re-researches them)
See `_rejected_fx_packs` in docs/FREE_ASSETS.json for the quoted terms:
untiedgames (no raw redistribution), BDragon1727 (non-commercial only),
Zerie (contested), pimen (no license file travels with the art).

**One genuinely blocked item:** the only redistribution-plausible pixel **slash
arc** found anywhere (tbbk's, 3x3 of 64x47, 100% white — ideal for the Sword
Wisp) has its CC0 claim only in a third-party README, and opengameart.org cannot
be reached from here to confirm. Not installed. If you can open
https://opengameart.org/content/pixel-art-sword-slash-effect and it says CC0,
say so and it goes in immediately.

### Sound effects (the next audio pass)
- **Kenney Impact Sounds / Interface Sounds / RPG Audio / Digital Audio** — CC0,
  via the ETdoFresh/kenney.nl GitHub mirror (`https://github.com/ETdoFresh/kenney.nl.git`).
  Covers impacts, UI clicks, coins. Mapping 65 game slots to specific files is
  its own careful pass — done next, not rushed.
- **RPG Sound Pack by artisticdude** — CC0, OpenGameArt (verified GitHub mirror):
  creature snarls and melee hits.

### 3D (if more variety is ever wanted)
- **Quaternius Medieval Village MegaKit (free tier)** — CC0, ~170 models,
  plaster/brick/tile PBR textures included. Heavier, stylized-realistic.
  Via `https://github.com/fda0/Treasure.git` (git-lfs; per-file
  `media.githubusercontent.com` fetch works from the build environment).
- **KayKit Medieval Hexagon Pack** — CC0 whole-town set on hex bases; good for
  skyline dressing beyond the walls, not for walk-up props.

## Rules that still apply to bought/free packs alike
- CC0 preferred; CC-BY acceptable with attribution shipped in-game.
- "Personal use only" or no-redistribution licenses are disqualified — record
  any purchase in docs/FREE_ASSETS.json with its license text either way.
- No character/enemy/boss art from packs, ever — actors are original, locked.
- Colour ownership survives pack art: nothing violet on hostiles, nothing
  red/orange on friendlies, green/gold accents kept small (see
  ART_CLEANUP_TODO.md).
