# Project Zero Climb - First Playtest Package

This package is the handoff for an 8-12 minute Godot vertical slice. Start with:

1. `docs/CLAUDE_GODOT_BUILD_BRIEF.md` - detailed build phases and acceptance tests.
2. `docs/CLAUDE_START_PROMPT.txt` - paste this into Claude with the ZIP attached.
3. `docs/PROJECT_ZERO_CLIMB_MASTER_GUIDE_v1.0.pdf` - illustrated reference guide.
4. `docs/PROJECT_ZERO_CLIMB_MASTER_GUIDE_v1.0.md` - editable source guide.
5. `docs/ASSET_MANIFEST.json` - authoritative asset status, atlas grids, and intended use.
6. `docs/LEVEL1_BALANCE.json` - prototype combat and encounter numbers.
7. `docs/FIRST_PLAYTEST_CHECKLIST.md` - completion and test checklist.
8. `level1_prototype/maps/PZC_Sunfall_Ward_Route_Map_v1.png` - exact first-level flow.

## Locked identity

- Genre: connected-room action roguelite and auto-attacking summon battler.
- Hero: Tower Exile, orange scarf, indigo coat, violet Shard Core.
- Controls: movement, optional Focus Weapon aim, Rally, dash, Convergence.
- Team: one Focus Weapon and three persistent autonomous summons.
- Starter summons: Rune Hound, Sword Wisp, Gun Construct.
- First biome: Sunfall Ward, a warm tower-town district corrupted by Rifts.
- Hero target: 88 pixels tall at 1080p in normal combat.
- Art: bold 16-bit-inspired anime sprites in dimensional HD-pixel environments.
- Friendly effects: violet with blue-white core.
- Hostile telegraphs: red/orange.
- Rewards/interactables: gold and teal.

## Important prototype note

The alpha PNGs and split frames are ready for rapid prototyping, but they are AI-generated first-playtest assets, not final production animation. Claude should preserve their proportions and filenames, use nearest-neighbor filtering, and avoid repainting or silently changing the visual identity. Before commercial release, an artist should normalize pivots, silhouettes, frame-to-frame anatomy, hit flashes, and environment construction.

## Build boundary

The first playable build must contain only:

- One hero.
- One Focus Weapon: Conjurer Staff.
- Three starter summons.
- Six enemy roles, introduced gradually.
- One elite variant.
- One optional Rift.
- One Spirit Well/merchant.
- One boss: The First Bell.
- One 8-12 minute route.
- One reward-card system.
- Basic Stability, Overdrive, Rally, dash, save settings, and controller support.

Anything else belongs in backlog until this slice is fun and stable.
