## Thermal forecast: how a ship's coming orbit drives what Red's telescopes can
## see of it, over about one revolution ahead (docs/REALISM-SOURCES.md §2).
##
## Each sample is the same worst-case look the game's heat gauge makes now
## (hud.gd _heat_state), moved to a future time:
## - Our ship coasts under full gravity (Gravity.coast, the sim's own model,
##   in steps of at most 300 s, as Sim.predict_state). A burn changes the orbit,
##   so the forecast is redone as soon as the ship's state leaves its path.
## - Each Red or unknown track that may carry a telescope
##   (Sensing.eye_class: assume the worst for an unclassified one) is
##   carried ahead from Blue's estimate, never the truth, on a two-body Kepler
##   coast (Track.coast; Kepler.propagate). Over hours in low orbit the moons
##   move it by kilometres, nothing next to the ranges that matter here
##   (a simplification, for speed). Everyone is assumed to coast.
## - The share of the Sun the ship will see is Thermal.sunlight at the future
##   point and time (oblate Jupiter, the moons, a limb-darkened disc), and the
##   skin temperature is integrated sample to sample with Thermal.skin_step
##   (lumped capacitance, Gilmore 2002; Gaite & Fernández-Rico 2012). HYDRA's skin answers over about a day
##   (C/4εσAT³), so a two-hour shadow cools it by only a few kelvin: what the
##   forecast mostly shows is geometry (range to each telescope, Jupiter in
##   the line of sight), and it says so.
## - The look is Sensing.ir_look on a shallow copy of the ship with r, the
##   skin temperature and the sunlight share set for that time. It handles
##   Jupiter blocking the line of sight and Jupiter's bright disc behind the
##   target. The radiators keep their present load; if the ship is dark, the
##   sink runs out when Thermal.dark_left says and the full waste heat returns.
## - Verdicts as the HUD's: COLD while Pd = Φ(S/N − 5) ≤ 2 % a look, SEEN at
##   S/N 5 (NEO Surveyor's threshold, Mainzer et al. 2023), WARM between.
##
## The ghost streak (a game layer over the same verdict): how long a Blue ship
## has stayed COLD without a break, by sim time, with ranks at design values.
class_name Forecast
extends RefCounted

const HEAT_PD := 0.02 # as HUD.HEAT_PD: a look's Pd at or under which we call the ship hidden
const MIN_H := 3.0 * 3600.0 # s, the shortest horizon
const MAX_H := 24.0 * 3600.0 # s, the longest
const SAMPLES := 84
const REAL_REFRESH := 2.0 # s of real time between recomputes at most
## New coast steps get_for flies per call: a fresh path (on opening, or after
## a burn) fills in over a few frames instead of stalling one. Sized for about
## 7 ms a call on a desktop, half the 15 ms forecast_test allows, so a slower
## machine (the CI runner) stays inside it too.
const BUDGET := 12
## Ghost streak ranks: [hours COLD without a break, name]. Design values.
const RANKS := [[1.0, "QUIET"], [6.0, "DARK"], [24.0, "BLACK"], [72.0, "GHOST"]]
## A broken streak this long (s) or more is reported in the event log (design value).
const REPORT_BREAK := 3600.0

var last: Dictionary = {}
var cache := {} # reused between computes: the ship's coast and each track's, by grid time
var _key := ""
var _real := -1e9
var compute_ms := 0.0


## The cached forecast for a ship: recomputed when sim time has moved on by a
## sample step, every REAL_REFRESH s of real time, when the ship's state has
## left the forecast path (a burn), or for another ship. Each recompute reuses
## the coasts already flown (cache), so only the new tail is integrated.
func get_for(sim: Sim, ship_id: String) -> Dictionary:
	var now := Time.get_ticks_msec() / 1000.0
	var stale := last.is_empty() or _key != ship_id or now - _real >= REAL_REFRESH
	if not stale:
		stale = last.get("partial", false) or sim.t - float(last.t0) >= float(last.step) or sim.t < float(last.t0)
	if not stale and sim.by_id.has(ship_id):
		# Off the path: a burn since, or a jump in time.
		var p := position_at(last, sim.t)
		stale = p.is_empty() or V.dist(p, sim.by_id[ship_id].r) > 50.0
	if stale:
		if _key != ship_id:
			cache = {}
		var t0 := Time.get_ticks_usec()
		last = compute(sim, ship_id, -1.0, SAMPLES, cache, BUDGET)
		compute_ms = (Time.get_ticks_usec() - t0) / 1000.0
		last.ms = compute_ms
		_key = ship_id
		_real = now
	return last


