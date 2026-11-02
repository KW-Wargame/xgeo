## Red's behaviour. Red flies by the same physics as Blue and knows only what
## its own sensors and its handler tell it. Every Red ship reports home and
## keeps its heat down; one with the role "shadow" (plan.target, plan.legs)
## inspects its target up close (_shadow). Red's links to its handler: jammed,
## spoofed or captured cut the commands that keep its plans fresh.
class_name RedAI
extends RefCounted

const H := 3600.0
## The world this belongs to, held weakly: Sim holds this too, and a strong
## reference each way is a cycle that RefCounted never frees.
var sim: Sim:
	get:
		return _sim.get_ref()
	set(v):
		_sim = weakref(v)
var _sim := WeakRef.new()


func _init(sim_: Sim) -> void:
	sim = sim_
	for s in sim.red_ships():
		s.ai = {"next_tx": _first_tx(s), "silent_until": 0.0, "evasions": 2, "last_evade": -1e9, "state": "idle", "arrival": INF, "fixes": 0}
		s.bursts = []
	for s in sim.red_ships():
		if s.get("role", "") == "shadow":
			s.ai.state = "phase"
			s.ai.leg = 0
			s.ai.last_link = 0.0
			s.ai.legs = (s.plan.legs as Array).duplicate(true) # its own copy: reactions add and change legs


func _first_tx(s: Dictionary) -> float:
	if not s.cls.has("ttc"):
		return INF
	return sim.stream("red").randf_range(0.2, 1.0) * float(s.cls.ttc.every[0])


## Is this Red ship still taking orders from its handler?
func linked(s: Dictionary) -> bool:
	return not (s.get("jammed_until", -1.0) > sim.t or s.get("captured", false) or s.get("disabled", false))


func can_see(s: Dictionary) -> bool:
	return s.get("dazzled_until", -1.0) <= sim.t and not s.get("disabled", false)


## Which Blue warships and inspectors does this Red ship know about, and how?
func threats(s: Dictionary) -> Array:
	var out := []
	for b in sim.blue_ships():
		if not b.kind in ["warship", "inspector"]:
			continue
		var seen: bool = can_see(s) and s.cls.has("ir") and sim.sensing.ir_sees(s, b)
		var loud := float(b.get("loud_until", -1.0)) > sim.t
		if seen or loud:
			var d := V.sub(b.r, s.r)
			var closing := V.dot(d, V.sub(b.v, s.v)) < 0.0
			out.append({"s": b, "range": V.norm(d), "closing": closing, "burning": sim.burning(b.id) and seen, "loud": loud})
	return out


func think() -> void:
	for s in sim.red_ships():
		if not s.alive or s.get("captured", false) or s.get("disabled", false):
			continue
		_talk(s)
		_heat(s)
		if s.role == "shadow":
			_shadow(s)


## Reports home on a habit, unless it feels hunted: one of ours burning, loud,
## or closing within camp.quiet_km (150,000 km at Jupiter; at the Earth the
## scenario sets it). With a handler on the ground (camp.handler) it can only
## talk while the station is above its horizon mask; a report due meanwhile
## waits for the next pass.
func _talk(s: Dictionary) -> void:
	if not s.cls.has("ttc"):
		return
	var ai: Dictionary = s.ai
	var hunted := false
	var quiet_km := float(sim.camp.get("quiet_km", 150000.0))
	for th in threats(s):
		if th.burning or th.loud or (th.range < quiet_km and (th.closing or quiet_km < 1000.0)):
			hunted = true
	if hunted and ai.silent_until < sim.t:
		if sim.tracks.has(s.id):
			sim.say("red_quiet", Lang.f("red_quiet", [sim.sensing.label_for(s.id)]), "warn")
	if hunted:
		ai.silent_until = maxf(ai.silent_until, sim.t + 6.0 * H)
	if sim.t >= ai.next_tx and sim.t >= ai.silent_until and in_view(s):
		s.bursts.append({"start": sim.t, "end": sim.t + float(s.cls.ttc.burst), "kind": "ttc"})
		ai.next_tx = sim.t + sim.stream("red").randf_range(float(s.cls.ttc.every[0]), float(s.cls.ttc.every[1]))


