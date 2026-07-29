class_name AssetCheck
extends RefCounted

## Reports whether this checkout has its art and audio.
##
## assets/ is gitignored while LFS upload is blocked from the build environment,
## so a fresh clone is a working game with no pictures in it. That is a supported
## state — everything boots, every scene loads, every acceptance suite passes or
## skips — but it looks exactly like a broken build if nobody says so.
##
## Godot's own message for this is 72 lines of "Resource file not found" scrolled
## past before the window opens. This turns that into one paragraph naming the fix.

const PROBES := {
	"hero and summon frames": "res://assets/actors",
	"enemy and boss frames": "res://assets/enemies",
	"effect atlases": "res://assets/vfx",
	"UI art": "res://assets/ui",
	"placeholder audio": "res://assets/audio",
}


static func missing_groups() -> Array[String]:
	var missing: Array[String] = []
	for label in PROBES:
		var dir := DirAccess.open(PROBES[label])
		# Absent, or present but empty — an empty directory survives a checkout in
		# ways that read as "there but broken" rather than "not fetched".
		if dir == null or (dir.get_files().is_empty() and dir.get_directories().is_empty()):
			missing.append(label)
	return missing


static func has_assets() -> bool:
	return missing_groups().is_empty()


## One block of text, or "" when everything is present. Returned rather than
## printed so the caller decides where it goes — stdout on boot, a Label in a
## later title screen.
static func report() -> String:
	var missing := missing_groups()
	if missing.is_empty():
		return ""
	var lines: Array[String] = []
	lines.append("")
	lines.append("  ┌─ This checkout has no art or audio " + "─".repeat(30))
	lines.append("  │")
	lines.append("  │  Missing: %s" % ", ".join(missing))
	lines.append("  │")
	lines.append("  │  The game still runs and every scene loads — the actors are")
	lines.append("  │  just invisible. assets/ is gitignored because Git LFS upload")
	lines.append("  │  is blocked from the build environment.")
	lines.append("  │")
	lines.append("  │  To fix it:")
	lines.append("  │      ./tools/fetch_assets.sh <bundle-url-or-zip>")
	lines.append("  │      godot --headless --path . --import")
	lines.append("  │")
	lines.append("  │  See docs/ASSET_DELIVERY.md.")
	lines.append("  └" + "─".repeat(65))
	lines.append("")
	return "\n".join(lines)
