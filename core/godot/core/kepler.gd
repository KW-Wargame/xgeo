## Two-body motion with universal variables, after Curtis (2020) Algorithms
## 3.3 and 3.4 and Bate, Mueller & White (1971); corroborated by Weber,
## Orbital Mechanics & Astrodynamics (open text), Eqs. 251–255, 267. A port of
## src/engine/kepler.js (tests/run_tests.gd checks it against that engine);
## both solve propagate's equation by safeguarded Newton, as plain Newton can
## run away on long coasts of fast paths (tests/kepler_test.gd).
## Kept as the exact reference the n-body integrator (gravity.gd) is tested on.
class_name Kepler


## Half-angle forms: 1 − cos x = 2 sin²(x/2) keeps full precision as x → 2π,
## where Lambert's long-way (> 180°) transfers need it.
static func stumpff_c(z: float) -> float:
	if z > 1e-6:
		return 2.0 * pow(sin(sqrt(z) / 2.0), 2.0) / z
	if z < -1e-6:
		return 2.0 * pow(sinh(sqrt(-z) / 2.0), 2.0) / -z
	return 0.5 - z / 24.0 + z * z / 720.0


static func stumpff_s(z: float) -> float:
	if z > 1e-6:
		var s := sqrt(z)
		return (s - sin(s)) / (s * s * s)
	if z < -1e-6:
		var s := sqrt(-z)
		return (sinh(s) - s) / (s * s * s)
	return 1.0 / 6.0 - z / 120.0 + z * z / 5040.0


## Orbital period (s), T = 2π √(a³/μ).
static func period(a: float, mu: float) -> float:
	return TAU * sqrt(a * a * a / mu)


## Semi-major axis (km) by vis-viva; negative for a hyperbola.
static func semi_major_axis(r: PackedFloat64Array, v: PackedFloat64Array, mu: float) -> float:
	return 1.0 / (2.0 / V.norm(r) - V.dot(v, v) / mu)


static func energy(r: PackedFloat64Array, v: PackedFloat64Array, mu: float) -> float:
	return V.dot(v, v) / 2.0 - mu / V.norm(r)


## State after dt seconds of coasting from (r0, v0). Returns [r, v].
static func propagate(r0: PackedFloat64Array, v0: PackedFloat64Array, dt: float, mu: float) -> Array:
	if dt == 0.0:
		return [r0.duplicate(), v0.duplicate()]
	var r0n := V.norm(r0)
	var vr0 := V.dot(r0, v0) / r0n
	var alpha := 2.0 / r0n - V.dot(v0, v0) / mu
	var sqmu := sqrt(mu)
	if alpha > 1e-12:
		var T := period(1.0 / alpha, mu)
		dt = fmod(dt, T)
		if dt == 0.0:
			return [r0.duplicate(), v0.duplicate()]
	var chi := sqmu * absf(alpha) * dt
	if not (alpha > 1e-12):
		chi = signf(dt) * sqrt(mu) * absf(dt) / r0n # near-parabolic start
	if alpha < -1e-12:
		# Hyperbola: Vallado (2013) Algorithm 8's start (as in hapsira's vallado.py), or Newton overflows cosh on long coasts.
		var a := 1.0 / alpha
		var q := (-2.0 * mu * alpha * dt) / (V.dot(r0, v0) + signf(dt) * sqrt(-mu * a) * (1.0 - r0n * alpha))
		if q > 0.0:
			chi = signf(dt) * sqrt(-a) * log(q)
	# Kepler's equation in χ, F(χ) = 0. F rises with χ everywhere (dF/dχ = r > 0),
	# so the root is bracketed: from χ = 0 (F = −√μ·Δt) out, doubling, until F
	# changes sign. Newton's step is taken when it stays inside the bracket,
	# else the bracket is halved (safeguarded Newton: Press et al. 2007, §9.4,
	# "rtsafe"). Plain Newton from the start guess can run away on a long
	# coast of a fast open (or near-parabolic) path: thousands of km off, or
	# off to infinity.
	var kf := func(x: float) -> Array:
		var zz := alpha * x * x
		var Cx := stumpff_c(zz)
		var Sx := stumpff_s(zz)
		var Fx := (r0n * vr0 / sqmu) * x * x * Cx + (1.0 - alpha * r0n) * x * x * x * Sx + r0n * x - sqmu * dt
		var dFx := (r0n * vr0 / sqmu) * x * (1.0 - zz * Sx) + (1.0 - alpha * r0n) * x * x * Cx + r0n
		return [Fx, dFx]
	var sg := signf(dt)
	var lo := 0.0 # F(lo)·sg < 0
	var hi := chi if chi * sg > 0.0 and is_finite(chi) else sg * sqmu * absf(dt) / r0n
	for _i in 200:
		var fh: float = kf.call(hi)[0]
		if not (fh * sg < 0.0): # past the root (an overflow, inf or nan, counts as past)
			break
		lo = hi
		hi *= 2.0
	if hi < lo:
		var k := lo
		lo = hi
		hi = k
	if not (chi > lo and chi < hi):
		chi = (lo + hi) / 2.0
	for i in 200:
		var ff: Array = kf.call(chi)
		var F: float = ff[0]
		var dF: float = ff[1]
		if F < 0.0:
			lo = chi
		elif F > 0.0:
			hi = chi
		else:
			break
		var nx := chi - F / dF
		if not (nx > lo and nx < hi): # Newton would leave the bracket: halve it instead
			nx = (lo + hi) / 2.0
		var step := absf(nx - chi)
		chi = nx
		if step < 1e-9 * maxf(1.0, absf(chi)) or hi - lo < 1e-12 * maxf(1.0, absf(chi)):
			break
	var z := alpha * chi * chi
	var C := stumpff_c(z)
	var S := stumpff_s(z)
	var f := 1.0 - (chi * chi / r0n) * C
	var g := dt - (chi * chi * chi / sqmu) * S
	var r := V.add(V.scale(r0, f), V.scale(v0, g))
	var rn := V.norm(r)
	var fdot := (sqmu / (rn * r0n)) * (z * S - 1.0) * chi
	var gdot := 1.0 - (chi * chi / rn) * C
	var v := V.add(V.scale(r0, fdot), V.scale(v0, gdot))
	return [r, v]


