## Heat: where every watt a ship makes goes, and how much of it an infrared
## telescope sees (docs/REALISM-SOURCES.md §2).
## - Skin: a convex hull of area A takes in α·S·A/4 of sunlight (S = 50.26 W/m²
##   at Jupiter, NASA fact sheet; α from Henninger 1984, NASA RP-1121) plus the
##   heat that leaks out from inside, and radiates εσT⁴A (Stefan–Boltzmann). Each
##   class's skin temperature in sunlight is a design value; the leak that holds
##   it there follows, so in Jupiter's shadow the skin cools to (leak/εσA)^¼.
## - Sunlight is the share of the Sun's disc a ship sees (sunlight()): the Sun
##   at its true 3-D place (ephem.gd), a disc of radius 695,700 km (IAU 2015 B3)
##   darkened to its limb as I(μ) = 1 − u(1 − μ), u = 0.6 (the visible-band
##   value, Cox 2000, Allen's Astrophysical Quantities §14.7; white-light 0.61
##   measured by Tripathi et al. 2020, J. Sci. Res. BHU 64(1); used for all
##   sunlight: a simplification), hidden by Jupiter as an oblate ellipsoid
##   (71,492 × 66,854 km, Archinal et al. 2018), by the four moons, and near a
##   planet by that planet. Full shadow (umbra) is 0, the rim (penumbra) between.
## - The skin has heat capacity: C·dT/dt = leak + α·S·f·A/4 − εσT⁴A (a lumped
##   capacitance; Gilmore 2002, Spacecraft Thermal Control Handbook; corroborated
##   by Gaite & Fernández-Rico 2012, JTHT 26:511, §II Eq. 1), so
##   it cools through a shadow and warms after, over a time C/(4εσAT³). C is
##   the class's sig.C (J/K) if set, else aluminium (897 J/kg·K at 298 K: 24.20 J/mol·K, NIST-JANAF,
##   Chase 1998, via the NIST Chemistry WebBook) for a quarter of the dry mass (design value).
## - Reactor: a plant of P_e at end-to-end efficiency η makes P_e(1/η − 1) of
##   waste heat (NASA Glenn's JIMO power-system study: 100 kWe at 20.2%; Mason
##   2003), rejected by a two-sided
##   radiator at T = (Q/2εσA)^¼ (JIMO: 170 m² over both faces, ε 0.9; Siamidis 2005).
##   The electricity itself ends as heat in the loads, inside the skin's budget.
## - Aspect: each radiator face is Lambertian, I(θ) = εσT⁴A·cosθ/π (NAWCWD TP 8347
##   §7-1), so a panel edge-on to an observer shows only its edge. Every ship lays
##   its radiators flat to the plane of play, normal out of the plane: everyone in
##   the plane (here, everyone) sees only the edge, and the Sun, also in the plane,
##   puts no load on the faces. The game is planar; in 3-D the same trick needs
##   the threats to share a plane.
## - Heat sink: a phase-change store (kg × latent heat; Leimkuehler 2011, Choi
##   2012) or water evaporated and vented takes the radiator's load so the ship
##   can go dark for a while. A phase-change store is refrozen afterwards by
##   running the radiator harder; vented water is gone. The switch acts at once
##   (reactor(): the heat is settled up to the moment of the switch, and the
##   radiators go cold or light then, not at the next look). The sink takes
##   the plant's waste heat only: the skin's leak heat and sunlight still
##   show, so a big warm hull stays visible close in, dark or not.
## - Laser: 1 MW of beam at 25% wall-plug dumps 3 MW into the radiators while it fires.
## - In band: a telescope sees only the 6–10 µm share of each body's emission
##   (NEO Surveyor's NC2 band, Mainzer et al. 2023), from the Planck series of
##   Widger & Woodall (1976, Bull. AMS 57:1217; the same series as Lewis &
##   McClarren 2025, arXiv:2503.08892, §3.1).
class_name Thermal
extends RefCounted

const C2 := 14387.768775 # µm·K, second radiation constant hc/k (CODATA 2018)
const BAND := [6.0, 10.0] # µm, NEO Surveyor NC2
const SIGMA := RF.SIGMA_SB
## Refreezing a phase-change store: the radiator carries up to this many times
## the plant's own waste heat extra while it refreezes (design value).
const RECHARGE := 1.0
const LIMB_U := 0.6
const CP_AL := 897.0 # J/kg·K
const SKIN_SHARE := 0.25 # share of dry mass that holds the skin's heat (design value)
const SUBSTEP := 60.0 # s, skin-temperature integration step
## Sample points across the Sun's disc: [x, y] in units of its radius, weight
## (annulus area × limb darkening), normalised. Built once.
static var _disc: Array = []

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


