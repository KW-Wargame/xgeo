# Physics verification

Every piece of physics xGEO uses is checked against something that can be verified without trusting the game: a maintained, citable library, JPL data, a published worked example, or a Monte Carlo of the physical process itself. The suite tests **the game's own numbers**. Godot evaluates its own GDScript functions and writes the results out. Python never reimplements the game in order to grade it.

```
node tools/verify.mjs              # dump Core's physics, then run the suite and print the table
node tools/verify.mjs -k moons     # extra arguments go to pytest
```

The first run creates `tools/verify/.venv` from `tools/verify/requirements.txt` (it needs Python 3.12 or later; on Windows, `winget install -e --id Python.Python.3.12`). Every later run works offline: JPL data is cached in `tools/verify/fixtures/`. The full table is written to `tools/verify/out/results.md` and `results.json`.

Result on 2 Nov 2026 (Godot 4.7.2), in the full repository: **681 of 681 comparisons within tolerance, 64 tests passed**, plus 4 INFO rows for known simplifications. On 26 Oct 2026: 762 of 762, 63 tests; on xGEO Core alone (the published folder, with no scenario file) then: 550 of 550 within tolerance, 57 tests passed, 2 INFO rows; the 6 tests of the effects (jammer, uplink turnaround, pointing, laser, HPM, kill probability) skip there, because their parameters come from a scenario file. On 25 Oct 2026: 762 of 762, 63 tests. (On 23 Oct 2026: 359 of 359, 51 tests, 16 INFO.)

## How it works

| Piece | Role |
| --- | --- |
| `tools/verify/fetch_fixtures.py` | Run once, online. Fetches JPL Horizons state vectors for Io, Europa, Ganymede and Callisto (relative to Jupiter, ICRF, TDB) at J2000, across the campaign window (2041-03-14 + 20 d, 2 h steps) and across 2036–2046 (1 d steps), plus the GM values from the body headers and JPL's mean-element table (JUP365). It stores both the raw API text and a parsed copy. |
| `tools/verify/fixtures/published_values.json` | Published constants and standards, each with its citation and URL: Juno gravity (Durante 2020, Iess 2018, Folkner 2017), the IAU 2015 pole, ITU-R P.525, CCSDS 401 turnaround, DSN 810-005 bands, the monopulse slope, and the beamwidth rule. |
| `tools/verify/make_cases.py` | Writes `fixtures/cases.json`, a deterministic grid of inputs: orbits from circular to e = 0.999 and hyperbolic, 3-D and retrograde, long- and short-way Lambert transfers, points around Jupiter, RF parameters from S to Ka band, random lines of sight, tracker states, bearing-line geometries, and the published worked examples. |
| `godot/tests/dump_physics.gd` | **The bridge.** It runs every case through `godot/core/*.gd` and adds cases built from the live campaign (every ship, every sensor, emitter, radar and weapon class in `game.json` and `campaign.json`). It writes `tools/verify/out/game_physics.json`. It computes nothing itself. |
| `tools/verify/tests/test_*.py` | Compare the dump with the references. Each comparison is recorded with its tolerance (`conftest.py`: `check.rel`, `check.abs`, `check.bound`, `check.true`, and `check.info` for known simplifications). |
| `tools/verify/refs.py` | Reference models assembled from hapsira and scipy (the force model, DOP853 integration, the two-body STM; the full-model STM is checked by differences of its coasts). Its one transcription of game code is the moon ephemeris, which drives the reference integrator. It is tested against the game's own moon states before it is used. |

**Plugging in a new model.** The IR, sidelobe, ear-pointing and heat models are due to be replaced (REALISM-SOURCES.md §8). To add a replacement:
1. Add a section to `dump_physics.gd` that calls the new functions on a grid of inputs and on the campaign platforms.
2. Add a `tests/test_<model>.py` that compares the output with an independent reference (astropy `BlackBody` in-band integration, ITU-R envelopes, a Monte Carlo of the detector) using `check.*`.
3. Turn the current INFO rows into `check.rel` or `check.bound` once the model they describe has been replaced.

## Models, references and results

Tolerances are relative unless a unit is given. The "Result" column is the worst case over every input.

### Orbits

