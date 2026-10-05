class_name KeyBinds
extends RefCounted

## Registers the gameplay actions at runtime so the key layout lives in one
## readable place instead of inside project.godot. Rebind by editing the
## constants below, or add the same action names in Project Settings > Input Map
## and these defaults will step aside.

## Lane keys, left to right. Physical codes, so the layout holds on AZERTY too.
const LANE_KEYS: Array[int] = [KEY_D, KEY_F, KEY_J, KEY_K, KEY_S, KEY_L]

const ACTION_KEYS := {
	&"restart": KEY_R,
	&"toggle_autoplay": KEY_F1,
}

static func lane_action(lane: int) -> StringName:
	return StringName("lane_%d" % lane)

## Call once before reading any lane input.
static func ensure_actions(lane_count: int) -> void:
	for lane in lane_count:
		_add_action(lane_action(lane), LANE_KEYS[lane % LANE_KEYS.size()])
	for action: StringName in ACTION_KEYS:
		_add_action(action, ACTION_KEYS[action])

## Human-readable key names for the on-screen hint, e.g. "D F J K".
static func lane_hint(lane_count: int) -> String:
	var names: PackedStringArray = []
	for lane in lane_count:
		names.append(OS.get_keycode_string(LANE_KEYS[lane % LANE_KEYS.size()]))
	return " ".join(names)

static func _add_action(action: StringName, keycode: int) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	InputMap.action_add_event(action, event)
