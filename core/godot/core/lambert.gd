## Lambert's problem: the orbit joining r1 to r2 in a given time of flight.
## Izzo's method (Izzo 2015, "Revisiting Lambert's problem", CMDA 121:1–15):
## in his non-dimensional variables, Householder's third-order iteration on the
## time of flight from his initial guesses, with the multi-revolution branches.
## The same method, step for step, as the C++ kernel's (one engine for every
## edition); tested against src/engine/lambert.js, which solves the same problem
## a different way (Curtis 2020, Algorithm 5.2, universal variables by
## bisection).
##
## Lambert is exact for Jupiter alone. Under real gravity (J2 and the moons)
## a transfer drifts off its aim, which is why ships fly correction burns.
class_name Lambert


## The single-revolution transfer: [v1, v2] (km/s, leaving r1 and arriving at
## r2), or [] when there is none (r1 and r2 in line with the centre, so the
## plane is undefined, or a time or mu that is not positive). Prograde means
## the motion is anticlockwise seen from +z, or from pole when one is given:
## the departing orbit's own (r × v), so a transfer off an inclined or
## polar orbit goes the way that orbit goes.
static func solve(r1: PackedFloat64Array, r2: PackedFloat64Array, tof: float, mu: float, prograde := true, pole := PackedFloat64Array()) -> Array:
	var all := solve_all(r1, r2, tof, mu, prograde, 0, pole)
	return [] if all.is_empty() else [all[0].v1, all[0].v2]


## Every transfer: the single revolution first, then for each number of whole
## revolutions up to max_revs that the time allows, Izzo's left branch (the
## longer period) and the right. Each {v1, v2, revs, left}; [] as solve.
static func solve_all(r1: PackedFloat64Array, r2: PackedFloat64Array, tof: float, mu: float, prograde := true, max_revs := 0, pole := PackedFloat64Array()) -> Array:
	if not (tof > 0.0) or not (mu > 0.0):
		return []
	var c := V.norm(V.sub(r2, r1))
	var n1 := V.norm(r1)
	var n2 := V.norm(r2)
	var s := (c + n1 + n2) / 2.0
	var ir1 := V.scale(r1, 1.0 / n1)
	var ir2 := V.scale(r2, 1.0 / n2)
	var ih := V.cross(ir1, ir2)
	var hn := V.norm(ih)
	if not (hn > 1e-12):
		return []
	ih = V.scale(ih, 1.0 / hn)
	var lam := sqrt(maxf(0.0, 1.0 - c / s))
	var it1: PackedFloat64Array
	var it2: PackedFloat64Array
	if (V.dot(ih, pole) if pole.size() == 3 else ih[2]) < 0.0:
		lam = -lam
		it1 = V.cross(ir1, ih)
		it2 = V.cross(ir2, ih)
	else:
		it1 = V.cross(ih, ir1)
		it2 = V.cross(ih, ir2)
	if not prograde:
		lam = -lam
		it1 = V.scale(it1, -1.0)
		it2 = V.scale(it2, -1.0)
	var l2 := lam * lam
	var l3 := l2 * lam
	var t := sqrt(2.0 * mu / (s * s * s)) * tof

	# How many revolutions the time allows: below T0 of the most, the least time of that count decides (Halley's method).
	var nmax := int(floor(t / PI))
	var t00 := acos(lam) + lam * sqrt(1.0 - l2)
	var t1 := 2.0 / 3.0 * (1.0 - l3)
	if nmax > 0 and t < t00 + nmax * PI:
		var x_old := 0.0
		var tmin := t00 + nmax * PI
		for i in 13:
			var d := _derivatives(lam, x_old, tmin)
			var x_new := x_old - d[0] * d[1] / (d[1] * d[1] - d[0] * d[2] / 2.0) if d[0] != 0.0 else x_old
			var done := absf(x_old - x_new) < 1e-13
			tmin = _tof(lam, x_new, nmax)
			x_old = x_new
			if done:
				break
		if tmin > t:
			nmax -= 1
	nmax = mini(maxi(max_revs, 0), nmax)

	# x for each branch, from Izzo's initial guesses (eqs. 30 and 31).
	var xs: Array[float] = []
	var out: Array = []
	var x0: float
	if t >= t00:
		x0 = -(t - t00) / (t - t00 + 4.0)
	elif t <= t1:
		x0 = t1 * (t1 - t) / (2.0 / 5.0 * (1.0 - l2 * l3) * t) + 1.0
	else:
		x0 = pow(t / t00, log(2.0) / log(t1 / t00)) - 1.0
	xs.append(_householder(lam, t, x0, 0, 1e-5, 15))
	out.append({"revs": 0, "left": false})
	for i in range(1, nmax + 1):
		var q := pow((i * PI + PI) / (8.0 * t), 2.0 / 3.0)
		xs.append(_householder(lam, t, (q - 1.0) / (q + 1.0), i, 1e-8, 15))
		out.append({"revs": i, "left": true})
		q = pow(8.0 * t / (i * PI), 2.0 / 3.0)
		xs.append(_householder(lam, t, (q - 1.0) / (q + 1.0), i, 1e-8, 15))
		out.append({"revs": i, "left": false})

	# The velocities from x (Izzo §4).
	var gamma := sqrt(mu * s / 2.0)
	var rho := (n1 - n2) / c
	var sigma := sqrt(1.0 - rho * rho)
	for i in xs.size():
		var x := xs[i]
		var y := sqrt(1.0 - l2 + l2 * x * x)
		var vr1 := gamma * ((lam * y - x) - rho * (lam * y + x)) / n1
		var vr2 := -gamma * ((lam * y - x) + rho * (lam * y + x)) / n2
		var vt := gamma * sigma * (y + lam * x)
		out[i].v1 = V.add(V.scale(ir1, vr1), V.scale(it1, vt / n1))
		out[i].v2 = V.add(V.scale(ir2, vr2), V.scale(it2, vt / n2))
	return out


