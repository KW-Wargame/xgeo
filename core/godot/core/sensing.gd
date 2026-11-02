## Space domain awareness: everything Blue can learn, and nothing more.
## The only way truth reaches Blue's tracks is through here.
## - IR looks: what a ship radiates in the 6–10 µm band toward the sensor (skin,
##   radiators by aspect, a hot drive; Thermal) over R², against the sensor's
##   in-band noise-equivalent irradiance, gives an SNR; each look detects with
##   Pd = Φ(SNR − 5) (NEO Surveyor's S/N-5 threshold), and noise alone sometimes
##   crosses it (false alarms). Jupiter blocks the line of sight, and its bright
##   disc behind a target raises the noise.
## - Visible looks: sunlight a sunlit hull scatters (Lambert sphere), against a
##   GEODSS-class limiting magnitude. Nothing in Jupiter's shadow is seen this way.
## - Radio: each Red command burst is heard by an ear with the probability an
##   energy detector gives (RF.detect_pd) for its Friis-over-kTB SNR integrated
##   for the burst (radiometer equation). Both antennas follow the ITU-R patterns
##   (Antenna): an emitter aims at whoever it talks to, so Blue mostly hears a
##   sidelobe. Warships and buoys carry receive arrays that hear every direction
##   at once; Ganymede's 12 m dish hears far but only where it points (tip and cue).
## - Direction finding: an interferometer gives a bearing to
##   σ = λ/(2πd)·σφ, σφ ≈ 1/(√2·SNR) for the cross-correlation phase (RF.df_sigma);
##   lines from two ears cross into a fix.
## - Identification: a strong enough recording measures the modulation
##   (classify); a close telescope look names the hull (identify).
## - In a 3-D world (dims 3: a world about another body than Jupiter, or ships
##   off the plane) tracks are 3-D and every angle is a direction, a unit
##   vector with sigma in each of the two angles across it. Ground sites
##   (kind "site", on the turning Earth) carry radars that are always on and
##   see above their elevation mask. Objects in the public catalogue (the
##   scenario's "catalogued") start with a track.
class_name Sensing
extends RefCounted

## The world this belongs to, held weakly: Sim holds this too, and a strong
## reference each way is a cycle that RefCounted never frees.
var sim: Sim:
	get:
		return _sim.get_ref()
	set(v):
		_sim = weakref(v)
var _sim := WeakRef.new()
var pending := {} # ship id -> recent bearing lines not yet a track
var auto := false # analyse every intercept as it arrives
const DF_FLOOR := 20e-6 # rad
var last_look := 0.0
## Single-look detections that are not yet tracks, false alarms among them: {t, from, bearing, by}.
## Only lines from two places at once that cross make a track, so a false alarm never does.
var false_lines: Array = []
## Where each pointed dish looks: ear id -> {"mode": "auto" | "track" | "park", "track": ship id}.
## "auto" (the assist) points at the hostile or unknown track seen most recently.
var dish_aim := {}
## Position components of Blue's tracks: 2 in the planar campaign, 3 in a
## world that is not (set by begin()).
var dims := 2


## The class to assume for a track Blue has not classified, when asking what
## its telescope could see: the most sensitive infrared telescope among the
## scenario's classes that are not Blue's own (assume the worst), or "" if
## there is none. From the scenario's data, so no scenario's names are built in.
static func worst_ir(sim: Sim) -> String:
	# Red's order of battle in this scenario (what intelligence says it fields),
	# not every class in the data: a Blue design nobody fields here is no Red eye.
	var red := {}
	for s in sim.ships:
		if s.side == "red":
			red[String(s.classId)] = true
	var best := ""
	var nei := INF
	for cid in red:
		var c: Dictionary = sim.data.classes.get(cid, {})
		if not c.has("ir"):
			continue
		var n := float(c.ir.get("neiBand", c.ir.get("nei", INF)))
		if n < nei:
			nei = n
			best = cid
	return best


## The class Blue assumes for track tr's telescope: its assessed class if
## that carries one, else the worst case (worst_ir). "" if none could.
static func eye_class(sim: Sim, tr: Track) -> String:
	if tr.class_id != "":
		return tr.class_id if sim.data.classes.get(tr.class_id, {}).has("ir") else ""
	return worst_ir(sim)


func _init(sim_: Sim) -> void:
	sim = sim_


func gauss() -> float:
	return sim.stream("sensing").randfn(0.0, 1.0)


## The opening picture: a ship with "opening_track" (its label) starts with a
## track, already seen but loose (the scenario's opening sigma_km, sigma_kms),
## and the scenario's opening cue says how it was found; one with
## "beacon_track" starts named by its beacon, tight and identified.
func begin() -> void:
	dims = world_dims(sim)
	# The scenario's opening, or game.json's own when it runs alone.
	var op: Dictionary = sim.camp.get("opening", sim.data.scenario.get("opening", {}))
	for h in sim.ships:
		if h.has("opening_track"):
			var sp := float(op.get("sigma_km", 3000.0))
			var sv := float(op.get("sigma_kms", 0.3))
			var P := Track.diag([(sp * 4.0 / 3.0) ** 2, (sp * 4.0 / 3.0) ** 2, (sv * 4.0 / 3.0) ** 2, (sv * 4.0 / 3.0) ** 2])
			var x := PackedFloat64Array()
			if dims == 3:
				var ps := (sp * 4.0 / 3.0) ** 2
				var vs := (sv * 4.0 / 3.0) ** 2
				P = Track.diag([ps, ps, ps, vs, vs, vs])
				for i in 3:
					x.append(h.r[i] + gauss() * sp)
				for i in 3:
					x.append(h.v[i] + gauss() * sv)
			else:
				x = PackedFloat64Array([h.r[0] + gauss() * sp, h.r[1] + gauss() * sp, h.v[0] + gauss() * sv, h.v[1] + gauss() * sv])
			sim.tracks[h.id] = Track.new(h.id, String(h.opening_track), x, P, 0.0)
			if op.has("cue"):
				sim.say("cue", op.cue[1] if Lang.doctrinal else op.cue[0], "alert")
		elif h.has("beacon_track"):
			var tr := Track.new(h.id, String(h.beacon_track), PackedFloat64Array([h.r[0], h.r[1], h.v[0], h.v[1]]), Track.diag([50.0 ** 2, 50.0 ** 2, 0.01 ** 2, 0.01 ** 2]), 0.0)
			if dims == 3:
				tr = Track.new(h.id, String(h.beacon_track), PackedFloat64Array([h.r[0], h.r[1], h.r[2], h.v[0], h.v[1], h.v[2]]), Track.diag([50.0 ** 2, 50.0 ** 2, 50.0 ** 2, 0.01 ** 2, 0.01 ** 2, 0.01 ** 2]), 0.0)
			tr.ident = "identified"
			tr.side = "neutral"
			tr.class_id = h.classId
			sim.tracks[h.id] = tr
	sim.track_n = 4423
	_catalogued()


