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
## The chart open in the chart editor app while it test plays, so the editor
## comes back exactly as it was, undo history included. Null otherwise.
var editor_doc: ChartDoc = null
## The rest of the editor's state to restore after a test play (file, cursor,
## zoom...). See ChartEditor.
var editor_state := {}

## Where the game and the result screen go when the player backs out: the
## editor during a test play, song select otherwise.
func exit_scene() -> String:
	return EDITOR_SCENE if editor_doc != null else MENU_SCENE

## Forgets the test play's editor session (the editor has taken it back).
func clear_editor_session() -> void:
	editor_doc = null
	editor_state = {}
	play_from_time = 0.0

## Closing the chart editor's window during a test play goes back to the
## editor first if there are unsaved changes, so they can be saved. (The
## editor turns off quitting on close; this decides for it meanwhile.)
func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_CLOSE_REQUEST or editor_doc == null:
		return
	if editor_doc.modified:
		editor_state["quit_requested"] = true
		get_tree().change_scene_to_file.call_deferred(EDITOR_SCENE)
	else:
		get_tree().quit()

## Every chart, bundled and the player's own. See ChartStore.
func list_charts() -> PackedStringArray:
	return ChartStore.list_charts()
