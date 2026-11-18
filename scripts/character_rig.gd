class_name CharacterRig
extends Node3D
## A rigged character model (the humanoid .glb skeletons exported from Blender)
## animated procedurally: relaxed arms, breathing, weight shifts, a walk cycle
## driven by how fast the rig moves, head look-at, and gestures for cutscenes.
## The models ship in an A-pose with no animations, so every pose is solved here
## with two-bone IK on the arms and legs.
##
## Skeleton space: the character faces +Z, their left is +X, feet at y = 0.
## The rig node itself faces -Z (Godot's forward), so the model is turned 180°.

## Gestures. Each one sets where the hands go; the rig blends between them.
enum Gesture { IDLE, TALK, CALM, SHOW_HAND, POINT, TOUCH_HEAD, AFTER_YOU, FLASHLIGHT, STARTLE }

const GESTURE_NAMES := {
	"idle": Gesture.IDLE, "talk": Gesture.TALK, "calm": Gesture.CALM,
	"show_hand": Gesture.SHOW_HAND, "point": Gesture.POINT, "touch_head": Gesture.TOUCH_HEAD,
	"after_you": Gesture.AFTER_YOU, "flashlight": Gesture.FLASHLIGHT, "startle": Gesture.STARTLE,
}

## Path of the .glb to load.
@export var model_path := ""
## Uniform scale for the model (Jason is shrunk so his eyes meet the player camera).
@export var model_scale := 1.0
## Which hand is bandaged (Daniel's left); SHOW_HAND raises it.
@export var bandaged_left := true
## Hides the head (first person) but keeps a full-body shadow.
var first_person := false:
	set(value):
		first_person = value
		_apply_first_person()
## World point to look at, or Vector3.INF to look ahead.
var look_target := Vector3.INF
## World point for POINT; world point the hand holds for FLASHLIGHT.
var gesture_target := Vector3.INF
## 0 standing, 1 full crouch.
var crouch := 0.0

var gesture: Gesture = Gesture.IDLE
var skeleton: Skeleton3D
var model: Node3D

var _shadow_model: Node3D
var _shadow_skeleton: Skeleton3D
var _time := 0.0
var _gesture_time := 0.0
var _phase := 0.0
var _walk := 0.0  # 0..1 blend into the walk cycle
var _last_pos := Vector3.INF
var _speed := 0.0
var _seed := 0.0
# Smoothed IK targets (skeleton space).
var _hand: Dictionary[String, Vector3] = {"L": Vector3.ZERO, "R": Vector3.ZERO}
var _pole: Dictionary[String, Vector3] = {"L": Vector3.ZERO, "R": Vector3.ZERO}
var _palm: Dictionary[String, Vector3] = {"L": Vector3.LEFT, "R": Vector3.RIGHT}
var _finger: Dictionary[String, float] = {"L": 0.35, "R": 0.35}
var _twist: Dictionary[String, float] = {"L": 0.0, "R": 0.0}
var _finger_open: Dictionary[String, float] = {"L": 1.0, "R": 1.0}
var _wrist_bend: Dictionary[String, Quaternion] = {"L": Quaternion.IDENTITY, "R": Quaternion.IDENTITY}
var _dt := 0.0
var _chest_twist := 0.0
var _last_yaw := INF
var _turn_rate := 0.0
var _shuffle := 0.0
var _hand_vel: Dictionary[String, Vector3] = {"L": Vector3.ZERO, "R": Vector3.ZERO}
var _pointing: Dictionary[String, bool] = {"L": false, "R": false}
## Which hand does the talking this line.
var _talk_hand := "R"
var _look := Vector2.ZERO  # yaw, pitch (radians, character space)
var _lean := 0.0
var _initialised := false
var _b: Dictionary[String, int] = {}  # bone name -> index
var _len: Dictionary[String, float] = {}  # "L_upper" etc -> length
## Palm normal in each hand bone's own space (measured from the finger roots).
var _palm_local: Dictionary[String, Vector3] = {"L": Vector3.RIGHT, "R": Vector3.LEFT}
## Per finger bone: the local axis that bends it toward the palm, and the one
## that spreads it sideways.
var _curl_axis: Dictionary[int, Vector3] = {}
var _spread_axis: Dictionary[int, Vector3] = {}
## Per hand, in the hand bone's space: index-to-little direction reversed (out of
## the thumb side), and the wrist-to-middle-knuckle vector.
var _across_local: Dictionary[String, Vector3] = {"L": Vector3.FORWARD, "R": Vector3.FORWARD}
var _knuckle_local: Dictionary[String, Vector3] = {"L": Vector3.UP * 0.09, "R": Vector3.UP * 0.09}

## Flashlight grip (right hand). Set each frame by the player while it's held in
## first person: the world point on the barrel's axis where the palm holds it,
## the barrel direction (toward the lens), and the way the palm faces.
var grip_point := Vector3.INF
var grip_axis := Vector3.FORWARD
var grip_palm := Vector3.LEFT
## Finger curl around the barrel (wraps it without sinking in).
const GRIP_CURL := 1.45
## Barrel centre from the hand bone's line, along the palm normal (skeleton units).
const GRIP_DEPTH := 0.032
## How far toward the knuckles the barrel sits (0 wrist, 1 knuckles).
const GRIP_ALONG := 0.8
## Most the wrist bends (radians) to aim the barrel beyond what the forearm gives.
const GRIP_WRIST_MAX := 0.5
## Where the elbow points while holding the light, from the wrist (skeleton space:
## -X is his right, -Y down, +Z forward).
const GRIP_ELBOW := Vector3(-0.3, -0.65, -0.1)
## Barrel angle across the fist (radians from square to the knuckles).
const GRIP_OBLIQUE := 0.45
## Thumb joint's distance from the barrel axis (barrel radius + thumb, skeleton units).
const GRIP_THUMB_REST := 0.028
var _grip_basis := Basis.IDENTITY
## The right forearm's direction last frame (skeleton space), for rolling the grip.
var _grip_forearm := Vector3(0.4, 0.75, 0.5).normalized()
## True while the right hand carries the flashlight (any gesture): the fingers
## stay wrapped round it, and one-handed gestures use the left hand instead.
var holding := false

## Name shown on subtitles for this character ("Daniel"); their lines move the jaw.
@export var speaker_name := ""
## Prop model (see Props) for the ID card; look_at_id() lifts it up in the free
## hand (the one without the flashlight), studies it and puts it away.
@export var id_model := ""
var _id_card: Node3D
## Seconds into taking out / reading / putting away the ID (-1 when not).
var _id_time := -1.0
## Seconds the card is held up to read, and the whole animation's length.
var _id_hold := 3.5
var _id_len := 6.4
## Small idle behaviours (holding the hurt hand, clasping hands, glancing round).
@export var fidgets := false
# Speech: a jaw-open timeline built from the line's text.
var _speech: Array[Vector2] = []  # (time, openness)
var _speech_time := 0.0
var _speech_len := 0.0
var _jaw := 0.0
var _jaw_vel := 0.0
var _talk_energy := 0.0  # smoothed loudness, drives nods and hand beats
var _talk_style := 0
# Idle fidgets.
var _fidget := ""
var _fidget_time := 0.0
var _fidget_len := 0.0
var _fidget_wait := 4.0
var _glance_side := 1.0
# Body volumes the arms must stay out of (measured from the meshes at load).
# Torso: elliptical slices [height, half-width, front z, back z] in rest pose.
var _torso: Array[Vector4] = []
var _torso_lo := 0.0
## Metres the body travels per step. The planted foot slides back by exactly
## this much (see _foot_target), so the feet grip the floor instead of skating.
const STEP_LENGTH := 0.6
## Foot spacing, centre to centre (half-width, skeleton units). The A-pose rest
## has the feet at 0.20, far outside the hips (0.115): they stand under the hips.
const STANCE_STAND := 0.108
const STANCE_WALK := 0.085
var _torso_step := 0.04
var _thigh_radius := 0.09
## The head (with hair) as an ellipsoid in the Head bone's rest space: centre and radii.
var _head_c := Vector3.ZERO
var _head_r := Vector3(0.09, 0.12, 0.1)
var _tip_dir: Dictionary[String, Vector3] = {"L": Vector3.DOWN, "R": Vector3.DOWN}
var _pole_push: Dictionary[String, Vector3] = {"L": Vector3.ZERO, "R": Vector3.ZERO}


func _ready() -> void:
	_seed = randf() * 100.0
	var scene: PackedScene = load(model_path)
	if scene == null:
		push_error("CharacterRig: could not load %s (open the project in the Godot editor once to import it)" % model_path)
		return
	model = _instance(scene)
	_smooth_hair(model)
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	for i in skeleton.get_bone_count():
		_b[skeleton.get_bone_name(i)] = i
	for side in ["Left", "Right"]:
		var s: String = side[0]
		_len[s + "_upper"] = _rest(side + "UpperArm").distance_to(_rest(side + "LowerArm"))
		_len[s + "_lower"] = _rest(side + "LowerArm").distance_to(_rest(side + "Hand"))
		_len[s + "_thigh"] = _rest(side + "UpperLeg").distance_to(_rest(side + "LowerLeg"))
		_len[s + "_shin"] = _rest(side + "LowerLeg").distance_to(_rest(side + "Foot"))
		_measure_hand(side, s)
	_measure_body()
	if bandaged_left:
		_attach_bandage("Left", "L")
	_apply_first_person()
	if not speaker_name.is_empty():
		GameState.line_shown.connect(_on_line_shown)
	_pose(0.0)


## The bandage on Daniel's hand: a gauze wrap around the wrist and palm, soaked through
## with blood (assets/models/daniel_bandage.png), riding on the hand bone. (The model's
## own small wrist band sits hidden under the cuff, so it is switched off.)
func _attach_bandage(side: String, s: String) -> void:
	if not _b.has(side + "Hand") or not _knuckle_local.has(s):
		return
	for mesh: MeshInstance3D in model.find_children("*Bandage*", "MeshInstance3D", true, false):
		mesh.visible = false
	var along: Vector3 = _knuckle_local[s].normalized()
	# (the stored palm normal for this bone points out of the back of the hand)
	var palm: Vector3 = -(_palm_local[s] - along * _palm_local[s].dot(along)).normalized()
	var across := along.cross(palm).normalized()
	var attach := BoneAttachment3D.new()
	attach.bone_name = side + "Hand"
	skeleton.add_child(attach)
	var wrap := MeshInstance3D.new()
	wrap.mesh = _bandage_mesh()
	wrap.basis = Basis(across, along, palm)  # mesh: x across the hand, y toward the knuckles, z out of the palm
	wrap.position = palm * 0.014 + along * 0.008  # the bone runs nearer the back of the hand than its middle
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/models/daniel_bandage.png")
	mat.roughness = 0.95
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	wrap.material_override = mat
	attach.add_child(wrap)


