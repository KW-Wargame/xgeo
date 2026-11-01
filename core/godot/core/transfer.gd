## Interplanetary transfers: from wherever a ship is (about Jupiter, or about
## another planet once it has arrived) to another planet.
##
## The first guess is the patched-conic method (Curtis 2020, §8.6–8.9):
## - the heliocentric leg is Lambert's problem about the Sun, from the planet
##   the ship is leaving to where the target planet will be (Lambert.solve);
## - the excess speed it needs, v∞ = v₁ − v_planet, is then flown out of the
##   planet's pull on an escape hyperbola that passes through the ship's
##   position now and leaves along v∞ (departure());
## - on arrival, stopping in the orbit asked for (by default circular, 1.5
##   radii up) costs √(v∞² + 2μ/r_p) − v_p (Curtis 2020, Eq. 8.59), and the
##   aim point is offset by the B-plane distance b = r_p·√(1 + 2μ/(r_p·v∞²))
##   so the ship passes the planet at r_p instead of hitting its centre, on
##   the side that gives the tilt asked for (Eq. 8.53; Weber, Orbital
##   Mechanics & Astrodynamics, open text, "Planetary arrival"; arrival.gd).
## The burn actually flown is then corrected under the game's full gravity
## (Sun, planets, Jupiter and its moons; gravity.gd): coast the trial, take the
## miss at arrival, and correct v∞ by Newton's method, starting from the
## two-body arc's Jacobian and improving it after each pass by Broyden's
## update (differential correction, Vallado 2013; single shooting as in
## NASA/TP-20220014814, §5.2.1). Climbing out of
## Jupiter's well takes weeks, and the Sun's tide over them bends v∞ by a few
## tenths of a km/s, which patched conics leave out: hundreds of millions of km
## at Mars after three years. Two or three passes take it out.
class_name Transfer

const CAPTURE_R := 1.5 # arrival orbit, in planet radii (design value)
const PASSES := 6


## Which body's pull a point is under (sphere of influence, Laplace): a planet
## if it is inside that planet's, Jupiter inside Jupiter's, else the Sun.
static func home(r: PackedFloat64Array, ms: float) -> String:
	if V.norm(r) < Ephem.soi("jupiter"):
		return "jupiter"
	for b in Ephem.PLANETS:
		if b != "jupiter" and V.dist(r, Ephem.pos(b, ms)) < Ephem.soi(b):
			return b
	return "sun"


## The velocity at r (relative to a body of gm mu) whose escape hyperbola leaves
## with excess velocity vinf. Two answers, one each way round; [] if none.
## The hyperbola lies in the plane of r and vinf; with Δ the angle from r to
## the asymptote, its eccentricity solves r(1 + e·cos(θ∞ − Δ)) = (μ/v∞²)(e² − 1),
## θ∞ = acos(−1/e) (Curtis 2020, Eqs. 2.45, 2.100, 2.103; Weber, "Hyperbolic
## trajectories"), by bisection.
static func departure(r: PackedFloat64Array, vinf: PackedFloat64Array, mu: float) -> Array:
	var rn := V.norm(r)
	var vi := V.norm(vinf)
	if vi < 1e-9:
		return []
	var e1 := V.scale(r, 1.0 / rn)
	var vh := V.scale(vinf, 1.0 / vi)
	var perp := V.sub(vh, V.scale(e1, V.dot(vh, e1)))
	if V.norm(perp) < 1e-9:
		perp = V.cross(V.of(0, 0, 1), e1) # straight out: either way round is the same plane
	perp = V.scale(perp, 1.0 / V.norm(perp))
	var d0 := acos(clampf(V.dot(e1, vh), -1.0, 1.0))
	var out := []
	for side in [[d0, perp], [TAU - d0, V.scale(perp, -1.0)]]:
		var D: float = side[0]
		var f := func(e: float) -> float:
			var ti := acos(-1.0 / e)
			return rn * (1.0 + e * cos(ti - D)) - mu / (vi * vi) * (e * e - 1.0)
		var lo := 1.0 + 1e-12
		var hi := 1e6 if D <= PI else minf(1e6, -1.0 / cos(D / 2.0))
		if f.call(lo) <= 0.0 or f.call(hi) >= 0.0:
			continue
		for i in 200:
			var mid := (lo + hi) / 2.0
			if f.call(mid) > 0.0:
				lo = mid
			else:
				hi = mid
		var e := (lo + hi) / 2.0
		var th := acos(-1.0 / e) - D
		var p := mu / (vi * vi) * (e * e - 1.0)
		var h := sqrt(mu * p)
		var vr := mu / h * e * sin(th)
		var vt := mu / h * (1.0 + e * cos(th))
		out.append(V.add(V.scale(e1, vr), V.scale(side[1], vt)))
	return out


