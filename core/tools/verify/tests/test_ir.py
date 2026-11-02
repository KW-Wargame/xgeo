"""Infrared and visible detection (Godot build, docs/REALISM-SOURCES.md sec. 2):
the game's in-band Planck fractions against astropy's BlackBody, skin and
radiator energy balances, every ship's intensity rebuilt term by term from its
class data and geometry, who sees whom with S/N, Pd and background, visible
magnitudes from the Sun's absolute magnitude, the heat sink's energy
accounting, and the false-alarm rate against its Poisson mean.
"""
import math

import astropy.constants as const
import astropy.units as u
import numpy as np
from astropy.modeling.physical_models import BlackBody
from scipy.integrate import quad
from scipy.stats import norm, poisson

MODEL = "ir"
SIGMA = const.sigma_sb.to(u.W / u.m ** 2 / u.K ** 4).value
BAND = (6.0, 10.0)  # um, NEO Surveyor NC2 (Mainzer et al. 2023)


def _band_radiance(T, lo_um, hi_um):
    """Planck radiance integrated over [lo, hi] (W m^-2 sr^-1), from astropy's BlackBody."""
    bb = BlackBody(temperature=T * u.K, scale=1.0 * u.W / (u.m ** 2 * u.sr * u.m))
    f = lambda lam: bb(lam * u.m).to(u.W / (u.m ** 2 * u.sr * u.m), equivalencies=u.spectral_density(lam * u.m)).value
    edges = np.geomspace(lo_um * 1e-6, hi_um * 1e-6, 40)
    return sum(quad(f, a, b, epsabs=0, epsrel=1e-11)[0] for a, b in zip(edges[:-1], edges[1:]))


_FRAC = {}


def frac(T, lo=BAND[0], hi=BAND[1]):
    """Share of sigma T^4 in [lo, hi] um: pi x the band radiance (Lambertian)."""
    k = (T, lo, hi)
    if k not in _FRAC:
        _FRAC[k] = math.pi * _band_radiance(T, lo, hi) / (SIGMA * T ** 4) if T > 0 else 0.0
    return _FRAC[k]


def skin_T(sig, S, lit):
    a = sig.get("alpha", sig["eps"])
    leak = max(0.0, sig["eps"] * SIGMA * sig["T"] ** 4 * sig["A"] - a * S * sig["A"] / 4)
    q = leak + (a * S * sig["A"] / 4 if lit else 0.0)
    return (q / (sig["eps"] * SIGMA * sig["A"])) ** 0.25 if q > 0 else 3.0


def grey_band(sig, T):
    return sig["eps"] * SIGMA * T ** 4 * sig["A"] * frac(T) / (4 * math.pi)


def rad_I(rad, T, th):
    if T <= 0:
        return 0.0, 0.0
    M = SIGMA * T ** 4 * frac(T) / math.pi
    edge_eps = rad.get("edgeEps", rad["eps"])  # a stealth hull's low-e finish on the edge (Henninger 1984)
    return rad["eps"] * M * rad["A"] * abs(math.cos(th)), edge_eps * M * rad.get("t", 0.02) * math.sqrt(rad["A"]) * abs(math.sin(th))


def waste(cl):
    r = cl.get("thermal", {}).get("reactor")
    return r["kWe"] * 1e3 * (1 / r["eta"] - 1) if r else 0.0


def test_band_fraction(game, check):
    """Widger & Woodall (1976) series against direct integration of Planck's law."""
    for c in game["sensing"]["band"]:
        T = c["T"]
        check.rel(f"6-10 um share of a {T:g} K black body", c["frac"], frac(T), 1e-6, "astropy BlackBody, integrated (Planck 1901)", floor=1e-12)
        check.rel(f"share below 10 um at {T:g} K", c["below10"], frac(T, 0.05, 10.0), 1e-6, "astropy BlackBody, 0.05-10 um", floor=1e-12)


def test_skin_energy_balance(game, check):
    """Sunlight alpha S A/4 on a convex hull plus the internal leak, radiated as eps sigma T^4 A (Stefan-Boltzmann)."""
    for c in game["sensing"]["skins"]:
        s, S = c["sig"], c["S"]
        a = s.get("alpha", s["eps"])
        leak = max(0.0, s["eps"] * SIGMA * s["T"] ** 4 * s["A"] - a * S * s["A"] / 4)
        check.rel(f"{c['class']} internal leak", c["leak"], leak, 1e-9, "eps sigma T_design^4 A - alpha S A/4", floor=1e-6)
        check.rel(f"{c['class']} skin in sunlight", c["T_lit"], skin_T(s, S, True), 1e-9, "energy balance")
        check.rel(f"{c['class']} skin in Jupiter's shadow", c["T_shadow"], skin_T(s, S, False), 1e-9, "energy balance without sunlight")
        check.rel(f"{c['class']} skin in band", c["I_band"], grey_band(s, s["T"]), 1e-6, "eps sigma T^4 A/4 pi x Planck share")


