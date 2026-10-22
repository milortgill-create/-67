extends Node3D
## Тестовый полигон («песочница»): закрытый бетонный зал, ящики, бочки, кирпичи,
## доски, бутылки, два манекена (пассивный и агрессивный) и смартфон в руках игрока.
## Всё строится в коде, чтобы сцена оставалась простой и читаемой.

const HALF := 15.0          # половина размера зала (стены на ±15 м)
const WALL_H := 6.0
const PLAYER_START := Vector3(0, 0, 8.0)

var player: Player
var touch: TouchControls
var props: Array[PropBody] = []
var mannequins: Array[Mannequin] = []
var phone: PropBody

var _prompt: Label
var _message: Label
var _hp_label: Label
var _msg_timer := 0.0
var _action_btn: Button
var _reset_btn: Button
var _concrete: Material


func _ready() -> void:
	_concrete = _make_concrete()
	_build_environment()
	_build_arena()
	_build_player()
	_build_hud()
	_build_scene_objects()
	_show_message("Полигон готов. Наведите прицел и нажмите ДЕЙСТВИЕ.")


# ---------------------------------------------------------------- окружение

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.06, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.75, 0.78)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	add_child(we)

	# «дневной свет» через верхний проём; потолок не отбрасывает тень
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-65, 35, 0)
	sun.light_energy = 0.5
	sun.shadow_enabled = true
	add_child(sun)

	# ряд ламп под потолком
	var bulb_mat := StandardMaterial3D.new()
	bulb_mat.albedo_color = Color(1, 1, 0.95)
	bulb_mat.emission_enabled = true
	bulb_mat.emission = Color(1, 0.97, 0.9)
	bulb_mat.emission_energy_multiplier = 3.0
	for x in [-9.0, 0.0, 9.0]:
		for z in [-9.0, 0.0, 9.0]:
			var lamp := OmniLight3D.new()
			lamp.position = Vector3(x, 5.6, z)
			lamp.light_energy = 1.6
			lamp.omni_range = 16.0
			lamp.light_color = Color(1.0, 0.95, 0.85)
			add_child(lamp)
			var bulb := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.2
			sm.height = 0.4
			bulb.mesh = sm
			bulb.material_override = bulb_mat
			bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			bulb.position = Vector3(x, 5.85, z)
			add_child(bulb)


func _make_concrete() -> Material:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.04
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.noise = noise
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.58, 0.58, 0.56)
	m.albedo_texture = tex
	m.roughness = 0.95
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.25, 0.25, 0.25)
	return m


func _static_box(pos: Vector3, size: Vector3, mat: Material, casts_shadow: bool = true) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.position = pos
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	if not casts_shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sb.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	add_child(sb)
	return sb


func _visual_box(pos: Vector3, size: Vector3, color: Color) -> void:
	## Декоративная разметка на полу (без коллизии).
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = PropFactory.material(color, 0.6)
	mi.position = pos
	add_child(mi)


func _build_arena() -> void:
	var plaster: StandardMaterial3D = PropFactory.material(Color(0.8, 0.79, 0.76), 0.9)
	# пол: толстая плита, верхняя грань на y = 0
	_static_box(Vector3(0, -0.5, 0), Vector3(32, 1, 32), _concrete)
	# стены
	var h := WALL_H
	_static_box(Vector3(-HALF - 0.25, h * 0.5, 0), Vector3(0.5, h, 31), plaster)
	_static_box(Vector3(HALF + 0.25, h * 0.5, 0), Vector3(0.5, h, 31), plaster)
	_static_box(Vector3(0, h * 0.5, -HALF - 0.25), Vector3(31, h, 0.5), plaster)
	_static_box(Vector3(0, h * 0.5, HALF + 0.25), Vector3(31, h, 0.5), plaster)
	# потолок (не отбрасывает тень, чтобы дневной свет проникал внутрь)
	_static_box(Vector3(0, h + 0.25, 0), Vector3(32, 0.5, 32), plaster, false)
	# желтая разметка зоны броска
	var yellow := Color(0.95, 0.8, 0.1)
	_visual_box(Vector3(0, 0.005, 5.0), Vector3(10, 0.01, 0.1), yellow)
	_visual_box(Vector3(0, 0.005, 10.0), Vector3(10, 0.01, 0.1), yellow)
	_visual_box(Vector3(-5, 0.005, 7.5), Vector3(0.1, 0.01, 5), yellow)
	_visual_box(Vector3(5, 0.005, 7.5), Vector3(0.1, 0.01, 5), yellow)


