## Blue's counterspace effects, non-kinetic first. Each is decided by physics,
## and each has a cost: being heard, being seen, escalation.
## Categories after USSF "Space Warfighting: A Framework for Planners" (2025):
## space link interdiction (jam, spoof), orbital strike (dazzle, HPM, kinetic),
## cyberspace warfare (capture).
## - Jamming and spoofing: the jammer's power reaches the target's receiver
##   through a sidelobe, the handler's uplink through the main lobe; J/S by
##   Friis decides (needed J/S is a design value). A jammer is loud: Red hears it.
## - Dazzle: the laser's spot spreads by diffraction and jitter,
##   spot = R·√((1.22λ/D)² + j²) (1.22λ/D: Hecht 2017; jitter added in quadrature,
##   an engineering approximation); irradiance P/(π spot²) above a
##   focal plane's saturation blinds it for hours. Firing heats the radiators.
## - HPM: far-field strength E = √(30PG)/R (Balanis 2016; ITU-R P.525-4, Annex §2.1,
##   eq. 1) against an upset threshold.
## - Capture: enough recorded command traffic to learn the link, then out-shout the handler.
## - Kinetic: a kill vehicle (its own object, class skv) is fired on a transfer
##   to where the track says the target will be. Its IR seeker acquires the
##   target when it sees it (Sensing.ir_sees); from then on it re-aims at the
##   true target every GUIDE_EVERY s with its divert thrusters (a Lambert
##   re-solve: ideal guidance) while it has the fuel. It hits if it passes
##   within the target's hard body, and the round works (reliability). The
##   hit is a hypervelocity collision (Breakup): a catastrophic one breaks the
##   target up, a lesser one craters it and knocks out what it struck. Either
##   leaves a debris cloud (NASA Standard Breakup Model). Irreversible.
class_name Effects
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
var cfg: Dictionary
var jamming := {} # shooter id -> {target, mode: "jam"/"spoof"}
var kvs: Array = [] # flights: {id (the kill vehicle's object), target, launch, arrive, aim, reach, rel, acquired, done, result}
const GUIDE_EVERY := 30.0 # s between the seeker's course corrections (design value)
const GUIDE_LAST := 20.0 # s: no corrections closer in than this, the thrusters cannot act in time (design value)
const SEEKER_RAD := 1e-5 # rad: 1σ error of the seeker's line of sight to the target (design value: a pixel's worth of an IR focal plane, divided by its S/N)
var radar_on := {}
## Jamming technique per shooter: "spot" (all the power on the target's
## uplink channel, which you only know once you have identified its downlink)
## or "barrage" (the whole deep-space X-band uplink allocation, so the power is spread).
var technique := {}

## Deep-space (Category B) X-band uplink 7145–7190 MHz (DSN 810-005 Module 201;
## 7190–7235 MHz is the near-Earth Category A allocation); a command uplink ~1 MHz wide.
const UPLINK_BAND_HZ := 45e6
const UPLINK_BW_HZ := 1e6
## Coherent transponder turnaround for X band, 880/749 (CCSDS 401 Rec. 2.6.2, DSN 810-005):
## a downlink at f_down implies the uplink at f_down × 749/880.
const TURNAROUND := 749.0 / 880.0


func _init(sim_: Sim) -> void:
	sim = sim_
	cfg = sim.camp.get("effects", {})


func _fspl_db(R_m: float, f: float) -> float:
	return 20.0 * log(4.0 * PI * R_m * f / RF.C_MS) / log(10.0)


## Jam-to-signal (dB) at target's receiver from shooter's jammer, against its handler's uplink.
func js_db(shooter: Dictionary, target: Dictionary) -> float:
	return _js_raw(shooter, target) - spread_db(shooter.id, target.id)


## The target's uplink, if we have identified one of its downlink reports:
## {down, up} in Hz, or {} if unknown.
func uplink(target_id: String) -> Dictionary:
	for rec in sim.intercepts:
		if rec.ship == target_id and rec.classified:
			return {"down": float(rec.f), "up": float(rec.f) * TURNAROUND}
	return {}


## The technique that will actually be used: spot needs the channel.
func technique_for(shooter_id: String, target_id: String) -> String:
	var want: String = technique.get(shooter_id, "spot")
	return "spot" if want == "spot" and not uplink(target_id).is_empty() else "barrage"


## Power lost by spreading the jammer across the band (dB): 0 for spot.
func spread_db(shooter_id: String, target_id: String) -> float:
	return 0.0 if technique_for(shooter_id, target_id) == "spot" else 10.0 * log(UPLINK_BAND_HZ / UPLINK_BW_HZ) / log(10.0)


func _js_raw(shooter: Dictionary, target: Dictionary) -> float:
	return js_terms(shooter, target).js_db


