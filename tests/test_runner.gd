extends SceneTree

const Importer = preload("res://addons/unity2godot_sprites/unity_sprite_importer.gd")
const Candidate = preload("res://addons/unity2godot_sprites/conversion_candidate.gd")
const ImportDock = preload("res://addons/unity2godot_sprites/import_dock.gd")

var failures: PackedStringArray = []
var source_root := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_run_tests()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("PASS: scan, library, clips, coordinates, conflicts, copying, and scenes")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _run_tests() -> void:
	var dock := ImportDock.new()
	root.add_child(dock)
	_check(dock.name == "Unity Sprites", "Editor dock did not initialize")
	dock.free()

	source_root = OS.get_user_data_dir().path_join("unity2godot_sprites_test_source")
	_remove_tree(source_root)
	_remove_tree(ProjectSettings.globalize_path("res://test_output"))
	DirAccess.make_dir_recursive_absolute(source_root)
	_create_fixture()

	var candidates := Importer.scan_folder(source_root)
	_check(candidates.size() == 4, "Expected library, clips, and two invalid candidates")
	var library: UnitySpriteCandidate
	var clips: UnitySpriteCandidate
	var invalid: UnitySpriteCandidate
	var malformed: UnitySpriteCandidate
	for candidate in candidates:
		if candidate.display_name == "hero" and candidate.source_kind == Candidate.SourceKind.SPRITE_LIBRARY:
			library = candidate
		elif candidate.display_name == "hero" and candidate.source_kind == Candidate.SourceKind.ANIMATION_CLIPS:
			clips = candidate
		elif candidate.display_name == "broken":
			invalid = candidate
		elif candidate.display_name == "malformed":
			malformed = candidate
	_check(library != null and library.animation_count == 2 and library.frame_count == 4, "Sprite Library scan summary is incorrect")
	_check(clips != null and clips.animation_count == 2 and clips.frame_count == 4, "AnimationClip scan summary is incorrect")
	_check(invalid != null and not invalid.is_valid(), "Missing metadata should produce an invalid candidate")
	_check(malformed != null and not malformed.is_valid(), "Malformed metadata should produce an invalid candidate")

	if library != null:
		var result := Importer.convert_candidate(library, "res://test_output/library", true, false)
		_check(result.ok, "Sprite Library conversion failed: %s" % result.error)
		_check(FileAccess.file_exists(result.texture_path), "Source PNG was not copied")
		_check(FileAccess.file_exists(result.sprite_frames_path), "SpriteFrames was not saved")
		_check(FileAccess.file_exists(result.scene_path), "Optional AnimatedSprite2D scene was not saved")
		var frames := load(result.sprite_frames_path) as SpriteFrames
		_check(frames != null and frames.get_animation_names().size() == 2, "Library animations could not be loaded")
		if frames != null:
			_check(frames.get_frame_count(&"Idle") == 2, "Idle frame count changed")
			_check(frames.get_animation_loop(&"Idle"), "Library Idle animation should loop")
			var atlas := frames.get_frame_texture(&"Idle", 0) as AtlasTexture
			_check(atlas.region == Rect2(0, 0, 2, 2), "Unity-to-Godot atlas coordinates are incorrect")
		var packed_scene := load(result.scene_path) as PackedScene
		var instance := packed_scene.instantiate() if packed_scene != null else null
		_check(instance is AnimatedSprite2D, "Generated scene root is not AnimatedSprite2D")
		if instance != null:
			instance.free()
		var collision_result := Importer.convert_candidate(library, "res://test_output/library", true, false)
		_check(not collision_result.ok and collision_result.error.contains("already exists"), "Existing output should require overwrite approval")
		var overwritten := Importer.convert_candidate(library, "res://test_output/library", true, true)
		_check(overwritten.ok, "Approved overwrite failed")

	if clips != null:
		var result := Importer.convert_candidate(clips, "res://test_output/clips", false, false)
		_check(result.ok, "AnimationClip conversion failed: %s" % result.error)
		var frames := load(result.sprite_frames_path) as SpriteFrames
		_check(frames != null and frames.has_animation(&"Walk") and frames.has_animation(&"Attack"), "Clip animations are missing")
		if frames != null:
			_check(frames.get_frame_count(&"Walk") == 2, "Walk frame order/count changed")
			_check(is_equal_approx(frames.get_animation_speed(&"Walk"), 12.0), "AnimationClip sample rate was not preserved")
			_check(frames.get_animation_loop(&"Walk"), "AnimationClip loop flag was not preserved")
			_check(not frames.get_animation_loop(&"Attack"), "Non-looping AnimationClip changed")
			var second_frame := frames.get_frame_texture(&"Walk", 1) as AtlasTexture
			_check(second_frame.region.position.x == 2.0, "AnimationClip frame order was not preserved")

	var collision_candidates: Array[UnitySpriteCandidate] = []
	if library != null:
		collision_candidates.append(library)
	var collisions := Importer.find_collisions(collision_candidates, "res://test_output/library", true)
	_check(collisions.size() == 3, "Collision report should include texture, SpriteFrames, and scene")
	_check(Importer.scan_folder(source_root.path_join("missing")).is_empty(), "Missing folder should return no candidates")

	_remove_tree(source_root)


