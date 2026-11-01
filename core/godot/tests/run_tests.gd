## Physics tests, run headless:
##   godot --headless --path godot --script res://tests/run_tests.gd
## Parity: the GDScript physics against the JS engine's own results
## (tests/fixtures/parity.json, from tools/export-godot.mjs). Validation: the
## n-body integrator against exact Kepler motion, energy, and Jupiter's J2
## apsidal precession against the analytic rate.
extends SceneTree

var fails := 0
var passes := 0


func check(name: String, ok: bool, detail := "") -> void:
	if ok:
		passes += 1
	else:
		fails += 1
		print("FAIL ", name, "  ", detail)


func rel(a: float, b: float) -> float:
	return absf(a - b) / maxf(absf(b), 1e-300)


func vrel(a: PackedFloat64Array, b: Array) -> float:
	return V.dist(a, V.from(b)) / maxf(V.norm(V.from(b)), 1e-12)


func _init() -> void:
	# On game.json alone (its own opening: HYDRA, the freighter, TRK 4417), as
	# xGEO Core ships and runs these; the scenario's checks are in shadow_test.
	Sim.campaign_path = ""
	var fx: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/parity.json"))
	var mu: float = fx.mu

	# --- parity with the JS engine ---
	for c in fx.propagate:
		var s := Kepler.propagate(V.from(c.r), V.from(c.v), c.dt, mu)
		check("propagate dt=%s" % c.dt, vrel(s[0], c.out.r) < 1e-9 and vrel(s[1], c.out.v) < 1e-9, str(vrel(s[0], c.out.r)) + " " + str(vrel(s[1], c.out.v)))
	var sim := Sim.new()
	for c in fx.moons:
		var m := sim.moon(c.id)
		var s := Kepler.from_elements(m, float(sim.data.epochOffset) + c.t, mu + float(m.gm))
		check("moon %s t=%s" % [c.id, c.t], vrel(s[0], c.out.r) < 1e-10 and vrel(s[1], c.out.v) < 1e-10)
	for c in fx.lambert:
		var sol := Lambert.solve(V.from(c.r1), V.from(c.r2), c.tof, mu)
		if c.out == null:
			check("lambert none", sol.is_empty())
		else:
			check("lambert tof=%s" % c.tof, not sol.is_empty() and vrel(sol[0], c.out.v1) < 1e-8 and vrel(sol[1], c.out.v2) < 1e-8)
	# Every branch Izzo's method gives, single and multi-revolution, flown by the two-body propagator, arrives where it was aimed.
	var lr1 := V.of(1.2e6, -3.0e5, 2.0e4)
	var lr2 := V.of(-4.0e5, 1.5e6, -6.0e4)
	var lp := 2.0 * PI * sqrt(pow(1.4e6, 3) / mu)
	var all := Lambert.solve_all(lr1, lr2, 3.6 * lp, mu, true, 5)
	var worst := 0.0
	for tr in all:
		worst = maxf(worst, V.dist(Kepler.propagate(lr1, tr.v1, 3.6 * lp, mu)[0], lr2))
	check("lambert: %d transfers (single and multi-revolution) arrive where aimed" % all.size(), all.size() >= 5 and worst < 1e-3, "%d, %.6f km" % [all.size(), worst])
	var retro := Lambert.solve(lr1, lr2, 0.4 * lp, mu, false)
	check("lambert: a retrograde transfer arrives where aimed", not retro.is_empty() and V.dist(Kepler.propagate(lr1, retro[0], 0.4 * lp, mu)[0], lr2) < 1e-3)
	for c in fx.rf.stumpff:
		check("stumpff z=%s" % c.z, rel(Kepler.stumpff_c(c.z), c.C) < 1e-12 and rel(Kepler.stumpff_s(c.z), c.S) < 1e-12)
	for c in fx.rf.dishGain:
		check("dish gain", rel(RF.dish_gain(c.D, c.f), c.out) < 1e-12)
	var fr: Dictionary = fx.rf.friis
	check("friis", rel(RF.friis(fr.Pt, fr.Gt, fr.Gr, fr.R, fr.f), fr.out) < 1e-12)
	check("noise", rel(RF.noise(fx.rf.noise.Ts, fx.rf.noise.B), fx.rf.noise.out) < 1e-12)
	check("integrate", rel(RF.integrate(fx.rf.integrate.snr, fx.rf.integrate.B, fx.rf.integrate.tau), fx.rf.integrate.out) < 1e-12)
	check("df sigma", rel(RF.df_sigma(fx.rf.dfSigma.f, fx.rf.dfSigma.d, fx.rf.dfSigma.snr), fx.rf.dfSigma.out) < 1e-9, str(RF.df_sigma(fx.rf.dfSigma.f, fx.rf.dfSigma.d, fx.rf.dfSigma.snr)) + " vs " + str(fx.rf.dfSigma.out))
	var ttc: Dictionary = sim.data.classes.vesper.ttc
	var em := {"Pt": ttc.Pt, "G": RF.from_db(ttc.towardUsDbi), "f": ttc.f, "bw": ttc.bw}
	for c in fx.rf.interceptRangeKm:
		check("intercept range", rel(RF.intercept_range_km(em, c.esm, ttc.burst, fx.detectSnr), c.out) < 1e-12)
	for c in fx.rf.signature:
		var r := RF.signature_ranges(c.sig, c.engine, fx.nei)
		check("IR range %s" % c.id, rel(r.cold, c.out.cold) < 1e-12 and rel(r.burning, c.out.burning) < 1e-12)
	for c in fx.rf.deltaV:
		check("delta-v %s" % c.id, rel(RF.delta_v(c.ve, c.dry, c.prop), c.out) < 1e-12)

	# --- the integrator: with J2 and the moons off it must reproduce Kepler ---
	var g := Gravity.new(mu, sim.moons, sim.moon_state)
	g.use_j2 = false
	g.use_moons = false
	var hy: Dictionary = sim.ship("hydra")
	var exact := Kepler.propagate(hy.r, hy.v, 86400.0, mu)
	var num := g.coast(hy.r, hy.v, 0.0, 86400.0, 60.0)
	check("coast = Kepler over a day", V.dist(num[0], exact[0]) < 0.01, "%f km" % V.dist(num[0], exact[0]))
	var e0 := Kepler.energy(hy.r, hy.v, mu)
	check("energy kept", rel(Kepler.energy(num[0], num[1], mu), e0) < 1e-10)

	# --- J2 turns an eccentric equatorial orbit's periapsis at 1.5 n J2 (R/p)² ---
	# (dω/dt + dΩ/dt at i = 0; Vallado 2013 eq. 9-41, Curtis 2020 eq. 4.52–4.53)
	g.use_j2 = true
	var a := 300000.0
	var e := 0.3
	var rp := a * (1.0 - e)
	var r0 := V.of(rp, 0.0)
	var v0 := V.of(0.0, sqrt(mu * (1.0 + e) / rp))
	var n := sqrt(mu / (a * a * a))
	var p := a * (1.0 - e * e)
	var rate := 1.5 * n * Gravity.J2 * pow(Gravity.R_REF / p, 2.0)
	var days := 60.0
	var st := g.coast(r0, v0, 0.0, days * 86400.0, 30.0)
	var ev := V.sub(V.scale(V.cross(st[1], V.cross(st[0], st[1])), 1.0 / mu), V.scale(st[0], 1.0 / V.norm(st[0])))
	var drift := atan2(ev[1], ev[0])
	var want := fmod(rate * days * 86400.0 + PI, TAU) - PI
	check("J2 apsidal precession", rel(drift, want) < 0.03, "got %.5f rad, analytic %.5f" % [drift, want])

	# --- the moons matter: Ganymede's pull over a week, near its orbit ---
	g.use_moons = true
	var with_moons := g.coast(hy.r, hy.v, 0.0, 7 * 86400.0, 60.0)
	g.use_moons = false
	var without := g.coast(hy.r, hy.v, 0.0, 7 * 86400.0, 60.0)
	var gap := V.dist(with_moons[0], without[0])
	check("moons perturb HYDRA over a week", gap > 100.0, "%f km" % gap)
	print("moons move HYDRA %.0f km in a week" % gap)

	# --- the gradient of the full force model (J2, moons, Sun) against central
	# differences of accel, off the plane so J2's z terms count; then the
	# transition matrix flown with the orbit against differences of whole coasts ---
	var gf: Gravity = sim.gravity
	var gr := V.of(hy.r[0], hy.r[1], 4.0e4)
	var gd := gf.gradient(gr, 3600.0)
	var gworst := 0.0
	for j in 3:
		var up := gr.duplicate()
		var dn := gr.duplicate()
		up[j] += 1.0
		dn[j] -= 1.0
		var col := V.scale(V.sub(gf.accel(up, 3600.0), gf.accel(dn, 3600.0)), 0.5)
		for i in 3:
			gworst = maxf(gworst, absf(gd[i][j] - col[i]) / absf(gd[0][0]))
	check("gravity gradient = differences of accel", gworst < 1e-7, str(gworst))
	var sdt := 6.0 * 3600.0
	var sv: PackedFloat64Array = hy.v.duplicate()
	var sm := gf.coast_stm(hy.r, sv, 0.0, sdt)
	var plain := gf.coast(hy.r, sv, 0.0, sdt)
	check("coast_stm flies the plain coast", V.dist(sm[0], plain[0]) == 0.0 and V.dist(sm[1], plain[1]) == 0.0)
	var sworst := 0.0
	var steps := [1.0, 1.0, 1.0, 1e-4, 1e-4, 1e-4]
	for j in 6:
		var s_up: PackedFloat64Array = hy.r.duplicate()
		s_up.append_array(sv)
		var s_dn := s_up.duplicate()
		s_up[j] += steps[j]
		s_dn[j] -= steps[j]
		var ca: Array = gf.coast(s_up.slice(0, 3), s_up.slice(3), 0.0, sdt)
		var cb: Array = gf.coast(s_dn.slice(0, 3), s_dn.slice(3), 0.0, sdt)
		var col := V.scale(V.sub(ca[0], cb[0]), 0.5 / steps[j])
		col.append_array(V.scale(V.sub(ca[1], cb[1]), 0.5 / steps[j]))
		for i in 6:
			var sc := 1.0 if i < 3 else sdt # each block made dimensionless by the coast's length
			sworst = maxf(sworst, absf(sm[2][i][j] - col[i]) * sc * (1.0 if j < 3 else 1.0 / sdt))
	check("transition matrix = differences of whole coasts", sworst < 1e-5, str(sworst))
	print("gravity gradient off differences by ", gworst, "; transition matrix by ", sworst, " (scaled)")

	# --- hearing: GAN STN hears a report out to the engine's range ---
	# (Red's reporting habit is the scenario's: Core alone, with no scenario file, has none to hear.)
	sim.advance(3.0 * 3600.0)
	if not sim.camp.is_empty():
		check("first report heard by someone", sim.intercepts.size() >= 1, "%d intercepts" % sim.intercepts.size())

	# --- an intercept flown under real gravity: Lambert aims for Jupiter alone, so
	# J2 and the moons drift it off; execute() refines the burn under the full
	# force model (Sim.refine). Halfway, it is re-aimed: by almost nothing when
	# the target holds its orbit (Core alone), by more when the scenario moves it ---
	var game := Sim.new()
	var plan := game.plan_intercept("hydra", "h1", 18.0 * 3600.0, true)
	check("intercept plan affordable", plan.ok, str(plan.get("why")))
	var hy0: Dictionary = game.by_id["hydra"]
	var tof0: float = plan.arrive - game.t
	var lambert_only: Array = game.gravity.coast(hy0.r, V.add(hy0.v, plan.dv_vec), game.t, tof0, 60.0)
	var miss_lambert := V.dist(lambert_only[0], plan.node)
	check("Lambert alone misses under real gravity", miss_lambert > 50.0, "%f km" % miss_lambert)
	game.execute(plan)
	var best := INF
	var miss_mid := 0.0
	for i in 18 * 6:
		if i == 9 * 6:
			var fix := game.plan_intercept("hydra", "h1", plan.arrive - game.t, true)
			miss_mid = V.dist(game.predict("hydra", (plan.arrive - game.t) / 3600.0, 54).back(), fix.node)
			game.execute(fix)
		game.advance(600.0)
		best = minf(best, game.range_km("hydra", "h1"))
	for i in 60:
		game.advance(30.0)
		best = minf(best, game.range_km("hydra", "h1"))
	print("Lambert alone would miss by %.0f km; refined, re-aimed by %.0f km at mid-course, closest %.1f km" % [miss_lambert, miss_mid, best])
	check("refined intercept brings HYDRA within 50 km", best < 50.0, "%f km" % best)
	print("%d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)