## A lumpy elliptical tube (wrist -> knuckles), slightly bulged over the palm, with
## rolled ends. UV: u around the wrap, v along it.
func _bandage_mesh() -> ArrayMesh:
	var rings := 16
	var segments := 28
	var y0 := -0.05
	var y1 := 0.092
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grid: Array = []
	for i in rings + 1:
		var t := float(i) / rings
		var y := lerpf(y0, y1, t)
		# Narrow at the wrist, wider across the palm; the ends roll out a little.
		var width := lerpf(0.036, 0.054, smoothstep(0.1, 0.6, t)) * (1.0 + 0.1 * (1.0 - smoothstep(0.0, 0.08, t)) + 0.06 * smoothstep(0.92, 1.0, t))
		var thick := lerpf(0.032, 0.04, smoothstep(0.1, 0.6, t)) * (1.0 + 0.1 * (1.0 - smoothstep(0.0, 0.08, t)))
		var row: Array = []
		for j in segments + 1:
			var a := TAU * float(j) / segments
			var lump := 1.0 + 0.04 * sin(a * 3.0 + t * 9.0) + 0.03 * sin(t * 23.0 + a * 5.0)
			row.append(Vector3(cos(a) * width * lump, y, sin(a) * thick * lump))
		grid.append(row)
	for i in rings:
		for j in segments:
			var a: Vector3 = grid[i][j]
			var b: Vector3 = grid[i][j + 1]
			var c: Vector3 = grid[i + 1][j]
			var d: Vector3 = grid[i + 1][j + 1]
			var uv_a := Vector2(float(j) / segments, float(i) / rings)
			var uv_b := Vector2(float(j + 1) / segments, float(i) / rings)
			var uv_c := Vector2(float(j) / segments, float(i + 1) / rings)
			var uv_d := Vector2(float(j + 1) / segments, float(i + 1) / rings)
			for tri: Array in [[a, b, c, uv_a, uv_b, uv_c], [b, d, c, uv_b, uv_d, uv_c]]:
				for k in 3:
					st.set_uv(tri[3 + k])
					st.add_vertex(tri[k])
	st.generate_normals()
	return st.commit()


## Measures the clothed torso (elliptical slices from the hips to the armpits)
## and the thighs from the model's own vertices, so the arms can be kept outside.
func _measure_body() -> void:
	var lo := _rest("Hips").y - 0.14
	var armpit := _rest("LeftUpperArm").y - 0.07
	var hi := _rest("Neck").y + 0.03  # up to the base of the neck, so a hand on the back of the neck is covered too
	var n := int((hi - lo) / _torso_step) + 1
	var rx: Array[float] = []
	var zf: Array[float] = []
	var zb: Array[float] = []
	for i in n:
		rx.append(0.0)
		zf.append(-INF)
		zb.append(INF)
	var thigh_a := _rest("LeftUpperLeg")
	var thigh_b := _rest("LeftLowerLeg")
	var thigh_d: Array[float] = []
	var head_rest := skeleton.get_bone_global_rest(_b["Head"])
	var head_inv := head_rest.affine_inverse()
	var head_lo := Vector3(INF, INF, INF)
	var head_hi := Vector3(-INF, -INF, -INF)
	var to_skel := skeleton.global_transform.affine_inverse()
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var lname := String(mesh.name).to_lower()
		var xf := to_skel * mesh.global_transform
		if lname.contains("body") or lname.contains("hair"):
			# The head (skin and hair) above the base of the skull, for the arm to avoid.
			for s in mesh.mesh.get_surface_count():
				for v: Vector3 in mesh.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
					var w := xf * v
					if w.y >= head_rest.origin.y - 0.02 and absf(w.x) < 0.16:
						var q := head_inv * w
						head_lo = head_lo.min(q)
						head_hi = head_hi.max(q)
		if lname.contains("hair") or lname.contains("eye") or lname.contains("teeth") or lname.contains("tongue") or lname.contains("high-poly"):
			continue
		for s in mesh.mesh.get_surface_count():
			var verts: PackedVector3Array = mesh.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for v in verts:
				var p := xf * v
				# Above the armpits only the shoulders and neck count, not the upper arms.
				var reach_x := 0.26 if p.y <= armpit else lerpf(0.22, 0.085, clampf((p.y - armpit) / maxf(hi - armpit, 0.01), 0.0, 1.0))
				if p.y >= lo and p.y <= hi and absf(p.x) < reach_x:
					var i := int((p.y - lo) / _torso_step)
					rx[i] = maxf(rx[i], absf(p.x))
					zf[i] = maxf(zf[i], p.z)
					zb[i] = minf(zb[i], p.z)
				if p.x > 0.0:
					var c := Geometry3D.get_closest_point_to_segment(p, thigh_a, thigh_b)
					var along := (c - thigh_a).length() / maxf(0.01, thigh_a.distance_to(thigh_b))
					var d := p.distance_to(c)
					if along > 0.4 and along < 0.8 and d < 0.16:
						thigh_d.append(d)
	_torso.clear()
	_torso_lo = lo
	for i in n:
		if zf[i] == -INF:
			_torso.append(_torso[i - 1] if i > 0 else Vector4(lo, 0.15, 0.1, -0.1))
		else:
			# The upper arms creep into the top slices; a chest is never this wide.
			_torso.append(Vector4(lo + (i + 0.5) * _torso_step, minf(rx[i], 0.215 if lo + i * _torso_step < armpit else 0.16), zf[i], zb[i]))
	if head_lo.x < INF:
		_head_c = (head_lo + head_hi) * 0.5
		_head_r = (head_hi - head_lo) * 0.5 * 0.96  # a head is rounder than its bounding box
	if thigh_d.size() > 20:
		# Most of the trouser leg, not the jacket flaring over it.
		thigh_d.sort()
		_thigh_radius = clampf(thigh_d[int(thigh_d.size() * 0.85)], 0.05, 0.11)


## A point on the head's surface (skeleton space) in the direction `dir` from its
## centre (head-local: +X his left, +Y up, +Z forward), `margin` outside it.
func _head_surface_for_hand(dir: Vector3, margin: float) -> Vector3:
	# The head-touch is keyed for the right hand and mirrored for the left (holding the
	# flashlight). Mirroring a point across the body's centre line misses a head that is
	# turned, so for the left hand the point is found on the head itself (direction
	# flipped), then mirrored back so the final mirror lands it on the real head.
	if not holding:
		return _head_surface(dir, margin)
	var p := _head_surface(Vector3(-dir.x, dir.y, dir.z), margin)
	return p * Vector3(-1, 1, 1)


func _head_surface(dir: Vector3, margin: float) -> Vector3:
	var d := dir.normalized()
	return skeleton.get_bone_global_pose(_b["Head"]) * (_head_c + d * (_head_r + Vector3.ONE * margin))


## Pushes a skeleton-space point out of the torso and thighs (plus `margin`).
## The torso follows the chest (or hips, low down); the thighs follow the legs.
func _push_out(p: Vector3, margin: float) -> Vector3:
	if _torso.is_empty():
		return p
	var bone := _b["Chest"] if p.y > skeleton.get_bone_global_pose(_b["Spine"]).origin.y else _b["Hips"]
	var to_rest := skeleton.get_bone_global_rest(bone) * skeleton.get_bone_global_pose(bone).affine_inverse()
	var q := to_rest * p
	var i := int((q.y - _torso_lo) / _torso_step)
	if i >= 0 and i < _torso.size():
		var slice := _torso[i]
		var cz := (slice.z + slice.w) * 0.5
		var rz := (slice.z - slice.w) * 0.5 + margin
		var rxm := slice.y + margin
		var dx := q.x / rxm
		var dz := (q.z - cz) / rz
		var r := sqrt(dx * dx + dz * dz)
		if r < 1.0:
			if r < 0.001:
				dz = 1.0
				r = 1.0
			q.x = dx / r * rxm
			q.z = cz + dz / r * rz
			p = to_rest.affine_inverse() * q
	# The head: the hand rests on it, never inside it.
	var head_pose := skeleton.get_bone_global_pose(_b["Head"])
	var hq := head_pose.affine_inverse() * p  # head-local, where the ellipsoid was measured
	var hd := (hq - _head_c) / (_head_r + Vector3.ONE * margin)
	var hr := hd.length()
	if hr < 1.0:
		if hr < 0.001:
			hd = Vector3.BACK
			hr = 1.0
		hq = _head_c + hd / hr * (_head_r + Vector3.ONE * margin)
		p = head_pose * hq
	for side in ["Left", "Right"]:
		var a := skeleton.get_bone_global_pose(_b[side + "UpperLeg"]).origin
		var b := skeleton.get_bone_global_pose(_b[side + "LowerLeg"]).origin
		var c := Geometry3D.get_closest_point_to_segment(p, a, b)
		var d := p - c
		var rad := _thigh_radius + margin
		if d.length() < rad:
			if d.length() < 0.001:
				d = Vector3.BACK
			p = c + d.normalized() * rad
	return p


## Where the barrel's axis sits in the right hand's own space: part way from the
## wrist to the knuckles, out from the palm by the barrel's depth.
func _grip_center_local() -> Vector3:
	return _knuckle_local["R"] * GRIP_ALONG + _palm_local["R"] * GRIP_DEPTH


## The barrel's direction in the right hand's space. A fist doesn't hold a bar
## square to the knuckles: it lies obliquely across the palm, the thumb end
## angled toward the fingertips.
func _grip_axis_local() -> Vector3:
	var al: Vector3 = _across_local["R"]
	var up := Vector3.UP - al * al.dot(Vector3.UP)  # the fingers' direction, square to it
	return (al + up.normalized() * tan(GRIP_OBLIQUE)).normalized()