## The jamming budget term by term (dB, and the angles behind them), every
## antenna through its ITU pattern (Antenna):
##   J = Pj + Gj(aim error) + Gv(angle at the victim between its handler and us) − L(us → victim)
##   S = Pu + Gu(peak) + Gv(0) − L(handler → victim)
## Our jammer points at Blue's track, not the truth, so a poor track costs gain,
## unless the shooter's own telescope sees the target (sees_to_aim): then the
## beam follows the telescope's line of sight and is off by its bearing error;
## the victim's dish points at its handler, so we come in through a sidelobe
## unless we stand near that line. Victims without a dish in the data take the
## fixed main/side gains of cfg.jam.rx.
func js_terms(shooter: Dictionary, target: Dictionary) -> Dictionary:
	var j: Dictionary = cfg.jam.jammer
	var up: Dictionary = cfg.jam.handlerUplink
	var f: float = j.f
	var h := sim.handler_pos()
	var aim: PackedFloat64Array = sim.tracks[target.id].pos() if sim.tracks.has(target.id) else target.r
	var err := float(sim.data.cfg.ir.bearingSigma) if sees_to_aim(shooter, target) else Antenna.angle_at(shooter.r, aim, target.r)
	var gj := Antenna.gain_dbi(float(j.dish), f, err)
	var gu := Antenna.peak_dbi(float(up.dish), f)
	var off := Antenna.angle_at(target.r, h, shooter.r)
	var gv_j: float
	var gv_s: float
	var ttc: Dictionary = target.cls.get("ttc", {})
	if ttc.has("dish"):
		gv_j = Antenna.gain_dbi(float(ttc.dish), f, off)
		gv_s = Antenna.peak_dbi(float(ttc.dish), f)
	else:
		gv_j = float(cfg.jam.rx.sideDbi)
		gv_s = float(cfg.jam.rx.mainDbi)
	var lj := _fspl_db(V.dist(shooter.r, target.r) * 1000.0, f)
	var ls := _fspl_db(V.dist(target.r, h) * 1000.0, f)
	var J := RF.db(float(j.Pj)) + gj + gv_j - lj
	var S := RF.db(float(up.Pt)) + gu + gv_s - ls
	return {"Pj_dbw": RF.db(float(j.Pj)), "Gj_dbi": gj, "aim_err": err, "Gv_j_dbi": gv_j, "victim_off": off, "Lj_db": lj, "J_dbw": J,
		"Pu_dbw": RF.db(float(up.Pt)), "Gu_dbi": gu, "Gv_s_dbi": gv_s, "Ls_db": ls, "S_dbw": S, "js_db": J - S}


## How close (km) the shooter must be for J/S to reach need (dB): the
## farthest point on the line from the target out through the shooter where
## the budget closes. Not J/S scaled by 1/R² alone: the jammer aims at our
## track, so a loose track that costs nothing far off (its error a sliver of
## a degree) pulls the beam off the target up close, and the reach shrinks as
## you approach. Searched on a log scale, then refined by bisection.
func jam_range_km(shooter: Dictionary, target: Dictionary, need: float) -> float:
	var R := V.dist(shooter.r, target.r)
	if R <= 0.0:
		return 0.0
	# The map asks every frame: the answer is kept for half a minute of game
	# time, or until the range changes by 2 %.
	var key := "%s|%s|%.1f|%d|%d|%s" % [shooter.id, target.id, need, int(sim.t / 30.0), int(log(R) * 50.0), technique_for(shooter.id, target.id)]
	if _reach.has(key):
		return _reach[key]
	if _reach.size() > 64:
		_reach.clear()
	_reach[key] = _jam_reach(shooter, target, need, R)
	return _reach[key]


var _reach := {}


func _jam_reach(shooter: Dictionary, target: Dictionary, need: float, R: float) -> float:
	var u := V.scale(V.sub(shooter.r, target.r), 1.0 / R)
	var probe := shooter.duplicate()
	var js_at := func(d: float) -> float:
		probe.r = V.add(target.r, V.scale(u, d))
		return js_db(probe, target)
	var far := maxf(R * 4.0, 2e5)
	var d := 0.05
	var best := 0.0
	var miss := 0.0
	while d <= far:
		if js_at.call(d) >= need:
			best = d
			miss = 0.0
		elif best > 0.0 and miss == 0.0:
			miss = d
		d *= 1.4
	if best <= 0.0:
		return 0.0
	if miss == 0.0:
		miss = best * 1.4
	for i in 20:
		var m := sqrt(best * miss)
		if js_at.call(m) >= need:
			best = m
		else:
			miss = m
	return best


## How far off our jammer's beam points from the target (rad), because it aims
## at our track's estimate; and the beam's half-width, for comparison.
func jam_aim(shooter: Dictionary, target: Dictionary) -> Dictionary:
	var t := js_terms(shooter, target)
	var bw := deg_to_rad(70.0 * RF.wavelength(float(cfg.jam.jammer.f)) / float(cfg.jam.jammer.dish))
	return {"err": float(t.aim_err), "half_bw": bw / 2.0, "scope": sees_to_aim(shooter, target), "track_err_km": V.dist(sim.tracks[target.id].pos(), target.r) if sim.tracks.has(target.id) else 0.0}


## Does the shooter's own telescope see the target (Sensing.ir_sees: S/N ≥ 5 in
## infrared or visible light)? Then the jammer is slaved to it: the telescope
## tracks the target in closed loop and the antenna mount follows its line of
## sight, the pointing, acquisition and tracking of space laser terminals
## (after Kaushal & Kaddoum 2017, IEEE Comm. Surveys & Tutorials 19(1); slaving an RF
## dish to the telescope is an extrapolation). The beam is
## then off by the telescope's bearing error alone, cfg.ir.bearingSigma
## (50 µrad, a design value), not by how far our track has wandered. Only Blue
## aims this way: Red's jamming isn't modelled.
func sees_to_aim(shooter: Dictionary, target: Dictionary) -> bool:
	return shooter.get("side", "") == "blue" and shooter.cls.has("ir") and sim.sensing.ir_sees(shooter, target)


## Can the shooter point a beam of this dish at the track? (3 dB beamwidth ≈ 70 λ/D degrees, Skolnik;
## NAWCWD TP 8347, §3-1.)
## What counts is how unsure the track is across the line of sight: a beam
## covers all of its length, so not knowing how far along it hardly matters.
func can_point(shooter: Dictionary, target_id: String, dish: float, f: float) -> bool:
	if not sim.tracks.has(target_id):
		return false
	if sees_to_aim(shooter, sim.by_id[target_id]):
		return true
	var tr: Track = sim.tracks[target_id]
	var bw := deg_to_rad(70.0 * RF.wavelength(f) / dish)
	return tr.cross_sigma(shooter.r) / maxf(1.0, V.dist(shooter.r, tr.pos())) < bw / 2.0


## Does the shooter's class carry this effect payload (classes.js payloads:
## "ccss" the jammer, "hpmx" the microwave projector, "cyber")?
static func carries(shooter: Dictionary, payload: String) -> bool:
	return payload in shooter.cls.get("payloads", [])


