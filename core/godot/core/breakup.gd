## What a hypervelocity hit does: the NASA Standard Breakup Model (SBM) for the
## debris, and which of the target's components the hit lands on.
##
## The 1998 NASA Breakup Model (Johnson, Krisko, Liou & Anz-Meador 2001, "NASA's
## new breakup model of EVOLVE 4.0", Adv. Space Res. 28(9) 1377-1384), as
## NASA's Orbital Debris Program Office states it (Krisko 2011, "Proper
## implementation of the 1998 NASA Breakup Model", Orbital Debris Quarterly News
## 15(4) 4-5):
## - A collision is catastrophic when the projectile's kinetic energy over the
##   target's mass reaches 40 J/g (EMR, as used by Joubert & Tingay 2020,
##   arXiv:2008.03657). Then the whole of both breaks up.
## - Fragments of characteristic length Lc (m) or larger: N = 0.1 M^0.75 Lc^-1.71,
##   with M = Mt + Mp (kg) when catastrophic, else M = Mp · v² (kg, km/s): a
##   small projectile fully fragmented, cratering a large target that survives.
## - Each fragment's area-to-mass ratio χ = log10(A/m) is drawn for its
##   λc = log10(Lc) from Johnson et al. 2001's spacecraft distributions, as
##   tabulated in Frey & Colombo 2021, JGCD 44(1), App. B: bimodal above 11 cm
##   (eqs. B5), one normal below 8 cm (eqs. B6), and a blend linear in λc between
##   (eqs. B7-B8; the 2001 paper names a transition but not its form),
##   and its speed from log10 Δv (m/s) ~ N(0.9χ + 2.9, 0.4) (collisions; Thiele &
##   Boley 2022, J. Astronaut. Sci., after Frey & Colombo 2021, JGCD 44(1)).
## The model gives speeds, not directions: they are drawn isotropically, in
## opposite pairs so the cloud's momentum is the wreck's (Joubert & Tingay instead redraw until the
## cloud's net momentum is under 1%).
class_name Breakup

const EMR_CATASTROPHIC := 40.0 # J/g (Johnson et al. 2001)
const LC_MIN := 0.1 # m: the smallest fragment counted, about what deep-space radars catalogue (design value)
const LC_MAX := 1.0 # m: the power law's top; larger pieces are the few big remnants (Krisko 2011)
const SAMPLES := 120 # fragments flown individually per cloud, each standing for n / SAMPLES (display and tracking)
## Spall and shock carry past the struck component: neighbours within this
## distance along the hull are also knocked out, each with this chance (design values).
const NEAR_M := 2.0
const NEAR_P := 0.5


## Energy-to-mass ratio (J/g) of a projectile mp_kg at v_kms on a target mt_kg.
static func emr(mp_kg: float, v_kms: float, mt_kg: float) -> float:
	return 0.5 * mp_kg * pow(v_kms * 1000.0, 2.0) / maxf(mt_kg * 1000.0, 1e-9)


## The collision mass M (kg) behind the fragment count.
static func collision_mass(mp_kg: float, v_kms: float, mt_kg: float) -> float:
	if emr(mp_kg, v_kms, mt_kg) >= EMR_CATASTROPHIC:
		return mt_kg + mp_kg
	return mp_kg * v_kms * v_kms


## Fragments of Lc or larger (m) from a collision of mass M (kg).
static func fragments(M: float, lc := LC_MIN) -> int:
	return int(floor(0.1 * pow(M, 0.75) * pow(lc, -1.71)))


## Draw Lc (m) from the power law N(>Lc) ∝ Lc^-k between lmin and lmax
## (collisions k = 1.71, explosions 1.6).
static func _draw_lc(rng: RandomNumberGenerator, k := 1.71, lmin := LC_MIN, lmax := LC_MAX) -> float:
	var lo := pow(lmin, -k)
	var hi := pow(lmax, -k)
	return pow(lo - rng.randf() * (lo - hi), -1.0 / k)


static func _ramp(x: float, x0: float, y0: float, x1: float, y1: float) -> float:
	if x <= x0:
		return y0
	if x >= x1:
		return y1
	return y0 + (y1 - y0) * (x - x0) / (x1 - x0)


