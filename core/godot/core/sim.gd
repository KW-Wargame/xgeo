## The running world: time, the moons, every ship coasting under real gravity
## (gravity.gd), and the systems that act on it each look: sensing (what Blue
## learns), Red's behaviour, the effects, and the campaign's bookkeeping.
## Content: data/game.json (exported from the JS engine) and
## a scenario file (data/scenarios/close_pass_earth.json, CLOSE PASS; the
## Jupiter shadowing survives as a test world, tests/fixtures/jupiter_shadow.json).
class_name Sim
extends RefCounted

signal logged(entry: Dictionary)

const HOUR := 3600.0
const DAY := 86400.0
const LOOK := 600.0 # s between sensor looks (as the JS game)

var data: Dictionary
var camp: Dictionary
var mu: float
var t := 0.0
var ships: Array = [] # Dictionary per ship: exported fields plus r, v, cls, state flags
var by_id := {}
var moons: Array
var gravity: Gravity
## Random draws come from named streams, one per subsystem (stream()), so a
## change in how often one subsystem draws never shifts another's numbers, and
## run N of a seed is the same world on every machine.
var master_seed := 0
var run := 0
var streams := {} # name -> RandomNumberGenerator
var intercepts: Array = [] # recordings: {id, ship, kind, f, bw, start, end, heard_by: {ear: snr}, df, classified}
var tracks := {} # ship id -> Track (Blue's belief)
var track_n := 4417
var log: Array = []
var escalation := 0.0
var tutorial := false # the walkthrough is running: Red plays by the scenario's "tutorial" settings
var next_look := LOOK
var sensing: Sensing
var thermal: Thermal
var red: RedAI
var traffic: Traffic
var effects: Effects
var campaign: Campaign
var debris: Array = [] # clouds (Breakup.cloud): {r, v, t, n, M, cat, of, frags}
var scheduled: Array = [] # planned burns: {at, id, target, tof}; to an orbit also {goal, nu}; joining it on arrival {insert: true, goal}


## The scenario a plain Sim.new() plays ("" for none: game.json alone).
static var campaign_path := "res://data/scenarios/close_pass_earth.json"

## The world the app plays (Sim.make()): a plain Sim, unless a layer built on
## Core (Pro) sets its own world here before the first scene starts.
static var maker := Callable()


static func make() -> Sim:
	return maker.call() if maker.is_valid() else Sim.new()


## The body the world's frame is centred on, whose pull mu is: Jupiter for
## the campaign; a world about another body (a planet in ephem.gd) sets it,
## and the view draws the Sun, the planets and Jupiter about it (body_pos).
var central := "jupiter"
## How the view opens on this world: {actor (the ship the player acts with),
## focus (a ship or body id), dist (render units, 1,000 km), pitch}, from a
## scenario's "view" block or a layer's world; what is left out stays the campaign's.
var opening := {}
## The heading's operation and area (HUD) for a world with no campaign file;
## a campaign's own "name" and "area" come first.
var title := ""
var area := ""


func _init(path := "res://data/game.json", camp_path := "*", seed_ := -1, run_ := 0) -> void:
	if camp_path == "*":
		camp_path = campaign_path
	data = JSON.parse_string(FileAccess.get_file_as_string(path))
	camp = JSON.parse_string(FileAccess.get_file_as_string(camp_path)) if camp_path != "" and FileAccess.file_exists(camp_path) else {}
	interplanetary = bool(camp.get("interplanetary", false)) or OS.get_cmdline_user_args().has("--interplanetary")
	# A scenario about another body: its "central" block stands in for Jupiter's
	# (data.jupiter holds the central body's constants, named for the campaign
	# it began with), with that body's moons (none at Earth here) and its date.
	var cb: Dictionary = camp.get("central", {})
	if not cb.is_empty():
		central = String(cb.id)
		data.jupiter.merge(cb, true)
		data.moons = cb.get("moons", [])
		data.startUtc = float(cb.get("startUtc", data.startUtc))
	mu = data.jupiter.gm
	moons = data.moons
	# How the view opens and the ship it acts with: {actor, focus, dist, pitch}.
	opening = camp.get("view", data.scenario.get("view", {})) # game.json alone has its own
	# The force model holds the constants it needs, not this Sim: no reference
	# cycle, and a track (Track.gravity is shared) never calls into a freed world.
	gravity = Gravity.new(mu, moons, _moon_state_of(moons, mu, float(data.epochOffset)))
	gravity.utc_of = _utc_of(float(data.startUtc))
	if not cb.is_empty():
		gravity.central = central
		gravity.j2 = float(cb.j2)
		gravity.r_ref = float(cb.radius)
		gravity.pole = _icrf_dir(cb.get("pole", [0.0, 0.0, 1.0]))
		if Ephem.BODY.has(central):
			gravity.far = Ephem.soi(central)
	Track.gravity = gravity
	master_seed = int(data.scenario.seed) if seed_ < 0 else seed_
	run = run_
	for k in camp.get("classes", {}):
		data.classes[k] = camp.classes[k]
	for k in camp.get("hulls", {}):
		data.hulls[k] = camp.hulls[k]
	# A class without a hull drawing (the kill vehicle: a model of its own) gets an empty one.
	for k in data.classes:
		if not data.hulls.has(k):
			data.hulls[k] = {"parts": []}
	# A campaign may bring its own ships in place of the JS game's.
	for s in camp.get("ships", data.scenario.ships):
		var d: Dictionary = s.duplicate(true)
		if d.has("orbit"):
			_place(d)
		elif d.has("state"):
			_place_state(d)
		elif d.has("near"):
			var o: Dictionary = by_id[String(d.near.of)]
			var rv := beside(o.r, o.v, d.near.ric_m)
			d.r0 = rv[0]
			d.v0 = rv[1]
			d.t0 = 0.0
		_add(d)
	if not camp.is_empty():
		_add_campaign()
	_update_fixed()
	thermal = Thermal.new(self)
	sensing = Sensing.new(self)
	red = RedAI.new(self)
	traffic = Traffic.new(self)
	effects = Effects.new(self)
	campaign = Campaign.new(self)
	sensing.begin()
	thermal.step(LOOK)


func _add(s: Dictionary) -> void:
	s.cls = data.classes[s.classId]
	if s.has("r0"):
		s.r = V.from(s.r0)
		s.v = V.from(s.v0)
	if s.cls.has("prop") and not s.has("prop"):
		s.prop = s.cls.prop
		s.dry = s.cls.dry
	# A ship with no part in a campaign (game.json alone) has no Red role.
	if not s.has("role"):
		s.role = ""
	s.alive = true
	s.flash_until = -1.0
	ships.append(s)
	by_id[s.id] = s


## A campaign ship on a circular orbit in the plane: {radius_km, phase_deg,
## along_km (+ ahead along the orbit), radial_km (+ out)}. Circular under the
## game's gravity, J2 included: v² = μ/r + (3/2)μJ2R²/r³ in the equator.
func _place(d: Dictionary) -> void:
	var o: Dictionary = d.orbit
	var rn := float(o.radius_km) + float(o.get("radial_km", 0.0))
	var ang := deg_to_rad(float(o.get("phase_deg", 0.0))) + float(o.get("along_km", 0.0)) / float(o.radius_km)
	var vc := sqrt(mu / rn + 1.5 * Gravity.J2 * mu * Gravity.R_REF * Gravity.R_REF / (rn * rn * rn))
	d.r0 = [rn * cos(ang), rn * sin(ang), 0.0]
	d.v0 = [-vc * sin(ang), vc * cos(ang), 0.0]
	d.t0 = 0.0


