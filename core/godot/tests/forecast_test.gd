## The thermal forecast (core/forecast.gd), headless:
##   godot --headless --path godot --script res://tests/forecast_test.gd
## - In the shadowing scenario at T+6 it returns a revolution of samples.
## - Each sample's sunlight is Thermal.sunlight at that point and time.
## - Sample 0 is the HUD's verdict now (the same worst-case look).
## - The ghost streak counts COLD sim time, ranks up once, and resets when seen.
## - One compute stays well under 15 ms.
extends SceneTree

var fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok    " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _initialize() -> void:
	Sim.campaign_path = "res://tests/fixtures/jupiter_shadow.json"
	var sim := Sim.new("res://data/game.json", "res://tests/fixtures/jupiter_shadow.json")
	while sim.t < 6.0 * 3600.0:
		sim.advance(Sim.LOOK)
	_samples(sim)
	_timing(sim)
	_streak(sim)
	print("forecast_test: %d failed" % fails)
	quit(1 if fails > 0 else 0)


func _samples(sim: Sim) -> void:
	var f := Forecast.compute(sim, "hydra")
	var S: Array = f.get("samples", [])
	_check(S.size() == Forecast.SAMPLES + 1, "forecast returns %d samples" % S.size())
	_check(float(f.horizon) >= Forecast.MIN_H and float(f.horizon) <= Forecast.MAX_H, "horizon %.1f h within 3–24 h" % (float(f.horizon) / 3600.0))
	var worst := 0.0
	for i in [0, 7, 21, 40, S.size() - 1]:
		worst = maxf(worst, absf(float(S[i].sun) - sim.thermal.sunlight(S[i].r, float(S[i].t))))
	_check(worst < 1e-9, "sunlight in the samples is Thermal.sunlight there (worst diff %.9f)" % worst)
	# Sample 0's position and time are the ship's now.
	_check(V.dist(S[0].r, sim.by_id.hydra.r) < 1e-6 and float(S[0].t) == sim.t, "sample 0 is the ship now")
	# The path agrees with Sim.predict_state (the same gravity model).
	var hy: Dictionary = sim.by_id.hydra
	var p := sim.gravity.coast(hy.r, hy.v, sim.t, float(S.back().t) - sim.t, 300.0)
	_check(V.dist(p[0], S.back().r) < 5.0, "the path is the sim's own coast (%.3f km off at the end)" % V.dist(p[0], S.back().r))
	# Sample 0 is the HUD's verdict (the same loop as hud.gd _heat_state).
	var snr := 0.0
	for e in Forecast.eyes(sim):
		snr = maxf(snr, float(sim.sensing.ir_look({"r": e.r_now, "cls": e.cls}, sim.by_id.hydra).snr))
	_check(absf(snr - float(S[0].snr)) <= 1e-9 * maxf(1.0, snr), "sample 0's S/N is the HUD's (%.4f vs %.4f)" % [float(S[0].snr), snr])
	# A future sample is Sensing.ir_look on the ship moved there.
	var j := 30
	var x: Dictionary = sim.by_id.hydra.duplicate()
	x.r = S[j].r
	x.heat = sim.by_id.hydra.heat.duplicate()
	x.heat.T_skin = S[j].T_skin
	x.heat.sun = S[j].sun
	x.flash_until = -1e9
	var sj := 0.0
	for e in Forecast.eyes(sim):
		sj = maxf(sj, float(sim.sensing.ir_look({"r": Forecast._track_pos(e, float(S[j].t), {}), "cls": e.cls}, x).snr))
	_check(absf(sj - float(S[j].snr)) <= 1e-9 * maxf(1.0, sj), "a future sample's S/N is Sensing.ir_look there (%.4f vs %.4f)" % [float(S[j].snr), sj])
	# Track estimates flown by Kepler's equation agree with Track.coast.
	var off := 0.0
	for e in Forecast.eyes(sim):
		for dt in [600.0, 7200.0, 20000.0]:
			var a: PackedFloat64Array = Track.coast(e.x, sim.t + dt - float(e.t))
			off = maxf(off, V.dist(V.of(a[0], a[1]), Forecast._track_pos(e, sim.t + dt, {})))
	_check(off < 0.01, "track coasts agree with Track.coast (worst %.6f km)" % off)
	# The shadow entry is where the true sunlight share falls through a half.
	var te := float(f.shadow.enter)
	if te > 0.0:
		var hy2: Dictionary = sim.by_id.hydra
		var b4 := sim.gravity.coast(hy2.r, hy2.v, sim.t, te - 30.0 - sim.t, 60.0)
		var af := sim.gravity.coast(hy2.r, hy2.v, sim.t, te + 30.0 - sim.t, 60.0)
		_check(sim.thermal.sunlight(b4[0], te - 30.0) >= 0.5 and sim.thermal.sunlight(af[0], te + 30.0) < 0.5, "shadow entry within 30 s (at +%.2f h)" % ((te - sim.t) / 3600.0))
	var lv := {}
	for smp in S:
		lv[smp.level] = int(lv.get(smp.level, 0)) + 1
	print("  levels %s · eyes %d · T %.1f–%.1f K · shadow %s · cold windows %d · next change %s" % [str(lv), int(f.eyes), float(f.T_min), float(f.T_max), str(f.shadow), f.cold.size(), str(f.next_change)])
	_check(float(f.T_max) - float(f.T_min) < 20.0, "the skin swings only a few kelvin (%.1f K)" % (float(f.T_max) - float(f.T_min)))


