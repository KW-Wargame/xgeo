## Real gravity for everything that coasts: Jupiter as an oblate body (point
## mass plus its J2 zonal harmonic) and the pull of the four Galilean moons.
##
## - J2 = 14696.514e-6 at reference radius 71,492 km, measured from Juno's
##   first orbits: Folkner, W. M. et al. (2017), "Jupiter gravity field
##   estimated from the first two Juno orbits", Geophys. Res. Lett. 44,
##   4694–4700, Table 2 (also tabulated in A&A 613, A32, 2018, Table 1).
## - The J2 acceleration is the gradient of the zonal potential term
##   −μJ2R²(3z²−r²)/(2r⁵); in the equatorial plane it is purely radial,
##   −(3/2)μJ2R²/r⁴ (Vallado 2013, Fundamentals of Astrodynamics, §8.6; corroborated
##   by hapsira's J2_perturbation, which the repo test matches to 9e-11).
## - The moons act as third bodies. The frame is centred on Jupiter, which the
##   moons also pull, so each moon adds its direct pull minus the pull it
##   gives Jupiter (the "indirect" term): μm[(rm−r)/|rm−r|³ − rm/|rm|³]
##   (Curtis 2020, ch. 10; Montenbruck & Gill 2000, §3.3; corroborated by
##   NASA/TP-20220014814, §7.1, Eq. 117).
## - The Sun and the eight planets act the same way, from JPL's approximate
##   planetary positions (ephem.gd), GMs from DE440: the Sun everywhere (its
##   tide moves a ship near Ganymede ~10 km in three days), the planets once a
##   ship is out past the Galilean system (FAR), where their pull can matter;
##   inside it their tides are below 1e-12 km/s² (under 1e-7 of Jupiter's pull). So a ship can leave Jupiter
##   and fly to Mars or Earth in the same frame, no patching of conics: Cowell's
##   method in a Jupiter-centred frame (Montenbruck & Gill 2000, §3.3;
##   NASA/TP-20220014814, §7.1).
## The moons' own motion is the JPL mean-element ephemeris (moons.gd).
## Integrated by DOP853, the Dormand–Prince 8(5,3) pair with error control
## (coast, coast_to, coast_stm): every step held to a relative 1e-12, so steps lengthen
## on quiet arcs and shorten at a close pass or near a planet, with no step
## rule to tune. tools/verify checks the coasts against scipy's DOP853 at
## 1e-13. The classical fourth-order Runge–Kutta step (step) stays for tests.
class_name Gravity

const J2 := 14696.514e-6
const R_REF := 71492.0
const FAR := 3.0e6 # km from Jupiter: past Callisto (1.88e6) the planets join in
const ETA_NEAR := 0.01 # the forecast's measure of coast cost close to Jupiter: work per sample grows as dt / (ETA_NEAR sqrt(r³/μ))

var mu: float
var moons: Array # of Dictionary (with gm)
var moon_state: Callable # (id, t) -> [r, v]
## The central body's oblateness: J2 at reference radius r_ref, about its pole
## (a unit vector in the game frame). Jupiter's unless a world names another
## body (Sim, a scenario's "central" block).
var j2 := J2
var r_ref := R_REF
var pole := PackedFloat64Array([0.0, 0.0, 1.0])
var central := "jupiter"
var use_j2 := true
var use_moons := true
var use_sun := true
var utc_of: Callable # (t) -> UTC ms; unset, no Sun or planets
## About a body other than Jupiter, the planets join in past this distance
## (km): its sphere of influence, set with the central body (Sim). Inside it
## their tides are below 1e-12 km/s² at the Earth.
var far := FAR


func _init(mu_: float, moons_: Array, moon_state_: Callable) -> void:
	mu = mu_
	moons = moons_
	moon_state = moon_state_