## The shadowing: an uncooperative rendezvous and proximity operation on Blue's
## radar satellite, in the order LeoLabs reported the real one (Oct 2026):
## close in from long range, reposition ahead of and behind the target,
## loiter in extreme proximity, then a controlled departure. Its legs are
## plan.legs, [along-track km (+ ahead), hours to hold there, hours to get there];
## each hop is two burns (go, then match) that its handler must command, so a
## hop waits while the link is down. Lost its link for LOST_H inside 200 km
## with a Blue ship shadowing it (within PRESENCE_KM), it retreats on its own to
## a higher, slower orbit and drifts off, as visiting vehicles abort an approach
## on loss of contact (Progress M-06M, 2010). Cut off but alone, it holds its
## slot and waits for its link: an autonomous vehicle's safe choice when nothing
## threatens it (design values). So jamming from afar stalls it; it takes
## jamming and presence together to make it leave.
## Running out of legs means the inspection is complete.
## It watches our inspector too, through its own telescope (threats()), each
## time it settles in a slot (design values, after how visiting vehicles and
## inspectors keep a keep-out zone and abort when it is broken):
## - crowded (one of ours within CROWD_KM of it): it gives up the slot for
##   one EVADE_KM on the far side of its target from ours; after EVASIONS of
##   those, crowded again, it gives the inspection up and leaves;
## - alone (none of ours seen within ALONE_KM): it pushes in, taking its next
##   slot at half the distance (no nearer than CLOSEST_KM).
## So you drive it off by staying on it, and it gets closest when you are away.
## Tension (sim.escalation) runs both ways, where the scenario sets it
## (camp.escalation; design values):
## - it rises when it parks inside the keep-out of its target (redInside),
##   each time ours crowd it into giving way (blueCrowd), and for every hour
##   one of ours is within the keep-out of it (blueTooClosePerHour);
## - at cautiousAt or more it gives way once fewer and no longer pushes in
##   when alone; at leaveAt or more it leaves at the first crowding.
## So pressing hard drives it off sooner, at a price in tension.
const LOST_H := 3.0
const CROWD_KM := 5.0
const EVADE_KM := 8.0
const EVASIONS := 2
const ALONE_KM := 50.0
const CLOSEST_KM := 0.5
## No hop passes nearer its target than this (km): a hop straight along the
## target's orbit passes through it, so it takes the cheapest that stays clear.
const SAFE_PASS_KM := 0.4
const SHIFT_LOOKS := 4
const LEAVE_KMS := 0.004 # its departure burn, prograde (4 m/s; design value)
const PRESENCE_KM := 25.0 # design value: wide enough that one MATCH keeps you inside it for the 3 h cut-off (a match drifts ~20 km in 3 h)


## The nearest live Blue ship within PRESENCE_KM of s, or "".
func _shadowed_by(s: Dictionary) -> String:
	var best := ""
	var bd := _red("presenceKm", PRESENCE_KM)
	for b in sim.blue_ships():
		if b.has("onMoon") or b.get("kind", "") in ["station", "kv", "buoy", "freighter", "commercial"]: # a warship, not its target or a buoy
			continue
		var d := V.dist(b.r, s.r)
		if d <= bd:
			bd = d
			best = b.id
	return best


