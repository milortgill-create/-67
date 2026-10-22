class_name Mannequin
extends Node3D
## Манекен из 11 капсульных частей, соединённых шарнирами Generic6DOF с пределами углов.
##
## Состояния:
##   STAND   — стоит. Поза задаётся параметрами (походка, удар, реакция).
##   RAGDOLL — физическое тело: падает и кувыркается. Только от СИЛЬНЫХ ударов.
##   GETUP   — встаёт по ключевым кадрам: упор на руки → на колени → полуприсед → стоя.
##
## Реакция на лёгкие удары (state STAND): отшатывается, хватается за место удара.
## Порог падения — энергия удара RAGDOLL_ENERGY (импульс для игрока, m*v для предметов).
##
## Виды: PASSIVE — не атакует, встаёт, когда игрок подходит ближе 4 м;
##       AGGRESSIVE — замечает игрока в радиусе 9 м, идёт и бьёт; сбитый встаёт сам.
##
## Системы координат: части — дети корня Mannequin, rest_map[name] — стойка относительно корня.
## Перёд манекена — локальная +Z. Сгиб вперёд у суставов — отрицательный угол.

const PASSIVE := 0
const AGGRESSIVE := 1

const STAND := 0
const RAGDOLL := 1
const GETUP := 2

const RAGDOLL_ENERGY := 100.0
const BODY_COLOR := Color(0.92, 0.9, 0.86)
const JOINT_COLOR := Color(0.16, 0.16, 0.18)
const WALK_SPEED := 1.5
const SENSE_RANGE := 9.0
const ATTACK_RANGE := 1.2
const PUNCH_COOLDOWN := 1.3
const PUNCH_DAMAGE := 8.0
const FLINCH_TIME := 0.7
const OBSTACLE_DIST := 0.9

# ключевые кадры вставания: [длительность, поза]; dy — смещение корня по высоте
const GETUP_KEYS := [
	[0.9, {"dy": -0.25, "lean": -0.9, "hipL": 0.1, "hipR": 0.1, "kneeL": 1.2, "kneeR": 1.2, "shL": -1.5, "shR": -1.5}],
	[0.7, {"dy": -0.3, "lean": -0.3, "kneeL": 1.5, "kneeR": 1.5, "shL": -0.5, "shR": -0.5}],
	[0.6, {"dy": -0.12, "lean": -0.15, "hipL": -0.3, "hipR": -0.3, "kneeL": 0.9, "kneeR": 0.9, "shL": -0.2, "shR": -0.2}],
	[0.6, {}],
]

var kind := PASSIVE
var state := STAND
var parts: Array[RigidBody3D] = []
var part_map: Dictionary = {}
var rest_map: Dictionary = {}

var _pend_part: RigidBody3D = null
var _pend_impulse := Vector3.ZERO
var _settle_t := 0.0
var _getup_from: Array[Transform3D] = []
var _ragdoll_t := 0.0
var _getup_targets: Array = []
var _getup_root := Transform3D.IDENTITY
var _getup_seg := 0
var _getup_seg_t := 0.0
var _phase := 0.0
var _punch_t := -1.0
var _punch_cd := 0.0
var _punch_done := false
var _flinch_t := 0.0
var _flinch_part := ""


