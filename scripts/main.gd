extends Node3D

const G0 := 9.80665
const SEA_LEVEL_DENSITY := 1.225
const SCALE_HEIGHT := 8500.0

var rocket: RigidBody3D
var camera: Camera3D
var throttle := 0.0
var fuel_mass := 7800.0
var dry_mass := 4200.0
var max_thrust := 230000.0
var isp := 285.0
var engine_on := false
var altitude := 0.0
var velocity := 0.0
var mission_time := 0.0

var altitude_label: Label
var speed_label: Label
var throttle_label: Label
var fuel_label: Label
var status_label: Label
var time_label: Label

func _ready() -> void:
	_build_world()
	_build_rocket()
	_build_hud()

func _physics_process(delta: float) -> void:
	if Input.is_action_pressed("throttle_up"):
		throttle = min(1.0, throttle + delta * 0.45)
	if Input.is_action_pressed("throttle_down"):
		throttle = max(0.0, throttle - delta * 0.45)

	if Input.is_action_just_pressed("stage"):
		engine_on = !engine_on

	if Input.is_action_just_pressed("reset_flight"):
		get_tree().reload_current_scene()

	if rocket:
		_update_flight(delta)
		_update_camera(delta)
		_update_hud()

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.005, 0.008, 0.018)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.18, 0.21, 0.30)
	environment.ambient_light_energy = 0.8
	env.environment = environment
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -28, 0)
	sun.light_energy = 1.8
	sun.shadow_enabled = true
	add_child(sun)

	var ground := StaticBody3D.new()
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2000, 2, 2000)
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.055, 0.06, 0.07)
	mat.roughness = 0.92
	mesh.material_override = mat
	ground.add_child(mesh)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2000, 2, 2000)
	collider.shape = shape
	ground.add_child(collider)
	ground.position.y = -1
	add_child(ground)

	var pad := MeshInstance3D.new()
	var pad_mesh := CylinderMesh.new()
	pad_mesh.top_radius = 16
	pad_mesh.bottom_radius = 16
	pad_mesh.height = 1.2
	pad.mesh = pad_mesh
	pad.position.y = 0.6
	var pad_mat := StandardMaterial3D.new()
	pad_mat.albedo_color = Color(0.13, 0.14, 0.16)
	pad_mat.metallic = 0.65
	pad_mat.roughness = 0.38
	pad.material_override = pad_mat
	add_child(pad)

func _build_rocket() -> void:
	rocket = RigidBody3D.new()
	rocket.name = "Vehicle"
	rocket.position = Vector3(0, 10.5, 0)
	rocket.mass = (dry_mass + fuel_mass) / 1000.0
	rocket.linear_damp = 0.02
	rocket.angular_damp = 1.2
	add_child(rocket)

	var body_mesh := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 1.7
	cylinder.bottom_radius = 1.7
	cylinder.height = 15.0
	body_mesh.mesh = cylinder
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.88, 0.89, 0.91)
	body_mat.metallic = 0.15
	body_mat.roughness = 0.35
	body_mesh.material_override = body_mat
	rocket.add_child(body_mesh)

	var nose := MeshInstance3D.new()
	var nose_mesh := CylinderMesh.new()
	nose_mesh.top_radius = 0.05
	nose_mesh.bottom_radius = 1.7
	nose_mesh.height = 4.2
	nose.mesh = nose_mesh
	nose.position.y = 9.55
	nose.material_override = body_mat
	rocket.add_child(nose)

	var engine := MeshInstance3D.new()
	var engine_mesh := CylinderMesh.new()
	engine_mesh.top_radius = 0.85
	engine_mesh.bottom_radius = 1.25
	engine_mesh.height = 2.0
	engine.mesh = engine_mesh
	engine.position.y = -8.5
	var engine_mat := StandardMaterial3D.new()
	engine_mat.albedo_color = Color(0.08, 0.09, 0.11)
	engine_mat.metallic = 0.9
	engine_mat.roughness = 0.22
	engine.material_override = engine_mat
	rocket.add_child(engine)

	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 1.7
	capsule.height = 18.0
	collision.shape = capsule
	rocket.add_child(collision)

	camera = Camera3D.new()
	camera.current = true
	camera.fov = 58
	add_child(camera)
	camera.position = Vector3(34, 20, 34)
	camera.look_at(rocket.global_position, Vector3.UP)

