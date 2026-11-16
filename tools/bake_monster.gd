extends SceneTree
## Sculpts the spirit's body parts as signed distance fields and bakes them to
## meshes in res://assets/monster/. Rerun after changing any shape:
##   godot --headless --path . -s res://tools/bake_monster.gd
##
## Each part is modelled in its own pivot space (see scripts/monster_body.gd
## for where the pivots sit). Units are metres; the creature faces -Z.

const OUT_DIR := "res://assets/monster/"
const A := SdfShape.ADD
const S := SdfShape.SUB


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var start := Time.get_ticks_msec()
	_bake("pelvis", _pelvis(), Vector3(-0.16, -0.17, -0.13), Vector3(0.16, 0.16, 0.12), 0.006)
	_bake("torso", _torso(), Vector3(-0.24, -0.05, -0.17), Vector3(0.24, 0.66, 0.15), 0.006)
	_bake("neck", _neck(), Vector3(-0.07, -0.05, -0.08), Vector3(0.07, 0.23, 0.06), 0.004)
	_bake("head", _head(), Vector3(-0.12, -0.06, -0.15), Vector3(0.12, 0.27, 0.15), 0.0035)
	_bake("jaw", _jaw(), Vector3(-0.075, -0.08, -0.1), Vector3(0.075, 0.03, 0.025), 0.003)
	_bake("upper_arm", _upper_arm(), Vector3(-0.07, -0.6, -0.07), Vector3(0.07, 0.06, 0.07), 0.004)
	_bake("forearm", _forearm(), Vector3(-0.05, -0.54, -0.05), Vector3(0.05, 0.04, 0.05), 0.0035)
	_bake("hand_r", _hand(1.0), Vector3(-0.07, -0.29, -0.09), Vector3(0.07, 0.03, 0.05), 0.0025)
	_bake("hand_l", _hand(-1.0), Vector3(-0.07, -0.29, -0.09), Vector3(0.07, 0.03, 0.05), 0.0025)
	_bake("thigh", _thigh(), Vector3(-0.08, -0.51, -0.08), Vector3(0.08, 0.07, 0.07), 0.005)
	_bake("shin", _shin(), Vector3(-0.06, -0.46, -0.06), Vector3(0.06, 0.05, 0.07), 0.004)
	_bake("foot", _foot(), Vector3(-0.06, -0.08, -0.24), Vector3(0.06, 0.04, 0.07), 0.003)
	print("baked in %.1fs" % ((Time.get_ticks_msec() - start) / 1000.0))
	quit()


func _bake(part: String, shape: SdfShape, lo: Vector3, hi: Vector3, cell: float) -> void:
	var t := Time.get_ticks_msec()
	var mesh := shape.to_mesh(lo, hi, cell)
	var tris := mesh.surface_get_array_index_len(0) / 3 if mesh.get_surface_count() > 0 else 0
	var lods: int = RenderingServer.mesh_get_surface(mesh.get_rid(), 0).get("lods", []).size() if mesh.get_surface_count() > 0 else 0
	var err := ResourceSaver.save(mesh, OUT_DIR + part + ".res", ResourceSaver.FLAG_COMPRESS)
	print("  %-10s %6d tris  %d lods  %5.1fs  %s" % [part, tris, lods, (Time.get_ticks_msec() - t) / 1000.0, "ok" if err == OK else "SAVE FAILED"])


# --- Body ---------------------------------------------------------------------------

## Pivot: hips (0.93 m above the floor).
func _pelvis() -> SdfShape:
	var s := SdfShape.new()
	s.ellipsoid(Vector3(0, -0.01, 0.0), Vector3(0.115, 0.085, 0.08))
	s.cone(Vector3(0, 0.0, 0.005), Vector3(0, 0.13, 0.0), 0.085, 0.08, A, 0.04)  # waist
	for side: float in [-1.0, 1.0]:
		s.sphere(Vector3(0.1 * side, 0.035, -0.045), 0.024, A, 0.025)  # hip bones
		s.cone(Vector3(0.08 * side, -0.03, 0.0), Vector3(0.08 * side, -0.13, 0.0), 0.058, 0.052, A, 0.04)  # thigh tops
	# Hollows below the hip bones.
	for side: float in [-1.0, 1.0]:
		s.sphere(Vector3(0.075 * side, -0.02, -0.105), 0.03, S, 0.02)
	return s