| Model (game code) | Equation | Reference | Tolerance | Result |
| --- | --- | --- | --- | --- |
| Two-body propagation (`Kepler.propagate`) | Universal-variable Kepler equation, Curtis Alg. 3.3/3.4 | [hapsira](https://github.com/pleiszenburg/hapsira) 0.18 `farnocchia` and `vallado`; scipy `solve_ivp` DOP853 at rtol 1e-13. 122 cases: circular, e = 0.5, 0.95, 0.999, hyperbolic (e = 1.5, 3), 3-D, retrograde, every campaign ship, dt from 60 s to 30 d, negative dt | 1e-8 | 2.3e-10 |
| Conservation | Energy, angular momentum | vis-viva, Kepler II | 1e-9 | 5e-11 |
| Worked examples | — | Curtis (2020) Ex. 3.7; Vallado (2013) Ex. 2-4 | half the last printed digit | 3.9e-6 (Curtis), 3.3e-8 (Vallado) |
| Elements → state (`Kepler.from_elements`, pure-Kepler case) | Kepler's equation by Newton | hapsira `M_to_E`, `E_to_nu`, `coe2rv`, e = 0–0.99 | 1e-10 | 1.6e-14 |
| Stumpff functions | c(z), s(z) | 80-term Maclaurin series (Curtis eqs. 3.52–3.53) | 1e-9 | 9e-12 |
| Lambert (`Lambert.solve`, `Lambert.solve_all`) | Izzo (2015), Householder iteration, with the multi-revolution branches (since 30 Oct 2026; before, universal variables by bisection, Curtis Alg. 5.2, which src/engine/lambert.js still uses and the parity test checks against to 1e-8) | hapsira `izzo` (Izzo 2015); 129 transfers including every ship from WARDEN | 1e-6 | 7.3e-15 (Core alone, 111 transfers); every non-degenerate transfer solved |
| Lambert worked example | — | Curtis (2020) Ex. 5.2 | 6e-5 | 8e-6 |
| Force model (`Gravity.accel`) | μ/r² + J2 zonal + four moons as third bodies (direct − indirect) | hapsira `J2_perturbation`, `third_body`; central-difference gradient of the J2 potential | 1e-9 | 9e-11 |
| Integrator (`Gravity.coast`, DOP853) | DOP853 at rtol 1e-12 with error control, coasted in the game's own segments, 1 day, J2 + moons, test orbits and every ship of the scenario; and a 20-day J2 arc | DOP853 at rtol 1e-13 on hapsira's force terms | 1 cm (the need is 5 m, a tenth of the radar's 50 m range σ); 1 m over the 20 days | 2.75 mm (retrograde test orbit); 0.13 m over 20 days. RK4 before 27 Oct 2026: 1.0 m in a day (CLOSE PASS's inspector) |
| J2 secular rates | Ω̇ = −3/2 nJ2(R/p)² cos i, ω̇ = 3/4 nJ2(R/p)²(5cos²i − 1) | Vallado (2013) eqs. 9-41/9-42; 20-day arc at a = 3.1 R_J, i = 30° | 1% | 0.40% / 0.36% (first-order theory) |

### Jupiter system

| Quantity | Game | Reference | Tolerance | Result |
| --- | --- | --- | --- | --- |
| Jupiter GM | 126,687,000 km³/s² (NASA fact sheet) | JPL Horizons JUP365 126,686,531.9 ± 1.3; Juno/Durante 2020 126,686,534.1; IAU 2015 nominal (astropy) | 1e-5 | 3.7e-6 (kept: about 370 σ of JPL's estimate, but only 1.8e-6 in any period) |
| J2 (R = 71,492 km) | 14,696.514 × 10⁻⁶ (Folkner 2017) | Iess et al. 2018: 14,696.572 × 10⁻⁶ (as tabulated in A&A 2019, aa35938-19) | 1e-5 | 3.9e-6 |
| R_J | 71,492 km | IAU 2015 (astropy `R_jup`) | exact | 0 |
| Moon GMs | JPL values | Horizons body headers (JUP365) | 2e-8 | 5e-9 |
| SI c, k, σ, g₀ | — | c, k and σ exact since the 2019 SI (scipy.constants, CODATA 2022; identical to CODATA 2018); g₀ CGPM 1901 | 1e-9 | 3e-11 |
| Element clock | leap seconds ignored | astropy.time | 75 s | 69.2 s (0.16° of Io) |

### Galilean moons against JPL Horizons

The game's moons are planar Kepler ellipses built from JPL's mean elements. The mean longitude advances at the observed sidereal period (NASA Jovian satellite fact sheet) and the mean anomaly at JPL's tabulated period P (`anomalisticPeriodDays`), so the periapsis precesses at the difference between the two. JPL's legend calls P the sidereal period; the game uses it as the mean-anomaly period because, with the fact-sheet sidereal periods, that reproduces Horizons (`test_moons.py`). The implied apsidal periods match JPL's "P apsis" for Io (1.333 yr) and roughly for Europa (1.333 vs 1.394 yr), but not for Ganymede (135 vs 68.3 yr) or Callisto (536 vs 278 yr), a simplification bounded by the errors below. The frame is Jupiter's equator (IAU 2015 pole), with x pointing at its ascending node on the ICRF equator. The game's J2000 longitudes match Horizons in that frame to within 0.06–0.7°.

| Moon | Planar position error, campaign window | Longitude error | 2036–2046 longitude error | Out-of-plane (ignored) | Bound |
| --- | --- | --- | --- | --- | --- |
| Io | 2,970 km | 0.40° | 0.43° | 340 km | 5,000 km, 0.7° |
| Europa | 1,230 km | 0.10° | 0.24° | 5,370 km | 5,000 km, 0.5° |
| Ganymede | 6,400 km | 0.34° | 0.38° | 2,490 km | 10,000 km, 0.6° |
| Callisto | 23,200 km | 0.71° | 0.72° | 9,900 km | 30,000 km, 1.0° |

The mean-longitude rates agree with a least-squares fit to 10 years of Horizons positions to 1.4e-7 (Callisto 1e-6). The Laplace angle λ_I − 3λ_E + 2λ_G follows Horizons to within 1.1°.

### Radio

| Model | Equation | Reference | Tolerance | Result |
| --- | --- | --- | --- | --- |
| Dish gain (`RF.dish_gain`) | G = η(πD/λ)², η = 0.55 | IEEE Std 145-2013, G = 4πA_e/λ²; 35 dishes, 0.8–70 m, S to Ka band | 1e-12 | 4e-16 |
| Gain realism | — | DSN 34 m BWG at X band, 68.24 dBi at 8425 MHz (810-005 Module 104 Rev. O, Table 8) | ≤ 1.5 dB conservative | 1.24 dB below (η 0.55 vs about 0.69) |
| Friis / free-space loss (`RF.friis`, `Effects._fspl_db`) | Pr = PtGtGr(λ/4πR)² | Exact 20 log(4πR/λ) of [ITU-R P.525-4](https://www.itu.int/rec/R-REC-P.525/en) eq. (3); eq. (4) L = 32.4 + 20 log f(MHz) + 20 log d(km) rounds the exact constant 32.4478 | 0.05 dB | 0.048 dB (ITU's rounded constant) |
| Noise (`RF.noise`) | kTB | k exact (2019 SI); −174 dBm/Hz at T0 = 290 K (ITU-R P.372-17 §2); −228.6 dBW/K/Hz (10 log k) | 0.03 dB | 0.025 dB |
| Radiometer gain (`RF.integrate`) | SNR·√(Bτ) | Monte Carlo of an energy detector, 2,000 trials (total-power radiometer equation: Dicke 1946; Wilson et al. 2013; Condon & Ransom ch. 3 eq. 3.154; Dicke's switched radiometer is 2× worse) | 6% | 1.5% |
| Burst SNR and intercept range (`Sensing.link_snr`, `RF.intercept_range_km`) | Friis/kTB·√(Bτ) | Independent dB-form link budget and its brentq root; every emitter × receiver class (48 pairs) | 1e-9 | 6e-15 |
| Interferometer DF (`RF.df_sigma`) | σθ = λ/(2πd)·σφ, σφ² = (1 + 2s)/(2Bτs²) | Monte Carlo of a two-element cross-correlator on an unknown noise-like signal; the (1 + 2s) form follows from the Knapp & Carter (1976) coherence Cramér–Rao bound in the narrowband limit; its weak-signal limit σφ = 1/(√2·SNR) is Thompson, Moran & Swenson (2017) §6.2.4, eq. 6.64 | 8% | 3% |
| Radar (`Sensing.radar_snr`) | SNR = P_avg G² λ² σ t / ((4π)³ R⁴ k Ts) | Skolnik (2008) (chapter not verified; NAWCWD TP 8347 §4-5 eq. [1] gives the same form), independent dB form; 130 radar × hull × range cases | 1e-9 | 6e-15 |
| Radar range claim | — | LORE / tutorial "inside 13,000 km on 0.5 m²" (25 kW average) | 5% | 13,018 km |
| Radar angle (`Sensing.radar_angle_sigma`) | θ3/(k_m√(2 SNR)), k_m = 1.6 | Barton (2005) monopulse (k_m = 1.6 a typical value; MIT LL radar lectures, slide EST&TRACK-27) | 0.2% | 0.14% |
| Diffraction | 1.22 λ/D | First zero of J₁/π = 1.2197 (scipy) | 3e-4 | 2.4e-4 |

### Effects

| Model | Equation | Reference | Tolerance | Result |
| --- | --- | --- | --- | --- |
| Jammer J/S (`Effects._js_raw`, `js_db`, `jam_range_km`) | One-way jamming equation | Adamy (2001) EW 101 and the public-domain NAWCWD TP 8347 support-jamming equations (one-way form), independent dB form, 12 geometries; brentq for the range | 1e-9 dB | 3e-14 |
| Barrage spread (`spread_db`) | 10 log(B_band/B_ch) | DSN 810-005 Module 201 Rev. F: deep-space X uplink 7145–7190 MHz | 1e-9 dB | 16.53 dB |
| Coherent turnaround | f_up = f_down × 749/880 | CCSDS 401.0-B-32 Rec. 2.6.2; every downlink lands inside the uplink band | exact | exact |
| Beam pointing (`can_point`) | 1σ error < HPBW/2, HPBW = 70λ/D° | Balanis (2016) ch. 15; NAWCWD TP 8347 §3-1 (BW = 70λ/d) | decisions | 7 of 7 agree |
| Laser spot (`spot_m`) | R√((1.22λ/D)² + j²): 1.22λ/D from Hecht (2017), jitter added in quadrature (engineering approximation) | Airy first dark ring (scipy `jn_zeros`) | 3e-4 | 2.4e-4 |
| Dazzle range | irradiance = 10 W/m² | self-consistency; LORE 263,600 km | 100 km | 2 km |
| HPM reach (`hpm_range_km`) | E = √(30PG)/R | E = √(η₀S), η₀ = μ₀c (scipy), so the constant 30 is 29.98 rounded; ITU-R P.525-4 Annex §2.1 eq. (1) e = √(30p)/d | 1e-3 | 3.5e-4 |
| Kill vehicle Pk (`Effects.kill_probability`) | rel·(1 − exp(−r²/2σ²)) | scipy.stats.rayleigh CDF (circular bivariate normal miss is Rayleigh: Papoulis & Pillai 2002; DTIC AD1043284) | 1e-10 | < 1e-11 |
| Rocket equation (`RF.delta_v`) | vₑ ln(m₀/m₁) | Tsiolkovsky; every ship's Δv against LORE.md | 0.006 km/s | 0.0045 km/s |

### Infrared and tracking

| Model | Equation | Reference | Tolerance | Result |
| --- | --- | --- | --- | --- |
| Grey-body power (`RF.grey`) | εσT⁴A | astropy `BlackBody` integrated over 0.1 µm–10 cm | 1e-6 | 8e-11 |
| In-band share (`Thermal.band_fraction`) | Widger & Woodall (1976) series, 6–10 µm (same series: Lewis & McClarren 2025, arXiv:2503.08892, §3.1) | astropy `BlackBody` integrated, 60–3,000 K | 1e-6 | 6e-11 |
| Skin temperature (`Thermal.skin_T`) | εσT⁴A = leak + αSA/4 (sunlit) or leak (shadow) | Independent energy balance, every class | 1e-9 | 8e-11 |
| Radiators (`Thermal.radiator_T`, `radiator_I`) | Q = P_e(1/η − 1) = 2εσT⁴A; I = εσT⁴A·cosθ/π (+ edge) | Independent; JIMO design point (364 kWt, 170 m², 200 K sink; Siamidis 2005) | 1e-6; 2% | 1e-10; 1.1% |
| Intensity (`Thermal.intensity`) | Skin + radiator face + edge (+ nozzle), in band | Rebuilt from class data and geometry, 54 ship–aspect cases; Jupiter's shadow by cylinder | 1e-6 | 8e-11; 0 wrong |
| Visible magnitude (`Sensing.vis_mag`) | Sun's M_V 4.81 (Willmer 2018) to 1 AU and Jupiter's irradiance; Lambert sphere p·Φ(α)·r²/R², r² = A/4π (Madhusudhan & Burrows 2012 eq. 3; before 25 Oct 2026 the game used p·(A/4)·Φ/R², π times too bright) | Independent; Sun at 1 AU vs Torres (2010) −26.76 | 1e-6 mag; 0.03 mag | 5e-9; 0.002 |
| Heat sink (`Thermal.step`) | Stored += Q·dt while dark; vented water is used up | Energy conservation over 30 looks | 1e-9 | 0 wrong |
| False alarms (`Sensing._false_alarms`) | Poisson, mean 0.1 per sensor per look (design value) | scipy.stats.poisson 99.98% interval, 4,000 looks | interval | 1,217 vs mean 1,200 |
| Occultation (`Sensing.occulted`) | Segment–sphere | Dense sampling of 300 random lines | decisions | 0 wrong |
| Detection (`Sensing.ir_look`, `ir_sees`) | S/N = I/R²/(NEI·background), disc ×50, glare ×5; Pd = Φ(S/N − 5); sees = S/N ≥ 5 in IR or visible | Independent implementation, every sensor–target pair at the start; scipy.stats.norm | decisions; 1e-5 | 36 of 36 agree |
| Unscented update (`Track._update`) | Julier sigma points, κ = 0, circular mean for bearings | [filterpy](https://github.com/rlabbe/filterpy) 1.4.5 `UnscentedKalmanFilter`, `JulierSigmaPoints` | 1e-6 | 3e-12 |
| STM (`Track.stm`) | Central differences of the Kepler solver | Two-body variational equations, DOP853 | 1e-5 | 8e-10 |
| Full-model STM (`Gravity.coast_stm`, the tracker's covariance) | Variational equations flown with the orbit; gravity gradient by hand (point mass, J2, moons, Sun) | Central differences of scipy DOP853 coasts on hapsira's J2 and third-body terms, 3 ships over 6 h (one off the plane); in `run_tests.gd`, the gradient against differences of `accel` | 1e-5 (blocks scaled by the coast's length) | 2.9e-6; gradient 2e-10 |
| Covariance prediction | FPFᵀ + Q (white-noise acceleration) | filterpy `Q_continuous_white_noise` (Bar-Shalom et al. 2001 §6.2; Labbe, *Kalman and Bayesian Filters in Python* ch. 7) | 1e-4 | 4e-10 |
| Bearing-line fix (`Track.cross_fix`) | Weighted least squares | scipy `least_squares`; Fisher information inverse (AoA Fisher information as in Herath & Pathirana 2013, *Sensors* 13:12277) | 1 m; 1e-9 | 2e-5 m; 7e-14 |

## Fixes made to the game

Each fix was made in GDScript and in the JS mirror where one exists. The exporter was then re-run.

**Player-facing changes, listed first:**

| # | What | Before | After | Player effect |
| --- | --- | --- | --- | --- |
| 1 | **Moon ephemeris** (`Kepler.from_elements`, `positionFromElements`, `MOONS`). The mean motion came from Kepler's third law, √(μ/a³), which ignores J2 and the Laplace resonance. It now uses the observed sidereal period for the mean longitude and JPL's tabulated period for the mean anomaly. | Longitude error vs Horizons at the campaign start: Io 114°, Europa 1.6°, Ganymede 34.4°, Callisto 21.4° | 0.40°, 0.10°, 0.34°, 0.71° | **Significant.** At the start, Ganymede (and with it the scenario, which is laid out relative to Ganymede) sits 34° further round, Callisto 21° and Io 114°. Relative to Ganymede, Callisto (the handler) moves 13° and the civil traffic (absolute phases) 34°. The Godot tests still pass (73/0, 8/0). HYDRA's week-long moon perturbation changed from 825 km to 1,998 km. The scripted intercept still closes, at 33 km against 23 km before (the limit is 50 km). |
| 2 | **Interferometer DF σ** (`RF.df_sigma`, `dfSigma`). The phase CRB 1/√(2·SNR) was being fed the integrated radiometer SNR. For an unknown signal, the cross-correlation phase error is (1 + 2s)/(2Bτs²) ≈ 1/(2·SNR²) (confirmed by Monte Carlo). | 12 m baseline, X band: 106 / 61 / 19 µrad at SNR 10 / 30 / 300 (with the 20 µrad floor: 107 / 64 / 28) | 33 / 11 / 1.1 µrad (with the floor: 39 / 23 / 20) | **Significant.** Ship DF fixes get 2–3× tighter, and most are now limited by the 20 µrad design floor. The station's 200 m array was already floor-limited and is unchanged. The database window's "DF σ at SNR 30" falls with it. |
| 3 | **Barrage spread** (`Effects.UPLINK_BAND_HZ`). The deep-space (Category B) X uplink is 7145–7190 MHz. 7190–7235 MHz is Category A. | 90 MHz, 19.54 dB | 45 MHz, 16.53 dB | **Significant.** Barrage jamming reaches 1.41× further (3 dB). Spot jamming is unchanged. |
| 4 | **Radar angle σ** (`Sensing.radar_angle_sigma`). Changed to the monopulse form. | θ3/√SNR | θ3/(1.6√(2 SNR)), 2.26× smaller | Moderate. Radar tracks get a tighter cross-range. Range (50 m) is unchanged. |
| 5 | **Lambert long-way transfers** (`Kepler.stumpff_c`, `stumpffC`). 1 − cos√z lost all precision as z → 4π², which made every transfer over 180° fail. The fix uses the half-angle form 2 sin²(√z/2)/z. | 63 of 129 test transfers had no solution, all those over 180°, including 27 of the 30 from WARDEN to campaign ships | All solved, within 1.9e-12 of Izzo | Moderate. Intercepts and pocket transfers that need the long way round are now possible. Any plan the game could already make is unchanged. |

**Accuracy fixes with no effect on balance:**

| # | What | Before | After |
| --- | --- | --- | --- |
| 6 | Hyperbolic propagation over long coasts: the start of Newton's method now follows Vallado (2013) Algorithm 8 | 30-day hyperbolic coast diverged (\|r\| ≈ 10⁶² km) | 1.7e-13 relative |
| 7 | Kepler's equation for e near 1: Danby's starter, 50 iterations | e = 0.99, M = 11°: 83% position error | 5e-15 |
| 8 | 64-bit maths in place of Godot's 32-bit `Vector2` (laser spread, DF floor, tracker range measurement, bearing-fix normals) | Range measurement rounded to about 0.06 km at 10⁶ km (the size of the radar's σ); dazzle range out by 1e-7 | Double precision. Dazzle range 263,602.14 → 263,602.13 km |
| 9 | JS radar aperture efficiency 0.6 → 0.55, to match Godot and its database window | JS: 15,292 km on 0.5 m² | 14,641 km (same as Godot) |

**Source-audit fixes (25 Oct 2026):**

| # | What | Before | After |
| --- | --- | --- | --- |
| 10 | **Reflected sunlight** (`Sensing.vis_mag`). A Lambert sphere's flux ratio is p·Φ(α)·r²/R² (Madhusudhan & Burrows 2012 eq. 3), with r² = A/4π for the hull's total area A. The game had p·(A/4)·Φ/R², the cross-section πr² in place of r²: π times (1.24 mag) too bright. `test_ir.py` had copied the same expression, so it could not catch it. | Visible 1 m detection ranges (thousand km): GADFLY 680, CROW 833, WREN 481, WARDEN 2,150, PFS 3,709, HMH-5 5,865 | 384, 470, 271, 1,213, 2,093, 3,309 (×0.564 = 1/√π). **Player-facing:** sunlit ships are found by telescope at a little over half the distance. |
| 11 | **Fragment area-to-mass** (`Breakup._draw_chi`). The bimodal large-object law holds above 11 cm only; between 8 and 11 cm the NASA Standard Breakup Model blends it linearly in λc with the small-object law (Frey & Colombo 2021, *JGCD* 44(1), App. B eqs. B5–B8). The minimum fragment size stays 0.10 m, so 0.10–0.11 m fragments now use the blend. | Bimodal law from 0.10 m | Blend between 8 and 11 cm. Small effect on play. |
| 12 | **Free-space loss reference** (`test_rf.py`, `published_values.json`). ITU-R P.525-4 eq. (4) uses 32.4, not 32.45; the game uses the exact eq. (3) form, 32.4478. | Test bound 0.005 dB against a misquoted 32.45 | Bound 0.05 dB against the published 32.4 (difference 0.048 dB). No game change. |
| 13 | **Aluminium specific heat** (`Thermal`, 897 J/(kg·K)) is now cited to NIST-JANAF (Chase 1998: 24.20 J/(mol·K) at 298 K). Incropera's Table A.1, cited before, gives 903 at 300 K. | — | No game change. |

Refactors that keep the public API: `Sensing.link_snr`, `Sensing.radar_snr`, `Sensing.radar_angle_sigma` and `Effects.kill_probability` were extracted from inline code so the suite can call them, and `RF.df_sigma` gained an optional `n = Bτ` argument.

## Known simplifications and their bounds

| Simplification | Bound / size | Status |
| --- | --- | --- |
| Moons are planar mean-element ellipses: no inclinations, no mutual perturbations | Planar error ≤ 23,000 km (Callisto) over the campaign; ≤ 10,000 km out of plane; ≤ 0.72° in longitude, 2036–2046 | Bounded in `test_moons.py` |
| Jupiter GM from the fact sheet | 3.7e-6 relative | Bounded |
| Element clock ignores leap seconds and TT − UTC | 69.2 s (Io 0.16°) | Bounded |
| IR: grey bodies in band (no spectral emissivity, no reflected sunlight in 6–10 µm, no specular glints) | Reflected sunlight is 0.24% of S in 6–10 µm (REALISM-SOURCES §2) | Design simplification |
| Radiators lie flat to the game's plane, so every observer sees their edge; temperatures change at once (no thermal lag) | — | Design simplification (stated in the simplifies note) |
| Visible telescopes look only where Blue holds a track (narrow-field imagers, ~100 s stares) | — | Design simplification |
| Red plans with S/N ≥ 5 (expected detection); Blue's looks roll Pd | — | Design simplification |
| **Fixed sidelobe and main-lobe gains** (−12 / 33 dBi, `towardUsDbi`) | — | **To be replaced by ITU envelopes, see REALISM-SOURCES §8** |
| Laser irradiance: P over the first-null disc (with jitter) | True on-axis peak is 2.3× higher (equivalent Strehl ratio 0.44); a perfect optic would dazzle out to about 399,000 km | Conservative, reported as INFO |
| Aperture efficiency 0.55 everywhere | 1.2 dB below DSN's 34 m | Conservative |
| No radar losses; detection on SNR alone | — | Design simplification |
| DF assumes broadside (σ grows as 1/cos θ off axis) and both elements of the array at the ES dish's gain | — | Design simplification |
| Kill-vehicle reach = divert × t/2; Pk uses the circular 1σ major axis | — | Design value (LORE) |
| HPM constant 30 for η₀/4π = 29.98 | 0.035% in reach | Bounded |
| ITU-R P.525-4 eq. (4)'s rounded 32.4 dB vs the exact eq. (3) constant 32.4478 dB | 0.048 dB | Bounded |

## For other owners

These are outside the files this pass owned. They are left for their owners:
- `godot/data/campaign.json`: three texts still say "uplink 7145–7235 MHz" or "barrage spreads it over 90 MHz" (`effects.jam.note`, `database.ccss.basis`, `sources.dsn810`).
- `godot/ui/database_window.gd` `_jam_line()` hard-codes `90e6` and "over 90 MHz". It should use `Effects.UPLINK_BAND_HZ`.
- `src/content/why.js` (`kepler3`) says the game moves the moons by T = 2π√(a³/GM). It now moves them at their observed rates; Kepler's law still agrees to 0.1%.
