# Project Zero Climb

Connected-room action roguelite. Godot 4.7. Building one **8–12 minute vertical
slice** for the first playtest.

Design source of truth: `docs/PROJECT_ZERO_CLIMB_MASTER_GUIDE_v1.0.md`
Build plan: `docs/CLAUDE_GODOT_BUILD_BRIEF.md` (16 numbered phases)
Art still to produce: `docs/ART_REQUIREMENTS.md`
Regenerating the three off-model sheets: `docs/ART_REGENERATION_SHEETS_3_4_8.md`
Animation recommendations: `docs/ANIMATION_GUIDE.md`
Generation prompts: `docs/ART_GENERATION_PROMPTS.md` (per sheet) and
`docs/ART_GENERATION_MASTER_PROMPT.md` (one paste, all eleven sheets)
Defects in shipped art: `ART_CLEANUP_TODO.md`
Higgsfield animation test: `docs/HIGGSFIELD_ANIMATION_TEST.md`
Realistic additive effects: `docs/REALISTIC_VFX.md`
Getting the art onto your machine: `docs/ASSET_DELIVERY.md`

## Status

| Phase | Scope | State |
|---|---|---|
| 0 | Project foundation | **complete** — 19/19 acceptance checks |
| 1 | Hero sandbox | **complete** — 15/15 acceptance checks |
| 2 | Conjurer Staff and targeting | **complete** — 22/22 acceptance checks |
| 3 | Shared summon architecture | **complete** — 29/29 acceptance checks |
| 4 | Starter species | **complete** — 17/17 acceptance checks |
| 5 | Enemies | **complete** — 27/27 acceptance checks |
| 6 | Combat room framework | **complete** — 23/23 acceptance checks |
| 7 | Rewards, inventory, evolution | **complete** — 23/23 acceptance checks |
| 8 | Sunfall Ward blockout | **complete** — 9/9 acceptance checks |
| 9 | Spirit Well and merchant | **complete** — 20/20 acceptance checks |
| 10 | Optional Rift | **complete** — 18/18 acceptance checks |
| 11 | The First Bell | **complete** — 19/19 acceptance checks |
| 12 | Rally, Stability, Convergence | **complete** — 24/24 acceptance checks |
| 13 | HUD and menus | **complete** — 15/15 acceptance checks |
| 14 | Save and results | **complete** — 16/16 acceptance checks |
| 15 | Performance and QA | **complete** — 12/12 acceptance checks |

**All sixteen phases are built, and F5 now plays.** `scenes/playable.tscn` is the
main scene: the Ward, the hero, three bonded summons, a follow camera, the HUD, the
audio mixer, the realistic effects, and enemies that spawn from the balance file
when you walk into a combat space.

Not yet chained into one run: room-to-room progression through
`EncounterController`'s gates, the reward screen between rooms, the merchant, the
Rift, and the boss fight. All are built and tested — see the phase table — but the
playable build is a ward you can fight in, not the full 8–12 minute loop yet.

Four realistic effects — fire, beam, lightning, shockwave — are generated,
installed and drawn additively over the pixel actors. They are the only generated
art in the project and exist by explicit owner request; `docs/REALISTIC_VFX.md`
covers the pipeline, the enforced colour-ownership gate and the measured cost.

```bash
./tools/vfx_from_video.py --sources <dir>      # video -> additive sprite sheets
godot --headless --path . --script scripts/tools/build_additive_vfx.gd
./tools/screenshot.sh scenes/tests/vfx_showcase.tscn build/shots/vfx.png 30
```

There is also a full placeholder sound set — 65 SFX slots and three music beds,
synthesised from scratch with numpy, nothing downloaded or licensed. `AudioDirector`
implements guide §14's mix priority as a voice-limited mixer, so the player's damage
warning stays audible in a 250-enemy room. `CombatPresentation` wires both audio and
effects to combat from the outside, and cannot change the fight.

```bash
./tools/make_placeholder_audio.py    # regenerates every WAV in ~3s, byte-identical
```

## Godot version

Targets **Godot 4.7** (4.7.1 is current as of July 2026) and verified on it: all
375 checks pass, the project imports with zero errors, and the additive VFX shader
compiles and renders identically.

