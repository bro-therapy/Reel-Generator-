# PixelLab MCP setup

One command, run once, from anywhere on the Mac:

```bash
claude mcp add pixellab https://api.pixellab.ai/mcp -t http -H "Authorization: Bearer YOUR-KEY"
```

Check it:

```bash
claude mcp list
```

That is the whole setup.

## Why it is not more clever than that

An earlier version of this put a `pixellab` entry in a committed `.mcp.json` with
the key as `${PIXELLAB_API_KEY}` from the shell, so the secret never touched a
file. That is genuinely tidier, and it was the wrong call here: it needed the
environment variable set AND a per-project approval AND it collided with the
user-scope server added by the command above. Three ways to fail instead of none,
to protect a key on a personal machine.

`claude mcp add` stores the key in the user-scope config in the home directory,
outside the repo. `.mcp.json` and `.mcp.local.json` are both gitignored, so a key
cannot reach the repo by accident either way.

The one real rule: **never paste the key into a chat message.** Chat transcripts
keep it forever. If that happens, rotate it in the PixelLab dashboard and re-run
the `claude mcp add` command with the new one.

## It only works on the Mac

`api.pixellab.ai` is blocked by the network policy of the remote Claude Code
environment — `403 CONNECT tunnel failed` from the agent proxy, the same block that
rules out itch.io, ambientCG and Poly Haven. So:

- **Local Claude Code on the Mac** — PixelLab tools work.
- **claude.ai/code web sessions** — they do not, and the server shows as failed.
  That is the environment, not the key. Nothing to debug.

## What it is for

CLAUDE.md's hard rule stands: **do not replace or generate art.** The package ships
transparent split frames for actors, enemies, boss, effects and icons, and those are
the game's art. PixelLab covers the gaps the owner has named:

- cleaning up the hero's cutout (the "weird part of all of that kind of photo above
  his head");
- a walk cycle that reads as walking, and a separate dash animation;
- clean animations for the three summons.

Anything past that is a redesign and gets raised first.

## Before installing anything it produces

```bash
python3 tools/validate_sprite_delivery.py <folder-of-frames>
```

That script exists because sprite deliveries have arrived misaligned before, and
the drift is invisible until the character bobs in-game. It checks per-frame height
variance, width variance, and edge contact — the giveaway for a frame cropped
through the character.

`docs/SPRITE_DELIVERY_SPEC.md` is the spec to hand any generator;
`docs/SPRITE_GENERATION_RECIPE.md` covers prompt shape and the pivot rules.