## 2 if every ship starts in the plane of Jupiter's campaign, else 3: a world
## about another body, or any ship off the plane.
static func world_dims(sim_: Sim) -> int:
	if sim_.central != "jupiter":
		return 3
	for s in sim_.ships:
		if s.has("r") and absf(float(s.r[2])) > 1e-9:
			return 3
	return 2


## Objects already in the public catalogue (the scenario's "catalogued":
## [{id, sigma_km, sigma_kms, side?}]) start with a track: the truth plus
## Gaussian noise of that 1σ in each axis, drawn from the "setup" stream, and
## that covariance. The catalogue names the object (identified, its class);
## whose side it is on, it does not say unless the scenario does.
func _catalogued() -> void:
	for c in sim.camp.get("catalogued", []):
		var id := String(c.id)
		if not sim.by_id.has(id) or sim.tracks.has(id):
			continue
		var o: Dictionary = sim.by_id[id]
		var sp := float(c.get("sigma_km", 1.0))
		var sv := float(c.get("sigma_kms", 0.001))
		var g := sim.stream("setup")
		var x := PackedFloat64Array()
		var v := []
		for i in dims:
			x.append(o.r[i] + g.randfn(0.0, 1.0) * sp)
			v.append(sp * sp)
		for i in dims:
			x.append(o.v[i] + g.randfn(0.0, 1.0) * sv)
			v.append(sv * sv)
		var tr := Track.new(id, "TRK %d" % sim.track_n, x, Track.diag(v), sim.t)
		sim.track_n += 3
		tr.ident = "identified"
		tr.class_id = o.classId
		tr.side = String(c.get("side", "unknown"))
		tr.last_seen = sim.t
		sim.tracks[id] = tr


## A measured direction from a to b: the true one turned by two independent
## Gaussian angles of 1σ sig across it (small angles).
func noisy_dir(a: PackedFloat64Array, b: PackedFloat64Array, sig: float) -> PackedFloat64Array:
	var d := V.sub(b, a)
	var u := V.scale(d, 1.0 / V.norm(d))
	var ee := Track.across_of(u)
	var m := V.add(u, V.add(V.scale(ee[0], gauss() * sig), V.scale(ee[1], gauss() * sig)))
	return V.scale(m, 1.0 / V.norm(m))


## Our craft that look: an infrared sensor, a telescope, or both (an
## inspector may carry only a telescope: WATCHMAN-1).
func sensors() -> Array:
	return sim.blue_ships().filter(func(s): return s.cls.has("ir") or s.cls.has("optical"))


func ears() -> Array:
	return sim.blue_ships().filter(func(s): return s.cls.has("esm"))


## Does Jupiter block the line from a to b?
func occulted(a: PackedFloat64Array, b: PackedFloat64Array) -> bool:
	var d := V.sub(b, a)
	var L2 := V.dot(d, d)
	var u := clampf(-V.dot(a, d) / L2, 0.0, 1.0)
	return V.norm(V.add(a, V.scale(d, u))) < sim.central_radius()


## Sensors stare all the time; the game checks them every look. A burn since
## the last look still lit the ship up, so it is judged at its brightest (as the JS game).
func lit(s: Dictionary) -> bool:
	return float(s.get("flash_until", -1.0)) > last_look


## In-band radiant intensity (W/sr) of ship s toward a point (Thermal.intensity):
## skin, radiators by aspect, and a drive that burned since the last look.
func intensity(s: Dictionary, toward: PackedFloat64Array) -> float:
	return float(sim.thermal.intensity(s, toward, lit(s)).total)


## The glare round the planet's lit limb reaches glareCone times its
## apparent radius, but no more than GLARE_MAX past the limb: from low orbit
## the Earth fills most of the sky, and three times its radius would leave no
## sky at all. 20° is about the Hubble Space Telescope's bright-Earth
## avoidance angle (design value, after it).
const GLARE_MAX := deg_to_rad(20.0)


## How bright the sky behind the target is, as a multiple of the sensor's NEI:
## Jupiter's disc (design value inside the derived ×26–92), then stray light near it.
func background(o: Dictionary, p: PackedFloat64Array) -> float:
	var to_j := V.scale(o.r, -1.0)
	var to_x := V.sub(p, o.r)
	var ang := acos(clampf(V.dot(to_j, to_x) / (V.norm(to_j) * V.norm(to_x)), -1.0, 1.0))
	var jr := asin(minf(1.0, sim.central_radius() / V.norm(o.r)))
	var band: Dictionary = sim.data.cfg.ir.band
	if ang < jr:
		return float(band.discFactor)
	if ang < jr + minf((float(sim.data.cfg.ir.glareCone) - 1.0) * jr, GLARE_MAX):
		return float(band.glareFactor)
	return 1.0


## Sensor o's infrared look at x: SNR = I/R²/(NEI·background), in band.
func ir_look(o: Dictionary, x: Dictionary) -> Dictionary:
	if not o.cls.has("ir") or occulted(o.r, x.r):
		return {"snr": 0.0, "occulted": true}
	var R := V.dist(o.r, x.r) * 1000.0
	var terms: Dictionary = sim.thermal.intensity(x, o.r, lit(x))
	var bg := background(o, x.r)
	var nei := float(o.cls.ir.get("neiBand", o.cls.ir.nei)) * bg
	var snr: float = float(terms.total) / (R * R) / nei
	return {"snr": snr, "pd": pd(snr), "R_m": R, "nei": nei, "bg": bg, "terms": terms, "occulted": false}


