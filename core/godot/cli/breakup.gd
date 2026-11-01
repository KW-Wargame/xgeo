## xGEO Core's breakup draws, for checking the model from outside Godot.
##   godot --headless --path godot --script res://cli/breakup.gd -- --cases=in.json --out=out.json
## in.json: {"sample": [{kind, size, body, lc_min, lc_max, k, seed}, ...],
##           "density": [{states: [[r, v], ...], w, edges, mu}, ...]}
## out.json: {"sample": [Breakup.sample(...), ...], "density": [[...], ...]}
extends SceneTree


func _init() -> void:
	var o := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		o[kv[0]] = kv[1] if kv.size() > 1 else ""
	var cases = JSON.parse_string(FileAccess.get_file_as_string(String(o.get("cases", ""))))
	if not cases is Dictionary:
		printerr("cannot read --cases")
		quit(1)
		return
	var out := {"sample": [], "density": []}
	for c in cases.get("sample", []):
		var rng := RandomNumberGenerator.new()
		rng.seed = int(c.seed)
		var s := Breakup.sample(String(c.kind), float(c.size), String(c.body), float(c.lc_min), float(c.lc_max), int(c.k), rng)
		for key in ["lc", "am", "area", "mass", "dv"]:
			s[key] = Array(s[key])
		out.sample.append(s)
	for c in cases.get("density", []):
		var states := []
		for x in c.states:
			states.append([PackedFloat64Array(x[0]), PackedFloat64Array(x[1])])
		out.density.append(Array(Breakup.spatial_density(states, PackedFloat64Array(c.w), PackedFloat64Array(c.edges), float(c.mu))))
	var f := FileAccess.open(String(o.get("out", "")), FileAccess.WRITE)
	if f == null:
		printerr("cannot write --out")
		quit(1)
		return
	f.store_string(JSON.stringify(out, "", false, true))
	f.close()
	quit(0)
