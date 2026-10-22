class_name BackpackUI
extends Control
## Рюкзак: затемнённый экран со списком слотов (сетка). Нажатие на слот с предметом
## открывает табличку с названием, описанием и весом. Из таблички предмет можно достать.
## Сигналы: take_out(index) — достать предмет; store_held — положить предмет из рук; closed.

signal take_out(index: int)
signal store_held
signal closed

const COLS := 4
const SLOTS := 12

var _items: Array = []
var _holding := ""
var _title: Label
var _grid: GridContainer
var _store_btn: Button
var _detail: PanelContainer
var _detail_title: Label
var _detail_desc: Label
var _detail_weight: Label
var _detail_index := -1
var _detail_take: Button


func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(Color(0.13, 0.15, 0.18, 0.97), 14))
	panel.custom_minimum_size = Vector2(620, 0)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 26)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)

	_grid = GridContainer.new()
	_grid.columns = COLS
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	box.add_child(_grid)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)

	_store_btn = _btn("Положить предмет из рук", Color(0.2, 0.5, 0.3))
	_store_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_store_btn.pressed.connect(func() -> void: store_held.emit())
	row.add_child(_store_btn)

	var close := _btn("Закрыть", Color(0.35, 0.35, 0.4))
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close.pressed.connect(close_panel)
	row.add_child(close)

	# табличка с описанием предмета (поверх сетки)
	_detail = PanelContainer.new()
	_detail.add_theme_stylebox_override("panel", _style(Color(0.09, 0.1, 0.12, 1.0), 12))
	_detail.custom_minimum_size = Vector2(440, 0)
	_detail.set_anchors_preset(Control.PRESET_CENTER)
	_detail.visible = false
	center.add_child(_detail)

	var dbox := VBoxContainer.new()
	dbox.add_theme_constant_override("separation", 10)
	_detail.add_child(dbox)
	_detail_title = Label.new()
	_detail_title.add_theme_font_size_override("font_size", 24)
	dbox.add_child(_detail_title)
	_detail_desc = Label.new()
	_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_desc.add_theme_font_size_override("font_size", 18)
	dbox.add_child(_detail_desc)
	_detail_weight = Label.new()
	_detail_weight.add_theme_font_size_override("font_size", 18)
	_detail_weight.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))
	dbox.add_child(_detail_weight)
	var drow := HBoxContainer.new()
	drow.add_theme_constant_override("separation", 12)
	dbox.add_child(drow)
	_detail_take = _btn("Достать", Color(0.2, 0.45, 0.8))
	_detail_take.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_take.pressed.connect(_on_take_pressed)
	drow.add_child(_detail_take)
	var back := _btn("Назад", Color(0.35, 0.35, 0.4))
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(func() -> void: _detail.visible = false)
	drow.add_child(back)


func open(items: Array, holding: String) -> void:
	visible = true
	refresh(items, holding)


func close_panel() -> void:
	visible = false
	_detail.visible = false
	closed.emit()


func refresh(items: Array, holding: String) -> void:
	## Перестраивает сетку слотов по текущему содержимому рюкзака.
	_items = items.duplicate()
	_holding = holding
	var kg := 0.0
	for it in _items:
		kg += float((it as Dictionary)["weight"])
	_title.text = "Рюкзак — %d / %d слотов · %.1f кг" % [_items.size(), SLOTS, kg]
	_store_btn.disabled = holding == ""
	_store_btn.text = "Положить: " + holding if holding != "" else "Нет предмета в руках"
	for c in _grid.get_children():
		c.queue_free()
	for i in SLOTS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(130, 70)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 16)
		if i < _items.size():
			var it: Dictionary = _items[i]
			b.text = str(it["title"])
			b.tooltip_text = "%.1f кг" % float(it["weight"])
			b.add_theme_stylebox_override("normal", _style(Color(0.26, 0.36, 0.5), 8))
			b.pressed.connect(_show_detail.bind(i))
		else:
			b.text = "—"
			b.disabled = true
			b.add_theme_stylebox_override("disabled", _style(Color(0.18, 0.2, 0.23), 8))
		_grid.add_child(b)
	_detail.visible = false


func _show_detail(index: int) -> void:
	if index < 0 or index >= _items.size():
		return
	var it: Dictionary = _items[index]
	_detail_index = index
	_detail_title.text = str(it["title"])
	_detail_desc.text = str(it.get("desc", ""))
	_detail_weight.text = "Вес: %.2f кг" % float(it["weight"])
	_detail.visible = true


func _on_take_pressed() -> void:
	var idx := _detail_index
	_detail.visible = false
	take_out.emit(idx)


func _btn(text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 52)
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_color", Color(1, 1, 1))
	b.add_theme_stylebox_override("normal", _style(color, 10))
	b.add_theme_stylebox_override("hover", _style(color, 10))
	b.add_theme_stylebox_override("pressed", _style(color.darkened(0.2), 10))
	b.add_theme_stylebox_override("disabled", _style(Color(0.25, 0.25, 0.28), 10))
	return b


func _style(color: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb
