class_name SdfShape
extends RefCounted
## A tiny signed-distance-field sculpting kit plus a surface-nets mesher.
## Used offline by tools/bake_monster.gd to turn blended primitives into
## smooth meshes. Not used at runtime.
##
## Build a shape by stacking operations in order:
##   shape.ellipsoid(...)            adds (smooth union with blend k)
##   shape.sphere(..., SUB, 0.01)    carves (smooth subtraction)

enum { ADD, SUB }
enum Kind { SPHERE, ELLIPSOID, CONE, RIB }

## Each op: [kind, mode, k, a, b, r1, r2, radii, bound_center, bound_radius]
var _ops: Array = []
## Vertex-colour paint: [center, radius, colour, strength]. Multiplies the
## material's albedo, so it darkens sockets, lips, claw tips and so on.
var _paints: Array = []


## Tints the surface near `center`, fading out over `radius`.
func paint(center: Vector3, radius: float, color: Color, strength: float = 1.0) -> SdfShape:
	_paints.append([center, radius, color, strength])
	return self


func _paint_at(p: Vector3) -> Color:
	var col := Color.WHITE
	for entry: Array in _paints:
		var d := p.distance_to(entry[0])
		var radius: float = entry[1]
		if d >= radius:
			continue
		var f := 1.0 - smoothstep(radius * 0.45, radius, d)  # full strength in the inner half
		col = col.lerp(entry[2], f * entry[3])
	return col


func sphere(center: Vector3, radius: float, mode: int = ADD, k: float = 0.0) -> SdfShape:
	_ops.append([Kind.SPHERE, mode, k, center, Vector3.ZERO, radius, 0.0, Vector3.ZERO, center, radius])
	return self


func ellipsoid(center: Vector3, radii: Vector3, mode: int = ADD, k: float = 0.0) -> SdfShape:
	var bound := maxf(radii.x, maxf(radii.y, radii.z))
	_ops.append([Kind.ELLIPSOID, mode, k, center, Vector3.ZERO, 0.0, 0.0, radii, center, bound])
	return self


## Capsule that tapers from radius r1 at `a` to r2 at `b`.
func cone(a: Vector3, b: Vector3, r1: float, r2: float, mode: int = ADD, k: float = 0.0) -> SdfShape:
	var mid := (a + b) * 0.5
	var bound := a.distance_to(b) * 0.5 + maxf(r1, r2)
	_ops.append([Kind.CONE, mode, k, a, b, r1, r2, Vector3.ZERO, mid, bound])
	return self


func capsule(a: Vector3, b: Vector3, r: float, mode: int = ADD, k: float = 0.0) -> SdfShape:
	return cone(a, b, r, r, mode, k)


## A rib: an elliptical ring (radii.x, radii.z) around `center`, tube radius
## `tube`, kept only where z < z_limit (the front and sides), dipping by
## `slope` toward the front.
func rib(center: Vector3, radii: Vector3, tube: float, slope: float, z_limit: float, k: float = 0.0) -> SdfShape:
	var bound := maxf(radii.x, radii.z) + tube + absf(slope)
	_ops.append([Kind.RIB, ADD, k, center, Vector3(z_limit, 0, 0), tube, slope, radii, center, bound])
	return self


func eval(p: Vector3) -> float:
	var d := 1e9
	for op: Array in _ops:
		var mode: int = op[1]
		var k: float = op[2]
		# Cheap rejection: a lower bound on the distance to this primitive.
		var lower: float = p.distance_to(op[8]) - op[9]
		if mode == ADD:
			if lower > d + k:
				continue
		elif lower > k:
			continue
		var s := _prim(op, p)
		if mode == ADD:
			d = _smin(d, s, k)
		else:
			d = -_smin(-d, s, k)
	return d