## The right hand's skeleton-space orientation for holding the flashlight: its
## index-finger side points down the barrel and its palm faces `grip_palm`.
func _grip_basis_skel() -> Basis:
	var to_skel := skeleton.global_transform.basis.orthonormalized().inverse()
	var a := (to_skel * grip_axis).normalized()
	var n := to_skel * grip_palm
	n = (n - a * n.dot(a)).normalized()
	var al := _grip_axis_local()
	var nl: Vector3 = _palm_local["R"]
	nl = (nl - al * nl.dot(al)).normalized()
	var local := Basis(al, nl, al.cross(nl))
	var want := Basis(a, n, a.cross(n))
	return (want * local.inverse()).orthonormalized()


## World transform for the flashlight model held in the right hand: its barrel
## (lens toward +Z) runs through the curled fingers along the index side.
## `grip_z` is where the hand holds it along the model's length.
func held_transform(grip_z: float) -> Transform3D:
	var hand := skeleton.get_bone_global_pose(_b["RightHand"])
	var al := _grip_axis_local()
	var nl: Vector3 = _palm_local["R"]
	nl = (nl - al * nl.dot(al)).normalized()
	# Flashlight axes in hand space: +Z down the barrel, +Y (its switch) away
	# from the palm so it sits under the thumb.
	var local := Basis(nl.cross(al) * -1.0, -nl, al)
	var xf := skeleton.global_transform
	var basis := (xf.basis * hand.basis * local).orthonormalized()
	var centre := xf * (hand * _grip_center_local())
	return Transform3D(basis, centre - basis.z * grip_z)


## Works out, from the rest skeleton, which way each palm faces and which way
## every finger bone bends (the rig's bone rolls are not axis-aligned).
func _measure_hand(side: String, s: String) -> void:
	if not _b.has(side + "IndexProximal") or not _b.has(side + "LittleProximal"):
		return
	var across := _rest(side + "IndexProximal") - _rest(side + "LittleProximal")
	var along := _rest(side + "MiddleIntermediate") - _rest(side + "MiddleProximal")
	var palm := (across.cross(along) * (-1.0 if s == "L" else 1.0)).normalized()
	var hand_basis := skeleton.get_bone_global_rest(_b[side + "Hand"]).basis
	_palm_local[s] = (hand_basis.inverse() * palm).normalized()
	_across_local[s] = (hand_basis.inverse() * across).normalized()
	_knuckle_local[s] = hand_basis.inverse() * (_rest(side + "MiddleProximal") - _rest(side + "Hand"))
	for finger in ["Thumb", "Index", "Middle", "Ring", "Little"]:
		for part in ["Metacarpal", "Proximal", "Intermediate", "Distal"]:
			var name: String = side + finger + part
			if not _b.has(name):
				continue
			var bone: int = _b[name]
			var g := skeleton.get_bone_global_rest(bone)
			var kids := skeleton.get_bone_children(bone)
			var dir := (skeleton.get_bone_global_rest(kids[0]).origin - g.origin).normalized() if kids.size() > 0 else g.basis.y.normalized()
			# The thumb folds across the palm toward the little finger.
			var toward := palm if finger != "Thumb" else (palm * 0.75 - across.normalized() * 0.55).normalized()
			var axis := dir.cross(toward)
			if axis.length() < 0.01:
				continue
			_curl_axis[bone] = (g.basis.inverse() * axis.normalized()).normalized()
			# Positive spread swings the finger toward the index/thumb side.
			var spread := palm * signf(palm.cross(dir).dot(across))
			_spread_axis[bone] = (g.basis.inverse() * spread).normalized()


## Hair, brows and lashes are alpha-cut cards. A hard cut at 0.5 leaves jagged,
## shimmering strand edges up close, so blend the cut edge with MSAA
## (alpha to coverage), soften the threshold, filter the texture
## anisotropically and take the glitter out of the highlight.
func _smooth_hair(root: Node3D) -> void:
	for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		for s in mesh.mesh.get_surface_count():
			var src := mesh.mesh.surface_get_material(s) as BaseMaterial3D
			if src == null or src.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
				continue
			var name := src.resource_name.to_lower()
			var hair := name.contains("hair")
			if not (hair or name.contains("eyebrow") or name.contains("eyelash")):
				continue
			var mat := src.duplicate() as BaseMaterial3D
			mat.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE_AND_TO_ONE
			mat.alpha_antialiasing_edge = 0.3 if hair else 0.2
			mat.alpha_scissor_threshold = 0.38 if hair else 0.25
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			if hair:
				mat.roughness = 0.58
				mat.metallic_specular = 0.3
			mesh.set_surface_override_material(s, mat)


func _instance(scene: PackedScene) -> Node3D:
	var m: Node3D = scene.instantiate()
	m.rotation.y = PI
	m.scale = Vector3.ONE * model_scale
	add_child(m)
	return m


func _process(delta: float) -> void:
	if skeleton == null:
		return
	_time += delta
	_gesture_time += delta
	var pos := global_position
	if _last_pos != Vector3.INF and delta > 0.0:
		var moved := Vector2(pos.x - _last_pos.x, pos.z - _last_pos.z).length()
		_speed = lerpf(_speed, moved / delta, minf(1.0, 10.0 * delta))
		_phase += moved / (STEP_LENGTH * model_scale) * PI
	_last_pos = pos
	_walk = move_toward(_walk, 1.0 if _speed > 0.25 else 0.0, delta * 4.0)
	# Turning on the spot: little shuffle steps instead of the feet skating round.
	var yaw := global_rotation.y
	if _last_yaw != INF and delta > 0.0:
		var turned := absf(angle_difference(_last_yaw, yaw))
		_turn_rate = lerpf(_turn_rate, turned / delta, minf(1.0, 8.0 * delta))
		if _walk < 0.5:
			_phase += turned * 2.2
	_last_yaw = yaw
	_shuffle = move_toward(_shuffle, 1.0 if _turn_rate > 0.35 and _walk < 0.5 else 0.0, delta * 3.0)
	_update_fidget(delta)
	if _id_time >= 0.0:
		_id_time += delta
		if _id_time >= _id_len:
			_id_time = -1.0
	_pose(delta)
	_update_mouth(delta)
	_update_id_card()
	if _shadow_skeleton != null:
		for i in skeleton.get_bone_count():
			_shadow_skeleton.set_bone_pose(i, skeleton.get_bone_pose(i))
		_shadow_skeleton.set_bone_pose_scale(_b["Head"], Vector3.ONE)


## Starts a gesture by name ("talk", "point", ...). Unknown names fall back to idle.
func play(gesture_name: String, target := Vector3.INF) -> void:
	var next: Gesture = GESTURE_NAMES.get(gesture_name, Gesture.IDLE)
	if next == gesture and target == gesture_target:
		return  # keep going: back-to-back lines with the same gesture shouldn't restart it
	if next == Gesture.TALK and gesture != Gesture.TALK:
		_talk_hand = "R" if randf() < 0.65 else "L"
		_talk_style = randi() % 3
		if holding:  # the flashlight hand stays down; no two-handed explaining
			_talk_hand = "L"
			_talk_style = [0, 2].pick_random()
	if next != Gesture.IDLE:
		_fidget = ""
	gesture = next
	gesture_target = target
	_gesture_time = 0.0


func _on_line_shown(speaker: String, text: String, duration: float) -> void:
	if speaker.to_lower() == speaker_name.to_lower():
		speak(text, duration)


## Moves the jaw to a line of dialogue. With no recorded voice, the mouth shapes
## come from the letters: open on vowels, shut on m/b/p, nearly shut on f/v,
## still on commas and full stops, at a natural speaking pace.
func speak(text: String, duration: float) -> void:
	_speech.clear()
	var rate := 0.06
	var t := 0.06
	var amp := randf_range(0.85, 1.1) * (1.2 if text.contains("!") else 1.0)
	var lower := text.to_lower()
	for i in lower.length():
		var c := lower[i]
		var open := 0.32
		var dt := rate
		if c in "ao":
			open = 1.0
		elif c in "eiuy":
			open = 0.65
		elif c in "mbp":
			open = 0.0
		elif c in "fvw":
			open = 0.12
		elif c == " ":
			open = 0.18
			dt = rate * 0.6
		elif c in ",;:-":
			open = 0.0
			dt = 0.2
		elif c in ".?!…":
			open = 0.0
			dt = 0.3
		elif c in "'\"":
			continue
		_speech.append(Vector2(t, open * amp))
		t += dt
	_speech.append(Vector2(t, 0.0))
	# Squeeze into the subtitle's time if needed, never stretch.
	var avail := maxf(0.5, duration - 0.15)
	if t > avail:
		for k in _speech.size():
			_speech[k].x *= avail / t
		t = avail
	_speech_len = t
	_speech_time = 0.0


func is_speaking() -> bool:
	return _speech_time < _speech_len


func _update_mouth(delta: float) -> void:
	var target := 0.0
	if _speech_time < _speech_len:
		_speech_time += delta
		for k in range(_speech.size() - 1, -1, -1):
			if _speech[k].x <= _speech_time:
				target = _speech[k].y
				break
	# A jaw has weight: follow the letters on a fast critically damped spring.
	var step := clampf(delta, 0.0, 1.0 / 30.0)
	var w := 24.0
	_jaw_vel += ((target - _jaw) * w * w - _jaw_vel * 2.0 * w) * step
	_jaw += _jaw_vel * step
	_talk_energy = lerpf(_talk_energy, target, minf(1.0, 5.0 * delta))
	if _b.has("Jaw"):
		var open := clampf(_jaw, -0.05, 1.3) * 0.16 + 0.012
		var jaw := _b["Jaw"]
		skeleton.set_bone_pose_rotation(jaw, skeleton.get_bone_rest(jaw).basis.get_rotation_quaternion() * Quaternion(Vector3.RIGHT, open))


