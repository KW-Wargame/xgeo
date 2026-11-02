## Tracking: what Blue believes about a target, never the truth itself.
## A port of src/engine/tracking.js. State x = [x, y, vx, vy] (km, km/s) in
## a planar world (Jupiter's campaign), or [x, y, z, vx, vy, vz] in a 3-D one
## (a world about the Earth, inclined orbits); d = 2 or 3 position components,
## the covariance P is 2d × 2d. The planar code is kept as it was, to the last
## bit; the 3-D measurements are directions (two angles about the line of
## sight) and ranges.
## - The covariance moves with a state-transition matrix (Bar-Shalom, Li &
##   Kirubarajan 2001, ch. 6; Labbe, Kalman and Bayesian Filters in Python,
##   ch. 7).
## - Measurements (bearings, ranges) fold in by an unscented update (Julier &
##   Uhlmann 2004): sample points spread by the covariance are pushed through
##   the true, curved measurement function.
## - The estimate coasts on the full force model (Jupiter with J2, the four
##   moons and the Sun), as real orbit determination does: the mean, and the
##   covariance by the transition matrix flown with it (Gravity.coast_stm, the
##   variational equations; Montenbruck & Gill 2000, §7.2), as the C++
##   kernel's tracker does. Quick on-screen forecasts (fast) and a bearing's
##   few minutes of age use the two-body solution and its finite-difference
##   matrix. Process noise covers what the model leaves out: small unseen pushes.
## - New tracks start from crossing bearings: a least-squares fix from two or
##   more lines taken at nearly the same time.
class_name Track
extends RefCounted

const MU := 126.687e6
static var gravity: Gravity # the world's force model, set by Sim
var id: String # the truth it follows (sim uses it only to name the track)
var label: String
var x: PackedFloat64Array
var P: Array # 2d × 2d (4×4 or 6×6), rows of PackedFloat64Array
var t: float
## Past this 1σ / range, a bearing is too curved for the unscented update (design value).
const CURVED := 0.1
## Bearings alone don't tell how far: between two craft in nearly the same
## orbit (linearised relative motion), angles-only range can't be observed unless the observer manoeuvres
## (Woffinden & Geller 2009, IEEE Trans. AES 45(3)). So close in, without a
## recent range, the estimate keeps at least this 1σ along the line of sight,
## as a share of the range (design value, from the shadowing's own runs: the
## range error held near 0.37 of the range). A radar range lifts it.
const RANGE_FLOOR := 0.5
const RANGED_FOR := 1800.0 # s a range measurement counts as recent
## Manoeuvre detection by the innovation (Bar-Shalom, Li & Kirubarajan 2001,
## ch. 11; Labbe, ch. 14): a bearing whose normalised innovation squared passes the χ²(1)
## 99.9% point (10.83) is taken as a burn nobody saw; the track widens as for
## a burn of up to MANEUVER_DV (km/s) in the last look (design values).
const MANEUVER_GATE := 10.83
## The same for a direction (two angles): the χ²(2) 99.9% point.
const MANEUVER_GATE_2 := 13.82
const MANEUVER_DV := 0.05
const MANEUVER_SINCE := 600.0
var unseen_burns := 0
## 3-D tracks (a world about the Earth): a burn is sized, not just allowed for.
## - An unseen burn (a sighting outside the gate) widens the velocity by the
##   smallest of BURN_SIZES that brings the sighting back inside it, as a jump
##   any time since the last sighting; only a sighting no size explains gets
##   the largest.
## - A seen burn (its plume) is a jump at the moment it was seen: the track
##   widens by BURN_GUESS (no more than the engine could give), and the next
##   sightings widen it further only if they need to. The position fixes
##   after it then size the burn, from how far the track has moved off where
##   it would be without it (input estimation; Bar-Shalom, Li & Kirubarajan
##   2001, §11.6). burn holds it.
## Sizes and guess are design values: an inspector's hops in low orbit are
## 0.1 to a few m/s, a transfer tens.
const BURN_SIZES := [0.001, 0.005, 0.02, 0.05]
const BURN_GUESS := 0.005
## The burn last seen: {n, at, x0 and t0 (the estimate then, without it),
## sized, dv (km/s), sigma (km/s, 1σ of each component)}; {} if none.
var burn := {}
var ranged_at := -INF
## What the ranges measured since the last burn tell: the sum of their 1/σ²
## (1/km²). Angles alone cannot tell the range of a craft in nearly the same
## orbit (Woffinden & Geller 2009), so after a burn (seen, or shown by a
## sighting) only ranges can; yet the filter, its velocity now off, goes on
## claiming the range it had. So from the first burn on, the estimate claims
## no better along the line of sight than those ranges together
## (range_floor): a telescope ranging a hull by its size at 30 km (σ ~1.5 km
## a look) leaves a track of 1.5 km, then 1.1, 0.9..., not the 0.1 km the
## filter made of it while the truth sat 2 km off; one radar fix (14 m)
## settles it.
var range_info := 0.0
var burned := false # a burn has been seen or shown since the track began
var accel_noise := 6e-7 # km/s²: small unseen pushes and what the model leaves out (tuned on the retired NIGHT HERON campaign test, when the covariance still moved two-body)
## A 3-D track's accel_noise² weighted by direction in its orbit's own axes:
## (radial, along the track, across it). ONE, the default, is the same on
## every axis. A passive satellite's force-model error is not the same in
## each (on real laser ranges to LAGEOS-1 a track with one value was cautious
## along the track and too sure across it); the game's noise stands for
## unseen small pushes, so its scenarios keep ONE.
var noise_axes := Vector3.ONE
var ident := "unknown" # unknown → classified → identified
var seen_id := false # named by a telescope (the hull seen): ident "identified"
var heard_id := false # its signal matched in the threat library: its uplink is known
var class_id := ""
var side := "unknown"
var last_seen := 0.0
var lkp := PackedFloat64Array() # last known position: the estimate when it was last detected (km)
var lkp_t := -1.0
var in_contact := false
var how := ""
var lobs: Array = [] # recent detections, for drawing: {t, from, bearing, kind (ir, vis, df, radar), by (sensor id), range (km, radar only), sigma (rad, df)}
var intercepts := 0 # strong recordings of its command link (for cyber)