func _prim(op: Array, p: Vector3) -> float:
	match op[0]:
		Kind.SPHERE:
			return p.distance_to(op[3]) - op[5]
		Kind.ELLIPSOID:
			var r: Vector3 = op[7]
			var q: Vector3 = p - op[3]
			var k0 := (q / r).length()
			var k1 := (q / (r * r)).length()
			if k1 < 1e-9:
				return -minf(r.x, minf(r.y, r.z))
			return k0 * (k0 - 1.0) / k1
		Kind.CONE:
			return _round_cone(p, op[3], op[4], op[5], op[6])
		Kind.RIB:
			var c: Vector3 = op[3]
			var r: Vector3 = op[7]
			var q: Vector3 = p - c
			var front := clampf(-q.z / r.z, 0.0, 1.0)
			var e := (Vector2(q.x / r.x, q.z / r.z).length() - 1.0) * minf(r.x, r.z)
			var dy: float = q.y + op[6] * front
			var tube: float = op[5]
			var z_limit: float = op[4].x
			var ring: float = sqrt(e * e + dy * dy) - tube
			return maxf(ring, q.z - z_limit)
	return 1e9


static func _smin(a: float, b: float, k: float) -> float:
	if k <= 0.0:
		return minf(a, b)
	var h := clampf(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
	return lerpf(b, a, h) - k * h * (1.0 - h)


## Exact SDF of a capsule with different end radii (Inigo Quilez).
static func _round_cone(p: Vector3, a: Vector3, b: Vector3, r1: float, r2: float) -> float:
	var ba := b - a
	var l2 := ba.dot(ba)
	var rr := r1 - r2
	var a2 := l2 - rr * rr
	var il2 := 1.0 / l2
	var pa := p - a
	var y := pa.dot(ba)
	var z := y - l2
	var xv := pa * l2 - ba * y
	var x2 := xv.dot(xv)
	var y2 := y * y * l2
	var z2 := z * z * l2
	var k := signf(rr) * rr * rr * x2
	if signf(z) * a2 * z2 > k:
		return sqrt(x2 + z2) * il2 - r2
	if signf(y) * a2 * y2 < k:
		return sqrt(x2 + y2) * il2 - r1
	return (sqrt(x2 * a2 * il2) + y * rr) * il2 - r1


## Surface nets: one vertex per surface-crossing cell, one quad per crossing
## edge. Returns a smooth-shaded ArrayMesh with automatic LODs.
func to_mesh(lo: Vector3, hi: Vector3, cell: float) -> ArrayMesh:
	var n := Vector3i(((hi - lo) / cell).ceil()) + Vector3i.ONE
	var nx := n.x
	var ny := n.y
	var nz := n.z
	var values := PackedFloat32Array()
	values.resize(nx * ny * nz)
	for k in nz:
		for j in ny:
			for i in nx:
				values[i + nx * (j + ny * k)] = eval(lo + Vector3(i, j, k) * cell)

	var cell_vertex := PackedInt32Array()
	cell_vertex.resize(nx * ny * nz)
	cell_vertex.fill(-1)
	var verts := PackedVector3Array()
	var corner_offsets: Array[Vector3i] = [
		Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(1, 1, 0),
		Vector3i(0, 0, 1), Vector3i(1, 0, 1), Vector3i(0, 1, 1), Vector3i(1, 1, 1),
	]
	var edges := [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]
	var corner_values := PackedFloat32Array()
	corner_values.resize(8)

	for k in nz - 1:
		for j in ny - 1:
			for i in nx - 1:
				var inside := 0
				for c in 8:
					var o := corner_offsets[c]
					var v := values[(i + o.x) + nx * ((j + o.y) + ny * (k + o.z))]
					corner_values[c] = v
					if v < 0.0:
						inside += 1
				if inside == 0 or inside == 8:
					continue
				var sum := Vector3.ZERO
				var count := 0
				for e: Array in edges:
					var va := corner_values[e[0]]
					var vb := corner_values[e[1]]
					if (va < 0.0) == (vb < 0.0):
						continue
					var t := va / (va - vb)
					var pa := Vector3(corner_offsets[e[0]])
					var pb := Vector3(corner_offsets[e[1]])
					sum += pa.lerp(pb, t)
					count += 1
				var local := sum / count
				cell_vertex[i + nx * (j + ny * k)] = verts.size()
				verts.append(lo + (Vector3(i, j, k) + local) * cell)

	var normals := PackedVector3Array()
	normals.resize(verts.size())
	var eps := cell * 0.5
	for v in verts.size():
		var p := verts[v]
		var g := Vector3(
			eval(p + Vector3(eps, 0, 0)) - eval(p - Vector3(eps, 0, 0)),
			eval(p + Vector3(0, eps, 0)) - eval(p - Vector3(0, eps, 0)),
			eval(p + Vector3(0, 0, eps)) - eval(p - Vector3(0, 0, eps)))
		normals[v] = g.normalized()

	var indices := PackedInt32Array()
	for k in nz:
		for j in ny:
			for i in nx:
				var v0 := values[i + nx * (j + ny * k)]
				if i < nx - 1 and j > 0 and k > 0:
					var v1 := values[(i + 1) + nx * (j + ny * k)]
					if (v0 < 0.0) != (v1 < 0.0):
						_quad(indices, verts, normals, cell_vertex, nx, ny,
							Vector3i(i, j - 1, k - 1), Vector3i(i, j, k - 1), Vector3i(i, j, k), Vector3i(i, j - 1, k))
				if j < ny - 1 and i > 0 and k > 0:
					var v1 := values[i + nx * ((j + 1) + ny * k)]
					if (v0 < 0.0) != (v1 < 0.0):
						_quad(indices, verts, normals, cell_vertex, nx, ny,
							Vector3i(i - 1, j, k - 1), Vector3i(i, j, k - 1), Vector3i(i, j, k), Vector3i(i - 1, j, k))
				if k < nz - 1 and i > 0 and j > 0:
					var v1 := values[i + nx * (j + ny * (k + 1))]
					if (v0 < 0.0) != (v1 < 0.0):
						_quad(indices, verts, normals, cell_vertex, nx, ny,
							Vector3i(i - 1, j - 1, k), Vector3i(i, j - 1, k), Vector3i(i, j, k), Vector3i(i - 1, j, k))

	var colors := PackedColorArray()
	colors.resize(verts.size())
	for v in verts.size():
		colors[v] = _paint_at(verts[v])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	# Let Godot build distance LODs so the full-detail mesh is only drawn up close.
	var importer := ImporterMesh.new()
	importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
	importer.generate_lods(25.0, 60.0, [])
	return importer.get_mesh()


static func _quad(indices: PackedInt32Array, verts: PackedVector3Array, normals: PackedVector3Array,
		cell_vertex: PackedInt32Array, nx: int, ny: int,
		c0: Vector3i, c1: Vector3i, c2: Vector3i, c3: Vector3i) -> void:
	var ids := PackedInt32Array()
	for c: Vector3i in [c0, c1, c2, c3]:
		var id := cell_vertex[c.x + nx * (c.y + ny * c.z)]
		if id < 0:
			return
		ids.append(id)
	_tri(indices, verts, normals, ids[0], ids[1], ids[2])
	_tri(indices, verts, normals, ids[0], ids[2], ids[3])


## Godot treats clockwise triangles as front-facing, so order each triangle
## so its winding normal points into the surface.
static func _tri(indices: PackedInt32Array, verts: PackedVector3Array, normals: PackedVector3Array, a: int, b: int, c: int) -> void:
	var face := (verts[b] - verts[a]).cross(verts[c] - verts[a])
	var outward := normals[a] + normals[b] + normals[c]
	if face.dot(outward) > 0.0:
		indices.append_array([a, c, b])
	else:
		indices.append_array([a, b, c])