func _update_fidget(delta: float) -> void:
	if not fidgets or gesture != Gesture.IDLE or _walk > 0.2 or crouch > 0.1 or is_speaking():
		_fidget = ""
		_fidget_wait = maxf(_fidget_wait, 2.0)
		return
	if _fidget.is_empty():
		_fidget_wait -= delta
		if _fidget_wait <= 0.0:
			_fidget = ["hold_wrist", "clasp", "flex_hand", "glance", "hold_wrist"].pick_random()
			_fidget_len = randf_range(2.5, 3.5) if _fidget == "glance" else randf_range(4.0, 7.0)
			_fidget_time = 0.0
			_glance_side = -1.0 if randf() < 0.5 else 1.0
	else:
		_fidget_time += delta
		if _fidget_time >= _fidget_len:
			_fidget = ""
			_fidget_wait = randf_range(4.0, 9.0)


## 0 -> 1 -> 0 over the current fidget.
func _fidget_env() -> float:
	return smoothstep(0.0, 0.9, _fidget_time) * (1.0 - smoothstep(_fidget_len - 0.9, _fidget_len, _fidget_time))


## Yaw of the POINT target relative to where the character faces (radians,
## + is his left).
func point_yaw() -> float:
	if skeleton == null or gesture_target == Vector3.INF:
		return 0.0
	var local := skeleton.global_transform.affine_inverse() * gesture_target
	return atan2(local.x, local.z)


## World position of a bone (for cameras and pointing).
func bone_position(bone_name: String) -> Vector3:
	if skeleton == null or not _b.has(bone_name):
		return global_position
	return skeleton.global_transform * skeleton.get_bone_global_pose(_b[bone_name]).origin


func head_position() -> Vector3:
	return bone_position("Head") + Vector3(0, 0.06 * model_scale, 0)


func bandaged_hand_position() -> Vector3:
	return bone_position("LeftHand" if bandaged_left else "RightHand")


# --- Posing --------------------------------------------------------------------------

func _pose(delta: float) -> void:
	_dt = delta
	var k := 1.0 if not _initialised else minf(1.0, 7.0 * delta)
	var t := _time + _seed
	var breath := sin(t * 1.6)
	var walk_swing := sin(_phase) * _walk

	# Reset everything we drive to the rest pose.
	for name in ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head",
			"LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand",
			"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot"]:
		skeleton.set_bone_pose_rotation(_b[name], skeleton.get_bone_rest(_b[name]).basis.get_rotation_quaternion())

	# Hips: weight shift and a slow sway at idle, a bob while walking, a drop when crouching.
	var hips := _b["Hips"]
	var rest_hips := skeleton.get_bone_rest(hips).origin
	# Idle: a slow weight shift. Walking: the weight rides over each stance leg.
	var shift := sin(t * 0.35) * 0.018 * (1.0 - _walk) + sin(_phase - 0.5) * 0.02 * _walk
	# Feet first: where each foot wants to be this frame.
	var legs := maxf(_walk, _shuffle * 0.45)
	var feet := {"Left": _foot_target("Left", legs), "Right": _foot_target("Right", legs)}
	# The hips sink just enough that the stretched-out stance leg can still reach its
	# foot (so the foot stays planted), highest mid-stance, lowest at heel strike.
	var drop := maxf(crouch * 0.42, _hip_drop_to_reach(feet) * legs)
	skeleton.set_bone_pose_position(hips, rest_hips + Vector3(shift, -drop, 0))
	_rotate_global(hips, Basis(Vector3.UP, sin(_phase) * 0.12 * _walk) * Basis(Vector3.BACK, -shift * 1.6))

	# Torso: breathing, counter-rotation against the hips while walking, crouch and bow lean.
	var lean_target := crouch * 0.45 + 0.06 * _walk
	if gesture == Gesture.AFTER_YOU:
		lean_target += 0.22 * _envelope(0.3, 2.2)
	_lean = lerpf(_lean, lean_target, k)
	# Pointing: the chest turns toward the target too (up to ~30 degrees), so the
	# arm never has to reach round behind him.
	var twist_target := 0.0
	if gesture == Gesture.POINT and gesture_target != Vector3.INF:
		twist_target = clampf(point_yaw(), -0.55, 0.55) * _envelope(0.0, 0.0)
	_chest_twist = lerpf(_chest_twist, twist_target, k * 0.6)
	_rotate_global(_b["Spine"], Basis(Vector3.UP, -sin(_phase) * 0.18 * _walk + _chest_twist * 0.5) * Basis(Vector3.RIGHT, _lean * 0.5 + breath * 0.008))
	_rotate_global(_b["Chest"], Basis(Vector3.UP, _chest_twist * 0.5) * Basis(Vector3.RIGHT, _lean * 0.35 + breath * 0.015))
	_rotate_global(_b["UpperChest"], Basis(Vector3.RIGHT, breath * 0.012))

	# Legs: feet planted (or stepping), knees bend forward.
	for side in ["Left", "Right"]:
		var sg := 1.0 if side == "Left" else -1.0
		var ft: Dictionary = feet[side]
		var knee_pole := _rest(side + "LowerLeg") + Vector3(sg * 0.05, 0, 1.0)
		_two_bone(side + "UpperLeg", side + "LowerLeg", side + "Foot", ft.pos, knee_pole)
		# Foot roll about the ankle (toes are +Z, so toes up is a negative X turn).
		var pitch: float = ft.toe_up * 0.25 - ft.heel * 0.45
		_set_global_basis(_b[side + "Foot"], Basis(Vector3.RIGHT, -pitch) * skeleton.get_bone_global_rest(_b[side + "Foot"]).basis)
		if _b.has(side + "Toes"):
			# The toes stay on the floor while the heel is up.
			var toes := _b[side + "Toes"]
			skeleton.set_bone_pose_rotation(toes, skeleton.get_bone_rest(toes).basis.get_rotation_quaternion())
			_rotate_global(toes, Basis(Vector3.RIGHT, -float(ft.heel) * 0.4))

	# Arms: blend the hands, elbows, palm direction and finger curl toward the gesture.
	var arm_k := 1.0 if not _initialised else minf(1.0, 4.0 * delta)
	var targets := _arm_targets(t, walk_swing)
	for s in ["L", "R"]:
		var tgt: Dictionary = targets[s]
		if not _initialised:
			_hand[s] = tgt.hand
			_pole[s] = tgt.pole
			_palm[s] = tgt.palm
			_finger[s] = tgt.curl
		# Hands move on a critically damped spring: they ease in and ease out
		# like a real arm instead of leaping off at full speed.
		var step := clampf(delta, 0.0, 1.0 / 20.0) if _initialised else 0.0
		var w := 7.0
		_hand_vel[s] += ((tgt.hand - _hand[s]) * w * w - _hand_vel[s] * 2.0 * w) * step
		_hand[s] += _hand_vel[s] * step
		_pole[s] = _pole[s].lerp(tgt.pole, arm_k)
		_palm[s] = _blend_dir(_palm[s], tgt.palm, arm_k)
		_finger[s] = lerpf(_finger[s], tgt.curl, arm_k)
		_pointing[s] = tgt.point
		var side := "Left" if s == "L" else "Right"
		# Keep the hand out of the body: the wrist, and the fingertips ahead of it.
		var target: Vector3 = _hand[s]
		# (The flashlight hand is held out in front by the camera; its curled
		# fingers point at the chest, which would wrongly drag it down.)
		if not (gesture == Gesture.FLASHLIGHT and s == "R"):
			target = _push_out(target, 0.045)
			var tip := target + _tip_dir[s] * 0.1
			target += _push_out(tip, 0.02) - tip
		# Elbows: if last frame's elbow sank into the torso, swing the pole outward.
		var pole: Vector3 = _pole[s] + _pole_push[s]
		_two_bone(side + "UpperArm", side + "LowerArm", side + "Hand", target, pole)
		var elbow := skeleton.get_bone_global_pose(_b[side + "LowerArm"]).origin
		var forearm_mid := elbow.lerp(skeleton.get_bone_global_pose(_b[side + "Hand"]).origin, 0.5)
		var push := (_push_out(elbow, 0.06) - elbow) + (_push_out(forearm_mid, 0.045) - forearm_mid)
		if gesture == Gesture.FLASHLIGHT and s == "R":
			push = Vector3.ZERO
		var dt := maxf(delta, 1.0 / 120.0)
		if push.length() > 0.001:
			_pole_push[s] += push * 6.0 * minf(1.0, 10.0 * dt)  # grows while it sinks in
		else:
			_pole_push[s] = _pole_push[s].lerp(Vector3.ZERO, minf(1.0, 1.5 * dt))  # relaxes slowly
		_pole_push[s] = _pole_push[s].limit_length(0.8)
		if s == "R" and gesture == Gesture.FLASHLIGHT and grip_point != Vector3.INF:
			# Holding the flashlight: the hand takes the grip orientation exactly.
			# The part of that turn that is a roll about the forearm goes into the
			# forearm (that's how a wrist really rotates); it is worked out directly
			# each frame, so the result never depends on how the arm got there.
			var lower := _b["RightLowerArm"]
			var hb := _b["RightHand"]
			var fore := skeleton.get_bone_global_pose(lower)
			var f := (skeleton.get_bone_global_pose(hb).origin - fore.origin).normalized()
			var q := Quaternion((_grip_basis * skeleton.get_bone_global_pose(hb).basis.orthonormalized().inverse()).orthonormalized())
			var roll := clampf(2.0 * atan2(Vector3(q.x, q.y, q.z).dot(f), q.w), -PI, PI)
			roll = clampf(wrapf(roll, -PI, PI), -2.2, 2.2)
			_twist["R"] = roll
			_rotate_global(lower, Basis(f, roll))
			# Keep the wrist within a comfortable bend: past GRIP_WRIST_MAX the hand
			# (and the flashlight with it) follows the forearm instead.
			var want_hand := _grip_basis
			var fore_dir := (skeleton.get_bone_global_pose(hb).origin - skeleton.get_bone_global_pose(lower).origin).normalized()
			_grip_forearm = fore_dir
			var fingers := want_hand.y.normalized()
			var bend := fore_dir.angle_to(fingers)
			if bend > GRIP_WRIST_MAX:
				var ax := fingers.cross(fore_dir)
				if ax.length() > 0.0001:
					want_hand = Basis(ax.normalized(), bend - GRIP_WRIST_MAX) * want_hand
			_set_global_basis(hb, want_hand)
		else:
			_orient_hand(side, s)
		_curl_fingers(side, s, t)
		_tip_dir[s] = skeleton.get_bone_global_pose(_b[side + "Hand"]).basis.y.normalized()

	# Head: look at the target (neck takes some, head the rest).
	var want := Vector2(sin(t * 0.23) * 0.12, sin(t * 0.31) * 0.04 - 0.03)
	if gesture == Gesture.SHOW_HAND:
		want = Vector2(0.1 if bandaged_left else -0.1, -0.55)
	elif gesture == Gesture.TOUCH_HEAD and _gesture_time > 0.9 and _gesture_time < 2.55:
		want = Vector2(0.15, -0.3)  # wince: head dips toward the hand
	elif gesture == Gesture.TOUCH_HEAD and _gesture_time >= 2.55 and _gesture_time < 3.85:
		want = Vector2(-0.12, -0.42)  # looking at the fingers
	elif gesture == Gesture.POINT and gesture_target != Vector3.INF and _gesture_time < 1.8:
		var local := (skeleton.global_transform.affine_inverse() * gesture_target) - _rest("Head")
		want = Vector2(clampf(atan2(local.x, local.z) - _chest_twist, -1.1, 1.1), clampf(atan2(local.y, Vector2(local.x, local.z).length()), -0.5, 0.4))
	elif look_target != Vector3.INF:
		var local := (skeleton.global_transform.affine_inverse() * look_target) - _rest("Head")
		var yaw := atan2(local.x, local.z)
		var pitch := atan2(local.y, Vector2(local.x, local.z).length())
		want = Vector2(clampf(yaw, -1.1, 1.1), clampf(pitch, -0.6, 0.5))
	# Talking: small nods on the stressed syllables and a slow tilt.
	if is_speaking() or _talk_energy > 0.02:
		want.y += -_talk_energy * 0.06 + sin(t * 2.1) * 0.012 * _talk_energy
		want.x += sin(t * 0.8) * 0.04 * _talk_energy
	# Idle fidgets: a glance over the shoulder, or looking down at the hurt hand.
	if _fidget == "glance":
		want.x += _glance_side * 0.7 * _fidget_env()
		want.y += 0.05 * _fidget_env()
	elif _fidget == "flex_hand":
		want = want.lerp(Vector2(0.15 if bandaged_left else -0.15, -0.5), _fidget_env())
	if _id_time >= 0.0:
		# Eyes down on the card while it's up; a small tilt as he turns it over.
		var reading := smoothstep(0.3, 1.0, _id_time) * (1.0 - smoothstep(0.8 + _id_hold, 1.5 + _id_hold, _id_time))
		want = want.lerp(Vector2((0.1 if ID_HAND == "L" else -0.1) + sin(_id_time * 1.3) * 0.03, -0.52), reading)
	_look = _look.lerp(want, minf(1.0, 4.0 * delta) if _initialised else 1.0)
	var look_basis := Basis(Vector3.UP, _look.x) * Basis(Vector3.RIGHT, -_look.y)
	_rotate_global(_b["Neck"], Basis(Vector3.UP, _look.x * 0.4) * Basis(Vector3.RIGHT, -_look.y * 0.4))
	_set_global_basis(_b["Head"], look_basis * skeleton.get_bone_global_rest(_b["Head"]).basis)
	_initialised = true


