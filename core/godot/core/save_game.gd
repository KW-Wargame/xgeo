## Save and continue: the whole running world in one file (user://), in
## Godot's binary encoding (var_to_bytes), which keeps every double bit for bit.
## (Text, var_to_str, does not: str_to_var reads some 17-digit numbers back one
## unit in the last place off, and a loaded world then drifts from the one saved.
## Older text saves are still read.)
class_name SaveGame

const PATH := "user://xgeo.save"
## Where saves went before 26 Oct 2026: still read, and moved on the next save.
const OLD_PATH := "user://night_heron.save"
const SHIP_SKIP := ["cls", "plan_ref"]


## The save to read: the current file, else one from before the rename.
static func found() -> String:
	if FileAccess.file_exists(PATH):
		return PATH
	return OLD_PATH if FileAccess.file_exists(OLD_PATH) else ""


static func save(sim: Sim) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_buffer(var_to_bytes(state_of(sim)))
	if FileAccess.file_exists(OLD_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(OLD_PATH))


## The whole running world as one value, its own copy (nothing in it is
## shared with the sim): what a save holds, and what a branch keeps.
static func state_of(sim: Sim) -> Dictionary:
	var ships := []
	for s in sim.ships:
		var d := {}
		for k in s:
			if not SHIP_SKIP.has(k):
				d[k] = s[k]
		ships.append(d)
	var tracks := {}
	for id in sim.tracks:
		var tr: Track = sim.tracks[id]
		tracks[id] = {"label": tr.label, "x": tr.x, "P": tr.P, "t": tr.t, "ident": tr.ident, "class_id": tr.class_id, "side": tr.side, "last_seen": tr.last_seen, "in_contact": tr.in_contact, "intercepts": tr.intercepts, "lkp": tr.lkp, "lkp_t": tr.lkp_t, "burn": tr.burn, "ranged_at": tr.ranged_at}
	var state := {"t": sim.t, "next_look": sim.next_look, "escalation": sim.escalation, "ships": ships, "tracks": tracks, "track_n": sim.track_n,
		"intercepts": sim.intercepts, "log": sim.log, "debris": sim.debris, "scheduled": sim.scheduled, "seed": sim.master_seed, "run": sim.run, "rng": sim.stream_states(),
		"jamming": sim.effects.jamming, "kvs": sim.effects.kvs, "radar": sim.effects.radar_on, "found": sim.campaign.found, "measures": sim.campaign.measures(), "pending": sim.sensing.pending,
		"auto": sim.sensing.auto, "dish_aim": sim.sensing.dish_aim, "last_look": sim.sensing.last_look, "doctrinal": Lang.doctrinal}
	return bytes_to_var(var_to_bytes(state)) # a deep copy, every double bit for bit


static func load_into(sim: Sim) -> bool:
	var path := found()
	if path == "":
		return false
	var raw := FileAccess.get_file_as_bytes(path)
	# A text save (before 26 Oct 2026) starts with "{"; a binary one with its type code.
	var state = str_to_var(raw.get_string_from_utf8()) if raw.size() > 0 and raw[0] == 0x7B else bytes_to_var(raw)
	if typeof(state) != TYPE_DICTIONARY:
		return false
	apply(sim, state)
	return true


## Put a world taken by state_of() back into the sim (a copy of it, so the
## state can be applied again later).
static func apply(sim: Sim, state_in: Dictionary) -> void:
	var state: Dictionary = bytes_to_var(var_to_bytes(state_in))
	sim.t = state.t
	sim.next_look = state.next_look
	sim.escalation = state.escalation
	sim.ships.clear()
	sim.by_id.clear()
	for d in state.ships:
		d.cls = Damage.cls_for(sim.data.classes[d.classId], d.get("damage", []))
		sim.ships.append(d)
		sim.by_id[d.id] = d
	sim.tracks.clear()
	for id in state.tracks:
		var s: Dictionary = state.tracks[id]
		var tr := Track.new(id, s.label, s.x, s.P, s.t)
		for k in ["ident", "class_id", "side", "last_seen", "in_contact", "intercepts", "lkp_t", "burn", "ranged_at"]:
			tr.set(k, s.get(k, tr.get(k)))
		tr.lkp = PackedFloat64Array(s.get("lkp", tr.pos()))
		sim.tracks[id] = tr
	sim.track_n = state.track_n
	sim.intercepts = state.intercepts
	sim.log = state.log
	sim.debris = state.debris
	sim.scheduled = state.scheduled
	sim.restore_streams(state)
	sim.effects.jamming = state.jamming
	sim.effects.kvs = state.kvs
	sim.effects.radar_on = state.radar
	sim.campaign.found = state.found
	sim.campaign.restore(state.get("measures", {}))
	sim.sensing.pending = state.pending
	sim.sensing.auto = state.auto
	sim.sensing.dish_aim = state.get("dish_aim", {})
	sim.sensing.last_look = state.last_look
	Lang.doctrinal = state.doctrinal