## The heliocentric leg and the burn for it, from state (r, v) relative to the
## body `from` at UTC ms0, to planet `to` after tof seconds. The cheaper of the
## two departures. {} if no transfer.
static func patched(r: PackedFloat64Array, v: PackedFloat64Array, from: String, to: String, ms0: float, tof: float, arr := {}) -> Dictionary:
	var sun0: Array = Ephem.state("sun", ms0)
	var P0: Array = _planet(from, ms0)
	# Heliocentric: planet relative to the Sun (game frame is Jupiter-centred).
	var R1 := V.sub(P0[0], sun0[0])
	var V1 := V.sub(P0[1], sun0[1])
	var ms1 := ms0 + tof * 1000.0
	var sun1: Array = Ephem.state("sun", ms1)
	var P1: Array = _planet(to, ms1)
	var R2 := V.sub(P1[0], sun1[0])
	var sol := Lambert.solve(R1, R2, tof, Ephem.GM_SUN)
	if sol.is_empty():
		return {}
	var vinf := V.sub(sol[0], V1)
	var mu := Ephem.gm(from)
	var best := {}
	for vd in departure(r, vinf, mu):
		var dv := V.norm(V.sub(vd, v))
		if best.is_empty() or dv < float(best.dv):
			best = {"v1": vd, "dv": dv}
	if best.is_empty():
		return {}
	var vinf2 := V.sub(sol[1], V.sub(P1[1], sun1[1]))
	best.vinf = vinf
	best.vinf_arr = vinf2
	var a := arrive(to, vinf2, ms1, arr)
	best.capture = a.capture
	best.tilt = a.tilt
	best.total = float(best.dv) + float(best.capture)
	# Aim: the planet, offset in the B-plane for a pass at the low point asked for.
	best.aim_off = a.aim
	best.R1 = R1
	best.V1 = V1
	best.R2 = V.add(R2, best.aim_off)
	return best


## Arriving at planet `to` with excess velocity vinf2 at ms, into the orbit
## arr asks for (Arrival.radii; {} is CAPTURE_R radii, circular, least tilt):
## {capture (km/s), aim (B-plane offset, km), tilt (rad)}.
static func arrive(to: String, vinf2: PackedFloat64Array, ms: float, arr := {}) -> Dictionary:
	var A := Arrival.radii(to, arr)
	var mu2 := Ephem.gm(to)
	var vn := maxf(V.norm(vinf2), 1e-9)
	var s := V.scale(vinf2, 1.0 / vn)
	var pl := Arrival.plane(s, Arrival.pole(to, ms), A.i)
	return {"capture": Arrival.capture_dv(vn, mu2, A.rp, A.ra), "aim": Arrival.aim(s, pl[0], vn, mu2, A.rp), "tilt": pl[1]}


## The Jacobian of the two-body arc about the Sun (arrival position per km/s
## of v∞, from R1 at V1 + v∞), by finite differences of 1 m/s: three columns.
static func jacobian(R1: PackedFloat64Array, V1: PackedFloat64Array, vinf: PackedFloat64Array, tof: float) -> Array:
	var v0 := V.add(V1, vinf)
	var r0: PackedFloat64Array = Kepler.propagate(R1, v0, tof, Ephem.GM_SUN)[0]
	var h := 1e-3
	var J := []
	for k in 3:
		var dv := V.of(h if k == 0 else 0.0, h if k == 1 else 0.0, h if k == 2 else 0.0)
		var rk: PackedFloat64Array = Kepler.propagate(R1, V.add(v0, dv), tof, Ephem.GM_SUN)[0]
		J.append(V.scale(V.sub(rk, r0), 1.0 / h))
	return J


## x with J·x = b (J as three columns), by Cramer's rule in 64-bit floats.
static func solve3(J: Array, b: PackedFloat64Array) -> PackedFloat64Array:
	var det := V.dot(J[0], V.cross(J[1], J[2]))
	if absf(det) < 1e-30:
		return PackedFloat64Array()
	return V.of(V.dot(b, V.cross(J[1], J[2])) / det, V.dot(J[0], V.cross(b, J[2])) / det, V.dot(J[0], V.cross(J[1], b)) / det)


## Broyden's update of J after a step dx changed the residual by dy:
## J += (dy − J·dx)·dxᵀ / (dx·dx) (Broyden 1965; Press et al. 2007, §9.7;
## corroborated by Bindel 2023, Cornell CS 4220 notes "Broyden", §2).
static func broyden(J: Array, dx: PackedFloat64Array, dy: PackedFloat64Array) -> Array:
	var Jdx := V.add(V.add(V.scale(J[0], dx[0]), V.scale(J[1], dx[1])), V.scale(J[2], dx[2]))
	var u := V.scale(V.sub(dy, Jdx), 1.0 / V.dot(dx, dx))
	return [V.add(J[0], V.scale(u, dx[0])), V.add(J[1], V.scale(u, dx[1])), V.add(J[2], V.scale(u, dx[2]))]


## v∞ for the heliocentric arc from R1 (planet moving at V1) to R2 in tof.
static func vinf_to(R1: PackedFloat64Array, V1: PackedFloat64Array, R2: PackedFloat64Array, tof: float) -> PackedFloat64Array:
	var sol := Lambert.solve(R1, R2, tof, Ephem.GM_SUN)
	return PackedFloat64Array() if sol.is_empty() else V.sub(sol[0], V1)


## A planet's (or Jupiter's) game-frame state [r, v] at UTC ms.
static func _planet(b: String, ms: float) -> Array:
	return Ephem.state(b, ms)