## Share of a black body's exitance at wavelengths shorter than lam (µm) at T (K):
## (15/π⁴) Σ e^(−nx)/n · (x³ + 3x²/n + 6x/n² + 6/n³), x = c₂/λT (Widger & Woodall 1976).
static func frac_below(lam: float, T: float) -> float:
	if T <= 0.0:
		return 0.0
	var x := C2 / (lam * T)
	var s := 0.0
	var terms := clampi(int(2.0 + 30.0 / x), 4, 2000)
	for n in range(1, terms + 1):
		var fn := float(n)
		s += exp(-fn * x) / fn * (x * x * x + 3.0 * x * x / fn + 6.0 * x / (fn * fn) + 6.0 / (fn * fn * fn))
	return clampf(15.0 / pow(PI, 4.0) * s, 0.0, 1.0)


## Share of a black body's exitance inside the band [a, b] µm.
static func band_fraction(T: float, a: float = BAND[0], b: float = BAND[1]) -> float:
	return maxf(0.0, frac_below(b, T) - frac_below(a, T))


static func sun_flux(sim_data: Dictionary) -> float:
	return float(sim_data.jupiter.sunIrradiance)


## Heat leaking out through the skin from inside (W): what holds the design
## skin temperature in sunlight. Never negative: a skin that sunlight alone would
## hold warmer than its design value runs at its sunlit equilibrium instead.
static func skin_leak(sig: Dictionary, S: float) -> float:
	var A := float(sig.A)
	var a := float(sig.get("alpha", sig.eps))
	return maxf(0.0, float(sig.eps) * SIGMA * pow(float(sig.T), 4.0) * A - a * S * A / 4.0)


## Skin temperature (K), sunlit or in shadow.
static func skin_T(sig: Dictionary, S: float, sunlit: bool) -> float:
	var A := float(sig.A)
	var a := float(sig.get("alpha", sig.eps))
	var q := skin_leak(sig, S) + (a * S * A / 4.0 if sunlit else 0.0)
	return pow(q / (float(sig.eps) * SIGMA * A), 0.25) if q > 0.0 else 3.0


## The plant's waste heat (W) and its radiator's temperature (K) when it carries Q.
static func waste(cls: Dictionary) -> float:
	var th: Dictionary = cls.get("thermal", {})
	if not th.has("reactor"):
		return 0.0
	return float(th.reactor.kWe) * 1000.0 * (1.0 / float(th.reactor.eta) - 1.0)


static func radiator_T(rad: Dictionary, Q: float) -> float:
	return pow(Q / (2.0 * float(rad.eps) * SIGMA * float(rad.A)), 0.25) if Q > 0.0 else 0.0


## In-band intensity (W/sr) of a radiator at T seen at angle th from its normal:
## the face, cosθ, plus the edge, a strip t × √A, sinθ (t is a design value), at
## the face's ε unless the edge has its own finish (edgeEps: a stealth hull's
## low-ε coating, Henninger 1984).
static func radiator_I(rad: Dictionary, T: float, th: float) -> Dictionary:
	if T <= 0.0:
		return {"face": 0.0, "edge": 0.0}
	var M := SIGMA * pow(T, 4.0) * band_fraction(T) / PI
	return {"face": float(rad.eps) * M * float(rad.A) * absf(cos(th)), "edge": float(rad.get("edgeEps", rad.eps)) * M * float(rad.get("t", 0.02)) * sqrt(float(rad.A)) * absf(sin(th))}


static func grey_band(sig: Dictionary, T := -1.0) -> float:
	var TT := float(sig.T) if T < 0.0 else T
	return float(sig.eps) * SIGMA * pow(TT, 4.0) * float(sig.A) * band_fraction(TT) / (4.0 * PI)


## Is this point in shadow (more than half the Sun hidden)?
func in_shadow(r: PackedFloat64Array, at := NAN) -> bool:
	return sunlight(r, at) < 0.5