## Pivot: spine, 0.04 m above the hips. Sunken belly, ribs pushing through.
func _torso() -> SdfShape:
	var s := SdfShape.new()
	s.cone(Vector3(0, 0.0, 0.005), Vector3(0, 0.24, 0.0), 0.08, 0.1, A)  # waist
	s.ellipsoid(Vector3(0, 0.36, 0.0), Vector3(0.14, 0.18, 0.105), A, 0.06)  # ribcage
	# Sloping shoulders and trapezius running up into the neck.
	for side: float in [-1.0, 1.0]:
		s.cone(Vector3(0.0, 0.56, 0.0), Vector3(0.15 * side, 0.52, 0.0), 0.045, 0.04, A, 0.05)
		s.sphere(Vector3(0.158 * side, 0.515, -0.005), 0.045, A, 0.03)  # shoulder
		s.ellipsoid(Vector3(0.075 * side, 0.43, 0.08), Vector3(0.055, 0.07, 0.022), A, 0.03)  # shoulder blade
		s.capsule(Vector3(0.02 * side, 0.535, -0.075), Vector3(0.15 * side, 0.545, -0.035), 0.013, A, 0.012)  # collarbone
	s.cone(Vector3(0, 0.5, -0.005), Vector3(0, 0.63, -0.025), 0.05, 0.038, A, 0.03)  # neck base
	# Ribs: thin ridges across the front and sides, dipping toward the sternum.
	for i in 6:
		var y := 0.47 - i * 0.045
		var dy := y - 0.36
		var squash := sqrt(maxf(0.0, 1.0 - pow(dy / 0.18, 2.0)))
		var radii := Vector3(0.14 * squash + 0.002, 0.0, 0.105 * squash + 0.002)
		s.rib(Vector3(0, y, 0), radii, 0.008, 0.03 + i * 0.004, 0.04, 0.01)
	s.capsule(Vector3(0, 0.49, -0.1), Vector3(0, 0.33, -0.103), 0.012, A, 0.015)  # sternum
	# Spine knobs down the back.
	for i in 9:
		s.sphere(Vector3(0, 0.08 + i * 0.06, 0.07 + sin(i * 0.4) * 0.03), 0.014, A, 0.012)
	# Starved, hollow stomach under the ribs.
	s.ellipsoid(Vector3(0, 0.17, -0.135), Vector3(0.08, 0.08, 0.06), S, 0.035)
	# Hollows above the collarbones.
	for side: float in [-1.0, 1.0]:
		s.sphere(Vector3(0.07 * side, 0.565, -0.06), 0.022, S, 0.015)
		s.paint(Vector3(0.07 * side, 0.56, -0.06), 0.035, Color(0.55, 0.5, 0.5), 0.5)
	s.paint(Vector3(0, 0.17, -0.1), 0.09, Color(0.6, 0.56, 0.55), 0.5)  # starved stomach
	return s


## Pivot: base of the neck. Long and thin, tendons standing out.
func _neck() -> SdfShape:
	var s := SdfShape.new()
	s.cone(Vector3(0, -0.02, 0.0), Vector3(0, 0.21, 0.0), 0.04, 0.029)
	for side: float in [-1.0, 1.0]:
		s.capsule(Vector3(0.028 * side, 0.18, 0.005), Vector3(0.012 * side, 0.0, -0.032), 0.01, A, 0.01)
	s.sphere(Vector3(0, 0.085, -0.03), 0.011, A, 0.01)  # throat
	return s


