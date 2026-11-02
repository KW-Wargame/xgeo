/**
 * A study: many runs of a scenario, for each course of action and each value of
 * one setting, spread across the computer's cores, then a report.
 *
 *   node tools/study.mjs study.json [--runs=40] [--jobs=8] [--out=dir]
 *   node tools/study.mjs --scenario=res://data/examples/test_range.json --coa=none,res://data/examples/test_range_coa.json --runs=20 --hours=24
 *
 * A study file (godot/data/examples/test_range_study.json is one):
 *   {"name": "...", "scenario": "res://...", "hours": 48, "runs": 40, "seed": 4417,
 *    "coas": ["none", "res://data/examples/close_pass_shadow.json"],
 *    "set": {"escalation.leaveAt": 50}, "vary": {"path": "red_ai.crowdKm", "values": [3, 5, 8]},
 *    "sample": {"red_ai.evadeKm": [5, 12], "red_ai.evasions": [1, 3]}}
 * "sample" draws those settings afresh for each run (cli/batch.gd --sample): what
 * is not known about Red, spread over the runs.
 * Command-line options override the file's. Paths in "coas" are res:// (the
 * godot/ folder) or relative to the study file.
 *
 * Writes to --out (default studies/<name>-<date>/):
 *   runs.jsonl   every run as cli/batch.gd wrote it
 *   runs.csv     one row per run, for a spreadsheet
 *   summary.json each case and course of action: n, means with 95% intervals,
 *                and the paired difference from the first one
 *   report.html  the same, with charts; opens offline in any browser
 *
 * Runs are paired: run k is the same world for every case and course of action
 * (common random numbers, cli/batch.gd), so differences are measured on pairs.
 * Intervals: Wilson's score interval for shares (Wilson 1927); Student's t for
 * means and for paired differences (Law 2015, Simulation Modeling and Analysis,
 * 5th ed., §9.4 and §10.2).
 */
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const proj = path.join(root, 'godot');
const winget = path.join(os.homedir(), 'AppData/Local/Microsoft/WinGet/Packages');
const godot = process.env.GODOT ?? (fs.existsSync(winget)
  ? fs.readdirSync(winget).filter(d => d.startsWith('GodotEngine.GodotEngine')).map(d => path.join(winget, d)).flatMap(d => fs.readdirSync(d).filter(f => /_console\.exe$/.test(f)).map(f => path.join(d, f)))[0]
  : 'godot');

// ---------------------------------------------------------------- options
const args = process.argv.slice(2);
const flags = Object.fromEntries(args.filter(a => a.startsWith('--')).map(a => { const i = a.indexOf('='); return i < 0 ? [a.slice(2), 'true'] : [a.slice(2, i), a.slice(i + 1)]; }));
const file = args.find(a => !a.startsWith('--'));
const study = file ? JSON.parse(fs.readFileSync(file, 'utf8')) : {};
const here = file ? path.dirname(path.resolve(file)) : process.cwd();
const coaPath = p => (p === 'none' || p.startsWith('res://') || path.isAbsolute(p)) ? p : path.resolve(here, p);
const opt = {
  name: flags.name ?? study.name ?? 'study',
  scenario: flags.scenario ?? study.scenario,
  hours: Number(flags.hours ?? study.hours ?? 48),
  runs: Number(flags.runs ?? study.runs ?? 20),
  seed: flags.seed ?? study.seed,
  coas: (flags.coa ? flags.coa.split(',') : (study.coas ?? ['none'])).map(coaPath),
  set: flags.set ?? Object.entries(study.set ?? {}).map(([k, v]) => `${k}=${JSON.stringify(v)}`).join(';'),
  sample: flags.sample ?? Object.entries(study.sample ?? {}).map(([k, [a, b]]) => `${k}=${a}..${b}`).join(';'),
  vary: flags.vary ?? (study.vary ? `${study.vary.path}=${study.vary.values.map(v => JSON.stringify(v)).join('|')}` : ''),
};
const jobs = Math.max(1, Math.min(Number(flags.jobs ?? Math.max(1, os.cpus().length - 1)), opt.runs));
const stamp = new Date().toISOString().slice(0, 16).replace(/[:T]/g, '-');
const out = path.resolve(flags.out ?? path.join(root, 'studies', `${opt.name.replace(/[^\w.-]+/g, '_')}-${stamp}`));
fs.mkdirSync(out, { recursive: true });