## χ = log10(A/m) for a spacecraft fragment of λc = log10(Lc): the large-object
## law above 11 cm, the small-object law below 8 cm, blended between (eq. B8).
static func _draw_chi(lc: float, rng: RandomNumberGenerator) -> float:
	var l := log(lc) / log(10.0)
	var w := _ramp(l, log(0.08) / log(10.0), 0.0, log(0.11) / log(10.0), 1.0) # eq. B7
	if rng.randf() >= w:
		return rng.randfn(_ramp(l, -1.75, -0.3, -1.25, -1.0), 0.2 + 0.1333 * maxf(l + 3.5, 0.0)) # eqs. B6
	var alpha := _ramp(l, -1.95, 0.0, 0.55, 1.0) # = 0.3 + 0.4(λc + 1.2) between the ends
	var mu1 := _ramp(l, -1.1, -0.6, 0.0, -0.95)
	var s1 := _ramp(l, -1.3, 0.1, -0.3, 0.3)
	var mu2 := _ramp(l, -0.7, -1.2, -0.1, -2.0)
	var s2 := _ramp(l, -0.5, 0.5, -0.3, 0.3)
	if rng.randf() < alpha:
		return rng.randfn(mu1, s1)
	return rng.randfn(mu2, s2)


## Ejection speed (km/s) for a fragment of area-to-mass χ.
static func _draw_dv(chi: float, rng: RandomNumberGenerator) -> float:
	return pow(10.0, rng.randfn(0.9 * chi + 2.9, 0.4)) / 1000.0


## Fragments of Lc or larger (m) from an explosion of scaling factor S
## (1 for a typical rocket body or spacecraft; Johnson et al. 2001).
static func explosion_fragments(S: float, lc := LC_MIN) -> int:
	return int(floor(6.0 * S * pow(lc, -1.6)))


## A fragment's average cross-section (m²) for its characteristic length Lc (m)
## (Johnson et al. 2001).
static func area(lc: float) -> float:
	if lc < 0.00167:
		return 0.540424 * lc * lc
	return 0.556945 * pow(lc, 2.0047077)


## χ = log10(A/m) for a fragment of a rocket body (upper stage): the large-object
## law above 11 cm (Johnson et al. 2001), the
## same small-object law as a spacecraft's below 1.7 cm, blended between.
static func _draw_chi_rb(lc: float, rng: RandomNumberGenerator) -> float:
	var l := log(lc) / log(10.0)
	var w := _ramp(l, log(0.017) / log(10.0), 0.0, log(0.11) / log(10.0), 1.0)
	if rng.randf() >= w:
		return rng.randfn(_ramp(l, -1.75, -0.3, -1.25, -1.0), 0.2 + 0.1333 * maxf(l + 3.5, 0.0))
	var alpha := _ramp(l, -1.4, 1.0, 0.0, 0.5) # = 1 - 0.3571(λc + 1.4) between the ends
	var mu1 := _ramp(l, -0.5, -0.45, 0.0, -0.9)
	var s2 := _ramp(l, -1.0, 0.28, 0.1, 0.1)
	if rng.randf() < alpha:
		return rng.randfn(mu1, 0.55)
	return rng.randfn(-0.9, s2)


## The fragments of a breakup as the model draws them, for Earth orbit and
## smaller sizes than cloud() flies: kind "collision" (size: the collision mass
## M, kg) or "explosion" (size: the scaling factor S); body "sc" (spacecraft)
## or "rb" (rocket body); Lc between lc_min and lc_max (m; the model is stated
## down to 1 mm). k draws, each standing for n / k fragments: {n, lc, am
## (m²/kg), area (m²), mass (kg), dv (km/s)}. Explosion speeds: log10 Δv (m/s)
## ~ N(0.2χ + 1.85, 0.4) (Johnson et al. 2001).
static func sample(kind: String, size: float, body: String, lc_min: float, lc_max: float, k: int, rng: RandomNumberGenerator) -> Dictionary:
	var explosion := kind == "explosion"
	var n: int
	if explosion:
		n = explosion_fragments(size, lc_min) - explosion_fragments(size, lc_max)
	else:
		n = fragments(size, lc_min) - fragments(size, lc_max)
	var out := {"n": n, "lc": PackedFloat64Array(), "am": PackedFloat64Array(), "area": PackedFloat64Array(), "mass": PackedFloat64Array(), "dv": PackedFloat64Array()}
	for i in k:
		var lc := _draw_lc(rng, 1.6 if explosion else 1.71, lc_min, lc_max)
		var chi := _draw_chi_rb(lc, rng) if body == "rb" else _draw_chi(lc, rng)
		var dv := pow(10.0, rng.randfn(0.2 * chi + 1.85, 0.4)) / 1000.0 if explosion else _draw_dv(chi, rng)
		var a := area(lc)
		out.lc.append(lc)
		out.am.append(pow(10.0, chi))
		out.area.append(a)
		out.mass.append(a / pow(10.0, chi))
		out.dv.append(dv)
	return out