## The Gauss hypergeometric 2F1(3, 1; 5/2; z), for the time near the parabola (Izzo eq. 20).
static func _hypergeometric(z: float, tol: float) -> float:
	var sj := 1.0
	var cj := 1.0
	var err := 1.0
	var j := 0
	while err > tol and j < 1000:
		var cj1 := cj * (3.0 + j) * (1.0 + j) / (2.5 + j) * z / (j + 1)
		sj += cj1
		err = absf(cj1)
		cj = cj1
		j += 1
	return sj


## Lagrange's form of the time (Izzo eq. 9), used a little away from the parabola.
static func _tof_lagrange(lam: float, x: float, n: int) -> float:
	var a := 1.0 / (1.0 - x * x)
	if a > 0.0:
		var alfa := 2.0 * acos(x)
		var beta := 2.0 * asin(sqrt(lam * lam / a))
		if lam < 0.0:
			beta = -beta
		return a * sqrt(a) * ((alfa - sin(alfa)) - (beta - sin(beta)) + 2.0 * PI * n) / 2.0
	var alfa := 2.0 * _acosh(x)
	var beta := 2.0 * _asinh(sqrt(-lam * lam / a))
	if lam < 0.0:
		beta = -beta
	return -a * sqrt(-a) * ((beta - sinh(beta)) - (alfa - sinh(alfa))) / 2.0


## T(x) for n revolutions: Battin's series at the parabola, Lagrange near it, Izzo's eq. 18 elsewhere.
static func _tof(lam: float, x: float, n: int) -> float:
	var dist := absf(x - 1.0)
	if dist < 0.2 and dist > 0.01:
		return _tof_lagrange(lam, x, n)
	var k := lam * lam
	var e := x * x - 1.0
	var rho := absf(e)
	var z := sqrt(1.0 + k * e)
	if dist < 0.01:
		var eta := z - lam * x
		var s1 := 0.5 * (1.0 - lam - x * eta)
		var q := 4.0 / 3.0 * _hypergeometric(s1, 1e-11)
		return (eta * eta * eta * q + 4.0 * lam * eta) / 2.0 + n * PI / pow(rho, 1.5)
	var y := sqrt(rho)
	var g := x * z - lam * e
	var d: float
	if e < 0.0:
		d = n * PI + acos(g)
	else:
		d = log(y * (z - lam * x) + g)
	return (x - lam * z - d / y) / e


## dT/dx and the next two derivatives at x where the time is t (Izzo eq. 22).
static func _derivatives(lam: float, x: float, t: float) -> Array[float]:
	var l2 := lam * lam
	var l3 := l2 * lam
	var umx2 := 1.0 - x * x
	var y := sqrt(1.0 - l2 * umx2)
	var y2 := y * y
	var y3 := y2 * y
	var d1 := (3.0 * t * x - 2.0 + 2.0 * l3 * x / y) / umx2
	var d2 := (3.0 * t + 5.0 * x * d1 + 2.0 * (1.0 - l2) * l3 / y3) / umx2
	var d3 := (7.0 * x * d2 + 8.0 * d1 - 6.0 * (1.0 - l2) * l2 * l3 * x / y3 / y2) / umx2
	return [d1, d2, d3]


## Householder's third-order iteration on T(x) = t from x0.
static func _householder(lam: float, t: float, x0: float, n: int, eps: float, iter_max: int) -> float:
	var err := 1.0
	var it := 0
	while err > eps and it < iter_max:
		var tx := _tof(lam, x0, n)
		var d := _derivatives(lam, x0, tx)
		var delta := tx - t
		var d1s := d[0] * d[0]
		var x1 := x0 - delta * (d1s - delta * d[1] / 2.0) / (d[0] * (d1s - delta * d[1]) + d[2] * delta * delta / 6.0)
		err = absf(x0 - x1)
		x0 = x1
		it += 1
	return x0


static func _acosh(x: float) -> float:
	return log(x + sqrt(x * x - 1.0))


static func _asinh(x: float) -> float:
	return signf(x) * log(absf(x) + sqrt(x * x + 1.0))