static func _build_disc() -> void:
	var rings := 12
	var tot := 0.0
	for k in rings:
		var q0 := float(k) / rings
		var q1 := float(k + 1) / rings
		var q := (q0 + q1) / 2.0 if k > 0 else 0.0
		var n := 1 if k == 0 else 6 * k
		var mu := sqrt(maxf(0.0, 1.0 - q * q))
		var w := (q1 * q1 - q0 * q0) * (1.0 - LIMB_U * (1.0 - mu)) / n
		for j in n:
			var ph := TAU * (j + 0.5 * (k % 2)) / n
			_disc.append([q * cos(ph), q * sin(ph), w])
			tot += w
	for d in _disc:
		d[2] /= tot


## What share of the Sun's light reaches r (0 in full shadow, 1 in full sun).
func sunlight(r: PackedFloat64Array, at := NAN) -> float:
	var tt: float = sim.t if is_nan(at) else at
	var ms := sim.utc_ms(tt)
	# The bodies that could stand in the way: [centre, equatorial, polar radius].
	var bodies := [[V.of(0, 0, 0), sim.central_radius(), sim.central_polar()]]
	for m in sim.moons:
		bodies.append([sim.moon_state(m.id, tt)[0], float(m.radius), float(m.radius)])
	if V.norm(r) > Gravity.FAR:
		for b in Ephem.PLANETS:
			if b != "jupiter":
				bodies.append([Ephem.pos(b, ms), float(Ephem.BODY[b].re), float(Ephem.BODY[b].rp)])
	return lit_share(r, sim.sun_pos(tt), bodies)


## The geometry alone: the limb-darkened share of a Sun at sun (km) seen from
## r past these bodies ([centre, equatorial radius, polar radius], pole on z).
static func lit_share(r: PackedFloat64Array, sun: PackedFloat64Array, bodies: Array) -> float:
	var sv := V.sub(sun, r)
	var ds := V.norm(sv)
	var sh := V.scale(sv, 1.0 / ds)
	var rho_s := asin(Ephem.R_SUN / ds)
	var near := []
	for b in bodies:
		var ov := V.sub(b[0], r)
		var do := V.norm(ov)
		if do >= ds or do <= float(b[1]):
			continue
		var along := V.dot(ov, sh)
		if along <= 0.0:
			continue
		var sep := acos(clampf(along / do, -1.0, 1.0))
		var rho_o := asin(float(b[1]) / do)
		if sep >= rho_s + rho_o:
			continue # clear of the disc
		if sep + rho_s <= asin(float(b[2]) / do):
			return 0.0 # the whole disc behind it, even at its poles: umbra
		near.append(b)
	if near.is_empty():
		return 1.0
	# The rim: trace rays to points across the disc.
	if _disc.is_empty():
		_build_disc()
	var u := V.cross(sh, V.of(0, 0, 1))
	if V.norm(u) < 1e-9:
		u = V.of(1, 0, 0)
	u = V.scale(u, 1.0 / V.norm(u))
	var w := V.cross(sh, u)
	var tr := tan(rho_s)
	var lit := 0.0
	for d in _disc:
		var dir := V.add(sh, V.add(V.scale(u, tr * float(d[0])), V.scale(w, tr * float(d[1]))))
		dir = V.scale(dir, 1.0 / V.norm(dir))
		var hit := false
		for b in near:
			if _ray_hits(V.sub(r, b[0]), dir, float(b[1]), float(b[2])):
				hit = true
				break
		if not hit:
			lit += float(d[2])
	return lit


## Does a ray from o (relative to a body's centre) along dir pass through the
## ellipsoid of equatorial radius a and polar radius c (pole along z)?
static func _ray_hits(o: PackedFloat64Array, dir: PackedFloat64Array, a: float, c: float) -> bool:
	var k := a / c
	var oo := V.of(o[0], o[1], o[2] * k)
	var dd := V.of(dir[0], dir[1], dir[2] * k)
	var A := V.dot(dd, dd)
	var B := V.dot(oo, dd)
	var t := -B / A
	if t <= 0.0:
		return false
	var closest := V.add(oo, V.scale(dd, t))
	return V.dot(closest, closest) < a * a


## The skin's heat capacity (J/K).
static func heat_capacity(s: Dictionary) -> float:
	var sig: Dictionary = s.cls.sig
	if sig.has("C"):
		return float(sig.C)
	return CP_AL * SKIN_SHARE * float(s.get("dry", s.cls.get("dry", 1.0))) * 1000.0