func _init(id_: String, label_: String, x_: PackedFloat64Array, P_: Array, t_: float) -> void:
	id = id_
	label = label_
	x = x_
	P = P_
	t = t_
	lkp = pos()
	lkp_t = t_


## The world's gravitational parameter (km³/s²): its force model's, else
## Jupiter's (the same number in Jupiter's campaign).
static func mu() -> float:
	return gravity.mu if gravity != null else MU


## Position components in this track's state: 2 (planar) or 3.
func dims() -> int:
	return x.size() / 2


static func coast(s: PackedFloat64Array, dt: float) -> PackedFloat64Array:
	if s.size() == 6:
		var s3 := Kepler.propagate(V.of(s[0], s[1], s[2]), V.of(s[3], s[4], s[5]), dt, mu())
		return PackedFloat64Array([s3[0][0], s3[0][1], s3[0][2], s3[1][0], s3[1][1], s3[1][2]])
	var st := Kepler.propagate(V.of(s[0], s[1]), V.of(s[2], s[3]), dt, mu())
	return PackedFloat64Array([st[0][0], st[0][1], st[1][0], st[1][1]])


static func stm(s: PackedFloat64Array, dt: float) -> Array:
	var n := s.size()
	var d := n / 2
	var cols := []
	for j in n:
		var step := 1.0 if j < d else 1e-4
		var up := s.duplicate()
		var dn := s.duplicate()
		up[j] += step
		dn[j] -= step
		var a := coast(up, dt)
		var b := coast(dn, dt)
		var c := PackedFloat64Array()
		for i in n:
			c.append((a[i] - b[i]) / (2.0 * step))
		cols.append(c)
	var F := []
	for i in n:
		var row := PackedFloat64Array()
		for j in n:
			row.append(cols[j][i])
		F.append(row)
	return F


static func mul(A: Array, B: Array) -> Array:
	var out := []
	for i in A.size():
		var row := PackedFloat64Array()
		for j in B[0].size():
			var s := 0.0
			for k in B.size():
				s += A[i][k] * B[k][j]
			row.append(s)
		out.append(row)
	return out


static func transpose(A: Array) -> Array:
	var out := []
	for j in A[0].size():
		var row := PackedFloat64Array()
		for i in A.size():
			row.append(A[i][j])
		out.append(row)
	return out


static func diag(v: Array) -> Array:
	var out := []
	for i in v.size():
		var row := PackedFloat64Array()
		row.resize(v.size())
		row.fill(0.0)
		row[i] = v[i]
		out.append(row)
	return out


const PLANE := [0, 1, 3, 4] # x, y, vx, vy in a 3-D [r, v]


## Move the estimate forward to time to.
## fast: coast the mean and its covariance on Jupiter alone, for quick
## on-screen estimates (the filter itself always uses the full force model).
func predict(to: float, fast := false) -> void:
	var dt := to - t
	if dt <= 0.0:
		return
	var F: Array
	var d := dims()
	var FP: Array
	if d == 3 and not flyable(x):
		fast = true # an estimate diving into the body: two-body motion, which any orbit has
	if gravity != null and not fast and d == 3 and ellipse().major > UT_WIDE * V.norm(pos()):
		FP = _predict_unscented(dt) # [] if its points could not all be flown
	if not FP.is_empty():
		pass
	elif gravity != null and not fast and d == 3:
		# 3-D: the mean and the whole 6 × 6 transition matrix in one integration.
		var s3 := gravity.coast_stm(V.of(x[0], x[1], x[2]), V.of(x[3], x[4], x[5]), t, dt)
		x = PackedFloat64Array([s3[0][0], s3[0][1], s3[0][2], s3[1][0], s3[1][1], s3[1][2]])
		F = s3[2]
	elif gravity != null and not fast:
		# The mean and its transition matrix in one integration under the full
		# force model; the plane's block of the 6 × 6 (x, y, vx, vy).
		var st := gravity.coast_stm(V.of(x[0], x[1]), V.of(x[2], x[3]), t, dt)
		x = PackedFloat64Array([st[0][0], st[0][1], st[1][0], st[1][1]])
		F = []
		for i in PLANE:
			var row := PackedFloat64Array()
			for j in PLANE:
				row.append(st[2][i][j])
			F.append(row)
	else:
		F = stm(x, dt)
		x = coast(x, dt)
	var q := accel_noise * accel_noise
	var d3 := dt * dt * dt / 3.0 * q
	var d2 := dt * dt / 2.0 * q
	var d1 := dt * q
	# White-noise acceleration on each axis (Bar-Shalom et al. 2001, §6.2.2);
	# with noise_axes, in the orbit's axes at the end of the step.
	if FP.is_empty():
		FP = mul(mul(F, P), transpose(F))
	var g := _axes_weight() if d == 3 and noise_axes != Vector3.ONE else []
	for a in d:
		for b in d:
			var w: float = (1.0 if a == b else 0.0) if g.is_empty() else g[a][b]
			if w == 0.0:
				continue
			FP[a][b] += d3 * w
			FP[a][b + d] += d2 * w
			FP[a + d][b] += d2 * w
			FP[a + d][b + d] += d1 * w
	P = FP
	t = to


## Aᵀ diag(noise_axes) A, A's rows the radial, along-track and cross-track
## unit vectors of the estimate's orbit.
func _axes_weight() -> Array:
	var r := V.of(x[0], x[1], x[2])
	var h := V.cross(r, V.of(x[3], x[4], x[5]))
	var c := V.scale(h, 1.0 / V.norm(h))
	var rh := V.scale(r, 1.0 / V.norm(r))
	var ax := [rh, V.cross(c, rh), c]
	var w := [noise_axes.x, noise_axes.y, noise_axes.z]
	var g := []
	for i in 3:
		var row := PackedFloat64Array([0.0, 0.0, 0.0])
		for j in 3:
			for k in 3:
				row[j] += w[k] * ax[k][i] * ax[k][j]
		g.append(row)
	return g


