## xGEO Core's batch runner: many runs of a scenario for each course of action,
## one JSON line of outcomes per run, for Monte Carlo and course-of-action
## comparison.
##   godot --headless --path godot --script res://cli/batch.gd -- --coa=a.json,b.json [options]
## Options:
##   --coa=a.json,b.json  the courses of action, comma-separated (core/orders.gd);
##                        "none" plays one with no orders
##   --runs=20            runs 0..19 of the seed; or a range, --runs=20-39, so
##                        several processes can share a batch
##   --scenario=, --seed=, --hours=72, --out=   as cli/run.gd
##   --set=red_ai.crowdKm=3;escalation.leaveAt=40
##                        fixed settings for every run (Sim.overrides: dotted
##                        paths into the scenario, "game." for game.json; each
##                        value is JSON, so 3, true, [1,2] and "text" all work)
##   --vary=red_ai.crowdKm=3|5|8
##                        one setting swept: every value is a case, played for
##                        every course of action on the same runs
##   --sample=red_ai.crowdKm=3..8;red_ai.evasions=1..3
##                        settings drawn afresh for each run, uniformly between
##                        the bounds (whole numbers if both bounds are): what we
##                        do not know about Red, spread over the runs. Run k
##                        draws the same values for every case and course of
##                        action, so the comparison stays paired
## Common random numbers: run k of a seed is the same world for every course of
## action (Sim.stream: every subsystem's stream starts from seed, run and name),
## so two courses of action meet the same opening track error, the same
## detections and the same chance draws until their own orders change what
## happens. The difference between them is then measured on paired runs, with
## far less noise than independent runs give (Law 2015, Simulation Modeling and
## Analysis, 5th ed., §11.2).
## Lines: {"type":"batch", ...} first, then one {"type":"run", case, coa, run, ...}
## per run, case and course of action, in run order. tools/study.mjs runs a
## study across all the computer's cores and writes its report.
extends SceneTree


func _init() -> void:
	quit(main())


## The whole batch, from the command line's options: 0 when done, 1 on a bad
## option. The game calls it too when started with --batch (scenes/main.gd),
## as an exported program does not run --script.
static func main() -> int:
	var o := _options()
	Sim.campaign_path = o.get("scenario", Sim.campaign_path)
	var coas := []
	for path in String(o.get("coa", "none")).split(","):
		var list = [] if path == "none" else Orders.read(path)
		if list == null:
			printerr("cannot read the course of action %s" % path)
			return 1
		coas.append({"name": path.get_file().get_basename() if path != "none" else "none", "path": path, "orders": list})
	var span := String(o.get("runs", "20")).split("-")
	var first := int(span[0]) if span.size() == 2 else 0
	var last := int(span[1]) if span.size() == 2 else int(span[0]) - 1
	var hours := float(o.get("hours", "72"))
	var fixed = _settings(String(o.get("set", "")))
	if fixed == null:
		return 1
	var sample := {}
	for part in String(o.get("sample", "")).split(";", false):
		var i := part.find("=")
		var b := part.substr(i + 1).split("..")
		if i < 1 or b.size() != 2 or not b[0].is_valid_float() or not b[1].is_valid_float():
			printerr("cannot read the sampled setting %s (path=low..high)" % part)
			return 1
		sample[part.substr(0, i)] = [b[0], b[1]]
	var cases := [{"name": "base", "set": {}}]
	if o.has("vary"):
		var i := String(o.vary).find("=")
		if i < 1:
			printerr("--vary needs path=v1|v2|...")
			return 1
		var path := String(o.vary).substr(0, i)
		cases = []
		for text in String(o.vary).substr(i + 1).split("|"):
			var v = JSON.parse_string(text)
			cases.append({"name": "%s=%s" % [path, text], "set": {path: v if v != null else text}})
	var seed := int(o.get("seed", "-1"))
	var f: FileAccess = null
	if o.has("out"):
		f = FileAccess.open(o.out, FileAccess.WRITE)
		if f == null:
			printerr("cannot write %s" % o.out)
			return 1
	var emit := func(d: Dictionary) -> void:
		var line := JSON.stringify(d)
		if f:
			f.store_line(line)
			f.flush()
		else:
			print(line)
	Sim.overrides = fixed
	var probe := Sim.new("res://data/game.json", "*", seed, first)
	var master := probe.master_seed
	emit.call({"type": "batch", "engine": "xGEO Core", "scenario": Sim.campaign_path, "name": probe.camp.get("name", ""), "seed": probe.master_seed,
		"runs": [first, last], "hours": hours, "set": fixed, "sample": sample, "cases": cases.map(func(c): return c.name),
		"coas": coas.map(func(c): return {"name": c.name, "path": c.path, "orders": c.orders.size()})})
	probe = null
	for k in range(first, last + 1):
		var drawn := {}
		for path in sample:
			var g := RandomNumberGenerator.new()
			g.seed = Sim.stream_seed(master, k, "study/" + path)
			var lo: String = sample[path][0]
			var hi: String = sample[path][1]
			drawn[path] = g.randi_range(int(lo), int(hi)) if lo.is_valid_int() and hi.is_valid_int() else g.randf_range(float(lo), float(hi))
		for cs in cases:
			Sim.overrides = (fixed as Dictionary).duplicate()
			Sim.overrides.merge(drawn, true)
			Sim.overrides.merge(cs.set, true)
			for c in coas:
				var row := play(seed, k, c, hours)
				row.case = cs.name
				row.sampled = drawn
				emit.call(row)
	if f:
		f.close()
	return 0


