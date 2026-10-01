class_name Aerodynamics
extends RefCounted

static func drag_coefficient(mach: float, base_cd: float = 0.26) -> float:
	var m: float = max(0.0, mach)
	if m < 0.7:
		return base_cd
	if m < 0.9:
		return lerp(base_cd, base_cd * 1.35, (m - 0.7) / 0.2)
	if m < 1.2:
		return lerp(base_cd * 1.35, base_cd * 1.75, (m - 0.9) / 0.3)
	if m < 3.0:
		return lerp(base_cd * 1.75, base_cd * 1.15, (m - 1.2) / 1.8)
	if m < 8.0:
		return lerp(base_cd * 1.15, base_cd * 0.95, (m - 3.0) / 5.0)
	return base_cd * 0.90

static func dynamic_pressure(density: float, airspeed: float) -> float:
	return 0.5 * density * airspeed * airspeed

static func convective_heating_w_m2(density: float, airspeed: float, nose_radius_m: float = 0.75) -> float:
	if density <= 0.0 or airspeed <= 0.0:
		return 0.0
	var radius: float = max(nose_radius_m, 0.05)
	var velocity_km_s: float = airspeed / 1000.0
	return 1.83e-4 * sqrt(density / radius) * pow(velocity_km_s * 1000.0, 3.0)

static func lift_coefficient(angle_of_attack_rad: float, mach: float) -> float:
	var slope: float = 2.8
	if mach > 1.0:
		slope = 1.7
	return clamp(slope * angle_of_attack_rad, -1.1, 1.1)