func _update_flight(delta: float) -> void:
	mission_time += delta
	altitude = max(0.0, rocket.global_position.y - 9.0)
	velocity = rocket.linear_velocity.length()

	if Input.is_action_pressed("pitch_left"):
		rocket.apply_torque(Vector3(0, 0, 26000.0))
	if Input.is_action_pressed("pitch_right"):
		rocket.apply_torque(Vector3(0, 0, -26000.0))

	if engine_on and throttle > 0.0 and fuel_mass > 0.0:
		var thrust := max_thrust * throttle
		var thrust_dir := rocket.global_transform.basis.y.normalized()
		rocket.apply_central_force(thrust_dir * thrust)

		var mass_flow := thrust / (isp * G0)
		fuel_mass = max(0.0, fuel_mass - mass_flow * delta)
		rocket.mass = max(0.1, (dry_mass + fuel_mass) / 1000.0)

		var density := SEA_LEVEL_DENSITY * exp(-altitude / SCALE_HEIGHT)
		var v := rocket.linear_velocity
		if v.length() > 0.1:
			var drag_force := 0.5 * density * v.length_squared() * 0.34 * 9.1
			rocket.apply_central_force(-v.normalized() * drag_force)

	if fuel_mass <= 0.0:
		engine_on = false

func _update_camera(delta: float) -> void:
	var distance := clamp(32.0 + velocity * 0.035, 32.0, 120.0)
	var desired := rocket.global_position + Vector3(distance, max(15.0, distance * 0.45), distance)
	camera.global_position = camera.global_position.lerp(desired, clamp(delta * 2.4, 0.0, 1.0))
	camera.look_at(rocket.global_position + rocket.linear_velocity * 0.08, Vector3.UP)

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var title := Label.new()
	title.text = "APOAPSIS"
	title.position = Vector2(38, 28)
	title.add_theme_font_size_override("font_size", 32)
	layer.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "FLIGHT TEST 01"
	subtitle.position = Vector2(40, 69)
	subtitle.modulate = Color(0.62, 0.67, 0.76)
	subtitle.add_theme_font_size_override("font_size", 14)
	layer.add_child(subtitle)

	var panel := ColorRect.new()
	panel.color = Color(0.02, 0.025, 0.035, 0.88)
	panel.position = Vector2(34, 815)
	panel.size = Vector2(1852, 218)
	layer.add_child(panel)

	altitude_label = _hud_label(panel, Vector2(34, 26), "ALTITUDE")
	speed_label = _hud_label(panel, Vector2(330, 26), "SPEED")
	throttle_label = _hud_label(panel, Vector2(610, 26), "THROTTLE")
	fuel_label = _hud_label(panel, Vector2(900, 26), "PROPELLANT")
	time_label = _hud_label(panel, Vector2(1220, 26), "MISSION")
	status_label = _hud_label(panel, Vector2(1510, 26), "STATUS")

	var help := Label.new()
	help.text = "W/S THROTTLE     A/D PITCH     SPACE ENGINE     R RESET"
	help.position = Vector2(40, 1000)
	help.modulate = Color(0.58, 0.61, 0.68)
	help.add_theme_font_size_override("font_size", 13)
	layer.add_child(help)

func _hud_label(parent: Control, pos: Vector2, caption: String) -> Label:
	var caption_label := Label.new()
	caption_label.text = caption
	caption_label.position = pos
	caption_label.modulate = Color(0.54, 0.59, 0.68)
	caption_label.add_theme_font_size_override("font_size", 13)
	parent.add_child(caption_label)

	var value := Label.new()
	value.position = pos + Vector2(0, 34)
	value.add_theme_font_size_override("font_size", 29)
	parent.add_child(value)
	return value

func _update_hud() -> void:
	altitude_label.text = "%0.0f m" % altitude
	speed_label.text = "%0.1f m/s" % velocity
	throttle_label.text = "%0.0f %%" % (throttle * 100.0)
	fuel_label.text = "%0.0f kg" % fuel_mass
	time_label.text = "T+ %02d:%02d" % [int(mission_time) / 60, int(mission_time) % 60]
	if fuel_mass <= 0.0:
		status_label.text = "FUEL DEPLETED"
	elif engine_on:
		status_label.text = "ENGINE ACTIVE"
	else:
		status_label.text = "ENGINE SAFE"