## Past this 1σ, as a share of the distance from the centre, a 3-D track is
## too wide for its transition matrix: tens of km along a low orbit bend with
## it (the "banana"), and the straight-line covariance misses the radial and
## velocity spread the bend adds, so a later radar fix would set the velocity
## wrong. Then the covariance is carried by sample points, each flown on the
## full force model (the unscented transform; Julier & Uhlmann 2004), which
## see the bend. Design value: 0.001, ~7 km in low Earth orbit.
const UT_WIDE := 1e-3


## Can a 3-D state be flown on the full force model? Not if its orbit's
## periapsis lies inside 0.9 of the central body's radius (an estimate thrown
## there by a wide track's update, or one of its sample points).
static func flyable(p: PackedFloat64Array) -> bool:
	if gravity == null:
		return true
	var r := V.of(p[0], p[1], p[2])
	var v := V.of(p[3], p[4], p[5])
	var rn := V.norm(r)
	var h2 := V.dot(V.cross(r, v), V.cross(r, v))
	var m := gravity.mu
	var E := V.dot(v, v) / 2.0 - m / rn
	var e := sqrt(maxf(0.0, 1.0 + 2.0 * E * h2 / (m * m)))
	return h2 / m / (1.0 + e) >= 0.9 * gravity.r_ref


## The unscented prediction over dt: 2n sample points spread by √(n P), each
## coasted; the mean and covariance (before process noise) of where they land.
func _predict_unscented(dt: float) -> Array:
	var n := x.size()
	var Pn := []
	for row in P:
		var r := PackedFloat64Array()
		for v in row:
			r.append(v * n)
		Pn.append(r)
	var L := cholesky(Pn)
	var pts := []
	for j in n:
		for sgn in [1.0, -1.0]:
			var p := x.duplicate()
			for i in n:
				p[i] += sgn * L[i][j]
			# A point whose orbit dives into the central body cannot be flown
			# (the integrator's steps would shrink without end): then the
			# transition matrix carries the covariance after all.
			if not flyable(p):
				return []
			pts.append(p)
	var ys := []
	for p in pts:
		var st := gravity.coast(V.of(p[0], p[1], p[2]), V.of(p[3], p[4], p[5]), t, dt)
		ys.append(PackedFloat64Array([st[0][0], st[0][1], st[0][2], st[1][0], st[1][1], st[1][2]]))
	var w := 1.0 / (2.0 * n)
	var m := PackedFloat64Array()
	m.resize(n)
	m.fill(0.0)
	for y in ys:
		for i in n:
			m[i] += w * y[i]
	var out := []
	for i in n:
		var row := PackedFloat64Array()
		row.resize(n)
		row.fill(0.0)
		out.append(row)
	for y in ys:
		for i in n:
			for j in n:
				out[i][j] += w * (y[i] - m[i]) * (y[j] - m[j])
	x = m
	return out


static func wrap_angle(a: float) -> float:
	return atan2(sin(a), cos(a))


static func cholesky(A: Array) -> Array:
	var n := A.size()
	var L := []
	for i in n:
		var z := PackedFloat64Array()
		z.resize(n)
		z.fill(0.0)
		L.append(z)
	for i in n:
		for j in i + 1:
			var s: float = A[i][j]
			for k in j:
				s -= L[i][k] * L[j][k]
			L[i][j] = sqrt(maxf(s, 1e-18)) if i == j else s / L[j][j]
	return L


## One scalar unscented update. h maps a state to the predicted measurement.
func _update(z: float, h: Callable, R: float, angle: bool) -> void:
	var n := x.size()
	var Pn := []
	for row in P:
		var r := PackedFloat64Array()
		for v in row:
			r.append(v * n)
		Pn.append(r)
	var L := cholesky(Pn)
	var pts := []
	for j in n:
		var a := x.duplicate()
		var b := x.duplicate()
		for i in n:
			a[i] += L[i][j]
			b[i] -= L[i][j]
		pts.append(a)
		pts.append(b)
	var w := 1.0 / (2.0 * n)
	var ys := []
	for p in pts:
		ys.append(h.call(p))
	var mean := 0.0
	if angle:
		var sx := 0.0
		var cx := 0.0
		for y in ys:
			sx += sin(y)
			cx += cos(y)
		mean = atan2(sx, cx)
	else:
		for y in ys:
			mean += y * w
	var d := []
	for y in ys:
		d.append(wrap_angle(y - mean) if angle else y - mean)
	var Pyy := R
	for v in d:
		Pyy += w * v * v
	var K := PackedFloat64Array()
	for i in n:
		var s := 0.0
		for k in pts.size():
			s += w * (pts[k][i] - x[i]) * d[k]
		K.append(s / Pyy)
	var innov := wrap_angle(z - mean) if angle else z - mean
	for i in n:
		x[i] += K[i] * innov
	for i in n:
		for j in n:
			P[i][j] -= K[i] * Pyy * K[j]
	for i in n:
		for j in i:
			var m: float = (P[i][j] + P[j][i]) / 2.0
			P[i][j] = m
			P[j][i] = m


