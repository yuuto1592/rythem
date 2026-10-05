extends Control

## Song select. Builds one button per chart in res://songs/ so dropping a new
## JSON file in there is all it takes to add a song.

@onready var _list: VBoxContainer = %ChartList
@onready var _autoplay: CheckBox = %AutoplayCheck
@onready var _hint: Label = %HintLabel

func _ready() -> void:
	_autoplay.button_pressed = GameState.autoplay
	_autoplay.toggled.connect(_on_autoplay_toggled)
	_hint.text = "Lane keys: %s" % KeyBinds.lane_hint(4)
	_populate()

func _populate() -> void:
	for child in _list.get_children():
		child.queue_free()

	var charts := GameState.list_charts()
	if charts.is_empty():
		var empty := Label.new()
		empty.text = "No charts found in %s" % GameState.SONGS_DIR
		_list.add_child(empty)
		return

	for path in charts:
		var chart := Chart.load_from_file(path)
		if chart == null:
			continue
		var button := Button.new()
		button.text = "%s   ·   %d notes   ·   %d BPM" % [chart.title, chart.notes.size(), roundi(chart.bpm)]
		button.custom_minimum_size = Vector2(420.0, 48.0)
		button.pressed.connect(_on_chart_pressed.bind(path))
		_list.add_child(button)

	if _list.get_child_count() > 0:
		(_list.get_child(0) as Control).grab_focus()

func _on_chart_pressed(path: String) -> void:
	Sfx.play_ui()
	GameState.chart_path = path
	get_tree().change_scene_to_file.call_deferred(GameState.GAME_SCENE)

func _on_autoplay_toggled(pressed: bool) -> void:
	GameState.autoplay = pressed

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_tree().quit()
