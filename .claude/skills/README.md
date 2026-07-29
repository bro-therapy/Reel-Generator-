# Installed skills

Third-party Godot and game-design skills, curated for Project Zero Climb. These load
on demand — Claude picks one when a task matches its description.

## Provenance

| Source | License | Skills taken |
|---|---|---|
| [jame581/GodotPrompter](https://github.com/jame581/GodotPrompter) | MIT | 27 Godot-technical |
| [gamedev-skills/awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills) | Apache-2.0 | 5 design disciplines |

Full license texts: `LICENSE-GodotPrompter-MIT.txt`,
`LICENSE-awesome-gamedev-Apache-2.0.txt`, `NOTICE-awesome-gamedev.txt`.

## What was deliberately NOT installed

**Hooks.** GodotPrompter ships a `SessionStart` hook (`hooks/hooks.json`) that runs a
command on every startup, resume, clear, and compact, plus a `PostToolUse` hook in its
own `.claude/settings.json` that fires on every Edit and Write. Neither was installed —
only the `skills/` directory was copied. If you ever want the hook's skill-routing
behavior, install it deliberately and read `hooks/run-hook.cmd` first.

**Overlapping skills.** Where both repos covered the same ground (camera, input,
performance), the GodotPrompter version was kept — it's deeper per topic. The
awesome-gamedev picks are the engine-agnostic design skills that don't overlap.

**Irrelevant skills.** Skipped C#, mobile, XR, multiplayer, dedicated-server,
GDExtension, localization, 2D movement, tilemap, inventory, dialogue, and procedural
generation — none apply to this project. Also skipped third-party addon skills
(LimboAI, Beehave, PhantomCamera, Popochiu) since the project doesn't use those addons.

## Audit performed at install

- All 32 skills have valid frontmatter (`name` + `description`).
- Every file is Markdown. No scripts, no executables, no exec bits.
- No SKILL.md references `curl`, `wget`, `pip install`, `npm install`, or `subprocess`.

## Standing caution

Skill files are instructions that enter the context when triggered. These come from
third parties and were reviewed at install, but they are not covered by this project's
review process on future updates. If you re-pull either repo, re-audit before trusting
new content — particularly anything that adds hooks or scripts.

## Coverage gaps

Research turned up nothing for two things this project actually needs:

1. **Safe hand-editing of `.tscn` / `.tres` text formats.** Every existing skill that
   manipulates scene files does it through an MCP server driving a live Godot editor.
   Since this environment has no Godot binary, scene files here are written by hand —
   an area with no skill coverage anywhere.
2. **Sprite pipeline that closes the loop to Godot.** Asset skills stop at PNG + JSON
   manifest; none generate `SpriteFrames` or `AtlasTexture` resources. Given this
   project imports ~185 split frames per `ASSET_MANIFEST.json`, that importer is
   custom work.