func _create_fixture() -> void:
	var hero_path := source_root.path_join("hero.png")
	var image := Image.create(4, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for x in 2:
		for y in 2:
			image.set_pixel(x, y, Color.RED)
	for x in range(2, 4):
		for y in 2:
			image.set_pixel(x, y, Color.BLUE)
	_check(image.save_png(hero_path) == OK, "Could not create synthetic PNG")
	_write(hero_path + ".meta", _texture_meta("test-guid"))
	_write(source_root.path_join("hero.asset"), _library_yaml())
	_write(source_root.path_join("walk.anim"), _clip_yaml("Walk", true, ["1001", "1002"]))
	_write(source_root.path_join("attack.anim"), _clip_yaml("Attack", false, ["1003", "1004"]))
	var broken := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	broken.fill(Color.WHITE)
	broken.save_png(source_root.path_join("broken.png"))
	_write(source_root.path_join("broken.asset"), _library_yaml())
	broken.save_png(source_root.path_join("malformed.png"))
	_write(source_root.path_join("malformed.png.meta"), "this is not Unity YAML")
	_write(source_root.path_join("malformed.asset"), _library_yaml())


func _texture_meta(guid: String) -> String:
	return """fileFormatVersion: 2
guid: %s
TextureImporter:
  spriteSheet:
    sprites:
    - serializedVersion: 2
      name: Idle_0
      rect:
        x: 0
        y: 0
        width: 2
        height: 2
    - serializedVersion: 2
      name: Idle_1
      rect:
        x: 2
        y: 0
        width: 2
        height: 2
    - serializedVersion: 2
      name: Attack_0
      rect:
        x: 0
        y: 0
        width: 2
        height: 2
    - serializedVersion: 2
      name: Attack_1
      rect:
        x: 2
        y: 0
        width: 2
        height: 2
  internalIDToNameTable:
  - first:
      213: 1001
    second: Idle_0
  - first:
      213: 1002
    second: Idle_1
  - first:
      213: 1003
    second: Attack_0
  - first:
      213: 1004
    second: Attack_1
""" % guid


func _library_yaml() -> String:
	return """%YAML 1.1
SpriteLibraryAsset:
  - m_Name: Idle
    m_CategoryList:
    - m_Name: Idle_0
    - m_Name: Idle_1
  - m_Name: Attack
    m_CategoryList:
    - m_Name: Attack_0
    - m_Name: Attack_1
"""


func _clip_yaml(animation_name: String, looping: bool, ids: Array[String]) -> String:
	var keys := ""
	for id in ids:
		keys += "      - time: 0\n        value: {fileID: %s, guid: test-guid, type: 3}\n" % id
	return """%%YAML 1.1
AnimationClip:
  m_Name: %s
  m_SampleRate: 12
  m_EditorCurves:
  - curve:
%s    attribute: m_Sprite
  m_AnimationClipSettings:
    m_LoopTime: %d
""" % [animation_name, keys, 1 if looping else 0]


func _write(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "Could not write fixture: %s" % path)
	if file != null:
		file.store_string(content)
		file.close()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var directory := DirAccess.open(path)
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		var child := path.path_join(entry)
		if directory.current_is_dir():
			_remove_tree(child)
		else:
			DirAccess.remove_absolute(child)
		entry = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(path)