## A bearing (rad from +x, in the plane) measured from s at time tm.
## Unsure compared with how far it is from the sensor (a ship alongside, a
## few km off, after a burn has widened the track to tens of km), one bearing
## is too curved for the unscented update: its sample points sit all round the
## sensor. Then it goes in as what it says in a straight line: the target is
## on the measured line of bearing, its distance across that line 0 ± σ·range,
## a measurement linear in position (the pseudo-linear estimator: Lindgren &
## Gong 1978, IEEE Trans. AES 14(4); Aidala & Nardone 1982, IEEE Trans. AES
## 18(4):432–441).
func update_bearing(s: PackedFloat64Array, bearing: float, sigma: float, tm := NAN) -> void:
	if dims() == 3:
		update_dir(s, V.of(cos(bearing), sin(bearing), 0.0), sigma, tm)
		return
	var dt := 0.0 if is_nan(tm) else tm - t
	# Where the estimate puts it when the bearing was taken (a recording's
	# bearing can be minutes old), and how that moves with the state now.
	var xm := x if absf(dt) < 1.0 else coast(x, dt)
	# A bearing far outside what the estimate expects means the target moved in
	# a way it didn't model: an unseen burn. Widen the track for one first.
	if nis_bearing(xm, s, bearing, sigma) > MANEUVER_GATE:
		maneuver_seen(MANEUVER_SINCE, MANEUVER_DV)
		unseen_burns += 1
		xm = x if absf(dt) < 1.0 else coast(x, dt)
	var rng := sqrt((xm[0] - s[0]) * (xm[0] - s[0]) + (xm[1] - s[1]) * (xm[1] - s[1]))
	if ellipse().major > CURVED * rng:
		var n0 := -sin(bearing)
		var n1 := cos(bearing)
		var H := PackedFloat64Array([n0, n1, 0.0, 0.0])
		if absf(dt) >= 1.0:
			var F := stm(x, dt)
			for j in 4:
				H[j] = n0 * F[0][j] + n1 * F[1][j]
		var cross := n0 * (xm[0] - s[0]) + n1 * (xm[1] - s[1])
		# Without a range, a bearing says nothing about distance along it; the
		# pseudo-linear gain still pulls the estimate toward the observer (its
		# known short-range bias), so keep its position step across the line.
		var unranged := t - ranged_at > RANGED_FOR
		_update_linear(H, -cross, sigma * sigma * rng * rng, V.of(n0, n1) if unranged else PackedFloat64Array())
		if unranged:
			_floor_along(s, RANGE_FLOOR * rng)
		return
	if absf(dt) < 1.0:
		_update(bearing, func(p): return atan2(p[1] - s[1], p[0] - s[0]), sigma * sigma, true)
	else:
		var h := func(p):
			var q := coast(p, dt)
			return atan2(q[1] - s[1], q[0] - s[0])
		_update(bearing, h, sigma * sigma, true)


## One scalar Kalman update for a measurement linear in the state: H·x,
## with innovation `innov` and variance R (Joseph form, so P stays symmetric
## and positive, and right for any gain). Given a unit vector `across`, the
## position step is held to it.
func _update_linear(H: PackedFloat64Array, innov: float, R: float, across := PackedFloat64Array()) -> void:
	var n := x.size()
	var PH := PackedFloat64Array()
	PH.resize(n)
	PH.fill(0.0)
	for i in n:
		for j in n:
			PH[i] += P[i][j] * H[j]
	var S := R
	for i in n:
		S += H[i] * PH[i]
	var K := PackedFloat64Array()
	K.resize(n)
	K.fill(0.0)
	for i in n:
		K[i] = PH[i] / S
	if not across.is_empty():
		if n == 4:
			var k := K[0] * across[0] + K[1] * across[1]
			K[0] = k * across[0]
			K[1] = k * across[1]
		else:
			var k3 := K[0] * across[0] + K[1] * across[1] + K[2] * across[2]
			for i in 3:
				K[i] = k3 * across[i]
	for i in n:
		x[i] += K[i] * innov
	# P = (I − K H) P (I − K H)ᵀ + K R Kᵀ
	var A := []
	for i in n:
		var row := PackedFloat64Array()
		row.resize(n)
		for j in n:
			row[j] = (1.0 if i == j else 0.0) - K[i] * H[j]
		A.append(row)
	P = mul(mul(A, P), transpose(A))
	for i in n:
		for j in n:
			P[i][j] += K[i] * R * K[j]


## Keep at least sd (km, 1σ) of position uncertainty along the line from s
## to the estimate, adding only what is missing in that direction.
func _floor_along(s: PackedFloat64Array, sd: float) -> void:
	if dims() == 3:
		_floor_along3(s, sd)
		return
	var u := V.of(x[0] - s[0], x[1] - s[1])
	var un := V.norm(u)
	if un < 1e-9:
		return
	u = V.scale(u, 1.0 / un)
	var have: float = u[0] * u[0] * P[0][0] + 2.0 * u[0] * u[1] * P[0][1] + u[1] * u[1] * P[1][1]
	var add := sd * sd - have
	if add <= 0.0:
		return
	P[0][0] += add * u[0] * u[0]
	P[0][1] += add * u[0] * u[1]
	P[1][0] += add * u[0] * u[1]
	P[1][1] += add * u[1] * u[1]


func _floor_along3(s: PackedFloat64Array, sd: float) -> void:
	var u := V.sub(pos(), s)
	var un := V.norm(u)
	if un < 1e-9:
		return
	u = V.scale(u, 1.0 / un)
	var have := 0.0
	for i in 3:
		for j in 3:
			have += u[i] * P[i][j] * u[j]
	var add := sd * sd - have
	if add <= 0.0:
		return
	for i in 3:
		for j in 3:
			P[i][j] += add * u[i] * u[j]


## Two unit vectors across the direction u (a right-handed set u, e1, e2),
## built about the axis u leans on least.
static func across_of(u: PackedFloat64Array) -> Array:
	var a := V.of(1.0, 0.0, 0.0)
	if absf(u[1]) <= absf(u[0]) and absf(u[1]) <= absf(u[2]):
		a = V.of(0.0, 1.0, 0.0)
	elif absf(u[2]) <= absf(u[0]) and absf(u[2]) <= absf(u[1]):
		a = V.of(0.0, 0.0, 1.0)
	var e1 := V.cross(u, a)
	e1 = V.scale(e1, 1.0 / V.norm(e1))
	return [e1, V.cross(u, e1)]


