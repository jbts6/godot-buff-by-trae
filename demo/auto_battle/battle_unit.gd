extends CharacterBody2D

signal died(unit)
signal hit_dealt(attacker, target, damage)

var entity_id: int
var camp: String
var stats
var buffs
var ds
var enums_rt
var pipe
var replay

var max_hp: float = 100.0
var move_speed: float = 120.0
var attack_range: float = 36.0
var attack_cooldown: float = 0.8
var attack_damage: float = 10.0
var chase_range: float = 2000.0

var _hp: float = 100.0
var _target = null
var _attack_timer: float = 0.0
var _is_dead: bool = false
var _flash_timer: float = 0.0
var _state: String = "idle"
var _battle_active: bool = false

var _body: ColorRect
var _hp_bar: ProgressBar
var _name_label: Label
var _dmg_label: Label
var _collision_shape: CollisionShape2D

func setup(eid: int, c: String, dataset, enums_runtime, start_pos: Vector2) -> void:
	entity_id = eid
	camp = c
	ds = dataset
	enums_rt = enums_runtime
	position = start_pos

	stats = OmniStatsComponent.new(eid, ds)
	buffs = OmniBuffCore.new(ds, enums_rt)
	pipe = OmniDamagePipeline.new()
	replay = OmniReplay.new()

	var hp_id = int(ds.stat_id("HP"))
	var atk_id = int(ds.stat_id("ATK"))
	if hp_id >= 0:
		max_hp = float(stats.get_final(hp_id))
	else:
		stats.add_base(int(ds.stat_id("HP")), max_hp)
	if atk_id >= 0:
		attack_damage = 0.0
	_hp = max_hp
	_build_visuals()

func set_battle_active(active: bool) -> void:
	_battle_active = active
	if not active:
		velocity = Vector2.ZERO
		_state = "idle"

func _build_visuals() -> void:
	_collision_shape = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(32, 32)
	_collision_shape.shape = shape
	add_child(_collision_shape)

	_body = ColorRect.new()
	_body.size = Vector2(32, 32)
	_body.position = Vector2(-16, -16)
	if camp == "ally":
		_body.color = Color(0.2, 0.6, 1.0)
	else:
		_body.color = Color(1.0, 0.3, 0.2)
	add_child(_body)

	var icon = TextureRect.new()
	icon.texture = load("res://icon.svg")
	icon.size = Vector2(24, 24)
	icon.position = Vector2(-12, -12)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(icon)

	_hp_bar = ProgressBar.new()
	_hp_bar.min_value = 0.0
	_hp_bar.max_value = max_hp
	_hp_bar.value = max_hp
	_hp_bar.custom_minimum_size = Vector2(40, 6)
	_hp_bar.position = Vector2(-20, -28)
	_hp_bar.show_percentage = false
	var style_bg = StyleBoxFlat.new()
	style_bg.bg_color = Color(0.2, 0.2, 0.2)
	_hp_bar.add_theme_stylebox_override("background", style_bg)
	var style_fill = StyleBoxFlat.new()
	if camp == "ally":
		style_fill.bg_color = Color(0.2, 0.8, 0.2)
	else:
		style_fill.bg_color = Color(0.8, 0.2, 0.2)
	_hp_bar.add_theme_stylebox_override("fill", style_fill)
	add_child(_hp_bar)

	_name_label = Label.new()
	if camp == "ally":
		_name_label.text = "Ally-%d" % entity_id
	else:
		_name_label.text = "Enemy-%d" % entity_id
	_name_label.position = Vector2(-20, -44)
	_name_label.add_theme_font_size_override("font_size", 10)
	add_child(_name_label)

	_dmg_label = Label.new()
	_dmg_label.text = ""
	_dmg_label.position = Vector2(-10, -60)
	_dmg_label.add_theme_font_size_override("font_size", 14)
	_dmg_label.visible = false
	add_child(_dmg_label)