def test_radiators(game, check):
    """Reactor waste P_e(1/eta - 1) on a two-sided Lambertian panel: 2 eps sigma T^4 A = Q, I = eps sigma T^4 A cos(theta)/pi."""
    for c in game["sensing"]["radiators"]:
        th, rad = c["thermal"], c["thermal"]["radiator"]
        Q = th["reactor"]["kWe"] * 1e3 * (1 / th["reactor"]["eta"] - 1)
        check.rel(f"{c['class']} waste heat", c["Q"], Q, 1e-9, "P_e (1/eta - 1)")
        T = (Q / (2 * rad["eps"] * SIGMA * rad["A"])) ** 0.25
        check.rel(f"{c['class']} radiator temperature", c["T"], T, 1e-9, "Q = 2 eps sigma T^4 A")
        for a in c["by_angle"]:
            face, edge = rad_I(rad, T, math.radians(a["theta_deg"]))
            check.rel(f"{c['class']} radiator face at {a['theta_deg']:g} deg", a["I"]["face"], face, 1e-6, "Lambert's cosine law (NAWCWD TP 8347 sec. 7-1)", floor=1e-9)
            check.rel(f"{c['class']} radiator edge at {a['theta_deg']:g} deg", a["I"]["edge"], edge, 1e-6, "edge strip t x sqrt(A), side-on", floor=1e-9)
        if c["class"] == "sentinel":
            # JIMO: 364 kWt from 170 m^2 (both faces), eps 0.9, effective ~457 K against a 200 K sink (Siamidis et al. 2005).
            T_jimo = (364e3 / (0.9 * SIGMA * 170) + 200.0 ** 4) ** 0.25
            check.rel("Warden's radiator vs JIMO's design point", c["T"], T_jimo, 0.02, "Siamidis et al. 2005, NASA/TM-2005-213337 (364 kWt, 170 m^2, 200 K sink)")
        if c["class"] == "pfs":
            check.rel("EXCALIBUR's radiators while the laser fires", c["laser_T"], ((Q + 3e6) / (2 * rad["eps"] * SIGMA * rad["A"])) ** 0.25, 1e-9, "Q + 3 MW of laser waste (25% wall-plug)")


def _shadow(r, u_sun, R_J):
    along = np.dot(r, u_sun)
    return along < 0 and np.linalg.norm(r - along * u_sun) < R_J


def test_intensity_terms(game, check):
    """Every ship toward observers in three directions in the plane, rebuilt from class data and geometry.
    Radiators lie flat to the plane, so every in-plane observer sees them edge-on (90 deg from the normal)."""
    classes = game["platforms"]["classes"]
    g = game["sensing"]["glare"]
    R_J, u_sun, S = game["constants"]["R_J"], np.array(g["sun_dir"]), g["S"]
    bad_shadow = 0
    for c in game["sensing"]["intensity"]:
        cl = classes[c["class"]]
        r, at = np.array(c["r"]), np.array(c["toward"])
        lit = not _shadow(r, u_sun, R_J)
        bad_shadow += lit == c["shadow"]
        Ts = skin_T(cl["sig"], S, lit)
        total = grey_band(cl["sig"], Ts)
        h = c["heat"] or {}
        if cl.get("thermal", {}).get("radiator") and h.get("T_rad", 0) > 0:
            face, edge = rad_I(cl["thermal"]["radiator"], h["T_rad"], math.pi / 2)
            total += face + edge
        d = at - r
        name = f"{c['id']} toward {math.degrees(math.atan2(d[1], d[0])) % 360:.0f} deg"
        check.rel(f"{name}, coasting", c["cold"]["total"], total, 1e-6, "skin + radiator face + edge, in band", floor=1e-12)
        if cl.get("engine"):
            hot = cl["engine"]["hot"]
            check.rel(f"{name}, burning", c["burning"]["total"], total + grey_band(hot, hot["T"]), 1e-6, "plus the nozzle, in band", floor=1e-12)
    check.true(f"Jupiter's shadow ({len(game['sensing']['intensity'])} cases, {bad_shadow} wrong)", bad_shadow == 0, "cylinder behind Jupiter, away from the Sun")


