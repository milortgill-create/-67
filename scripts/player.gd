class_name Player
extends CharacterBody3D
## Игрок: вид от первого лица, ходьба (тяжёлая поклажа замедляет), камера,
## руки-модели с анимацией удара, физический захват предметов, рюкзак, травмы и HP.
##
## Захват: предмет остаётся динамическим RigidBody3D; каждый физический шаг его скорость
## подгоняется к точке в руке, поэтому он сталкивается со стенами и предметами.
## Коллизия «игрок ↔ предмет» отключается на время захвата и броска.

signal message(text: String)
signal hp_changed(value: int)
signal injuries_changed(levels: Dictionary)

const MOVE_SPEED := 4.2
const GRAVITY := 9.8
const LOOK_SENS := 0.0045
const GRAB_RANGE := 2.8
const PUNCH_RANGE := 2.6
const HOLD_MAX_MASS := 45.0
const PUNCH_BASE := 45.0       # импульс обычного удара
const PUNCH_RUN := 110.0       # добавка при ударе с разбега (полный бег)
const HOLD_GAIN := 14.0
const MAX_HOLD_SPEED := 14.0
const MAX_HP := 100
const EXEMPT_DIST := 1.0
const INV_SLOTS := 12
const INV_MAX_ITEM_MASS := 20.0
const CARRY_SLOW_KG := 50.0
const FALL_SAFE_M := 2.0
const SWING_TIME := 0.45
const SWING_IMPACT := 0.17
const HEAL_RATE := 0.015
const INJURY_PARTS := ["head", "torso", "arm_l", "arm_r", "leg_l", "leg_r"]

const SKIN := Color(0.87, 0.68, 0.55)
const SKIN_SHADE := Color(0.78, 0.58, 0.46)
const NAIL := Color(0.9, 0.82, 0.78)
const SLEEVE := Color(0.18, 0.22, 0.27)
const SHOULDER_R := Vector3(0.26, -0.56, -0.12)
const SHOULDER_L := Vector3(-0.26, -0.56, -0.12)
const HAND_R := Vector3(0.22, -0.27, -0.6)
const HAND_L := Vector3(-0.3, -0.36, -0.55)

var touch: TouchControls = null
var spawn_position := Vector3.ZERO
var input_enabled := true

var head: Node3D
var camera: Camera3D
var hand_anchor: Node3D
var arm_rig_r: Node3D
var held: PropBody = null
var hp := MAX_HP
var injuries: Dictionary = {}
var items: Array = []  # [{kind, title, weight, desc}] — рюкзак

var _exempt: Array[PropBody] = []
var _bob_t := 0.0
var _bob_amp := 0.0
var _shake := 0.0
var _action_prev := false
var _falling := false
var _fall_from := 0.0
var _swing_t := -1.0
var _swing_hit_done := false


func _ready() -> void:
	add_to_group("player")
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	add_child(cs)

	head = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 1.6, 0)
	add_child(head)

	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = 75.0
	camera.near = 0.05
	camera.far = 200.0
	head.add_child(camera)
	camera.current = true

	for k in INJURY_PARTS:
		injuries[k] = 0.0
	_build_hands()

	hand_anchor = Node3D.new()
	hand_anchor.name = "HandAnchor"
	hand_anchor.position = HAND_R
	camera.add_child(hand_anchor)


# ---------------------------------------------------------------- руки

func _build_hands() -> void:
	var skin := _mat(SKIN, 0.6)
	var shade := _mat(SKIN_SHADE, 0.7)
	var nail := _mat(NAIL, 0.3)
	var sleeve := _mat(SLEEVE, 0.9)

	# правая рука: вращается вокруг плеча (анимация удара)
	arm_rig_r = Node3D.new()
	arm_rig_r.name = "ArmRigR"
	arm_rig_r.position = SHOULDER_R
	camera.add_child(arm_rig_r)
	var rel := HAND_R - SHOULDER_R
	_sleeve_arm(arm_rig_r, Vector3.ZERO, rel * 0.55 + Vector3(0.0, 0.0, 0.0), sleeve, skin)
	_forearm(arm_rig_r, rel * 0.55, rel, skin, shade)
	_hand(arm_rig_r, rel, true, skin, shade, nail)

	# левая рука (расслабленная, пустая)
	_sleeve_arm(camera, SHOULDER_L, Vector3(-0.33, -0.8, -0.34), sleeve, skin)
	_forearm(camera, Vector3(-0.33, -0.8, -0.34), HAND_L, skin, shade)
	_hand(camera, HAND_L, false, skin, shade, nail)