## Equilibrium skin temperature (K) at sunlight share f.
static func skin_eq(sig: Dictionary, S: float, f: float) -> float:
	var A := float(sig.A)
	var a := float(sig.get("alpha", sig.eps))
	var q := skin_leak(sig, S) + a * S * f * A / 4.0
	return pow(q / (float(sig.eps) * SIGMA * A), 0.25) if q > 0.0 else 3.0


## Advance a skin temperature T over dt seconds at sunlight share f.
static func skin_step(sig: Dictionary, S: float, f: float, C: float, T: float, dt: float) -> float:
	var A := float(sig.A)
	var a := float(sig.get("alpha", sig.eps))
	var q := skin_leak(sig, S) + a * S * f * A / 4.0
	var n := maxi(1, ceili(dt / SUBSTEP))
	var h := dt / n
	for i in n:
		# Implicit in the T⁴ term (linearised), so a long step cannot overshoot.
		var k := 4.0 * float(sig.eps) * SIGMA * A * T * T * T
		T += h * (q - float(sig.eps) * SIGMA * A * pow(T, 4.0)) / (C + h * k)
	return T


## The skin's time constant (s) near temperature T.
static func skin_tau(s: Dictionary, T: float) -> float:
	var sig: Dictionary = s.cls.sig
	return heat_capacity(s) / (4.0 * float(sig.eps) * SIGMA * float(sig.A) * T * T * T)


## The ship's skin temperature now (K), set to equilibrium on first asking.
func skin_now(s: Dictionary) -> float:
	var h: Dictionary = s.get("heat", {})
	if not h.has("T_skin"):
		h.T_skin = skin_eq(s.cls.sig, sun_flux(sim.data), sunlight(s.r))
		s.heat = h
	return float(h.T_skin)


## Each look: settle every powered ship's heat flows for the last dt seconds.
func step(dt: float) -> void:
	var S := sun_flux(sim.data)
	for s in sim.ships:
		if s.alive and s.cls.has("sig") and s.has("r"):
			var T0 := skin_now(s)
			var f := sunlight(s.r)
			s.heat.sun = f
			s.heat.T_skin = skin_step(s.cls.sig, S, f, heat_capacity(s), T0, dt)
	for s in sim.ships:
		if not s.alive or not s.cls.has("thermal") or not s.cls.thermal.has("reactor"):
			continue
		var h: Dictionary = s.get("heat", {})
		# Only the part of the look not already settled (a switch mid-look settled up to then).
		var pre := float(h.get("pre", 0.0))
		h.pre = 0.0
		s.heat = h
		reactor(s, maxf(dt - pre, 0.0))


## The plant's heat over the last dt seconds, to the radiators or into the sink:
## the sink fills by what it takes, the radiators carry the rest (their
## temperature, T_rad, follows at once: a panel's time constant is minutes,
## shorter than a look). dt = 0 sets the radiators for the present mode alone.
func reactor(s: Dictionary, dt: float) -> void:
	var th: Dictionary = s.cls.thermal
	var h: Dictionary = s.get("heat", {})
	var Q := waste(s.cls)
	var stored := float(h.get("stored", 0.0))
	var cap := 0.0
	if th.has("sink"):
		cap = float(th.sink.kg) * float(th.sink.kJkg) * 1000.0 - float(h.get("vented", 0.0))
	var Qr := Q
	var dark: bool = h.get("dark", false) and cap - stored > 1.0
	if dark:
		Qr = 0.0
		if dt > 0.0:
			var take := minf(Q * dt, cap - stored)
			stored += take
			Qr = Q - take / dt
			if stored >= cap - 1.0:
				h.dark = false
				if s.side == "blue":
					sim.say("sink_full", Lang.f("sink_full", [s.short]), "warn")
	elif h.get("dark", false):
		h.dark = false # nothing left to take the heat
	elif stored > 0.0:
		if th.sink.get("vent", false):
			h.vented = float(h.get("vented", 0.0)) + stored
			stored = 0.0
		elif dt > 0.0:
			var give := 0.0 if h.get("hold", false) else minf(stored, RECHARGE * Q * dt) # hold: put off refreezing
			stored -= give
			Qr = Q + give / dt
		elif not h.get("hold", false):
			Qr = Q * (1.0 + RECHARGE) # refreezing from now on
	# The laser's waste heat, for the dwell after each shot (judged at its peak, like a burn).
	if float(s.get("laser_fired", -1e9)) > sim.sensing.last_look - float(s.cls.get("weapon", {}).get("maxDwell", 0.0)):
		var w: Dictionary = s.cls.weapon
		Qr += float(w.power) * (1.0 / float(w.get("wallPlug", 0.25)) - 1.0)
	h.stored = stored
	h.Q = Qr
	h.T_rad = radiator_T(th.radiator, Qr)
	h.settled = sim.t # when the heat was last settled
	s.heat = h