def _occulted(a, b, R):
    """Independent: sample the segment densely and look for any point inside Jupiter."""
    t = np.linspace(0, 1, 20001)[:, None]
    pts = a + (b - a) * t
    return bool(np.min(np.linalg.norm(pts, axis=1)) < R)


def test_occultation(game, check):
    R = game["constants"]["R_J"]
    bad = 0
    for c in game["sensing"]["occult"]:
        a, b = np.array(c["a"]), np.array(c["b"])
        if _occulted(a, b, R * (1 - 1e-4)) != c["blocked"] and _occulted(a, b, R * (1 + 1e-4)) != c["blocked"]:
            bad += 1
    check.true(f"Jupiter blocks the line of sight ({len(game['sensing']['occult'])} random lines, {bad} wrong)", bad == 0, "dense sampling of each segment")


def test_detection(game, check):
    """S/N = I/R^2/(NEI x background); Pd = Phi(S/N - 5) (NEO Surveyor's S/N 5); 'sees' = S/N >= 5 in IR or visible."""
    R_J = game["constants"]["R_J"]
    g = game["sensing"]["glare"]
    k = g["band"]["threshold"]
    bad = uncued = 0
    for c in game["sensing"]["ir_sees"]:
        o, x = np.array(c["or"]), np.array(c["xr"])
        if _occulted(o, x, R_J):
            snr = 0.0
        else:
            ang = math.acos(np.clip(np.dot(-o, x - o) / (np.linalg.norm(o) * np.linalg.norm(x - o)), -1, 1))
            jr = math.asin(min(1.0, R_J / np.linalg.norm(o)))
            # Glare reaches cone x the apparent radius, but no more than 20 deg past the limb
            # (about Hubble's bright-Earth avoidance angle; sensing.gd GLARE_MAX).
            edge = jr + min((g["cone"] - 1) * jr, math.radians(20.0))
            bg = g["band"]["discFactor"] if ang < jr else (g["band"]["glareFactor"] if ang < edge else 1.0)
            snr = c["I"] / (np.linalg.norm(x - o) * 1000) ** 2 / (c["nei_band"] * bg)
            bad += abs(bg - c["bg"]) > 1e-9
        bad += not math.isclose(snr, c["snr"], rel_tol=1e-9, abs_tol=1e-12)
        if c["snr"] > 0:
            bad += not math.isclose(norm.cdf(c["snr"] - k), c["pd"], rel_tol=1e-5, abs_tol=1e-7)
        bad += ((c["snr"] >= k) or (c["vis_snr"] >= k)) != c["sees"]
        uncued += c["vis_snr"] > 0 and not c.get("tracked", True)
    check.true(f"who sees whom at the start ({len(game['sensing']['ir_sees'])} pairs, {bad} differ)", bad == 0, "independent S/N with occultation and background; scipy.stats.norm for Pd")
    check.true(f"visible looks only at tracked ships ({uncued} uncued)", uncued == 0, "narrow-field telescopes are cued (user decision, REALISM-SOURCES sec. 8.3)")
    for s, want in [(4, 0.16), (5, 0.50), (6, 0.84), (7, 0.98)]:
        check.abs(f"Pd at S/N {s}", norm.cdf(s - k), want, 0.005, "REALISM-SOURCES sec. 2 table (Phi(SNR - 5))")


