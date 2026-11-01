## Every word the player reads, in plain or doctrinal language.
##
## Doctrinal terms follow US doctrine:
## - JP 3-85, Joint Electromagnetic Spectrum Operations (2020): electromagnetic
##   support (ES), attack (EA), protection (EP); emission control (EMCON);
##   direction finding (DF).
## - JP 3-14, Space Operations (2018, Change 1 2020): space situational awareness
##   (SSA); the Space Force (SFDD-1, 2025) now says space domain awareness (SDA).
## - JP 3-60, Joint Targeting: find, fix, track, target, engage, assess (F2T2EA).
## - USSF, Space Warfighting: A Framework for Planners (2025): counterspace as
##   orbital, electromagnetic and cyberspace warfare; space link interdiction;
##   active defense (escort, counterattack) and passive defense (threat warning,
##   military deception). Counterspace effects are reversible or nonreversible
##   (USSF framework pp. 5, 9): deceive, disrupt, deny, degrade, destroy (JP 3-14
##   GL-5, negation).
## Blue is the U.S. Space Corps (fiction, modelled on the Space Force's Deltas 2,
## 3, 7 and 9) with its CSpO and NATO partners. Red is unflagged.
## Plain language says the same thing in everyday words. The game is the same
## either way; only the words change.
class_name Lang

static var doctrinal := false

const TX := {
	"overview": ["Overview", "Overview"],
	"selected": ["Selected", "Selected track"],
	"effects": ["What you can do to it", "Counterspace options"],
	"signals": ["Signals", "ES"],
	"ew_console": ["Listening station", "EW console"],
	"planner": ["Plan a move", "Maneuver planner"],
	"theatre": ["Campaign", "Campaign · COP"],
	"log": ["What happened", "Event log"],
	"track": ["contact", "track"],
	"tracks": ["Contacts", "Tracks"],
	"unknown": ["Unknown", "Unknown"],
	"classified": ["Type known", "Classified"],
	"identified": ["Named", "Identified"],
	"hostile": ["Enemy", "Hostile"],
	"neutral": ["Neutral", "Neutral"],
	"friend": ["Ours", "Friendly"],
	"quiet": ["Quiet", "EMCON"],
	"loud": ["Loud", "EMCON broken"],
	"df": ["Find direction", "DF"],
	"classify": ["Identify signal", "Classify"],
	"heard": ["Heard", "Intercepts"],
	"fuel": ["Fuel", "Δv"],
	"plan_intercept": ["Plan intercept", "Plan intercept"],
	"burn": ["Burn", "Execute burn"],
	"look": ["Look (IR)", "IR look"],
	"focus": ["Focus", "Focus"],
	"listen": ["Listen", "ES"],
	"ear": ["Ear", "ES receiver"],
	"jam": ["Jam its orders", "EA · uplink jamming"],
	"spoof": ["Fake its position", "EA · deception"],
	"dazzle": ["Blind it", "Directed energy · dazzle"],
	"hpm": ["Microwave pulse", "HPM"],
	"cyber": ["Take control", "Cyberspace · capture"],
	"kinetic": ["Interceptor", "Kinetic · KV"],
	"escalation": ["Escalation", "Escalation"],
	"pocket": ["pocket", "named area of interest"],
	"pockets": ["Pockets", "NAIs"],
	"find": ["Heard", "Find"], "fix": ["Located and identified", "Fix"], "trackstep": ["Following", "Track"],
	"target": ["Ready to decide", "Target"], "engage": ["Acted", "Engage"], "assess": ["Out of the fight", "Assess"],
	"aou": ["could be anywhere within", "AOU 2σ"],
	"debrief": ["How it went", "After-action review"],
	"objectives": ["What you must do", "Objectives"],
	"sda": ["Knowing what's up there", "Space domain awareness"],
	"blue_force": ["U.S. Space Corps and allies", "USSC / CSpO"],
	"red_force": ["Unflagged", "Unflagged (Red)"],
	"civil_force": ["Civil and neutral", "Civil / neutral"],
	"database": ["Database", "Platform database"],
	"db_open": ["Look it up", "Database entry"],
	"db_search": ["Search names, types, equipment…", "Search: name, designation, type, equipment"],
	"not_identified": ["Not yet identified", "NOT YET IDENTIFIED"],
	"db_not_identified": ["You have not worked out what this is yet. Identify one of its signals or get a close look and its page appears here.", "Class not yet identified by any track. Classify an intercept or obtain a visible-light ID."],
	"db_units": ["Ships of this class", "Units"],
	"db_propulsion": ["Engine and fuel", "Propulsion"],
	"db_sensors": ["Sensors", "Sensors"],
	"db_emitters": ["What it transmits", "Emitters"],
	"db_weapons": ["What it can do", "Weapons and effects"],
	"db_signature": ["How easy it is to see", "Signature"],
	"db_basis": ["How real is this", "Realism basis"],
	"db_sources": ["Sources", "Sources"],
	"db_fitted": ["Fitted to", "Fitted to"],
	"db_equipment": ["Equipment", "Equipment"],
}

