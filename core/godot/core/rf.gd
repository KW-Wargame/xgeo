## Radio and infrared physics, SI units. A port of src/engine/rf.js,
## sensors.js and signals.js (the parts the 3D game needs first).
## - Friis transmission formula, Pr = Pt Gt Gr (λ/4πR)² (Friis 1946; NAWCWD TP 8347,
##   2013, §4-3).
## - Dish gain G = η(πD/λ)² (Skolnik 2008; ITU-R SA.509-3, recommends 1.3). Noise N = kTB.
## - Radiometer equation: integrating τ seconds over bandwidth B multiplies
##   SNR by √(Bτ) (Wilson, Rohlfs & Hüttemeister 2013; Condon & Ransom, Essential
##   Radio Astronomy, §3.6.2, eq. 3.154).
## - Interferometer bearing σθ = σφ·λ/(2πd) (Poisel 2012; Thompson, Moran & Swenson
##   2017, eq. 12.1), with the phase error of a cross-correlation of two elements
##   σφ² = (1 + 2s)/(2 n s²) for per-sample SNR s over n = Bτ samples. The
##   weak-signal limit is TMS 2017 §6.2.4, eq. 6.64; the (1 + 2s) factor follows
##   from the Knapp & Carter (1976) Cramér–Rao bound in terms of coherence,
##   γ² = s²/(1 + s)², in the narrowband limit. About 1/(√2·SNR) in the integrated
##   SNR the game detects with.
## - Grey-body emission P = εσT⁴A; irradiance at range R is P/(4πR²) (Hudson 1969;
##   OpenStax University Physics 2, §1.6).
## - Diffraction limit 1.22λ/D (Hecht 2017; OpenStax University Physics 3, §4.5, Eq. 4.5).
class_name RF

const C_MS := 299792458.0
const K_BOLTZ := 1.380649e-23
const SIGMA_SB := 5.670374419e-8


static func db(x: float) -> float:
	return 10.0 * log(x) / log(10.0)


static func from_db(d: float) -> float:
	return pow(10.0, d / 10.0)


static func wavelength(f: float) -> float:
	return C_MS / f


static func dish_gain(D: float, f: float, eff := 0.55) -> float:
	return eff * pow(PI * D / wavelength(f), 2.0)


static func friis(Pt: float, Gt: float, Gr: float, R: float, f: float) -> float:
	return Pt * Gt * Gr * pow(wavelength(f) / (4.0 * PI * R), 2.0)


static func noise(Ts: float, B: float) -> float:
	return K_BOLTZ * Ts * B


static func integrate(snr: float, B: float, tau: float) -> float:
	return snr * sqrt(B * maxf(tau, 0.0))


## 1σ bearing (rad, broadside) from an interferometer of baseline d (m) on a
## signal heard at integrated SNR snr (= s√n, the radiometer SNR) over n = Bτ
## samples. Without n, the weak-signal limit s ≪ 1, σφ = 1/(√2·snr) (the sim
## always passes n; loud relays inside ~10⁶ km reach s ~ 0.2). Verified by Monte
## Carlo of the correlator in tools/verify/tests/test_df.py.
static func df_sigma(f: float, d: float, snr: float, n := 0.0) -> float:
	var q := maxf(snr, 1e-9)
	var var_phi := 1.0 / (2.0 * q * q)
	if n > 0.0:
		var_phi *= 1.0 + 2.0 * q / sqrt(n)
	return wavelength(f) / (TAU * d) * sqrt(var_phi)


static func diffraction(lam: float, D: float) -> float:
	return 1.22 * lam / D


## How far (km) a receiver hears an emitter that lasts `seconds`, at the
## detection threshold. emitter: {Pt, G, f, bw}; esm: {dish, Ts}.
static func intercept_range_km(emitter: Dictionary, esm: Dictionary, seconds: float, detect_snr: float) -> float:
	var at1m := integrate(friis(emitter.Pt, emitter.G, dish_gain(esm.dish, emitter.f), 1.0, emitter.f) / noise(esm.Ts, emitter.bw), emitter.bw, seconds)
	return sqrt(at1m / detect_snr) / 1000.0


static func grey(sig: Dictionary) -> float:
	return float(sig.eps) * SIGMA_SB * pow(float(sig.T), 4.0) * float(sig.A)


## IR detection ranges (km) coasting and burning, for a sensor of this NEI (W/m²).
static func signature_ranges(sig: Dictionary, engine, nei: float) -> Dictionary:
	var cold := grey(sig) / (4.0 * PI)
	var hot := cold + (grey(engine.hot) / (4.0 * PI) if engine != null else 0.0)
	return {"cold": sqrt(cold / nei) / 1000.0, "burning": sqrt(hot / nei) / 1000.0}


## Δv left (km/s) by the rocket equation.
static func delta_v(ve: float, dry: float, prop: float) -> float:
	return ve * log((dry + prop) / dry) if prop > 0.0 else 0.0