## Sensor o's visible look at x: sunlight scattered off a diffuse sphere,
## Lambert phase law Φ(α) = (sin α + (π − α) cos α)/π and geometric albedo
## p = ⅔·diffuse·(1 − α_s) (Madhusudhan & Burrows 2012). Magnitude against the
## Sun's, scaled to Jupiter's distance by the irradiance; S/N 5 at the limit
## (design value; the 1 m GEODSS/LINEAR result is magnitude 22 at S/N 4).
## The telescopes are narrow-field imagers that reach that limit by staring at
## one spot (~100 s, Stokes 1996; Stokes et al. 1998, Lincoln Lab. J. 11(1):27),
## so Blue's look only where it already holds a
## track: infrared and listening find a ship, the telescope follows up.
## (cued = false gives the photometry regardless, for the tests.)
func vis_look(o: Dictionary, x: Dictionary, cued := true) -> Dictionary:
	if not o.cls.has("optical") or occulted(o.r, x.r):
		return {"snr": 0.0}
	if cued and o.side == "blue" and not sim.tracks.has(x.id):
		return {"snr": 0.0, "uncued": true}
	var f := sim.thermal.sunlight(x.r)
	if f <= 0.0:
		return {"snr": 0.0, "shadow": true}
	var bg := background(o, x.r)
	if bg > 1.0:
		return {"snr": 0.0, "glare": true} # Jupiter's sunlit disc swamps a visible telescope
	var vis: Dictionary = sim.data.cfg.vis
	var sig: Dictionary = x.cls.sig
	var to_o := V.sub(o.r, x.r)
	var ph := acos(clampf(V.dot(sim.sun_dir(), to_o) / V.norm(to_o), -1.0, 1.0))
	var R := V.norm(to_o) * 1000.0
	var m := vis_mag(sig, R, ph, Thermal.sun_flux(sim.data), vis)
	var lim := vis_limit(float(o.cls.optical.aperture), vis)
	var snr := float(sim.data.cfg.ir.band.threshold) * pow(10.0, -0.4 * (m - lim)) * f # in the rim, dimmed by the hidden share
	return {"snr": snr, "sun": f, "pd": pd(snr), "mag": m, "limit": lim, "phase": ph, "R_m": R}


## Apparent V magnitude of a hull at R m and phase angle ph: the Sun's
## (absolute V at 1 AU, dimmed to the local irradiance) less 2.5·log₁₀ of the
## share it returns, p·Φ(α)·r²/R² (Madhusudhan & Burrows 2012 eq. 3), with r² = A/4π
## for a sphere of the hull's surface area A (geometric albedo p is per cross-section πr²).
static func vis_mag(sig: Dictionary, R: float, ph: float, S: float, vis: Dictionary) -> float:
	var phi := (sin(ph) + (PI - ph) * cos(ph)) / PI
	var p := 2.0 / 3.0 * float(sig.get("diffuse", 0.2)) * (1.0 - float(sig.get("alpha", 0.5)))
	var ratio := p * float(sig.A) / (4.0 * PI) * phi / (R * R)
	var m_sun := float(vis.sunAbsV) + 5.0 * log(4.8481368e-6 / 10.0) / log(10.0) - 2.5 * log(S / float(vis.solarConstant)) / log(10.0)
	return m_sun - 2.5 * log(maxf(ratio, 1e-300)) / log(10.0)


## Limiting magnitude (S/N 5) of a telescope of this aperture.
static func vis_limit(aperture: float, vis: Dictionary) -> float:
	return float(vis.limitMag) + 2.5 * log(aperture / float(vis.refAperture)) / log(10.0)


## Photons per second a telescope of aperture D (m) collects from a source of
## V magnitude mag, as electrons after the optics' throughput and the
## detector's quantum efficiency: the V band's zero point, 3.63e-11 W m⁻² nm⁻¹
## at 545 nm (Bessell, Castelli & Plez 1998, A&A 333, 231, Table A2) over the
## band's 88 nm (Bessell 1990, PASP 102, 1181), is 8.8e9 photons s⁻¹ m⁻² for
## magnitude 0.
const V_ZERO_PHOTONS := 3.63e-11 * 88.0 * 545e-9 / (6.62607015e-34 * 299792458.0) # photons s⁻¹ m⁻²


static func photon_rate(mag: float, D: float, qe := 1.0, throughput := 1.0) -> float:
	return V_ZERO_PHOTONS * pow(10.0, -0.4 * mag) * PI * D * D / 4.0 * qe * throughput


## Pixels a moving point source covers in one exposure: a disc of diameter w
## (the seeing or PSF, px) dragged L = rate·t px, a stadium of area
## πw²/4 + w·L. A streak spreads the same light over more sky (Shell 2010,
## "Optimizing orbital debris monitoring with optical telescopes", AMOS).
static func streak_pixels(w_px: float, rate_px_s: float, t: float) -> float:
	return PI * w_px * w_px / 4.0 + w_px * rate_px_s * t


## SNR of a source in an exposure of t s (the CCD equation; Merline & Howell
## 1995, Exp. Astron. 6, 163): S·t / √(S·t + n·(B·t + D·t + R²)), with S the
## source's electrons per second inside the aperture, n its pixels, B the sky's
## and D the dark current's electrons per pixel per second, R the read noise
## (e⁻ rms). The sky per pixel is photon_rate of its surface brightness (mag
## arcsec⁻²) times the pixel's area (arcsec²).
static func ccd_snr(S: float, t: float, n: float, B: float, D := 0.0, R := 0.0) -> float:
	var s := S * t
	return s / sqrt(maxf(s + n * (B * t + D * t + R * R), 1e-300))


## How far (km) a telescope of this aperture sees a sunlit hull at S/N 5, side-lit (phase 90°).
static func vis_range_km(sig: Dictionary, aperture: float, S: float, vis: Dictionary, ph := PI / 2.0) -> float:
	var dm := vis_limit(aperture, vis) - vis_mag(sig, 1.0, ph, S, vis)
	return pow(10.0, 0.2 * dm) / 1000.0


## Probability a look at this SNR crosses the S/N-5 threshold: Φ(SNR − 5) for
## Gaussian noise (one look; false alarms ≈ 2.9×10⁻⁷ per resolution element).
func pd(snr: float) -> float:
	return RF.q(float(sim.data.cfg.ir.band.threshold) - snr)


## Would sensor o expect to see x right now (S/N ≥ 5, infrared or visible)?
## The UI and Red's planning use this; Blue's looks roll Pd.
func ir_sees(o: Dictionary, x: Dictionary) -> bool:
	var k := float(sim.data.cfg.ir.band.threshold)
	return float(ir_look(o, x).snr) >= k or float(vis_look(o, x).snr) >= k


func bearing(from: PackedFloat64Array, to: PackedFloat64Array) -> float:
	return atan2(to[1] - from[1], to[0] - from[0])