func laser(shooter: Dictionary) -> Dictionary:
	return shooter.cls.get("weapon", {}) if shooter.cls.get("weapon", {}).get("kind", "") == "laser" else {}


## Beam half-angle (rad): diffraction 1.22λ/D and jitter in quadrature, in 64-bit
## (Godot's Vector2 is 32-bit, which put a 1e-7 error on these ranges).
static func _spread(w: Dictionary) -> float:
	var d := 1.22 * float(w.lambda) / float(w.aperture)
	var j := float(w.jitter)
	return sqrt(d * d + j * j)


func spot_m(w: Dictionary, R_km: float) -> float:
	return R_km * 1000.0 * _spread(w)


## Irradiance (W/m²) the laser puts on a target at R km.
func irradiance(w: Dictionary, R_km: float) -> float:
	var s := spot_m(w, R_km)
	return float(w.power) / (PI * s * s)


func dazzle_range_km(w: Dictionary) -> float:
	var k := _spread(w)
	return sqrt(float(w.power) / (PI * float(cfg.dazzle.saturationWm2))) / k / 1000.0


func hpm_range_km() -> float:
	var h: Dictionary = cfg.hpm
	return sqrt(30.0 * float(h.peakW) * RF.from_db(h.gainDbi)) / float(h.upsetVm) / 1000.0


func escalate(by: float, why: String) -> void:
	var before := sim.escalation
	sim.escalation += by
	for mark in [50.0, 75.0, 90.0]:
		if before < mark and sim.escalation >= mark:
			sim.say("escalation_warn", Lang.f("escalation_warn", [int(mark)]), "alert")