## Acceleration (km/s²) at position r and sim time t.
func accel(r: PackedFloat64Array, t: float) -> PackedFloat64Array:
	var r2 := V.dot(r, r)
	var rn := sqrt(r2)
	var a := V.scale(r, -mu / (r2 * rn))
	if use_j2 and central == "jupiter":
		var z2 := r[2] * r[2] / r2
		var k := -1.5 * J2 * mu * R_REF * R_REF / (r2 * r2 * rn)
		a = V.add(a, V.of(k * r[0] * (1.0 - 5.0 * z2), k * r[1] * (1.0 - 5.0 * z2), k * r[2] * (3.0 - 5.0 * z2)))
	elif use_j2:
		a = V.add(a, _j2_pole(r))
	if use_moons:
		for m in moons:
			var rm: PackedFloat64Array = moon_state.call(m.id, t)[0]
			var d := V.sub(rm, r)
			var dn := V.norm(d)
			var rmn := V.norm(rm)
			var gm: float = m.gm
			a = V.add(a, V.sub(V.scale(d, gm / (dn * dn * dn)), V.scale(rm, gm / (rmn * rmn * rmn))))
	if use_sun and utc_of.is_valid():
		var ms: float = utc_of.call(t)
		a = V.add(a, _third(r, _sun_at(t, ms), Ephem.GM_SUN))
		if central == "jupiter":
			if rn > FAR:
				for b in Ephem.PLANETS:
					if b != "jupiter":
						a = V.add(a, _third(r, Ephem.pos(b, ms), float(Ephem.BODY[b].gm)))
		if central == "earth" and use_moons:
			a = V.add(a, _third(r, _moon_at(t, ms), Ephem.GM_MOON))
		if central != "jupiter" and rn > far:
			# About another body: every other planet, Jupiter among them, from
			# the central body (the ephemeris is centred on Jupiter).
			var c := Ephem.pos(central, ms)
			for b in Ephem.PLANETS:
				if b != central:
					a = V.add(a, _third(r, V.sub(Ephem.pos(b, ms), c), float(Ephem.BODY[b].gm)))
	return a


## J2 about any pole p: -(3/2)μJ2R²/r⁵ [(1 − 5z²/r²) r + 2z p], z = r·p
## (Vallado 2013, §8.6, with the pole along p rather than z).
func _j2_pole(r: PackedFloat64Array) -> PackedFloat64Array:
	var r2 := V.dot(r, r)
	var z := V.dot(r, pole)
	var k := -1.5 * j2 * mu * r_ref * r_ref / (r2 * r2 * sqrt(r2))
	return V.add(V.scale(r, k * (1.0 - 5.0 * z * z / r2)), V.scale(pole, 2.0 * k * z))


## The Sun for this instant, kept for the next asker at the same time (each
## coast starts its steps at the tick's time).
var _sun_memo := {}


func _sun_at(t: float, ms: float) -> PackedFloat64Array:
	if _sun_memo.has(t):
		return _sun_memo[t]
	if _sun_memo.size() > 64:
		_sun_memo.clear()
	var p := Ephem.pos("sun", ms) if central == "jupiter" else V.sub(Ephem.pos("sun", ms), Ephem.pos(central, ms))
	_sun_memo[t] = p
	return p


var _moon_memo := {}


func _moon_at(t: float, ms: float) -> PackedFloat64Array:
	if _moon_memo.has(t):
		return _moon_memo[t]
	if _moon_memo.size() > 64:
		_moon_memo.clear()
	_moon_memo[t] = Ephem.moon(ms)
	return _moon_memo[t]


## A third body at rb: its pull on the ship less its pull on Jupiter.
static func _third(r: PackedFloat64Array, rb: PackedFloat64Array, gm: float) -> PackedFloat64Array:
	var d := V.sub(rb, r)
	var dn := V.norm(d)
	var bn := V.norm(rb)
	return V.sub(V.scale(d, gm / (dn * dn * dn)), V.scale(rb, gm / (bn * bn * bn)))


