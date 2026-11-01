## Arriving at another body to stay: the Moon from the Earth, or a planet at
## the end of a flight between planets; and the Earth–Moon Lagrange points.
##
## The flight is aimed off the body's centre in the B-plane (the plane through
## the body square to the incoming asymptote, the excess velocity v∞), by
## b = r_p·√(1 + 2μ/(r_p·v∞²)), so that it passes at the low point asked for
## (Curtis 2020, Eq. 8.53), and on the side that tilts the orbit as asked.
## Inside the body's pull a correction burn re-aims it: a Lambert arc about
## the body to the low point, refined under full gravity (Sim._approach).
## At the low point one burn slows it into the orbit asked for, costing
## √(v∞² + 2μ/r_p) − v_p (Curtis 2020, Eq. 8.59, for an ellipse of low point
## r_p and high point r_a, v_p = √(2μ/r_p − 2μ/(r_p + r_a))).
## Tilts are to the body's equator, about its north pole (IAU 2015). The
## arriving hyperbola's plane holds v∞, so the orbit's tilt can be no less
## than v∞'s declination: asked for less, it arrives at that least tilt.
class_name Arrival

## North poles at J2000: ICRF right ascension and declination (deg), IAU 2015
## (Archinal et al. 2018, Tables 1 and 2; rates and periodic terms omitted).
const POLES := {"mercury": [281.0103, 61.4155], "venus": [272.76, 67.16], "earth": [0.0, 90.0], "mars": [317.269202, 54.432516],
	"jupiter": [268.056595, 64.495303], "saturn": [40.589, 83.537], "uranus": [257.311, -15.175], "neptune": [299.36, 43.46],
	"moon": [269.9949, 66.5392]}
const MOON_R := 1737.4 # km, IAU 2015 mean radius
const GM_EARTH := 398600.435507 # km³/s², DE440, the Earth alone


static func gm(body: String) -> float:
	return Ephem.GM_MOON if body == "moon" else Ephem.gm(body)


static func radius(body: String) -> float:
	return MOON_R if body == "moon" else float(Ephem.BODY[body].re)


static func name_of(body: String) -> String:
	return "the Moon" if body == "moon" else String(Ephem.BODY[body].name)


## The body's north pole as a unit vector in the game frame.
static func pole(body: String, ms: float) -> PackedFloat64Array:
	var p: Array = POLES[body]
	var a := deg_to_rad(float(p[0]))
	var d := deg_to_rad(float(p[1]))
	var g := Ephem._to_game(V.of(cos(d) * cos(a), cos(d) * sin(a), sin(d)), Ephem.centuries(ms))
	return V.scale(g, 1.0 / V.norm(g))


## The Moon about the Earth (game frame): [r, v], v by a central difference.
static func moon_state(ms: float) -> Array:
	var a := Ephem.moon(ms - 60000.0)
	var b := Ephem.moon(ms + 60000.0)
	return [Ephem.moon(ms), V.scale(V.sub(b, a), 1.0 / 120.0)]


## The orbit's plane holding the unit vector s (v∞, or where the craft is),
## tilted i (rad; < 0: the least) to the body's pole: [h (unit normal), the
## tilt it gets]. Of the two planes at that tilt, the one nearer `near`'s
## (the plane it is in now: cheaper to turn), else the one whose node leads.
static func plane(s: PackedFloat64Array, pole_: PackedFloat64Array, i: float, near := PackedFloat64Array()) -> Array:
	var pp := V.sub(pole_, V.scale(s, V.dot(pole_, s)))
	var m := V.norm(pp) # cos of v∞'s declination
	if m < 1e-9:
		var any := V.cross(s, V.of(1, 0, 0) if absf(s[0]) < 0.9 else V.of(0, 1, 0))
		return [V.scale(any, 1.0 / V.norm(any)), PI / 2.0]
	var A := V.scale(pp, 1.0 / m)
	var B := V.cross(s, A)
	if i < 0.0:
		return [A, acos(clampf(m, -1.0, 1.0))] # the least tilt
	var c := cos(i) / m
	if c >= 1.0:
		return [A, acos(clampf(m, -1.0, 1.0))]
	if c <= -1.0:
		return [V.scale(A, -1.0), PI - acos(clampf(m, -1.0, 1.0))]
	var al := acos(c)
	var h1 := V.add(V.scale(A, cos(al)), V.scale(B, sin(al)))
	var h2 := V.sub(V.scale(A, cos(al)), V.scale(B, sin(al)))
	return [h2 if near.size() == 3 and V.dot(h2, near) > V.dot(h1, near) else h1, i]