func _shadow(s: Dictionary) -> void:
	var ai: Dictionary = s.ai
	var tgt: Dictionary = sim.by_id.get(String(s.plan.get("target", "")), {})
	if tgt.is_empty() or not tgt.alive or ai.state in ["departed", "complete"]:
		return
	var up := linked(s)
	if up:
		ai.last_link = sim.t
	var rng := V.dist(s.r, tgt.r)
	_tension(s)
	match ai.state:
		"retreat":
			if rng > 200.0:
				ai.state = "departed"
				sim.say("shadow_gone", Lang.f("shadow_gone", [_label(s), Lang.km(rng)]), "good", {"from": s.id})
			return
		"match":
			if sim.t >= float(ai.match_at) - 1.0:
				sim.burn(s.id, V.sub(_slot_v(s, tgt), s.v))
				ai.state = "hold"
				ai.hold_until = sim.t + float(ai.legs[ai.leg][1]) * H
				_report(s)
				if rng < _keep_out():
					_raise("redInside", "shadow_inside" if sim.tracks.has(s.id) else "")
				if sim.tracks.has(s.id):
					sim.say("shadow_hold", Lang.f("shadow_hold", [_label(s), _where_rel(float(ai.legs[ai.leg][0])), tgt.short]), "warn", {"from": s.id})
	var cut_off: bool = ai.state in ["match", "hold"] and rng < 200.0 and sim.t - float(ai.last_link) > _red("lostHours", LOST_H) * H
	if cut_off and _shadowed_by(s) == "":
		# Cut off but nobody alongside: it holds and waits for its link.
		if not ai.get("told_waiting", false) and sim.tracks.has(s.id):
			ai.told_waiting = true
			sim.say("shadow_waits", Lang.f("shadow_waits", [_label(s), Lang.km(_red("presenceKm", PRESENCE_KM))]), "warn", {"from": s.id})
	elif cut_off:
		# Lost its handler with one of ours alongside: back off to a safe, higher orbit (~40 km up).
		sim.burn(s.id, V.scale(V.scale(s.v, 1.0 / V.norm(s.v)), _red("leaveKms", LEAVE_KMS)))
		ai.state = "retreat"
		sim.say("shadow_retreat", Lang.f("shadow_retreat", [_label(s)]), "good", {"from": s.id})
		return
	if not up:
		return
	if ai.state == "hold":
		var near := _nearest_watcher(s)
		if not near.is_empty() and float(near.range) < _red("crowdKm", CROWD_KM):
			_raise("blueCrowd", "")
			if int(ai.get("evaded", 0)) >= _evasions():
				# Crowded again after giving way: it gives the inspection up.
				sim.burn(s.id, V.scale(V.scale(s.v, 1.0 / V.norm(s.v)), _red("leaveKms", LEAVE_KMS)))
				ai.state = "retreat"
				sim.say("shadow_driven", Lang.f("shadow_driven", [_label(s), tgt.short]), "good", {"from": s.id})
				return
			# Give way: a slot on the far side of the target from ours, then on with the plan.
			ai.evaded = int(ai.get("evaded", 0)) + 1
			var side := signf(V.dot(V.sub(near.s.r, tgt.r), tgt.v))
			ai.legs.insert(int(ai.leg) + 1, [-(side if side != 0.0 else 1.0) * _red("evadeKm", EVADE_KM), 4.0, 2.0])
			ai.leg = int(ai.leg) + 1
			_hop(s, tgt)
			if ai.state == "match":
				sim.say("shadow_crowded", Lang.f("shadow_crowded", [_label(s), tgt.short]), "good", {"from": s.id})
			return
	if ai.state == "phase" or (ai.state == "hold" and sim.t >= float(ai.hold_until)):
		if ai.state == "hold":
			ai.leg = int(ai.leg) + 1
			# Nobody of ours in sight: it takes its next slot nearer.
			var near := _nearest_watcher(s)
			if int(ai.leg) < ai.legs.size() and (near.is_empty() or float(near.range) > _red("aloneKm", ALONE_KM)) and sim.escalation < _esc("cautiousAt", INF):
				var leg: Array = ai.legs[ai.leg]
				var along := float(leg[0])
				if absf(along) > _red("closestKm", CLOSEST_KM):
					leg[0] = signf(along) * maxf(_red("closestKm", CLOSEST_KM), absf(along) * 0.5)
					if sim.tracks.has(s.id):
						sim.say("shadow_push", Lang.f("shadow_push", [_label(s), tgt.short]), "warn", {"from": s.id})
		if int(ai.leg) >= ai.legs.size():
			ai.state = "complete"
			sim.burn(s.id, V.scale(V.scale(s.v, 1.0 / V.norm(s.v)), _red("leaveKms", LEAVE_KMS)))
			sim.say("shadow_done", Lang.f("shadow_done", [_label(s), tgt.short]), "alert", {"from": s.id})
			return
		_hop(s, tgt)