## A direction (unit vector u, the line of sight) measured from s at time tm,
## 1σ sigma (rad) in each of the two angles across it: the 3-D bearing. It goes
## in as two angles about the measured line, each 0 ± sigma: atan2 of the
## estimate's offset across the line (along e1, then e2) over its distance
## along it, two scalar unscented updates. As for a bearing, when the estimate
## is too unsure for that (curved), each angle goes in pseudo-linearly as a
## distance across the line, 0 ± sigma·range; and without a recent range the
## floor along the line holds.
func update_dir(s: PackedFloat64Array, u: PackedFloat64Array, sigma: float, tm := NAN) -> void:
	var dt := 0.0 if is_nan(tm) else tm - t
	var xm := x if absf(dt) < 1.0 else coast(x, dt)
	if nis_dir(xm, s, u, sigma) > MANEUVER_GATE_2:
		_size_unseen(func(): return nis_dir(xm, s, u, sigma), MANEUVER_GATE_2)
		unseen_burns += 1
		xm = x if absf(dt) < 1.0 else coast(x, dt)
	var ee := across_of(u)
	var rng := V.dist(V.of(xm[0], xm[1], xm[2]), s)
	if ellipse().major > CURVED * rng:
		var unranged := t - ranged_at > RANGED_FOR
		var F := stm(x, dt) if absf(dt) >= 1.0 else []
		for e in ee:
			var H := PackedFloat64Array([e[0], e[1], e[2], 0.0, 0.0, 0.0])
			if absf(dt) >= 1.0:
				for j in 6:
					H[j] = e[0] * F[0][j] + e[1] * F[1][j] + e[2] * F[2][j]
			var xn := x if absf(dt) < 1.0 else coast(x, dt)
			var cross := V.dot(e, V.of(xn[0] - s[0], xn[1] - s[1], xn[2] - s[2]))
			_update_linear(H, -cross, sigma * sigma * rng * rng, e if unranged else PackedFloat64Array())
		if unranged:
			_floor_along(s, RANGE_FLOOR * rng)
		else:
			_floor_along(s, range_floor())
		return
	for e in ee:
		var h := func(p):
			var q: PackedFloat64Array = p if absf(dt) < 1.0 else coast(p, dt)
			var dd := V.of(q[0] - s[0], q[1] - s[1], q[2] - s[2])
			return atan2(V.dot(dd, e), V.dot(dd, u))
		_update(0.0, h, sigma * sigma, true)
	_floor_along(s, range_floor())


## The least 1σ (km) along the line of sight: what the ranges since the last
## burn tell together (range_info); 0 before any burn, or with no range since.
func range_floor() -> float:
	return 1.0 / sqrt(range_info) if burned and range_info > 0.0 else 0.0


## A burn (seen or shown): the ranges before it no longer tell where it is.
func _burned() -> void:
	burned = true
	range_info = 0.0


## The normalised innovation squared of a direction u taken from s (two
## angles across it), against the estimate's state xm, linearised.
func nis_dir(xm: PackedFloat64Array, s: PackedFloat64Array, u: PackedFloat64Array, sigma: float) -> float:
	var dd := V.of(xm[0] - s[0], xm[1] - s[1], xm[2] - s[2])
	if V.dot(dd, dd) < 1e-12:
		return 0.0
	var ee := across_of(u)
	var b := V.dot(dd, u)
	var Hs := []
	var nu := []
	for e in ee:
		var a := V.dot(dd, e)
		var q := a * a + b * b
		# d atan2(a, b)/dr = (b e - a u)/(a² + b²)
		Hs.append(V.scale(V.sub(V.scale(e, b), V.scale(u, a)), 1.0 / q))
		nu.append(-atan2(a, b))
	var S := [[sigma * sigma, 0.0], [0.0, sigma * sigma]]
	for k in 2:
		for l in 2:
			for i in 3:
				for j in 3:
					S[k][l] += Hs[k][i] * P[i][j] * Hs[l][j]
	var det: float = S[0][0] * S[1][1] - S[0][1] * S[1][0]
	if absf(det) < 1e-300:
		return 0.0
	return (nu[0] * nu[0] * S[1][1] - 2.0 * nu[0] * nu[1] * S[0][1] + nu[1] * nu[1] * S[0][0]) / det


## The normalised innovation squared of a bearing taken from s, against the
## estimate's state xm (linearised: the bearing moves by n/r per km across it).
func nis_bearing(xm: PackedFloat64Array, s: PackedFloat64Array, z: float, sigma: float) -> float:
	var dx: float = xm[0] - s[0]
	var dy: float = xm[1] - s[1]
	var r2 := dx * dx + dy * dy
	if r2 < 1e-12:
		return 0.0
	var h0 := -dy / r2
	var h1 := dx / r2
	var S: float = h0 * h0 * P[0][0] + 2.0 * h0 * h1 * P[0][1] + h1 * h1 * P[1][1] + sigma * sigma
	var nu := wrap_angle(z - atan2(dy, dx))
	return nu * nu / S


## 1σ position uncertainty across the line of sight from s (km): what decides
## whether a beam aimed from s lands on it (how far along it hardly matters).
func cross_sigma(s: PackedFloat64Array) -> float:
	if dims() == 3:
		# The wider of the two directions across the line of sight.
		var w := V.sub(pos(), s)
		var wn := V.norm(w)
		if wn < 1e-9:
			return ellipse().major
		var ee := across_of(V.scale(w, 1.0 / wn))
		var m := [[0.0, 0.0], [0.0, 0.0]]
		for k in 2:
			for l in 2:
				for i in 3:
					for j in 3:
						m[k][l] += ee[k][i] * P[i][j] * ee[l][j]
		var mid: float = (m[0][0] + m[1][1]) / 2.0
		var diff := sqrt(pow((m[0][0] - m[1][1]) / 2.0, 2.0) + m[0][1] * m[0][1])
		return sqrt(maxf(0.0, mid + diff))
	var u := V.of(x[0] - s[0], x[1] - s[1])
	var un := V.norm(u)
	if un < 1e-9:
		return ellipse().major
	var n := V.of(-u[1] / un, u[0] / un)
	return sqrt(maxf(0.0, n[0] * n[0] * P[0][0] + 2.0 * n[0] * n[1] * P[0][1] + n[1] * n[1] * P[1][1]))


func update_range(s: PackedFloat64Array, rng: float, sigma: float) -> void:
	ranged_at = t
	range_info += 1.0 / (sigma * sigma)
	if dims() == 3:
		_update(rng, func(p): return sqrt((p[0] - s[0]) * (p[0] - s[0]) + (p[1] - s[1]) * (p[1] - s[1]) + (p[2] - s[2]) * (p[2] - s[2])), sigma * sigma, false)
		return
	# 64-bit: a 32-bit Vector2 rounds a 10⁶ km range to ~0.06 km, the size of a radar range sigma.
	_update(rng, func(p): return sqrt((p[0] - s[0]) * (p[0] - s[0]) + (p[1] - s[1]) * (p[1] - s[1])), sigma * sigma, false)


