@tool
extends VBoxContainer

const Importer = preload("res://addons/unity2godot_sprites/unity_sprite_importer.gd")
const Candidate = preload("res://addons/unity2godot_sprites/conversion_candidate.gd")

var candidates: Array[UnitySpriteCandidate] = []
var source_path_edit: LineEdit
var output_path_edit: LineEdit
var result_tree: Tree
var create_scene_check: CheckBox
var convert_button: Button
var status_label: Label
var log_output: RichTextLabel
var source_dialog: FileDialog
var output_dialog: FileDialog
var overwrite_dialog: ConfirmationDialog
var pending_candidates: Array[UnitySpriteCandidate] = []


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	name = "Unity Sprites"
	custom_minimum_size = Vector2(0, 300)

	var header := Label.new()
	header.text = "Unity 2D Sprite Converter"
	header.add_theme_font_size_override("font_size", 16)
	add_child(header)

	var source_row := HBoxContainer.new()
	add_child(source_row)
	var source_label := Label.new()
	source_label.text = "Unity folder"
	source_label.custom_minimum_size.x = 110
	source_row.add_child(source_label)
	source_path_edit = LineEdit.new()
	source_path_edit.placeholder_text = "Choose a Unity asset folder"
	source_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	source_row.add_child(source_path_edit)
	var source_button := Button.new()
	source_button.text = "Browse..."
	source_button.pressed.connect(_show_source_dialog)
	source_row.add_child(source_button)

	var output_row := HBoxContainer.new()
	add_child(output_row)
	var output_label := Label.new()
	output_label.text = "Godot output"
	output_label.custom_minimum_size.x = 110
	output_row.add_child(output_label)
	output_path_edit = LineEdit.new()
	output_path_edit.text = "res://converted_unity_sprites"
	output_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	output_row.add_child(output_path_edit)
	var output_button := Button.new()
	output_button.text = "Browse..."
	output_button.pressed.connect(_show_output_dialog)
	output_row.add_child(output_button)

	var action_row := HBoxContainer.new()
	add_child(action_row)
	var scan_button := Button.new()
	scan_button.text = "Scan Folder"
	scan_button.pressed.connect(_scan_folder)
	action_row.add_child(scan_button)
	create_scene_check = CheckBox.new()
	create_scene_check.text = "Create AnimatedSprite2D scenes"
	action_row.add_child(create_scene_check)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_child(spacer)
	convert_button = Button.new()
	convert_button.text = "Convert Selected"
	convert_button.disabled = true
	convert_button.pressed.connect(_request_conversion)
	action_row.add_child(convert_button)

	result_tree = Tree.new()
	result_tree.columns = 6
	result_tree.column_titles_visible = true
	result_tree.set_column_title(0, "Convert")
	result_tree.set_column_title(1, "Asset")
	result_tree.set_column_title(2, "Type")
	result_tree.set_column_title(3, "Animations")
	result_tree.set_column_title(4, "Frames")
	result_tree.set_column_title(5, "Status")
	result_tree.set_column_custom_minimum_width(0, 70)
	result_tree.set_column_expand(0, false)
	result_tree.set_column_expand(3, false)
	result_tree.set_column_expand(4, false)
	result_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	result_tree.custom_minimum_size.y = 150
	add_child(result_tree)

	status_label = Label.new()
	status_label.text = "Choose a Unity asset folder to begin."
	add_child(status_label)
	log_output = RichTextLabel.new()
	log_output.bbcode_enabled = true
	log_output.fit_content = true
	log_output.custom_minimum_size.y = 70
	log_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(log_output)

	source_dialog = FileDialog.new()
	source_dialog.access = FileDialog.ACCESS_FILESYSTEM
	source_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	source_dialog.title = "Choose Unity Asset Folder"
	source_dialog.dir_selected.connect(func(path: String) -> void: source_path_edit.text = path)
	add_child(source_dialog)

	output_dialog = FileDialog.new()
	output_dialog.access = FileDialog.ACCESS_RESOURCES
	output_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	output_dialog.title = "Choose Godot Output Folder"
	output_dialog.dir_selected.connect(func(path: String) -> void: output_path_edit.text = path)
	add_child(output_dialog)

	overwrite_dialog = ConfirmationDialog.new()
	overwrite_dialog.title = "Replace Existing Files?"
	overwrite_dialog.confirmed.connect(_convert_pending)
	add_child(overwrite_dialog)


