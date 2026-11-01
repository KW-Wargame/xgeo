"""The force model (Jupiter point mass + J2 + the four Galilean moons) and the
game's RK4 integrator, against hapsira's perturbation functions, a numerical
gradient of the J2 potential, scipy DOP853, and the analytic J2 secular rates."""
import math

import numpy as np
from hapsira.core.elements import rv2coe

import refs

MODEL = "gravity"


def _env(game):
    c = game["constants"]
    return c["mu"], c["J2"], c["R_REF"], c["moons"], c["epochOffset"]


def test_moon_port_matches_game(game, check):
    """refs.game_moon_state is a transcription used only to drive the reference integrator: check it first."""
    mu, J2, R, moons, eo = _env(game)
    worst = 0.0
    for m in moons:
        for row in game["moons"][m["id"]][::7]:
            worst = max(worst, np.linalg.norm(refs.game_moon_state(m, eo + row["t"]) - np.array(row["out"]["r"])))
    check.bound("python transcription of the moon model = game", worst, 1e-3, "game's own moon states", unit="km")


def _j2_potential_grad(r, mu, J2, R, h=1.0):
    """a = grad V_J2, V_J2 = -(mu/r) J2 (R/r)^2 P2(z/r) = -mu J2 R^2 (3 z^2 - r^2) / (2 r^5), by central differences."""
    def U(p):
        rn = np.linalg.norm(p)
        return -mu * J2 * R * R * (3 * p[2] ** 2 - rn ** 2) / (2 * rn ** 5)
    g = np.zeros(3)
    for i in range(3):
        e = np.zeros(3)
        e[i] = h
        g[i] = (U(r + e) - U(r - e)) / (2 * h)
    return g


def test_acceleration(game, check):
    mu, J2, R, moons, eo = _env(game)
    w = {"j2": 0.0, "moons": 0.0, "both": 0.0, "point": 0.0, "j2grad": 0.0}
    for c in game["gravity"]["accel"]:
        r, t, a = np.array(c["r"]), c["t"], np.array(c["a"])
        ref = refs.accel(r, t, mu, J2, R, moons, eo, c["j2"], c["moons"])
        pm = -mu * r / np.linalg.norm(r) ** 3
        pert_game, pert_ref = a - pm, ref - pm
        key = "both" if c["j2"] and c["moons"] else "j2" if c["j2"] else "moons" if c["moons"] else "point"
        if key == "point":
            w[key] = max(w[key], np.linalg.norm(a - ref) / np.linalg.norm(ref))
        else:
            w[key] = max(w[key], np.linalg.norm(pert_game - pert_ref) / np.linalg.norm(pert_ref))
        if key == "j2":
            w["j2grad"] = max(w["j2grad"], np.linalg.norm(pert_game - _j2_potential_grad(r, mu, J2, R)) / np.linalg.norm(pert_game))
    check.bound("point mass", w["point"], 1e-14, "Newton")
    check.bound("J2 perturbation vs hapsira", w["j2"], 1e-12, "hapsira.core.perturbations.J2_perturbation", note="relative to the perturbation itself")
    check.bound("J2 perturbation vs gradient of the J2 potential", w["j2grad"], 1e-6, "numerical gradient of the zonal potential (Vallado 2013 sec. 8.7)")
    check.bound("moons' third-body pull vs hapsira", w["moons"], 1e-9, "hapsira.core.perturbations.third_body (Curtis 2020 sec. 12.10)", note="direct minus indirect term")
    check.bound("J2 + moons together", w["both"], 1e-9, "hapsira", note="1e-9: the reference reads moon positions from a transcription good to 2e-6 km")


def test_integrator_vs_dop853(game, check):
    mu, J2, R, moons, eo = _env(game)
    worst = {}
    for c in game["gravity"]["coast"]:
        if c["name"] == "j2_secular":
            continue
        s = c["samples"]
        t_eval = [x["t"] for x in s]
        sol = refs.integrate(np.array(s[0]["r"]), np.array(s[0]["v"]), c["t0"], c["dt"], mu, J2, R, moons, eo, c["j2"], c["moons"], t_eval=t_eval)
        err = max(np.linalg.norm(np.array(x["r"]) - sol.y[:3, k]) for k, x in enumerate(s))
        if err > worst.get("err", 0.0):
            worst = {"err": err, "name": c["name"]}
    check.bound(f"Gravity.coast (DOP853, rtol 1e-12), 1 day, J2 + moons (worst: {worst['name']})", worst["err"], 1e-5, "scipy DOP853 (rtol 1e-13) on hapsira's force terms",
                unit="km", note="1 cm, against a need of 5 m (a tenth of the radar's 50 m range sigma, the finest measurement in the game)")


