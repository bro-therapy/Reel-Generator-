# Letting Claude drive the Godot editor on your Mac

Short version: **this only helps on your machine, and it is optional.** Read the
first section before installing anything — it may already be solved for you.

## What is already true

In the cloud sessions we work in, Claude already drives Godot directly. Not
through the editor UI, but through the same Godot binary the editor uses:

- builds the hero and summon SpriteFrames from the split PNGs
- imports assets, regenerates `.import` files and resource UIDs
- runs all 22 acceptance suites (443 checks) and reads the failures
- renders real frames under a virtual display and measures the pixels — the
  colour-ownership suite exists because of this

That is why the screenshots in chat are real captures from the actual game.
Nothing about the sprite work, the effects, the props or the tests needed a
Godot MCP.

**So an MCP server would not have changed any of the work so far**, and
installing one in the cloud container would control a Godot in the cloud, not
the Godot on your Desktop.

## What an MCP server would actually add

It matters in exactly one situation: **you running Claude Code on your own Mac,
with the Godot editor open**, and wanting Claude to click around inside that
editor — select nodes, drag things, adjust an inspector value, see the scene
tree as the editor sees it.

Every Godot MCP server works the same way:

1. a Node.js server process on your Mac
2. an addon inside the Godot project (`addons/godot_mcp/`)
3. the editor **open and running** — the addon cannot work headlessly
4. Claude Code (or Desktop) on the same machine, configured to talk to it

Step 3 is the important one. It is a bridge to a *live editor*, which is the
one thing a cloud session cannot have.

## If you want it anyway

Candidates, all Godot 4.x and MIT-ish licensed. Read their READMEs before
trusting them with your project folder — these are third-party tools, and they
get write access to your game.

| Repo | Notes |
|---|---|
| https://github.com/mkdevkit/godot-mcp | 173 tools, needs Godot **4.4+** (we are on 4.7.1, fine). Requires the addon + editor open. |
| https://github.com/Raunaksplanet/godot-mcp-server | ~40 tools, aims at scenes/scripts/export. |
| https://github.com/hybridindie/godot-mcp | Largest surface, 175 tools. |
| https://github.com/ee0pdt/Godot-MCP | Older, simpler, easy to read end to end. |

Setup, using mkdevkit as the example:

```bash
# 1. get it and build it (needs Node.js installed)
cd ~/Desktop
git clone https://github.com/mkdevkit/godot-mcp.git
cd godot-mcp/server && npm install && npm run build

# 2. put the addon in the game project
cp -R ~/Desktop/godot-mcp/addons/godot_mcp ~/Desktop/project-zero-climb/addons/

# 3. open the project in Godot, then:
#    Project -> Project Settings -> Plugins -> Godot MCP -> Enable
```

Then copy `docs/godot-mcp.mcp.json.example` to `.mcp.json` in the game folder
and fix the path inside it to wherever you cloned the server.

**Why the template is not already `.mcp.json`:** a real `.mcp.json` in the repo
root gets loaded by every Claude Code session in this folder, including cloud
ones, where the path does not exist — so every session would start with a failed
server. Copy it only on the machine where the server actually lives, and keep it
out of git (`.mcp.json` is gitignored for exactly this reason).

## The honest recommendation

You said you are "so bad at Godot". The good news is that the workflow already
requires almost nothing from you in Godot:

```bash
cd ~/Desktop/project-zero-climb
bash tools/update_mac.sh     # pulls the new build + fetches art/music/effects
```

then open the project and press **F5**. That is the whole job. Everything else —
sprite frames, effects, balance, tests — happens on the code side, which is
where Claude is already working.

Install the MCP if you want to *tinker in the editor with help*. Do not install
it expecting it to change how the cloud sessions work; it cannot reach them.