## One run of one course of action, to the end of the operation or of hours.
static func play(seed: int, run: int, coa: Dictionary, hours: float) -> Dictionary:
	var sim := Sim.new("res://data/game.json", "*", seed, run)
	var orders := Orders.new(coa.orders)
	var dv0 := {}
	for s in sim.blue_ships():
		if s.cls.has("engine"):
			dv0[s.id] = sim.delta_v(s.id)
	var end_t := hours * Sim.HOUR
	while sim.t < end_t - 1e-6 and not sim.campaign.over:
		orders.due(sim)
		sim.advance(maxf(minf(minf(orders.next_t(), sim.t + Sim.LOOK), end_t) - sim.t, 0.0))
	var used := 0.0
	for id in dv0:
		used += float(dv0[id]) - (sim.delta_v(id) if sim.by_id[id].alive else 0.0)
	var dbf: Dictionary = JSON.parse_string(JSON.stringify(sim.campaign.debrief())) if not sim.camp.is_empty() else {}
	var objectives := {}
	for x in dbf.get("objectives", []):
		objectives[x.id] = x.state
	var left := 0
	for r in sim.ships:
		if r.side == "red" and sim.campaign.neutralized(r):
			left += 1
	var score: Dictionary = dbf.get("score", {})
	var refused := orders.reports.filter(func(r): return not r.ok).map(func(r): return "%s at %d s: %s" % [r.order.do, int(r.t), r.why])
	return {"type": "run", "coa": coa.name, "run": run, "seed": sim.master_seed, "t_end": sim.t, "over": sim.campaign.over,
		"result": sim.campaign.result, "won": sim.campaign.result == "won", "escalation": sim.escalation, "blue_dv_used": used,
		"objectives": objectives, "reds": dbf.get("reds", []), "debris": sim.debris.size(),
		"score": score.get("total", 0.0), "score_parts": score.get("parts", []).map(func(p): return [p.id, p.got, p.of]),
		"closest_km": sim.campaign.closest_km if sim.campaign.closest_km < INF else -1.0, "closest_t": sim.campaign.closest_t,
		"custody": sim.campaign._custody(), "red_neutralized": left,
		"orders": {"given": orders.reports.size(), "ok": orders.reports.size() - refused.size(), "refused": refused}}


## "a.b=1;c=[2,3]" as {path: value}; null (and a message) if it cannot be read.
static func _settings(text: String):
	var out := {}
	for part in text.split(";", false):
		var i := part.find("=")
		if i < 1:
			printerr("cannot read the setting %s (path=value)" % part)
			return null
		var v = JSON.parse_string(part.substr(i + 1))
		out[part.substr(0, i)] = v if v != null else part.substr(i + 1)
	return out


static func _options() -> Dictionary:
	var o := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var i := a.find("=")
			o[a.substr(2, i - 2)] = a.substr(i + 1)
	return o
