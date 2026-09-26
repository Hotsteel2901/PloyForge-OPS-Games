# Map data: Cinder v2 (open desert town, defusal), Containment (open zombie lab), Obsidian (dusk towers).

extends Node



# Collider helper: wall box

static func _W(x1: float, z1: float, x2: float, z2: float, h: float = 4.5, y: float = 0.0, type: String = "wall") -> Dictionary:

	return {

		"min": Vector3(min(x1, x2), y, min(z1, z2)),

		"max": Vector3(max(x1, x2), y + h, max(z1, z2)),

		"type": type,

	}



# Crate / cover box

static func _CR(x: float, z: float, sx: float, sz: float, h: float, y: float = 0.0, type: String = "crate") -> Dictionary:

	return {

		"min": Vector3(x - sx / 2.0, y, z - sz / 2.0),

		"max": Vector3(x + sx / 2.0, y + h, z + sz / 2.0),

		"type": type,

	}



# Elevated floor slab

static func _B(x1: float, z1: float, x2: float, z2: float, y: float, h: float = 0.3) -> Dictionary:

	return {

		"min": Vector3(min(x1, x2), y, min(z1, z2)),

		"max": Vector3(max(x1, x2), y + h, max(z1, z2)),

		"type": "floor",

	}



# Stair step (0.4m riser)

static func _ST(x1: float, z1: float, x2: float, z2: float, y0: float) -> Dictionary:

	return {

		"min": Vector3(min(x1, x2), y0, min(z1, z2)),

		"max": Vector3(max(x1, x2), y0 + 0.4, max(z1, z2)),

		"type": "step",

	}



# Roof slab (visual + projectile block, never walkable / nav-blocking)

static func _CL(x1: float, z1: float, x2: float, z2: float, y: float) -> Dictionary:

	return {

		"min": Vector3(min(x1, x2), y, min(z1, z2)),

		"max": Vector3(max(x1, x2), y + 0.3, max(z1, z2)),

		"type": "ceiling",

	}



# Solid deco -> derived collider heights (feet-up from deco pos.y)

const PROP_HEIGHT: Dictionary = {

	"crate": 1.0, "barrel": 1.0, "tire": 0.7, "sandbag": 0.6, "pallet": 0.25,

	"ac_unit": 0.8, "hydrant": 0.6, "vehicle": 1.8, "rock": 1.0, "pylon": 3.0,

	"billboard": 2.0, "bush": 0.6, "debris": 0.5, "ruin": 2.0, "tower_shell": 4.0,

	"vent": 0.4, "duct": 0.4,

}





# Every solid deco gets a matching AABB collider so players cannot walk through props.

# Conservative footprint: max(scale.x, scale.z); skipped when already covered by an

# existing collider at that spot (2D overlap > 0.4m in both axes, same vertical band)

# or when the prop sits inside a wall / ceiling footprint.

static func _derive_prop_colliders(deco: Array, existing: Array) -> Array:

	var out: Array = []

	var all: Array = existing.duplicate()

	for d in deco:

		var t: String = d.get("type", "")

		if not PROP_HEIGHT.has(t):

			continue

		var pos: Vector3 = d.pos

		var s: Vector3 = d.get("scale", Vector3.ONE)

		var h: float = PROP_HEIGHT[t] * s.y if t == "crate" else PROP_HEIGHT[t]

		var f: float = max(s.x, s.z) * 0.5

		var cand := {

			"min": Vector3(pos.x - f, pos.y, pos.z - f),

			"max": Vector3(pos.x + f, pos.y + h, pos.z + f),

			"type": "deco_" + t,

		}

		if _covered_by(cand, all):

			continue

		all.append(cand)

		out.append(cand)

	return out





static func _covered_by(cand: Dictionary, existing: Array) -> bool:

	var cx: float = (cand.min.x + cand.max.x) * 0.5

	var cz: float = (cand.min.z + cand.max.z) * 0.5

	var cy: float = (cand.min.y + cand.max.y) * 0.5

	for c in existing:

		var typ: String = c.get("type", "wall")

		# prop sitting inside/on a wall or ceiling footprint = skip (wall already collides)

		if typ == "wall" or typ == "ceiling":

			if cy > c.min.y - 0.3 and cy < c.max.y + 0.3 \

				and cx > c.min.x - 0.35 and cx < c.max.x + 0.35 \

				and cz > c.min.z - 0.35 and cz < c.max.z + 0.35:

				return true

		# floors/steps are walkable surfaces, not obstacles: props on top still need colliders

		if typ == "floor" or typ == "step":

			continue

		# covered by an obstacle occupying the same vertical band

		if not (c.min.y <= cy and c.max.y >= cand.min.y + 0.1):

			continue

		var ox: float = min(cand.max.x, c.max.x) - max(cand.min.x, c.min.x)

		var oz: float = min(cand.max.z, c.max.z) - max(cand.min.z, c.min.z)

		if ox > 0.4 and oz > 0.4:

			return true

	return false





# ============================================================================

# CINDER v2 - "Open Desert Town" (140x140, no perimeter walls)

# ============================================================================