def test_transition_matrix(game, check):
    """Gravity.coast_stm, the tracker's covariance under the full force model: its matrix
    against central differences of whole reference coasts (no variational equations of
    our own to share a mistake with), and its end state against the plain coast."""
    mu, J2, R, moons, eo = _env(game)
    worst, wend = 0.0, 0.0
    steps = [1.0, 1.0, 1.0, 1e-4, 1e-4, 1e-4]
    for c in game["gravity"]["stm"]:
        x0, dt = np.array(c["r"] + c["v"]), c["dt"]
        F = np.array(c["phi"])
        end = refs.integrate(x0[:3], x0[3:], c["t0"], dt, mu, J2, R, moons, eo, t_eval=[c["t0"] + dt]).y[:, -1]
        wend = max(wend, np.linalg.norm(np.array(c["r1"]) - end[:3]))
        for j in range(6):
            up, dn = x0.copy(), x0.copy()
            up[j] += steps[j]
            dn[j] -= steps[j]
            a = refs.integrate(up[:3], up[3:], c["t0"], dt, mu, J2, R, moons, eo, t_eval=[c["t0"] + dt]).y[:, -1]
            b = refs.integrate(dn[:3], dn[3:], c["t0"], dt, mu, J2, R, moons, eo, t_eval=[c["t0"] + dt]).y[:, -1]
            col = (a - b) / (2 * steps[j])
            scale = np.array([1, 1, 1, dt, dt, dt]) * (1.0 if j < 3 else 1.0 / dt)  # each block dimensionless by the coast's length
            worst = max(worst, np.max(np.abs(F[:, j] - col) * scale))
    n = len(game["gravity"]["stm"])
    check.bound(f"Gravity.coast_stm end state, {n} ships over 6 h", wend, 1e-5, "scipy DOP853 (rtol 1e-13) on hapsira's force terms", unit="km")
    check.bound(f"Gravity.coast_stm transition matrix, {n} ships over 6 h (one off the plane)", worst, 1e-5,
                "central differences (1 km, 1e-4 km/s) of scipy DOP853 coasts on hapsira's J2 and third-body terms",
                note="each block scaled by the coast's length to be dimensionless; differencing whole coasts is itself good to about 1e-6")


def test_j2_secular_rates(game, check):
    """Analytic first-order J2 secular rates (Vallado 2013 eqs. 9-41, 9-42; Curtis 2020 eqs. 4.52-4.53):
    dOmega/dt = -3/2 n J2 (R/p)^2 cos i,  domega/dt = 3/4 n J2 (R/p)^2 (5 cos^2 i - 1)."""
    mu, J2, R, moons, eo = _env(game)
    c = next(x for x in game["gravity"]["coast"] if x["name"] == "j2_secular")
    t, raan, argp, a_s, e_s, i_s = [], [], [], [], [], []
    for x in c["samples"]:
        p, ecc, inc, O, w, nu = rv2coe(mu, np.array(x["r"]), np.array(x["v"]))
        t.append(x["t"]), raan.append(O), argp.append(w), a_s.append(p / (1 - ecc ** 2)), e_s.append(ecc), i_s.append(inc)
    t = np.array(t)
    a, e, i = np.mean(a_s), np.mean(e_s), np.mean(i_s)
    n = math.sqrt(mu / a ** 3)
    p = a * (1 - e * e)
    k = n * J2 * (R / p) ** 2
    dO = -1.5 * k * math.cos(i)
    dw = 0.75 * k * (5 * math.cos(i) ** 2 - 1)
    fO = np.polyfit(t, np.unwrap(raan), 1)[0]
    fw = np.polyfit(t, np.unwrap(argp), 1)[0]
    ref = "first-order secular theory, Vallado 2013 eqs. 9-41/9-42"
    check.rel("nodal regression rate", fO, dO, 0.01, ref, note=f"{math.degrees(dO) * 86400 * 20:.1f} deg over 20 days; residual is J2^2 and short-period terms")
    check.rel("apsidal advance rate", fw, dw, 0.01, ref, note=f"{math.degrees(dw) * 86400 * 20:.1f} deg over 20 days")
    sol = refs.integrate(np.array(c["samples"][0]["r"]), np.array(c["samples"][0]["v"]), 0.0, c["dt"], mu, J2, R, moons, eo, True, False, t_eval=[c["dt"]])
    check.bound("20-day J2 arc, Gravity.coast vs scipy DOP853", np.linalg.norm(np.array(c["samples"][-1]["r"]) - sol.y[:3, -1]), 0.001, "scipy DOP853 rtol 1e-13",
                unit="km", note="a 0.58-day orbit at 3 Jupiter radii, 34 revolutions")
