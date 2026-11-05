extends TestCase

## Where backing out of a run leads. Restores the autoload's state afterwards.

func test_exit_goes_to_the_editor_only_during_a_test_play() -> void:
	var saved_doc := GameState.editor_doc
	var saved_state := GameState.editor_state.duplicate()

	GameState.clear_editor_session()
	check_eq(GameState.exit_scene(), GameState.MENU_SCENE, "no test play from the editor: song select")
	GameState.editor_doc = ChartDoc.new()
	check_eq(GameState.exit_scene(), GameState.EDITOR_SCENE, "test playing from the editor: back to it")
	GameState.clear_editor_session()
	check_eq(GameState.exit_scene(), GameState.MENU_SCENE, "session handed back")
	check(GameState.editor_state.is_empty(), "nothing left over")

	GameState.editor_doc = saved_doc
	GameState.editor_state = saved_state
