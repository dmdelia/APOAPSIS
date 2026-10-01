extends SceneTree

var game: Node

func _initialize() -> void:
	call_deferred("_run")

func _fail(message: String) -> void:
	push_error("APOAPSIS RENDER TEST FAILED: " + message)
	quit(1)

func _capture(name: String) -> Image:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("viewport capture failed for " + name)
		return null
	var err: Error = image.save_png("res://test-output/" + name + ".png")
	if err != OK:
		_fail("could not save " + name)
		return null
	return image

func _count_bright_pixels(image: Image, rect: Rect2i) -> int:
	var count: int = 0
	for y: int in range(rect.position.y, rect.end.y, 2):
		for x: int in range(rect.position.x, rect.end.x, 2):
			var c: Color = image.get_pixel(x, y)
			if c.r > 0.72 and c.g > 0.72 and c.b > 0.72:
				count += 1
	return count

func _count_planet_blue_pixels(image: Image, rect: Rect2i) -> int:
	var count: int = 0
	for y: int in range(rect.position.y, rect.end.y, 2):
		for x: int in range(rect.position.x, rect.end.x, 2):
			var c: Color = image.get_pixel(x, y)
			if c.b > 0.30 and c.b > c.r * 1.25 and c.g > c.r * 1.15:
				count += 1
	return count

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
	var builder_image: Image = await _capture("builder")
	if builder_image == null or _count_bright_pixels(builder_image, Rect2i(500, 50, 280, 620)) < 250:
		_fail("builder capture contains no visible vehicle geometry")
		return

	game._launch()
	await process_frame
	await process_frame
	game._update_flight_visuals(0.016)
	await process_frame
	var flight_image: Image = await _capture("flight_pad")
	if flight_image == null or _count_bright_pixels(flight_image, Rect2i(500, 60, 300, 560)) < 180:
		_fail("flight capture contains no visible rocket")
		return

	game._enter_map()
	await process_frame
	await process_frame
	game._update_map(0.016)
	await process_frame
	var map_image: Image = await _capture("map")
	if map_image == null or _count_planet_blue_pixels(map_image, Rect2i(320, 100, 620, 520)) < 1200:
		_fail("map capture contains no visible planet")
		return

	print("APOAPSIS RENDER CAPTURE PASSED")
	quit(0)