## The ship's place on the forecast path at time at (linear between samples).
static func position_at(f: Dictionary, at: float) -> PackedFloat64Array:
	var S: Array = f.get("samples", [])
	if S.size() < 3 or at < float(S[0].t) or at > float(S.back().t):
		return PackedFloat64Array()
	var i := 0 if at < float(S[1].t) else clampi(1 + int((at - float(S[1].t)) / float(f.step)), 1, S.size() - 2)
	var u := clampf((at - float(S[i].t)) / maxf(float(S[i + 1].t) - float(S[i].t), 1e-9), 0.0, 1.0)
	var a: PackedFloat64Array = S[i].r
	var b: PackedFloat64Array = S[i + 1].r
	return V.add(a, V.scale(V.sub(b, a), u))


## About one revolution of the ship about Jupiter (2π√(a³/μ), a from its
## orbital energy), clamped to 3–24 h; 24 h when it is not bound.
static func horizon(sim: Sim, s: Dictionary) -> float:
	var r := V.norm(s.r)
	var E := V.dot(s.v, s.v) / 2.0 - sim.mu / r
	if E >= 0.0:
		return MAX_H
	var a := -sim.mu / (2.0 * E)
	return clampf(TAU * sqrt(a * a * a / sim.mu), MIN_H, MAX_H)


## S/N at or under which a look's Pd is HEAT_PD: Pd = Φ(S/N − k) (Sensing.pd).
static func cold_snr(sim: Sim) -> float:
	return float(sim.data.cfg.ir.band.threshold) - RF.q_inv(HEAT_PD)


static func level_of(sim: Sim, snr: float, eyes: int) -> String:
	if eyes == 0:
		return "none"
	if snr >= float(sim.data.cfg.ir.band.threshold):
		return "seen"
	if sim.sensing.pd(snr) > HEAT_PD:
		return "warm"
	return "cold"


## The telescopes to fear: [{label, cls, x (Blue's state estimate), t, r_now}].
static func eyes(sim: Sim) -> Array:
	var out := []
	for id in sim.tracks:
		var tr: Track = sim.tracks[id]
		if tr.side == "neutral" or not sim.by_id.has(id) or not sim.by_id[id].alive:
			continue
		var cid := Sensing.eye_class(sim, tr)
		if cid == "":
			continue
		var cls: Dictionary = sim.data.classes[cid]
		if not cls.has("ir"):
			continue
		out.append({"id": id, "label": tr.label, "cls": cls, "nei": float(cls.ir.get("neiBand", cls.ir.nei)), "x": tr.x, "t": tr.t, "r_now": tr.pos()})
	return out


