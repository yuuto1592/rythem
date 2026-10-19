extends Node

## Autoload. The handful of values that have to survive a scene change.

const MENU_SCENE := "res://scenes/main_menu.tscn"
const GAME_SCENE := "res://scenes/game.tscn"
const RESULT_SCENE := "res://scenes/result.tscn"
const EDITOR_SCENE := "res://scenes/editor.tscn"

## Chart the next run will play.
var chart_path := "res://songs/01_warm_up.json"
## When true the game hits every note for you. Handy for checking a new chart.
var autoplay := false
## Filled in by the game scene, read by the result screen. See Game._build_result().
var last_result := {}
## Chart time the next run starts from (the editor's "Test from here"); 0 plays
## the whole chart.
var play_from_time := 0.0
## The chart open in the editor while a test play runs, so the editor comes back
## exactly as it was, undo history included. Null when the editor is not in use.
var editor_doc: ChartDoc = null
## The rest of the editor's state: what to open, and what to restore after a
## test play (file name, cursor, zoom...). See ChartEditor.
var editor_state := {}

## Where the game and the result screen go when the player backs out: the
## editor while one is open, song select otherwise.
func exit_scene() -> String:
	return EDITOR_SCENE if editor_doc != null else MENU_SCENE

## Opens the editor on [param path], or on a new chart when it is empty.
func open_editor(path: String) -> void:
	editor_doc = null
	editor_state = {"open_path": path}
	play_from_time = 0.0

## Forgets the editor session (called when leaving the editor for song select).
func close_editor() -> void:
	editor_doc = null
	editor_state = {}
	play_from_time = 0.0

## Every chart, bundled and the player's own. See ChartStore.
func list_charts() -> PackedStringArray:
	return ChartStore.list_charts()