func label_for(id: String) -> String:
	if sim.tracks.has(id):
		return sim.tracks[id].label
	return "unknown"


## Every look: IR on every Red and neutral ship, then the radio recordings.
func look() -> void:
	var t := sim.t
	for x in sim.ships:
		if x.side == "blue" or not x.alive:
			continue
		var tr: Track = sim.tracks.get(x.id)
		if tr != null:
			# Civil traffic coasts on two-body prediction: it never manoeuvres here, and
			# the full-gravity filter for a dozen tracks is the costliest thing a look does.
			tr.predict(t, x.get("kind", "") == "civil")
		var seen := false
		for o in sensors():
			# Each look is a draw: Pd = Φ(SNR − 5) in infrared, then in visible light.
			var by := ""
			var p_ir := float(ir_look(o, x).get("pd", 0.0))
			if p_ir > 1e-9 and sim.stream("sensing").randf() < p_ir:
				by = "IR"
			else:
				var p_vis := float(vis_look(o, x).get("pd", 0.0))
				if p_vis > 1e-9 and sim.stream("sensing").randf() < p_vis:
					by = "VIS"
			if by == "":
				continue
			var sig: float = sim.data.cfg.ir.bearingSigma
			var u3 := PackedFloat64Array()
			var b := 0.0
			if dims == 3:
				u3 = noisy_dir(o.r, x.r, sig)
				b = atan2(u3[1], u3[0])
			else:
				b = bearing(o.r, x.r) + gauss() * sig
			if tr != null:
				if lit(x) and float(x.get("seen_burn_at", -1.0)) < t - 1.0:
					# How hard could it have burned? Thrust over mass, for as long as the plume could have lasted.
					var m := (float(x.get("dry", 10.0)) + float(x.get("prop", 0.0))) * 1000.0
					var thrust: float = x.cls.engine.thrust if x.cls.has("engine") else 0.0
					var bound := thrust / m * maxf(float(x.get("burn_seconds", 300.0)), 300.0) / 1000.0
					if dims == 3:
						# A jump at the moment it was seen, sized by the sightings after it (Track.burn_seen).
						if int(tr.burn.get("n", -1)) != int(x.get("burns", 0)):
							tr.burn_seen(int(x.get("burns", 0)), float(x.get("burn_at", t)), maxf(0.001, bound))
					else:
						tr.maneuver_seen(sim.LOOK, maxf(0.05, bound))
					x.seen_burn_at = t
					if int(x.get("burn_logged", -1)) != int(x.get("burns", 0)):
						x.burn_logged = int(x.get("burns", 0))
						sim.say("burn_seen", Lang.f("burn_seen", [tr.label]), "alert")
				# Ranging by size (stadiametric): a hull of known class and length L
				# that spans angle θ is at L/θ. The telescope measures θ to about one
				# diffraction element, so σR ≈ R²·(1.22λ/D)/L: metres at a few km,
				# useless at a thousand. It ends the range ambiguity of bearings alone.
				# In 3-D, with the direction it is one position fix (Track.update_fix),
				# right however wide the track is.
				var sig_r := INF
				if o.cls.has("optical") and tr.class_id == x.classId:
					var res := 1.22 * float(sim.data.cfg.ir.visibleLambda) / float(o.cls.optical.aperture)
					sig_r = pow(V.dist(o.r, x.r) * 1000.0, 2.0) * res / float(x.cls.length)
				if dims == 3 and sig_r < 0.2 * V.dist(o.r, x.r) * 1000.0:
					tr.update_fix(o.r, (V.dist(o.r, x.r) * 1000.0 + gauss() * sig_r) / 1000.0, u3, sig_r / 1000.0, sig)
					tr.lobs.append({"t": t, "from": o.r, "bearing": b, "dir": u3, "kind": "ir" if by == "IR" else "vis", "by": o.id, "range": V.dist(o.r, x.r)})
				elif dims == 3:
					tr.update_dir(o.r, u3, sig)
					tr.lobs.append({"t": t, "from": o.r, "bearing": b, "dir": u3, "kind": "ir" if by == "IR" else "vis", "by": o.id})
				else:
					tr.update_bearing(o.r, b, sig)
					tr.lobs.append({"t": t, "from": o.r, "bearing": b, "kind": "ir" if by == "IR" else "vis", "by": o.id})
				seen = true
				tr.how = by
			else:
				var line := {"t": t, "from": o.r, "bearing": b, "sigma": sig, "by": o.id}
				if dims == 3:
					line.dir = u3
				_pend(x.id, line)
			# A close look with a telescope names the hull: inside id_range_km, where
			# the hull's length spans the Johnson criteria's 12.8 resolution elements.
			if o.cls.has("optical") and tr != null and not tr.seen_id:
				if V.dist(o.r, x.r) <= id_range_km(sim, float(o.cls.optical.aperture), float(x.cls.length)):
					tr.seen_id = true
					_identify(tr, x, "identified")
			# Ranging by size (stadiametric): a hull of known class and length L
			# that spans angle θ is at L/θ. The telescope measures θ to about one
			# diffraction element, so σR ≈ R²·(1.22λ/D)/L: metres at a few km,
			# useless at a thousand. It ends the range ambiguity of bearings alone.
			if o.cls.has("optical") and tr != null and tr.class_id == x.classId and seen and dims == 2:
				var r_m := V.dist(o.r, x.r) * 1000.0
				var res := 1.22 * float(sim.data.cfg.ir.visibleLambda) / float(o.cls.optical.aperture)
				var sig_r := r_m * r_m * res / float(x.cls.length)
				if sig_r < 0.2 * r_m:
					tr.update_range(o.r, (r_m + gauss() * sig_r) / 1000.0, sig_r / 1000.0)
		if tr == null and seen == false:
			_try_start(x.id)
		if tr != null:
			if seen:
				tr.mark_seen(t)
			if tr.burn.get("sized", false) and not tr.burn.get("told", false):
				tr.burn.told = true
				sim.say("burn_sized", Lang.f("burn_sized", [tr.label, "%.1f" % (V.norm(tr.burn.dv) * 1000.0), "%.1f" % (float(tr.burn.sigma) * 1000.0)]), "info", {"from": x.id})
			if tr.in_contact and not seen and x.side == "red":
				sim.say("lost", Lang.f("lost", [tr.label]), "warn")
			tr.in_contact = seen
			if not seen and tr.stale(t):
				sim.tracks.erase(x.id)
				pending.erase(x.id)
				sim.say("dropped", Lang.f("dropped", [tr.label]), "warn")
				continue
			tr.lobs = tr.lobs.filter(func(l): return t - l.t < 3.0 * sim.LOOK)
	_false_alarms(t)
	_radar(t)
	_listen(last_look, t)
	last_look = t