// ---------------------------------------------------------------- run
const parts = [];
for (let j = 0; j < jobs; j++) {
  const a = Math.floor(j * opt.runs / jobs), b = Math.floor((j + 1) * opt.runs / jobs) - 1;
  if (b >= a) parts.push([a, b]);
}
const t0 = Date.now();
console.log(`${opt.name}: ${opt.runs} runs x ${opt.coas.length} course(s) of action${opt.vary ? ` x ${opt.vary.split('=')[1].split('|').length} values of ${opt.vary.split('=')[0]}` : ''}, ${opt.hours} h each, on ${parts.length} cores`);
const one = ([a, b], k) => new Promise((resolve, reject) => {
  const f = path.join(out, `part${k}.jsonl`);
  const cli = ['--headless', '--path', proj, '--script', 'res://cli/batch.gd', '--', `--coa=${opt.coas.join(',')}`, `--runs=${a}-${b}`, `--hours=${opt.hours}`, `--out=${f}`];
  if (opt.scenario) cli.push(`--scenario=${opt.scenario}`);
  if (opt.seed !== undefined) cli.push(`--seed=${opt.seed}`);
  if (opt.set) cli.push(`--set=${opt.set}`);
  if (opt.vary) cli.push(`--vary=${opt.vary}`);
  if (opt.sample) cli.push(`--sample=${opt.sample}`);
  const p = spawn(godot, cli, { cwd: root, stdio: ['ignore', 'ignore', 'pipe'] });
  let err = '';
  p.stderr.on('data', d => { err += d; });
  p.on('close', code => code === 0 ? resolve(f) : reject(new Error(`runs ${a}-${b}: Godot exited ${code}\n${err.slice(-2000)}`)));
});
const files = await Promise.all(parts.map(one));
const lines = files.flatMap(f => fs.readFileSync(f, 'utf8').trim().split('\n').filter(Boolean).map(l => JSON.parse(l)));
const head = lines.find(l => l.type === 'batch');
const runs = lines.filter(l => l.type === 'run').sort((x, y) => x.run - y.run);
for (const f of files) fs.rmSync(f);
fs.writeFileSync(path.join(out, 'runs.jsonl'), [head, ...runs].map(r => JSON.stringify(r)).join('\n') + '\n');
const secs = (Date.now() - t0) / 1000;

// ---------------------------------------------------------------- statistics
// Student's t quantile, two-sided 95%: Hill's (1970) series in the normal
// quantile, good to 1e-4 for df >= 2; df = 1 exact.
function t975(df) {
  if (df <= 0) return NaN;
  if (df === 1) return 12.7062;
  const z = 1.959964, z2 = z * z;
  return z + (z * (z2 + 1)) / (4 * df) + (z * (5 * z2 * z2 + 16 * z2 + 3)) / (96 * df * df)
    + (z * (3 * z2 ** 3 + 19 * z2 * z2 + 17 * z2 - 15)) / (384 * df ** 3) + (z * (79 * z2 ** 4 + 776 * z2 ** 3 + 1482 * z2 * z2 - 1920 * z2 - 945)) / (92160 * df ** 4);
}
function mean(xs) {
  const n = xs.length; if (!n) return { n, mean: NaN, lo: NaN, hi: NaN };
  const m = xs.reduce((a, b) => a + b, 0) / n;
  const sd = n > 1 ? Math.sqrt(xs.reduce((a, b) => a + (b - m) ** 2, 0) / (n - 1)) : 0;
  const h = n > 1 ? t975(n - 1) * sd / Math.sqrt(n) : NaN;
  return { n, mean: m, sd, lo: m - h, hi: m + h };
}
function share(k, n) { // Wilson score interval, 95%
  if (!n) return { k, n, p: NaN, lo: NaN, hi: NaN };
  const z = 1.959964, p = k / n, d = 1 + z * z / n, c = (p + z * z / (2 * n)) / d, h = z * Math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d;
  return { k, n, p, lo: Math.max(0, c - h), hi: Math.min(1, c + h) };
}
const median = xs => { const s = [...xs].sort((a, b) => a - b); return s.length ? (s.length % 2 ? s[(s.length - 1) / 2] : (s[s.length / 2 - 1] + s[s.length / 2]) / 2) : NaN; };

