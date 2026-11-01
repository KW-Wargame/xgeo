## Where the Sun and the planets are, seen from Jupiter, in the game's frame.
## JPL's approximate planetary positions (Standish & Williams 1992, "Keplerian
## Elements for Approximate Positions of the Major Planets", JPL SSD;
## https://ssd.jpl.nasa.gov/planets/approx_pos.html): Table 1 (mean ecliptic
## and equinox of J2000, valid 1800–2050), and outside those years Table 2a with
## the extra mean-anomaly terms of Table 2b for Jupiter to Neptune (3000 BC to
## 3000 AD). Computed by the algorithm on that page, rotated to the ICRF equator
## (obliquity 23.43928°, as there) and then into Jupiter's equatorial frame: x
## toward the ascending node of Jupiter's equator on the ICRF equator, z its IAU
## 2015 pole (Archinal et al. 2018). The game's moons and ships live in that
## plane; the Sun and the planets sit a few degrees out of it, and the physics
## keeps their true 3-D positions.
## "earth" is the Earth–Moon barycentre (the tables give no other), within
## 4,700 km of Earth's centre.
## Masses: GM from JPL's DE440 (Park et al. 2021; https://ssd.jpl.nasa.gov/astro_par.html),
## "system" values (planet plus moons) as listed there except Earth, given alone
## with the Moon added for the barycentre. Radii: equatorial and polar, IAU WGCCRE
## 2015 (Archinal et al. 2018, Table 4; readable copy NAIF pck00011.tpc BODY*_RADII;
## JPL https://ssd.jpl.nasa.gov/planets/phys_par.html),
## the Sun's the IAU 2015 nominal radius (Resolution B3).
## Checked against JPL Horizons in tools/verify (test_ephem.py).
class_name Ephem
extends RefCounted

const AU_KM := 149597870.7
const JD_UNIX := 2440587.5
const JD_J2000 := 2451545.0
const OBLIQUITY_DEG := 23.43928
const GM_SUN := 132712440041.279419 # km³/s², DE440
const R_SUN := 695700.0 # km, IAU 2015 B3 nominal

