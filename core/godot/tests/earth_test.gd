## A world about the Earth (a scenario's "central" block), headless:
##   godot --headless --path godot --script res://tests/earth_test.gd
## - The scenario's central body stands in for Jupiter: its GM, radius and
##   date; ships start from their state in the GCRF or beside another ship.
## - Its J2 turns ICEYE-X36's node a day as the secular rate says (Vallado
##   2013, eq. 9-41: dΩ/dt = −(3/2) n J2 (R/p)² cos i, here from the starting
##   state's osculating a, so near 1.04° rather than the sun-synchronous
##   0.9856° of its mean elements), about the Earth's pole (not Jupiter's).
## - A craft placed on the no-drift orbit stays near (J2 and the Sun move both
##   alike), and the Sun is about 1 AU away.
extends SceneTree

var fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok    " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _init() -> void:
	var sim := Sim.new("res://data/game.json", "res://tests/fixtures/earth_test.json")
	var x: Dictionary = sim.by_id.x36
	var k: Dictionary = sim.by_id.k
	_check(sim.central == "earth" and absf(sim.mu - 398600.4418) < 1e-9 and absf(sim.central_radius() - 6378.137) < 1e-9 and sim.moons.is_empty(),
		"the scenario's central body is the Earth: its GM, radius, no moons")
	_check(absf(V.norm(x.r) - 6929.0) < 15.0 and absf(V.dist(x.r, k.r) * 1000.0 - sqrt(140.0 * 140.0 + 500.0 * 500.0)) < 0.01,
		"ICEYE-X36 starts %.1f km from the centre, the second craft %.1f m from it" % [V.norm(x.r), V.dist(x.r, k.r) * 1000.0])
	var pole := sim.gravity.pole
	var node0 := V.cross(pole, V.cross(x.r, x.v))
	var h := V.cross(x.r, x.v)
	var a := Kepler.semi_major_axis(x.r, x.v, sim.mu)
	var inc := acos(V.dot(h, pole) / V.norm(h))
	var n := sqrt(sim.mu / pow(a, 3.0))
	var want := -1.5 * n * 1.08262668e-3 * pow(6378.137 / a, 2.0) * cos(inc) * 86400.0
	var orbit := TAU / n
	var far := 0.0
	while sim.t < orbit:
		sim.advance(60.0)
		far = maxf(far, V.dist(x.r, k.r))
	_check(far < 0.8, "the craft on the no-drift orbit stays within %.0f m over an orbit" % (far * 1000.0))
	while sim.t < 86400.0:
		sim.advance(600.0)
	var node1 := V.cross(pole, V.cross(x.r, x.v))
	var turned := atan2(V.dot(V.cross(node0, node1), pole), V.dot(node0, node1))
	_check(absf(turned - want) < 0.01 * absf(want),
		"the node turns %.4f° in a day (J2's secular rate: %.4f°)" % [rad_to_deg(turned), rad_to_deg(want)])
	var au := V.norm(sim.sun_pos()) / 149597870.7
	_check(au > 0.98 and au < 1.0, "the Sun is %.4f AU from the Earth in late October" % au)
	print("%d failed" % fails)
	quit(1 if fails > 0 else 0)
