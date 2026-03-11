@tool
extends EditorPlugin

var dock: Control

func _enter_tree():
	# Use a more robust instantiation method for tool scripts
	var dock_script = preload("res://addons/hiruai/dock.gd")
	if dock_script:
		dock = VBoxContainer.new()
		dock.set_script(dock_script)
		dock.name = "HiruAI"
		add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)
	
	# Start Ghost Autocomplete
	var ghost_script = preload("res://addons/hiruai/ghost_autocomplete.gd")
	if ghost_script:
		var ghost = Node.new()
		ghost.set_script(ghost_script)
		ghost.name = "GhostAutocomplete"
		add_child(ghost)
	
	print("[HiruAI] ✅ Plugin loaded.")

func _exit_tree():
	if dock:
		remove_control_from_docks(dock)
		dock.queue_free()
		
	var ghost = get_node_or_null("GhostAutocomplete")
	if ghost:
		ghost.queue_free()
		
	print("[HiruAI] Plugin unloaded.")
