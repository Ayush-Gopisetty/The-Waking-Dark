class_name MonsterBody
extends Node3D
## The spirit's physical body: a rigged, skinned model (assets/monster/spirit.glb,
## built in Blender on a MakeHuman base) animated procedurally in code. Look: a
## pale, wet, emaciated humanoid. Bald elongated skull tilted to one side, hollow
## black eye sockets, slack mouth, ribs showing, arms long enough that the
## fingers hang past the knees.
##
## Shadowy presence: it carries its own darkness. A black fog cloud moves with it
## (drinks the flashlight beam and the ambient fog glow), a dark halo bleeds its
## silhouette into the dark, black smoke rolls off its back, trails from its
## hands and pools at its feet. All of it grows in a chase and thins out when
## the bright beam burns it.
##
## The animation is written as rotations of "virtual pivots" (as if every limb
## hung straight down from its joint, creature facing local -Z); _apply() maps
## them onto the skeleton's bones.
##
## Origin is at the feet; the creature faces local -Z.

const MODEL := "res://assets/monster/spirit.glb"
const MODEL_SCALE := 0.95
const BURN_COLOR := Color(1.0, 0.45, 0.15)
## Eye centres in skeleton space (from the Blender landmarks), sunk into the sockets.
const EYE := Vector3(0.034, 1.969, 0.131)

var _skin: StandardMaterial3D
var _hollow: StandardMaterial3D
var _smoke: CPUParticles3D
var _hand_smoke: Array[CPUParticles3D] = []
var _pool: CPUParticles3D
var _aura: FogVolume
var _aura_mat: FogMaterial
var _halo: ShaderMaterial