## What each effect would take right now, for the Selected item window.
## Returns [{key, ok, line, cost}] in the player's language.
func options(shooter_id: String, target_id: String) -> Array:
	if cfg.is_empty():
		return [] # a scenario with no effects (CLOSE PASS at the Earth: an inspector carries none)
	var sh: Dictionary = sim.by_id[shooter_id]
	var tg: Dictionary = sim.by_id[target_id]
	var R := V.dist(sh.r, tg.r)
	var out := []
	var tr: Track = sim.tracks.get(target_id)
	var hostile := tr != null and tr.side == "hostile"
	var d := Lang.doctrinal
	var need: float = cfg.jam.needJsDb
	var js := js_db(sh, tg)
	var point := can_point(sh, target_id, cfg.jam.jammer.dish, cfg.jam.jammer.f)
	var jr := jam_range_km(sh, tg, need)
	var not_red := "" if hostile else ("Not a known enemy" if not d else "ROE: target not declared hostile")
	# What each effect needs, as conditions met or not, for the tooltip cards:
	# [met, the short line], met null for a note. The enemy check comes first.
	# "doc": more card lines to follow the checks: a gauge of the live value,
	# then (doctrinal terms only) the real terms and the formula the code
	# computes, as "[bar]", "[d]" and "[f]" lines.
	var foe := [hostile, ("A known enemy" if hostile else "Not a known enemy: identify it first") if not d else ("Declared hostile" if hostile else "Not declared hostile (ROE)")]
	var aim := jam_aim(sh, tg) if tr != null else {"err": 0.0, "half_bw": 1.0, "track_err_km": 0.0}
	var on_beam: bool = float(aim.err) <= float(aim.half_bw)
	var scope: bool = aim.get("scope", false)
	var beam := [on_beam, ((("Beam on it, steered by our telescope" if scope else "Beam on it") if on_beam else "Beam %.0f° off it: fix %s out. Close in or tighten it" % [rad_to_deg(float(aim.err)), _km(float(aim.track_err_km))]) if not d
		else (("On target: slaved to the IR track" if scope else "On target") if on_beam else "Aim error %.1f° > ½ beamwidth %.1f° · track off %s" % [rad_to_deg(float(aim.err)), rad_to_deg(float(aim.half_bw)), _km(float(aim.track_err_km))]))]
	var fix := [point, ((("Our telescope sees it to aim" if scope else "Fix tight enough to aim") if point else "Fix too loose to aim") if not d
		else (("Pointing slaved to the IR track" if scope else "AOU across the LOS < ½ beamwidth") if point else "AOU across the LOS > ½ beamwidth"))]
	# Jam
	var jam_line: String
	if not point:
		jam_line = "Fix too loose to aim the beam" if not d else "Track too loose to point (AOU > beamwidth)"
	elif js < need and not on_beam:
		jam_line = ("Beam off it: fix %s out. Close in or tighten it" % _km(float(aim.track_err_km))) if not d else ("J/S %+.1f dB: aim error %.1f° > ½ beamwidth" % [js, rad_to_deg(float(aim.err))])
	elif js < need:
		jam_line = ("Too far: get within %s (now %s)" % [_km(jr), _km(R)]) if not d else ("J/S %+.1f dB, need +%.0f · close to %s" % [js, need, _km(jr)])
	else:
		jam_line = "Close enough: it loses its orders" if not d else ("J/S %+.1f dB: uplink denied" % js)
	var jams := carries(sh, "ccss")
	var tech := technique_for(shooter_id, target_id)
	var up := uplink(target_id)
	if not d:
		jam_line += ("  ·  SPOT on %.1f MHz" % (float(up.up) / 1e6)) if tech == "spot" else "  ·  BARRAGE: identify its signal to spot-jam"
	else:
		jam_line += ("  ·  SPOT %.1f MHz" % (float(up.up) / 1e6)) if tech == "spot" else ("  ·  BARRAGE −%.1f dB" % spread_db(shooter_id, target_id))
	if jams:
		var T := js_terms(sh, tg)
		out.append({"key": "jam", "ok": hostile and js >= need and point, "technique": tech, "on": jamming.get(shooter_id, {}).get("mode", "") == "jam",
			"line": not_red if not hostile else jam_line,
			"what": "Drown out its controller's orders. Cut off 3 hours with one of ours alongside, it gives up and leaves; alone, it waits." if not d else "Deny the handler's command uplink. Denied 3 h with a Blue ship inside 25 km, it aborts; otherwise it holds.",
			"checks": [foe, fix] + ([beam] if js < need and not on_beam else []) + [[js >= need, (("In reach: %s now, works to %s" % [_km(R), _km(jr)]) if js >= need else (("Too far: %s now, works inside %s" % [_km(R), _km(jr)]) if jr > 0.0 else "Out of reach until the beam is on it")) if not d
					else "J/S %+.1f dB, need +%.0f · reach %s" % [js, need, _km(jr)]],
				[null, (("Spot: all its power on its channel, %.1f MHz" % (float(up.up) / 1e6)) if tech == "spot" else "Barrage: identify its signal to spot-jam") if not d
					else (("Spot: uplink %.1f MHz, its downlink × 749/880" % (float(up.up) / 1e6)) if tech == "spot" else "Barrage over 45 MHz: −%.1f dB spread" % spread_db(shooter_id, target_id))]],
			"doc": ["[bar] Reach %s · you are at %s | %f | %f | %s" % [_km(jr), _km(R), jr, maxf(R, 1e-6), "#b4c8dc" if js >= need else "#ce9440"],
				"[d] J %.1f dBW · S %.1f dBW · J/S %+.1f dB" % [float(T.J_dbw), float(T.S_dbw), js],
				"[f] J = Pj + Gj(aim) + Gv(off axis) − Lj",
				"[f] S = Pu + Gu + Gv(0) − Ls",
				"[f] J/S = J − S − spread  dB",
				"[f] L = 20·log(4πRf/c)",
				"[d] [i] Friis budget, ITU-R dish patterns; JP 3-85"],
			"cost": ("Everyone hears you while it runs · escalation +%.0f/h" if not d else "EMCON broken · escalation +%.0f/h") % float(cfg.jam.escalationPerHour),
			"tip": "%s || %s\nDrown out its controller's orders. Stop and it hears again.\n[d] Uplink jamming through the victim's sidelobe, against the handler's main lobe" % Lang.TX.jam})
	# Spoof
	var sp_need := float(cfg.spoof.needJsDb)
	var sp_line: String
	if tg.role != "tender":
		sp_line = "Only on a ship that steers by its controller's ranging" if not d else "Target does not navigate by handler ranging"
	elif not point or js < sp_need:
		sp_line = ("Too far: get within %s" % _km(jam_range_km(sh, tg, sp_need))) if not d else ("J/S %+.1f dB, need %+.0f" % [js, sp_need])
	else:
		sp_line = ("Fed a false position: drifts ~%.0f km off an hour" if not d else "Ranging deception: %.0f km/h induced error") % float(cfg.spoof.driftKmPerHour)
	if jams:
		out.append({"key": "spoof", "ok": hostile and js >= sp_need and point and tg.role == "tender", "on": jamming.get(shooter_id, {}).get("mode", "") == "spoof",
			"line": not_red if not hostile else sp_line,
			"what": "Fake the ranging tones it steers by, so it drifts off course." if not d else "Deceive the handler's ranging so its orbit solution drifts.",
			"checks": [foe, [tg.role == "tender", (("Steers by its controller's ranging" if tg.role == "tender" else "Doesn't steer by ranging: no effect") if not d else ("Navigates by handler ranging" if tg.role == "tender" else "Not ranging-dependent"))], fix,
				[js >= sp_need, (("Close enough" if js >= sp_need else "Too far: get within %s" % _km(jam_range_km(sh, tg, sp_need))) if not d else "J/S %+.1f dB, need %+.0f" % [js, sp_need])],
				[null, ("Drifts ~%.0f km off course an hour" if not d else "Induced error %.0f km/h") % float(cfg.spoof.driftKmPerHour)]],
			"doc": ["[f] J/S as for jamming, need %+.0f dB" % sp_need, "[f] error += %.0f km/h × t" % float(cfg.spoof.driftKmPerHour)],
			"cost": ("You can be heard · escalation +%.0f" if not d else "EMCON broken · escalation +%.0f") % float(cfg.spoof.escalation),
			"tip": "%s || %s\nIt steers by a false position and wastes fuel correcting. Reversible." % Lang.TX.spoof})
	var w := laser(sh)
	if not w.is_empty():
		var E := irradiance(w, R)
		var sat := float(cfg.dazzle.saturationWm2)
		var sees := sim.sensing.ir_sees(sh, tg)
		var dz: String
		if not sees:
			dz = "Can't see it from here to aim" if not d else "No IR track: cannot point"
		elif E < sat:
			dz = ("Too far: get within %s (now %s)" % [_km(dazzle_range_km(w)), _km(R)]) if not d else ("%.1f W/m² on target, need %.0f · reach %s" % [E, sat, _km(dazzle_range_km(w))])
		else:
			dz = ("Close enough: blinds it for %d hours" if not d else "Irradiance sufficient: sensor saturated %d h") % int(cfg.dazzle.blindHours)
		out.append({"key": "dazzle", "ok": hostile and sees and E >= sat, "line": not_red if not hostile else dz,
			"what": ("Shine the laser into its telescope. Blind for %d hours. Reversible." if not d else "Saturate its IR focal plane with the laser for %d h. Reversible.") % int(cfg.dazzle.blindHours),
			"checks": [foe, [sees, (("Our telescope sees it to aim" if sees else "Can't see it from here to aim") if not d else ("IR track: director can point" if sees else "No IR track: cannot point"))],
				[E >= sat, (("Close enough" if E >= sat else "Too far: %s now, works inside %s" % [_km(R), _km(dazzle_range_km(w))]) if not d else "%s W/m² on target, need %.0f · reach %s" % [_g(E), sat, _km(dazzle_range_km(w))])]],
			"doc": ["[bar] Light on it | %f | %f | %s" % [E, sat, "#b4c8dc" if E >= sat else "#ce9440"],
				"[d] Spot %.2f m at %s · E %s W/m²" % [spot_m(w, R), _km(R), _g(E)],
				"[f] spot = R·√((1.22λ/D)² + j²)",
				"[f] E = P / (π·spot²) ≥ Esat",
				"[d] [i] 1.22λ/D after Hecht 2017; jitter in quadrature (engineering approximation)"],
			"cost": ("Heats your radiators: seen from farther · escalation +%.0f" if not d else "Thermal signature up · escalation +%.0f") % float(cfg.dazzle.escalation),
			"tip": "%s || %s\nThe beam spreads with distance, so range matters. Reversible." % Lang.TX.dazzle})
	if carries(sh, "hpmx"):
		var hr := hpm_range_km()
		var Eh := sqrt(30.0 * float(cfg.hpm.peakW) * RF.from_db(cfg.hpm.gainDbi)) / maxf(R * 1000.0, 1e-6)
		out.append({"key": "hpm", "ok": hostile and R <= hr, "line": not_red if not hostile else ((("Close enough: it would burn out its electronics" if R <= hr else "Need to be within %s (now %s)" % [_km(hr), _km(R)])) if not d else ("Range %s, effective inside %s" % [_km(R), _km(hr)])),
			"what": "A microwave pulse that burns out its electronics. Permanent, no debris." if not d else "HPM: a nanosecond pulse past the upset threshold. Irreversible, no debris.",
			"checks": [foe, [R <= hr, (("Close enough" if R <= hr else "Too far: %s now, works inside %s" % [_km(R), _km(hr)]) if not d else "E %s V/m at %s, upset %.0f V/m" % [_g(Eh), _km(R), float(cfg.hpm.upsetVm)])]],
			"doc": ["[bar] Field on it | %f | %f | %s" % [Eh, float(cfg.hpm.upsetVm), "#b4c8dc" if R <= hr else "#ce9440"],
				"[f] E = √(30·P·G) / R",
				"[f] reach = √(30·P·G) / E_upset",
				"[d] [i] After Balanis 2016"],
			"cost": ("Permanent, but no debris · escalation +%.0f" if not d else "Irreversible · escalation +%.0f") % float(cfg.hpm.escalation),
			"tip": "%s || %s\nThe field weakens with distance: close range only. The ship stays whole." % Lang.TX.hpm})
	var heard := int(tg.get("heard_strong", 0))
	var need_n := int(cfg.cyber.interceptsNeeded)
	# Take it only while our jammer holds its controller off: otherwise its owner just commands it back.
	var held: bool = jamming.get(shooter_id, {}).get("mode", "") == "jam" and String(jamming.get(shooter_id, {}).get("target", "")) == target_id
	var cy: String
	if heard < need_n:
		cy = ("Record %d more clear messages first (%d of %d)" if not d else "Insufficient collection: %d more strong intercepts (%d/%d)") % [need_n - heard, heard, need_n]
	elif js < float(cfg.cyber.needJsDb) or not point:
		cy = ("Codes learned. Get within %s to take over" % _km(jr)) if not d else ("Link exploitable; J/S %+.1f dB, need +%.0f" % [js, float(cfg.cyber.needJsDb)])
	elif not held:
		cy = "Jam its orders first, so its owner can't take it back" if not d else "Requires active uplink denial (jam) on this target"
	else:
		cy = "Ready: send it your own orders" if not d else "Ready: command-link capture"
	if jams and carries(sh, "cyber"):
		out.append({"key": "cyber", "ok": hostile and heard >= need_n and js >= float(cfg.cyber.needJsDb) and point and held, "line": not_red if not hostile else cy,
			"what": "Out-shout its controller in its own codes. It's yours from then on." if not d else "Exploit its command link and take control of it.",
			"checks": [foe, [heard >= need_n, (("Its codes learned" if heard >= need_n else "Record %d more clear messages: identify its strong signals" % (need_n - heard)) if not d else "Collection %d/%d strong intercepts" % [heard, need_n])], fix,
				[js >= float(cfg.cyber.needJsDb), (("Close enough" if js >= float(cfg.cyber.needJsDb) else "Too far: get within %s" % _km(jam_range_km(sh, tg, float(cfg.cyber.needJsDb)))) if not d else "J/S %+.1f dB, need +%.0f" % [js, float(cfg.cyber.needJsDb)])],
				[held, ("Your jammer is holding its controller off" if held else "Jam its orders first: its owner would command it back") if not d else ("Uplink denied" if held else "Uplink not denied")]],
			"doc": ["[bar] Messages recorded %d of %d | %d | %d" % [mini(heard, need_n), need_n, mini(heard, need_n), need_n],
				"[f] J/S as for jamming, need +%.0f dB" % float(cfg.cyber.needJsDb)],
			"cost": ("You keep it, and its records name its friends · escalation +%.0f" if not d else "Exploitation reveals linked tracks · escalation +%.0f") % float(cfg.cyber.escalation),
			"tip": "%s || %s\nRecord its messages (Identify signal on strong ones), then out-shout its controller." % Lang.TX.cyber})
	if sh.cls.get("weapon", {}).get("kind", "") == "kinetic":
		var k := kv_check(sh, target_id)
		var kdoc := []
		if k.ok:
			kdoc = ["[bar] Chance to hit | %f | 1 | #b4c8dc" % float(k.pk), "[d] Divert reach %s vs 1σ %s" % [_km(float(k.reach)), _km(float(k.sigma))]]
		kdoc += ["[f] t_go = R / (v_close + v_boost)", "[f] reach = divert · t_go / 2", "[f] Pk = rel · (1 − e^(−reach²/2σ²))", "[d] [i] Pk: Rayleigh CDF (Papoulis & Pillai 2002); t_go and reach are design values"]
		out.append({"key": "kinetic", "ok": hostile and k.ok, "line": not_red if not hostile else k.line,
			"what": "Fire an interceptor where our track says it will be. The last resort." if not d else "Hit-to-kill: a KV on a Lambert transfer to the track's forecast.",
			"checks": [foe, [k.ok, k.line]],
			"doc": kdoc,
			"cost": ("Debris for years · can't be undone · escalation +%.0f" if not d else "Debris-generating, irreversible · escalation +%.0f") % float(cfg.kinetic.escalation),
			"tip": "%s || %s\nIt steers only so far before it arrives. Outside that, or if it dodges, it misses." % Lang.TX.kinetic})
	return out


