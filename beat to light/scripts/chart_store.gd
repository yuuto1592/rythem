class_name ChartStore
extends RefCounted

## Where charts and their music live, and how they are read and written.
##
## Bundled charts are in res://songs. Run from the Godot editor, that folder is
## writable, so charts made there land in the project (and can be committed).
## An exported game cannot write to res://, so it saves to user://songs instead
## (on Windows: %APPDATA%\Godot\app_userdata\beat to light\songs). Song select
## lists both.

const BUNDLED_DIR := "res://songs"
const USER_DIR := "user://songs"

## Where new and edited charts are saved.
static func writable_dir() -> String:
	return BUNDLED_DIR if OS.has_feature("editor") else USER_DIR

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

## Writes [param doc] as [param file_name].json in [param dir] (default: the
## writable folder). Returns the path written, or "" on failure.
static func save(doc: ChartDoc, file_name: String, dir := "") -> String:
	var target_dir := dir if not dir.is_empty() else writable_dir()
	DirAccess.make_dir_recursive_absolute(target_dir)
	var path := target_dir.path_join(file_name_for(file_name) + ".json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return ""
	file.store_string(doc.to_json_text())
	file.close()
	return path

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

## Copies an .ogg from anywhere on disk next to the charts in [param dir]
## (default: the writable folder). Returns the name to put in the chart's
## "music" field, or "" on failure.
static func import_music(source: String, dir := "") -> String:
	var target_dir := dir if not dir.is_empty() else writable_dir()
	DirAccess.make_dir_recursive_absolute(target_dir)
	var file_name := source.get_file()
	var dest := target_dir.path_join(file_name)
	if ProjectSettings.globalize_path(dest) == ProjectSettings.globalize_path(source):
		return file_name
	var err := DirAccess.copy_absolute(source, dest)
	if err != OK:
		push_error("Could not copy %s to %s: %s" % [source, dest, error_string(err)])
		return ""
	return file_name
