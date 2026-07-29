#!/usr/bin/env python3
"""Split Project Zero Climb prototype atlases into fixed-size PNG cells."""

from pathlib import Path
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "output" / "level1_prototype"


ATLASES = [
    {
        "source": BASE / "actors" / "PZC_Tower_Exile_Locomotion_Atlas_ALPHA_GRID_v1.png",
        "output": BASE / "actors" / "hero_locomotion_frames",
        "rows": ["south", "southwest", "west", "northwest", "north", "northeast", "east", "southeast"],
        "cols": ["idle", "walk_contact", "walk_passing", "run_extension", "run_recovery"],
        "cell": (162, 242),
    },
    {
        "source": BASE / "actors" / "PZC_Tower_Exile_Action_Atlas_ALPHA_GRID_v1.png",
        "output": BASE / "actors" / "hero_action_frames",
        "rows": ["top", "bottom"],
        "cols": [
            "idle_or_rally",
            "dash_or_focus",
            "dash_streak_or_convergence_start",
            "dash_recover_or_convergence",
            "hurt_or_victory",
            "knockback_or_interact",
            "summon_start_or_revive",
            "summon_release_or_defeat",
        ],
        "cell": (222, 444),
    },
    {
        "source": BASE / "actors" / "PZC_Starter_Summons_Action_Atlas_ALPHA_GRID_v1.png",
        "output": BASE / "actors" / "summon_action_frames",
        "rows": ["rune_hound", "sword_wisp", "gun_construct"],
        "cols": ["idle", "move", "aim_or_windup", "attack", "attack_recover", "hit", "reform"],
        "cell": (220, 342),
    },
    {
        "source": BASE / "enemies" / "PZC_Level1_Enemy_Action_Atlas_ALPHA_v1.png",
        "output": BASE / "enemies" / "enemy_action_frames",
        "rows": ["rift_crawler", "lantern_hexer", "bellguard", "nest_idol", "blade_mite", "siphon_eye"],
        "cols": ["idle", "move_contact", "move_passing", "attack_windup", "attack_active", "death"],
        "cell": (209, 209),
    },
    {
        "source": BASE / "enemies" / "PZC_First_Bell_Action_Atlas_ALPHA_GRID_v1.png",
        "output": BASE / "enemies" / "boss_action_frames",
        "rows": ["the_first_bell"],
        "cols": [
            "idle",
            "move",
            "slam_windup",
            "slam_impact",
            "chain_sweep_windup",
            "bell_toll",
            "stagger_core_open",
            "defeat",
        ],
        "cell": (272, 724),
    },
    {
        "source": BASE / "vfx" / "PZC_Level1_Combat_VFX_Atlas_ALPHA_GRID_v1.png",
        "output": BASE / "vfx" / "vfx_frames",
        "rows": ["friendly_a", "friendly_b", "hostile", "pickup_status"],
        "cols": [f"fx_{index:02d}" for index in range(1, 9)],
        "cell": (222, 222),
    },
    {
        "source": BASE / "ui" / "PZC_Pickup_Relic_Icon_Atlas_ALPHA_GRID_v1.png",
        "output": BASE / "ui" / "icon_frames",
        "rows": ["pickup", "focus_upgrade", "summon_relic", "general_relic"],
        "cols": [f"icon_{index:02d}" for index in range(1, 9)],
        "cell": (222, 222),
    },
]


def split_atlas(spec: dict) -> int:
    image = Image.open(spec["source"]).convert("RGBA")
    cell_w, cell_h = spec["cell"]
    expected = (cell_w * len(spec["cols"]), cell_h * len(spec["rows"]))
    if image.size != expected:
        raise ValueError(f"{spec['source'].name}: expected {expected}, found {image.size}")

    spec["output"].mkdir(parents=True, exist_ok=True)
    count = 0
    for row_index, row_name in enumerate(spec["rows"]):
        for col_index, col_name in enumerate(spec["cols"]):
            box = (
                col_index * cell_w,
                row_index * cell_h,
                (col_index + 1) * cell_w,
                (row_index + 1) * cell_h,
            )
            frame = image.crop(box)
            filename = f"{row_index:02d}_{row_name}__{col_index:02d}_{col_name}.png"
            frame.save(spec["output"] / filename, optimize=True)
            count += 1
    return count


def main() -> None:
    total = 0
    for spec in ATLASES:
        count = split_atlas(spec)
        total += count
        print(f"{spec['source'].name}: {count} frames")
    print(f"Total: {total} frames")


if __name__ == "__main__":
    main()