func _km(x: float) -> String:
	return Lang.km(x)


## A number to three significant figures, for the cards (GDScript has no %g).
static func _g(x: float) -> String:
	return String.num(x, clampi(2 - int(floor(log(maxf(absf(x), 1e-12)) / log(10.0))), 0, 12))


func kv_check(sh: Dictionary, target_id: String) -> Dictionary:
	var w: Dictionary = sh.cls.weapon
	var rounds := int(sh.get("rounds", w.rounds))
	if rounds <= 0:
		return {"ok": false, "line": "No interceptors left" if not Lang.doctrinal else "Magazine empty"}
	var tr: Track = sim.tracks.get(target_id)
	if tr == null:
		return {"ok": false, "line": "No track on it" if not Lang.doctrinal else "No track"}
	var R := V.dist(sh.r, tr.pos())
	var d := V.sub(tr.pos(), sh.r)
	var closing := -V.dot(d, V.sub(tr.vel(), sh.v)) / maxf(V.norm(d), 1e-9)
	var v := maxf(0.1, closing + float(w.boost))
	var tgo := R / v
	if tgo > float(w.maxFlight):
		return {"ok": false, "line": ("Too far: %s to get there, max %s" if not Lang.doctrinal else "Out of range: TOF %s > %s") % [_hm(tgo), _hm(float(w.maxFlight))]}
	var reach := float(w.divert) * tgo / 2.0
	var sigma: float = tr.forecast(sim.t + tgo, true).ellipse().major
	var pk := kill_probability(reach, sigma, float(w.reliability))
	return {"ok": true, "line": ("%d%% chance to hit · arrives in %s · %d left" if not Lang.doctrinal else "Pk %d%% · TOF %s · %d rounds") % [int(pk * 100.0), _hm(tgo), rounds], "pk": pk, "tgo": tgo, "reach": reach, "sigma": sigma}