def test_visible(game, check):
    """V magnitude of a Lambert sphere: the Sun's absolute V (4.81, Willmer 2018) moved to 1 AU, dimmed to Jupiter's
    irradiance, times p Phi(alpha) r^2 / R^2 (r^2 = A / 4 pi) with p = 2/3 x diffuse x (1 - alpha_s)."""
    vis = game["sensing"]["glare"]["vis"]
    S = game["sensing"]["glare"]["S"]
    m_1au = vis["sunAbsV"] + 5 * math.log10((1 * u.AU).to(u.pc).value / 10)
    check.abs("the Sun's apparent V at 1 AU", m_1au, -26.76, 0.03, "Torres (2010) V = -26.76 +/- 0.03")
    for c in game["sensing"]["vis"]:
        s, ph = c["sig"], c["phase"]
        phi = (math.sin(ph) + (math.pi - ph) * math.cos(ph)) / math.pi
        p = 2 / 3 * s.get("diffuse", 0.2) * (1 - s.get("alpha", 0.5))
        m = m_1au - 2.5 * math.log10(S / vis["solarConstant"]) - 2.5 * math.log10(p * s["A"] / (4 * math.pi) * phi / c["R_m"] ** 2)
        check.abs(f"{c['x']} seen from {c['o']}: V magnitude", c["mag"], m, 1e-6, "Lambert sphere (Madhusudhan & Burrows 2012, ApJ 747:25, eq. 3)")
        lim = vis["limitMag"] + 2.5 * math.log10(c["aperture"] / vis["refAperture"])
        check.abs(f"{c['o']} limiting magnitude", c["limit"], lim, 1e-9, "GEODSS CCD limit 22 for 1 m (Stokes et al. 1996; LINEAR, Stokes et al. 1998: mag 22 at S/N 4 in < 100 s; the game's S/N 5 is a design value)")
        check.rel(f"{c['x']} seen from {c['o']}: S/N", c["snr"], 5 * 10 ** (-0.4 * (m - lim)), 1e-5, "S/N 5 at the limit, proportional to flux", floor=1e-30)


def test_heat_sink(game, check):
    """While dark the sink takes Q x dt until full and the radiator carries nothing; vented water is gone afterwards."""
    cl = game["platforms"]["classes"]["sentinel"]
    sk = cl["thermal"]["sink"]
    Q = waste(cl)
    cap = sk["kg"] * sk["kJkg"] * 1e3
    look = game["constants"]["LOOK"]
    rows = game["sensing"]["sink"]
    want = 0.0
    bad = 0
    for row in rows[:12]:
        want = min(cap, want + Q * look)
        bad += not math.isclose(row["stored"], want, rel_tol=1e-9)
        bad += row["dark"] and not math.isclose(row["Q"], 0.0, abs_tol=1e-6)
    check.true(f"sink fills at the waste heat while dark ({bad} of 12 looks wrong)", bad == 0, "energy conservation: Q x dt into kg x L")
    check.rel("HYDRA dark time on its vented water", cap / Q / 3600, 5e9 / 395049.5 / 3600, 1e-4, "2 t x 2.5 MJ/kg (Leimkuehler et al. 2011) / 395 kW")
    after = rows[12]
    check.rel("vented water is used up when the radiators come back", after["vented"], rows[11]["stored"], 1e-9, "consumable sink")


def test_false_alarms(game, check):
    fa = game["sensing"]["false_alarms"]
    mu = fa["looks"] * fa["sensors"] * fa["mean_per_sensor"]
    lo, hi = poisson.ppf(1e-4, mu), poisson.ppf(1 - 1e-4, mu)
    check.true(f"false alarms over {fa['looks']} looks: {fa['count']} (Poisson mean {mu:.0f})", lo <= fa["count"] <= hi, "scipy.stats.poisson, 99.98% interval")


def test_signature_ranges(game, check):
    """The database's ranges at S/N 5 for Blue's 0.5 m LWIR, rebuilt."""
    S = game["sensing"]["glare"]["S"]
    nei = game["platforms"]["classes"]["sentinel"]["ir"]["neiBand"]
    for kname, r in game["platforms"]["signature_ranges"].items():
        cl = game["platforms"]["classes"][kname]
        skin = grey_band(cl["sig"], skin_T(cl["sig"], S, True))
        edge = face = 0.0
        if cl.get("thermal", {}).get("radiator"):
            rad = cl["thermal"]["radiator"]
            T = (waste(cl) / (2 * rad["eps"] * SIGMA * rad["A"])) ** 0.25
            face, edge = rad_I(rad, T, 0.0)[0], rad_I(rad, T, math.pi / 2)[1]
        R = lambda I: math.sqrt(I / (5 * nei)) / 1000
        check.rel(f"{kname} seen coasting", r["cold"], R(skin + edge), 1e-6, "sqrt(I / (5 NEI))")
        check.rel(f"{kname} seen radiators face-on", r["face"], R(skin + face), 1e-6, "sqrt(I / (5 NEI))")
        check.rel(f"{kname} seen in shadow", r["shadow"], R(grey_band(cl["sig"], skin_T(cl["sig"], S, False))), 1e-6, "sqrt(I / (5 NEI))")
        if cl.get("engine"):
            hot = cl["engine"]["hot"]
            check.rel(f"{kname} seen burning", r["burning"], R(skin + edge + grey_band(hot, hot["T"])), 1e-6, "sqrt(I / (5 NEI))")