# ---------------------------------------------------------------- игрок

func _build_player() -> void:
	player = Player.new()
	player.name = "Player"
	player.spawn_position = PLAYER_START
	player.position = PLAYER_START
	add_child(player)
	player.message.connect(_show_message)
	player.hp_changed.connect(_on_hp_changed)


# ---------------------------------------------------------------- предметы и манекены

func _spawn(body: PropBody, pos: Vector3, yaw: float = 0.0) -> PropBody:
	add_child(body)
	body.position = pos
	body.rotation.y = yaw
	props.append(body)
	return body


func _build_scene_objects() -> void:
	# деревянные ящики (обычные 15 кг и малые)
	_spawn(PropFactory.make_crate(), Vector3(-6.0, 0.41, -4.0))
	_spawn(PropFactory.make_crate(), Vector3(-4.9, 0.41, -4.0))
	_spawn(PropFactory.make_crate(), Vector3(-5.45, 0.41, -5.1))
	_spawn(PropFactory.make_crate(), Vector3(-5.45, 1.22, -4.5), 0.2)
	_spawn(PropFactory.make_crate(), Vector3(-9.0, 0.41, -2.0))
	_spawn(PropFactory.make_crate(), Vector3(-9.0, 0.41, -3.1))
	_spawn(PropFactory.make_crate(0.6, 6.0), Vector3(7.0, 0.31, -7.0))
	_spawn(PropFactory.make_crate(0.6, 6.0), Vector3(7.8, 0.31, -7.0))

	# металлические бочки (40 кг)
	_spawn(PropFactory.make_barrel(), Vector3(3.0, 0.485, -5.0))
	_spawn(PropFactory.make_barrel(), Vector3(4.3, 0.485, -5.0))
	_spawn(PropFactory.make_barrel(), Vector3(3.65, 0.485, -6.2))
	_spawn(PropFactory.make_barrel(), Vector3(-11.0, 0.485, 4.0))
	_spawn(PropFactory.make_barrel(), Vector3(-11.0, 0.485, 5.4))
	_spawn(PropFactory.make_barrel(), Vector3(11.0, 0.485, -6.0))

	# кирпичи: паллета 4x2x3 и россыпь
	for layer in 3:
		for i in 4:
			for j in 2:
				var p := Vector3(-10.0 + i * 0.24 - 0.36, 0.0375 + layer * 0.066, -9.0 + j * 0.12 - 0.06)
				_spawn(PropFactory.make_brick(), p)
	for k in 6:
		_spawn(PropFactory.make_brick(), Vector3(8.0 + k * 0.3, 0.04, 4.0 + (k % 2) * 0.2), 0.3 * k)

	# доски (3 кг)
	_spawn(PropFactory.make_board(), Vector3(5.0, 0.02, 2.0), 0.4)
	_spawn(PropFactory.make_board(), Vector3(5.4, 0.02, 2.9), 0.3)
	_spawn(PropFactory.make_board(1.4), Vector3(-8.0, 0.02, 6.0), -0.8)
	_spawn(PropFactory.make_board(1.4), Vector3(-8.4, 0.02, 6.2), -0.6)

	# пустые бутылки (0.5 кг): два ряда на полу и россыпь
	for i in 5:
		_spawn(PropFactory.make_bottle(), Vector3(4.0 + i * 0.35, 0.125, -2.0))
		_spawn(PropFactory.make_bottle(), Vector3(4.17 + i * 0.35, 0.125, -2.35))
	for p in [Vector3(-2, 0.125, -1.5), Vector3(-1.5, 0.125, -2.2), Vector3(-2.5, 0.125, -2.8),
			Vector3(-1.0, 0.125, -3.5), Vector3(0.2, 0.125, -1.2), Vector3(-0.5, 0.125, -0.6)]:
		_spawn(PropFactory.make_bottle(), p, 1.3 * p.x)

	# манекены: №1 — пассивный (встаёт при приближении), №2 — агрессивный (бьёт)
	var passive := Mannequin.new()
	passive.name = "MannequinPassive"
	passive.kind = Mannequin.PASSIVE
	passive.position = Vector3(-3.0, 0.0, -9.0)
	add_child(passive)
	mannequins.append(passive)

	var aggressive := Mannequin.new()
	aggressive.name = "MannequinAggressive"
	aggressive.kind = Mannequin.AGGRESSIVE
	aggressive.position = Vector3(3.0, 0.0, -9.0)
	add_child(aggressive)
	mannequins.append(aggressive)

	# смартфон — сразу в руках игрока
	phone = _spawn(PropFactory.make_phone(), Vector3(0, 1.2, 0))
	player.grab_body(phone)