## Where one foot goes this frame (skeleton space), with how far the heel is
## peeled up and the toes raised. A step is two halves: the planted foot slides
## back at exactly the body's speed (z falls linearly over a step's length), then
## swings forward (eased) with a lift.
func _foot_target(side: String, legs: float) -> Dictionary:
	var sg := 1.0 if side == "Left" else -1.0
	var foot_rest := _rest(side + "Foot")
	var reach := STEP_LENGTH * 0.5
	var u := fposmod(_phase + (0.0 if side == "Left" else PI) - PI * 0.5, TAU) / PI  # 0..2
	var z := 0.0
	var lift := 0.0
	var heel := 0.0
	var toe_up := 0.0
	if u < 1.0:  # planted, moving back under the body
		z = reach * (1.0 - 2.0 * u)
		heel = pow(u, 5.0)  # the heel peels off as it passes behind
	else:  # swinging forward
		var v := u - 1.0
		z = reach * (-1.0 + 2.0 * smoothstep(0.0, 1.0, v))
		lift = sin(v * PI)
		heel = pow(maxf(0.0, 1.0 - v * 3.0), 2.0)
		toe_up = pow(v, 3.0) * (1.0 - smoothstep(0.9, 1.0, v))  # toes up, flat again at contact
	var half_width := lerpf(STANCE_STAND, STANCE_WALK, legs)
	var pos := Vector3(sg * half_width + sg * 0.02 * crouch, foot_rest.y + (lift * 0.1 + heel * 0.035) * legs, foot_rest.z + z * legs)
	return {"pos": pos, "heel": heel * legs, "toe_up": toe_up * legs}


## How far the hips must sink for both legs to reach their feet (never past a
## nearly straight leg), in skeleton space.
func _hip_drop_to_reach(feet: Dictionary) -> float:
	var worst := 0.0
	for side in ["Left", "Right"]:
		var key := String(side[0])
		var hip := _rest(side + "UpperLeg")
		var length := (float(_len[key + "_thigh"]) + float(_len[key + "_shin"])) * 0.995
		var f: Vector3 = feet[side].pos
		var flat := Vector2(f.x - hip.x, f.z - hip.z).length_squared()
		var vertical := sqrt(maxf(length * length - flat, 0.0001))
		worst = maxf(worst, hip.y - f.y - vertical)
	return worst