## Objects per km³ in spherical shells between radii edges (km), each orbit
## (r, v, about a body of mu km³/s²) weighted by w and averaged over its period:
## the fraction of time an ellipse spends inside radius R is M(E_R)/π, with
## R = a(1 − e cos E_R) and M = E − e sin E (Kessler 1981, Icarus 48, 39).
## Orbits that escape are left out.
static func spatial_density(states: Array, w: PackedFloat64Array, edges: PackedFloat64Array, mu: float) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(edges.size() - 1)
	out.fill(0.0)
	for i in states.size():
		var r: PackedFloat64Array = states[i][0]
		var v: PackedFloat64Array = states[i][1]
		var rn := V.norm(r)
		var a := 1.0 / (2.0 / rn - V.dot(v, v) / mu)
		if a <= 0.0:
			continue
		var h := V.cross(r, v)
		var e := sqrt(maxf(0.0, 1.0 - V.dot(h, h) / (mu * a)))
		var below := func(R: float) -> float:
			if e < 1e-12:
				return 1.0 if R >= a else 0.0
			var c := clampf((1.0 - R / a) / e, -1.0, 1.0)
			var E := acos(c)
			return (E - e * sin(E)) / PI
		for j in out.size():
			out[j] += w[i] * (below.call(edges[j + 1]) - below.call(edges[j]))
	for j in out.size():
		out[j] /= 4.0 / 3.0 * PI * (pow(edges[j + 1], 3.0) - pow(edges[j], 3.0))
	return out


## A debris cloud about (r, v): {r, v, t, n, M, cat, of, frags: [{r, v, dv}]}.
static func cloud(r: PackedFloat64Array, v: PackedFloat64Array, t: float, M: float, cat: bool, of: String, rng: RandomNumberGenerator) -> Dictionary:
	var n := fragments(M)
	var k := mini(SAMPLES, maxi(2, n + n % 2))
	var frags := []
	for i in k / 2:
		var lc := _draw_lc(rng)
		var chi := _draw_chi(lc, rng)
		var dv := _draw_dv(chi, rng)
		var u := rng.randf() * 2.0 - 1.0
		var th := rng.randf() * TAU
		var d := V.of(sqrt(1.0 - u * u) * cos(th) * dv, sqrt(1.0 - u * u) * sin(th) * dv, u * dv)
		for sgn in [1.0, -1.0]:
			frags.append({"r": r.duplicate(), "v": V.add(v, V.scale(d, sgn)), "dv": dv, "lc": lc, "am": pow(10.0, chi)})
	return {"r": r.duplicate(), "v": v.duplicate(), "t": t, "n": n, "M": M, "cat": cat, "of": of, "frags": frags}


## Mass (kg) of a ship as it is now: dry plus propellant (tonnes in the data).
static func mass_kg(s: Dictionary) -> float:
	var dry := float(s.get("dry", s.cls.get("dry", 0.0)))
	if dry <= 0.0:
		dry = float(s.cls.get("mass", 1.0)) # a class without a mass budget: one tonne (design value)
	return (dry + float(s.get("prop", 0.0))) * 1000.0


## Where on the hull a hit lands: a part drawn by the area it presents
## (averaged over approach directions), and the neighbours the shock reaches.
## Returns the components knocked out, as damage tags (see Damage); each part
## struck goes into hits_out as {part (its index in the hull), side (a
## radiator's wing: "p" or "s"), x (m from the bow), primary}.
static func struck(s: Dictionary, hull: Dictionary, rng: RandomNumberGenerator, hits_out: Array = []) -> Array:
	var parts: Array = hull.get("parts", [])
	if parts.is_empty():
		return ["structure"]
	var w := []
	var tot := 0.0
	for p in parts:
		var a := _area(p)
		w.append(a)
		tot += a
	var pick := rng.randf() * tot
	var hit: Dictionary = parts[0]
	for i in parts.size():
		pick -= float(w[i])
		if pick <= 0.0:
			hit = parts[i]
			break
	var x := float(hit.get("x", 0.0)) + float(hit.get("len", 0.0)) / 2.0
	var tags := [_tag(s, hit)]
	hits_out.append({"part": parts.find(hit), "side": _side(hit, rng), "x": x, "primary": true})
	for p in parts:
		if p == hit:
			continue
		var x0 := float(p.get("x", 0.0))
		var x1 := x0 + float(p.get("len", 0.0))
		var gap := maxf(0.0, maxf(x0 - x, x - x1))
		if gap <= NEAR_M and rng.randf() < NEAR_P:
			var t := _tag(s, p)
			hits_out.append({"part": parts.find(p), "side": _side(p, rng), "x": x0 + (x1 - x0) / 2.0, "primary": false})
			if not tags.has(t):
				tags.append(t)
	return tags


