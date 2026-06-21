@tool
class_name UnitySpriteConversionResult
extends RefCounted

var ok := false
var candidate_name := ""
var animation_count := 0
var frame_count := 0
var texture_path := ""
var sprite_frames_path := ""
var scene_path := ""
var error := ""
var warnings: PackedStringArray = []


static func failure(name: String, message: String) -> UnitySpriteConversionResult:
	var result := UnitySpriteConversionResult.new()
	result.candidate_name = name
	result.error = message
	return result

