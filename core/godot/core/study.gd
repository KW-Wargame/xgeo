## A study: many runs of a scenario for each course of action, spread over the
## computer's cores (one cli/batch.gd process each), then summarised. The same
## study tools/study.mjs runs from the command line, here from inside the
## program, with no other software needed.
##   var s := Study.from_file("res://data/examples/close_pass_study.json")
##   s.start()                 # then poll s.running() and s.progress()
##   s.finish()                # merge; s.summary, and runs.csv, runs.jsonl and
##                             # summary.json in s.dir
## Runs are paired: run k is the same world for every course of action (common
## random numbers, cli/batch.gd), so differences are measured on pairs.
## Intervals: Wilson's score interval for shares (Wilson 1927); Student's t for
## means and paired differences (Law 2015, Simulation Modeling and Analysis,
## 5th ed., §9.4 and §10.2); Spearman's rank correlation for what drives the
## score.
class_name Study
extends RefCounted

const Z := 1.959964

var name := "study"
var about := ""
var scenario := ""
var hours := 48.0
var runs := 20
var seed := -1
var coas: Array = ["none"] # "none" or a res:// path to a course of action
var fixed: Dictionary = {} # path -> value, for every run
var sample: Dictionary = {} # path -> [low, high], drawn afresh for each run
var dir := "" # where the results go (an absolute path)
var rows: Array = [] # every run, in run order, after finish()
var head: Dictionary = {}
var summary: Array = []
var seconds := 0.0
var error := ""
var _pids: Array = []
var _files: Array = []
var _t0 := 0


static func from_file(path: String) -> Study:
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	var s := Study.new()
	if not d is Dictionary:
		s.error = "cannot read %s" % path
		return s
	s.name = String(d.get("name", s.name))
	s.about = String(d.get("about", ""))
	s.scenario = String(d.get("scenario", ""))
	s.hours = float(d.get("hours", s.hours))
	s.runs = int(d.get("runs", s.runs))
	s.seed = int(d.get("seed", -1))
	s.coas = Array(d.get("coas", s.coas))
	s.fixed = d.get("set", {})
	s.sample = d.get("sample", {})
	return s


## A course of action's short name: its file's name without the folder.
static func coa_name(path: String) -> String:
	return "none" if path == "none" else path.get_file().get_basename()


## Start the runs: one process per core, each on its own share of the runs.
func start(jobs := -1) -> bool:
	if jobs < 1:
		jobs = maxi(1, OS.get_processor_count() - 1)
	jobs = mini(jobs, runs)
	if dir == "":
		dir = OS.get_user_data_dir().path_join("studies").path_join("%s-%s" % [name.validate_filename().replace(" ", "_"), Time.get_datetime_string_from_system().replace(":", "-")])
	DirAccess.make_dir_recursive_absolute(dir)
	var base := ["--headless"]
	if OS.has_feature("template"): # an exported program runs no --script: its main scene runs the batch
		base += ["--", "--batch"]
	else: # run from the editor or the command line: name the project
		base += ["--path", ProjectSettings.globalize_path("res://"), "--script", "res://cli/batch.gd", "--"]
	base += ["--coa=" + ",".join(coas), "--hours=%s" % hours]
	if scenario != "":
		base.append("--scenario=" + scenario)
	if seed >= 0:
		base.append("--seed=%d" % seed)
	if not fixed.is_empty():
		base.append("--set=" + ";".join(fixed.keys().map(func(k): return "%s=%s" % [k, JSON.stringify(fixed[k])])))
	if not sample.is_empty():
		base.append("--sample=" + ";".join(sample.keys().map(func(k): return "%s=%s..%s" % [k, _num(sample[k][0]), _num(sample[k][1])])))
	_pids.clear()
	_files.clear()
	_t0 = Time.get_ticks_msec()
	for j in jobs:
		var a := j * runs / jobs
		var b := (j + 1) * runs / jobs - 1
		if b < a:
			continue
		var f := dir.path_join("part%d.jsonl" % j)
		var pid := OS.create_process(OS.get_executable_path(), base + ["--runs=%d-%d" % [a, b], "--out=" + f])
		if pid <= 0:
			error = "could not start the runs"
			stop()
			return false
		_pids.append(pid)
		_files.append(f)
	return true


## A bound as batch.gd reads it: a whole number stays whole (then whole
## numbers are drawn), anything else is a decimal.
static func _num(v) -> String:
	return str(int(v)) if (v is int or (v is float and v == floorf(v) and absf(v) < 1e15)) else str(v)