Also verified on **4.3**, in both directions — a project declaring 4.7 opens on 4.3
without complaint and vice versa. So either works, but install 4.7.

```bash
godot --version    # expect 4.7.x
```

## Getting it running on your own machine

`assets/` is gitignored — Git LFS upload is blocked from the build environment. The
project runs without it (every scene loads; the actors are just invisible), and the
art arrives as one verified bundle:

```bash
./tools/fetch_assets.sh <bundle-url-or-zip>
godot --headless --path . --import
./tools/check_project.sh
```

See `docs/ASSET_DELIVERY.md`. The permanent fix is a GitHub Release: 2 GB per file,
free, out of git history, and a URL `curl` can actually fetch.

The eleven-sheet art package is installed (`tools/install_sheet_package.py`).
Sheets 1–2 give all six evolved summon forms, which was Phase 7's only art
blocker. Sheets 3, 4 and 8 are installed but deliberately not wired — they were
generated without reference images and re-invented creatures that already exist.
Finished regeneration prompts for all three are in
`docs/ART_REGENERATION_SHEETS_3_4_8.md`; the defects are logged in
`ART_CLEANUP_TODO.md`.

```bash
./tools/make_reference_sheets.py    # reference images to attach to the prompts
./tools/compare_frames.py           # side-by-side check on whatever comes back
```

## Running it

```bash
godot --path .                      # the playable build — this is the game
godot --path . scenes/tests/hero_sandbox.tscn   # Phase 1 hero sandbox
godot --path . scenes/tests/focus_range.tscn    # Phase 2 targeting range
godot --path . scenes/tests/summon_field.tscn   # Phase 3 summon field
godot --path . scenes/tests/species_field.tscn  # Phase 4 species behaviours
godot --path . scenes/tests/enemy_field.tscn    # Phase 5 enemy roles
godot --path . scenes/tests/reward_demo.tscn    # Phase 7 three-card offer
godot --path . scenes/tests/evolution_field.tscn # Phase 7 all nine summon forms
godot --path . scenes/world/sunfall_ward.tscn   # Phase 8 the level blockout
godot --path . scenes/tests/vfx_showcase.tscn   # the four realistic effects
```

## Seeing it without a monitor

Godot renders here through a virtual display with software GL, so the look can
be checked on a headless box:

```bash
./tools/screenshot.sh scenes/tests/reward_demo.tscn build/shots/reward.png
./tools/screenshot.sh scenes/tests/enemy_field.tscn build/shots/enemy.png 60 180
```

Extra numbers capture several frames of the same run. `--headless` cannot be
used for this — its dummy renderer draws nothing.

This is worth doing. The first render of the project immediately showed the hero
measuring 80 px against his locked 88 px target, which eight phases of headless
acceptance checks had not caught: the Phase 1 check projects the sprite *cell*
rather than the drawn character. See `ART_CLEANUP_TODO.md`.

All sixteen phases plus the effects, audio, presentation and playable suites:
**375 checks, 0 failures.** One command runs everything:

```bash
./tools/check_project.sh
```

WASD moves, Space dashes, F3 toggles the debug overlay.

## Acceptance tests

Each phase has a headless, CI-usable harness that exits non-zero on failure.

```bash
godot --headless --path . --script scripts/tests/phase0_acceptance.gd
godot --headless --path . --script scripts/tests/phase1_acceptance.gd
godot --headless --path . --script scripts/tests/phase2_acceptance.gd
godot --headless --path . --script scripts/tests/phase3_acceptance.gd
godot --headless --path . --script scripts/tests/phase4_acceptance.gd
godot --headless --path . --script scripts/tests/phase5_acceptance.gd
godot --headless --path . --script scripts/tests/phase6_acceptance.gd
godot --headless --path . --script scripts/tests/phase7_acceptance.gd
godot --headless --path . --script scripts/tests/phase8_acceptance.gd
godot --headless --path . --script scripts/tests/phase9_acceptance.gd
godot --headless --path . --script scripts/tests/phase10_acceptance.gd
godot --headless --path . --script scripts/tests/phase11_acceptance.gd
godot --headless --path . --script scripts/tests/phase12_acceptance.gd
godot --headless --path . --script scripts/tests/phase13_acceptance.gd
godot --headless --path . --script scripts/tests/phase14_acceptance.gd
godot --headless --path . --script scripts/tests/phase15_acceptance.gd
godot --headless --path . --script scripts/tests/vfx_acceptance.gd
godot --headless --path . --script scripts/tests/audio_acceptance.gd
godot --headless --path . --script scripts/tests/presentation_acceptance.gd
```

