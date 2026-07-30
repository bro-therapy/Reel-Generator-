# Sprite delivery spec — what replacement/new frames must look like to drop in

The owner wants better walk cycles and summon animations than the shipped
package carries, possibly generated with an external tool (SpriteCook, ChatGPT,
a commissioned artist — the tool does not matter). This is the contract that
makes any such output installable without code changes. It exists because two
generation paths have already been measured and rejected, and the failure was
never art quality — it was **frame-to-frame consistency**:

- Higgsfield image-to-video: 25% height variance across a walk cycle
  (docs/HIGGSFIELD_ANIMATION_TEST.md). A hero who breathes 25% of his height
  every stride is unusable, however pretty each frame is.
- Higgsfield `autosprite` (purpose-built for this): present in their catalog but
  uncallable — "Job set type not supported" (docs/HIGGSFIELD_ASSET_GUIDE.md).

## The hero (Tower Exile)

| Property | Value |
|---|---|
| Canvas per frame | **162 x 242 px**, transparent PNG |
| Character height | ~213 px of the canvas (must read at 88 px on screen) |
| Directions | 8, in this order: south, southwest, west, northwest, north, northeast, east, southeast |
| Gait frames per direction | idle, walk_contact, walk_passing, run_extension, run_recovery |
| Naming | `{dir_index:02d}_{dir_name}__{col:02d}_{col_name}.png`, e.g. `02_west__01_walk_contact.png` |
| Install to | `assets/actors/hero_locomotion_frames/` |

**What must stay identical across every frame of a cycle:**
- Character height (±2 px). This is the thing generators fail at.
- Ground contact row (feet on the same pixel row; the pipeline corrects ±2 px
  and audits the rest — `docs/generated/hero_pivot_audit.json`).
- Palette and costume: coat, orange scarf, gauntlet, boots, white hair streak —
  all five must survive at 88 px (guide hard rule).
- No background pixels. The frames are composited over the world; the cleanup
  pass (`tools/clean_frame_residue.py`) removes border-touching strays but
  cannot rescue a frame with a baked backdrop.

**More walk frames are welcome.** The current walk is a 2-frame cycle
(contact/passing) because that is all the package shipped. If a tool produces a
clean 4/6/8-frame cycle per direction at the sizes above, name them
`walk_contact`, `walk_passing`, `walk_contact2`, `walk_passing2`, ... and the
builder (`scripts/tools/build_hero_spriteframes.gd`) is a 5-line change per new
column. Consistency beats frame count: a rock-solid 2-frame walk reads better
than a wobbly 8-frame one.

## Summons (Rune Hound, Sword Wisp, Gun Construct)

| Property | Value |
|---|---|
| Canvas per frame | match the existing frames in `assets/actors/summon_action_frames/` (per-species) |
| States | idle, move, aim_or_windup, attack, attack_recover, hit, reform |
| Naming | `{species_index:02d}_{species}__{state_index:02d}_{state}.png` |
| **Most wanted** | **side-profile move cycles** (2-4 frames per species) — the summons currently glide with one pose |

Colour rule for anything friendly: violet / indigo / blue-white only. A summon
frame with warm-orange effects will be rejected on sight — warm belongs to
enemies.

## Effects (attack/magic flipbooks)

The additive VFX pipeline ingests PNG sprite sheets (grid layout, transparent,
any cell size) via `tools/vfx_from_video.py` + `docs/VFX_SOURCES.json`, and
enforces colour ownership by hue histogram — a wrong-side sheet refuses to
build. Slash arcs, muzzle flashes, magic impacts: friendly = violet/blue-white,
hostile = red/orange/warm. 6-16 cells per effect is the sweet spot.

## How to hand frames over

Zip them with the exact folder names above and either put the zip in the
"My video game" Drive folder (the bootstrap knows how to fetch from there) or
anywhere `curl` can reach. After installing:

    python3 tools/clean_frame_residue.py     # strip stray pixels
    godot --headless --path . --script scripts/tools/build_hero_spriteframes.gd
    godot --headless --path . --script scripts/tools/build_summon_spriteframes.gd
    ./tools/check_project.sh                 # the audits will say if a frame drifts

The pivot audit fails loudly on inconsistent ground rows, and Phase 1/2/3
acceptance verifies every animation actually plays. Bad frames cannot sneak in
silently — that is the point of the pipeline.
