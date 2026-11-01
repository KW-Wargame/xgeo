## The tracker in three dimensions (a world about the Earth), headless:
##   godot --headless --path godot --script res://tests/track3d_test.gd
## - Jupiter's campaign stays planar: 4-state tracks, as before.
## - Lines of sight in 3-D cross where the target is (Track.cross_fix), and a
##   track started there is 6-state.
## - A Red craft on ICEYE-X36's orbit (inclined 97.85°), in the public
##   catalogue, starts with a 6-state track at its catalogue accuracy. Over a
##   day of looks, ground radars (PFISR, LeoLabs Midland) see it only above
##   their elevation masks; the track stays consistent with the truth (its
##   NEES, the normalised estimation error squared, near its 6 degrees of
##   freedom; Bar-Shalom, Li & Kirubarajan 2001, §5.4), and each radar pass
##   tightens it.
extends SceneTree

var fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok    " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


## eᵀ P⁻¹ e over the first e.size() states, by Gauss-Jordan elimination
## (P symmetric positive). Velocities (states 3-5) are scaled by 1,000 s to km,
## so the matrix is not ill-conditioned by its units.
static func nees(e_: PackedFloat64Array, P: Array) -> float:
	var n := e_.size()
	var e := PackedFloat64Array()
	for i in n:
		e.append(e_[i] * (1000.0 if i >= 3 else 1.0))
	var A := []
	for i in n:
		var row := PackedFloat64Array()
		for j in n:
			row.append(float(P[i][j]) * (1000.0 if i >= 3 else 1.0) * (1000.0 if j >= 3 else 1.0))
		row.append(e[i])
		A.append(row)
	for c in n:
		var piv := c
		for r in range(c + 1, n):
			if absf(A[r][c]) > absf(A[piv][c]):
				piv = r
		var tmp = A[c]
		A[c] = A[piv]
		A[piv] = tmp
		for r in n:
			if r == c:
				continue
			var f: float = A[r][c] / A[c][c]
			for k in range(c, n + 1):
				A[r][k] -= f * A[c][k]
	var s := 0.0
	for i in n:
		s += e[i] * A[i][n] / A[i][i]
	return s