func _sleeve_arm(parent: Node3D, a: Vector3, b: Vector3, sleeve: Material, _skin: Material) -> void:
	_limb(parent, a, b, 0.055, sleeve)


func _forearm(parent: Node3D, a: Vector3, b: Vector3, skin: Material, shade: Material) -> void:
	## Предплечье — конус из двух капсул (локоть толще, запястье тоньше), тёмная полоса у запястья.
	_limb(parent, a, b, 0.04, skin)
	_limb(parent, a.lerp(b, 0.75), b, 0.03, skin)
	_sphere_at(parent, b, 0.03, shade)  # запястье


func _hand(parent: Node3D, center: Vector3, pointing: bool, skin: Material, shade: Material, nail: Material) -> void:
	## Детализированная кисть: ладонь с мякотью, костяшки, четыре пальца по три фаланги
	## с суставами и ногтями, большой палец с двумя фалангами.
	## pointing=true — правая рука у прицела (кулак, готовый к удару).
	var g := Node3D.new()
	g.name = "Hand"
	g.position = center
	g.rotation.x = 0.25 if pointing else 0.0
	parent.add_child(g)

	_ellipsoid(g, Vector3(0, 0, 0), Vector3(0.042, 0.028, 0.034), skin)        # ладонь
	_ellipsoid(g, Vector3(0, -0.012, 0.012), Vector3(0.036, 0.016, 0.03), shade)  # тыл/мякоть
	# костяшки
	for i in 4:
		_sphere_at(g, Vector3(-0.03 + i * 0.02, 0.0, -0.035), 0.0125, skin)

	for i in 4:
		var x := -0.03 + i * 0.02
		var base := Vector3(x, 0.0, -0.035)
		var p1 := Vector3(x, -0.012, -0.075)     # кулак: пальцы согнуты
		var p2 := Vector3(x, -0.036, -0.088)
		var p3 := Vector3(x, -0.046, -0.068)
		if not pointing:
			p1 = Vector3(x, 0.0, -0.105)         # открытая ладонь: пальцы вытянуты
			p2 = Vector3(x, -0.004, -0.14)
			p3 = Vector3(x, -0.006, -0.165)
		_limb(g, base, p1, 0.0105, skin)
		_limb(g, p1, p2, 0.0098, skin)
		_limb(g, p2, p3, 0.009, skin)
		_sphere_at(g, base, 0.0125, skin)   # сустав ПЯ
		_sphere_at(g, p1, 0.0112, skin)     # сустав ПФ
		_sphere_at(g, p2, 0.0102, skin)     # сустав МФ
		# ноготь на кончике пальца (с тыльной стороны)
		var tip_dir := (p3 - p2).normalized()
		_ellipsoid(g, p3 + Vector3(0, 0.006, 0) + tip_dir * 0.001, Vector3(0.0075, 0.003, 0.0085), nail)

	# большой палец
	var th0 := Vector3(-0.04, 0.0, -0.012)
	var th1 := Vector3(-0.036, 0.034, -0.05) if pointing else Vector3(-0.05, 0.02, -0.07)
	var th2 := Vector3(-0.014, 0.034, -0.078) if pointing else Vector3(-0.05, 0.022, -0.105)
	_limb(g, th0, th1, 0.0128, skin)
	_limb(g, th1, th2, 0.0115, skin)
	_sphere_at(g, th1, 0.0125, skin)
	_ellipsoid(g, th2 + Vector3(0, 0.006, 0), Vector3(0.0078, 0.003, 0.0088), nail)


