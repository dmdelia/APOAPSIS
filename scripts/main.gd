extends Node3D

enum GameMode { MENU, BUILDER, FLIGHT, MAP }

const EARTH_RADIUS: float = 6378137.0
const EARTH_MU: float = 3.986004418e14
const EARTH_ROTATION_RATE: float = 7.2921159e-5
const LAUNCH_LATITUDE_DEG: float = 28.6084
const LAUNCH_LONGITUDE_DEG: float = -80.6043
const PHYSICS_STEP: float = 1.0 / 120.0

const COLOR_BG := Color(0.008, 0.012, 0.020)
const COLOR_PANEL := Color(0.025, 0.034, 0.050, 0.95)
const COLOR_PANEL_2 := Color(0.040, 0.052, 0.075, 0.94)
const COLOR_LINE := Color(0.15, 0.20, 0.28, 0.85)
const COLOR_TEXT := Color(0.92, 0.95, 1.0)
const COLOR_MUTED := Color(0.52, 0.60, 0.70)
const COLOR_ACCENT := Color(0.10, 0.58, 0.98)
const COLOR_GOOD := Color(0.25, 0.90, 0.58)
const COLOR_WARN := Color(1.0, 0.62, 0.18)
const COLOR_DANGER := Color(1.0, 0.28, 0.32)

var mode: int = GameMode.MENU
var vehicle := VehicleModel.new()
var part_stack: Array[String] = PartCatalog.default_stack()

var sim_position: DVec3 = DVec3.new()
var sim_velocity: DVec3 = DVec3.new()
var attitude := Quaternion.IDENTITY
var angular_rate := Vector3.ZERO
var launch_position_ecef: DVec3 = DVec3.new()
var launch_up_ecef: DVec3 = DVec3.new(0.0, 1.0, 0.0)
var launch_east_ecef: DVec3 = DVec3.new(1.0, 0.0, 0.0)
var launch_north_ecef: DVec3 = DVec3.new(0.0, 0.0, -1.0)
var physics_accumulator: float = 0.0
var mission_time: float = 0.0
var max_q: float = 0.0
var heat_flux_w_m2: float = 0.0
var g_load: float = 1.0
var has_liftoff: bool = false
var landed: bool = false
var crashed: bool = false
var last_event: String = "READY"
var warp_factor: float = 1.0
var last_stage_visual: int = -1

var environment: Environment
var sky_material: ProceduralSkyMaterial
var sun: DirectionalLight3D

var world_root: Node3D
var launch_site: Node3D
var builder_floor: Node3D
var rocket_visual: Node3D
var plume_visual: MeshInstance3D
var map_root: Node3D
var map_trajectory: MeshInstance3D
var map_vehicle_marker: MeshInstance3D

var camera: Camera3D
var camera_yaw: float = deg_to_rad(42.0)
var camera_pitch: float = deg_to_rad(-18.0)
var camera_distance: float = 48.0
var camera_dragging: bool = false
var camera_drag_origin := Vector2.ZERO
var builder_spin: float = 0.0

var ui_layer: CanvasLayer
var menu_ui: Control
var builder_ui: Control
var flight_ui: Control
var map_ui: Control

var stack_list: VBoxContainer
var builder_status: Label
var builder_mass: Label
var builder_twr: Label
var builder_dv: Label
var builder_stage_count: Label
var launch_button: Button

var flight_values: Dictionary = {}
var flight_event: Label
var flight_warp: Label
var map_values: Dictionary = {}
var map_refresh_timer: float = 0.0

func _ready() -> void:
	_create_environment()
	_create_world()
	_create_camera()
	_create_ui()
	_show_menu()

func _process(delta: float) -> void:
	match mode:
		GameMode.MENU:
			_update_menu_camera(delta)
		GameMode.BUILDER:
			_update_builder_camera(delta)
		GameMode.FLIGHT:
			_update_flight(delta)
		GameMode.MAP:
			_update_map(delta)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_RIGHT:
			camera_dragging = mouse_button.pressed
			camera_drag_origin = mouse_button.position
		elif mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_button.pressed:
			camera_distance = max(10.0, camera_distance * 0.88)
		elif mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_button.pressed:
			camera_distance = min(500.0, camera_distance * 1.12)

	if event is InputEventMouseMotion and camera_dragging:
		var motion := event as InputEventMouseMotion
		camera_yaw -= motion.relative.x * 0.006
		camera_pitch = clamp(camera_pitch - motion.relative.y * 0.006, deg_to_rad(-80.0), deg_to_rad(65.0))

	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.physical_keycode == KEY_ESCAPE:
			if mode == GameMode.MENU:
				get_tree().quit()
			elif mode == GameMode.BUILDER:
				_show_menu()
			else:
				_show_builder()
		elif key.physical_keycode == KEY_1:
			_set_warp(1.0)
		elif key.physical_keycode == KEY_2:
			_set_warp(5.0)
		elif key.physical_keycode == KEY_3:
			_set_warp(20.0)
		elif key.physical_keycode == KEY_4:
			_set_warp(100.0)

func _create_environment() -> void:
	var world_environment := WorldEnvironment.new()
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.65
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = true
	environment.glow_intensity = 0.75

	sky_material = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.025, 0.12, 0.28)
	sky_material.sky_horizon_color = Color(0.42, 0.63, 0.82)
	sky_material.ground_bottom_color = Color(0.015, 0.02, 0.025)
	sky_material.ground_horizon_color = Color(0.30, 0.34, 0.36)
	sky_material.sun_angle_max = 20.0
	sky_material.sun_curve = 0.08

	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.sky = sky
	world_environment.environment = environment
	add_child(world_environment)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -28.0, 0.0)
	sun.light_energy = 2.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 16000.0
	add_child(sun)

