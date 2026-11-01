## An orbit to go to, rather than a craft: its shape (low and high points),
## its tilt to the central body's equator (inclination), where it crosses the
## equator going north (the node, RAAN), and where its low point lies (the
## argument of perigee). The planner's "Go to" offers the common ones (GEO,
## GPS's, Molniya, Tundra, sun-synchronous, a transfer to GEO, a disposal
## orbit, a re-entry) and any the user sets by hand; the engine flies there
## by Lambert to the cheapest point on it, then a second burn on arrival to
## join it (Sim.plan_goal, Sim.plan_insert).
## A spec: {name, hp, ha (km above the surface), i (deg), raan ("ours" or deg),
## argp (deg)}. Elements: {a, e, i, raan, argp} (km, rad). Angles are measured
## in the central body's equator: about its true pole, from the vernal
## equinox (the game frame's for a world other than the Earth).
class_name OrbitGoal

## Earth's J2 and the Sun's mean motion about it, for the sun-synchronous tilt
## (Vallado 2013, eq. 9-41; J2 from EGM2008).
const J2 := 1.08262668e-3
const SSO_RATE := 1.99106e-7 # rad/s: 360° a year


## The common orbits, as specs for this world (heights above its surface).
static func presets(sim: Sim) -> Array:
	var out := [
		["leo", {"name": "Low, circular", "hp": 500.0, "ha": 500.0, "i": -1.0, "raan": "ours", "argp": 0.0}],
	]
	if sim.central == "earth":
		out.append_array([
			["sso", {"name": "Sun-synchronous", "hp": 700.0, "ha": 700.0, "i": sso_tilt(sim, 700.0), "raan": "ours", "argp": 0.0}],
			["gps", {"name": "Medium (GPS)", "hp": 20180.0, "ha": 20180.0, "i": 55.0, "raan": "ours", "argp": 0.0}],
			["gto", {"name": "Transfer to GEO", "hp": 250.0, "ha": 35786.0, "i": 27.0, "raan": "ours", "argp": 0.0}],
			["geo", {"name": "Geostationary", "hp": 35786.0, "ha": 35786.0, "i": 0.0, "raan": "ours", "argp": 0.0}],
			["grave", {"name": "Above GEO (disposal)", "hp": 36086.0, "ha": 36086.0, "i": 0.0, "raan": "ours", "argp": 0.0}],
			["molniya", {"name": "Molniya", "hp": 600.0, "ha": 39700.0, "i": 63.4, "raan": "ours", "argp": 270.0}],
			["tundra", {"name": "Tundra", "hp": 24400.0, "ha": 47100.0, "i": 63.4, "raan": "ours", "argp": 270.0}],
			["reentry", {"name": "Re-entry (low point 50 km)", "hp": 50.0, "ha": -1.0, "i": -1.0, "raan": "ours", "argp": 0.0}],
		])
	return out


## The tilt (deg) that turns a circular orbit at height h with the Sun.
static func sso_tilt(sim: Sim, h: float) -> float:
	var R := sim.central_radius()
	var a := R + h
	var c := -2.0 * SSO_RATE * pow(a, 3.5) / (3.0 * J2 * R * R * sqrt(sim.mu))
	return rad_to_deg(acos(clampf(c, -1.0, 1.0)))


## The equator's frame: [x toward the equinox, y, z the pole].
static func frame(sim: Sim) -> Array:
	var z := V.of(0, 0, 1)
	var x := V.of(1, 0, 0)
	if sim.central == "earth":
		var B := Ephem.earth_fixed(sim.utc_ms())
		z = sim._icrf_dir([B.z.x, B.z.y, B.z.z])
		x = sim._icrf_dir([1.0, 0.0, 0.0])
	z = V.scale(z, 1.0 / V.norm(z))
	x = V.sub(x, V.scale(z, V.dot(x, z)))
	x = V.scale(x, 1.0 / V.norm(x))
	return [x, V.cross(z, x), z]


