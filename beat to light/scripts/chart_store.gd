class_name ChartStore
extends RefCounted

## Where charts and their music live, and how they are read and written.
##
## Bundled charts are in res://songs. Run from the Godot editor, that folder is
## writable, so charts made there land in the project (and can be committed).
## An exported build cannot write to res://, so the chart editor app saves to
## user://songs instead (on Windows: %APPDATA%\Godot\app_userdata\beat to
## light\songs), which the game and the editor app share. Song select lists
## both folders.

const BUNDLED_DIR := "res://songs"
const USER_DIR := "user://songs"

## Where new charts are saved by default.
static func writable_dir() -> String:
	return BUNDLED_DIR if OS.has_feature("editor") else USER_DIR

## False for the bundled charts in an exported build, which are read-only.
static func is_writable(path: String) -> bool:
	return not path.begins_with("res://") or OS.has_feature("editor")

## Every chart: the bundled ones first, then the player's own. Each group is
## sorted by file name.
static func list_charts() -> PackedStringArray:
	var paths := list_charts_in(BUNDLED_DIR)
	paths.append_array(list_charts_in(USER_DIR))
	return paths

static func list_charts_in(dir: String) -> PackedStringArray:
	var paths: PackedStringArray = []
	if not DirAccess.dir_exists_absolute(dir):
		return paths
	for file in DirAccess.get_files_at(dir):
		# Exported projects can list the remapped name, so tolerate both.
		var file_name := file.trim_suffix(".remap")
		if file_name.ends_with(".json"):
			paths.append(dir.path_join(file_name))
	paths.sort()
	return paths

static func is_user_chart(path: String) -> bool:
	return path.begins_with("user://")

## A safe file name from whatever was typed: "My Song #2" -> "my_song_2".
static func file_name_for(text: String) -> String:
	var out := ""
	for c in text.strip_edges().to_lower():
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_" or c == "-":
			out += c
		elif not out.ends_with("_"):
			out += "_"
	out = out.trim_prefix("_").trim_suffix("_")
	return out if not out.is_empty() else "chart"

## Writes [param doc] to [param path], with [param music] in its music field
## when given. Returns false if the file could not be written.
static func write_chart(doc: ChartDoc, path: String, music := "") -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(doc.to_json_text(music))
	file.close()
	return true

## What the music field should say for a chart saved to [param new_chart_path],
## whose music is [param music] as seen from [param old_chart_path]. Music kept
## elsewhere is copied next to the chart, so the two travel together. If it
## cannot be copied (music bundled inside an exported game), it is referred to
## by its full path instead.
static func music_for(new_chart_path: String, old_chart_path: String, music: String) -> String:
	if music.is_empty():
		return ""
	var source := resolve_music(old_chart_path, music)
	var dir := new_chart_path.get_base_dir()
	if _same_path(source.get_base_dir(), dir):
		return source.get_file()
	var copied := import_music(source, dir)
	return copied if not copied.is_empty() else source

## Where a chart's music is: a path with a scheme (res://, user://) or an
## absolute path is used as is; a bare file name sits next to the chart.
static func resolve_music(chart_path: String, music: String) -> String:
	if music.is_empty():
		return ""
	if music.contains("://") or music.is_absolute_path():
		return music
	return chart_path.get_base_dir().path_join(music)

## Loads a chart's music, or returns null if there is none or it cannot be read.
static func load_music(chart_path: String, music: String) -> AudioStream:
	var path := resolve_music(chart_path, music)
	if path.is_empty():
		return null
	# Music shipped with the game has been imported; load it as a resource.
	if ResourceLoader.exists(path):
		var stream := ResourceLoader.load(path) as AudioStream
		if stream != null:
			return stream
	# Anything else (copied in by the editor) is read straight from the file.
	if path.get_extension().to_lower() == "ogg" and FileAccess.file_exists(path):
		return AudioStreamOggVorbis.load_from_file(path)
	return null

## Copies a music file from anywhere on disk into [param dir] (default: the
## writable folder). Returns the name to put in the chart's "music" field, or
## "" on failure. A different file already there under the same name is left
## alone; the copy gets a numbered name instead ("song_2.ogg").
static func import_music(source: String, dir := "") -> String:
	var target_dir := dir if not dir.is_empty() else writable_dir()
	if not FileAccess.file_exists(source):
		return ""
	DirAccess.make_dir_recursive_absolute(target_dir)
	var base := source.get_file().get_basename()
	var extension := source.get_extension()
	var file_name := source.get_file()
	var n := 1
	while FileAccess.file_exists(target_dir.path_join(file_name)):
		var existing := target_dir.path_join(file_name)
		if _same_path(existing, source) or FileAccess.get_md5(existing) == FileAccess.get_md5(source):
			return file_name  # already there
		n += 1
		file_name = "%s_%d.%s" % [base, n, extension]
	var err := DirAccess.copy_absolute(source, target_dir.path_join(file_name))
	if err != OK:
		push_error("Could not copy %s to %s: %s" % [source, target_dir, error_string(err)])
		return ""
	return file_name

static func _same_path(a: String, b: String) -> bool:
	return ProjectSettings.globalize_path(a).simplify_path() == ProjectSettings.globalize_path(b).simplify_path()