func _create_world() -> void:
	world_root = Node3D.new()
	world_root.name = "World"
	add_child(world_root)

	launch_site = WorldFactory.build_launch_site()
	world_root.add_child(launch_site)

	builder_floor = Node3D.new()
	builder_floor.name = "BuilderFloor"
	world_root.add_child(builder_floor)

	var floor := MeshInstance3D.new()
	var floor_mesh := CylinderMesh.new()
	floor_mesh.top_radius = 12.0
	floor_mesh.bottom_radius = 12.0
	floor_mesh.height = 0.8
	floor_mesh.radial_segments = 72
	floor.mesh = floor_mesh
	floor.position.y = 0.4
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.055, 0.070, 0.095)
	floor_mat.metallic = 0.72
	floor_mat.roughness = 0.30
	floor.material_override = floor_mat
	builder_floor.add_child(floor)

	for i: int in range(12):
		var tick := MeshInstance3D.new()
		var tick_mesh := BoxMesh.new()
		tick_mesh.size = Vector3(0.06, 0.025, 2.0)
		tick.mesh = tick_mesh
		var angle := float(i) * TAU / 12.0
		tick.position = Vector3(cos(angle) * 10.5, 0.83, sin(angle) * 10.5)
		tick.rotation.y = -angle
		var tick_mat := StandardMaterial3D.new()
		tick_mat.albedo_color = COLOR_ACCENT
		tick_mat.emission_enabled = true
		tick_mat.emission = COLOR_ACCENT
		tick_mat.emission_energy_multiplier = 1.3
		tick.material_override = tick_mat
		builder_floor.add_child(tick)

	map_root = WorldFactory.build_map_earth(18.0)
	map_root.visible = false
	add_child(map_root)

	map_trajectory = MeshInstance3D.new()
	map_root.add_child(map_trajectory)

	map_vehicle_marker = MeshInstance3D.new()
	var marker_mesh := SphereMesh.new()
	marker_mesh.radius = 0.55
	marker_mesh.height = 1.10
	map_vehicle_marker.mesh = marker_mesh
	var marker_mat := StandardMaterial3D.new()
	marker_mat.albedo_color = COLOR_ACCENT
	marker_mat.emission_enabled = true
	marker_mat.emission = COLOR_ACCENT
	marker_mat.emission_energy_multiplier = 2.5
	map_vehicle_marker.material_override = marker_mat
	map_root.add_child(map_vehicle_marker)

func _create_camera() -> void:
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 52.0
	camera.near = 0.20
	camera.far = 8000.0
	camera.make_current()
	add_child(camera)

func _create_ui() -> void:
	ui_layer = CanvasLayer.new()
	add_child(ui_layer)
	menu_ui = _build_menu_ui()
	builder_ui = _build_builder_ui()
	flight_ui = _build_flight_ui()
	map_ui = _build_map_ui()

func _build_menu_ui() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(root)

	var vignette := ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.color = Color(0.005, 0.008, 0.015, 0.28)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vignette)

	var panel := PanelContainer.new()
	panel.position = Vector2(72, 80)
	panel.size = Vector2(560, 650)
	panel.add_theme_stylebox_override("panel", _panel_style(COLOR_PANEL, 18.0))
	root.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 42)
	margin.add_theme_constant_override("margin_right", 42)
	margin.add_theme_constant_override("margin_top", 42)
	margin.add_theme_constant_override("margin_bottom", 42)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	margin.add_child(box)

	var eyebrow := Label.new()
	eyebrow.text = "ORBITAL FLIGHT SIMULATOR"
	eyebrow.modulate = COLOR_ACCENT
	eyebrow.add_theme_font_size_override("font_size", 15)
	box.add_child(eyebrow)

	var title := Label.new()
	title.text = "APOAPSIS"
	title.add_theme_font_size_override("font_size", 58)
	title.modulate = COLOR_TEXT
	box.add_child(title)

	var desc := Label.new()
	desc.text = "BUILD. LAUNCH. ORBIT. RETURN."
	desc.modulate = COLOR_MUTED
	desc.add_theme_font_size_override("font_size", 18)
	box.add_child(desc)

	var spacer := Control.new()
	spacer.custom_minimum_size.y = 26
	box.add_child(spacer)

	var new_vehicle := _make_button("NEW VEHICLE", true)
	new_vehicle.custom_minimum_size.y = 62
	new_vehicle.pressed.connect(_show_builder)
	box.add_child(new_vehicle)

	var quick_launch := _make_button("QUICK LAUNCH", false)
	quick_launch.custom_minimum_size.y = 54
	quick_launch.pressed.connect(_quick_launch)
	box.add_child(quick_launch)

	var separator := HSeparator.new()
	separator.add_theme_constant_override("separation", 18)
	box.add_child(separator)

	var simulation := Label.new()
	simulation.text = "SIMULATION CORE"
	simulation.modulate = COLOR_MUTED
	simulation.add_theme_font_size_override("font_size", 13)
	box.add_child(simulation)

	for line: String in [
		"120 Hz deterministic flight integration",
		"Pressure-dependent thrust and specific impulse",
		"Earth rotation, atmosphere, Mach and dynamic pressure",
		"Two-body orbital elements and re-entry heating"
	]:
		var item := Label.new()
		item.text = "•  " + line
		item.modulate = Color(0.72, 0.78, 0.86)
		item.add_theme_font_size_override("font_size", 14)
		box.add_child(item)

	var version := Label.new()
	version.text = "PRE-ALPHA 0.1.0"
	version.position = Vector2(76, 760)
	version.modulate = Color(0.40, 0.47, 0.56)
	version.add_theme_font_size_override("font_size", 12)
	root.add_child(version)

	return root

