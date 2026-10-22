class_name PropBody
extends RigidBody3D
## Физический предмет полигона.
##  - title / hold_radius — название для подсказки и расстояние до точки удержания;
##  - breakable — может ли предмет разбиться (стекло / дерево) и при какой скорости удара;
##  - is_held — предмет сейчас в руках игрока (тогда он не ломается и не бьёт игрока).

const NONE := 0
const GLASS := 1
const WOOD := 2

var title := "предмет"
var hold_radius := 0.2
var breakable := NONE
var break_speed := 5.0
var is_held := false
var item_kind := ""      # ключ для рюкзака и спавна (см. PropFactory.make_by_kind)
var desc := ""           # описание для таблички в рюкзаке
var bulky := false       # громоздкое: в рюкзак не помещается

var _prev_speed := 0.0
var _broken := false


func _ready() -> void:
	set_meta("pickable", true)
	set_meta("title", title)
	set_meta("hold_radius", hold_radius)
	continuous_cd = true  # не проваливаться сквозь пол
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_contact)


func _physics_process(_delta: float) -> void:
	# скорость до шага физики — при столкновении это и есть сила удара
	_prev_speed = linear_velocity.length()


func _on_contact(other: Node) -> void:
	if is_held or _broken:
		return
	if other.has_method("receive_object_hit"):
		if _prev_speed > 2.0:
			other.call("receive_object_hit", _prev_speed, mass)
		return
	if breakable != NONE and _prev_speed > break_speed:
		_broken = true
		call_deferred("_do_break")


func _do_break() -> void:
	var root := get_parent() as Node3D
	if root != null:
		if breakable == GLASS:
			ShatterFX.break_glass(root, global_position)
		else:
			ShatterFX.break_wood(root, global_position)
	queue_free()
