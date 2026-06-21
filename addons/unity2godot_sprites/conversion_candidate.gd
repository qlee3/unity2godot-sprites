@tool
class_name UnitySpriteCandidate
extends RefCounted

enum SourceKind {
	SPRITE_LIBRARY,
	ANIMATION_CLIPS,
}

var selected := true
var source_kind := SourceKind.SPRITE_LIBRARY
var display_name := ""
var texture_path := ""
var meta_path := ""
var library_path := ""
var animation_paths: PackedStringArray = []
var animation_count := 0
var frame_count := 0
var warnings: PackedStringArray = []


func stable_id() -> String:
	return "%d:%s:%s" % [source_kind, texture_path, library_path]


func kind_label() -> String:
	return "Sprite Library" if source_kind == SourceKind.SPRITE_LIBRARY else "Animation Clips"


func is_valid() -> bool:
	return warnings.is_empty() and not texture_path.is_empty() and not meta_path.is_empty()