## The forecast for ship_id over horizon_s (default: horizon()) in n steps.
## Returns {t0, step, horizon, k, k_cold, eyes, samples, now, peak, shadow,
## cold, next_change, burn_best, rad, sink, dark} where each sample is
## {t, r, sun, T_skin, snr, pd, level, who, R, behind, snr_dark, snr_lit, snr_burn}.
static func compute(sim: Sim, ship_id: String, horizon_s := -1.0, n := SAMPLES, memo := {}, budget := -1) -> Dictionary:
	var s: Dictionary = sim.by_id.get(ship_id, {})
	if s.is_empty() or not s.has("r") or not s.cls.has("sig"):
		return {}
	var H := horizon_s if horizon_s > 0.0 else horizon(sim, s)
	var dt := maxf(60.0, snappedf(H / n, 60.0))
	# The budget is in samples of 300 s steps. Close to Jupiter the coast takes
	# shorter steps (Gravity.ETA_NEAR), so a sample costs more and fewer fit a call.
	if budget > 0:
		var rn := V.norm(s.r)
		var per := ceilf(dt / minf(300.0, Gravity.ETA_NEAR * sqrt(rn * rn * rn / sim.mu)))
		budget = maxi(1, roundi(budget * ceilf(dt / 300.0) / per))
	if float(memo.get("dt", -1.0)) != dt:
		memo.clear()
		memo.dt = dt
	if not memo.has("path"):
		memo.path = {} # grid t -> [r, v, sunlight share]
		memo.tracks = {} # "id@t" -> {grid t -> position}
	var k := float(sim.data.cfg.ir.band.threshold)
	var EY := eyes(sim)
	var th: Dictionary = s.cls.get("thermal", {})
	var h0: Dictionary = s.get("heat", {})
	var rad: bool = th.has("radiator") and Thermal.waste(s.cls) > 0.0
	var dark: bool = h0.get("dark", false)
	var T_full := Thermal.radiator_T(th.radiator, Thermal.waste(s.cls)) if rad else 0.0
	var edge_full := float(Thermal.radiator_I(th.radiator, T_full, PI / 2.0).edge) if rad else 0.0
	var eng := Thermal.grey_band(s.cls.engine.hot) if s.cls.has("engine") else 0.0
	var dark_end := sim.t + sim.thermal.dark_left(s) if dark else -1.0
	var Sf := Thermal.sun_flux(sim.data)
	var C := Thermal.heat_capacity(s)
	var T := sim.thermal.skin_now(s)
	var flash := float(s.get("flash_until", -1.0))
	var RJ := sim.central_radius()
	var disc := float(sim.data.cfg.ir.band.discFactor)
	var glare := float(sim.data.cfg.ir.band.glareFactor)
	var cone := float(sim.data.cfg.ir.glareCone)
	# Which coasts of the tracks can be reused: a track updated since is flown afresh.
	var tk := {}
	for e in EY:
		var key := "%s@%.3f" % [e.id, float(e.t)]
		if not memo.tracks.has(key):
			memo.tracks[key] = {}
		tk[e.id] = memo.tracks[key]
	for key in memo.tracks.keys():
		if not tk.values().has(memo.tracks[key]):
			memo.tracks.erase(key)
	var path: Dictionary = memo.path
	var g0 := (floorf(sim.t / dt) + 1.0) * dt
	var times := [sim.t]
	for j in n:
		times.append(g0 + j * dt)
	# The ship's coast: from now to the first grid point, then along the grid.
	# The cached path stands only while the ship is still on it (no burn since).
	var st := sim.gravity.coast(s.r, s.v, sim.t, g0 - sim.t, 300.0)
	if not path.has(g0) or V.dist(path[g0][0], st[0]) > 1.0:
		path.clear()
	for key in path.keys():
		if float(key) < g0:
			path.erase(key)
	var samples := []
	var f_prev := -1.0
	var partial := false
	var ahead := {}
	for i in times.size():
		var at: float = times[i]
		if i > 1 and budget >= 0 and not path.has(at):
			if budget == 0:
				partial = true # the rest next time (get_for spreads a fresh coast over frames)
				break
			budget -= 1
		var r: PackedFloat64Array
		var f: float
		if i == 0:
			r = s.r
			f = sim.thermal.sunlight(r, at)
		else:
			if not path.has(at):
				if i > 1:
					if not ahead.has(at):
						# One integration over the run of grid points still to fill.
						var want := []
						for j in range(i, times.size() if budget < 0 else mini(times.size(), i + budget + 1)):
							if path.has(times[j]):
								break
							want.append(times[j])
						var got := sim.gravity.coast_to(st[0], st[1], float(times[i - 1]), want)
						for j in want.size():
							ahead[want[j]] = got[j]
					st = ahead[at]
				path[at] = [st[0], st[1], sim.thermal.sunlight(st[0], at)]
			else:
				st = [path[at][0], path[at][1]]
			r = path[at][0]
			f = float(path[at][2])
			T = Thermal.skin_step(s.cls.sig, Sf, (f + f_prev) / 2.0, C, T, at - float(times[i - 1]))
		f_prev = f
		var x := s.duplicate()
		x.r = r
		var hh: Dictionary = h0.duplicate()
		hh.T_skin = T
		hh.sun = f
		if dark and at > dark_end and rad:
			hh.T_rad = T_full
			hh.Q = Thermal.waste(s.cls)
		x.heat = hh
		if i > 0 and at > flash:
			x.flash_until = -1e9
		var smp := {"t": at, "r": r, "sun": f, "T_skin": T, "snr": 0.0, "who": "", "R": 0.0, "behind": 0, "snr_dark": 0.0, "snr_lit": 0.0, "snr_burn": 0.0}
		# Sensing.ir_look's sum, SNR = I/R²/(NEI·bg), occultation and Jupiter's
		# bright disc included, with the ship's in-band intensity worked once for
		# every telescope (Thermal.intensity does not depend on where they are:
		# all observers are in the plane, radiators edge-on).
		var terms: Dictionary = sim.thermal.intensity(x, r, sim.sensing.lit(x))
		var base := float(terms.skin) + float(terms.engine)
		for e in EY:
			var op: PackedFloat64Array = e.r_now if i == 0 else _track_pos(e, at, tk[e.id])
			var bg := _sky(op, r, RJ, disc, glare, cone)
			if bg <= 0.0:
				smp.behind += 1
				continue
			var R := V.dist(op, r) * 1000.0
			var nei := float(e.nei) * bg
			var per := 1.0 / (R * R) / nei # S/N per W/sr
			var snr := float(terms.total) * per
			smp.snr_dark = maxf(smp.snr_dark, per * base)
			smp.snr_lit = maxf(smp.snr_lit, per * (base + edge_full))
			smp.snr_burn = maxf(smp.snr_burn, per * (float(terms.skin) + float(terms.edge) + float(terms.face) + eng))
			if snr >= smp.snr:
				smp.snr = snr
				smp.who = e.label
				smp.R = R / 1000.0
		smp.pd = sim.sensing.pd(smp.snr)
		smp.level = level_of(sim, smp.snr, EY.size())
		samples.append(smp)
	var out := {"id": ship_id, "t0": sim.t, "step": dt, "horizon": float(times.back()) - sim.t, "partial": partial, "full_t": float(times.back()), "k": k, "k_cold": cold_snr(sim), "eyes": EY.size(), "samples": samples,
		"now": samples[0].level, "rad": rad, "sink": th.has("sink"), "dark": dark, "dark_left": sim.thermal.dark_left(s), "edge_full": edge_full}
	_derive(sim, out)
	return out