## Chance a kill vehicle that can divert reach km hits a target whose position
## is uncertain by sigma km (1σ, taken circular): the Rayleigh CDF
## 1 − exp(−reach²/2σ²) (Papoulis & Pillai 2002; DTIC AD1043284, Rayleigh/CEP),
## times the round's reliability.
static func kill_probability(reach: float, sigma: float, reliability: float) -> float:
	return reliability * (1.0 - exp(-(reach * reach) / (2.0 * sigma * sigma)))


func _hm(t: float) -> String:
	var m := int(round(t / 60.0))
	return "%d m" % m if m < 60 else "%d h %02d m" % [m / 60, m % 60]


## The player chooses an effect.
func use(key: String, shooter_id: String, target_id: String) -> bool:
	var sh: Dictionary = sim.by_id[shooter_id]
	var tg: Dictionary = sim.by_id[target_id]
	var opt := {}
	for o in options(shooter_id, target_id):
		if o.key == key:
			opt = o
	if (key == "jam" or key == "spoof") and jamming.get(shooter_id, {}).get("mode", "") == key:
		jamming.erase(shooter_id)
		return true
	if opt.is_empty() or not opt.ok:
		return false
	var label: String = sim.tracks[target_id].label
	match key:
		"jam", "spoof":
			jamming[shooter_id] = {"target": target_id, "mode": key}
			sim.say("jam_on", Lang.f("jam_on" if key == "jam" else "spoof_on", [sh.short, label]), "warn", {"from": shooter_id, "to": target_id})
			if key == "spoof" and not tg.get("spoof_charged", false):
				tg.spoof_charged = true
				escalate(float(cfg.spoof.escalation), "spoof")
		"dazzle":
			tg.dazzled_until = sim.t + float(cfg.dazzle.blindHours) * H
			sh.laser_at = target_id # the director slews onto it (Rig)
			sh.laser_fired = sim.t # its 3 MW of waste heat goes to the radiators for the dwell (Thermal.step)
			escalate(float(cfg.dazzle.escalation), "dazzle")
			sim.say("dazzle_hit", Lang.f("dazzle_hit", [label, int(cfg.dazzle.blindHours)]), "good", {"from": shooter_id, "to": target_id})
		"hpm":
			tg.disabled = true
			escalate(float(cfg.hpm.escalation), "hpm")
			sim.say("hpm_hit", Lang.f("hpm_hit", [label]), "good", {"from": shooter_id, "to": target_id})
		"cyber":
			tg.captured = true
			escalate(float(cfg.cyber.escalation), "cyber")
			sim.say("cyber_hit", Lang.f("cyber_hit", [label]), "good", {"from": shooter_id, "to": target_id})
			_exploit(tg)
		"kinetic":
			_launch(sh, target_id)
	return true


## A captured node's logs: rough tracks on the Red ships it talked to.
func _exploit(tg: Dictionary) -> void:
	for r in sim.red_ships():
		if r.id == tg.id or not r.alive or sim.tracks.has(r.id):
			continue
		if tg.role == "relay" or r.role == "relay":
			var P := Track.diag([3000.0 ** 2, 3000.0 ** 2, 0.2 ** 2, 0.2 ** 2])
			var x := PackedFloat64Array([r.r[0] + sim.stream("effects").randfn() * 2000.0, r.r[1] + sim.stream("effects").randfn() * 2000.0, r.v[0], r.v[1]])
			if sim.sensing.dims == 3:
				P = Track.diag([3000.0 ** 2, 3000.0 ** 2, 3000.0 ** 2, 0.2 ** 2, 0.2 ** 2, 0.2 ** 2])
				x = PackedFloat64Array([x[0], x[1], r.r[2] + sim.stream("effects").randfn() * 2000.0, r.v[0], r.v[1], r.v[2]])
			var tr := Track.new(r.id, "TRK %d" % sim.track_n, x, P, sim.t)
			sim.track_n += 3
			tr.ident = "classified"
			tr.class_id = r.classId
			tr.side = "hostile"
			sim.tracks[r.id] = tr
			sim.say("new_track", Lang.f("new_track", [tr.label, sim.sensing._where(tr.pos())]), "alert")


