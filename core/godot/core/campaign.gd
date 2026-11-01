## The campaign's bookkeeping: objectives, pockets found, how it ends, the
## score and the debrief. Objectives and their wording come from the campaign
## file: CLOSE PASS at the Earth (data/scenarios/close_pass_earth.json), and
## the Jupiter shadowing the tests keep (tests/fixtures/jupiter_shadow.json).
## What the shadowing objectives measure, at every look (Sim.LOOK):
## - keep_out: the shadowing craft's closest to its target (km, at the looks);
## - custody: the share of the time our track on it was good (1σ under
##   camp.custody_km);
## - fuel: the share of the acting craft's Δv used.
## The score (camp.score: weights out of 100) gives each objective its share
## by how well it went, not just done or failed (score()).
class_name Campaign
extends RefCounted

## The world this belongs to, held weakly: Sim holds this too, and a strong
## reference each way is a cycle that RefCounted never frees.
var sim: Sim:
	get:
		return _sim.get_ref()
	set(v):
		_sim = weakref(v)
var _sim := WeakRef.new()
var found := {} # pocket id -> time found
var over := false
var result := "" # "won", "lost", "time"
var why := ""
var ended_by := "" # the objective whose failure ended it
var ended_at := 0.0 # sim time it ended
var closest_km := INF # the shadowing craft's closest to its target, at the looks
var custody_s := 0.0 # time our track on it was good
var watched_s := 0.0 # time counted for custody
var dv0 := -1.0 # the acting craft's Δv at the start (km/s)
var closest_t := -1.0 # when it was closest
## What the debrief replays, one entry a look while a shadowing craft works:
## {t, k: the shadowing craft, w: the acting craft, each [radial, along-track,
## cross-track] km from its target, in the target's frame; esc}.
var history: Array = []


func _init(sim_: Sim) -> void:
	sim = sim_


func pockets_with_red() -> Array:
	var ids := []
	for r in sim.red_ships():
		if r.has("pocket") and not ids.has(r.pocket):
			ids.append(r.pocket)
	return ids


## Red neutralized: destroyed, captured, disabled, or gone home.
func neutralized(r: Dictionary) -> bool:
	if not r.alive or r.get("captured", false) or r.get("disabled", false):
		return true
	return r.get("ai", {}).get("state", "") == "departed"


## The shadowing craft, if this campaign has one.
func _shadow() -> Dictionary:
	for r in sim.red_ships():
		if r.get("role", "") == "shadow":
			return r
	return {}


func status() -> Array:
	var out := []
	var need := pockets_with_red()
	for o in sim.camp.get("objectives", []):
		var st := "open"
		match o.id:
			"find":
				st = "done" if found.size() >= need.size() else "open"
			"signal":
				st = "done" if sim.intercepts.any(func(r): return sim.by_id[r.ship].get("role", "") == "shadow" and r.classified) else "open"
			"stop":
				var sh := _shadow()
				st = "failed" if sh.get("ai", {}).get("state", "") == "complete" else ("done" if not sh.is_empty() and neutralized(sh) else "open")
			"debris":
				st = "failed" if not sim.debris.is_empty() else ("done" if over else "open")
			"protect_sat":
				var asset: Dictionary = sim.by_id.get(String(_shadow().get("plan", {}).get("target", "")), {})
				st = "failed" if not asset.is_empty() and not asset.alive else ("done" if over else "open")
			"peace":
				st = "failed" if sim.escalation >= float(sim.camp.escalation.war) else ("done" if over else "open")
			"keep_out":
				st = "failed" if closest_km < _keep_out() else ("done" if over else "open")
			"custody":
				st = ("done" if _custody() >= float(sim.camp.get("custody_share", 0.8)) else "failed") if over else "open"
			"fuel":
				st = "failed" if _used() > 0.5 else ("done" if over else "open")
		var progress := ""
		if o.id == "find":
			progress = "%d of %d" % [found.size(), need.size()]
		elif o.id == "keep_out" and closest_km < INF:
			progress = "· closest %s" % (Lang.km(closest_km) if closest_km >= 1.0 else "%d m" % roundi(closest_km * 1000.0))
		elif o.id == "custody" and watched_s > 0.0:
			progress = "· %d%% of the time" % roundi(_custody() * 100.0)
		elif o.id == "fuel" and dv0 > 0.0:
			progress = "· %d%% used" % roundi(_used() * 100.0)
		out.append({"id": o.id, "text": o.text, "state": st, "fail": o.fail, "progress": progress})
	return out