## Sensing.occulted and Sensing.background for a telescope at o looking at p,
## in plain floats (the forecast makes hundreds of these looks): 0 when
## Jupiter is in the line of sight, else the sky's brightness behind p as a
## multiple of the sensor's NEI (Jupiter's disc, the glare round it, or 1).
## forecast_test checks the sum against Sensing.ir_look.
static func _sky(o: PackedFloat64Array, p: PackedFloat64Array, RJ: float, disc: float, glare: float, cone: float) -> float:
	var dx := p[0] - o[0]
	var dy := p[1] - o[1]
	var dz := p[2] - o[2]
	var L2 := dx * dx + dy * dy + dz * dz
	var od := o[0] * dx + o[1] * dy + o[2] * dz
	var u := clampf(-od / L2, 0.0, 1.0)
	var cx := o[0] + u * dx
	var cy := o[1] + u * dy
	var cz := o[2] + u * dz
	if sqrt(cx * cx + cy * cy + cz * cz) < RJ:
		return 0.0
	var on := sqrt(o[0] * o[0] + o[1] * o[1] + o[2] * o[2])
	var ang := acos(clampf(-od / (on * sqrt(L2)), -1.0, 1.0))
	var jr := asin(minf(1.0, RJ / on))
	if ang < jr:
		return disc
	if ang < cone * jr:
		return glare
	return 1.0


