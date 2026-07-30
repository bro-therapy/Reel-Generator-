# Getting better walk frames without learning a sprite tool

Written for the owner, who asked whether Claude can just drive PixelLab. Short
answer at the bottom of each section; read "Do this first" before paying anyone.

## Do this first: look at what the walk already does

The walk complaint had two causes and only one of them was the frame count.

The other was **foot sliding** — the stride played at a fixed rate no matter how
fast the hero was actually moving, so his feet skated across the ground at any
speed below a sprint. That is fixed (the stride now scales with ground speed)
and it is the bigger of the two effects on how a walk reads.

So: run the current build and watch him walk before spending anything.

```bash
cd ~/Desktop/project-zero-climb && bash tools/update_mac.sh
```

If it still reads badly, then the frame count is the problem and the rest of
this document applies. If it reads fine, the money is better spent on the
summons' missing side-profile frames than on the hero.

## The honest risk with any AI sprite tool

The shipped hero is **detailed, painterly pixel art, 213 px tall** — coat
folds, a gauntlet with individual plates, a scarf with fabric shading, a white
hair streak. Most AI pixel-art generators produce clean, simple sprites at
32–128 px, because that is what the training data mostly is.

Two things follow:

1. **Style match is the real risk, not animation quality.** New frames that are
   crisper, flatter or simpler than the existing ones will read as a *different
   character* the moment he turns. That is worse than a 2-frame walk.
2. **Resolution has to land on an integer multiple.** Pixel art upscaled by a
   non-integer factor (128 -> 242 is 1.89x) turns to mush. If a tool emits
   128 px sprites, the usable path is 2x to 256 and a re-export of the whole set
   at that size, not a one-off rescale of the walk.

`tools/validate_sprite_delivery.py` catches resolution and consistency
automatically. It cannot catch style drift — that one needs your eye, side by
side with an existing frame.

**Therefore: generate ONE direction's walk cycle on a free trial and look at it
next to `00_south__00_idle.png` before buying anything.**

## Path A — Claude drives the tool (needs two things from you)

The generation API is blocked from the cloud environment by its network policy:

```
CONNECT api.pixellab.ai:443  ->  HTTP/1.1 403 Forbidden
```

To hand the job over entirely, two changes are needed:

1. **Allow the host.** In the Claude Code web environment settings, add
   `api.pixellab.ai` to the allowed outbound hosts. (See
   https://code.claude.com/docs/en/claude-code-on-the-web for where the network
   policy lives.)
2. **Provide the key as an environment variable**, named `PIXELLAB_API_KEY` —
   set in the environment's variables, **not pasted into chat**. Chat history is
   not a secret store, and a key pasted there is a key you have to rotate.

With those two in place Claude can do the whole loop unattended: generate,
validate, install, rebuild the SpriteFrames, run the suites, screenshot, push.

## Path B — you click, Claude checks (no settings changes)

Roughly ten minutes of your time, no API key, works today.

**What to ask for**, whatever the tool's exact wording:

| Setting | Value | Why |
|---|---|---|
| Reference image | `assets/actors/hero_locomotion_frames/00_south__00_idle.png` | Style anchor. Upload the file, do not describe him in words. |
| Directions | 8 (S, SW, W, NW, N, NE, E, SE) | The game uses all eight; four means he slides sideways facing forward. |
| Animation | Walk cycle, **4 frames minimum** | The current 2 is the thing being fixed. |
| Canvas | 162 x 242, or an exact integer fraction (81 x 121) | Anything else needs the whole set re-exported. |
| Background | Transparent | A baked background cannot composite over the world. |
| Method | **Skeleton-based** if offered | A rig physically cannot change his height mid-stride. Image-to-video can, and did: 25% variance, measured. |

**Then send me the folder.** Any of: a zip in the Drive folder, a link I can
curl, or files committed to a branch. I run:

```bash
python3 tools/validate_sprite_delivery.py <folder>
```

which gives a straight ACCEPT / REJECT in seconds, measuring height variance per
cycle, ground-row drift, transparency, canvas consistency, edge clipping and the
signature palette elements. If it accepts, I install, rebuild and push. If it
rejects, you have lost a free trial and nothing else.

## Path C — go back to the original artist

The 40-frame locomotion atlas already exists in this exact style, and whoever
produced it can add walk frames that match by construction — no style-drift risk
at all. `docs/SPRITE_DELIVERY_SPEC.md` is written to be handed straight to them.

This is also the only clean fix for the separate defect the validator found: 32
of 40 atlas cells are drawn wider than their cell, so the cape is sliced flat in
6 run frames (see ART_CLEANUP_TODO.md). A re-export with 24 px of horizontal
padding fixes that and the walk frames in one pass.

## Recommendation

1. Play the current build first — the sliding fix may have already solved it.
2. If not, spend a free trial on **one** direction and compare it side by side.
3. Prefer Path C for the hero if the original artist is reachable; the style
   match is free there and expensive everywhere else.
4. The summons' side-profile move frames are the bigger visible gap either way —
   they currently glide with a single pose.