## Noise crosses the S/N-5 threshold somewhere in a sensor's field now and then:
## a Poisson count each look (mean falseAlarmsPerLook, a design value), each a
## line of bearing to nothing. Lines from two sensors never cross on one, so
## confirming a contact from two places is what weeds them out.
func _false_alarms(t: float) -> void:
	var mean := float(sim.data.cfg.ir.band.falseAlarmsPerLook)
	for o in sensors():
		var n := 0
		var L := exp(-mean)
		var p := sim.stream("sensing").randf()
		while p > L:
			n += 1
			p *= sim.stream("sensing").randf()
		for i in n:
			false_lines.append({"t": t, "from": o.r, "bearing": sim.stream("sensing").randf() * TAU, "by": o.id})
	false_lines = false_lines.filter(func(l): return t - l.t < 2.0 * sim.LOOK)


## What the sensor crews see that is not yet a track: single-look lines of
## bearing, real and false alike (the UI cannot tell them apart, nor can Blue).
func blips() -> Array:
	var out := []
	for id in pending:
		if not sim.tracks.has(id):
			out.append_array(pending[id].filter(func(l): return sim.t - l.t < 2.0 * sim.LOOK))
	out.append_array(false_lines)
	return out


func _pend(id: String, line: Dictionary) -> void:
	if not pending.has(id):
		pending[id] = []
	pending[id].append(line)
	pending[id] = pending[id].filter(func(l): return sim.t - l.t < 2.0 * Sim.HOUR)


## Start a track when lines from two places, taken at the same moment, cross
## at a useful angle. (Lines from different times don't cross where the target
## is: it moved in between, ~2,500 km in 300 s at 8 km/s. An infrared look and a
## radio burst heard minutes apart are not the same moment.)
func _try_start(id: String) -> void:
	var lines: Array = pending.get(id, [])
	if lines.size() < 2:
		return
	for i in lines.size():
		var group := [lines[i]]
		var seen_by := {lines[i].by: true}
		for j in lines.size():
			if j != i and not seen_by.has(lines[j].by) and absf(lines[j].t - lines[i].t) <= 1.0:
				group.append(lines[j])
				seen_by[lines[j].by] = true
		if group.size() < 2:
			continue
		var cross := absf(Track.wrap_angle(group[0].bearing - group[1].bearing))
		if group[0].has("dir") and group[1].has("dir"):
			cross = acos(clampf(absf(V.dot(group[0].dir, group[1].dir)), 0.0, 1.0))
		if minf(cross, PI - cross) < deg_to_rad(4.0):
			continue
		var fix := Track.cross_fix(group)
		if not fix.ok:
			continue
		var label := "TRK %d" % sim.track_n
		sim.track_n += 3
		var tr := Track.start(id, label, fix, group[0].t)
		tr.predict(sim.t)
		sim.tracks[id] = tr
		pending.erase(id)
		sim.say("new_track", Lang.f("new_track", [label, _where(fix.r)]), "alert")
		if sim.by_id[id].has("pending_class"):
			tr.heard_id = true
			_identify(tr, sim.by_id[id], "classified")
		return


func _where(r: PackedFloat64Array) -> String:
	for p in sim.camp.get("pockets", []):
		if p.kind == "lagrange" and V.dist(r, sim.pocket_center(p)) < float(p.size) * 1.5:
			return p.name
	var rn := V.norm(r)
	return "%.2f Mkm out" % (rn / 1e6)


## How close (km) a telescope of this aperture (m) must be to identify a hull
## this long (m): the Johnson criteria (Johnson 1958; Sjaardema, Smith & Birch
## 2015, SAND2015-6368, §2.2, Table 1) take ~6.4 line pairs, 12.8 resolution
## elements, across a target to identify it at 50% probability; each element is
## the diffraction limit 1.22 λ/D in visible light. Johnson counted across the
## target's critical (smallest) dimension; using the hull's length is a
## simplification, and a generous one. A 1 m
## telescope names a 10 m inspector inside ~1,200 km, a 100 m ship inside ~12,000.
static func id_range_km(sim_: Sim, aperture: float, length_m: float) -> float:
	var theta := 1.22 * float(sim_.data.cfg.ir.visibleLambda) / aperture
	return length_m / (2.0 * float(sim_.data.cfg.ir.idCycles)) / theta / 1000.0


func _identify(tr: Track, x: Dictionary, level: String) -> void:
	var order := ["unknown", "classified", "identified"]
	if order.find(level) <= order.find(tr.ident):
		return
	tr.ident = level
	tr.class_id = x.classId
	tr.side = "hostile" if x.side == "red" else x.side
	sim.say("classified", Lang.f("classified", [tr.label, String(x.cls.name)]), "alert" if x.side == "red" else "good")


## Record each Red burst that ended since the last look, at every ear that heard it.
func _listen(a: float, b: float) -> void:
	for x in sim.ships:
		if (x.side != "red" and x.get("kind", "") != "civil") or not x.alive:
			continue
		for burst in x.get("bursts", []):
			if burst.end <= a or burst.end > b:
				continue
			var ttc: Dictionary = x.cls.ttc
			var mid := (float(burst.start) + float(burst.end)) / 2.0
			var rec := {"id": "INT-%03d" % (sim.intercepts.size() + 1), "ship": x.id, "kind": burst.get("kind", "ttc"), "f": ttc.f, "bw": ttc.bw, "mod": ttc.mod,
				"start": burst.start, "end": burst.end, "heard_by": {}, "ear_pos": {}, "budget": {}, "truth": _back(x, mid), "df": false, "classified": false}
			for e in ears():
				var bud := budget(x, burst, e, mid)
				if bud.is_empty() or sim.stream("sensing").randf() >= float(bud.pd):
					continue
				rec.heard_by[e.id] = bud.snr
				rec.ear_pos[e.id] = bud.ear_pos
				rec.budget[e.id] = bud
			if rec.heard_by.is_empty():
				continue
			sim.intercepts.append(rec)
			var who := ", ".join(rec.heard_by.keys().map(func(k): return sim.by_id[k].short))
			# Traffic we have already put a name to is not news.
			var known: Track = sim.tracks.get(x.id)
			if known == null or known.side != "neutral":
				sim.say("heard", Lang.f("heard", [rec.id, "%.1f MHz %s" % [ttc.f / 1e6, "burst" if rec.kind == "ttc" else "long burst"], who]), "info", {"intercept": rec.id})
			if auto:
				df(rec.id)
				classify(rec.id)