func _timing(sim: Sim) -> void:
	var fc := Forecast.new()
	var t0 := Time.get_ticks_usec()
	var runs := 5
	for i in runs:
		Forecast.compute(sim, "hydra")
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / runs
	print("  compute from scratch: %.2f ms (84 samples, no cache)" % ms)
	var calls := 0
	var first := 0.0
	# Close to Jupiter a sample costs more coast steps (Gravity.ETA_NEAR), so a
	# fresh path takes more calls: about 60 at 1.5 Jupiter radii, a second of frames.
	while calls < 120:
		fc.get_for(sim, "hydra")
		first = maxf(first, fc.compute_ms)
		calls += 1
		if not fc.last.partial:
			break
	print("  fresh path over %d get_for calls, worst %.2f ms" % [calls, first])
	_check(first < 15.0 and fc.last.samples.size() == Forecast.SAMPLES + 1, "a fresh path fills in over frames, each under 15 ms (%.2f ms)" % first)
	var t1 := Time.get_ticks_usec()
	fc.get_for(sim, "hydra")
	_check((Time.get_ticks_usec() - t1) / 1000.0 < 0.5, "a cached call is free")
	# Sim time moves on by a step: the recompute reuses the coasts flown.
	var worst := 0.0
	for i in 6:
		sim.advance(Sim.LOOK)
		fc._real = -1e9
		fc.get_for(sim, "hydra")
		worst = maxf(worst, fc.compute_ms)
	print("  recompute after a look (warm cache): worst %.2f ms" % worst)
	_check(worst < 15.0, "a warm recompute under 15 ms (%.2f ms)" % worst)


func _streak(sim: Sim) -> void:
	var said := []
	sim.logged.connect(func(e): if String(e.code).begins_with("ghost"): said.append(e.code))
	var id := "hydra"
	sim.by_id[id].erase("ghost")
	Forecast.update_streak(sim, id, "cold")
	var t0 := sim.t
	# Pretend time passes (the streak reads sim.t only).
	for i in 9:
		sim.t += 1800.0
		Forecast.update_streak(sim, id, "cold")
	var st := Forecast.streak(sim, id)
	_check(absf(float(st.run) - (sim.t - t0)) < 1e-6, "the streak counts cold sim time (%.1f h)" % (float(st.run) / 3600.0))
	_check(int(st.rank) == 1 and said.count("ghost_rank") == 1, "one rank reached, said once (%s)" % str(said))
	sim.t += 1800.0
	Forecast.update_streak(sim, id, "seen")
	st = Forecast.streak(sim, id)
	_check(float(st.run) == 0.0 and int(st.rank) == 0, "seen: the streak resets")
	_check(float(st.best) >= 4.4 * 3600.0, "the best is kept (%.1f h)" % (float(st.best) / 3600.0))
	_check(said.count("ghost_broken") == 1, "a long streak broken is reported once")
	sim.t = t0