func running() -> bool:
	return _pids.any(func(p): return OS.is_process_running(p))


## How far along: the share of all runs written so far.
func progress() -> float:
	var done := 0
	for f in _files:
		if FileAccess.file_exists(f):
			done += maxi(FileAccess.get_file_as_string(f).count("\n") - 1, 0)
	return clampf(float(done) / maxf(runs * coas.size(), 1), 0.0, 1.0)


func stop() -> void:
	for p in _pids:
		if OS.is_process_running(p):
			OS.kill(p)
	_pids.clear()


## Merge the parts, write runs.jsonl, runs.csv and summary.json, summarise.
func finish() -> bool:
	seconds = (Time.get_ticks_msec() - _t0) / 1000.0
	rows.clear()
	head = {}
	for f in _files:
		for line in FileAccess.get_file_as_string(f).split("\n", false):
			var d = JSON.parse_string(line)
			if d is Dictionary and d.get("type") == "batch" and head.is_empty():
				head = d
			elif d is Dictionary and d.get("type") == "run":
				rows.append(d)
		DirAccess.remove_absolute(f)
	_files.clear()
	if rows.size() < runs * coas.size():
		error = "only %d of %d runs came back" % [rows.size(), runs * coas.size()]
		if rows.is_empty():
			return false
	rows.sort_custom(func(x, y): return int(x.run) < int(y.run) or (int(x.run) == int(y.run) and coas.map(coa_name).find(x.coa) < coas.map(coa_name).find(y.coa)))
	var jl := FileAccess.open(dir.path_join("runs.jsonl"), FileAccess.WRITE)
	jl.store_line(JSON.stringify(head))
	for r in rows:
		jl.store_line(JSON.stringify(r))
	jl.close()
	FileAccess.open(dir.path_join("runs.csv"), FileAccess.WRITE).store_string(csv())
	summary = summarise(rows, coas.map(coa_name))
	FileAccess.open(dir.path_join("summary.json"), FileAccess.WRITE).store_string(JSON.stringify({"name": name, "engine": head.get("engine", ""),
		"scenario": head.get("scenario", scenario), "seed": head.get("seed", seed), "runs": runs, "hours": hours, "set": fixed, "sample": sample,
		"seconds": seconds, "groups": summary}, " "))
	return true


## Each course of action: n, the share won, the mean score, fuel and custody
## with their 95% intervals, the paired score difference from the first, the
## closest approach, and each sampled setting's rank correlation with the score.
static func summarise(all: Array, names: Array) -> Array:
	var out := []
	var first := {}
	for r in all:
		if r.coa == names[0]:
			first[int(r.run)] = r
	var keys := []
	for r in all:
		for k in r.get("sampled", {}):
			if not k in keys:
				keys.append(k)
	keys.sort()
	for nm in names:
		var R := all.filter(func(r): return r.coa == nm)
		var g := {"coa": nm, "n": R.size(),
			"won": share(R.filter(func(r): return r.won).size(), R.size()),
			"score": mean_ci(R.map(func(r): return float(r.get("score", 0.0)))),
			"fuel_ms": mean_ci(R.map(func(r): return float(r.blue_dv_used) * 1000.0)),
			"custody": mean_ci(R.map(func(r): return float(r.get("custody", 0.0)))),
			"closest_km": median(R.map(func(r): return float(r.get("closest_km", -1.0))).filter(func(x): return x >= 0.0)),
			"score_vs_first": null, "drivers": {}}
		if nm != names[0]:
			g.score_vs_first = mean_ci(R.filter(func(r): return first.has(int(r.run))).map(func(r): return float(r.get("score", 0.0)) - float(first[int(r.run)].get("score", 0.0))))
		for k in keys:
			g.drivers[k] = spearman(R.map(func(r): return float(r.sampled.get(k, 0.0))), R.map(func(r): return float(r.get("score", 0.0))))
		out.append(g)
	return out


