class_name PropFactory
extends RefCounted
## Фабрика физических предметов. Массы — реалистичные:
## бутылка 0.5 кг, доска 3 кг, ящик 15 кг, металлическая бочка 40 кг.
## Коллизии — простые (box/cylinder); детали (доски, обручи, этикетки, гвозди) — только визуальные.


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


static func add_visual(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	## Чисто визуальная деталь (без коллизии).
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi


static func _box(size: Vector3) -> BoxMesh:
	var bm := BoxMesh.new()
	bm.size = size
	return bm


static func _cyl(r: float, h: float) -> CylinderMesh:
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 16
	return cm


static func make_by_kind(kind: String) -> PropBody:
	## Спавн предмета по ключу из рюкзака или из меню.
	match kind:
		"bottle":
			return make_bottle()
		"brick":
			return make_brick()
		"phone":
			return make_phone()
		"crate_small":
			return make_crate(0.6, 6.0)
		"crate":
			return make_crate()
		"board_short":
			return make_board(0.9)
		"board":
			return make_board()
		"barrel":
			return make_barrel()
	return make_bottle()


# ---------------------------------------------------------------- ящик

static func make_crate(size: float = 0.8, mass: float = 15.0) -> PropBody:
	var small := size <= 0.65
	var b := make(mass, "деревянный ящик" if not small else "малый ящик", size * 0.87, PropBody.WOOD, 6.0)
	b.item_kind = "crate_small" if small else "crate"
	b.bulky = not small
	b.desc = "Малый деревянный ящик %d см, %.0f кг. Ломается от сильного удара." % [roundi(size * 100), mass] if small \
		else "Деревянный ящик %d см, %.0f кг. Громоздкий." % [roundi(size * 100), mass]
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * size
	var bs := BoxShape3D.new()
	bs.size = bm.size
	# основа — тёмный каркас, поверх — доски
	add_shape(b, bm, bs, material(Color(0.5, 0.35, 0.2), 0.85))

	var plank_mats := [
		material(Color(0.66, 0.47, 0.27), 0.85),
		material(Color(0.6, 0.42, 0.24), 0.85),
		material(Color(0.7, 0.52, 0.31), 0.8),
	]
	var batten := material(Color(0.4, 0.27, 0.15), 0.9)
	var nail := material(Color(0.2, 0.2, 0.22), 0.4, 0.8)
	var h := size / 3.0
	var inset := size * 0.5 + 0.004
	# доски на четырёх боковых гранях, по три в ряд
	for n in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var along_x: bool = absf(n.z) > 0.5  # грань ±Z: доски горизонтальные вдоль X
		for i in 3:
			var yy := -size * 0.33 + i * h
			var mat: Material = plank_mats[(i + int(absf(n.x) * 2.0)) % 3]
			var sz := Vector3(size * 0.96, h * 0.9, 0.012) if along_x else Vector3(0.012, h * 0.9, size * 0.96)
			add_visual(b, _box(sz), mat, n * inset + Vector3(0, yy, 0))
			# два гвоздя на доску
			for sx in [-1.0, 1.0]:
				var off := Vector3(sx * size * 0.42, yy, 0) if along_x else Vector3(0, yy, sx * size * 0.42)
				add_visual(b, _sphere(0.0065), nail, n * (inset + 0.006) + off)
	# бруски-обвязка по углам
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			add_visual(b, _box(Vector3(0.05, size * 1.01, 0.05)), batten,
				Vector3(cx * (size * 0.5 - 0.012), 0.0, cz * (size * 0.5 - 0.012)))
	# поперечные рейки сверху
	add_visual(b, _box(Vector3(size * 0.98, 0.03, 0.05)), batten, Vector3(0, size * 0.5 + 0.005, 0))
	add_visual(b, _box(Vector3(size * 0.98, 0.03, 0.05)), batten, Vector3(0, size * 0.5 + 0.005, size * 0.33))
	add_visual(b, _box(Vector3(size * 0.98, 0.03, 0.05)), batten, Vector3(0, size * 0.5 + 0.005, -size * 0.33))
	# трафарет-метка
	var stencil := material(Color(0.12, 0.12, 0.12), 0.9)
	add_visual(b, _box(Vector3(size * 0.3, size * 0.14, 0.004)), stencil,
		Vector3(size * 0.2, -size * 0.1, size * 0.5 + 0.009))
	return b


# ---------------------------------------------------------------- бочка

static func make_barrel() -> PropBody:
	var b := make(40.0, "металлическая бочка", 0.55)
	b.item_kind = "barrel"
	b.bulky = true
	b.desc = "Металлическая бочка на 200 л, 40 кг. Очень тяжёлая и громоздкая."
	var cm := _cyl(0.3, 0.95)
	var cs := CylinderShape3D.new()
	cs.radius = 0.3
	cs.height = 0.95
	add_shape(b, cm, cs, material(Color(0.25, 0.38, 0.5), 0.45, 0.7))
	# обручи: тёмные металлические кольца
	var hoop := material(Color(0.12, 0.13, 0.15), 0.35, 0.9)
	var tm := TorusMesh.new()
	tm.inner_radius = 0.296
	tm.outer_radius = 0.322
	tm.rings = 24
	tm.ring_segments = 8
	for y in [-0.36, -0.12, 0.12, 0.36]:
		add_visual(b, tm, hoop, Vector3(0, y, 0))
	# крышка и пробка
	add_visual(b, _cyl(0.29, 0.02), material(Color(0.2, 0.3, 0.4), 0.45, 0.7), Vector3(0, 0.475, 0))
	add_visual(b, _cyl(0.04, 0.03), hoop, Vector3(0.12, 0.49, 0.1))
	# ржавые потёки для вида
	var rust := material(Color(0.5, 0.27, 0.12, 0.85), 0.95)
	add_visual(b, _box(Vector3(0.012, 0.5, 0.006)), rust, Vector3(0.2, -0.05, 0.27), Vector3(0, 0.3, 0))
	add_visual(b, _box(Vector3(0.01, 0.35, 0.006)), rust, Vector3(-0.22, 0.1, -0.26), Vector3(0, -0.4, 0))
	return b


# ---------------------------------------------------------------- кирпич

static func make_brick() -> PropBody:
	var b := make(2.5, "кирпич", 0.13)
	b.item_kind = "brick"
	b.desc = "Строительный кирпич, 2.5 кг. Не бьётся, но тяжёлый."
	var bm := BoxMesh.new()
	bm.size = Vector3(0.23, 0.065, 0.11)
	var bs := BoxShape3D.new()
	bs.size = bm.size
	add_shape(b, bm, bs, material(Color(0.6, 0.26, 0.18), 0.95))
	# пустота (щель) сверху и цветовые пятна
	add_visual(b, _box(Vector3(0.1, 0.004, 0.04)), material(Color(0.42, 0.18, 0.12), 0.95), Vector3(0, 0.0345, 0))
	add_visual(b, _box(Vector3(0.05, 0.066, 0.112)), material(Color(0.66, 0.34, 0.24), 0.95), Vector3(-0.06, 0, 0))
	return b


# ---------------------------------------------------------------- доска

static func make_board(length: float = 1.8) -> PropBody:
	var storable := length <= 1.0
	var b := make(3.0, "доска" if not storable else "короткая доска", length * 0.5)
	b.item_kind = "board_short" if storable else "board"
	b.bulky = not storable
	b.desc = "Строительная доска %d см, 3 кг." % roundi(length * 100) + ("" if storable else " Громоздкая.")
	var bm := BoxMesh.new()
	bm.size = Vector3(length, 0.03, 0.2)
	var bs := BoxShape3D.new()
	bs.size = bm.size
	add_shape(b, bm, bs, material(Color(0.82, 0.66, 0.44), 0.7))
	# годовые кольца (полоски вдоль доски) и сучок
	var grain := material(Color(0.7, 0.53, 0.33), 0.8)
	for z in [-0.07, -0.02, 0.04, 0.08]:
		add_visual(b, _box(Vector3(length * 0.98, 0.002, 0.006)), grain, Vector3(0, 0.0165, z))
	var knot := material(Color(0.45, 0.3, 0.17), 0.8)
	add_visual(b, _box(Vector3(0.05, 0.002, 0.03)), knot, Vector3(-length * 0.22, 0.0165, 0.02))
	return b


# ---------------------------------------------------------------- бутылка

static func make_bottle() -> PropBody:
	var b := make(0.5, "пустая бутылка", 0.15, PropBody.GLASS, 3.0)
	b.item_kind = "bottle"
	b.desc = "Пустая стеклянная бутылка, 0.5 кг. Разбивается при сильном ударе."
	var cm := _cyl(0.033, 0.24)
	var cs := CylinderShape3D.new()
	cs.radius = 0.033
	cs.height = 0.24
	var glass := material(Color(0.1, 0.45, 0.22, 0.7), 0.08)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	add_shape(b, cm, cs, glass)
	# горлышко и крышка
	add_visual(b, _cyl(0.013, 0.05), glass, Vector3(0, 0.145, 0))
	add_visual(b, _cyl(0.016, 0.022), material(Color(0.6, 0.12, 0.1), 0.5, 0.3), Vector3(0, 0.18, 0))
	# этикетка: белая бумага и цветная полоса
	add_visual(b, _cyl(0.0345, 0.11), material(Color(0.93, 0.92, 0.86), 0.9), Vector3(0, -0.01, 0))
	add_visual(b, _cyl(0.0352, 0.025), material(Color(0.9, 0.45, 0.12), 0.7), Vector3(0, 0.035, 0))
	return b


# ---------------------------------------------------------------- телефон

static func make_phone() -> PropBody:
	## Смартфон: 7.5 x 15.5 x 0.9 см, светящийся экран сверху.
	var b := make(0.19, "смартфон", 0.1)
	b.item_kind = "phone"
	b.desc = "Смартфон, 190 г. Помещается в карман."
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


static func _sphere(r: float) -> SphereMesh:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	return sm
