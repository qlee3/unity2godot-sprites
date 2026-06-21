@tool
extends EditorPlugin

const ImportDock = preload("res://addons/unity2godot_sprites/import_dock.gd")

var dock: Control
var bottom_panel_button: Button


func _enter_tree() -> void:
	dock = ImportDock.new()
	bottom_panel_button = add_control_to_bottom_panel(dock, "Unity Sprites")


func _exit_tree() -> void:
	if dock != null:
		remove_control_from_bottom_panel(dock)
		dock.free()
	dock = null
	bottom_panel_button = null