func _keep_out() -> float:
	return float(sim.camp.get("keep_out_km", 1.0))


## The share of the time our track on the shadowing craft was good.
func _custody() -> float:
	return custody_s / watched_s if watched_s > 0.0 else 0.0


## The share of the acting craft's Δv used so far.
func _used() -> float:
	var id := String(sim.camp.get("view", {}).get("actor", ""))
	if dv0 <= 0.0 or not sim.by_id.has(id):
		return 0.0
	return clampf(1.0 - sim.delta_v(id) / dv0, 0.0, 1.0)


## Each look: how close the shadowing craft is to its target, and how good our track on it is.
func _measure() -> void:
	var id := String(sim.camp.get("view", {}).get("actor", ""))
	if dv0 < 0.0 and sim.by_id.has(id):
		dv0 = sim.delta_v(id)
	var sh := _shadow()
	if sh.is_empty() or not sh.alive:
		return
	var tgt: Dictionary = sim.by_id.get(String(sh.get("plan", {}).get("target", "")), {})
	if not tgt.is_empty():
		var d := V.dist(sh.r, tgt.r)
		if d < closest_km:
			closest_km = d
			closest_t = sim.t
		var me: Dictionary = sim.by_id.get(String(sim.camp.get("view", {}).get("actor", "")), {})
		history.append({"t": sim.t, "k": ric(sh.r, tgt), "w": ric(me.r, tgt) if not me.is_empty() else [], "esc": sim.escalation})
	if neutralized(sh):
		return
	watched_s += Sim.LOOK
	var tr: Track = sim.tracks.get(sh.id)
	if tr != null and float(tr.ellipse().major) < float(sim.camp.get("custody_km", 1.0)):
		custody_s += Sim.LOOK


const MEASURES := ["closest_km", "closest_t", "custody_s", "watched_s", "dv0", "history"]


## What the objectives have measured so far, for a save (save_game.gd).
func measures() -> Dictionary:
	var out := {}
	for k in MEASURES:
		out[k] = get(k)
	return out


func restore(m: Dictionary) -> void:
	for k in MEASURES:
		if m.has(k):
			set(k, m[k])


## p relative to ship c in c's frame: [radial, along-track, cross-track] (km).
static func ric(p: PackedFloat64Array, c: Dictionary) -> Array:
	var d := V.sub(p, c.r)
	var rh := V.scale(c.r, 1.0 / V.norm(c.r))
	var h := V.cross(c.r, c.v)
	var ch := V.scale(h, 1.0 / V.norm(h))
	var ih := V.cross(ch, rh)
	return [V.dot(d, rh), V.dot(d, ih), V.dot(d, ch)]


## The debrief's timeline: the log's lines about the shadowing craft and the
## tension it cost, oldest first: [{t, text, kind}].
func timeline() -> Array:
	var sh := _shadow()
	var out := []
	for e in sim.log:
		var code := String(e.code)
		var about: bool = sh.is_empty() or String(e.get("data", {}).get("from", "")) == String(sh.get("id", "")) or code in ["blue_too_close", "shadow_inside", "burn_seen"]
		if about and (code.begins_with("shadow_") or code in ["blue_too_close", "burn_seen", "burn_sized", "new_track", "lost", "dropped"]):
			out.append({"t": float(e.t), "text": String(e.text), "kind": String(e.kind)})
	return out