## A craft's orbit as elements (from its state now).
static func of_state(sim: Sim, r: PackedFloat64Array, v: PackedFloat64Array) -> Dictionary:
	var F := frame(sim)
	var mu := sim.mu
	var h := V.cross(r, v)
	var hz := V.dot(h, F[2])
	var i := acos(clampf(hz / V.norm(h), -1.0, 1.0))
	var nvec := V.cross(F[2], h) # toward the ascending node
	var raan := 0.0
	if V.norm(nvec) > 1e-9:
		raan = fposmod(atan2(V.dot(nvec, F[1]), V.dot(nvec, F[0])), TAU)
		nvec = V.scale(nvec, 1.0 / V.norm(nvec))
	else:
		nvec = F[0]
	var ev := V.sub(V.scale(r, V.dot(v, v) / mu - 1.0 / V.norm(r)), V.scale(v, V.dot(r, v) / mu))
	var e := V.norm(ev)
	var a := 1.0 / (2.0 / V.norm(r) - V.dot(v, v) / mu)
	var argp := 0.0
	if e > 1e-6:
		var hn := V.scale(h, 1.0 / V.norm(h))
		argp = fposmod(atan2(V.dot(V.cross(nvec, ev), hn), V.dot(nvec, ev)), TAU)
	return {"a": a, "e": e, "i": i, "raan": raan, "argp": argp}


## A spec made into elements, for a craft (whose node "ours" means its own,
## and whose tilt -1 means its own; a high point -1 keeps its own).
static func elements(sim: Sim, spec: Dictionary, id: String) -> Dictionary:
	var s: Dictionary = sim.by_id[id]
	var own := of_state(sim, s.r, s.v)
	var R := sim.central_radius()
	var rp := R + float(spec.hp)
	var ra: float = R + float(spec.ha) if float(spec.ha) >= 0.0 else float(own.a) * (1.0 + float(own.e))
	if ra < rp:
		var k := ra
		ra = rp
		rp = k
	var i := deg_to_rad(float(spec.i)) if float(spec.i) >= 0.0 else float(own.i)
	var raan := float(own.raan) if String(spec.raan) == "ours" else deg_to_rad(float(spec.raan))
	return {"a": (rp + ra) / 2.0, "e": (ra - rp) / (ra + rp), "i": i, "raan": raan, "argp": deg_to_rad(float(spec.get("argp", 0.0)))}


## The orbit's state at true anomaly nu: [r, v] in the game frame.
static func state(sim: Sim, el: Dictionary, nu: float) -> Array:
	var F := frame(sim)
	var mu := sim.mu
	var a := float(el.a)
	var e := float(el.e)
	var p := a * (1.0 - e * e)
	var rn := p / (1.0 + e * cos(nu))
	var P := _axis(F, el, 0.0)
	var Qv := _axis(F, el, PI / 2.0)
	var r := V.add(V.scale(P, rn * cos(nu)), V.scale(Qv, rn * sin(nu)))
	var k := sqrt(mu / p)
	var v := V.add(V.scale(P, -k * sin(nu)), V.scale(Qv, k * (e + cos(nu))))
	return [r, v]


## The orbit's in-plane direction at angle u from its low point.
static func _axis(F: Array, el: Dictionary, u: float) -> PackedFloat64Array:
	var O := float(el.raan)
	var w := float(el.argp) + u
	var i := float(el.i)
	var x := cos(O) * cos(w) - sin(O) * sin(w) * cos(i)
	var y := sin(O) * cos(w) + cos(O) * sin(w) * cos(i)
	var z := sin(w) * sin(i)
	return V.add(V.add(V.scale(F[0], x), V.scale(F[1], y)), V.scale(F[2], z))


## The anomaly of the point on the orbit nearest r (r turned into its plane).
static func nu_at(sim: Sim, el: Dictionary, r: PackedFloat64Array) -> float:
	var F := frame(sim)
	var P := _axis(F, el, 0.0)
	var Qv := _axis(F, el, PI / 2.0)
	return atan2(V.dot(r, Qv), V.dot(r, P))