const HALO_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, blend_mix, shadows_disabled;
uniform float grow = 0.018;
uniform float strength = 0.85;
uniform sampler2D wisps : repeat_enable, filter_linear;
void vertex() {
	VERTEX += NORMAL * grow;
}
void fragment() {
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float n = texture(wisps, UV * 3.0 + vec2(TIME * 0.04, -TIME * 0.07)).r;
	ALBEDO = vec3(0.0);
	ALPHA = clamp(pow(rim, 1.6) * strength * (0.45 + n), 0.0, 0.95);
}
"""

var _model: Node3D
var _skel: Skeleton3D
var _b: Dictionary[String, int] = {}
## Per bone: straightening correction (skeleton space) so a zero pivot rotation
## means "hangs straight down", like the virtual pivots.
var _fix: Dictionary[int, Basis] = {}
## Pivot rotations (Euler, pivot space) set by animate(), applied by _apply().
var _rot: Dictionary[String, Vector3] = {}
var _hip_drop := 0.0
var _hip_sway := 0.0
var _foot_rest_y := 0.0

var _phase := 0.0
var _time := 0.0
var _chase_blend := 0.0
var _burn_blend := 0.0
var _twitch := Vector2.ZERO
var _twitch_target := Vector2.ZERO
var _twitch_timer := 0.0

## Bones the animation drives, parents before children.
const DRIVEN: Array[String] = [
	"Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "Jaw",
	"LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot",
]


func _ready() -> void:
	_make_materials()
	_build()
	_build_smoke()
	_build_shadow()
	animate(0.0, 0.0, false, 0.0)


## Called every physics frame by the spirit AI.
## ground_speed in m/s; burn is 0..1 (how badly the light is hurting it).
func animate(delta: float, ground_speed: float, chasing: bool, burn: float) -> void:
	if _skel == null:
		return
	_time += delta
	_phase += ground_speed * delta * 3.0
	var stride := clampf(ground_speed / 1.5, 0.0, 1.0)
	_chase_blend = lerpf(_chase_blend, 1.0 if chasing else 0.0, minf(1.0, 4.0 * delta))
	_burn_blend = lerpf(_burn_blend, burn, minf(1.0, 8.0 * delta))
	var chase := _chase_blend * (1.0 - _burn_blend)
	var burning := _burn_blend
	var calm := 1.0 - chase

	# Legs: a lurching, uneven gait. The right leg drags a little.
	for i in 2:
		var side := -1.0 if i == 0 else 1.0  # left (-X in pivot space) first
		var s: String = "Left" if i == 0 else "Right"
		var swing := sin(_phase + (0.0 if i == 0 else PI))
		var reach := 0.55 if i == 0 else 0.42
		var thigh := 0.14 + swing * reach * stride + burning * 0.3
		var knee := -(0.3 + maxf(0.0, -swing) * 0.85 * stride + burning * 0.5)
		_rot[s + "UpperLeg"] = Vector3(thigh, 0, side * 0.03)
		_rot[s + "LowerLeg"] = Vector3(knee, 0, 0)
		_rot[s + "Foot"] = Vector3(-(thigh + knee), 0, 0)

	# Torso: hunched and sunken. Leans in to chase, recoils from the light.
	# The pivot torso bends at one joint; the bones share it out up the spine.
	var breath := sin(_time * 1.1) * 0.025
	var lurch := absf(sin(_phase)) * stride
	_hip_drop = lurch * 0.04
	_hip_sway = sin(_phase) * 0.07 * stride
	_rot["Hips"] = Vector3(0, 0, _hip_sway)
	var spine := Vector3(-0.38 - chase * 0.32 + burning * 0.25 + breath, sin(_phase) * 0.1 * stride, -sin(_phase) * 0.08 * stride + 0.05)
	_rot["Spine"] = spine * 0.35
	_rot["Chest"] = spine * 0.35
	_rot["UpperChest"] = spine * 0.3

	# Arms: hang long and limp, sway with the gait, reach out in a chase, and
	# claw up over the face when burned.
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var s: String = "Left" if i == 0 else "Right"
		var swing := -sin(_phase + (0.0 if i == 0 else PI)) * 0.3 * stride
		var hang := 0.3 + swing + sin(_time * 0.9 + i) * 0.03
		var reach := 1.6 + sin(_time * 7.0 + i * 2.0) * 0.12
		var shield := 1.5 + sin(_time * 31.0 + i) * 0.06
		_rot[s + "UpperArm"] = Vector3(lerpf(lerpf(hang, reach, chase), shield, burning), 0, side * lerpf(lerpf(0.12, 0.16, chase), -0.75, burning))
		_rot[s + "LowerArm"] = Vector3(lerpf(lerpf(0.12, 0.2, chase), 2.1, burning), 0, 0)
		_rot[s + "Hand"] = Vector3(lerpf(0.05, 0.35, chase) + sin(_time * 11.0 + i) * 0.06 * chase, 0, 0)

	# Head: lolls to one side with sudden snaps. In a chase it locks forward.
	_twitch_timer -= delta
	if _twitch_timer <= 0.0:
		_twitch_timer = randf_range(0.7, 3.0)
		_twitch_target = Vector2(randf_range(-0.2, 0.2), randf_range(-0.35, 0.35))
	_twitch = _twitch.lerp(_twitch_target, minf(1.0, 18.0 * delta))
	_rot["Neck"] = Vector3(-0.2 - chase * 0.25 - burning * 0.2, (sin(_time * 0.5) * 0.12 + _twitch.y) * calm, 0)
	_rot["Head"] = Vector3(0.45 + chase * 0.35 - burning * 0.35 + _twitch.x * calm, 0, lerpf(0.45, 0.12, chase) + _twitch.y * 0.3 * calm)
	# The jaw hangs slack; it gapes in a chase and screams when burned.
	_rot["Jaw"] = Vector3(-(0.04 + chase * 0.16 + burning * 0.26 + absf(sin(_time * 1.9)) * 0.02), 0, 0)

	_apply()

	# Burning: skin glows from within, the body shudders, smoke thickens.
	_skin.emission_energy_multiplier = burning * (2.2 + sin(_time * 38.0) * 0.9)
	position.x = sin(_time * 55.0) * 0.025 * burning
	position.z = cos(_time * 47.0) * 0.025 * burning
	if _smoke != null:
		_smoke.speed_scale = 1.0 + burning * 2.5

	# Its darkness: thicker in a chase, breathing slowly, burned away by the light.
	var gloom := (1.0 + chase * 0.6 + sin(_time * 0.7) * 0.15) * (1.0 - burning * 0.85)
	if _aura_mat != null:
		_aura_mat.density = 3.0 * gloom
		_aura.rotation.y = _time * 0.15  # the noise inside swirls
	if _halo != null:
		_halo.set_shader_parameter("strength", 0.85 * gloom)
	for s in _hand_smoke:
		s.speed_scale = 1.0 + chase + burning * 2.0
		s.emitting = burning < 0.6
	if _pool != null:
		_pool.emitting = burning < 0.6


# --- Skeleton mapping --------------------------------------------------------------

## Pivot-space Euler -> skeleton-space rotation. The model is turned 180° about Y
## (it faces +Z in its own space), which flips the sign of X and Z rotations.
func _euler(v: Vector3) -> Basis:
	return Basis.from_euler(Vector3(-v.x, v.y, -v.z))


func _apply() -> void:
	# Frame of each driven bone = parent's frame * its own pivot rotation.
	var frame: Dictionary[int, Basis] = {}
	var target: Dictionary[int, Basis] = {}
	for name in DRIVEN:
		var bone: int = _b[name]
		var parent := _skel.get_bone_parent(bone)
		var pf := _frame_of(parent, frame)
		var f: Basis = pf * _euler(_rot.get(name, Vector3.ZERO))
		frame[bone] = f
		target[bone] = f * _fix.get(bone, Basis.IDENTITY) * _skel.get_bone_global_rest(bone).basis
	for name in DRIVEN:
		var bone: int = _b[name]
		var parent := _skel.get_bone_parent(bone)
		var parent_basis := Basis.IDENTITY
		if parent >= 0:
			parent_basis = target[parent] if target.has(parent) else _inherited(parent, frame)
		_skel.set_bone_pose_rotation(bone, (parent_basis.inverse() * target[bone]).orthonormalized().get_rotation_quaternion())
	# Hips: sway and lurch, then keep the lower foot planted on the floor.
	var hips: int = _b["Hips"]
	var rest_hips := _skel.get_bone_rest(hips).origin
	_skel.set_bone_pose_position(hips, rest_hips)
	var low := minf(_skel.get_bone_global_pose(_b["LeftFoot"]).origin.y, _skel.get_bone_global_pose(_b["RightFoot"]).origin.y)
	_skel.set_bone_pose_position(hips, rest_hips + Vector3(0, _foot_rest_y - low - _hip_drop, 0))


## Frame of a bone that may not be driven: inherit from the nearest driven ancestor.
func _frame_of(bone: int, frame: Dictionary[int, Basis]) -> Basis:
	while bone >= 0:
		if frame.has(bone):
			return frame[bone]
		bone = _skel.get_bone_parent(bone)
	return Basis.IDENTITY


## Global basis of an undriven bone: rides along with its driven ancestor.
func _inherited(bone: int, frame: Dictionary[int, Basis]) -> Basis:
	var b := bone
	var fix := Basis.IDENTITY
	while b >= 0:
		if frame.has(b):
			fix = _fix.get(b, Basis.IDENTITY)
			break
		b = _skel.get_bone_parent(b)
	return _frame_of(bone, frame) * fix * _skel.get_bone_global_rest(bone).basis


# --- Construction ------------------------------------------------------------------

func _build() -> void:
	var scene: PackedScene = load(MODEL)
	if scene == null:
		push_error("MonsterBody: could not load %s (open the project in the editor once to import it)" % MODEL)
		return
	_model = scene.instantiate()
	_model.rotation.y = PI
	_model.scale = Vector3.ONE * MODEL_SCALE
	add_child(_model)
	_skel = _model.find_children("*", "Skeleton3D", true, false)[0]
	for i in _skel.get_bone_count():
		_b[_skel.get_bone_name(i)] = i
	for mesh: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		var src := mesh.mesh.surface_get_material(0) as BaseMaterial3D
		if src != null:
			_skin.albedo_texture = src.albedo_texture
		mesh.material_override = _skin

	# Straighten the A-pose limbs so a zero pivot rotation hangs them straight down
	# (arms a touch outward so the long hands clear the thighs).
	for side in ["Left", "Right"]:
		var out := 1.0 if side == "Left" else -1.0  # the character's left is +X here
		var arm_down := Vector3(out * 0.06, -1, 0).normalized()
		var upper := _straighten(side + "UpperArm", side + "LowerArm", arm_down, Basis.IDENTITY)
		var lower := _straighten(side + "LowerArm", side + "Hand", arm_down, upper)
		_fix[_b[side + "Hand"]] = lower
		var thigh := _straighten(side + "UpperLeg", side + "LowerLeg", Vector3.DOWN, Basis.IDENTITY)
		var shin := _straighten(side + "LowerLeg", side + "Foot", Vector3.DOWN, thigh)
		_fix[_b[side + "Foot"]] = shin
	_foot_rest_y = _skel.get_bone_global_rest(_b["LeftFoot"]).origin.y

	# Glossy black eyes deep in the sockets, to catch the flashlight.
	for side: float in [-1.0, 1.0]:
		var attach := BoneAttachment3D.new()
		attach.bone_name = "Head"
		_skel.add_child(attach)
		var head_rest := _skel.get_bone_global_rest(_b["Head"])
		var eye := MeshInstance3D.new()
		eye.mesh = _sphere(0.0125)
		eye.material_override = _hollow
		eye.position = head_rest.affine_inverse() * Vector3(EYE.x * side, EYE.y, EYE.z)
		attach.add_child(eye)


## Correction that turns bone -> child onto `dir`, after the parent's correction.
func _straighten(bone_name: String, child_name: String, dir: Vector3, parent_fix: Basis) -> Basis:
	var a := _skel.get_bone_global_rest(_b[bone_name]).origin
	var c := _skel.get_bone_global_rest(_b[child_name]).origin
	var have := (parent_fix * (c - a)).normalized()
	var fix := Basis(Quaternion(have, dir)) * parent_fix
	_fix[_b[bone_name]] = fix
	return fix


func _build_smoke() -> void:
	# Rolling off its back and shoulders.
	_smoke = _smoke_emitter(48, 3.2, 0.7, 0.7, 1.5)
	_smoke.emission_box_extents = Vector3(0.2, 0.55, 0.14)
	_smoke.position = Vector3(0, 1.2, 0.1)
	_smoke.direction = Vector3(0, 1, 0.3)
	add_child(_smoke)

	# Trailing from the fingers (world-space particles, so they stream behind it).
	for side in (["Left", "Right"] if _skel != null else []):
		var attach := BoneAttachment3D.new()
		attach.bone_name = side + "Hand"
		_skel.add_child(attach)
		var wisp := _smoke_emitter(16, 1.8, 0.65, 0.3, 0.8)
		wisp.emission_box_extents = Vector3(0.04, 0.08, 0.04)
		wisp.position = Vector3(0, 0.1, 0)  # toward the fingers (bone +Y)
		wisp.direction = Vector3(0, -1, 0)
		wisp.gravity = Vector3(0, -0.05, 0)
		attach.add_child(wisp)
		_hand_smoke.append(wisp)

	# Pooling around its feet, low and slow.
	_pool = _smoke_emitter(22, 4.0, 0.6, 0.7, 1.8)
	_pool.emission_box_extents = Vector3(0.35, 0.03, 0.3)
	_pool.position = Vector3(0, 0.08, 0)
	_pool.direction = Vector3(1, 0.05, 0)
	_pool.spread = 180.0
	_pool.flatness = 0.9
	_pool.gravity = Vector3(0, 0.0, 0)
	add_child(_pool)


func _smoke_emitter(amount: int, lifetime: float, alpha: float, size_min: float, size_max: float) -> CPUParticles3D:
	var smoke := CPUParticles3D.new()
	smoke.amount = amount
	smoke.lifetime = lifetime
	smoke.preprocess = lifetime  # already smoking when it appears
	smoke.local_coords = false
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	smoke.spread = 35.0
	smoke.initial_velocity_min = 0.05
	smoke.initial_velocity_max = 0.2
	smoke.gravity = Vector3(0, 0.12, 0)
	smoke.scale_amount_min = size_min
	smoke.scale_amount_max = size_max
	smoke.angle_min = 0.0
	smoke.angle_max = 360.0
	smoke.angular_velocity_min = -20.0
	smoke.angular_velocity_max = 20.0
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.4))
	grow.add_point(Vector2(1, 1.4))
	smoke.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(0, 0, 0, 0))
	fade.set_color(1, Color(0, 0, 0, 0))
	fade.add_point(0.25, Color(0.01, 0.01, 0.012, alpha))
	smoke.color_ramp = fade

	var puff := GradientTexture2D.new()
	puff.fill = GradientTexture2D.FILL_RADIAL
	puff.fill_from = Vector2(0.5, 0.5)
	puff.fill_to = Vector2(1.0, 0.5)
	var falloff := Gradient.new()
	falloff.set_color(0, Color(1, 1, 1, 1))
	falloff.set_color(1, Color(1, 1, 1, 0))
	puff.gradient = falloff
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = puff
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var quad := QuadMesh.new()
	quad.size = Vector2(0.6, 0.6)
	quad.material = material
	smoke.mesh = quad
	return smoke


func _build_shadow() -> void:
	if _skel == null:
		return
	# A black fog cloud around the body: soaks up the flashlight beam and the
	# ambient fog glow, so it stands in its own patch of darkness.
	var noise := FastNoiseLite.new()
	noise.frequency = 0.08
	noise.fractal_octaves = 3
	var density := NoiseTexture3D.new()
	density.width = 48
	density.height = 48
	density.depth = 48
	density.seamless = true
	density.noise = noise
	_aura_mat = FogMaterial.new()
	_aura_mat.albedo = Color(0, 0, 0)
	_aura_mat.emission = Color(0, 0, 0)
	_aura_mat.edge_fade = 1.4
	_aura_mat.density_texture = density
	_aura = FogVolume.new()
	_aura.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
	_aura.size = Vector3(1.9, 2.9, 1.7)
	_aura.position = Vector3(0, 1.2, 0.05)
	_aura.material = _aura_mat
	add_child(_aura)

	# A dark halo hugging the silhouette, so its outline bleeds into the dark.
	var wisp_noise := FastNoiseLite.new()
	wisp_noise.frequency = 0.02
	wisp_noise.fractal_octaves = 3
	var wisps := NoiseTexture2D.new()
	wisps.noise = wisp_noise
	wisps.seamless = true
	var shader := Shader.new()
	shader.code = HALO_SHADER
	_halo = ShaderMaterial.new()
	_halo.shader = shader
	_halo.set_shader_parameter("wisps", wisps)
	_skin.next_pass = _halo


func _make_materials() -> void:
	# Fine wrinkles and pores on top of the painted skin.
	var pore_noise := FastNoiseLite.new()
	pore_noise.frequency = 0.06
	pore_noise.fractal_octaves = 4
	var pores := NoiseTexture2D.new()
	pores.noise = pore_noise
	pores.seamless = true
	pores.as_normal_map = true
	pores.bump_strength = 4.0

	# Wet, glossy skin: low roughness plus a clearcoat for the slick highlights.
	# The albedo texture comes from the model (painted in Blender).
	_skin = StandardMaterial3D.new()
	_skin.roughness = 0.3
	_skin.metallic_specular = 0.7
	_skin.clearcoat_enabled = true
	_skin.clearcoat = 1.0
	_skin.clearcoat_roughness = 0.1
	_skin.normal_enabled = true
	_skin.normal_texture = pores
	_skin.normal_scale = 0.25
	_skin.uv1_scale = Vector3(6.0, 6.0, 1.0)
	_skin.emission_enabled = true
	_skin.emission = BURN_COLOR
	var crack_noise := FastNoiseLite.new()
	crack_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	crack_noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	crack_noise.frequency = 0.04
	var crack_ramp := Gradient.new()
	crack_ramp.set_color(0, Color(1, 1, 1))
	crack_ramp.set_color(1, Color(0, 0, 0))
	crack_ramp.set_offset(0, 0.0)
	crack_ramp.set_offset(1, 0.12)
	var cracks := NoiseTexture2D.new()
	cracks.noise = crack_noise
	cracks.color_ramp = crack_ramp
	cracks.seamless = true
	_skin.emission_texture = cracks
	_skin.emission_energy_multiplier = 0.0

	# Hollow eyes: black, but wet.
	_hollow = StandardMaterial3D.new()
	_hollow.albedo_color = Color(0.0, 0.0, 0.0)
	_hollow.roughness = 0.06
	_hollow.metallic_specular = 0.9


func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	return mesh