const cases = head.cases, coas = head.coas.map(c => c.name);
const groups = [];
for (const cs of cases) for (const coa of coas) groups.push({ case: cs, coa, rows: runs.filter(r => r.case === cs && r.coa === coa) });
const base = groups[0];
const keepOut = r => r.objectives?.keep_out !== 'failed';
const summary = groups.map(g => {
  const R = g.rows, byRun = new Map(base.rows.map(r => [r.run, r]));
  const pairs = R.filter(r => byRun.has(r.run)).map(r => r.score - byRun.get(r.run).score);
  return {
    case: g.case, coa: g.coa, n: R.length,
    won: share(R.filter(r => r.won).length, R.length),
    red_driven_off: share(R.filter(r => r.red_neutralized > 0).length, R.length),
    keep_out_held: share(R.filter(keepOut).length, R.length),
    score: mean(R.map(r => r.score)),
    closest_km: { median: median(R.map(r => r.closest_km).filter(x => x >= 0)), min: Math.min(...R.map(r => r.closest_km).filter(x => x >= 0)) },
    custody: mean(R.map(r => r.custody)),
    fuel_ms: mean(R.map(r => r.blue_dv_used * 1000)),
    escalation: mean(R.map(r => r.escalation)),
    refused_orders: R.reduce((a, r) => a + (r.orders?.given - r.orders?.ok || 0), 0),
    score_vs_first: g === base ? null : mean(pairs),
  };
});
fs.writeFileSync(path.join(out, 'summary.json'), JSON.stringify({ study: opt, engine: head.engine, scenario: head.scenario, scenario_name: head.name, seed: head.seed, runs: opt.runs, hours: opt.hours, seconds: secs, groups: summary }, null, 1));

// ---------------------------------------------------------------- CSV
const parts_ids = [...new Set(runs.flatMap(r => (r.score_parts ?? []).map(p => p[0])))];
const objs = [...new Set(runs.flatMap(r => Object.keys(r.objectives ?? {})))];
const sampledKeys = [...new Set(runs.flatMap(r => Object.keys(r.sampled ?? {})))];
const csvHead = ['case', 'coa', 'run', 'seed', 'result', 'won', 'score', ...parts_ids.map(p => `score_${p}`), 'closest_km', 'closest_h', 'custody', 'blue_dv_used_ms', 'escalation', 'red_neutralized', 'debris', 'orders_given', 'orders_ok', 't_end_h', ...objs.map(o => `obj_${o}`), ...sampledKeys];
const q = v => { const s = String(v ?? ''); return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s; };
const csv = [csvHead.join(','), ...runs.map(r => {
  const sp = Object.fromEntries((r.score_parts ?? []).map(p => [p[0], p[1]]));
  return [r.case, r.coa, r.run, r.seed, r.result, r.won, r.score?.toFixed(3), ...parts_ids.map(p => sp[p]?.toFixed(3)), r.closest_km?.toFixed(4), (r.closest_t / 3600).toFixed(2),
    r.custody?.toFixed(4), (r.blue_dv_used * 1000).toFixed(2), r.escalation, r.red_neutralized, r.debris, r.orders?.given, r.orders?.ok, (r.t_end / 3600).toFixed(2), ...objs.map(o => r.objectives?.[o]), ...sampledKeys.map(k => r.sampled?.[k])].map(q).join(',');
})];
fs.writeFileSync(path.join(out, 'runs.csv'), csv.join('\n') + '\n');

