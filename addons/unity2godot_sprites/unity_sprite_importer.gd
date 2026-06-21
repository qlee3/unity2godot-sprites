@tool
class_name UnitySpriteImporter
extends RefCounted

const Candidate = preload("res://addons/unity2godot_sprites/conversion_candidate.gd")
const ConversionResult = preload("res://addons/unity2godot_sprites/conversion_result.gd")

const LOOPING_LIBRARY_ANIMATIONS := {
	"Block": true, "Climb": true, "Crawl": true, "Fire": true,
	"Idle": true, "Ready": true, "Run": true,
}
const LIBRARY_ANIMATION_SPEEDS := {
	"Block": 6.0, "Climb": 6.0, "Crawl": 8.0, "Death": 8.0,
	"Fire": 10.0, "Idle": 4.0, "Jab": 12.0, "Jump": 8.0,
	"Push": 10.0, "Ready": 4.0, "Roll": 14.0, "Run": 10.0,
	"Shot": 10.0, "Slash": 12.0,
}


static func scan_folder(source_root: String) -> Array[UnitySpriteCandidate]:
	var normalized := source_root.simplify_path()
	if not DirAccess.dir_exists_absolute(normalized):
		return []
	var files: PackedStringArray = []
	_collect_files(normalized, files)
	var file_set := {}
	var guid_to_texture := {}
	var textures: PackedStringArray = []
	var clips: PackedStringArray = []
	for path in files:
		file_set[path] = true
		if path.to_lower().ends_with(".png"):
			textures.append(path)
		elif path.to_lower().ends_with(".anim"):
			clips.append(path)
	for texture_path in textures:
		var meta_path := texture_path + ".meta"
		if file_set.has(meta_path):
			var guid := _parse_meta_guid(meta_path)
			if not guid.is_empty():
				guid_to_texture[guid] = texture_path

	var candidates: Array[UnitySpriteCandidate] = []
	for texture_path in textures:
		var meta_path := texture_path + ".meta"
		var base_path := texture_path.get_basename()
		var library_path := base_path + ".asset"
		if file_set.has(library_path):
			var candidate := Candidate.new()
			candidate.source_kind = Candidate.SourceKind.SPRITE_LIBRARY
			candidate.display_name = base_path.get_file()
			candidate.texture_path = texture_path
			candidate.meta_path = meta_path
			candidate.library_path = library_path
			_populate_library_summary(candidate)
			candidates.append(candidate)

	var clips_by_texture := {}
	for clip_path in clips:
		var clip_data := _parse_animation_clip(clip_path)
		var clip_guids: Dictionary = clip_data.guids
		for guid in clip_guids:
			if not guid_to_texture.has(guid):
				continue
			var texture_path: String = guid_to_texture[guid]
			if not clips_by_texture.has(texture_path):
				clips_by_texture[texture_path] = []
			if not clips_by_texture[texture_path].has(clip_path):
				clips_by_texture[texture_path].append(clip_path)
	for texture_path in clips_by_texture:
		var candidate := Candidate.new()
		candidate.source_kind = Candidate.SourceKind.ANIMATION_CLIPS
		candidate.display_name = texture_path.get_basename().get_file()
		candidate.texture_path = texture_path
		candidate.meta_path = texture_path + ".meta"
		candidate.animation_paths = PackedStringArray(clips_by_texture[texture_path])
		_populate_clip_summary(candidate)
		candidates.append(candidate)

	candidates.sort_custom(func(a: UnitySpriteCandidate, b: UnitySpriteCandidate) -> bool:
		return a.display_name.naturalnocasecmp_to(b.display_name) < 0
	)
	return candidates


static func validate_candidate(candidate: UnitySpriteCandidate) -> PackedStringArray:
	var errors: PackedStringArray = []
	if not FileAccess.file_exists(candidate.texture_path):
		errors.append("Texture is missing: %s" % candidate.texture_path)
	if not FileAccess.file_exists(candidate.meta_path):
		errors.append("Texture metadata is missing: %s" % candidate.meta_path)
	var frames := _parse_texture_meta(candidate.meta_path)
	if frames.is_empty():
		errors.append("No sliced sprites were found in the texture metadata")
	if candidate.source_kind == Candidate.SourceKind.SPRITE_LIBRARY:
		if not FileAccess.file_exists(candidate.library_path):
			errors.append("Sprite Library asset is missing: %s" % candidate.library_path)
		elif _parse_library_categories(candidate.library_path).is_empty():
			errors.append("No categories were found in the Sprite Library asset")
	elif candidate.animation_paths.is_empty():
		errors.append("No AnimationClip files reference this texture")
	else:
		for clip_path in candidate.animation_paths:
			if _parse_animation_clip(clip_path).frame_ids.is_empty():
				errors.append("No sprite frames were found in %s" % clip_path.get_file())
	return errors


