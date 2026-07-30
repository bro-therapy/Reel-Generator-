class_name CombatPresentation
extends Node

## Connects the audio and effect layers to combat, in one place.
##
##   var show := CombatPresentation.new()
##   add_child(show)
##   show.bind_boss(boss)
##   show.bind_convergence(convergence)
##   show.bind_enemy(enemy)
##
## Everything here is a *listener*. It subscribes to signals the combat systems
## already emit and turns them into sound and light. It never calls back into
## them, never changes a number, and nothing it does can alter the outcome of a
## fight.
##
## That constraint is the reason this file exists at all rather than the same
## calls being sprinkled through the boss and the summons. Presentation wired into
## behaviour scripts means every future balance change risks a visual regression
## and every visual change risks a balance regression. Keeping it on the outside
## means the combat suites still test combat, and the twelve phases of acceptance
## checks that passed before this existed pass unchanged after it.
##
## It also means presentation is *optional*. A headless acceptance harness simply
## does not create one, which is why none of them had to change.

## Sound and effect for each thing worth showing. Slot names come from
## docs/generated/audio_slots.json; effect ids from data/vfx/realtime/.
##
## Not every event gets an effect — the four generated sheets are what exists, and
## inventing a fifth to fill a row here would be generating art nobody asked for.
const BOSS_MOVES := {
	&"slam": {"sound": &"boss_slam", "effect": &"shockwave", "scale": 1.0},
	&"chain_sweep": {"sound": &"boss_chain_sweep", "effect": &"", "scale": 1.0},
	&"toll": {"sound": &"boss_toll", "effect": &"", "scale": 1.0},
}

var audio: AudioDirector
var vfx: AdditiveVfxPool
var particles: ParticleFx

## Set false to run the game silent and unadorned without tearing the wiring out.
@export var enabled := true

var _bound: Array[Object] = []


func _ready() -> void:
	if audio == null:
		audio = AudioDirector.new()
		audio.name = "Audio"
		add_child(audio)
		audio.initialize()
	if vfx == null:
		vfx = AdditiveVfxPool.new()
		vfx.name = "Vfx"
		add_child(vfx)
		vfx.load_effects()
	if particles == null:
		particles = ParticleFx.new()
		particles.name = "Particles"
		add_child(particles)
		particles.initialize()


# ------------------------------------------------------------------------ boss

## Every per-action feedback the hero produces: muzzle flash and shot sound on
## fire, impact burst on a landed bolt, dash burst, footstep dust. This is the
## binding whose absence the second playtest reported as "I don't see anything
## on the screen" — the weapon had a signal, the audio had the slots, and
## nothing connected them.
func bind_hero(hero: Player) -> void:
	if hero == null:
		return
	var weapon := hero.focus_weapon()
	if weapon != null and not weapon.fired.is_connected(_on_hero_fired):
		weapon.fired.connect(_on_hero_fired.bind(weapon))
	var pool := hero.get_node_or_null("ProjectilePool") as ProjectilePool
	if pool != null and not pool.projectile_impacted.is_connected(_on_hero_bolt_impact):
		pool.projectile_impacted.connect(_on_hero_bolt_impact)
	if not hero.dashed.is_connected(_on_hero_dashed):
		hero.dashed.connect(_on_hero_dashed.bind(hero))
	if not hero.stepped.is_connected(_on_hero_stepped):
		hero.stepped.connect(_on_hero_stepped.bind(hero))


func _on_hero_fired(_target: Node3D, _damage: int, _crit: bool, weapon: FocusWeaponController) -> void:
	if particles != null:
		particles.burst(&"muzzle_violet", weapon.muzzle_position(), weapon.last_fire_direction())
	_sound(&"staff_shot", weapon.muzzle_position())


func _on_hero_bolt_impact(at: Vector3) -> void:
	if particles != null:
		particles.burst(&"impact_violet", at)
	_sound(&"staff_impact", at)


func _on_hero_dashed(hero: Player) -> void:
	if particles != null:
		particles.burst(&"dash_burst", hero.global_position + Vector3(0, 0.25, 0),
			-hero.facing_vector())
	_sound(&"hero_dash", hero.global_position)


func _on_hero_stepped(hero: Player) -> void:
	if particles != null:
		particles.burst(&"dust_puff", hero.global_position + Vector3(0, 0.06, 0))
	_sound(&"hero_step", hero.global_position)


func bind_boss(boss: FirstBellBoss) -> void:
	if boss == null or boss in _bound:
		return
	_bound.append(boss)
	boss.attack_landed.connect(_on_boss_attack.bind(boss))
	boss.staggered.connect(_on_boss_staggered.bind(boss))
	boss.stagger_ended.connect(_on_boss_stagger_ended.bind(boss))
	boss.phase_changed.connect(_on_boss_phase.bind(boss))
	boss.defeated.connect(_on_boss_defeated.bind(boss))
	boss.crawlers_called.connect(_on_crawlers_called.bind(boss))


func _on_boss_attack(kind: StringName, _amount: int, boss: FirstBellBoss) -> void:
	if not enabled:
		return
	var entry: Dictionary = BOSS_MOVES.get(kind, {})
	if entry.is_empty():
		return
	_sound(entry["sound"], _origin(boss))
	if entry["effect"] != &"":
		# Phase two's slam is a wider ring, so the effect grows with it. Guide §11:
		# "a bigger radius, not more damage" — the visual is the only thing that
		# changes, which is exactly what a presentation layer should be doing.
		var grow := 1.25 if boss.phase == FirstBellBoss.Phase.TWO else 1.0
		_effect(entry["effect"], _origin(boss), float(entry["scale"]) * grow)


