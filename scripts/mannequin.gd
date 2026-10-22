class_name Mannequin
extends Node3D
## Манекен (болванка) из отдельных физических частей, соединённых шарнирами.
## Стоит неподвижно (части заморожены). При ударе или столкновении с летящим
## предметом «оживает» — становится полноценным ragdoll: падает и кувыркается.

const SKIN := Color(0.87, 0.8, 0.68)

var parts: Array[RigidBody3D] = []
var rest_xf: Array[Transform3D] = []
var active := false

var _pend_part: RigidBody3D = null
var _pend_impulse := Vector3.ZERO


func _ready() -> void:
	_build()


func _make_part(part_name: String, mass: float, pos: Vector3, mesh: Mesh, shape: Shape3D) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.name = part_name
	b.mass = mass
	b.continuous_cd = true
	b.contact_monitor = true
	b.max_contacts_reported = 4
	b.freeze = true
	b.position = pos
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = SKIN
	m.roughness = 0.6
	mi.material_override = m
	b.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	b.add_child(cs)
	b.set_meta("mannequin", self)
	b.body_entered.connect(_on_part_contact.bind(b))
	add_child(b)
	parts.append(b)
	return b


func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


func _box_shape(size: Vector3) -> BoxShape3D:
	var s := BoxShape3D.new()
	s.size = size
	return s


func _cap(radius: float, height: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = height
	return m


func _cap_shape(radius: float, height: float) -> CapsuleShape3D:
	var s := CapsuleShape3D.new()
	s.radius = radius
	s.height = height
	return s


func _pin(a: RigidBody3D, b: RigidBody3D, at: Vector3) -> void:
	## Шарнир-«шарик» в точке at: части вращаются свободно, но не отрываются.
	var j := PinJoint3D.new()
	j.position = at
	add_child(j)
	j.node_a = j.get_path_to(a)
	j.node_b = j.get_path_to(b)


func _build() -> void:
	var head := _make_part("Head", 4.0, Vector3(0, 1.66, 0), _sphere(0.12), _sphere_shape(0.12))
	var torso := _make_part("Torso", 12.0, Vector3(0, 1.27, 0), _box(Vector3(0.42, 0.5, 0.22)), _box_shape(Vector3(0.42, 0.5, 0.22)))
	var pelvis := _make_part("Pelvis", 8.0, Vector3(0, 0.93, 0), _box(Vector3(0.36, 0.22, 0.2)), _box_shape(Vector3(0.36, 0.22, 0.2)))

	var arm_l := _make_part("ArmL", 2.0, Vector3(-0.3, 1.27, 0), _cap(0.055, 0.36), _cap_shape(0.055, 0.36))
	var fore_l := _make_part("ForeL", 1.5, Vector3(-0.3, 0.85, 0), _cap(0.05, 0.32), _cap_shape(0.05, 0.32))
	var arm_r := _make_part("ArmR", 2.0, Vector3(0.3, 1.27, 0), _cap(0.055, 0.36), _cap_shape(0.055, 0.36))
	var fore_r := _make_part("ForeR", 1.5, Vector3(0.3, 0.85, 0), _cap(0.05, 0.32), _cap_shape(0.05, 0.32))

	var thigh_l := _make_part("ThighL", 5.0, Vector3(-0.11, 0.6, 0), _cap(0.075, 0.5), _cap_shape(0.075, 0.5))
	var shin_l := _make_part("ShinL", 3.0, Vector3(-0.11, 0.21, 0), _cap(0.065, 0.42), _cap_shape(0.065, 0.42))
	var thigh_r := _make_part("ThighR", 5.0, Vector3(0.11, 0.6, 0), _cap(0.075, 0.5), _cap_shape(0.075, 0.5))
	var shin_r := _make_part("ShinR", 3.0, Vector3(0.11, 0.21, 0), _cap(0.065, 0.42), _cap_shape(0.065, 0.42))

	# Шарниры (после того как все части добавлены в дерево)
	_pin(head, torso, Vector3(0, 1.52, 0))
	_pin(torso, pelvis, Vector3(0, 1.03, 0))
	_pin(torso, arm_l, Vector3(-0.25, 1.42, 0))
	_pin(torso, arm_r, Vector3(0.25, 1.42, 0))
	_pin(arm_l, fore_l, Vector3(-0.3, 1.05, 0))
	_pin(arm_r, fore_r, Vector3(0.3, 1.05, 0))
	_pin(pelvis, thigh_l, Vector3(-0.11, 0.84, 0))
	_pin(pelvis, thigh_r, Vector3(0.11, 0.84, 0))
	_pin(thigh_l, shin_l, Vector3(-0.11, 0.37, 0))
	_pin(thigh_r, shin_r, Vector3(0.11, 0.37, 0))

	# Части не должны сталкиваться друг с другом (иначе они отталкивают соседей)
	for i in parts.size():
		for j in range(i + 1, parts.size()):
			parts[i].add_collision_exception_with(parts[j])

	for p in parts:
		rest_xf.append(p.transform)


func _sphere(radius: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	return m


func _sphere_shape(radius: float) -> SphereShape3D:
	var s := SphereShape3D.new()
	s.radius = radius
	return s


## Удар игрока: часть получает импульс, манекен становится ragdoll.
func punch(part: RigidBody3D, impulse: Vector3) -> void:
	activate()
	_pend_part = part
	_pend_impulse = impulse


## Переход из статичного состояния в ragdoll.
func activate() -> void:
	if active:
		return
	active = true
	for p in parts:
		p.freeze = false
		p.sleeping = false


## Возврат манекена в исходную стойку.
func reset_pose() -> void:
	active = false
	_pend_part = null
	for i in parts.size():
		var p := parts[i]
		p.freeze = true
		p.linear_velocity = Vector3.ZERO
		p.angular_velocity = Vector3.ZERO
		p.transform = rest_xf[i]


func _physics_process(_delta: float) -> void:
	if _pend_part != null:
		# Импульс применяем на следующем физическом шаге, уже после разморозки
		_pend_part.apply_central_impulse(_pend_impulse)
		_pend_part.apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 4.0)
		_pend_part = null


func _on_part_contact(other: Node, part: RigidBody3D) -> void:
	if other.has_method("take_hit"):
		# Манекен, который летит и бьёт игрока
		var spd := part.linear_velocity.length()
		if spd > 1.5:
			other.take_hit(spd)
		return
	var rb := other as RigidBody3D
	if rb != null and rb.has_meta("pickable") and rb.linear_velocity.length() > 2.0:
		# В манекен врезался летящий предмет — включаем ragdoll
		activate()