func _init() -> void:
	# 1. Jupiter's campaign stays planar.
	Sim.campaign_path = "res://tests/fixtures/jupiter_shadow.json"
	var jup := Sim.new("res://data/game.json", "res://tests/fixtures/jupiter_shadow.json")
	var planar := jup.sensing.dims == 2
	for id in jup.tracks:
		planar = planar and (jup.tracks[id] as Track).x.size() == 4 and (jup.tracks[id] as Track).P.size() == 4
	_check(planar, "Jupiter's campaign keeps planar tracks (%d of them, 4-state)" % jup.tracks.size())

	# 2. Two lines of sight in 3-D cross at the target; a track starts there, 6-state.
	var sim := Sim.new("res://data/game.json", "res://tests/fixtures/track3d_test.json")
	var tgt := V.of(1200.0, 6500.0, -2400.0)
	var lines := []
	for o in [V.of(-3000.0, 5000.0, 2000.0), V.of(4000.0, 3000.0, -4000.0)]:
		var d := V.sub(tgt, o)
		lines.append({"from": o, "dir": V.scale(d, 1.0 / V.norm(d)), "sigma": 1e-4, "bearing": atan2(d[1], d[0])})
	var fix := Track.cross_fix(lines)
	_check(fix.ok and V.dist(fix.r, tgt) < 1e-6 and (fix.P2 as Array).size() == 3,
		"two 3-D lines of sight cross at the target (off by %.6f m)" % (V.dist(fix.r, tgt) * 1000.0 if fix.ok else INF))
	var started := Track.start("t", "T", fix, 0.0)
	_check(started.x.size() == 6 and started.P.size() == 6 and absf(V.norm(started.vel()) - sqrt(sim.mu / V.norm(tgt))) < 1e-9,
		"a track started at a 3-D fix is 6-state, on a circular-speed guess")
	# A direction (two angles) pulls a 3-D track onto the line of sight, both
	# when it is narrow (unscented) and when it is wide (pseudo-linear).
	for wide in [5.0, 1500.0]:
		var o := V.of(-3000.0, 5000.0, 2000.0)
		var off := V.scale(V.of(0.6, -0.4, 0.8), wide)
		var t3 := Track.new("d", "D", PackedFloat64Array([tgt[0] + off[0], tgt[1] + off[1], tgt[2] + off[2], 1.0, 2.0, 7.0]), Track.diag([wide * wide, wide * wide, wide * wide, 1e-6, 1e-6, 1e-6]), 0.0)
		var u := V.sub(tgt, o)
		u = V.scale(u, 1.0 / V.norm(u))
		var before := V.norm(V.sub(V.sub(t3.pos(), tgt), V.scale(u, V.dot(V.sub(t3.pos(), tgt), u))))
		t3.update_dir(o, u, 1e-5)
		var miss := V.sub(t3.pos(), tgt)
		var across := V.norm(V.sub(miss, V.scale(u, V.dot(miss, u))))
		_check(across < 0.05 * before and t3.cross_sigma(o) < 0.1 * wide and t3.ellipse().major > 0.5 * wide,
			"a direction pulls a track %.0f km wide onto the line of sight: across it %.2f → %.3f km, 1σ across %.3f km, along it still %.0f km" % [wide, before, across, t3.cross_sigma(o), t3.ellipse().major])

	# 3. The catalogued Red craft over a day of radar looks.
	var x: Dictionary = sim.by_id.r1
	var tr: Track = sim.tracks.get("r1")
	_check(sim.sensing.dims == 3 and tr != null and tr.x.size() == 6 and tr.P.size() == 6 and absf(tr.ellipse().major - 0.2) < 1e-9,
		"the catalogued craft starts with a 6-state track, 1σ 200 m")
	var h := V.cross(x.r, x.v)
	_check(rad_to_deg(acos(V.dot(h, sim.gravity.pole) / V.norm(h))) > 90.0, "its orbit is inclined: %.2f° to the Earth's equator" % rad_to_deg(acos(V.dot(h, sim.gravity.pole) / V.norm(h))))
	var masks := {}
	for s in sim.ships:
		if s.get("kind", "") == "site":
			masks[s.id] = deg_to_rad(float(s.cls.radar.min_el_deg))
	var n := 0
	var sum := 0.0
	var high := 0
	var passes := 0
	var tight := 0
	var below_mask := 0
	var worst_ratio := 0.0
	var sum_p := 0.0
	var last_p := 0.0
	while sim.t < Sim.DAY - 1.0:
		var before: float = tr.forecast(sim.t + Sim.LOOK).ellipse().major
		sim.advance(Sim.LOOK)
		tr = sim.tracks.get("r1")
		if tr == null:
			break
		var e := PackedFloat64Array()
		for i in 3:
			e.append(tr.x[i] - x.r[i])
		for i in 3:
			e.append(tr.x[3 + i] - x.v[i])
		var q := nees(e, tr.P)
		n += 1
		sum += q
		if q > 22.46: # χ²(6) 99.9%
			high += 1
		var qp := nees(e.slice(0, 3), tr.P)
		sum_p += qp
		last_p = qp
		var radar_now := false
		for l in tr.lobs:
			if l.kind == "radar" and absf(float(l.t) - sim.t) < 1.0:
				radar_now = true
				var site: Dictionary = sim.by_id[l.by]
				var up := V.scale(site.r, 1.0 / V.norm(site.r))
				var el := asin(V.dot(V.sub(x.r, site.r), up) / V.dist(x.r, site.r))
				if el < masks[l.by] - 1e-9:
					below_mask += 1
		if radar_now:
			passes += 1
			var after: float = tr.ellipse().major
			worst_ratio = maxf(worst_ratio, after / before)
			if after < 0.7 * before:
				tight += 1
	_check(tr != null and n >= 143, "the track is held all day (%d looks)" % n)
	# One measurement a look (600 s) per site: a pass above PFISR's 45° or
	# Midland's 30° lasts minutes, so a day catches few.
	_check(passes >= 1 and below_mask == 0, "the radars saw it on %d looks, never below their elevation masks" % passes)
	var mean := sum / maxf(1.0, n)
	var mean_p := sum_p / maxf(1.0, n)
	_check(mean > 2.0 and mean < 12.0 and mean_p > 1.0 and mean_p < 6.0 and high <= n / 20,
		"consistent: mean NEES %.2f (6 expected), position alone %.2f (3 expected), over %d looks; %d past the χ²(6) 99.9%% point" % [mean, mean_p, n, high])
	_check(passes > 0 and tight == passes and worst_ratio < 0.2,
		"each radar look tightens it: the 1σ after over before at worst %.3f" % worst_ratio)
	if tr != null:
		_check(last_p < 16.27, "after a day: %.1f km off the truth with 1σ %.1f km (position NEES %.2f)" % [V.dist(tr.pos(), x.r), tr.ellipse().major, last_p])
	print("%d failed" % fails)
	quit(1 if fails > 0 else 0)