## Sentences: [plain, doctrinal], with %s / %.2f placeholders.
const FX := {
	"burn": ["%s burned %.2f km/s. Its drive glowed: anyone watching saw it.", "%s executed %.2f km/s burn. Drive plume observable system-wide."],
	"heard": ["%s: a %s, heard by %s.", "INTERCEPT %s: %s, %s."],
	"df": ["Bearings on %s from %d listener(s).", "DF on %s: %d LOB."],
	"new_track": ["New contact %s: lines crossed near %s.", "TRACK %s INITIATED: LOB fix near %s."],
	"classified": ["%s identified: %s.", "%s CLASSIFIED: %s."],
	"burn_seen": ["%s just burned. It's on the move.", "%s: maneuver detected."],
	"burn_sized": ["%s burned about %s m/s (give or take %s).", "%s: maneuver estimated, %s m/s (1σ %s)."],
	"lost": ["Lost sight of %s.", "%s: contact lost."],
	"dropped": ["%s dropped: not seen for too long to say where it is.", "%s: track dropped."],
	"sink_full": ["%s heat sink is full: radiators back on.", "%s: heat sink saturated, radiators restored."],
	"dark_on": ["%s gone dark: its waste heat goes into the heat sink.", "%s: thermal EMCON, heat to sink."],
	"dark_off": ["%s radiators back on.", "%s: radiators restored."],
	"jam_on": ["%s jamming %s. You are loud now.", "%s: EA on %s. EMCON broken."],
	"jam_hit": ["%s can't hear its handler.", "%s: uplink denied."],
	"spoof_on": ["%s feeding %s false ranging.", "%s: deception on %s's ranging."],
	"dazzle_hit": ["%s's sensors blinded for %d h.", "%s: IR sensor dazzled, %d h."],
	"hpm_hit": ["%s's electronics knocked out.", "%s: disabled by HPM."],
	"cyber_hit": ["You have control of %s. Its logs name its friends.", "%s captured. Exploitation reveals linked tracks."],
	"kv_away": ["Interceptor away on %s: %d%% to hit, %s flight.", "KV away on %s. Pk %d%%, TOF %s."],
	"kv_hit": ["%s destroyed. %d pieces of debris now share its orbit.", "%s destroyed: catastrophic breakup, %d debris objects (≥10 cm)."],
	"kv_cripple": ["%s hit but not broken up: %s knocked out. %d pieces of debris.", "%s damaged, non-catastrophic: %s lost. %d debris objects (≥10 cm)."],
	"kv_miss": ["Interceptor missed %s by %s.", "KV miss on %s: miss distance %s."],
	"red_quiet": ["%s went quiet.", "%s: EMCON."],
	"pocket_found": ["Found a Red pocket: %s.", "NAI %s confirmed: hostile presence."],
	"shadow_hold": ["%s has parked %s %s.", "%s: station-keeping %s %s."],
	"shadow_retreat": ["%s lost its handler and is backing away.", "%s: loss of command link; abort to safe orbit observed."],
	"shadow_waits": ["%s can't hear its handler, but it's holding its slot. Get a ship within %s of it to make it leave.", "%s: link lost, holding position (no proximity threat inside %s)."],
	"shadow_gone": ["%s has broken off, %s away and drifting.", "%s: departed proximity, range %s, opening."],
	"shadow_inside": ["Red is parked inside the keep-out of our satellite: tension rises (+%d).", "Red RPO inside keep-out; escalation +%d."],
	"blue_too_close": ["%s is within a kilometre of %s. Red reads that as a threat: escalation %d.", "%s inside 1 km of %s; escalation %d."],
	"shadow_crowded": ["%s doesn't want our inspector that close: it's moving to the far side of %s.", "%s: Blue proximity; repositioning beyond %s."],
	"shadow_driven": ["%s has given up on %s with our inspector on it, and is leaving.", "%s: RPO on %s aborted under Blue proximity; departure observed."],
	"shadow_push": ["%s sees none of ours near and is moving in closer to %s.", "%s: unobserved; closing on %s."],
	"shadow_done": ["%s finished its inspection of %s and left. It got what it came for.", "%s: RPO on %s complete; departure observed."],
	"escalation_warn": ["Escalation at %d. Red is getting ready to fight openly.", "Escalation %d: indications of hostile intent to escalate."],
}


static func t(key: String) -> String:
	var v: Array = TX.get(key, [key, key])
	return v[1] if doctrinal else v[0]


static func f(key: String, args: Array) -> String:
	var v: Array = FX.get(key, ["%s", "%s"])
	return (v[1] if doctrinal else v[0]) % args


## A distance as the player reads it: "12,938 km", or "1.04 Mkm" from a
## million kilometres.
static func km(x: float) -> String:
	if x >= 1e6:
		return "%.2f Mkm" % (x / 1e6)
	var s := str(int(round(x)))
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += ","
		out += s[i]
	return out + " km"
