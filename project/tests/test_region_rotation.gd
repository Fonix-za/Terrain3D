extends SceneTree

var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func make_region() -> Terrain3DRegion:
	var region := Terrain3DRegion.new()
	region.region_size = 64
	region.vertex_spacing = 1.0
	region.location = Vector2i.ZERO
	var height := Image.create_empty(64, 64, false, Image.FORMAT_RF)
	height.set_pixel(1, 2, Color(9.0, 0.0, 0.0))
	region.height_map = height
	var control := Image.create_empty(64, 64, false, Image.FORMAT_RF)
	control.set_pixel(1, 2, Color(Terrain3DUtil.as_float(Terrain3DUtil.enc_uv_rotation(3) | 7), 0, 0))
	region.control_map = control
	var color := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	color.set_pixel(1, 2, Color.RED)
	region.color_map = color
	var transforms: Array[Transform3D] = [Transform3D(Basis.IDENTITY, Vector3(1, 2, 2))]
	var colors := PackedColorArray([Color.BLUE])
	region.instances = {0: {Vector2i.ZERO: [transforms, colors, false]}}
	return region

func _initialize() -> void:
	var source_region := make_region()
	var expected_positions := [Vector2i(1, 2), Vector2i(61, 1), Vector2i(62, 61), Vector2i(2, 62)]
	var expected_origins := [Vector3(1, 2, 2), Vector3(61, 2, 1), Vector3(62, 2, 61), Vector3(2, 2, 62)]
	for turns in range(4):
		var region: Terrain3DRegion = source_region.rotated(turns)
		check(region != null, "rotation %d returned null" % turns)
		if region == null:
			continue
		var pos: Vector2i = expected_positions[turns]
		check(is_equal_approx(region.height_map.get_pixelv(pos).r, 9.0), "height rotation %d" % turns)
		check(region.color_map.get_pixelv(pos).r > 0.9, "color rotation %d" % turns)
		var bytes: PackedByteArray = region.control_map.get_data()
		var bits: int = bytes.decode_u32((pos.y * 64 + pos.x) * 4)
		check(Terrain3DUtil.get_uv_rotation(bits) == (3 + 4 * turns) % 16, "control angle %d" % turns)
		check(bits & 7 == 7, "control flags %d" % turns)
		var cells: Dictionary = region.instances[0]
		check(cells.size() == 1, "cell count %d" % turns)
		for cell in cells:
			var triple: Array = cells[cell]
			var transform: Transform3D = triple[0][0]
			check(transform.origin.is_equal_approx(expected_origins[turns]), "instance position %d" % turns)
			check(Vector2(transform.origin.x, transform.origin.z).is_equal_approx(Vector2(pos)), "painted mesh misaligned with height %d" % turns)
			check(triple[1][0] == Color.BLUE, "instance color %d" % turns)
			check(cell == Vector2i(int(transform.origin.x) / 32, int(transform.origin.z) / 32), "cell key %d" % turns)
	check(source_region.height_map.get_pixel(1, 2).r == 9.0, "source changed")
	var edge_region := make_region()
	var edge_transforms: Array[Transform3D] = [
		Transform3D(Basis.IDENTITY, Vector3.ZERO),
		Transform3D(Basis.IDENTITY, Vector3(63.999, 0, 63.999)),
	]
	edge_region.instances = {0: {Vector2i.ZERO: [edge_transforms, PackedColorArray([Color.RED, Color.BLUE]), false]}}
	var edge_rotated: Terrain3DRegion = edge_region.rotated(1)
	for cell in edge_rotated.instances[0]:
		for transform in edge_rotated.instances[0][cell][0]:
			check(transform.origin.x >= 0.0 and transform.origin.x < 64.0, "edge X outside region")
			check(transform.origin.z >= 0.0 and transform.origin.z < 64.0, "edge Z outside region")
	check(source_region.rotated(-1) == null, "negative turn count accepted")
	check(source_region.rotated(4) == null, "turn count 4 accepted")
	run_copy_tests.call_deferred(source_region)