Or all of them at once, which is what to run before believing a change:

```bash
./tools/check_project.sh
```

## Regenerating actor SpriteFrames

`data/characters/tower_exile_frames.tres` is generated from the package split
frames — do not hand-edit it. Rebuild after any actor art change:

```bash
godot --headless --path . --script scripts/tools/build_hero_spriteframes.gd
godot --headless --path . --script scripts/tools/build_summon_spriteframes.gd
godot --headless --path . --script scripts/tools/build_vfx_spriteframes.gd
godot --headless --path . --script scripts/tools/build_enemy_spriteframes.gd
godot --headless --path . --script scripts/tools/build_effect_spriteframes.gd
godot --headless --path . --script scripts/tools/build_additive_vfx.gd
```

These also refresh the ground-pivot audits in `docs/generated/` and the runtime
pivot correction tables. Treat baselining as required for any new actor art:
every row in the first-playtest package needed correction (13–28 px of drift),
though the eleven-sheet package lands at 0–1 px, so it is a check that can pass.

## Layout

```
assets/       prototype art from the package (LFS)
data/         Resources and generated SpriteFrames
docs/         package documentation, balance, manifest
scenes/       actors, enemies, rooms, ui, tests
scripts/      data, actors, combat, run, ui, tools, tests
```

## Testing discipline

Acceptance checks are verified by mutation testing, not trusted on green. A
deliberate wrong value is injected into the code and the suite must fail; if it
passes, the check is weak and gets rewritten. Mutants are run against every phase and are currently all killed.

Two rules came out of that and apply to every new check:

1. **Assert against the specification, never the implementation.** Expected values
   come from `docs/LEVEL1_BALANCE.json`, not from the resource under test —
   otherwise a wrong value is compared against itself and passes.
2. **Isolate the property under test.** A check that runs during unrelated
   combat measures combat noise. Every flaky check found so far was caused by this.
3. **Never depend on `_ready()` ordering.** A value copied in `_ready` may not be
   there yet for a caller running right after `add_child`. Four separate bugs this
   project have come from that assumption — read from the data resource directly.
4. **Assert on what the code did, not on the file it should have read.** Phase 7's
   first pivot check compared two numbers straight out of the audit JSON and passed
   happily with the lookup hard-wired to the wrong row. It now asks the summon which
   corrections it actually loaded.
5. **Make sure the mutation you inject can actually change behaviour.** Several
   survivors here turned out to be equivalent mutants sitting behind a second,
   redundant guard. A survivor means "investigate", not automatically "weak test" —
   but it does mean the check has not been proven yet.
6. **Never assert on a counter the mutant would delete.** The boss telegraph check
   watched `untelegraphed_hits`, which only increments inside the branch a broken
   gate removes — so it passed with the gate gone. It now watches the telegraph's
   own state at the moment damage lands, and separately builds the case the gate
   exists for by tearing the telegraph away mid-windup.
7. **Check the shipped artefact, not the file it was built from.** The effect
   colour gate reads the `.png` that ships rather than the `.json` that produced
   it. Checking the input would pass happily against a texture nobody rebuilt.
8. **A guard hidden behind another guard is not tested.** Convergence refuses to
   retrigger both because it is active *and* because triggering empties the meter.
   Removing the first changed nothing until the test refilled the meter directly.

## Working rules

See `CLAUDE.md`. The short version: don't redesign the game, don't replace or
generate art, don't expand scope, keep balance data-driven, and log art issues in
`ART_CLEANUP_TODO.md` instead of repainting.

Art and audio go through **Git LFS** (`.gitattributes`). Run `git lfs install`
after cloning.