## A ship from its state at the scenario's start in the ICRF (GCRF) about the
## central body: {"state": {"r": km, "v": km/s}}, as an element set gives it
## (SGP4, then TEME to GCRF).
func _place_state(d: Dictionary) -> void:
	d.r0 = Array(_icrf_vec(d.state.r))
	d.v0 = Array(_icrf_vec(d.state.v))
	d.t0 = 0.0


func _icrf_vec(x: Array) -> PackedFloat64Array:
	return Ephem._to_game(PackedFloat64Array([float(x[0]), float(x[1]), float(x[2])]), Ephem.centuries(float(data.startUtc)))


func _icrf_dir(x: Array) -> PackedFloat64Array:
	var g := _icrf_vec(x)
	return V.scale(g, 1.0 / V.norm(g))


## A state ric_m metres from (r, v) in its radial, in-track and cross-track
## axes that does not drift away: the reference velocity, plus the frame's turn
## (omega = r x v / r^2) carried to the offset, plus -2 n x0 in-track for a
## radial offset x0 (the Clohessy-Wiltshire condition for no secular drift:
## Vallado 2013, Fundamentals of Astrodynamics, section 6.8). It then circles its
## place on a 2:1 ellipse, x0 radially and 2 x0 in-track, once an orbit.
static func beside(r: PackedFloat64Array, v: PackedFloat64Array, ric_m: Array) -> Array:
	var R := V.scale(r, 1.0 / V.norm(r))
	var h := V.cross(r, v)
	var C := V.scale(h, 1.0 / V.norm(h))
	var I := V.cross(C, R)
	var d := V.add(V.add(V.scale(R, float(ric_m[0]) * 1e-3), V.scale(I, float(ric_m[1]) * 1e-3)), V.scale(C, float(ric_m[2]) * 1e-3))
	var w := V.scale(h, 1.0 / V.dot(r, r))
	var n := V.norm(w)
	return [V.add(r, d), V.add(V.add(v, V.cross(w, d)), V.scale(I, -2.0 * n * float(ric_m[0]) * 1e-3))]


func _add_campaign() -> void:
	for r in camp.get("red", []):
		if r.get("from_game", false):
			by_id[r.id].role = r.role
			by_id[r.id].pocket = r.pocket
			continue
		var choices: Array = r.pocket if r.pocket is Array else [r.pocket]
		var pk: Dictionary = pocket(choices[stream("setup").randi() % choices.size()])
		var st := pocket_state(pk, 0.0)
		var off := V.of(float(r.offset[0]), float(r.offset[1]))
		var s := {"id": r.id, "name": r.name, "short": r.short, "side": "red", "kind": "hostile", "classId": r.class, "role": r.role, "pocket": pk.id, "operator": "UNKNOWN", "flag": "NONE",
			"r0": [st[0][0] + off[0], st[0][1] + off[1], 0.0], "v0": [st[1][0], st[1][1], 0.0], "t0": 0.0, "plan": r.duplicate()}
		_add(s)
	# Civil traffic on circular orbits: each one its own emitter (traffic.gd).
	for c in camp.get("civil", []):
		var rn := float(c.radius_km)
		var ang := deg_to_rad(float(c.phase_deg))
		var vc := sqrt(mu / rn)
		var s := {"id": c.id, "name": c.name, "short": c.short, "side": "neutral", "kind": "civil", "classId": c.class, "role": "CIVIL TRAFFIC", "operator": c.get("operator", ""),
			"r0": [rn * cos(ang), rn * sin(ang), 0.0], "v0": [-vc * sin(ang), vc * cos(ang), 0.0], "t0": 0.0}
		_add(s)
		if c.has("f"):
			# Its own channel: a copy of the class with this frequency.
			s.cls = s.cls.duplicate(true)
			s.cls.ttc.f = float(c.f)
	# Ground sites (radars, telescopes) on the turning Earth: {id, name, class, ground}.
	for g in camp.get("sites", []):
		var s: Dictionary = g.duplicate(true)
		s.classId = g.class
		s.side = g.get("side", "blue")
		s.kind = "site"
		var st := ground_state(g.ground)
		s.r0 = Array(st[0])
		s.v0 = Array(st[1])
		s.t0 = 0.0
		_add(s)
	for b in camp.get("blue_extra", []):
		var g := moon_state(b.staged.moon, 0.0)
		var rn := V.norm(g[0])
		var ang := atan2(g[0][1], g[0][0]) - float(b.staged.trail_km) / rn
		var vc := sqrt(mu / rn)
		var s: Dictionary = b.duplicate(true)
		s.classId = b.class
		s.r0 = [rn * cos(ang), rn * sin(ang), 0.0]
		s.v0 = [-vc * sin(ang), vc * cos(ang), 0.0]
		s.t0 = 0.0
		_add(s)


func pocket(id: String) -> Dictionary:
	for p in camp.get("pockets", []):
		if p.id == id:
			return p
	return {}


## The point a pocket is centred on at time at, and its velocity: a Lagrange
## point leads or trails its moon by 60° on the same orbit; any other sits
## still, radius km out on the x axis.
func pocket_state(p: Dictionary, at: float) -> Array:
	if p.kind == "lagrange":
		var m := moon_state(p.moon, at)
		var a := deg_to_rad(float(p.lead))
		return [V.of(m[0][0] * cos(a) - m[0][1] * sin(a), m[0][0] * sin(a) + m[0][1] * cos(a)), V.of(m[1][0] * cos(a) - m[1][1] * sin(a), m[1][0] * sin(a) + m[1][1] * cos(a))]
	return [V.of(float(p.radius), 0), V.of(0, 0)]


func pocket_center(p: Dictionary, at := NAN) -> PackedFloat64Array:
	return pocket_state(p, t if is_nan(at) else at)[0]


func moon(id: String) -> Dictionary:
	for m in moons:
		if m.id == id:
			return m
	return {}


## Moon state from JPL mean elements at sim time at. Returns [r, v].
static func _moon_state_of(moons_: Array, mu_: float, epoch_offset: float) -> Callable:
	return func(id: String, at: float) -> Array:
		for m in moons_:
			if m.id == id:
				return Kepler.from_elements(m, epoch_offset + at, mu_ + float(m.gm))
		return []


static func _utc_of(start_ms: float) -> Callable:
	return func(at: float) -> float: return start_ms + at * 1000.0


func moon_state(id: String, at: float) -> Array:
	var m := moon(id)
	return Kepler.from_elements(m, float(data.epochOffset) + at, mu + float(m.gm))


func ship(id: String) -> Dictionary:
	return by_id.get(id, {})


func pos(id: String) -> PackedFloat64Array:
	return by_id[id].r


## Does Blue know what this ship is? Ours, or a track it has classified. A
## track it hasn't is drawn only as its symbol: no hull on the map, a blur of
## heat in the infrared camera, until it is identified.
func class_known(id: String) -> bool:
	if by_id.has(id) and by_id[id].side == "blue":
		return true
	return tracks.has(id) and String(tracks[id].class_id) != ""


func range_km(a: String, b: String) -> float:
	return V.dist(pos(a), pos(b))