## Widen the estimate after a burn is seen (a white-noise velocity jump).
func maneuver_seen(since: float, vel_sigma := 3.0) -> void:
	var v := vel_sigma * vel_sigma
	var pairs := [[0, 2], [1, 3]] if dims() == 2 else [[0, 3], [1, 4], [2, 5]]
	for pq in pairs:
		var p: int = pq[0]
		var q: int = pq[1]
		P[p][p] += v * since * since
		P[p][q] += v * since
		P[q][p] += v * since
		P[q][q] += v


## A radar's range and two angles from s (3-D tracks): the measured range
## rng along the measured direction u is a position z = s + rng·u, with
## covariance σr² u uᵀ + (σa·rng)² (I − u uᵀ). That position is linear in the
## state, so it goes in by a plain Kalman update however wide the track (the
## converted-measurement filter: Lerro & Bar-Shalom 1993, IEEE Trans. AES
## 29(4):1015; Bar-Shalom, Li & Kirubarajan 2001, §10.4.3), where range and
## angles taken one by one through their curved functions would mislead a
## track hundreds of km wide. A fix far outside what the track expects
## (χ²(3) 99.9%) is first taken as an unseen burn, as for a bearing.
const MANEUVER_GATE_3 := 16.27


func update_fix(s: PackedFloat64Array, rng: float, u: PackedFloat64Array, sigma_r: float, sigma_a: float) -> void:
	ranged_at = t
	range_info += 1.0 / (sigma_r * sigma_r)
	var z := V.add(s, V.scale(u, rng))
	var ca := (sigma_a * rng) ** 2
	var R := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
	for i in 3:
		for j in 3:
			R[i][j] = (sigma_r * sigma_r - ca) * u[i] * u[j] + (ca if i == j else 0.0)
	for attempt in 2:
		var S := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
		for i in 3:
			for j in 3:
				S[i][j] = P[i][j] + R[i][j]
		var Si := inv3(S)
		if Si.is_empty():
			return
		var nu := V.of(z[0] - x[0], z[1] - x[1], z[2] - x[2])
		var nis := 0.0
		for i in 3:
			for j in 3:
				nis += nu[i] * Si[i][j] * nu[j]
		if attempt == 0 and nis > MANEUVER_GATE_3:
			_size_unseen(func(): return _nis_fix(z, R), MANEUVER_GATE_3)
			unseen_burns += 1
			continue
		# K = P Hᵀ S⁻¹ (H picks the position), then the Joseph form.
		var K := []
		for i in 6:
			var row := PackedFloat64Array([0.0, 0.0, 0.0])
			for j in 3:
				for k in 3:
					row[j] += P[i][k] * Si[k][j]
			K.append(row)
		for i in 6:
			x[i] += K[i][0] * nu[0] + K[i][1] * nu[1] + K[i][2] * nu[2]
		var A := []
		for i in 6:
			var row := PackedFloat64Array()
			row.resize(6)
			for j in 6:
				row[j] = (1.0 if i == j else 0.0) - (K[i][j] if j < 3 else 0.0)
			A.append(row)
		P = mul(mul(A, P), transpose(A))
		for i in 6:
			for j in 6:
				for a in 3:
					for b in 3:
						P[i][j] += K[i][a] * R[a][b] * K[j][b]
		_floor_along3(s, range_floor())
		_size_burn()
		return


## The normalised innovation squared of a position z (covariance R) against the estimate.
func _nis_fix(z: PackedFloat64Array, R: Array) -> float:
	var S := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
	for i in 3:
		for j in 3:
			S[i][j] = P[i][j] + R[i][j]
	var Si := inv3(S)
	if Si.is_empty():
		return 0.0
	var nu := V.of(z[0] - x[0], z[1] - x[1], z[2] - x[2])
	var nis := 0.0
	for i in 3:
		for j in 3:
			nis += nu[i] * Si[i][j] * nu[j]
	return nis


## An unseen burn: widen by the smallest of BURN_SIZES that brings the
## sighting (its nis()) inside the gate, as a jump any time since the last sighting.
func _size_unseen(nis: Callable, gate: float) -> void:
	_burned()
	var since := maxf(MANEUVER_SINCE, t - last_seen)
	var P0 := P.map(func(r): return r.duplicate())
	for dv in BURN_SIZES:
		P = P0.map(func(r): return r.duplicate())
		maneuver_seen(since, dv)
		if float(nis.call()) <= gate:
			return


## A burn seen at time `at` (its plume; burn number n), of at most `most`
## km/s: a velocity jump at that moment, guessed at BURN_GUESS. The estimate
## as it was, knowing nothing of the burn, is kept to size it by.
func burn_seen(n: int, at: float, most: float) -> void:
	var since := maxf(t - at, 1.0)
	burn = {"n": n, "at": at, "x0": x.duplicate(), "t0": t, "sized": false}
	_burned()
	maneuver_seen(since, minf(BURN_GUESS, most))


## After a position fix: size the burn seen last, until it is sized. The
## estimate without the burn is flown to now on the same force model; where
## the track now puts it, less that, is the burn's effect, δr = Φrv·Δv (the
## two-body transition matrix from the burn to now, which the Earth's
## flattening changes by a part in a thousand). So Δv = Φrv⁻¹·δr, and its
## covariance Φrv⁻¹·Prr·Φrv⁻ᵀ. Sized once its 1σ is under half its size, or
## under SIZED_KMS (a burn too small to size better).
const SIZED_KMS := 0.0002
func _size_burn() -> void:
	if burn.is_empty() or burn.sized or dims() != 3 or t - float(burn.at) < 1.0:
		return
	var c := Track.new(id, label, PackedFloat64Array(burn.x0), P.map(func(r): return r.duplicate()), float(burn.t0))
	c.predict(t)
	var F := stm(coast(c.x, float(burn.at) - t), t - float(burn.at))
	var Frv := [[F[0][3], F[0][4], F[0][5]], [F[1][3], F[1][4], F[1][5]], [F[2][3], F[2][4], F[2][5]]]
	var Fi := inv3(Frv)
	if Fi.is_empty():
		return
	var dr := V.of(x[0] - c.x[0], x[1] - c.x[1], x[2] - c.x[2])
	var dv := V.of(0.0, 0.0, 0.0)
	for i in 3:
		dv[i] = Fi[i][0] * dr[0] + Fi[i][1] * dr[1] + Fi[i][2] * dr[2]
	var var_sum := 0.0
	for i in 3:
		for a in 3:
			for b in 3:
				var_sum += Fi[i][a] * P[a][b] * Fi[i][b]
	burn.dv = dv
	burn.sigma = sqrt(maxf(0.0, var_sum / 3.0))
	burn.sized = float(burn.sigma) < maxf(0.5 * V.norm(dv), SIZED_KMS)


