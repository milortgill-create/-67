class_name Player
extends CharacterBody3D
## Игрок: вид от первого лица, ходьба, камера с покачиванием и тряской,
## детализированные кисти, физический захват предметов, броски и удары.
##
## Захват: предмет остаётся динамическим RigidBody3D. Каждый физический шаг его
## скорость подгоняется к точке в руке, поэтому он сталкивается со стенами
## и другими предметами, а не проходит сквозь них (как в GoreBox).
## Коллизия «игрок ↔ предмет» отключается на время захвата и броска.

signal message(text: String)
signal hp_changed(value: int)

const MOVE_SPEED := 4.2
const GRAVITY := 9.8
const LOOK_SENS := 0.0045
const GRAB_RANGE := 2.8
const PUNCH_RANGE := 2.6
const HOLD_MAX_MASS := 45.0
const PUNCH_IMPULSE := 55.0
const HOLD_GAIN := 14.0
const MAX_HOLD_SPEED := 14.0
const MAX_HP := 100
const EXEMPT_DIST := 1.0

const SKIN := Color(0.85, 0.66, 0.52)
const SLEEVE := Color(0.18, 0.22, 0.27)

var touch: TouchControls = null
var spawn_position := Vector3.ZERO

var head: Node3D
var camera: Camera3D
var hand_anchor: Node3D
var held: PropBody = null
var hp := MAX_HP

var _exempt: Array[PropBody] = []
var _bob_t := 0.0
var _bob_amp := 0.0
var _shake := 0.0
var _action_prev := false


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

	_build_hands()

	hand_anchor = Node3D.new()
	hand_anchor.name = "HandAnchor"
	hand_anchor.position = Vector3(0.22, -0.27, -0.6)
	camera.add_child(hand_anchor)


# ---------------------------------------------------------------- руки

func _build_hands() -> void:
	var skin := _mat(SKIN, 0.7)
	var sleeve := _mat(SLEEVE, 0.9)
	# правая рука (держит предметы)
	_limb(camera, Vector3(0.26, -0.56, -0.12), Vector3(0.31, -0.8, -0.34), 0.05, sleeve)
	_limb(camera, Vector3(0.31, -0.8, -0.34), Vector3(0.24, -0.31, -0.56), 0.042, skin)
	_fist(Vector3(0.22, -0.27, -0.6), true, skin)
	# левая рука (пустая, расслабленная)
	_limb(camera, Vector3(-0.26, -0.56, -0.12), Vector3(-0.33, -0.8, -0.34), 0.05, sleeve)
	_limb(camera, Vector3(-0.33, -0.8, -0.34), Vector3(-0.3, -0.36, -0.52), 0.042, skin)
	_fist(Vector3(-0.3, -0.36, -0.55), false, skin)


func _fist(center: Vector3, curled: bool, mat: Material) -> void:
	## Кисть из ладони, четырёх пальцев (по три фаланги) и большого пальца.
	## curled = true — кулак, обхватывающий предмет; false — раскрытая ладонь.
	var g := Node3D.new()
	g.name = "Hand"
	g.position = center
	camera.add_child(g)

	var palm := MeshInstance3D.new()
	var pb := BoxMesh.new()
	pb.size = Vector3(0.085, 0.075, 0.06)
	palm.mesh = pb
	palm.material_override = mat
	g.add_child(palm)

	# тыльная сторона кисти: переход от запястья
	var back := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(0.075, 0.03, 0.05)
	back.mesh = bb
	back.material_override = mat
	back.position = Vector3(0, 0.045, 0.03)
	g.add_child(back)

	var knuckle_r := 0.0125
	for x in [-0.03, -0.01, 0.01, 0.03]:
		var base := Vector3(x, 0.02, -0.035)
		var p1: Vector3
		var p2: Vector3
		var p3: Vector3
		if curled:
			p1 = Vector3(x, -0.004, -0.068)
			p2 = Vector3(x, -0.032, -0.078)
			p3 = Vector3(x, -0.044, -0.058)
		else:
			p1 = Vector3(x, 0.0, -0.1)
			p2 = Vector3(x, -0.004, -0.135)
			p3 = Vector3(x, -0.006, -0.16)
		_limb(g, base, p1, 0.011, mat)
		_limb(g, p1, p2, 0.01, mat)
		_limb(g, p2, p3, 0.0095, mat)
		_sphere_at(g, base, knuckle_r, mat)
		_sphere_at(g, p1, knuckle_r * 0.85, mat)

	# большой палец
	if curled:
		_limb(g, Vector3(-0.042, 0.005, -0.012), Vector3(-0.03, 0.035, -0.055), 0.012, mat)
		_limb(g, Vector3(-0.03, 0.035, -0.055), Vector3(-0.012, 0.03, -0.075), 0.0105, mat)
	else:
		_limb(g, Vector3(-0.042, 0.005, -0.012), Vector3(-0.05, 0.02, -0.06), 0.012, mat)
		_limb(g, Vector3(-0.05, 0.02, -0.06), Vector3(-0.05, 0.02, -0.1), 0.0105, mat)


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
	cap.height = a.distance_to(b) + radius * 2.0
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