## Pivot: top of the neck. An emaciated skull under wet skin: high bald
## dome, deep sockets, hollow cheeks. The lower jaw is a separate part.
func _head() -> SdfShape:
	var s := SdfShape.new()
	s.ellipsoid(Vector3(0, 0.125, 0.02), Vector3(0.08, 0.118, 0.098))  # cranium
	s.ellipsoid(Vector3(0, 0.15, 0.045), Vector3(0.072, 0.098, 0.082), A, 0.03)  # swollen back of the skull
	s.cone(Vector3(0, 0.075, -0.045), Vector3(0, 0.012, -0.064), 0.056, 0.034, A, 0.03)  # face, tapering down
	s.cone(Vector3(0, -0.01, 0.025), Vector3(0, 0.05, 0.02), 0.027, 0.03, A, 0.02)  # neck join
	s.capsule(Vector3(-0.036, 0.1, -0.09), Vector3(0.036, 0.1, -0.09), 0.006, A, 0.025)  # brow
	for side: float in [-1.0, 1.0]:
		s.ellipsoid(Vector3(0.05 * side, 0.052, -0.074), Vector3(0.016, 0.01, 0.014), A, 0.02)  # cheekbone
		s.ellipsoid(Vector3(0.079 * side, 0.07, 0.002), Vector3(0.006, 0.018, 0.012), A, 0.008)  # ear stub
	s.capsule(Vector3(0, 0.062, -0.102), Vector3(0, 0.04, -0.107), 0.005, A, 0.014)  # flat nose
	s.ellipsoid(Vector3(0, 0.012, -0.087), Vector3(0.015, 0.0045, 0.006), A, 0.008)  # thin upper lip
	# Carve: everything below the mouth line belongs to the jaw.
	s.ellipsoid(Vector3(0, -0.058, -0.08), Vector3(0.062, 0.062, 0.06), S, 0.004)
	for side: float in [-1.0, 1.0]:
		s.sphere(Vector3(0.086 * side, 0.1, -0.035), 0.03, S, 0.02)  # gaunt temples
		s.sphere(Vector3(0.056 * side, 0.02, -0.08), 0.02, S, 0.016)  # hollow cheeks
		s.ellipsoid(Vector3(0.03 * side, 0.07, -0.1), Vector3(0.021, 0.023, 0.036), S, 0.012)  # deep sockets
		s.ellipsoid(Vector3(0.042 * side, 0.062, -0.094), Vector3(0.01, 0.012, 0.022), S, 0.01)  # drooping outer corner
		s.sphere(Vector3(0.007 * side, 0.038, -0.11), 0.0042, S, 0.003)  # nostrils
	# Paint: black-bruised sockets, dark lips, shadowed hollows.
	var bruise := Color(0.13, 0.1, 0.11)
	for side: float in [-1.0, 1.0]:
		s.paint(Vector3(0.03 * side, 0.068, -0.085), 0.048, bruise, 1.0)
		s.paint(Vector3(0.034 * side, 0.042, -0.09), 0.03, Color(0.32, 0.26, 0.28), 0.7)  # bags under the eyes
		s.paint(Vector3(0.056 * side, 0.02, -0.075), 0.03, Color(0.5, 0.45, 0.46), 0.5)  # cheek hollows
		s.paint(Vector3(0.086 * side, 0.1, -0.04), 0.035, Color(0.55, 0.52, 0.52), 0.4)  # temples
		s.paint(Vector3(0.007 * side, 0.038, -0.108), 0.008, Color(0.08, 0.06, 0.06), 1.0)  # nostrils
	s.paint(Vector3(0, 0.01, -0.086), 0.026, Color(0.26, 0.18, 0.2), 0.9)  # upper lip
	return s


## Pivot: jaw hinge, just below the ears. Sculpted in head space and shifted,
## so the jaw lines up with the face when closed.
const JAW_PIVOT := Vector3(0, 0.025, -0.005)

func _jaw() -> SdfShape:
	var s := SdfShape.new()
	var o := -JAW_PIVOT
	for side: float in [-1.0, 1.0]:
		s.cone(Vector3(0.04 * side, 0.026, -0.008) + o, Vector3(0.016 * side, -0.022, -0.058) + o, 0.011, 0.011, A, 0.022)  # jawline
	s.ellipsoid(Vector3(0, -0.025, -0.066) + o, Vector3(0.016, 0.014, 0.013), A, 0.018)  # narrow chin
	s.ellipsoid(Vector3(0, -0.006, -0.056) + o, Vector3(0.029, 0.019, 0.025), A, 0.02)  # lower face
	s.ellipsoid(Vector3(0, 0.001, -0.079) + o, Vector3(0.014, 0.0038, 0.0055), A, 0.008)  # thin lower lip
	for side: float in [-1.0, 1.0]:
		s.sphere(Vector3(0.04 * side, -0.005, -0.06) + o, 0.014, S, 0.014)  # sunken jaw hollows
	s.paint(Vector3(0, 0.001, -0.078) + o, 0.024, Color(0.26, 0.18, 0.2), 0.9)  # lower lip
	for side: float in [-1.0, 1.0]:
		s.paint(Vector3(0.038 * side, -0.005, -0.058) + o, 0.026, Color(0.52, 0.47, 0.48), 0.5)
	return s


# --- Arms -----------------------------------------------------------------------------

## Pivot: shoulder joint. Hangs along -Y.
func _upper_arm() -> SdfShape:
	var s := SdfShape.new()
	s.cone(Vector3(0, 0.0, 0), Vector3(0, -0.54, 0), 0.034, 0.022)
	s.ellipsoid(Vector3(0, -0.05, 0.0), Vector3(0.04, 0.075, 0.04), A, 0.03)  # wasted deltoid
	s.sphere(Vector3(0, -0.555, 0.006), 0.026, A, 0.02)  # elbow
	s.sphere(Vector3(0, -0.55, 0.024), 0.016, A, 0.012)  # elbow point
	return s