## A behaviour setting from the scenario's "red_ai" block (lostHours, crowdKm,
## evadeKm, evasions, aloneKm, closestKm, presenceKm, leaveKms), or the
## constant above: a study can then vary them (cli/batch.gd --vary).
func _red(key: String, or_else: float) -> float:
	return float(sim.camp.get("red_ai", {}).get(key, or_else))


## A tension setting from the scenario (camp.escalation), or `or_else`.
func _esc(key: String, or_else: float) -> float:
	return float(sim.camp.get("escalation", {}).get(key, or_else))


func _keep_out() -> float:
	return float(sim.camp.get("keep_out_km", 1.0))


## How many times it gives way before it leaves: fewer as tension rises.
## In the walkthrough, the scenario's tutorial.evasions (CLOSE PASS: once, so
## following the steps wins it).
func _evasions() -> int:
	var most := int(sim.camp.get("tutorial", {}).get("evasions", EVASIONS)) if sim.tutorial else int(_red("evasions", EVASIONS))
	if sim.escalation >= _esc("leaveAt", INF):
		return 0
	if sim.escalation >= _esc("cautiousAt", INF):
		return maxi(0, most - 1)
	return most


## Raise the tension by the scenario's `key`, saying so with `code` if any.
func _raise(key: String, code: String) -> void:
	var by := _esc(key, 0.0)
	if by <= 0.0:
		return
	sim.effects.escalate(by, key)
	if code != "":
		sim.say(code, Lang.f(code, [int(roundf(by))]), "warn")


## Each look: one of ours inside the keep-out of it raises the tension.
func _tension(s: Dictionary) -> void:
	var per_h := _esc("blueTooClosePerHour", 0.0)
	if per_h <= 0.0 or not s.ai.state in ["phase", "match", "hold"]:
		return
	for b in sim.blue_ships():
		if b.alive and b.kind in ["warship", "inspector"] and V.dist(b.r, s.r) < _keep_out():
			var was := sim.escalation
			sim.effects.escalate(per_h * Sim.LOOK / H, "blue_close")
			if int(was / 10.0) != int(sim.escalation / 10.0) or not s.ai.get("told_close", false):
				s.ai.told_close = true
				sim.say("blue_too_close", Lang.f("blue_too_close", [String(b.short), _label(s), int(sim.escalation)]), "warn")
			return


## The nearest of our inspectors and warships this ship knows of:
## {s, range}, or {} when it sees none.
func _nearest_watcher(s: Dictionary) -> Dictionary:
	var best := {}
	for th in threats(s):
		if best.is_empty() or float(th.range) < float(best.range):
			best = th
	return best