func run_copy_tests(source_region: Terrain3DRegion) -> void:
	var source := Terrain3D.new()
	var destination := Terrain3D.new()
	source.free_editor_textures = false
	destination.free_editor_textures = false
	root.add_child(source)
	root.add_child(destination)
	await process_frame
	source.change_region_size(64)
	destination.change_region_size(64)
	var source_mesh: Terrain3DMeshAsset = source.assets.get_mesh_asset(0)
	var scene_root := Node3D.new()
	var mesh_node := MeshInstance3D.new()
	mesh_node.mesh = BoxMesh.new()
	scene_root.add_child(mesh_node)
	mesh_node.owner = scene_root
	var body := StaticBody3D.new()
	body.collision_layer = 4
	scene_root.add_child(body)
	body.owner = scene_root
	var shape_node := CollisionShape3D.new()
	shape_node.shape = BoxShape3D.new()
	shape_node.position = Vector3(0.5, 0.0, 0.25)
	body.add_child(shape_node)
	shape_node.owner = scene_root
	var packed_scene := PackedScene.new()
	check(packed_scene.pack(scene_root) == OK, "scene packing failed")
	source_mesh.scene_file = packed_scene
	var source_texture := Terrain3DTextureAsset.new()
	source.assets.set_texture_asset(0, source_texture)
	destination.assets.set_texture_asset(0, source_texture)
	destination.assets.set_mesh_asset(0, source_mesh)
	source.data.add_region(source_region)
	var copy_error: int = destination.data.copy_region_from(source, Vector2i.ZERO, Vector2i(1, 0), 1)
	check(copy_error == OK, "cross-terrain copy failed")
	check(destination.data.has_region(Vector2i(1, 0)), "copied region missing")
	check(source.data.get_region(Vector2i.ZERO).height_map.get_pixel(1, 2).r == 9.0, "copy changed source")
	check(destination.data.copy_region_from(source, Vector2i.ZERO, Vector2i(2, 0), 2, false) == OK, "second copy failed")
	destination.data.update_maps()
	destination.instancer.update_mmis()
	var saved_region: Terrain3DRegion = destination.data.get_region(Vector2i(1, 0))
	check(saved_region.save("user://rotated_region.res") == OK, "save failed")
	var loaded_region: Terrain3DRegion = ResourceLoader.load("user://rotated_region.res", "", ResourceLoader.CACHE_MODE_IGNORE)
	check(loaded_region != null, "reload failed")
	if loaded_region != null:
		check(loaded_region.height_map.get_pixel(61, 1).r == 9.0, "reloaded height wrong")
		check(loaded_region.instances.has(0), "reloaded instances missing")
	for i in range(3):
		RenderingServer.force_draw()
		await process_frame
		await physics_frame
	var query := PhysicsPointQueryParameters3D.new()
	query.position = Vector3(64 + 60.75, 2.0, 1.5)
	query.collision_mask = 4
	if not Engine.is_editor_hint():
		check(not destination.get_world_3d().direct_space_state.intersect_point(query).is_empty(), "rotated mesh collision missing")
	source_mesh.copy_collision_shapes = false
	for i in range(3):
		RenderingServer.force_draw()
		await process_frame
		await physics_frame
	if not Engine.is_editor_hint():
		check(destination.get_world_3d().direct_space_state.intersect_point(query).is_empty(), "collision checkbox did not remove collision")
	source_mesh.copy_collision_shapes = true
	for i in range(3):
		RenderingServer.force_draw()
		await process_frame
		await physics_frame
	if not Engine.is_editor_hint():
		check(not destination.get_world_3d().direct_space_state.intersect_point(query).is_empty(), "collision checkbox did not rebuild collision")
	check(destination.data.copy_region_from(source, Vector2i.ZERO, Vector2i(1, 0), 1) == ERR_ALREADY_EXISTS, "occupied destination accepted")
	check(destination.data.copy_region_from(source, Vector2i.ZERO, Vector2i(16, 0), 1) != OK, "out of bounds accepted")
	check(destination.data.copy_region_from(source, Vector2i(2, 0), Vector2i(2, 0), 1) != OK, "missing source accepted")
	var wrong_size := Terrain3D.new()
	root.add_child(wrong_size)
	await process_frame
	wrong_size.change_region_size(128)
	check(wrong_size.data.copy_region_from(source, Vector2i.ZERO, Vector2i.ZERO, 1) == ERR_INVALID_DATA, "region-size mismatch accepted")
	wrong_size.queue_free()
	destination.vertex_spacing = 2.0
	check(destination.data.copy_region_from(source, Vector2i.ZERO, Vector2i(3, 0), 1) == ERR_INVALID_DATA, "spacing mismatch accepted")
	destination.vertex_spacing = 1.0
	destination.assets.set_texture_asset(0, Terrain3DTextureAsset.new())
	check(destination.data.copy_region_from(source, Vector2i.ZERO, Vector2i(3, 0), 1) == ERR_INVALID_DATA, "texture asset mismatch accepted")
	destination.assets.set_texture_asset(0, source_texture)
	destination.assets.set_mesh_asset(0, Terrain3DMeshAsset.new())
	check(destination.data.copy_region_from(source, Vector2i.ZERO, Vector2i(3, 0), 1) == ERR_INVALID_DATA, "mesh asset mismatch accepted")
	destination.data.remove_regionl(Vector2i(1, 0))
	check(not destination.data.has_region(Vector2i(1, 0)), "remove copied region failed")
	for i in range(3):
		RenderingServer.force_draw()
		await process_frame
		await physics_frame
	if not Engine.is_editor_hint():
		check(destination.get_world_3d().direct_space_state.intersect_point(query).is_empty(), "stale painted collision after remove")
	source.queue_free()
	destination.queue_free()
	scene_root.free()
	print("Terrain region rotation failures: ", failures.size())
	quit(0 if failures.is_empty() else 1)