## [a au, e, I deg, L deg, varpi deg, Omega deg] and their rates per Julian century.
## Table 1, 1800–2050.
const T1 := {
	"mercury": [[0.38709927, 0.20563593, 7.00497902, 252.25032350, 77.45779628, 48.33076593],
		[0.00000037, 0.00001906, -0.00594749, 149472.67411175, 0.16047689, -0.12534081]],
	"venus": [[0.72333566, 0.00677672, 3.39467605, 181.97909950, 131.60246718, 76.67984255],
		[0.00000390, -0.00004107, -0.00078890, 58517.81538729, 0.00268329, -0.27769418]],
	"earth": [[1.00000261, 0.01671123, -0.00001531, 100.46457166, 102.93768193, 0.0],
		[0.00000562, -0.00004392, -0.01294668, 35999.37244981, 0.32327364, 0.0]],
	"mars": [[1.52371034, 0.09339410, 1.84969142, -4.55343205, -23.94362959, 49.55953891],
		[0.00001847, 0.00007882, -0.00813131, 19140.30268499, 0.44441088, -0.29257343]],
	"jupiter": [[5.20288700, 0.04838624, 1.30439695, 34.39644051, 14.72847983, 100.47390909],
		[-0.00011607, -0.00013253, -0.00183714, 3034.74612775, 0.21252668, 0.20469106]],
	"saturn": [[9.53667594, 0.05386179, 2.48599187, 49.95424423, 92.59887831, 113.66242448],
		[-0.00125060, -0.00050991, 0.00193609, 1222.49362201, -0.41897216, -0.28867794]],
	"uranus": [[19.18916464, 0.04725744, 0.77263783, 313.23810451, 170.95427630, 74.01692503],
		[-0.00196176, -0.00004397, -0.00242939, 428.48202785, 0.40805281, 0.04240589]],
	"neptune": [[30.06992276, 0.00859048, 1.77004347, -55.12002969, 44.96476227, 131.78422574],
		[0.00026291, 0.00005105, 0.00035372, 218.45945325, -0.32241464, -0.00508664]],
}
## Table 2a, 3000 BC – 3000 AD.
const T2 := {
	"mercury": [[0.38709843, 0.20563661, 7.00559432, 252.25166724, 77.45771895, 48.33961819],
		[0.00000000, 0.00002123, -0.00590158, 149472.67486623, 0.15940013, -0.12214182]],
	"venus": [[0.72332102, 0.00676399, 3.39777545, 181.97970850, 131.76755713, 76.67261496],
		[-0.00000026, -0.00005107, 0.00043494, 58517.81560260, 0.05679648, -0.27274174]],
	"earth": [[1.00000018, 0.01673163, -0.00054346, 100.46691572, 102.93005885, -5.11260389],
		[-0.00000003, -0.00003661, -0.01337178, 35999.37306329, 0.31795260, -0.24123856]],
	"mars": [[1.52371243, 0.09336511, 1.85181869, -4.56813164, -23.91744784, 49.71320984],
		[0.00000097, 0.00009149, -0.00724757, 19140.29934243, 0.45223625, -0.26852431]],
	"jupiter": [[5.20248019, 0.04853590, 1.29861416, 34.33479152, 14.27495244, 100.29282654],
		[-0.00002864, 0.00018026, -0.00322699, 3034.90371757, 0.18199196, 0.13024619]],
	"saturn": [[9.54149883, 0.05550825, 2.49424102, 50.07571329, 92.86136063, 113.63998702],
		[-0.00003065, -0.00032044, 0.00451969, 1222.11494724, 0.54179478, -0.25015002]],
	"uranus": [[19.18797948, 0.04685740, 0.77298127, 314.20276625, 172.43404441, 73.96250215],
		[-0.00020455, -0.00001550, -0.00180155, 428.49512595, 0.09266985, 0.05739699]],
	"neptune": [[30.06952752, 0.00895439, 1.77005520, 304.22289287, 46.68158724, 131.78635853],
		[0.00006447, 0.00000818, 0.00022400, 218.46515314, 0.01009938, -0.00606302]],
}
## Table 2b: b, c, s, f, added to M as b·T² + c·cos(f·T) + s·sin(f·T) (degrees).
const T2B := {
	"jupiter": [-0.00012452, 0.06064060, -0.35635438, 38.35125000],
	"saturn": [0.00025899, -0.13434469, 0.87320147, 38.35125000],
	"uranus": [0.00058331, -0.97731848, 0.17689245, 7.67025000],
	"neptune": [-0.00041348, 0.68346318, -0.10162547, 7.67025000],
}
## GM km³/s² (DE440), equatorial and polar radius km (IAU 2015).
const BODY := {
	"mercury": {"name": "Mercury", "gm": 22031.868551, "re": 2440.53, "rp": 2438.26},
	"venus": {"name": "Venus", "gm": 324858.592, "re": 6051.8, "rp": 6051.8},
	"earth": {"name": "Earth", "gm": 403503.235625, "re": 6378.1366, "rp": 6356.7519}, # Earth 398600.435507 + Moon 4902.800118
	"mars": {"name": "Mars", "gm": 42828.375816, "re": 3396.19, "rp": 3376.20},
	"jupiter": {"name": "Jupiter", "gm": 126712764.1, "re": 71492.0, "rp": 66854.0},
	"saturn": {"name": "Saturn", "gm": 37940584.8418, "re": 60268.0, "rp": 54364.0},
	"uranus": {"name": "Uranus", "gm": 5794556.4, "re": 25559.0, "rp": 24973.0},
	"neptune": {"name": "Neptune", "gm": 6836527.10058, "re": 24764.0, "rp": 24341.0},
}
const PLANETS := ["mercury", "venus", "earth", "mars", "jupiter", "saturn", "uranus", "neptune"]
## Jupiter's north pole, IAU 2015 (Archinal et al. 2018, Table 1; NAIF pck00011.tpc
## BODY599_POLE_RA/DEC): RA, Dec and rates per century; periodic terms (< 0.005°) omitted.
const POLE := [268.056595, -0.006499, 64.495303, 0.002413]
## Kept for older callers and tests: the two sets this file first held.
const EM_BARY := [[1.00000261, 0.01671123, -0.00001531, 100.46457166, 102.93768193, 0.0],
	[0.00000562, -0.00004392, -0.01294668, 35999.37244981, 0.32327364, 0.0]]
const JUPITER := [[5.20288700, 0.04838624, 1.30439695, 34.39644051, 14.72847983, 100.47390909],
	[-0.00011607, -0.00013253, -0.00183714, 3034.74612775, 0.21252668, 0.20469106]]