static func _cinder() -> Dictionary:

	var c: Array = []

	# --- Buildings (6 standalone blocks, 1m-thick walls, 3-4m door openings,

	#     flat roofs you cannot climb, windows as wall deco) ---

	# B1 General Store x[-32,-20] z[-34,-24]

	c.append(_W(-32, -24, -28, -23))

	c.append(_W(-24, -24, -20, -23))

	c.append(_W(-20, -34, -19, -30.5))

	c.append(_W(-20, -27.5, -19, -24))

	c.append(_W(-32, -34, -31, -24))

	c.append(_W(-32, -34, -20, -33))

	c.append(_CL(-32, -34, -20, -24, 4.5))

	# B2 Garage x[20,32] z[-34,-24]

	c.append(_W(20, -24, 24, -23))

	c.append(_W(28, -24, 32, -23))

	c.append(_W(20, -34, 21, -30.5))

	c.append(_W(20, -27.5, 21, -24))

	c.append(_W(32, -34, 33, -24))

	c.append(_W(20, -34, 32, -33))

	c.append(_CL(20, -34, 32, -24, 4.5))

	# B3 Market Cafe x[-32,-20] z[12,24]

	c.append(_W(-32, 24, -28, 25))

	c.append(_W(-24, 24, -20, 25))

	c.append(_W(-20, 12, -19, 16))

	c.append(_W(-20, 20, -19, 24))

	c.append(_W(-32, 12, -20, 13))

	c.append(_W(-32, 12, -31, 24))

	c.append(_CL(-32, 12, -20, 24, 4.5))

	# B4 Hotel x[20,32] z[12,24]

	c.append(_W(20, 12, 21, 16))

	c.append(_W(20, 20, 21, 24))

	c.append(_W(20, 24, 29, 25))

	c.append(_W(32, 12, 33, 24))

	c.append(_W(20, 12, 32, 13))

	c.append(_CL(20, 12, 32, 24, 4.5))

	# B5 B-Site building x[-18,-6] z[-18,-8]

	c.append(_W(-18, -8, -15.5, -7))

	c.append(_W(-12.5, -8, -6, -7))

	c.append(_W(-6, -18, -5, -14.5))

	c.append(_W(-6, -11.5, -5, -8))

	c.append(_W(-18, -18, -17, -8))

	c.append(_W(-18, -18, -6, -17))

	c.append(_CL(-18, -18, -6, -8, 4.5))

	# B6 x[0,12] z[-30,-18] (A courtyard on its north side)

	c.append(_W(0, -30, 1, -25.5))

	c.append(_W(0, -22.5, 1, -18))

	c.append(_W(12, -30, 13, -25.5))

	c.append(_W(12, -22.5, 13, -18))

	c.append(_W(3.5, -18, 12, -17))

	c.append(_W(0, -18, 0.5, -17))

	c.append(_W(0, -30, 4.5, -29))

	c.append(_W(7.5, -30, 12, -29))

	c.append(_CL(0, -30, 12, -18, 4.5))

	# --- Elevated catwalks over mid street (steps at both ends, top y=1.2) ---

	c.append(_B(-14, -4, -8, -2, 1.2))

	c.append(_ST(-17, -4, -16, -2, 0.0))

	c.append(_ST(-16, -4, -15, -2, 0.4))

	c.append(_ST(-15, -4, -14, -2, 0.8))

	c.append(_ST(-8, -4, -7, -2, 0.8))

	c.append(_ST(-7, -4, -6, -2, 0.4))

	c.append(_ST(-6, -4, -5, -2, 0.0))

	c.append(_B(8, -4, 14, -2, 1.2))

	c.append(_ST(5, -4, 6, -2, 0.0))

	c.append(_ST(6, -4, 7, -2, 0.4))

	c.append(_ST(7, -4, 8, -2, 0.8))

	c.append(_ST(14, -4, 15, -2, 0.8))

	c.append(_ST(15, -4, 16, -2, 0.4))

	c.append(_ST(16, -4, 17, -2, 0.0))

	# --- Mesa (low rock ledge, NE of A-long, steps up the west side) ---

	c.append(_B(34, -44, 42, -36, 1.6))

	c.append(_ST(30, -44, 31, -36, 0.0))

	c.append(_ST(31, -44, 32, -36, 0.4))

	c.append(_ST(32, -44, 33, -36, 0.8))

	c.append(_ST(33, -44, 34, -36, 1.2))

	# --- Ruined tower shell (NW, walls with openings, no roof) ---

	c.append(_W(-38, -54, -33.5, -53))

	c.append(_W(-30.5, -54, -26, -53))

	c.append(_W(-26, -54, -25, -49.5))

	c.append(_W(-26, -46.5, -25, -42))

	c.append(_W(-38, -42, -26, -41))

	c.append(_W(-38, -54, -37, -42))

	c.append(_W(-33, -50, -31, -48, 1.6))

	# --- Low stone cover walls ---

	c.append(_W(12, 1, 16, 3, 1.6))

	c.append(_W(-32, -38.5, -28, -37.5, 1.6))

	c.append(_W(4, -38.5, 8, -37.5, 1.6))

	# --- B alley roof (covered passage mid -> B site) ---

	c.append(_CL(-6, -16, 0, -10, 4.5))

	# --- A site courtyard cover ---

	c.append(_CR(2, -36, 1.2, 1.2, 1.3))

	c.append(_CR(10, -36, 1.2, 1.2, 1.3))

	c.append(_CR(10, -32, 1.2, 1.2, 1.3))

	c.append(_CR(2, -32, 1.2, 1.2, 1.3))

	c.append(_CR(6, -38, 2.0, 1.2, 1.2))

	# --- B site interior cover ---

	c.append(_CR(-16, -15, 1.2, 1.2, 1.3))

	c.append(_CR(-10, -16, 1.2, 1.2, 1.3))

	c.append(_CR(-7, -13, 1.4, 1.2, 1.3))

	var lights: Array = [

		{"type": "light", "pos": Vector3(-58, 3.0, 2), "color": Color("d8e8ff"), "energy": 1.5, "range": 11.0},

		{"type": "light", "pos": Vector3(-54, 3.0, -4), "color": Color("ffe3b0"), "energy": 1.2, "range": 9.0},

		{"type": "light", "pos": Vector3(56, 3.0, 0), "color": Color("ffe3b0"), "energy": 1.6, "range": 11.0},

		{"type": "light", "pos": Vector3(50, 3.0, 10), "color": Color("ffe3b0"), "energy": 1.3, "range": 9.0},

		{"type": "light", "pos": Vector3(48, 3.0, -8), "color": Color("ffe3b0"), "energy": 1.3, "range": 9.0},

		{"type": "light", "pos": Vector3(-20, 3.0, 0), "color": Color("ffd9a0"), "energy": 1.6, "range": 11.0},

		{"type": "light", "pos": Vector3(0, 3.0, 2), "color": Color("ffd9a0"), "energy": 1.6, "range": 11.0},

		{"type": "light", "pos": Vector3(20, 3.0, 0), "color": Color("ffd9a0"), "energy": 1.6, "range": 11.0},

		{"type": "light", "pos": Vector3(-32, 3.0, 4), "color": Color("ffd9a0"), "energy": 1.3, "range": 9.0},

		{"type": "light", "pos": Vector3(-8, 3.0, 10), "color": Color("ffe3b0"), "energy": 1.8, "range": 11.0},

		{"type": "light", "pos": Vector3(8, 3.0, 10), "color": Color("ffe3b0"), "energy": 1.8, "range": 11.0},

		{"type": "light", "pos": Vector3(0, 3.0, 12), "color": Color("ffe3b0"), "energy": 1.4, "range": 9.0},

		{"type": "light", "pos": Vector3(-12, 3.0, 30), "color": Color("ffd9a0"), "energy": 1.4, "range": 10.0},

		{"type": "light", "pos": Vector3(16, 3.0, 30), "color": Color("ffd9a0"), "energy": 1.4, "range": 10.0},

		{"type": "light", "pos": Vector3(-20, 3.0, -41), "color": Color("ffd9a0"), "energy": 1.4, "range": 10.0},

		{"type": "light", "pos": Vector3(12, 3.0, -41), "color": Color("ffd9a0"), "energy": 1.4, "range": 10.0},

		{"type": "light", "pos": Vector3(6, 3.2, -34), "color": Color("ffe3b0"), "energy": 2.0, "range": 12.0},

		{"type": "light", "pos": Vector3(10, 3.2, -37), "color": Color("ffe3b0"), "energy": 1.4, "range": 9.0},

		{"type": "light", "pos": Vector3(-12, 3.6, -13), "color": Color("d8e8ff"), "energy": 2.4, "range": 12.0},

		{"type": "light", "pos": Vector3(-15, 3.6, -16), "color": Color("d8e8ff"), "energy": 1.8, "range": 10.0},

		{"type": "light", "pos": Vector3(-8, 3.6, -10), "color": Color("d8e8ff"), "energy": 1.8, "range": 10.0},

		{"type": "light", "pos": Vector3(-3, 3.8, -13), "color": Color("d8e8ff"), "energy": 2.2, "range": 11.0},

		{"type": "light", "pos": Vector3(4, 3.6, -28), "color": Color("ffe3b0"), "energy": 2.0, "range": 11.0},

		{"type": "light", "pos": Vector3(8, 3.6, -22), "color": Color("ffe3b0"), "energy": 1.6, "range": 10.0},

		{"type": "light", "pos": Vector3(-26, 3.6, -29), "color": Color("ffe3b0"), "energy": 2.2, "range": 11.0},

		{"type": "light", "pos": Vector3(-28, 3.6, -26), "color": Color("ffe3b0"), "energy": 1.6, "range": 9.0},

		{"type": "light", "pos": Vector3(26, 3.6, -29), "color": Color("ffe3b0"), "energy": 2.2, "range": 11.0},

		{"type": "light", "pos": Vector3(28, 3.6, -26), "color": Color("ffe3b0"), "energy": 1.6, "range": 9.0},

		{"type": "light", "pos": Vector3(-26, 3.6, 18), "color": Color("ffe3b0"), "energy": 2.2, "range": 11.0},

		{"type": "light", "pos": Vector3(-28, 3.6, 21), "color": Color("ffe3b0"), "energy": 1.6, "range": 9.0},

		{"type": "light", "pos": Vector3(-22, 3.6, 20), "color": Color("ffe3b0"), "energy": 1.4, "range": 9.0},

		{"type": "light", "pos": Vector3(26, 3.6, 18), "color": Color("ffe3b0"), "energy": 2.2, "range": 11.0},

		{"type": "light", "pos": Vector3(28, 3.6, 21), "color": Color("ffe3b0"), "energy": 1.6, "range": 9.0},

		{"type": "light", "pos": Vector3(-32, 3.6, -48), "color": Color("d8e8ff"), "energy": 2.0, "range": 11.0},

	]



	var deco: Array = [

		# --- T compound (east desert) ---

		{"type": "vehicle", "pos": Vector3(58, 0, -10), "rot": 0.3, "scale": Vector3(1.4, 1, 0.9), "variant": 0},

		{"type": "vehicle", "pos": Vector3(44, 0, 10), "rot": -0.2, "scale": Vector3(1.4, 1, 0.9), "variant": 1},

		{"type": "vehicle", "pos": Vector3(46, 0, -6), "rot": 0.8, "scale": Vector3(1.2, 1, 0.8), "variant": 2},

		{"type": "crate", "pos": Vector3(52, 0, 9), "rot": -0.3, "scale": Vector3(1, 1, 1), "variant": 1},

		{"type": "crate", "pos": Vector3(48, 0, 8), "rot": 0.1, "scale": Vector3(1, 1, 1), "variant": 2},

		{"type": "crate", "pos": Vector3(45, 0, 2), "rot": 0.4, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "barrel", "pos": Vector3(53, 0, -8), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 2},

		{"type": "barrel", "pos": Vector3(49, 0, 10), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "sandbag", "pos": Vector3(49, 0, 0), "rot": 1.1, "scale": Vector3(1, 1, 1), "variant": 1},

		{"type": "sandbag", "pos": Vector3(57, 0, 8), "rot": -0.4, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "tire", "pos": Vector3(54, 0, 11), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "rock", "pos": Vector3(59, 0, -6), "rot": 0.7, "scale": Vector3(1.3, 0.9, 1.1), "variant": 0},

		{"type": "bush", "pos": Vector3(60, 0, 4), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "pylon", "pos": Vector3(59, 0, 9), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "paint_stripe", "pos": Vector3(44, 0, -5), "rot": PI / 2, "scale": Vector3(2.0, 0.5, 1), "variant": 0},

		{"type": "paint_stripe", "pos": Vector3(44, 0, 0), "rot": PI / 2, "scale": Vector3(2.0, 0.5, 1), "variant": 0},

		{"type": "paint_stripe", "pos": Vector3(44, 0, 5), "rot": PI / 2, "scale": Vector3(2.0, 0.5, 1), "variant": 0},

		# --- CT spawn (west gate) ---

		{"type": "crate", "pos": Vector3(-52, 0, -8), "rot": 0.1, "scale": Vector3(1, 1, 1), "variant": 2},

		{"type": "crate", "pos": Vector3(-50, 0, 9), "rot": 0.3, "scale": Vector3(1, 1, 1), "variant": 1},

		{"type": "sandbag", "pos": Vector3(-55, 0, 8), "rot": 0.4, "scale": Vector3(1, 1, 1), "variant": 1},

		{"type": "hydrant", "pos": Vector3(-58, 0, -3), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "rock", "pos": Vector3(-60, 0, 8), "rot": 0.5, "scale": Vector3(1.1, 0.8, 1), "variant": 0},

		{"type": "bush", "pos": Vector3(-49, 0, -10), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

		# --- Mid street ---

		{"type": "crate", "pos": Vector3(-24, 0, 3), "rot": 0.2, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "crate", "pos": Vector3(24, 0, -3), "rot": -0.3, "scale": Vector3(1, 1, 1), "variant": 1},

		{"type": "barrel", "pos": Vector3(-18, 0, -5), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "barrel", "pos": Vector3(18, 0, 5), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 1},

		{"type": "sandbag", "pos": Vector3(6, 0, 3), "rot": 0.5, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "sandbag", "pos": Vector3(-6, 0, -3), "rot": -0.5, "scale": Vector3(1, 1, 1), "variant": 1},

		{"type": "hydrant", "pos": Vector3(4, 0, -2), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "billboard", "pos": Vector3(-36, 0, 2), "rot": PI, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "billboard", "pos": Vector3(36, 0, -2), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 1},

		{"type": "lamp", "pos": Vector3(-16, 0, 2), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "lamp", "pos": Vector3(16, 0, 2), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "paint_stripe", "pos": Vector3(0, 0, -7), "rot": 0, "scale": Vector3(3.0, 0.6, 1), "variant": 0},

		{"type": "paint_stripe", "pos": Vector3(0, 0, 7), "rot": 0, "scale": Vector3(3.0, 0.6, 1), "variant": 0},

		# --- Market plaza + back street ---

		{"type": "crate", "pos": Vector3(-14, 0, 10), "rot": 0.2, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "crate", "pos": Vector3(12, 0, 11), "rot": -0.2, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "crate", "pos": Vector3(16, 0, 9), "rot": 0.4, "scale": Vector3(1, 1, 1), "variant": 1},

		{"type": "pallet", "pos": Vector3(-12, 0, 9), "rot": 0.5, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "barrel", "pos": Vector3(-8, 0, 10), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 2},

		{"type": "banner", "pos": Vector3(-10, 3.0, 12), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "lamp", "pos": Vector3(0, 3.0, 10), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "lamp", "pos": Vector3(-16, 3.0, 9), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "billboard", "pos": Vector3(-28, 0, 29), "rot": PI, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "vehicle", "pos": Vector3(38, 0, 30), "rot": 1.5, "scale": Vector3(1.4, 1, 0.9), "variant": 0},

		{"type": "vehicle", "pos": Vector3(-38, 0, 30), "rot": -1.5, "scale": Vector3(1.4, 1, 0.9), "variant": 1},

		# --- A-long street ---

		{"type": "crate", "pos": Vector3(-38, 0, -40), "rot": 0.2, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "crate", "pos": Vector3(0, 0, -42), "rot": -0.3, "scale": Vector3(1, 1, 1), "variant": 2},

		{"type": "crate", "pos": Vector3(-14, 0, -42), "rot": 0.3, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "barrel", "pos": Vector3(-30, 0, -41), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 2},

		{"type": "rock", "pos": Vector3(-50, 0, -40), "rot": 0.6, "scale": Vector3(1.2, 0.9, 1.1), "variant": 0},

		{"type": "ruin", "pos": Vector3(-8, 0, -41), "rot": 0.5, "scale": Vector3(1.5, 1, 1), "variant": 0},

		{"type": "ruin", "pos": Vector3(22, 0, -42), "rot": -0.3, "scale": Vector3(1.2, 1, 0.8), "variant": 1},

		{"type": "billboard", "pos": Vector3(-46, 0, -39), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 1},

		# --- A site courtyard ---

		{"type": "crate", "pos": Vector3(2, 0, -37), "rot": 0.3, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "crate", "pos": Vector3(10, 0, -31), "rot": 0.2, "scale": Vector3(1, 1, 1), "variant": 2},

		{"type": "barrel", "pos": Vector3(4, 0, -35), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 1},

		{"type": "sandbag", "pos": Vector3(3, 0, -39), "rot": 0.5, "scale": Vector3(1, 1, 1), "variant": 1},

		{"type": "scorch_mark", "pos": Vector3(6, 0, -35), "rot": 0.4, "scale": Vector3(1, 1, 1), "variant": 0},

		# --- B5 interior (B site) + B alley ---

		{"type": "crate", "pos": Vector3(-16, 0, -15), "rot": 0.2, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "crate", "pos": Vector3(-9, 0, -17), "rot": -0.3, "scale": Vector3(1, 1, 1), "variant": 1},

		{"type": "crate", "pos": Vector3(-7, 0, -9), "rot": 0.1, "scale": Vector3(1, 1, 1), "variant": 2},

		{"type": "barrel", "pos": Vector3(-14, 0, -10), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 2},

		{"type": "vent", "pos": Vector3(-17.6, 2.4, -13), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "duct", "pos": Vector3(-12, 2.6, -17.6), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "graffiti", "pos": Vector3(-17.7, 1.6, -15), "rot": 0, "scale": Vector3(1.2, 0.8, 1), "variant": 0},

		{"type": "crate", "pos": Vector3(-4, 0, -14), "rot": 0.2, "scale": Vector3(1, 1, 1), "variant": 0},

		# --- B6 interior ---

		{"type": "crate", "pos": Vector3(2, 0, -30), "rot": 0.2, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "crate", "pos": Vector3(10, 0, -26), "rot": 0.1, "scale": Vector3(1, 1, 1), "variant": 2},

		{"type": "barrel", "pos": Vector3(4, 0, -24), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 2},

		{"type": "ac_unit", "pos": Vector3(5, 0, -23), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "vent", "pos": Vector3(11.6, 2.4, -26), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

		# --- B1 interior ---

		{"type": "crate", "pos": Vector3(-30, 0, -32), "rot": 0.2, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "crate", "pos": Vector3(-22, 0, -30), "rot": -0.2, "scale": Vector3(1, 1, 1), "variant": 1},

		{"type": "ac_unit", "pos": Vector3(-30, 0, -29), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "vent", "pos": Vector3(-20.6, 2.4, -30), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

		# --- B2 interior ---

		{"type": "crate", "pos": Vector3(22, 0, -32), "rot": 0.2, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "crate", "pos": Vector3(30, 0, -30), "rot": -0.2, "scale": Vector3(1, 1, 1), "variant": 1},

		{"type": "ac_unit", "pos": Vector3(24, 0, -31), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "vent", "pos": Vector3(31.6, 2.4, -28), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

		# --- B3 interior ---

		{"type": "crate", "pos": Vector3(-30, 0, 14), "rot": 0.2, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "crate", "pos": Vector3(-22, 0, 16), "rot": -0.3, "scale": Vector3(1, 1, 1), "variant": 1},

		{"type": "barrel", "pos": Vector3(-27, 0, 19), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 2},

		{"type": "ac_unit", "pos": Vector3(-21, 0, 13), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "vent", "pos": Vector3(-31.6, 2.4, 20), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "graffiti", "pos": Vector3(-20.4, 1.6, 18), "rot": 0, "scale": Vector3(1.2, 0.8, 1), "variant": 0},

		# --- B4 interior ---

		{"type": "crate", "pos": Vector3(22, 0, 14), "rot": 0.2, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "crate", "pos": Vector3(30, 0, 16), "rot": -0.2, "scale": Vector3(1, 1, 1), "variant": 1},

		{"type": "ac_unit", "pos": Vector3(21, 0, 15), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "vent", "pos": Vector3(31.6, 2.4, 20), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

		# --- Tower + desert fringe ---

		{"type": "ruin", "pos": Vector3(-34, 0, -47), "rot": 0.3, "scale": Vector3(1.4, 1, 0.9), "variant": 0},

		{"type": "debris", "pos": Vector3(-36, 0, -52), "rot": 0.6, "scale": Vector3(0.8, 0.8, 0.8), "variant": 0},

		{"type": "rock", "pos": Vector3(-40, 0, -50), "rot": 0.5, "scale": Vector3(1.4, 1, 1.2), "variant": 0},

		{"type": "rock", "pos": Vector3(-24, 0, -44), "rot": -0.6, "scale": Vector3(1.1, 0.8, 1), "variant": 1},

		{"type": "tower_shell", "pos": Vector3(66, 0, -26), "rot": 0, "scale": Vector3(2, 2, 2), "variant": 0},

		{"type": "ruin", "pos": Vector3(64, 0, -30), "rot": 0.7, "scale": Vector3(1.2, 1, 0.8), "variant": 1},

		{"type": "rock", "pos": Vector3(-10, 0, 40), "rot": 0.4, "scale": Vector3(1.5, 1, 1.3), "variant": 0},

		{"type": "rock", "pos": Vector3(26, 0, 40), "rot": -0.5, "scale": Vector3(1.2, 0.9, 1), "variant": 1},

		{"type": "bush", "pos": Vector3(30, 0, 38), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "bush", "pos": Vector3(36, 0, -36), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "pylon", "pos": Vector3(40, 0, -30), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

	]



	return {

		"id": "cinder",

		"name": "Cinder",

		"mode": "defusal",

		"size": Vector2(140, 140),

		"open_world": true,

		"sky": {

			"zenith": Color("3a6fb8"),

			"horizon": Color("e8d9b4"),

			"ground": Color("8a7355"),

			"fog": Color("d9c28a"),

			"fog_density": 0.0015,

			"sun_dir": Vector3(0.55, 0.35, -0.75),

			"sun_color": Color("ffedc8"),

			"sun_energy": 2.8,

			"ambient_energy": 0.95,

			"fill_energy": 0.2,

			"fill_color": Color("9fb4ff"),

			"glow_intensity": 1.0,

			"glow_strength": 0.14,

			"saturation": 1.18,

			"contrast": 1.08,

			"cloud_coverage": 0.18,

			"cloud_density": 0.5,

			"haze": 0.25,

			"volumetric": 0.03,

			"exposure": 1.0,
			"hdri_exposure": 0.5,

		},

		"spawns": {

			"CT": [

				{"x": -57, "z": -6, "yaw": -PI / 2},

				{"x": -56, "z": 3, "yaw": -PI / 2},

				{"x": -54, "z": -1, "yaw": -PI / 2},

				{"x": -53, "z": 6, "yaw": -PI / 2},

				{"x": -52, "z": -5, "yaw": -PI / 2},

				{"x": -51, "z": 1, "yaw": -PI / 2},

			],

			"T": [

				{"x": 57, "z": -6, "yaw": PI / 2},

				{"x": 56, "z": 3, "yaw": PI / 2},

				{"x": 54, "z": -1, "yaw": PI / 2},

				{"x": 53, "z": 6, "yaw": PI / 2},

				{"x": 55, "z": -8, "yaw": PI / 2},

				{"x": 55, "z": 2, "yaw": PI / 2},

			],

		},

		"sites": [

			{"id": "A", "pos": Vector3(6, 0, -34), "radius": 2.8, "color": Color("ffcf4a")},

			{"id": "B", "pos": Vector3(-12, 0, -13), "radius": 2.8, "color": Color("5fd0ff")},

		],

		"colliders": c + _boundary_walls(Vector2(140, 140)),

		"props": lights,

		"deco": deco,

		"ammoBoxes": [

			{"pos": Vector3(52, 0, 10), "respawn": 20},

			{"pos": Vector3(-50, 0, -8), "respawn": 20},

			{"pos": Vector3(6, 0, -33), "respawn": 20},

			{"pos": Vector3(-14, 0, -11), "respawn": 20},

			{"pos": Vector3(0, 0, 10), "respawn": 20},

		],

		"healthBoxes": [

			{"pos": Vector3(54, 0, -3), "respawn": 25},

			{"pos": Vector3(-48, 0, 4), "respawn": 25},

			{"pos": Vector3(2, 0, -25), "respawn": 25},

			{"pos": Vector3(-10, 0, -14), "respawn": 25},

		],

		"shots": [

			{"name": "01_t_spawn", "pos": Vector3(56, 3.0, 0), "look": Vector3(-30, 1.6, 0), "fov": 66},

			{"name": "02_ct_gate", "pos": Vector3(-56, 3.0, 3), "look": Vector3(-10, 1.6, 0), "fov": 64},

			{"name": "03_mid_street", "pos": Vector3(-14, 3.0, 0), "look": Vector3(24, 1.6, -4), "fov": 60},

			{"name": "04_catwalk", "pos": Vector3(-11, 4.2, -3), "look": Vector3(10, 1.5, 2), "fov": 58},

			{"name": "05_mesa", "pos": Vector3(38, 4.6, -40), "look": Vector3(-6, 1.5, 10), "fov": 60},

			{"name": "06_a_long", "pos": Vector3(-44, 3.0, -41), "look": Vector3(20, 1.5, -34), "fov": 58},

			{"name": "07_a_site", "pos": Vector3(3, 3.0, -36), "look": Vector3(9, 1.5, -30), "fov": 56},

			{"name": "08_b_site", "pos": Vector3(-8, 3.0, -11), "look": Vector3(-15, 1.5, -16), "fov": 56},

			{"name": "09_b_alley", "pos": Vector3(-3, 3.0, -12), "look": Vector3(-6, 1.5, -14), "fov": 58},
			{"name": "t1_probe", "pos": Vector3(55, 1.62, -8), "look": Vector3(60, 1.6, -8), "fov": 74},
			{"name": "t2_probe", "pos": Vector3(-51, 1.62, 1), "look": Vector3(-46, 1.6, 1), "fov": 74},
			{"name": "t3_probe", "pos": Vector3(56, 1.62, 3), "look": Vector3(60, 1.6, 3), "fov": 74},
			{"name": "t4_probe", "pos": Vector3(0, 1.62, 20), "look": Vector3(10, 1.5, 5), "fov": 74},
			{"name": "10_plaza", "pos": Vector3(0, 3.0, 10), "look": Vector3(-22, 1.6, 14), "fov": 62},

		],

	}





# ============================================================================

# CONTAINMENT - zombie lab, opened up (no second-story slab grid, 6m atrium)

# ============================================================================

static func _containment() -> Dictionary:

	var c: Array = [

		_W(-28, -28, 28, -27, 6.0), _W(-28, 27, 28, 28, 6.0), _W(-28, -28, -27, 28, 6.0), _W(27, -28, 28, 28, 6.0),

		# corner room walls (kept)

		_W(-7, -7, -2, -3, 3.2), _W(-7, 3, -2, 7, 3.2), _W(2, -7, 7, -3, 3.2), _W(2, 3, 7, 7, 3.2),

		_W(-7, -7, -3, -2, 3.2), _W(3, -7, 7, -2, 3.2), _W(-7, 2, -3, 7, 3.2), _W(3, 2, 7, 7, 3.2),

		# tall central atrium ceiling (y=6); old 3.4m walkable slab grid removed entirely

		_CL(-26, -26, 26, 26, 6.0),

		# pillars + cover

		_CR(-12, 12, 1.1, 1.1, 2.8, 0, "pillar"), _CR(0, 20, 1.1, 1.1, 2.8, 0, "pillar"),

		_CR(-20, -20, 1.8, 1.8, 1.4), _CR(-20, -16, 1.8, 1.8, 1.4), _CR(-16, -20, 1.8, 1.8, 1.4),

		_CR(20, 20, 1.8, 1.8, 1.4), _CR(20, 16, 1.8, 1.8, 1.4), _CR(16, 20, 1.8, 1.8, 1.4),

		_CR(-20, 20, 1.8, 1.8, 1.4), _CR(-20, 16, 1.8, 1.8, 1.4),

		_CR(20, -20, 1.8, 1.8, 1.4), _CR(20, -16, 1.8, 1.8, 1.4),

		_CR(0, -16, 1.5, 1.5, 1.3), _CR(0, 16, 1.5, 1.5, 1.3), _CR(-16, 0, 1.5, 1.5, 1.3), _CR(16, 0, 1.5, 1.5, 1.3),

		_CR(0, -24, 1.4, 1.4, 1.2), _CR(0, 24, 1.4, 1.4, 1.2), _CR(-24, 0, 1.4, 1.4, 1.2), _CR(24, 0, 1.4, 1.4, 1.2),

		_CR(-8, -24, 1.2, 1.2, 1.2), _CR(8, 24, 1.2, 1.2, 1.2),

		_CR(-24, -12, 1.0, 1.0, 1.0, 0, "barrel"), _CR(-24, 12, 1.0, 1.0, 1.0, 0, "barrel"),

		_CR(24, -12, 1.0, 1.0, 1.0, 0, "barrel"), _CR(24, 12, 1.0, 1.0, 1.0, 0, "barrel"),

		_CR(-18, -24, 1.0, 1.0, 1.0, 0, "barrel"), _CR(18, 24, 1.0, 1.0, 1.0, 0, "barrel"),

		# open-layout low cover walls

		_W(-10, -12, -6, -8, 1.6), _W(6, -12, 10, -8, 1.6),

		_W(-10, 8, -6, 12, 1.6), _W(6, 8, 10, 12, 1.6),

		_W(-12, -24, -8, -20, 1.6), _W(8, -24, 12, -20, 1.6),

		_W(-12, 20, -8, 24, 1.6), _W(8, 20, 12, 24, 1.6),

	]

	var lights: Array = [

		{"type": "light", "pos": Vector3(0, 5.2, 0), "color": Color("c9ffe8"), "energy": 4.5, "range": 24.0},

		{"type": "light", "pos": Vector3(-20, 5.4, -20), "color": Color("b9ffe0"), "energy": 3.2, "range": 16.0},

		{"type": "light", "pos": Vector3(20, 5.4, -20), "color": Color("b9ffe0"), "energy": 3.2, "range": 16.0},

		{"type": "light", "pos": Vector3(-20, 5.4, 20), "color": Color("b9ffe0"), "energy": 3.2, "range": 16.0},

		{"type": "light", "pos": Vector3(20, 5.4, 20), "color": Color("b9ffe0"), "energy": 3.2, "range": 16.0},

		{"type": "light", "pos": Vector3(0, 5.4, -24), "color": Color("9fe8c8"), "energy": 2.8, "range": 14.0},

		{"type": "light", "pos": Vector3(0, 5.4, 24), "color": Color("9fe8c8"), "energy": 2.8, "range": 14.0},

		{"type": "light", "pos": Vector3(-24, 5.4, 0), "color": Color("9fe8c8"), "energy": 2.8, "range": 14.0},

		{"type": "light", "pos": Vector3(24, 5.4, 0), "color": Color("9fe8c8"), "energy": 2.8, "range": 14.0},

	]

	# 10m light grid under the tall ceiling

	for gx in range(-20, 28, 10):

		for gz in range(-20, 28, 10):

			if abs(gx) > 26 or abs(gz) > 26:

				continue

			lights.append({"type": "light", "pos": Vector3(gx, 5.2, gz), "color": Color("b9ffe0"), "energy": 2.0, "range": 11.0})

	var deco: Array = [

		{"type": "pipe", "pos": Vector3(-26.8, 3.0, 10), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "pipe", "pos": Vector3(26.8, 3.0, -10), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "vent", "pos": Vector3(-26.8, 2.4, 10), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "vent", "pos": Vector3(26.8, 2.4, -10), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "duct", "pos": Vector3(-12, 2.6, 26.8), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "pipe", "pos": Vector3(0, 2.6, -26.8), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 1},

		{"type": "crate", "pos": Vector3(-22, 0, -22), "rot": 0.2, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "crate", "pos": Vector3(22, 0, 22), "rot": -0.3, "scale": Vector3(1, 1, 1), "variant": 1},

		{"type": "crate", "pos": Vector3(-22, 0, 22), "rot": 0.1, "scale": Vector3(1, 1, 1), "variant": 2},

		{"type": "crate", "pos": Vector3(22, 0, -22), "rot": -0.1, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "crate", "pos": Vector3(-20, 0, -12), "rot": 0.3, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "crate", "pos": Vector3(20, 0, 12), "rot": -0.2, "scale": Vector3(1, 1, 1), "variant": 1},

		{"type": "crate", "pos": Vector3(-6, 0, -20), "rot": 0.2, "scale": Vector3(1, 1, 1), "variant": 2},

		{"type": "crate", "pos": Vector3(6, 0, 20), "rot": -0.3, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "barrel", "pos": Vector3(-10, 0, 10), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "barrel", "pos": Vector3(10, 0, -10), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 2},

		{"type": "barrel", "pos": Vector3(12, 0, -10), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 1},

		{"type": "barrel", "pos": Vector3(-12, 0, 10), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "sandbag", "pos": Vector3(-12, 0, -14), "rot": 0.4, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "sandbag", "pos": Vector3(12, 0, 14), "rot": -0.4, "scale": Vector3(1, 1, 1), "variant": 1},

		{"type": "sandbag", "pos": Vector3(8, 0, 20), "rot": 0.3, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "tire", "pos": Vector3(-4, 0, 4), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "tire", "pos": Vector3(4, 0, -4), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 1},

		{"type": "tire", "pos": Vector3(-20, 0, 6), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "pallet", "pos": Vector3(-14, 0, 0), "rot": 0.3, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "debris", "pos": Vector3(16, 0, 16), "rot": 0.7, "scale": Vector3(0.9, 0.8, 0.8), "variant": 0},

		{"type": "debris", "pos": Vector3(-16, 0, -16), "rot": -0.5, "scale": Vector3(0.8, 0.7, 0.7), "variant": 0},

		{"type": "stain", "pos": Vector3(-16, 0, 16), "rot": 0.5, "scale": Vector3(1.2, 1, 1), "variant": 0},

		{"type": "scorch_mark", "pos": Vector3(6, 0, -6), "rot": 0.4, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "graffiti", "pos": Vector3(-26.8, 1.6, -12), "rot": 0, "scale": Vector3(1.2, 0.8, 1), "variant": 0},

		{"type": "lamp", "pos": Vector3(-6.5, 2.6, 8), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "lamp", "pos": Vector3(6.5, 2.6, -8), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "lamp", "pos": Vector3(0, 2.6, 0), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "lamp", "pos": Vector3(-16, 2.6, -16), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "lamp", "pos": Vector3(16, 2.6, 16), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

	]

	return {

		"id": "containment",

		"name": "Containment",

		"mode": "zombie",

		"size": Vector2(56, 56),

		"sky": {

			"zenith": Color("3a7a55"),

			"horizon": Color("a8d8bd"),

			"ground": Color("2e4a3a"),

			"fog": Color("6f9a80"),

			"fog_density": 0.008,

			"sun_dir": Vector3(0.3, 0.35, -0.9),

			"sun_color": Color("d2ffe8"),

			"sun_energy": 2.4,

			"ambient_energy": 1.1,

			"fill_energy": 0.35,

			"fill_color": Color("8fe8c8"),

			"glow_intensity": 1.0,

			"glow_strength": 0.18,

			"saturation": 1.02,

			"contrast": 1.06,

			"cloud_coverage": 0.45,

			"cloud_density": 0.4,

			"haze": 0.35,

			"volumetric": 0.022,

			"exposure": 1.15,
				"hdri_exposure": 0.5,

		},

		"spawns": {

			"HUMAN": [

				{"x": -24, "z": -20, "yaw": 0.6}, {"x": -24, "z": 20, "yaw": -0.6},

				{"x": 24, "z": -20, "yaw": PI - 0.6}, {"x": 24, "z": 20, "yaw": PI + 0.6},

				{"x": -18, "z": 0, "yaw": 1.2}, {"x": 18, "z": 0, "yaw": -1.2},

				{"x": 0, "z": -22, "yaw": 0.3}, {"x": 0, "z": 22, "yaw": -0.3},

			],

			"ZOMBIE": [

				{"x": 0, "z": 0, "yaw": 2.5}, {"x": 0, "z": -4.5, "yaw": 0},

				{"x": 4.5, "z": 0, "yaw": -1.5}, {"x": -4.5, "z": 0, "yaw": 1.5},

			],

		},

		"sites": [],

		"colliders": c + _boundary_walls(Vector2(56, 56)),

		"props": lights,

		"deco": deco,

		"ammoBoxes": [

			{"pos": Vector3(-24, 0, -20), "respawn": 20}, {"pos": Vector3(-24, 0, 20), "respawn": 20},

			{"pos": Vector3(24, 0, -20), "respawn": 20}, {"pos": Vector3(24, 0, 20), "respawn": 20},

			{"pos": Vector3(0, 0, 0), "respawn": 20}, {"pos": Vector3(-14, 0, 0), "respawn": 20},

			{"pos": Vector3(14, 0, 0), "respawn": 20},

		],

		"healthBoxes": [

			{"pos": Vector3(-18, 0, -18), "respawn": 25}, {"pos": Vector3(-18, 0, 18), "respawn": 25},

			{"pos": Vector3(18, 0, -18), "respawn": 25}, {"pos": Vector3(18, 0, 18), "respawn": 25},

			{"pos": Vector3(0, 0, 0), "respawn": 25},

		],

		"shots": [

			{"name": "01_atrium", "pos": Vector3(0, 2.6, 8), "look": Vector3(0, 1.4, -10), "fov": 62},

			{"name": "02_cover_walls", "pos": Vector3(0, 2.6, 0), "look": Vector3(8, 1.4, 0), "fov": 62},

			{"name": "03_corner_room", "pos": Vector3(8, 2.6, -14), "look": Vector3(-10, 1.4, 12), "fov": 64},

			{"name": "04_top_down", "pos": Vector3(0, 20.0, 0), "look": Vector3(0, 0, -1), "fov": 55},

		],

	}





# ============================================================================

# OBSIDIAN - dusk towers (layout kept, prop-collision derivation applied)

# ============================================================================

static func _obsidian() -> Dictionary:

	var stairs: Array = []

	for i in range(8):

		var y0: float = 0.4 * i

		stairs.append({"min": Vector3(-3, y0, -25 + i), "max": Vector3(3, y0 + 0.4, -24 + i), "type": "step"})

		stairs.append({"min": Vector3(-3, y0, 24 - i), "max": Vector3(3, y0 + 0.4, 25 - i), "type": "step"})

		stairs.append({"min": Vector3(-25 + i, y0, -3), "max": Vector3(-24 + i, y0 + 0.4, 3), "type": "step"})

		stairs.append({"min": Vector3(24 - i, y0, -3), "max": Vector3(25 - i, y0 + 0.4, 3), "type": "step"})

	var c: Array = [

		_W(-26, -26, 26, -25, 5), _W(-26, 25, 26, 26, 5), _W(-26, -26, -25, 26, 5), _W(25, -26, 26, 26, 5),

		_B(-26, -25, -3, -17, 3.2), _B(3, -25, 26, -17, 3.2), _B(-26, 17, -3, 25, 3.2), _B(3, 17, 26, 25, 3.2),

		_B(-25, -26, -17, -3, 3.2), _B(-25, 3, -17, 26, 3.2), _B(17, -26, 25, -3, 3.2), _B(17, 3, 25, 26, 3.2),

		_CR(0, 0, 2, 2, 1.3), _CR(-3, -3, 1.5, 1.5, 1.3), _CR(3, 3, 1.5, 1.5, 1.3),

		_CR(-10, -22, 1.6, 1.6, 1.2), _CR(-22, -14, 1.6, 1.6, 1.2), _CR(22, 14, 1.6, 1.6, 1.2), _CR(10, 22, 1.6, 1.6, 1.2),

		_CR(-5, 5, 1.2, 1.2, 1.2), _CR(5, -5, 1.2, 1.2, 1.2), _CR(-10, 10, 1.2, 1.2, 1.2), _CR(10, -10, 1.2, 1.2, 1.2),

		_W(-12, -2, -8, 2, 1.6), _W(8, -2, 12, 2, 1.6),

		_CR(-6, -6, 0.9, 0.9, 2.6, 0, "pillar"), _CR(6, 6, 0.9, 0.9, 2.6, 0, "pillar"),

		_CR(-6, 6, 0.9, 0.9, 2.6, 0, "pillar"), _CR(6, -6, 0.9, 0.9, 2.6, 0, "pillar"),

		_CR(-18, 0, 1, 1, 1, 0, "barrel"), _CR(18, 0, 1, 1, 1, 0, "barrel"),

		_CR(-22, -20, 1, 1, 1, 0, "barrel"), _CR(22, 20, 1, 1, 1, 0, "barrel"),

		_CR(-22, 20, 1, 1, 1, 0, "barrel"), _CR(22, -20, 1, 1, 1, 0, "barrel"),

		_CR(18, 6, 1.1, 1.1, 1.1, 3.2), _CR(22, 14, 1.1, 1.1, 1.1, 3.2),

		_CR(-18, -6, 1.1, 1.1, 1.1, 3.2), _CR(-22, -14, 1.1, 1.1, 1.1, 3.2),

		_CR(-8, 22, 1.2, 1.1, 1.1, 3.2), _CR(8, -22, 1.2, 1.1, 1.1, 3.2),

		_CR(-6, 18, 1.2, 1.1, 1.1, 3.2), _CR(6, 18, 1.2, 1.1, 1.1, 3.2),

		_CR(-6, -18, 1.2, 1.1, 1.1, 3.2), _CR(6, -18, 1.2, 1.1, 1.1, 3.2),

	] + stairs

	var lights: Array = [

		{"type": "light", "pos": Vector3(-10, 6.6, -8), "color": Color("ffd9a0"), "energy": 2.2, "range": 12.0},

		{"type": "light", "pos": Vector3(20, 8.4, 10), "color": Color("ffd9a0"), "energy": 2.2, "range": 12.0},

		{"type": "light", "pos": Vector3(0, 6.6, 0), "color": Color("b8c8ff"), "energy": 3.2, "range": 16.0},

		{"type": "light", "pos": Vector3(-22, 6.6, 0), "color": Color("b8c8ff"), "energy": 2.8, "range": 14.0},

		{"type": "light", "pos": Vector3(22, 6.6, 0), "color": Color("b8c8ff"), "energy": 2.8, "range": 14.0},

		{"type": "light", "pos": Vector3(0, 6.6, -22), "color": Color("b8c8ff"), "energy": 2.8, "range": 14.0},

		{"type": "light", "pos": Vector3(0, 6.6, 22), "color": Color("b8c8ff"), "energy": 2.8, "range": 14.0},

		{"type": "light", "pos": Vector3(-20, 8.4, -10), "color": Color("ffd9a0"), "energy": 2.0, "range": 11.0},

	]

	var deco: Array = [

		{"type": "crate", "pos": Vector3(-12, 0, -12), "rot": 0.2, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "crate", "pos": Vector3(12, 0, 12), "rot": -0.3, "scale": Vector3(1, 1, 1), "variant": 1},

		{"type": "barrel", "pos": Vector3(-14, 0, 14), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 2},

		{"type": "barrel", "pos": Vector3(14, 0, -14), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "tire", "pos": Vector3(-12, 0, 8), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 1},

		{"type": "tire", "pos": Vector3(12, 0, -8), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "crate", "pos": Vector3(22, 3.2, 18), "rot": 0.1, "scale": Vector3(1, 1, 1), "variant": 2},

		{"type": "crate", "pos": Vector3(-22, 3.2, -18), "rot": -0.1, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "lamp", "pos": Vector3(-10, 5.8, -8), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "lamp", "pos": Vector3(20, 7.6, 10), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

		# ground-level props without manual colliders -> derived colliders

		{"type": "crate", "pos": Vector3(6, 0, 10), "rot": 0.2, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "crate", "pos": Vector3(-8, 0, 12), "rot": -0.2, "scale": Vector3(1, 1, 1), "variant": 1},

		{"type": "crate", "pos": Vector3(14, 0, -12), "rot": 0.3, "scale": Vector3(1, 1, 1), "variant": 2},

		{"type": "sandbag", "pos": Vector3(12, 0, -6), "rot": 0.4, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "tire", "pos": Vector3(-12, 0, 6), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "barrel", "pos": Vector3(0, 0, 10), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 1},

		{"type": "rock", "pos": Vector3(-6, 0, -10), "rot": 0.5, "scale": Vector3(1.1, 0.9, 1), "variant": 0},

		{"type": "bush", "pos": Vector3(14, 0, 0), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "hydrant", "pos": Vector3(0, 0, -14), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "debris", "pos": Vector3(10, 0, 12), "rot": 0.6, "scale": Vector3(0.8, 0.8, 0.8), "variant": 0},

		{"type": "ac_unit", "pos": Vector3(-14, 0, 0), "rot": 0, "scale": Vector3(1, 1, 1), "variant": 0},

		{"type": "pallet", "pos": Vector3(0, 0, 6), "rot": 0.3, "scale": Vector3(1, 1, 1), "variant": 0},

	]

	return {

		"id": "obsidian",

		"name": "Obsidian",

		"mode": "defusal",

		"size": Vector2(52, 52),

		"sky": {

			"zenith": Color("1d2a4d"),

			"horizon": Color("8b6a86"),

			"ground": Color("3a3040"),

			"fog": Color("6a5a74"),

			"fog_density": 0.007,

			"sun_dir": Vector3(-0.35, 0.22, -0.9),

			"sun_color": Color("ffc890"),

			"sun_energy": 2.2,

			"ambient_energy": 1.0,

			"fill_energy": 0.55,

			"fill_color": Color("8f8fff"),

			"glow_intensity": 1.1,

			"glow_strength": 0.2,

			"saturation": 1.12,

			"contrast": 1.08,

			"cloud_coverage": 0.55,

			"cloud_density": 0.5,

			"haze": 0.42,

			"volumetric": 0.022,

			"exposure": 1.32,
				"use_hdri": false,

			"stars": 0.25,

		},

		"spawns": {

			"CT": [

				{"x": -22, "z": -6, "yaw": -PI / 2}, {"x": -22, "z": 6, "yaw": -PI / 2},

				{"x": -22, "z": -2, "yaw": -PI / 2}, {"x": -22, "z": 2, "yaw": -PI / 2},

				{"x": -24, "z": 0, "yaw": -PI / 2}, {"x": -20, "z": 0, "yaw": -PI / 2},

			],

			"T": [

				{"x": 22, "z": -6, "yaw": PI / 2}, {"x": 22, "z": 6, "yaw": PI / 2},

				{"x": 22, "z": -2, "yaw": PI / 2}, {"x": 22, "z": 2, "yaw": PI / 2},

				{"x": 24, "z": 0, "yaw": PI / 2}, {"x": 20, "z": 0, "yaw": PI / 2},

			],

		},

		"sites": [

			{"id": "A", "pos": Vector3(-10, 0, -8), "radius": 2.8, "color": Color("ffcf4a")},

			{"id": "B", "pos": Vector3(20, 3.2, 10), "radius": 2.8, "color": Color("5fd0ff")},

		],

		"colliders": c + _boundary_walls(Vector2(52, 52)),

		"props": lights,

		"deco": deco,

		"ammoBoxes": [

			{"pos": Vector3(-18, 0, -18), "respawn": 20}, {"pos": Vector3(-18, 0, 18), "respawn": 20},

			{"pos": Vector3(18, 0, -18), "respawn": 20}, {"pos": Vector3(18, 0, 18), "respawn": 20},

			{"pos": Vector3(0, 0, 0), "respawn": 20}, {"pos": Vector3(20, 3.2, 10), "respawn": 20},

			{"pos": Vector3(-20, 3.2, -10), "respawn": 20}, {"pos": Vector3(0, 3.2, 20), "respawn": 20},

			{"pos": Vector3(0, 3.2, -20), "respawn": 20},

		],

		"healthBoxes": [

			{"pos": Vector3(-14, 0, -14), "respawn": 25}, {"pos": Vector3(-14, 0, 14), "respawn": 25},

			{"pos": Vector3(14, 0, -14), "respawn": 25}, {"pos": Vector3(14, 0, 14), "respawn": 25},

			{"pos": Vector3(0, 3.2, 20), "respawn": 25},

		],

		"shots": [

			{"name": "01_tower_view", "pos": Vector3(0, 5.8, -10), "look": Vector3(0, 2.2, 14), "fov": 64},

			{"name": "02_tower_top", "pos": Vector3(0, 5.8, 10), "look": Vector3(-14, 2.0, 4), "fov": 60},

			{"name": "03_ground", "pos": Vector3(-14, 3.0, -6), "look": Vector3(8, 1.5, 4), "fov": 66},

		],

	"nav": [],

	}





# Invisible map-boundary walls (players can't walk out of the world).
static func _boundary_walls(size: Vector2) -> Array:
	var half: float = size.x / 2.0 - 1.0
	var w: float = 2.0
	return [
		{"min": Vector3(-half - w, -1.0, -half - w), "max": Vector3(half + w, 12.0, -half), "type": "boundary"},
		{"min": Vector3(-half - w, -1.0, half), "max": Vector3(half + w, 12.0, half + w), "type": "boundary"},
		{"min": Vector3(-half - w, -1.0, -half), "max": Vector3(-half, 12.0, half), "type": "boundary"},
		{"min": Vector3(half, -1.0, -half - w), "max": Vector3(half + w, 12.0, half + w), "type": "boundary"},
	]


var MAPS: Dictionary = {}





func _ready() -> void:

	_rebuild()





func get_map(map_id: String) -> Dictionary:

	if MAPS.is_empty():

		_rebuild()

	return MAPS.get(map_id, MAPS.get("cinder", {}))





func get_map_ids() -> Array:

	return ["cinder", "containment", "obsidian"]





func _rebuild() -> void:

	MAPS = {

		"cinder": _cinder(),

		"containment": _containment(),

		"obsidian": _obsidian(),

	}

	for map_key in MAPS:

		var m: Dictionary = MAPS[map_key]

		# derive colliders from solid deco before nav generation so nav sees the props

		var derived: Array = _derive_prop_colliders(m.get("deco", []), m.get("colliders", []))

		if not derived.is_empty():

			m["colliders"] = m.get("colliders", []) + derived

		if m.get("nav", []).is_empty():
			m["nav"] = _generate_nav(m)
		# 自动生成的导航在生成时已做过连边物理验证与连通裁剪，无需再次净化；
		# _sanitize_nav_links 仅用于手工维护的 nav（当前三张图全部自动生成）。


# 对手写/生成的导航图做物理净化：
# 1) 删除穿过障碍物的同层连线（跨层连线=走台阶，保留）；
# 2) 保证链接双向一致；
# 3) 若净化后出现孤立节点，尝试与最近同层可达节点补连。
static func _sanitize_nav_links(m: Dictionary) -> void:
	# 对手写/生成的导航图做物理净化与连通性修复：
	# 1) 删除穿过障碍物的同层连线（跨层连线=走台阶，保留）；
	# 2) 保证链接双向一致；
	# 3) 若净化导致图分裂，跨连通分量补最近的可达连线，直到全图连通。
	var nav: Array = m.nav
	if nav.is_empty():
		return
	var colliders: Array = m.colliders
	var removed: int = 0
	for i in range(nav.size()):
		var a: Dictionary = nav[i]
		var ay: float = float(a.get("y", 0.0))
		var links: Array = a.links
		var j: int = links.size() - 1
		while j >= 0:
			var li: int = links[j]
			if li < 0 or li >= nav.size() or li == i:
				links.remove_at(j)
				removed += 1
				j -= 1
				continue
			var b: Dictionary = nav[li]
			var by: float = float(b.get("y", 0.0))
			if absf(ay - by) < 0.5 and not _walk_line_clear(Vector3(a.x, 0.0, a.z), Vector3(b.x, 0.0, b.z), colliders, ay):
				links.remove_at(j)
				removed += 1
			j -= 1
	# 双向一致性：A→B 存在则 B→A 也存在
	for i in range(nav.size()):
		for li in nav[i].links:
			if li >= 0 and li < nav.size() and not nav[li].links.has(i):
				nav[li].links.append(i)
	# 连通分量
	var comp: Dictionary = {}
	var comps: Array = []
	for i in range(nav.size()):
		if comp.has(i):
			continue
		var cid: int = comps.size()
		var q: Array = [i]
		comp[i] = cid
		while not q.is_empty():
			var u: int = q.pop_front()
			for li in nav[u].links:
				if li >= 0 and li < nav.size() and not comp.has(li):
					comp[li] = cid
					q.push_back(li)
		comps.append(cid)
	# 跨分量最近可达连线，直到全图连通（防止净化后手写导航断成多块）
	var guard: int = 0
	while comps.size() > 1 and guard < 500:
		guard += 1
		var best_a: int = -1
		var best_b: int = -1
		var best_d: float = INF
		for i in range(nav.size()):
			var ay: float = float(nav[i].get("y", 0.0))
			for k in range(i + 1, nav.size()):
				if comp.get(i, -1) == comp.get(k, -1):
					continue
				if absf(ay - float(nav[k].get("y", 0.0))) >= 0.5:
					continue
				var dd: float = Vector2(nav[i].x - nav[k].x, nav[i].z - nav[k].z).length()
				if dd >= best_d or dd > 60.0:
					continue
				if _walk_line_clear(Vector3(nav[i].x, 0.0, nav[i].z), Vector3(nav[k].x, 0.0, nav[k].z), colliders, ay):
					best_d = dd
					best_a = i
					best_b = k
		if best_a == -1:
			break  # 无法再同层连通（跨层需台阶，已保留）
		nav[best_a].links.append(best_b)
		nav[best_b].links.append(best_a)
		# 合并分量
		var old_cid: int = comp[best_b]
		var new_cid: int = comp[best_a]
		for node_i in range(nav.size()):
			if comp.get(node_i, -1) == old_cid:
				comp[node_i] = new_cid
		comps.pop_back()
	if removed > 0:
		print("[Nav] %s: removed %d wall-crossing links" % [m.get("id", "?"), removed])

# Auto-generate a robust, fully-connected 2m-grid nav graph (flat maps only; elevated maps hand-author nav).
# Fixes: disconnected regions, unreachable spawns/sites, and 500ms Dijkstra stalls.
static func _generate_nav(m: Dictionary) -> Array:
	# 多层自动导航：地面层(y=0) + 所有可站立平台层(slab 顶面) + 台阶带跨层连线。
	# 每层都是 2m 网格，节点判定余量 = 玩家碰撞半宽 + 0.1（0.45）。
	# 之前 margin=0.7 会把 3m 门洞净宽压到 1.6m，室内一个导航节点都生成不出来，
	# bot 只能撞墙或走穿墙捷径。
	var spacing: float = 2.0
	var margin: float = 0.45
	var heights: Array = [0.0]
	for c in m.colliders:
		if c.type == "floor" and c.max.y - c.min.y <= 0.5 and c.max.y > 0.6:
			if not heights.has(c.max.y):
				heights.append(c.max.y)
	heights.sort()
	# 空间哈希：障碍碰撞体按 4m 格子分桶，点/线检查只查相关格子（启动提速 ~20x）
	var cells: Dictionary = {}
	var cs: float = 4.0
	for ci in range(m.colliders.size()):
		var c: Dictionary = m.colliders[ci]
		if c.type == "ceiling":
			continue
		var mn: Vector3 = c.min
		var mx: Vector3 = c.max
		var cx0: int = int(floor(mn.x / cs))
		var cx1: int = int(floor((mx.x - 0.01) / cs))
		var cz0: int = int(floor(mn.z / cs))
		var cz1: int = int(floor((mx.z - 0.01) / cs))
		for gx in range(cx0, cx1 + 1):
			for gz in range(cz0, cz1 + 1):
				var key: Vector2i = Vector2i(gx, gz)
				if not cells.has(key):
					cells[key] = []
				cells[key].append(ci)
	var layers: Array = []
	var offsets: Array = []
	var all_nodes: Array = []
	for h in heights:
		offsets.append(all_nodes.size())
		var layer: Array = _nav_layer(m, h, margin, spacing, cells, cs)
		layers.append(layer)
		for n in layer:
			all_nodes.append(n)
	# 层内 8 邻域连线 + 物理验证（斜连要求两边正交都通，避免切角）
	for li in range(layers.size()):
		var h: float = heights[li]
		var base: int = offsets[li]
		var layer: Array = layers[li]
		var idx: Dictionary = {}
		for ni in range(layer.size()):
			idx[layer[ni].gi] = ni
		for key in idx:
			var v: Vector2i = key
			var i: int = idx[v]
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if idx.has(v + d):
					var j: int = idx[v + d]
					if _walk_line_clear(Vector3(all_nodes[base + i].x, 0.0, all_nodes[base + i].z), Vector3(all_nodes[base + j].x, 0.0, all_nodes[base + j].z), m.colliders, h, cells, cs):
						all_nodes[base + i].links.append(base + j)
			for d in [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
				if idx.has(v + d) and idx.has(v + Vector2i(d.x, 0)) and idx.has(v + Vector2i(0, d.y)):
					var j: int = idx[v + d]
					if _walk_line_clear(Vector3(all_nodes[base + i].x, 0.0, all_nodes[base + i].z), Vector3(all_nodes[base + j].x, 0.0, all_nodes[base + j].z), m.colliders, h, cells, cs):
						all_nodes[base + i].links.append(base + j)
	# 跨层台阶连线：平台节点连到下层最近的物理可达节点（3D 视线忽略可通行面），
	# 这样连线天然落在台阶带上，bot 沿直线走会被台阶块逐级顶上去。
	for li in range(1, layers.size()):
		var base_hi: int = offsets[li]
		var base_lo: int = offsets[li - 1]
		for ni in range(layers[li].size()):
			var p: Dictionary = all_nodes[base_hi + ni]
			var best: int = -1
			var best_d: float = INF
			for nj in range(layers[li - 1].size()):
				var g: Dictionary = all_nodes[base_lo + nj]
				var dd: float = Vector2(p.x - g.x, p.z - g.z).length()
				if dd >= best_d or dd > 25.0:
					continue
				if _walk_line_clear_3d(Vector3(p.x, p.y, p.z), Vector3(g.x, g.y, g.z), m.colliders, cells, cs):
					best_d = dd
					best = base_lo + nj
			if best != -1:
				p.links.append(best)
				all_nodes[best].links.append(base_hi + ni)
	# keep the largest connected component only (drop unreachable islands)
	var comp_of: Array = []
	comp_of.resize(all_nodes.size())
	for i in range(all_nodes.size()):
		comp_of[i] = -1
	var comp_sizes: Array = []
	for i in range(all_nodes.size()):
		if comp_of[i] != -1:
			continue
		var cid: int = comp_sizes.size()
		var q: Array = [i]
		comp_of[i] = cid
		var sz: int = 0
		while not q.is_empty():
			var u: int = q.pop_front()
			sz += 1
			for li in all_nodes[u].links:
				if comp_of[li] == -1:
					comp_of[li] = cid
					q.push_back(li)
		comp_sizes.append(sz)
	var largest: int = 0
	for cid in range(comp_sizes.size()):
		if comp_sizes[cid] > comp_sizes[largest]:
			largest = cid
	var keep := {}
	var remap: Array = []
	remap.resize(all_nodes.size())
	var new_nodes: Array = []
	for i in range(all_nodes.size()):
		if comp_of[i] == largest:
			remap[i] = new_nodes.size()
			new_nodes.append(all_nodes[i])
			keep[i] = true
	for i in range(new_nodes.size()):
		var nl: Array = []
		for li in new_nodes[i].links:
			if keep.has(li):
				nl.append(remap[li])
		new_nodes[i]["links"] = nl
	all_nodes = new_nodes
	# ensure every spawn and site has a node within 4m of the connected graph; add connectors if needed
	var anchors: Array = []
	for team_key in m.get("spawns", {}):
		for s in m.spawns[team_key]:
			anchors.append(Vector3(float(s.x), float(s.get("y", 0.0)), float(s.z)))
	for site in m.get("sites", []):
		anchors.append(Vector3(site.pos.x, float(site.pos.y), site.pos.z))
	for a in anchors:
		var nearest: int = -1
		var best_d: float = INF
		for i in range(all_nodes.size()):
			var dd: float = Vector2(all_nodes[i].x - a.x, all_nodes[i].z - a.z).length() + absf(float(all_nodes[i].y) - a.y) * 3.0
			if dd < best_d:
				best_d = dd
				nearest = i
		if nearest == -1 or best_d > 4.0:
			# add a connector node at the anchor, linked to the nearest existing node
			all_nodes.append({"x": a.x, "y": a.y, "z": a.z, "links": []})
			var ni: int = all_nodes.size() - 1
			# 只有锚点到最近节点的线段物理可达（不穿墙）才建立连接，
			# 否则 BFS 会沿这条"穿墙捷径"规划路线，bot 走到一半撞墙原地打转。
			if nearest != -1 and _walk_line_clear_3d(a, Vector3(all_nodes[nearest].x, float(all_nodes[nearest].y), all_nodes[nearest].z), m.colliders, cells, cs):
				all_nodes[ni].links.append(nearest)
				all_nodes[nearest].links.append(ni)
	return all_nodes


# 线段（含半径）覆盖的碰撞体候选索引列表（去重），只查线段经过的格子。
static func _line_cells(a: Vector3, b: Vector3, cells: Dictionary, cs: float) -> Array:
	var out: Array = []
	var seen := {}
	var len: float = Vector2(b.x - a.x, b.z - a.z).length()
	var steps: int = maxi(1, int(ceil(len / (cs * 0.5))))
	for s in range(steps + 1):
		var t: float = float(s) / float(steps)
		var px: float = a.x + (b.x - a.x) * t
		var pz: float = a.z + (b.z - a.z) * t
		var key: Vector2i = Vector2i(int(floor(px / cs)), int(floor(pz / cs)))
		if seen.has(key):
			continue
		seen[key] = true
		var bucket: Array = cells.get(key, [])
		for ci in bucket:
			if not seen.has(ci):
				seen[ci] = true
				out.append(ci)
	return out


# 生成一层 2m 网格导航节点（h=0 为地面层；h>0 为平台层，节点必须踩在对应高度的 slab 上）。
static func _nav_layer(m: Dictionary, h: float, margin: float, spacing: float, cells: Dictionary, cs: float) -> Array:
	var nodes: Array = []
	var size: Vector2 = m.size
	var lo: float = -size.x / 2.0 + 1.0
	var hi: float = size.x / 2.0 - 1.0
	var z: float = lo
	var zi: int = 0
	while z <= hi:
		var x: float = lo
		var xi: int = 0
		while x <= hi:
			if _nav_point_ok(m, x, z, h, margin, cells, cs):
				nodes.append({"x": x, "y": h, "z": z, "links": [], "gi": Vector2i(xi, zi)})
			xi += 1
			x = lo + xi * spacing
		zi += 1
		z = lo + zi * spacing
	return nodes


static func _nav_point_ok(m: Dictionary, x: float, z: float, h: float, margin: float, cells: Dictionary, cs: float) -> bool:
	# 只查点所在格子及其 8 邻域（margin 可能跨格）
	var cx: int = int(floor(x / cs))
	var cz: int = int(floor(z / cs))
	var cands: Array = []
	var seen := {}
	for gx in range(cx - 1, cx + 2):
		for gz in range(cz - 1, cz + 2):
			var bucket: Array = cells.get(Vector2i(gx, gz), [])
			for ci in bucket:
				if not seen.has(ci):
					seen[ci] = true
					cands.append(ci)
	if h <= 0.01:
		# 地面层：任何贴地障碍都阻挡（高于头顶的平台/屋顶 slab 不算）
		for ci in cands:
			var c: Dictionary = m.colliders[ci]
			var mn: Vector3 = c.min
			var mx: Vector3 = c.max
			if mn.y > 0.2:
				continue
			if x + margin > mn.x and x - margin < mx.x and z + margin > mn.z and z - margin < mx.z:
				return false
		return true
	# 平台层：先确认脚底踩在某块顶面为 h 的 slab 上
	var on_slab := false
	for c in m.colliders:
		if c.type != "floor":
			continue
		if absf(c.max.y - h) > 0.01 or c.max.y - c.min.y > 0.5:
			continue
		if x + margin > c.min.x and x - margin < c.max.x and z + margin > c.min.z and z - margin < c.max.z:
			on_slab = true
			break
	if not on_slab:
		return false
	# 再检查本层障碍（该垂直区间内的墙/箱/桶等；floor/ceiling 为可通行面不算）
	for ci in cands:
		var c: Dictionary = m.colliders[ci]
		if c.type == "floor" or c.type == "ceiling" or c.type == "step":
			continue
		var mn: Vector3 = c.min
		var mx: Vector3 = c.max
		if mn.y > h + 2.6 or mx.y < h - 0.3:
			continue
		if x + margin > mn.x and x - margin < mx.x and z + margin > mn.z and z - margin < mx.z:
			return false
	return true


static func _walk_line_clear(a: Vector3, b: Vector3, colliders: Array, height: float = 0.0, cells: Dictionary = {}, cs: float = 4.0) -> bool:
	var dir := b - a
	var len: float = dir.length()
	if len < 1e-6:
		return true
	dir /= len
	var r: float = 0.35
	var lo_y: float = height - 0.3
	var hi_y: float = height + 2.6
	# 候选碰撞体：有空间格则只查线段经过的格子（启动提速），否则全量
	var cands: Array
	if not cells.is_empty():
		cands = _line_cells(a, b, cells, cs)
	else:
		cands = []
		for ci in range(colliders.size()):
			cands.append(ci)
	# 线段包围盒粗筛：与线段（含半径）不相交的碰撞体直接跳过
	var min_x: float = min(a.x, b.x) - r
	var max_x: float = max(a.x, b.x) + r
	var min_z: float = min(a.z, b.z) - r
	var max_z: float = max(a.z, b.z) + r
	for ci in cands:
		var c: Dictionary = colliders[ci]
		if c.type == "ceiling":
			continue
		var mn: Vector3 = c.min
		var mx: Vector3 = c.max
		if mn.y > hi_y or mx.y < lo_y:
			continue
		if mx.x < min_x or mn.x > max_x or mx.z < min_z or mn.z > max_z:
			continue
		var t0: float = 0.0
		var t1: float = len
		var hit := false
		for i in range(3):
			var ri: float = r if i != 1 else 0.0
			var o: float = a[i]
			var d: float = dir[i]
			var lo: float = mn[i] - ri
			var hi: float = mx[i] + ri
			if absf(d) < 1e-9:
				if o < lo or o > hi:
					hit = true
					break
			else:
				var ta: float = (lo - o) / d
				var tb: float = (hi - o) / d
				if ta > tb:
					var tmp: float = ta
					ta = tb
					tb = tmp
				t0 = max(t0, ta)
				t1 = min(t1, tb)
				if t0 > t1:
					hit = true
					break
		if not hit:
			return false
	return true
# 3D 视线版 _walk_line_clear：检查线段（含垂直分量）是否穿过任何实体碰撞体。
# 用于跨层连线/锚点连线：floor/step 视为可通行面（bot 会被台阶块顶上去），
# ceiling 与未被占用层的 slab 不阻挡。
static func _walk_line_clear_3d(a: Vector3, b: Vector3, colliders: Array, cells: Dictionary = {}, cs: float = 4.0) -> bool:
	var dir := b - a
	var len: float = dir.length()
	if len < 1e-6:
		return true
	dir /= len
	var r: float = 0.35
	# 候选碰撞体：有空间格则只查线段经过的格子，否则全量
	var cands: Array
	if not cells.is_empty():
		cands = _line_cells(a, b, cells, cs)
	else:
		cands = []
		for ci in range(colliders.size()):
			cands.append(ci)
	# 线段包围盒粗筛
	var min_x: float = min(a.x, b.x) - r
	var max_x: float = max(a.x, b.x) + r
	var min_y: float = min(a.y, b.y) - 0.3
	var max_y: float = max(a.y, b.y) + 2.6
	var min_z: float = min(a.z, b.z) - r
	var max_z: float = max(a.z, b.z) + r
	for ci in cands:
		var c: Dictionary = colliders[ci]
		if c.type == "ceiling" or c.type == "floor" or c.type == "step":
			continue
		var mn: Vector3 = c.min
		var mx: Vector3 = c.max
		if mn.y > max_y or mx.y < min_y:
			continue
		if mx.x < min_x or mn.x > max_x or mx.z < min_z or mn.z > max_z:
			continue
		var t0: float = 0.0
		var t1: float = len
		var hit := false
		for i in range(3):
			var ri: float = r if i != 1 else 0.0
			var o: float = a[i]
			var d: float = dir[i]
			var lo: float = mn[i] - ri
			var hi: float = mx[i] + ri
			if absf(d) < 1e-9:
				if o < lo or o > hi:
					hit = true
					break
			else:
				var ta: float = (lo - o) / d
				var tb: float = (hi - o) / d
				if ta > tb:
					var tmp: float = ta
					ta = tb
					tb = tmp
				t0 = max(t0, ta)
				t1 = min(t1, tb)
				if t0 > t1:
					hit = true
					break
		if not hit:
			return false
	return true