func _reset_scene() -> void:
	## Полная перестройка объектов: разбитое и сбитое возвращается в исходное состояние.
	player.release_held()
	for p in props:
		if is_instance_valid(p):
			p.queue_free()
	for m in mannequins:
		if is_instance_valid(m):
			m.queue_free()
	props.clear()
	mannequins.clear()
	player.global_position = PLAYER_START
	player.velocity = Vector3.ZERO
	_build_scene_objects()
	_show_message("Сцена сброшена.")


# ---------------------------------------------------------------- интерфейс

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)

	touch = TouchControls.new()
	touch.name = "TouchControls"
	layer.add_child(touch)
	player.touch = touch
	touch.action_pressed.connect(player.on_action)

	# прицел
	var cross := Label.new()
	cross.text = "+"
	cross.add_theme_font_size_override("font_size", 36)
	cross.set_anchors_preset(Control.PRESET_FULL_RECT)
	cross.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cross.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(cross)

	# подсказка под прицелом
	_prompt = Label.new()
	_prompt.anchor_left = 0.0
	_prompt.anchor_right = 1.0
	_prompt.anchor_top = 0.5
	_prompt.anchor_bottom = 0.5
	_prompt.offset_top = 32.0
	_prompt.offset_bottom = 72.0
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 22)
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_prompt)

	# сообщения сверху
	_message = Label.new()
	_message.anchor_left = 0.0
	_message.anchor_right = 1.0
	_message.anchor_top = 0.0
	_message.anchor_bottom = 0.0
	_message.offset_top = 90.0
	_message.offset_bottom = 130.0
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.add_theme_font_size_override("font_size", 24)
	_message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_message)

	# здоровье
	_hp_label = Label.new()
	_hp_label.position = Vector2(20, 120)
	_hp_label.add_theme_font_size_override("font_size", 22)
	_hp_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
	_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hp_label)
	_on_hp_changed(player.hp)

	# подсказка по управлению
	var info := Label.new()
	info.text = "Стик слева — ходьба · свайп справа — камера\nДЕЙСТВИЕ — взять / бросить / ударить\nПК: WASD, мышь (ПКМ — камера), E/Space/ЛКМ — действие"
	info.position = Vector2(20, 14)
	info.add_theme_font_size_override("font_size", 16)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(info)

	# кнопка «Действие»
	_action_btn = _make_button("ДЕЙСТВИЕ", Color(0.9, 0.35, 0.2, 0.6), 200.0)
	_action_btn.anchor_left = 1.0
	_action_btn.anchor_right = 1.0
	_action_btn.anchor_top = 1.0
	_action_btn.anchor_bottom = 1.0
	_action_btn.offset_left = -240.0
	_action_btn.offset_right = -40.0
	_action_btn.offset_top = -240.0
	_action_btn.offset_bottom = -40.0
	_action_btn.pressed.connect(player.on_action)
	layer.add_child(_action_btn)

	# кнопка сброса
	_reset_btn = _make_button("СБРОС", Color(0.2, 0.45, 0.8, 0.6), 60.0)
	_reset_btn.anchor_left = 1.0
	_reset_btn.anchor_right = 1.0
	_reset_btn.offset_left = -200.0
	_reset_btn.offset_right = -40.0
	_reset_btn.offset_top = 20.0
	_reset_btn.offset_bottom = 80.0
	_reset_btn.pressed.connect(_reset_scene)
	layer.add_child(_reset_btn)


func _make_button(text: String, color: Color, corner: float) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 26)
	b.add_theme_color_override("font_color", Color(1, 1, 1))
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(int(corner * 0.5))
	for style in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(style, sb)
	return b


func _show_message(text: String) -> void:
	_message.text = text
	_msg_timer = 2.0


func _on_hp_changed(value: int) -> void:
	_hp_label.text = "HP: %d / %d" % [value, Player.MAX_HP]


func _process(delta: float) -> void:
	touch.exclude_rects = [_action_btn.get_global_rect(), _reset_btn.get_global_rect()]
	_prompt.text = player.get_aim_hint()
	if _msg_timer > 0.0:
		_msg_timer -= delta
		if _msg_timer <= 0.0:
			_message.text = ""
