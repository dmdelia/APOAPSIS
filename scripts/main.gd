extends Node3D

enum GameMode { BUILDER, FLIGHT, MAP }

const EARTH_RADIUS: float = 6378137.0
const EARTH_ROTATION_RATE: float = 7.2921159e-5
const LAUNCH_LATITUDE_DEG: float = 28.6084
const LAUNCH_LONGITUDE_DEG: float = -80.6043
const FIXED_DT: float = 1.0 / 120.0

var mode: int = GameMode.BUILDER
var vehicle: VehicleModel = VehicleModel.new()
var part_stack: Array[String] = []

var sim_position: Vector3 = Vector3.ZERO
var sim_velocity: Vector3 = Vector3.ZERO
var attitude: Quaternion = Quaternion.IDENTITY
var angular_rate: Vector3 = Vector3.ZERO
var accumulator: float = 0.0
var mission_time: float = 0.0
var last_event: String = "READY"
var max_q: float = 0.0

var root_visual: Node3D
var rocket_visual: Node3D
var camera: Camera3D
var earth_visual: MeshInstance3D
var ground_visual: MeshInstance3D
var pad_visual: MeshInstance3D
var exhaust_visual: MeshInstance3D

var ui_layer: CanvasLayer
var builder_panel: PanelContainer
var builder_stack_box: VBoxContainer
var builder_stats: Label
var flight_hud: Control
var map_panel: Control
var telemetry_labels: Dictionary = {}
var map_labels: Dictionary = {}

func _ready() -> void:
	_create_environment()
	_create_camera()
	_create_ui()
	_load_default_vehicle()
	_show_builder()

func _process(delta: float) -> void:
	if mode == GameMode.BUILDER:
		return

	_handle_flight_input(delta)
	if mode == GameMode.FLIGHT:
		accumulator += min(delta, 0.1)
		while accumulator >= FIXED_DT:
			_simulate_step(FIXED_DT)
			accumulator -= FIXED_DT
		_update_flight_visuals(delta)
		_update_flight_hud()
	elif mode == GameMode.MAP:
		_update_map_view()

func _create_environment() -> void:
	var world_environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.002, 0.004, 0.011)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.22, 0.24, 0.30)
	env.ambient_light_energy = 0.45
	world_environment.environment = env
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, -34.0, 0.0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	add_child(sun)

	root_visual = Node3D.new()
	root_visual.name = "WorldVisuals"
	add_child(root_visual)

	earth_visual = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	earth_visual.mesh = sphere
	earth_visual.scale = Vector3.ONE * EARTH_RADIUS
	earth_visual.position = Vector3(0.0, -EARTH_RADIUS, 0.0)
	var earth_mat := StandardMaterial3D.new()
	earth_mat.albedo_color = Color(0.035, 0.115, 0.19)
	earth_mat.metallic = 0.0
	earth_mat.roughness = 0.82
	earth_visual.material_override = earth_mat
	root_visual.add_child(earth_visual)

	ground_visual = MeshInstance3D.new()
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(12000.0, 12000.0)
	ground_visual.mesh = ground_mesh
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.12, 0.13, 0.11)
	ground_mat.roughness = 1.0
	ground_visual.material_override = ground_mat
	root_visual.add_child(ground_visual)

	pad_visual = MeshInstance3D.new()
	var pad_mesh := CylinderMesh.new()
	pad_mesh.top_radius = 24.0
	pad_mesh.bottom_radius = 24.0
	pad_mesh.height = 1.4
	pad_visual.mesh = pad_mesh
	pad_visual.position.y = 0.7
	var pad_mat := StandardMaterial3D.new()
	pad_mat.albedo_color = Color(0.11, 0.115, 0.125)
	pad_mat.metallic = 0.7
	pad_mat.roughness = 0.3
	pad_visual.material_override = pad_mat
	root_visual.add_child(pad_visual)

func _create_camera() -> void:
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 55.0
	camera.near = 0.05
	camera.far = 20000000.0
	add_child(camera)

