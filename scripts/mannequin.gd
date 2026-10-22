class_name Mannequin
extends Node3D
## Манекен из 11 капсульных частей, соединённых шарнирами Generic6DOF с пределами углов.
##
## Состояния:
##   STAND   — стоит (части заморожены, поза можно анимировать);
##   RAGDOLL — физический труп: части динамические, падает и кувыркается;
##   GETUP   — встаёт: части плавно переходят в стойку.
##
## Виды:
##   PASSIVE    — не агрессивен. Если сбит, встаёт, когда игрок подходит близко.
##   AGGRESSIVE — видит игрока в радиусе, идёт к нему и бьёт. Сбитый — встаёт сам.
##
## Системы координат: части — дети корня (Mannequin). Стойка задаётся
## rest_xf[i] (локальный трансформ относительно корня). Корень — «тело» на полу.
## Вперёд манекена — локальная +Z.

const PASSIVE := 0
const AGGRESSIVE := 1

const STAND := 0
const RAGDOLL := 1
const GETUP := 2

const BODY_COLOR := Color(0.92, 0.9, 0.86)
const JOINT_COLOR := Color(0.16, 0.16, 0.18)
const WALK_SPEED := 1.5
const SENSE_RANGE := 9.0
const ATTACK_RANGE := 1.2
const PUNCH_COOLDOWN := 1.3
const PUNCH_DAMAGE := 8.0
const GETUP_TIME := 1.2

var kind := PASSIVE
var state := STAND
var parts: Array[RigidBody3D] = []
var rest_xf: Array[Transform3D] = []
var part_map: Dictionary = {}
var rest_map: Dictionary = {}
var spawn_xf := Transform3D.IDENTITY

var _pend_part: RigidBody3D = null
var _pend_impulse := Vector3.ZERO
var _settle_t := 0.0
var _getup_t := 0.0
var _getup_from: Array[Transform3D] = []
var _getup_to := Transform3D.IDENTITY
var _phase := 0.0
var _punch_t := -1.0
var _punch_cd := 0.0
var _punch_done := false


func _ready() -> void:
	spawn_xf = transform
	_build()


# ---------------------------------------------------------------- сборка

func _make_part(part_name: String, mass: float, pos: Vector3, radius: float, height: float) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.name = part_name
	b.mass = mass
	b.continuous_cd = true
	b.contact_monitor = true
	b.max_contacts_reported = 4
	b.freeze = true
	b.position = pos
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = radius
	cm.height = height
	mi.mesh = cm
	mi.material_override = _mat(BODY_COLOR, 0.6)
	b.add_child(mi)
	var cs := CollisionShape3D.new()
	var cshape := CapsuleShape3D.new()
	cshape.radius = radius
	cshape.height = height
	cs.shape = cshape
	b.add_child(cs)
	b.set_meta("mannequin", self)
	b.body_entered.connect(_on_part_contact.bind(b))
	add_child(b)
	parts.append(b)
	part_map[part_name] = b
	return b


