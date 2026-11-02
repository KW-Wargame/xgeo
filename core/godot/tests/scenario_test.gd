## The end-to-end check of xGEO Core, on the TEST RANGE scenario
## (data/examples/test_range.json), headless, Core alone:
##   godot --headless --path godot --script res://tests/scenario_test.gd
## Where run_tests checks each model against its reference, this plays one
## world through every part of Core and checks that the parts agree:
## 1. The scenario loads: every ship, the station on its moon, the civil
##    emitter, the opening track.
## 2. Determinism: the same seed gives the same world; another seed does not.
## 3. Two days of flight stay physical: finite, outside Jupiter, orbits kept.
## 4. Sensing: bursts heard, classified, direction-found by two ears; the
##    track on the inspector stays honest (truth inside its own 4σ); Jupiter
##    hides the far ship.
## 5. Manoeuvre planning: a planned and refined transfer arrives.
## 6. Effects against their formulas: jam, dazzle (and the laser's heat), HPM,
##    Pk; each used once, each paid for in escalation.
## 7. A kill vehicle hits: the target breaks up, the debris objective fails.
## 8. The campaign: objectives, the end of the operation, the debrief.
## 9. Save and load give back the same world; the command-line runner writes
##    well-formed JSON lines; a finished world is freed.
## 10. Random streams: each subsystem's seed is SHA-256 of seed, run and name
##    (checked against Python's hashlib); drawing from one stream leaves the
##    others alone; another run of a seed is another world.
## 11. A course of action: the runner gives timed orders, reports which were
##    carried out and why not, changes the outcome, and replays byte for byte.
## 12. Real time: a sim second is a second of UTC; a ship turns at its real
##    orbital rate with J2 and Io at its real period. A scenario may compress
##    its story, never the clock or the physics.
## 13. A world's central body: Jupiter unless the world says otherwise (the
##    frame's origin, so the Sun is where ephem.gd puts it); a world about
##    Earth has Earth at its origin and Jupiter where the ephemeris puts it
##    from Earth. Sim.make() makes a plain world unless a layer sets a maker.
## Thresholds are design values for a test, chosen with margin over what the
## models give; each is stated where it is checked.
extends SceneTree

const RANGE := "res://data/examples/test_range.json"
var fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok    " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _world(seed_ := -1, run := 0) -> Sim:
	return Sim.new("res://data/game.json", RANGE, seed_, run)


## The runner on TEST RANGE: [exit code, its lines parsed, the raw text].
func _run(args: Array) -> Array:
	var out := OS.get_user_data_dir().path_join("scenario_test.jsonl")
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://cli/run.gd", "--",
		"--scenario=" + RANGE, "--out=" + out] + args)
	var text := FileAccess.get_file_as_string(out) if FileAccess.file_exists(out) else ""
	DirAccess.remove_absolute(out)
	var lines := text.strip_edges().split("\n") if text != "" else PackedStringArray()
	return [code, Array(lines).map(func(l): return JSON.parse_string(l)), text]


## The batch runner on TEST RANGE: [exit code, its lines parsed].
func _batch(args: Array) -> Array:
	var out := OS.get_user_data_dir().path_join("scenario_batch.jsonl")
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://cli/batch.gd", "--",
		"--scenario=" + RANGE, "--out=" + out] + args)
	var text := FileAccess.get_file_as_string(out) if FileAccess.file_exists(out) else ""
	DirAccess.remove_absolute(out)
	return [code, Array(text.strip_edges().split("\n")).map(func(l): return JSON.parse_string(l)) if text != "" else []]


## Put a ship beside another (offset km along its track, same velocity).
func _beside(sim: Sim, id: String, of: String, along_km: float) -> void:
	var o: Dictionary = sim.by_id[of]
	var u := V.scale(o.v, 1.0 / V.norm(o.v))
	sim.by_id[id].r = V.add(o.r, V.scale(u, along_km))
	sim.by_id[id].v = o.v.duplicate()