## Per side: hand target, elbow pole, palm direction and finger curl for the
## current gesture, all in skeleton space (front +Z, his left +X).
func _arm_targets(t: float, walk_swing: float) -> Dictionary:
	var out := {}
	for s in ["L", "R"]:
		var x := 1.0 if s == "L" else -1.0
		var sway := sin(t * 0.9 + x) * 0.01
		# Relaxed: hands hang beside the thighs, palms in, swinging when walking.
		var fwd := -walk_swing * x  # this arm's swing: + forward (opposite its leg)
		var hand := Vector3(x * 0.235, 0.86, 0.05 + sway + fwd * 0.19)
		# The elbow bends more on the forward swing and straightens behind.
		hand.y += maxf(0.0, fwd) * 0.06
		hand.x -= x * maxf(0.0, fwd) * 0.03
		hand.y -= crouch * 0.3
		hand.z += crouch * 0.25
		out[s] = _arm(hand, Vector3(x * 0.45, 1.1, -0.6), Vector3(-x, 0, -0.15), 0.35)
	# Gestures ease in (and some ease back out) from the relaxed pose.
	match gesture:
		Gesture.TALK:
			# Hands beat with the stressed syllables (_talk_energy) on top of a slow
			# drift. Three styles, picked per line so it doesn't repeat.
			var main := _talk_hand
			var x := 1.0 if main == "L" else -1.0
			var e := _talk_energy
			var drift := sin(_gesture_time * 0.7) * 0.02
			var beat := sin(_gesture_time * 0.9 + 1.0) * 0.012 - e * 0.035
			match _talk_style:
				0:
					# One hand, forearm up, palm turned up and in.
					_blend(out, main, _arm(Vector3(x * (0.2 + drift), 1.12 + beat, 0.3 + e * 0.03), Vector3(x * 0.7, 0.9, -0.3), Vector3(-x * 0.55, 0.8, 0.15), 0.3 + e * 0.1), _envelope(0.0, 0.0))
				1:
					# Both hands explaining, palms facing each other, opening on stresses.
					for s in ["L", "R"]:
						var sx := 1.0 if s == "L" else -1.0
						_blend(out, s, _arm(Vector3(sx * (0.15 + e * 0.035), 1.07 + beat * 0.7, 0.29), Vector3(sx * 0.7, 0.9, -0.3), Vector3(-sx, 0.15, 0.2), 0.32), _envelope(0.0, 0.0))
				_:
					# One hand palm down, small chopping beats.
					_blend(out, main, _arm(Vector3(x * (0.17 + drift), 1.07 + beat * 1.3, 0.3), Vector3(x * 0.7, 0.85, -0.3), Vector3(-x * 0.2, -1.0, 0.15), 0.38), _envelope(0.0, 0.0))
		Gesture.CALM:
			# "Easy": both hands out, palms toward Jason, a slow settling push.
			var push := sin(_gesture_time * 1.2) * 0.02
			for s in ["L", "R"]:
				var x := 1.0 if s == "L" else -1.0
				_blend(out, s, _arm(Vector3(x * 0.2, 1.12, 0.34 + push), Vector3(x * 0.7, 0.9, -0.2), Vector3(-x * 0.3, -0.55, 0.8), 0.2), _envelope(0.0, 0.0))
		Gesture.STARTLE:
			for s in ["L", "R"]:
				var x := 1.0 if s == "L" else -1.0
				_blend(out, s, _arm(Vector3(x * 0.24, 1.0, 0.22), Vector3(x * 0.7, 0.8, -0.3), Vector3(-x * 0.3, 0.0, 1.0), 0.25), _envelope(0.0, 0.0))
		Gesture.SHOW_HAND:
			# Raise it, look at it, then let it drop again.
			var main := "L" if bandaged_left else "R"
			var x := 1.0 if main == "L" else -1.0
			_blend(out, main, _arm(Vector3(x * 0.1, 1.2, 0.3), Vector3(x * 0.7, 0.9, -0.3), Vector3(-x * 0.3, 0.75, -0.55), 0.3), _envelope(0.2, 2.0))
		Gesture.POINT:
			var tgt := Vector3(-0.6, 1.3, 0.8)
			if gesture_target != Vector3.INF:
				tgt = skeleton.global_transform.affine_inverse() * gesture_target
			# Point with the hand on the target's side, from where the shoulder is now
			# (the chest has turned toward it), never across or behind the body.
			var main := "L" if tgt.x > 0.0 else "R"
			var x := 1.0 if main == "L" else -1.0
			var shoulder := skeleton.get_bone_global_pose(_b[("Left" if main == "L" else "Right") + "UpperArm"]).origin
			var dir := (tgt - shoulder).normalized()
			# Keep the arm in front of the shoulder: at most ~25 degrees behind sideways.
			var flat := Vector2(dir.x * x, dir.z)
			var ang := atan2(flat.y, flat.x)  # 0 = straight out to the side, +90 = forward
			if ang < -0.45:
				var keep := Vector2(cos(-0.45), sin(-0.45)) * flat.length()
				dir = Vector3(keep.x * x, dir.y, keep.y).normalized()
			dir.y = clampf(dir.y, -0.35, 0.45)
			dir = dir.normalized()
			var reach := (_len[main + "_upper"] + _len[main + "_lower"]) * 0.88  # elbow soft, not locked
			var pole := shoulder + Vector3(x * 0.3, -0.5, -0.2)
			_blend(out, main, _arm(shoulder + dir * reach, pole, Vector3(-x * 0.3, -1, 0), 0.6, true), _envelope(0.15, 0.0))
		Gesture.TOUCH_HEAD:
			# Hand up in front, elbow lifting out to the side, fingers to the wound at
			# the back of the head (a small wince and rub), then forward to look at the
			# fingers for blood, and down again.
			var rub := sin(_gesture_time * 6.0) * 0.012
			# With the flashlight in his right hand, he uses the left (mirrored).
			var h := "L" if holding else "R"
			out[h] = _mirror_arm(_track(_gesture_time, [
				[0.0, _mirror_arm(out[h], holding)],
				[0.55, _arm(Vector3(-0.27, 1.22, 0.24), Vector3(-0.8, 0.9, -0.1), Vector3(0.6, 0.3, 0.6), 0.4)],
				# (points on the head itself, so the hand rests on it wherever the head is)
				[1.0, _arm(_head_surface_for_hand(Vector3(-1.0, -0.2, 0.15), 0.05), Vector3(-0.95, 1.55, 0.35), Vector3(0.9, 0.0, 0.3), 0.45)],
				# (a stop on the way round, so the hand follows the curve of the skull instead of cutting across it)
				[1.25, _arm(_head_surface_for_hand(Vector3(-0.85, -0.15, -0.55), 0.06), Vector3(-0.95, 1.7, 0.28), Vector3(0.55, -0.05, 0.65), 0.5)],
				[1.5, _arm(_head_surface_for_hand(Vector3(-0.4, -0.12 + rub * 6.0, -1.0), 0.05), Vector3(-0.95, 1.85, 0.2), Vector3(0.2, -0.1, 1.0), 0.55)],
				[2.2, _arm(_head_surface_for_hand(Vector3(-0.45, -0.18 - rub * 6.0, -0.95), 0.05), Vector3(-0.95, 1.85, 0.2), Vector3(0.2, -0.1, 1.0), 0.6)],
				# (comes away from the head to the side first, then forward: never across the face)
				[2.6, _arm(Vector3(-0.4, 1.46, 0.34), Vector3(-0.85, 1.4, 0.1), Vector3(0.4, 0.25, 0.2), 0.5)],
				[3.1, _arm(Vector3(-0.1, 1.42, 0.3), Vector3(-0.75, 1.1, 0.0), Vector3(0.1, 0.35, -0.95), 0.45)],
				[3.65, _arm(Vector3(-0.11, 1.4, 0.3), Vector3(-0.75, 1.1, 0.0), Vector3(0.1, 0.35, -0.95), 0.5)],
				[4.45, _mirror_arm(out[h], holding)],
			]), holding)
		Gesture.AFTER_YOU:
			# An open palm toward the door, with a small bow.
			_blend(out, "R", _arm(Vector3(-0.42, 1.08, 0.38), Vector3(-0.6, 0.8, -0.4), Vector3(0.2, 1, 0.1), 0.2), _envelope(0.4, 0.0))
		Gesture.FLASHLIGHT:
			if grip_point != Vector3.INF:
				# Work back from the flashlight: where must the wrist be, and how
				# must the hand turn, for the palm to sit against the barrel with
				# the index finger toward the lens?
				var basis := _grip_basis_skel()
				# Roll the hand round the barrel so the fingers line up as closely as
				# possible with the forearm (last frame's): the straightest wrist that
				# still points the light down the view.
				var a := (basis * _grip_axis_local()).normalized()
				var y := basis.y.normalized()
				var yp := y - a * y.dot(a)
				var fp := _grip_forearm - a * _grip_forearm.dot(a)
				if yp.length() > 0.01 and fp.length() > 0.01:
					basis = (Basis(a, yp.normalized().signed_angle_to(fp.normalized(), a)) * basis).orthonormalized()
				var axis := skeleton.global_transform.affine_inverse() * grip_point
				var wrist := axis - basis * (_grip_center_local())
				_grip_basis = basis
				# Put the elbow where the forearm lines up behind the hand (as near
				# as the arm allows), so the wrist stays nearly straight.
				# Elbow down and out to his right side, a little back: the natural way
				# to hold a light up in front of you (not tucked under the chin).
				var pole := wrist + GRIP_ELBOW
				out["R"] = _arm(wrist, pole, basis * _palm_local["R"], GRIP_CURL)
			elif gesture_target != Vector3.INF:
				var local := skeleton.global_transform.affine_inverse() * gesture_target
				out["R"] = _arm(local, Vector3(-0.5, 0.8, -0.3), Vector3(1, 0, 0), GRIP_CURL)
		Gesture.IDLE:
			if not _fidget.is_empty():
				_fidget_arms(out)
	if _id_time >= 0.0:
		_id_arm(out, _id_time)
	return out


## Starts the look-at-the-ID animation: lift it up, read it for `hold` seconds,
## put it away.
func look_at_id(hold := 3.5) -> void:
	if not id_model.is_empty():
		_id_hold = hold
		_id_len = 0.9 + hold + 0.7 + 0.3 + 1.0
		_id_time = 0.0


## Puts the ID away at once (a cutscene ended).
func stop_id() -> void:
	_id_time = -1.0
	if _id_card != null:
		_id_card.visible = false


## World position of the ID card while it is held up (INF otherwise).
func id_card_position() -> Vector3:
	return _id_card.global_position if _id_card != null and _id_card.visible else Vector3.INF


## The hand that handles the ID: the left (the right holds the flashlight).
const ID_HAND := "L"


## Holding up the ID with the free hand: card in hand at the hip, up in front
## of the eyes to read it (turning it a little), then into the jacket.
func _id_arm(out: Dictionary, time: float) -> void:
	var o := ID_HAND
	var x := 1.0 if o == "L" else -1.0
	var rest: Dictionary = out[o]
	var pocket := _arm(Vector3(x * 0.1, 1.18, 0.17), Vector3(x * 0.8, 1.0, -0.2), Vector3(-x * 0.3, 0.0, -0.95), 0.7)
	var turn := sin(time * 1.3) * 0.12
	# Held up in front of the chest, the card turned toward his eyes.
	var at := Vector3(x * 0.1, 1.27, 0.3)
	var palm := Vector3(-x * (0.25 + turn), 0.45, -0.85)
	var read := _arm(at, Vector3(x * 0.75, 0.85, -0.25), palm, 0.62)
	out[o] = _track(time, [
		[0.0, rest], [0.9, read], [0.9 + _id_hold, read], [1.6 + _id_hold, pocket], [1.9 + _id_hold, pocket], [_id_len, rest],
	])


## The ID card itself: appears in the fingers once the hand is out of the
## jacket, faces his eyes, and is gone again when the hand goes back in.
func _update_id_card() -> void:
	var showing := _id_time >= 0.0 and _id_time < 1.7 + _id_hold and not id_model.is_empty()
	if not showing:
		if _id_card != null:
			_id_card.visible = false
		return
	if _id_card == null:
		_id_card = Props.instance(id_model)
		_id_card.top_level = true
		add_child(_id_card)
		# Readable in the dark: the card catches a little light of its own.
		for mi: MeshInstance3D in _id_card.find_children("*", "MeshInstance3D", true, false):
			var src := mi.mesh.surface_get_material(0) as BaseMaterial3D
			if src != null:
				var lit := src.duplicate() as BaseMaterial3D
				lit.emission_enabled = true
				lit.emission_texture = src.albedo_texture
				lit.emission = Color(1.0, 0.85, 0.7)
				lit.emission_energy_multiplier = 0.35
				mi.set_surface_override_material(0, lit)
	_id_card.visible = true
	var side := "Left" if ID_HAND == "L" else "Right"
	var xf := skeleton.global_transform
	var thumb := xf * skeleton.get_bone_global_pose(_b[side + "ThumbDistal"]).origin
	var index := xf * skeleton.get_bone_global_pose(_b[side + "IndexIntermediate"]).origin
	var wrist := xf * skeleton.get_bone_global_pose(_b[side + "Hand"]).origin
	var pinch := thumb.lerp(index, 0.5)
	var eyes := head_position()
	var face := (eyes - pinch).normalized()                 # the printed side looks at him
	var up := ((pinch - wrist).normalized() * 0.2 + Vector3.UP).normalized()
	up = (up - face * up.dot(face)).normalized()
	var right := up.cross(face).normalized()
	# The model lies flat: its long edge is X, its printed face is +Y.
	var basis := Basis(right, face, right.cross(face)) * model_scale
	# Just in front of the fingers (toward the eyes), thumb overlapping its lower edge.
	_id_card.global_transform = Transform3D(basis, pinch + (up * 0.028 + face * 0.014) * model_scale)


## Idle fidgets: the bandaged hand (B) and the other hand (O).
func _fidget_arms(out: Dictionary) -> void:
	var b := "L" if bandaged_left else "R"
	var o := "R" if bandaged_left else "L"
	var bx := 1.0 if b == "L" else -1.0
	var env := _fidget_env()
	var ft := _fidget_time
	match _fidget:
		"hold_wrist":
			# Cradles the hurt hand in front, the other hand holding its wrist.
			_blend(out, b, _arm(Vector3(bx * 0.08, 0.98, 0.21), Vector3(bx * 0.7, 0.9, -0.3), Vector3(-bx * 0.35, 0.7, 0.25), 0.45), env)
			var rub := sin(ft * 2.4) * 0.008
			_blend(out, o, _arm(Vector3(bx * 0.0 + rub, 1.0, 0.2), Vector3(-bx * 0.7, 0.9, -0.3), Vector3(bx * 0.1, -1.0, 0.1), 0.75), env)
		"clasp":
			# Hands loosely together low in front.
			for s in ["L", "R"]:
				var sx := 1.0 if s == "L" else -1.0
				_blend(out, s, _arm(Vector3(sx * 0.055, 0.9, 0.19), Vector3(sx * 0.7, 0.9, -0.3), Vector3(-sx, -0.1, 0.25), 0.62), env)
		"flex_hand":
			# Raises the hurt hand and slowly opens and closes it, testing it.
			var curl := 0.45 + sin(ft * 2.2) * 0.38
			_blend(out, b, _arm(Vector3(bx * 0.14, 1.03, 0.25), Vector3(bx * 0.7, 0.9, -0.3), Vector3(-bx * 0.3, 0.8, 0.2), curl), env)