## Go to the next leg's slot: Lambert, corrected under full gravity, arriving on a look.
## When the hop takes more than an orbit (in low orbit a few hours is a few
## turns) Lambert's arcs of all its turns are weighed, and the shooting
## (Sim._shoot) corrects the one taken, as single-turn re-aiming would lose
## the turns.
## A hop along the target's orbit loops above and below it, and where it
## crosses the target depends on when it arrives: so it weighs arriving up to
## SHIFT_LOOKS looks early or late, and takes the cheapest that keeps
## SAFE_PASS_KM from the target all the way (if none does, the one that keeps
## furthest). The weighing is two-body throughout (_arc); the pulls it leaves
## out are nearly the same on both craft, so the passes hold under full gravity.
func _hop(s: Dictionary, tgt: Dictionary) -> void:
	var ai: Dictionary = s.ai
	var leg: Array = ai.legs[ai.leg]
	var looks := maxf(1.0, roundf(float(leg[2]) * H / Sim.LOOK))
	var pick := {}
	for k in range(-SHIFT_LOOKS, SHIFT_LOOKS + 1):
		if looks + k < 1.0:
			continue
		var arc := _arc(s, tgt, float(leg[0]), (looks + k) * Sim.LOOK)
		if arc.is_empty():
			continue
		var clear := float(arc.pass_km) >= SAFE_PASS_KM
		var better: bool = pick.is_empty() 			or (clear and (not pick.clear or float(arc.cost) < float(pick.cost))) 			or (not clear and not pick.clear and float(arc.pass_km) > float(pick.pass_km))
		if better:
			pick = arc
			pick.clear = clear
	if pick.is_empty():
		return
	var tof := float(pick.tof)
	var turns := int(pick.turns)
	var v1: PackedFloat64Array = pick.v1
	var st := sim.gravity.coast(tgt.r, tgt.v, sim.t, tof, 60.0)
	var node := V.add(st[0], V.scale(V.scale(st[1], 1.0 / V.norm(st[1])), float(leg[0])))
	var plan := {"id": s.id, "node": node, "arrive": sim.t + tof, "dv_vec": V.sub(v1, s.v)}
	if turns > 0:
		var sh := sim._shoot(s.id, v1, node, tof)
		if float(sh[1]) > 1.0:
			return
		plan.dv_vec = V.sub(sh[0], s.v)
	else:
		sim.refine(plan)
	if V.norm(plan.dv_vec) * 2.2 > sim.delta_v(s.id):
		ai.state = "complete"
		return
	sim.burn(s.id, plan.dv_vec)
	ai.state = "match"
	ai.match_at = plan.arrive
	_report(s)


## A hop to `along` km from the target taking tof, two-body throughout: the
## cheapest of Lambert's arcs of all the turns, with how close it passes the
## target on the way. {v1, cost, pass_km, tof, turns}, or {} for none.
func _arc(s: Dictionary, tgt: Dictionary, along: float, tof: float) -> Dictionary:
	var end := Kepler.propagate(tgt.r, tgt.v, tof, sim.mu)
	var node := V.add(end[0], V.scale(V.scale(end[1], 1.0 / V.norm(end[1])), along))
	var a := Kepler.semi_major_axis(s.r, s.v, sim.mu)
	var turns := int(tof / (TAU * sqrt(pow(a, 3.0) / sim.mu))) if a > 0.0 else 0
	var all := Lambert.solve_all(s.r, node, tof, sim.mu, true, turns, V.cross(s.r, s.v))
	if all.is_empty():
		return {}
	var v1: PackedFloat64Array = all[0].v1
	for o in all:
		if V.dist(o.v1, s.v) < V.dist(v1, s.v):
			v1 = o.v1
	# The closest it passes: both coasted in steps of about two minutes.
	var p := [s.r, v1]
	var q := [tgt.r, tgt.v]
	var n := maxi(30, int(tof / 120.0))
	var least := V.dist(p[0], q[0])
	for i in n:
		p = Kepler.propagate(p[0], p[1], tof / n, sim.mu)
		q = Kepler.propagate(q[0], q[1], tof / n, sim.mu)
		least = minf(least, V.dist(p[0], q[0]))
	return {"v1": v1, "cost": V.dist(v1, s.v), "pass_km": least, "tof": tof, "turns": turns}