func _on_boss_staggered(_seconds: float, boss: FirstBellBoss) -> void:
	if not enabled:
		return
	_sound(&"boss_stagger", _origin(boss))
	# The core is exposed, which is the moment the player is meant to read. It gets
	# the fire, warm and hostile, sitting on the boss rather than on the floor.
	_effect(&"fire", _origin(boss), 1.4)


func _on_boss_stagger_ended(boss: FirstBellBoss) -> void:
	if enabled:
		_sound(&"boss_core_break", _origin(boss))


func _on_boss_phase(phase: int, boss: FirstBellBoss) -> void:
	if enabled and phase == 2:
		_sound(&"boss_toll", _origin(boss))


func _on_boss_defeated(boss: FirstBellBoss) -> void:
	if enabled:
		_sound(&"boss_defeat", _origin(boss))


func _on_crawlers_called(_count: int, boss: FirstBellBoss) -> void:
	if enabled:
		_sound(&"rift_entry", _origin(boss))


# ----------------------------------------------------------------- convergence

func bind_convergence(c: ConvergenceController) -> void:
	if c == null or c in _bound:
		return
	_bound.append(c)
	c.triggered.connect(_on_convergence_triggered)
	c.ended.connect(_on_convergence_ended)
	c.signature_fired.connect(_on_signature_fired)


func _on_convergence_triggered(_seconds: float) -> void:
	if enabled:
		_sound(&"convergence_start", Vector3.ZERO, false)


func _on_convergence_ended() -> void:
	if enabled:
		_sound(&"convergence_end", Vector3.ZERO, false)


## One signature per bonded summon. The lightning burst is the friendly effect and
## it is violet by construction — the colour gate in the build tool and the VFX
## suite both refuse it otherwise — so a Convergence cannot come out looking
## hostile however loud it gets.
func _on_signature_fired(spirit_id: StringName) -> void:
	if not enabled:
		return
	_effect(&"lightning", _signature_origin, 1.0)
	match spirit_id:
		&"rune_hound":
			_sound(&"rune_hound_crescent", _signature_origin)
		&"sword_wisp":
			_sound(&"sword_wisp_slash", _signature_origin)
		&"gun_construct":
			_sound(&"gun_construct_burst", _signature_origin)
		_:
			_sound(&"staff_impact", _signature_origin)


## Where signatures appear. Set by whoever owns the fight, since this node has no
## opinion about where the player is standing.
var _signature_origin := Vector3.ZERO


func set_signature_origin(at: Vector3) -> void:
	_signature_origin = at


# --------------------------------------------------------------------- enemies

func bind_enemy(enemy: EnemyBase) -> void:
	if enemy == null or enemy in _bound:
		return
	_bound.append(enemy)
	var family := _slot_family(enemy)
	# Arities match EnemyBase exactly. A lambda with optional parameters does not
	# satisfy a two-argument signal — Godot rejects the connection at emit time,
	# which fails as a runtime error rather than at parse.
	enemy.attack_landed.connect(
		func(_target: Node3D, _amount: int) -> void:
			_sound(StringName("%s_attack" % family), _origin(enemy)))
	enemy.died.connect(
		func(_e: EnemyBase) -> void:
			_sound(StringName("%s_death" % family), _origin(enemy))
			# Warm ember burst — the hostile side's colour, never violet.
			if particles != null:
				particles.burst(&"death_warm", _origin(enemy) + Vector3(0, 0.5, 0)))
	enemy.damaged.connect(
		func(_amount: int, _remaining: int) -> void:
			_sound(StringName("%s_hit" % family), _origin(enemy))
			if particles != null:
				particles.burst(&"hit_warm", _origin(enemy) + Vector3(0, 0.6, 0)))


## The enemy's own id *is* the slot name — `enemy_<id>_<event>` — because the audio
## set is generated from data/enemies/, so a species cannot exist without slots.
##
## No fuzzy matching and no fallback. The first version matched substrings against
## six invented role names and quietly resolved five of the seven real enemies to
## the crawler's sound; every check still passed, because the one enemy under test
## was the crawler. A missing slot now warns by name, once, which is a defect you
## find in a minute instead of a mix that is subtly wrong forever.
func _slot_family(enemy: EnemyBase) -> String:
	return "enemy_%s" % (String(enemy.data.id) if enemy.data != null else "unknown")


# ---------------------------------------------------------------------- helpers

## Positional by default. `at` is ignored for non-positional sounds, which is
## everything that belongs to the player rather than to a place in the room.
func _sound(slot: StringName, at: Vector3, positional: bool = true) -> void:
	if audio == null or slot == &"":
		return
	if positional:
		audio.play_at(slot, at)
	else:
		audio.play(slot)


func _effect(id: StringName, at: Vector3, scale_multiplier: float) -> void:
	if vfx == null or id == &"" or not vfx.has_effect(id):
		return
	vfx.play(id, at, scale_multiplier)


## Nodes added this frame are not in the tree yet, so global_position throws. This
## has bitten this project four times now; every read of a world position from a
## possibly-fresh node goes through here.
static func _origin(node: Object) -> Vector3:
	var n3 := node as Node3D
	if n3 == null:
		return Vector3.ZERO
	return n3.global_position if n3.is_inside_tree() else n3.position


func stop_all() -> void:
	if audio != null:
		audio.stop_all()
	if vfx != null:
		vfx.stop_all()


func bound_count() -> int:
	return _bound.size()
