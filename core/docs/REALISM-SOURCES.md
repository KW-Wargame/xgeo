# xGEO realism sources: beams, heat, TDOA/FDOA, intercept, ECCM

Research for the next set of mechanics. Compiled 2026-10-23. Nothing here changes code or data; it records what the most credible available sources say, how sure we can be, the simplest faithful game model, and where the current game disagrees.

**Verification labels used below**
- **[V-text]**: I fetched the document and read the passage; the section, table or page is given.
- **[V-record]**: I confirmed the work exists (publisher, DOI or official listing) but could not read the passage cited (paywall, 403, or book). The equation is the standard form reproduced in the textbooks; its exact equation number in the original is not confirmed.
- **UNVERIFIED**: I could not confirm it. Do not treat it as sourced.
- **Derived**: I computed it from verified inputs; the script logic is stated so it can be re-run.

Line numbers in the conflicts section are as of this reading. Other agents are editing `godot/core/*.gd` now, so they may have moved.

---

## 1. Antenna beam geometry: main lobe, sidelobes, intercept and jamming

### Model

**Boresight gain and beamwidth.** A reflector of diameter D at wavelength λ has peak gain
`G0 = η (π D / λ)²` (η = aperture efficiency, typically 0.55 to 0.7).
Its half-power (3 dB) full beamwidth is `θ3dB ≈ 70 λ / D` degrees.
- ITU-R SA.509-3 §1.3 gives `G0 = 10 log[η (πD/λ)²]` dBi and the half-beamwidth `φ0 = 20√3 / (D/λ)` degrees, so the full beamwidth is 69.3 λ/D [V-text].
- NAWCWD TP 8347 §3-1 (p. 3-1.1) gives "Parabolic antenna beamwidth: BW = 70 λ/d" [V-text].

**Off-axis gain (sidelobe envelopes).** The ITU reference patterns are the most credible public source. They are envelopes of the sidelobe peaks, used for interference coordination. Real antennas have nulls between the peaks and can sit below the envelope in many directions (SA.509-3, considering b and c).

| Pattern | Applies to | Gain G(φ), φ in degrees off boresight | Status |
|---|---|---|---|
| ITU-R SA.509-3 (12/2013) §1.1, single entry | Space-research earth stations and radio astronomy, D/λ ≥ 100, 1–30 GHz | G0 − 3(φ/φ0)² for φ < φ1; G0 − 17 for φ1 ≤ φ < φ2; **32 − 25 log φ** for φ2 ≤ φ < 48°; −10 (48–80°); −5 (80–120°, spillover); −10 (120–180°). φ1 = φ0√(17/3); φ2 = 10^((49 − G0)/25) | [V-text] |
| ITU-R SA.509-3 §1.2, multiple entry (aggregate) | same | as above with G0 − 20, **29 − 25 log φ**, then −13 / −8 / −13 dBi | [V-text] |
| ITU-R S.465-5 recommends 2 | FSS earth stations, 2–30 GHz | **32 − 25 log φ** for φmin ≤ φ < 48°; −10 dBi for 48–180°; φmin = max(1°, 100 λ/D) | [V-text] |
| ITU-R S.465-5 Note 4 | D/λ ≤ 100 | **52 − 10 log(D/λ) − 25 log φ** for 100λ/D ≤ φ < 48°; **10 − 10 log(D/λ)** for 48–180°. Note 2: "use with caution … for antennas with D/λ less than 50" | [V-text] |
| ITU-R S.1428-1 | FSS earth stations, 10.7–30 GHz, 20 ≤ D/λ ≤ 100 | Gmax = 20 log(D/λ) + 7.7; main lobe Gmax − 2.5×10⁻³(Dφ/λ)²; G1 = 29 − 25 log(95λ/D); 29 − 25 log φ to 33.1°; −9 dBi to 80°; then −5 dBi 80–180° (20 ≤ D/λ ≤ 25), or −4 dBi 80–120° and −9 dBi 120–180° (25 < D/λ ≤ 100). A separate pattern covers D/λ > 100 | [V-text] |
| ITU-R S.672-4 | Space-station (satellite) antennas, design objective | Near sidelobes LN = −20 or −25 dB below peak; far sidelobe **LF = 0 dBi**; back lobe LB = max(15 + LN + 0.25 Gm + 5 log z, 0) dBi | [V-text] |

**What these give for the dishes in the game (derived, η = 0.55):**

| Dish | f | D/λ | HPBW 70λ/D | G0 | S.465 Note 4 far-sidelobe floor |
|---|---|---|---|---|---|
| 0.8 m (jam victim, "33 dBi") | 7.18 GHz | 19.2 | 3.65° | 33.0 dBi | −2.8 dBi |
| 1.0 m (Red TT&C class) | 8.43 GHz | 28.1 | 2.49° | 36.3 dBi | −4.5 dBi |
| 1.5 m (Warden ES / CCS-S) | 8.43 GHz | 42.2 | 1.66° | 39.8 dBi | −6.3 dBi |
| 3 m (handler) | 7.18 GHz | 71.8 | 0.97° | 44.5 dBi | −8.6 dBi |
| 12 m (Ganymede Station ES) | 8.43 GHz | 337 | 0.21° | 57.9 dBi | −10 dBi (SA.509) |
| 1 m Ka crosslink | 32.1 GHz | 107 | 0.65° | 47.9 dBi | −10 dBi |

At Ka band (32 GHz) the SA.509-3 envelope is extrapolated slightly beyond its stated ~30 GHz limit (S.465-5 likewise covers "2 to about 30 GHz").

S.465 Note 4 for an 0.8 m dish at 7.18 GHz gives about +21.7 dBi at 5° off axis, +14.2 at 10°, +6.6 at 20°, +2.2 at 30° and −2.8 dBi beyond 48° (derived).

**Intercepting a downlink (ES).** At the ear, `Pr = Pt · Gt(θe) · Gr(θr) · (λ / 4πR)²` (Friis 1946 [V-record]; NAWCWD TP 8347 §4-3, one-way radar equation, p. 4-3.1 [V-text]). Here θe is the angle at the emitter between its boresight (toward its handler) and the ear, and θr is the angle at the ear between the ear's boresight and the emitter. Both gains matter. An ear with a big dish hears only what lies inside its own beam.

**Jamming an uplink.** The jammer has to get into the victim's receive pattern. The one-way jam-to-signal ratio at the victim receiver is Friis applied twice:

`J/S = [Pj · Gj · Gv(θj) / Rj²] / [Ps · Gs · Gv(0) / Rs²] · min(1, Bv / Bj)`

In dB: `J/S = ERPj − ERPs − 20 log Rj + 20 log Rs + Gv(θj) − Gv(0) − 10 log(Bj/Bv)`, where:
- Gv(θj) is the victim antenna's gain toward the jammer, at angle θj off the victim's boresight (which points at its handler).
- Gv(0) is the main-lobe gain toward the handler.
- The last term is the bandwidth factor: spot (Bj ≈ Bv) versus barrage (Bj ≫ Bv).

This is the communications (one-way) form of NAWCWD TP 8347 §4-9 "Side lobe jamming to signal ratio (for SOJ/SIJ)" (p. 4-9.1). That form carries Gr(SL)/Gr(ML) and the bandwidth factor BF = 10 log(BWJ/BWR) [V-text]. The NAWCWD version is the radar case, with the signal's two-way R⁴ and σ terms; for a comms link both paths are one-way. Adamy, *EW 101* (Artech 2001) presents the comms J/S in this dB form [V-record; page not checked].

**How much J/S is enough** has no universal number. NAWCWD §4-7 (p. 4-7.3): "the effectiveness of EA is not a direct mathematical function of J/S"; the J/S needed depends on the technique and the victim [V-text]. The game's +6 dB is already labelled a design value. That is correct, and it should stay labelled.

### Recommended parameters

| Parameter | Value | Source |
|---|---|---|
| Beamwidth | 70 λ/D deg (69.3 λ/D) | NAWCWD §3-1; SA.509-3 §1.3 |
| Large-dish pattern (D/λ ≥ 100) | SA.509-3 single-entry | ITU-R SA.509-3 |
| Small-dish pattern (D/λ 20–100) | S.465-5 Note 4, or S.1428-1 (strictly 10.7–30 GHz) | ITU-R |
| Spacecraft antenna far sidelobes | 0 dBi design objective (LF) | ITU-R S.672-4 |
| Jammer, uplink, handler EIRPs | **No public figures.** CCS/Meadowlands power and EIRP are not published (L3Harris and USSF releases describe frequency range, weight and automation only). | Defense News 2025-04-15 [V-record]; L3Harris |

### Confidence and limits
- Friis geometry and beamwidth: high.
- Sidelobe levels: medium. The ITU patterns are peak envelopes for coordination, so they are conservative (high) for a well-designed antenna. A low-sidelobe military antenna can do much better, but its patterns are not public.
- Real jammer EIRPs: not public. Any value is an extrapolation.

### Simplest faithful game model
1. Add one function, `gain_dbi(D, f, φ_deg, eta)`. It returns `G0 − 3(φ/φ0)²` inside the main lobe and the S.465 Note 4 envelope outside it (or SA.509 when D/λ ≥ 100).
2. Give every TT&C emitter a boresight: the unit vector to its handler or relay.
3. ES: replace `towardUsDbi` with `gain_dbi(emitter dish, f, angle(handler, ear))`. Also apply `gain_dbi(ear dish, f, angle(ear pointing, emitter))` for the ear (see §4).
4. Jamming: replace `sideDbi` with `gain_dbi(victim dish, f, angle(handler, jammer) seen from the victim)`.
5. Optionally, subtract a per-class "pattern quality" margin below the envelope (design value, for example 0–10 dB). This represents low-sidelobe design and nulls; label it as a design value.

---

## 2. Heat budget and IR stealth

### Model

**Energy balance.** Each surface or radiator i balances heat in against heat out:

`Q_internal + α_s · S · A_sun + Q_planet = Σ ε_i σ (T_i⁴ − T_sink⁴) A_i F_i`

(Stefan–Boltzmann; σ = 5.670374419×10⁻⁸ W m⁻² K⁻⁴, CODATA.) Between steady states, `m c dT/dt` (sensible) or `m L` (latent, phase-change) stores the imbalance.

**Inputs at Jupiter**

| Quantity | Value | Source |
|---|---|---|
| Solar irradiance at Jupiter | **50.26 W m⁻²** | NASA GSFC Jupiter Fact Sheet (updated 2 Oct 2024) [V-text] |
| Jupiter "black-body temperature" (fact sheet) | 109.9 K (with Bond albedo 0.343) | NASA fact sheet [V-text]. This is the equilibrium temperature of a body with no internal heat. It is **not** what Jupiter emits. |
| Jupiter emitted thermal power | **14.098 ± 0.031 W m⁻²** (Cassini epoch), Bond albedo 0.503 ± 0.012, internal heat 7.485 W m⁻² | Li et al. 2018, *Nat. Commun.* 9:3709, Table 1 [V-text] |
| Jupiter effective (emission) temperature | 124.4 ± 0.3 K (Voyager IRIS) | Hanel et al. 1981, *JGR* 86:8705 (abstract) [V-text]; **125.6 K** derived from Li et al.'s 14.098 W m⁻² |
| Jupiter view factor from a plate facing it at Ganymede's orbit (1.0704 Mkm) | sin²(3.83°) = 0.0045 | Derived (geometry). Planet IR loading on radiators there is negligible (~0.06 W m⁻²). |

**Surface optical properties** (NASA RP-1121, Henninger 1984, GSFC; average measured values; α_s = solar absorptance, ε = normal emittance) [V-text]:

| Surface | α_s | ε |
|---|---|---|
| Vapor-deposited aluminium | 0.08 | 0.02 |
| Vapor-deposited silver | 0.04 | 0.02 |
| Vapor-deposited gold | 0.19 | 0.02 |
| Second-surface mirror, silver backing (Helios) | 0.07 | 0.79 |
| Silver-backed film (Teflon type; the table layout in the scan is ambiguous about thickness) | 0.08–0.09 | 0.81–0.88 |
| Carbon black paint NS-7 | 0.96 | 0.88 |

**What this implies (derived).** A sun-facing plate with an insulated back reaches `T = (α S / (ε σ))^¼`. At Jupiter:
- vapor-deposited aluminium: 244 K
- silver-backed mirror (OSR, Helios α 0.07 / ε 0.79): 94 K (the 0.08/0.81 Teflon-type film gives 97 K)
- black paint: 176 K

Low-ε shiny metal gets warmer in sunlight than black paint, because α/ε is large. A cold, low-ε stealth hull therefore has to be shaded, or it has to dump its heat through radiators turned away from the observer.

**Reactor waste heat** [V-text]:
- Space Brayton systems "tend to optimize at efficiencies of about 20 to 25 percent with radiator temperatures in the 400 to 600 K range" (Siamidis et al., NASA/TM-2005-213337, abstract).
- JIMO (Mason, NASA/TM-2003-212596): **100 kWe** design, Brayton cycle 21.7%, end-to-end 20.2%, so **496 kWt** of reactor power. Studies scaled the design from 20 to 200 kWe.
- JIMO heat rejection: 364 kWt rejected by **170 m²** of two-sided radiator, ε 0.9, NaK 556 K in and 399 K out, 200 K effective sink (Siamidis 2005 §II, §IV). That is an effective radiator temperature of about 457 K (derived).
- Kilopower/KRUSTY ground test (2018): ~25% overall system efficiency, ~35% Stirling component efficiency, 1.5–5 kWt (Poston et al. 2020, *Nucl. Technol.* 206; via abstract and search summary) [V-record].
- Derived: a 200 kWe plant at 20–25% rejects **600–790 kW**. That takes ~460–600 m² of radiator at 400 K (ε 0.9), or ~190–250 m² at 500 K.

**Laser waste heat.**
- Industrial Yb fibre lasers exceed 30% wall-plug efficiency, and the best commercial units exceed 50% (Laser Focus World, trade press) [V-record].
- Review: Zervas & Codemard 2014, *IEEE JSTQE* 20(5):219 [V-record; efficiency figures not read].
- Lockheed Martin's 2014 30 kW SBC fibre laser was described only as using "approximately 50 percent less electricity than alternative solid-state laser technologies" [V-text]. There is no wall-plug number for any weapon-class system in a verified public source.
- The game's 25% system efficiency (3 MW of waste per 1 MW of beam) is conservative and defensible.

**Heat storage** [V-text]:

| Medium | Latent heat | Source |
|---|---|---|
| Paraffin waxes (CnH2n+2) | 155–253 kJ/kg | Choi 2012, NASA GSFC (PCM for LHP compensation chamber) |
| n-hexadecane (flown, IceCube CubeSat 2017) | 235 kJ/kg at 18 °C | Choi 2018, NASA GSFC |
| n-pentadecane | ~200 kJ/kg | Leimkuehler et al. 2011, NASA JSC |
| Water ice (fusion) | 333 kJ/kg | Leimkuehler et al. 2011 |
| Water evaporated (consumable, vented) | ~2,500 kJ/kg | Leimkuehler et al. 2011 |

Derived: one 600 s HEL-1M shot (1.8 GJ of waste heat) needs 9 t of paraffin, 5.4 t of ice, or 0.72 t of water vented.

**Aspect-dependent signature.**
- A diffuse (Lambertian) surface's intensity falls as the cosine of the angle from its normal (NAWCWD TP 8347 §7-1, "Infrared source characteristics", ~p. 7-1.11) [V-text].
- So a flat radiator face radiates `I(θ) = ε σ T⁴ A cosθ / π` W sr⁻¹. Edge-on, only its edge area shows.
- A convex hull radiating uniformly averages `ε σ T⁴ A / 4π`, which is the game's current isotropic form. That form is right for a sphere and wrong for a radiator.

**Sensor bands and sensitivity: NEO Surveyor, the game's own reference** (Mainzer et al. 2023, *PSJ* 4:224) [V-text]:
- NC1 = 4.0–5.2 µm and NC2 = 6–10 µm, on a 50 cm telescope.
- "Since we plan to extract point sources at an S/N of 5 or greater…": NESI5 is 110–280 µJy in NC2 and 65–120 µJy in NC1. It is set by the zodiacal background over the field of regard, and each observation is 180 s, built from 30 s exposures.
- Zodiacal background at 1 AU is 1,700–22,000 nW m⁻² sr⁻¹ in NC2 and 220–4,200 in NC1.
- Derived (flat-Fν approximation over 6–10 µm, Δν = 2.0×10¹³ Hz): NESI5 ≈ **2.2–5.6×10⁻¹⁷ W m⁻² in-band**, so the 1σ in-band NEI is ≈ 0.4–1.1×10⁻¹⁷ W m⁻².

**Background at Jupiter.**
- Scattered zodiacal light "is not significantly detectable at r > 3 au" (Matsumoto et al. 2018, *AJ* 156:86, Pioneer 10, B and R bands) [V-text].
- Mid-IR thermal zodiacal emission at 5.2 AU: **UNVERIFIED**. I found no measured value. The dust density and temperature are lower there, so it is expected to be below 1-AU levels, but how far below is not established.
- Jupiter's disc in 6–10 µm, as a grey body at 125.6 K (derived approximation; Jupiter's real spectrum has bands and 5 µm "hot spots"): ~1.4×10⁻² W m⁻² sr⁻¹. That is 650–8,500 times NEO Surveyor's zodiacal background.
- For a background-limited sensor, noise scales as √background, so a target seen against the disc has NEI × **26–92** (derived).
- Off-disc stray light depends on the telescope's design. There is no public number.