func _build() -> void:
	_make_part("Head", 4.0, Vector3(0, 1.66, 0), 0.1, 0.26)
	_make_part("Torso", 12.0, Vector3(0, 1.27, 0), 0.17, 0.52)
	_make_part("Pelvis", 8.0, Vector3(0, 0.93, 0), 0.15, 0.22)
	for s in [-1.0, 1.0]:
		var sfx := "L" if s < 0 else "R"
		_make_part("Arm" + sfx, 2.0, Vector3(0.3 * s, 1.27, 0), 0.055, 0.36)
		_make_part("Fore" + sfx, 1.5, Vector3(0.3 * s, 0.85, 0), 0.05, 0.32)
		_make_part("Thigh" + sfx, 5.0, Vector3(0.11 * s, 0.6, 0), 0.075, 0.5)
		_make_part("Shin" + sfx, 3.0, Vector3(0.11 * s, 0.21, 0), 0.065, 0.42)

	# шарниры с пределами углов (положительная сторона — назад/наружу)
	var head: RigidBody3D = part_map["Head"]
	var torso: RigidBody3D = part_map["Torso"]
	var pelvis: RigidBody3D = part_map["Pelvis"]
	_joint(torso, head, Vector3(0, 1.53, 0), [-0.6, 0.6, -0.9, 0.9, -0.5, 0.5])   # шея
	_joint(pelvis, torso, Vector3(0, 1.03, 0), [-0.5, 0.5, -0.3, 0.3, -0.4, 0.4])  # позвоночник
	for s in [-1.0, 1.0]:
		var sfx := "L" if s < 0 else "R"
		var arm: RigidBody3D = part_map["Arm" + sfx]
		var fore: RigidBody3D = part_map["Fore" + sfx]
		var thigh: RigidBody3D = part_map["Thigh" + sfx]
		var shin: RigidBody3D = part_map["Shin" + sfx]
		# плечо: сгиб вперёд до ~160°, назад ~50°, отведение до ~125°
		_joint(torso, arm, Vector3(0.27 * s, 1.42, 0), [-2.8, 0.9, -1.2, 1.2, -2.2, 2.2])
		# локоть: сгибается только вперёд (до ~130°)
		_joint(arm, fore, Vector3(0.3 * s, 1.05, 0), [-2.3, 0.05, -0.2, 0.2, -0.1, 0.1])
		# бедро: сгиб вперёд ~115°, назад ~20°
		_joint(pelvis, thigh, Vector3(0.11 * s, 0.84, 0), [-2.0, 0.35, -0.6, 0.6, -0.5, 0.5])
		# колено: сгибается только назад (до ~130°)
		_joint(thigh, shin, Vector3(0.11 * s, 0.37, 0), [0.0, 2.3, -0.1, 0.1, -0.1, 0.1])

	for p in parts:
		rest_xf.append(p.transform)
		rest_map[str(p.name)] = p.transform

	_add_details()


func _joint(a: RigidBody3D, b: RigidBody3D, at: Vector3, lim: Array) -> void:
	var j := Generic6DOFJoint3D.new()
	j.position = at
	add_child(j)
	j.node_a = j.get_path_to(a)
	j.node_b = j.get_path_to(b)
	j.exclude_nodes_from_collision = true
	# линейные степени свободы заблокированы — части не отрываются друг от друга
	j.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
	j.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
	j.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
	j.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
	j.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
	j.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
	j.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
	j.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
	j.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
	# угловые пределы
	j.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	j.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	j.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	j.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, lim[0])
	j.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, lim[1])
	j.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, lim[2])
	j.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, lim[3])
	j.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, lim[4])
	j.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, lim[5])


func _add_details() -> void:
	## Видимые суставы, лицо, ступни и кисти — чтобы манекен не был «белой колбаской».
	var joint_mat := _mat(JOINT_COLOR, 0.5)
	var dark := _mat(Color(0.1, 0.1, 0.12), 0.7)
	var belt := _mat(Color(0.25, 0.2, 0.15), 0.8)
	var head: RigidBody3D = part_map["Head"]
	var torso: RigidBody3D = part_map["Torso"]
	var pelvis: RigidBody3D = part_map["Pelvis"]

	# лицо (перёд — +Z)
	for ex in [-0.035, 0.035]:
		_vis(head, _sphere(0.018), dark, Vector3(ex, 0.03, 0.09))
	_vis(head, _box(Vector3(0.02, 0.04, 0.02)), _mat(BODY_COLOR, 0.6), Vector3(0, -0.005, 0.1))
	_vis(head, _cyl(0.04, 0.08), joint_mat, Vector3(0, -0.13, 0))  # шея между головой и торсом

	# торс: грудная пластина и плечевые суставы
	_vis(torso, _box(Vector3(0.28, 0.34, 0.02)), _mat(Color(0.95, 0.94, 0.9), 0.5), Vector3(0, 0.02, 0.165))
	for s in [-1.0, 1.0]:
		_vis(torso, _sphere(0.06), joint_mat, Vector3(0.27 * s, 0.15, 0))
	# таз: пояс и тазобедренные суставы
	_vis(pelvis, _cyl(0.16, 0.05), belt, Vector3(0, 0.07, 0))
	for s in [-1.0, 1.0]:
		_vis(pelvis, _sphere(0.06), joint_mat, Vector3(0.11 * s, -0.09, 0))

	for s in [-1.0, 1.0]:
		var sfx := "L" if s < 0 else "R"
		var arm: RigidBody3D = part_map["Arm" + sfx]
		var fore: RigidBody3D = part_map["Fore" + sfx]
		var thigh: RigidBody3D = part_map["Thigh" + sfx]
		var shin: RigidBody3D = part_map["Shin" + sfx]
		_vis(arm, _sphere(0.05), joint_mat, Vector3(0, -0.22, 0))  # локоть
		_vis(fore, _sphere(0.058), _mat(BODY_COLOR, 0.6), Vector3(0, -0.2, 0))  # кисть-кулак
		_vis(fore, _box(Vector3(0.09, 0.07, 0.07)), _mat(BODY_COLOR, 0.6), Vector3(0, -0.23, 0))
		_vis(thigh, _sphere(0.06), joint_mat, Vector3(0, -0.23, 0))  # колено
		_vis(shin, _box(Vector3(0.11, 0.06, 0.25)), dark, Vector3(0, -0.19, 0.06))  # ступня
		_vis(shin, _sphere(0.045), joint_mat, Vector3(0, -0.12, 0))  # голеностоп


