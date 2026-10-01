class_name OrbitMath
extends RefCounted

const MU_EARTH: float = 3.986004418e14
const EARTH_RADIUS: float = 6378137.0

static func gravity_acceleration(position: Vector3) -> Vector3:
	var radius: float = position.length()
	if radius <= 1.0:
		return Vector3.ZERO
	return -position.normalized() * (MU_EARTH / (radius * radius))

static func elements(position: Vector3, velocity: Vector3) -> Dictionary:
	var r: float = position.length()
	var v2: float = velocity.length_squared()
	if r < 1.0:
		return _invalid()

	var h_vec: Vector3 = position.cross(velocity)
	var h: float = h_vec.length()
	if h < 0.0001:
		return _invalid()

	var e_vec: Vector3 = velocity.cross(h_vec) / MU_EARTH - position / r
	var eccentricity: float = e_vec.length()
	var energy: float = 0.5 * v2 - MU_EARTH / r
	var semi_major_axis: float = INF
	if abs(energy) > 0.000001:
		semi_major_axis = -MU_EARTH / (2.0 * energy)

	var periapsis_radius: float = h * h / (MU_EARTH * (1.0 + eccentricity))
	var apoapsis_radius: float = INF
	if eccentricity < 1.0:
		apoapsis_radius = semi_major_axis * (1.0 + eccentricity)

	var inclination: float = 0.0
	if h > 0.0:
		inclination = rad_to_deg(acos(clamp(h_vec.z / h, -1.0, 1.0)))

	var period: float = INF
	if semi_major_axis > 0.0 and eccentricity < 1.0:
		period = TAU * sqrt(pow(semi_major_axis, 3.0) / MU_EARTH)

	return {
		"valid": true,
		"eccentricity": eccentricity,
		"semi_major_axis_m": semi_major_axis,
		"periapsis_m": periapsis_radius - EARTH_RADIUS,
		"apoapsis_m": apoapsis_radius - EARTH_RADIUS if is_finite(apoapsis_radius) else INF,
		"inclination_deg": inclination,
		"period_s": period,
		"specific_energy": energy,
		"angular_momentum": h
	}

static func _invalid() -> Dictionary:
	return {
		"valid": false,
		"eccentricity": 0.0,
		"semi_major_axis_m": 0.0,
		"periapsis_m": -EARTH_RADIUS,
		"apoapsis_m": -EARTH_RADIUS,
		"inclination_deg": 0.0,
		"period_s": 0.0,
		"specific_energy": 0.0,
		"angular_momentum": 0.0
	}