// ---------------------------------------------------------------- report
const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;');
const f1 = x => Number.isFinite(x) ? x.toFixed(1) : '—';
const f2 = x => Number.isFinite(x) ? x.toFixed(2) : '—';
const pc = x => Number.isFinite(x) ? `${Math.round(x * 100)}%` : '—';
const label = g => (cases.length > 1 ? `${g.case} · ` : '') + g.coa;
function niceStep(raw) { const e = 10 ** Math.floor(Math.log10(raw)); return [1, 2, 2.5, 5, 10].map(m => m * e).find(m => m >= raw); }
// Spearman's rank correlation: how strongly a setting drawn per run moves an outcome.
function ranks(xs) { const o = xs.map((x, i) => [x, i]).sort((a, b) => a[0] - b[0]), r = new Array(xs.length); for (let i = 0; i < o.length;) { let j = i; while (j + 1 < o.length && o[j + 1][0] === o[i][0]) j++; for (let k = i; k <= j; k++) r[o[k][1]] = (i + j) / 2 + 1; i = j + 1; } return r; }
function spearman(xs, ys) { const a = ranks(xs), b = ranks(ys), ma = a.reduce((p, q) => p + q, 0) / a.length, mb = b.reduce((p, q) => p + q, 0) / b.length; let sab = 0, saa = 0, sbb = 0; for (let i = 0; i < a.length; i++) { sab += (a[i] - ma) * (b[i] - mb); saa += (a[i] - ma) ** 2; sbb += (b[i] - mb) ** 2; } return saa && sbb ? sab / Math.sqrt(saa * sbb) : NaN; }
function ciChart(title, unit, get, lo0, hi0) { // a dot and its 95% interval per group
  const H = 34 * summary.length + 46, x0 = 260, x1 = 820;
  const vals = summary.flatMap(g => { const v = get(g); return [v.lo, v.hi, v.mean ?? v.p].filter(Number.isFinite); });
  const step = niceStep((Math.max(hi0, ...vals) - Math.min(lo0, ...vals)) / 4 || 1);
  const lo = Math.floor(Math.min(lo0, ...vals) / step) * step, hi = Math.ceil((Math.max(hi0, ...vals) || 1) / step) * step;
  const sx = v => x0 + (v - lo) / (hi - lo || 1) * (x1 - x0);
  let s = `<figure><figcaption>${esc(title)}</figcaption><svg viewBox="0 0 860 ${H}" role="img" aria-label="${esc(title)}">`;
  for (let v = lo; v <= hi + step / 2; v += step) { s += `<line x1="${sx(v)}" y1="8" x2="${sx(v)}" y2="${H - 30}" class="g"/><text x="${sx(v)}" y="${H - 12}" class="t" text-anchor="middle">${unit === '%' ? Math.round(v * 100) + '%' : +v.toFixed(2)}</text>`; }
  summary.forEach((g, i) => {
    const v = get(g), y = 26 + i * 34, m = v.mean ?? v.p;
    s += `<text x="${x0 - 12}" y="${y + 5}" class="l" text-anchor="end">${esc(label(g))}</text>`;
    if (Number.isFinite(v.lo)) s += `<line x1="${sx(v.lo)}" y1="${y}" x2="${sx(v.hi)}" y2="${y}" class="ci"/>`;
    s += `<circle cx="${sx(m)}" cy="${y}" r="6" class="d"><title>${esc(label(g))}: ${unit === '%' ? pc(m) : f2(m)} (95%: ${unit === '%' ? pc(v.lo) : f2(v.lo)} to ${unit === '%' ? pc(v.hi) : f2(v.hi)})</title></circle>`;
  });
  return s + '</svg></figure>';
}
const rowsHtml = summary.map(g => `<tr><td>${esc(label(g))}</td><td class="n">${g.n}</td><td class="n">${pc(g.won.p)} <small>${pc(g.won.lo)}–${pc(g.won.hi)}</small></td>
<td class="n">${f1(g.score.mean)} <small>±${f1(g.score.hi - g.score.mean)}</small></td><td class="n">${g.score_vs_first ? `${g.score_vs_first.mean >= 0 ? '+' : ''}${f1(g.score_vs_first.mean)} <small>${f1(g.score_vs_first.lo)} to ${f1(g.score_vs_first.hi)}</small>` : 'baseline'}</td>
<td class="n">${pc(g.keep_out_held.p)}</td><td class="n">${f2(g.closest_km.median)} <small>min ${f2(g.closest_km.min)}</small></td><td class="n">${pc(g.custody.mean)}</td><td class="n">${f1(g.fuel_ms.mean)}</td><td class="n">${f1(g.escalation.mean)}</td><td class="n">${pc(g.red_driven_off.p)}</td></tr>`).join('\n');
const sampledKeys2 = [...new Set(runs.flatMap(r => Object.keys(r.sampled ?? {})))];
const sens = groups.map(g => ({ label: label(g), rho: sampledKeys2.map(k => spearman(g.rows.map(r => r.sampled[k]), g.rows.map(r => r.score))) }));
const sensHtml = !sampledKeys2.length ? '' : `<h2>What drives the score</h2>
<p>Spearman's rank correlation between each setting drawn per run and the score, for each row (−1 to +1; with ${opt.runs} runs, values inside about ±${(1.96 / Math.sqrt(Math.max(opt.runs - 1, 1))).toFixed(2)} could be chance).</p>
<div class="tw"><table><tr><th>Case · course of action</th>${sampledKeys2.map(k => `<th class="n">${esc(k)}</th>`).join('')}</tr>
${sens.map(x => `<tr><td>${esc(x.label)}</td>${x.rho.map(v => `<td class="n" style="${Math.abs(v) > 1.96 / Math.sqrt(Math.max(opt.runs - 1, 1)) ? 'font-weight:700' : 'color:var(--ink2)'}">${Number.isFinite(v) ? (v >= 0 ? '+' : '') + v.toFixed(2) : '—'}</td>`).join('')}</tr>`).join('')}</table></div>`;
{ // the summary again, now with the sensitivity of each row's score to each drawn setting
  const sm = JSON.parse(fs.readFileSync(path.join(out, 'summary.json'), 'utf8'));
  sm.sensitivity = sens.map(x => ({ row: x.label, spearman_score: Object.fromEntries(sampledKeys2.map((k, i) => [k, x.rho[i]])) }));
  fs.writeFileSync(path.join(out, 'summary.json'), JSON.stringify(sm, null, 1));
}
const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${esc(opt.name)} · xGEO study</title>
<style>
:root{--ink:#1d1f22;--ink2:#5b5f66;--rule:#e3e0d8;--bg:#fbfaf7;--blue:#1673b0;--red:#c8452a}
body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.5 system-ui,-apple-system,"Segoe UI",sans-serif}
main{max-width:1100px;margin:0 auto;padding:28px 16px 60px}h1{font-size:26px;margin:0 0 4px}h2{font-size:18px;margin:34px 0 8px;border-top:1px solid var(--rule);padding-top:16px}
.sub{color:var(--ink2);margin:0 0 18px}.tw{overflow-x:auto}table{border-collapse:collapse;width:100%;font-size:14px}th,td{padding:6px 8px;border-bottom:1px solid var(--rule);text-align:left;vertical-align:top}
th{font-size:12px;letter-spacing:.06em;text-transform:uppercase;color:var(--ink2)}.n{text-align:right;white-space:nowrap}small{color:var(--ink2)}
figure{margin:18px 0}figcaption{font-weight:600;margin-bottom:4px}svg{width:100%;height:auto}.g{stroke:var(--rule)}.t{font-size:12px;fill:var(--ink2)}.l{font-size:13px;fill:var(--ink)}.ci{stroke:var(--blue);stroke-width:3;stroke-linecap:round;opacity:.5}.d{fill:var(--blue)}
code{font:13px ui-monospace,Consolas,monospace;background:#f1efe9;padding:1px 4px}ul{padding-left:20px}
</style></head><body><main>
<h1>${esc(opt.name)}</h1>
<p class="sub">${esc(head.name)} · ${esc(head.engine)} · ${opt.runs} paired runs of ${opt.hours} h each, seed ${head.seed} · ${new Date().toISOString().slice(0, 16).replace('T', ' ')} UTC · ${f1(secs)} s on ${parts.length} cores</p>
<h2>Results</h2>
<div class="tw"><table><tr><th>Case · course of action</th><th class="n">Runs</th><th class="n">Won (95%)</th><th class="n">Score (±95%)</th><th class="n">Score vs first, paired (95%)</th><th class="n">Keep-out held</th><th class="n">Closest km, median</th><th class="n">Custody</th><th class="n">Fuel m/s</th><th class="n">Tension</th><th class="n">Red driven off</th></tr>
${rowsHtml}</table></div>
${ciChart('Score out of 100, mean and 95% interval', '', g => g.score, 0, 100)}
${ciChart('Share of runs won, with 95% interval', '%', g => g.won, 0, 1)}
${ciChart('Fuel used by Blue, m/s, mean and 95% interval', '', g => g.fuel_ms, 0, 0)}
${sensHtml}
<h2>How to read this</h2>
<ul>
<li>Every row plays the same ${opt.runs} worlds: run k has the same opening track errors and chance draws in every row (common random numbers). The paired difference from the first row is therefore much tighter than comparing the rows' own intervals.</li>
<li>Shares carry Wilson 95% intervals; means and paired differences carry Student's t 95% intervals. With few runs the intervals are wide: add runs before drawing a conclusion.</li>
<li>The score, the objectives and Red's behaviour are the scenario's design values; the physics under them is the engine's (Research Edition, §10). A study answers "which course of action does better in this model", not "what would happen".</li>
</ul>
<h2>Set-up</h2>
<ul><li>Scenario: <code>${esc(head.scenario)}</code></li>
<li>Courses of action: ${head.coas.map(c => `<code>${esc(c.name)}</code> (${c.orders} orders)`).join(', ')}</li>
${opt.vary ? `<li>Varied: <code>${esc(opt.vary)}</code></li>` : ''}${opt.sample ? `<li>Drawn afresh for each run, uniformly: <code>${esc(opt.sample)}</code></li>` : ''}${opt.set ? `<li>Fixed settings: <code>${esc(opt.set)}</code></li>` : ''}
<li>Files: <code>runs.csv</code> (one row per run), <code>runs.jsonl</code>, <code>summary.json</code>.</li></ul>
</main></body></html>
`;
fs.writeFileSync(path.join(out, 'report.html'), html);
console.log(summary.map(g => `  ${label(g).padEnd(40)} won ${pc(g.won.p).padStart(4)}  score ${f1(g.score.mean).padStart(5)} ±${f1(g.score.hi - g.score.mean)}  fuel ${f1(g.fuel_ms.mean)} m/s`).join('\n'));
console.log(`${runs.length} runs in ${f1(secs)} s -> ${out}`);
