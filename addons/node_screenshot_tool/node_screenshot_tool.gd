@tool
extends EditorPlugin

var panel: Panel

func _enter_tree():
	assert(Engine.get_version_info().major >= 4)

	panel = preload("node_screenshot_panel.tscn").instantiate()
	add_control_to_dock(EditorPlugin.DockSlot.DOCK_SLOT_LEFT_UR, panel)
	panel.plugin = self

func _exit_tree():
	if panel:
		remove_control_from_docks(panel)
		panel.queue_free()
		panel = null