## What an ear is receiving in the window [a, b]: every Red or civil burst on
## the air then that the next look has yet to record and that the ear stands an
## even chance or better of detecting, with the SNR it will integrate over the
## whole burst (from where things are now). For the live waterfall and spectrum;
## it changes nothing. [{ship, f, bw, mod, start, end, snr, pd}]
func on_air(ear_id: String, a: float, b: float) -> Array:
	var out := []
	var e: Dictionary = sim.by_id.get(ear_id, {})
	if e.is_empty() or not e.cls.has("esm") or not e.alive:
		return out
	for x in sim.ships:
		if (x.side != "red" and x.get("kind", "") != "civil") or not x.alive or not x.cls.has("ttc"):
			continue
		for burst in x.get("bursts", []):
			if burst.end <= last_look or burst.end <= a or burst.start > b:
				continue
			var bud := budget(x, burst, e, sim.t)
			if bud.is_empty():
				break
			if float(bud.pd) >= 0.5:
				var ttc: Dictionary = x.cls.ttc
				out.append({"ship": x.id, "f": float(ttc.f), "bw": float(ttc.bw), "mod": String(ttc.mod), "start": float(burst.start), "end": float(burst.end), "snr": bud.snr, "pd": bud.pd})
	return out


## The link budget of one burst at one ear at time `at`, term by term, for
## detection and the Inspector; empty if Jupiter is in the way.
## {Pt_dbw, Gt_dbi, off_t, aim, fspl_db, Gr_dbi, off_r, ear, N_dbw, int_db, snr, pd, R_m, ear_pos}
func budget(x: Dictionary, burst: Dictionary, e: Dictionary, at: float) -> Dictionary:
	var ttc: Dictionary = x.cls.ttc
	var xr := _back(x, at)
	var er := _back(e, at)
	if occulted(er, xr):
		return {}
	var f := float(ttc.f)
	var bw := float(ttc.bw)
	var dur := float(burst.end) - float(burst.start)
	var Pt := float(ttc.Pt) * float(burst.get("power", 1.0))
	var R := V.dist(er, xr) * 1000.0
	var tx := emitter_gain(x, burst, er, at)
	var rx := ear_gain(e, xr, f, at)
	var esm: Dictionary = e.cls.esm
	var snr := link_snr(Pt, tx.dbi, rx.dbi, f, bw, float(esm.Ts), R, dur)
	var n := bw * dur
	return {"Pt_dbw": RF.db(Pt), "Gt_dbi": tx.dbi, "off_t": tx.off, "aim": tx.aim,
		"fspl_db": 2.0 * RF.db(4.0 * PI * R / RF.wavelength(f)), "Gr_dbi": rx.dbi, "off_r": rx.off, "ear": rx.how,
		"N_dbw": RF.db(RF.noise(float(esm.Ts), bw)), "int_db": RF.db(sqrt(n)), "snr": snr,
		"pd": RF.detect_pd(snr, float(sim.data.cfg.radio.get("pfa", 1e-6)), n), "R_m": R, "ear_pos": er}


## Where an emitter's antenna points during a burst: Red's command link at its
## handler on Callisto, civil probes at Earth, the ore hauler at Ganymede's
## traffic control, a relay's wake call at the ship it wakes.
func emitter_aim(x: Dictionary, burst: Dictionary, at: float) -> PackedFloat64Array:
	var aim := String(burst.get("aim_at", x.cls.ttc.get("aim", "handler")))
	if aim == "earth":
		return V.add(_back(x, at), V.scale(sim.earth_dir(at), 1e10))
	if aim == "handler":
		return sim.handler_pos(at)
	if not sim.moon(aim).is_empty():
		return sim.moon_state(aim, at)[0]
	if sim.by_id.has(aim):
		return _back(sim.by_id[aim], at)
	return sim.handler_pos(at)


## An emitter's gain toward a point: its dish's ITU pattern at the angle off its
## boresight. {dbi, off (rad), aim (what it points at)}
func emitter_gain(x: Dictionary, burst: Dictionary, toward: PackedFloat64Array, at: float) -> Dictionary:
	var ttc: Dictionary = x.cls.ttc
	var aim := String(burst.get("aim_at", ttc.get("aim", "handler")))
	if not ttc.has("dish"):
		return {"dbi": float(ttc.get("towardUsDbi", 0.0)), "off": NAN, "aim": aim}
	var off := Antenna.angle_at(_back(x, at), emitter_aim(x, burst, at), toward)
	return {"dbi": Antenna.gain_dbi(float(ttc.dish), float(ttc.f), off), "off": off, "aim": aim}


## An ear's gain toward a point. {dbi, off (rad), how}
## - A receive array forms a beam toward every direction at once (the game's
##   extension of the TDRS S-band multiple-access arrays, whose beams cover an
##   Earth-facing field, NASA TM-105422); its gain is the aperture's
##   peak times the projected area of the face nearest that way, cos θ (the
##   scan loss of a planar array). Its faces are fixed in inertial space, 4 of
##   them 90° apart (design value), so the worst loss is cos 45°, 1.5 dB.
## - A dish hears through its ITU pattern at the angle off where it points.
func ear_gain(e: Dictionary, toward: PackedFloat64Array, f: float, at: float) -> Dictionary:
	var esm: Dictionary = e.cls.esm
	var er := _back(e, at)
	if String(esm.get("kind", "array")) == "array":
		var d := V.sub(toward, er)
		var th := atan2(d[1], d[0])
		var step := TAU / float(esm.get("faces", 4))
		var scan := absf(Track.wrap_angle(th - round(th / step) * step))
		return {"dbi": Antenna.peak_dbi(float(esm.dish), f) + RF.db(cos(scan)), "off": scan, "how": "array"}
	var off := Antenna.angle_at(er, dish_point(e), toward)
	return {"dbi": Antenna.gain_dbi(float(esm.dish), f, off), "off": off, "how": "dish"}


