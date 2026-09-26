extends SceneTree

var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func make_region(location: Vector2i, height_value: float, tint: Color) -> Terrain3DRegion:
	var region := Terrain3DRegion.new()
	region.region_size = 64
	region.vertex_spacing = 1.0
	region.location = location
	var height := Image.create_empty(64, 64, false, Image.FORMAT_RF)
	height.fill(Color(height_value, 0, 0))
	region.height_map = height
	var color := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	color.fill(tint)
	region.color_map = color
	var control := Image.create_empty(64, 64, false, Image.FORMAT_RF)
	control.fill(Color(Terrain3DUtil.as_float(Terrain3DUtil.enc_base(0) | Terrain3DUtil.enc_nav(true)), 0, 0))
	region.control_map = control
	return region

func _initialize() -> void:
	run_tests.call_deferred()

func run_tests() -> void:
	var terrain := Terrain3D.new()
	root.add_child(terrain)
	await process_frame
	terrain.change_region_size(64)
	terrain.collision_mode = 3 # Full / Game
	terrain.assets.set_texture_asset(0, Terrain3DTextureAsset.new())
	terrain.assets.set_texture_asset(1, Terrain3DTextureAsset.new())
	var values := {Vector2i(0, 0): 0.0, Vector2i(1, 0): 10.0, Vector2i(0, 1): 20.0, Vector2i(1, 1): 30.0}
	for location in values:
		var tint := Color.RED if location.x == 0 else Color.BLUE
		check(terrain.data.add_region(make_region(location, values[location], tint), false) == OK, "add region %s" % location)
	terrain.data.update_maps()
	var original_center: float = terrain.data.get_region(Vector2i.ZERO).height_map.get_pixel(20, 20).r
	var invalid: Dictionary = terrain.data.stitch_region_seams(8, true, 31)
	check(invalid.error == ERR_INVALID_PARAMETER, "invalid transition texture accepted")
	check(terrain.data.get_region(Vector2i.ZERO).height_map.get_pixel(63, 20).r == 0.0, "invalid call changed maps")
	check(terrain.data.stitch_region_seams(0).error == ERR_INVALID_PARAMETER, "zero-width stitch accepted")
	var report: Dictionary = terrain.data.stitch_region_seams(8, true, 1, 4.0)
	check(report.error == OK, "stitch failed")
	check(report.stitched_edges == 4, "expected four joins")
	check(report.steep_edges.size() == 4, "steep joins not reported")
	check(terrain.data.get_region(Vector2i.ZERO).height_map.get_pixel(20, 20).r == original_center, "interior changed")
	for row in range(2):
		for y in range(64):
			var left: Terrain3DRegion = terrain.data.get_region(Vector2i(0, row))
			var right: Terrain3DRegion = terrain.data.get_region(Vector2i(1, row))
			check(is_equal_approx(left.height_map.get_pixel(63, y).r, right.height_map.get_pixel(0, y).r), "X height seam %d,%d" % [row, y])
			check(left.color_map.get_pixel(63, y).is_equal_approx(right.color_map.get_pixel(0, y)), "X color seam %d,%d" % [row, y])
	for column in range(2):
		for x in range(64):
			var top: Terrain3DRegion = terrain.data.get_region(Vector2i(column, 0))
			var bottom: Terrain3DRegion = terrain.data.get_region(Vector2i(column, 1))
			check(is_equal_approx(top.height_map.get_pixel(x, 63).r, bottom.height_map.get_pixel(x, 0).r), "Z height seam %d,%d" % [column, x])
	var left_control: PackedByteArray = terrain.data.get_region(Vector2i.ZERO).control_map.get_data()
	var right_control: PackedByteArray = terrain.data.get_region(Vector2i(1, 0)).control_map.get_data()
	for bits in [left_control.decode_u32((20 * 64 + 63) * 4), right_control.decode_u32((20 * 64) * 4)]:
		check(Terrain3DUtil.get_overlay(bits) == 1, "transition texture missing")
		check(Terrain3DUtil.get_blend(bits) == 255, "transition edge weight wrong")
		check(Terrain3DUtil.is_nav(bits), "navigation flag lost")
	check(Terrain3DUtil.get_overlay(left_control.decode_u32((20 * 64 + 20) * 4)) == 0, "interior texture changed")
	var control_before: PackedByteArray = terrain.data.get_region(Vector2i.ZERO).control_map.get_data()
	var color_before: Color = terrain.data.get_region(Vector2i.ZERO).color_map.get_pixel(63, 20)
	check(terrain.data.stitch_region_seams(2, false, -1).error == OK, "height-only stitch failed")
	check(terrain.data.get_region(Vector2i.ZERO).control_map.get_data() == control_before, "height-only stitch changed textures")
	check(terrain.data.get_region(Vector2i.ZERO).color_map.get_pixel(63, 20) == color_before, "height-only stitch changed colors")
	var stitched_region: Terrain3DRegion = terrain.data.get_region(Vector2i.ZERO)
	check(stitched_region.save("user://stitched_region.res") == OK, "stitched region save failed")
	var reloaded: Terrain3DRegion = ResourceLoader.load("user://stitched_region.res", "", ResourceLoader.CACHE_MODE_IGNORE)
	check(reloaded != null, "stitched region reload failed")
	if reloaded != null:
		check(is_equal_approx(reloaded.height_map.get_pixel(63, 20).r, stitched_region.height_map.get_pixel(63, 20).r), "stitched height did not persist")
	if not Engine.is_editor_hint():
		var camera := Camera3D.new()
		root.add_child(camera)
		camera.position = Vector3(63, 40, 20)
		terrain.set_camera(camera)
		for i in range(3):
			await physics_frame
		var query := PhysicsRayQueryParameters3D.create(Vector3(64, 50, 20), Vector3(64, -50, 20))
		var hit: Dictionary = terrain.get_world_3d().direct_space_state.intersect_ray(query)
		check(not hit.is_empty(), "stitched terrain collision missing")
		if not hit.is_empty():
			check(absf(hit.position.y - 5.0) < 0.25, "collision height was not refreshed")
		camera.queue_free()
	terrain.queue_free()
	print("Terrain seam failures: ", failures.size())
	quit(0 if failures.is_empty() else 1)