func _ellipsoid(parent: Node3D, pos: Vector3, radii: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	mi.mesh = sm
	mi.material_override = mat
	mi.transform = Transform3D(Basis.from_scale(radii), pos)
	parent.add_child(mi)


func _sphere_at(parent: Node3D, pos: Vector3, r: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	mi.mesh = sm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


func _limb(parent: Node3D, a: Vector3, b: Vector3, radius: float, mat: Material) -> void:
	## Цилиндрическая «кость» между точками a и b (CapsuleMesh, ориентированный по отрезку).
	var mi := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = radius
	cap.height = maxf(a.distance_to(b), 0.001) + radius * 2.0
	mi.mesh = cap
	mi.material_override = mat
	var y := (b - a).normalized()
	var x := y.cross(Vector3(0, 0, 1))
	if x.length() < 0.01:
		x = y.cross(Vector3(1, 0, 0))
	x = x.normalized()
	var z := x.cross(y).normalized()
	mi.transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)
	parent.add_child(mi)


func _mat(color: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m


# ---------------------------------------------------------------- движение

func carry_weight() -> float:
	## Вес рюкзака + половина веса предмета в руках (его несут, а не тащат).
	var w := 0.0
	for it in items:
		w += float((it as Dictionary)["weight"])
	if held != null:
		w += held.mass * 0.5
	return w


func speed_mult() -> float:
	## Тяжёлая поклажа замедляет: от 100% до 45% скорости.
	return clampf(1.0 - carry_weight() / CARRY_SLOW_KG, 0.45, 1.0)


func _physics_process(delta: float) -> void:
	_update_held()
	_update_exemptions()
	var input := _get_move_input() if input_enabled else Vector2.ZERO
	var dir := global_basis * Vector3(input.x, 0.0, input.y)
	dir.y = 0.0
	var spd := MOVE_SPEED * speed_mult()
	velocity.x = dir.x * spd
	velocity.z = dir.z * spd
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	_track_fall()


func _track_fall() -> void:
	## Падение с высоты больше FALL_SAFE_M ломает ноги и снимает HP.
	var on_floor := is_on_floor()
	if not on_floor and not _falling:
		_falling = true
		_fall_from = global_position.y
	elif on_floor and _falling:
		_falling = false
		var drop := _fall_from - global_position.y
		if drop > FALL_SAFE_M:
			var legs := randf()
			injure("leg_l", 0.5 + legs * 0.2)
			injure("leg_r", 0.5 + (1.0 - legs) * 0.2)
			damage((drop - FALL_SAFE_M) * 15.0)
			take_hit(drop)
			message.emit("Падение с высоты %.1f м!" % drop)


func _get_move_input() -> Vector2:
	if touch != null and touch.move_vector.length() > 0.05:
		return touch.move_vector.limit_length(1.0)
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_D):
		v.x += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		v.x -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		v.y += 1.0
	if Input.is_physical_key_pressed(KEY_W):
		v.y -= 1.0
	return v.normalized()


func _process(delta: float) -> void:
	if touch != null and input_enabled:
		var look := touch.consume_look()
		rotate_y(-look.x * LOOK_SENS)
		head.rotation.x = clampf(head.rotation.x - look.y * LOOK_SENS, -1.45, 1.45)
	elif touch != null:
		touch.consume_look()

	# клавиша E / Space — действие (для ПК)
	var act_now := input_enabled and (Input.is_physical_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_SPACE))
	if act_now and not _action_prev:
		on_action()
	_action_prev = act_now

	_update_swing(delta)
	_update_camera_fx(delta)
	_heal(delta)


