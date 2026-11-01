## Vector maths in 64-bit floats. Godot's Vector3 is 32-bit, which at Jupiter
## distances (millions of km) rounds to hundreds of metres; physics uses these
## PackedFloat64Array triples instead, and only rendering uses Vector3.
class_name V


static func of(x: float, y: float, z: float = 0.0) -> PackedFloat64Array:
	return PackedFloat64Array([x, y, z])


static func from(a: Array) -> PackedFloat64Array:
	return PackedFloat64Array([float(a[0]), float(a[1]), float(a[2]) if a.size() > 2 else 0.0])


static func add(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	return of(a[0] + b[0], a[1] + b[1], a[2] + b[2])


static func sub(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	return of(a[0] - b[0], a[1] - b[1], a[2] - b[2])


static func scale(a: PackedFloat64Array, k: float) -> PackedFloat64Array:
	return of(a[0] * k, a[1] * k, a[2] * k)


static func dot(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


static func cross(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	return of(a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


static func norm(a: PackedFloat64Array) -> float:
	return sqrt(dot(a, a))


static func dist(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	return norm(sub(a, b))


## A game-frame vector (a velocity, a direction) as the same vector in Godot's
## y-up world, unscaled.
static func dir(a: PackedFloat64Array) -> Vector3:
	return Vector3(a[0], a[2], -a[1])


## Game plane (x, y; z up out of the plane) to Godot's y-up world, in render units.
static func to_world(r: PackedFloat64Array, origin: PackedFloat64Array, unit_km: float) -> Vector3:
	return Vector3((r[0] - origin[0]) / unit_km, (r[2] - origin[2]) / unit_km, -(r[1] - origin[1]) / unit_km)
