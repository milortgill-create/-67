class_name Player
extends CharacterBody3D
## Игрок: вид от первого лица, ходьба, камера с покачиванием и тряской,
## руки, захват/бросок предметов и удары по манекенам.

signal message(text: String)

const MOVE_SPEED := 4.2
const GRAVITY := 9.8
const LOOK_SENS := 0.0045
const GRAB_RANGE := 2.8
const PUNCH_RANGE := 2.6
const HOLD_MAX_MASS := 40.0
const THROW_SPEED := 9.0
const PUNCH_IMPULSE := 55.0

const SKIN := Color(0.85, 0.66, 0.52)
const SLEEVE := Color(0.18, 0.22, 0.27)

var touch: TouchControls = null

var head: Node3D
var camera: Camera3D
var hand_anchor: Node3D
var held: RigidBody3D = null

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

	_build_arms()

	hand_anchor = Node3D.new()
	hand_anchor.name = "HandAnchor"
	hand_anchor.position = Vector3(0.22, -0.26, -0.6)
	camera.add_child(hand_anchor)


func _build_arms() -> void:
	var skin_mat := StandardMaterial3D.new()
	skin_mat.albedo_color = SKIN
	skin_mat.roughness = 0.7
	var sleeve_mat := StandardMaterial3D.new()
	sleeve_mat.albedo_color = SLEEVE
	sleeve_mat.roughness = 0.9

	# правая рука (держит предметы)
	_limb(camera, Vector3(0.26, -0.56, -0.12), Vector3(0.31, -0.8, -0.34), 0.05, sleeve_mat)
	_limb(camera, Vector3(0.31, -0.8, -0.34), Vector3(0.23, -0.3, -0.58), 0.042, skin_mat)
	_hand(Vector3(0.23, -0.3, -0.58), skin_mat)
	# левая рука
	_limb(camera, Vector3(-0.26, -0.56, -0.12), Vector3(-0.33, -0.8, -0.34), 0.05, sleeve_mat)
	_limb(camera, Vector3(-0.33, -0.8, -0.34), Vector3(-0.3, -0.36, -0.52), 0.042, skin_mat)
	_hand(Vector3(-0.3, -0.36, -0.52), skin_mat)


func _hand(pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.045
	sm.height = 0.09
	mi.mesh = sm
	mi.material_override = mat
	mi.position = pos
	camera.add_child(mi)


func _limb(parent: Node3D, a: Vector3, b: Vector3, radius: float, mat: Material) -> void:
	## Цилиндрическая «кость» между точками a и b (через CapsuleMesh).
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


func _physics_process(delta: float) -> void:
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


## Вызывается, когда игрока ударили (манекен, летящий предмет).
func take_hit(strength: float) -> void:
	_shake = clampf(maxf(_shake, strength / 6.0), 0.0, 1.0)
	if strength > 3.0:
		message.emit("Вас ударили!")


func _aim_hit(max_dist: float) -> Dictionary:
	var from := camera.global_position
	var to := from + (-camera.global_basis.z) * max_dist
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q)


func get_aim_hint() -> String:
	if held != null:
		return "ДЕЙСТВИЕ — бросить: " + str(held.get_meta("title", "предмет"))
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
	if col.has_meta("pickable") and col.mass <= HOLD_MAX_MASS and dist <= GRAB_RANGE:
		grab_body(col)
	elif col.has_meta("mannequin") and dist <= PUNCH_RANGE:
		var m := col.get_meta("mannequin") as Mannequin
		var fwd := -camera.global_basis.z
		m.punch(col, fwd * PUNCH_IMPULSE + Vector3.UP * 6.0)
		message.emit("Удар!")


func grab_body(body: RigidBody3D) -> void:
	if held != null or body == null:
		return
	held = body
	body.collision_layer = 0  # в руках предмет не сталкивается ни с чем
	body.collision_mask = 0
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.freeze = true
	body.reparent(hand_anchor, false)
	var r: float = body.get_meta("hold_radius", 0.2)
	body.transform = Transform3D(Basis.from_euler(Vector3(-0.9, 0.2, 0.0)), Vector3(0, 0, -r * 0.5))


func release_held() -> void:
	## Отпустить предмет без броска (он просто падает под действием гравитации).
	if held == null:
		return
	var body := held
	held = null
	body.reparent(get_parent(), true)
	body.freeze = false
	body.collision_layer = 1
	body.collision_mask = 1
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO


func _throw_held() -> void:
	var body := held
	var fwd := -camera.global_basis.z
	release_held()
	body.linear_velocity = fwd * THROW_SPEED + Vector3.UP * 2.0 + velocity * 0.3
	body.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
	message.emit("Бросок!")