func _update_camera_fx(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	var grounded := is_on_floor()
	if grounded and speed > 0.2:
		_bob_t += delta * (speed * 2.6 + 2.0)
	var target_amp := clampf(speed / MOVE_SPEED, 0.0, 1.0) * 0.03 if grounded else 0.0
	_bob_amp = lerpf(_bob_amp, target_amp, clampf(delta * 8.0, 0.0, 1.0))
	var bob := Vector3(cos(_bob_t) * _bob_amp * 0.6, sin(_bob_t * 2.0) * _bob_amp, 0.0)

	_shake = maxf(0.0, _shake - delta * 1.2)
	var sh := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * _shake * 0.06
	camera.position = bob + sh
	camera.rotation.z = sin(_bob_t) * _bob_amp * 0.6 + randf_range(-1.0, 1.0) * _shake * 0.05


# ---------------------------------------------------------------- анимация удара

func _start_swing() -> void:
	_swing_t = 0.0
	_swing_hit_done = false


func _update_swing(delta: float) -> void:
	## Замах (назад), удар (вперёд и вниз), возврат. Попадание — в момент SWING_IMPACT.
	if _swing_t < 0.0:
		return
	_swing_t += delta
	var windup := Vector3(0.9, 0.5, 0.0)
	var strike := Vector3(-1.25, -0.35, 0.0)
	var rot: Vector3
	if _swing_t < SWING_IMPACT:
		rot = Vector3.ZERO.lerp(windup, _swing_t / SWING_IMPACT)
	elif _swing_t < SWING_TIME * 0.5:
		var u := (_swing_t - SWING_IMPACT) / (SWING_TIME * 0.5 - SWING_IMPACT)
		rot = windup.lerp(strike, clampf(u, 0.0, 1.0))
	else:
		var v := (_swing_t - SWING_TIME * 0.5) / (SWING_TIME * 0.5)
		rot = strike.lerp(Vector3.ZERO, clampf(v, 0.0, 1.0))
	arm_rig_r.rotation = rot
	if not _swing_hit_done and _swing_t >= SWING_IMPACT:
		_swing_hit_done = true
		_punch_impact()
	if _swing_t >= SWING_TIME:
		_swing_t = -1.0
		arm_rig_r.rotation = Vector3.ZERO


func _punch_impact() -> void:
	var hit := _aim_hit(PUNCH_RANGE)
	if hit.is_empty():
		message.emit("Мимо")
		return
	var col := hit["collider"] as RigidBody3D
	if col == null or not col.has_meta("mannequin"):
		return
	var m := col.get_meta("mannequin") as Mannequin
	var fwd := -camera.global_basis.z
	# удар с разбега сильнее: при полном беге хватает, чтобы сбить манекен
	var run := clampf(Vector2(velocity.x, velocity.z).length() / MOVE_SPEED, 0.0, 1.0)
	var power := PUNCH_BASE + PUNCH_RUN * run
	m.punch(col, fwd * power + Vector3.UP * 3.0)
	message.emit("Удар!")


# ---------------------------------------------------------------- урон и травмы

func take_hit(strength: float) -> void:
	## Камера трясётся тем сильнее, чем сильнее удар.
	_shake = clampf(maxf(_shake, strength / 6.0), 0.0, 1.0)


func receive_punch(amount: float) -> void:
	## Удар кулаком манекена-бойца: голова или корпус, руки обычно прикрывают.
	take_hit(amount)
	var part: String = ["head", "torso", "arm_l", "arm_r"][randi() % 4]
	injure(part, 0.5)
	damage(amount)
	message.emit("Вас ударили!")


func receive_object_hit(speed: float, mass: float) -> void:
	## Предмет (или летящий манекен) попал в игрока.
	take_hit(speed)
	injure(INJURY_PARTS[randi() % INJURY_PARTS.size()], clampf(speed * mass * 0.04, 0.1, 0.6))
	damage(clampf(speed * mass * 0.3, 0.0, 20.0))


func injure(part: String, amount: float) -> void:
	if not injuries.has(part):
		return
	injuries[part] = minf(1.0, float(injuries[part]) + amount)
	injuries_changed.emit(injuries)


func _heal(delta: float) -> void:
	var changed := false
	for k in injuries.keys():
		var v := float(injuries[k])
		if v > 0.0:
			injuries[k] = maxf(0.0, v - delta * HEAL_RATE)
			changed = true
	if changed:
		injuries_changed.emit(injuries)


func damage(amount: float) -> void:
	hp = maxi(0, hp - int(round(amount)))
	hp_changed.emit(hp)
	if hp <= 0:
		_respawn()


func _respawn() -> void:
	release_held()
	hp = MAX_HP
	hp_changed.emit(hp)
	for k in injuries.keys():
		injuries[k] = 0.0
	injuries_changed.emit(injuries)
	global_position = spawn_position
	velocity = Vector3.ZERO
	message.emit("Вы потеряли сознание — возрождение на старте")


func reset_state() -> void:
	## Полный сброс (кнопка СБРОС): здоровье, травмы, рюкзак и руки.
	release_held()
	items.clear()
	hp = MAX_HP
	hp_changed.emit(hp)
	for k in injuries.keys():
		injuries[k] = 0.0
	injuries_changed.emit(injuries)
	velocity = Vector3.ZERO
	global_position = spawn_position


# ---------------------------------------------------------------- рюкзак

func store_held() -> bool:
	## Положить предмет из рук в рюкзак. Громоздкое (бочка, длинная доска) не влезает.
	if held == null:
		return false
	var b := held
	if items.size() >= INV_SLOTS:
		message.emit("Рюкзак полон")
		return false
	if b.bulky or b.mass > INV_MAX_ITEM_MASS:
		message.emit("Слишком громоздко для рюкзака")
		return false
	items.append({"kind": b.item_kind, "title": b.title, "weight": b.mass, "desc": b.desc})
	release_held()
	b.queue_free()
	message.emit("В рюкзаке: " + b.title)
	return true


func take_item(index: int) -> Dictionary:
	## Достать предмет из рюкзака. Возвращает его запись (kind для спавна в мире) или {}.
	if index < 0 or index >= items.size():
		return {}
	var it: Dictionary = items[index]
	items.remove_at(index)
	return it


# ---------------------------------------------------------------- прицел и действия

func _aim_hit(max_dist: float) -> Dictionary:
	var from := camera.global_position
	var to := from + (-camera.global_basis.z) * max_dist
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q)