## One RK4 step of length h from (r, v) at time t. Returns [r, v].
func step(r: PackedFloat64Array, v: PackedFloat64Array, t: float, h: float) -> Array:
	var k1v := accel(r, t)
	var k1r := v
	var r2 := V.add(r, V.scale(k1r, h / 2.0))
	var v2 := V.add(v, V.scale(k1v, h / 2.0))
	var k2v := accel(r2, t + h / 2.0)
	var k2r := v2
	var r3 := V.add(r, V.scale(k2r, h / 2.0))
	var v3 := V.add(v, V.scale(k2v, h / 2.0))
	var k3v := accel(r3, t + h / 2.0)
	var k3r := v3
	var r4 := V.add(r, V.scale(k3r, h))
	var v4 := V.add(v, V.scale(k3v, h))
	var k4v := accel(r4, t + h)
	var k4r := v4
	var rn := V.add(r, V.scale(V.add(V.add(k1r, V.scale(k2r, 2.0)), V.add(V.scale(k3r, 2.0), k4r)), h / 6.0))
	var vn := V.add(v, V.scale(V.add(V.add(k1v, V.scale(k2v, 2.0)), V.add(V.scale(k3v, 2.0), k4v)), h / 6.0))
	return [rn, vn]


## The Dormand–Prince 8(5,3) pair (Hairer, Nørsett & Wanner 1993, Solving
## Ordinary Differential Equations I, §II.5 and dop853.f), with the step control
## and first step of scipy's DOP853 (HNW §II.4), whose coefficients these are.
const RTOL := 1e-12
const ATOL := 1e-12
const DC := [0.0, 0.05260015195876773, 0.0789002279381516, 0.1183503419072274, 0.2816496580927726, 0.3333333333333333, 0.25, 0.3076923076923077, 0.6512820512820513, 0.6, 0.8571428571428571, 1.0]
const DA := [
	[],
	[0.05260015195876773],
	[0.0197250569845379, 0.0591751709536137],
	[0.02958758547680685, 0.0, 0.08876275643042054],
	[0.2413651341592667, 0.0, -0.8845494793282861, 0.924834003261792],
	[0.037037037037037035, 0.0, 0.0, 0.17082860872947386, 0.12546768756682242],
	[0.037109375, 0.0, 0.0, 0.17025221101954405, 0.06021653898045596, -0.017578125],
	[0.03709200011850479, 0.0, 0.0, 0.17038392571223998, 0.10726203044637328, -0.015319437748624402, 0.008273789163814023],
	[0.6241109587160757, 0.0, 0.0, -3.3608926294469414, -0.868219346841726, 27.59209969944671, 20.154067550477894, -43.48988418106996],
	[0.47766253643826434, 0.0, 0.0, -2.4881146199716677, -0.590290826836843, 21.230051448181193, 15.279233632882423, -33.28821096898486, -0.020331201708508627],
	[-0.9371424300859873, 0.0, 0.0, 5.186372428844064, 1.0914373489967295, -8.149787010746927, -18.52006565999696, 22.739487099350505, 2.4936055526796523, -3.0467644718982196],
	[2.273310147516538, 0.0, 0.0, -10.53449546673725, -2.0008720582248625, -17.9589318631188, 27.94888452941996, -2.8589982771350235, -8.87285693353063, 12.360567175794303, 0.6433927460157636],
]
const DB := [0.054293734116568765, 0.0, 0.0, 0.0, 0.0, 4.450312892752409, 1.8915178993145003, -5.801203960010585, 0.3111643669578199, -0.1521609496625161, 0.20136540080403034, 0.04471061572777259]
const DE3 := [-0.18980075407240762, 0.0, 0.0, 0.0, 0.0, 4.450312892752409, 1.8915178993145003, -5.801203960010585, -0.4226823213237919, -0.1521609496625161, 0.20136540080403034, 0.02265179219836082, 0.0]
const DE5 := [0.01312004499419488, 0.0, 0.0, 0.0, 0.0, -1.2251564463762044, -0.4957589496572502, 1.6643771824549864, -0.35032884874997366, 0.3341791187130175, 0.08192320648511571, -0.022355307863886294, 0.0]
const DCX := [0.1, 0.2, 0.7777777777777778]
const DAX := [
	[0.056167502283047954, 0.0, 0.0, 0.0, 0.0, 0.0, 0.25350021021662483, -0.2462390374708025, -0.12419142326381637, 0.15329179827876568, 0.00820105229563469, 0.007567897660545699, -0.008298],
	[0.03183464816350214, 0.0, 0.0, 0.0, 0.0, 0.028300909672366776, 0.053541988307438566, -0.05492374857139099, 0.0, 0.0, -0.00010834732869724932, 0.0003825710908356584, -0.00034046500868740456, 0.1413124436746325],
	[-0.42889630158379194, 0.0, 0.0, 0.0, 0.0, -4.697621415361164, 7.683421196062599, 4.06898981839711, 0.3567271874552811, 0.0, 0.0, 0.0, -0.0013990241651590145, 2.9475147891527724, -9.15095847217987],
]
const DD := [
	[-8.428938276109013, 0.0, 0.0, 0.0, 0.0, 0.5667149535193777, -3.0689499459498917, 2.38466765651207, 2.117034582445028, -0.871391583777973, 2.2404374302607883, 0.6315787787694688, -0.08899033645133331, 18.148505520854727, -9.194632392478356, -4.436036387594894],
	[10.427508642579134, 0.0, 0.0, 0.0, 0.0, 242.28349177525817, 165.20045171727028, -374.5467547226902, -22.113666853125306, 7.733432668472264, -30.674084731089398, -9.332130526430229, 15.697238121770845, -31.139403219565178, -9.35292435884448, 35.81684148639408],
	[19.985053242002433, 0.0, 0.0, 0.0, 0.0, -387.0373087493518, -189.17813819516758, 527.8081592054236, -11.57390253995963, 6.8812326946963, -1.0006050966910838, 0.7777137798053443, -2.778205752353508, -60.19669523126412, 84.32040550667716, 11.99229113618279],
	[-25.69393346270375, 0.0, 0.0, 0.0, 0.0, -154.18974869023643, -231.5293791760455, 357.6391179106141, 93.40532418362432, -37.45832313645163, 104.0996495089623, 29.8402934266605, -43.53345659001114, 96.32455395918828, -39.17726167561544, -149.72683625798564],
]