## The velocity that keeps a ship at r alongside one at (tr, tv): the
## target's own orbit, turned about the central body to r. Same energy, so the
## same period, and the same flight-path angle: the two coast round together at
## their offset, where matching velocity alone (equal speeds at different
## places in the field) lets them drift apart (Clohessy–Wiltshire; Vallado
## 2013, §6.8). The turn is about tr × r (Rodrigues' formula), so an offset
## out of the target's plane tilts the orbit with it; in the game plane it is
## the turn about z it always was.
func station_v(r: PackedFloat64Array, tr: PackedFloat64Array, tv: PackedFloat64Array) -> PackedFloat64Array:
	var v2 := V.dot(tv, tv) + 2.0 * mu * (1.0 / V.norm(r) - 1.0 / V.norm(tr))
	var spd := sqrt(maxf(v2, 0.0)) / maxf(V.norm(tv), 1e-9)
	if r.size() < 3 or tr.size() < 3 or tv.size() < 3 or (r[2] == 0.0 and tr[2] == 0.0 and tv[2] == 0.0):
		var th := atan2(tr[0] * r[1] - tr[1] * r[0], tr[0] * r[0] + tr[1] * r[1])
		var c := cos(th)
		var s := sin(th)
		return V.of((tv[0] * c - tv[1] * s) * spd, (tv[0] * s + tv[1] * c) * spd, 0.0)
	var k := V.cross(tr, r)
	var kn := V.norm(k)
	if kn < 1e-12:
		return V.scale(tv, spd)
	k = V.scale(k, 1.0 / kn)
	var c := V.dot(tr, r) / (V.norm(tr) * V.norm(r))
	var s := kn / (V.norm(tr) * V.norm(r))
	var out := V.add(V.add(V.scale(tv, c), V.scale(V.cross(k, tv), s)), V.scale(k, V.dot(k, tv) * (1.0 - c)))
	return V.scale(out, spd)


func range_rate(a: String, b: String) -> float:
	var d := V.sub(pos(b), pos(a))
	var dv := V.sub(by_id[b].v, by_id[a].v)
	return V.dot(d, dv) / maxf(V.norm(d), 1e-9)


func utc(at := NAN) -> Dictionary:
	var ms := float(data.startUtc) + (t if is_nan(at) else at) * 1000.0
	return Time.get_datetime_dict_from_unix_time(int(ms / 1000.0))


func delta_v(id: String) -> float:
	var s: Dictionary = by_id[id]
	if not s.cls.has("engine") or not s.has("prop"):
		return 0.0
	return RF.delta_v(float(s.cls.engine.ve), float(s.dry), float(s.prop))


## A line in the log. code: a stable id; text: what the player reads (already
## in the chosen language); kind: info / good / warn / alert.
func say(code: String, text: String, kind := "info", data_ := {}) -> void:
	var e := {"t": t, "code": code, "text": text, "kind": kind, "data": data_}
	log.append(e)
	logged.emit(e)


## Advance the world by dt seconds. Systems act at every look boundary.
func advance(dt: float) -> void:
	while dt > 1e-9:
		var h := minf(dt, next_look - t)
		if h <= 1e-9:
			h = minf(dt, LOOK)
		h = minf(h, effects.max_step()) # fine steps while a kill vehicle homes
		for b in scheduled: # stop on a planned burn's moment: flown late, it is another burn
			if float(b.at) - t > 1e-6:
				h = minf(h, float(b.at) - t)
		_step(h)
		dt -= h
		for b in scheduled.duplicate():
			if t >= b.at:
				scheduled.erase(b)
				var tgt: String = b.target
				if b.get("insert", false):
					execute(plan_insert(b.id, b.goal))
					continue
				if b.get("approach", false):
					_approach(b)
					continue
				if b.get("capture", false):
					_capture(b)
					continue
				if tgt.begins_with("goal:"):
					execute(plan_goal(b.id, b.goal, b.tof, float(b.nu), tgt))
					continue
				var plan := plan_to(b.id, pocket_center(pocket(tgt.substr(7)), t + b.tof), b.tof, 0.0, tgt) if tgt.begins_with("pocket:") else (plan_planet(b.id, tgt.substr(7), b.tof, b.get("arr", {})) if tgt.begins_with("planet:") else plan_intercept(b.id, tgt, b.tof))
				execute(plan)
		if t >= next_look - 1e-6:
			thermal.step(LOOK)
			sensing.look()
			red.think()
			traffic.think()
			effects.tick(LOOK)
			campaign.check()
			next_look += LOOK


func _step(h: float) -> void:
	var sub_h := minf(60.0, h)
	for s in ships:
		if s.has("r") and not s.has("onMoon") and not s.has("ground") and s.alive:
			# Civil traffic keeps to Kepler orbits (cheap); everyone else feels the moons.
			var st: Array = Kepler.propagate(s.r, s.v, h, mu) if s.get("kind", "") == "civil" else gravity.coast(s.r, s.v, t, h, sub_h)
			s.r = st[0]
			s.v = st[1]
	# Debris: the cloud's centre and each fragment flown on its own orbit.
	for d in debris:
		var st := Kepler.propagate(d.r, d.v, h, mu)
		d.r = st[0]
		d.v = st[1]
		for f in d.get("frags", []):
			var fs := Kepler.propagate(f.r, f.v, h, mu)
			f.r = fs[0]
			f.v = fs[1]
	effects.step(h)
	t += h
	_update_fixed()


func _update_fixed() -> void:
	for s in ships:
		if s.has("onMoon"):
			var st := moon_state(s.onMoon, t)
			s.r = st[0]
			s.v = st[1]
		elif s.has("ground"):
			var st := ground_state(s.ground)
			s.r = st[0]
			s.v = st[1]


const EARTH_RATE := 7.292115e-5 # rad/s, IERS Conventions 2010 (sidereal)
const WGS84_F := 1.0 / 298.257223563


## A site on the Earth at {lat_deg, lon_deg, h_km} (WGS 84, geodetic) in the
## world's frame now, and its velocity as the Earth turns it: the
## ellipsoid's point (Vallado 2013, Algorithm 51), turned into the ICRF by
## Ephem.earth_fixed, then into the game's axes.
func ground_state(g: Dictionary, at := NAN) -> Array:
	var lat := deg_to_rad(float(g.lat_deg))
	var lon := deg_to_rad(float(g.lon_deg))
	var h := float(g.get("h_km", 0.0))
	var Re := central_radius()
	var e2 := WGS84_F * (2.0 - WGS84_F)
	var N := Re / sqrt(1.0 - e2 * sin(lat) * sin(lat))
	var ecef := Vector3((N + h) * cos(lat) * cos(lon), (N + h) * cos(lat) * sin(lon), (N * (1.0 - e2) + h) * sin(lat))
	var ms := utc_ms(at)
	var B := Ephem.earth_fixed(ms)
	var icrf := B * ecef
	var r := Ephem._to_game(PackedFloat64Array([icrf.x, icrf.y, icrf.z]), Ephem.centuries(ms))
	var pole := _icrf_dir([B.z.x, B.z.y, B.z.z])
	return [r, V.scale(V.cross(pole, r), EARTH_RATE)]


## Coast a copy of a ship's state ahead under full gravity (its true future).
func predict(id: String, hours: float, points := 120) -> Array:
	var s: Dictionary = by_id[id]
	return predict_state(s.r, s.v, hours, points)


func predict_state(r: PackedFloat64Array, v: PackedFloat64Array, hours: float, points := 120) -> Array:
	var out := [r]
	var st := [r, v]
	var dt := hours * HOUR / points
	for i in points:
		st = gravity.coast(st[0], st[1], t + i * dt, dt, 300.0)
		out.append(st[0])
	return out