func _create_ui() -> void:
	ui_layer = CanvasLayer.new()
	add_child(ui_layer)

	builder_panel = PanelContainer.new()
	builder_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(builder_panel)

	var builder_margin := MarginContainer.new()
	builder_margin.add_theme_constant_override("margin_left", 54)
	builder_margin.add_theme_constant_override("margin_right", 54)
	builder_margin.add_theme_constant_override("margin_top", 42)
	builder_margin.add_theme_constant_override("margin_bottom", 42)
	builder_panel.add_child(builder_margin)

	var builder_root := HBoxContainer.new()
	builder_root.add_theme_constant_override("separation", 42)
	builder_margin.add_child(builder_root)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(460, 0)
	left.add_theme_constant_override("separation", 14)
	builder_root.add_child(left)

	var title := Label.new()
	title.text = "APOAPSIS"
	title.add_theme_font_size_override("font_size", 42)
	left.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "VEHICLE ASSEMBLY"
	subtitle.modulate = Color(0.62, 0.67, 0.75)
	subtitle.add_theme_font_size_override("font_size", 16)
	left.add_child(subtitle)

	var separator := HSeparator.new()
	left.add_child(separator)

	for part_id: String in ["capsule", "tank_small", "tank_large", "engine_aquila", "engine_orion", "decoupler", "fin"]:
		var data: Dictionary = PartCatalog.get_part(part_id)
		var button := Button.new()
		button.text = "+  " + str(data.get("name", part_id))
		button.custom_minimum_size = Vector2(0, 48)
		button.pressed.connect(_on_add_part.bind(part_id))
		left.add_child(button)

	var row := HBoxContainer.new()
	left.add_child(row)

	var remove_button := Button.new()
	remove_button.text = "REMOVE LAST"
	remove_button.pressed.connect(_on_remove_last)
	row.add_child(remove_button)

	var reset_button := Button.new()
	reset_button.text = "DEFAULT VEHICLE"
	reset_button.pressed.connect(_load_default_vehicle)
	row.add_child(reset_button)

	var launch_button := Button.new()
	launch_button.text = "ROLL OUT & LAUNCH"
	launch_button.custom_minimum_size = Vector2(0, 60)
	launch_button.pressed.connect(_launch)
	left.add_child(launch_button)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 12)
	builder_root.add_child(right)

	var stack_title := Label.new()
	stack_title.text = "CURRENT STACK"
	stack_title.add_theme_font_size_override("font_size", 24)
	right.add_child(stack_title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(scroll)

	builder_stack_box = VBoxContainer.new()
	builder_stack_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	builder_stack_box.add_theme_constant_override("separation", 8)
	scroll.add_child(builder_stack_box)

	builder_stats = Label.new()
	builder_stats.add_theme_font_size_override("font_size", 18)
	right.add_child(builder_stats)

	flight_hud = Control.new()
	flight_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(flight_hud)

	var top_bar := ColorRect.new()
	top_bar.color = Color(0.01, 0.014, 0.022, 0.88)
	top_bar.position = Vector2(28, 24)
	top_bar.size = Vector2(650, 84)
	flight_hud.add_child(top_bar)

	var flight_title := Label.new()
	flight_title.text = "APOAPSIS  /  FLIGHT"
	flight_title.position = Vector2(20, 12)
	flight_title.add_theme_font_size_override("font_size", 24)
	top_bar.add_child(flight_title)

	var event_label := Label.new()
	event_label.name = "event"
	event_label.position = Vector2(20, 48)
	event_label.modulate = Color(0.62, 0.68, 0.76)
	event_label.add_theme_font_size_override("font_size", 14)
	top_bar.add_child(event_label)
	telemetry_labels["event"] = event_label

	var bottom := ColorRect.new()
	bottom.color = Color(0.01, 0.014, 0.022, 0.92)
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.position = Vector2(28, -178)
	bottom.size = Vector2(1864, 150)
	flight_hud.add_child(bottom)

	var fields: Array[String] = ["ALTITUDE", "SPEED", "VERT SPEED", "MACH", "DYN PRESSURE", "THROTTLE", "MASS", "FUEL", "APOAPSIS", "PERIAPSIS", "T+ "]
	var x: float = 20.0
	for field: String in fields:
		var group := VBoxContainer.new()
		group.position = Vector2(x, 18)
		group.size = Vector2(155, 105)
		bottom.add_child(group)
		var cap := Label.new()
		cap.text = field
		cap.modulate = Color(0.52, 0.58, 0.67)
		cap.add_theme_font_size_override("font_size", 11)
		group.add_child(cap)
		var value := Label.new()
		value.text = "-"
		value.add_theme_font_size_override("font_size", 21)
		group.add_child(value)
		telemetry_labels[field] = value
		x += 166.0

	var help := Label.new()
	help.text = "W/S THROTTLE   A/D PITCH   Q/E YAW   Z/C ROLL   SPACE STAGE   M MAP   X SHUTDOWN   R RESET"
	help.position = Vector2(36, 111)
	help.modulate = Color(0.55, 0.60, 0.68)
	help.add_theme_font_size_override("font_size", 12)
	bottom.add_child(help)

	map_panel = Control.new()
	map_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(map_panel)

	var map_bg := ColorRect.new()
	map_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_bg.color = Color(0.002, 0.004, 0.011, 0.96)
	map_panel.add_child(map_bg)

	var map_title := Label.new()
	map_title.text = "ORBITAL MAP"
	map_title.position = Vector2(44, 34)
	map_title.add_theme_font_size_override("font_size", 30)
	map_bg.add_child(map_title)

	var map_info := VBoxContainer.new()
	map_info.position = Vector2(44, 100)
	map_info.size = Vector2(430, 420)
	map_info.add_theme_constant_override("separation", 14)
	map_bg.add_child(map_info)

	for key: String in ["APOAPSIS", "PERIAPSIS", "ECCENTRICITY", "INCLINATION", "PERIOD", "VELOCITY", "ALTITUDE"]:
		var label := Label.new()
		label.text = key + ": -"
		label.add_theme_font_size_override("font_size", 20)
		map_info.add_child(label)
		map_labels[key] = label

	var hint := Label.new()
	hint.text = "M RETURN TO FLIGHT"
	hint.position = Vector2(44, 960)
	hint.modulate = Color(0.58, 0.64, 0.72)
	hint.add_theme_font_size_override("font_size", 14)
	map_bg.add_child(hint)

func _load_default_vehicle() -> void:
	part_stack = PartCatalog.default_stack()
	_refresh_builder()

func _on_add_part(part_id: String) -> void:
	part_stack.append(part_id)
	_refresh_builder()

func _on_remove_last() -> void:
	if not part_stack.is_empty():
		part_stack.pop_back()
	_refresh_builder()

func _refresh_builder() -> void:
	if builder_stack_box == null:
		return
	for child: Node in builder_stack_box.get_children():
		child.queue_free()

	var total_dry: float = 0.0
	var total_fuel: float = 0.0
	var engines: int = 0
	var index: int = 1
	for part_id: String in part_stack:
		var data: Dictionary = PartCatalog.get_part(part_id)
		var row := Label.new()
		row.text = "%02d   %s" % [index, str(data.get("name", part_id))]
		row.add_theme_font_size_override("font_size", 18)
		builder_stack_box.add_child(row)
		total_dry += float(data.get("dry_mass", 0.0))
		total_fuel += float(data.get("fuel", 0.0))
		if str(data.get("type", "")) == "engine":
			engines += 1
		index += 1

	builder_stats.text = "PARTS %d     DRY %s     PROPELLANT %s     ENGINES %d" % [
		part_stack.size(),
		_format_mass(total_dry),
		_format_mass(total_fuel),
		engines
	]

func _show_builder() -> void:
	mode = GameMode.BUILDER
	builder_panel.visible = true
	flight_hud.visible = false
	map_panel.visible = false
	if rocket_visual != null:
		rocket_visual.queue_free()
		rocket_visual = null
	camera.position = Vector3(34, 24, 34)
	camera.look_at(Vector3(0, 8, 0), Vector3.UP)

func _launch() -> void:
	if part_stack.is_empty():
		return
	vehicle.configure(part_stack)
	_create_rocket_visual()
	_initialize_simulation()
	mode = GameMode.FLIGHT
	builder_panel.visible = false
	flight_hud.visible = true
	map_panel.visible = false
	last_event = "PAD READY / SPACE TO IGNITE"

func _initialize_simulation() -> void:
	var lat: float = deg_to_rad(LAUNCH_LATITUDE_DEG)
	var lon: float = deg_to_rad(LAUNCH_LONGITUDE_DEG)
	sim_position = Vector3(
		EARTH_RADIUS * cos(lat) * cos(lon),
		EARTH_RADIUS * sin(lat),
		EARTH_RADIUS * cos(lat) * sin(lon)
	)
	var omega := Vector3(0.0, EARTH_ROTATION_RATE, 0.0)
	sim_velocity = omega.cross(sim_position)
	attitude = Quaternion.IDENTITY
	angular_rate = Vector3.ZERO
	mission_time = 0.0
	max_q = 0.0
	accumulator = 0.0
	vehicle.set_throttle(0.0)

func _create_rocket_visual() -> void:
	if rocket_visual != null:
		rocket_visual.queue_free()
	rocket_visual = Node3D.new()
	rocket_visual.name = "Rocket"
	root_visual.add_child(rocket_visual)

	var y: float = 0.0
	for part_id: String in part_stack:
		var data: Dictionary = PartCatalog.get_part(part_id)
		var part := MeshInstance3D.new()
		var h: float = float(data.get("height", 1.0))
		var r: float = float(data.get("radius", 1.0))
		var type_name: String = str(data.get("type", ""))

		if type_name == "capsule":
			var capsule_mesh := CylinderMesh.new()
			capsule_mesh.top_radius = 0.12
			capsule_mesh.bottom_radius = r
			capsule_mesh.height = h
			part.mesh = capsule_mesh
		elif type_name == "fin":
			var fin_mesh := CylinderMesh.new()
			fin_mesh.top_radius = r * 0.55
			fin_mesh.bottom_radius = r
			fin_mesh.height = h
			part.mesh = fin_mesh
		else:
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = r
			cylinder.bottom_radius = r * (0.72 if type_name == "engine" else 1.0)
			cylinder.height = h
			part.mesh = cylinder

		var mat := StandardMaterial3D.new()
		if type_name == "engine":
			mat.albedo_color = Color(0.08, 0.085, 0.095)
			mat.metallic = 0.9
			mat.roughness = 0.22
		elif type_name == "decoupler":
			mat.albedo_color = Color(0.16, 0.17, 0.19)
			mat.metallic = 0.75
			mat.roughness = 0.30
		elif type_name == "fin":
			mat.albedo_color = Color(0.18, 0.19, 0.21)
			mat.metallic = 0.55
			mat.roughness = 0.34
		else:
			mat.albedo_color = Color(0.86, 0.875, 0.90)
			mat.metallic = 0.16
			mat.roughness = 0.34
		part.material_override = mat
		part.position.y = y + h * 0.5
		rocket_visual.add_child(part)
		y += h

	exhaust_visual = MeshInstance3D.new()
	var plume := CylinderMesh.new()
	plume.top_radius = 0.7
	plume.bottom_radius = 0.18
	plume.height = 7.0
	exhaust_visual.mesh = plume
	exhaust_visual.position.y = -3.5
	var plume_mat := StandardMaterial3D.new()
	plume_mat.albedo_color = Color(1.0, 0.46, 0.08)
	plume_mat.emission_enabled = true
	plume_mat.emission = Color(1.0, 0.23, 0.03)
	plume_mat.emission_energy_multiplier = 6.0
	exhaust_visual.material_override = plume_mat
	exhaust_visual.visible = false
	rocket_visual.add_child(exhaust_visual)

func _handle_flight_input(delta: float) -> void:
	if Input.is_action_just_pressed("map_view"):
		if mode == GameMode.FLIGHT:
			mode = GameMode.MAP
			flight_hud.visible = false
			map_panel.visible = true
		else:
			mode = GameMode.FLIGHT
			flight_hud.visible = true
			map_panel.visible = false
		return

	if mode != GameMode.FLIGHT:
		return

	var throttle_delta: float = 0.42 * delta
	if Input.is_action_pressed("throttle_up"):
		vehicle.set_throttle(vehicle.throttle + throttle_delta)
	if Input.is_action_pressed("throttle_down"):
		vehicle.set_throttle(vehicle.throttle - throttle_delta)

	if Input.is_action_just_pressed("stage"):
		last_event = vehicle.activate_or_stage()
	if Input.is_action_just_pressed("shutdown"):
		vehicle.shutdown()
		last_event = "ENGINE SHUTDOWN"
	if Input.is_action_just_pressed("reset_flight"):
		_show_builder()
		return

	var pitch_input: float = Input.get_axis("pitch_left", "pitch_right")
	var yaw_input: float = Input.get_axis("yaw_left", "yaw_right")
	var roll_input: float = Input.get_axis("roll_left", "roll_right")
	var target_rate := Vector3(pitch_input, yaw_input, roll_input) * 0.38
	angular_rate = angular_rate.lerp(target_rate, clamp(delta * 3.0, 0.0, 1.0))

func _simulate_step(dt: float) -> void:
	mission_time += dt

	var altitude: float = max(0.0, sim_position.length() - EARTH_RADIUS)
	var atmosphere: Dictionary = Atmosphere1976.sample(altitude)
	var pressure: float = float(atmosphere["pressure"])
	var density: float = float(atmosphere["density"])

	var omega := Vector3(0.0, EARTH_ROTATION_RATE, 0.0)
	var atmosphere_velocity: Vector3 = omega.cross(sim_position)
	var relative_air_velocity: Vector3 = sim_velocity - atmosphere_velocity
	var airspeed: float = relative_air_velocity.length()

	var gravity: Vector3 = OrbitMath.gravity_acceleration(sim_position)
	var force: Vector3 = gravity * vehicle.total_mass()

	var engine_data: Dictionary = vehicle.consume_and_get_thrust(dt, pressure)
	var thrust: float = float(engine_data["thrust"])
	var up: Vector3 = sim_position.normalized()
	var east: Vector3 = Vector3.UP.cross(up).normalized()
	if east.length_squared() < 0.01:
		east = Vector3.RIGHT
	var north: Vector3 = up.cross(east).normalized()

	var q_pitch := Quaternion(east, angular_rate.x * dt)
	var q_yaw := Quaternion(north, angular_rate.y * dt)
	var q_roll := Quaternion(up, angular_rate.z * dt)
	attitude = (q_roll * q_yaw * q_pitch * attitude).normalized()
	var thrust_direction: Vector3 = attitude * up
	if thrust > 0.0:
		force += thrust_direction.normalized() * thrust

	if airspeed > 0.01 and density > 0.0000001:
		var cd: float = 0.28
		var drag: float = 0.5 * density * airspeed * airspeed * cd * vehicle.reference_area()
		force -= relative_air_velocity.normalized() * drag
		var q_dynamic: float = 0.5 * density * airspeed * airspeed
		max_q = max(max_q, q_dynamic)

	var acceleration: Vector3 = force / vehicle.total_mass()
	sim_velocity += acceleration * dt
	sim_position += sim_velocity * dt

	if sim_position.length() < EARTH_RADIUS:
		sim_position = sim_position.normalized() * EARTH_RADIUS
		var radial_velocity: float = sim_velocity.dot(sim_position.normalized())
		if radial_velocity < 0.0:
			sim_velocity -= sim_position.normalized() * radial_velocity

func _update_flight_visuals(delta: float) -> void:
	if rocket_visual == null:
		return

	var altitude: float = max(0.0, sim_position.length() - EARTH_RADIUS)
	var up: Vector3 = sim_position.normalized()
	var lat: float = deg_to_rad(LAUNCH_LATITUDE_DEG)
	var lon: float = deg_to_rad(LAUNCH_LONGITUDE_DEG)
	var launch_pos := Vector3(
		EARTH_RADIUS * cos(lat) * cos(lon),
		EARTH_RADIUS * sin(lat),
		EARTH_RADIUS * cos(lat) * sin(lon)
	)
	var local_offset: Vector3 = sim_position - launch_pos

	rocket_visual.position = local_offset
	rocket_visual.quaternion = attitude

	var airspeed: float = (sim_velocity - Vector3(0.0, EARTH_ROTATION_RATE, 0.0).cross(sim_position)).length()
	var follow_distance: float = clamp(42.0 + airspeed * 0.018, 42.0, 300.0)
	var desired_camera := local_offset + Vector3(follow_distance, follow_distance * 0.42, follow_distance)
	camera.position = camera.position.lerp(desired_camera, clamp(delta * 2.2, 0.0, 1.0))
	camera.look_at(local_offset + up * 5.0, Vector3.UP)

	exhaust_visual.visible = vehicle.engines_armed and vehicle.throttle > 0.0 and vehicle.current_fuel() > 0.0
	if exhaust_visual.visible:
		exhaust_visual.scale.y = 0.45 + vehicle.throttle * 1.05

	ground_visual.visible = altitude < 25000.0
	pad_visual.visible = altitude < 25000.0

func _update_flight_hud() -> void:
	var altitude: float = max(0.0, sim_position.length() - EARTH_RADIUS)
	var radial_speed: float = sim_velocity.dot(sim_position.normalized())
	var atmosphere: Dictionary = Atmosphere1976.sample(altitude)
	var sound_speed: float = float(atmosphere["speed_of_sound"])
	var density: float = float(atmosphere["density"])
	var air_velocity: Vector3 = sim_velocity - Vector3(0.0, EARTH_ROTATION_RATE, 0.0).cross(sim_position)
	var airspeed: float = air_velocity.length()
	var mach: float = airspeed / max(sound_speed, 1.0)
	var q_dynamic: float = 0.5 * density * airspeed * airspeed
	var orbit: Dictionary = OrbitMath.elements(sim_position, sim_velocity)

	_set_telemetry("ALTITUDE", _format_distance(altitude))
	_set_telemetry("SPEED", "%0.1f m/s" % sim_velocity.length())
	_set_telemetry("VERT SPEED", "%+0.1f m/s" % radial_speed)
	_set_telemetry("MACH", "%0.2f" % mach)
	_set_telemetry("DYN PRESSURE", "%0.1f kPa" % (q_dynamic / 1000.0))
	_set_telemetry("THROTTLE", "%0.0f%%" % (vehicle.throttle * 100.0))
	_set_telemetry("MASS", _format_mass(vehicle.total_mass()))
	_set_telemetry("FUEL", _format_mass(vehicle.current_fuel()))
	_set_telemetry("APOAPSIS", _format_distance(float(orbit["apoapsis_m"])))
	_set_telemetry("PERIAPSIS", _format_distance(float(orbit["periapsis_m"])))
	_set_telemetry("T+ ", _format_time(mission_time))

	var event_label: Label = telemetry_labels["event"] as Label
	event_label.text = "%s   |   STAGE %d/%d   |   MAX Q %0.1f kPa" % [
		last_event,
		vehicle.current_stage + 1,
		vehicle.stage_count(),
		max_q / 1000.0
	]

func _update_map_view() -> void:
	var altitude: float = max(0.0, sim_position.length() - EARTH_RADIUS)
	var orbit: Dictionary = OrbitMath.elements(sim_position, sim_velocity)
	_set_map("APOAPSIS", _format_distance(float(orbit["apoapsis_m"])))
	_set_map("PERIAPSIS", _format_distance(float(orbit["periapsis_m"])))
	_set_map("ECCENTRICITY", "%0.5f" % float(orbit["eccentricity"]))
	_set_map("INCLINATION", "%0.2f deg" % float(orbit["inclination_deg"]))
	_set_map("PERIOD", _format_time(float(orbit["period_s"])) if is_finite(float(orbit["period_s"])) else "ESCAPE")
	_set_map("VELOCITY", "%0.1f m/s" % sim_velocity.length())
	_set_map("ALTITUDE", _format_distance(altitude))

	camera.position = Vector3(EARTH_RADIUS * 1.45, EARTH_RADIUS * 0.65, EARTH_RADIUS * 1.45)
	camera.look_at(Vector3(0.0, -EARTH_RADIUS, 0.0), Vector3.UP)

func _set_telemetry(key: String, value: String) -> void:
	var label: Label = telemetry_labels[key] as Label
	label.text = value

func _set_map(key: String, value: String) -> void:
	var label: Label = map_labels[key] as Label
	label.text = key + ": " + value

func _format_distance(value_m: float) -> String:
	if not is_finite(value_m):
		return "ESCAPE"
	if abs(value_m) >= 1000000.0:
		return "%0.2f Mm" % (value_m / 1000000.0)
	if abs(value_m) >= 1000.0:
		return "%0.1f km" % (value_m / 1000.0)
	return "%0.0f m" % value_m

func _format_mass(value_kg: float) -> String:
	if value_kg >= 1000.0:
		return "%0.2f t" % (value_kg / 1000.0)
	return "%0.0f kg" % value_kg

func _format_time(seconds: float) -> String:
	if not is_finite(seconds) or seconds < 0.0:
		return "-"
	var total: int = int(seconds)
	var hours: int = total / 3600
	var minutes: int = (total % 3600) / 60
	var secs: int = total % 60
	if hours > 0:
		return "%02d:%02d:%02d" % [hours, minutes, secs]
	return "%02d:%02d" % [minutes, secs]