func _ready() -> void:
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

	# шарниры с пределами углов (лимиты: [x_min, x_max, y_min, y_max, z_min, z_max])
	var head: RigidBody3D = part_map["Head"]
	var torso: RigidBody3D = part_map["Torso"]
	var pelvis: RigidBody3D = part_map["Pelvis"]
	_joint(torso, head, Vector3(0, 1.53, 0), [-0.6, 0.6, -0.9, 0.9, -0.5, 0.5])    # шея
	_joint(pelvis, torso, Vector3(0, 1.03, 0), [-0.5, 0.5, -0.3, 0.3, -0.4, 0.4])   # позвоночник
	for s in [-1.0, 1.0]:
		var sfx := "L" if s < 0 else "R"
		var arm: RigidBody3D = part_map["Arm" + sfx]
		var fore: RigidBody3D = part_map["Fore" + sfx]
		var thigh: RigidBody3D = part_map["Thigh" + sfx]
		var shin: RigidBody3D = part_map["Shin" + sfx]
		# плечо: вперёд до ~160°, назад до ~50°, отведение до ~125°
		_joint(torso, arm, Vector3(0.27 * s, 1.42, 0), [-2.8, 0.8, -1.2, 1.2, -2.2, 2.2])
		# локоть: сгибается только вперёд, до ~130°, без выворота
		_joint(arm, fore, Vector3(0.3 * s, 1.05, 0), [-2.3, 0.05, -0.2, 0.2, -0.1, 0.1])
		# бедро: вперёд до ~110°, назад до ~20°, без сильного отведения
		_joint(pelvis, thigh, Vector3(0.11 * s, 0.84, 0), [-1.9, 0.3, -0.6, 0.6, -0.4, 0.4])
		# колено: сгибается только назад, до ~130°
		_joint(thigh, shin, Vector3(0.11 * s, 0.37, 0), [0.0, 2.3, -0.1, 0.1, -0.1, 0.1])

	for p in parts:
		rest_map[str(p.name)] = p.transform

	_add_details()


func _joint(a: RigidBody3D, b: RigidBody3D, at: Vector3, lim: Array) -> void:
	var j := Generic6DOFJoint3D.new()
	j.position = at
	add_child(j)
	j.node_a = j.get_path_to(a)
	j.node_b = j.get_path_to(b)
	j.exclude_nodes_from_collision = true
	# линейные степени свободы заблокированы — части не отрываются
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
	## Видимые суставы, лицо, ступни, пояс — чтобы манекен не был «белой колбаской».
	var joint_mat := _mat(JOINT_COLOR, 0.5)
	var dark := _mat(Color(0.1, 0.1, 0.12), 0.7)
	var belt := _mat(Color(0.25, 0.2, 0.15), 0.8)
	var head: RigidBody3D = part_map["Head"]
	var torso: RigidBody3D = part_map["Torso"]
	var pelvis: RigidBody3D = part_map["Pelvis"]

	for ex in [-0.035, 0.035]:
		_vis(head, _sphere(0.018), dark, Vector3(ex, 0.03, 0.09))
	_vis(head, _box(Vector3(0.02, 0.04, 0.02)), _mat(BODY_COLOR, 0.6), Vector3(0, -0.005, 0.1))
	_vis(head, _cyl(0.04, 0.08), joint_mat, Vector3(0, -0.13, 0))

	_vis(torso, _box(Vector3(0.28, 0.34, 0.02)), _mat(Color(0.95, 0.94, 0.9), 0.5), Vector3(0, 0.02, 0.165))
	for s in [-1.0, 1.0]:
		_vis(torso, _sphere(0.06), joint_mat, Vector3(0.27 * s, 0.15, 0))
	_vis(pelvis, _cyl(0.16, 0.05), belt, Vector3(0, 0.07, 0))
	for s in [-1.0, 1.0]:
		_vis(pelvis, _sphere(0.06), joint_mat, Vector3(0.11 * s, -0.09, 0))

	for s in [-1.0, 1.0]:
		var sfx := "L" if s < 0 else "R"
		var arm: RigidBody3D = part_map["Arm" + sfx]
		var fore: RigidBody3D = part_map["Fore" + sfx]
		var thigh: RigidBody3D = part_map["Thigh" + sfx]
		var shin: RigidBody3D = part_map["Shin" + sfx]
		_vis(arm, _sphere(0.05), joint_mat, Vector3(0, -0.22, 0))
		_vis(fore, _sphere(0.058), _mat(BODY_COLOR, 0.6), Vector3(0, -0.2, 0))
		_vis(fore, _box(Vector3(0.09, 0.07, 0.07)), _mat(BODY_COLOR, 0.6), Vector3(0, -0.23, 0))
		_vis(thigh, _sphere(0.06), joint_mat, Vector3(0, -0.23, 0))
		_vis(shin, _box(Vector3(0.11, 0.06, 0.25)), dark, Vector3(0, -0.19, 0.06))
		_vis(shin, _sphere(0.045), joint_mat, Vector3(0, -0.12, 0))


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
	## Поворот вокруг оси X через точку p (в координатах корня).
	return Transform3D(Basis(Vector3.RIGHT, ang), p) * Transform3D(Basis(), -p)


