extends Control

## Song select. Builds one button per chart, bundled (res://songs/) and the
## player's own, made with the chart editor app (see ChartStore), so dropping a
## new JSON file in there is all it takes to add a song.

## The list grows with the charts up to this height, then scrolls.
const LIST_MAX_HEIGHT := 336.0
const ROW_HEIGHT := 48.0

@onready var _scroll: ScrollContainer = %ChartScroll
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
		empty.text = "No charts found in %s or %s" % [ChartStore.BUNDLED_DIR, ChartStore.USER_DIR]
		_list.add_child(empty)
		_scroll.custom_minimum_size.y = ROW_HEIGHT
		return

	var first: Button = null
	var rows := 0
	for path in charts:
		var chart := Chart.load_from_file(path)
		if chart == null:
			continue
		var play := Button.new()
		play.text = "%s%s   ·   %d notes   ·   %d BPM" % [
			"[mine] " if ChartStore.is_user_chart(path) else "",
			chart.title, chart.notes.size(), roundi(chart.bpm)]
		play.custom_minimum_size = Vector2(500.0, ROW_HEIGHT)
		play.pressed.connect(_on_chart_pressed.bind(path))
		_list.add_child(play)
		rows += 1
		if first == null:
			first = play

	# Rows plus the margin that keeps the focus outline from being clipped.
	var separation := _list.get_theme_constant(&"separation")
	_scroll.custom_minimum_size.y = minf(rows * (ROW_HEIGHT + separation) + 6.0, LIST_MAX_HEIGHT)
	if first != null:
		first.grab_focus()

func _on_chart_pressed(path: String) -> void:
	Sfx.play_ui()
	GameState.chart_path = path
	get_tree().change_scene_to_file.call_deferred(GameState.GAME_SCENE)

func _on_autoplay_toggled(pressed: bool) -> void:
	GameState.autoplay = pressed

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_tree().quit()
