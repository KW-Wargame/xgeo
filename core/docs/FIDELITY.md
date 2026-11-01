# xGEO Core: fidelity of each model

Every model and value in xGEO Core carries one of three labels:

- **Real:** sourced and checked against an independent reference
  ([PHYSICS-VERIFICATION.md](PHYSICS-VERIFICATION.md)).
- **Projected:** near-future, grounded in programmes that exist today.
- **Notional:** invented for a scenario, the way studies fly notional systems.

A Real model can be fed Notional inputs: the radar equation is Real, a Red
jammer's power is Notional, and the range it yields is only as good as both.

| Model | File | Label | Checked against | What it leaves out |
|---|---|---|---|---|
| Two-body motion | `kepler.gd` | Real | hapsira, DOP853; Curtis and Vallado worked examples | nothing within two-body |
| Lambert intercepts | `lambert.gd` | Real | hapsira `izzo`; Curtis Ex. 5.2 | nothing: Izzo's method with its multi-revolution branches (`solve_all`); the game's ships use the single revolution |
| Gravity: Jupiter J2 and the Galilean moons | `gravity.gd` | Real | hapsira J2 and third-body terms; DOP853 | higher harmonics (J4 and up), Sun and Saturn, relativity, radiation pressure |
| Moon positions | `gravity.gd`, `ephem.gd` | Real, simplified | JPL Horizons, 2036–2046 | planar mean elements, no mutual perturbations: up to 23,000 km and 0.72° off |
| Sun and planets | `ephem.gd` | Real | JPL approximate positions (Standish & Williams 1992) | arc-minute accuracy only |
| Propagation overall | `sim.gd` | Real, not operational | DOP853 with error control at rtol 1e-12, within 3 mm a day of scipy's DOP853 at 1e-13 | not the high-fidelity propagation used in operations |
| Time | `sim.gd`, `ephem.gd` | Real, simplified | astropy.time | leap seconds are ignored: the clock runs 69.2 s from TT (0.16° of Io's orbit) |
| Radio link budgets, noise, integration | `rf.gd` | Real | ITU-R P.525, published examples | atmospheric and plasma effects, multipath |
| Antenna patterns | `antenna.gd` | Real | ITU-R reference patterns | real dishes' measured patterns |
| Radar range equation | `rf.gd` | Real | radar handbooks (REALISM-SOURCES) | clutter, Swerling fluctuation beyond the stated case |
| Direction finding | `sensing.gd` | Real | interferometer accuracy formula | multipath, calibration errors |
| Jamming (J/S, spot and barrage) | `effects.gd`, `rf.gd` | Real equations, Notional powers | jamming equation; powers are design values | effect is binary (cut or not), Red does not hop or null |
| Heat and infrared | `thermal.gd` | Real | Stefan–Boltzmann, Planck band fractions | Jupiter as a grey body, zodiacal background not verified at 5.2 AU |
| Heat forecast | `forecast.gd` | Real model, Notional thresholds | the same IR look as `sensing.gd` | |
| Tracking filter | `tracking.gd` | Real | filterpy; consistency (NEES) over many runs; its transition matrix against differences of reference coasts | the covariance moves under the full force model (the transition matrix flown with the mean); quick on-screen forecasts and a bearing's age use the two-body one; planar: the state is [x, y, vx, vy] in Jupiter's equatorial plane, while ships move in 3-D (the Sun pulls them out of it by metres over days); data association is by truth id; drop thresholds are design values |
| Breakup and debris | `breakup.gd` | Real | NASA Standard Breakup Model | long-term debris evolution |
| Component damage | `damage.gd` | Notional | | |
| Nuclear-thermal drives at 900 s | `game.json` classes | Projected | NASA tested specific impulse | |
| Ship classes, equipment sizes | `game.json`, the scenario files | Notional | sizes are design values; performance follows the physics | |
| Red's behaviour | `red_ai.gd` | Notional | | does not adapt by hopping, nulling or optical links |
| Escalation scores, objectives | `effects.gd`, `campaign.gd` | Notional | | |
| Civil radio traffic | `traffic.gd` | Notional | | |
| Timescale (weeks compressed to days) | the Jupiter test world (`tests/fixtures/jupiter_shadow.json`) | Notional | the schedule only: the inspector's holds are hours, not days, and its hops are quicker, paid for in real Δv. The clock and the physics run in real time (`scenario_test.gd`, section 12: UTC, a ship's orbital rate with J2, Io's period) | |

Run the checks: the Godot tests listed in Core's README, and
`node tools/verify.mjs` (every number against independent references; the
results table is in [PHYSICS-VERIFICATION.md](PHYSICS-VERIFICATION.md)).