## Pivot: elbow.
func _forearm() -> SdfShape:
	var s := SdfShape.new()
	s.cone(Vector3(0, 0.0, 0), Vector3(0, -0.5, 0), 0.028, 0.016)
	s.ellipsoid(Vector3(0, -0.09, 0.004), Vector3(0.031, 0.1, 0.026), A, 0.03)
	s.ellipsoid(Vector3(0, -0.505, 0.0), Vector3(0.022, 0.014, 0.016), A, 0.01)  # wrist bones
	return s


## Pivot: wrist. Palm faces -Z, fingers hang along -Y with a slight curl
## toward the palm. thumb_side = +1 puts the thumb at +X.
func _hand(thumb_side: float) -> SdfShape:
	var s := SdfShape.new()
	s.ellipsoid(Vector3(0, -0.05, 0.0), Vector3(0.032, 0.055, 0.012))  # palm
	var lengths := [0.062, 0.07, 0.066, 0.055]
	for f in 4:
		var x := (f - 1.5) * 0.017 * -thumb_side
		var base := Vector3(x, -0.1, 0.0)
		s.sphere(base, 0.0105, A, 0.01)  # knuckle
		var dir := Vector3((f - 1.5) * -0.05 * -thumb_side, -1.0, 0.0).normalized()
		var p := base
		var radius := 0.0088
		var seg: float = lengths[f]
		for joint in 3:
			dir = dir.rotated(Vector3.RIGHT, 0.2)  # curl toward the palm (-Z)
			var q := p + dir * seg
			var end_radius := radius * 0.82 if joint < 2 else 0.0022  # last bone tapers to a claw
			s.cone(p, q, radius, end_radius, A, 0.004)
			if joint < 2:
				s.sphere(q, radius * 0.95, A, 0.004)  # knobbly joint
			if joint == 2:
				s.paint(q, 0.03, Color(0.16, 0.13, 0.11), 1.0)  # dark claw
			p = q
			radius = end_radius
			seg *= 0.82
	# Thumb.
	var t0 := Vector3(0.026 * thumb_side, -0.035, -0.006)
	var t1 := t0 + Vector3(0.012 * thumb_side, -0.05, -0.02)
	var t2 := t1 + Vector3(0.002 * thumb_side, -0.045, -0.018)
	s.cone(t0, t1, 0.011, 0.009, A, 0.01)
	s.cone(t1, t2, 0.009, 0.0022, A, 0.004)
	s.paint(t2, 0.025, Color(0.16, 0.13, 0.11), 1.0)
	# Tendons along the back of the hand.
	for f in 4:
		var x := (f - 1.5) * 0.017 * -thumb_side
		s.capsule(Vector3(x * 0.6, -0.01, 0.009), Vector3(x, -0.095, 0.007), 0.0045, A, 0.006)
	return s


# --- Legs ------------------------------------------------------------------------------

## Pivot: hip joint.
func _thigh() -> SdfShape:
	var s := SdfShape.new()
	s.cone(Vector3(0, 0.02, 0), Vector3(0, -0.44, 0), 0.052, 0.03)
	s.sphere(Vector3(0, -0.45, -0.004), 0.037, A, 0.025)  # knee
	s.sphere(Vector3(0, -0.44, -0.03), 0.02, A, 0.015)  # kneecap
	return s


## Pivot: knee.
func _shin() -> SdfShape:
	var s := SdfShape.new()
	s.cone(Vector3(0, 0.0, 0), Vector3(0, -0.42, 0), 0.033, 0.02)
	s.ellipsoid(Vector3(0, -0.11, 0.018), Vector3(0.03, 0.1, 0.03), A, 0.03)  # wasted calf
	s.capsule(Vector3(0, -0.03, -0.025), Vector3(0, -0.36, -0.016), 0.01, A, 0.015)  # shin bone
	for side: float in [-1.0, 1.0]:
		s.sphere(Vector3(0.02 * side, -0.42, 0.0), 0.015, A, 0.012)  # ankle bones
	return s


## Pivot: ankle. Long, bony foot with long toes.
func _foot() -> SdfShape:
	var s := SdfShape.new()
	s.sphere(Vector3(0, -0.025, 0.025), 0.028)  # heel
	s.cone(Vector3(0, -0.02, 0.01), Vector3(0, -0.035, -0.13), 0.026, 0.019, A, 0.02)
	for t in 5:
		var x := (t - 2.0) * 0.014
		var length := 0.06 - absf(t - 1.0) * 0.008
		var base := Vector3(x, -0.038, -0.13 + absf(t - 1.5) * 0.008)
		s.capsule(Vector3(x * 0.5, -0.025, -0.04), base, 0.006, A, 0.008)  # foot bones
		var tip := base + Vector3(x * 0.15, -0.012, -length)
		s.cone(base, tip, 0.0095, 0.004, A, 0.006)
	return s