func _rest(part_name: String) -> Transform3D:
	return rest_map[part_name] as Transform3D


func _local_pose(p: Dictionary) -> Dictionary:
	## Локальные трансформы всех частей для параметров позы:
	## lean — наклон торса (+ назад); hipX/kneeX — бедро и колено; shX/elX — плечо и локоть.
	var out := {}
	var lean: float = p.get("lean", 0.0)
	var spine := _rot_x(Vector3(0, 0.93, 0), lean)
	out["Pelvis"] = _rest("Pelvis")
	out["Torso"] = spine * _rest("Torso")
	out["Head"] = spine * _rest("Head")
	for s in [-1.0, 1.0]:
		var sfx := "L" if s < 0 else "R"
		var hip: float = p.get("hip" + sfx, 0.0)
		var knee: float = p.get("knee" + sfx, 0.0)
		var sh: float = p.get("sh" + sfx, 0.0)
		var el: float = p.get("el" + sfx, 0.0)
		var h := _rot_x(Vector3(0.11 * s, 0.84, 0), hip)
		out["Thigh" + sfx] = h * _rest("Thigh" + sfx)
		var k := _rot_x(h * Vector3(0.11 * s, 0.37, 0), knee)
		out["Shin" + sfx] = k * h * _rest("Shin" + sfx)
		var shm := _rot_x(spine * Vector3(0.27 * s, 1.42, 0), sh) * spine
		out["Arm" + sfx] = shm * _rest("Arm" + sfx)
		var elm := _rot_x(shm * Vector3(0.3 * s, 1.05, 0), el) * shm
		out["Fore" + sfx] = elm * _rest("Fore" + sfx)
	return out


func _apply_local(out: Dictionary) -> void:
	for key in out.keys():
		(part_map[key] as RigidBody3D).transform = out[key]


func _apply_pose(phase: float, amp: float, punch: float) -> void:
	## Походка (phase, amp), выброс правой руки (punch 0..1) и реакция на удар.
	var sw := sin(phase) * amp
	var kn := 0.9 * (amp / 0.3)
	var p := {
		"hipL": sw, "hipR": -sw,
		"kneeL": maxf(0.0, -sin(phase)) * kn, "kneeR": maxf(0.0, sin(phase)) * kn,
		"shL": -sw * 0.6, "shR": lerpf(sw * 0.6, -1.5, punch),
		"elL": 0.0, "elR": 0.0, "lean": 0.0,
	}
	if _flinch_t > 0.0:
		var f := _flinch_t / FLINCH_TIME
		if _flinch_part == "Head" or _flinch_part == "Torso":
			p["lean"] = float(p["lean"]) + 0.35 * f
		if _flinch_part == "Head":
			# удар в голову — обе руки закрывают лицо
			for sd in ["L", "R"]:
				p["sh" + sd] = -1.5 * f
				p["el" + sd] = -2.0 * f
		if _flinch_part.begins_with("Arm") or _flinch_part.begins_with("Fore"):
			# хватается за место удара: рука поднимается к голове
			var side := "L" if _flinch_part.ends_with("L") else "R"
			p["sh" + side] = -1.6 * f
			p["el" + side] = -1.9 * f
		if _flinch_part.begins_with("Thigh") or _flinch_part.begins_with("Shin"):
			# припадает на ногу
			var lside := "L" if _flinch_part.ends_with("L") else "R"
			p["knee" + lside] = maxf(float(p["knee" + lside]), 0.7 * f)
			p["hip" + lside] = -0.25 * f
	_apply_local(_local_pose(p))


# ---------------------------------------------------------------- управление

func punch(part: RigidBody3D, impulse: Vector3) -> void:
	## Удар игрока. Слабый — только реакция; сильный (энергия >= порога) — ragdoll.
	if state == RAGDOLL:
		_pend_part = part
		_pend_impulse = impulse
		return
	if impulse.length() >= RAGDOLL_ENERGY:
		activate()
		_pend_part = part
		_pend_impulse = impulse
	else:
		react(str(part.name))