static func get_output_paths(candidate: UnitySpriteCandidate, output_root: String, create_scene: bool) -> PackedStringArray:
	var root := output_root.trim_suffix("/")
	var base_name := _safe_file_name(candidate.display_name)
	if candidate.source_kind == Candidate.SourceKind.ANIMATION_CLIPS:
		base_name += "_clips"
	var paths := PackedStringArray([
		root + "/textures/" + base_name + ".png",
		root + "/animations/" + base_name + "_frames.tres",
	])
	if create_scene:
		paths.append(root + "/scenes/" + base_name + ".tscn")
	return paths


static func find_collisions(candidates: Array[UnitySpriteCandidate], output_root: String, create_scene: bool) -> PackedStringArray:
	var collisions: PackedStringArray = []
	for candidate in candidates:
		for path in get_output_paths(candidate, output_root, create_scene):
			if FileAccess.file_exists(path) and not collisions.has(path):
				collisions.append(path)
	return collisions


static func convert_candidate(
	candidate: UnitySpriteCandidate,
	output_root: String,
	create_scene: bool = false,
	overwrite: bool = false
) -> UnitySpriteConversionResult:
	var validation_errors := validate_candidate(candidate)
	if not validation_errors.is_empty():
		return ConversionResult.failure(candidate.display_name, "\n".join(validation_errors))
	if not output_root.begins_with("res://"):
		return ConversionResult.failure(candidate.display_name, "Output folder must be inside the Godot project (res://)")
	var paths := get_output_paths(candidate, output_root, create_scene)
	for path in paths:
		if FileAccess.file_exists(path) and not overwrite:
			return ConversionResult.failure(candidate.display_name, "Output already exists: %s" % path)

	for directory in [paths[0].get_base_dir(), paths[1].get_base_dir()]:
		var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
		if directory_error != OK:
			return ConversionResult.failure(candidate.display_name, "Could not create output folder: %s" % directory)
	if create_scene:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(paths[2].get_base_dir()))
	var copy_error := DirAccess.copy_absolute(candidate.texture_path, ProjectSettings.globalize_path(paths[0]))
	if copy_error != OK:
		return ConversionResult.failure(candidate.display_name, "Could not copy texture (error %d)" % copy_error)

	var texture := _load_copied_texture(paths[0])
	if texture == null:
		return ConversionResult.failure(candidate.display_name, "Could not load copied texture: %s" % paths[0])
	var build_result: Dictionary
	if candidate.source_kind == Candidate.SourceKind.SPRITE_LIBRARY:
		build_result = _build_library_frames(candidate, texture)
	else:
		build_result = _build_clip_frames(candidate, texture)
	if not build_result.get("ok", false):
		return ConversionResult.failure(candidate.display_name, build_result.get("error", "Conversion failed"))
	var sprite_frames: SpriteFrames = build_result.sprite_frames
	var save_error := ResourceSaver.save(sprite_frames, paths[1])
	if save_error != OK:
		return ConversionResult.failure(candidate.display_name, "Could not save SpriteFrames (error %d)" % save_error)
	if create_scene:
		var scene_error := _save_animated_sprite_scene(sprite_frames, candidate.display_name, paths[2])
		if scene_error != OK:
			return ConversionResult.failure(candidate.display_name, "Could not save scene (error %d)" % scene_error)

	var result := ConversionResult.new()
	result.ok = true
	result.candidate_name = candidate.display_name
	result.animation_count = build_result.animation_count
	result.frame_count = build_result.frame_count
	result.texture_path = paths[0]
	result.sprite_frames_path = paths[1]
	result.scene_path = paths[2] if create_scene else ""
	return result


static func _collect_files(folder: String, output: PackedStringArray) -> void:
	var directory := DirAccess.open(folder)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var path := folder.path_join(entry)
			if directory.current_is_dir():
				_collect_files(path, output)
			else:
				output.append(path)
		entry = directory.get_next()
	directory.list_dir_end()


static func _populate_library_summary(candidate: UnitySpriteCandidate) -> void:
	candidate.animation_count = _parse_library_categories(candidate.library_path).size()
	candidate.frame_count = _parse_texture_meta(candidate.meta_path).size()
	candidate.warnings = validate_candidate(candidate)