## The osculating Kepler ellipse through a state: the orbit with Jupiter alone,
## drawn from its elements (r = p / (1 + e cos θ)) rather than by propagating.
func osculating(r: PackedFloat64Array, v: PackedFloat64Array, points := 256) -> Array:
	var h := V.cross(r, v)
	var ev := V.sub(V.scale(V.cross(v, h), 1.0 / mu), V.scale(r, 1.0 / V.norm(r)))
	var e := V.norm(ev)
	if e >= 0.999:
		return []
	var p := V.dot(h, h) / mu
	var w := atan2(ev[1], ev[0]) if e > 1e-9 else 0.0
	var out := []
	for i in points + 1:
		var th := TAU * i / points
		var rr := p / (1.0 + e * cos(th))
		out.append(V.of(rr * cos(th + w), rr * sin(th + w)))
	return out


## Our first station (a fixed site in space, kind "station"), or "".
func station() -> String:
	for s in ships:
		if s.side == "blue" and s.kind == "station" and s.alive:
			return s.id
	return ""


## The class of the first live Red craft with a radio, or "".
func red_radio_class() -> String:
	for s in ships:
		if s.side == "red" and s.alive and s.cls.has("ttc"):
			return String(s.classId)
	return ""


## How far (km) an ear hears one of a Red class's command reports at even odds,
## from a bystander's angle: 90° off the line to its handler (a far sidelobe),
## with the ear looking straight at it.
func ear_range(ear_id: String, red_class: String, off_t := PI / 2.0) -> float:
	return Sensing.reach_km(data.classes[red_class].ttc, by_id[ear_id].cls.esm, off_t, float(data.cfg.radio.get("pfa", 1e-6)))


## Plan a transfer that meets a target tof seconds from now. For a Red ship
## it aims at Blue's track (its forecast), unless truth is asked for (tests);
## sigma says how wide the target's uncertainty will be on arrival.
func plan_intercept(id: String, target: String, tof: float, truth := false) -> Dictionary:
	var s: Dictionary = by_id[id]
	var tgt: Dictionary = by_id[target]
	var node: PackedFloat64Array
	var sigma := 0.0
	var now: Array # where it is now and how it moves (ours: the truth; Red: our track)
	if tgt.side == "red" and not truth:
		if not tracks.has(target):
			return {"ok": false, "why": "no track on it"}
		var f: Track = tracks[target].forecast(t + tof)
		node = f.pos()
		sigma = f.ellipse().major
		var f0: Track = tracks[target].forecast(t)
		now = [f0.pos(), f0.vel()]
	else:
		node = predict(target, tof / HOUR, maxi(12, int(tof / 600.0))).back()
		now = [tgt.r, tgt.v]
	# Lambert is two-body: aimed at where two-body motion takes the target, it
	# leaves out the same pulls (the Earth's bulge) on both craft, so its cost
	# is close to the real one; the burn is then refined to the true node.
	var aim := node
	if now[0].size() == s.r.size() and V.dist(now[0], s.r) < 0.05 * V.norm(s.r):
		aim = Kepler.propagate(now[0], now[1], tof, mu)[0]
	return plan_to(id, node, tof, sigma, target, aim)


## A transfer to node in tof: Lambert's cheapest arc of all the whole turns
## the time allows (in low orbit a few hours is a few turns, and the
## single-turn arc the long way round costs hundreds of m/s). One with turns
## is flown as a "turns" plan: refined by shooting (_shoot), which keeps them.
func plan_to(id: String, node: PackedFloat64Array, tof: float, sigma := 0.0, target := "", aim := PackedFloat64Array()) -> Dictionary:
	var s: Dictionary = by_id[id]
	if aim.is_empty():
		aim = node
	var a := Kepler.semi_major_axis(s.r, s.v, mu)
	var turns := int(tof / (TAU * sqrt(pow(a, 3.0) / mu))) if a > 0.0 else 0
	var all := Lambert.solve_all(s.r, aim, tof, mu, true, mini(turns, 8), V.cross(s.r, s.v))
	if all.is_empty():
		return {"ok": false, "why": "no transfer"}
	var best: Dictionary = all[0]
	for o in all:
		if V.dist(o.v1, s.v) < V.dist(best.v1, s.v):
			best = o
	var dv_vec := V.sub(best.v1, s.v)
	var dv := V.norm(dv_vec)
	var ok := dv <= delta_v(id)
	var plan := {"ok": ok, "why": "" if ok else "not enough fuel", "id": id, "target": target, "dv_vec": dv_vec, "dv": dv, "arrive": t + tof, "node": node, "sigma": sigma, "v2": best.v2}
	if int(best.revs) > 0:
		plan.kind = "turns"
	return plan


## To an orbit rather than a craft (OrbitGoal elements): Lambert to the point
## at anomaly nu on it, arriving after tof; flown, it sets the burn that joins
## the orbit there (plan_insert) for the moment it arrives.
func plan_goal(id: String, goal: Dictionary, tof: float, nu: float, target := "goal:") -> Dictionary:
	if goal.has("body"):
		return plan_moon(id, goal, tof, target)
	var st := Arrival.lagrange(int(goal.point), utc_ms(t + tof)) if goal.has("point") else OrbitGoal.state(self, goal, nu)
	var plan := plan_to(id, st[0], tof, 0.0, target)
	plan.goal = goal
	if goal.has("point"):
		plan.kind = "point" # days out, the Moon bends it: refined by the state-transition matrix
	return plan


## Join an orbit from where a craft is: the orbit's velocity at its point
## nearest the craft, less the craft's own (no refining: it is a burn now).
func plan_insert(id: String, goal: Dictionary) -> Dictionary:
	var s: Dictionary = by_id[id]
	var vg: PackedFloat64Array = Arrival.lagrange(int(goal.point), utc_ms())[1] if goal.has("point") else OrbitGoal.state(self, goal, OrbitGoal.nu_at(self, goal, s.r))[1]
	var dv_vec := V.sub(vg, s.v)
	var dv := V.norm(dv_vec)
	var ok := dv <= delta_v(id)
	return {"ok": ok, "why": "" if ok else "not enough fuel", "id": id, "target": "goal:joined", "dv_vec": dv_vec, "dv": dv, "arrive": t, "node": s.r, "kind": "orbit"}


## To the Moon, to stay (goal {body: "moon", hp, ha, i}): a Lambert arc about
## the Earth to the Moon's place on arrival, aimed off it in the B-plane for a
## pass at the low point asked for (Arrival). Flown, it sets the correction
## near the Moon and the burn into orbit there (_approach, _capture).
func plan_moon(id: String, goal: Dictionary, tof: float, target := "goal:moon") -> Dictionary:
	var s: Dictionary = by_id[id]
	var c := moon_cell(s.r, s.v, t, tof, goal)
	if c.is_empty():
		return {"ok": false, "why": "no transfer"}
	var dv_vec := V.sub(c.v1, s.v)
	var dv := V.norm(dv_vec)
	var ok := dv <= delta_v(id)
	return {"ok": ok, "why": "" if ok else "not enough fuel", "id": id, "target": target, "dv_vec": dv_vec, "dv": dv, "arrive": t + tof, "node": c.node, "sigma": 0.0,
		"v2": c.v2, "kind": "arrive", "body": "moon", "arr": goal, "capture": c.capture}