## The same arm pose for the other hand (mirrored across the body), if `flip`.
func _mirror_arm(pose: Dictionary, flip: bool) -> Dictionary:
	if not flip:
		return pose
	var m := Vector3(-1, 1, 1)
	return {"hand": pose.hand * m, "pole": pose.pole * m, "palm": pose.palm * m, "curl": pose.curl, "point": pose.point}


## Eases through keyed arm poses: [[seconds, pose], ...] (the first and last are
## usually the relaxed pose, so the motion starts and ends at rest).
func _track(time: float, keys: Array) -> Dictionary:
	if time <= keys[0][0]:
		return keys[0][1]
	for i in range(1, keys.size()):
		if time <= keys[i][0]:
			var w := smoothstep(keys[i - 1][0], keys[i][0], time)
			var out := {"L": keys[i - 1][1]}
			_blend(out, "L", keys[i][1], w)
			return out["L"]
	return keys[keys.size() - 1][1]


func _arm(hand: Vector3, pole: Vector3, palm: Vector3, curl: float, point := false) -> Dictionary:
	return {"hand": hand, "pole": pole, "palm": palm.normalized(), "curl": curl, "point": point}


## Rotates direction `a` toward `b` by `w`, safe for any inputs (slerp needs
## exactly unit vectors and has no answer for opposite ones).
func _blend_dir(a: Vector3, b: Vector3, w: float) -> Vector3:
	a = a.normalized()
	b = b.normalized()
	var axis := a.cross(b)
	if axis.length() < 0.0001:
		if a.dot(b) > 0.0:
			return b if w >= 1.0 else a
		axis = a.cross(Vector3.UP if absf(a.y) < 0.9 else Vector3.RIGHT)
	return a.rotated(axis.normalized(), a.angle_to(b) * clampf(w, 0.0, 1.0)).normalized()


## Moves one side of `out` toward `pose` by `w` (0 relaxed, 1 the gesture).
func _blend(out: Dictionary, s: String, pose: Dictionary, w: float) -> void:
	var base: Dictionary = out[s]
	out[s] = {
		"hand": base.hand.lerp(pose.hand, w),
		"pole": base.pole.lerp(pose.pole, w),
		"palm": _blend_dir(base.palm, pose.palm, w),
		"curl": lerpf(base.curl, pose.curl, w),
		"point": pose.point and w > 0.5,
	}


## 0 -> 1 ease in from `start` seconds into the gesture; back to 0 at `hold_until` if > 0.
func _envelope(start: float, hold_until: float) -> float:
	var t := _gesture_time
	var v := smoothstep(start, start + 0.6, t)
	if hold_until > 0.0:
		v *= 1.0 - smoothstep(hold_until, hold_until + 0.7, t)
	return v


## Turns the forearm about its own axis (the way a wrist really rotates) so the
## palm faces `_palm`, then lets the hand follow it.
func _orient_hand(side: String, s: String) -> void:
	var lower := _b[side + "LowerArm"]
	var hand := _b[side + "Hand"]
	var fore := skeleton.get_bone_global_pose(lower)
	var axis := (skeleton.get_bone_global_pose(hand).origin - fore.origin).normalized()
	# Palm normal measured from the rest skeleton (see _measure_hand).
	var palm := skeleton.get_bone_global_pose(hand).basis * _palm_local[s]
	var have := (palm - axis * palm.dot(axis)).normalized()
	var want := (_palm[s] - axis * _palm[s].dot(axis))
	# Keep the twist continuous from frame to frame (no flipping the long way round
	# when the target is near 180 degrees), and within what a forearm can turn.
	# When the wanted palm lines up with the forearm there is no twist to read,
	# so hold the last one rather than dropping it (that snapped the hand).
	var goal := _twist[s]
	if want.length() > 0.15 and have.length() > 0.05:
		var raw := have.signed_angle_to(want.normalized(), axis)
		goal = clampf(_twist[s] + wrapf(raw - _twist[s], -PI, PI), -2.4, 2.4)
	# A wrist turns at a human speed, never in one frame.
	# Eased: it speeds up and slows down like a real forearm rather than spinning
	# at a fixed rate (which read as the hand flicking round).
	var step := maxf(_dt, 1.0 / 120.0)
	var angle := _twist[s] + clampf((goal - _twist[s]) * minf(1.0, 5.0 * step), -2.6 * step, 2.6 * step) if _initialised else goal
	_twist[s] = angle
	_rotate_global(lower, Basis(axis, angle))
	# Whatever the twist can't reach, the wrist bends for (up to ~55 degrees),
	# e.g. palms pushed out toward someone.
	palm = skeleton.get_bone_global_pose(hand).basis * _palm_local[s]
	var bend_axis := palm.cross(_palm[s])
	var off := palm.angle_to(_palm[s])
	# Fade out near 180 degrees, where the bend direction is undefined and would flip.
	var bend := minf(off, 0.95) * (1.0 - smoothstep(1.7, 2.3, off))
	# Smoothed: when the palm is far from where it should face, the bend's
	# direction can swing round within a frame, which flicked the hand.
	var target_q := Quaternion.IDENTITY
	if bend_axis.length() > 0.001 and bend > 0.02:
		target_q = Quaternion(bend_axis.normalized(), bend)
	_wrist_bend[s] = _wrist_bend[s].slerp(target_q, minf(1.0, 7.0 * maxf(_dt, 1.0 / 120.0))) if _initialised else target_q
	_rotate_global(hand, Basis(_wrist_bend[s]))
	# A relaxed wrist droops a little toward the palm...
	var g := skeleton.get_bone_global_pose(hand)
	var fingers := (g.basis.y).normalized()
	palm = g.basis * _palm_local[s]
	var droop_axis := fingers.cross(palm)
	if droop_axis.length() > 0.01:
		_rotate_global(hand, Basis(droop_axis.normalized(), 0.12 * (1.0 - absf(_finger[s] - 0.35))))
	# ...and the hand trails behind the arm's motion (follow-through), so fast
	# moves end with a soft flick instead of a stiff stop.
	var vel := _hand_vel[s]
	var lag_axis := fingers.cross(vel)
	if lag_axis.length() > 0.001:
		_rotate_global(hand, Basis(lag_axis.normalized(), -clampf(vel.length() * 0.22, 0.0, 0.28)))


const FINGER_CASCADE := {"Index": 0.8, "Middle": 1.0, "Ring": 1.1, "Little": 1.22}
const FINGER_SPREAD := {"Index": 1.0, "Middle": 0.15, "Ring": -0.55, "Little": -1.0}


func _curl_fingers(side: String, s: String, t: float) -> void:
	if s == "R" and holding:
		_grip_fingers(_finger[s])
		return
	# Fingers close as far as the pose says, but never into the body: near the head
	# or torso they open just enough to stay outside (smoothed, so no popping).
	var hand := skeleton.get_bone_global_pose(_b[side + "Hand"]).origin
	var near_body := hand.distance_to(skeleton.get_bone_global_pose(_b["Head"]) * _head_c) < 0.42 \
			or (_push_out(hand, 0.11) - hand).length() > 0.001
	var allowed := 1.0
	if near_body:
		for trial: float in [1.0, 0.7, 0.45, 0.2, 0.0]:
			_apply_fingers(side, s, t, trial)
			allowed = trial
			if not _fingers_in_body(side):
				break
	var dt := maxf(_dt, 1.0 / 120.0)
	_finger_open[s] = allowed if allowed < _finger_open[s] else move_toward(_finger_open[s], allowed, 2.5 * dt)
	_apply_fingers(side, s, t, _finger_open[s])


## True if a finger's outer joints or tip are inside the head, torso or thighs.
func _fingers_in_body(side: String) -> bool:
	for finger in ["Index", "Middle", "Ring", "Little"]:
		if not _b.has(side + finger + "Distal"):
			continue
		var distal := skeleton.get_bone_global_pose(_b[side + finger + "Distal"])
		var mid := skeleton.get_bone_global_pose(_b[side + finger + "Intermediate"]).origin
		for q: Vector3 in [mid, distal.origin, distal.origin + distal.basis.y.normalized() * 0.022]:
			if (_push_out(q, 0.004) - q).length() > 0.004:
				return true
	return false


func _apply_fingers(side: String, s: String, t: float, scale: float) -> void:
	var x := 1.0 if s == "L" else -1.0
	var curl := _finger[s] * scale
	# Open hands fan the fingers a little; curled ones draw them together.
	var spread := clampf(0.22 - curl * 0.35, -0.08, 0.16)
	var i := 0
	for finger in ["Index", "Middle", "Ring", "Little"]:
		# Fingers curl a little more toward the little finger, like a resting hand,
		# and each drifts on its own so the hand never looks frozen.
		var own := curl * float(FINGER_CASCADE[finger]) + sin(t * (0.5 + i * 0.13) + x * 1.7 + i * 2.1) * 0.035 * scale
		for part in ["Proximal", "Intermediate", "Distal"]:
			var name: String = side + finger + part
			if not _b.has(name):
				continue
			var amount := own * (0.75 if part == "Proximal" else (1.0 if part == "Intermediate" else 0.7))
			var fan := 0.0
			if part == "Proximal":
				fan = spread * float(FINGER_SPREAD[finger])
			if finger == "Index" and _pointing[s]:
				amount = 0.04
				fan = 0.0
			_bend(_b[name], amount, fan)
		i += 1
	# Thumb: relaxed it rests along the index; it folds in over the curled
	# fingers when pointing or gripping.
	var tuck := clampf(curl, 0.0, 1.2) + (0.5 if _pointing[s] else 0.0)
	var thumb := {"Metacarpal": 0.12 + tuck * 0.22, "Proximal": 0.1 + tuck * 0.35, "Distal": 0.08 + tuck * 0.4}
	for part: String in thumb:
		var name: String = side + "Thumb" + part
		if _b.has(name):
			_bend(_b[name], float(thumb[part]) + sin(t * 0.45 + x) * 0.02, 0.0)


