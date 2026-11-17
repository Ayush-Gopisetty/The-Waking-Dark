class_name Daniel
extends CharacterRig
## Daniel Mercer, rendered from assets/models/daniel.glb and animated by
## CharacterRig (idle breathing, walk cycle, cutscene gestures). Act 1 only
## needs him at a few fixed spots, so he is moved by the level, not by AI.
## Spirits stay out of GameState.DANIEL_REPEL_RADIUS around him.

## Set by cutscenes; while true Daniel doesn't turn or pick where to look on his own.
var directed := false

var _walk_dir := Vector3.ZERO
var _tween: Tween


func _init() -> void:
	model_path = "res://assets/models/daniel.glb"
	bandaged_left = true
	speaker_name = "Daniel"
	fidgets = true


func _process(delta: float) -> void:
	if visible:
		GameState.daniel_position = global_position
	if _last_pos != Vector3.INF:
		var step := Vector3(global_position.x - _last_pos.x, 0, global_position.z - _last_pos.z)
		if step.length() > 0.0005:
			_walk_dir = step.normalized()
	var walking := _speed > 0.3
	var player := GameState.player
	if player != null and visible and not directed:
		var to := (_walk_dir if walking else player.global_position - global_position)
		if to.length() > 0.01:
			var yaw := atan2(-to.x, -to.z)
			rotation.y = lerp_angle(rotation.y, yaw, minf(1.0, (6.0 if walking else 1.5) * delta))
		look_target = Vector3.INF if walking else player.camera.global_position
	super(delta)


## Moves Daniel (instantly, or walking over `seconds`).
func move_to(pos: Vector3, seconds: float = 0.0) -> void:
	if _tween != null:
		_tween.kill()
	if seconds <= 0.0:
		global_position = pos
		_last_pos = Vector3.INF
		return
	_tween = create_tween()
	# Constant speed: the legs are driven by distance travelled, so an eased start and
	# stop made the body slide before the feet had begun to step.
	_tween.tween_property(self, "global_position", pos, seconds).set_trans(Tween.TRANS_LINEAR)


func _exit_tree() -> void:
	GameState.daniel_position = Vector3.INF