## One way to the Moon from (r0, v0) at t0, flying tof: the patched conic's
## {v1, v2, dv, capture, node (the aim point), vinf, tilt}; {} if none.
func moon_cell(r0: PackedFloat64Array, v0: PackedFloat64Array, t0: float, tof: float, goal: Dictionary) -> Dictionary:
	var ms := utc_ms(t0 + tof)
	var m := Arrival.moon_state(ms)
	var A := Arrival.radii("moon", goal)
	var off := V.of(0, 0, 0)
	var sol := []
	var vn := 0.0
	var pl := []
	for _k in 3: # the aim moves the arrival, and the arrival the aim: settles in two or three
		sol = Lambert.solve(r0, V.add(m[0], off), tof, mu, true, V.cross(r0, v0))
		if sol.is_empty():
			return {}
		var vi := V.sub(sol[1], m[1])
		vn = V.norm(vi)
		var sd := V.scale(vi, 1.0 / vn)
		pl = Arrival.plane(sd, Arrival.pole("moon", ms), A.i)
		off = Arrival.aim(sd, pl[0], vn, Ephem.GM_MOON, A.rp)
	return {"v1": sol[0], "v2": sol[1], "dv": V.dist(sol[0], v0), "capture": Arrival.capture_dv(vn, Ephem.GM_MOON, A.rp, A.ra), "node": V.add(m[0], off), "vinf": vn, "tilt": pl[1]}


## A body's state in the world's frame at sim time at: the Moon (about the
## Earth), or a planet.
func body_state(body: String, at := NAN) -> Array:
	if body == "moon":
		return Arrival.moon_state(utc_ms(at))
	var P := Ephem.state(body, utc_ms(at))
	return [to_world(P[0], at), to_world_v(P[1], at)]


## Near the body: re-aim at the low point (a Lambert arc about the body to it,
## refined under full gravity), and set the burn into orbit for when it is there.
func _approach(b: Dictionary) -> void:
	var id: String = b.id
	var body: String = b.body
	var s: Dictionary = by_id[id]
	if not s.alive:
		return
	var A := Arrival.radii(body, b.arr)
	var mu_b := Arrival.gm(body)
	var B := body_state(body)
	var r := V.sub(s.r, B[0])
	var v := V.sub(s.v, B[1])
	var rn := V.norm(r)
	var vinf := sqrt(maxf(V.dot(v, v) - 2.0 * mu_b / rn, 1e-6))
	# The plane holds where the craft is (a Lambert arc's plane holds both
	# its ends), at the tilt asked for, the nearer of the two to its own.
	var h := V.cross(r, v)
	h = V.scale(h, 1.0 / V.norm(h))
	if A.i >= 0.0:
		h = Arrival.plane(V.scale(r, 1.0 / rn), Arrival.pole(body, utc_ms()), A.i, h)[0]
	var sd := V.sub(v, V.scale(h, V.dot(v, h)))
	sd = V.scale(sd, 1.0 / V.norm(sd))
	var P := V.scale(Arrival.periapsis_dir(sd, h, vinf, mu_b, A.rp), A.rp)
	var tof := Arrival.time_to_peri(rn, vinf, mu_b, A.rp)
	var tag := "orbit:" + body
	if tof < 600.0:
		scheduled.append({"at": t + maxf(tof, 1.0), "id": id, "target": tag, "capture": true, "body": body, "arr": b.arr})
		return
	var sol := Lambert.solve(r, P, tof, mu_b, true, h)
	if sol.is_empty():
		say("burn", "%s found no way to its low point at %s." % [s.short, Arrival.name_of(body)], "warn")
		return
	var node := V.add(body_state(body, t + tof)[0], P)
	var v1: PackedFloat64Array = _shoot(id, V.add(sol[0], B[1]), node, tof)[0]
	var dv_vec := V.sub(v1, s.v)
	var dv := V.norm(dv_vec)
	if execute({"ok": dv <= delta_v(id), "id": id, "target": tag, "dv_vec": dv_vec, "dv": dv, "arrive": t + tof, "node": node, "kind": "orbit"}):
		scheduled.append({"at": t + tof, "id": id, "target": tag, "capture": true, "body": body, "arr": b.arr})
	else:
		say("burn", "%s cannot afford the correction to its low point at %s." % [s.short, Arrival.name_of(body)], "warn")


## At the low point: slow into the orbit asked for, its low point where the
## craft is, in the plane it is in.
func _capture(b: Dictionary) -> void:
	var id: String = b.id
	var body: String = b.body
	var s: Dictionary = by_id[id]
	if not s.alive:
		return
	var A := Arrival.radii(body, b.arr)
	var mu_b := Arrival.gm(body)
	var B := body_state(body)
	var r := V.sub(s.r, B[0])
	var v := V.sub(s.v, B[1])
	var rn := V.norm(r)
	var h := V.cross(r, v)
	var td := V.cross(h, r)
	td = V.scale(td, 1.0 / V.norm(td))
	var ra := maxf(float(A.ra), rn)
	var dv_vec := V.sub(V.scale(td, sqrt(mu_b * (2.0 / rn - 2.0 / (rn + ra)))), v)
	var dv := V.norm(dv_vec)
	if not execute({"ok": dv <= delta_v(id), "id": id, "target": "orbit:" + body, "dv_vec": dv_vec, "dv": dv, "arrive": t, "node": s.r, "kind": "orbit"}):
		say("burn", "%s cannot afford to stop at %s: it needs %.2f km/s." % [s.short, Arrival.name_of(body), dv], "warn")


## The velocity now that takes a craft to node in tof under full gravity, and
## how far it misses (km): Newton's method from v1, its Jacobian the
## state-transition matrix's position-by-velocity block (Gravity.coast_stm).
func _shoot(id: String, v1: PackedFloat64Array, node: PackedFloat64Array, tof: float) -> Array:
	var s: Dictionary = by_id[id]
	var best := v1
	var bm := INF
	for _i in 8:
		var st := gravity.coast_stm(s.r, v1, t, tof)
		var miss := V.sub(st[0], node)
		if V.norm(miss) < bm:
			bm = V.norm(miss)
			best = v1
		if bm < 0.5:
			break
		var phi: Array = st[2]
		var J := [V.of(phi[0][3], phi[1][3], phi[2][3]), V.of(phi[0][4], phi[1][4], phi[2][4]), V.of(phi[0][5], phi[1][5], phi[2][5])]
		var dx := Transfer.solve3(J, miss)
		if dx.is_empty():
			break
		v1 = V.sub(v1, dx)
	return [best, bm]


## Lambert's transfer is two-body. Close to Jupiter its oblateness (J2) bends a
## few hours' coast by thousands of km, so the burn actually flown is corrected
## by shooting: coast the trial transfer under the game's full gravity, move the
## aim point by the miss, re-solve, until it arrives within 50 m (a few passes;
## the classic differential-correction method, Vallado 2013; single shooting as in
## NASA/TP-20220014814, §5.2.1). Far out,
## where J2 is small, the first pass already lands. Updates dv_vec, dv, v2, and
## miss_km: how far from its aim the burn it settles on arrives, flown under full
## gravity. Returns whether that is within tol_km; when it is not (the shooting
## stalls, or Lambert has no arc to a moved aim), it keeps the best pass it flew
## and execute() refuses the burn rather than fly a silent miss.
const REFINE_PASSES := 8 # design value: from 12,000 km off, 7 corrections reach a few m