## A track's estimated place at time at, coasting (memoised per grid time).
## Blue's estimate flown on its two-body ellipse by Kepler's equation
## (M = E − e sin E, Newton's method; Curtis 2020; as on JPL SSD's "Approximate
## Positions of the Planets" page), the same motion as
## Track.coast's universal-variable propagation, far cheaper in GDScript.
## Unbound or degenerate states fall back to Track.coast.
static func _track_pos(e: Dictionary, at: float, memo: Dictionary) -> PackedFloat64Array:
	if memo.has(at):
		return memo[at]
	if not e.has("el"):
		e.el = _elements(e.x)
	var el: Dictionary = e.el
	var dt := at - float(e.t)
	var out: PackedFloat64Array
	if el.is_empty():
		var x: PackedFloat64Array = Track.coast(e.x, dt)
		out = V.of(x[0], x[1], x[2]) if x.size() == 6 else V.of(x[0], x[1])
	else:
		var ec := float(el.e)
		var M := float(el.M0) + float(el.n) * dt
		var E := M + ec * sin(M)
		for k in 8:
			var d := (E - ec * sin(E) - M) / (1.0 - ec * cos(E))
			E -= d
			if absf(d) < 1e-12:
				break
		var nu := 2.0 * atan2(sqrt(1.0 + ec) * sin(E / 2.0), sqrt(1.0 - ec) * cos(E / 2.0))
		var rr := float(el.a) * (1.0 - ec * cos(E))
		var ang := float(el.w) + float(el.dir) * nu
		out = V.of(rr * cos(ang), rr * sin(ang))
	memo[at] = out
	return out


## Planar Kepler elements of a track state [x, y, vx, vy] about the world's
## centre (Track.mu(): Jupiter's in the campaign): {a, e, w, M0, n, dir}; {} if not a bound ellipse.
static func _elements(x: PackedFloat64Array) -> Dictionary:
	if x.size() != 4:
		return {} # a 3-D track ([x, y, z, vx, vy, vz]) coasts by Track.coast
	var mu := Track.mu()
	var r := sqrt(x[0] * x[0] + x[1] * x[1])
	var v2 := x[2] * x[2] + x[3] * x[3]
	var E := v2 / 2.0 - mu / r
	var h := x[0] * x[3] - x[1] * x[2]
	if E >= 0.0 or absf(h) < 1e-6:
		return {}
	var a := -mu / (2.0 * E)
	var ex := x[3] * h / mu - x[0] / r
	var ey := -x[2] * h / mu - x[1] / r
	var ec := sqrt(ex * ex + ey * ey)
	if ec >= 0.99:
		return {}
	var dir := 1.0 if h > 0.0 else -1.0
	var w := atan2(ey, ex) if ec > 1e-10 else atan2(x[1], x[0])
	var nu0 := dir * (atan2(x[1], x[0]) - w)
	var E0 := 2.0 * atan2(sqrt(1.0 - ec) * sin(nu0 / 2.0), sqrt(1.0 + ec) * cos(nu0 / 2.0))
	return {"a": a, "e": ec, "w": w, "M0": E0 - ec * sin(E0), "n": sqrt(mu / (a * a * a)), "dir": dir}


## When the ship crosses c in S/N between samples a and b (log-linear).
static func _cross_t(a: Dictionary, b: Dictionary, key: String, c: float) -> float:
	var la := log(maxf(float(a[key]), 1e-4))
	var lb := log(maxf(float(b[key]), 1e-4))
	var lc := log(maxf(c, 1e-4))
	var u := 0.5 if absf(lb - la) < 1e-9 else clampf((lc - la) / (lb - la), 0.0, 1.0)
	return lerpf(float(a.t), float(b.t), u)


## Between samples a and b, when the level changes (interpolated on S/N
## against the boundary it crosses).
static func _edge_t(f: Dictionary, a: Dictionary, b: Dictionary) -> float:
	var hi := {"cold": 0, "warm": 1, "seen": 2, "none": 0}
	var la: int = hi.get(a.level, 0)
	var lb: int = hi.get(b.level, 0)
	var c := float(f.k_cold) if mini(la, lb) == 0 else float(f.k)
	return _cross_t(a, b, "snr", c)