func _show_source_dialog() -> void:
	if not source_path_edit.text.is_empty() and DirAccess.dir_exists_absolute(source_path_edit.text):
		source_dialog.current_dir = source_path_edit.text
	source_dialog.popup_centered_ratio(0.7)


func _show_output_dialog() -> void:
	output_dialog.current_dir = output_path_edit.text if output_path_edit.text.begins_with("res://") else "res://"
	output_dialog.popup_centered_ratio(0.7)


func _scan_folder() -> void:
	log_output.clear()
	var source_path := source_path_edit.text.strip_edges()
	if not DirAccess.dir_exists_absolute(source_path):
		_set_error("Choose an existing Unity asset folder.")
		return
	status_label.text = "Scanning..."
	candidates = Importer.scan_folder(source_path)
	_rebuild_tree()
	var valid_count := 0
	for candidate in candidates:
		if candidate.is_valid():
			valid_count += 1
	status_label.text = "Found %d compatible source(s), %d ready to convert." % [candidates.size(), valid_count]
	convert_button.disabled = valid_count == 0


func _rebuild_tree() -> void:
	result_tree.clear()
	var root := result_tree.create_item()
	for index in candidates.size():
		var candidate := candidates[index]
		var item := result_tree.create_item(root)
		item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		item.set_checked(0, candidate.is_valid())
		item.set_editable(0, candidate.is_valid())
		item.set_metadata(0, index)
		item.set_text(1, candidate.display_name)
		item.set_tooltip_text(1, candidate.texture_path)
		item.set_text(2, candidate.kind_label())
		item.set_text(3, str(candidate.animation_count))
		item.set_text(4, str(candidate.frame_count))
		if candidate.warnings.is_empty():
			item.set_text(5, "Ready")
		else:
			item.set_text(5, "Warning")
			item.set_tooltip_text(5, "\n".join(candidate.warnings))


func _selected_candidates() -> Array[UnitySpriteCandidate]:
	var selected: Array[UnitySpriteCandidate] = []
	var root := result_tree.get_root()
	if root == null:
		return selected
	var item := root.get_first_child()
	while item != null:
		var index: int = item.get_metadata(0)
		if item.is_checked(0) and index >= 0 and index < candidates.size():
			selected.append(candidates[index])
		item = item.get_next()
	return selected


func _request_conversion() -> void:
	var output_root := output_path_edit.text.strip_edges().trim_suffix("/")
	if not output_root.begins_with("res://"):
		_set_error("Output must be a folder inside this Godot project (res://).")
		return
	pending_candidates = _selected_candidates()
	if pending_candidates.is_empty():
		_set_error("Select at least one valid asset.")
		return
	var collisions := Importer.find_collisions(pending_candidates, output_root, create_scene_check.button_pressed)
	if not collisions.is_empty():
		overwrite_dialog.dialog_text = "%d existing file(s) will be replaced:\n\n%s" % [collisions.size(), "\n".join(collisions)]
		overwrite_dialog.popup_centered(Vector2i(640, 360))
		return
	_convert_pending()


func _convert_pending() -> void:
	var output_root := output_path_edit.text.strip_edges().trim_suffix("/")
	var collisions := Importer.find_collisions(pending_candidates, output_root, create_scene_check.button_pressed)
	var overwrite := not collisions.is_empty()
	var successes := 0
	var failures := 0
	log_output.clear()
	for candidate in pending_candidates:
		var result := Importer.convert_candidate(candidate, output_root, create_scene_check.button_pressed, overwrite)
		if result.ok:
			successes += 1
			log_output.append_text("[color=green]OK[/color] %s: %d animations, %d frames -> %s\n" % [result.candidate_name, result.animation_count, result.frame_count, result.sprite_frames_path])
		else:
			failures += 1
			log_output.append_text("[color=red]FAILED[/color] %s: %s\n" % [result.candidate_name, result.error])
	status_label.text = "Conversion complete: %d succeeded, %d failed." % [successes, failures]
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()
	pending_candidates.clear()


func _set_error(message: String) -> void:
	status_label.text = message
	log_output.clear()
	log_output.append_text("[color=red]%s[/color]" % message)
