class_name Hud
extends Control

## Read-only view of the run. The game pushes values in; the HUD never reads
## game state back out.

const JUDGEMENT_HOLD := 0.35

@onready var _song: Label = %SongLabel
@onready var _score: Label = %ScoreLabel
@onready var _combo: Label = %ComboLabel
@onready var _judgement: Label = %JudgementLabel
@onready var _accuracy: Label = %AccuracyLabel
@onready var _hint: Label = %HintLabel
@onready var _autoplay: Label = %AutoplayLabel
@onready var _progress: ProgressBar = %ProgressBar

var _judgement_timer := 0.0

func _ready() -> void:
	_combo.text = ""
	_judgement.modulate.a = 0.0

func set_song(title: String, artist: String) -> void:
	_song.text = title if artist.is_empty() else "%s — %s" % [title, artist]

func set_hint(text: String) -> void:
	_hint.text = text

func set_autoplay(enabled: bool) -> void:
	_autoplay.visible = enabled

func set_score(score: int) -> void:
	_score.text = "%07d" % score

func set_accuracy(accuracy: float) -> void:
	_accuracy.text = "%.2f%%" % (accuracy * 100.0)

func set_combo(combo: int) -> void:
	_combo.text = str(combo) if combo >= 2 else ""

func set_progress(ratio: float) -> void:
	_progress.value = clampf(ratio, 0.0, 1.0)

func show_judgement(rank: Judge.Rank) -> void:
	_judgement.text = Judge.RANK_NAME[rank]
	_judgement.modulate = Judge.RANK_COLOR[rank]
	_judgement_timer = JUDGEMENT_HOLD

func _process(delta: float) -> void:
	if _judgement_timer <= 0.0:
		return
	_judgement_timer = maxf(_judgement_timer - delta, 0.0)
	_judgement.modulate.a = minf(_judgement_timer / (JUDGEMENT_HOLD * 0.5), 1.0)