## The ship a pointed dish is following, or "" when it is parked.
func dish_target(e: Dictionary) -> String:
	var a: Dictionary = dish_aim.get(e.id, {"mode": "auto"})
	match String(a.get("mode", "auto")):
		"track":
			var id := String(a.get("track", ""))
			return id if sim.tracks.has(id) else ""
		"park":
			return ""
	# The assist: the hostile track seen most recently, else the newest unknown one.
	var best := ""
	var best_key := -INF
	for id in sim.tracks:
		var tr: Track = sim.tracks[id]
		if tr.side != "hostile" and tr.side != "unknown":
			continue
		var key := tr.last_seen + (1e9 if tr.side == "hostile" else 0.0)
		if key > best_key:
			best_key = key
			best = id
	return best


## Where a pointed dish looks: at its target's estimated position (Blue's track,
## not the truth: a poor track points the beam off the ship), else straight up,
## away from Jupiter.
func dish_point(e: Dictionary) -> PackedFloat64Array:
	var id := dish_target(e)
	if id != "":
		return sim.tracks[id].pos()
	return V.scale(e.r, 2.0)


## Integrated SNR at a receiver of system temperature Ts from a burst of power Pt (W)
## with antenna gains Gt and Gr (dBi) toward each other, at range R (m), lasting
## dur (s): Friis over kTB, times √(B·dur) (radiometer equation).
static func link_snr(Pt: float, Gt_dbi: float, Gr_dbi: float, f: float, bw: float, Ts: float, R: float, dur: float) -> float:
	return RF.integrate(RF.friis(Pt, RF.from_db(Gt_dbi), RF.from_db(Gr_dbi), R, f) / RF.noise(Ts, bw), bw, dur)


## Radar echo SNR (monostatic radar equation, Skolnik 2008; NAWCWD TP 8347, §4-5,
## eq. 1, with N = kTsB and Bτ ≈ 1; in its average-power and dwell-time form): SNR = P_avg·G²·λ²·σ·t / ((4π)³·R⁴·k·Ts), R in m. No losses.
static func radar_snr(rd: Dictionary, rcs: float, R: float) -> float:
	var f := float(rd.f)
	var G := RF.dish_gain(float(rd.dish), f) if rd.has("dish") else RF.from_db(float(rd.gain))
	var lam := RF.wavelength(f)
	return float(rd.pAvg) * G * G * lam * lam * rcs * float(rd.tau) / (pow(4.0 * PI, 3.0) * pow(R, 4.0) * RF.K_BOLTZ * float(rd.Ts))


## 1σ angle error (rad) of a monopulse radar at this SNR: θ3/(km·√(2·SNR)), with
## the 3 dB beamwidth θ3 ≈ 70λ/D degrees = 1.22λ/D of a tapered dish and the
## monopulse slope km ≈ 1.6, a typical value (Barton 2005, Radar System Analysis
## and Modeling; consistent with MIT Lincoln Laboratory, Introduction to Radar
## Systems: Tracking and Parameter Estimation, 2008).
## A radar block with its gain (dBi) and no dish: the dish of that gain at 55%
## efficiency (RF.dish_gain inverted).
static func radar_angle_sigma(rd: Dictionary, snr: float) -> float:
	var lam := RF.wavelength(float(rd.f))
	var D := float(rd.dish) if rd.has("dish") else lam / PI * sqrt(RF.from_db(float(rd.gain)) / 0.55)
	return 1.22 * lam / D / (1.6 * sqrt(2.0 * maxf(snr, 1e-9)))


## Where a ship was at time at (a few minutes ago at most): coast it back.
func _back(s: Dictionary, at: float) -> PackedFloat64Array:
	if s.has("onMoon"):
		return sim.moon_state(s.onMoon, at)[0]
	return Kepler.propagate(s.r, s.v, at - sim.t, sim.mu)[0]


func intercept(id: String) -> Dictionary:
	for r in sim.intercepts:
		if r.id == id:
			return r
	return {}


func best_snr(rec: Dictionary) -> float:
	var b := 0.0
	for k in rec.heard_by:
		b = maxf(b, rec.heard_by[k])
	return b


## Take bearings on a recording from every ear that heard it.
func df(id: String) -> int:
	var rec := intercept(id)
	if rec.is_empty() or rec.df or sim.t - rec.end > float(sim.data.cfg.radio.recordSeconds):
		return 0
	rec.df = true
	var lines := []
	for ear_id in rec.heard_by:
		var e: Dictionary = sim.by_id[ear_id]
		# Thermal noise sets σ = λ/(2πd)·σφ, the cross-correlation phase error over the
		# burst's Bτ samples (RF.df_sigma); calibration of the array and knowledge of our
		# own position put a floor under it (20 µrad: design value).
		var thermal := RF.df_sigma(rec.f, float(e.cls.esm.baseline), rec.heard_by[ear_id], float(rec.bw) * (float(rec.end) - float(rec.start)))
		var sig := sqrt(thermal * thermal + DF_FLOOR * DF_FLOOR)
		var from: PackedFloat64Array = rec.ear_pos[ear_id]
		if dims == 3:
			var u := noisy_dir(from, rec.truth, sig)
			lines.append({"t": (rec.start + rec.end) / 2.0, "from": from, "bearing": atan2(u[1], u[0]), "dir": u, "sigma": sig, "by": ear_id})
			continue
		lines.append({"t": (rec.start + rec.end) / 2.0, "from": from, "bearing": bearing(from, rec.truth) + gauss() * sig, "sigma": sig, "by": ear_id})
	rec.lines = lines
	var tr: Track = sim.tracks.get(rec.ship)
	if tr != null:
		tr.predict(sim.t)
		for l in lines:
			if l.has("dir") and tr.dims() == 3:
				tr.update_dir(l.from, l.dir, l.sigma, l.t)
				tr.lobs.append({"t": sim.t, "from": l.from, "bearing": l.bearing, "dir": l.dir, "kind": "df", "by": l.by, "sigma": l.sigma})
				continue
			tr.update_bearing(l.from, l.bearing, l.sigma, l.t)
			tr.lobs.append({"t": sim.t, "from": l.from, "bearing": l.bearing, "kind": "df", "by": l.by, "sigma": l.sigma})
		tr.mark_seen(rec.end)
	else:
		for l in lines:
			_pend(rec.ship, l)
		_try_start(rec.ship)
	sim.say("df", Lang.f("df", [rec.id, lines.size()]), "good")
	return lines.size()


