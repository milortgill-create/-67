class_name PropFactory
extends RefCounted
## Фабрика физических предметов. Массы — реалистичные:
## бутылка 0.5 кг, доска 3 кг, ящик 15 кг, металлическая бочка 40 кг.


static func material(color: Color, rough: float = 0.8, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m


static func make(mass: float, title: String, hold_radius: float, breakable: int = 0, break_speed: float = 5.0) -> PropBody:
	var b := PropBody.new()
	b.mass = mass
	b.title = title
	b.hold_radius = hold_radius
	b.breakable = breakable
	b.break_speed = break_speed
	return b


static func add_shape(b: PropBody, mesh: Mesh, shape: Shape3D, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	b.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	b.add_child(cs)


static func make_crate(size: float = 0.8, mass: float = 15.0) -> PropBody:
	var b := make(mass, "деревянный ящик", size * 0.87, PropBody.WOOD, 6.0)
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * size
	var bs := BoxShape3D.new()
	bs.size = bm.size
	add_shape(b, bm, bs, material(Color(0.62, 0.44, 0.24), 0.85))
	# деревянные рейки и углы для вида
	for z_side in [-1.0, 1.0]:
		var rail := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(size * 1.02, size * 0.12, size * 0.1)
		rail.mesh = rm
		rail.material_override = material(Color(0.4, 0.27, 0.14), 0.9)
		rail.position = Vector3(0, 0, z_side * size * 0.5)
		b.add_child(rail)
	return b


static func make_barrel() -> PropBody:
	var b := make(40.0, "металлическая бочка", 0.55)
	var cm := CylinderMesh.new()
	cm.top_radius = 0.3
	cm.bottom_radius = 0.3
	cm.height = 0.95
	var cs := CylinderShape3D.new()
	cs.radius = 0.3
	cs.height = 0.95
	add_shape(b, cm, cs, material(Color(0.25, 0.38, 0.5), 0.45, 0.7))
	return b


static func make_brick() -> PropBody:
	var b := make(2.5, "кирпич", 0.13)
	var bm := BoxMesh.new()
	bm.size = Vector3(0.23, 0.065, 0.11)
	var bs := BoxShape3D.new()
	bs.size = bm.size
	add_shape(b, bm, bs, material(Color(0.6, 0.26, 0.18), 0.95))
	return b


static func make_board(length: float = 1.8) -> PropBody:
	var b := make(3.0, "доска", length * 0.5)
	var bm := BoxMesh.new()
	bm.size = Vector3(length, 0.03, 0.2)
	var bs := BoxShape3D.new()
	bs.size = bm.size
	add_shape(b, bm, bs, material(Color(0.82, 0.66, 0.44), 0.7))
	return b


static func make_bottle() -> PropBody:
	var b := make(0.5, "пустая бутылка", 0.15, PropBody.GLASS, 3.0)
	var cm := CylinderMesh.new()
	cm.top_radius = 0.033
	cm.bottom_radius = 0.033
	cm.height = 0.24
	var cs := CylinderShape3D.new()
	cs.radius = 0.033
	cs.height = 0.24
	var glass := material(Color(0.1, 0.45, 0.22, 0.7), 0.08)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	add_shape(b, cm, cs, glass)
	return b


static func make_phone() -> PropBody:
	## Смартфон: 7.5 x 15.5 x 0.9 см, светящийся экран сверху.
	var b := make(0.19, "смартфон", 0.1)
	var bm := BoxMesh.new()
	bm.size = Vector3(0.075, 0.009, 0.155)
	var bs := BoxShape3D.new()
	bs.size = bm.size
	add_shape(b, bm, bs, material(Color(0.07, 0.07, 0.08), 0.3, 0.6))
	var screen := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.068, 0.001, 0.142)
	screen.mesh = sm
	var smat := material(Color(0.05, 0.08, 0.14), 0.1)
	smat.emission_enabled = true
	smat.emission = Color(0.2, 0.55, 1.0)
	smat.emission_energy_multiplier = 1.2
	screen.material_override = smat
	screen.position = Vector3(0, 0.0048, 0)
	b.add_child(screen)
	return b