## The step size the last integration would take next: a hint for the next
## coast of the same craft (coast_from), so it skips the cautious first guess.
var last_h := 0.0


## Coast for dt seconds (either sign), the first step h0 (the craft's last
## step, from last_h); every step error-controlled as in coast_to, so only the
## work changes. Returns [r, v].
func coast_from(r: PackedFloat64Array, v: PackedFloat64Array, t: float, dt: float, h0: float) -> Array:
	var y := r.duplicate()
	y.append_array(v)
	var d := r.size()
	last_h = 0.0
	var yn: PackedFloat64Array = _flow(y, t, [t + dt], d, h0)[0]
	return [yn.slice(0, d), yn.slice(d, 2 * d)]


## Coast for dt seconds (either sign). Returns [r, v].
func coast(r: PackedFloat64Array, v: PackedFloat64Array, t: float, dt: float, _max_h := 60.0) -> Array:
	return coast_to(r, v, t, [t + dt])[0]


## The coast from (r, v) at t, sampled at each of times (in order, all on one
## side of t), as [r, v] per time. One DOP853 integration to the last time,
## every step error-controlled to RTOL (1e-12: a millimetre at a million
## kilometres), so the step shrinks on its own at a close pass and where a
## planet's pull bends the path past FAR. Samples inside a step come from the
## pair's 7th-order dense output (HNW §II.6; scipy's Dop853DenseOutput).
func coast_to(r: PackedFloat64Array, v: PackedFloat64Array, t: float, times: Array) -> Array:
	var y := r.duplicate()
	y.append_array(v)
	var d := r.size()
	var out := []
	for yi in _flow(y, t, times, d):
		out.append([yi.slice(0, d), yi.slice(d, 2 * d)])
	return out


