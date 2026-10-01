class_name PartCatalog
extends RefCounted

const PARTS: Dictionary = {
	"capsule": {
		"name": "Aster Command Capsule",
		"type": "capsule",
		"dry_mass": 1850.0,
		"fuel": 0.0,
		"height": 3.2,
		"radius": 1.6,
		"drag_coefficient": 0.32
	},
	"heatshield": {
		"name": "Aster Ablative Heatshield",
		"type": "heatshield",
		"dry_mass": 520.0,
		"fuel": 0.0,
		"height": 0.45,
		"radius": 1.68,
		"drag_coefficient": 0.90
	},
	"nose_cone": {
		"name": "NC-16 Nose Cone",
		"type": "nose",
		"dry_mass": 110.0,
		"fuel": 0.0,
		"height": 2.8,
		"radius": 1.6,
		"drag_coefficient": 0.18
	},
	"tank_small": {
		"name": "T-42 Propellant Tank",
		"type": "tank",
		"dry_mass": 760.0,
		"fuel": 5200.0,
		"height": 5.8,
		"radius": 1.65,
		"drag_coefficient": 0.24
	},
	"tank_medium": {
		"name": "T-66 Propellant Tank",
		"type": "tank",
		"dry_mass": 1110.0,
		"fuel": 8200.0,
		"height": 7.5,
		"radius": 1.75,
		"drag_coefficient": 0.235
	},
	"tank_large": {
		"name": "T-90 Propellant Tank",
		"type": "tank",
		"dry_mass": 1480.0,
		"fuel": 11800.0,
		"height": 9.6,
		"radius": 1.85,
		"drag_coefficient": 0.23
	},
	"engine_aquila": {
		"name": "Aquila 1",
		"type": "engine",
		"dry_mass": 510.0,
		"fuel": 0.0,
		"height": 2.0,
		"radius": 1.35,
		"thrust_sl": 845000.0,
		"thrust_vac": 934000.0,
		"isp_sl": 282.0,
		"isp_vac": 312.0,
		"min_throttle": 0.40,
		"drag_coefficient": 0.30
	},
	"engine_orion": {
		"name": "Orion Vacuum",
		"type": "engine",
		"dry_mass": 430.0,
		"fuel": 0.0,
		"height": 2.4,
		"radius": 1.2,
		"thrust_sl": 170000.0,
		"thrust_vac": 385000.0,
		"isp_sl": 250.0,
		"isp_vac": 356.0,
		"min_throttle": 0.22,
		"drag_coefficient": 0.28
	},
	"decoupler": {
		"name": "S-18 Stage Separator",
		"type": "decoupler",
		"dry_mass": 135.0,
		"fuel": 0.0,
		"height": 0.55,
		"radius": 1.7,
		"drag_coefficient": 0.35
	},
	"fin": {
		"name": "AF-3 Aerodynamic Fin Set",
		"type": "fin",
		"dry_mass": 155.0,
		"fuel": 0.0,
		"height": 1.8,
		"radius": 2.35,
		"drag_coefficient": 0.20
	}
}

static func get_part(id: String) -> Dictionary:
	if not PARTS.has(id):
		return {}
	return PARTS[id].duplicate(true)

static func all_ids() -> Array[String]:
	var result: Array[String] = []
	for key: Variant in PARTS.keys():
		result.append(str(key))
	return result

static func default_stack() -> Array[String]:
	return [
		"engine_aquila",
		"fin",
		"tank_large",
		"tank_medium",
		"decoupler",
		"engine_orion",
		"tank_small",
		"heatshield",
		"capsule"
	]
