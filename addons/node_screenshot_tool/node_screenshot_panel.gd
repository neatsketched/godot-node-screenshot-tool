@tool
extends Panel

var plugin: EditorPlugin
var eds: EditorSelection = EditorInterface.get_selection()

var preview_node: Node = null
var curr_scene: Node = null:
	set(x):
		curr_scene = x
		update_preview_node()
var curr_node: Node = null:
	set(x):
		curr_node = x
		update_preview_node()
var curr_aabb: AABB

var dont_touch: bool:
	get: return self == get_tree().edited_scene_root

func _ready():
	if dont_touch:
		set_process(false)
		return

	show_warning_text("Select a node to take a screenshot")
	%ResolutionButton.item_selected.connect(update_res)
	update_res(%ResolutionButton.selected)
	%FOVButton.item_selected.connect(update_fov)
	update_fov(%FOVButton.selected)
	visibility_changed.connect(check_visible)
	eds.selection_changed.connect(selection_changed)
	%Width.value_changed.connect(width_changed)
	%Height.value_changed.connect(height_changed)
	%Yaw.value_changed.connect(yaw_changed)
	%Pitch.value_changed.connect(pitch_changed)
	for slider: Slider in [%Width, %Height, %Yaw, %Pitch]:
		slider.value = slider.max_value / 2.0
	%ScreenshotButton.pressed.connect(take_screenshot)
	selection_changed()
	check_visible()

func update_res(idx: int) -> void:
	if dont_touch:
		return

	var res_str: String = %ResolutionButton.get_item_text(idx)
	var split: Array = res_str.split("x")
	%SubViewport.size = Vector2i(int(split[0]), int(split[1]))

func update_fov(idx: int) -> void:
	if dont_touch:
		return

	var fov_str: String = %FOVButton.get_item_text(idx)
	%Camera.fov = int(fov_str)

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if dont_touch:
		return

	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and %ViewportTexture.get_global_rect().has_point(get_global_mouse_position()):
		%Camera.position.z = clampf(%Camera.position.z + (0.05 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -0.05), 0.1, 50.0)
		accept_event()

func check_visible() -> void:
	update_preview_node()
	set_process(visible)

func _process(delta: float) -> void:
	var edited_node: Node = EditorInterface.get_edited_scene_root()
	if edited_node != curr_scene:
		curr_scene = edited_node
		curr_node = null
		selection_changed()

func selection_changed() -> void:
	if dont_touch:
		return

	var selected = eds.get_selected_nodes() 

	if selected.size() > 0:
		# Always pick first node in selection
		var potential_node = selected[0]
		if not potential_node is Node3D:
			return
		if curr_node != selected[0]:
			curr_node = selected[0]

func update_preview_node() -> void:
	if not is_visible_in_tree():
		return
	if dont_touch:
		return

	if preview_node:
		preview_node.queue_free()
		preview_node = null
	curr_aabb = AABB(Vector3.ZERO, Vector3.ZERO)
	if curr_scene and curr_node:
		if get_tree().edited_scene_root.scene_file_path == "":
			show_warning_text("Scene must be saved before screenshots can be taken")
			return
		if get_tree().edited_scene_root.scene_file_path == scene_file_path:
			show_warning_text("Can't take a screenshot of the editor scene!")
			return
		%WarningLabel.hide()
		%Crosshair.show()
		%ScreenshotButton.disabled = false

		var preview_scene: Node = load(get_tree().edited_scene_root.scene_file_path).instantiate()
		if curr_node == get_tree().edited_scene_root:
			preview_node = preview_scene
			%NodeHolder.add_child(preview_node)
		else:
			var node_path: NodePath = get_tree().edited_scene_root.get_path_to(curr_node)
			preview_node = preview_scene.get_node(node_path)
			preview_node.owner = null
			preview_node.get_parent().remove_child(preview_node)
			%NodeHolder.add_child(preview_node)
			preview_scene.queue_free()
		preview_node.global_position = Vector3.ZERO
		curr_aabb = _calculate_spatial_bounds(%NodeHolder)
		%CamRotater.global_position = curr_aabb.get_center()
		for slider: Slider in [%Width, %Height, %Yaw, %Pitch]:
			slider.value = slider.max_value / 2.0

func _calculate_spatial_bounds(parent: Node3D, exclude_top_level_transform: bool = true) -> AABB:
	var bounds: AABB = AABB()
	if parent is VisualInstance3D:
		bounds = parent.get_aabb()

	for i in range(parent.get_child_count()):
		var child: Node = parent.get_child(i)
		if child:
			if not child is Node3D:
				continue

			var child_bounds: AABB = _calculate_spatial_bounds(child, false)
			if bounds.size == Vector3.ZERO and parent:
				bounds = child_bounds
			else:
				bounds = bounds.merge(child_bounds)

	if bounds.size == Vector3.ZERO and not parent:
		bounds = AABB(Vector3(-0.2, -0.2, -0.2), Vector3(0.4, 0.4, 0.4))
	if not exclude_top_level_transform:
		bounds = parent.transform * bounds

	return bounds

func width_changed(value: float) -> void:
	if not curr_aabb:
		return
	if dont_touch:
		return

	%Camera.position.x = lerpf(-curr_aabb.size.x, curr_aabb.size.x, value / %Width.max_value)

func height_changed(value: float) -> void:
	if not curr_aabb:
		return
	if dont_touch:
		return

	%Camera.position.y = lerpf(-curr_aabb.size.y, curr_aabb.size.y, value / %Height.max_value)

func yaw_changed(value: float) -> void:
	if not preview_node:
		return
	if dont_touch:
		return

	preview_node.global_rotation_degrees.y = lerpf(-180.0, 180.0, value / %Yaw.max_value)
	curr_aabb = _calculate_spatial_bounds(%NodeHolder)
	%CamRotater.global_position = curr_aabb.get_center()

func pitch_changed(value: float) -> void:
	if not preview_node:
		return
	if dont_touch:
		return

	preview_node.global_rotation_degrees.x = lerpf(-180.0, 180.0, value / %Pitch.max_value)
	curr_aabb = _calculate_spatial_bounds(%NodeHolder)
	%CamRotater.global_position = curr_aabb.get_center()

func take_screenshot() -> void:
	var new_file_base: String = curr_scene.scene_file_path.trim_suffix('.tscn')
	new_file_base = new_file_base.trim_suffix('.scn')
	var id: int = 0
	var new_file_path: String = ""
	while new_file_path == "" or FileAccess.file_exists(new_file_path):
		id += 1
		new_file_path = "%s-%s-%s.png" % [new_file_base, "pix", id]

	%SubViewport.get_texture().get_image().save_png(new_file_path)
	print_rich("[color=green]Saved[/color] screenshot at [color=light_blue]%s[/color]" % new_file_path)
	EditorInterface.get_resource_filesystem().scan()

func show_warning_text(text: String) -> void:
	%WarningLabel.text = text
	%WarningLabel.show()
	%Crosshair.hide()
	%ScreenshotButton.disabled = true