func _physics_process(delta: float) -> void:
	if _is_dead or ds == null or not _battle_active:
		return

	_attack_timer = max(0.0, _attack_timer - delta)

	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_body.color = Color(0.2, 0.6, 1.0) if camp == "ally" else Color(1.0, 0.3, 0.2)

	_update_ai()

	match _state:
		"chase":
			_chase_target(delta)
		"attack":
			_try_attack()
		"idle":
			pass

func _update_ai() -> void:
	if _target == null or not is_instance_valid(_target) or _target._is_dead:
		_target = _find_nearest_enemy()
	if _target == null:
		_state = "idle"
		return

	var dist = position.distance_to(_target.position)
	if dist <= attack_range:
		_state = "attack"
	else:
		_state = "chase"

func _find_nearest_enemy():
	var best = null
	var best_dist = chase_range
	var all_units = get_parent().get_children()
	for u in all_units:
		if u == self or not u.has_method("take_damage"):
			continue
		if u.camp == camp:
			continue
		if u._is_dead:
			continue
		var d = position.distance_to(u.position)
		if d < best_dist:
			best_dist = d
			best = u
	return best

func _chase_target(delta: float) -> void:
	if _target == null:
		return
	var direction = (_target.position - position).normalized()
	velocity = direction * move_speed
	move_and_slide()

func _try_attack() -> void:
	if _attack_timer > 0.0:
		return
	if _target == null or _target._is_dead:
		return

	_attack_timer = attack_cooldown

	var base_dmg = attack_damage
	var atk_id = int(ds.stat_id("ATK"))
	if atk_id >= 0:
		base_dmg = float(stats.get_final(atk_id))

	var runtime_dict = {
		"stats_by_entity": {},
		"buff_by_entity": {},
	}
	var all_units = get_parent().get_children()
	for u in all_units:
		if u.has_method("take_damage") and not u._is_dead:
			runtime_dict["stats_by_entity"][u.entity_id] = u.stats
			runtime_dict["buff_by_entity"][u.entity_id] = u.buffs

	var dctx = pipe.deal_damage(
		stats,
		_target.stats,
		buffs,
		_target.buffs,
		ds,
		base_dmg,
		replay,
		0,
		0,
		runtime_dict,
		0,
		-1,
		0,
		0,
		false
	)

	var final_dmg = float(dctx.final_damage)
	_target.take_damage(final_dmg, self)
	hit_dealt.emit(self, _target, final_dmg)

	_do_ram_animation()

func _do_ram_animation() -> void:
	if _target == null:
		return
	var orig_pos = position
	var dir = (_target.position - position).normalized()
	var lunge = dir * 8.0
	position += lunge
	var tween = create_tween()
	tween.tween_property(self, "position", orig_pos, 0.15).set_ease(Tween.EASE_OUT)

func take_damage(amount: float, attacker = null) -> void:
	if _is_dead:
		return
	_hp = max(0.0, _hp - amount)
	_hp_bar.value = _hp

	_body.color = Color(1.0, 1.0, 1.0)
	_flash_timer = 0.12

	_show_damage_number(int(ceil(amount)))

	if _hp <= 0.0:
		_die()

func _show_damage_number(dmg: int) -> void:
	_dmg_label.text = "-%d" % dmg
	_dmg_label.visible = true
	_dmg_label.modulate = Color(1.0, 0.2, 0.2)
	_dmg_label.position = Vector2(-10, -60)
	var tween = create_tween()
	tween.tween_property(_dmg_label, "position:y", -90.0, 0.6).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_dmg_label, "modulate:a", 0.0, 0.6).set_delay(0.3)
	tween.tween_callback(func(): _dmg_label.visible = false)

func _die() -> void:
	_is_dead = true
	_state = "dead"
	velocity = Vector2.ZERO
	_body.color = Color(0.3, 0.3, 0.3)
	_body.modulate.a = 0.5
	_hp_bar.visible = false
	_name_label.text += " [DEAD]"
	died.emit(self)

func is_dead() -> bool:
	return _is_dead

func get_speed() -> float:
	return move_speed