## 1σ position ellipse: {major, minor, angle} (km, km, rad).
## In 3-D: major and minor are the 1σ semi-axes of the position ellipsoid
## (its largest and smallest; mid the third), angle that of the major axis of
## its shadow on x-y.
func ellipse() -> Dictionary:
	if dims() == 3:
		var ev := eig3(P)
		var ax: float = P[0][0]
		var bx: float = P[0][1]
		var dx: float = P[1][1]
		return {"major": sqrt(maxf(0.0, ev[0])), "minor": sqrt(maxf(0.0, ev[2])), "mid": sqrt(maxf(0.0, ev[1])), "angle": 0.5 * atan2(2.0 * bx, ax - dx)}
	var a: float = P[0][0]
	var b: float = P[0][1]
	var d: float = P[1][1]
	var mid := (a + d) / 2.0
	var diff := sqrt(pow((a - d) / 2.0, 2.0) + b * b)
	return {"major": sqrt(maxf(0.0, mid + diff)), "minor": sqrt(maxf(0.0, mid - diff)), "angle": 0.5 * atan2(2.0 * b, a - d)}


## Eigenvalues of the symmetric 3 × 3 block A[0..2][0..2], largest first
## (the trigonometric solution; Smith 1961, Commun. ACM 4(4):168).
static func eig3(A: Array) -> PackedFloat64Array:
	var a00: float = A[0][0]
	var a11: float = A[1][1]
	var a22: float = A[2][2]
	var a01: float = A[0][1]
	var a02: float = A[0][2]
	var a12: float = A[1][2]
	var p1 := a01 * a01 + a02 * a02 + a12 * a12
	var q := (a00 + a11 + a22) / 3.0
	var p2 := (a00 - q) * (a00 - q) + (a11 - q) * (a11 - q) + (a22 - q) * (a22 - q) + 2.0 * p1
	if p2 <= 1e-28 * q * q:
		return PackedFloat64Array([q, q, q])
	var p := sqrt(p2 / 6.0)
	var b00 := (a00 - q) / p
	var b11 := (a11 - q) / p
	var b22 := (a22 - q) / p
	var b01 := a01 / p
	var b02 := a02 / p
	var b12 := a12 / p
	var detb := b00 * (b11 * b22 - b12 * b12) - b01 * (b01 * b22 - b12 * b02) + b02 * (b01 * b12 - b11 * b02)
	var phi := acos(clampf(detb / 2.0, -1.0, 1.0)) / 3.0
	var e1 := q + 2.0 * p * cos(phi)
	var e3 := q + 2.0 * p * cos(phi + TAU / 3.0)
	return PackedFloat64Array([e1, 3.0 * q - e1 - e3, e3])


## Where the estimate says the target is at time at (a copy, coasted).
func forecast(at: float, fast := false) -> Track:
	var c := Track.new(id, label, x.duplicate(), P.map(func(r): return r.duplicate()), t)
	c.accel_noise = accel_noise
	c.noise_axes = noise_axes
	c.predict(at, fast)
	return c


## A detection folded in at time at: remember where it was.
func mark_seen(at: float) -> void:
	last_seen = maxf(last_seen, at)
	lkp = pos()
	lkp_t = at


## Drop it once nobody has detected it for DROP_AFTER s, or once its 1σ
## position is wider than DROP_SIGMA_KM. Real trackers delete tracks that go
## unconfirmed for N scans (Blackman & Popoli 1999; MathWorks trackHistoryLogic);
## dropping on a too-wide gate, and both thresholds, are design values.
const DROP_AFTER := 24.0 * 3600.0
const DROP_SIGMA_KM := 100000.0


func stale(at: float) -> bool:
	return at - last_seen > DROP_AFTER or ellipse().major > DROP_SIGMA_KM


func pos() -> PackedFloat64Array:
	if x.size() == 6:
		return V.of(x[0], x[1], x[2])
	return V.of(x[0], x[1])


func vel() -> PackedFloat64Array:
	if x.size() == 6:
		return V.of(x[3], x[4], x[5])
	return V.of(x[2], x[3])


