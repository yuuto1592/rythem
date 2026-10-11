extends Control

## Shows the dictionary the game scene left in GameState.last_result.

@onready var _song: Label = %SongLabel
@onready var _grade: Label = %GradeLabel
@onready var _score: Label = %ScoreLabel
@onready var _summary: Label = %SummaryLabel
@onready var _breakdown: VBoxContainer = %Breakdown
@onready var _retry: Button = %RetryButton
@onready var _menu: Button = %MenuButton

func _ready() -> void:
	_retry.pressed.connect(_on_retry)
	_menu.pressed.connect(_on_menu)
	_retry.grab_focus()
	_render(GameState.last_result)

func _render(result: Dictionary) -> void:
	if result.is_empty():
		_song.text = "No result to show"
		_grade.text = "-"
		_score.text = ""
		_summary.text = ""
		return

	var artist := str(result.get("artist", ""))
	_song.text = str(result.get("title", "?")) if artist.is_empty() \
			else "%s — %s" % [result.get("title", "?"), artist]
	_grade.text = str(result.get("grade", "-"))
	_score.text = "%07d" % int(result.get("score", 0))

	var parts: PackedStringArray = []
	parts.append("Accuracy %.2f%%" % (float(result.get("accuracy", 0.0)) * 100.0))
	parts.append("Max combo %d / %d" % [int(result.get("max_combo", 0)), int(result.get("judgement_count", 0))])
	if bool(result.get("full_combo", false)):
		parts.append("FULL COMBO")
	if bool(result.get("autoplay", false)):
		parts.append("(autoplay)")
	_summary.text = "   ·   ".join(parts)

	var counts: Dictionary = result.get("counts", {})
	for child in _breakdown.get_children():
		child.queue_free()
	for rank in Judge.RANK_NAME:
		var row := Label.new()
		row.text = "%s   ×   %d" % [Judge.RANK_NAME[rank], int(counts.get(rank, 0))]
		row.add_theme_color_override(&"font_color", Judge.RANK_COLOR[rank])
		_breakdown.add_child(row)

func _on_retry() -> void:
	Sfx.play_ui()
	get_tree().change_scene_to_file.call_deferred(GameState.GAME_SCENE)

func _on_menu() -> void:
	Sfx.play_ui()
	get_tree().change_scene_to_file.call_deferred(GameState.MENU_SCENE)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		_on_menu()
