# Image Generation Record

All new Level 1 images were created with the built-in image-generation workflow. Actor, enemy-action, VFX, and icon sheets were generated on a flat chroma background, converted locally to alpha PNGs, aligned to divisible grids, and split into individual cells.

The prompts below record the final production intent. Every prompt also required no watermark, no logos, original designs, the locked bold 16-bit anime pixel language, and no overlapping cells.

## Tower Exile locomotion atlas

- Reference: approved Tower Exile turnaround and eight-direction sheet.
- Request: eight facing rows in the order south, southwest, west, northwest, north, northeast, east, southeast.
- Frames: idle, walk contact, walk passing, run extension, run recovery.
- Invariants: orange scarf, indigo coat, white hair streak, purple gauntlet, heavy boots, fixed foot pivot, equal scale.
- Background: flat `#00ff00`.

## Tower Exile action atlas

- Reference: approved animation key poses and turnaround.
- Request: idle, dash anticipation/streak/recovery, hurt, knockback, summon start/release, Rally, staff attack, Convergence start/full, victory, interact, revive, defeat.
- Invariants: same hero and proportions; staff only where appropriate; purple effects with blue-white core.
- Background: flat `#00ff00`.

## Starter summon action atlas

- Reference: approved Rune Hound, Sword Wisp, and Gun Construct production sheet.
- Request: one species per row with idle, move, windup/aim, attack, recovery, hit, and reform states.
- Invariants: species silhouettes and relative scales; effects contained inside each cell.
- Background: flat `#00ff00`.

## Starter summon evolution sheet

- Rune Hound -> Volt Hound -> Tempest Fenrir.
- Sword Wisp -> Twin Oath Blades -> Halo Blade Seraph.
- Gun Construct -> Burst Golem -> Arsenal Titan.
- Each row includes one signature attack.
- Final forms remain animation-friendly and below roughly 1.5 times hero height.

## Sunfall Ward enemy lineup

- Rift Crawler: low black-stone chaser with horn plates and red core.
- Lantern Hexer: tall ranged caster with red lantern staff.
- Bellguard: broad tank with cracked bronze bell shield.
- Nest Idol: small spawner carrying a Rift nest.
- Blade Mite: lean dasher with scissor limbs.
- Siphon Eye: floating leech with red tether.
- Gilded Bellguard: gold elite with twin red cores.
- Neutral production-sheet background with attack insets and hero scale silhouette.

## Level 1 enemy action atlas

- One row per enemy in the lineup order.
- Frames: idle, move contact, move passing, red attack windup, attack active, death dissolve.
- Preserve exact lineup silhouettes.
- Background: flat `#00ff00`.

## The First Bell production sheet

- Original towering corrupted guardian fused to a cracked ceremonial bell.
- Bronze/black armor, chained arms, belfry shoulders, red exposed core, restrained violet Rift cracks.
- Turnaround plus stagger, slam, chain sweep, Crawler summon, and defeat poses.
- Approximately 2.5 times hero height.

## The First Bell action atlas

- Eight isolated actions: idle, move, slam windup, slam impact, chain sweep windup, bell toll, exposed-core stagger, and defeat.
- One fixed ground line, consistent boss scale, bronze/black body, red core, restrained violet cracks.
- Converted to transparent alpha and split into individual frames.

## Boss gameplay keyframe

- Tower Exile and three starter summons fighting The First Bell in a circular market-belfry arena.
- Hero uses the locked 88 px target with 10% camera pullback.
- Exposed boss core and red concentric slam telegraph fully visible.
- Friendly violet and hostile red remain separate.

## Sunfall Ward modular kit

- Warm tower-town isometric modules: floors, walls, corners, arch, stairs, low wall, stalls, facade, roofs, balcony, props, fountain, cart, Rift crystals, combat gate, Spirit Well, merchant kiosk, elite gate, boss emblem.
- Consistent isometric angle and warm sandstone/terracotta palette.
- No characters or labels.

## Combat VFX atlas

- Friendly rows: summoning portal sequence, Rune Hound slash, Sword Wisp arc, Gun Construct burst, Rally, staff bolt/impact, dash, Convergence, shield, heal, teleport.
- Hostile row: bullet, orb, cone, circle, dash line, slam, tether, portal.
- Pickup/status row: Spirit Core, essence, coin, level-up, frozen, shocked, weakened, elite.
- Background: flat `#00ff00`.

## Pickup and relic icon atlas

- 32 icons across currency/pickups, Focus upgrades, summon relics, and general relics.
- Bronze-rimmed silhouettes readable at 48 px.
- Background: flat `#00ff00`.

## HUD mockup

- 16:9 controller-first gameplay HUD over Sunfall Ward.
- Health/Stability top left, encounter progress top center, three summons bottom center, Focus bottom left, dash/Rally/Convergence bottom right.
- Center 70% clear.
- Symbols and bars only; no required generated text.

## Reward, Spirit Well, and merchant triptych

- Three-card reward choice.
- Team/evolution screen with three Bond slots.
- Five-offer merchant with reroll and locked item.
- Dark charcoal panels, bronze edging, violet energy, large controller selection focus.