## Interpolation cache: every body's game-frame position at whole steps of
## CACHE_S, so the gravity model can ask hundreds of times a frame cheaply.
## Cubic Hermite between nodes (with velocities by central difference): under
## a kilometre for Mercury at a 6-hour step, far less for the rest.
const CACHE_S := 21600.0
static var _cache := {} # node index -> {body: [r, v]}


static func jd(utc_ms: float) -> float:
	return JD_UNIX + utc_ms / 86400000.0


static func centuries(utc_ms: float) -> float:
	return (jd(utc_ms) - JD_J2000) / 36525.0


## The Earth's body-fixed axes (ITRF) in the ICRF at UTC ms: the columns of
## P^T · R3(GMST)^T, with IAU 1976 precession P (Lieske et al. 1977) and IAU
## 1982 mean sidereal time (Vallado 2013, Algorithms 15 and 23; eq. 3-47).
## Nutation (under 20") and polar motion (under 0.5") are left out, and UT1
## is taken as UTC (under 1 s, 0.004°): the Earth's map sits within about a
## kilometre of where it is. Pro turns it by IERS 2010 instead.
static func earth_fixed(utc_ms: float) -> Basis:
	var T := centuries(utc_ms)
	var as_ := PI / 648000.0
	var zeta := (2306.2181 * T + 0.30188 * T * T + 0.017998 * T * T * T) * as_
	var zz := (2306.2181 * T + 1.09468 * T * T + 0.018203 * T * T * T) * as_
	var th := (2004.3109 * T - 0.42665 * T * T - 0.041833 * T * T * T) * as_
	var sec := 67310.54841 + (876600.0 * 3600.0 + 8640184.812866) * T + 0.093104 * T * T - 6.2e-6 * T * T * T
	var gmst := fposmod(sec, 86400.0) / 86400.0 * TAU
	# Frame rotations as rows (R3(a): [[c, s, 0], [-s, c, 0], [0, 0, 1]]).
	var P := _mul(_r3(-zz), _mul(_r2(th), _r3(-zeta))) # J2000 to mean of date
	var M := _mul(_t(P), _t(_r3(gmst))) # Earth-fixed to J2000
	return Basis(Vector3(M[0][0], M[1][0], M[2][0]), Vector3(M[0][1], M[1][1], M[2][1]), Vector3(M[0][2], M[1][2], M[2][2]))


static func _r3(a: float) -> Array:
	return [[cos(a), sin(a), 0.0], [-sin(a), cos(a), 0.0], [0.0, 0.0, 1.0]]


static func _r2(a: float) -> Array:
	return [[cos(a), 0.0, -sin(a)], [0.0, 1.0, 0.0], [sin(a), 0.0, cos(a)]]


static func _t(A: Array) -> Array:
	return [[A[0][0], A[1][0], A[2][0]], [A[0][1], A[1][1], A[2][1]], [A[0][2], A[1][2], A[2][2]]]


static func _mul(A: Array, B: Array) -> Array:
	var C := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
	for i in 3:
		for j in 3:
			C[i][j] = A[i][0] * B[0][j] + A[i][1] * B[1][j] + A[i][2] * B[2][j]
	return C


## Heliocentric position (km) on the ICRF equator, from one element set,
## with Table 2b's terms if given.
static func helio(el: Array, T: float, extra: Array = []) -> Vector3:
	var p := helio64(el, T, extra)
	return Vector3(p[0], p[1], p[2])


static func helio64(el: Array, T: float, extra: Array = []) -> PackedFloat64Array:
	var a: float = el[0][0] + el[1][0] * T
	var e: float = el[0][1] + el[1][1] * T
	var I := deg_to_rad(el[0][2] + el[1][2] * T)
	var L: float = el[0][3] + el[1][3] * T
	var varpi: float = el[0][4] + el[1][4] * T
	var node: float = el[0][5] + el[1][5] * T
	var w := deg_to_rad(varpi - node)
	var O := deg_to_rad(node)
	var Md := L - varpi
	if not extra.is_empty():
		var f := deg_to_rad(float(extra[3]) * T)
		Md += float(extra[0]) * T * T + float(extra[1]) * cos(f) + float(extra[2]) * sin(f)
	var M := deg_to_rad(fposmod(Md + 180.0, 360.0) - 180.0)
	var E := M + e * sin(M)
	for i in 30:
		var dE := (E - e * sin(E) - M) / (1.0 - e * cos(E))
		E -= dE
		if absf(dE) < 1e-14:
			break
	var xp := a * (cos(E) - e)
	var yp := a * sqrt(1.0 - e * e) * sin(E)
	var x := (cos(w) * cos(O) - sin(w) * sin(O) * cos(I)) * xp + (-sin(w) * cos(O) - cos(w) * sin(O) * cos(I)) * yp
	var y := (cos(w) * sin(O) + sin(w) * cos(O) * cos(I)) * xp + (-sin(w) * sin(O) + cos(w) * cos(O) * cos(I)) * yp
	var z := sin(w) * sin(I) * xp + cos(w) * sin(I) * yp
	var ob := deg_to_rad(OBLIQUITY_DEG)
	return PackedFloat64Array([x * AU_KM, (cos(ob) * y - sin(ob) * z) * AU_KM, (sin(ob) * y + cos(ob) * z) * AU_KM])