func check() -> void:
	if over:
		return
	_measure()
	# A pocket is found when a classified hostile track sits inside it, tight enough to say so.
	for p in sim.camp.get("pockets", []):
		if found.has(p.id):
			continue
		for id in sim.tracks:
			var tr: Track = sim.tracks[id]
			if tr.side != "hostile" or sim.by_id[id].get("pocket", "") != p.id:
				continue
			var c := sim.pocket_center(p)
			var inside := V.dist(tr.pos(), c) < float(p.get("size", p.get("width", 200000.0))) * 1.5 if p.kind == "lagrange" else absf(V.norm(tr.pos()) - float(p.radius)) < float(p.width)
			if inside and tr.ellipse().major < float(p.get("size", p.get("width", 200000.0))):
				found[p.id] = sim.t
				sim.say("pocket_found", Lang.f("pocket_found", [p.name]), "good")
				break
	for o in status():
		if o.fail and o.state == "failed":
			ended_by = String(o.id)
			_end("lost", o.text)
			return
	if sim.red_ships().all(func(r): return neutralized(r)) and found.size() >= pockets_with_red().size():
		_end("won", "Every Red asset is out of the fight.")
	elif sim.camp.has("days") and sim.t >= float(sim.camp.days) * Sim.DAY:
		_end("time", "The operation's %d days are up." % int(sim.camp.days))


func _end(res: String, reason: String) -> void:
	over = true
	result = res
	why = reason
	ended_at = sim.t


## The score out of 100: each objective's weight (camp.score) times how well
## it went, from 0 to 1:
## - stop: 1 done, ½ still at it when time ran out, 0 failed;
## - keep_out: 1 if it never came inside keep_out_km, else the square of its
##   closest over that (half the distance earns a quarter);
## - custody: the share of good-track time over the share asked for (at most 1);
## - fuel: 1 with a quarter or less used, falling to 0 with all of it gone;
## - peace: 1 less the escalation over war's;
## - any other: 1 done, 0 otherwise.
## {total, parts: [{id, text, got, of}]}; {} when the campaign gives no weights.
func score() -> Dictionary:
	var w: Dictionary = sim.camp.get("score", {})
	if w.is_empty():
		return {}
	var parts := []
	var total := 0.0
	for o in status():
		if not w.has(o.id):
			continue
		var f := 1.0 if o.state == "done" else 0.0
		match o.id:
			"stop":
				f = 1.0 if o.state == "done" else (0.5 if o.state == "open" else 0.0)
			"keep_out":
				f = 1.0 if closest_km >= _keep_out() else pow(clampf(closest_km / _keep_out(), 0.0, 1.0), 2.0)
			"custody":
				f = clampf(_custody() / float(sim.camp.get("custody_share", 0.8)), 0.0, 1.0)
			"fuel":
				f = clampf((1.0 - _used()) / 0.75, 0.0, 1.0)
			"peace":
				f = clampf(1.0 - sim.escalation / float(sim.camp.escalation.war), 0.0, 1.0)
		var of := float(w[o.id])
		parts.append({"id": o.id, "text": o.text, "got": f * of, "of": of})
		total += f * of
	return {"total": total, "parts": parts}


## Grades for the debrief: what was done, and at what price.
func debrief() -> Dictionary:
	var reds := []
	for r in sim.red_ships():
		var how := "still active"
		if r.get("captured", false):
			how = "captured"
		elif r.get("destroyed", false):
			how = "destroyed (debris)"
		elif r.get("disabled", false):
			how = "disabled"
		elif neutralized(r):
			how = "out of the fight (%s)" % String(r.ai.state)
		reds.append({"name": sim.tracks[r.id].label if sim.tracks.has(r.id) else "never found", "class": r.cls.name, "how": how})
	# What to do differently: the advice of each failed objective, the one that ended it first.
	var advice := []
	var objs: Array = sim.camp.get("objectives", [])
	for o in status():
		if o.state != "failed":
			continue
		var a := ""
		for c in objs:
			if c.id == o.id:
				a = String(c.get("advice", ""))
		if a != "":
			if o.id == ended_by:
				advice.push_front(a)
			else:
				advice.append(a)
	return {"result": result, "why": why, "advice": advice, "objectives": status(), "reds": reds, "escalation": sim.escalation, "days": sim.t / Sim.DAY, "debris": sim.debris.size(), "score": score(), "timeline": timeline(), "history": history, "closest_t": closest_t, "closest_km": closest_km}
