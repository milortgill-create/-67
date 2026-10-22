class_name ShatterFX
extends RefCounted
## Эффекты разрушения: частицы (GPUParticles3D) + несколько физических осколков.
## Осколки удаляются через несколько секунд, чтобы не копить объекты.

const SHARD_LIFETIME := 6.0
const PARTICLE_LIFETIME := 2.0


static func _mat(color: Color, rough: float = 0.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m


static func break_glass(root: Node3D, pos: Vector3) -> void:
	_burst(root, pos, Color(0.3, 0.65, 0.4), 0.025, 28)
	for i in 7:
		var dir := Vector3(randf_range(-1.0, 1.0), randf_range(0.4, 1.0), randf_range(-1.0, 1.0)).normalized()
		_shard(root, pos, Vector3(0.035, 0.006, 0.025), Color(0.3, 0.65, 0.4), 0.03, dir * randf_range(1.0, 2.5))


static func break_wood(root: Node3D, pos: Vector3) -> void:
	_burst(root, pos, Color(0.6, 0.42, 0.24), 0.05, 36)
	for i in 6:
		var dir := Vector3(randf_range(-1.0, 1.0), randf_range(0.3, 1.0), randf_range(-1.0, 1.0)).normalized()
		_shard(root, pos, Vector3(0.14, 0.03, 0.035), Color(0.55, 0.38, 0.2), 0.2, dir * randf_range(1.0, 2.5))


static func _burst(root: Node3D, pos: Vector3, color: Color, piece: float, amount: int) -> void:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 0.9
	p.one_shot = true
	p.explosiveness = 1.0
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 75.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 3.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	p.process_material = pm
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * piece
	bm.material = _mat(color, 0.3)
	p.draw_pass_1 = bm
	root.add_child(p)
	p.global_position = pos
	p.emitting = true
	root.get_tree().create_timer(PARTICLE_LIFETIME).timeout.connect(p.queue_free)


static func _shard(root: Node3D, pos: Vector3, size: Vector3, color: Color, mass: float, impulse: Vector3) -> void:
	var rb := RigidBody3D.new()
	rb.mass = mass
	rb.continuous_cd = true
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(color, 0.2)
	rb.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	rb.add_child(cs)
	root.add_child(rb)
	rb.global_position = pos + Vector3(randf_range(-0.05, 0.05), randf_range(0.0, 0.05), randf_range(-0.05, 0.05))
	rb.linear_velocity = impulse
	rb.angular_velocity = Vector3(randf_range(-10, 10), randf_range(-10, 10), randf_range(-10, 10))
	root.get_tree().create_timer(SHARD_LIFETIME).timeout.connect(rb.queue_free)