func react(part_name: String) -> void:
	## Лёгкое попадание: отшатывание и реакция на место удара (только в стойке).
	if state != STAND:
		return
	_flinch_t = FLINCH_TIME
	_flinch_part = part_name
	_punch_t = -1.0


func activate() -> void:
	if state == RAGDOLL:
		return
	state = RAGDOLL
	_settle_t = 0.0
	_ragdoll_t = 0.0
	_punch_t = -1.0
	_flinch_t = 0.0
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


func _blocked(dir: Vector3) -> bool:
	## Есть ли препятствие (стена, ящик, бочка) на пути манекена.
	var from := global_position + Vector3(0, 1.0, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * OBSTACLE_DIST)
	var ex: Array[RID] = []
	for p in parts:
		ex.append(p.get_rid())
	q.exclude = ex
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _tick_stand(delta: float, player: Node3D) -> void:
	if _flinch_t > 0.0:
		_flinch_t = maxf(0.0, _flinch_t - delta)
		_apply_pose(_phase, 0.0, 0.0)
		if _flinch_t > 0.0:
			return  # отшатнулся — пауза
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
		var dir := to.normalized()
		if _blocked(dir):
			# обходим препятствие: поворачиваем в сторону
			rotation.y += delta * 2.5
			_apply_pose(0.0, 0.0, 0.0)
			return
		global_position += dir * WALK_SPEED * delta
		_phase += delta * WALK_SPEED * 6.0
		_apply_pose(_phase, 0.3, 0.0)
		return

	# атака: замах, удар в момент пика, возврат
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
	_ragdoll_t += get_physics_process_delta_time()
	# запасной таймер: даже если части не успокоились полностью, манекен встаёт через несколько секунд
	var can_get_up := false
	if kind == AGGRESSIVE:
		can_get_up = _settle_t > 2.5 or _ragdoll_t > 5.0
	elif player != null:
		can_get_up = (_settle_t > 0.8 or _ragdoll_t > 3.0) and _flat_to(player).length() < 4.0
	if can_get_up:
		_start_getup()


func _start_getup() -> void:
	## Подъём: от текущей позы (лежит) к ключевым кадрам, корень ставится туда, где лежит торс.
	state = GETUP
	_getup_from.clear()
	for p in parts:
		p.freeze = true
		_getup_from.append(p.global_transform)
	var torso: RigidBody3D = part_map["Torso"]
	var fwd := torso.global_basis.z
	var pos := torso.global_position
	pos.y = 0.0
	_getup_root = Transform3D(Basis(Vector3.UP, atan2(fwd.x, fwd.z)), pos)
	_getup_targets.clear()
	for key in GETUP_KEYS:
		var pose: Dictionary = key[1]
		var dy: float = pose.get("dy", 0.0)
		var root := Transform3D(_getup_root.basis, _getup_root.origin + Vector3(0, dy, 0))
		var local := _local_pose(pose)
		var world: Array[Transform3D] = []
		for p in parts:
			world.append(root * (local[str(p.name)] as Transform3D))
		_getup_targets.append(world)
	_getup_seg = 0
	_getup_seg_t = 0.0


func _tick_getup(delta: float) -> void:
	_getup_seg_t += delta
	var dur: float = GETUP_KEYS[_getup_seg][0]
	var u := clampf(_getup_seg_t / dur, 0.0, 1.0)
	var e := u * u * (3.0 - 2.0 * u)
	var prev: Array = _getup_from if _getup_seg == 0 else _getup_targets[_getup_seg - 1]
	var target: Array = _getup_targets[_getup_seg]
	for i in parts.size():
		parts[i].global_transform = (prev[i] as Transform3D).interpolate_with(target[i] as Transform3D, e)
	if u >= 1.0:
		_getup_seg += 1
		_getup_seg_t = 0.0
		if _getup_seg >= GETUP_KEYS.size():
			global_transform = _getup_root
			_apply_local(_local_pose({}))
			for i in parts.size():
				parts[i].transform = rest_map[str(parts[i].name)]
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
	if rb != null and rb.has_meta("pickable"):
		var speed := rb.linear_velocity.length()
		var energy := rb.mass * speed
		if energy >= RAGDOLL_ENERGY:
			activate()
		elif speed > 1.5:
			react(str(part.name))
