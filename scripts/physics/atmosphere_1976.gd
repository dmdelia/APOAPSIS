class_name Atmosphere1976
extends RefCounted

const G0: float = 9.80665
const R_AIR: float = 287.05287
const GAMMA: float = 1.4

const H_BASE: Array[float] = [0.0, 11000.0, 20000.0, 32000.0, 47000.0, 51000.0, 71000.0, 84852.0]
const T_BASE: Array[float] = [288.15, 216.65, 216.65, 228.65, 270.65, 270.65, 214.65, 186.946]
const P_BASE: Array[float] = [101325.0, 22632.06, 5474.889, 868.0187, 110.9063, 66.93887, 3.95642, 0.3734]
const LAPSE: Array[float] = [-0.0065, 0.0, 0.001, 0.0028, 0.0, -0.0028, -0.002, 0.0]

static func sample(altitude_m: float) -> Dictionary:
	var h: float = max(0.0, altitude_m)
	if h >= H_BASE[H_BASE.size() - 1]:
		var top_temperature: float = T_BASE[T_BASE.size() - 1]
		var top_pressure: float = P_BASE[P_BASE.size() - 1]
		var scale_height: float = R_AIR * top_temperature / G0
		var pressure: float = top_pressure * exp(-(h - H_BASE[H_BASE.size() - 1]) / scale_height)
		var density: float = pressure / (R_AIR * top_temperature)
		return {
			"temperature": top_temperature,
			"pressure": pressure,
			"density": density,
			"speed_of_sound": sqrt(GAMMA * R_AIR * top_temperature)
		}

	var layer: int = 0
	for i: int in range(H_BASE.size() - 1):
		if h >= H_BASE[i] and h < H_BASE[i + 1]:
			layer = i
			break

	var hb: float = H_BASE[layer]
	var tb: float = T_BASE[layer]
	var pb: float = P_BASE[layer]
	var lapse: float = LAPSE[layer]
	var temperature: float
	var pressure: float

	if abs(lapse) < 0.0000001:
		temperature = tb
		pressure = pb * exp(-G0 * (h - hb) / (R_AIR * tb))
	else:
		temperature = tb + lapse * (h - hb)
		pressure = pb * pow(tb / temperature, G0 / (R_AIR * lapse))

	var density: float = pressure / (R_AIR * temperature)
	return {
		"temperature": temperature,
		"pressure": pressure,
		"density": density,
		"speed_of_sound": sqrt(GAMMA * R_AIR * temperature)
	}