## Measure a recording's modulation: if it is strong enough, it names the class.
func classify(id: String) -> bool:
	var rec := intercept(id)
	if rec.is_empty() or rec.classified or best_snr(rec) < float(sim.data.cfg.radio.classifySnr):
		return false
	rec.classified = true
	var x: Dictionary = sim.by_id[rec.ship]
	x.heard_strong = int(x.get("heard_strong", 0)) + 1
	var tr: Track = sim.tracks.get(rec.ship)
	if tr != null:
		tr.heard_id = true
		_identify(tr, x, "classified")
		tr.intercepts = int(x.heard_strong)
	else:
		x.pending_class = true
	return true


## Radar, while it radiates: range to every track in its reach, as good as
## its pulse (σ ≈ 50 m, design value), and a monopulse bearing (radar_angle_sigma).
## Radar equation (Skolnik): SNR = P·G²·λ²·σ·τ / ((4π)³ R⁴ k T) (radar_snr).
func _radar(t: float) -> void:
	for o in sim.blue_ships():
		if not o.alive or not o.cls.has("radar"):
			continue
		if o.get("kind", "") == "site":
			_site_radar(o, t)
			continue
		if not sim.effects.radar_on.get(o.id, false):
			continue
		var rd: Dictionary = o.cls.radar
		for x in sim.ships:
			if x.side == "blue" or not x.alive or not sim.tracks.has(x.id) or occulted(o.r, x.r):
				continue
			var R := V.dist(o.r, x.r) * 1000.0
			var snr := radar_snr(rd, float(x.cls.get("rcs", 1.0)), R)
			if snr < 20.0:
				continue
			var tr: Track = sim.tracks[x.id]
			var sb := radar_angle_sigma(rd, snr)
			if tr.dims() == 3:
				# Range and both angles as one position fix (Track.update_fix).
				var u := noisy_dir(o.r, x.r, sb)
				tr.update_fix(o.r, R / 1000.0 + gauss() * 0.05, u, 0.05, sb)
				tr.lobs.append({"t": t, "from": o.r, "bearing": atan2(u[1], u[0]), "dir": u, "kind": "radar", "by": o.id, "range": R / 1000.0})
			else:
				tr.update_range(o.r, R / 1000.0 + gauss() * 0.05, 0.05)
				tr.update_bearing(o.r, bearing(o.r, x.r) + gauss() * sb, sb)
				tr.lobs.append({"t": t, "from": o.r, "bearing": bearing(o.r, x.r), "kind": "radar", "by": o.id, "range": R / 1000.0})
			tr.mark_seen(t)
			tr.in_contact = true
			tr.how = "RADAR"


## A ground site's radar (kind "site", on the turning Earth): always on, one
## measurement per look of every object not Blue's that stands above its
## elevation mask, measured from the local vertical (the site's direction
## from the centre), and inside its reach.
## - A site radar given by its measured accuracy ("site": true; the
##   operators' published figures: PFISR, LeoLabs, Space Fence) sees whatever is inside
##   max_range_km, with range to sigma_range_km and both angles to
##   sigma_angle_deg, and no SNR test.
## - Otherwise the radar equation decides (SNR 20, radar_snr), with range
##   to sigma_range_km (or 50 m) and angles to sigma_angle_deg (or the
##   monopulse radar_angle_sigma). The mask and these may sit in the radar
##   block or the class.
## An object it sees without a track starts one at the measured position
## (Track.start, its velocity a circular-orbit guess).
func _site_radar(o: Dictionary, t: float) -> void:
	var rd: Dictionary = o.cls.radar
	var measured := bool(rd.get("site", false))
	var min_el := deg_to_rad(float(rd.get("min_el_deg", o.cls.get("min_el_deg", 0.0))))
	var reach := float(rd.get("max_range_km", o.cls.get("max_range_km", INF)))
	var up := V.scale(o.r, 1.0 / V.norm(o.r))
	for x in sim.ships:
		if x.side == "blue" or not x.alive or not x.has("r"):
			continue
		var d := V.sub(x.r, o.r)
		var R := V.norm(d)
		if R > reach or asin(clampf(V.dot(d, up) / R, -1.0, 1.0)) < min_el:
			continue
		var sr := float(rd.get("sigma_range_km", o.cls.get("sigma_range_km", 0.05)))
		var sa := deg_to_rad(float(rd.get("sigma_angle_deg", o.cls.get("sigma_angle_deg", 0.0))))
		if not measured:
			var snr := radar_snr(rd, float(x.cls.get("rcs", 1.0)), R * 1000.0)
			if snr < 20.0:
				continue
			if sa <= 0.0:
				sa = radar_angle_sigma(rd, snr)
		var rm := R + gauss() * sr
		var u := noisy_dir(o.r, x.r, sa)
		var tr: Track = sim.tracks.get(x.id)
		if tr == null:
			# A position fix: range along the measured line, the angles across it.
			var ee := Track.across_of(u)
			var fix := {"r": V.add(o.r, V.scale(u, rm)), "P2": []}
			for i in 3:
				var row := []
				for j in 3:
					row.append(sr * sr * u[i] * u[j] + (sa * rm) ** 2 * (ee[0][i] * ee[0][j] + ee[1][i] * ee[1][j]))
				fix.P2.append(row)
			var label := "TRK %d" % sim.track_n
			sim.track_n += 3
			tr = Track.start(x.id, label, fix, t)
			sim.tracks[x.id] = tr
			pending.erase(x.id)
			sim.say("new_track", Lang.f("new_track", [label, _where(fix.r)]), "alert")
		else:
			tr.predict(t)
			tr.update_fix(o.r, rm, u, sr, sa)
		tr.lobs.append({"t": t, "from": o.r, "bearing": atan2(u[1], u[0]), "dir": u, "kind": "radar", "by": o.id, "range": R})
		tr.mark_seen(t)
		tr.in_contact = true
		tr.how = "RADAR"


## How far (km) an ear hears a burst at even odds when the emitter's dish is
## off_t rad off the ear and the ear looks straight at it. Pd is 50 % where the
## integrated SNR equals Q⁻¹(Pfa) (RF.detect_pd), whatever the per-sample SNR.
static func reach_km(ttc: Dictionary, esm: Dictionary, off_t: float, pfa: float) -> float:
	var f := float(ttc.f)
	var gt := Antenna.gain_dbi(float(ttc.dish), f, off_t) if ttc.has("dish") else float(ttc.get("towardUsDbi", 0.0))
	var at1m := link_snr(float(ttc.Pt), gt, Antenna.peak_dbi(float(esm.dish), f), f, float(ttc.bw), float(esm.Ts), 1.0, float(ttc.get("burst", 60.0)))
	return sqrt(at1m / RF.q_inv(pfa)) / 1000.0