## The velocity that keeps it in its slot: the target's, turned through the
## angle between them, so it rides the same circular orbit a little ahead or
## behind. Off the game's plane (at the Earth) Sim.station_v does it in 3-D.
func _slot_v(s: Dictionary, tgt: Dictionary) -> PackedFloat64Array:
	if s.r.size() > 2 and (absf(float(s.r[2])) > 1e-6 or absf(float(tgt.v[2])) > 1e-9):
		return sim.station_v(s.r, tgt.r, tgt.v)
	var a := atan2(tgt.r[0] * s.r[1] - tgt.r[1] * s.r[0], V.dot(tgt.r, s.r))
	var v: PackedFloat64Array = tgt.v
	return V.of(v[0] * cos(a) - v[1] * sin(a), v[0] * sin(a) + v[1] * cos(a))


## Each manoeuvre is followed by a report home: something for Blue to hear.
## Out of sight of its ground station, the report waits for the next pass.
func _report(s: Dictionary) -> void:
	if not s.cls.has("ttc") or sim.t < float(s.ai.silent_until):
		return
	if not in_view(s):
		s.ai.next_tx = minf(float(s.ai.next_tx), sim.t)
		return
	s.bursts.append({"start": sim.t, "end": sim.t + float(s.cls.ttc.burst), "kind": "ttc"})


## Can this ship talk to its handler now? Always, but for a handler on the
## ground (camp.handler.ground): then only while the station sees it above
## its mask (camp.handler.min_el_deg) and the Earth is not in between.
func in_view(s: Dictionary) -> bool:
	var hd: Dictionary = sim.camp.get("handler", {})
	if not hd.has("ground"):
		return true
	var g := sim.handler_pos()
	var d := V.sub(s.r, g)
	var el := asin(clampf(V.dot(d, g) / (V.norm(d) * V.norm(g)), -1.0, 1.0))
	return el >= deg_to_rad(float(hd.get("min_el_deg", 10.0)))


func _label(s: Dictionary) -> String:
	return sim.tracks[s.id].label if sim.tracks.has(s.id) else "An unknown craft"


func _where_rel(along: float) -> String:
	return ("%s ahead of" if along > 0.0 else "%s behind") % Lang.km(absf(along))


## Heat discipline: go dark on the heat sink while any Blue telescope it knows
## of (warships it has seen or been told of, and our stations' fixed ones) would
## still see the radiator's edge, and put off refreezing the sink while the
## extra heat that takes would show.
func _heat(s: Dictionary) -> void:
	if not s.cls.has("thermal") or not s.cls.thermal.has("radiator") or not s.has("heat"):
		return
	var h: Dictionary = s.heat
	var eyes := []
	for th in threats(s):
		if th.s.cls.has("ir"):
			eyes.append(th.s)
	for b in sim.blue_ships():
		if b.kind == "station" and b.alive and b.cls.has("ir"):
			eyes.append(b)
	if eyes.is_empty():
		return
	var Q := Thermal.waste(s.cls)
	var exposed := _shows(s, eyes, Q)
	var sink: Dictionary = s.cls.thermal.get("sink", {})
	var room := not sink.is_empty() and float(h.get("stored", 0.0)) < 0.9 * float(sink.kg) * float(sink.kJkg) * 1000.0
	if exposed and room and not h.get("dark", false):
		h.dark = true
	elif not exposed and h.get("dark", false):
		h.dark = false
	h.hold = float(h.get("stored", 0.0)) > 0.0 and _shows(s, eyes, Q * (1.0 + Thermal.RECHARGE))


## Would any of these telescopes see the radiator's edge, rejecting Q?
func _shows(s: Dictionary, eyes: Array, Q: float) -> bool:
	var ri := Thermal.radiator_I(s.cls.thermal.radiator, Thermal.radiator_T(s.cls.thermal.radiator, Q), PI / 2.0)
	var skin := Thermal.grey_band(s.cls.sig, sim.thermal.skin_now(s))
	for b in eyes:
		var R := V.dist(b.r, s.r) * 1000.0
		if (skin + float(ri.edge)) / (R * R) / float(b.cls.ir.get("neiBand", b.cls.ir.nei)) >= float(sim.data.cfg.ir.band.threshold):
			return true
	return false