static func _derive(sim: Sim, f: Dictionary) -> void:
	var S: Array = f.samples
	# Shadow: crossings of half the Sun.
	var sh := {"now": float(S[0].sun) < 0.5, "enter": -1.0, "exit": -1.0}
	for i in range(1, S.size()):
		var a: Dictionary = S[i - 1]
		var b: Dictionary = S[i]
		var fa := float(a.sun)
		var fb := float(b.sun)
		if (fa < 0.5) == (fb < 0.5):
			continue
		# The rim is crossed in well under a step in low orbit: bisect on the
		# chord between the samples for the moment the Sun's centre goes behind
		# Jupiter's limb (half the limb-darkened disc hidden, near enough: the
		# disc is far smaller than the planet seen from here). Tracing the whole
		# disc (Thermal.sunlight) at each probe would cost a hundred times more.
		var lo := 0.0
		var hi := 1.0
		var want_enter := fb < 0.5
		if (want_enter and sh.enter < 0.0) or (not want_enter and sh.exit < 0.0):
			var ms := sim.utc_ms(float(a.t))
			var sun := sim.sun_pos(float(a.t))
			for it in 10:
				var m := (lo + hi) / 2.0
				var rm := V.add(a.r, V.scale(V.sub(b.r, a.r), m))
				var d := V.sub(sun, rm)
				var hid := Thermal._ray_hits(rm, V.scale(d, 1.0 / V.norm(d)), sim.central_radius(), sim.central_polar())
				if hid == (fa < 0.5):
					lo = m
				else:
					hi = m
		var tc := lerpf(float(a.t), float(b.t), (lo + hi) / 2.0)
		if fb < 0.5:
			if sh.enter < 0.0:
				sh.enter = tc
		elif sh.exit < 0.0 and (sh.now or sh.enter >= 0.0):
			sh.exit = tc
	f.shadow = sh
	# Cold windows: runs of COLD, their ends interpolated.
	var cold := []
	var cur := {}
	for i in S.size():
		var c: bool = S[i].level == "cold"
		if c and cur.is_empty():
			cur = {"start": float(S[0].t) if i == 0 else _edge_t(f, S[i - 1], S[i]), "now": i == 0}
		elif not c and not cur.is_empty():
			cur.end = _edge_t(f, S[i - 1], S[i])
			cur.open = false
			cur.len = float(cur.end) - float(cur.start)
			cold.append(cur)
			cur = {}
	if not cur.is_empty():
		cur.end = float(S.back().t)
		cur.open = true
		cur.len = float(cur.end) - float(cur.start)
		cold.append(cur)
	f.cold = cold
	# The next change of verdict.
	f.next_change = {}
	for i in range(1, S.size()):
		if S[i].level != S[0].level:
			f.next_change = {"t": _edge_t(f, S[i - 1], S[i]), "level": S[i].level}
			break
	# The first time it will be SEEN.
	f.next_seen = -1.0
	for i in S.size():
		if S[i].level == "seen":
			f.next_seen = float(S[0].t) if i == 0 else _cross_t(S[i - 1], S[i], "snr", float(f.k))
			break
	# The brightest moment, and the best and worst moments to burn.
	var pk := 0
	var bb := 0
	for i in S.size():
		if float(S[i].snr) > float(S[pk].snr):
			pk = i
		if float(S[i].snr_burn) < float(S[bb].snr_burn):
			bb = i
	f.peak = {"t": S[pk].t, "snr": S[pk].snr, "who": S[pk].who, "i": pk}
	f.burn_now = level_of(sim, float(S[0].snr_burn), int(f.eyes))
	f.burn_best = {"t": S[bb].t, "snr": S[bb].snr_burn, "level": level_of(sim, float(S[bb].snr_burn), int(f.eyes)), "behind": int(S[bb].behind) >= int(f.eyes) and int(f.eyes) > 0, "shadow": float(S[bb].sun) < 0.5, "i": bb}
	var tmin := INF
	var tmax := -INF
	for smp in S:
		tmin = minf(tmin, float(smp.T_skin))
		tmax = maxf(tmax, float(smp.T_skin))
	f.T_min = tmin
	f.T_max = tmax


