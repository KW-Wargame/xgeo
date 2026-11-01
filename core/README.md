# xGEO Core

The simulation engine under xGEO, with no graphics: orbits, sensors, signals
and tracking around Jupiter. Everything the game knows about the world is
computed here; the game, [xGEO Live](https://kw-wargame.github.io/xgeo/), only draws it and sends orders
in. The game is not part of this folder or its licence.

Licence: **Apache 2.0** (`LICENSE`, `NOTICE`). Use it and change your own
copy for any purpose; keep the notices and do not call your version xGEO.
Open source, not open contribution: pull requests are not accepted, but bug
reports and requests are welcome as [issues](https://github.com/KW-Wargame/xgeo/issues). Status: alpha.
Core is for teaching, concept studies and research. It is not a validated
operational tool.

Download: [xgeo-core.zip](https://kw-wargame.github.io/xgeo/core/xgeo-core.zip). You need
[Godot 4.7](https://godotengine.org/download) (the standard build).

## Run it

```sh
godot --headless --path godot --script res://cli/run.gd -- --scenario= --hours=24 --step=600 --out=run.jsonl
```

`godot/cli/run.gd` loads a scenario, steps time and writes JSON lines: a
`start` line, one `step` line per `--step` seconds (Blue's ships, Blue's
tracks with their 1σ ellipses, escalation, and every log entry since the last
step), and an `end` line with the debrief. `--scenario=res://data/....json`
picks the scenario, `--seed=N` the random seed and `--run=K` the run of it
(each subsystem draws from its own stream, so runs 0..K-1 are a reproducible
Monte Carlo set), `--coa=orders.json` gives Blue's orders at set times (burn,
intercept, effect, buoy; see `docs/SCENARIOS.md`), `--truth=true` adds Red's and
neutrals' true states. A relative `--out` path is relative to the `godot/`
folder (Godot starts there), so `run.jsonl` above lands in `godot/run.jsonl`.
With no scenario file
(`--scenario=`) it runs on `game.json` alone: the classes, the equipment and
the opening positions. Units are km, km/s and s, centred on Jupiter.

From GDScript the same thing is `var sim := Sim.new()` then
`sim.advance(seconds)`, reading `sim.ships`, `sim.tracks` and `sim.log`; the
tests in `godot/tests/` do exactly this.

## What is in it

Each file opens with what it models and its sources. Fidelity labels (Real,
Projected, Notional) are in [docs/FIDELITY.md](docs/FIDELITY.md); the sources,
in full, in [docs/REALISM-SOURCES.md](docs/REALISM-SOURCES.md).

**Physical models**

| File | Models |
|---|---|
| `v.gd` | 64-bit vector maths (Godot's Vector3 is 32-bit) |
| `kepler.gd` | two-body motion, universal variables (Curtis 2020) |
| `lambert.gd` | Lambert's problem, intercept planning |
| `gravity.gd` | Jupiter with J2, the four Galilean moons |
| `ephem.gd` | the Sun and planets from Jupiter (JPL approximate positions) |
| `transfer.gd` | interplanetary transfers |
| `rf.gd` | Friis link budgets, radar range equation, noise, rocket equation |
| `antenna.gd` | dish gain off boresight (ITU-R reference patterns) |
| `thermal.gd` | heat balance, radiators, infrared intensity (Planck) |
| `forecast.gd` | how visible a ship will be over its coming orbit |
| `sensing.gd` | everything Blue can learn: IR looks, radio intercepts, direction finding, radar |
| `tracking.gd` | the unscented Kalman filter: Blue's belief, never the truth |
| `breakup.gd`, `damage.gd` | NASA Standard Breakup Model, component damage |
| `traffic.gd` | civil radio traffic on the same band |
| `sim.gd` | the running world that ties them together |

**Scenario rules** (in Core because they run headless, but they are rules of
play, not physics; most values here are Notional)

| File | Does |
|---|---|
| `effects.gd` | Blue's counterspace effects and their costs |
| `red_ai.gd` | Red's behaviour |
| `campaign.gd` | objectives, how a scenario ends, the debrief |
| `lang.gd` | every sentence the log prints, plain or doctrinal |
| `save_game.gd` | save and continue |

The data is JSON in `godot/data/`: `game.json` holds the classes and
constants. A scenario is another JSON file, passed with `--scenario=`; two
examples are in `godot/data/examples/`, and how to write one is in
[docs/SCENARIOS.md](docs/SCENARIOS.md).
A value in a data file is either cited (a `sources` entry) or marked as a design value.

## Test it

```sh
godot --headless --path godot --import
godot --headless --path godot --script res://tests/run_tests.gd
godot --headless --path godot --script res://tests/scenario_test.gd
godot --headless --path godot --script res://tests/forecast_test.gd
godot --headless --path godot --script res://tests/earth_test.gd
godot --headless --path godot --script res://tests/track3d_test.gd
node tools/check-core.mjs    # Core never reaches into the game
node tools/verify.mjs        # every number against independent references (needs Python 3.12+)
```

The verification suite (`tools/verify/`) evaluates Core's own functions and
compares them with hapsira, scipy, astropy, filterpy, JPL Horizons data and
published worked examples; the method and the latest results are in
[docs/PHYSICS-VERIFICATION.md](docs/PHYSICS-VERIFICATION.md). Its first run
installs the Python packages it needs into `tools/verify/.venv`; after that it
works offline.
