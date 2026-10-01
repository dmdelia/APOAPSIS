class_name DVec3
extends RefCounted

var x: float
var y: float
var z: float

func _init(px: float = 0.0, py: float = 0.0, pz: float = 0.0) -> void:
	x = px
	y = py
	z = pz

static func from_vector3(value: Vector3) -> DVec3:
	return DVec3.new(float(value.x), float(value.y), float(value.z))

func duplicate_value() -> DVec3:
	return DVec3.new(x, y, z)

func add(other: DVec3) -> DVec3:
	return DVec3.new(x + other.x, y + other.y, z + other.z)

func sub(other: DVec3) -> DVec3:
	return DVec3.new(x - other.x, y - other.y, z - other.z)

func scaled(factor: float) -> DVec3:
	return DVec3.new(x * factor, y * factor, z * factor)

func divided(divisor: float) -> DVec3:
	if absf(divisor) < 1.0e-30:
		return DVec3.new()
	var inv: float = 1.0 / divisor
	return scaled(inv)

func dot(other: DVec3) -> float:
	return x * other.x + y * other.y + z * other.z

func cross(other: DVec3) -> DVec3:
	return DVec3.new(
		y * other.z - z * other.y,
		z * other.x - x * other.z,
		x * other.y - y * other.x
	)

func length_squared() -> float:
	return x * x + y * y + z * z

func length() -> float:
	return sqrt(length_squared())

func normalized() -> DVec3:
	var len: float = length()
	if len <= 1.0e-30:
		return DVec3.new()
	return divided(len)

func distance_to(other: DVec3) -> float:
	return sub(other).length()

func to_vector3() -> Vector3:
	return Vector3(float(x), float(y), float(z))

func is_finite_value() -> bool:
	return is_finite(x) and is_finite(y) and is_finite(z)