## Fingers wrapped round the flashlight barrel: knuckles and middle joints
## follow its curve, fingertips rest on it (not into it), fingers side by side;
## the thumb folds over the top. Amounts tuned against the barrel's radius.
const GRIP_FINGER := ["Index", "Middle", "Ring", "Little"]
## Barrel radius plus half a finger, in skeleton units: where a finger touches.
const GRIP_TOUCH := 0.0255
var _grip_fit: Dictionary[String, Array] = {}


func _grip_fingers(_curl: float) -> void:
	var hand := skeleton.get_bone_global_pose(_b["RightHand"])
	var centre := hand * _grip_center_local()
	var axis := (hand.basis * _grip_axis_local()).normalized()
	for finger: String in GRIP_FINGER:
		if not _b.has("Right" + finger + "Distal"):
			continue
		var bones: Array[int] = [_b["Right" + finger + "Proximal"], _b["Right" + finger + "Intermediate"], _b["Right" + finger + "Distal"]]
		var fan := -0.06 * float(FINGER_SPREAD[finger])  # fingers close together
		if not _grip_fit.has(finger):
			# Fit once (the grip's shape never changes): close the finger the way a
			# hand does, joint by joint, each segment stopping when the next joint
			# (and finally the fingertip) touches the barrel.
			var fit := [0.1, 0.0, 0.0]
			var limit := [1.25, 1.6, 1.0]
			for k in 3:
				_bend(bones[1], fit[1], 0.0)
				_bend(bones[2], fit[2], 0.0)
				var angle: float = fit[k]
				while angle < limit[k]:
					_bend(bones[k], angle + 0.03, fan if k == 0 else 0.0)
					if _grip_gap(bones, k, centre, axis) < GRIP_TOUCH:
						break
					angle += 0.03
				fit[k] = angle
				_bend(bones[k], angle, fan if k == 0 else 0.0)
			_grip_fit[finger] = fit
		var f: Array = _grip_fit[finger]
		_bend(bones[0], f[0], fan)
		_bend(bones[1], f[1], 0.0)
		_bend(bones[2], f[2], 0.0)
	# Thumb: aimed rather than bent, so it lands on the barrel: its last joint
	# rests on the near side of the barrel, its tip lies along it toward the lens.
	if not (_b.has("RightThumbMetacarpal") and _b.has("RightThumbProximal") and _b.has("RightThumbDistal")):
		return
	_bend(_b["RightThumbMetacarpal"], 0.35, 0.0)
	_bend(_b["RightThumbProximal"], 0.0, 0.0)
	_bend(_b["RightThumbDistal"], 0.0, 0.0)
	var c := centre
	var a := axis
	var base := skeleton.get_bone_global_pose(_b["RightThumbProximal"]).origin
	var r := (base - c) - a * (base - c).dot(a)
	if r.length() < 0.001:
		return
	var rb := r.length()
	var h := (base - c).dot(a)
	r = r.normalized()
	# The thumb's first segment can only reach so far: pick the point on the
	# barrel surface (at GRIP_THUMB_REST from the axis) exactly one segment away,
	# on the lens side.
	var seg := skeleton.get_bone_rest(_b["RightThumbDistal"]).origin.length()
	var k := h + sqrt(maxf(seg * seg - (rb - GRIP_THUMB_REST) * (rb - GRIP_THUMB_REST), 0.0))
	_aim(_b["RightThumbProximal"], _b["RightThumbDistal"], c + r * GRIP_THUMB_REST + a * k)
	var d := _b["RightThumbDistal"]
	var g := skeleton.get_bone_global_pose(d)
	var along := (a + r * 0.12).normalized()  # lying along the barrel, not into it
	_set_global_basis(d, Basis(Quaternion(g.basis.y.normalized(), along)) * g.basis)


## Distance from the barrel's axis to the far end of finger segment `k`
## (the next joint, or the fingertip for the last segment), also checking
## the middle of the segment.
func _grip_gap(bones: Array[int], k: int, centre: Vector3, axis: Vector3) -> float:
	var from := skeleton.get_bone_global_pose(bones[k])
	var to: Vector3
	if k < 2:
		to = skeleton.get_bone_global_pose(bones[k + 1]).origin
	else:
		to = from.origin + from.basis.y.normalized() * 0.022
	var least := INF
	for q: Vector3 in [from.origin.lerp(to, 0.5), to]:
		var d := (q - centre) - axis * (q - centre).dot(axis)
		least = minf(least, d.length())
	return least


## Bends a finger bone toward the palm (and fans it sideways) about the axes
## measured in _measure_hand.
func _bend(bone: int, amount: float, fan: float) -> void:
	var rest := skeleton.get_bone_rest(bone).basis
	var r := Basis(_curl_axis.get(bone, Vector3.RIGHT), amount)
	if absf(fan) > 0.0005:
		r = Basis(_spread_axis.get(bone, Vector3.FORWARD), fan) * r
	skeleton.set_bone_pose_rotation(bone, (rest * r).get_rotation_quaternion())


# --- IK helpers (all skeleton space) ----------------------------------------------

func _rest(bone_name: String) -> Vector3:
	return skeleton.get_bone_global_rest(_b[bone_name]).origin


## Solves upper/lower so `end` reaches `target`, bending toward `pole`.
func _two_bone(upper_name: String, lower_name: String, end_name: String, target: Vector3, pole: Vector3) -> void:
	var upper := _b[upper_name]
	var lower := _b[lower_name]
	var root := skeleton.get_bone_global_pose(upper).origin
	var a := skeleton.get_bone_rest(lower).origin.length()
	var b := skeleton.get_bone_rest(_b[end_name]).origin.length()
	var to := target - root
	var d := clampf(to.length(), absf(a - b) + 0.01, a + b - 0.001)
	var n := to.normalized()
	var cos_a := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var bend := pole - root
	bend = bend - n * bend.dot(n)
	if bend.length() < 0.02:  # pole on the line: bend backward rather than flip
		bend = Vector3.BACK.cross(n).cross(n)
	bend = bend.normalized()
	var elbow := root + n * a * cos_a + bend * a * sqrt(1.0 - cos_a * cos_a)
	var end := root + n * d
	# Bend around the joint's real hinge. Shortest-arc aiming from the A-pose
	# flips when the joint folds tight (hand behind the head), twisting the elbow
	# sideways; matching the hinge axis keeps elbows and knees bending the way
	# they actually bend, and the forearm's roll steady.
	var mid := skeleton.get_bone_global_pose(lower).origin
	var tip := skeleton.get_bone_global_pose(lower) * skeleton.get_bone_rest(_b[end_name]).origin
	var hinge_now := _hinge(root, mid, tip)
	var hinge_want := bend.cross(n).normalized()
	var u0 := (mid - root).normalized()
	var u1 := (elbow - root).normalized()
	var from := Basis(u0, hinge_now, u0.cross(hinge_now).normalized())
	var to_basis := Basis(u1, hinge_want, u1.cross(hinge_want).normalized())
	var swing := to_basis * from.transposed()
	_set_global_basis(upper, swing.orthonormalized() * skeleton.get_bone_global_pose(upper).basis)
	# Now fold the lower bone about the hinge, then take up any small remainder.
	var g := skeleton.get_bone_global_pose(lower)
	var cur := (g * skeleton.get_bone_rest(_b[end_name]).origin) - g.origin
	var want := end - g.origin
	var fold := cur.signed_angle_to(want, hinge_want)
	_set_global_basis(lower, Basis(hinge_want, fold) * g.basis)
	_aim(lower, _b[end_name], end)


## Hinge axis of a two-bone chain (normal of its bend plane, oriented like
## bend.cross(n) in _two_bone).
func _hinge(root: Vector3, mid: Vector3, tip: Vector3) -> Vector3:
	var n := (tip - root).normalized()
	var off := (mid - root) - n * (mid - root).dot(n)
	if off.length() < 0.0005:
		off = Vector3.BACK.cross(n).cross(n)
	return off.normalized().cross(n).normalized()


## Rotates `bone` so its child `child` lands on `point`.
func _aim(bone: int, child: int, point: Vector3) -> void:
	var g := skeleton.get_bone_global_pose(bone)
	var child_pos := g * skeleton.get_bone_rest(child).origin
	var from := (child_pos - g.origin).normalized()
	var to := (point - g.origin).normalized()
	if from.is_equal_approx(to):
		return
	var q := Quaternion(from, to)
	_set_global_basis(bone, Basis(q) * g.basis)


## Applies a skeleton-space rotation on top of the bone's current pose.
func _rotate_global(bone: int, rotation_skel: Basis) -> void:
	_set_global_basis(bone, rotation_skel * skeleton.get_bone_global_pose(bone).basis)


func _set_global_basis(bone: int, basis: Basis) -> void:
	var parent := skeleton.get_bone_parent(bone)
	var parent_basis := Basis.IDENTITY if parent < 0 else skeleton.get_bone_global_pose(parent).basis
	skeleton.set_bone_pose_rotation(bone, (parent_basis.inverse() * basis).orthonormalized().get_rotation_quaternion())


# --- First person ------------------------------------------------------------------

## In first person the head is shrunk away so the camera sees the body, not the
## inside of the skull; a second copy draws only the shadow, head included.
func _apply_first_person() -> void:
	if skeleton == null:
		return
	if first_person and _shadow_model == null:
		_shadow_model = _instance(load(model_path))
		_shadow_skeleton = _shadow_model.find_children("*", "Skeleton3D", true, false)[0]
		for mesh: MeshInstance3D in _shadow_model.find_children("*", "MeshInstance3D", true, false):
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	if _shadow_model != null:
		_shadow_model.visible = first_person
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if first_person else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	skeleton.set_bone_pose_scale(_b["Head"], Vector3.ONE * (0.001 if first_person else 1.0))