## Which wing of a radiator pair a hit takes ("p": +y in Blender, "s": −y).
static func _side(p: Dictionary, rng: RandomNumberGenerator) -> String:
	return ("p" if rng.randf() < 0.5 else "s") if String(p.t) == "rad" else ""


## The tumble an off-centre hit leaves: the projectile's momentum p = mp·vrel
## (fully transferred, β = 1; DART's ejecta raised its push to β ≈ 3.6, Cheng
## et al. 2023, Nature 616:457, so this is the floor) acting at the hit point r
## from the centre of mass gives ΔL = r × p, and ω = I⁻¹ΔL with the hull as a
## solid cylinder: I = ½mR² about its axis, m(3R² + L²)/12 across it. The hull
## lies along its velocity (prograde, as the views hold it), the centre of mass
## at mid-length (design value). Seen from the projectile the hull is a
## rectangle; the hit lands across it at an impact parameter b drawn evenly in
## [−R, R], so the push passes b off the axis (the part of r along p adds
## nothing to r × p). The ship's attitude control then damps the tumble out
## over tau (design value).
const SPIN_TAU := 600.0 # s


static func spin(s: Dictionary, hull: Dictionary, mp_kg: float, vrel: PackedFloat64Array, x_hit: float, rng: RandomNumberGenerator) -> Dictionary:
	var m := mass_kg(s)
	var L := float(s.cls.get("length", 10.0))
	var R := 0.0
	for p in hull.get("parts", []):
		if String(p.t) in ["cyl", "tank", "nose"]:
			R = maxf(R, float(p.get("r", 0.0)))
	if R <= 0.0:
		R = L / 10.0
	var a := V.scale(s.v, 1.0 / maxf(V.norm(s.v), 1e-12)) # the bow's direction
	var e := V.cross(a, vrel) # across the hull as the projectile sees it
	var en := V.norm(e)
	if en < 1e-12:
		e = V.cross(a, V.of(0, 0, 1)) # a hit along the axis: any side will do
		en = V.norm(e)
	e = V.scale(e, 1.0 / maxf(en, 1e-12))
	var r := V.add(V.scale(a, L / 2.0 - x_hit), V.scale(e, (rng.randf() * 2.0 - 1.0) * R)) # m
	var dL := V.cross(r, V.scale(vrel, mp_kg * 1000.0)) # kg m²/s
	var along := V.dot(dL, a)
	var I_ax := 0.5 * m * R * R
	var I_tr := m * (3.0 * R * R + L * L) / 12.0
	var w := V.add(V.scale(a, along / I_ax), V.scale(V.sub(dL, V.scale(a, along)), 1.0 / I_tr))
	return {"w": [w[0], w[1], w[2]], "t0": 0.0, "tau": SPIN_TAU}


## The area a part presents, m², averaged over directions (rough shapes).
static func _area(p: Dictionary) -> float:
	var L := float(p.get("len", 1.0))
	match String(p.t):
		"cyl", "tank", "nose":
			return L * 2.0 * float(p.get("r", 1.0))
		"bell":
			return L * (float(p.get("r0", 0.5)) + float(p.get("r1", 1.0))) * float(p.get("n", 1))
		"dish", "aesa", "esm":
			return 0.785 * pow(float(p.get("d", 1.0)), 2.0)
		"dome":
			return PI * pow(float(p.get("r", 1.0)), 2.0)
		"rad":
			return L * float(p.get("span", 2.0)) * 0.5
		"truss":
			return L * 2.0 * float(p.get("r", 1.0)) * 0.3
		"pods":
			return L * float(p.get("h", 1.0)) * float(p.get("n", 1)) * 0.5
		"facet":
			return L * 0.5 * (float(p.get("h", 2.0)) + float(p.get("w", p.get("h", 2.0))))
		"turret":
			return 4.0
		"ground":
			return 0.0
	return 1.0


## The component a hull part stands for.
static func _tag(s: Dictionary, p: Dictionary) -> String:
	var c: Dictionary = s.cls
	match String(p.t):
		"bell":
			return "engine"
		"tank":
			return "tank"
		"rad":
			return "radiator"
		"dome":
			return "telescope"
		"turret":
			return "laser"
		"aesa":
			return "radar"
		"esm":
			return "esm"
		"pods":
			# A warship's pods are its launcher; a merchant's are cargo.
			return "interceptors" if c.get("weapon", {}).get("kind", "") == "kinetic" else "cargo"
		"dish":
			if c.has("ttc"):
				return "ttc"
			if c.has("radar") and float(p.get("d", 0.0)) >= 3.0:
				return "radar"
			if c.has("esm"):
				return "esm"
			return "datalink"
	return "structure"
