class_name BodyIcon
extends Control
## 2D-иконка человечка (силуэт) для HUD. Каждая часть тела подсвечивается
## красным пропорционально травме (0..1). Части: head, torso, arm_l, arm_r, leg_l, leg_r.

const BASE := Color(0.82, 0.84, 0.88, 0.55)
const HURT := Color(1.0, 0.15, 0.12, 0.95)

var levels: Dictionary = {}


func _ready() -> void:
	custom_minimum_size = Vector2(120, 170)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_levels(values: Dictionary) -> void:
	levels = values.duplicate()
	queue_redraw()


func _level(part: String) -> float:
	return clampf(float(levels.get(part, 0.0)), 0.0, 1.0)


func _tint(part: String) -> Color:
	return BASE.lerp(HURT, _level(part))


func _draw() -> void:
	# координаты в долях от квадрата 100 x 140, потом масштаб под размер контрола
	var s := minf(size.x / 100.0, size.y / 150.0)
	var o := Vector2(size.x * 0.5 - 50.0 * s, 6.0 * s)

	var head_c := o + Vector2(50, 18) * s
	draw_circle(head_c, 15.0 * s, _tint("head"))
	# шея
	draw_rect(Rect2(o + Vector2(44, 32) * s, Vector2(12, 8) * s), _tint("head"))

	# торс: трапеция
	var torso := PackedVector2Array([
		o + Vector2(28, 40) * s, o + Vector2(72, 40) * s,
		o + Vector2(68, 92) * s, o + Vector2(32, 92) * s,
	])
	draw_colored_polygon(torso, _tint("torso"))

	# руки: толстые линии от плеча до кисти
	_limb(o + Vector2(28, 44) * s, o + Vector2(14, 84) * s, 7.0 * s, "arm_r")
	_limb(o + Vector2(72, 44) * s, o + Vector2(86, 84) * s, 7.0 * s, "arm_l")

	# ноги
	_limb(o + Vector2(40, 92) * s, o + Vector2(38, 136) * s, 9.0 * s, "leg_r")
	_limb(o + Vector2(60, 92) * s, o + Vector2(62, 136) * s, 9.0 * s, "leg_l")

	# подписи частей и рамка
	draw_arc(head_c, 15.0 * s, 0.0, TAU, 24, Color(0, 0, 0, 0.5), 1.0 * s)


func _limb(a: Vector2, b: Vector2, width: float, part: String) -> void:
	draw_line(a, b, _tint(part), width * 2.0, true)
	draw_circle(a, width, _tint(part))
	draw_circle(b, width * 0.9, _tint(part))