func refine(plan: Dictionary, tol_km := 0.05) -> bool:
	if not plan.has("node") or not plan.has("arrive"):
		return true
	if plan.get("kind", "") == "planet":
		refine_planet(plan)
		return true
	if plan.get("kind", "") == "arrive":
		# Aimed in the B-plane, as if the Moon did not pull: the correction near it re-aims under its pull.
		gravity.use_moons = false
		var ok_ := _refine_to(plan, tol_km)
		gravity.use_moons = true
		return ok_
	if plan.get("kind", "") in ["point", "turns"]:
		var est := V.norm(plan.dv_vec)
		var sh := _shoot(plan.id, V.add(by_id[plan.id].v, plan.dv_vec), plan.node, float(plan.arrive) - t)
		plan.dv_vec = V.sub(sh[0], by_id[plan.id].v)
		plan.dv = V.norm(plan.dv_vec)
		plan.miss_km = sh[1]
		plan.ok = plan.dv <= delta_v(plan.id)
		# Over a few turns the shooting can settle on another, far dearer path
		# than the one planned (near a half-turn the arcs crowd together): not
		# the move the player was shown, so it is refused.
		if plan.get("kind", "") == "turns" and plan.dv > 2.0 * est + 0.005:
			plan.ok = false
			plan.why = "no path at this time near the planned cost (%.1f m/s, not %.1f)" % [plan.dv * 1000.0, est * 1000.0]
			return false
		return float(sh[1]) < 1.0 and plan.ok
	return _refine_to(plan, tol_km)


func _refine_to(plan: Dictionary, tol_km: float) -> bool:
	var s: Dictionary = by_id[plan.id]
	var tof := float(plan.arrive) - t
	if tof <= 0.0:
		return true
	var node: PackedFloat64Array = plan.node
	var aim := node
	var v1 := V.add(s.v, plan.dv_vec)
	var best_v := v1
	var best := INF
	for i in REFINE_PASSES:
		var st := gravity.coast(s.r, v1, t, tof, 60.0)
		var miss := V.sub(st[0], node)
		if V.norm(miss) < best:
			best = V.norm(miss)
			best_v = v1
			plan.v2 = st[1]
		if best < tol_km or i == REFINE_PASSES - 1:
			break
		aim = V.sub(aim, miss)
		var sol := Lambert.solve(s.r, aim, tof, mu, true, V.cross(s.r, s.v))
		if sol.is_empty():
			break
		v1 = sol[0]
	plan.dv_vec = V.sub(best_v, s.v)
	plan.dv = V.norm(plan.dv_vec)
	plan.miss_km = best
	return best < tol_km


## Flights between planets (core/transfer.gd). Off unless the campaign says
## "interplanetary": true (or the game is started with --interplanetary): the
## shadowing scenario plays inside Jupiter's system as before.
var interplanetary := false


## The central body's state in the ephemeris's frame (centred on Jupiter, the
## game's axes) at sim time at: zero for Jupiter's world. A world about another
## body adds it to a ship's state to place the ship among the planets, and
## takes it off a planet's to bring the planet into the world's frame.
func central_state(at := NAN) -> Array:
	if central == "jupiter":
		return [V.of(0, 0, 0), V.of(0, 0, 0)]
	return Ephem.state(central, utc_ms(at))


## A ship's state in the ephemeris's frame (see central_state).
func eph_state(id: String) -> Array:
	var s: Dictionary = by_id[id]
	if central == "jupiter":
		return [s.r, s.v]
	var C := central_state()
	return [V.add(s.r, C[0]), V.add(s.v, C[1])]


## A body's position (from the ephemeris's frame) in the world's frame at sim time at.
func to_world(p: PackedFloat64Array, at := NAN) -> PackedFloat64Array:
	return p if central == "jupiter" else V.sub(p, central_state(at)[0])


func to_world_v(v: PackedFloat64Array, at := NAN) -> PackedFloat64Array:
	return v if central == "jupiter" else V.sub(v, central_state(at)[1])


## Which body's pull a ship is under now: "jupiter", a planet, or "sun".
func home_of(id: String) -> String:
	return Transfer.home(eph_state(id)[0], utc_ms())


## A ship's state relative to a body (game frame axes).
func rel_state(id: String, body: String, at := NAN) -> Array:
	var s := eph_state(id)
	var P := Ephem.state(body, utc_ms(at))
	return [V.sub(s[0], P[0]), V.sub(s[1], P[1])]


## Plan a flight to a planet arriving tof seconds from now (patched conics,
## refined under full gravity when flown), to stay in the orbit arr asks for
## (Arrival.radii): flown, it sets the correction near the planet and the
## burn into that orbit at its low point (_approach, _capture).
func plan_planet(id: String, body: String, tof: float, arr := {}) -> Dictionary:
	var from := home_of(id)
	if from == body:
		return {"ok": false, "why": "already there"}
	if from == "sun":
		return _course_correction(id, body, tof, arr)
	var rv := rel_state(id, from)
	var tr := Transfer.patched(rv[0], rv[1], from, body, utc_ms(), tof, arr)
	if tr.is_empty():
		return {"ok": false, "why": "no transfer"}
	var s: Dictionary = by_id[id]
	var dv_vec := V.sub(V.add(tr.v1, Ephem.state(from, utc_ms())[1]), eph_state(id)[1])
	var dv := V.norm(dv_vec)
	var ok := dv <= delta_v(id)
	return {"ok": ok, "why": "" if ok else "not enough fuel", "id": id, "target": "planet:" + body, "kind": "planet", "body": body, "from": from,
		"dv_vec": dv_vec, "dv": dv, "arrive": t + tof, "node": to_world(V.add(Ephem.pos(body, utc_ms(t + tof)), tr.aim_off), t + tof), "sigma": 0.0,
		"vinf": tr.vinf, "R1": tr.R1, "V1": tr.V1, "R2": tr.R2, "capture": tr.capture, "total": tr.total, "v2": to_world_v(V.add(tr.vinf_arr, Ephem.state(body, utc_ms(t + tof))[1]), t + tof),
		"arr": arr, "vinf_arr": tr.vinf_arr, "tilt": tr.tilt}


## One cell of the planner's chart for a planet: wait dep seconds (coasting on
## the two-body orbit about where the ship is), then fly tof. Patched conics
## only, no refining: cheap enough for a grid. {} when no transfer.
## Leaving a planet, the escape hyperbola must lie in the plane of the ship's
## position and v∞ (Transfer.departure), so where in its orbit the ship burns
## matters: from low orbit a burn at the wrong point turns the plane too and
## can cost twice as much. As missions do, it burns at the best of PHASES
## points round the orbit that begins at dep; "dep" in the cell is that
## burn's wait, s.
const PHASES := 12


func planet_cell(id: String, body: String, dep: float, tof: float, arr := {}) -> Dictionary:
	var from := home_of(id)
	if from == body:
		return {}
	var rv := rel_state(id, from)
	if from != "sun":
		var mu_f := Ephem.gm(from)
		var en := V.dot(rv[1], rv[1]) / 2.0 - mu_f / V.norm(rv[0])
		var period := TAU * sqrt(pow(-mu_f / (2.0 * en), 3.0) / mu_f) if en < 0.0 else 0.0
		var best := {}
		for k in (PHASES if period > 0.0 and period < tof / 4.0 else 1):
			var w := dep + period * k / PHASES
			var st := Kepler.propagate(rv[0], rv[1], w, mu_f)
			var tr := Transfer.patched(st[0], st[1], from, body, utc_ms(t + w), tof, arr)
			if tr.is_empty() or (not best.is_empty() and float(tr.dv) >= float(best.dv)):
				continue
			best = {"dv": tr.dv, "capture": tr.capture, "total": tr.total, "dep": w, "tilt": tr.tilt, "node": to_world(V.add(Ephem.pos(body, utc_ms(t + w + tof)), tr.aim_off), t + w + tof)}
		return best
	var st := Kepler.propagate(rv[0], rv[1], dep, Ephem.gm(from))
	# Deep space: straight to it, a Lambert arc about the Sun (rel_state was heliocentric).
	var ms1 := utc_ms(t + dep + tof)
	var sun1 := Ephem.state("sun", ms1)
	var P1 := Ephem.state(body, ms1)
	var sol := Lambert.solve(st[0], V.sub(P1[0], sun1[0]), tof, Ephem.GM_SUN)
	if sol.is_empty():
		return {}
	var dv := V.dist(sol[0], st[1])
	var a := Transfer.arrive(body, V.sub(sol[1], V.sub(P1[1], sun1[1])), ms1, arr)
	return {"dv": dv, "capture": a.capture, "total": dv + float(a.capture), "dep": dep, "tilt": a.tilt, "node": to_world(P1[0], t + dep + tof)}