func _launch(sh: Dictionary, target_id: String) -> void:
	var k := kv_check(sh, target_id)
	var tr: Track = sim.tracks[target_id]
	var aim := tr.forecast(sim.t + k.tgo).pos()
	var sol := Lambert.solve(sh.r, aim, k.tgo, sim.mu, true, V.cross(sh.r, sh.v))
	if sol.is_empty():
		return
	sh.rounds = int(sh.get("rounds", sh.cls.weapon.rounds)) - 1
	var n := 1
	while sim.by_id.has("kv%d" % n):
		n += 1
	var cid := String(sh.cls.weapon.get("kv", "skv"))
	sim._add({"id": "kv%d" % n, "classId": cid, "name": "%s-%d" % [String(sim.data.classes[cid].name), n], "short": "KV-%d" % n,
		"side": "blue", "kind": "kv", "role": "HIT-TO-KILL · ON %s" % tr.label, "operator": String(sh.get("operator", "")), "flag": String(sh.get("flag", "")),
		"status": "IN FLIGHT", "from": sh.id, "r0": [sh.r[0], sh.r[1], sh.r[2]], "v0": [sol[0][0], sol[0][1], sol[0][2]], "t0": sim.t})
	kvs.append({"id": "kv%d" % n, "target": target_id, "launch": sim.t, "arrive": sim.t + k.tgo, "aim": aim, "reach": k.reach,
		"rel": float(sh.cls.weapon.reliability), "acquired": false, "jinked": false, "done": false, "fix_at": -1e9, "result": ""})
	escalate(float(cfg.kinetic.escalation), "kinetic")
	sim.say("kv_away", Lang.f("kv_away", [tr.label, int(k.pk * 100.0), _hm(k.tgo)]), "warn", {"from": sh.id, "to": target_id, "kv": "kv%d" % n})


## The flight's object, or {} once it is gone.
func kv_ship(kv: Dictionary) -> Dictionary:
	return sim.by_id.get(kv.id, {})


## The shortest step the world may take now: fine while a kill vehicle homes.
func max_step() -> float:
	var h := INF
	for kv in kvs:
		if not kv.done:
			h = minf(h, 2.0 if float(kv.arrive) - sim.t < 120.0 else GUIDE_EVERY)
	return h


## Continuous parts, every integration step: interceptors home and hit, close passes are caught between samples.
func step(h: float) -> void:
	var now := sim.t + h # the ships have already moved to now
	for kv in kvs:
		if kv.done:
			continue
		var k := kv_ship(kv)
		var tg: Dictionary = sim.by_id[kv.target]
		if k.is_empty():
			kv.done = true
			continue
		# The target jinks once, if it sees the kill vehicle coming and can spare the fuel.
		if not kv.jinked and tg.alive and tg.cls.has("ir") and sim.red.can_see(tg) and sim.sensing.ir_sees(tg, k):
			kv.jinked = true
			var los := V.sub(k.r, tg.r)
			var nrm := V.scale(V.of(-los[1], los[0]), 1.0 / maxf(V.norm(los), 1e-9))
			var dv := minf(1.0, sim.delta_v(tg.id) - 0.3)
			if dv > 0.2:
				sim.burn(tg.id, V.scale(nrm, dv * (1.0 if sim.stream("effects").randf() < 0.5 else -1.0)))
		var tgo := float(kv.arrive) - now
		# The seeker: it steers only on what it can see itself.
		if not kv.acquired and tg.alive and sim.sensing.ir_sees(k, tg):
			kv.acquired = true
			kv.acquired_at = now
		if kv.acquired and tg.alive and tgo > GUIDE_LAST and now - float(kv.fix_at) >= GUIDE_EVERY:
			kv.fix_at = now
			_divert(k, tg, now, tgo)
		if now >= float(kv.arrive) - 1e-6:
			_arrive(kv, k, tg, now)


## One course correction: the velocity that meets the target where it will
## truly be at the planned time, as much of it as the divert fuel allows.
## Lambert's two-body arc is shot through the game's real gravity (J2, the
## moons) and its aim moved by the miss until it lands within 20 cm (as
## Sim.refine does for transfers).
func _divert(k: Dictionary, tg: Dictionary, now: float, tgo: float) -> void:
	var sub := minf(10.0, tgo / 4.0)
	# Where the seeker puts the target: off by its angular error, across the line of sight.
	var los := V.sub(tg.r, k.r)
	var R := V.norm(los)
	var e := V.of(sim.stream("effects").randfn(), sim.stream("effects").randfn(), sim.stream("effects").randfn())
	e = V.sub(e, V.scale(los, V.dot(e, los) / maxf(R * R, 1e-12)))
	var seen := V.add(tg.r, V.scale(e, SEEKER_RAD * R))
	var goal: PackedFloat64Array = sim.gravity.coast(seen, tg.v, now, tgo, sub)[0]
	var aim := goal
	var v1 := PackedFloat64Array()
	for i in 6:
		var sol := Lambert.solve(k.r, aim, tgo, sim.mu)
		if sol.is_empty():
			return
		v1 = sol[0]
		var miss := V.sub(sim.gravity.coast(k.r, v1, now, tgo, sub)[0], goal)
		if V.norm(miss) < 2e-4:
			break
		aim = V.sub(aim, miss)
	var dv := V.sub(v1, k.v)
	var need := V.norm(dv)
	if need < 1e-4:
		return
	var have := sim.delta_v(k.id)
	if have <= 1e-6:
		return
	if need > have:
		dv = V.scale(dv, (have - 1e-9) / need)
	sim.burn(k.id, dv)