func get_aim_hint() -> String:
	if held != null:
		return "ДЕЙСТВИЕ — бросить: " + str(held.title)
	var hit := _aim_hit(GRAB_RANGE)
	if hit.is_empty():
		return ""
	var col := hit["collider"] as RigidBody3D
	if col == null:
		return ""
	if col.has_meta("pickable") and col.mass <= HOLD_MAX_MASS:
		return "ДЕЙСТВИЕ — взять: " + str(col.get_meta("title", ""))
	if col.has_meta("mannequin"):
		return "ДЕЙСТВИЕ — ударить (замах)"
	return ""


func on_action() -> void:
	## Действие: бросок из рук; взять предмет по прицелу; иначе — удар рукой (с замахом).
	if not input_enabled:
		return
	if held != null:
		_throw_held()
		return
	var hit := _aim_hit(GRAB_RANGE)
	if not hit.is_empty():
		var col := hit["collider"] as RigidBody3D
		var dist: float = camera.global_position.distance_to(hit["position"])
		if col is PropBody and col.has_meta("pickable") and col.mass <= HOLD_MAX_MASS and dist <= GRAB_RANGE:
			grab_body(col as PropBody)
			return
	if _swing_t < 0.0:
		_start_swing()


# ---------------------------------------------------------------- захват и бросок

func grab_body(body: PropBody) -> void:
	if held != null or body == null:
		return
	held = body
	body.is_held = true
	body.add_collision_exception_with(self)
	if not _exempt.has(body):
		_exempt.append(body)


func release_held() -> void:
	## Отпустить предмет без броска: он просто падает под действием гравитации.
	if held == null:
		return
	held.is_held = false
	held = null


func _throw_held() -> void:
	var body := held
	var fwd := -camera.global_basis.z
	# тяжёлые предметы летят медленнее
	var speed := lerpf(10.0, 5.0, clampf(body.mass / 40.0, 0.0, 1.0))
	release_held()
	body.linear_velocity = fwd * speed + Vector3.UP * 2.0 + velocity * 0.3
	body.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
	message.emit("Бросок!")


func _hold_target() -> Transform3D:
	var r := 0.2
	if held != null:
		r = held.hold_radius
	return hand_anchor.global_transform * Transform3D(Basis.from_euler(Vector3(-0.9, 0.2, 0.0)), Vector3(0, 0, -r * 0.5))


func _update_held() -> void:
	if held != null and not is_instance_valid(held):
		held = null
	if held == null:
		return
	# предмет подгоняется по скорости к точке в руке — остаётся физическим телом
	var target := _hold_target()
	var lin := (target.origin - held.global_position) * HOLD_GAIN
	if lin.length() > MAX_HOLD_SPEED:
		lin = lin.normalized() * MAX_HOLD_SPEED
	held.linear_velocity = lin + velocity
	var qt := target.basis.get_rotation_quaternion()
	var qb := held.global_transform.basis.get_rotation_quaternion()
	var qe := qt * qb.inverse()
	var angle := qe.get_angle()
	var axis := qe.get_axis()
	if angle > PI:
		angle = TAU - angle
		axis = -axis
	var av := axis * angle * 12.0
	if av.length() > 20.0:
		av = av.normalized() * 20.0
	held.angular_velocity = av


func _update_exemptions() -> void:
	## Коллизия с игроком отключена, пока предмет рядом (в руках или только что брошен).
	for b in _exempt.duplicate():
		if not is_instance_valid(b):
			_exempt.erase(b)
			continue
		if b == held:
			continue
		var d := Vector2(b.global_position.x - global_position.x, b.global_position.z - global_position.z).length()
		if d > EXEMPT_DIST:
			b.remove_collision_exception_with(self)
			_exempt.erase(b)