## In deep space, a course correction (what missions call a TCM): the burn
## that puts the ship on the Lambert arc about the Sun from where it is to the
## aim point, refined under full gravity like any other transfer.
func _course_correction(id: String, body: String, tof: float, arr := {}) -> Dictionary:
	var s := eph_state(id)
	var ms0 := utc_ms()
	var sun0 := Ephem.state("sun", ms0)
	var R1 := V.sub(s[0], sun0[0])
	var V1 := V.sub(s[1], sun0[1])
	var ms1 := utc_ms(t + tof)
	var sun1 := Ephem.state("sun", ms1)
	var P1 := Ephem.state(body, ms1)
	var sol := Lambert.solve(R1, V.sub(P1[0], sun1[0]), tof, Ephem.GM_SUN)
	if sol.is_empty():
		return {"ok": false, "why": "no transfer"}
	var vinf2 := V.sub(sol[1], V.sub(P1[1], sun1[1]))
	var a := Transfer.arrive(body, vinf2, ms1, arr)
	var off: PackedFloat64Array = a.aim
	sol = Lambert.solve(R1, V.add(V.sub(P1[0], sun1[0]), off), tof, Ephem.GM_SUN)
	if sol.is_empty():
		return {"ok": false, "why": "no transfer"}
	var dv_vec := V.sub(sol[0], V1)
	var dv := V.norm(dv_vec)
	var capture := float(a.capture)
	var plan := {"ok": dv <= delta_v(id), "why": "" if dv <= delta_v(id) else "not enough fuel", "id": id, "target": "planet:" + body, "kind": "planet", "body": body, "from": "sun",
		"dv_vec": dv_vec, "dv": dv, "arrive": t + tof, "node": to_world(V.add(P1[0], off), t + tof), "sigma": 0.0, "vinf": dv_vec, "R1": R1, "V1": V1,
		"R2": V.add(V.sub(P1[0], sun1[0]), off), "capture": capture, "total": dv + capture, "v2": to_world_v(V.add(vinf2, P1[1]), t + tof), "tcm": true,
		"arr": arr, "vinf_arr": vinf2, "tilt": a.tilt}
	return plan # its "v∞" is the burn itself, about the ship's own velocity


## Fly the trial under full gravity and correct v∞ by Newton's method until
## the ship arrives within a tenth of the target's sphere of influence of the
## aim point. The Jacobian (arrival per km/s of v∞) is the two-body arc's
## about the Sun, by finite differences: cheap, and close enough that each pass
## cuts the miss many times over; the full-gravity flight supplies the miss.
func refine_planet(plan: Dictionary) -> void:
	var s: Dictionary = by_id[plan.id]
	var tof := float(plan.arrive) - t
	var from: String = plan.from
	var rv := rel_state(plan.id, from if from != "sun" else "jupiter")
	var Pv: PackedFloat64Array = to_world_v(Ephem.state(from if from != "sun" else "jupiter", utc_ms())[1])
	var vinf: PackedFloat64Array = plan.vinf
	var v1 := V.add(s.v, plan.dv_vec)
	var tol := 0.1 * Ephem.soi(String(plan.body))
	var J := Transfer.jacobian(plan.R1, plan.V1, vinf, tof)
	var last := PackedFloat64Array()
	var dx := PackedFloat64Array()
	for i in Transfer.PASSES:
		var st := gravity.coast(s.r, v1, t, tof, 60.0)
		var miss := V.sub(st[0], plan.node)
		plan.v2 = st[1]
		plan.miss_km = V.norm(miss)
		if V.norm(miss) < tol:
			break
		if not last.is_empty():
			J = Transfer.broyden(J, dx, V.sub(miss, last))
		last = miss
		var step := Transfer.solve3(J, miss)
		if step.is_empty():
			break
		dx = V.scale(step, -1.0)
		vinf = V.add(vinf, dx)
		if from == "sun":
			v1 = V.add(s.v, vinf)
			continue
		var cands := Transfer.departure(rv[0], vinf, Ephem.gm(from))
		if cands.is_empty():
			break
		var best: PackedFloat64Array = cands[0]
		for c in cands:
			if V.dist(c, rv[1]) < V.dist(best, rv[1]):
				best = c
		v1 = V.add(best, Pv)
	plan.dv_vec = V.sub(v1, s.v)
	plan.dv = V.norm(plan.dv_vec)
	plan.vinf = vinf


## Settle into a circular orbit about whatever the ship is near, at its present
## distance, turning the way it is already going.
func plan_orbit(id: String) -> Dictionary:
	var body := home_of(id)
	if body == "sun":
		return {"ok": false, "why": "no planet near"}
	var rv := rel_state(id, body)
	var rn := V.norm(rv[0])
	var hz := V.cross(rv[0], rv[1])
	if V.norm(hz) < 1e-9:
		hz = V.of(0, 0, 1)
	var tdir := V.cross(hz, rv[0])
	tdir = V.scale(tdir, 1.0 / V.norm(tdir))
	var vc := V.scale(tdir, sqrt(Ephem.gm(body) / rn))
	var dv_vec := V.sub(vc, rv[1])
	var dv := V.norm(dv_vec)
	var ok := dv <= delta_v(id)
	return {"ok": ok, "why": "" if ok else "not enough fuel", "id": id, "target": "orbit:" + body, "dv_vec": dv_vec, "dv": dv, "arrive": t, "node": by_id[id].r, "kind": "orbit"}


## Burn: change velocity now and pay for it by the rocket equation; the drive
## glows for the length of the burn (thrust-limited), and at least 5 min.
## The random stream of one subsystem: setup, sensing, effects, breakup, red,
## traffic. Its seed is the first 60 bits of SHA-256 (FIPS 180-4) of
## "xgeo/<master seed>/<run>/<name>": streams of one run, and the runs of one
## seed, start far apart, and a new stream never moves the others. (A hash
## rather than SplitMix64: GDScript has no unsigned 64-bit arithmetic.)
func stream(name: String) -> RandomNumberGenerator:
	if not streams.has(name):
		var g := RandomNumberGenerator.new()
		g.seed = stream_seed(master_seed, run, name)
		streams[name] = g
	return streams[name]


static func stream_seed(master: int, run_: int, name: String) -> int:
	return ("xgeo/%d/%d/%s" % [master, run_, name]).sha256_text().substr(0, 15).hex_to_int()


## Every stream's position, for a save.
func stream_states() -> Dictionary:
	var out := {}
	for k in streams:
		out[k] = streams[k].state
	return out


## Put the streams back as saved. A save from before the streams (one shared
## generator, its state an int) restarts them from the seed: the world is the
## one saved, only its later chance draws differ.
func restore_streams(state: Dictionary) -> void:
	master_seed = int(state.get("seed", master_seed))
	run = int(state.get("run", run))
	streams.clear()
	var saved = state.get("rng", {})
	if saved is Dictionary:
		for k in saved:
			stream(k).state = int(saved[k])