## The planned meeting time: where both are, how close it passed, and what that did.
func _arrive(kv: Dictionary, k: Dictionary, tg: Dictionary, now: float) -> void:
	kv.done = true
	var back := now - float(kv.arrive)
	var kr: PackedFloat64Array = Kepler.propagate(k.r, k.v, -back, sim.mu)[0] if back > 1e-6 else k.r
	var tr_: PackedFloat64Array = Kepler.propagate(tg.r, tg.v, -back, sim.mu)[0] if back > 1e-6 else tg.r
	var miss := V.dist(kr, tr_)
	kv.miss_km = miss
	var hard := (float(tg.cls.get("length", 10.0)) / 2.0 + 0.3) / 1000.0 # the hull's half-length plus the KV's radius, km
	var label: String = sim.tracks[kv.target].label if sim.tracks.has(kv.target) else String(tg.short)
	if tg.alive and miss <= hard and sim.stream("effects").randf() < float(kv.rel):
		kv.result = "hit"
		impact(k, tg)
		return
	kv.result = "miss"
	# Spent: it coasts on, inert, an object in its own right.
	k.status = "SPENT · INERT"
	k.role = "SPENT KILL VEHICLE"
	sim.say("kv_miss", Lang.f("kv_miss", [label, ("%.0f m" % (miss * 1000.0)) if miss < 1.0 else _km(miss)]), "warn", {"to": kv.target, "kv": kv.id})


## A hypervelocity hit of projectile p on target tg (Breakup): breaks it up or
## craters it, and leaves the debris either way.
func impact(p: Dictionary, tg: Dictionary) -> Dictionary:
	var vrel := V.sub(p.v, tg.v)
	var v := V.norm(vrel)
	var mp := Breakup.mass_kg(p)
	var mt := Breakup.mass_kg(tg)
	var e := Breakup.emr(mp, v, mt)
	# A site on a moon's surface is anchored to the moon: the ground takes the
	# blow, so it cannot break up into orbit, be pushed or set tumbling. The
	# crater's ejecta are not tracked (design simplification).
	var ground := tg.has("onMoon")
	var cat := e >= Breakup.EMR_CATASTROPHIC and not ground
	var M := Breakup.collision_mass(mp, v, mt)
	var label: String = sim.tracks[tg.id].label if sim.tracks.has(tg.id) else String(tg.short)
	p.alive = false
	p.destroyed = true
	var out := {"emr": e, "cat": cat, "M": M, "v": v, "tags": []}
	if cat:
		# Everything breaks up; the cloud moves with the pair's centre of mass.
		var vc := V.scale(V.add(V.scale(tg.v, mt), V.scale(p.v, mp)), 1.0 / (mt + mp))
		var c := Breakup.cloud(tg.r, vc, sim.t, M, true, tg.id, sim.stream("breakup"))
		sim.debris.append(c)
		tg.alive = false
		tg.destroyed = true
		out.n = c.n
		sim.say("kv_hit", Lang.f("kv_hit", [label, c.n]), "good", {"to": tg.id, "from": p.id, "emr": e})
	else:
		# Cratered: the struck components are gone, the target is pushed by the
		# projectile's momentum, and the ejecta make a smaller cloud.
		var hull: Dictionary = sim.data.hulls.get(String(tg.classId), {})
		var hits := []
		var tags := Breakup.struck(tg, hull, sim.stream("breakup"), hits)
		Damage.apply(tg, sim.data.classes[tg.classId], tags)
		for h in hits:
			h.t = sim.t
		var all_hits: Array = tg.get("hits", [])
		all_hits.append_array(hits)
		tg.hits = all_hits
		out.tags = tags
		out.n = 0
		if not ground:
			# Pushed and set tumbling about its centre of mass by the hit.
			var sp := Breakup.spin(tg, hull, mp, vrel, float(hits[0].x) if not hits.is_empty() else float(tg.cls.get("length", 10.0)) / 2.0, sim.stream("breakup"))
			sp.t0 = sim.t
			tg.spin = sp
			tg.v = V.add(tg.v, V.scale(vrel, mp / mt))
			var c := Breakup.cloud(tg.r, tg.v, sim.t, M, false, tg.id, sim.stream("breakup"))
			sim.debris.append(c)
			out.n = c.n
		sim.say("kv_cripple", Lang.f("kv_cripple", [label, Damage.describe(tags), out.n]), "good", {"to": tg.id, "from": p.id, "emr": e})
	return out


## Every look: running jammers, radar, and their price.
func tick(dt: float) -> void:
	for sid in jamming.keys():
		var j: Dictionary = jamming[sid]
		var sh: Dictionary = sim.by_id[sid]
		var tg: Dictionary = sim.by_id[j.target]
		if not sh.alive or not tg.alive:
			jamming.erase(sid)
			continue
		sh.loud_until = sim.t + dt
		escalate(float(cfg.jam.escalationPerHour) * dt / H, "jam")
		var js := js_db(sh, tg)
		var point := can_point(sh, j.target, cfg.jam.jammer.dish, cfg.jam.jammer.f)
		if j.mode == "jam" and js >= float(cfg.jam.needJsDb) and point:
			if float(tg.get("jammed_until", -1.0)) < sim.t:
				tg.jam_since = sim.t # cut off from now: the HUD shows how long
				sim.say("jam_hit", Lang.f("jam_hit", [sim.tracks[j.target].label]), "good")
			tg.jammed_until = sim.t + dt + 1.0
		elif j.mode == "spoof" and js >= float(cfg.spoof.needJsDb) and point:
			tg.spoof_err_km = float(tg.get("spoof_err_km", 0.0)) + float(cfg.spoof.driftKmPerHour) * dt / H
	for sid in radar_on:
		if radar_on[sid]:
			sim.by_id[sid].loud_until = sim.t + dt
			escalate(float(cfg.radarPerHour) * dt / H, "radar")
