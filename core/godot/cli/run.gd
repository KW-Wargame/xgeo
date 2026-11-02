## xGEO Core's command-line front door: run a scenario with no window and
## write what happens as JSON lines, one object per line.
##   godot --headless --path godot --script res://cli/run.gd -- [options]
## Options (all optional):
##   --scenario=res://data/scenarios/close_pass_earth.json   the scenario file ("" for none)
##   --hours=24        how long to run (sim hours)
##   --step=600        seconds between snapshots (the sensor look is 600 s)
##   --seed=N          the master random seed (default: the scenario's)
##   --run=K           the run of that seed (default 0): run K of seed N is the
##                     same world everywhere; each subsystem draws from its own
##                     stream (Sim.stream), so runs 0..K-1 make a Monte Carlo set
##   --coa=path        a course of action: orders to give at set times (below)
##   --out=path        write to a file instead of standard output (a relative
##                     path is relative to the godot/ folder: Godot starts there)
##   --truth=false     also report Red's and neutrals' true states
## Lines: {"type":"start",...}, then per step {"type":"step",...} with every
## log entry since the last step, Blue's ships and Blue's tracks (the belief,
## with its 1σ ellipse, carried forward to the line's own t); a final {"type":"end",...} with the debrief. Each
## order given adds {"type":"order",...} with whether it was carried out.
## A course of action is a JSON file {"orders": [...]}: burn, intercept, match,
## effect, buoy, analyse, radar, each at its time (core/orders.gd lists them).
## t is seconds from the start; the run stops at each order's time to give it.
## Units: km, km/s, s; positions are centred on the scenario's central body
## (the Earth, in Close Pass), on axes that do not turn with it.
## Nothing here touches ui/ or scenes/: it is Core alone, as the tests run it.
extends SceneTree


func _init() -> void:
	var o := _options()
	Sim.campaign_path = o.get("scenario", Sim.campaign_path)
	var sim := Sim.new("res://data/game.json", "*", int(o.get("seed", "-1")), int(o.get("run", "0")))
	var list = Orders.read(o.coa) if o.has("coa") else []
	if list == null:
		printerr("cannot read the course of action %s" % o.coa)
		quit(1)
		return
	var orders := Orders.new(list)
	var hours := float(o.get("hours", "24"))
	var step := maxf(1.0, float(o.get("step", str(Sim.LOOK))))
	var truth: bool = o.get("truth", "false") == "true"
	var f: FileAccess = null
	if o.has("out"):
		f = FileAccess.open(o.out, FileAccess.WRITE)
		if f == null:
			printerr("cannot write %s" % o.out)
			quit(1)
			return
	var emit := func(d: Dictionary) -> void:
		var line := JSON.stringify(d)
		if f:
			f.store_line(line)
		else:
			print(line)
	emit.call({"type": "start", "engine": "xGEO Core", "scenario": Sim.campaign_path, "name": sim.camp.get("name", ""),
		"seed": sim.master_seed, "run": sim.run, "orders": list.size(), "utc": Time.get_datetime_string_from_unix_time(int(float(sim.data.startUtc) / 1000.0)) + "Z",
		"hours": hours, "step": step, "units": {"distance": "km", "speed": "km/s", "time": "s"}})
	var seen := sim.log.size()
	var end_t := hours * Sim.HOUR
	var next_snap := minf(step, end_t)
	while sim.t < end_t - 1e-6 and not sim.campaign.over:
		for r in orders.due(sim):
			emit.call(r)
		var stop := minf(next_snap, orders.next_t())
		sim.advance(maxf(stop - sim.t, 0.0))
		if sim.t >= next_snap - 1e-6 or sim.campaign.over:
			emit.call(_snapshot(sim, sim.log.slice(seen), truth))
			seen = sim.log.size()
			next_snap = minf(next_snap + step, end_t)
	var dbf := sim.campaign.debrief() if not sim.camp.is_empty() else {}
	emit.call({"type": "end", "t": sim.t, "over": sim.campaign.over, "result": sim.campaign.result, "debrief": JSON.parse_string(JSON.stringify(dbf))})
	if f:
		f.close()
	quit(0)


func _snapshot(sim: Sim, new_log: Array, truth: bool) -> Dictionary:
	var ships := []
	for s in sim.ships:
		if s.side != "blue" and not truth:
			continue
		ships.append({"id": s.id, "name": s.get("name", s.id), "side": s.side, "class": s.classId, "alive": s.alive,
			"r": _v(s.r), "v": _v(s.v), "delta_v": sim.delta_v(s.id)})
	var tracks := []
	for id in sim.tracks:
		var tr: Track = sim.tracks[id]
		# The estimate stands at its last look; coast it to now, as the map does,
		# so it lines up with the ships beside it.
		var now := tr.forecast(sim.t) if tr.t < sim.t else tr
		var e := now.ellipse()
		var d := {"label": tr.label, "ident": tr.ident, "side": tr.side, "class": tr.class_id, "in_contact": tr.in_contact,
			"last_seen": tr.last_seen, "r": _v(now.pos()), "v": _v(now.vel()),
			"sigma_km": {"major": e.major, "minor": e.minor, "angle": e.angle}}
		if truth:
			d.truth = id
		tracks.append(d)
	var log := []
	for e in new_log:
		log.append({"t": e.t, "code": e.code, "kind": e.kind, "text": e.text})
	return {"type": "step", "t": sim.t, "utc": Time.get_datetime_string_from_unix_time(int(sim.utc_ms() / 1000.0)) + "Z",
		"escalation": sim.escalation, "ships": ships, "tracks": tracks, "log": log}


static func _v(a: PackedFloat64Array) -> Array:
	return Array(a)


static func _options() -> Dictionary:
	var o := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var i := a.find("=")
			o[a.substr(2, i - 2)] = a.substr(i + 1)
	return o