func _vis(part: RigidBody3D, mesh: Mesh, mat: Material, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	part.add_child(mi)


func _mat(color: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m


func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	return m


func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


func _cyl(r: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	return m


# ---------------------------------------------------------------- поза

static func _rot_x(p: Vector3, ang: float) -> Transform3D:
	## Поворот вокруг оси X, проходящей через точку p (в координатах корня).
	return Transform3D(Basis(Vector3.RIGHT, ang), p) * Transform3D(Basis(), -p)


func _place(part_name: String, t: Transform3D) -> void:
	var p: RigidBody3D = part_map[part_name]
	p.transform = t * (rest_map[part_name] as Transform3D)


func _set_side(s: float, hip: float, knee: float, shoulder: float) -> void:
	var sfx := "L" if s < 0 else "R"
	var hip_p := Vector3(0.11 * s, 0.84, 0)
	var knee_p := Vector3(0.11 * s, 0.37, 0)
	var h := _rot_x(hip_p, hip)
	_place("Thigh" + sfx, h)
	var k := _rot_x(h * knee_p, knee)
	_place("Shin" + sfx, k * h)
	var sh := _rot_x(Vector3(0.27 * s, 1.42, 0), shoulder)
	_place("Arm" + sfx, sh)
	_place("Fore" + sfx, sh)


## phase — фаза походки; amp — амплитуда качания ног; punch — 0..1, выброс правой руки.
func _apply_pose(phase: float, amp: float, punch: float) -> void:
	var sw := sin(phase) * amp
	var kn := 0.9 * (amp / 0.3)
	var kl := maxf(0.0, -sin(phase)) * kn
	var kr := maxf(0.0, sin(phase)) * kn
	_set_side(-1.0, sw, kl, -sw * 0.6)
	_set_side(1.0, -sw, kr, lerpf(sw * 0.6, -1.5, punch))


# ---------------------------------------------------------------- управление

func punch(part: RigidBody3D, impulse: Vector3) -> void:
	## Удар игрока: часть получает импульс, манекен становится ragdoll.
	activate()
	_pend_part = part
	_pend_impulse = impulse


func activate() -> void:
	if state == RAGDOLL:
		return
	state = RAGDOLL
	_settle_t = 0.0
	_punch_t = -1.0
	for p in parts:
		p.freeze = false
		p.sleeping = false


func _get_player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D


func _physics_process(delta: float) -> void:
	if _pend_part != null:
		# импульс — на следующем шаге, уже после разморозки
		_pend_part.apply_central_impulse(_pend_impulse)
		_pend_part.apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 4.0)
		_pend_part = null

	var player := _get_player()
	if state == STAND:
		_tick_stand(delta, player)
	elif state == RAGDOLL:
		_tick_ragdoll(player)
	else:
		_tick_getup(delta)


func _flat_to(player: Node3D) -> Vector3:
	var to := player.global_position - global_position
	to.y = 0.0
	return to


func _tick_stand(delta: float, player: Node3D) -> void:
	if kind == PASSIVE or player == null:
		return
	var to := _flat_to(player)
	var dist := to.length()
	if dist > SENSE_RANGE:
		_phase = 0.0
		_apply_pose(0.0, 0.0, 0.0)
		return
	# поворачиваемся к игроку (вперёд манекена — +Z)
	rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), clampf(delta * 5.0, 0.0, 1.0))

	if dist > ATTACK_RANGE and _punch_t < 0.0:
		global_position += to.normalized() * WALK_SPEED * delta
		_phase += delta * WALK_SPEED * 6.0
		_apply_pose(_phase, 0.3, 0.0)
		return

	# атака: выброс руки, удар в момент пика
	_punch_cd = maxf(0.0, _punch_cd - delta)
	if _punch_t < 0.0:
		_apply_pose(0.0, 0.0, 0.0)
		if _punch_cd <= 0.0:
			_punch_t = 0.0
			_punch_done = false
		return
	_punch_t += delta
	var pa := sin(clampf(_punch_t / 0.45, 0.0, 1.0) * PI)
	if not _punch_done and _punch_t >= 0.2:
		_punch_done = true
		if dist <= ATTACK_RANGE + 0.3 and player.has_method("receive_punch"):
			player.call("receive_punch", PUNCH_DAMAGE)
	_apply_pose(0.0, 0.0, pa)
	if _punch_t >= 0.45:
		_punch_t = -1.0
		_punch_cd = PUNCH_COOLDOWN