## Position and velocity in the plane from mean elements at t seconds after
## their epoch (planar: longitude of periapsis = node + argument). Kepler's
## equation by Newton's method. The mean anomaly advances at √(μ/a³) unless
## the elements carry measured periods: observedPeriodDays (sidereal: the mean
## longitude) and anomalisticPeriodDays (the mean anomaly). JPL lists that P
## as the sidereal period; the game uses it as the mean-anomaly period because,
## with the fact-sheet sidereal periods, that reproduces Horizons. The
## periapsis then precesses at the difference. Kepler's third law alone would
## leave Io 114° and Ganymede 34° from JPL Horizons by 2041, since J2 and the
## Laplace resonance speed the moons up (tools/verify/tests/test_moons.py).
static func from_elements(el: Dictionary, t: float, mu: float) -> Array:
	var a: float = el.a
	var e: float = el.e
	var n := sqrt(mu / (a * a * a))
	var varpi_dot := 0.0
	if el.has("observedPeriodDays"):
		var n_lam := TAU / (float(el.observedPeriodDays) * 86400.0)
		n = TAU / (float(el.anomalisticPeriodDays) * 86400.0) if el.has("anomalisticPeriodDays") else n_lam
		varpi_dot = n_lam - n
	var M := fmod(deg_to_rad(el.M) + n * t, TAU)
	# Danby's (1987) starter E = M + 0.85 e sign(sin M) (as credited by Zechmeister 2018, A&A 619:A128): Newton from E = M can
	# fail to converge for e near 1.
	var E := M + 0.85 * e * signf(sin(M))
	for i in 50:
		var d := (E - e * sin(E) - M) / (1.0 - e * cos(E))
		E -= d
		if absf(d) < 1e-13:
			break
	var cE := cos(E)
	var sE := sin(E)
	var px := a * (cE - e)
	var py := a * sqrt(1.0 - e * e) * sE
	var varpi := fmod(deg_to_rad(float(el.node) + float(el.w)) + varpi_dot * t, TAU)
	var c := cos(varpi)
	var s := sin(varpi)
	var Edot := n / (1.0 - e * cE)
	var vx := -a * sE * Edot
	var vy := a * sqrt(1.0 - e * e) * cE * Edot
	var rx := px * c - py * s
	var ry := px * s + py * c
	# Velocity: the motion on the ellipse plus the turning of the ellipse.
	return [V.of(rx, ry), V.of(vx * c - vy * s - varpi_dot * ry, vx * s + vy * c + varpi_dot * rx)]
