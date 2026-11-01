## The bridge to the independent physics checks (tools/verify): evaluates the
## game's OWN physics functions on the inputs in tools/verify/fixtures/cases.json
## and on the live campaign (every ship, sensor, emitter and weapon), and writes
## the results as JSON for the pytest suite to compare with reference libraries.
##   godot --headless --path godot --script res://tests/dump_physics.gd -- --cases=<file> --out=<file>
## (node tools/verify.mjs runs it.) Nothing here computes physics itself:
## every number comes from godot/core/*.gd.
extends SceneTree

var sim: Sim


## Jupiter → Sun and each planet (km, game frame): the tables, or the gravity model's interpolated cache.
func planets_at(ms: float, interp: bool) -> Dictionary:
	var out := {}
	for b in ["sun"] + Ephem.PLANETS:
		if b != "jupiter":
			out[b] = arr(Ephem.pos(b, ms) if interp else Ephem.exact(b, ms))
	return out


func arr(p) -> Array:
	var out := []
	for x in p:
		out.append(float(x))
	return out


func mat(P: Array) -> Array:
	return P.map(func(r): return arr(r))


func state(st: Array) -> Dictionary:
	return {"r": arr(st[0]), "v": arr(st[1])}


func _init() -> void:
	# The platforms and effects of the scenario (tests/fixtures/jupiter_shadow.json, a test world) when it is here;
	# xGEO Core on its own has no scenario file, and then it runs on game.json alone.
	if not FileAccess.file_exists(Sim.campaign_path):
		Sim.campaign_path = ""
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var root := ProjectSettings.globalize_path("res://").path_join("..")
	var cases_path: String = args.get("cases", root.path_join("tools/verify/fixtures/cases.json"))
	var out_path: String = args.get("out", root.path_join("tools/verify/out/game_physics.json"))
	var cases: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(cases_path))
	sim = Sim.new("res://data/game.json", "res://tests/fixtures/jupiter_shadow.json")
	var t0 := Time.get_ticks_msec()
	var out := {
		"note": "Written by godot/tests/dump_physics.gd from the game's own functions. Do not edit.",
		"godot": Engine.get_version_info().string,
		"constants": constants(),
		"kepler": kepler(cases),
		"lambert": lambert(cases),
		"gravity": gravity(cases),
		"moons": moons(cases),
		"rf": rf(cases),
		"sensing": sensing(cases),
		"effects": effects(cases),
		"tracking": tracking(cases),
		"platforms": platforms(),
		"ephem": cases.ephem.map(func(k): return {"in": k, "sun": arr(Ephem.sun(k.utc_ms)), "earth": arr(Ephem.earth(k.utc_ms))}),
		"planets": cases.get("planets", []).map(func(k): return {"in": k, "exact": planets_at(k.utc_ms, false), "interp": planets_at(k.utc_ms, true)}),
		"shadow": shadow(),
		"skin": skin(),
	}
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "", false, true))
	f.close()
	print("dump_physics: wrote %s in %.1f s" % [out_path, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(0)


func constants() -> Dictionary:
	var moons := []
	for m in sim.moons:
		moons.append(m)
	return {"mu": sim.mu, "J2": Gravity.J2, "R_REF": Gravity.R_REF, "R_J": float(sim.data.jupiter.radius), "track_mu": Track.MU,
		"C_MS": RF.C_MS, "K_BOLTZ": RF.K_BOLTZ, "SIGMA_SB": RF.SIGMA_SB, "NTR_VE": float(sim.data.constants.NTR_VE), "G0": float(sim.data.constants.G0),
		"epochOffset": float(sim.data.epochOffset), "startUtc": float(sim.data.startUtc), "moons": moons,
		"UPLINK_BAND_HZ": Effects.UPLINK_BAND_HZ, "UPLINK_BW_HZ": Effects.UPLINK_BW_HZ, "TURNAROUND": Effects.TURNAROUND, "DF_FLOOR": Sensing.DF_FLOOR,
		"LOOK": Sim.LOOK, "bands": sim.data.bands, "cfg": sim.data.cfg, "effects_cfg": sim.camp.get("effects", {})}


func ship_cases() -> Array:
	var out := []
	for s in sim.ships:
		if s.has("r") and not s.has("onMoon"):
			out.append({"name": "ship:" + String(s.id), "r": arr(s.r), "v": arr(s.v)})
	return out


func kepler(cases: Dictionary) -> Dictionary:
	var prop := []
	var all: Array = cases.propagate.duplicate()
	for s in ship_cases():
		for dt in [600.0, 21600.0, 172800.0, -3600.0]:
			all.append({"name": s.name, "r": s.r, "v": s.v, "dt": dt})
	for c in all:
		var r := V.from(c.r)
		var v := V.from(c.v)
		var st := Kepler.propagate(r, v, float(c.dt), sim.mu)
		prop.append({"name": c.name, "r0": c.r, "v0": c.v, "dt": c.dt, "out": state(st), "a": Kepler.semi_major_axis(r, v, sim.mu), "energy": Kepler.energy(r, v, sim.mu),
			"period": Kepler.period(Kepler.semi_major_axis(r, v, sim.mu), sim.mu) if Kepler.semi_major_axis(r, v, sim.mu) > 0.0 else -1.0})
	var els := []
	for c in cases.elements:
		els.append({"el": c.el, "t": c.t, "out": state(Kepler.from_elements(c.el, float(c.t), sim.mu))})
	var stump := []
	for z in [-50.0, -4.0, -1e-5, -1e-7, 0.0, 1e-7, 1e-5, 2.5, 30.0, 39.0]:
		stump.append({"z": z, "C": Kepler.stumpff_c(z), "S": Kepler.stumpff_s(z)})
	var worked := []
	for c in cases.worked.propagate:
		worked.append({"in": c, "out": state(Kepler.propagate(V.from(c.r), V.from(c.v), float(c.dt), float(c.mu)))})
	return {"propagate": prop, "elements": els, "stumpff": stump, "worked": worked}


func lambert(cases: Dictionary) -> Array:
	var out := []
	for c in cases.worked.lambert:
		var sol := Lambert.solve(V.from(c.r1), V.from(c.r2), float(c.tof), float(c.mu))
		out.append({"name": "worked", "worked": c, "r1": c.r1, "r2": c.r2, "tof": c.tof, "mu": c.mu, "v1": arr(sol[0]) if not sol.is_empty() else null, "v2": arr(sol[1]) if not sol.is_empty() else null})
	var all: Array = cases.lambert.duplicate()
	var hy: Dictionary = sim.by_id.get("hydra", {})
	if not hy.is_empty():
		for s in sim.ships:
			if s.id != "hydra" and s.has("r") and not s.has("onMoon"):
				for tof in [6.0 * 3600.0, 18.0 * 3600.0, 3.0 * 86400.0]:
					all.append({"r1": arr(hy.r), "r2": arr(s.r), "tof": tof, "name": "hydra->" + String(s.id)})
	for c in all:
		var sol := Lambert.solve(V.from(c.r1), V.from(c.r2), float(c.tof), sim.mu)
		out.append({"name": c.get("name", ""), "r1": c.r1, "r2": c.r2, "tof": c.tof, "mu": sim.mu, "v1": arr(sol[0]) if not sol.is_empty() else null, "v2": arr(sol[1]) if not sol.is_empty() else null})
	return out


func gravity(cases: Dictionary) -> Dictionary:
	var g := Gravity.new(sim.mu, sim.moons, sim.moon_state)
	var acc := []
	for c in cases.accel:
		g.use_j2 = c.j2
		g.use_moons = c.moons
		acc.append({"r": c.r, "t": c.t, "j2": c.j2, "moons": c.moons, "a": arr(g.accel(V.from(c.r), float(c.t)))})
	var coasts := []
	var all: Array = cases.coast.duplicate()
	for s in ship_cases():
		all.append({"name": s.name, "r": s.r, "v": s.v, "t0": 0.0, "dt": 86400.0, "max_h": 60.0, "j2": true, "moons": true, "samples": 4})
	for c in all:
		g.use_j2 = c.j2
		g.use_moons = c.moons
		var st := [V.from(c.r), V.from(c.v)]
		var n := int(c.samples)
		var seg := float(c.dt) / n
		var samples := [{"t": float(c.t0), "r": arr(st[0]), "v": arr(st[1])}]
		var t := float(c.t0)
		for i in n:
			st = g.coast(st[0], st[1], t, seg, float(c.max_h))
			t += seg
			samples.append({"t": t, "r": arr(st[0]), "v": arr(st[1])})
		coasts.append({"name": c.name, "t0": c.t0, "dt": c.dt, "max_h": c.max_h, "j2": c.j2, "moons": c.moons, "samples": samples})
	# The transition matrix the tracker flies with its mean (J2 and the moons;
	# the reference has no Sun): the first ships, and one lifted off the plane.
	g.use_j2 = true
	g.use_moons = true
	var stms := []
	var ships := ship_cases().slice(0, 2)
	ships.append({"name": ships[0].name + " (off the plane)", "r": [ships[0].r[0], ships[0].r[1], 4.0e4], "v": ships[0].v})
	for c in ships:
		var st := g.coast_stm(V.from(c.r), V.from(c.v), 0.0, 6.0 * 3600.0)
		stms.append({"name": c.name, "r": c.r, "v": c.v, "t0": 0.0, "dt": 6.0 * 3600.0, "r1": arr(st[0]), "v1": arr(st[1]), "phi": mat(st[2])})
	return {"accel": acc, "coast": coasts, "stm": stms}


func moons(cases: Dictionary) -> Dictionary:
	var out := {}
	var eo := float(sim.data.epochOffset)
	for m in sim.moons:
		var rows := []
		for jd in cases.moon_jd_tdb:
			# Game time t is seconds after the campaign start; the elements' clock is epochOffset + t after J2000.
			var t := (float(jd) - float(cases.jd_j2000)) * 86400.0 - eo
			rows.append({"jd_tdb": jd, "t": t, "out": state(sim.moon_state(m.id, t))})
		out[m.id] = rows
	return out


func rf(cases: Dictionary) -> Dictionary:
	var c: Dictionary = cases.rf
	var fx := Effects.new(sim)
	return {
		"db": c.db.map(func(x): return {"x": x, "db": RF.db(x), "back": RF.from_db(RF.db(x))}),
		"wavelength": [2.2965e9, 8.43e9, 1e10].map(func(f): return {"f": f, "lam": RF.wavelength(f)}),
		"dish_gain": c.dish_gain.map(func(k): return {"D": k.D, "f": k.f, "G": RF.dish_gain(k.D, k.f)}),
		"friis": c.friis.map(func(k): return {"in": k, "Pr": RF.friis(k.Pt, k.Gt, k.Gr, k.R, k.f)}),
		"noise": c.noise.map(func(k): return {"in": k, "N": RF.noise(k.Ts, k.B)}),
		"integrate": c.integrate.map(func(k): return {"in": k, "out": RF.integrate(k.snr, k.B, k.tau)}),
		"df_sigma": c.df_sigma.map(func(k): return {"in": k, "out": RF.df_sigma(k.f, k.d, k.snr, k.n)}),
		"diffraction": c.diffraction.map(func(k): return {"in": k, "out": RF.diffraction(k.lam, k.D)}),
		"fspl": c.fspl.map(func(k): return {"in": k, "db": fx._fspl_db(k.R, k.f), "friis_unity_db": -RF.db(RF.friis(1.0, 1.0, 1.0, k.R, k.f))}),
		"grey": c.grey.map(func(k): return {"in": k, "P": RF.grey(k)}),
		"delta_v": c.delta_v.map(func(k): return {"in": k, "out": RF.delta_v(k.ve, k.dry, k.prop)}),
		"antenna": c.antenna.map(func(k): return {"in": k, "gain_dbi": Antenna.gain_dbi(k.D, k.f, deg_to_rad(k.phi_deg)), "peak_dbi": Antenna.peak_dbi(k.D, k.f), "beamwidth": Antenna.beamwidth(k.D, k.f)}),
		"detect": c.detect.map(func(k): return {"in": k, "pd": RF.detect_pd(k.snr, k.pfa, k.n), "q_inv": RF.q_inv(k.pfa)}),
	}


func sensing(cases: Dictionary) -> Dictionary:
	var se: Sensing = sim.sensing
	var occ := []
	for c in cases.occult:
		occ.append({"a": c.a, "b": c.b, "blocked": se.occulted(V.from(c.a), V.from(c.b))})
	# In-band IR (Thermal): Planck band fractions, skin and radiator heat, every
	# ship's intensity term by term toward observers at several aspects, and who
	# sees whom with the S/N, Pd and background each decision used.
	var S := Thermal.sun_flux(sim.data)
	var band := []
	for T in [60.0, 110.0, 140.0, 172.0, 200.0, 260.0, 300.0, 400.0, 460.0, 1000.0, 1300.0, 1400.0, 3000.0]:
		band.append({"T": T, "frac": Thermal.band_fraction(T), "below6": Thermal.frac_below(6.0, T), "below10": Thermal.frac_below(10.0, T)})
	var skins := []
	var rads := []
	for k in sim.data.classes:
		var cl: Dictionary = sim.data.classes[k]
		if not cl.has("sig"):
			continue
		skins.append({"class": k, "sig": cl.sig, "S": S, "leak": Thermal.skin_leak(cl.sig, S), "T_lit": Thermal.skin_T(cl.sig, S, true), "T_shadow": Thermal.skin_T(cl.sig, S, false), "I_band": Thermal.grey_band(cl.sig)})
		if cl.get("thermal", {}).has("radiator"):
			var Q := Thermal.waste(cl)
			var T := Thermal.radiator_T(cl.thermal.radiator, Q)
			var by := []
			for deg in [0.0, 30.0, 60.0, 85.0, 90.0]:
				by.append({"theta_deg": deg, "I": Thermal.radiator_I(cl.thermal.radiator, T, deg_to_rad(deg))})
			rads.append({"class": k, "thermal": cl.thermal, "Q": Q, "T": T, "by_angle": by, "laser_T": Thermal.radiator_T(cl.thermal.radiator, Q + (float(cl.weapon.power) * (1.0 / float(cl.weapon.get("wallPlug", 0.25)) - 1.0) if cl.get("weapon", {}).get("kind", "") == "laser" else 0.0))})
	var inten := []
	for s in sim.ships:
		if not s.cls.has("sig") or not s.has("r"):
			continue
		for deg in [0.0, 45.0, 90.0]:
			var at := V.add(s.r, V.of(cos(deg_to_rad(deg)) * 1e5, sin(deg_to_rad(deg)) * 1e5))
			inten.append({"id": s.id, "class": s.classId, "r": arr(s.r), "toward": arr(at), "heat": s.get("heat", {}), "shadow": sim.thermal.in_shadow(s.r), "cold": sim.thermal.intensity(s, at, false), "burning": sim.thermal.intensity(s, at, true)})
	var sees := []
	var vis := []
	for o in se.sensors():
		for x in sim.ships:
			if x.side == "blue":
				continue
			var L := se.ir_look(o, x)
			var Vc := se.vis_look(o, x)
			var Vl := se.vis_look(o, x, false)
			sees.append({"o": o.id, "x": x.id, "or": arr(o.r), "xr": arr(x.r), "nei_band": float(o.cls.ir.get("neiBand", o.cls.ir.nei)), "I": float(L.get("terms", {}).get("total", 0.0)), "snr": float(L.snr), "pd": float(L.get("pd", 0.0)), "bg": float(L.get("bg", 1.0)), "vis_snr": float(Vc.snr), "tracked": sim.tracks.has(x.id), "sees": se.ir_sees(o, x)})
			if Vl.has("mag"):
				vis.append({"o": o.id, "x": x.id, "sig": x.cls.sig, "aperture": float(o.cls.optical.aperture), "R_m": float(Vl.R_m), "phase": float(Vl.phase), "mag": float(Vl.mag), "limit": float(Vl.limit), "snr": float(Vl.snr), "pd": float(Vl.pd)})
	# The heat sink over a dark spell and its recharge: one ship, look by look.
	var sink := []
	if sim.by_id.has("hydra"):
		var hy: Dictionary = sim.by_id.hydra
		var keep: Dictionary = hy.get("heat", {}).duplicate(true)
		hy.heat = {"dark": true}
		for i in 30:
			if i == 12:
				hy.heat.dark = false
			sim.thermal.step(Sim.LOOK)
			sink.append({"i": i, "dark": hy.heat.get("dark", false), "stored": float(hy.heat.get("stored", 0.0)), "vented": float(hy.heat.get("vented", 0.0)), "Q": float(hy.heat.Q)})
		hy.heat = keep
	# False alarms: how many single-look lines noise alone makes, over many looks.
	var fa := 0
	var looks := 4000
	for i in looks:
		se.false_lines.clear()
		se._false_alarms(sim.t)
		fa += se.false_lines.size()
	se.false_lines.clear()
	var fa_out := {"looks": looks, "sensors": se.sensors().size(), "count": fa, "mean_per_sensor": float(sim.data.cfg.ir.band.falseAlarmsPerLook)}
	# Radar SNR on every class at a grid of ranges, and the angle error it reports.
	var radar := []
	for k in sim.data.classes:
		var cl: Dictionary = sim.data.classes[k]
		if not cl.has("radar"):
			continue
		for tk in sim.data.classes:
			var rcs := float(sim.data.classes[tk].get("rcs", 1.0))
			for R in cases.radar_R_km:
				var snr := Sensing.radar_snr(cl.radar, rcs, float(R) * 1000.0)
				radar.append({"radar_class": k, "radar": cl.radar, "target": tk, "rcs": rcs, "R_km": R, "snr": snr, "angle_sigma": Sensing.radar_angle_sigma(cl.radar, snr)})
	# Intercept SNR of every emitter class at every ES receiver class, at 1e6 km over one burst.
	# ... with the emitter's dish 0° to 180° off the receiver and the receiver at its peak.
	var pfa := float(sim.data.cfg.radio.get("pfa", 1e-6))
	var links := []
	for ek in sim.data.classes:
		var em: Dictionary = sim.data.classes[ek]
		if not em.has("ttc") or not em.ttc.has("dish"):
			continue
		var f := float(em.ttc.f)
		for rk in sim.data.classes:
			var rx: Dictionary = sim.data.classes[rk]
			if not rx.has("esm"):
				continue
			for off_deg in [0.0, 2.0, 10.0, 30.0, 90.0, 180.0]:
				var gt := Antenna.gain_dbi(float(em.ttc.dish), f, deg_to_rad(off_deg))
				var gr := Antenna.peak_dbi(float(rx.esm.dish), f)
				links.append({"emitter": ek, "receiver": rk, "ttc": em.ttc, "esm": rx.esm, "R_m": 1e9, "off_deg": off_deg, "Gt_dbi": gt, "Gr_dbi": gr,
					"snr": Sensing.link_snr(float(em.ttc.Pt), gt, gr, f, float(em.ttc.bw), float(rx.esm.Ts), 1e9, float(em.ttc.burst)),
					"range_km": Sensing.reach_km(em.ttc, rx.esm, deg_to_rad(off_deg), pfa)})
	# A receive array's gain all the way round (scan loss off its nearest face).
	var arrays := []
	for e in se.ears():
		if String(e.cls.esm.get("kind", "array")) != "array":
			continue
		for k in 48:
			var th := TAU * k / 48.0 + 0.01
			var toward := V.add(e.r, V.of(1e6 * cos(th), 1e6 * sin(th)))
			arrays.append({"ear": e.id, "esm": e.cls.esm, "f": 8.43e9, "theta": th, "gain_dbi": se.ear_gain(e, toward, 8.43e9, sim.t).dbi})
		break
	return {"occult": occ, "band": band, "skins": skins, "radiators": rads, "intensity": inten, "ir_sees": sees, "vis": vis, "sink": sink, "false_alarms": fa_out, "radar": radar, "links": links, "arrays": arrays, "pfa": pfa,
		"glare": {"cone": float(sim.data.cfg.ir.glareCone), "band": sim.data.cfg.ir.band, "vis": sim.data.cfg.vis, "sun_dir": arr(sim.sun_dir()), "S": S}}


func effects(cases: Dictionary) -> Dictionary:
	var fx: Effects = sim.effects
	var out := {}
	var w := {}
	# The laser of the scenario's ships, else of any class that carries one
	# (CLOSE PASS fields none; EXCALIBUR's class is in game.json).
	for s in sim.ships:
		if fx.laser(s).size() > 0:
			w = fx.laser(s)
	if w.is_empty():
		for k in sim.data.classes:
			if fx.laser({"cls": sim.data.classes[k]}).size() > 0:
				w = fx.laser({"cls": sim.data.classes[k]})
				break
	if not w.is_empty():
		out.laser = {"w": w, "dazzle_range_km": fx.dazzle_range_km(w), "spots": cases.laser_R_km.map(func(R): return {"R_km": R, "spot_m": fx.spot_m(w, R), "irradiance": fx.irradiance(w, R)})}
	out.hpm_range_km = fx.hpm_range_km()
	out.kill_probability = cases.kill_probability.map(func(k): return {"in": k, "pk": Effects.kill_probability(k.reach, k.sigma, k.rel)})
	# Jamming geometry: a shooter and a target placed around the handler (Callisto at t = 0).
	var hp := sim.handler_pos()
	var shooter: Dictionary = {}
	var target: Dictionary = {}
	for s in sim.ships:
		if s.side == "blue" and s.alive and shooter.is_empty() and not s.has("onMoon"):
			shooter = s
		if s.side == "red" and target.is_empty() and s.cls.get("ttc", {}).has("dish"):
			target = s
	var keep := [shooter.r, target.r]
	var jam := []
	# Without its telescope, so the jammer aims at the track (the case the
	# reference models); the telescope-slaved aim is checked by pointing below.
	var cls_keep: Dictionary = shooter.cls
	shooter.cls = cls_keep.duplicate()
	shooter.cls.erase("ir")
	# The shooter at angles th off the victim's line to its handler; the jammer aims at
	# Blue's track where there is one (its error from the truth costs gain).
	for dT in [2e5, 8e5, 1.5e6]:
		for dS in [1e3, 1e4, 5e4, 2e5]:
			for th_deg in [0.5, 5.0, 30.0, 90.0, 180.0]:
				var th := deg_to_rad(th_deg)
				target.r = V.add(hp, V.of(dT, 0.0, 0.0))
				shooter.r = V.add(target.r, V.of(-dS * cos(th), dS * sin(th), 0.0))
				fx.technique[shooter.id] = "barrage"
				var barrage := fx.js_db(shooter, target)
				var raw := fx._js_raw(shooter, target)
				var aim: PackedFloat64Array = sim.tracks[target.id].pos() if sim.tracks.has(target.id) else target.r
				jam.append({"handler": arr(hp), "target_r": arr(target.r), "shooter_r": arr(shooter.r), "aim": arr(aim), "victim_dish": float(target.cls.ttc.dish), "th_deg": th_deg,
					"terms": fx.js_terms(shooter, target), "js_raw_db": raw, "js_barrage_db": barrage, "spread_db": fx.spread_db(shooter.id, target.id),
					"range_for_need_km": fx._jam_reach(shooter, target, float(fx.cfg.jam.needJsDb), V.dist(shooter.r, target.r)),
					"reach_far_km": maxf(V.dist(shooter.r, target.r) * 4.0, 2e5)})
	shooter.cls = cls_keep
	shooter.r = keep[0]
	target.r = keep[1]
	fx.technique.erase(shooter.id)
	out.jam = jam
	# Pointing: the beam is "on" when the track's 1σ across the line of sight over range is below half the beamwidth.
	var pt := []
	var jf := float(fx.cfg.jam.jammer.f)
	var jd := float(fx.cfg.jam.jammer.dish)
	var trk := Track.new(target.id, "TEST", PackedFloat64Array([shooter.r[0] + 1e5, shooter.r[1], 0.0, 0.0]), Track.diag([1.0, 1.0, 1e-6, 1e-6]), sim.t)
	var had: Track = sim.tracks.get(target.id)
	sim.tracks[target.id] = trk
	for sig in [500.0, 1000.0, 1500.0, 1650.0, 1750.0, 2000.0, 3000.0]:
		# σ across the line of sight (the track lies along +x from the shooter): what cross_sigma reads.
		trk.P = Track.diag([1.0, sig * sig, 1e-6, 1e-6])
		pt.append({"sigma_km": sig, "range_km": 1e5, "dish": jd, "f": jf, "can_point": fx.can_point(shooter, target.id, jd, jf), "scope": fx.sees_to_aim(shooter, sim.by_id[target.id])})
	if had != null:
		sim.tracks[target.id] = had
	else:
		sim.tracks.erase(target.id)
	out.pointing = pt
	out.uplinks = []
	for k in sim.data.classes:
		if sim.data.classes[k].has("ttc"):
			out.uplinks.append({"class": k, "down": float(sim.data.classes[k].ttc.f), "up": float(sim.data.classes[k].ttc.f) * Effects.TURNAROUND})
	return out


func tracking(cases: Dictionary) -> Dictionary:
	var keep := Track.gravity
	Track.gravity = null
	var upd := []
	for c in cases.ukf:
		var P := []
		for row in c.P:
			P.append(PackedFloat64Array(row))
		var tr := Track.new("x", "T", PackedFloat64Array(c.x), P, 0.0)
		# The unscented step itself: update_bearing may first widen the track
		# (an unseen burn) or take the straight-line branch, checked elsewhere.
		var sp := V.from(c.s)
		if c.kind == "bearing":
			tr._update(float(c.z), func(p): return atan2(p[1] - sp[1], p[0] - sp[0]), float(c.sigma) * float(c.sigma), true)
		else:
			tr._update(float(c.z), func(p): return sqrt((p[0] - sp[0]) * (p[0] - sp[0]) + (p[1] - sp[1]) * (p[1] - sp[1])), float(c.sigma) * float(c.sigma), false)
		upd.append({"in": c, "x": arr(tr.x), "P": mat(tr.P)})
	var stms := []
	for c in cases.stm:
		var x := PackedFloat64Array(c.x)
		var P0 := Track.diag([100.0, 400.0, 1e-4, 4e-4])
		var tr := Track.new("x", "T", x, P0, 0.0)
		tr.predict(float(c.dt))
		stms.append({"x": c.x, "dt": c.dt, "F": mat(Track.stm(x, float(c.dt))), "coast": arr(Track.coast(x, float(c.dt))), "P0": mat(P0), "P": mat(tr.P), "x1": arr(tr.x), "accel_noise": tr.accel_noise})
	var fixes := []
	for c in cases.cross_fix:
		var lines := []
		for l in c.lines:
			lines.append({"from": V.from(l.from), "bearing": float(l.bearing), "sigma": float(l.sigma)})
		var f := Track.cross_fix(lines)
		fixes.append({"in": c, "ok": f.ok, "r": arr(f.r) if f.ok else null, "P2": f.P2 if f.ok else null})
	Track.gravity = keep
	return {"update": upd, "stm": stms, "cross_fix": fixes}


## The campaign platforms, as the game sees them: classes (game + campaign) and starting ships.
## Jupiter's shadow at the campaign's start: points across its edge, beside the
## equator and over the pole, at four distances behind it, and the share of
## the Sun each sees (Thermal.lit_share, Jupiter alone).
func shadow() -> Dictionary:
	var sim := Sim.new("res://data/game.json", "res://tests/fixtures/jupiter_shadow.json")
	var sun := Ephem.exact("sun", sim.utc_ms(0.0))
	var sh := V.scale(sun, 1.0 / V.norm(sun))
	var u := V.cross(sh, V.of(0, 0, 1))
	u = V.scale(u, 1.0 / V.norm(u))
	var w := V.cross(sh, u)
	var re := float(sim.data.jupiter.radius)
	var rp: float = Ephem.BODY.jupiter.rp
	var body := [[V.of(0, 0, 0), re, rp]]
	var pts := []
	for d in [2.0e5, 1.07e6, 1.0e7, 5.0e7]:
		var rho := Ephem.R_SUN / V.norm(sun)
		for side in [["eq", u, re], ["pole", w, rp]]:
			for i in 25:
				var off: float = float(side[2]) * (1.0 - d / V.norm(sun)) + (i - 12) / 12.0 * 1.6 * d * rho
				var r := V.add(V.scale(sh, -d), V.scale(side[1], off))
				pts.append({"d": d, "side": side[0], "r": arr(r), "f": Thermal.lit_share(r, sun, body)})
	return {"sun": arr(sun), "re": re, "rp": rp, "R_sun": Ephem.R_SUN, "limb_u": Thermal.LIMB_U, "points": pts}


## A skin cooling into shadow and warming out of it (Thermal.skin_step), each
## hour for six hours, for HYDRA's class.
func skin() -> Dictionary:
	var sim := Sim.new("res://data/game.json", "res://tests/fixtures/jupiter_shadow.json")
	var s: Dictionary = sim.by_id["hydra"]
	var S := Thermal.sun_flux(sim.data)
	var C := Thermal.heat_capacity(s)
	var sig: Dictionary = s.cls.sig
	var out := {"sig": sig, "S": S, "C": C, "leak": Thermal.skin_leak(sig, S), "runs": []}
	for f in [[1.0, 0.0], [0.0, 1.0]]:
		var T := Thermal.skin_eq(sig, S, f[0])
		var ts := [T]
		for i in 6:
			T = Thermal.skin_step(sig, S, f[1], C, T, 3600.0)
			ts.append(T)
		out.runs.append({"from": f[0], "to": f[1], "T": ts})
	return out


func platforms() -> Dictionary:
	var ships := []
	for s in sim.ships:
		var d := {"id": s.id, "class": s.classId, "side": s.side}
		if s.has("r"):
			d.r = arr(s.r)
			d.v = arr(s.v)
		if s.has("dry"):
			d.dry = float(s.dry)
		if s.has("prop"):
			d.prop = float(s.prop)
		if s.cls.has("engine") and s.has("prop"):
			d.delta_v = sim.delta_v(s.id)
		ships.append(d)
	var ranges := {}
	for k in sim.data.classes:
		var c: Dictionary = sim.data.classes[k]
		if c.has("sig"):
			ranges[k] = Thermal.ranges(c, float(sim.data.classes.sentinel.ir.neiBand), Thermal.sun_flux(sim.data))
	return {"classes": sim.data.classes, "ships": ships, "signature_ranges": ranges}