## A planet's heliocentric ICRF position (km): Table 1 in its years, else 2a+2b.
static func planet_helio(body: String, T: float) -> PackedFloat64Array:
	if T >= -2.0 and T <= 0.5:
		return helio64(T1[body], T)
	return helio64(T2[body], T, T2B.get(body, []))


## Rows of the ICRF → Jupiter-equator rotation at T centuries from J2000.
static func frame(T: float) -> Basis:
	var ra := deg_to_rad(POLE[0] + POLE[1] * T)
	var dec := deg_to_rad(POLE[2] + POLE[3] * T)
	var z := Vector3(cos(dec) * cos(ra), cos(dec) * sin(ra), sin(dec))
	var x := Vector3(0, 0, 1).cross(z).normalized()
	return Basis(x, z.cross(x), z)


## ICRF → game frame in 64 bits (the Basis rows are directions; their 32-bit
## rounding, 1e-7, is 0.1 km at a million km and 150 km at 10 AU: well inside
## the tables' own error).
static func _to_game(v: PackedFloat64Array, T: float) -> PackedFloat64Array:
	var F := frame(T)
	var r := PackedFloat64Array([0, 0, 0])
	for i in 3:
		var row: Vector3 = F[i]
		r[i] = float(row.x) * v[0] + float(row.y) * v[1] + float(row.z) * v[2]
	return r


## Jupiter → body (km), game frame, straight from the tables. body is "sun" or a planet.
static func exact(body: String, utc_ms: float) -> PackedFloat64Array:
	var T := centuries(utc_ms)
	var j := planet_helio("jupiter", T)
	if body == "sun":
		return _to_game(PackedFloat64Array([-j[0], -j[1], -j[2]]), T)
	if body == "jupiter":
		return PackedFloat64Array([0, 0, 0])
	var p := planet_helio(body, T)
	return _to_game(PackedFloat64Array([p[0] - j[0], p[1] - j[1], p[2] - j[2]]), T)


## Jupiter → Sun (km), in the game frame (z is out of the game's plane).
static func sun(utc_ms: float) -> PackedFloat64Array:
	return exact("sun", utc_ms)