## A tight hostile track on a Red ship: what a good fix would give.
func _tight(sim: Sim, id: String) -> void:
	var h: Dictionary = sim.by_id[id]
	var tr := Track.new(id, "TRK %s" % h.short, PackedFloat64Array([h.r[0], h.r[1], h.v[0], h.v[1]]), Track.diag([0.5 ** 2, 0.5 ** 2, 0.001 ** 2, 0.001 ** 2]), sim.t)
	tr.side = "hostile"
	tr.ident = "classified"
	tr.class_id = h.classId
	sim.tracks[id] = tr


func _fingerprint(sim: Sim) -> String:
	var parts := []
	for s in sim.ships:
		parts.append("%s %.9f %.9f" % [s.id, s.r[0], s.r[1]])
	# By id: a loaded save gives the tracks back in another order, the same tracks.
	# (as plain strings: the opening track's key is a StringName, which sorts apart)
	var ids := sim.tracks.keys().map(func(k): return String(k))
	ids.sort()
	for id in ids:
		parts.append("%s %.6f %.6f" % [id, sim.tracks[id].x[0], sim.tracks[id].x[1]])
	parts.append(str(sim.log.map(func(e): return e.text)))
	return "\n".join(parts)


func _init() -> void:
	# 1. It loads.
	var sim := _world()
	for id in ["pelican", "lancer", "excal", "gstn", "h1", "h2", "c1"]:
		_check(sim.by_id.has(id), "%s is in the world" % id)
	var g: Array = sim.moon_state("ganymede", sim.t)
	_check(V.dist(sim.by_id.gstn.r, g[0]) < 1e-6, "Ganymede Station rides its moon")
	_check(sim.tracks.has("h1") and sim.tracks.h1.side != "neutral", "the opening track on the inspector is held")
	_check(sim.camp.name == "TEST RANGE" and sim.effects.cfg.has("jam"), "the scenario's effects block is read")

	# 2. Determinism.
	var a := _world()
	var b := _world()
	var c := _world(1)
	for w in [a, b, c]:
		w.advance(6.0 * Sim.HOUR)
	_check(_fingerprint(a) == _fingerprint(b), "the same seed gives the same world after 6 h, to the last digit")
	_check(_fingerprint(a) != _fingerprint(c), "another seed gives another world")
	a = null
	b = null
	c = null

	# 3-4. Two days of flight, the inspector's track watched as it goes.
	var R_J := float(sim.data.jupiter.radius)
	var r0 := V.norm(sim.by_id.pelican.r)
	var worst_sig := 0.0
	var worst_err := 0.0
	var finite := true
	var outside := true
	for i in 48:
		sim.advance(Sim.HOUR)
		for s in sim.ships:
			if not s.alive:
				continue
			finite = finite and is_finite(s.r[0]) and is_finite(s.r[1]) and is_finite(s.v[0]) and is_finite(s.v[1])
			outside = outside and V.norm(s.r) > R_J
		if sim.tracks.has("h1"):
			var tr: Track = sim.tracks.h1.forecast(sim.t)
			var err := V.dist(tr.pos(), sim.by_id.h1.r)
			var sig := maxf(tr.ellipse().major, 1e-9)
			if err / sig > worst_err / maxf(worst_sig, 1e-9):
				worst_err = err
				worst_sig = sig
	_check(finite, "every state stays finite over two days")
	_check(outside, "nothing falls inside Jupiter (%.0f km)" % R_J)
	# The weather satellite flies no manoeuvres: the moons and J2 move it, by far less than 2% in radius.
	_check(absf(V.norm(sim.by_id.pelican.r) / r0 - 1.0) < 0.02, "an unmanoeuvred orbit keeps its size (%.3f%%)" % (100.0 * absf(V.norm(sim.by_id.pelican.r) / r0 - 1.0)))
	# Track honesty: the truth inside 4σ of the belief, worst case over 48 looks (design threshold).
	_check(worst_sig > 0.0 and worst_err <= 4.0 * worst_sig, "the inspector's track stays honest: at worst %.3f km off at 1σ %.3f km" % [worst_err, worst_sig])

	print("  %d intercepts in two days" % sim.intercepts.size())
	_check(sim.intercepts.size() > 0, "bursts are heard")
	var two_ears := sim.intercepts.filter(func(r): return r.heard_by.size() >= 2)
	_check(not two_ears.is_empty(), "some bursts are heard by two ears (needed to fix a position)")
	if not two_ears.is_empty():
		# Fresh enough to direction-find: hear one now.
		var fresh := sim.intercepts.filter(func(r): return r.heard_by.size() >= 2 and not r.df and sim.t - float(r.end) <= float(sim.data.cfg.radio.recordSeconds))
		if fresh.is_empty():
			print("  (no unfixed two-ear burst inside the recording window at the end; DF checked on a new run)")
			var d := _world()
			while d.t < 2.0 * Sim.DAY and not d.intercepts.any(func(r): return r.heard_by.size() >= 2):
				d.advance(600.0)
			fresh = d.intercepts.filter(func(r): return r.heard_by.size() >= 2)
			_check(not fresh.is_empty() and d.sensing.df(fresh[0].id) >= 2, "direction-finding draws one line per ear")
		else:
			_check(sim.sensing.df(fresh[0].id) >= 2, "direction-finding draws one line per ear")
	var classified := sim.intercepts.any(func(r): return r.classified) or sim.intercepts.any(func(r): return sim.sensing.classify(r.id))
	_check(classified, "a strong burst is classified by its modulation")

	# Occultation: h2 sits on the far side of Jupiter from the Blue ships at the start.
	var o := _world()
	_check(o.sensing.occulted(o.by_id.lancer.r, o.by_id.h2.r), "Jupiter hides the far ship from LANCER")
	_check(not o.sensing.occulted(o.by_id.lancer.r, o.by_id.pelican.r), "and does not hide PELICAN-3, on the same side")

	# 5. Planning: a 90-minute transfer to the weather satellite (a third of an
	# orbit: single-revolution Lambert), refined, arrives (truth: it is ours).
	var p := _world()
	var plan := p.plan_intercept("lancer", "pelican", 1.5 * Sim.HOUR, true)
	_check(plan.get("ok", false), "a 90 min transfer to PELICAN-3 is planned (%.1f m/s)" % (float(plan.get("dv", 0.0)) * 1000.0))
	_check(p.execute(plan), "and flown")
	p.advance(1.5 * Sim.HOUR)
	var miss := p.range_km("lancer", "pelican")
	# 50 km: design threshold, as run_tests uses for an intercept.
	_check(miss < 50.0, "it arrives within 50 km (%.2f km)" % miss)

	# 6. Effects, against their own formulas.
	var e := _world()
	var cfg := e.effects.cfg
	var hr := e.effects.hpm_range_km()
	var hr_ref := sqrt(30.0 * float(cfg.hpm.peakW) * pow(10.0, float(cfg.hpm.gainDbi) / 10.0)) / float(cfg.hpm.upsetVm) / 1000.0
	_check(absf(hr / hr_ref - 1.0) < 1e-9, "HPM reach is √(30PG)/E: %.2f km" % hr)
	_check(absf(Effects.kill_probability(1.0, 1.0, 0.9) - 0.9 * (1.0 - exp(-0.5))) < 1e-12, "Pk is the Rayleigh CDF times reliability")
	var w := e.effects.laser(e.by_id.excal)
	_check(not w.is_empty(), "EXCALIBUR carries a laser")
	if not w.is_empty():
		var dz := e.effects.dazzle_range_km(w)
		_check(absf(e.effects.irradiance(w, dz) / float(cfg.dazzle.saturationWm2) - 1.0) < 0.01, "at the dazzle reach (%.0f km) the irradiance is the saturation level" % dz)
		_check(e.effects.irradiance(w, dz / 2.0) > e.effects.irradiance(w, dz), "closer is brighter")
	var jr := e.effects.jam_range_km(e.by_id.lancer, e.by_id.h1, float(cfg.jam.needJsDb))
	_check(jr > 0.0 and is_finite(jr), "LANCER's jammer has a reach on the inspector's link (%.0f km)" % jr)

	# Used: LANCER and EXCALIBUR beside the inspector with a tight track.
	_tight(e, "h1")
	_beside(e, "lancer", "h1", -minf(20.0, hr * 0.5))
	_beside(e, "excal", "h1", -30.0)
	var esc0 := e.escalation
	_check(e.effects.use("jam", "lancer", "h1"), "jam: on")
	e.advance(Sim.HOUR)
	_check(e.escalation > esc0, "jamming costs escalation by the hour (+%.1f)" % (e.escalation - esc0))
	_check(e.effects.use("jam", "lancer", "h1") and not e.effects.jamming.has("lancer"), "jam: off again")
	_tight(e, "h1")
	_beside(e, "excal", "h1", -30.0)
	var heat0 := float(e.by_id.excal.get("heat", {}).get("Q", 0.0))
	var dazzled := e.effects.use("dazzle", "excal", "h1")
	_check(dazzled, "dazzle from EXCALIBUR at 30 km")
	if dazzled:
		_check(float(e.by_id.h1.dazzled_until) > e.t, "the inspector is blind until %.1f h" % ((float(e.by_id.h1.dazzled_until) - e.t) / Sim.HOUR))
		e.advance(600.0)
		_check(float(e.by_id.excal.get("heat", {}).get("Q", 0.0)) > heat0, "the laser's waste heat reaches the radiators (Q %.0f → %.0f W)" % [heat0, float(e.by_id.excal.get("heat", {}).get("Q", 0.0))])
	_tight(e, "h1")
	_beside(e, "lancer", "h1", -minf(20.0, hr * 0.5))
	var esc1 := e.escalation
	_check(e.effects.use("hpm", "lancer", "h1") and e.by_id.h1.get("disabled", false), "HPM inside its reach disables the inspector")
	_check(absf(e.escalation - esc1 - float(cfg.hpm.escalation)) < 1e-9, "and costs its escalation (+%.0f)" % float(cfg.hpm.escalation))
	_check(e.campaign.neutralized(e.by_id.h1), "a disabled inspector counts as out of the fight")
	var h: Dictionary = e.by_id.h1
	_check(not e.effects.use("hpm", "pelican", "h1"), "a ship without the payload cannot fire it")

	# The burning engine shows in the IR: the thermal model's plume term.
	var lancer: Dictionary = e.by_id.lancer
	var toward := V.scale(lancer.r, -1.0)
	_check(float(e.thermal.intensity(lancer, toward, true).total) > float(e.thermal.intensity(lancer, toward, false).total), "a burning engine is brighter in the IR")

	# 7. Kill vehicles. On the 0.5 t inspector, from 3,000 km behind it: a catastrophic breakup.
	var k := _world()
	_beside(k, "lancer", "h1", -3000.0)
	_tight(k, "h1")
	_check(k.effects.use("kinetic", "lancer", "h1"), "a kill vehicle is fired at the inspector")
	var kv: Dictionary = k.effects.kvs.back()
	var t0 := k.t
	while not kv.done and k.t - t0 < 4.0 * Sim.HOUR:
		k.advance(60.0)
	_check(kv.result == "hit", "it hits (miss %.1f m)" % (float(kv.get("miss_km", -1.0)) * 1000.0))
	_check(not k.by_id.h1.alive and k.debris.size() == 1 and k.debris[0].cat, "the inspector breaks up into one debris cloud")
	# On the 60 t tender the same hit is not catastrophic (EMR under 40 J/g): cratered, still flying.
	var k2 := _world()
	_beside(k2, "lancer", "h2", -3000.0)
	_tight(k2, "h2")
	k2.effects.use("kinetic", "lancer", "h2")
	var kv2: Dictionary = k2.effects.kvs.back()
	while not kv2.done and k2.t - t0 < 4.0 * Sim.HOUR:
		k2.advance(60.0)
	_check(kv2.result == "hit" and k2.by_id.h2.alive and not k2.by_id.h2.get("damage", []).is_empty(), "on the 60 t tender it craters, not breaks up (lost: %s)" % Damage.describe(k2.by_id.h2.get("damage", [])))
	var deb := k.campaign.status().filter(func(x): return x.id == "debris")
	_check(not deb.is_empty() and deb[0].state == "failed", "the debris objective is failed")

	# 8. The campaign: every objective reported; the operation ends on time with a debrief.
	var st := sim.campaign.status()
	_check(st.size() == sim.camp.objectives.size(), "every objective has a state")
	_check(st.all(func(x): return x.state in ["open", "done", "failed"]), "states are open, done or failed")
	sim.campaign.check()
	_check(sim.campaign.over, "after two days the operation is over (%s: %s)" % [sim.campaign.result, sim.campaign.why])
	var db := sim.campaign.debrief()
	_check(db.has("result") and db.objectives.size() == st.size() and is_finite(float(db.days)), "the debrief reports result, objectives and days (%s, %.1f d)" % [db.result, float(db.days)])

	# 9. Save and load (the player's own save file is kept aside and put back).
	var keep := FileAccess.get_file_as_string(SaveGame.PATH) if FileAccess.file_exists(SaveGame.PATH) else ""
	SaveGame.save(sim)
	var back := _world()
	_check(SaveGame.load_into(back), "the save loads")
	_check(_fingerprint(back) == _fingerprint(sim), "into the same world, to the last digit")
	back.advance(Sim.HOUR)
	sim.advance(Sim.HOUR)
	_check(_fingerprint(back) == _fingerprint(sim), "and the two run on alike")
	# A save from before the random streams: one generator, its state an int.
	SaveGame.save(sim)
	var old: Dictionary = bytes_to_var(FileAccess.get_file_as_bytes(SaveGame.PATH))
	old.rng = 12345
	old.erase("seed")
	old.erase("run")
	FileAccess.open(SaveGame.PATH, FileAccess.WRITE).store_buffer(var_to_bytes(old))
	var older := _world()
	_check(SaveGame.load_into(older) and _fingerprint(older) == _fingerprint(sim), "a save from before the streams still loads, into the same world")
	older = null
	if keep != "":
		FileAccess.open(SaveGame.PATH, FileAccess.WRITE).store_string(keep)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.PATH))

	# The command-line runner on this scenario.
	var plain := _run(["--hours=3", "--step=600"])
	var parsed: Array = plain[1]
	_check(plain[0] == 0 and parsed.size() == 20, "the runner exits cleanly with start, 18 steps and end (%d lines)" % parsed.size())
	_check(parsed.all(func(x): return x is Dictionary), "every line is a JSON object")
	if parsed.size() >= 2 and parsed[0] is Dictionary and parsed.back() is Dictionary:
		_check(parsed[0].type == "start" and parsed[0].name == "TEST RANGE" and parsed.back().type == "end", "it starts with the scenario's name and ends with a debrief")

	# 10. Random streams. The seeds against Python: hashlib.sha256(b"xgeo/4417/0/setup").hexdigest()[:15].
	_check(Sim.stream_seed(4417, 0, "setup") == 0xf40a3220fb5b489 and Sim.stream_seed(4417, 0, "sensing") == 0xc5a7b235956e3de,
		"stream seeds are SHA-256 of seed, run and name (FIPS 180-4, as Python's hashlib gives)")
	var s1 := _world()
	var s2 := _world()
	for i in 1000:
		s2.stream("traffic").randf()
	var same := true
	for name in ["setup", "sensing", "effects", "breakup", "red"]:
		same = same and s1.stream(name).randf() == s2.stream(name).randf()
	_check(same, "a thousand extra draws on one stream leave every other stream's next draw unchanged")
	var run0 := _world(-1, 0)
	var run1 := _world(-1, 1)
	run0.advance(6.0 * Sim.HOUR)
	run1.advance(6.0 * Sim.HOUR)
	_check(_fingerprint(run0) != _fingerprint(run1), "run 1 of a seed is another world than run 0")
	s1 = null
	s2 = null
	run0 = null
	run1 = null

	# 11. A course of action (data/examples/test_range_coa.json).
	var coa := ["--hours=3", "--step=600", "--coa=res://data/examples/test_range_coa.json"]
	var ca := _run(coa)
	var cb := _run(coa)
	var given: Array = ca[1].filter(func(x): return x is Dictionary and x.type == "order")
	var did := given.map(func(x): return "%s %s" % [x.order.do, "ok" if x.ok else "refused"])
	_check(ca[0] == 0 and did == ["intercept ok", "effect refused", "burn ok", "buoy refused", "burn refused"], "every order is reported, carried out or refused (%s)" % ", ".join(did))
	_check(given.size() == 5 and given[1].why != "" and String(given[4].why).contains("Blue"), "a refusal says why: the rules of engagement, a Red ship")
	_check(given.size() == 5 and given[0].t == 1800.0 and given[2].t == 5400.0, "each order is given at its time")
	_check(ca[1].size() == 25 and ca[1].back().type == "end", "snapshots still come every step around the orders (%d lines)" % ca[1].size())
	var last_ships := func(lines: Array) -> String:
		var snaps: Array = lines.filter(func(x): return x is Dictionary and x.type == "step")
		return JSON.stringify(snaps.back().ships) if not snaps.is_empty() else ""
	_check(last_ships.call(ca[1]) != last_ships.call(plain[1]), "the course of action changes the outcome")
	_check(ca[2] != "" and ca[2] == cb[2], "the same seed, run and orders replay byte for byte")

	# 11b. The other orders, given directly (core/orders.gd).
	var ow := _world()
	_check(Orders.give(ow, {"do": "analyse"}).ok and ow.sensing.auto, "analyse turns on the analysis of every burst heard")
	_check(Orders.give(ow, {"do": "radar", "ship": "lancer", "on": true}).ok and ow.effects.radar_on.get("lancer", false), "radar makes a ship radiate")
	_check(not Orders.give(ow, {"do": "radar", "ship": "pelican"}).ok, "radar is refused to a ship without one")
	_beside(ow, "lancer", "h1", 30.0)
	ow.by_id.lancer.v = V.add(ow.by_id.lancer.v, V.of(0.01, -0.02, 0.0))
	var m := Orders.give(ow, {"do": "match", "ship": "lancer", "target": "h1"})
	var tv: Array = Orders._seen(ow, "h1")
	_check(m.ok and V.dist(ow.by_id.lancer.v, ow.station_v(ow.by_id.lancer.r, tv[0], tv[1])) < 1e-9, "match flies the velocity that keeps it alongside the track")
	ow = _world() # not analysing: the inspector stays unidentified, so the jam stays refused
	var q := Orders.new([{"t": 0, "until": 1200, "do": "effect", "effect": "jam", "ship": "excal", "target": "h1"}])
	while q.next_t() < INF:
		q.due(ow)
		ow.advance(maxf(q.next_t() - ow.t, 0.0) if q.next_t() < INF else 0.0)
	_check(q.reports.size() == 1 and not q.reports[0].ok and q.reports[0].tries == 3, "an order with until is tried every look and given up after (%d tries)" % (q.reports[0].tries if q.reports.size() == 1 else -1))
	ow = null

	# 11c. The batch runner (cli/batch.gd): runs in order, common random
	# numbers, and the same lines from one process or from two.
	var both := _batch(["--coa=none,none", "--runs=2", "--hours=4"])
	var rows: Array = both[1].filter(func(x): return x is Dictionary and x.type == "run")
	_check(both[0] == 0 and both[1][0].type == "batch" and rows.map(func(x): return int(x.run)) == [0, 0, 1, 1], "the batch runner writes a header and each run for each course of action, in order")
	_check(rows.size() == 4 and JSON.stringify(rows[0]) == JSON.stringify(rows[1]) and JSON.stringify(rows[2]) == JSON.stringify(rows[3]), "common random numbers: the same run of two identical courses of action ends identically")
	var part0 := _batch(["--coa=none,none", "--runs=0-0", "--hours=4"])
	var part1 := _batch(["--coa=none,none", "--runs=1-1", "--hours=4"])
	var joined: Array = part0[1].filter(func(x): return x is Dictionary and x.type == "run") + part1[1].filter(func(x): return x is Dictionary and x.type == "run")
	_check(JSON.stringify(joined) == JSON.stringify(rows), "two processes on runs 0 and 1 give the lines one process gives")

	# 11d. Settings changed without editing the file (Sim.overrides): a dotted
	# path, a list entry by its id or index, a missing key refused; then the
	# batch runner's --sample, the same draw for every course of action on run k.
	var dd := {"ships": [{"id": "a", "orbit": {"radius_km": 1.0}}, {"id": "b"}]}
	_check(Sim.set_setting(dd, "ships.a.orbit.radius_km", 2.0) == "" and dd.ships[0].orbit.radius_km == 2.0, "a setting is reached by a dotted path and a list entry's id")
	_check(Sim.set_setting(dd, "ships.1.side", "red") == "" and dd.ships[1].side == "red", "a list entry is reached by its index")
	_check(Sim.set_setting(dd, "ships.c.side", "red") != "" and Sim.set_setting(dd, "nope.x", 1) != "", "a path to nothing is refused")
	Sim.overrides = {"ships.pelican.orbit.radius_km": 100000.0}
	var moved := _world()
	Sim.overrides = {}
	_check(absf(V.norm(moved.by_id.pelican.r) - 100000.0) < 1.0 and absf(V.norm(_world().by_id.pelican.r) - 92940.0) < 1.0, "an override changes the world it is set for, and only that one")
	Sim.overrides = {"escalation.war": 90}
	var kept: Dictionary = SaveGame.state_of(_world()).get("overrides", {})
	Sim.overrides = {}
	_check(kept == {"escalation.war": 90} and Sim.get_setting({"a": [{"id": "b", "c": 3}]}, "a.b.c") == 3 and Sim.get_setting({}, "a.b") == null, "a save keeps the edits its world was built with; a setting reads back by its path")
	var drawn := _batch(["--coa=none,none", "--runs=2", "--hours=1", "--sample=escalation.war=90.0..100.0;escalation.spare=1..3"])
	var srows: Array = drawn[1].filter(func(x): return x is Dictionary and x.type == "run")
	_check(drawn[0] == 0 and srows.size() == 4 and JSON.stringify(srows[0].sampled) == JSON.stringify(srows[1].sampled) and JSON.stringify(srows[0].sampled) != JSON.stringify(srows[2].sampled), "--sample draws per run, the same for every course of action")
	_check(srows.all(func(x): return x.sampled["escalation.war"] >= 90.0 and x.sampled["escalation.war"] <= 100.0 and x.sampled["escalation.spare"] in [1, 2, 3, 1.0, 2.0, 3.0]), "sampled settings stay inside their bounds, whole numbers when both bounds are")

	# 11e. A study (core/study.gd): its statistics against published values,
	# then a real one across processes, merged in run order.
	var wil := Study.share(8, 10)
	_check(absf(wil.lo - 0.4902) < 1e-4 and absf(wil.hi - 0.9433) < 1e-4, "Wilson's interval for 8 of 10 is 0.490 to 0.943 (Newcombe 1998, method 3)")
	_check(absf(Study.t975(10) - 2.2281) < 1e-3 and absf(Study.t975(30) - 2.0423) < 1e-4, "Student's t, 95% two-sided: 2.228 at 10 df, 2.042 at 30")
	var mc := Study.mean_ci([1.0, 2.0, 3.0, 4.0, 5.0])
	_check(absf(mc.mean - 3.0) < 1e-12 and absf(mc.hi - mc.mean - 2.7764 * sqrt(2.5) / sqrt(5.0)) < 2e-3, "a mean's 95% interval is t·s/√n")
	_check(absf(Study.spearman([1, 2, 3, 4], [10, 20, 40, 30]) - 0.8) < 1e-12 and absf(Study.spearman([1, 2, 2, 3], [1, 2, 3, 4]) - 0.9487) < 1e-4, "Spearman's rank correlation, with ties sharing their rank")
	var stu := Study.from_file("res://data/examples/test_range_study.json")
	stu.runs = 4
	stu.hours = 2.0
	stu.dir = OS.get_user_data_dir().path_join("scenario_study")
	var started := stu.start(2)
	var waited := 0
	while stu.running() and waited < 120000:
		OS.delay_msec(100)
		waited += 100
	_check(started and stu.finish() and stu.rows.size() == 8 and stu.rows.map(func(r): return int(r.run)) == [0, 0, 1, 1, 2, 2, 3, 3], "a study on two processes comes back whole, in run order")
	_check(stu.summary.size() == 2 and stu.summary[0].n == 4 and stu.summary[1].score_vs_first != null and FileAccess.get_file_as_string(stu.dir.path_join("runs.csv")).count("\n") == 9, "it summarises each course of action and writes a row per run")
	for f in DirAccess.get_files_at(stu.dir):
		DirAccess.remove_absolute(stu.dir.path_join(f))
	DirAccess.remove_absolute(stu.dir)

	# 12. Real time. A scenario may compress its story (CLOSE PASS: weeks into
	# days, by shorter holds and quicker hops paid for in real Δv); the clock and
	# the physics never are: one sim second is one second of UTC and of orbit.
	var rt := _world()
	var u0 := rt.utc_ms()
	var p0: PackedFloat64Array = rt.by_id.pelican.r
	var io0: PackedFloat64Array = rt.moon_state("io", rt.t)[0]
	rt.advance(6.0 * Sim.HOUR)
	_check(rt.utc_ms() - u0 == 6.0 * Sim.HOUR * 1000.0, "six sim hours are six hours of UTC")
	var p1: PackedFloat64Array = rt.by_id.pelican.r
	var turned := absf(atan2(p0[0] * p1[1] - p0[1] * p1[0], V.dot(p0, p1)))
	var a_p := V.norm(p0)
	# A circular equatorial orbit's rate with J2: ω² = μ/a³ (1 + 3/2 J2 (R/a)²) (Vallado 2013, §8.6, the radial J2 term).
	var w_j2 := sqrt(rt.mu / (a_p * a_p * a_p) * (1.0 + 1.5 * Gravity.J2 * pow(Gravity.R_REF / a_p, 2.0)))
	var kepler_turn := absf(fposmod(w_j2 * 6.0 * Sim.HOUR + PI, TAU) - PI)
	# 0.5%: a design value for a test, above what the moons and a slight eccentricity add in six hours.
	_check(absf(turned - kepler_turn) < 0.005 * kepler_turn, "a ship turns through its real orbital rate √(μ/a³ (1 + 3/2 J2 (R/a)²)) (%.4f rad, expected %.4f)" % [turned, kepler_turn])
	var io1: PackedFloat64Array = rt.moon_state("io", rt.t)[0]
	var io_turn := absf(atan2(io0[0] * io1[1] - io0[1] * io1[0], V.dot(io0, io1)))
	# Io's sidereal period, 1.769138 d (JPL Solar System Dynamics, planetary satellite mean elements).
	_check(absf(io_turn - TAU * 6.0 / (1.769138 * 24.0)) < 0.01, "Io moves at its real rate (%.4f rad in 6 h)" % io_turn)
	rt = null

	# A finished world is freed (no reference cycles keep it).
	var wr: WeakRef = weakref(sim)
	sim = null
	e = null
	k = null
	k2 = null
	p = null
	o = null
	back = null
	h = {}
	lancer = {}
	kv = {}
	kv2 = {}
	_check(wr.get_ref() == null, "a finished world is freed")

	# 13. The central body.
	var cw := _world()
	var cms := cw.utc_ms()
	_check(cw.central == "jupiter" and V.norm(cw.body_pos("jupiter")) == 0.0 and V.norm(V.sub(cw.body_pos("sun"), Ephem.pos("sun", cms))) == 0.0,
			"a world is about Jupiter unless it says otherwise: the Sun where ephem.gd puts it")
	cw.central = "earth"
	var cj := cw.body_pos("jupiter")
	var cwant := V.scale(Ephem.pos("earth", cms), -1.0)
	_check(V.norm(cw.body_pos("earth")) == 0.0 and V.norm(V.sub(cj, cwant)) < 1e-6 * V.norm(cwant),
			"a world about Earth: Earth at its origin, Jupiter %.3f AU from it" % (V.norm(cj) / Ephem.AU_KM))
	_check(cw.central_radius() == float(Ephem.BODY.earth.re), "a world about Earth: its central radius is Earth's")
	_check(Sim.make() is Sim and not Sim.maker.is_valid(), "Sim.make() makes a plain world with no maker set")
	cw = null

	print("%d failed" % fails)
	quit(1 if fails > 0 else 0)