func _physics_process(delta: float) -> void:
	_update_held()
	_update_exemptions()
	var input := _get_move_input()
	var dir := global_basis * Vector3(input.x, 0.0, input.y)
	dir.y = 0.0
	velocity.x = dir.x * MOVE_SPEED
	velocity.z = dir.z * MOVE_SPEED
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()


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
	if touch != null:
		var look := touch.consume_look()
		rotate_y(-look.x * LOOK_SENS)
		head.rotation.x = clampf(head.rotation.x - look.y * LOOK_SENS, -1.45, 1.45)

	# клавиша E / Space — действие (для ПК)
	var act_now := Input.is_physical_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_SPACE)
	if act_now and not _action_prev:
		on_action()
	_action_prev = act_now

	_update_camera_fx(delta)


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


# ---------------------------------------------------------------- урон

func take_hit(strength: float) -> void:
	## Камера трясётся тем сильнее, чем сильнее удар.
	_shake = clampf(maxf(_shake, strength / 6.0), 0.0, 1.0)
	if strength > 3.0:
		message.emit("Вас ударили!")


func receive_punch(amount: float) -> void:
	## Удар кулаком манекена-бойца.
	take_hit(amount)
	damage(amount)


func receive_object_hit(speed: float, mass: float) -> void:
	## Предмет (или летящий манекен) попал в игрока.
	take_hit(speed)
	damage(clampf(speed * mass * 0.3, 0.0, 20.0))


func damage(amount: float) -> void:
	hp = maxi(0, hp - int(round(amount)))
	hp_changed.emit(hp)
	if hp <= 0:
		_respawn()


func _respawn() -> void:
	release_held()
	hp = MAX_HP
	hp_changed.emit(hp)
	global_position = spawn_position
	velocity = Vector3.ZERO
	message.emit("Вы потеряли сознание — возрождение на старте")


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
		return "ДЕЙСТВИЕ — ударить манекен"
	return ""


## Главное действие: бросить предмет из рук, либо взять/ударить то, на что наведён прицел.
func on_action() -> void:
	if held != null:
		_throw_held()
		return
	var hit := _aim_hit(GRAB_RANGE)
	if hit.is_empty():
		return
	var dist: float = camera.global_position.distance_to(hit["position"])
	var col := hit["collider"] as RigidBody3D
	if col == null:
		return
	if col is PropBody and col.has_meta("pickable") and col.mass <= HOLD_MAX_MASS and dist <= GRAB_RANGE:
		grab_body(col as PropBody)
	elif col.has_meta("mannequin") and dist <= PUNCH_RANGE:
		var m := col.get_meta("mannequin") as Mannequin
		var fwd := -camera.global_basis.z
		m.punch(col, fwd * PUNCH_IMPULSE + Vector3.UP * 6.0)
		message.emit("Удар!")


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