## The Moon from the Earth's centre (km), game frame: Montenbruck & Gill's
## low-precision series (2000, Satellite Orbits, §3.3.2, Eqs. 3.47–3.48;
## after Brown's theory), ecliptic and equinox of J2000 turned to the ICRF by
## the obliquity. Good to a few arcminutes and about 500 km: what a third-body
## pull needs (its tide at 7,000 km from the Earth is under 1.2e-9 km/s²).
const GM_MOON := 4902.800118 # km³/s², DE440
static func moon(utc_ms: float) -> PackedFloat64Array:
	var T := centuries(utc_ms)
	var d := PI / 180.0
	var L0 := 218.31617 + 481267.88088 * T - 1.3972 * T
	var l := (134.96292 + 477198.86753 * T) * d
	var lp := (357.52543 + 35999.04944 * T) * d
	var F := (93.27283 + 483202.01873 * T) * d
	var D := (297.85027 + 445267.11135 * T) * d
	var lam := L0 + (22640.0 * sin(l) + 769.0 * sin(2 * l) - 4586.0 * sin(l - 2 * D) + 2370.0 * sin(2 * D) - 668.0 * sin(lp) - 412.0 * sin(2 * F)
		- 212.0 * sin(2 * l - 2 * D) - 206.0 * sin(l + lp - 2 * D) + 192.0 * sin(l + 2 * D) - 165.0 * sin(lp - 2 * D) + 148.0 * sin(l - lp)
		- 125.0 * sin(D) - 110.0 * sin(l + lp) - 55.0 * sin(2 * F - 2 * D)) / 3600.0
	var beta := (18520.0 * sin(F + (lam - L0) * d + (412.0 * sin(2 * F) + 541.0 * sin(lp)) / 3600.0 * d) - 526.0 * sin(F - 2 * D) + 44.0 * sin(l + F - 2 * D)
		- 31.0 * sin(-l + F - 2 * D) - 25.0 * sin(-2 * l + F) - 23.0 * sin(lp + F - 2 * D) + 21.0 * sin(-l + F) + 11.0 * sin(-lp + F - 2 * D)) / 3600.0
	var r := 385000.0 - 20905.0 * cos(l) - 3699.0 * cos(2 * D - l) - 2956.0 * cos(2 * D) - 570.0 * cos(2 * l) + 246.0 * cos(2 * l - 2 * D) - 205.0 * cos(lp - 2 * D) - 171.0 * cos(l + 2 * D) - 152.0 * cos(l + lp - 2 * D)
	var la := lam * d
	var be := beta * d
	var x := r * cos(be) * cos(la)
	var y := r * cos(be) * sin(la)
	var z := r * sin(be)
	var e := OBLIQUITY_DEG * d
	return _to_game(PackedFloat64Array([x, y * cos(e) - z * sin(e), y * sin(e) + z * cos(e)]), T)


## Jupiter → Earth (km): the Earth–Moon barycentre, 0.0003° from Earth at 5 AU.
static func earth(utc_ms: float) -> PackedFloat64Array:
	return exact("earth", utc_ms)


static func _node(i: int) -> Dictionary:
	if _cache.has(i):
		return _cache[i]
	if _cache.size() > 20000:
		_cache.clear()
	var out := {}
	var ms := i * CACHE_S * 1000.0
	var d := 600.0 * 1000.0 # ±10 min for the velocity
	for b in ["sun"] + PLANETS:
		if b == "jupiter":
			continue
		var a := exact(b, ms - d)
		var c := exact(b, ms + d)
		var v := PackedFloat64Array([(c[0] - a[0]) / 1200.0, (c[1] - a[1]) / 1200.0, (c[2] - a[2]) / 1200.0])
		out[b] = [exact(b, ms), v]
	_cache[i] = out
	return out


## Jupiter → body (km) and its velocity (km/s) relative to Jupiter, game frame,
## by cubic Hermite interpolation of the cache. Fast; use it in loops.
static func state(body: String, utc_ms: float) -> Array:
	if body == "jupiter":
		return [PackedFloat64Array([0, 0, 0]), PackedFloat64Array([0, 0, 0])]
	var s := utc_ms / 1000.0 / CACHE_S
	var i := floori(s)
	var u := s - i
	var A: Array = _node(i)[body]
	var B: Array = _node(i + 1)[body]
	var h := CACHE_S
	var h00 := 2 * u * u * u - 3 * u * u + 1
	var h10 := u * u * u - 2 * u * u + u
	var h01 := -2 * u * u * u + 3 * u * u
	var h11 := u * u * u - u * u
	var d00 := (6 * u * u - 6 * u) / h
	var d10 := 3 * u * u - 4 * u + 1
	var d01 := (-6 * u * u + 6 * u) / h
	var d11 := 3 * u * u - 2 * u
	var r := PackedFloat64Array([0, 0, 0])
	var v := PackedFloat64Array([0, 0, 0])
	for k in 3:
		r[k] = h00 * A[0][k] + h10 * h * A[1][k] + h01 * B[0][k] + h11 * h * B[1][k]
		v[k] = d00 * A[0][k] + d10 * A[1][k] + d01 * B[0][k] + d11 * B[1][k]
	return [r, v]


static func pos(body: String, utc_ms: float) -> PackedFloat64Array:
	return state(body, utc_ms)[0]


static func gm(body: String) -> float:
	return GM_SUN if body == "sun" else float(BODY[body].gm)


## Sphere of influence radius (km), Laplace: a·(m/M)^(2/5) (Curtis 2020, §8.4).
static func soi(body: String) -> float:
	return float(T1[body][0][0]) * AU_KM * pow(gm(body) / GM_SUN, 0.4)