## Least-squares fix of where lines of bearing cross. lines: [{from, bearing, sigma}].
## Returns {ok, r, P2} with a 2×2 position covariance from the line geometry.
## Lines with a "dir" (a unit vector) are 3-D: the fix is the point nearest
## them all in the least-squares sense, sum of w (I - u uT)(r - o) = 0, and
## P2 is 3 × 3.
static func cross_fix(lines: Array) -> Dictionary:
	if not lines.is_empty() and lines[0].has("dir"):
		return _cross_fix3(lines)
	var A := [[0.0, 0.0], [0.0, 0.0]]
	var b := [0.0, 0.0]
	for l in lines:
		var n := PackedFloat64Array([-sin(l.bearing), cos(l.bearing)]) # normal to the line (64-bit: not a Vector2)
		var dist := 1e5 # weight lines by their cross-track error at a nominal 100,000 km
		var w := 1.0 / pow(l.sigma * dist, 2.0)
		var o: PackedFloat64Array = l.from
		var c := n[0] * o[0] + n[1] * o[1]
		A[0][0] += w * n[0] * n[0]
		A[0][1] += w * n[0] * n[1]
		A[1][1] += w * n[1] * n[1]
		b[0] += w * n[0] * c
		b[1] += w * n[1] * c
	A[1][0] = A[0][1]
	var det: float = A[0][0] * A[1][1] - A[0][1] * A[1][0]
	if absf(det) < 1e-30:
		return {"ok": false}
	var rx: float = (A[1][1] * b[0] - A[0][1] * b[1]) / det
	var ry: float = (-A[1][0] * b[0] + A[0][0] * b[1]) / det
	# Re-weight each line by its true distance to the fix for the covariance.
	var I := [[0.0, 0.0], [0.0, 0.0]]
	for l in lines:
		var n := PackedFloat64Array([-sin(l.bearing), cos(l.bearing)])
		var o: PackedFloat64Array = l.from
		var rr := maxf(1000.0, sqrt((rx - o[0]) * (rx - o[0]) + (ry - o[1]) * (ry - o[1])))
		var w := 1.0 / pow(l.sigma * rr, 2.0)
		I[0][0] += w * n[0] * n[0]
		I[0][1] += w * n[0] * n[1]
		I[1][1] += w * n[1] * n[1]
	I[1][0] = I[0][1]
	var d2: float = I[0][0] * I[1][1] - I[0][1] * I[1][0]
	if absf(d2) < 1e-30:
		return {"ok": false}
	var P2 := [[I[1][1] / d2, -I[0][1] / d2], [-I[1][0] / d2, I[0][0] / d2]]
	return {"ok": true, "r": V.of(rx, ry), "P2": P2}


## The 3 × 3 inverse (adjugate over determinant); [] if singular.
static func inv3(M: Array) -> Array:
	var c00: float = M[1][1] * M[2][2] - M[1][2] * M[2][1]
	var c01: float = M[1][2] * M[2][0] - M[1][0] * M[2][2]
	var c02: float = M[1][0] * M[2][1] - M[1][1] * M[2][0]
	var det: float = M[0][0] * c00 + M[0][1] * c01 + M[0][2] * c02
	var sc: float = absf(M[0][0]) + absf(M[1][1]) + absf(M[2][2])
	if det == 0.0 or absf(det) < 1e-12 * sc * sc * sc:
		return []
	var c10: float = M[0][2] * M[2][1] - M[0][1] * M[2][2]
	var c11: float = M[0][0] * M[2][2] - M[0][2] * M[2][0]
	var c12: float = M[0][1] * M[2][0] - M[0][0] * M[2][1]
	var c20: float = M[0][1] * M[1][2] - M[0][2] * M[1][1]
	var c21: float = M[0][2] * M[1][0] - M[0][0] * M[1][2]
	var c22: float = M[0][0] * M[1][1] - M[0][1] * M[1][0]
	return [[c00 / det, c10 / det, c20 / det], [c01 / det, c11 / det, c21 / det], [c02 / det, c12 / det, c22 / det]]


static func _cross_fix3(lines: Array) -> Dictionary:
	var A := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
	var b := [0.0, 0.0, 0.0]
	for l in lines:
		var u: PackedFloat64Array = l.dir
		var o: PackedFloat64Array = l.from
		var w := 1.0 / pow(l.sigma * 1e5, 2.0)
		for i in 3:
			for j in 3:
				var m := w * ((1.0 if i == j else 0.0) - u[i] * u[j])
				A[i][j] += m
				b[i] += m * o[j]
	var Ai := inv3(A)
	if Ai.is_empty():
		return {"ok": false}
	var r := V.of(0.0, 0.0, 0.0)
	for i in 3:
		r[i] = Ai[i][0] * b[0] + Ai[i][1] * b[1] + Ai[i][2] * b[2]
	# Re-weight each line by its true distance to the fix for the covariance.
	var I := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
	for l in lines:
		var u: PackedFloat64Array = l.dir
		var rr := maxf(1.0, V.dist(r, l.from))
		var w := 1.0 / pow(l.sigma * rr, 2.0)
		for i in 3:
			for j in 3:
				I[i][j] += w * ((1.0 if i == j else 0.0) - u[i] * u[j])
	var P3 := inv3(I)
	if P3.is_empty():
		return {"ok": false}
	return {"ok": true, "r": r, "P2": P3}


## Start a track at a fix, with a circular-orbit prior on velocity.
## In 3-D one fix does not give the orbit's plane: the prior is circular and
## prograde about the world's pole, its 1σ in each axis 0.7 of the circular
## speed (design value), so an orbit in any plane through the fix is in reach.
static func start(id_: String, label_: String, fix: Dictionary, at: float) -> Track:
	if (fix.P2 as Array).size() == 3:
		var r3: PackedFloat64Array = fix.r
		var rn3 := V.norm(r3)
		var vc3 := sqrt(mu() / rn3)
		var pole := gravity.pole if gravity != null else V.of(0.0, 0.0, 1.0)
		var along := V.cross(pole, r3)
		if V.norm(along) < 1e-6 * rn3:
			along = V.cross(V.of(1.0, 0.0, 0.0), r3)
		var v3 := V.scale(along, vc3 / V.norm(along))
		var vs3 := maxf(1.0, 0.7 * vc3) ** 2
		var P6 := diag([0.0, 0.0, 0.0, vs3, vs3, vs3])
		for i in 3:
			for j in 3:
				P6[i][j] = float(fix.P2[i][j])
		return Track.new(id_, label_, PackedFloat64Array([r3[0], r3[1], r3[2], v3[0], v3[1], v3[2]]), P6, at)
	var r: PackedFloat64Array = fix.r
	var rn := V.norm(r)
	var vc := sqrt(mu() / rn)
	var vx := -r[1] / rn * vc
	var vy := r[0] / rn * vc
	var P2: Array = fix.P2
	var vs := 1.0 * 1.0 # (km/s)²: it could be on any nearby orbit
	var P0 := [PackedFloat64Array([P2[0][0], P2[0][1], 0, 0]), PackedFloat64Array([P2[1][0], P2[1][1], 0, 0]), PackedFloat64Array([0, 0, vs, 0]), PackedFloat64Array([0, 0, 0, vs])]
	return Track.new(id_, label_, PackedFloat64Array([r[0], r[1], vx, vy]), P0, at)
