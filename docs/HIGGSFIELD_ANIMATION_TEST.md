# Higgsfield for sprite animation — measured result

The package ships **poses, not animations**: one frame per state for every summon,
enemy and boss. `ANIMATION_GUIDE.md` calls that the single biggest problem in the
project, and death — one frame — the weakest moment in the game.

This is a measured test of whether Higgsfield can close that gap, not an opinion.

## The test

One generation: Rune Hound idle → 5 s image-to-video → 6 extracted frames.

- Input: the shipped `00_rune_hound__00_idle.png`, cropped to content, 4× nearest,
  centred on a flat dark plate at 720×1280
- Model: `kling3_0_turbo`, image-to-video from a start frame
- Prompt: death — stagger, buckle, collapse, dissolve; locked camera; keep the design
- Cost: **7.5 credits** (balance was 3072, so roughly 400 more like it)

Upload works from a sandbox: `media_upload` returns a presigned URL, PUT the bytes,
`media_confirm`. No browser needed.

## What worked — and it is the hard part

**It stayed on-model.** Same crystalline violet wolf, same mane, same diamond chest
gem, same paw shapes, same palette.

That matters more than it sounds. Sheets 3, 4 and 8 of the art package failed for
exactly one reason: generated from text alone, with no picture of the creature, so
the model invented a new one. Image-to-video is conditioned on the actual sprite, so
being on-model is structural rather than something the prompt has to beg for.

The motion is also plausible: weight shifts, the body turns, the head lowers, and by
the last frame the creature has dissolved out of frame entirely — which is arguably
the correct end of a death animation.

## What did not work

Measured on the extracted frames, against the same gate the art pipeline uses:

| Property | Measured | Project gate |
|---|---|---|
| Contact baseline spread | **32 px** (≈8.5 px at sprite scale) | 0 ideal, corrects under ~3 |
| Drawn height spread | **196 px, 25%** | — |
| Horizontal drift | **42 px** | — |

The baseline drift is survivable: the runtime pivot table already corrects a 28 px
spread on the Rift Crawler, so 8.5 px is inside what the engine handles.

**The 25% height variance is not.** It is the same defect logged against the hero's
idle frames — a creature that changes size between frames cannot be fixed by any
single scale, and normalising height automatically would be wrong because a
collapsing creature is genuinely shorter. That needs a human eye per frame.

The creature also turns to profile and wanders 42 px sideways despite the prompt
asking for a locked, centred subject.

## Verdict

**Use it for key poses, not for finished cycles.** That is exactly what
`ANIMATION_GUIDE.md` §6 already recommends, and this test is the first evidence that
the recommendation holds for video models too — with one upgrade: video is a far
better source of key poses than text-to-image, because it cannot drift off-model.

A realistic pipeline:

1. Generate 2–3 s of motion from the shipped frame (short runs drift less)
2. Pull the 3–4 extreme poses — windup, contact, recovery
3. Clean each by hand: re-key the background, normalise scale against the source
   sprite, put the contact foot on the source foot row
4. Run the existing pivot audit and require `baseline_spread_px` near 0
5. In-between by hand or with a tweening tool

Steps 1–2 are where the time is saved. Steps 3–5 are the work that keeps this project
from accumulating another sheet 4.

## Worth trying next

- `seedance_2_0` instead — it is tagged `reference / identity / consistent` and
  accepts `image_references` alongside `start_image`, which may hold framing better
- 2–3 s instead of 5 s
- A chroma-green plate instead of dark, so `tools/install_sheet_package.py` can key
  the extracted frames with the machinery that already exists
- Generating on a visible ground line drawn into the input plate, giving the model a
  horizon to keep the feet on

**None of this is committed to the project.** No generated frame has been installed;
`CLAUDE.md` still says do not replace or generate art, and this document exists so
the owner can decide whether to change that rule with real numbers in front of them.