func _tick_ragdoll(player: Node3D) -> void:
	var avg := 0.0
	for p in parts:
		avg += p.linear_velocity.length() + p.angular_velocity.length() * 0.3
	avg /= float(parts.size())
	if avg < 0.25:
		_settle_t += get_physics_process_delta_time()
	else:
		_settle_t = 0.0
	var can_get_up := false
	if kind == AGGRESSIVE:
		can_get_up = _settle_t > 2.5
	elif player != null:
		can_get_up = _settle_t > 0.8 and _flat_to(player).length() < 4.0
	if can_get_up:
		_start_getup()


func _start_getup() -> void:
	state = GETUP
	_getup_t = 0.0
	_getup_from.clear()
	for p in parts:
		p.freeze = true
		_getup_from.append(p.global_transform)
	var torso: RigidBody3D = part_map["Torso"]
	var fwd := torso.global_basis.z
	var pos := torso.global_position
	pos.y = 0.0
	_getup_to = Transform3D(Basis(Vector3.UP, atan2(fwd.x, fwd.z)), pos)


func _tick_getup(delta: float) -> void:
	_getup_t += delta
	var u := clampf(_getup_t / GETUP_TIME, 0.0, 1.0)
	var e := u * u * (3.0 - 2.0 * u)
	for i in parts.size():
		parts[i].global_transform = _getup_from[i].interpolate_with(_getup_to * rest_xf[i], e)
	if u >= 1.0:
		global_transform = _getup_to
		for i in parts.size():
			parts[i].transform = rest_xf[i]
		state = STAND
		_phase = 0.0
		_punch_t = -1.0
		_punch_cd = 0.5


func _on_part_contact(other: Node, part: RigidBody3D) -> void:
	if other.has_method("receive_object_hit"):
		# манекен в полёте бьёт игрока
		var spd := part.linear_velocity.length()
		if spd > 1.5 and state == RAGDOLL:
			other.call("receive_object_hit", spd, part.mass)
		return
	var rb := other as RigidBody3D
	if rb != null and rb.has_meta("pickable") and rb.linear_velocity.length() > 2.0:
		# в манекен врезался летящий предмет — включаем ragdoll
		activate()
