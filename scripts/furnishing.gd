class_name Furnishing
## Hand-built furniture and fittings (visual only; the level adds collision).
## Every builder returns a Node3D whose origin is the floor centre of the piece,
## width along X, depth along Z, height along Y; the "front" faces +Z.

static var _brass: StandardMaterial3D
static var _iron: StandardMaterial3D
static var _cloth: StandardMaterial3D
static var _glass: StandardMaterial3D


static func _mat(color: Color, metallic: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = rough
	return m


static func brass() -> StandardMaterial3D:
	if _brass == null:
		_brass = _mat(Color(0.62, 0.47, 0.2), 0.9, 0.35)
	return _brass


static func iron() -> StandardMaterial3D:
	if _iron == null:
		_iron = _mat(Color(0.12, 0.12, 0.13), 0.7, 0.45)
	return _iron


static func cloth() -> StandardMaterial3D:
	if _cloth == null:
		_cloth = _mat(Color(0.2, 0.06, 0.07), 0.0, 1.0)
		_cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _cloth


static func _box(parent: Node3D, pos: Vector3, size: Vector3, material: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func _cyl(parent: Node3D, pos: Vector3, radius: float, height: float, material: Material, rot := Vector3.ZERO, top_radius := -1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius if top_radius < 0.0 else top_radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.rings = 1
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func _ball(parent: Node3D, pos: Vector3, radius: float, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 10
	mesh.rings = 5
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _darker(wood: Material) -> Material:
	var m := (wood as StandardMaterial3D).duplicate() as StandardMaterial3D
	m.albedo_color = m.albedo_color.darkened(0.35)
	return m


## A plain wooden table: overhanging top, apron, turned-looking legs and a stretcher.
static func table(size: Vector3, wood: Material) -> Node3D:
	var root := Node3D.new()
	var top := 0.045
	_box(root, Vector3(0, size.y - top * 0.5, 0), Vector3(size.x, top, size.z), wood)
	var inset := 0.07
	var lx := size.x * 0.5 - inset
	var lz := size.z * 0.5 - inset
	var leg_h := size.y - top
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_cyl(root, Vector3(sx * lx, leg_h * 0.5, sz * lz), 0.032, leg_h, wood, Vector3.ZERO, 0.045)
	var dark := _darker(wood)
	var apron := 0.09
	_box(root, Vector3(0, leg_h - apron * 0.5, lz), Vector3(lx * 2.0, apron, 0.025), dark)
	_box(root, Vector3(0, leg_h - apron * 0.5, -lz), Vector3(lx * 2.0, apron, 0.025), dark)
	_box(root, Vector3(lx, leg_h - apron * 0.5, 0), Vector3(0.025, apron, lz * 2.0), dark)
	_box(root, Vector3(-lx, leg_h - apron * 0.5, 0), Vector3(0.025, apron, lz * 2.0), dark)
	_box(root, Vector3(0, 0.17, 0), Vector3(lx * 2.0, 0.03, 0.03), dark)  # stretcher
	return root


## A kitchen counter: cabinet doors with brass knobs under a thick top and backsplash.
static func counter(size: Vector3, wood: Material) -> Node3D:
	var root := Node3D.new()
	var dark := _darker(wood)
	var kick := 0.09
	_box(root, Vector3(0, kick * 0.5, -0.02), Vector3(size.x - 0.04, kick, size.z - 0.1), dark)
	var body_h := size.y - kick - 0.05
	_box(root, Vector3(0, kick + body_h * 0.5, 0), Vector3(size.x - 0.02, body_h, size.z - 0.04), wood)
	_box(root, Vector3(0, size.y - 0.025, 0.015), Vector3(size.x + 0.04, 0.05, size.z + 0.04), dark)
	_box(root, Vector3(0, size.y + 0.07, -size.z * 0.5 + 0.015), Vector3(size.x + 0.04, 0.14, 0.03), dark)
	var doors := maxi(2, int(round(size.x / 0.7)))
	var w := (size.x - 0.06) / doors
	for i in doors:
		var x := -size.x * 0.5 + 0.03 + w * (i + 0.5)
		_box(root, Vector3(x, kick + body_h * 0.5, size.z * 0.5 - 0.018), Vector3(w - 0.03, body_h - 0.1, 0.02), dark)
		_box(root, Vector3(x, kick + body_h * 0.5, size.z * 0.5 - 0.006), Vector3(w - 0.12, body_h - 0.2, 0.012), wood)
		var side := 1.0 if i % 2 == 0 else -1.0
		_ball(root, Vector3(x + side * (w * 0.5 - 0.07), kick + body_h * 0.75, size.z * 0.5 + 0.015), 0.018, brass())
	return root


## A writing desk: top, two drawer pedestals with brass pulls, and a back panel.
static func desk(size: Vector3, wood: Material) -> Node3D:
	var root := Node3D.new()
	var dark := _darker(wood)
	var top := 0.05
	_box(root, Vector3(0, size.y - top * 0.5, 0), Vector3(size.x, top, size.z), wood)
	var ped_w := minf(0.42, size.x * 0.3)
	var ped_h := size.y - top
	for s: float in [-1.0, 1.0]:
		var x := s * (size.x * 0.5 - ped_w * 0.5 - 0.03)
		_box(root, Vector3(x, ped_h * 0.5 + 0.03, 0), Vector3(ped_w, ped_h - 0.06, size.z - 0.08), wood)
		_box(root, Vector3(x, 0.03, 0), Vector3(ped_w + 0.02, 0.06, size.z - 0.04), dark)
		for d in 3:
			var y := 0.2 + d * ((ped_h - 0.3) / 3.0)
			_box(root, Vector3(x, y, size.z * 0.5 - 0.035), Vector3(ped_w - 0.04, (ped_h - 0.3) / 3.0 - 0.02, 0.02), dark)
			_box(root, Vector3(x, y, size.z * 0.5 - 0.02), Vector3(0.1, 0.012, 0.012), brass())
	_box(root, Vector3(0, size.y * 0.5 - 0.02, -size.z * 0.5 + 0.04), Vector3(size.x - ped_w * 2.0 - 0.08, size.y - 0.14, 0.02), dark)
	_box(root, Vector3(0, size.y - top - 0.05, size.z * 0.5 - 0.05), Vector3(size.x - ped_w * 2.0 - 0.08, 0.1, 0.02), dark)
	return root


## A cast-iron boiler furnace: riveted bands, a door with a glowing grate, flue, legs.
## The door faces -X in the level, so the caller turns it.
static func furnace(size: Vector3, fire: Material) -> Node3D:
	var root := Node3D.new()
	var leg := 0.14
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_box(root, Vector3(sx * (size.x * 0.5 - 0.1), leg * 0.5, sz * (size.z * 0.5 - 0.1)), Vector3(0.12, leg, 0.12), iron())
	var body_h := size.y - leg - 0.25
	_box(root, Vector3(0, leg + body_h * 0.5, 0), Vector3(size.x, body_h, size.z), iron())
	# Cast mouldings and riveted bands around the body.
	for y: float in [leg + 0.04, leg + body_h - 0.04]:
		_box(root, Vector3(0, y, 0), Vector3(size.x + 0.06, 0.07, size.z + 0.06), _darker(iron()))
	for y: float in [leg + body_h * 0.33, leg + body_h * 0.7]:
		_box(root, Vector3(0, y, 0), Vector3(size.x + 0.03, 0.05, size.z + 0.03), _darker(iron()))
		for i in 7:
			var t := -size.z * 0.5 + 0.12 + i * ((size.z - 0.24) / 6.0)
			_ball(root, Vector3(size.x * 0.5 + 0.02, y, t), 0.016, brass())
			_ball(root, Vector3(-size.x * 0.5 - 0.02, y, t), 0.016, brass())
	# Dome top and flue pipe to the ceiling.
	_cyl(root, Vector3(0, size.y - 0.18, 0), minf(size.x, size.z) * 0.42, 0.14, iron(), Vector3.ZERO, minf(size.x, size.z) * 0.3)
	_cyl(root, Vector3(0, size.y + 0.3, 0), 0.12, 0.9, iron())
	# Firing door on the -X face: frame, glowing opening with bars, handle, ash pan.
	var fx := -size.x * 0.5 - 0.025
	_box(root, Vector3(fx, leg + body_h * 0.52, 0), Vector3(0.05, 0.62, 0.78), _darker(iron()))
	_box(root, Vector3(fx - 0.026, leg + body_h * 0.52, 0), Vector3(0.02, 0.46, 0.62), fire)  # proud of the door frame, not flush with it
	for i in 5:
		_box(root, Vector3(fx - 0.03, leg + body_h * 0.52, -0.27 + i * 0.135), Vector3(0.025, 0.5, 0.025), iron())
	_cyl(root, Vector3(fx - 0.05, leg + body_h * 0.52 - 0.28, 0.3), 0.012, 0.16, brass(), Vector3(PI * 0.5, 0, 0))
	_box(root, Vector3(fx - 0.12, 0.26, 0), Vector3(0.3, 0.04, 0.6), _darker(iron()))
	return root


## A window: moulded frame, cross mullions, sill, glass and drawn curtains.
## `size.x` is the width, `size.y` the height; the window faces +Z.
static func window(size: Vector2, glow: Material, curtains := true) -> Node3D:
	var root := Node3D.new()
	var wood := _mat(Color(0.13, 0.09, 0.07), 0.0, 0.7)
	var f := 0.07
	# The glass sits clear of the wall face (never coplanar with it), behind the frame.
	_box(root, Vector3(0, 0, 0.02), Vector3(size.x - 0.02, size.y - 0.02, 0.004), glow)
	_box(root, Vector3(0, 0, 0.005), Vector3(size.x + 0.04, size.y + 0.04, 0.01), wood)  # reveal behind the glass
	_box(root, Vector3(0, size.y * 0.5 - f * 0.5, 0.02), Vector3(size.x + f, f, 0.08), wood)
	_box(root, Vector3(0, -size.y * 0.5 + f * 0.5, 0.02), Vector3(size.x + f, f, 0.08), wood)
	for s: float in [-1.0, 1.0]:
		_box(root, Vector3(s * (size.x * 0.5), 0, 0.02), Vector3(f, size.y, 0.08), wood)
	_box(root, Vector3(0, 0, 0.02), Vector3(0.035, size.y, 0.05), wood)      # mullion
	_box(root, Vector3(0, size.y * 0.12, 0.02), Vector3(size.x, 0.035, 0.05), wood)  # transom
	_box(root, Vector3(0, -size.y * 0.5 - 0.035, 0.07), Vector3(size.x + 0.2, 0.05, 0.16), wood)  # sill
	_box(root, Vector3(0, size.y * 0.5 + 0.05, 0.05), Vector3(size.x + 0.3, 0.05, 0.1), wood)    # lintel
	if curtains:
		_cyl(root, Vector3(0, size.y * 0.5 + 0.16, 0.14), 0.014, size.x + 0.5, iron(), Vector3(0, 0, PI * 0.5))
		for s: float in [-1.0, 1.0]:
			var x := s * (size.x * 0.5 + 0.12)
			for i in 3:
				_box(root, Vector3(x + s * (i - 1) * 0.05, -0.1, 0.14 + (i % 2) * 0.025), Vector3(0.08, size.y + 0.2 - i * 0.05, 0.015), cloth(), Vector3(0, 0, s * (i - 1) * 0.03))
	return root


## A hook rail: backboard, three iron hooks and a small brass plate.
static func hook_rail(width: float) -> Node3D:
	var root := Node3D.new()
	var board := _mat(Color(0.34, 0.24, 0.15), 0.0, 0.8)
	_box(root, Vector3(0, 0, 0), Vector3(width, 0.12, 0.025), board)
	_box(root, Vector3(0, 0.07, 0.005), Vector3(width + 0.04, 0.025, 0.035), board)
	for i in 3:
		var x := (i - 1) * width * 0.3
		_cyl(root, Vector3(x, -0.01, 0.045), 0.008, 0.07, iron(), Vector3(PI * 0.5, 0, 0))
		_cyl(root, Vector3(x, 0.014, 0.08), 0.008, 0.05, iron())
		_ball(root, Vector3(x, 0.04, 0.08), 0.011, iron())
		_ball(root, Vector3(x, 0.0, 0.016), 0.015, brass())
	return root


## A manila case folder with loose pages sticking out and a string tie.
static func case_folder(paper: Material) -> Node3D:
	var root := Node3D.new()
	var manila := _mat(Color(0.62, 0.5, 0.3), 0.0, 0.9)
	_box(root, Vector3(0, 0.007, 0), Vector3(0.23, 0.012, 0.31), manila)
	_box(root, Vector3(-0.07, 0.007, -0.17), Vector3(0.08, 0.012, 0.03), manila)  # tab
	for i in 4:
		_box(root, Vector3(0.0, 0.0145 + i * 0.0008, 0.015), Vector3(0.2, 0.001, 0.27), paper, Vector3(0, (i - 1.5) * 0.04, 0))
	_box(root, Vector3(0, 0.0165, 0.0), Vector3(0.012, 0.002, 0.31), _mat(Color(0.75, 0.7, 0.55), 0.0, 1.0))
	return root


## Books for the worn bookcase model, in the model's own units (add as a child of
## the model so it scales with it). One draw call: every book is a coloured box
## in a single MultiMesh. `skip` lists shelf rows to leave bare.
const SHELF_TOPS := [0.10, 0.40, 0.68, 0.96, 1.28, 1.66]
const SHELF_GAPS := [0.24, 0.22, 0.24, 0.28, 0.34, 0.36]


static func bookcase_books(seed_value: int, skip: Array = []) -> MultiMeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var items: Array = []  # [Transform3D, Color]
	for row in SHELF_TOPS.size():
		if row in skip:
			continue
		var gap: float = SHELF_GAPS[row]
		var x := -0.57
		while x < 0.55:
			var w := rng.randf_range(0.03, 0.065)
			var h := rng.randf_range(0.7, 0.95) * gap
			var d := rng.randf_range(0.2, 0.3)
			var hue := rng.randf_range(0.0, 0.08) if rng.randf() < 0.6 else rng.randf_range(0.08, 0.62)
			var color := Color.from_hsv(hue, rng.randf_range(0.35, 0.65), rng.randf_range(0.22, 0.42)).srgb_to_linear()
			var lean := 0.0 if rng.randf() < 0.92 else rng.randf_range(-0.3, 0.3)
			var basis := Basis(Vector3(0, 0, 1), lean) * Basis.from_scale(Vector3(w, h, d))
			items.append([Transform3D(basis, Vector3(x + w * 0.5, SHELF_TOPS[row] + h * 0.5, 0.02)), color])
			x += w + 0.004 + (rng.randf_range(0.05, 0.16) if rng.randf() < 0.07 else 0.0)
	var mesh := BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.85
	mesh.material = mat
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = mesh
	multi.instance_count = items.size()
	for i in items.size():
		multi.set_instance_transform(i, items[i][0])
		multi.set_instance_color(i, items[i][1])
	var node := MultiMeshInstance3D.new()
	node.multimesh = multi
	return node


## A cast-iron kitchen range: four burners, an oven door with a handle, a warming
## shelf, legs and a flue. Width along X, front faces +Z.
static func stove(size: Vector3) -> Node3D:
	var root := Node3D.new()
	var dark := _darker(iron())
	var leg := 0.12
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_cyl(root, Vector3(sx * (size.x * 0.5 - 0.06), leg * 0.5, sz * (size.z * 0.5 - 0.06)), 0.03, leg, iron(), Vector3.ZERO, 0.045)
	var body_h := size.y - leg - 0.04
	_box(root, Vector3(0, leg + body_h * 0.5, 0), Vector3(size.x, body_h, size.z), iron())
	_box(root, Vector3(0, size.y - 0.02, 0), Vector3(size.x + 0.04, 0.04, size.z + 0.04), dark)  # hob plate
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var p := Vector3(sx * size.x * 0.22, size.y + 0.006, sz * size.z * 0.2 - 0.04)
			_cyl(root, p, 0.09, 0.012, iron())
			_cyl(root, p + Vector3(0, 0.008, 0), 0.05, 0.008, dark)
	# Oven door: raised panel, a dull glass window, a brass handle bar and a thermometer dial.
	var fz := size.z * 0.5 + 0.012
	_box(root, Vector3(0, leg + body_h * 0.42, fz), Vector3(size.x - 0.16, body_h * 0.6, 0.025), dark)
	_box(root, Vector3(0, leg + body_h * 0.46, fz + 0.016), Vector3(size.x * 0.4, body_h * 0.22, 0.008), _mat(Color(0.05, 0.03, 0.02), 0.2, 0.2))
	_cyl(root, Vector3(0, leg + body_h * 0.68, fz + 0.05), 0.011, size.x - 0.28, brass(), Vector3(0, 0, PI * 0.5))
	for sx: float in [-1.0, 1.0]:
		_box(root, Vector3(sx * (size.x * 0.5 - 0.15), leg + body_h * 0.68, fz + 0.03), Vector3(0.02, 0.02, 0.04), brass())
	_ball(root, Vector3(size.x * 0.32, leg + body_h * 0.9, fz), 0.022, brass())
	_ball(root, Vector3(-size.x * 0.32, leg + body_h * 0.9, fz), 0.022, brass())
	# Warming shelf on posts and the flue up the back wall.
	for s: float in [-1.0, 1.0]:
		_cyl(root, Vector3(s * (size.x * 0.5 - 0.04), size.y + 0.2, -size.z * 0.5 + 0.06), 0.012, 0.4, iron())
	_box(root, Vector3(0, size.y + 0.4, -size.z * 0.5 + 0.12), Vector3(size.x, 0.02, 0.2), dark)
	_cyl(root, Vector3(0, size.y + 1.0, -size.z * 0.5 + 0.1), 0.065, 2.0, iron())
	return root


## A turned wooden stand: base, column, rim and top plate (candle stand / key plinth).
static func pedestal(size: Vector3, wood: Material) -> Node3D:
	var root := Node3D.new()
	var dark := _darker(wood)
	_box(root, Vector3(0, 0.04, 0), Vector3(size.x, 0.08, size.z), dark)
	_box(root, Vector3(0, 0.1, 0), Vector3(size.x - 0.08, 0.05, size.z - 0.08), wood)
	_cyl(root, Vector3(0, size.y * 0.5, 0), size.x * 0.17, size.y - 0.2, wood, Vector3.ZERO, size.x * 0.13)
	for y: float in [0.3, size.y * 0.5, size.y - 0.3]:
		_cyl(root, Vector3(0, y, 0), size.x * 0.23, 0.04, wood)
	_box(root, Vector3(0, size.y - 0.03, 0), Vector3(size.x, 0.06, size.z), dark)
	_box(root, Vector3(0, size.y - 0.07, 0), Vector3(size.x - 0.1, 0.04, size.z - 0.1), wood)
	return root


## A brass dish with a cluster of wax candles and small flames.
static func candle_cluster(flame: Material) -> Node3D:
	var root := Node3D.new()
	var wax := _mat(Color(0.8, 0.74, 0.58), 0.0, 0.7)
	_cyl(root, Vector3(0, 0.012, 0), 0.11, 0.024, brass(), Vector3.ZERO, 0.08)
	_cyl(root, Vector3(0, 0.03, 0), 0.115, 0.01, brass())
	for i in 3:
		var offset := Vector3((i - 1) * 0.07, 0.0, (i % 2) * 0.05 - 0.02)
		var h := 0.14 + i * 0.05
		_cyl(root, offset + Vector3(0, 0.03 + h * 0.5, 0), 0.016, h, wax)
		_box(root, offset + Vector3(0, 0.03 + h + 0.006, 0), Vector3(0.003, 0.012, 0.003), iron())
		var f := _ball(root, offset + Vector3(0, 0.03 + h + 0.03, 0), 0.011, flame)
		f.scale = Vector3(0.7, 1.7, 0.7)
	return root


## A settee: padded seat and back, turned arms and short legs.
static func bench(size: Vector3, wood: Material) -> Node3D:
	var root := Node3D.new()
	var dark := _darker(wood)
	var fabric := _mat(Color(0.16, 0.08, 0.09), 0.0, 1.0)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_cyl(root, Vector3(sx * (size.x * 0.5 - 0.05), 0.12, sz * (size.z * 0.5 - 0.05)), 0.03, 0.24, wood, Vector3.ZERO, 0.04)
	_box(root, Vector3(0, 0.27, 0), Vector3(size.x, 0.06, size.z), dark)
	_box(root, Vector3(0, 0.35, 0.02), Vector3(size.x - 0.14, 0.12, size.z - 0.08), fabric)
	_box(root, Vector3(0, 0.62, -size.z * 0.5 + 0.06), Vector3(size.x - 0.1, 0.5, 0.1), fabric, Vector3(-0.12, 0, 0))
	_box(root, Vector3(0, 0.9, -size.z * 0.5 + 0.03), Vector3(size.x, 0.07, 0.06), dark)
	for s: float in [-1.0, 1.0]:
		_box(root, Vector3(s * (size.x * 0.5 - 0.035), 0.5, 0.0), Vector3(0.07, 0.07, size.z), dark)
		_box(root, Vector3(s * (size.x * 0.5 - 0.035), 0.4, 0.0), Vector3(0.05, 0.28, 0.05), wood)
		_box(root, Vector3(s * (size.x * 0.5 - 0.035), 0.6, -size.z * 0.5 + 0.06), Vector3(0.07, 0.7, 0.07), dark)
	return root


## A chandelier lying where it fell: tilted iron ring, candle cups and a broken chain.
static func chandelier(size: Vector3) -> Node3D:
	var root := Node3D.new()
	var ring := Node3D.new()
	ring.position = Vector3(0, 0.22, 0)
	ring.rotation = Vector3(0.18, 0.4, 0.12)
	root.add_child(ring)
	var torus := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.5
	tm.outer_radius = 0.56
	tm.rings = 24
	tm.ring_segments = 8
	torus.mesh = tm
	torus.material_override = iron()
	ring.add_child(torus)
	torus.scale = Vector3(1.0, 1.0, size.z / size.x * 1.35)
	for i in 6:
		var a := i * TAU / 6.0
		var p := Vector3(cos(a) * 0.53, 0.0, sin(a) * 0.53 * (size.z / size.x * 1.35))
		_cyl(ring, p + Vector3(0, 0.04, 0), 0.03, 0.08, brass(), Vector3.ZERO, 0.04)
		if i != 2 and i != 4:
			_cyl(ring, p + Vector3(0, 0.15, 0), 0.014, 0.14, _mat(Color(0.75, 0.7, 0.55), 0.0, 0.7))
		_box(ring, p * 0.5, Vector3(0.52, 0.015, 0.015), iron(), Vector3(0, -a, 0))
	_cyl(ring, Vector3(0, 0.18, 0), 0.03, 0.36, iron())
	for i in 4:
		_cyl(root, Vector3(0.35 + i * 0.1, 0.03, -0.1 + i * 0.08), 0.012, 0.1, iron(), Vector3(PI * 0.5, 0, i * 0.7))
	return root


## Collapsed masonry and splintered beams, jumbled inside `size`.
static func rubble(size: Vector3, wood: Material, stone: Material, seed_value: int) -> Node3D:
	var root := Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in 14:
		var s := Vector3(rng.randf_range(0.15, 0.5), rng.randf_range(0.1, 0.25), rng.randf_range(0.15, 0.4))
		var p := Vector3(rng.randf_range(-0.5, 0.5) * size.x, rng.randf_range(0.0, 0.5) * size.y + s.y * 0.5, rng.randf_range(-0.5, 0.5) * size.z)
		_box(root, p - Vector3(0, size.y * 0.5, 0), s, stone, Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * PI, rng.randf_range(-0.4, 0.4)))
	for i in 5:
		var len := rng.randf_range(0.8, 1.5)
		var p := Vector3(rng.randf_range(-0.4, 0.4) * size.x, rng.randf_range(0.2, 0.6) * size.y, rng.randf_range(-0.4, 0.4) * size.z)
		_box(root, p - Vector3(0, size.y * 0.5, 0), Vector3(len, 0.09, 0.14), wood, Vector3(rng.randf_range(-0.5, 0.5), rng.randf() * PI, rng.randf_range(-0.6, 0.6)))
	return root
