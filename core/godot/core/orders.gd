## A course of action: Blue's orders at set times, as data (cli/run.gd --coa,
## cli/batch.gd). Each order is one thing a player does in the game, through
## the same functions, so a course of action plays by the game's rules: a
## transfer is planned on Blue's track of a Red ship, not its truth; an effect
## needs what the Selected item window would need; fuel is spent as flown.
## A file is {"orders": [...]}; each order has "t" (s from the start), "do",
## and its fields:
##   burn       ship, dv [x, y, z] km/s
##   intercept  ship, target, tof s; behind_km (optional): aim that far behind
##              the target along its orbit, to arrive beside it, not on it
##   match      ship, target: the velocity that keeps ship alongside the target
##              (Sim.station_v, on Blue's track for a Red ship)
##   effect     effect (jam, spoof, dazzle, hpm, cyber, kinetic), ship, target;
##              stop: true ends a jam or spoof
##   buoy       ship
##   analyse    on (default true): take bearings on and classify every burst
##              heard, as it is heard (the game's auto-analysis)
##   radar      ship, on: radiate (ranges every track in reach; escalates)
## An order refused at its time is given up, unless it has "until" (s): then it
## is tried again every look (600 s) until it is carried out or until passes.
## "Jam as soon as it is identified" is {"t": 0, "until": 86400, ...}.
class_name Orders
extends RefCounted

var queue := [] # orders still to give, by time
var reports := [] # every order given: {type: "order", t, order, ok, why, tries}


func _init(orders: Array) -> void:
	for o in orders:
		var d: Dictionary = o.duplicate(true)
		d.tries = 0
		queue.append(d)
	_sort()


## The orders of a course-of-action file, or null if it cannot be read.
static func read(path: String):
	var coa = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not (coa is Dictionary and coa.get("orders") is Array):
		return null
	return coa.orders


## When the next order is due (INF when none is left).
func next_t() -> float:
	return float(queue[0].get("t", 0.0)) if not queue.is_empty() else INF


## Give every order due by now. Returns the reports of those settled (carried
## out, or refused for good); an order still inside its "until" waits a look.
func due(sim: Sim) -> Array:
	var out := []
	while not queue.is_empty() and float(queue[0].get("t", 0.0)) <= sim.t + 1e-6:
		var o: Dictionary = queue.pop_front()
		o.tries = int(o.tries) + 1
		var r := give(sim, o)
		var again := float(o.get("t", 0.0)) + Sim.LOOK
		if not r.ok and o.has("until") and again <= float(o.until) + 1e-6:
			o.t = again
			queue.append(o)
			_sort()
			continue
		var clean := o.duplicate()
		clean.erase("tries")
		r.order = clean
		r.tries = int(o.tries)
		reports.append(r)
		out.append(r)
	return out


func _sort() -> void:
	queue.sort_custom(func(a, b): return float(a.get("t", 0.0)) < float(b.get("t", 0.0)))


## Give one order now. Returns {type: "order", t, ok, why} (and dv for a transfer).
static func give(sim: Sim, order: Dictionary) -> Dictionary:
	var out := {"type": "order", "t": sim.t, "ok": false, "why": ""}
	var what := String(order.get("do", ""))
	if what == "analyse":
		sim.sensing.auto = bool(order.get("on", true))
		out.ok = true
		return out
	var id := String(order.get("ship", ""))
	var target := String(order.get("target", ""))
	if not sim.by_id.has(id) or sim.by_id[id].side != "blue":
		out.why = "no Blue ship %s" % id
		return out
	if not sim.by_id[id].alive:
		out.why = "%s is lost" % id
		return out
	if target != "" and not sim.by_id.has(target):
		out.why = "no target %s" % target
		return out
	match what:
		"burn":
			var dv: Array = order.get("dv", [])
			out.ok = dv.size() == 3 and sim.burn(id, V.of(float(dv[0]), float(dv[1]), float(dv[2])))
			out.why = "" if out.ok else "cannot burn that"
		"intercept":
			var tof := float(order.get("tof", 6.0 * Sim.HOUR))
			var plan := sim.plan_intercept(id, target, tof)
			var behind := float(order.get("behind_km", 0.0))
			if plan.get("node") != null and behind != 0.0:
				plan = sim.plan_to(id, _behind(sim, target, plan.node, behind), tof, float(plan.get("sigma", 0.0)), target)
			out.ok = sim.execute(plan)
			out.why = "" if out.ok else String(plan.get("why", "cannot fly it"))
			if out.ok:
				out.dv = plan.dv
				out.arrive = plan.arrive # when it meets: the order's time + tof
				out.miss_km = plan.get("miss_km", 0.0) # from its aim, flown under full gravity
				out.sigma_km = plan.get("sigma", 0.0) # the target's 1σ there, on Blue's track
		"match":
			var tv := _seen(sim, target)
			if tv.is_empty():
				out.why = "no track on it"
				return out
			out.ok = sim.burn(id, V.sub(sim.station_v(sim.by_id[id].r, tv[0], tv[1]), sim.by_id[id].v))
			out.why = "" if out.ok else "not enough fuel"
		"effect":
			var key := String(order.get("effect", ""))
			var on: Dictionary = sim.effects.jamming.get(id, {})
			var running: bool = on.get("mode", "") == key and on.get("target", "") == target
			if key in ["jam", "spoof"] and (running == not bool(order.get("stop", false))):
				out.ok = true # already as ordered (use() would toggle it)
				return out
			out.ok = sim.effects.use(key, id, target)
			if not out.ok:
				for x in sim.effects.options(id, target):
					if x.key == key:
						out.why = String(x.get("line", ""))
				if out.why == "":
					out.why = "no such effect"
		"buoy":
			var b := sim.drop_buoy(id)
			out.ok = b != ""
			out.why = "" if out.ok else "no buoy to drop"
		"radar":
			if not sim.by_id[id].cls.has("radar"):
				out.why = "%s has no radar" % id
				return out
			sim.effects.radar_on[id] = bool(order.get("on", true))
			out.ok = true
		_:
			out.why = "unknown order %s" % what
	return out


## Where and how fast Blue believes the target is: our own ships exactly, a
## Red ship by its track. [] without a track.
static func _seen(sim: Sim, target: String) -> Array:
	var tgt: Dictionary = sim.by_id[target]
	if tgt.side != "red":
		return [tgt.r, tgt.v]
	if not sim.tracks.has(target):
		return []
	var tr: Track = sim.tracks[target].forecast(sim.t) # a copy: the track itself is left as it is
	return [tr.pos(), tr.vel()]


## A point km behind node along the target's orbit (the direction it travels):
## along h × node, h the orbit's pole (r × v), so it keeps to an inclined
## orbit's plane; in the game plane it is the turn about z it always was.
static func _behind(sim: Sim, target: String, node: PackedFloat64Array, km: float) -> PackedFloat64Array:
	var tv := _seen(sim, target)
	var r: PackedFloat64Array = tv[0] if not tv.is_empty() else node
	var v: PackedFloat64Array = tv[1] if not tv.is_empty() else V.of(-node[1], node[0])
	var along := V.cross(V.cross(r, v), node)
	return V.sub(node, V.scale(along, km / maxf(V.norm(along), 1e-12)))
