class_name RocketFactory
extends RefCounted

static func build(part_ids: Array[String], active_from_stage: int = 0) -> Node3D:
	var root := Node3D.new()
	root.name = "RocketVisual"

	var visible_ids: Array[String] = _active_ids(part_ids, active_from_stage)
	var y: float = 0.0

	for part_id: String in visible_ids:
		var data: Dictionary = PartCatalog.get_part(part_id)
		if data.is_empty():
			continue
		var part := _make_part(part_id, data)
		var h: float = float(data.get("height", 1.0))
		part.position.y = y + h * 0.5
		root.add_child(part)
		y += h

	root.set_meta("vehicle_height", y)
	return root

static func vehicle_height(part_ids: Array[String], active_from_stage: int = 0) -> float:
	var height: float = 0.0
	for part_id: String in _active_ids(part_ids, active_from_stage):
		var data: Dictionary = PartCatalog.get_part(part_id)
		height += float(data.get("height", 0.0))
	return height

static func _active_ids(part_ids: Array[String], active_from_stage: int) -> Array[String]:
	if active_from_stage <= 0:
		return part_ids.duplicate()

	var stage: int = 0
	var result: Array[String] = []
	for part_id: String in part_ids:
		if stage >= active_from_stage:
			result.append(part_id)
		var data: Dictionary = PartCatalog.get_part(part_id)
		if str(data.get("type", "")) == "decoupler":
			stage += 1
	return result