## The coast for dt seconds with its state-transition matrix: [r, v, Φ], Φ the
## 2d × 2d matrix (rows of PackedFloat64Array) of how the end state [r, v]
## moves with the start state. Φ flies alongside the orbit in the same
## integration, by the variational equations dΦ/dt = [[0, I], [G, 0]] Φ with G
## this force model's gradient (Montenbruck & Gill 2000, §7.2), so the steps
## and the end state are the plain coast's to the last bit: the step control
## watches the orbit alone, which holds Φ to about the same relative accuracy.
func coast_stm(r: PackedFloat64Array, v: PackedFloat64Array, t: float, dt: float) -> Array:
	var d := r.size()
	var n := 2 * d
	var y := r.duplicate()
	y.append_array(v)
	for i in n:
		for j in n:
			y.append(1.0 if i == j else 0.0)
	var yn: PackedFloat64Array = _flow(y, t, [t + dt], d)[0]
	var phi := []
	for i in n:
		phi.append(yn.slice(n + i * n, n + (i + 1) * n))
	return [yn.slice(0, d), yn.slice(d, n), phi]


## One DOP853 integration of y (the state [r, v], d each, then any Φ rows)
## from t, sampled at each of times: y per time.
func _flow(y: PackedFloat64Array, t: float, times: Array, d: int, h0 := 0.0) -> Array:
	var out := []
	var n := y.size()
	var nm := 2 * d # what the step control watches: the orbit
	var t_end: float = times.back()
	var span := absf(t_end - t)
	var sg := signf(t_end - t)
	var next := 0
	while next < times.size() and absf(float(times[next]) - t) <= 1e-9:
		out.append(y)
		next += 1
	if next == times.size():
		return out
	var f := _deriv(t, y, d)
	var h := minf(h0, span) if h0 > 0.0 else _first_step(t, y, f, d, sg, span)
	var rejected := false
	var k := []
	k.resize(16)
	while next < times.size():
		var hs := minf(h, sg * (t_end - t))
		var cut := hs < h # the last step, cut short to land on t_end
		var hh := sg * hs
		k[0] = f
		for s in range(1, 12):
			k[s] = _deriv(t + float(DC[s]) * hh, _stage(y, k, DA[s], s, hh, n), d)
		var yn := y.duplicate()
		var e5 := 0.0
		var e3 := 0.0
		for i in n:
			var b := 0.0
			var a5 := 0.0
			var a3 := 0.0
			for j in 12:
				var kj: float = k[j][i]
				b += float(DB[j]) * kj
				a5 += float(DE5[j]) * kj
				a3 += float(DE3[j]) * kj
			yn[i] += hh * b
			if i < nm:
				var sc := ATOL + maxf(absf(y[i]), absf(yn[i])) * RTOL
				e5 += (a5 / sc) * (a5 / sc)
				e3 += (a3 / sc) * (a3 / sc)
		var err := 0.0 if e5 == 0.0 and e3 == 0.0 else hs * e5 / sqrt((e5 + 0.01 * e3) * nm)
		if err >= 1.0:
			h = hs * maxf(0.2, 0.9 * pow(err, -0.125))
			rejected = true
			continue
		var fac := 10.0 if err == 0.0 else minf(10.0, 0.9 * pow(err, -0.125))
		if rejected:
			fac = minf(1.0, fac)
		var t_new := t_end if hs >= sg * (t_end - t) else t + hh
		var fn := _deriv(t_new, yn, d)
		# Samples inside this step: the interpolant, built once per step.
		var F := []
		while next < times.size() and sg * (float(times[next]) - t_new) < -1e-9:
			if F.is_empty():
				F = _dense(t, y, f, yn, fn, k, hh, n, d)
			var x := (float(times[next]) - t) / hh
			var yi := PackedFloat64Array()
			yi.resize(n)
			for i in n:
				var acc := 0.0
				for m in 7:
					acc += float(F[6 - m][i])
					acc *= x if m % 2 == 0 else 1.0 - x
				yi[i] = acc + y[i]
			out.append(yi)
			next += 1
		while next < times.size() and absf(float(times[next]) - t_new) <= 1e-9:
			out.append(yn)
			next += 1
		t = t_new
		y = yn
		f = fn
		last_h = maxf(hs * fac, h) if cut else hs * fac
		h = hs * fac
		rejected = false
	return out


