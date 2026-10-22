class_name TouchControls
extends Control
## Сенсорное управление:
##  - левая половина экрана: виртуальный джойстик (появляется там, где палец коснулся);
##  - правая половина экрана: свайп = поворот камеры;
##  - на ПК: ПКМ-перетаскивание = камера, ЛКМ (вне кнопок) = действие.
## Кнопки (exclude_rects) не обрабатываются здесь — ими занимается Godot GUI.

signal action_pressed

const MOVE_RADIUS := 110.0
const SPLIT_X := 0.5

var move_vector := Vector2.ZERO
var exclude_rects: Array = []

var _move_index := -1
var _move_origin := Vector2.ZERO
var _move_pos := Vector2.ZERO
var _look_index := -1
var _mouse_look := false
var _look_accum := Vector2.ZERO


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func consume_look() -> Vector2:
	var v := _look_accum
	_look_accum = Vector2.ZERO
	return v


func _is_excluded(p: Vector2) -> bool:
	for r in exclude_rects:
		if (r as Rect2).has_point(p):
			return true
	return false


func _input(event: InputEvent) -> void:
	var vs := get_viewport_rect().size
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			if _is_excluded(t.position):
				return
			if t.position.x < vs.x * SPLIT_X:
				if _move_index == -1:
					_move_index = t.index
					_move_origin = t.position
					_move_pos = t.position
					move_vector = Vector2.ZERO
			else:
				if _look_index == -1:
					_look_index = t.index
		else:
			if t.index == _move_index:
				_move_index = -1
				move_vector = Vector2.ZERO
			if t.index == _look_index:
				_look_index = -1
		queue_redraw()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _move_index:
			_move_pos = d.position
			var off := _move_pos - _move_origin
			var length := minf(off.length(), MOVE_RADIUS)
			if off.length() > 0.001:
				move_vector = off.normalized() * (length / MOVE_RADIUS)
			queue_redraw()
		elif d.index == _look_index:
			_look_accum += d.relative
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_mouse_look = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not _is_excluded(mb.position):
			action_pressed.emit()
	elif event is InputEventMouseMotion and _mouse_look:
		_look_accum += (event as InputEventMouseMotion).relative


func _draw() -> void:
	if _move_index != -1:
		draw_circle(_move_origin, MOVE_RADIUS, Color(1, 1, 1, 0.12))
		draw_arc(_move_origin, MOVE_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 3.0)
		var knob := _move_origin + move_vector * MOVE_RADIUS
		draw_circle(knob, 42.0, Color(1, 1, 1, 0.35))