func _build_builder_ui() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(root)

	var top := ColorRect.new()
	top.color = Color(0.010, 0.016, 0.026, 0.94)
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 0.0
	top.offset_top = 0.0
	top.offset_right = 0.0
	top.offset_bottom = 76.0
	root.add_child(top)

	var title := Label.new()
	title.text = "APOAPSIS  /  VEHICLE ASSEMBLY"
	title.position = Vector2(32, 22)
	title.add_theme_font_size_override("font_size", 24)
	title.modulate = COLOR_TEXT
	top.add_child(title)

	var hint := Label.new()
	hint.text = "RIGHT DRAG ROTATE   WHEEL ZOOM   ESC MENU"
	hint.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hint.position = Vector2(-430, 28)
	hint.size = Vector2(395, 28)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.modulate = COLOR_MUTED
	hint.add_theme_font_size_override("font_size", 12)
	top.add_child(hint)

	var left := PanelContainer.new()
	left.position = Vector2(24, 96)
	left.size = Vector2(355, 870)
	left.add_theme_stylebox_override("panel", _panel_style(COLOR_PANEL, 14.0))
	root.add_child(left)

	var left_margin := MarginContainer.new()
	left_margin.add_theme_constant_override("margin_left", 18)
	left_margin.add_theme_constant_override("margin_right", 18)
	left_margin.add_theme_constant_override("margin_top", 18)
	left_margin.add_theme_constant_override("margin_bottom", 18)
	left.add_child(left_margin)

	var palette := VBoxContainer.new()
	palette.add_theme_constant_override("separation", 9)
	left_margin.add_child(palette)

	var parts_title := Label.new()
	parts_title.text = "PART CATALOG"
	parts_title.modulate = COLOR_MUTED
	parts_title.add_theme_font_size_override("font_size", 13)
	palette.add_child(parts_title)

	for part_id: String in ["capsule", "heatshield", "nose_cone", "tank_small", "tank_medium", "tank_large", "engine_aquila", "engine_orion", "decoupler", "fin"]:
		var part := PartCatalog.get_part(part_id)
		var button := _make_part_button(part_id, part)
		palette.add_child(button)

	var right := PanelContainer.new()
	right.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	right.offset_left = -390.0
	right.offset_top = 96.0
	right.offset_right = -24.0
	right.offset_bottom = -24.0
	right.add_theme_stylebox_override("panel", _panel_style(COLOR_PANEL, 14.0))
	root.add_child(right)

	var right_margin := MarginContainer.new()
	right_margin.add_theme_constant_override("margin_left", 18)
	right_margin.add_theme_constant_override("margin_right", 18)
	right_margin.add_theme_constant_override("margin_top", 18)
	right_margin.add_theme_constant_override("margin_bottom", 18)
	right.add_child(right_margin)

	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 10)
	right_margin.add_child(side)

	var stack_title := Label.new()
	stack_title.text = "VEHICLE STACK"
	stack_title.modulate = COLOR_MUTED
	stack_title.add_theme_font_size_override("font_size", 13)
	side.add_child(stack_title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 390
	side.add_child(scroll)

	stack_list = VBoxContainer.new()
	stack_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack_list.add_theme_constant_override("separation", 6)
	scroll.add_child(stack_list)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	side.add_child(action_row)

	var default_button := _make_button("DEFAULT", false)
	default_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	default_button.pressed.connect(_load_default_stack)
	action_row.add_child(default_button)

	var clear_button := _make_button("CLEAR", false)
	clear_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clear_button.pressed.connect(_clear_stack)
	action_row.add_child(clear_button)

	var stats_sep := HSeparator.new()
	side.add_child(stats_sep)

	var stats_title := Label.new()
	stats_title.text = "FLIGHT ESTIMATE"
	stats_title.modulate = COLOR_MUTED
	stats_title.add_theme_font_size_override("font_size", 13)
	side.add_child(stats_title)

	builder_mass = _stat_line(side, "WET MASS")
	builder_twr = _stat_line(side, "SEA LEVEL TWR")
	builder_dv = _stat_line(side, "IDEAL ΔV")
	builder_stage_count = _stat_line(side, "STAGES")

	builder_status = Label.new()
	builder_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	builder_status.custom_minimum_size.y = 42
	builder_status.add_theme_font_size_override("font_size", 14)
	side.add_child(builder_status)

	launch_button = _make_button("ROLL OUT TO PAD", true)
	launch_button.custom_minimum_size.y = 58
	launch_button.pressed.connect(_launch)
	side.add_child(launch_button)

	return root

func _build_flight_ui() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(root)

	var top := PanelContainer.new()
	top.position = Vector2(24, 22)
	top.size = Vector2(820, 94)
	top.add_theme_stylebox_override("panel", _panel_style(Color(0.010, 0.016, 0.026, 0.88), 12.0))
	root.add_child(top)

	var top_margin := MarginContainer.new()
	top_margin.add_theme_constant_override("margin_left", 18)
	top_margin.add_theme_constant_override("margin_right", 18)
	top_margin.add_theme_constant_override("margin_top", 12)
	top_margin.add_theme_constant_override("margin_bottom", 12)
	top.add_child(top_margin)

	var top_box := VBoxContainer.new()
	top_margin.add_child(top_box)

	var title := Label.new()
	title.text = "APOAPSIS  /  FLIGHT"
	title.add_theme_font_size_override("font_size", 22)
	top_box.add_child(title)

	flight_event = Label.new()
	flight_event.text = "PAD READY"
	flight_event.modulate = COLOR_MUTED
	flight_event.add_theme_font_size_override("font_size", 13)
	top_box.add_child(flight_event)

	var bottom := PanelContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 24.0
	bottom.offset_top = -188.0
	bottom.offset_right = -24.0
	bottom.offset_bottom = -24.0
	bottom.add_theme_stylebox_override("panel", _panel_style(Color(0.010, 0.016, 0.026, 0.91), 12.0))
	root.add_child(bottom)

	var bottom_margin := MarginContainer.new()
	bottom_margin.add_theme_constant_override("margin_left", 18)
	bottom_margin.add_theme_constant_override("margin_right", 18)
	bottom_margin.add_theme_constant_override("margin_top", 14)
	bottom_margin.add_theme_constant_override("margin_bottom", 12)
	bottom.add_child(bottom_margin)

	var bottom_box := VBoxContainer.new()
	bottom_box.add_theme_constant_override("separation", 8)
	bottom_margin.add_child(bottom_box)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	bottom_box.add_child(row)

	for key: String in ["ALTITUDE", "SPEED", "VERTICAL", "MACH", "MAX Q", "THROTTLE", "MASS", "FUEL", "APOAPSIS", "PERIAPSIS"]:
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cap := Label.new()
		cap.text = key
		cap.modulate = COLOR_MUTED
		cap.add_theme_font_size_override("font_size", 10)
		cell.add_child(cap)
		var value := Label.new()
		value.text = "-"
		value.add_theme_font_size_override("font_size", 18)
		cell.add_child(value)
		flight_values[key] = value
		row.add_child(cell)

	var lower := HBoxContainer.new()
	lower.add_theme_constant_override("separation", 22)
	bottom_box.add_child(lower)

	var controls := Label.new()
	controls.text = "W/S THROTTLE   A/D PITCH   Q/E YAW   Z/C ROLL   SPACE STAGE   X CUTOFF   M MAP   RMB CAMERA   WHEEL ZOOM"
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.modulate = COLOR_MUTED
	controls.add_theme_font_size_override("font_size", 11)
	lower.add_child(controls)

	flight_warp = Label.new()
	flight_warp.text = "WARP 1×"
	flight_warp.modulate = COLOR_ACCENT
	flight_warp.add_theme_font_size_override("font_size", 12)
	lower.add_child(flight_warp)

	return root

func _build_map_ui() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(root)

	var panel := PanelContainer.new()
	panel.position = Vector2(30, 28)
	panel.size = Vector2(400, 500)
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.010, 0.016, 0.026, 0.94), 14.0))
	root.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 13)
	margin.add_child(box)

	var title := Label.new()
	title.text = "ORBITAL MAP"
	title.add_theme_font_size_override("font_size", 26)
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "EARTH REFERENCE FRAME"
	subtitle.modulate = COLOR_MUTED
	subtitle.add_theme_font_size_override("font_size", 12)
	box.add_child(subtitle)

	var sep := HSeparator.new()
	box.add_child(sep)

	for key: String in ["APOAPSIS", "PERIAPSIS", "ECCENTRICITY", "INCLINATION", "PERIOD", "VELOCITY", "ALTITUDE"]:
		var row := HBoxContainer.new()
		var cap := Label.new()
		cap.text = key
		cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cap.modulate = COLOR_MUTED
		cap.add_theme_font_size_override("font_size", 12)
		row.add_child(cap)
		var val := Label.new()
		val.text = "-"
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val.add_theme_font_size_override("font_size", 17)
		row.add_child(val)
		map_values[key] = val
		box.add_child(row)

	var hint := Label.new()
	hint.text = "M RETURN TO FLIGHT   RMB CAMERA   WHEEL ZOOM"
	hint.position = Vector2(34, 990)
	hint.modulate = COLOR_MUTED
	hint.add_theme_font_size_override("font_size", 11)
	root.add_child(hint)

	return root