## Seconds of heat sink left at the plant's full waste heat.
func dark_left(s: Dictionary) -> float:
	var th: Dictionary = s.cls.get("thermal", {})
	if not th.has("sink") or waste(s.cls) <= 0.0:
		return 0.0
	var h: Dictionary = s.get("heat", {})
	var cap := float(th.sink.kg) * float(th.sink.kJkg) * 1000.0 - float(h.get("vented", 0.0))
	return maxf(0.0, cap - float(h.get("stored", 0.0))) / waste(s.cls)


## The crew's choice: send the waste heat to the sink (dark) or to the radiators.
func set_dark(id: String, on: bool) -> void:
	var s: Dictionary = sim.by_id[id]
	var h: Dictionary = s.get("heat", {})
	if on and dark_left(s) <= 0.0:
		return
	# Settle the heat up to now in the old mode, then switch: the radiators go
	# cold (or light) at once, not at the next look.
	if s.cls.get("thermal", {}).has("reactor") and s.alive:
		var pre := clampf(sim.t - float(h.get("settled", sim.t)), 0.0, Sim.LOOK)
		reactor(s, pre)
		h = s.heat
		h.pre = float(h.get("pre", 0.0)) + pre
	h.dark = on
	s.heat = h
	if s.cls.get("thermal", {}).has("reactor") and s.alive:
		reactor(s, 0.0)
	sim.say("dark_on" if on else "dark_off", Lang.f("dark_on" if on else "dark_off", [s.short]), "info")


## Everything a ship radiates toward a point, in band (W/sr), term by term.
func intensity(s: Dictionary, toward: PackedFloat64Array, burning := false) -> Dictionary:
	var f := float(s.get("heat", {}).get("sun", -1.0))
	if f < 0.0:
		f = sunlight(s.r)
	var lit := f >= 0.5
	var Th := skin_now(s) if s.has("cls") and s.has("alive") else skin_eq(s.cls.sig, sun_flux(sim.data), f)
	var out := {"skin": grey_band(s.cls.sig, Th), "T_skin": Th, "sunlit": lit, "sun": f, "face": 0.0, "edge": 0.0, "engine": 0.0, "T_rad": 0.0, "theta": 0.0, "Q": 0.0}
	var h: Dictionary = s.get("heat", {})
	if s.cls.has("thermal") and s.cls.thermal.has("radiator") and float(h.get("T_rad", 0.0)) > 0.0:
		var th := PI / 2.0 # radiators flat to the plane: every in-plane observer is 90° off their normal
		var ri := radiator_I(s.cls.thermal.radiator, float(h.T_rad), th)
		out.face = ri.face
		out.edge = ri.edge
		out.T_rad = float(h.T_rad)
		out.theta = th
		out.Q = float(h.get("Q", 0.0))
	if burning and s.cls.has("engine"):
		out.engine = grey_band(s.cls.engine.hot)
	out.total = float(out.skin) + float(out.face) + float(out.edge) + float(out.engine)
	return out


## How far (km) a sensor of in-band NEI sees this class at SNR k: coasting in
## sunlight (skin, radiators edge-on), radiators face-on (an observer off the
## plane, for reference), burning, and in shadow.
static func ranges(cls: Dictionary, nei: float, S: float, k := 5.0) -> Dictionary:
	var sig: Dictionary = cls.sig
	var skin := grey_band(sig, skin_T(sig, S, true))
	var shade := grey_band(sig, skin_T(sig, S, false))
	var face := 0.0
	var edge := 0.0
	if cls.has("thermal") and cls.thermal.has("radiator"):
		var T := radiator_T(cls.thermal.radiator, waste(cls))
		face = radiator_I(cls.thermal.radiator, T, 0.0).face
		edge = radiator_I(cls.thermal.radiator, T, PI / 2.0).edge
	var eng: float = grey_band(cls.engine.hot) if cls.has("engine") else 0.0
	var R := func(I: float) -> float: return sqrt(I / (k * nei)) / 1000.0
	return {"cold": R.call(skin + edge), "dark": R.call(skin), "face": R.call(skin + face), "burning": R.call(skin + edge + eng), "shadow": R.call(shade)}