## The ghost streak: call with the ship's verdict now (the HUD's heat level),
## as often as liked. It counts sim time, so it holds through warp; a
## verdict that flickers between two calls at high warp goes unseen.
## State lives on the ship: s.ghost = {since, best, rank, best_rank}.
static func update_streak(sim: Sim, ship_id: String, level: String) -> Dictionary:
	if not sim.by_id.has(ship_id):
		return {}
	var s: Dictionary = sim.by_id[ship_id]
	if not s.has("ghost"):
		s.ghost = {"since": -1.0, "best": 0.0, "rank": 0, "best_rank": 0, "at": sim.t}
	var g: Dictionary = s.ghost
	if sim.t < float(g.get("at", 0.0)) - 1.0:
		g.since = -1.0 # time ran backwards (a load): start again
		g.rank = 0
	g.at = sim.t
	var hidden := level == "cold" or level == "none"
	if hidden:
		if float(g.since) < 0.0:
			g.since = sim.t
		var run := sim.t - float(g.since)
		g.best = maxf(float(g.best), run)
		var r := rank_of(run)
		if r > int(g.rank):
			g.rank = r
			g.best_rank = maxi(int(g.best_rank), r)
			var nm: String = RANKS[r - 1][1]
			var span := _hm(float(RANKS[r - 1][0]) * 3600.0)
			sim.say("ghost_rank", ("%s: %s below 2 %% Pd a look. Streak rank %s." if Lang.doctrinal else "%s: %s cold, unseen. Streak rank %s.") % [String(s.get("short", ship_id)), span, nm], "good")
	elif float(g.since) >= 0.0:
		var run := sim.t - float(g.since)
		if run >= REPORT_BREAK:
			var word := "seen" if level == "seen" else "showing"
			sim.say("ghost_broken", "%s %s after %s dark" % [String(s.get("short", ship_id)), word, _hm(run)], "warn")
		g.since = -1.0
		g.rank = 0
	return g


## The rank a streak of run seconds has reached (0: none yet).
static func rank_of(run: float) -> int:
	var r := 0
	for i in RANKS.size():
		if run >= float(RANKS[i][0]) * 3600.0:
			r = i + 1
	return r


## The streak now: {run, best, rank, name, next_name, next_at (s), frac}.
static func streak(sim: Sim, ship_id: String) -> Dictionary:
	var s: Dictionary = sim.by_id.get(ship_id, {})
	var g: Dictionary = s.get("ghost", {"since": -1.0, "best": 0.0, "rank": 0, "best_rank": 0})
	var run := sim.t - float(g.since) if float(g.since) >= 0.0 else 0.0
	var r := rank_of(run)
	var lo := 0.0 if r == 0 else float(RANKS[r - 1][0]) * 3600.0
	var hi := float(RANKS[mini(r, RANKS.size() - 1)][0]) * 3600.0
	return {"run": run, "on": float(g.since) >= 0.0, "best": maxf(float(g.best), run), "rank": r, "name": "—" if r == 0 else String(RANKS[r - 1][1]),
		"next_name": "" if r >= RANKS.size() else String(RANKS[r][1]), "next_at": hi, "frac": 1.0 if r >= RANKS.size() else clampf((run - lo) / maxf(hi - lo, 1.0), 0.0, 1.0),
		"best_rank": maxi(int(g.get("best_rank", 0)), r)}


## A span as "1 h 05 m" / "40 m" / "3.0 days".
static func _hm(t: float) -> String:
	var m := int(round(t / 60.0))
	if m < 60:
		return "%d m" % m
	if m < 48 * 60:
		return ("%d h" % (m / 60)) if m % 60 == 0 else "%d h %02d m" % [m / 60, m % 60]
	return "%.1f days" % (t / 86400.0)
