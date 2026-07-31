# PixelLab MCP setup

PixelLab generates and animates pixel-art sprites. Connecting it as an MCP server
lets Claude call it directly instead of the owner driving the web UI by hand —
which is the whole point, given "I don't know what I'm doing and I don't have the
time to learn it right now".

## The key never goes in a file

`.mcp.json` is committed and references `${PIXELLAB_API_KEY}`. Claude Code expands
that from the environment at startup, so the repo carries the wiring and your shell
carries the secret. Nothing to gitignore, nothing to redact, and no way to leak it
by pushing.

Put it in your shell profile once:

```bash
echo 'export PIXELLAB_API_KEY="your-key-here"' >> ~/.zshrc
source ~/.zshrc
```

Then, from the project directory:

```bash
cd ~/Desktop/project-zero-climb
claude mcp list
```

`pixellab` should appear as connected. If it does not, `claude mcp get pixellab`
prints what it tried.

**Do not paste the key into a chat message.** Anything typed into a conversation is
in the transcript for good. A key that has been pasted should be rotated in the
PixelLab dashboard and replaced in `~/.zshrc` — nothing else changes, because
nothing else ever held it.

## It only works on the Mac

`api.pixellab.ai` is blocked by the network policy of the remote Claude Code
environment (`403 CONNECT tunnel failed` from the agent proxy), which is the same
block that rules out itch.io, ambientCG and Poly Haven. So:

- **Local Claude Code on the Mac** — PixelLab tools are available.
- **claude.ai/code remote sessions** — they are not, and the server will show as
  failed. That is the environment, not the key.

This is worth knowing before debugging a "broken" connection that is working fine.

## What it is for, and what it is not for

CLAUDE.md's hard rule stands: **do not replace or generate art.** The package ships
transparent split frames for actors, enemies, boss, effects and icons, and those are
the game's art. PixelLab is for the gaps the owner has actually named:

- cleaning up the hero's cutout (the "weird part of all of that kind of photo above
  his head");
- walk cycles that read as walking, and a separate dash animation;
- clean animations for the three summons.

Anything beyond that is a redesign and needs to be raised first.

## Delivery format

Whatever comes back has to satisfy `tools/validate_sprite_delivery.py` before it is
installed — that script exists because sprite deliveries have arrived misaligned
before and the drift is invisible until the character bobs in-game. It checks
per-frame height variance, width variance, and edge contact (the giveaway for a
frame that was cropped through the character).

`docs/SPRITE_DELIVERY_SPEC.md` is the spec to hand to any generator, PixelLab
included. `docs/SPRITE_GENERATION_RECIPE.md` covers prompt shape and the pivot rules.

Run it before committing anything:

```bash
python3 tools/validate_sprite_delivery.py <folder-of-frames>
```