## One row per run, for a spreadsheet.
func csv() -> String:
	var objs := []
	var keys := []
	for r in rows:
		for o in r.get("objectives", {}):
			if not o in objs:
				objs.append(o)
		for k in r.get("sampled", {}):
			if not k in keys:
				keys.append(k)
	var lines := [",".join(["coa", "run", "seed", "result", "won", "score", "closest_km", "custody", "blue_dv_used_ms", "escalation", "red_neutralized", "t_end_h"] + objs.map(func(o): return "obj_" + o) + keys)]
	for r in rows:
		var cells := [r.coa, r.run, r.get("seed", ""), r.get("result", ""), r.won, "%.3f" % float(r.get("score", 0.0)), "%.4f" % float(r.get("closest_km", -1.0)),
			"%.4f" % float(r.get("custody", 0.0)), "%.2f" % (float(r.blue_dv_used) * 1000.0), r.get("escalation", ""), r.get("red_neutralized", ""), "%.2f" % (float(r.get("t_end", 0.0)) / 3600.0)]
		cells += objs.map(func(o): return r.get("objectives", {}).get(o, ""))
		cells += keys.map(func(k): return r.get("sampled", {}).get(k, ""))
		lines.append(",".join(cells.map(func(c): var s := str(c); return "\"%s\"" % s.replace("\"", "\"\"") if s.contains(",") or s.contains("\"") else s)))
	return "\n".join(lines) + "\n"


## Student's t, two-sided 95%: Hill's (1970) series in the normal quantile,
## good to 1e-4 for df >= 2; df = 1 exact.
static func t975(df: int) -> float:
	if df <= 0:
		return NAN
	if df == 1:
		return 12.7062
	var z2 := Z * Z
	return Z + Z * (z2 + 1) / (4.0 * df) + Z * (5 * z2 * z2 + 16 * z2 + 3) / (96.0 * df * df) \
		+ Z * (3 * pow(z2, 3) + 19 * z2 * z2 + 17 * z2 - 15) / (384.0 * pow(df, 3)) \
		+ Z * (79 * pow(z2, 4) + 776 * pow(z2, 3) + 1482 * z2 * z2 - 1920 * z2 - 945) / (92160.0 * pow(df, 4))


## A mean and its 95% interval (Student's t).
static func mean_ci(xs: Array) -> Dictionary:
	var n := xs.size()
	if n == 0:
		return {"n": 0, "mean": NAN, "lo": NAN, "hi": NAN}
	var m: float = xs.reduce(func(a, b): return a + b, 0.0) / n
	var sd := sqrt(xs.reduce(func(a, b): return a + (b - m) * (b - m), 0.0) / (n - 1)) if n > 1 else 0.0
	var h := t975(n - 1) * sd / sqrt(n) if n > 1 else NAN
	return {"n": n, "mean": m, "sd": sd, "lo": m - h, "hi": m + h}


## A share k of n and its 95% interval (Wilson's score interval).
static func share(k: int, n: int) -> Dictionary:
	if n == 0:
		return {"k": 0, "n": 0, "p": NAN, "lo": NAN, "hi": NAN}
	var p := float(k) / n
	var d := 1.0 + Z * Z / n
	var c := (p + Z * Z / (2.0 * n)) / d
	var h := Z * sqrt(p * (1.0 - p) / n + Z * Z / (4.0 * n * n)) / d
	return {"k": k, "n": n, "p": p, "lo": maxf(0.0, c - h), "hi": minf(1.0, c + h)}


static func median(xs: Array) -> float:
	if xs.is_empty():
		return NAN
	var s := xs.duplicate()
	s.sort()
	var n := s.size()
	return s[n / 2] if n % 2 == 1 else (s[n / 2 - 1] + s[n / 2]) / 2.0


## Ranks from 1, ties sharing their average rank.
static func ranks(xs: Array) -> Array:
	var o := range(xs.size())
	o.sort_custom(func(a, b): return xs[a] < xs[b])
	var r := []
	r.resize(xs.size())
	var i := 0
	while i < o.size():
		var j := i
		while j + 1 < o.size() and xs[o[j + 1]] == xs[o[i]]:
			j += 1
		for k in range(i, j + 1):
			r[o[k]] = (i + j) / 2.0 + 1.0
		i = j + 1
	return r


## Spearman's rank correlation, -1 to +1 (NaN when either side is constant).
static func spearman(xs: Array, ys: Array) -> float:
	if xs.size() < 2:
		return NAN
	var a := ranks(xs)
	var b := ranks(ys)
	var ma: float = a.reduce(func(p, q): return p + q, 0.0) / a.size()
	var mb: float = b.reduce(func(p, q): return p + q, 0.0) / b.size()
	var sab := 0.0
	var saa := 0.0
	var sbb := 0.0
	for i in a.size():
		sab += (a[i] - ma) * (b[i] - mb)
		saa += (a[i] - ma) * (a[i] - ma)
		sbb += (b[i] - mb) * (b[i] - mb)
	return sab / sqrt(saa * sbb) if saa > 0.0 and sbb > 0.0 else NAN