## y + h Σ a_j k_j over the first s stages.
static func _stage(y: PackedFloat64Array, k: Array, a: Array, s: int, h: float, n: int) -> PackedFloat64Array:
	var ys := y.duplicate()
	for i in n:
		var acc := 0.0
		for j in s:
			acc += float(a[j]) * k[j][i]
		ys[i] += h * acc
	return ys


## The dense-output coefficients of the step (t, y) → (t + h, yn): three more
## stages, then F as scipy's Dop853 _dense_output_impl builds it.
func _dense(t: float, y: PackedFloat64Array, f: PackedFloat64Array, yn: PackedFloat64Array, fn: PackedFloat64Array, k: Array, h: float, n: int, d: int) -> Array:
	k[12] = fn
	for e in 3:
		var s := 13 + e
		k[s] = _deriv(t + float(DCX[e]) * h, _stage(y, k, DAX[e], s, h, n), d)
	var F := []
	var f0 := PackedFloat64Array()
	var f1 := PackedFloat64Array()
	var f2 := PackedFloat64Array()
	f0.resize(n)
	f1.resize(n)
	f2.resize(n)
	for i in n:
		var dy := yn[i] - y[i]
		f0[i] = dy
		f1[i] = h * f[i] - dy
		f2[i] = 2.0 * dy - h * (fn[i] + f[i])
	F.append_array([f0, f1, f2])
	for row in DD:
		var fr := PackedFloat64Array()
		fr.resize(n)
		for i in n:
			var acc := 0.0
			for j in 16:
				acc += float(row[j]) * k[j][i]
			fr[i] = h * acc
		F.append(fr)
	return F


## d/dt of the state [r, v]: [v, accel(r, t)]; with Φ's rows after it, also
## dΦ/dt: Φ's lower rows on top, G times its upper rows below.
func _deriv(t: float, y: PackedFloat64Array, d: int) -> PackedFloat64Array:
	var n := 2 * d
	var out := y.slice(d, n)
	var r := y.slice(0, d)
	out.append_array(accel(r, t))
	if y.size() > n:
		out.append_array(y.slice(n + d * n, n + n * n))
		var G := gradient(r, t)
		for i in d:
			for j in n:
				var acc := 0.0
				for k in d:
					acc += G[i][k] * y[n + k * n + j]
				out.append(acc)
	return out


