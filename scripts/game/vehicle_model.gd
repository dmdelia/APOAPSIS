class_name VehicleModel
extends RefCounted

const G0: float = 9.80665

var stack: Array[String] = []
var stages: Array[Dictionary] = []
var current_stage: int = 0
var throttle: float = 0.0
var engines_armed: bool = false

func configure(part_stack: Array[String]) -> void:
	stack = part_stack.duplicate()
	_rebuild_stages()
	current_stage = 0
	throttle = 0.0
	engines_armed = false

func _rebuild_stages() -> void:
	stages.clear()
	var stage: Dictionary = _empty_stage()
	for part_id: String in stack:
		var part: Dictionary = PartCatalog.get_part(part_id)
		if part.is_empty():
			continue
		var part_type: String = str(part.get("type", ""))
		if part_type == "decoupler":
			stage["dry_mass"] = float(stage["dry_mass"]) + float(part["dry_mass"])
			stages.append(stage)
			stage = _empty_stage()
			continue
		stage["part_ids"].append(part_id)
		stage["dry_mass"] = float(stage["dry_mass"]) + float(part.get("dry_mass", 0.0))
		stage["fuel"] = float(stage["fuel"]) + float(part.get("fuel", 0.0))
		stage["fuel_capacity"] = float(stage["fuel_capacity"]) + float(part.get("fuel", 0.0))
		stage["radius"] = max(float(stage["radius"]), float(part.get("radius", 0.0)))
		if part_type == "engine":
			stage["engines"].append(part)
	if not stage["part_ids"].is_empty() or float(stage["dry_mass"]) > 0.0:
		stages.append(stage)

func _empty_stage() -> Dictionary:
	return {
		"part_ids": [],
		"dry_mass": 0.0,
		"fuel": 0.0,
		"fuel_capacity": 0.0,
		"radius": 0.5,
		"engines": []
	}

func total_mass() -> float:
	var mass: float = 0.0
	for i: int in range(current_stage, stages.size()):
		var stage: Dictionary = stages[i]
		mass += float(stage["dry_mass"]) + float(stage["fuel"])
	return max(mass, 1.0)

func current_fuel() -> float:
	if current_stage >= stages.size():
		return 0.0
	return float(stages[current_stage]["fuel"])

func current_fuel_capacity() -> float:
	if current_stage >= stages.size():
		return 0.0
	return float(stages[current_stage]["fuel_capacity"])

func current_radius() -> float:
	var radius: float = 0.5
	for i: int in range(current_stage, stages.size()):
		radius = max(radius, float(stages[i]["radius"]))
	return radius

func reference_area() -> float:
	var r: float = current_radius()
	return PI * r * r

func stage_count() -> int:
	return stages.size()

func has_next_stage() -> bool:
	return current_stage + 1 < stages.size()

func activate_or_stage() -> String:
	if current_stage >= stages.size():
		return "NO STAGE"
	if not engines_armed:
		engines_armed = true
		if throttle <= 0.0:
			throttle = 1.0
		return "STAGE %d IGNITION" % (current_stage + 1)
	if has_next_stage():
		current_stage += 1
		engines_armed = true
		return "STAGE %d SEPARATION / IGNITION" % current_stage
	engines_armed = false
	return "ENGINES SAFE"

func shutdown() -> void:
	engines_armed = false

func set_throttle(value: float) -> void:
	throttle = clamp(value, 0.0, 1.0)

func consume_and_get_thrust(dt: float, ambient_pressure: float) -> Dictionary:
	if current_stage >= stages.size() or not engines_armed or throttle <= 0.0:
		return {"thrust": 0.0, "mass_flow": 0.0, "isp": 0.0}
	var stage: Dictionary = stages[current_stage]
	if float(stage["fuel"]) <= 0.0:
		engines_armed = false
		return {"thrust": 0.0, "mass_flow": 0.0, "isp": 0.0}

	var pressure_ratio: float = clamp(ambient_pressure / 101325.0, 0.0, 1.0)
	var total_thrust: float = 0.0
	var total_flow: float = 0.0
	var weighted_isp: float = 0.0
	var active_engines: int = 0

	for engine_variant: Variant in stage["engines"]:
		var engine: Dictionary = engine_variant
		var min_throttle: float = float(engine.get("min_throttle", 0.0))
		var effective_throttle: float = 0.0 if throttle <= 0.0 else max(throttle, min_throttle)
		var thrust: float = lerp(float(engine["thrust_vac"]), float(engine["thrust_sl"]), pressure_ratio) * effective_throttle
		var isp: float = lerp(float(engine["isp_vac"]), float(engine["isp_sl"]), pressure_ratio)
		total_thrust += thrust
		total_flow += thrust / max(isp * G0, 0.001)
		weighted_isp += isp
		active_engines += 1

	if active_engines == 0:
		engines_armed = false
		return {"thrust": 0.0, "mass_flow": 0.0, "isp": 0.0}

	var requested_propellant: float = total_flow * dt
	var available_propellant: float = float(stage["fuel"])
	var scale: float = 1.0
	if requested_propellant > available_propellant and requested_propellant > 0.0:
		scale = available_propellant / requested_propellant
	stage["fuel"] = max(0.0, available_propellant - requested_propellant)
	stages[current_stage] = stage

	if float(stage["fuel"]) <= 0.0001:
		engines_armed = false

	return {
		"thrust": total_thrust * scale,
		"mass_flow": total_flow * scale,
		"isp": weighted_isp / float(active_engines)
	}