## Complementary error function, Numerical Recipes in C (Press et al. 1992,
## 2nd ed., §6.2, erfcc): Chebyshev fit, fractional error below 1.2e-7 everywhere,
## so the far tail that false-alarm rates live in stays accurate.
static func erfc(x: float) -> float:
	var z := absf(x)
	var t := 1.0 / (1.0 + 0.5 * z)
	var ans := t * exp(-z * z - 1.26551223 + t * (1.00002368 + t * (0.37409196 + t * (0.09678418 + t * (-0.18628806 + t * (0.27886807 + t * (-1.13520398 + t * (1.48851587 + t * (-0.82215223 + t * 0.17087277)))))))))
	return ans if x >= 0.0 else 2.0 - ans


## Standard normal tail Q(x) = P(N(0,1) > x), and its inverse (by bisection).
static func q(x: float) -> float:
	return 0.5 * erfc(x / sqrt(2.0))


static func q_inv(p: float) -> float:
	var lo := -12.0
	var hi := 12.0
	for i in 80:
		var m := 0.5 * (lo + hi)
		if q(m) > p:
			lo = m
		else:
			hi = m
	return 0.5 * (lo + hi)


## Probability an energy detector (radiometer) set for false-alarm rate pfa sees a
## signal of integrated SNR snr over n = Bτ samples, in the Gaussian approximation
## (Urkowitz 1967, "Energy detection of unknown deterministic signals", Proc. IEEE 55;
## the same moments as Rashid & Nanzer 2024, arXiv:2403.19556, eqs. 2–3):
## the statistic's mean rises by snr noise-sigmas and its spread by √(1 + 2s),
## s = snr/√n the per-sample SNR. Pd = Q((Q⁻¹(pfa) − snr)/√(1 + 2s)).
static func detect_pd(snr: float, pfa: float, n := 0.0) -> float:
	var s := snr / sqrt(n) if n > 0.0 else 0.0
	return q((q_inv(pfa) - snr) / sqrt(1.0 + 2.0 * s))


## ln k! (exact sum below 20, Stirling's series above: error under 1e-14).
static func log_fact(k: int) -> float:
	if k < 20:
		var s := 0.0
		for i in range(2, k + 1):
			s += log(float(i))
		return s
	var x := float(k + 1)
	return (x - 0.5) * log(x) - x + 0.5 * log(TAU) + 1.0 / (12.0 * x) - 1.0 / (360.0 * pow(x, 3.0)) + 1.0 / (1260.0 * pow(x, 5.0))


## Q(n, T) = e^-T Σ_{j<n} T^j/j!: the chance n pulses of noise alone, square-law
## detected and summed (in units of the noise power), pass T.
static func _noise_q(n: int, T: float) -> float:
	var s := 0.0
	for j in n:
		s += exp(-T + (float(j) * log(T) if j > 0 else 0.0) - log_fact(j))
	return s


## The threshold T (noise powers, summed over n pulses) for a false-alarm rate pfa.
static func radar_threshold(pfa: float, n := 1) -> float:
	var lo := 0.0
	var hi := float(n) + 20.0 * sqrt(float(n)) + 80.0
	for i in 100:
		var m := 0.5 * (lo + hi)
		if _noise_q(n, m) > pfa:
			lo = m
		else:
			hi = m
	return 0.5 * (lo + hi)


## Probability a radar detects a target of mean per-pulse SNR snr in n pulses
## integrated noncoherently (square law) at false-alarm rate pfa, for Swerling's
## target cases (Swerling 1960, IRE Trans. IT-6; Marcum 1960): 0, a steady
## echo; 1 and 3, an echo that fluctuates from scan to scan (Rayleigh, and one
## dominant scatterer: χ² with 2 and 4 degrees of freedom); 2 and 4, the same
## from pulse to pulse. Given the echo energy, the sum is noncentral χ², a
## Poisson mixture of central ones: Pd = Σ_k w_k Q(n + k, T). A steady echo
## gives Poisson weights of mean E = n·snr; the fluctuating cases make E itself
## Gamma-distributed with shape m (1, n, 2, 2n for cases 1 to 4: independent
## pulses add their shapes), which turns the weights negative binomial,
## w_k = C(k+m-1, k) p^m (1-p)^k with p = m/(m + E). Exact, to 1e-12.
static func radar_pd(snr: float, pfa: float, n := 1, swerling := 0) -> float:
	var T := radar_threshold(pfa, n)
	var E := float(n) * maxf(snr, 0.0)
	var m: int = [0, 1, n, 2, 2 * n][clampi(swerling, 0, 4)]
	var lp := log(float(m) / (float(m) + E)) if m > 0 else 0.0
	var lq := log(E / (float(m) + E)) if m > 0 and E > 0.0 else -INF
	# miss = Σ w_k P(n + k, T), with P = 1 − Q falling as k grows.
	var P := 1.0 - _noise_q(n, T)
	var miss := 0.0
	var k := 0
	while k < 2000000:
		var lw: float
		if m == 0:
			lw = -E + (float(k) * log(E) if k > 0 else 0.0) - log_fact(k)
		else:
			lw = log_fact(k + m - 1) - log_fact(k) - log_fact(m - 1) + float(m) * lp + (float(k) * lq if k > 0 else 0.0)
		miss += exp(lw) * P
		var term := exp(-T + float(n + k) * log(T) - log_fact(n + k))
		if P < 1e-17 or (float(n + k) > T + 1.0 and term < 1e-18): # past the peak, P is rounding alone
			break
		P = maxf(0.0, P - term)
		k += 1
	return clampf(1.0 - miss, 0.0, 1.0)
