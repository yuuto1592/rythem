extends Node

## Autoload. The handful of values that have to survive a scene change.

const MENU_SCENE := "res://scenes/main_menu.tscn"
const GAME_SCENE := "res://scenes/game.tscn"
const RESULT_SCENE := "res://scenes/result.tscn"
const SONGS_DIR := "res://songs"

## Chart the next run will play.
var chart_path := "res://songs/01_warm_up.json"
## When true the game hits every note for you. Handy for checking a new chart.
var autoplay := false
## Filled in by the game scene, read by the result screen. See Game._build_result().
var last_result := {}

## Every chart in [constant SONGS_DIR], sorted by file name.
func list_charts() -> PackedStringArray:
	var paths: PackedStringArray = []
	for file in DirAccess.get_files_at(SONGS_DIR):
		# Exported projects see the imported name, so tolerate both.
		var file_name := file.trim_suffix(".remap")
		if file_name.ends_with(".json"):
			paths.append("%s/%s" % [SONGS_DIR, file_name])
	paths.sort()
	return paths
