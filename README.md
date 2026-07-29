# Game

A Godot 4 game project. Early stage — the scaffold runs, the design is open.

## Requirements

- [Godot 4.3+](https://godotengine.org/download) (standard build, no C# needed)
- [Git LFS](https://git-lfs.com) — **install before committing any art or audio**

```bash
git lfs install
```

## Running it

Open the project folder in Godot, or from the command line:

```bash
godot --path .
```

Press F5 in the editor. You should get a dark window with a blue square you can
move using the arrow keys or WASD.

## Layout

```
project.godot       ← engine config, entry point
scenes/
  main.tscn         ← root scene, loaded on start
  player.tscn       ← placeholder player
scripts/
  main.gd           ← global setup
  player.gd         ← 8-directional movement
assets/             ← art, audio, fonts (tracked via Git LFS)
```

## Assets and repo size

Art and audio are routed through Git LFS via `.gitattributes`. Godot's own
`.tscn` / `.tres` / `.gd` files stay as plain text so they diff and merge
properly.

Two rules worth keeping:

1. **Run `git lfs install` before your first asset commit.** LFS can't
   retroactively fix files already in history.
2. **Never commit exports or build output.** `.gitignore` covers the usual
   suspects, but check `git status` before committing after an export.

This repo previously held an unrelated project that reached 556MB of history by
committing generated video directly. Recovering from that meant discarding the
history entirely. The LFS setup above exists so that doesn't happen twice.

## Status

The scaffold was written by hand and has not been opened in the Godot editor
yet. On first open, Godot will regenerate resource UIDs and rewrite
`project.godot` with its full default set — that's expected, and the resulting
diff is safe to commit.