static func _make_part(part_id: String, data: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = part_id

	var part_type: String = str(data.get("type", ""))
	var h: float = float(data.get("height", 1.0))
	var r: float = float(data.get("radius", 1.0))

	match part_type:
		"capsule":
			_build_capsule(root, h, r)
		"tank":
			_build_tank(root, h, r, part_id)
		"engine":
			_build_engine(root, h, r, part_id)
		"decoupler":
			_build_decoupler(root, h, r)
		"fin":
			_build_fins(root, h, r)
		"nose":
			_build_nose(root, h, r)
		"heatshield":
			_build_heatshield(root, h, r)
		_:
			_build_tank(root, h, r, part_id)

	return root

static func _build_capsule(root: Node3D, h: float, r: float) -> void:
	var shell := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.18
	cone.bottom_radius = r
	cone.height = h
	cone.radial_segments = 48
	shell.mesh = cone
	shell.material_override = _material(Color(0.90, 0.92, 0.95), 0.12, 0.30)
	root.add_child(shell)

	var window_band := MeshInstance3D.new()
	var band := CylinderMesh.new()
	band.top_radius = r * 0.72
	band.bottom_radius = r * 0.82
	band.height = 0.34
	band.radial_segments = 48
	window_band.mesh = band
	window_band.position.y = -h * 0.14
	window_band.material_override = _material(Color(0.025, 0.065, 0.10), 0.45, 0.15, Color(0.02, 0.12, 0.22), 0.6)
	root.add_child(window_band)

	var stripe := MeshInstance3D.new()
	var stripe_mesh := CylinderMesh.new()
	stripe_mesh.top_radius = r * 1.005
	stripe_mesh.bottom_radius = r * 1.005
	stripe_mesh.height = 0.16
	stripe_mesh.radial_segments = 48
	stripe.mesh = stripe_mesh
	stripe.position.y = -h * 0.42
	stripe.material_override = _material(Color(0.07, 0.09, 0.12), 0.55, 0.28)
	root.add_child(stripe)

static func _build_tank(root: Node3D, h: float, r: float, part_id: String) -> void:
	var body := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = r
	mesh.bottom_radius = r
	mesh.height = h
	mesh.radial_segments = 48
	body.mesh = mesh
	body.material_override = _material(Color(0.82, 0.85, 0.90), 0.32, 0.26)
	root.add_child(body)

	for sy: float in [-h * 0.45, h * 0.45]:
		var ring := MeshInstance3D.new()
		var ring_mesh := CylinderMesh.new()
		ring_mesh.top_radius = r * 1.025
		ring_mesh.bottom_radius = r * 1.025
		ring_mesh.height = 0.14
		ring_mesh.radial_segments = 48
		ring.mesh = ring_mesh
		ring.position.y = sy
		ring.material_override = _material(Color(0.11, 0.13, 0.16), 0.72, 0.22)
		root.add_child(ring)

	var stripe := MeshInstance3D.new()
	var stripe_mesh := CylinderMesh.new()
	stripe_mesh.top_radius = r * 1.008
	stripe_mesh.bottom_radius = r * 1.008
	stripe_mesh.height = max(0.16, h * 0.035)
	stripe_mesh.radial_segments = 48
	stripe.mesh = stripe_mesh
	stripe.material_override = _material(Color(0.08, 0.45, 0.78), 0.35, 0.24)
	root.add_child(stripe)

	if "large" in part_id:
		var mid := MeshInstance3D.new()
		var mid_mesh := CylinderMesh.new()
		mid_mesh.top_radius = r * 1.012
		mid_mesh.bottom_radius = r * 1.012
		mid_mesh.height = 0.10
		mid_mesh.radial_segments = 48
		mid.mesh = mid_mesh
		mid.position.y = h * 0.24
		mid.material_override = _material(Color(0.12, 0.14, 0.17), 0.6, 0.24)
		root.add_child(mid)

static func _build_engine(root: Node3D, h: float, r: float, part_id: String) -> void:
	var mount := MeshInstance3D.new()
	var mount_mesh := CylinderMesh.new()
	mount_mesh.top_radius = r * 0.82
	mount_mesh.bottom_radius = r * 0.88
	mount_mesh.height = h * 0.30
	mount_mesh.radial_segments = 40
	mount.mesh = mount_mesh
	mount.position.y = h * 0.34
	mount.material_override = _material(Color(0.13, 0.15, 0.18), 0.9, 0.18)
	root.add_child(mount)

	var bell := MeshInstance3D.new()
	var bell_mesh := CylinderMesh.new()
	bell_mesh.top_radius = r * 0.42
	bell_mesh.bottom_radius = r * (0.82 if "orion" in part_id else 0.66)
	bell_mesh.height = h * 0.72
	bell_mesh.radial_segments = 48
	bell.mesh = bell_mesh
	bell.position.y = -h * 0.18
	bell.material_override = _material(Color(0.035, 0.042, 0.052), 0.95, 0.14)
	root.add_child(bell)

	var throat := MeshInstance3D.new()
	var throat_mesh := CylinderMesh.new()
	throat_mesh.top_radius = r * 0.30
	throat_mesh.bottom_radius = r * 0.30
	throat_mesh.height = h * 0.18
	throat_mesh.radial_segments = 32
	throat.mesh = throat_mesh
	throat.position.y = h * 0.10
	throat.material_override = _material(Color(0.32, 0.34, 0.36), 0.95, 0.12)
	root.add_child(throat)

static func _build_decoupler(root: Node3D, h: float, r: float) -> void:
	var body := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = r
	mesh.bottom_radius = r
	mesh.height = h
	mesh.radial_segments = 48
	body.mesh = mesh
	body.material_override = _material(Color(0.12, 0.13, 0.15), 0.85, 0.20)
	root.add_child(body)

	var band := MeshInstance3D.new()
	var band_mesh := CylinderMesh.new()
	band_mesh.top_radius = r * 1.04
	band_mesh.bottom_radius = r * 1.04
	band_mesh.height = h * 0.32
	band_mesh.radial_segments = 48
	band.mesh = band_mesh
	band.material_override = _material(Color(0.88, 0.38, 0.06), 0.30, 0.30)
	root.add_child(band)

static func _build_fins(root: Node3D, h: float, r: float) -> void:
	var core := MeshInstance3D.new()
	var core_mesh := CylinderMesh.new()
	core_mesh.top_radius = r * 0.60
	core_mesh.bottom_radius = r * 0.60
	core_mesh.height = h
	core_mesh.radial_segments = 40
	core.mesh = core_mesh
	core.material_override = _material(Color(0.78, 0.81, 0.85), 0.35, 0.28)
	root.add_child(core)

	for i: int in range(4):
		var fin := MeshInstance3D.new()
		var fin_mesh := BoxMesh.new()
		fin_mesh.size = Vector3(r * 0.95, h * 0.72, 0.10)
		fin.mesh = fin_mesh
		fin.position.y = -h * 0.10
		fin.position.x = r * 0.78
		fin.rotation.y = i * PI * 0.5
		fin.material_override = _material(Color(0.10, 0.12, 0.15), 0.72, 0.24)
		root.add_child(fin)

static func _build_nose(root: Node3D, h: float, r: float) -> void:
	var shell := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.02
	mesh.bottom_radius = r
	mesh.height = h
	mesh.radial_segments = 48
	shell.mesh = mesh
	shell.material_override = _material(Color(0.90, 0.92, 0.95), 0.18, 0.28)
	root.add_child(shell)

static func _build_heatshield(root: Node3D, h: float, r: float) -> void:
	var shield := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = r
	mesh.bottom_radius = r * 1.03
	mesh.height = h
	mesh.radial_segments = 48
	shield.mesh = mesh
	shield.material_override = _material(Color(0.07, 0.055, 0.045), 0.10, 0.88)
	root.add_child(shield)

static func make_plume(radius: float = 0.9) -> MeshInstance3D:
	var plume := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.75
	mesh.bottom_radius = radius * 0.14
	mesh.height = 8.0
	mesh.radial_segments = 32
	plume.mesh = mesh
	plume.position.y = -4.0
	plume.material_override = _material(
		Color(1.0, 0.46, 0.08),
		0.0,
		0.12,
		Color(1.0, 0.20, 0.025),
		8.0
	)
	return plume

static func _material(
	color: Color,
	metallic: float,
	roughness: float,
	emission: Color = Color.BLACK,
	emission_energy: float = 0.0
) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	if emission_energy > 0.0:
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = emission_energy
	return mat
