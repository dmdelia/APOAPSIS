class_name WorldFactory
extends RefCounted

static func build_launch_site() -> Node3D:
	var root := Node3D.new()
	root.name = "LaunchSite"

	var ground := MeshInstance3D.new()
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(20000.0, 20000.0)
	ground.mesh = ground_mesh
	ground.material_override = _material(Color(0.075, 0.085, 0.075), 0.0, 1.0)
	root.add_child(ground)

	var concrete := MeshInstance3D.new()
	var concrete_mesh := CylinderMesh.new()
	concrete_mesh.top_radius = 34.0
	concrete_mesh.bottom_radius = 34.0
	concrete_mesh.height = 1.4
	concrete_mesh.radial_segments = 64
	concrete.mesh = concrete_mesh
	concrete.position.y = 0.7
	concrete.material_override = _material(Color(0.19, 0.20, 0.21), 0.0, 0.92)
	root.add_child(concrete)

	var deck := MeshInstance3D.new()
	var deck_mesh := CylinderMesh.new()
	deck_mesh.top_radius = 15.0
	deck_mesh.bottom_radius = 15.0
	deck_mesh.height = 2.2
	deck_mesh.radial_segments = 64
	deck.mesh = deck_mesh
	deck.position.y = 1.8
	deck.material_override = _material(Color(0.075, 0.08, 0.095), 0.78, 0.28)
	root.add_child(deck)

	for i: int in range(4):
		var mount := MeshInstance3D.new()
		var mount_mesh := BoxMesh.new()
		mount_mesh.size = Vector3(2.8, 3.2, 5.5)
		mount.mesh = mount_mesh
		var angle: float = float(i) * PI * 0.5
		mount.position = Vector3(cos(angle) * 7.0, 3.0, sin(angle) * 7.0)
		mount.rotation.y = -angle
		mount.material_override = _material(Color(0.10, 0.11, 0.125), 0.72, 0.28)
		root.add_child(mount)

	var tower := Node3D.new()
	tower.position = Vector3(-18.0, 0.0, -7.0)
	root.add_child(tower)

	for i: int in range(4):
		var leg := MeshInstance3D.new()
		var leg_mesh := BoxMesh.new()
		leg_mesh.size = Vector3(0.8, 52.0, 0.8)
		leg.mesh = leg_mesh
		leg.position = Vector3(0.0 if i < 2 else 5.0, 26.0, 0.0 if i % 2 == 0 else 5.0)
		leg.material_override = _material(Color(0.20, 0.22, 0.25), 0.82, 0.24)
		tower.add_child(leg)

	for level: int in range(9):
		var platform := MeshInstance3D.new()
		var platform_mesh := BoxMesh.new()
		platform_mesh.size = Vector3(7.2, 0.34, 7.2)
		platform.mesh = platform_mesh
		platform.position = Vector3(2.5, 4.0 + level * 5.6, 2.5)
		platform.material_override = _material(Color(0.11, 0.12, 0.14), 0.84, 0.26)
		tower.add_child(platform)

	var road := MeshInstance3D.new()
	var road_mesh := BoxMesh.new()
	road_mesh.size = Vector3(180.0, 0.08, 13.0)
	road.mesh = road_mesh
	road.position = Vector3(70.0, 0.05, 0.0)
	road.material_override = _material(Color(0.055, 0.058, 0.062), 0.0, 0.98)
	root.add_child(road)

	return root

static func build_map_earth(radius: float = 18.0) -> Node3D:
	var root := Node3D.new()
	root.name = "MapEarth"

	var earth := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 96
	sphere.rings = 64
	earth.mesh = sphere
	earth.material_override = _material(Color(0.035, 0.18, 0.32), 0.0, 0.70)
	root.add_child(earth)

	var atmosphere := MeshInstance3D.new()
	var atmosphere_mesh := SphereMesh.new()
	atmosphere_mesh.radius = radius * 1.025
	atmosphere_mesh.height = radius * 2.05
	atmosphere_mesh.radial_segments = 96
	atmosphere_mesh.rings = 64
	atmosphere.mesh = atmosphere_mesh
	var atmosphere_mat := StandardMaterial3D.new()
	atmosphere_mat.albedo_color = Color(0.14, 0.48, 0.92, 0.12)
	atmosphere_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	atmosphere_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	atmosphere.material_override = atmosphere_mat
	root.add_child(atmosphere)

	return root

static func _material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	return mat