**Reflected sunlight** (derived from a 5772 K solar spectrum):
- 54% of 50.26 W m⁻² (~27 W m⁻²) falls in 0.4–0.9 µm. That is the light a visible telescope (GEODSS-type) uses to find satellites.
- 0.24% (~0.12 W m⁻²) falls in 6–10 µm. A 50 m² diffuse surface with IR reflectance 0.9 would return ~1.7 W sr⁻¹ in NC2, ten times the in-band thermal emission of Vesper's hull (0.16 W sr⁻¹, below).
- A polished low-ε surface reflects specularly, though, so it produces a glint only in one direction.

### Detection becomes probabilistic
- **IR (Gaussian noise, single look):** `Pd = Φ(SNR − k)` with threshold k·σ. At k = 5 (NEO Surveyor's S/N ≥ 5), Pfa ≈ 2.9×10⁻⁷ per resolution element. Pd is 0.16 at SNR 4, 0.50 at SNR 5, 0.84 at SNR 6 and 0.98 at SNR 7 (derived).
- **Radio and radar (Albersheim 1981):** `SNR_dB = −5 log N + [6.2 + 4.54/√(N + 0.44)] · log10(A + 0.12AB + 1.7B)`, with `A = ln(0.62/Pfa)` and `B = ln(Pd/(1 − Pd))`. This holds for a non-fluctuating target in Gaussian noise with a linear detector (MathWorks `albersheim` documentation, citing Richards 2005 and Skolnik 2001) [V-text for the form; my fetch tool rendered the √ ambiguously; the original is Albersheim, *Proc. IEEE* 69(7):839, 1981, V-record].
  - Derived, for N = 1: Pd 0.5 / Pfa 10⁻⁶ needs 11.2 dB; Pd 0.9 / Pfa 10⁻⁶ needs 13.1 dB; Pd 0.98 / Pfa 10⁻³ needs 12.0 dB.
  - The last value matches the NAWCWD nomograph example (Pd 98%, Pn 10⁻³, 12 dB; §5-2, p. 5-2.3) [V-text].
  - Validity limits often quoted (Pfa 10⁻⁷ to 10⁻³, Pd 0.1 to 0.9, error < 0.2 dB): **UNVERIFIED** (Richards 2005 not read).
- **Typical minimum S/N** (NAWCWD §5-2 Table 1, p. 5-2.2) [V-text]:

  | Use | Minimum S/N |
  |---|---|
  | Skilled operator | 3–8 dB |
  | Auto-detection | 10–14 dB |
  | Auto-detection with amplitude, TOA and frequency measurement | 14–18 dB |
  | Phase-interferometer AOA | 14–18 dB |
  | Amplitude-comparison AOA | 16–24 dB |

### Confidence
- High: Stefan–Boltzmann, solar flux, Jupiter's emission, coating properties, Brayton and JIMO numbers, PCM heats, the NEO Surveyor bands and threshold.
- Medium: the in-band NEI conversion (flat-Fν approximation).
- Low: Jupiter-disc band radiance (a grey-body approximation) and zodiacal background at 5.2 AU (unmeasured in my sources).

### Simplest faithful game model
- Each class gets a **hull** (ε_h, A_h, convex) and a **radiator** (ε_r, A_r, a normal direction).
  - Each tick, the radiator temperature comes from `Q_waste(t) = εσT⁴A` (steady state). Optionally, a heat store (kg × kJ/kg) absorbs bursts, such as laser shots, and bleeds out.
  - Hull temperature comes from solar input and a small internal load.
- The observer sees `I = I_hull + I_rad · max(0, cos θ)`, with each term multiplied by its **in-band fraction** (the Planck integral over 6–10 µm, precomputable per temperature).
- `SNR = I / R² / NEI_inband`, then `Pd = Φ(SNR − 5)` per look. Background × 26–92 against the disc (a design value inside that derived range).
- Optional: a visible-band channel for sunlit, diffuse targets.

---

## 3. Geolocation by TDOA and FDOA

### Model
- **TDOA** between sensors i and j: `Δτ_ij = (|r − s_i| − |r − s_j|) / c`. Each measurement puts the emitter on a hyperboloid.
- **FDOA:** `Δf_ij = −(f/c) · [d|r − s_i|/dt − d|r − s_j|/dt]`. It gives range-rate differences, so it constrains velocity as well.
- DSN 810-005 Module 202 (Rev. D, eq. 12) states the one-way Doppler/range-rate relation: σ_f = (f_C/c) σ_V one-way, (2f_C/c) σ_V two-way [V-text].
- **Solvers:** Ho & Chan 1997 (*IEEE TAES* 33(3):770–783, known altitude). Ho & Xu 2004 (*IEEE TSP* 52(9):2453–2463), an algebraic moving-source solution that reaches the CRLB at moderate noise (Crossref abstract) [V-record].
- **Cramér–Rao bounds** (Stein 1981, *IEEE TASSP* 29(3):588–599) [V-record; equation numbers not checked, form as reproduced in secondary sources]:
  - `σ_TDOA = 1 / (β √(B T γ))` and `σ_FDOA = 1 / (T_e √(B T γ))`.
  - β = rms bandwidth (≈ πB/√3 for a flat spectrum); T_e = rms duration (≈ πT/√3); B = noise bandwidth; T = integration time.
  - `1/γ = ½ (1/γ1 + 1/γ2 + 1/(γ1γ2))` combines the two sensors' SNRs.
  - Readable corroboration: Fowler, M. L., EECE 522 Notes 15 "ML for TDOA/FDOA" (Binghamton University), slide 8 "Stein's CRLB for TDOA" gives σ_TDOA ≥ 1/(2πB_rms√(BT·SNR_eff)) and σ_FDOA ≥ 1/(2πT_rms√(BT·SNR_eff)); for a flat band B_rms = B/√12, so 2πB_rms = πB/√3 = β (and likewise T_e). Slide 9 notes that Stein states rather than derives these. The SNR combination is consistent with the Knapp & Carter (1976) coherence bound (|γ12|² = s1s2/((1+s1)(1+s2)); derived) [V-text for the slides].
- **Derived example:** a 2 MHz BPSK burst over 120 s at effective input SNR −20 dB gives σ_TDOA ≈ 0.18 ns (5 cm) and σ_FDOA ≈ 3×10⁻⁶ Hz.
  - Thermal noise is therefore **not** what limits accuracy for long bursts. The limits are clocks and knowledge of the sensors' own positions and velocities: Ho, Lu & Kovavisaruch 2007, *IEEE TSP* 55(2):684–696, "in the presence of receiver location errors" [V-record].
  - 1 m of sensor-position error is 3.3 ns of TDOA error.

### Clocks, relaying and light-time
- **Clocks.**
  - NASA's Deep Space Atomic Clock showed 3×10⁻¹⁵ long-term stability over 23 days and drift of 3.0(0.7)×10⁻¹⁶ per day (Burt et al. 2021, *Nature* 595:43) [V-record, from abstract and press summaries].
  - Conventional space clocks accumulate ~1 ns per day (APS *Physics* summary) [V-record].
  - Absolute synchronisation between platforms needs two-way time transfer. GPS does not exist at Jupiter, so **this is a real constraint**.
  - **No public number exists** for the time-transfer accuracy achievable between Jovian platforms. Use a design value.
- **Relaying recordings.** Cross-correlation needs both raw recordings in one place: complex samples at ≥ B per second (Shannon 1949, *Proc. IRE* 37:10 [V-record]; readable: E. Modiano, MIT OCW 16.36, Lecture 2, sampling theorem [V-text]). A 2 MHz burst over 120 s at 8-bit I/Q is ~480 MB per sensor (derived, assuming 8-bit samples, a design value). That costs crosslink time.
- **Light-time.** 1 Mkm is 3.34 s (c exact, SI). Recordings from sensors a few Mkm apart arrive seconds late, and the fix is for the burst's epoch.

### Real systems
- HawkEye 360 uses clusters of three LEO satellites flying in formation (the Pathfinder was 3 × 13.4 kg launch wet mass, on SFL's 15 kg-class NEMO bus) with wideband SDRs, multilaterating emitters by TDOA/FDOA. The satellites are spaced ~125 km along-track and use synchronised GPS receivers. Sources: Sarda et al., IAC-18-B4.4.1 abstract [V-text]; ESA eoPortal [V-text].
- **HawkEye 360 geolocation accuracy numbers: UNVERIFIED.** I found no quantitative figure in a verified source.

### Simplest faithful game model
- Two or more ears hear the same burst, and their recordings are relayed to one node (a time cost from the datalink). Each ear pair then yields one TDOA line (a hyperbola in-plane) with σ = √(σ_CRLB² + σ_clock² + σ_pos²/c²). σ_clock and σ_pos are design values, stated as such.
- Add FDOA for range-rate.
- A cheap version: feed TDOA/FDOA as additional measurement types into the existing Kalman `Track`, next to bearings.

---

## 4. Receiver scheduling and probability of intercept

### Model
- **POI.** For a receiver that revisits a channel or beam position with period T_r, dwells T_d, and faces a signal of duration τ that starts at random, the chance one burst is caught is roughly `min(1, (τ + T_d − t_min) / T_r)` per channel. Here t_min is the minimum time on signal needed for detection. Over n independent opportunities, `P = 1 − (1 − p)ⁿ`.
  - This is the standard window-coincidence form. Rigorous treatments: Self & Smith 1985, "Intercept time and its prediction", *IEE Proc. F* 132(4):215 [V-record]; Clarkson, Perkins & Mareels 1996, *IEEE Trans. Inf. Theory* 42(3):959–971 (number-theoretic intercept-time solutions) [V-record]; Wiley, *ELINT* (Artech 2006) [V-record]. The expression above is my simplified statement. **Its exact equation in those works is UNVERIFIED.**
- **Channelized (FFT) versus scanning receivers.** A digital channelizer covers its whole instantaneous bandwidth (IBW) at once, so frequency POI is 1 inside the IBW. A scanning superhet covers B/F of the band at any instant.
- **Modern IBW.** AMD Zynq UltraScale+ RFSoC (DS889) has 14-bit RF-ADCs at up to 5–5.9 GS/s, inputs to 6 GHz (Gen 3) or 7.125 GHz (DFE), and ~2.5 GHz of Nyquist bandwidth per ADC at 5 GS/s [V-record; DS889 table summarised by search, not read line by line].
  - The whole deep-space X-band downlink allocation (8400–8450 MHz, **50 MHz**; DSN 810-005 Module 201 Rev. F, deep-space bands table [V-text]) fits ~50 times over.
  - So **frequency scanning inside one deep-space band is not a realistic constraint for a 2041 receiver.** The constraints that are real:
    - **Spatial:** a 12 m dish has a 0.21° beam, a 1.5 m dish 1.66° (§1).
    - **Bands:** S, X and Ka are 2.3, 8.4 and 32 GHz, so one front end does not cover all three.
    - **Recording and relay capacity.**
    - **Processing:** the detection SNR needed (§2).

### Simplest faithful game model
- Each ear has a pointing direction and beamwidth 70λ/D, plus optionally a low-gain, wide-field antenna (for example a horn at ~15–20 dBi; design value) for cueing. Detection uses the dish gain only if the emitter lies inside the beam; otherwise the low-gain antenna's gain applies.
- The player schedules dish pointing (which sector or which track), not frequency. Bands are a second axis if Ka/S emitters exist.
- POI then emerges from geometry and burst timing instead of a formula.

---

## 5. Red adaptation (ECCM) and uncertain effects assessment

### Spread spectrum and frequency hopping
- Processing gain `PG = (S/N)out / (S/N)in = 2 B_sin T_s` for DS. For FH against interference that fills the hopping band, PG equals the ratio of the hopping bandwidth to the information bandwidth (ITU-R SM.1055-0 (1994) §3, eqs. (2) (DS) and (3) (FH); "the most important parameter of an SS system") [V-text].
- A smart FH system "may even note which hops contain interfering signals" (SM.1055 §4) [V-text].
- Effect on J/S: the required J/S rises by PG. A 2 MHz command link spread over the 45 MHz deep-space uplink allocation gains ≤ 13.5 dB (derived).
- The USSF *Space Warfighting* framework lists "changing radio frequencies used for satellite communications" and "frequency hopping" as forms of manoeuvre (p. 14) [V-text].

### Adaptive nulling
- Lincoln Laboratory's 43.5–45.5 GHz spaceborne nulling antenna produced "broadband nulls at least **30 dB** deep with a resolution of about **0.1°**". Nulling systems achieve "interference rejection of several tens of decibels in a fraction of a second" (Cummings 1992, *Lincoln Lab. J.* 5(2):173, abstract and p. 173) [V-text].
- Nulling needs at least two sensors or elements. Power-inversion algorithms null stronger jammers more deeply. Very-low-duty-cycle pulsed jamming can exploit the slow un-adaptation, but coding and interleaving defeat it (same source) [V-text].
- Game consequence: nulling works only if the jammer is more than ~the nulling resolution away from the handler direction, as seen by the victim.

### Power control and burn-through
- Burn-through is where S overcomes J at the minimum effective J/S (NAWCWD §4-8, p. 4-8.x) [V-text].
- For comms, the handler can raise its EIRP or narrow its beam. J/S falls by the same number of dB.

### Switch to optical
- NASA DSOC (on Psyche) [V-text]:
  - 267 Mb/s from 31 million km on 11 Dec 2023 (JPL DSOC mission page).
  - Data downlinked from **494 million km** on 3 Dec 2024 (JPL DSOC mission page).
  - 13.6 Tb received in total; concluded 2 Sep 2025 (JPL DSOC mission page). The June 2023 fact sheet predates these results and planned an end in October 2025.
  - 22 cm flight aperture on an isolation-and-pointing assembly. A Table Mountain uplink laser served as both data uplink and pointing beacon; downlink went to the 5.1 m Hale telescope with a superconducting nanowire photon-counting receiver.
- Final-pass rates of 12.4–20.8 Mb/s near 2.3 AU come from press reporting quoting the project (The Register 2025) [V-record].
- Derived: a 22 cm aperture at ~1 µm has a diffraction half-angle to the first null of 1.22λ/D ≈ 5.5 µrad, so the beam radius is ~5.5 km (about 11 km across) per Mkm. An eavesdropper or jammer has to sit inside it. Laser wavelength: **UNVERIFIED** (the fact sheet says "near-infrared").
- Pointing needs a beacon and a large receiver.

### Home-on-jam and jammer geolocation
- A jammer is the loudest emitter in the band. One-way propagation means Red hears it from far beyond the range at which it is effective (NAWCWD one-way equation §4-3) [V-text]. Red can DF and TDOA it like any other emitter, so §3 applies in reverse.
- Doctrine expects this. Among JEMSO tasks in support of space operations, JP 3-85 lists exploit capabilities that locate emitters jamming satellite links (p. I-10, para 1.d.(2)(a)) [V-text]. It defines direction finding as taking bearings on RF emitters with a highly directional antenna (pp. III-15 and GL-6), and "precision geolocation" as managing friendly assets to geolocate threat RF systems for targeting (p. B-4, para 2.d.(5)) [V-text]. **None of the three doctrine documents mentions TDOA or FDOA by name.**

### Self-interference and look-through
- Transmitting and receiving at once in the same band is limited by self-interference, which is "one of the biggest practical impediments" to in-band full duplex (Sabharwal et al. 2014, *IEEE JSAC* 32(9):1637) [V-record; numeric isolation figures not read].
- Look-through (periodic jammer pauses to monitor the victim) is standard practice (Adamy *EW 101/102* [V-record]; US Patent 5,321,405 (1994), background, describes periodically interrupting jamming to measure the victim signal [V-record, search-only]). **Specific look-through duty cycles: no public number found.**
- The CCS-S jams the 7.1 GHz uplink while ES listens at 8.4 GHz downlink. Being out of band, it is far less affected. The degree of filter isolation is a design value.
- Doctrine treats friendly interference as a force-level coordination problem, not a matter of receiver physics [V-text, JP 3-85]:
  - JEMSO exist partly to "avoid friendly fire electromagnetic attack incidents" (p. x).
  - Space-support management tasks include deconflicting satellite EMS use to reduce EMI and friendly-fire EA (p. I-11, para 1.d.(2)(d)).
  - EMCON is defined as minimising detection by enemy sensors, *mutual interference among friendly systems*, and enemy interference with deception (p. GL-9).
  - The joint restricted frequency list (JRFL) has three categories. TABOO frequencies are never to be jammed by friendly forces. PROTECTED frequencies are friendly ones shielded from inadvertent friendly jamming. GUARDED frequencies are enemy ones being exploited, which are jammed only after the commander weighs the gain against the loss of intelligence (p. III-8).
  - The EM attack control authority (EACA) is the authority to order EM energy transmitted or stopped (pp. II-2–II-3).
- **The documents say nothing on look-through, or on a platform's own jammer deafening its own receivers.** The same-platform isolation question stays with the engineering sources above.

### Effects assessment
- The USSF framework (p. 17): "For effective assessment, indicators should be developed at the same time as the objectives, effects, and tasks they measure … Indicators should be either directly observable or be reliably inferred." It also says assessing space superiority "is challenging" [V-text].
- Space link interdiction is non-kinetic and includes electromagnetic attack (p. 9) [V-text].

**Reversible effects (JP 3-85, 22 May 2020) [V-text]**
- EA can destroy, degrade, disrupt or deceive. The first three are denial effects on "a continuum of temporary to permanent and partial to complete" (p. B-1, para 2.a).
- Degradation may last seconds or the whole operation, and a proficient operator may work around it (p. B-1, para 2.a.(2)).
- Disruption "temporarily interrupts" a system. A trained operator may defeat it with EP such as changing frequency (pp. B-1–B-2, para 2.a.(3)). Advanced EA can disrupt "nondestructively" (p. B-2).
- Offensive EA often suppresses a threat "for only a limited period of time" (p. I-7, para 1.c.(2)(a)).
- The word "reversible" does not appear in JP 3-85, JP 3-60 or AFDP 3-60. The doctrinal concepts are "temporary" effects and "nonlethal" effects. The USSF *Space Warfighting* framework does use the word: "reversible, temporary effects" (p. 5) and "reversible or nonreversible" actions (p. 9).

**EW assessment (JP 3-85) [V-text]**
- After each JEMSO execution cycle, the JEMSO cell (JEMSOC) assesses EMSO effectiveness against the MOEs and MOPs in the JEMSO appendix (p. IV-4, para 3.a).
- The MOE assessment is "technically focused", analysing cause and effect. It includes collateral damage due to EA (p. IV-5, para 3.a.(2)).
- EA in the air tasking order should be synchronised with it "to enable EW assessments and improve BDA accuracy" (p. IV-5).
- BDA teams should include, or have access to, someone trained in JEMSO/EW, so they can judge whether EW actions succeeded (p. II-5, para 2.b.(2)(i)).
- ES and SIGINT "perform an important combat assessment role" by giving feedback on the results of friendly attacks (pp. III-16–III-17, para 3.n.(1)).
- Assessment data feed EW reprogramming (p. IV-5, para 3.b.(4)).

**Combat assessment (JP 3-60, 28 Sep 2018, App. D; AFDP 3-60, 1 May 2026) [V-text]**
- Combat assessment (CA) is phase 6 of the joint targeting cycle. It has three elements (JP 3-60 p. D-1, para 2.a):
  - BDA;
  - munitions effectiveness assessment (MEA);
  - reattack recommendations or future targeting.
- Phase 6 also outputs a collateral damage assessment (JP 3-60 p. II-32; AFDP p. 26).
- BDA has three phases (JP 3-60 pp. D-1–D-4; AFDP p. 26):
  - Phase I: physical damage/change, often from a single source.
  - Phase II: functional damage/change. This is *inferred* from the physical damage plus all-source intelligence, and must include an estimate of recuperation time (p. D-3).
  - Phase III: target-system assessment.
- Each physical assessment is given a confidence of **confirmed, probable or possible** (p. D-2). The enemy's camouflage, concealment and deception can distort it (p. D-2).
- Indicators and collection plans should be prepared in advance, "especially if the damage/change cannot be directly observed" (p. D-3, para (b)5).
- MEA compares actual against predicted effectiveness to change tactics or weapons (p. D-5).
- A reattack recommendation compares what was done (BDA) and how (MEA) against the MOEs set at the start of the cycle (p. D-5).
- When data are missing, assessors carry a *predicted* effect as a placeholder probability. They update it as each step in the chain is confirmed: tasked, released, engaged (pp. D-6–D-7, para 2.b).
- Measures and indicators (MOEs, MOPs) should be relevant, observable, responsive and resourced. They are built in phase 1, alongside the objectives (JP 3-60 p. II-4, para 3.a.(3)). AFDP lists them in the air operations directive (p. 20).
- JP 3-60 does not define MOE or MOP itself. It refers to JP 5-0 (p. D-7, para 3.b), which was not read.
- Metrics can be objective (directly observed) or subjective (indirect). Success is measured by "indications" that effects are changing activity (p. D-7, para 3.a).
- **Non-kinetic effects are hard to see (doctrine says so plainly):**
  - For nonlethal effects, the target must be assessed continuously, because the effects can take days, weeks or months to show (JP 3-60 p. II-31, step 6).
  - Nonlethal direct effects "may not be so immediate or easily recognizable" (JP 3-60 p. II-35, para 5.e.(1)).
  - AFDP: "The initial effects of non-kinetic operations are often subtle or may be of short duration". Full effects may take days or months to emerge, "if at all" (p. 21).
  - Functional characteristics "may not be directly observed" (AFDP p. 5).
- Faithful model (now doctrine-backed): separate the **measure of performance** (J/S achieved: Blue knows its own EIRP, and the geometry is known to track accuracy) from the **measure of effectiveness** (did the target lose its orders?). The MOE is inferred only from observable indicators: the target stops responding to handler bursts, repeats its requests, changes frequency, or manoeuvres off-plan. Each inference carries a confidence. Doctrine's confidence words are confirmed, probable and possible (JP 3-60 p. D-2), and its estimate is updated step by step (pp. D-6–D-7).

### EW terms and divisions (JP 3-85) [V-text]
- JP 3-85 (2020) replaced JP 3-13.1 *Electronic Warfare* (p. v). It renamed "electronic warfare" to **electromagnetic warfare** (EW) and electronic attack/protection to electromagnetic attack/protection (pp. GL-6, GL-8, GL-9).
- JEMSO are military actions to exploit, attack, protect and manage the electromagnetic operational environment (p. I-1, para 1.b.(1); p. GL-10). As a crisis escalates, they shift from access coordination to EMS superiority (p. I-1, para 1.a.(2)).
- EMS superiority is control of the spectrum enough to operate "without prohibitive interference" while affecting the enemy's ability to do the same (pp. I-4–I-5, para 1.b.(10); p. GL-8).
- EW has three divisions: EA, ES and EP (p. I-5, para 1.b.(12)).
  - **ES**: search for, intercept, identify, and locate or localise sources of radiated EM energy, for threat recognition, targeting and planning (p. I-6, para 1.c.(1)(b); p. GL-8). ES differs from SIGINT by who tasks it and why (p. I-6). ES effects are *detect* and *exploit* (collect, characterise, locate, track) (p. B-2, para 2.b).
  - **EA**: EM energy, directed energy or antiradiation weapons used to degrade, neutralise or destroy combat capability. EA "is considered a form of fires" (p. I-7, para 1.c.(2); pp. I-13 and GL-6).
    - Jamming is the deliberate radiation, reradiation or reflection of EM energy to deny the enemy effective use of the EMS (p. GL-7).
    - EM intrusion inserts energy into transmission paths to deceive or confuse (p. GL-7).
    - Deception presents false inputs to sensors or data links (p. B-2, para 2.a.(4)). JP 3-85 never uses the word "spoofing"; doctrine's terms are intrusion and deception.
  - **EP**: protecting friendly forces from any effects of EMS use, friendly or enemy, or from natural phenomena (pp. I-7–I-8, para 1.c.(3)). Its listed examples include:
    - frequency agility and spread spectrum;
    - *multispectral low-observability (stealth)*;
    - EM hardening;
    - EMCON.
  - Under JP 3-85, the game's stealth ships are practising EP.
- Space (p. I-10, para 1.d.(2)) lists JEMSO tasks in support of space operations:
  - locate satellite-link jammers;
  - deceive, disrupt and degrade enemy uplinks, downlinks and crosslinks;
  - harden friendly links against EMI;
  - deconflict to avoid friendly-fire EA.
- Most system degradation comes from EMI (p. I-10). EMI may be intentional (EA) or not (p. I-10).
- The JEMSOC is the CCDR/JFC's standing staff element to "plan, coordinate, execute, and assess JEMSO" (p. II-10, para 3.a.(1)).
- Maneuver in the EMS means changing power, frequency, direction and waveform (p. I-13, para 3.d). EP can thwart disruption, and EW reprogramming is driven by assessment (pp. B-1, IV-5). This is the doctrinal basis for Red adaptation (Q14).

### How doctrine maps onto the game
Kill-chain terms are from JP 3-60 (2018) unless marked. AFDP 3-60 calls F2T2EA "colloquially" the kill chain, and says it applies to non-kinetic means including the EMS and space (p. 29).

| Game step | Doctrinal term | Cite | Where the game diverges |
|---|---|---|---|
| **Hear** (UI "Heard" / Find) | F2T2EA *Find*: detect an "emerging target". ES *search/intercept*; ES effect *detect* | JP 3-60 pp. II-24–II-26; JP 3-85 pp. I-6, B-2 | The find pill is always lit (`campaign_window.gd:56`). Doctrine's Find also sorts detections into target, not-a-target, or pass to deliberate targeting (Fig. II-12). |
| **Locate** (DF; UI "Located" / Fix) | *Fix*: "a position determined from terrestrial, electronic, or astronomical data". DF; precision geolocation | JP 3-60 pp. II-26–II-27; JP 3-85 pp. III-15, B-4, GL-6 | Doctrine's Fix outputs **PID and** an engagement-quality location (p. II-27). The game takes identification as a separate later step. |
| **Track** (UI "Following") | *Track*: maintain continuity; if lost, repeat fix | JP 3-60 pp. II-27–II-28 | Consistent. |
| **Identify** (UI "Enemy confirmed" / Target) | PID can come from "electronic warfare support systems" or visual recognition. CID must be complete before engagement | JP 3-60 p. II-22, para 3.e.(2)(a) | The game uses this step as the **Target** pill. In doctrine, *Target* is the decision step: validation against the law of war, ROE, no-strike list and collateral damage; selecting an option; submitting assessment requirements (pp. II-28–II-30). See Q18. |
| **Close in** | No doctrinal step. Part of Target (select engagement option) and phase 5 mission planning/force execution. EMS maneuver | JP 3-60 pp. II-21–II-22, II-29; JP 3-85 p. I-13 | Game-specific. Physics (J/S rising 6 dB per halving of range) drives it, not process. |
| **Look closer** | CID / PID by visual recognition. "Correlation and fusing of data" confirms identity | JP 3-60 pp. II-22, II-27 | Consistent. "Signal and picture should agree" is all-source correlation. |
| **Attack** (Engage) | *Engage*. EA as a form of fires; jamming; EACA authorises transmission | JP 3-60 pp. II-30–II-31; JP 3-85 pp. I-7, I-13, II-2–II-3 | The engage pill lights from true jam state (`jammed_until`), not from "engagement ordered". |
| **Effect** | EA effects destroy/degrade/disrupt/deceive. DE to disrupt or destroy. Cyberspace payloads delivered by EA | JP 3-85 pp. B-1–B-3, I-10 | The game's jam is a binary "loses its orders". Doctrine has a temporary-to-permanent, partial-to-complete continuum (p. B-1). |
| **Assess loop** | F2T2EA *Assess* (initial, BDA phase I), then phase 6 CA: BDA (I–III), MEA, reattack | JP 3-60 pp. II-31–II-32, D-1–D-7; AFDP pp. 25–27 | The assess pill lights from `campaign.neutralized()`, which reads Red's true AI state. Doctrine assesses with confidence from indicators. See Q13, Q17. |
| **ROE / escalation** | ROE gate the Target step. "Escalation of force guidance" in ROE helps "avoid raising the level of conflict unnecessarily". DE supports escalation-of-force efforts | JP 3-60 pp. II-17, II-28–II-29; AFDP pp. 8–10; JP 3-85 pp. IV-1, B-3 | Doctrine gives no escalation ladder or points. The escalation meter (per-act values, war at 100) remains a design value. |

The UI labels in this table are as of the first reading. Following Q18 (§8.1) and the 25 Oct 2026 source audit, the plain-word labels are to follow JP 3-60: *Fix* means located **and identified** (PID is acquired during Fix, p. II-27), and *Target* is the decision step (cleared to act after validation, ROE and the no-strike check, pp. II-28–II-30), not "Enemy confirmed".

## 6. LPI waveforms and specific emitter identification
- **LPI: detection below noise.**
  - An energy (radiometer) detector finds an unknown signal by integrating: its detectability grows with the time-bandwidth product (Urkowitz 1967, *Proc. IEEE* 55(4):523) [V-record]. The game's `√(Bτ)` rule is this detector. Readable corroboration: the radiometer equation σ_T ≈ T_s/√(Δν τ) (Condon & Ransom, *Essential Radio Astronomy*, NRAO online edition, ch. 3, §3.6.2 eq. 3.154) [V-text]; the game's Pd = Q((Q⁻¹(Pfa) − d)/√(1+2s)) matches the Gaussian energy-detector statistics in Rashid & Nanzer 2024, arXiv:2403.19556, §II eqs. (2)–(3) [V-text].
  - Cyclostationary (spectral-correlation) detection exploits modulation-induced periodicities. It separates signals from noise and from each other at low SNR (Gardner 1991, *IEEE SP Mag.* 8(2):14) [V-record].
  - Radar-LPI reference: Pace, P. E. (2009), *Detecting and Classifying Low Probability of Intercept Radar*, 2nd ed. (Artech) [V-record].
- **SEI (RF fingerprinting).** Transmitters can be identified individually by unique characteristics of their analog circuitry (Danev, Zanetti & Čapkun 2012, *ACM Comput. Surv.* 45(1):6, abstract [V-text]). Deep-learning SEI: Riyaz et al. 2018, *IEEE Commun. Mag.* 56(9):146; Merchant et al. 2018, *IEEE JSTSP* 12(1):160 [V-record]; readable example of the same technique: Sankhe et al. 2019, ORACLE, arXiv:1812.01124 (CNN fingerprinting of 16 individual USRP radios, abstract) [V-text]. **Accuracy figures and the SNR needed: UNVERIFIED** (not read). The game's `classifySnr` gate (identification needs a high-SNR recording) is a DESIGN VALUE, consistent with the SEI literature's report that accuracy degrades at low SNR; it is not a Danev finding (the Danev abstract does not mention SNR).

---

## 7. Conflicts with the current game: questions for the user

Each item gives the current behaviour, what the source says, and options with their gameplay consequence.

**Q1. ES ears hear every direction at full dish gain.**
- Now: `sensing.gd:294` (and the `_listen`/`on_air` paths) uses `RF.dish_gain(esm.dish)` for any emitter direction.
- Source: the beamwidth is 70λ/D, so 0.21° for the 12 m dish and 1.66° for 1.5 m (NAWCWD §3-1; SA.509-3). Outside the beam, gain drops to sidelobe levels (−10 dBi far out).
- Options:
  - (a) Keep, documented as "ears are assumed to be staring multi-beam arrays". Consequence: no pointing gameplay.
  - (b) Add dish pointing plus a low-gain cueing antenna. Consequence: this becomes the scheduling/POI mechanic; detections get rarer and positioning matters more.
  - (c) Keep omnidirectional detection, but credit dish gain only for analysis (DF/classify) of a cued signal.

**Q2. Emitter gain toward Blue is a fixed −10 to −15 dBi.**
- Now: `towardUsDbi` in `game.json:285` (Vesper −15) and `campaign.json` classes (crow −10, gadfly −15).
- Source: ITU envelopes for 1–1.5 m dishes give far sidelobes of about −3 to −6 dBi (S.465 Note 4), satellite antennas a 0 dBi far-sidelobe objective (S.672-4), and +10 to +20 dBi within 5–10° of boresight. Envelopes are upper bounds; low-sidelobe designs can do better, but no public data exist.
- Options:
  - (a) Keep, and relabel the value as "below the ITU envelope: assumes a low-sidelobe military antenna (design value)".
  - (b) Use the angle-dependent envelope. Consequence: Red is heard 7–15 dB louder far off-axis (intercept range ×2.2–5.6), and enormously louder near the Red-to-handler line, so a buoy placed on that line hears the main lobe.
  - (c) Envelope minus a fixed design margin, such as 6–10 dB.

**Q3. The victim's receive gain toward the jammer is a fixed −12 dBi.**
- Now: `campaign.json:51` `rx.sideDbi`, used at `effects.gd:78`.
- Source: for the 0.8 m, 33 dBi antenna the game assumes (D/λ = 19), S.465 Note 4 gives +14 dBi at 10°, +2 dBi at 30° and −2.8 dBi beyond 48°. S.465 Note 2 warns that the reference pattern is unreliable for D/λ < 50.
- Options:
  - (a) Keep, relabelled as a design value.
  - (b) Angle-dependent gain. Consequence: J/S is +9 to +26 dB better than now, so jamming works from 3–20 times farther, and the geometry (getting near the handler's line of sight) becomes the skill.
  - (c) Envelope minus a margin.
- Related: should the handler's transmit gain also drop when the target is off its boresight (pointing error from the handler's own tracking)?

**Q4. The X-band uplink band is wrong.**
- Now: `effects.gd:31–32` (`UPLINK_BAND_HZ = 90e6`, comment "7145–7235 MHz"), the `campaign.json:51` jam note, and `campaign.json:142` (`dsn810`).
- Source: DSN 810-005 Module 201 Rev. F, bands table: deep-space X uplink **7145–7190 MHz**; 7190–7235 MHz is the near-Earth (< 2 Mkm from Earth) uplink. The X/X turnaround 880/749 is correct (Module 201 Table 1) [V-text].
- Options:
  - (a) Change to 45 MHz. The barrage spread becomes 16.5 dB instead of 19.5 dB, so barrage jamming is 3 dB stronger.
  - (b) Keep 90 MHz, but say Red at Jupiter is not bound by Earth-centred ITU allocations (fiction), and fix the citation text either way.

**Q5. IR detection compares bolometric output to an in-band NEI.**
- Now: `sensing.gd:74–99` and `rf.gd:72–80` use εσT⁴A/4π (all wavelengths) against NEI 7.3×10⁻¹⁶ (`game.json:764`, "NEO Surveyor").
- Source: NEO Surveyor detects in 6–10 µm at S/N ≥ 5, with NESI5 ≈ 2.2–5.6×10⁻¹⁷ W m⁻² in-band per 180 s (derived from Mainzer 2023). A 140 K body puts only 0.78% of its power in 6–10 µm; a 110 K body 0.09%; a 290 K body 22%.
- Derived detection ranges, game versus in-band at SNR 5:

  | Target | Game | In-band, SNR 5 |
  |---|---|---|
  | Vesper | 169,000 km | 54,000–86,000 km |
  | Moth | 60,000 km | 6,600–10,000 km |
  | Gadfly | 279,000 km | 198,000–316,000 km |
  | PFS | 5.4 Mkm | 7.9–12.6 Mkm |
  | HMH-5 | 10.6 Mkm | 17.8–28.4 Mkm |
  | NTR-25 plume | 6.0 Mkm | 6.6–10.5 Mkm |

- Options:
  - (a) Keep, and document the NEI as an "effective bolometric NEI" that is not NEO Surveyor's (fix the LORE/database claim).
  - (b) In-band model. Consequence: cold stealth gets much stronger (Moth nearly invisible beyond 10,000 km), warm ships are seen farther, and `why.js:45` ("seen from about 170,000 km") changes.
  - (c) Keep the bolometric form but tune the NEI per target-temperature class (not recommended: hides the physics).

**Q6. Detection is a deterministic threshold.**
- Now: IR uses SNR ≥ 1 (`sensing.gd:99`); radio uses ≥ 10 (`game.json:772`); DF uses any heard intercept (`sensing.gd:335`).
- Source: NEO Surveyor extracts at S/N ≥ 5. Albersheim needs 13.1 dB for Pd 0.9 at Pfa 10⁻⁶. NAWCWD Table 1 gives 10–14 dB for auto-detection and 14–18 dB for interferometer AOA.
- Options:
  - (a) Keep thresholds, but raise IR to 5 and DF to ~25 (14 dB).
  - (b) Probabilistic Pd with a false-alarm rate (false tracks appear). Consequence: uncertainty, and repeated looks matter.
  - (c) Probabilistic Pd without false alarms (simpler).

**Q7. There is no reflected sunlight and no visible-band detection.**
- Now: optical is used only for identification (`sensing.gd`, the `visibleLambda` block).
- Source: 27 W m⁻² of sunlight in 0.4–0.9 µm at Jupiter. GEODSS-class telescopes (the game's own lineage) find satellites by reflected sunlight. Low-ε metals reflect 90%+ (specularly: glints).
- Options:
  - (a) Keep, and document "Blue's visible telescopes are ID-only (simplification)".
  - (b) Add a visible detection channel with phase angle and a glint term. Consequence: sunlit Red ships become findable, shadow and Jupiter-eclipse become tactics, and Vesper's chined hull (glint control) gains a purpose.

**Q8. Vesper's thermal state is not an energy balance.**
- Now: `game.json` Vesper sig T 140 K, ε 0.08, A 150 m² radiates 261 W in total, with no solar input or internal load.
- Source: a low-ε metal surface in Jupiter sunlight equilibrates at ~210–245 K (Henninger α/ε; derived). Its own transmitter, avionics and an idle NTR must reject heat somewhere.
- Options:
  - (a) Keep, and state that Vesper rides behind a sunshield and dumps waste heat through radiators turned away from Blue (a narrative simplification).
  - (b) Model hull plus pointed radiator (§2). Consequence: Vesper's stealth depends on aspect; flanking it, or being near its radiator normal, finds it.
- Also, `why.js:45` says "a dull coating". Low emissivity means a shiny, metallic finish; dull or matte finishes are usually high-ε.

**Q9. Reactor waste heat is missing from the signatures.**
- Now: Warden sig 190 K, ε 0.2, 400 m² gives 5.9 kW in total, yet the database credits a "200 kWe fission reactor (JIMO lineage)" (`campaign.json` sentinel and pfs entries; `jimo` source line 136).
- Source: JIMO's baseline was **100 kWe** (20.2% efficient, 496 kWt), with 364 kWt rejected from 170 m² at ~400–556 K (Mason 2003; Siamidis 2005). A 200 kWe plant rejects 600–790 kW.
- Options:
  - (a) Add the radiator waste to the signature. If face-on, Warden is ~11 times brighter (radius ×~11) unless the radiators are edge-on; aspect becomes central.
  - (b) Keep, saying the reactor idles at low power except when the radar or laser runs (state the idle power as a design value).
  - (c) Fix the "JIMO = 200 kWe" wording either way.

**Q10. Laser heat bookkeeping is inconsistent.**
- Now: `sensing.gd:79` adds 3 MW into the whole-hull `sig.A` (1,200 m², ε 0.85, base 260 K), while the database says 2,288 m² of radiator at 400 K. `effects.gd` sets `laser_hot_until = t + 1 h` regardless of the shot. No heat storage.
- Options:
  - (a) Keep, and document it.
  - (b) A radiator plus heat-store model. Consequence: shot duration, cooldown and IR bloom follow from storage mass (for example 9 t of paraffin per 600 s shot).

**Q11. Jupiter's "blackBodyK" is 109.9 K.**
- Now: `game.json:16`. I found no use in `godot/core`.
- Source: that is the fact-sheet equilibrium value; Jupiter emits 14.1 W m⁻², T_eff ≈ 125 K (Li 2018; Hanel 1981).
- Option: if it is ever used as an IR background, use 14.1 W m⁻² (125.6 K), or relabel the field "equilibriumK". Consequence: none until it is used.

**Q12. The glare factor is ×25 within 3 Jupiter angular radii.**
- Now: `game.json:765–766`.
- Source: there is no direct source. The derived on-disc background-limited penalty is ×26–92 (NC2, against 1-AU zodiacal levels); off-disc stray light is design-specific.
- Options:
  - (a) Keep ×25, labelled as a design value at the low end of the derived on-disc range.
  - (b) Split into on-disc ×50 (design value inside 26–92) and off-disc halo ×3–10 (design value).

**Q13. Jamming success is known instantly and for certain.**
- Now: `effects.gd:374–375` posts "jam_hit" ("it would lose its orders") the moment J/S ≥ need.
- Source: the USSF framework (p. 17) says indicators must be observable or reliably inferred. J/S is a measure of performance; loss of command is not directly observable.
- Doctrine [V-text]:
  - Functional damage is *inferred*, with a stated confidence: confirmed, probable or possible (JP 3-60 pp. D-2–D-3).
  - Indicators are needed when the effect "cannot be directly observed" (p. D-3).
  - Nonlethal effects must be assessed continuously and can take days to months to show (p. II-31).
  - Reattack is generally not recommended on phase I BDA alone, except after a confirmed miss (p. II-31).
  - AFDP: non-kinetic effects are "often subtle or may be of short duration" (p. 21).
  - JP 3-85: EW MOEs are assessed after each execution cycle (pp. IV-4–IV-5).
- Options:
  - (a) Keep, but reword the message to "J/S achieved (MOP)".
  - (b) Uncertain assessment: an effect probability, plus indicators (target misses expected responses or manoeuvres off-plan) that build confidence over time. Report it as possible → probable → confirmed (JP 3-60 p. D-2). Consequence: the player has to decide under uncertainty.

**Q14. Red never adapts.**
- Now: fixed frequency, unspread BPSK, no nulling.
- Source: frequency hopping and frequency change are named USSF manoeuvre options (p. 14). SS processing gain is 2BT (ITU-R SM.1055). Spaceborne nulling reaches ≥ 30 dB with 0.1° resolution (Cummings 1992). Optical links are flown (DSOC).
- Doctrine [V-text, JP 3-85]:
  - EP examples include frequency agility and spread spectrum (p. I-8).
  - A trained operator "may be able to thwart disruption" by EP such as changing frequency (pp. B-1–B-2).
  - Degradation can be worked around by a proficient operator (p. B-1).
  - EMS maneuver means changing power, frequency, direction and waveform (p. I-13).
  - JP 3-85 is US doctrine about friendly EP, but it describes exactly the counters Red would use.
- Options:
  - (a) Keep Red static (a simpler teaching game).
  - (b) Escalating Red responses after it detects jamming: hop (+PG), then null (−30 dB J if the jammer is more than the resolution off the handler line), then optical. Consequence: an arms race; spot jamming loses value against hopping, and geometry matters for nulling.

**Q15. Planned frequency-scan scheduling.**
- Source: modern ADCs (RFSoC, ~2.5 GHz IBW per ADC) cover the whole 50 MHz deep-space X downlink at once (DS889; DSN 810-005 Module 201).
- Options:
  - (a) Build scheduling on dish pointing and bands (S/X/Ka) rather than frequency within X.
  - (b) Keep frequency scanning and justify it with an older or narrower receiver (a design value, which weakens the realism claim).

**Q16. The radiometer integration assumes perfect knowledge of the burst.**
- Now: `rf.gd:44` integrates exactly the burst's band and duration.
- Source: Urkowitz's energy detector assumes known band and interval; an unknown burst in a channelizer suffers mismatch.
- Options:
  - (a) Keep, as a small documented optimism.
  - (b) Add a fixed mismatch loss of 1–3 dB (design value).

**Q17. The kill-chain pills read ground truth.**
- Now: `campaign_window.gd:56`. The *engage* pill reads the target's true `jammed_until`, `dazzled_until`, `captured` and `disabled`. The *assess* pill reads `campaign.neutralized()` (`campaign.gd:26`), which checks Red's true AI state (`aborted`, `missed`, `spent`).
- Doctrine [V-text]:
  - Assess is an estimate drawn from observations, with a confidence (JP 3-60 pp. II-31, D-2, D-6–D-7).
  - AFDP asks "Are we measuring the right things?" (p. 25).
- Options:
  - (a) Keep, labelled as an umpire's view.
  - (b) Drive *engage* from "engagement ordered and transmitted" (p. II-30), and *assess* from Blue's assessed belief, shown as possible/probable/confirmed. The truth is revealed in the after-action review.
  - (c) Do (b), and keep the truth visible only on an easy difficulty setting.

**Q18. Identification sits in the wrong step.**
- Now: the *target* pill ("Enemy confirmed") lights when the track is classified hostile, and ROE then allow fire.
- Doctrine [V-text, JP 3-60]:
  - PID is an *output of Fix* (pp. II-22, II-27), and may come from EW support systems.
  - *Target* is the decision step: validation against the law of war, ROE, no-strike list and restricted target list; selecting the engagement option; submitting assessment requirements (pp. II-28–II-30).
- Options:
  - (a) Relabel. Fix = location plus PID. Target = the player's engage decision, passing the ROE check, with an option chosen.
  - (b) Keep the game's order, and document it as a teaching simplification.

**Q19. Jamming has no intelligence cost.**
- Doctrine [V-text]: GUARDED enemy frequencies are exploited for intelligence. They are jammed only after the commander weighs the operational gain against the loss of technical information (JP 3-85 p. III-8).
- Now: I found nothing in the game that makes jamming Red's link cost Blue intelligence. **Not checked exhaustively.**
- Options:
  - (a) Keep, and document it.
  - (b) Once jammed, Red goes quiet or changes frequency, so the player can lose a signal they were exploiting. This ties into Q14.

**Q20. Collateral effects of barrage jamming.**
- Doctrine [V-text, JP 3-85]:
  - TABOO frequencies (including distress and safety) are never to be jammed by friendly forces, and PROTECTED friendly frequencies are shielded from friendly jamming (p. III-8).
  - EW MOEs include collateral damage assessment due to EA (p. IV-5).
  - JEMSO aim to avoid friendly-fire EA incidents (pp. x, I-11).
- Now: barrage jamming covers the deep-space X uplink band, which civil and allied users also use. Whether the game charges a civil or allied cost for this is **not checked**.
- Options:
  - (a) Keep, and document it.
  - (b) Barrage jamming also disrupts civil and allied uplinks in the band, which costs escalation and appears in the debrief as collateral effects.
  - (c) Add a simple JRFL: some civil channels are TABOO, and barrage must notch them, at a cost in J/S.

**Fact fix (no decision needed).** The EW console says "ELECTRONIC ATTACK" (`ew_console.gd:165`). Since JP 3-85 (2020) the US joint term is *electromagnetic* attack (p. GL-6). `GAME-DESIGN.md` and `LORE.md` already use "electromagnetic".

---

## 8. What could not be verified
- HawkEye 360 geolocation accuracy figures.
- Exact equation numbers in Stein 1981, Self & Smith 1985, Clarkson 1996, Wiley *ELINT* and Adamy (books and paywalled; forms stated are the standard ones).
- The three doctrine texts have now been read from copies the user supplied (see §5 and bibliography 9–11). They are still silent on the following:
  - TDOA/FDOA;
  - look-through;
  - own-platform jammer-to-receiver isolation;
  - the words "spoofing" and "reversible" (the USSF *Space Warfighting* framework, by contrast, does speak of "reversible, temporary effects" and "reversible or nonreversible" actions, pp. 5, 9);
  - any escalation ladder.
- JP 3-60 was read in its 28 Sep 2018 edition. AFDP 3-60 (p. 3, fn. 8) says JP 3-60 was updated in 2024. **The 2024 edition was not read**, so the 2018 page cites may not match it.
- JP 5-0 (the MOE/MOP definitions that JP 3-60 p. D-7 points to) was not read.
- CCS/Meadowlands power and EIRP. They are not public, and no figure exists to verify.
- Mid-IR zodiacal background at 5.2 AU, and Jupiter's band-resolved brightness temperatures (the grey-body figure is an approximation).
- Albersheim validity limits; the DSOC laser wavelength; SEI accuracy numbers; numeric self-interference isolation; look-through duty cycles.

---

### 8.7 Solar system, shadows and interplanetary flight (25 Oct 2026)

- **Planets.** All eight planets come from JPL's approximate Keplerian elements: Table 1 for 1800–2050, otherwise Tables 2a and 2b for 3000 BC–3000 AD (E. M. Standish & J. G. Williams, *Keplerian Elements for Approximate Positions of the Major Planets*, JPL Solar System Dynamics, https://ssd.jpl.nasa.gov/planets/approx_pos.html). "Earth" in those tables is the Earth–Moon barycentre, and the game uses it as such. `godot/core/ephem.gd` turns them into Jupiter-centred positions in the game frame (Jupiter's equator, IAU pole) and caches them on a cubic-Hermite grid every 6 h. The cache adds under 1 km.
  - **Checked against JPL Horizons.** `tools/verify/fetch_planets.py` fetched Horizons vectors for every planet in two windows: 2030–2050 every 73 days, and 2060–2199 every 199 days (Horizons has no Jupiter-centred data past 2200). `test_planets_vs_horizons` passes when the error stays inside 1.5 × the error JPL states for the body plus the one it states for Jupiter.
  - **Masses and sizes.** GM values come from DE440 (Park et al. 2021). That includes the Sun, 132,712,440,041.279 km³/s². Radii come from the IAU WGCCRE 2015 report (Archinal et al. 2018, Table 4; Table 1 is the pole and rotation table and Table 2 the satellites). The paper is paywalled (free read through Springer's SharedIt link, https://rdcu.be/b32V4); the readable copy of the same values is NAIF's generic PCK pck00011.tpc, `BODY199`–`BODY899_RADII` (e.g. `BODY599_RADII = 71492 71492 66854`) [V-text]. The solar radius is the IAU 2015 nominal value, 695,700 km (Resolution B3).
- **Gravity of the Sun and planets.** The integrator still works in a Jupiter-centred frame (Cowell's method). It adds each third body's direct pull and the indirect term for Jupiter's own acceleration toward it (O. Montenbruck & E. Gill, *Satellite Orbits*, Springer 2000, §3.3 [V-record]; readable: NASA/TP-20220014814 (2022), *Astrodynamics Convention and Modeling Reference for Lunar, Cislunar, and Libration Point Orbits*, §7.1 eq. (117), the same direct-minus-indirect point-mass form [V-text]). The Sun is always on. Planets are added only beyond 3 million km from Jupiter. Inside that radius their tidal pull is under 10⁻⁷ of Jupiter's (Saturn at its closest, 2GMr/d³ ≈ 9 × 10⁻¹³ km/s² against 1.4 × 10⁻⁵ km/s² at 3 million km), so they are left out to save time. That cut-off is a design value.
  - **Step size (27 Oct 2026).** The integrator is now DOP853, the Dormand–Prince 8(5,3) pair with error control (E. Hairer, S. P. Nørsett & G. Wanner, *Solving Ordinary Differential Equations I*, 2nd ed., Springer 1993, §II.5, §II.4 for the first step and §II.6 for dense output [V-record]; readable: the coefficients and step control as scipy ships them, `scipy/integrate/_ivp/dop853_coefficients.py` and `rk.py` [V-text]). Every step is held to a relative 1e-12, so the step follows the orbit everywhere and the rules below are retired. Against scipy's DOP853 at 1e-13 the worst ship drifts 2.75 mm in a day; RK4 under those rules drifted up to 1.0 m. It is also faster: two days of the campaign take 3.6 s of wall time against 5.0 s, and the forecast 38 ms against 94 ms, because it samples its grid from one integration by dense output. Retired rules, for the record: beyond the same radius, RK4 took adaptive steps of 0.004 × the shortest free-fall time sqrt(d³/μ) to any body (S. Aarseth, *Gravitational N-Body Simulations*, CUP 2003, ch. 2, time-step criteria [V-record]; readable: the free-fall criterion τ = η√(r³/μ) in Pelupessy, Jänes & Portegies Zwart 2012, *New Astron.* 17:711, arXiv:1205.5668, §2.3 eq. (13) [V-text]). The coefficient is a design value. Inside 3 million km the step was the one asked for (60 s for ships), capped at 0.01 × sqrt(r³/μ) of Jupiter by the same criterion (26 Oct 2026): at 1.3 Jupiter radii, where CLOSE PASS is flown, a flat 60 s drifted 44 m a day from DOP853; the cap takes it to about 25 s and 1 m a day. Above about 2.3 Jupiter radii the cap does not bite. The 0.01 is a design value.
  - **Spheres of influence.** These come from Laplace's rule, r = a (m/M)^(2/5) (H. Curtis, *Orbital Mechanics for Engineering Students*, 4th ed. 2020, §8.4 [V-record, section from the table of contents]; readable: B. Weber, *Orbital Mechanics & Astrodynamics*, open textbook, CC BY-SA 4.0, "Sphere of influence", eq. 352 [V-text]).
- **Shadows.** The Sun is a disc of 695,700 km radius, darkened toward the limb with the linear law I(μ) = 1 − u(1 − μ) and u = 0.6, a visible-band value (A. N. Cox ed., *Allen's Astrophysical Quantities*, 4th ed., Springer 2000, §14.7 [V-record]; corroborated by a white-light measurement averaging u = 0.61, Tripathi, Chaubey & Singh 2020, *J. Sci. Res. (BHU)* 64(1), doi:10.37398/JSR.2020.640132 [V-text], a modest single measurement). The disc is split into 12 rings, 397 rays in all. The light that reaches a ship is the weighted share of rays not blocked by Jupiter, the four Galilean moons, or (beyond 3 million km) any planet. Jupiter is drawn as an oblate spheroid, 71,492 km at the equator and 66,854 km at the poles, so the shadow covers both umbra and penumbra (Montenbruck & Gill §3.4.2, conical shadow model).
  - **Checked.** `tools/verify/tests/test_shadow.py` compares the game against a dense numpy integration over the disc (max error 0.019, bound 0.02) and checks the umbra and penumbra cone edges.
  - **In play.** The telescope's signal-to-noise ratio is scaled by the sunlit share, so a ship in the penumbra is half as easy to see in reflected light, and a ship in the umbra is not seen by it at all. `in_shadow` means less than half lit.
- **Skin heat capacity.** Skin temperature no longer jumps to its steady value. It follows C dT/dt = P_leak + α S f A/4 − ε σ T⁴ A, stepped implicitly with the T⁴ term linearised. The specific heat is that of aluminium at 298 K, 897 J/(kg·K): NIST-JANAF Thermochemical Tables (M. W. Chase, 4th ed., *J. Phys. Chem. Ref. Data* Monograph 9, 1998), Cp = 24.20 J/(mol·K) for solid Al at 298.15 K, ÷ 26.98 g/mol [V-text, NIST Chemistry WebBook]. (Incropera et al. 2007, Table A.1, gives 903 J/(kg·K) for pure Al at 300 K; the 0.7% difference does not matter in play.) C = 897 × 0.25 × dry mass: a quarter of the dry mass is taken to be skin and structure that reaches the radiators. That share is a design value, and a ship's `sig.C` can override it. The single-node model is the standard first cut in spacecraft thermal design (D. Gilmore ed., *Spacecraft Thermal Control Handbook*, vol. 1, 2nd ed., Aerospace Press 2002 [V-record; the chapter number is not confirmed and should be checked against a copy]; readable: the lumped-node balance C dT/dt = Q − AεσT⁴ in Gaite & Fernández-Rico 2012, *J. Thermophys. Heat Transf.* 26:511, arXiv:1202.4372, §II eq. (1), which cites Gilmore [V-text]).
  - **What it means in play.** For HYDRA the time constant is about 40 h (it was 22.5 h at the old 190 K skin), so passing through Jupiter's shadow cools the skin from 156 K by only a few kelvin.
  - **HYDRA's insulation (25 Oct 2026, user decision).** The skin's sunlit temperature is now 156 K (DESIGN VALUE), derived rather than picked: multi-layer insulation at an effective emittance ε* = 0.015 from a 293 K interior, the good end of the typical 0.015–0.03 (Selvadurai, Chandran, Valentini & Lamprecht 2022, *Appl. Sci.* 12(6):2858, eq. 3; open access), leaks 2.3 kW, and sunlight (α 0.078) adds the rest. The old 190 K implied ε* above 0.03, worse than a typical blanket. Effect, against the KITE's 0.1 m camera at S/N 5: radiating 249,000 km, dark 65,000 km (was 293,000 and 168,000), so at the scenario's 70,000 km start a dark HYDRA is hidden. The sink lasts 3 h 31 m at 395 kW. Most of HYDRA's warmth is its own leak heat, not sunlight. Steady temperatures are unchanged.
  - **Checked.** `test_shadow.py` checks the skin integration against scipy's `solve_ivp` (within 0.0002 K).
- **Flying between planets.** The planner plans with patched conics (Curtis ch. 8; D. Vallado, *Fundamentals of Astrodynamics and Applications*, 4th ed., Microcosm 2013, §7.6 and ch. 12 [V-record; the Vallado section is not confirmed]; readable: B. Weber, *Orbital Mechanics & Astrodynamics*, open textbook, interplanetary chapters [V-text]).
  - **How a plan is built.** A heliocentric Lambert arc runs from the planet you start at to the target. The escape burn is fitted so its hyperbola leaves from the ship's actual position. Arrival is costed as a capture into an orbit at 1.5 planet radii (a design value). The departure-date by flight-time chart is a porkchop plot of those costs.
  - **Refining the plan.** The plan is then flown under full gravity and corrected by Newton's method. It starts from a two-body Jacobian and updates it with Broyden's method (C. G. Broyden, *Math. Comp.* 19:577–593, 1965; Press et al., *Numerical Recipes*, 3rd ed. 2007, §9.7 [V-record; section from the 2nd ed., not confirmed in the 3rd]; readable: D. Bindel, Cornell CS 4220 lecture notes, 14 Apr 2023, "Broyden", §2 [V-text]) for up to 6 passes. It is accepted when it arrives within 0.1 of the target's sphere of influence. The Sun's tide during escape bends the departure by about 0.3 km/s, which is why two-body planning alone misses. That is also why real missions fly trajectory-correction burns: the planner offers one from deep space, again by Lambert.
  - **Entering orbit.** Inside a planet's sphere of influence, "ENTER ORBIT" circularises about that planet.
  - **Limits.** Interplanetary planning is on only when a campaign sets `interplanetary`, or with `--interplanetary`. The shadowing scenario leaves it off. Escaping Jupiter from HYDRA's low orbit costs about 15 km/s, more than HYDRA's 8.66 km/s. That is real physics, not a game limit.
  - **Trip estimates in the Solar System window.** Each body's row and card give the cheapest trip there: a Hohmann transfer between circular orbits about the Sun (Curtis §6.3; Weber, heliocentric Hohmann section [V-text]). Flight time is half the transfer ellipse. The burn to leave comes from the departure hyperbola at the ship's own radius and speed (Curtis §8.6, planetary departure). The burn to stop is a capture at 1.5 radii, the same as the planner. The next window comes from the phase angle (Curtis §8.3, rendezvous opportunities). For the Sun, the "flight" is the fall to its surface. These are lower bounds for display only; the planner's porkchop gives the real cost for a real date. Checked at the scenario date: Jupiter to Mars 3.2 yr, to Earth 2.9 yr, a fall into the Sun 2.2 yr.
  - **Time rates.** Time rates up to 7 days per second are offered when the flag is on, capped by a 30 ms per frame simulation budget, and the HUD shows the rate actually achieved.
- **Lit from the real Sun.** The 3D map, the close-up ship views and the trailer's framing now take the Sun's direction from the ephemeris. Before, they used a fixed direction from the concept art, 83° off the true Sun at the scenario's date (12 Oct 2041). The shadow cones drawn on the map (Jupiter's and each moon's umbra and penumbra) follow the same conical model as the game's shadow test (Vallado 2013 §5.3).
- **Heat forecast (HEAT window, F7).** The forecast flies the ship ahead one orbit (3–24 h) under the sim's own gravity, and each Red telescope along Blue's track of it (two-body). At each of 85 steps it recomputes the same S/N the game judges looks by (Sensing.ir_look), with the Sun's share, Jupiter blocking the line of sight, and the skin integrated as above. It is a prediction from what Blue knows, not the truth: it assumes everyone coasts. The "ghost streak" ranks (QUIET 1 h, DARK 6 h, BLACK 24 h, GHOST 72 h hidden) are design values, a score with no real-world counterpart.

### 8.8 Jupiter's look: map, shading and rings (25 Oct 2026)

Code: `godot/scenes/jovian_bodies.gd`, `godot/shaders/planet.gdshader`, `godot/shaders/jupiter_ring.gdshader` (+ `.gdshaderinc`, `jupiter_ring_line.gdshader`). Used by the 3D map and close views (`space_view.gd`); the IR view keeps its own thermal rendering.

- **Map.** Cassini's best cylindrical map of Jupiter, PIA07782 (NASA/JPL/Space Science Institute, public domain), from the full-resolution lossless TIFF on NASA's photojournal (3601 × 1801, 0.1° per pixel in planetocentric latitude and longitude) [V-text: the photojournal caption]. `tools/assets.mjs` drops the duplicated 360° column, eases the last 40 rows of cloud into the flat fill Cassini left over the poles (north of 88.4° N, south of 82° S), and scales it to 4096 × 2048 (power of two, mipmapped; 1.1 MB JPG). Longitude is as published. Hubble's OPAL maps (Simon, Wong & Orton 2015) were checked as an alternative: they are the same 0.1° grid (3600 × 1800) with wider polar gaps, so Cassini was kept.
- **Shape.** Jupiter is drawn oblate, 71,492 km equatorial, 66,854 km polar (§8.7).
- **Limb darkening.** Minnaert's law, I/F = (I/F)₀ μ₀^k μ^(k−1), with **k = 1.0**: Binder & McCarthy (1973) find k = 1.0 over Jupiter's whole disc for its clouds from 0.6 to 1.6 µm [V-text, NTRS report 19730014045, Appendix A abstract and §IV]. k = 1 is Lambert-like darkening toward the limb. Mendikoa et al. (2017) tabulate k per filter and latitude for 0.38–1.7 µm (their supplementary tables, not checked).
- **Terminator.** The Sun is a 0.1° disc at 5.2 AU, so the true penumbra is about 0.1° wide. A soft edge of ±0.022 in cos(incidence) (≈1.3°) is a DESIGN VALUE, standing in for the high haze still catching light just past it.
- **Haze, night side, colour.** The cream glow on the sunlit limb (stratospheric haze at grazing view), the faint cool night side, a saturation of 0.7 and a contrast gamma of 1.35 on the map are ART DIRECTION, matched to the concept mockups; nothing is measured there.
- **Moons.** Airless: a lunar-Lambert blend of Lambert and Lommel–Seeliger (half each, a DESIGN VALUE), with a hard terminator.
- **Ring structure** (de Pater, Hamilton, Showalter, Throop & Burns 2018, *The Rings of Jupiter*, Table 6.1, from Ockert-Bell et al. 1999 and de Pater et al. 1999, 2008) [V-text, arXiv:1707.00806]:

  | Component | RJ | Thickness | Normal optical depth |
  |---|---|---|---|
  | Halo | 1.40–1.71 | ~50,000 km | few × 10⁻⁶ |
  | Main ring | 1.72–1.806 | 30–100 km | few × 10⁻⁶ |
  | Amalthea gossamer | 1.8–2.55 | 2,300 km | 10⁻⁷ |
  | Thebe gossamer | 1.8–3.10 | 8,500 km | 10⁻⁸ |
  | Thebe extension | 3.1–3.8 | 9,000 km | 10⁻⁹ |

  The main ring has a ~800 km bright annulus at its sharp outer edge near 129,100 km (1.81 RJ), and Metis orbits at 1.79 RJ (drawn as a slight dip). Discovered by Voyager 1, 4 March 1979; Voyager 2, looking back toward the Sun from Jupiter's shadow, saw it glow brightly, showing it is dominated by micron dust that scatters forward into a diffraction lobe a few degrees wide (same chapter, §6.1). Its phase curve is flat from 1° to about 130° (§6.2, Throop et al. 2004).
- **Ring light, physical part.** Optically thin: brightness ∝ τ·P(phase)/(4|sin B|) for viewer elevation B, capped by each component's thickness (so the thick halo and gossamer rings never sharpen into a line; the thin main ring does). Brighter backlit than front-lit. Jupiter's shadow is cast on the ring by a ray toward the Sun against the oblate planet. The ring is hidden behind the planet and drawn over it in front, by the depth test.
- **Ring light, DESIGN LIBERTY.** With the real τ ≈ 5 × 10⁻⁶ the ring would show only backlit and nearly edge-on; front- or side-lit it is ~10⁻⁵ of Jupiter's disc. So:
  - the open ring sheet is brightened ×20,000 in the close views and ×7,000 on the far tactical map (where it stays faint, as in the mockup);
  - the edge-on main ring is drawn as an anti-aliased screen-space line, its brightness set by eye and falling as 1/√distance (physically 1/distance), so it reads across the system without flaring near the ring;
  - the forward-scattering lobe is broad and weak (Henyey–Greenstein g = 0.5 carrying 60%): backlit is about 8× front-lit, not the real hundreds to thousands;
  - the ring darkens the disc behind it as a thin line (opacity ×2,000; the real ring blocks a few millionths);
  - the gossamer rings are lifted ×1.5–4 relative to the main ring so they can be seen at all; the halo is drawn at 0.04 of the main ring face-on.
- **Scenario note.** The shadowing's ships orbit at 1.30–1.50 RJ, inside the halo and the main ring, so from there the main ring is a line along the horizon and passes behind Jupiter.

## 9. Bibliography

**Standards and agency documents**
1. ITU-R SA.509-3 (12/2013), *Space research earth station and radio astronomy reference antenna radiation pattern…* https://www.itu.int/dms_pubrec/itu-r/rec/sa/R-REC-SA.509-3-201312-I!!PDF-E.pdf
2. ITU-R S.465-5 (1993, editorial 2001), *Reference earth-station radiation pattern… 2 to about 30 GHz*. https://www.itu.int/dms_pubrec/itu-r/rec/s/R-REC-S.465-5-199304-S!!PDF-E.pdf (in force: S.465-6)
3. ITU-R S.1428-1 (2001), *Reference FSS earth-station radiation patterns… non-GSO… 10.7–30 GHz*. https://www.itu.int/dms_pubrec/itu-r/rec/s/R-REC-S.1428-1-200102-I!!PDF-E.pdf
4. ITU-R S.672-4 (1997), *Satellite antenna radiation pattern for use as a design objective in the FSS…* https://www.itu.int/dms_pubrec/itu-r/rec/s/R-REC-S.672-4-199709-I!!PDF-E.pdf
5. ITU-R SM.1055-0 (1994), *The use of spread spectrum techniques*. https://www.itu.int/dms_pubrec/itu-r/rec/sm/R-REC-SM.1055-0-199407-I!!PDF-E.pdf
6. JPL, *DSN Telecommunications Link Design Handbook* 810-005, Module 201 Rev. F (2022), *Frequency and Channel Assignments*. https://deepspace.jpl.nasa.gov/dsndocs/810-005/201/201F.pdf ; Module 202 Rev. D (2021), *Doppler Tracking*. https://deepspace.jpl.nasa.gov/dsndocs/810-005/202/202D.pdf
7. Naval Air Warfare Center Weapons Division (2013), *Electronic Warfare and Radar Systems Engineering Handbook*, NAWCWD TP 8347, 4th ed., approved for public release. https://everyspec.com/USN/NAVY-General/NAWCWD_TP_8347_4TH-ED_2013_55921/ (DTIC ADA617071)
8. U.S. Space Force (2025), *Space Warfighting: A Framework for Planners* (dated March 2025, released April 2025). https://csps.aerospace.org/sites/default/files/2025-10/USSF%20Space_Warfighting_A%20Framework%20for%20Planners%20%28final_20250410%29.pdf
9. Joint Chiefs of Staff (2018), JP 3-60 *Joint Targeting*, 28 Sep 2018 (revision of the 31 Jan 2013 edition), DoD FOIA reading room 21-F-0520. https://www.esd.whs.mil/Portals/54/Documents/FOID/Reading%20Room/Joint_Staff/21-F-0520_JP_3-60_9-28-2018.pdf [V-text, read from the user's copy of the scan]
   - Read: Ch. I pp. I-3 and I-10; Ch. II pp. II-3–II-4, II-11, II-13–II-17, II-20, II-22–II-32 and II-34–II-35 (joint targeting cycle, F2T2EA, nonlethal effects, effects); App. C pp. C-8 and C-10 (space, EW); App. D pp. D-1–D-8 (combat assessment); glossary pp. GL-5–GL-8.
   - Page cites are the printed folios. The OCR is clean enough to read.
   - Superseded by a 2024 edition (per AFDP 3-60 fn. 8), which was not read.
10. Joint Chiefs of Staff (2020), JP 3-85 *Joint Electromagnetic Spectrum Operations*, 22 May 2020; supersedes JP 3-13.1 and JP 6-01. https://irp.fas.org/doddir/dod/jp3_85.pdf [V-text, read from the user's copy]
    - Read: Ch. I pp. I-1–I-13; Ch. II pp. II-2–II-5 and II-10; Ch. III pp. III-8 and III-14–III-17; Ch. IV pp. IV-1–IV-5; App. B pp. B-1–B-4; glossary pp. GL-6–GL-10; exec. summary pp. v–x.
11. U.S. Air Force (2026), AFDP 3-60 *Targeting*, 1 May 2026. https://www.doctrine.af.mil/Portals/61/documents/AFDP_3-60/3-60-AFDP-TARGETING.pdf [V-text, read from the user's copy]
    - Read: Ch. 1 pp. 1–10 (principles, categories, characteristics, legal, ROE); Ch. 3 pp. 18–29 (joint targeting cycle, air tasking cycle, assessment, dynamic targeting / F2T2EA).
    - Page cites are the printed page numbers.
12. NASA GSFC, *Jupiter Fact Sheet* (updated 2 Oct 2024). https://nssdc.gsfc.nasa.gov/planetary/factsheet/jupiterfact.html
13. Henninger, J. H. (1984), *Solar Absorptance and Thermal Emittance of Some Common Spacecraft Thermal-Control Coatings*, NASA RP-1121. https://ntrs.nasa.gov/citations/19840015630
14. Mason, L. S. (2003), *A Power Conversion Concept for the Jupiter Icy Moons Orbiter*, NASA/TM-2003-212596 (AIAA-2003-6007). https://ntrs.nasa.gov/citations/20030105581
15. Siamidis, J., Mason, L., Beach, D. & Yuko, J. (2005), *Heat Rejection Concepts for Brayton Power Conversion Systems*, NASA/TM-2005-213337 (AIAA-2004-5654). https://ntrs.nasa.gov/api/citations/20050160234/downloads/20050160234.pdf
16. NASA GRC (2005), *Power-Conversion Concept Designed for the Jupiter Icy Moons Orbiter*. https://ntrs.nasa.gov/api/citations/20050192432/downloads/20050192432.pdf
17. Choi, M. K. (2012), *Phase Change Material for Temperature Control of Loop Heat Pipe Compensation Chamber*, NASA GSFC. https://ntrs.nasa.gov/api/citations/20120015405/downloads/20120015405.pdf
18. Choi, M. K. (2018), *Thermal Assessment of Paraffin Phase Change Material Mini-Packs on IceCube 3U CubeSat in Flight*, NASA GSFC. https://ntrs.nasa.gov/api/citations/20180004470/downloads/20180004470.pdf
19. Leimkuehler, T. O., Stephan, R. A. & Hawkins-Reynolds, E. (2011), *Testing and Failure Mechanisms of Ice Phase Change Material Heat Exchangers*, NASA JSC. https://ntrs.nasa.gov/api/citations/20110008723/downloads/20110008723.pdf
20. NASA/JPL (2023), *DSOC Technology Demonstration* fact sheet. https://www.nasa.gov/wp-content/uploads/2023/07/dsoc-fact-sheet-06152023.pdf ; JPL DSOC mission page. https://www.jpl.nasa.gov/missions/dsoc
21. AMD (2023), *Zynq UltraScale+ RFSoC Data Sheet: Overview*, DS889 v1.14. https://docs.amd.com/v/u/en-US/ds889-zynq-usp-rfsoc-overview

**Peer-reviewed papers**
22. Friis, H. T. (1946), A note on a simple transmission formula, *Proc. IRE* 34:254–256.
23. Stein, S. (1981), Algorithms for ambiguity function processing, *IEEE Trans. ASSP* 29(3):588–599. doi:10.1109/TASSP.1981.1163621
24. Ho, K. C. & Chan, Y. T. (1997), Geolocation of a known altitude object from TDOA and FDOA measurements, *IEEE Trans. AES* 33(3):770–783. doi:10.1109/7.599239
25. Ho, K. C. & Xu, W. (2004), An accurate algebraic solution for moving source location using TDOA and FDOA measurements, *IEEE Trans. Signal Process.* 52(9):2453–2463. doi:10.1109/TSP.2004.831921
26. Ho, K. C., Lu, X. & Kovavisaruch, L. (2007), Source localization using TDOA and FDOA measurements in the presence of receiver location errors: analysis and solution, *IEEE Trans. Signal Process.* 55(2):684–696. doi:10.1109/TSP.2006.885744
27. Albersheim, W. J. (1981), A closed-form approximation to Robertson's detection characteristics, *Proc. IEEE* 69(7):839. doi:10.1109/PROC.1981.12082
28. North, D. O. (1963 reprint of 1943 RCA report), An analysis of the factors which determine signal/noise discrimination in pulsed-carrier systems, *Proc. IEEE* 51(7):1016–1027. doi:10.1109/PROC.1963.2383 (background on the matched filter; no claim in the text rests on it)
29. Urkowitz, H. (1967), Energy detection of unknown deterministic signals, *Proc. IEEE* 55(4):523–531. doi:10.1109/PROC.1967.5573
30. Gardner, W. A. (1991), Exploitation of spectral redundancy in cyclostationary signals, *IEEE Signal Process. Mag.* 8(2):14–36. doi:10.1109/79.81007
31. Self, A. G. & Smith, B. G. (1985), Intercept time and its prediction, *IEE Proc. F* 132(4):215. doi:10.1049/ip-f-1.1985.0052
32. Clarkson, I. V. L., Perkins, J. E. & Mareels, I. M. Y. (1996), Number/theoretic solutions to intercept time problems, *IEEE Trans. Inf. Theory* 42(3):959–971. doi:10.1109/18.490557
33. Cummings, W. C. (1992), An adaptive nulling antenna for military satellite communications, *Lincoln Laboratory Journal* 5(2):173–. https://archive.ll.mit.edu/publications/journal/pdf/vol05_no2/5.2.1.nullingantenna.pdf
34. Sabharwal, A. et al. (2014), In-band full-duplex wireless: challenges and opportunities, *IEEE JSAC* 32(9):1637–1652. doi:10.1109/JSAC.2014.2330193
35. Danev, B., Zanetti, D. & Čapkun, S. (2012), On physical-layer identification of wireless devices, *ACM Comput. Surv.* 45(1). doi:10.1145/2379776.2379782
36. Riyaz, S., Sankhe, K., Ioannidis, S. & Chowdhury, K. (2018), Deep learning convolutional neural networks for radio identification, *IEEE Commun. Mag.* 56(9):146–152. doi:10.1109/MCOM.2018.1800153
37. Merchant, K., Revay, S., Stantchev, G. & Nousain, B. (2018), Deep learning for RF device fingerprinting in cognitive communication networks, *IEEE JSTSP* 12(1):160–167. doi:10.1109/JSTSP.2018.2796446
38. Hanel, R. A., Conrath, B. J., Herath, L. W., Kunde, V. G. & Pirraglia, J. A. (1981), Albedo, internal heat, and energy balance of Jupiter, *JGR* 86(A10):8705–8712. doi:10.1029/JA086iA10p08705
39. Li, L. et al. (2018), Less absorbed solar energy and more internal heat for Jupiter, *Nat. Commun.* 9:3709. doi:10.1038/s41467-018-06107-2
40. Mainzer, A. K. et al. (2023), The Near-Earth Object Surveyor Mission, *Planet. Sci. J.* 4:224. doi:10.3847/PSJ/ad0468
41. Matsumoto, T., Tsumura, K., Matsuoka, Y. & Pyo, J. (2018), Zodiacal light beyond Earth orbit observed with Pioneer 10, *AJ* 156:86. doi:10.3847/1538-3881/aad0f0
42. Leinert, C. et al. (1998), The 1997 reference of diffuse night sky brightness, *A&AS* 127:1–99. doi:10.1051/aas:1998105
43. Burt, E. A. et al. (2021), Demonstration of a trapped-ion atomic clock in space, *Nature* 595:43–47. doi:10.1038/s41586-021-03571-7
44. Poston, D. I., Gibson, M. A., Sanchez, R. G. & McClure, P. R. (2020), Results of the KRUSTY nuclear system test, *Nucl. Technol.* 206(sup1):S89–S117. doi:10.1080/00295450.2020.1730673
45. Zervas, M. N. & Codemard, C. A. (2014), High power fiber lasers: a review, *IEEE JSTQE* 20(5):219–241. doi:10.1109/JSTQE.2014.2321279
46. Shannon, C. E. (1949), Communication in the presence of noise, *Proc. IRE* 37(1):10–21. doi:10.1109/JRPROC.1949.232969
47. Sarda, K., CaJacob, D., Orr, N. & Zee, R. E. (2018), Making the invisible visible: precision RF-emitter geolocation from space by the HawkEye 360 Pathfinder mission, IAC-18-B4.4.1. https://iafastro.directory/iac/paper/id/42239/summary/

**Textbooks** (existence verified through publisher listings or reviews; passages not read)
48. Adamy, D. L., *EW 101* (2001), *EW 102* (2004), *EW 103* (2009), Artech House.
49. Poisel, R. A. (2012), *Electronic Warfare Target Location Methods*, 2nd ed., Artech House.
50. Wiley, R. G. (2006), *ELINT: The Interception and Analysis of Radar Signals*, Artech House.
51. Richards, M. A. (2005), *Fundamentals of Radar Signal Processing*, McGraw-Hill.
52. Skolnik, M. I. (2001), *Introduction to Radar Systems*, 3rd ed.; (2008) *Radar Handbook*, 3rd ed., McGraw-Hill.
53. Hudson, R. D. (1969), *Infrared System Engineering*, Wiley.
54. Torrieri, D. (2022), *Principles of Spread-Spectrum Communication Systems*, 5th ed., Springer. doi:10.1007/978-3-030-75343-6 (background on DS processing gain beside SM.1055; no claim in the text rests on it)
55. Pace, P. E. (2009), *Detecting and Classifying Low Probability of Intercept Radar*, 2nd ed., Artech House.

**Industry and press (lowest tier; used only where nothing better exists)**
56. Lockheed Martin (28 Jan 2014), *Lockheed Martin Demonstrates Weapons-Grade High Power Fiber Laser*. https://news.lockheedmartin.com/2014-01-28-Lockheed-Martin-Demonstrates-Weapons-Grade-High-Power-Fiber-Laser
57. Laser Focus World, *Photonic Frontiers: High-efficiency optical pumping* (wall-plug > 30% for industrial Yb fibre lasers). https://www.laserfocusworld.com/lasers-sources/article/16547048/
58. ESA eoPortal, *HawkEye 360*. https://eoportal.org/satellite-missions/hawkeye
59. Defense News (15 Apr 2025), *Space Force Meadowlands jammer ready for formal testing*. https://www.defensenews.com/space/2025/04/15/space-force-meadowlands-jammer-ready-for-formal-testing/
60. The Register (30 Sep 2025), *NASA's deep-space laser comms demo has left the chat*. https://www.theregister.com/2025/09/30/nasa_dsoc_demo/

## 8. Decisions (23 Oct 2026)

The user decided the four gameplay-changing conflicts:

- **Q1 / Q15, ear beams.** Real narrow beams (beamwidth ≈ 70λ/D). Ears must point: an assist aims them at known tracks and sweeps sectors, and an expert can turn it off and schedule pointing by hand. This replaces frequency-scan scheduling.
- **Q2 / Q3, sidelobes.** ITU reference envelopes by off-axis angle (SA.509-3, S.465-5, S.1428-1, S.672-4) for emitter toward ear, ear toward emitter, and victim toward jammer. Any rebalancing uses real levers only and is put to the user first.
- **Q5 / Q6 / Q7 / Q12, infrared.** An in-band Planck model with probabilistic detection around S/N 5, and occasional false alarms. Jupiter's disc counts as bright background, and the visible telescope also detects reflected sunlight. Tutorial and scenario distances that depend on IR will be retuned and shown to the user first.
- **Q8 / Q9 / Q10, heat.** Real reactor waste heat at JIMO's 100 kWe with its real radiator area. Radiators follow Lambert's cosine law and can be turned away from threats. A heat sink (cited PCM or vented water) lets a ship go dark for a while. Radar power must fit the power budget.

Fact fixes to apply without changing gameplay intent: Q4 (deep-space X uplink 7145–7190 MHz), Q8 wording ("dull coating" → low-emissivity metal), Q11 (Jupiter 125 K effective emission), Q13/Q14 (uncertain effects assessment, Red adaptation; both already planned), and Q16 (1–3 dB mismatch loss).

### 8.1 Doctrine decisions (23 Oct 2026)

- **Q17, assessment.** ENGAGE lights when the player acts. ASSESS shows Blue's estimate (possible → probable → confirmed), built from observable indicators (JP 3-60 D-2, D-3; AFDP 3-60 p. 21). The true state appears only in the after-action replay.
- **Q18, kill chain.** Match JP 3-60 F2T2EA. FIX means located and positively identified (II-22, II-27). TARGET is the player's decision to approve an option after an ROE/no-strike check (II-28–30).
- **Q19, intelligence cost.** Jamming an exploited frequency risks losing it, because Red may go quiet, hop or change channel (JP 3-85 III-8; B-1–B-2). This is folded into the Red-adaptation mechanic.
- **Q20, collateral effects.** A joint restricted frequency list marks civil and allied channels TABOO or PROTECTED (JP 3-85 III-8), and barrage jamming notches them at a J/S cost. Hitting one anyway raises escalation and shows in the debrief (IV-5).
- **Wording fix.** Use "electromagnetic warfare / electromagnetic attack", following JP 3-85 (p. v; GL-6).

### 8.2 Listening and jamming as built (23 Oct 2026)

- **Ears: tip and cue.** Warships and buoys carry 4-face receive arrays that form a beam toward every direction at once (TDRS S-band Multiple Access, NASA TM-105422 [V-text]). Gain is the aperture's peak plus 10 log cos(scan) off the nearest face; four faces fixed in inertial space are a design value, so the worst loss is 1.5 dB. Ganymede Station's 12 m dish hears through its SA.509-3 pattern at the angle off where it points. By default an assist points it at the hostile track seen most recently, else the newest unknown one. It aims at Blue's track, not the truth. The player can point it at a chosen track or park it.
- **Emitters point.** Red TT&C aims at the handler (Callisto), civil probes at Earth (JPL approximate ephemeris, `core/ephem.gd`, checked against Horizons to 0.2°), the ore hauler at Ganymede, and a relay's wake call at the sleeper. Every gain off boresight comes from SA.509-3 (D/λ ≥ 100) or S.465-5 Note 4 (D/λ < 100), with the shoulder join noted in `core/antenna.gd`. At Ka band (32 GHz) the SA.509-3 envelope is extrapolated slightly beyond its stated ~30 GHz limit. Note 2 of S.465 asks for caution below D/λ = 50, which covers every Red dish; the envelope is still the most credible public pattern.
- **Detection is probabilistic.** The energy detector gives Pd = Q((Q⁻¹(Pfa) − d)/√(1 + 2s)) at Pfa 10⁻⁶ (a design value), from Urkowitz (1967). This is checked against the exact chi-square distributions (scipy) to 0.01 for n ≥ 10⁵ samples. Even odds come at 6.8 dB.
- **Measured effect, and the user's decision.** Under the ITU envelope and Pd, the tender was heard by every ear (buoys at about +25 dB, warships at +13 to +19 dB); before, only the station heard it. The user asked for "whichever is most realistic, but … gamify it in order to show concepts and make the signals gameplay more fun".
  - The tender now uses LPI: direct-sequence spreading of its 2 Mbit/s reports to 20 MHz (20 Mchip/s), at 5 W. At fixed power an energy detector's integrated SNR is (P/kT)√(τ/B) (radiometer equation; Urkowitz 1967), so the spread from 2 to 20 MHz costs an eavesdropper's energy detector √(B_old/B_new), 5 dB, and the power cut from 20 to 5 W 6 dB more. ITU-R SM.1055-0 §1 notes that spread signals are noise-like and not readily detected; it gives the intended receiver's processing gain, not the eavesdropper's loss. These are design values on real techniques.
  - Over 10 campaign days: the station heard 6 of 10 reports when on a good track; buoys near its line to Callisto 8; HYDRA (35° off its beam) 6; EXCALIBUR broadside 1.
  - What it teaches: the side lobe depends on angle; standing near the target's line to its handler pays; spreading a signal hides it; the big dish must be cued.
- **JS prototype unchanged.** The 0.1 browser prototype has no patterns or pointing. It keeps its fixed −15 dBi, 20 W, 2 MHz link and its 10 dB threshold. The Godot export merges the tender's `lpi` values in (`tools/export-godot.mjs`).
- **Jamming is geometric.** J = Pj + Gj(our aim error against the track) + Gv(our angle off the victim's line to its handler) − L, and S = Pu + Gu + Gv(0) − L, all through the same ITU patterns. This is checked against an independent build of Adamy's equation over 60 geometries. From broadside the victim's discrimination is −44.8 dB (it was a fixed −45). Near its handler line it falls to −13 dB, and a loose track costs beam-pointing gain.
- **Inspector.** Click SNR HERE or the J/S meter in the SIGINT station for the budget term by term, with each term's angle, distance and source.

### 8.3 Heat and in-band infrared as built (23 Oct 2026)

- **In band, probabilistic.** Every IR telescope works in NEO Surveyor's NC2 band (6–10 µm). Each body's in-band share comes from the Widger & Woodall (1976) Planck series [V-record], checked against astropy to 6×10⁻¹¹; the same polylogarithm series is in Lewis & McClarren 2025, arXiv:2503.08892, §3.1 eqs. (24)–(29) [V-text]. The in-band 1σ NEI of the 0.5 m LWIR is 7×10⁻¹⁸ W/m², inside the 0.4–1.1×10⁻¹⁷ derived from NEO Surveyor's S/N-5 sensitivity (§2). The station's 2 m keeps its former 10× (7×10⁻¹⁹; design value). Red's sensors keep their old ratios to Blue's. A look detects with Pd = Φ(S/N − 5). Red's planning and the UI use the expected decision, S/N ≥ 5.
- **False alarms.** Each sensor reports a Poisson number of false single-look lines per look (mean 0.1, design value). Only lines from two places at one instant start a track. A false line never crosses another, and an IR line no longer crosses a radio line heard minutes earlier: that pairing had been starting overconfident tracks.
- **Background.** Against Jupiter's disc the NEI is ×50 (design value inside the derived ×26–92). Off the disc but within 3 Jupiter radii, stray light raises it ×5 (design value). This was ×25 everywhere in the cone before. A visible telescope sees nothing within the cone.
- **Skin.** Each class keeps its design skin temperature in sunlight. The leak that holds it there is εσT⁴A − αS·A/4, with α from Henninger (1984), or an area mix of its vapor-deposited aluminium and silvered-mirror entries. The KITE (ε 0.12, α 0.05), ORIEL (ε 0.5, α 0.3) and SKV (ε 0.8, α 0.2) pairs match no RP-1121 entry or mix; they are DESIGN VALUES (plausible finishes such as solar cells or paint). In Jupiter's shadow the skin cools to (leak/εσA)^¼, with no thermal lag (a stated simplification). VESPER drops from 140 K to 113 K; the MOTH, whose design temperature is below its sunlit equilibrium, runs at 137 K in sunlight.
- **Reactors and radiators.** WARDEN and PFS: 100 kWe at 20.2% (Mason 2003), so 395 kW of waste. WARDEN's 85 m² per face is JIMO's 170 m² two-sided radiator (Siamidis 2005), at 462 K; that is within 1.1% of JIMO's design point. PFS's 1,144 m² per face (its database's 52 m × 22 m) runs at 241 K, and at 413 K while the laser's 3 MW flows for the 600 s dwell. VESPER: a Kilopower-class 1 kWe plant at 25% (DESIGN VALUE: KRUSTY demonstrated ~25% system efficiency at 1.5–5 kWt but never produced 1 kWe, each converter giving ~90 We; Poston et al. 2020) and a 1.15 m² radiator at 400 K (design value). Radiators are Lambertian two-sided panels. Their edge is a 2 cm strip (design value). VESPER's edge carries its hull's ε 0.08 finish (`edgeEps`, design value on Henninger's low-ε coatings), so its edge shows 11× less than a bare ε 0.9 edge.
- **Aspect (user decision, 23 Oct 2026).** Every ship lays its radiators flat to the plane of play, normal toward the poles: the real best tactic in a near-planar system, edge-on to every observer at once. An earlier build turned them in the plane, edge-on to one threat; the other telescopes then saw a face, and the VESPER was in view 60% of the time. The face-on ranges below are kept for reference (an observer off the plane).
- **Going dark.** WARDEN: 2 t of water boiled off and vented (2.5 MJ/kg) carries 395 kW for 3.5 h, and is then gone. VESPER: 500 kg of water ice (333 kJ/kg, Leimkuehler 2011) for 15.4 h. The ice is refrozen afterwards by running the radiator at twice the waste heat (design value). Red goes dark when a known Blue telescope would still see its radiator's edge, and puts off refreezing while the doubled load would show.
- **Power budget.** The radar drops from 40 to 25 kW average (~75 kWe at 33%, design value), so it fits the 100 kWe plant. Range on 0.5 m² goes from 14,640 km to 13,018 km, and the tutorial now says "inside 13,000 km". The laser's 7 GJ store is text only in the Godot build. The plant would put back a shot's 2.4 GJ in 6.7 h, but no recharge gate is modelled.
- **Visible detection.** Sunlit ships are found by reflected sunlight:
  - The Sun's M_V 4.81 (Willmer 2018) is placed at 1 AU (−26.76, matching Torres 2010) and scaled to Jupiter's 50.26 W/m² against 1,361 (Kopp & Lean 2011).
  - Each hull is a Lambert sphere with geometric albedo p = ⅔·diffuse·(1 − α) and phase law Φ(α) = (sin α + (π − α) cos α)/π. Its flux relative to the incident sunlight is p·Φ(α)·r²/R², with r² = A/4π for a hull of total area A (Madhusudhan & Burrows 2012, *ApJ* 747:25, eq. 3). Before 25 Oct 2026 the game used p·(A/4)·Φ/R², which put the cross-section πr² where r² belongs: every hull was π times (1.24 mag) too bright and every visible range √π = 1.77× too long. The ranges below are after the fix.
  - The limit is magnitude 22 at 1 m for S/N 5 (GEODSS CCD, Stokes et al. 1996 [V-record, paywalled]). The same Lincoln Laboratory team's free journal paper gives magnitude 22 at **S/N 4** over a 2 deg² field in under 100 s (Stokes et al. 1998, *Lincoln Lab. J.* 11(1):27, abstract, "Initial Field Tests", Fig. 6 [V-text]); the game's S/N 5 (slightly conservative) and the 2.5·log₁₀ D scaling are DESIGN VALUES.
  - The diffuse fraction is a design value: 20% for ordinary hulls, and 2% for the polished, chined VESPER and MOTH.
  - **Cued only (user decision, 23 Oct 2026).** GEODSS reaches magnitude 22 by staring ~100 s at one field, so Blue's telescopes look only where Blue holds a track. A whole-sky search at that depth every 10 minutes had found the MOTH at 450,000 km and the GADFLY at 1.1 million km (measured with the pre-fix, π-too-bright reflection; about 0.56× those distances now). IR and listening find; the telescope follows up.
- **Measured ranges (thousand km, Blue 0.5 m LWIR at S/N 5; visible at 1 m, side-lit).** "Old" is the whole-spectrum model at S/N 1. The visible column is after the 25 Oct 2026 Lambert-sphere fix (before: VESPER 416, MOTH 304, GADFLY 680, CROW 833, WARDEN 2,150, PFS 3,709, HMH-5 5,865). Before the fix VESPER was 416 and MOTH 304; both re-measured after it. Other classes after the fix: WREN 271, GMC-2 632, LANTERN 509, hauler 770, PROSPECTOR 272.

  | Class | Old, cold | Old, burning | New, coasting (radiator edge-on) | New, dark | New, radiator face-on | New, in shadow | New, burning | Visible, 1 m |
  |---|---|---|---|---|---|---|---|---|
  | VESPER | 169 | 3,469 | 111 | 68 | 2,156 | 18 | 5,180 | 235 |
  | MOTH | 60 | 3,001 | 35 | 35 | 35 | 0 | 4,485 | 171 |
  | GADFLY | 279 | 1,110 | 250 | 250 | 250 | 235 | 1,908 | 384 |
  | CROW | 422 | 422 | 490 | 490 | 490 | 471 | 490 | 470 |
  | WARDEN | 803 | 6,081 | 1,445 | 826 | 25,466 | 765 | 8,460 | 1,213 |
  | PFS | 5,368 | 8,071 | 10,006 | 9,999 | 18,397 | 9,958 | 13,023 | 2,093 |
  | HMH-5 | 10,559 | 10,559 | 22,511 | 22,511 | 22,511 | 22,457 | 22,511 | 3,309 |
- **The campaign, before and after (72 h, Blue idle, 3 seeds; `godot/tests/measure_seen.gd`).** Share of looks in which any Blue telescope saw each Red ship. The last column was re-measured after the 25 Oct 2026 Lambert-sphere fix; the column before it is pre-fix. No start position moved: with the rules above, HYDRA's 220,000 km from the tender is twice the tender's coasting range (it was 1.3 times before).

  | Ship | Before (IR lines) | After, in-plane aim, sky search | After, as built, post-fix (IR / visible lines) |
  |---|---|---|---|
  | VESPER (tender) | 3.7% (99, its burn) | 60.5% | 2.4% (63 / 0: first seen at T+14.7 h by its burn; sunlight no longer holds it, since visible reach is now ~235,000 km; pre-fix 49.7%, 99 / 407) |
  | CROW (relay) | 38.5% | 54.6% | 52.0% (662 / 179; warm, 200 K skin; the station sees it) |
  | GADFLY (inspector) | 0% | 31.8% | 1.5% (13 / 0) |
  | MOTH (sleeper) | 0% | 59.1% | 0% |

### 8.4 CLOSE PASS, the beginner scenario (23 Oct 2026; named THE SHADOWING until 25 Oct)

`godot/data/campaign.json` (`id: shadow`) replaces Operation NIGHT HERON as the scenario a new game starts. NIGHT HERON was retired on 26 Oct 2026; its platforms (CROW, GADFLY, MOTH and the database entries) moved into `campaign.json`. The scenario is modelled on a real uncooperative rendezvous with a commercial radar satellite in October 2026, moved to low Jupiter orbit and not named in play. The Library cites the reporting it draws on.

- **The real sequence** (LeoLabs, as reported by [Breaking Defense](https://breakingdefense.com/2026/10/russian-satellite-stalked-iceye-spacecraft-in-potentially-dangerous-on-orbit-maneuvers/) and [The War Zone](https://www.twz.com/news-features/russias-satellite-unprecedented-shadowing-of-a-very-particular-radar-imaging-satellite-is-a-big-deal), 19 Oct 2026): coplanar alignment; closing from long range (neither report gives a starting distance); station-keeping within 5 km, then 1–2 km; a closest pass of 500 m (LeoLabs; another report gives 26 m); moves to ahead of and behind the target, loitering; a controlled departure into a larger orbit. The inspector's legs in the scenario follow it: −60 km, −5, +5, −1.5, −0.5 (the long loiter), +2, −0.5 km along-track, then complete.
- **The target.** ORIEL-36 is a 3.25 m X-band SAR smallsat, its size and layout from [ESA Earth Online's ICEYE mission description](https://earth.esa.int/eogateway/missions/iceye/description). Its skin, radar cross-section and the inspector's (the KITE, 1.78 m, 0.5 t) are design values.
- **The orbit.** 1.3 Rj (92,940 km from Jupiter's centre), 4.37 h period. That is inside Jupiter's radiation belts; a craft could live there only rad-hardened. Juno's titanium vault cuts its dose about 800 times ([NASA, 2016](https://www.nasa.gov/news-release/nasas-juno-spacecraft-to-risk-jupiters-fireworks-for-science)). The hardening of every craft in the scenario is a design value; no dose is modelled. User decision: low orbit, rad-hardened.
- **J2 and the planner.** At 1.3 Rj, Jupiter's oblateness (J2) bends a 3 h coast by thousands of km, so a two-body Lambert transfer misses. Every burn is now refined by differential-correction shooting through the full-gravity coast (Vallado, *Fundamentals of Astrodynamics and Applications*, §7.6 [V-record; section not confirmed]; readable: single shooting, NASA/TP-20220014814 (2022) §5.2.1 "Shooting Methods" [V-text]): `Sim.refine()`. HYDRA's transfer to ORIEL-36 comes out at 3.570 km/s flown against 3.869 two-body, and arrives 0.012 km from its aim point (`godot/tests/shadow_test.gd`). Circular orbits are placed with v² = μ/r + 1.5·μ·J2·R²/r³, so they don't breathe.
- **The planner in low orbit (0.7).** Its porkchop grid was sized for transfers among the moons (waits to 48 h, flights from 6 h). At ORIEL-36's 4.4 h period no cell could be burned and then matched within HYDRA's 8.66 km/s (the best cost 12.9). A target that circles in under 12 h now gets waits to 24 h in 1.5 h steps and flights of 1 to 6 h; our ship is coasted to each departure under the same full gravity (two-body drifts far in a day of low orbit), and each cell carries its MATCH cost, which CHEAPEST and BALANCED count. CHEAPEST to ORIEL-36 at the start: wait 18 h, fly 3 h, 1.90 km/s planned, 1.83 flown, 1.38 to match (`godot/tests/planner_test.gd`). The grid's steps are design values.
- **Tracking alongside (0.7).** With HYDRA a few km from the inspector, a seen burn widened the track to tens of km; the unscented bearing update then had its sample points all round the sensor, and the estimate ran off by 1,000 km and more while claiming under 1 km. Close in (1σ over a tenth of the range, a design value) a bearing now goes in as a straight-line measurement, the distance across the line of bearing 0 ± σ·range (the pseudo-linear estimator: Lindgren & Gong 1978, IEEE Trans. AES 14(4); Aidala & Nardone 1982, IEEE Trans. AES 18(4):432–441). Between craft in nearly the same orbit, angles-only range can't be observed without an observer manoeuvre (Woffinden & Geller 2009, IEEE Trans. AES 45(3)), so without a radar range in the last 30 min the estimate keeps at least 0.5 × range of 1σ along the line of sight (design value; the range error held near 0.37 of the range in the shadowing's own runs). The pseudo-linear estimator is known to be biased (Aidala & Nardone 1982; Bu, Meng & Zhou 2021, *Sensors* 21:5444, "can be severe in unfavorable geometries"), so without that range a bearing moves the position estimate only across its line. A bearing whose normalised innovation passes the χ²(1) 99.9 % point (10.83) is taken as a burn nobody saw and widens the track as for up to 50 m/s over the last 10 min (innovation-based manoeuvre detection: Bar-Shalom, Li & Kirubarajan, *Estimation with Applications to Tracking and Navigation*, Wiley 2001, ch. 11 [V-record]; readable: R. Labbe, *Kalman and Bayesian Filters in Python*, ch. 14, manoeuvre detection by the normalised residual [V-text]; χ²(1) at 0.999 is 10.828; the 50 m/s and 10 min are design values). Jamming aims by the uncertainty across the line of sight, which is what a beam has to cover. `godot/tests/shadow_test.gd`: 42 looks from alongside to departure, with every recording analysed as it arrives, none outside 3σ (worst 0.2σ: the track is cautious about range, as it should be without one).
- **Losing its link means leaving (design value).** Cut off from its handler for 3 h, the inspector backs away prograde (4 m/s) and departs. This is grounded in real practice, not a quoted rule: a Progress approach to the ISS was aborted when telemetry was lost ([CBS News, 2 July 2010, Progress M-06M](https://cbsnews.com/network/news/space/home/spacenews/files/64edf1cb54b2a367544df2f7bae69c31-17.html)), and ESA's ATV carried RETREAT and ESCAPE modes for the same reason. The 3 h threshold and the burn are design values. It backs away only if a Blue warship is within 25 km (`RedAI.PRESENCE_KM`); cut off with nobody near, it holds its slot and waits for its link. That split is also a design value: an autonomous vehicle has no reason to abort while nothing threatens it, and it means jamming alone, from out of sight, stalls the inspection without ending it. 25 km is set so that one velocity match keeps HYDRA inside it for the 3 h cut-off (a single match drifts about 20 km in that time).
- **Its radio** reports home after each maneuver: an X-band (8.436 GHz) BPSK burst at 256 kbaud, 10 W into a 0.4 m dish aimed at its handler, 90 s long (design values within ordinary CCSDS practice). It also keeps the existing Red rule: seeing a threat (burning, loud, or inside 150,000 km and closing), it goes quiet for 6 h. That is what makes going dark matter.
- **Compressed timescale (design value).** The real shadowing ran from 30 Sept with maneuvers on 15–19 Oct. The scenario plays it in about 57 h of game time over 3 days, so the hops come every few orbits.
- **Measured ranges (`godot/tests/measure_shadow.gd`, thousand km, IR at S/N 5).**

  | Observer → target | Coasting | Dark | Radiator face-on | Burning | In Jupiter's shadow |
  |---|---|---|---|---|---|
  | HYDRA's 0.5 m LWIR → the KITE | 200.6 | 200.6 | 200.6 | 313.4 | 195.5 |
  | The KITE's 0.1 m camera → HYDRA | 293.2 | 167.7 | 5,167.5 | 1,716.7 | 155.3 |
  | The KITE's camera → ORIEL-36 | 181.8 | | | | |

  HYDRA starts at 1.5 Rj, ~14,000 km above ORIEL-36's orbit and 38° behind, so the KITE can't see it until it closes, and sees it far sooner coasting than dark. HYDRA's ears hear the KITE's reports from 1.57 million km (90° off its beam); the Ganymede station from 20.46 million km.

- **Jamming its uplink** from beside it. Before its report is identified HYDRA can only barrage the 45 MHz uplink band: +29.0 dB at 500 km, +23.4 at 1,000, +17.5 at 2,000, +14.0 at 3,000, +9.5 at 5,000 and +3.5 dB at 10,000 km. Once identified, spot jamming puts it all on the 1 MHz channel, 16.5 dB more (10·log₁₀ 45). So HYDRA can hold the link cut from a few thousand km; it doesn't have to come close.

### 8.5 Track ageing and drop (24 Oct 2026)

- A contact on the map sits at its **last known position** (`Track.lkp`), where the filter put it on the last look that detected it. It moves only when a sensor detects it again, and then it jumps to the new fix. Between detections the uncertainty ellipse keeps growing around the filter's prediction, which is where it may be now. The planner aims there.
- **Drop.** A track nobody has detected for 24 h, or whose 1σ position is wider than 100,000 km, is deleted ("dropped") and has to be found again from fresh crossing bearings. Real trackers delete tracks that go unconfirmed for a number of scans or whose gate grows too wide (S. Blackman & R. Popoli, *Design and Analysis of Modern Tracking Systems*, Artech House, 1999, track confirmation and deletion [V-record]; readable: MathWorks `trackHistoryLogic` documentation, which cites Blackman & Popoli for M-of-N confirmation and deletion [V-text]). Both thresholds are design values. In 72 h with Blue idle no track drops in either campaign (`godot/tests/measure_drop.gd`): every Red ship is detected at least once a day. `godot/tests/drop_test.gd` checks the rule.

### 8.6 Contact symbols and their ageing (24 Oct 2026)

- **Standard.** Contacts are drawn after *MIL-STD-2525D, Department of Defense Interface Standard: Joint Military Symbology* (Joint Chiefs of Staff / DISA, 10 June 2014), https://www.jcs.mil/Portals/36/Documents/Doctrine/Other_Pubs/ms_2525d.pdf. Its NATO counterpart is *APP-6(D) NATO Joint Military Symbology* (NATO Standardization Office, STANAG 2019 Ed. 7, 2017). 2525D was later superseded by 2525E, which has the same frames for these cases; 2525E is published through the DLA ASSIST database, and we have not read it.
  - **Space frames.** The space symbol set is set 05 (2525D Table 1-1, *Standard Identities and Dimensions*; space icons in Tables 6-3 to 6-5). Friend is an arc, hostile a pointed roof, neutral a box and unknown/pending a clover top. All of them are open at the bottom like the air frames, with the space dimension's solid bar across the top.
  - **Colours.** Friend is cyan/blue, hostile red, neutral green, and unknown and pending yellow. As a cross-check, milsymbol's default "Medium" fills are friend rgb(0,168,220), hostile rgb(255,48,49), neutral rgb(0,226,110) and unknown rgb(255,255,0) (milsymbol, https://github.com/spatialillusions/milsymbol). The game keeps its own lighter tints of the same four hues so they read on the black map.
  - **Old positions.** A dashed frame is 2525D's status for an *anticipated, planned or suspected* position, as opposed to a *present* one (Table 1-2, *Present and Planned Status*). The game uses it for a contact drawn at its last known position while no sensor holds it.
- **Not read directly [to verify].** The jcs.mil PDF refused our fetch (HTTP 403), and it was not downloaded. The table numbers above come from milsymbol's 2525D test pages, which reproduce the standard's tables, https://cdn.jsdelivr.net/npm/milsymbol-esm@2.2.2/docs/milsymbol-2525d.html. The frame geometry is drawn from those and from 2525D as commonly implemented. Check it against the PDF before calling it exact.
- **NTDS style (the default).** The second style is a minimal one in the manner of the Naval Tactical Data System displays: open outlines over a dot. Friend is a semicircle, hostile a chevron, and unknown or neutral a half-square, using the air/space "upper half" shapes since NTDS has no space set. It is a simplified rendering of a historical naval convention, not a copy of any commercial game's art. Every symbol is drawn as vector lines in `Style.draw_symbol`. Switch styles under Map layers > Contact symbols (`user://settings.cfg`, `[map] symbols`).
- **Icon-only map.** The map prints nothing beside a contact's icon. Hovered or selected, it shows three plain lines, the way naval tactical displays label a track: its name, its course (degrees clockwise from the map frame's +y axis, 000–359°) and its speed. Range, 1σ and time since last detection are in the Overview and Selected windows. The acting ship and the camera's focus keep a short name.
- **Ageing on the map.** A contact out of contact is drawn at `Track.lkp` with a dashed outline. It fades from full strength to about 30 % over the 24 h before it drops (§8.5), and a small dial beside it fills clockwise over the same 24 h. A new detection moves it to the new fix with a brief ring. A dropped track is no longer in `sim.tracks` and simply stops being drawn. The fade curve and the dial are design choices, not part of the standard.

### 8.9 Ground radar passes, range after a burn, and custody (2 Nov 2026)

- **Radars measure all through a pass.** A ground radar used to measure once a sensor look (10 min). A pass above PFISR's 45° or LeoLabs' 30° lasts a few minutes, so most passes fell between two looks and went unmeasured (in a 24 h CLOSE PASS run the radars could see Cosmos 2612 for 4 to 8 min each). Each site now measures every `cadence_s` of its radar block (10 s in the scenario's sites; a design value for a radar keeping one object in track, where the real ones measure more often) while anything is in its view, between the looks too (`Sensing.plan_fixes`). Which minutes hold a pass is found on Kepler orbits once a minute with a margin of 15° and 20 % of reach; whether each fix happens is decided on the true state at its moment. In `godot/tests/track3d_test.gd` a catalogued craft is measured 54 times in 4 passes in a day, where it was measured on 1 look; it ends the day 0.8 km off the truth, not 25.9 km.
- **Range after a burn.** Telescopes range a hull of known size by the angle it spans (σR ≈ R²·1.22λ/(D·L), §8.4): metres at a few km, about 1.5 km at 30 km. After a burn nobody saw, the filter's velocity is off and its range with it, yet it went on claiming the range it had before (in the 24 h run: 2 km off along the line of sight for an hour while claiming 130 m). Angles alone cannot tell the range of a craft in nearly the same orbit (Woffinden & Geller 2009, above), so from a track's first burn (seen, or shown by a sighting outside the gate) the estimate claims no better along the line of sight than the ranges measured since the last burn, taken together: 1/√Σ(1/σᵢ²) (`Track.range_floor`). One radar fix settles it; a far telescope's ranges settle it slowly.
- **Custody.** The objective counted the track as held whenever its own 1σ was under 1 km. It now needs that and the estimate truly within 1 km of the truth, at the moment of each look (`Campaign`). With the two changes above, in the 24 h run with no orders, the track is within 1 km of the truth 92 % of the time and claims so 92 %, where before it was 78 % and claimed 93 %; the share of the time it was more than 3σ and 300 m off fell from 56 % to 5 %, nearly all of it after burns no sensor saw.

**Solar system, shadows and interplanetary flight (§8.7)**
61. Standish, E. M. & Williams, J. G., *Keplerian Elements for Approximate Positions of the Major Planets*, JPL Solar System Dynamics. https://ssd.jpl.nasa.gov/planets/approx_pos.html
62. Park, R. S., Folkner, W. M., Williams, J. G. & Boggs, D. H. (2021), The JPL Planetary and Lunar Ephemerides DE440 and DE441, *AJ* 161:105. doi:10.3847/1538-3881/abd414
63. Archinal, B. A. et al. (2018), Report of the IAU Working Group on Cartographic Coordinates and Rotational Elements: 2015, *Celest. Mech. Dyn. Astron.* 130:22. doi:10.1007/s10569-017-9805-5
64. IAU (2015), Resolution B3 on recommended nominal conversion constants for selected solar and planetary properties. https://www.iau.org/static/resolutions/IAU2015_English.pdf
65. JPL Horizons system, vector tables (fetched by `tools/verify/fetch_planets.py`). https://ssd.jpl.nasa.gov/horizons/
66. Cox, A. N. ed. (2000), *Allen's Astrophysical Quantities*, 4th ed., Springer.
67. Montenbruck, O. & Gill, E. (2000), *Satellite Orbits: Models, Methods and Applications*, Springer. doi:10.1007/978-3-642-58351-3
68. Aarseth, S. J. (2003), *Gravitational N-Body Simulations*, Cambridge University Press.
69. Gilmore, D. G. ed. (2002), *Spacecraft Thermal Control Handbook*, vol. 1, 2nd ed., The Aerospace Press.
70. Incropera, F. P., DeWitt, D. P., Bergman, T. L. & Lavine, A. S. (2007), *Fundamentals of Heat and Mass Transfer*, 6th ed., Wiley.
71. Curtis, H. D. (2020), *Orbital Mechanics for Engineering Students*, 4th ed., Butterworth-Heinemann.
72. Vallado, D. A. (2013), *Fundamentals of Astrodynamics and Applications*, 4th ed., Microcosm Press.
73. Broyden, C. G. (1965), A class of methods for solving nonlinear simultaneous equations, *Math. Comp.* 19:577–593. doi:10.1090/S0025-5718-1965-0198670-6
74. Press, W. H., Teukolsky, S. A., Vetterling, W. T. & Flannery, B. P. (2007), *Numerical Recipes*, 3rd ed., Cambridge University Press.

**Corroborating sources added in the 25 Oct 2026 source audit** (readable copies of values whose primary source is paywalled or a book)
75. Chase, M. W. (1998), *NIST-JANAF Thermochemical Tables*, 4th ed., *J. Phys. Chem. Ref. Data* Monograph 9 (aluminium, solid: Cp 24.20 J/(mol·K) at 298.15 K); via the NIST Chemistry WebBook, SRD 69. https://webbook.nist.gov/cgi/cbook.cgi?ID=C7429905&Mask=2
76. NAIF/JPL (2022), generic PCK kernel pck00011.tpc (IAU WGCCRE 2015 constants). https://naif.jpl.nasa.gov/pub/naif/generic_kernels/pck/pck00011.tpc
77. Weber, B., *Orbital Mechanics & Astrodynamics* (open textbook, CC BY-SA 4.0). https://orbital-mechanics.space/
78. NASA (2022), *Astrodynamics Convention and Modeling Reference for Lunar, Cislunar, and Libration Point Orbits*, NASA/TP-20220014814. https://ntrs.nasa.gov/citations/20220014814
79. Pelupessy, F. I., Jänes, J. & Portegies Zwart, S. (2012), N-body integrators with individual time steps from hierarchical splitting, *New Astron.* 17:711. arXiv:1205.5668
80. Bindel, D. (2023), CS 4220 lecture notes, 14 Apr 2023, "Broyden", Cornell University. https://www.cs.cornell.edu/courses/CS4220/2023sp/lec/2023-04-14.pdf
81. Gaite, J. & Fernández-Rico, G. (2012), Linear approach to the orbiting spacecraft thermal problem, *J. Thermophys. Heat Transf.* 26:511–522. arXiv:1202.4372
82. Tripathi, A. K., Chaubey, S. & Singh, A. K. (2020), Study of limb darkening effect and rotation period of Sun by using solar telescope, *J. Sci. Res. (BHU)* 64(1). doi:10.37398/JSR.2020.640132
83. Stokes, G. H., Evans, J. B., Viggh, H. E. M., Shelly, F. C. & Pearce, E. C. (1998), The Lincoln Near-Earth Asteroid Research (LINEAR) Program, *Lincoln Lab. J.* 11(1):27–40. https://archive.ll.mit.edu/publications/journal/pdf/vol11_no1/11_1linear.pdf
84. Madhusudhan, N. & Burrows, A. (2012), Analytic models for albedos, phase curves, and polarization of reflected light from exoplanets, *ApJ* 747:25, eq. 3. doi:10.1088/0004-637X/747/1/25
85. Condon, J. J. & Ransom, S. M. (2016), *Essential Radio Astronomy*, ch. 3 (NRAO online edition). https://www.cv.nrao.edu/~sransom/web/Ch3.html
86. Rashid, M. & Nanzer, J. A. (2024), Expectation maximization aided modified weighted sequential energy detector for distributed cooperative spectrum sensing, arXiv:2403.19556
87. Fowler, M. L., EECE 522 Notes 15, "ML for TDOA/FDOA" (revised), Binghamton University. https://ws2.binghamton.edu/fowler/fowler%20personal%20page/EE522_files/EECE%20522%20Notes_15%20ML%20for%20TDOA-FDOA_revised.pdf
88. Lindgren, A. G. & Gong, K. F. (1978), Position and velocity estimation via bearing observations, *IEEE Trans. AES* 14(4):564–577.
89. Aidala, V. J. & Nardone, S. C. (1982), Biased estimation properties of the pseudolinear tracking filter, *IEEE Trans. AES* 18(4):432–441.
90. Bu, S., Meng, A. & Zhou, G. (2021), *Sensors* 21(16):5444. https://pmc.ncbi.nlm.nih.gov/articles/PMC8399602/
91. Labbe, R. R., *Kalman and Bayesian Filters in Python* (open textbook, CC BY 4.0), ch. 7 and ch. 14. https://github.com/rlabbe/Kalman-and-Bayesian-Filters-in-Python
92. MathWorks, `trackHistoryLogic`, Sensor Fusion and Tracking Toolbox documentation. https://www.mathworks.com/help/fusion/ref/trackhistorylogic.html
93. Sankhe, K. et al. (2019), ORACLE: Optimized Radio clAssification through Convolutional neuraL nEtworks, arXiv:1812.01124
94. ITU-R P.372-17 (08/2024), *Radio noise* (T0 = 290 K, §2). https://www.itu.int/dms_pubrec/itu-r/rec/p/R-REC-P.372-17-202408-S!!PDF-E.pdf
95. JPL, *DSN Telecommunications Link Design Handbook* 810-005, Module 104 Rev. O, *34-m BWG Stations Telecommunications Interfaces* (Table 8 gain, Table 11 system temperatures). https://deepspace.jpl.nasa.gov/dsndocs/810-005/104/104O.pdf
96. CCSDS 401.0-B-32 (Oct 2021), *Radio Frequency and Modulation Systems, Part 1* (Recs 2.4.17B, 2.4.18, 2.6.2). https://public.ccsds.org/Pubs/401x0b32.pdf
97. Simon, A. A., Wong, M. H. & Orton, G. S. (2015), First results from the Hubble OPAL program: Jupiter in 2015, *ApJ* 812:55. doi:10.1088/0004-637X/812/1/55 (maps: MAST HLSP "OPAL", https://archive.stsci.edu/hlsp/opal)
98. NASA/JPL/Space Science Institute (2006), PIA07782, *Cassini's Best Maps of Jupiter (Cylindrical Map)*. https://science.nasa.gov/photojournal/cassinis-best-maps-of-jupiter-cylindrical-map
99. Binder, A. B. & McCarthy, D. W. (1973), IR spectrophotometry of Jupiter and Saturn, Appendix A of IIT Research Institute final report, NASA contract NASW-2363. NTRS 19730014045. https://ntrs.nasa.gov/citations/19730014045
100. Mendikoa, I., Sánchez-Lavega, A., Pérez-Hoyos, S., Hueso, R., Rojas, J. F. & López-Santiago, J. (2017), Temporal and spatial variations of the absolute reflectivity of Jupiter and Saturn from 0.38 to 1.7 µm with PlanetCam-UPV/EHU, *A&A* 607:A72. arXiv:1709.09664
101. de Pater, I., Hamilton, D. P., Showalter, M. R., Throop, H. B. & Burns, J. A. (2018), The Rings of Jupiter, ch. 6 in *Planetary Ring Systems*, eds. M. S. Tiscareno & C. D. Murray, Cambridge University Press. arXiv:1707.00806
102. Ockert-Bell, M. E. et al. (1999), The structure of Jupiter's ring system as revealed by the Galileo imaging experiment, *Icarus* 138:188–213. [V-record, via ref. 101]
103. Burns, J. A. et al. (1999), The formation of Jupiter's faint rings, *Science* 284:1146–1150. [V-record, via ref. 101]