static func _populate_clip_summary(candidate: UnitySpriteCandidate) -> void:
	candidate.animation_count = candidate.animation_paths.size()
	for clip_path in candidate.animation_paths:
		candidate.frame_count += _parse_animation_clip(clip_path).frame_ids.size()
	candidate.warnings = validate_candidate(candidate)


static func _build_library_frames(candidate: UnitySpriteCandidate, texture: Texture2D) -> Dictionary:
	var frames := _parse_texture_meta(candidate.meta_path)
	var categories := _parse_library_categories(candidate.library_path)
	var grouped := _group_frames(frames)
	var sprite_frames := _empty_sprite_frames()
	var total_frames := 0
	for category in categories:
		var category_name: String = category.name
		if not grouped.has(category_name):
			return {"ok": false, "error": "Category '%s' has no matching sliced sprites" % category_name}
		var category_frames: Array = grouped[category_name]
		if category_frames.size() != category.count:
			return {"ok": false, "error": "Category '%s' expects %d frames, found %d" % [category_name, category.count, category_frames.size()]}
		category_frames.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.index < b.index)
		var animation_name := StringName(category_name)
		sprite_frames.add_animation(animation_name)
		sprite_frames.set_animation_speed(animation_name, LIBRARY_ANIMATION_SPEEDS.get(category_name, 8.0))
		sprite_frames.set_animation_loop(animation_name, LOOPING_LIBRARY_ANIMATIONS.has(category_name))
		for frame in category_frames:
			sprite_frames.add_frame(animation_name, _make_atlas(texture, frame))
			total_frames += 1
	return {"ok": true, "sprite_frames": sprite_frames, "animation_count": categories.size(), "frame_count": total_frames}


static func _build_clip_frames(candidate: UnitySpriteCandidate, texture: Texture2D) -> Dictionary:
	var meta_frames := _parse_texture_meta(candidate.meta_path)
	var frames_by_name := {}
	for frame in meta_frames:
		frames_by_name[frame.name] = frame
	var id_names := _parse_internal_id_names(candidate.meta_path)
	var sprite_frames := _empty_sprite_frames()
	var total_frames := 0
	for clip_path in candidate.animation_paths:
		var clip_data := _parse_animation_clip(clip_path)
		var animation_name := StringName(clip_data.name)
		if sprite_frames.has_animation(animation_name):
			return {"ok": false, "error": "Duplicate animation name: %s" % clip_data.name}
		sprite_frames.add_animation(animation_name)
		sprite_frames.set_animation_speed(animation_name, clip_data.fps)
		sprite_frames.set_animation_loop(animation_name, clip_data.loop)
		for frame_id in clip_data.frame_ids:
			var frame_name: String = id_names.get(frame_id, "")
			if frame_name.is_empty() or not frames_by_name.has(frame_name):
				return {"ok": false, "error": "%s references unknown sprite fileID %s" % [clip_path.get_file(), frame_id]}
			sprite_frames.add_frame(animation_name, _make_atlas(texture, frames_by_name[frame_name]))
			total_frames += 1
	return {"ok": true, "sprite_frames": sprite_frames, "animation_count": candidate.animation_paths.size(), "frame_count": total_frames}


static func _empty_sprite_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	if frames.has_animation(&"default"):
		frames.remove_animation(&"default")
	return frames


static func _make_atlas(texture: Texture2D, frame: Dictionary) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(frame.x, texture.get_height() - frame.y - frame.height, frame.width, frame.height)
	return atlas


static func _load_copied_texture(resource_path: String) -> Texture2D:
	if DisplayServer.get_name() == "headless":
		var headless_image := Image.load_from_file(ProjectSettings.globalize_path(resource_path))
		if headless_image == null or headless_image.is_empty():
			return null
		return ImageTexture.create_from_image(headless_image)
	if Engine.is_editor_hint() and DisplayServer.get_name() != "headless":
		var filesystem := EditorInterface.get_resource_filesystem()
		filesystem.update_file(resource_path)
		filesystem.reimport_files(PackedStringArray([resource_path]))
	var texture := ResourceLoader.load(resource_path, "Texture2D", ResourceLoader.CACHE_MODE_REPLACE) as Texture2D
	if texture != null:
		return texture
	var image := Image.load_from_file(ProjectSettings.globalize_path(resource_path))
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)


static func _save_animated_sprite_scene(frames: SpriteFrames, display_name: String, path: String) -> Error:
	var sprite := AnimatedSprite2D.new()
	sprite.name = _safe_node_name(display_name)
	sprite.sprite_frames = frames
	var names := frames.get_animation_names()
	if not names.is_empty():
		sprite.animation = names[0]
	var scene := PackedScene.new()
	var pack_error := scene.pack(sprite)
	if pack_error != OK:
		sprite.free()
		return pack_error
	var save_error := ResourceSaver.save(scene, path)
	sprite.free()
	return save_error


