# xGEO Core: writing a scenario

A scenario is one JSON file: the platforms and equipment in play, where they
start, what Red does, and how the run ends. xGEO Core loads it on top of
`godot/data/game.json` (Jupiter, the moons, the sensor settings and a shared
set of classes) and runs it with no window through `godot/cli/run.gd`.

A complete, working example is
[`godot/data/examples/two_ships.json`](../godot/data/examples/two_ships.json):
a Blue weather satellite, a Blue warship and a Red inspector in low Jupiter
orbit. Every value in it is a design value (Notional). Copy it and change it.

A second example,
[`godot/data/examples/test_range.json`](../godot/data/examples/test_range.json)
(TEST RANGE), is the scenario Core's end-to-end test plays
(`godot/tests/scenario_test.gd`): every section on this page, an `effects`
block with the same design values as CLOSE PASS, and a Blue warship carrying
every sensor and effect. See *Testing a scenario* at the end.

The loader is `Sim._init` in `godot/core/sim.gd`; the end of the run is
`godot/core/campaign.gd`. This page describes what they read. Keys they do not
read are not listed.

## Fidelity of what you write

Your file feeds Real models (gravity, the radio and infrared equations, the
filter) with your own inputs. A class you invent, its sizes and powers, Red's
plan and the objectives are Notional: say so in a `note` (free text, ignored by
the loader). The labels are defined in [FIDELITY.md](FIDELITY.md).

## The file's sections

| Key | Required | Units | Meaning |
|---|---|---|---|
| `ships` | yes, in practice | | Every platform at the start. Without it the loader falls back to `game.json`'s own `scenario.ships`. |
| `classes` | no | | Classes of your own, by id. Added to `game.json`'s; the same id replaces `game.json`'s class. |
| `objectives` | yes, for a run that can end before `--hours` | | What Blue must do; which ones end the run. See *Objectives and how a run ends*. |
| `days` | no | days of sim time | The run ends with result `time` when this much sim time has passed. Without it, only the objectives (or `--hours`) end it. |
| `escalation` | if an objective is `peace` | | `war`: the escalation score (Notional) at which the `peace` objective fails. |
| `opening` | no | | Blue's first track on the Red ship whose id is `h1`. See *The opening track*. |
| `effects` | if anything uses an effect | | Settings for jamming, spoofing, dazzling, HPM, cyber, kinetic kills and radar (`effects.gd`). The CLI gives no orders, so a CLI run does not need them; xGEO Live and your own scripts that call `sim.effects` do. Copy the block from `examples/test_range.json`; the Jupiter test world (`godot/tests/fixtures/jupiter_shadow.json`, in the full repository) carries the same values with notes giving each value's basis. |
| `civil` | no | | Neutral civil traffic, each one a radio emitter on a circular orbit. See *Civil traffic*. |
| `pockets`, `red`, `blue_extra` | no | | Lagrange-point pockets and Red ships placed in them, and Blue buoys staged behind a moon. The Jupiter test world (`jupiter_shadow.json`) has pockets; no current scenario uses `red` or `blue_extra` (they came from the retired NIGHT HERON); see *Pockets*. |
| `interplanetary` | no | true / false | Allow flights between planets (`transfer.gd`). Default false. |
| `hulls` | no | | Hull drawings by class id, for xGEO Live only. Core gives a class with no hull an empty one. |
| `name` | no | | Printed in the CLI's `start` line. |
| `id`, `lost_advice`, `database`, `sources` | no | | Read by xGEO Live (tutorial choice, debrief, database window, sources), not by Core. |

Only `ships` and `classes` shape the world; the rest is bookkeeping.

## Placing ships

Each entry in `ships` is one platform:

| Key | Required | Units | Meaning |
|---|---|---|---|
| `id` | yes | | Unique. `h1` is special (*The opening track*). |
| `classId` | yes | | A class from this file's `classes` or from `game.json`. |
| `side` | yes | `blue`, `red`, `neutral` | Blue is the U.S. Space Corps and its partners; Red is unflagged. Only Blue's ships sense; only Red and civil ships are listened to. |
| `kind` | yes | | What it is to the rules: `warship` (Red treats it as a threat; it can drop buoys), `commercial`, `station`, `hostile` for Red. A Red inspector backs off only from a Blue ship that is not a `station`, `buoy`, `kv` or `commercial`. |
| `name`, `short` | yes | | Long name, and the short one used in log lines. |
| `orbit` | one of three | see below | A circular orbit in the game's plane. |
| `r0`, `v0` | one of three | km, km/s | A state vector, Jupiter-centred, `[x, y, z]`. Set `t0: 0` with it. |
| `onMoon` | one of three | `io`, `europa`, `ganymede`, `callisto` | Fixed at that moon's centre and carried with it (a station). |
| `dry`, `prop` | no | tonnes | Override the class's dry and propellant mass. |
| `role` | Red only | | Red's behaviour. See *Red's behaviour*. |
| `plan` | with `role: shadow` | | Red's plan. |

Other fields (`registry`, `operator`, `flag`, `status`) are carried along for
xGEO Live's windows.

`orbit` is the easy way:

| Key | Required | Units | Meaning |
|---|---|---|---|
| `radius_km` | yes | km from Jupiter's centre | Jupiter's radius is 71,492 km; the shipped scenario's low orbit is 92,940 km. |
| `phase_deg` | no, default 0 | degrees | Angle from the +x axis, counter-clockwise. Orbits are prograde (counter-clockwise). |
| `along_km` | no, default 0 | km | Moves the ship along the orbit: + ahead, − behind (an arc length on `radius_km`). |
| `radial_km` | no, default 0 | km | Moves it out (+) or in (−); the orbit is circular at the new radius. |

The speed is circular under the game's gravity, J2 included
(v² = μ/r + (3/2)μJ2R²/r³, `Sim._place`), so a ship placed this way coasts
round without a burn. Two ships at the same `radius_km` and `phase_deg` with
different `along_km` fly in formation; a small negative `radial_km` puts a ship
on a slightly faster, lower orbit, so it slowly catches up from behind. In the
example, the inspector starts 300 km behind and 10 km below its target, and
the warship 1,500 km behind and 40 km below.

## Classes: reuse or define

A ship's `classId` is looked up in one table: `game.json`'s classes with this
file's `classes` merged over them. So you can:

- **Reuse** a `game.json` class by id. Its ids are `sentinel` (Blue warship:
  infrared and optical telescopes, radio ears, radar, a nuclear-thermal drive),
  `pfs` (Blue protective-fires spacecraft), `station` (Blue surveillance site),
  `skv` (kill vehicle), `vesper` (Red covert tender), `hmh5` and `gmc2` (large
  civil hulls). The example's warship is a `sentinel`.
- **Define** your own under `classes`, as the example does for its satellite
  (`pelican`) and its inspector (`midge`). Copy the nearest existing class and
  change the values.
- **Replace** a `game.json` class by giving yours the same id. It replaces it
  for every ship in this run.

What a class needs:

| Key | Required | Units | Meaning |
|---|---|---|---|
| `name` | yes | | Shown when a track is identified, and in the debrief. |
| `length` | yes | m | Sets how close a telescope must be to identify it. |
| `sig` | yes | `T` K, `eps`, `A` m², `alpha`, `diffuse` | Its skin for the heat model: temperature, emissivity, area, solar absorptance. |
| `rcs` | yes | m² | Radar cross-section. |
| `dry`, `prop` | with `engine` | tonnes | Masses, unless the ship sets them. |
| `engine` | to manoeuvre | `ve` km/s, `thrust` N, `hot` {`A` m², `T` K, `eps`} | Exhaust speed, thrust, and the hot drive the infrared sees while it burns. Δv follows the rocket equation. |
| `ir` | to see by infrared | `aperture` m, `nei`, `neiBand` W/m² | The telescope and its noise-equivalent irradiance. |
| `ttc` | to be heard | `f` Hz, `Pt` W, `dish` m, `bw` Hz, `burst` s, `every` [min, max] s, `aim`, `mod` | Its command and telemetry radio. `aim` is `handler` (Red's outpost by Callisto), `earth`, a moon id, or a ship id. `every` is how long it waits between reports. |
| `esm`, `radar`, `optical`, `thermal` | no | | Radio ears, radar, a visible telescope, a reactor and radiators: copy them from `sentinel` in `game.json`. |

A ship that needs none of the optional blocks (the example's `pelican`) is
only something to be seen and guarded.

## Red's behaviour

`role` picks Red's brain (`red_ai.gd`). The general-purpose one is `shadow`:
an uncooperative rendezvous and inspection of a Blue ship.

```json
"role": "shadow",
"plan": {"target": "pelican", "legs": [[-40, 1, 2], [-3, 2, 1.5]]}
```

`target` is the ship it inspects. Each leg is `[along-track km (+ ahead),
hours to hold there, hours to get there]`: it flies to that slot beside the
target (two burns, which its handler must command), holds, then takes the next
leg. After the last hold the inspection is complete and it leaves. Cut off from
its handler for 3 hours within 200 km of its target with a Blue ship within
25 km of it, it backs off to a higher orbit and departs (design values). If a
leg would cost more than 1/2.2 (about 45%) of its remaining Δv, it ends the
inspection there.

A Red ship with no `role` only reports home on its `ttc` schedule.

## The opening track

A ship with `"opening_track": "<label>"` starts with a track under that label
(TRK 4417 in the examples), drawn from its true state with this much error:

| Key | Default | Units | Meaning |
|---|---|---|---|
| `opening.sigma_km` | 3000 | km | 1σ position error of the first track. |
| `opening.sigma_kms` | 0.3 | km/s | 1σ velocity error. |
| `opening.cue` | | [plain, doctrinal] | The log line that says how it was cued. |

A ship with `"beacon_track": "<label>"` starts named by its beacon: a tight,
identified neutral track. Any other Red ship starts unknown: Blue tracks it
only once its own sensors find it, unless it is listed in `catalogued`.

## Catalogued objects, ground radars and the opening view

These three blocks are used by `data/scenarios/close_pass_earth.json`.

- `catalogued`: objects Blue already has in a public catalogue. Each entry is
  `id`, optional `side`, `sigma_km` and `sigma_kms`. Blue starts with a track on
  each one: its true state plus random error of that size, already identified
  by class.
- `sites`: ground stations on the turning Earth. Each entry is `id`, `name`,
  `short`, `class` and `ground` {`lat_deg`, `lon_deg`, `h_km`} (WGS 84). A
  site's class may carry a `radar` block {`site`: true, `sigma_range_km`,
  `sigma_angle_deg`, `min_el_deg`, `max_range_km`, `cadence_s`}. The radar
  measures range and two angles for any non-Blue object above its elevation
  mask and within its reach.
- `view`: {`actor`, `focus`, `select`, `dist`, `pitch`}. These set the craft
  the player starts in, the craft the camera looks at, what is selected at
  first, and the camera's distance and tilt.

In a world centred on any body but Jupiter, tracks are 3-D (six numbers).

## Civil traffic

Each entry in `civil` is a neutral emitter on a circular, two-body orbit:
`id`, `class`, `name`, `short`, `radius_km`, `phase_deg`, optional `operator`
and `f` (Hz, its own channel; else the class's). Its class needs a `ttc`
block. Civil traffic is what makes Red's reports hard to pick out on the same
band.

## Pockets

`pockets` are places Red can hide: `{id, name, kind: "lagrange", moon, lead
(degrees, ±60 for L4/L5), size (km)}`. An entry in `red` places a Red ship in
one: `{id, name, short, class, role, pocket (an id, or a list to pick from by
the seed), offset: [x, y] km}`. A pocket counts as found when a classified
hostile track sits inside it with a 1σ ellipse smaller than its `size`. The
`lane` kind and `blue_extra` depend on the shelved scenario's freighter and
buoys.

## Objectives and how a run ends

Each objective is `{id, text, fail, advice}`:

| Key | Required | Meaning |
|---|---|---|
| `id` | yes | Which test it runs (below). An id not in this list stays open forever. |
| `text` | yes | What it says; the reason given if it ends the run. |
| `fail` | yes | `true`: failing it ends the run, lost. `false`: it is only graded. |
| `advice` | no | Shown in the debrief if it failed. |

The tests (`Campaign.status`):

| `id` | Done when | Failed when |
|---|---|---|
| `signal` | a report from the `shadow` ship has been recorded and identified | never |
| `stop` | the `shadow` ship is out of the fight | it completed its inspection |
| `protect_sat` | the run is over | the `shadow` ship's `plan.target` is destroyed |
| `debris` | the run is over | any debris exists |
| `peace` | the run is over | escalation reaches `escalation.war` |
| `find` | every pocket holding Red is found | never |
| `protect`, `sleeper`, `excal` | | tied to the shelved scenario's ships |

Every look (600 s of sim time), the campaign checks, in this order:

1. The first objective with `fail: true` that has failed ends the run:
   result `lost`.
2. Every Red ship out of the fight (destroyed, captured, disabled, departed,
   given up or out of fuel) and every pocket holding Red found: result `won`.
3. `days` passed: result `time`.

So a scenario needs at least one Red ship: with none, the second test passes at
the first look and the run is won at once.

The CLI runs for `--hours` whatever happens, and stops early once the run is
over. It gives no orders: Blue's ships coast and sense, and Red follows its
plan. A CLI run of the example is therefore lost when the inspector finishes.
To play Blue from the command line, give the runner a course of action
(below); for anything more, drive `Sim` from GDScript
(`sim.execute(sim.plan_intercept(...))`, `sim.effects`), as `godot/tests/` do.

## The seed and the run

The seed drives every random draw: the opening track's error, sensor noise,
when Red reports home, which pocket a Red ship picks. It is `game.json`'s
`scenario.seed` (4417) unless `--seed=N` is given; a scenario file cannot set
it. The same file, seed, run, orders and `--step` give the same output, byte
for byte.

Each part of Core draws from its own stream: `setup` (which pocket),
`sensing` (noise, detections, false alarms), `effects` (a kill vehicle's hit,
a captured node's logs, a jinking target), `breakup` (the debris and the
damage), `red` (when Red reports home) and `traffic` (civil emitters). A
stream's seed is the first 60 bits of SHA-256 (FIPS 180-4) of
`xgeo/<seed>/<run>/<name>`, so more draws in one part (a new sensor, say)
never move another part's numbers. `--run=K` picks run K of a seed: runs 0 to
K-1 of one seed are a Monte Carlo set that anyone can reproduce.

## A course of action

`--coa=file.json` gives Blue's orders at set times, from a file like
`data/examples/test_range_coa.json`:

```json
{"orders": [
  {"t": 1800, "do": "intercept", "ship": "lancer", "target": "h1", "tof": 7200},
  {"t": 3600, "do": "effect", "effect": "jam", "ship": "excal", "target": "h1"},
  {"t": 5400, "do": "burn", "ship": "excal", "dv": [0.0, 0.003, 0.0]},
  {"t": 5400, "do": "buoy", "ship": "lancer"}
]}
```

| Order | Fields | What it does |
|---|---|---|
| `burn` | `ship`, `dv` [x, y, z] km/s | An impulsive burn, paid for in propellant. |
| `intercept` | `ship`, `target`, `tof` s | A transfer that meets the target `tof` seconds later, refined under full gravity and flown. Against a Red ship it is planned on Blue's track, not the truth. |
| `effect` | `effect`, `ship`, `target` | `jam`, `spoof`, `dazzle`, `hpm`, `cyber` or `kinetic`, if it can be used then (in range, on the beam, a declared enemy). |
| `buoy` | `ship` | Drop a listening buoy, if the ship carries one and the scenario has the buoy class. |
| `match` | `ship`, `target` | The velocity that keeps the ship alongside the target, on Blue's track of a Red ship (same orbit, turned to where the ship is). |
| `analyse` | `on` (default true) | Take bearings on and classify every burst as it is heard, as the game's auto-analysis does. |
| `radar` | `ship`, `on` | Radiate: ranges every track in reach, and escalates while it runs. |

`intercept` also takes `behind_km`, to arrive that far behind the target along
its orbit instead of on it. An effect order with `stop: true` ends a jam or a
spoof. Any order may carry `until` (s): refused at its time, it is tried again
every look (600 s) until it is carried out or `until` passes, so "jam as soon
as the rules allow" is `{"t": 0, "until": 259200, "do": "effect", ...}`; the
`order` line then reports how many `tries` it took. The full list is in
`godot/core/orders.gd`.

`t` is seconds from the start; the runner stops at each order's time to give
it, and orders only Blue's ships. Each order adds an `order` line saying
whether it was carried out (`ok`) and, if not, why (`why`: not enough fuel,
not a known enemy, …). An order that cannot be carried out is reported and
skipped, not fatal.

## Running it

Put the file under `godot/` and pass its `res://` path:

```sh
godot --headless --path godot --script res://cli/run.gd -- \
  --scenario=res://data/examples/two_ships.json --hours=8 --step=1800 --seed=7
```

| Option | Default | Meaning |
|---|---|---|
| `--scenario=` | `res://data/scenarios/close_pass_earth.json` | The scenario. Empty runs `game.json` alone. |
| `--hours=` | 24 | Sim hours to run. |
| `--step=` | 600 | Seconds between `step` lines. The world acts every 600 s look whatever this is. |
| `--seed=` | `game.json`'s | The master random seed. |
| `--run=` | 0 | The run of that seed (a Monte Carlo set: 0, 1, 2, …). |
| `--coa=` | none | A course of action: Blue's orders at set times. |
| `--out=` | standard output | Write the lines to this file. |
| `--truth=` | false | Also report Red's and neutrals' true states. |

Godot prints its banner, and at exit some leaked-resource errors, around the
JSON; keep only the lines that start with `{`. Mistakes do not always stop
the run: a `classId` that does not exist prints a `SCRIPT ERROR` on standard
error, that ship is left out, and the run goes on without it. Check standard
error for `SCRIPT ERROR` after every change.

## Reading the output

One JSON object per line. Units are km, km/s and s, Jupiter-centred, in the
game's plane; `t` is sim seconds from the start.

- `start`: the scenario, its `name`, the seed, the run, the number of orders,
  the start time (UTC), hours and step.
- `step`, one per `--step`: `t` and `utc`; `escalation`; `ships`, Blue's (all
  of them with `--truth=true`) with position `r`, velocity `v` and remaining
  `delta_v`; `tracks`, Blue's belief about each contact, never the truth:
  `label`, `ident` (`unknown` until identified), `side`, `class`, `in_contact`,
  `last_seen`, `r`, `v` and the 1σ position ellipse `sigma_km` (`major`,
  `minor` in km, `angle` in radians); and `log`, every log entry since the last
  line, each with its own `t`, a stable `code`, a `kind` (info, good, warn,
  alert) and the `text`.
- `end`: the last `t`, `over`, `result` (`won`, `lost`, `time`, or empty if
  `--hours` ran out first) and the `debrief`: each objective's state, each Red
  ship's fate, escalation and debris.
- `order`, one per order given: `t`, the `order` as written, `ok`, `why`, and
  for an intercept the `dv` flown.

From the command above (seed 7), trimmed: positions, velocities and the second
Blue ship are cut, and `…` marks a cut.

```json
{"engine":"xGEO Core","hours":8.0,"name":"TWO SHIPS","orders":0,"run":0,"scenario":"res://data/examples/two_ships.json","seed":7,"step":1800.0,"type":"start","units":{"distance":"km","speed":"km/s","time":"s"},"utc":"2041-10-12T16:10:00Z"}
{"escalation":0.0,"log":[{"code":"red_quiet","kind":"warn","t":600.0,"text":"TRK 4417 went quiet."},{"code":"burn_seen","kind":"alert","t":1200.0,"text":"TRK 4417 just burned. It's on the move."}],"ships":[{"alive":true,"class":"sentinel","delta_v":8.6567842746427,"id":"lancer","name":"LANCER (USA 702)",…}],"t":1800.0,"tracks":[{"class":"","ident":"unknown","in_contact":true,"label":"TRK 4417","last_seen":1800.0,…,"side":"unknown","sigma_km":{"angle":-0.861880495496169,"major":62.6413797362481,"minor":2.15452248200939},…}],"type":"step","utc":"2041-10-12T16:40:00Z"}
…
{"escalation":0.0,"log":[{"code":"shadow_hold","kind":"warn","t":7800.0,"text":"TRK 4417 has parked 40 km behind PELICAN-3."},{"code":"burn_seen","kind":"alert","t":8400.0,"text":"TRK 4417 just burned. It's on the move."}],…,"t":9000.0,…}
…
{"escalation":0.0,"log":[{"code":"shadow_done","kind":"alert","t":24000.0,"text":"TRK 4417 finished its inspection of PELICAN-3 and left. It got what it came for."},…],…,"t":25200.0,…}
{"debrief":{"advice":["The inspector finished its look. Get alongside it and cut its command link."],…,"objectives":[{"id":"signal","state":"open",…},{"id":"stop","state":"failed",…},{"id":"protect_sat","state":"done",…},{"id":"peace","state":"done",…}],"reds":[{"class":"MIDGE-CLASS INSPECTOR","how":"still active","name":"TRK 4417"}],"result":"lost","why":"Make it break off before it finishes its inspection"},"over":true,"result":"lost","t":25200.0,"type":"end"}
```

Read it as: Blue holds the opening track; the inspector felt hunted by the
warship closing from behind and went quiet at 600 s, burned at 1,200 s, parked
40 km behind PELICAN-3, moved in to 3 km, and at 24,000 s finished. `stop` had
`fail: true`, so the run was lost at that look; the CLI's last step closed at
25,200 s. The track's 1σ ellipse is long and thin (62 km by 2 km): bearings
from one telescope pin the direction well and the range poorly.

Two things the output does not say directly. The opening cue is logged while
the scenario loads, before the first line, so it never appears. And the moment
the run ended is the `t` of the log line that ended it, not the `end` line's
`t`, which is the last step boundary.

## Many runs: the batch runner

`godot/cli/batch.gd` plays many runs of a scenario for each course of action
and writes one line of outcomes per run:

```sh
godot --headless --path godot --script res://cli/batch.gd --   --coa=a.json,b.json --runs=20 --hours=72 --out=batch.jsonl
```

`--runs=20` plays runs 0 to 19 of the seed; `--runs=20-39` plays those, so
several processes can share a batch and their lines join into the same file
one process would write. `none` in `--coa` is a course of action with no
orders. The first line, `batch`, names the scenario, seed, runs and courses of
action; then one `run` line per run and course of action: `coa`, `run`,
`result` and `won`, `t_end`, `escalation`, `blue_dv_used` (km/s, all of
Blue's ships), each objective's state, each Red ship's fate, the debris
clouds, and the orders carried out and refused (with why).

Run k is the same world for every course of action: the same opening track
error, detections and chance draws until the orders change what happens
(common random numbers, from the per-subsystem streams). Comparing two
courses of action run by run then measures the effect of the orders, with
much less noise than independent runs (Law 2015, *Simulation Modeling and
Analysis*, 5th ed., §11.2).

## Testing a scenario

`godot/tests/scenario_test.gd` plays TEST RANGE through every part of Core and
checks that the parts agree; copy it to check a scenario of your own:

```sh
godot --headless --path godot --script res://tests/scenario_test.gd
```

It checks that the scenario loads (every ship, a station riding its moon, the
civil emitter, the opening track); that the same seed gives the same world to
the last digit and another seed does not; two days of flight (every state
finite, nothing inside Jupiter, an unmanoeuvred orbit keeping its size); that
bursts are heard, classified and direction-found by two ears, and that the
track on the inspector stays honest (the truth inside 4σ of its own estimate);
that Jupiter hides a ship on its far side; a planned transfer arriving within
50 km; each effect against its formula (HPM reach √(30PG)/E, the laser's
irradiance at its dazzle reach, Pk, the jammer's reach) and in use, with its
escalation and the laser's waste heat; a kill vehicle breaking up a 0.5 t
inspector and only cratering a 60 t tender (the NASA breakup model's 40 J/g);
the objectives, the end of the operation and the debrief; a save that loads
back bit for bit and runs on alike, and a save from before the random streams
still loads; the command-line runner's JSON lines; the random streams (their
seeds against Python's SHA-256, a thousand extra draws on one leaving the
others alone, another run giving another world); a course of action (each
order given at its time, carried out or refused with the reason, changing the
outcome, and replaying byte for byte); that time is real (a sim second is a
second of UTC, a ship turns at its real orbital rate with J2, Io at its real
period); and that a finished world is freed.

A scenario may compress its story, as CLOSE PASS compresses weeks of the real
inspection into days, but only through its schedule: shorter holds and quicker
hops, paid for in real Δv. The clock and the physics are never scaled. Its thresholds (4σ, 50 km, 2%) are design
values for a test, chosen with margin over what the models give.