func _make_part_button(part_id: String, part: Dictionary) -> Button:
	var button := _make_button(str(part.get("name", part_id)), false)
	button.custom_minimum_size.y = 54
	var mass := float(part.get("dry_mass", 0.0))
	var fuel := float(part.get("fuel", 0.0))
	if fuel > 0.0:
		button.tooltip_text = "Dry %s  |  Propellant %s" % [_format_mass(mass), _format_mass(fuel)]
	else:
		button.tooltip_text = "Dry %s" % _format_mass(mass)
	button.pressed.connect(_add_part.bind(part_id))
	return button

func _stat_line(parent: VBoxContainer, caption_text: String) -> Label:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var cap := Label.new()
	cap.text = caption_text
	cap.modulate = COLOR_MUTED
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cap.add_theme_font_size_override("font_size", 12)
	row.add_child(cap)
	var value := Label.new()
	value.text = "-"
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.add_theme_font_size_override("font_size", 18)
	row.add_child(value)
	return value

func _make_button(text_value: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = text_value
	button.add_theme_font_size_override("font_size", 14)
	var normal_color := COLOR_ACCENT if primary else COLOR_PANEL_2
	var hover_color := Color(0.15, 0.66, 1.0) if primary else Color(0.065, 0.085, 0.12)
	button.add_theme_stylebox_override("normal", _button_style(normal_color, 8.0))
	button.add_theme_stylebox_override("hover", _button_style(hover_color, 8.0))
	button.add_theme_stylebox_override("pressed", _button_style(normal_color.darkened(0.18), 8.0))
	button.add_theme_stylebox_override("disabled", _button_style(Color(0.06, 0.07, 0.08), 8.0))
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color(0.35, 0.38, 0.42))
	return button