func burn(id: String, dv_vec: PackedFloat64Array) -> bool:
	var s: Dictionary = by_id[id]
	var dv := V.norm(dv_vec)
	if not s.alive or not s.cls.has("engine") or dv > delta_v(id) + 1e-9:
		return false
	var ve: float = s.cls.engine.ve
	var used := (float(s.dry) + float(s.prop)) * (1.0 - exp(-dv / ve))
	var seconds := used * 1000.0 * ve * 1000.0 / float(s.cls.engine.thrust)
	s.prop = float(s.prop) - used
	s.v = V.add(s.v, dv_vec)
	s.flash_until = t + maxf(seconds, 300.0)
	s.burn_seconds = seconds
	s.burn_dir = V.scale(dv_vec, 1.0 / maxf(dv, 1e-12))
	# The truth, for tests (sensing never reads it): burns at one moment add up.
	s.burn_dv_vec = V.add(s.burn_dv_vec, dv_vec) if float(s.get("burn_at", -1.0)) == t and s.has("burn_dv_vec") else dv_vec
	s.burn_at = t
	s.burns = int(s.get("burns", 0)) + 1
	return true


func execute(plan: Dictionary) -> bool:
	if not plan.get("ok", false):
		return false
	if plan.get("kind", "") != "orbit" and not refine(plan):
		if String(plan.get("why", "")) == "":
			plan.why = "no transfer under full gravity (%s km off)" % String.num(float(plan.get("miss_km", 0.0)), 1)
		plan.ok = false
		return false
	var ok := burn(plan.id, plan.dv_vec)
	if ok and plan.has("goal"):
		scheduled.append({"at": float(plan.arrive), "id": plan.id, "target": plan.target, "insert": true, "goal": plan.goal})
	if ok and plan.has("arr"):
		# Near the body, re-aim at the low point (Arrival): a while before
		# arriving, inside its pull (half its sphere of influence out).
		var body: String = plan.body
		var tof := float(plan.arrive) - t
		var lead := 8.0 * 3600.0
		if body != "moon":
			lead = 0.5 * Ephem.soi(body) / maxf(V.norm(plan.get("vinf_arr", V.of(0, 0, 0))), 0.5)
		lead = minf(lead, 0.3 * tof)
		scheduled.append({"at": float(plan.arrive) - lead, "id": plan.id, "target": plan.target, "approach": true, "body": body, "arr": plan.arr})
	if ok and by_id[plan.id].side == "blue":
		by_id[plan.id].plan_arrive = plan.arrive
		by_id[plan.id].plan_target = plan.target
		by_id[plan.id].plan_node = plan.node
		by_id[plan.id].plan_sigma = plan.get("sigma", 0.0)
		say("burn", Lang.f("burn", [by_id[plan.id].short, plan.dv]), "info")
	return ok


func burning(id: String) -> bool:
	return float(by_id[id].get("flash_until", -1.0)) > t


func blue_ships() -> Array:
	return ships.filter(func(s): return s.side == "blue" and s.alive)


func red_ships() -> Array:
	return ships.filter(func(s): return s.side == "red")


func day() -> int:
	return int(t / DAY) + 1


## Release a listening buoy from a warship, where it is and moving as it moves.
func drop_buoy(from_id: String) -> String:
	var s: Dictionary = by_id[from_id]
	# A scenario without the buoy's class (TEST RANGE: game.json alone) has none to drop.
	if int(s.get("buoys", 1 if s.kind == "warship" else 0)) <= 0 or not s.alive or not data.classes.has("wren"):
		return ""
	s.buoys = int(s.get("buoys", 1)) - 1
	var n := 1
	while by_id.has("b%d" % n):
		n += 1
	# Out of the back, clear of the hull: a hull's length and a half behind the
	# ship along its track, pushed off backward at 1 m/s, as spring deployers
	# eject small satellites (design value, in the 1–2 m/s of CubeSat
	# dispensers: Cal Poly CubeSat Design Specification rev. 14, 2022).
	var aft := V.scale(s.v, -1.0 / maxf(V.norm(s.v), 1e-9))
	var r0 := V.add(s.r, V.scale(aft, 1.5 * float(s.cls.get("length", 20.0)) / 1000.0))
	var v0 := V.add(s.v, V.scale(aft, 0.001))
	var b := {"id": "b%d" % n, "classId": "wren", "name": "WREN-%d ES BUOY" % n, "short": "WREN-%d" % n, "side": "blue", "kind": "buoy", "role": "PASSIVE ES · DIRECTION FINDING", "registry": "USA %d" % (660 + n), "operator": "U.S. SPACE CORPS · SPACE DELTA 7 (ISR)", "flag": "UNITED STATES", "status": "LISTENING",
		"r0": [r0[0], r0[1], 0.0], "v0": [v0[0], v0[1], 0.0], "t0": t}
	_add(b)
	say("buoy", ("%s dropped WREN-%d: another ear." if not Lang.doctrinal else "%s deployed WREN-%d (ES).") % [s.short, n], "good")
	return b.id


## Where Red's handler sits: the outpost near Callisto; about another body,
## the ground station the scenario names (camp.handler.ground), else that
## body's centre (for pointing a dish).
func handler_pos(at := NAN) -> PackedFloat64Array:
	var hd: Dictionary = camp.get("handler", {})
	if hd.has("ground"):
		return ground_state(hd.ground, at)[0]
	if moon("callisto").is_empty():
		return V.of(0, 0, 0)
	return moon_state("callisto", t if is_nan(at) else at)[0]


## Where a planet, Jupiter or "sun" is in the world's frame (km), at sim time at.
func body_pos(id: String, at := NAN) -> PackedFloat64Array:
	var ms := utc_ms(at)
	return V.sub(Ephem.pos(id, ms), Ephem.pos(central, ms))


## The central body's equatorial and polar radii (km): the world's own (a
## scenario's central block), else the ephemeris's for a planet.
func central_radius() -> float:
	return float(data.jupiter.radius) if central == "jupiter" or String(data.jupiter.get("id", "")) == central else float(Ephem.BODY[central].re)


func central_polar() -> float:
	if String(data.jupiter.get("id", "")) == central and data.jupiter.has("polarRadius"):
		return float(data.jupiter.polarRadius)
	return float(Ephem.BODY[central].rp)


## The Sun about the central body (km), at sim time at.
func sun_pos(at := NAN) -> PackedFloat64Array:
	return Ephem.pos("sun", utc_ms(at)) if central == "jupiter" else body_pos("sun", at)


func utc_ms(at := NAN) -> float:
	return float(data.startUtc) + (t if is_nan(at) else at) * 1000.0


## Unit vectors toward the Sun (from the central body) and toward Earth (from Jupiter), in the game plane
## (JPL approximate planetary positions, core/ephem.gd). At 5 AU the direction
## barely changes across the system, so it serves for any ship.
func sun_dir(at := NAN) -> PackedFloat64Array:
	return _planar_unit(Ephem.sun(utc_ms(at)) if central == "jupiter" else body_pos("sun", at))


func earth_dir(at := NAN) -> PackedFloat64Array:
	return _planar_unit(Ephem.earth(utc_ms(at)))


static func _planar_unit(v: PackedFloat64Array) -> PackedFloat64Array:
	var n := sqrt(v[0] * v[0] + v[1] * v[1])
	return V.of(v[0] / n, v[1] / n)