## The gradient of accel at r: the 3 × 3 matrix ∂a/∂r (1/s², rows of
## PackedFloat64Array), term by term as accel. A point mass gives
## μ/r³ (3 r̂r̂ᵀ − I); a third body the same in d = rb − r (its pull on Jupiter
## does not depend on r); J2, from a_i = c x_i (α_i r⁻⁵ − 5 z² r⁻⁷) with
## c = −(3/2) J2 μ R², α = (1, 1, 3), differentiated by hand and checked in
## tests/run_tests.gd against differences of accel. Three dimensions only.
func gradient(r: PackedFloat64Array, t: float) -> Array:
	var G := _point(r, mu)
	if use_j2 and central != "jupiter":
		# About another body's pole: the general J2 term, its gradient by
		# central differences (1 m) of the term alone (accel's elif branch).
		for j in 3:
			var hp := r.duplicate()
			var hm := r.duplicate()
			hp[j] += 1e-3
			hm[j] -= 1e-3
			var ap := _j2_pole(hp)
			var am := _j2_pole(hm)
			for i in 3:
				G[i][j] += (ap[i] - am[i]) / 2e-3
	elif use_j2:
		var r2 := V.dot(r, r)
		var r5 := 1.0 / (r2 * r2 * sqrt(r2))
		var r7 := r5 / r2
		var r9 := r7 / r2
		var z := r[2]
		var c := -1.5 * J2 * mu * R_REF * R_REF
		for i in 3:
			var al := 3.0 if i == 2 else 1.0
			for j in 3:
				var dij := 1.0 if i == j else 0.0
				var g := al * (dij * r5 - 5.0 * r[i] * r[j] * r7) - 5.0 * (z * z * dij * r7 - 7.0 * z * z * r[i] * r[j] * r9)
				if j == 2:
					g -= 10.0 * z * r[i] * r7
				G[i][j] += c * g
	if use_moons:
		for m in moons:
			_add(G, _point(V.sub(moon_state.call(m.id, t)[0], r), m.gm))
	if use_sun and utc_of.is_valid():
		var ms: float = utc_of.call(t)
		_add(G, _point(V.sub(_sun_at(t, ms), r), Ephem.GM_SUN))
		if central == "jupiter":
			if V.norm(r) > FAR:
				for b in Ephem.PLANETS:
					if b != "jupiter":
						_add(G, _point(V.sub(Ephem.pos(b, ms), r), float(Ephem.BODY[b].gm)))
		else:
			if central == "earth" and use_moons:
				_add(G, _point(V.sub(_moon_at(t, ms), r), Ephem.GM_MOON))
			if V.norm(r) > far:
				var c := Ephem.pos(central, ms)
				for b in Ephem.PLANETS:
					if b != central:
						_add(G, _point(V.sub(V.sub(Ephem.pos(b, ms), c), r), float(Ephem.BODY[b].gm)))
	return G


## gm/d³ (3 d̂d̂ᵀ − I): the gradient of a pull gm toward a body at d from here.
static func _point(dv: PackedFloat64Array, gm: float) -> Array:
	var d2 := V.dot(dv, dv)
	var k := gm / (d2 * sqrt(d2))
	var G := []
	for i in 3:
		var row := PackedFloat64Array([0.0, 0.0, 0.0])
		for j in 3:
			row[j] = k * (3.0 * dv[i] * dv[j] / d2 - (1.0 if i == j else 0.0))
		G.append(row)
	return G


static func _add(A: Array, B: Array) -> void:
	for i in A.size():
		for j in A[i].size():
			A[i][j] += B[i][j]


## The first step: HNW §II.4, as scipy's select_initial_step (order 7).
func _first_step(t: float, y: PackedFloat64Array, f: PackedFloat64Array, d: int, sg: float, span: float) -> float:
	var n := 2 * d # the orbit alone, as the step control
	var d0 := 0.0
	var d1 := 0.0
	for i in n:
		var sc := ATOL + absf(y[i]) * RTOL
		d0 += (y[i] / sc) * (y[i] / sc)
		d1 += (f[i] / sc) * (f[i] / sc)
	d0 = sqrt(d0 / n)
	d1 = sqrt(d1 / n)
	var h0 := 1e-6 if d0 < 1e-5 or d1 < 1e-5 else 0.01 * d0 / d1
	h0 = minf(h0, span)
	var y1 := y.duplicate()
	for i in y.size():
		y1[i] += sg * h0 * f[i]
	var f1 := _deriv(t + sg * h0, y1, d)
	var d2 := 0.0
	for i in n:
		var sc := ATOL + absf(y[i]) * RTOL
		d2 += ((f1[i] - f[i]) / sc) * ((f1[i] - f[i]) / sc)
	d2 = sqrt(d2 / n) / h0
	var h1 := maxf(1e-6, h0 * 1e-3) if d1 <= 1e-15 and d2 <= 1e-15 else pow(0.01 / maxf(d1, d2), 0.125)
	return minf(minf(100.0 * h0, h1), span)

