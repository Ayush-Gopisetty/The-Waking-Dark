class_name Props
## Loads the prop models (assets/props: Poly Haven CC0 furniture and the
## battery/key models made in Blender) and fits them into place.

const DIR := "res://assets/props/"

## Short names for the model files.
const MODELS := {
	"bed": "gothicbed_01/GothicBed_01_1k.gltf",
	"wardrobe": "gothiccabinet_01/GothicCabinet_01_1k.gltf",
	"hutch": "vintage_cabinet_01/vintage_cabinet_01_1k.gltf",
	"bookshelf": "wooden_bookshelf_worn/wooden_bookshelf_worn_1k.gltf",
	"shelf": "shelf_01/Shelf_01_1k.gltf",
	"clock": "vintage_grandfather_clock_01/vintage_grandfather_clock_01_1k.gltf",
	"chair": "woodenchair_01/WoodenChair_01_1k.gltf",
	"stool": "woodentable_02/WoodenTable_02_1k.gltf",
	"crate": "wooden_crate_01/wooden_crate_01_1k.gltf",
	"candleholders": "brass_candleholders/brass_candleholders_1k.gltf",
	"oil_lamp": "vintage_oil_lamp/vintage_oil_lamp_1k.gltf",
	"mirror": "ornate_mirror_01/ornate_mirror_01_1k.gltf",
	"painting": "fancy_picture_frame_01/fancy_picture_frame_01_1k.gltf",
	"flashlight": "flashlight/flashlight.glb",
	"battery": "battery/battery.glb",
	"key_brass": "key/key_brass.glb",
	"key_brass_tag": "key/key_brass_tag.glb",
	"key_iron_tag": "key/key_iron_tag.glb",
	"id_jason": "id/id_jason.glb",
}

static var _cache: Dictionary = {}
static var _shelf_wood: StandardMaterial3D


static func instance(model: String) -> Node3D:
	var path: String = DIR + MODELS.get(model, model)
	if not _cache.has(path):
		_cache[path] = load(path)
	var scene: PackedScene = _cache[path]
	if scene == null:
		push_error("Props: missing model %s" % path)
		return Node3D.new()
	return scene.instantiate()


## Bounding box of everything under `node`, in `node`'s own space.
static func bounds(node: Node3D) -> AABB:
	var acc: Array = [null]
	_bounds(node, Transform3D.IDENTITY, acc, true)
	return acc[0] if acc[0] != null else AABB()


static func _bounds(n: Node, xf: Transform3D, acc: Array, is_root: bool) -> void:
	var t := xf
	if n is Node3D and not is_root:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var a: AABB = t * (n as MeshInstance3D).mesh.get_aabb()
		acc[0] = a if acc[0] == null else (acc[0] as AABB).merge(a)
	for c in n.get_children():
		_bounds(c, t, acc, false)


## Places `model` standing on `floor_point`, turned by `yaw` (the model's front,
## +Z, faces that way), scaled uniformly so it fits inside `size` (x, y, z in
## world axes after the turn). With `by_height`, the height matches size.y
## exactly instead; with `stretch`, every axis matches size (slightly
## non-uniform). Returns the holder node (already added to `parent`).
static func place(parent: Node, model: String, floor_point: Vector3, size: Vector3, yaw: float = 0.0, by_height: bool = false, stretch: bool = false) -> Node3D:
	var holder := Node3D.new()
	holder.position = floor_point
	holder.rotation.y = yaw
	parent.add_child(holder)
	var m := instance(model)
	holder.add_child(m)
	var b := bounds(m)
	var turned := absf(sin(yaw)) > 0.7
	var want := Vector3(size.z, size.y, size.x) if turned else size
	var fit := Vector3(want.x / maxf(b.size.x, 0.001), want.y / maxf(b.size.y, 0.001), want.z / maxf(b.size.z, 0.001))
	var s := fit.y
	if not by_height:
		s = minf(s, minf(fit.x, fit.z))
	m.scale = fit if stretch else Vector3.ONE * s
	m.position = -Vector3(b.get_center().x, b.position.y, b.get_center().z) * m.scale
	return holder


## Fills a placed bookcase with books and darkens its pale wood.
static func stock_bookcase(holder: Node3D, seed_value: int, skip: Array = []) -> void:
	var m := holder.get_child(0) as Node3D
	for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
		if _shelf_wood == null:
			var src := mi.get_active_material(0) as StandardMaterial3D
			if src != null:
				_shelf_wood = src.duplicate() as StandardMaterial3D
				_shelf_wood.albedo_color = Color(0.45, 0.4, 0.36)
		if _shelf_wood != null:
			mi.material_override = _shelf_wood
	m.add_child(Furnishing.bookcase_books(seed_value, skip))


## Height of the model's top surface over its centre region (vertex scan), in
## the holder's space; for putting things on a bed or a shelf.
static func top_height(holder: Node3D, radius: float) -> float:
	var top := 0.0
	for mi: MeshInstance3D in holder.find_children("*", "MeshInstance3D", true, false):
		var xf := _relative(holder, mi)
		for s in mi.mesh.get_surface_count():
			var verts: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for v in verts:
				var p := xf * v
				if absf(p.x) < radius and absf(p.z) < radius:
					top = maxf(top, p.y)
	return top


static func _relative(root: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf
