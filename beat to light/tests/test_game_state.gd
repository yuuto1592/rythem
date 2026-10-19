extends TestCase

## Where backing out of a run leads. Restores the autoload's state afterwards.

func test_exit_goes_to_the_editor_only_while_one_is_open() -> void:
	var saved_doc := GameState.editor_doc
	var saved_state := GameState.editor_state.duplicate()

	GameState.close_editor()
	check_eq(GameState.exit_scene(), GameState.MENU_SCENE, "no editor: song select")
	GameState.editor_doc = ChartDoc.new()
	check_eq(GameState.exit_scene(), GameState.EDITOR_SCENE, "editor open: back to it")
	GameState.close_editor()
	check_eq(GameState.exit_scene(), GameState.MENU_SCENE, "editor closed again")

	GameState.open_editor("res://songs/01_warm_up.json")
	check_eq(GameState.editor_state.get("open_path"), "res://songs/01_warm_up.json", "remembers what to open")
	check(GameState.editor_doc == null, "opening starts without a document")

	GameState.editor_doc = saved_doc
	GameState.editor_state = saved_state
