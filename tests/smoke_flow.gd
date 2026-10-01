extends SceneTree

var game: Node

func _initialize() -> void:
	call_deferred("_run")

func _fail(message: String) -> void:
	push_error("APOAPSIS FLOW TEST FAILED: " + message)
	quit(1)

func _run() -> void:
	var packed: PackedScene = load("res://main.tscn") as PackedScene
	if packed == null:
		_fail("main.tscn could not be loaded")
		return

	game = packed.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame

	if game.menu_ui == null or not game.menu_ui.visible:
		_fail("main menu did not initialize")
		return

	game._show_builder()
	await process_frame

	if game.builder_ui == null or not game.builder_ui.visible:
		_fail("builder did not open")
		return
	if game.rocket_visual == null:
		_fail("builder rocket preview is missing")
		return
	if not game.vehicle.is_valid_vehicle():
		_fail("default vehicle is not flight ready: " + game.vehicle.validation_message())
		return
	if game.vehicle.current_twr(101325.0) <= 1.0:
		_fail("default vehicle cannot lift off")
		return
	if game.vehicle.estimated_delta_v() < 5000.0:
		_fail("default vehicle has implausibly low delta-v")
		return

	game._launch()
	await process_frame
	await process_frame

	if game.rocket_visual == null:
		_fail("flight rocket visual is missing")
		return
	if not game.flight_ui.visible:
		_fail("flight HUD is not visible")
		return

	game.vehicle.set_throttle(1.0)
	var ignition_message: String = game.vehicle.activate_or_stage()
	if "IGNITION" not in ignition_message:
		_fail("first stage failed to ignite")
		return

	var initial_altitude: float = game._current_altitude()
	for i: int in range(360):
		game._simulate_step(1.0 / 120.0)

	var altitude_after_burn: float = game._current_altitude()
	if altitude_after_burn <= initial_altitude:
		_fail("vehicle did not gain altitude under thrust")
		return
	if game.vehicle.current_fuel() >= game.vehicle.current_fuel_capacity():
		_fail("engine burn did not consume propellant")
		return

	var stage_before: int = game.vehicle.current_stage
	var stage_message: String = game.vehicle.activate_or_stage()
	if game.vehicle.has_next_stage() and game.vehicle.current_stage == stage_before:
		_fail("stage separation did not advance the stage")
		return
	if stage_message.is_empty():
		_fail("stage event produced no status")
		return

	game._rebuild_flight_vehicle()
	if game.rocket_visual == null:
		_fail("vehicle visual disappeared after staging")
		return

	game._enter_map()
	await process_frame
	if not game.map_root.visible:
		_fail("orbital map did not become visible")
		return
	if game.map_vehicle_marker == null:
		_fail("map vehicle marker is missing")
		return

	print("APOAPSIS FLOW TEST PASSED")
	quit(0)