func _panel_style(color: Color, radius: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = int(radius)
	style.corner_radius_top_right = int(radius)
	style.corner_radius_bottom_left = int(radius)
	style.corner_radius_bottom_right = int(radius)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = COLOR_LINE
	return style

func _button_style(color: Color, radius: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = int(radius)
	style.corner_radius_top_right = int(radius)
	style.corner_radius_bottom_left = int(radius)
	style.corner_radius_bottom_right = int(radius)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

func _show_menu() -> void:
	mode = GameMode.MENU
	menu_ui.visible = true
	builder_ui.visible = false
	flight_ui.visible = false
	map_ui.visible = false
	map_root.visible = false
	launch_site.visible = true
	builder_floor.visible = false
	_set_warp(1.0)
	_build_preview_vehicle()
	camera_yaw = deg_to_rad(38.0)
	camera_pitch = deg_to_rad(-14.0)
	camera_distance = 62.0
	camera.near = 0.20
	camera.far = 2500.0

func _show_builder() -> void:
	mode = GameMode.BUILDER
	menu_ui.visible = false
	builder_ui.visible = true
	flight_ui.visible = false
	map_ui.visible = false
	map_root.visible = false
	launch_site.visible = false
	builder_floor.visible = true
	_set_warp(1.0)
	_refresh_builder()
	camera_yaw = deg_to_rad(38.0)
	camera_pitch = deg_to_rad(-12.0)
	camera_distance = 42.0
	camera.near = 0.20
	camera.far = 2500.0

func _quick_launch() -> void:
	part_stack = PartCatalog.default_stack()
	_launch()

func _load_default_stack() -> void:
	part_stack = PartCatalog.default_stack()
	_refresh_builder()

func _clear_stack() -> void:
	part_stack.clear()
	_refresh_builder()

func _add_part(part_id: String) -> void:
	part_stack.append(part_id)
	_refresh_builder()

func _remove_part(index: int) -> void:
	if index >= 0 and index < part_stack.size():
		part_stack.remove_at(index)
	_refresh_builder()

func _refresh_builder() -> void:
	vehicle.configure(part_stack)
	for child: Node in stack_list.get_children():
		child.queue_free()

	for reverse_index: int in range(part_stack.size() - 1, -1, -1):
		var part_id: String = part_stack[reverse_index]
		var data := PartCatalog.get_part(part_id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		stack_list.add_child(row)

		var label := Label.new()
		label.text = "%02d   %s" % [reverse_index + 1, str(data.get("name", part_id))]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 13)
		row.add_child(label)

		var remove := Button.new()
		remove.text = "×"
		remove.custom_minimum_size = Vector2(34, 30)
		remove.pressed.connect(_remove_part.bind(reverse_index))
		row.add_child(remove)

	builder_mass.text = _format_mass(vehicle.total_mass())
	builder_twr.text = "%0.2f" % vehicle.current_twr(101325.0)
	builder_dv.text = "%0.0f m/s" % vehicle.estimated_delta_v()
	builder_stage_count.text = str(vehicle.stage_count())
	builder_status.text = vehicle.validation_message()
	builder_status.modulate = COLOR_GOOD if vehicle.is_valid_vehicle() else COLOR_WARN
	launch_button.disabled = not vehicle.is_valid_vehicle()

	_build_preview_vehicle()

func _build_preview_vehicle() -> void:
	if rocket_visual != null:
		rocket_visual.queue_free()
	rocket_visual = RocketFactory.build(part_stack)
	world_root.add_child(rocket_visual)
	rocket_visual.position = Vector3(0.0, 0.82, 0.0)
	rocket_visual.rotation = Vector3.ZERO
	plume_visual = null

func _launch() -> void:
	vehicle.configure(part_stack)
	if not vehicle.is_valid_vehicle():
		if mode != GameMode.BUILDER:
			_show_builder()
		return

	_initialize_simulation()
	_rebuild_flight_vehicle()

	mode = GameMode.FLIGHT
	menu_ui.visible = false
	builder_ui.visible = false
	flight_ui.visible = true
	map_ui.visible = false
	map_root.visible = false
	launch_site.visible = true
	builder_floor.visible = false
	camera_yaw = deg_to_rad(42.0)
	camera_pitch = deg_to_rad(-16.0)
	camera_distance = 54.0
	camera.near = 0.20
	camera.far = 12000.0
	camera.near = 0.20
	camera.far = 12000.0
	last_event = "PAD READY  |  SPACE IGNITION"
	_update_environment_for_altitude(0.0)

func _initialize_simulation() -> void:
	var lat: float = deg_to_rad(LAUNCH_LATITUDE_DEG)
	var lon: float = deg_to_rad(LAUNCH_LONGITUDE_DEG)
	launch_position_ecef = DVec3.new(
		EARTH_RADIUS * cos(lat) * cos(lon),
		EARTH_RADIUS * sin(lat),
		EARTH_RADIUS * cos(lat) * sin(lon)
	)
	launch_up_ecef = launch_position_ecef.normalized()
	var world_axis: DVec3 = DVec3.new(0.0, 1.0, 0.0)
	launch_east_ecef = world_axis.cross(launch_up_ecef).normalized()
	launch_north_ecef = launch_up_ecef.cross(launch_east_ecef).normalized()

	sim_position = launch_position_ecef.duplicate_value()
	var omega: DVec3 = DVec3.new(0.0, EARTH_ROTATION_RATE, 0.0)
	sim_velocity = omega.cross(sim_position)
	attitude = Quaternion.IDENTITY
	angular_rate = Vector3.ZERO
	physics_accumulator = 0.0
	mission_time = 0.0
	max_q = 0.0
	heat_flux_w_m2 = 0.0
	g_load = 1.0
	has_liftoff = false
	landed = false
	crashed = false
	warp_factor = 1.0
	vehicle.set_throttle(0.0)
	vehicle.engines_armed = false
	last_stage_visual = -1

func _rebuild_flight_vehicle() -> void:
	var old_position := Vector3.ZERO
	var old_basis := Basis.IDENTITY
	if rocket_visual != null:
		old_position = rocket_visual.position
		old_basis = rocket_visual.basis
		rocket_visual.queue_free()

	rocket_visual = RocketFactory.build(part_stack, vehicle.current_stage)
	world_root.add_child(rocket_visual)
	rocket_visual.position = old_position
	rocket_visual.basis = old_basis

	plume_visual = RocketFactory.make_plume(max(0.45, vehicle.current_radius() * 0.62))
	rocket_visual.add_child(plume_visual)
	plume_visual.visible = false
	last_stage_visual = vehicle.current_stage

func _update_menu_camera(delta: float) -> void:
	if rocket_visual == null:
		return
	builder_spin += delta * 0.10
	var h := RocketFactory.vehicle_height(part_stack)
	var target := Vector3(0.0, h * 0.46 + 0.8, 0.0)
	var orbit_yaw := camera_yaw + builder_spin
	var offset := _orbit_offset(orbit_yaw, camera_pitch, camera_distance)
	camera.position = camera.position.lerp(target + offset, clamp(delta * 2.8, 0.0, 1.0))
	camera.look_at(target, Vector3.UP)

func _update_builder_camera(delta: float) -> void:
	if rocket_visual == null:
		return
	var h := RocketFactory.vehicle_height(part_stack)
	var target := Vector3(0.0, h * 0.46 + 0.8, 0.0)
	var offset := _orbit_offset(camera_yaw, camera_pitch, camera_distance)
	camera.position = camera.position.lerp(target + offset, clamp(delta * 4.0, 0.0, 1.0))
	camera.look_at(target, Vector3.UP)

func _update_flight(delta: float) -> void:
	_handle_flight_controls(delta)

	var effective_warp := warp_factor
	if vehicle.engines_armed or _current_altitude() < 70000.0:
		effective_warp = 1.0
		if warp_factor != 1.0:
			warp_factor = 1.0

	physics_accumulator += min(delta, 0.10) * effective_warp
	var max_steps: int = 2400
	var steps: int = 0
	while physics_accumulator >= PHYSICS_STEP and steps < max_steps:
		_simulate_step(PHYSICS_STEP)
		physics_accumulator -= PHYSICS_STEP
		steps += 1

	if vehicle.current_stage != last_stage_visual:
		_rebuild_flight_vehicle()

	_update_flight_visuals(delta)
	_update_flight_hud()

func _handle_flight_controls(delta: float) -> void:
	var throttle_step := 0.45 * delta
	if Input.is_action_pressed("throttle_up"):
		vehicle.set_throttle(vehicle.throttle + throttle_step)
	if Input.is_action_pressed("throttle_down"):
		vehicle.set_throttle(vehicle.throttle - throttle_step)

	if Input.is_action_just_pressed("stage"):
		last_event = vehicle.activate_or_stage()
		_set_warp(1.0)
	if Input.is_action_just_pressed("shutdown"):
		vehicle.shutdown()
		last_event = "ENGINE CUTOFF"
	if Input.is_action_just_pressed("map_view"):
		_enter_map()
		return
	if Input.is_action_just_pressed("reset_flight"):
		_show_builder()
		return

	var pitch_input := Input.get_axis("pitch_left", "pitch_right")
	var yaw_input := Input.get_axis("yaw_left", "yaw_right")
	var roll_input := Input.get_axis("roll_left", "roll_right")
	var target_rate := Vector3(pitch_input, yaw_input, roll_input) * 0.24
	angular_rate = angular_rate.lerp(target_rate, clamp(delta * 4.0, 0.0, 1.0))

func _simulate_step(dt: float) -> void:
	if crashed or landed:
		return

	mission_time += dt
	var altitude: float = _current_altitude()
	var atmosphere: Dictionary = Atmosphere1976.sample(altitude)
	var pressure: float = float(atmosphere["pressure"])
	var density: float = float(atmosphere["density"])
	var speed_of_sound: float = maxf(float(atmosphere["speed_of_sound"]), 1.0)

	var omega: DVec3 = DVec3.new(0.0, EARTH_ROTATION_RATE, 0.0)
	var atmosphere_velocity: DVec3 = omega.cross(sim_position)
	var relative_air_velocity: DVec3 = sim_velocity.sub(atmosphere_velocity)
	var airspeed: float = relative_air_velocity.length()

	var mass: float = vehicle.total_mass()
	var gravity: DVec3 = OrbitMath.gravity_acceleration(sim_position)
	var total_force: DVec3 = gravity.scaled(mass)

	var engine_data: Dictionary = vehicle.consume_and_get_thrust(dt, pressure)
	var thrust: float = float(engine_data["thrust"])

	var radial_up_d: DVec3 = sim_position.normalized()
	var radial_up: Vector3 = radial_up_d.to_vector3()
	var east: Vector3 = Vector3.UP.cross(radial_up).normalized()
	if east.length_squared() < 0.01:
		east = launch_east_ecef.to_vector3()
	var north: Vector3 = radial_up.cross(east).normalized()

	var pitch_q: Quaternion = Quaternion(east, angular_rate.x * dt)
	var yaw_q: Quaternion = Quaternion(north, angular_rate.y * dt)
	var roll_q: Quaternion = Quaternion(radial_up, angular_rate.z * dt)
	attitude = (roll_q * yaw_q * pitch_q * attitude).normalized()

	var thrust_direction: Vector3 = (attitude * radial_up).normalized()
	if thrust > 0.0:
		total_force = total_force.add(DVec3.from_vector3(thrust_direction).scaled(thrust))
		if thrust > mass * gravity.length() * 1.01:
			has_liftoff = true

	if airspeed > 0.01 and density > 0.0000001:
		var mach: float = airspeed / speed_of_sound
		var cd: float = Aerodynamics.drag_coefficient(mach, 0.26)
		var q_dynamic: float = Aerodynamics.dynamic_pressure(density, airspeed)
		var drag: float = q_dynamic * cd * vehicle.reference_area()
		total_force = total_force.sub(relative_air_velocity.normalized().scaled(drag))
		max_q = max(max_q, q_dynamic)
		heat_flux_w_m2 = Aerodynamics.convective_heating_w_m2(density, airspeed, 0.75)
	else:
		heat_flux_w_m2 = 0.0

	var acceleration: DVec3 = total_force.divided(mass)
	g_load = max(0.0, acceleration.sub(gravity).length() / 9.80665)
	sim_velocity = sim_velocity.add(acceleration.scaled(dt))
	sim_position = sim_position.add(sim_velocity.scaled(dt))

	var current_radius: float = sim_position.length()
	if current_radius < EARTH_RADIUS:
		sim_position = sim_position.normalized().scaled(EARTH_RADIUS)
		var surface_velocity: DVec3 = omega.cross(sim_position)
		var impact_velocity: DVec3 = sim_velocity.sub(surface_velocity)
		var impact_speed: float = impact_velocity.length()

		if has_liftoff:
			if impact_speed <= 8.0:
				landed = true
				last_event = "TOUCHDOWN  %0.1f m/s" % impact_speed
			else:
				crashed = true
				last_event = "VEHICLE LOST  %0.1f m/s" % impact_speed
			vehicle.shutdown()

		sim_velocity = surface_velocity

func _update_flight_visuals(delta: float) -> void:
	if rocket_visual == null:
		return

	var local_pos: Vector3 = _inertial_position_to_launch_local(sim_position)
	# Floating origin: keep the active vehicle near world origin at all times.
	# Nearby world geometry moves relative to the vehicle instead of accumulating
	# large single-precision render coordinates.
	rocket_visual.position = Vector3(0.0, 2.9, 0.0)
	launch_site.position = -local_pos

	var current_up: Vector3 = sim_position.normalized().to_vector3()
	var physics_longitudinal: Vector3 = (attitude * current_up).normalized()
	var physics_right: Vector3 = (attitude * launch_east_ecef.to_vector3()).normalized()

	var local_y: Vector3 = _inertial_direction_to_launch_local(physics_longitudinal).normalized()
	var local_x: Vector3 = _inertial_direction_to_launch_local(physics_right).normalized()
	local_x = (local_x - local_y * local_x.dot(local_y)).normalized()
	if local_x.length_squared() < 0.01:
		local_x = Vector3.RIGHT
	var local_z: Vector3 = local_x.cross(local_y).normalized()
	local_x = local_y.cross(local_z).normalized()
	rocket_visual.basis = Basis(local_x, local_y, local_z)

	if plume_visual != null:
		plume_visual.visible = vehicle.engines_armed and vehicle.throttle > 0.0 and vehicle.current_fuel() > 0.0
		if plume_visual.visible:
			plume_visual.scale = Vector3(1.0 + vehicle.throttle * 0.10, 0.55 + vehicle.throttle * 1.35, 1.0 + vehicle.throttle * 0.10)

	var vehicle_height: float = RocketFactory.vehicle_height(part_stack, vehicle.current_stage)
	var target: Vector3 = rocket_visual.position + local_y * vehicle_height * 0.42
	var omega: DVec3 = DVec3.new(0.0, EARTH_ROTATION_RATE, 0.0)
	var speed: float = sim_velocity.sub(omega.cross(sim_position)).length()
	var dynamic_distance: float = clampf(camera_distance + speed * 0.002, 18.0, 220.0)
	var offset: Vector3 = _orbit_offset(camera_yaw, camera_pitch, dynamic_distance)
	var desired: Vector3 = target + offset
	camera.position = camera.position.lerp(desired, clamp(delta * 4.0, 0.0, 1.0))
	camera.look_at(target, Vector3.UP)

	var altitude: float = _current_altitude()
	launch_site.visible = altitude < 50000.0
	_update_environment_for_altitude(altitude)

func _update_flight_hud() -> void:
	var altitude: float = _current_altitude()
	var radial_speed: float = sim_velocity.dot(sim_position.normalized())
	var atmosphere: Dictionary = Atmosphere1976.sample(altitude)
	var omega: DVec3 = DVec3.new(0.0, EARTH_ROTATION_RATE, 0.0)
	var air_velocity: DVec3 = sim_velocity.sub(omega.cross(sim_position))
	var airspeed: float = air_velocity.length()
	var mach: float = airspeed / maxf(float(atmosphere["speed_of_sound"]), 1.0)
	var orbit: Dictionary = OrbitMath.elements(sim_position, sim_velocity)

	_set_flight_value("ALTITUDE", _format_distance(altitude))
	_set_flight_value("SPEED", "%0.0f m/s" % airspeed)
	_set_flight_value("VERTICAL", "%+0.0f m/s" % radial_speed)
	_set_flight_value("MACH", "%0.2f" % mach)
	_set_flight_value("MAX Q", "%0.1f kPa" % (max_q / 1000.0))
	_set_flight_value("THROTTLE", "%0.0f%%" % (vehicle.throttle * 100.0))
	_set_flight_value("MASS", _format_mass(vehicle.total_mass()))
	_set_flight_value("FUEL", _format_mass(vehicle.current_fuel()))
	_set_flight_value("APOAPSIS", _format_distance(float(orbit["apoapsis_m"])))
	_set_flight_value("PERIAPSIS", _format_distance(float(orbit["periapsis_m"])))

	var status_color: Color = COLOR_DANGER if crashed else (COLOR_GOOD if landed else COLOR_TEXT)
	flight_event.modulate = status_color
	flight_event.text = "%s   |   STAGE %d/%d   |   T+ %s   |   %0.2f g   |   HEAT %0.2f MW/m²" % [
		last_event,
		vehicle.current_stage + 1,
		vehicle.stage_count(),
		_format_time(mission_time),
		g_load,
		heat_flux_w_m2 / 1000000.0
	]
	flight_warp.text = "WARP %.0f×  [1-4]" % warp_factor

func _enter_map() -> void:
	mode = GameMode.MAP
	flight_ui.visible = false
	map_ui.visible = true
	map_root.visible = true
	launch_site.visible = false
	if rocket_visual != null:
		rocket_visual.visible = false
	camera_distance = 62.0
	camera_yaw = deg_to_rad(38.0)
	camera_pitch = deg_to_rad(-22.0)
	camera.near = 0.20
	camera.far = 500.0
	map_refresh_timer = 0.0
	_rebuild_orbit_trajectory()
	_update_map_values()

func _exit_map() -> void:
	mode = GameMode.FLIGHT
	flight_ui.visible = true
	map_ui.visible = false
	map_root.visible = false
	if rocket_visual != null:
		rocket_visual.visible = true
	camera_distance = 54.0

func _update_map(delta: float) -> void:
	if Input.is_action_just_pressed("map_view"):
		_exit_map()
		return

	if not vehicle.engines_armed and _current_altitude() >= 70000.0 and warp_factor > 1.0:
		physics_accumulator += min(delta, 0.10) * warp_factor
		var steps: int = 0
		while physics_accumulator >= PHYSICS_STEP and steps < 2400:
			_simulate_step(PHYSICS_STEP)
			physics_accumulator -= PHYSICS_STEP
			steps += 1

		map_refresh_timer += delta
		if map_refresh_timer >= 0.25:
			map_refresh_timer = 0.0
			_rebuild_orbit_trajectory()

	var target := Vector3.ZERO
	var offset := _orbit_offset(camera_yaw, camera_pitch, camera_distance)
	camera.position = target + offset
	camera.look_at(target, Vector3.UP)
	_update_map_values()

func _update_map_values() -> void:
	var orbit: Dictionary = OrbitMath.elements(sim_position, sim_velocity)
	_set_map_value("APOAPSIS", _format_distance(float(orbit["apoapsis_m"])))
	_set_map_value("PERIAPSIS", _format_distance(float(orbit["periapsis_m"])))
	_set_map_value("ECCENTRICITY", "%0.5f" % float(orbit["eccentricity"]))
	_set_map_value("INCLINATION", "%0.2f°" % float(orbit["inclination_deg"]))
	_set_map_value("PERIOD", _format_time(float(orbit["period_s"])) if is_finite(float(orbit["period_s"])) else "ESCAPE")
	_set_map_value("VELOCITY", "%0.0f m/s" % sim_velocity.length())
	_set_map_value("ALTITUDE", _format_distance(_current_altitude()))

	var scale: float = 18.0 / EARTH_RADIUS
	map_vehicle_marker.position = sim_position.scaled(scale).to_vector3()

func _rebuild_orbit_trajectory() -> void:
	var orbit: Dictionary = OrbitMath.elements(sim_position, sim_velocity)
	if not bool(orbit["valid"]) or not is_finite(float(orbit["period_s"])) or float(orbit["period_s"]) <= 0.0:
		map_trajectory.mesh = null
		return

	var period: float = float(orbit["period_s"])
	var points: int = 360
	var step: float = period / float(points)
	var pos: DVec3 = sim_position.duplicate_value()
	var vel: DVec3 = sim_velocity.duplicate_value()
	var scale: float = 18.0 / EARTH_RADIUS

	var immediate := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	immediate.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, material)

	for i: int in range(points + 1):
		var fade := 0.45 + 0.55 * (float(i) / float(points))
		immediate.surface_set_color(Color(COLOR_ACCENT.r, COLOR_ACCENT.g, COLOR_ACCENT.b, fade))
		immediate.surface_add_vertex(pos.scaled(scale).to_vector3())

		var a0: DVec3 = OrbitMath.gravity_acceleration(pos)
		vel = vel.add(a0.scaled(step))
		pos = pos.add(vel.scaled(step))

	immediate.surface_end()
	map_trajectory.mesh = immediate

func _set_warp(value: float) -> void:
	if mode == GameMode.FLIGHT and (vehicle.engines_armed or _current_altitude() < 70000.0) and value > 1.0:
		last_event = "TIME WARP LOCKED BELOW 70 km / UNDER THRUST"
		warp_factor = 1.0
	else:
		warp_factor = value
	if flight_warp != null:
		flight_warp.text = "WARP %.0f×  [1-4]" % warp_factor

func _current_altitude() -> float:
	return max(0.0, sim_position.length() - EARTH_RADIUS)

func _inertial_position_to_launch_local(position_inertial: DVec3) -> Vector3:
	var earth_fixed: DVec3 = _rotate_y_d(position_inertial, -EARTH_ROTATION_RATE * mission_time)
	var delta: DVec3 = earth_fixed.sub(launch_position_ecef)
	return Vector3(
		float(delta.dot(launch_east_ecef)),
		float(delta.dot(launch_up_ecef)),
		float(-delta.dot(launch_north_ecef))
	)

func _inertial_direction_to_launch_local(direction_inertial: Vector3) -> Vector3:
	var direction_d: DVec3 = DVec3.from_vector3(direction_inertial)
	direction_d = _rotate_y_d(direction_d, -EARTH_ROTATION_RATE * mission_time)
	return Vector3(
		float(direction_d.dot(launch_east_ecef)),
		float(direction_d.dot(launch_up_ecef)),
		float(-direction_d.dot(launch_north_ecef))
	)

func _rotate_y_d(value: DVec3, angle: float) -> DVec3:
	var c: float = cos(angle)
	var si: float = sin(angle)
	return DVec3.new(
		value.x * c + value.z * si,
		value.y,
		-value.x * si + value.z * c
	)

func _orbit_offset(yaw: float, pitch: float, distance: float) -> Vector3:
	var cp: float = cos(pitch)
	return Vector3(
		sin(yaw) * cp,
		-sin(pitch),
		cos(yaw) * cp
	) * distance

func _update_environment_for_altitude(altitude: float) -> void:
	var space_mix: float = clampf((altitude - 18000.0) / 90000.0, 0.0, 1.0)
	sky_material.sky_top_color = Color(0.025, 0.12, 0.28).lerp(Color(0.001, 0.002, 0.008), space_mix)
	sky_material.sky_horizon_color = Color(0.42, 0.63, 0.82).lerp(Color(0.012, 0.025, 0.055), space_mix)
	sky_material.ground_horizon_color = Color(0.30, 0.34, 0.36).lerp(Color(0.005, 0.008, 0.015), space_mix)
	environment.ambient_light_energy = lerp(0.65, 0.18, space_mix)

func _set_flight_value(key: String, value: String) -> void:
	var label := flight_values[key] as Label
	label.text = value

func _set_map_value(key: String, value: String) -> void:
	var label := map_values[key] as Label
	label.text = value

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
	var total := int(seconds)
	var hours := total / 3600
	var minutes := (total % 3600) / 60
	var secs := total % 60
	if hours > 0:
		return "%02d:%02d:%02d" % [hours, minutes, secs]
	return "%02d:%02d" % [minutes, secs]