static func _parse_texture_meta(path: String) -> Array[Dictionary]:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return []
	var frames: Array[Dictionary] = []
	var current := {}
	for line in text.split("\n"):
		if line.begins_with("      name: "):
			if current.has("height"):
				frames.append(current)
			current = {"name": line.trim_prefix("      name: ").strip_edges()}
		elif not current.is_empty() and line.begins_with("        x: "):
			current.x = line.trim_prefix("        x: ").to_int()
		elif not current.is_empty() and line.begins_with("        y: "):
			current.y = line.trim_prefix("        y: ").to_int()
		elif not current.is_empty() and line.begins_with("        width: "):
			current.width = line.trim_prefix("        width: ").to_int()
		elif not current.is_empty() and line.begins_with("        height: "):
			current.height = line.trim_prefix("        height: ").to_int()
	if current.has("height"):
		frames.append(current)
	return frames


static func _parse_library_categories(path: String) -> Array[Dictionary]:
	var text := FileAccess.get_file_as_string(path)
	var categories: Array[Dictionary] = []
	var current_index := -1
	for line in text.split("\n"):
		if line.begins_with("  - m_Name: "):
			categories.append({"name": line.trim_prefix("  - m_Name: ").strip_edges(), "count": 0})
			current_index = categories.size() - 1
		elif current_index >= 0 and line.begins_with("    - m_Name: "):
			categories[current_index].count += 1
	return categories


static func _parse_internal_id_names(path: String) -> Dictionary:
	var result := {}
	var pending_id := ""
	for raw_line in FileAccess.get_file_as_string(path).split("\n"):
		var line := raw_line.strip_edges()
		if line.begins_with("213: "):
			pending_id = line.trim_prefix("213: ")
		elif not pending_id.is_empty() and line.begins_with("second: "):
			result[pending_id] = line.trim_prefix("second: ").strip_edges()
			pending_id = ""
	return result


static func _parse_meta_guid(path: String) -> String:
	for raw_line in FileAccess.get_file_as_string(path).split("\n"):
		var line := raw_line.strip_edges()
		if line.begins_with("guid: "):
			return line.trim_prefix("guid: ").strip_edges()
	return ""


static func _parse_animation_clip(path: String) -> Dictionary:
	var result := {"name": path.get_basename().get_file(), "frame_ids": PackedStringArray(), "guids": {}, "fps": 12.0, "loop": false}
	var reading_curve := false
	for raw_line in FileAccess.get_file_as_string(path).split("\n"):
		var line := raw_line.strip_edges()
		if raw_line.begins_with("  m_Name: "):
			result.name = raw_line.trim_prefix("  m_Name: ").strip_edges()
		elif raw_line.begins_with("  - curve:"):
			reading_curve = true
		elif reading_curve and raw_line.begins_with("    attribute:"):
			reading_curve = false
		elif reading_curve and line.begins_with("value: {fileID: "):
			var reference := line.trim_prefix("value: {fileID: ").trim_suffix("}")
			var file_id := reference.get_slice(",", 0).strip_edges()
			result.frame_ids.append(file_id)
			var guid_marker := "guid: "
			var guid_position := reference.find(guid_marker)
			if guid_position >= 0:
				var guid := reference.substr(guid_position + guid_marker.length()).get_slice(",", 0).strip_edges()
				result.guids[guid] = true
		elif line.begins_with("m_SampleRate: "):
			result.fps = line.trim_prefix("m_SampleRate: ").to_float()
		elif line.begins_with("m_LoopTime: "):
			result.loop = line.trim_prefix("m_LoopTime: ").to_int() == 1
	return result


static func _group_frames(frames: Array[Dictionary]) -> Dictionary:
	var grouped := {}
	for frame in frames:
		var frame_name: String = frame.name
		var separator := frame_name.rfind("_")
		if separator < 1:
			continue
		var category := frame_name.left(separator)
		frame.index = frame_name.substr(separator + 1).to_int()
		if not grouped.has(category):
			grouped[category] = []
		grouped[category].append(frame)
	return grouped


static func _safe_file_name(value: String) -> String:
	var output := value.to_snake_case()
	for character in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]:
		output = output.replace(character, "_")
	return output if not output.is_empty() else "sprite"


static func _safe_node_name(value: String) -> String:
	var output := value.strip_edges().replace("/", "_").replace("@", "_").replace(":", "_")
	return output if not output.is_empty() else "AnimatedSprite2D"