## Where the low point lies for a pass along s at r_p in the plane of normal
## h: the asymptote turned through half the bend δ, sin(δ/2) = 1/e,
## e = 1 + r_p·v∞²/μ (Curtis 2020, Eqs. 8.40 and 2.100).
static func periapsis_dir(s: PackedFloat64Array, h: PackedFloat64Array, vinf: float, mu: float, rp: float) -> PackedFloat64Array:
	var sd := 1.0 / (1.0 + rp * vinf * vinf / mu)
	var cd := sqrt(1.0 - sd * sd)
	return V.sub(V.scale(s, sd), V.scale(V.cross(h, s), cd))


## The aim off the centre, in the B-plane, for a pass at r_p in the plane of h.
static func aim(s: PackedFloat64Array, h: PackedFloat64Array, vinf: float, mu: float, rp: float) -> PackedFloat64Array:
	return V.scale(V.cross(s, h), rp * sqrt(1.0 + 2.0 * mu / (rp * maxf(vinf * vinf, 1e-12))))


## The burn at the low point r_p into the orbit r_p × r_a, arriving at v∞.
static func capture_dv(vinf: float, mu: float, rp: float, ra: float) -> float:
	return sqrt(vinf * vinf + 2.0 * mu / rp) - sqrt(2.0 * mu / rp - 2.0 * mu / (rp + maxf(ra, rp)))


## The time from distance r in to the low point r_p on the hyperbola of v∞:
## r = a(1 − e·cosh H), t = √(−a³/μ)(e·sinh H − H) (Curtis 2020, Eqs. 3.40, 3.44).
static func time_to_peri(r: float, vinf: float, mu: float, rp: float) -> float:
	var a := -mu / maxf(vinf * vinf, 1e-12)
	var e := 1.0 + rp * vinf * vinf / mu
	var ch := maxf(1.0, (1.0 - r / a) / e)
	var H := log(ch + sqrt(ch * ch - 1.0))
	return sqrt(-a * a * a / mu) * (e * sinh(H) - H)


## The arrival orbit asked for, as radii from the centre: {rp, ra, i}. A spec
## gives heights above the surface (hp, ha) and the tilt (deg; < 0: any).
static func radii(body: String, spec: Dictionary) -> Dictionary:
	var R := radius(body)
	var rp := R + float(spec.get("hp", (Transfer.CAPTURE_R - 1.0) * R))
	var ra := maxf(rp, R + float(spec.get("ha", spec.get("hp", (Transfer.CAPTURE_R - 1.0) * R))))
	var i := float(spec.get("i", -1.0))
	return {"rp": rp, "ra": ra, "i": deg_to_rad(i) if i >= 0.0 else -1.0}


## Earth–Moon Lagrange point k (1 to 5) about the Earth at ms: [r, v], game
## frame. L1, L2 and L3 on the Earth–Moon line, from the restricted
## three-body problem's equilibrium x − (1−μ)(x+μ)/|x+μ|³ − μ(x−1+μ)/|x−1+μ|³ = 0
## (Szebehely 1967; Koon, Lo, Marsden and Ross 2011, §2.5), solved by Newton;
## L4 and L5 lead and trail the Moon by 60°. Scaled to the Moon's own distance
## and speed, they keep up with its eccentric orbit.
static func lagrange(k: int, ms: float) -> Array:
	var m := moon_state(ms)
	if k >= 4:
		var h := V.cross(m[0], m[1])
		h = V.scale(h, 1.0 / V.norm(h))
		var ang := PI / 3.0 if k == 4 else -PI / 3.0
		return [_turn(m[0], h, ang), _turn(m[1], h, ang)]
	var f := lagrange_x(k)
	return [V.scale(m[0], f), V.scale(m[1], f)]


## L1, L2 or L3 as a multiple of the Earth–Moon distance, from the Earth.
static func lagrange_x(k: int) -> float:
	var mu := Ephem.GM_MOON / (GM_EARTH + Ephem.GM_MOON)
	var g := func(x: float) -> float:
		var d1 := x + mu
		var d2 := x - 1.0 + mu
		return x - (1.0 - mu) * d1 / pow(absf(d1), 3.0) - mu * d2 / pow(absf(d2), 3.0)
	var x: float = [0.0, 0.84, 1.16, -1.0][k]
	for _i in 40:
		var dx := (float(g.call(x + 1e-7)) - float(g.call(x - 1e-7))) / 2e-7
		var step := float(g.call(x)) / dx
		x -= step
		if absf(step) < 1e-14:
			break
	return x + mu


## v turned by ang about the unit axis h (Rodrigues).
static func _turn(v: PackedFloat64Array, h: PackedFloat64Array, ang: float) -> PackedFloat64Array:
	return V.add(V.add(V.scale(v, cos(ang)), V.scale(V.cross(h, v), sin(ang))), V.scale(h, V.dot(h, v) * (1.0 - cos(ang))))
