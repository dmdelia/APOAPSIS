extends SceneTree

var game: Node

func _initialize() -> void:
	call_deferred("_run")

func _fail(message: String) -> void:
	push_error("APOAPSIS RENDER TEST FAILED: " + message)
	quit(1)

func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("viewport capture failed for " + name)
		return
	var err: Error = image.save_png("res://test-output/" + name + ".png")
	if err != OK:
		_fail("could not save " + name)
		return

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test-output"))
	root.size = Vector2i(1280, 720)

	var packed: PackedScene = load("res://main.tscn") as PackedScene
	if packed == null:
		_fail("main.tscn could not be loaded")
		return

	game = packed.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	await process_frame

	game._show_builder()
	await process_frame
	await process_frame
	await _capture("builder")

	game._launch()
	await process_frame
	await process_frame
	game._update_flight_visuals(0.016)
	await process_frame
	await _capture("flight_pad")

	game._enter_map()
	await process_frame
	await process_frame
	game._update_map(0.016)
	await process_frame
	await _capture("map")

	print("APOAPSIS RENDER CAPTURE PASSED")
	quit(0)
