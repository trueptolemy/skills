#!/usr/bin/env python3
"""Break a VM-vs-bare-metal score gap down into TMA nodes from EMON summary CSVs.

Subcommands
  inspect  list the cases found in EMON summary CSV(s) and the data the
           applicability checks need (no scores required)
  report   run the applicability checks, the breakdown and the EMON
           cross-check, and write a Markdown report

Method (see reference/method.md):
  gap_ratio = 1 - r = sum_i (Ratio_i,VM - (r/beta) * Ratio_i,BM) + r * (1/beta - 1)
  r = Score_VM / Score_BM, beta = (Freq_VM * Util_VM) / (Freq_BM * Util_BM)
Sub-nodes use per-environment weight factors w_i,E = Ratio_i,E / sum_j sub_Ratio_i,j,E.

Only the Python standard library is used.
"""
import argparse
import csv
import datetime
import json
import math
import os
import re
import sys

VERSION = '1.0'
HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_RULES = os.path.normpath(os.path.join(HERE, '..', 'reference', 'crosscheck-rules.json'))
L1 = ['Frontend_Bound', 'Bad_Speculation', 'Backend_Bound', 'Retiring']
TMA_RE = re.compile(r'^metric_TMA_(\.*)([A-Za-z0-9_]+)\(%\)$')

# key metrics in EMON summaries (first matching row wins)
KEY = {
    'util': r'^metric_CPU utilization %$',
    'util_kernel': r'^metric_CPU utilization% in kernel mode$',
    'freq': r'^metric_CPU operating frequency',
    'uncore': r'^metric_uncore frequency',
    'ddr': r'^metric_DDR data rate',
    'cpi': r'^metric_CPI$',
    'mux': r'^metric_EMON event mux reliability',
    'tma_version': r'^metric_TMA_Metrics_Version$',
    'samples': r'^(\$processed_samples|metric_EDP EMON total number of samples)$',
    'window': r'^\$samplingTime$',
    'inst': r'^INST_RETIRED\.ANY$',
    'clk': r'^CPU_CLK_UNHALTED\.THREAD$',
}

CONFIRM = {  # qualitative applicability conditions the agent confirms with the user
    'throughput': 'Throughput workload: score is proportional to 1/elapsed time, same copies/threads '
                  'and same score metric in every case',
    'host_side_tma': 'VM-case EMON was collected on the host, system-wide, without a guest/host mode '
                     'filter (TMA covers guest, hypervisor and transition cycles)',
    'same_phase': 'EMON windows of all cases cover comparable parts of their runs (all whole runs, or all '
                  'the same steady-state range)',
    'cpu_saturated': 'All CPUs are busy in steady state: no single-thread critical section, I/O, '
                     'sleep or off-CPU wait dominates',
}


CONFIRM_NO = {'same_phase': 'WARN'}   # severity of a "no" answer (default FAIL)


def die(msg):
    sys.stderr.write('tma_breakdown: %s\n' % msg)
    sys.exit(2)


def num(s):
    if s is None:
        return None
    t = str(s).strip()
    if not t:
        return None
    try:
        v = float(t)
    except ValueError:
        return None
    return v if math.isfinite(v) else None


def norm(s):
    return re.sub(r'\s+', ' ', str(s).strip().lower())


# ------------------------------------------------------------------ EMON loading
class Case:
    def __init__(self, name, path, column, values, order):
        self.name, self.path, self.column = name, path, column
        self.values = values            # row name -> float
        self.order = order              # row names in file order
        self.lower = {k.lower(): k for k in values}

    def get(self, pattern):
        rx = re.compile(pattern, re.I)
        for k in self.order:
            if rx.search(k) and self.values.get(k) is not None:
                return self.values[k]
        return None

    def event(self, name):
        k = self.lower.get(name.lower())
        return None if k is None else self.values.get(k)


def read_csv(path):
    with open(path, newline='', encoding='utf-8-sig', errors='replace') as f:
        rows = [r for r in csv.reader(f)]
    rows = [r for r in rows if r and any(c.strip() for c in r)]
    if len(rows) < 2:
        die('%s: not an EMON summary CSV (too few rows)' % path)
    return rows


HEADER_RANGE = {}   # path -> sample count named in the first header cell ("sample #1 - #N")


def load_emon(path):
    """Return {column header: Case} for one EMON summary CSV (metric/event rows x case columns)."""
    rows = read_csv(path)
    header = [h.strip() for h in rows[0]]
    mrange = re.search(r'sample #(\d+)\s*-\s*#(\d+)', header[0])
    if mrange:
        HEADER_RANGE[path] = int(mrange.group(2)) - int(mrange.group(1)) + 1
    cols = header[1:]
    if not cols:
        die('%s: no data column' % path)
    cases = {}
    order = [r[0].strip() for r in rows[1:]]
    for ci, col in enumerate(cols, start=1):
        vals = {}
        for r in rows[1:]:
            vals[r[0].strip()] = num(r[ci]) if ci < len(r) else None
        name = col or os.path.splitext(os.path.basename(path))[0]
        cases[name] = Case(name, path, col, vals, order)
    return cases


def parse_case_specs(emon_files, case_specs):
    """--emon PATH (all columns) and --case NAME=PATH[@COLUMN]."""
    cases = {}
    for p in emon_files or []:
        for name, c in load_emon(p).items():
            if name in cases:
                name = '%s (%s)' % (name, os.path.basename(p))
                c.name = name
            cases[name] = c
    for spec in case_specs or []:
        if '=' not in spec:
            die('--case expects NAME=PATH[@COLUMN], got %r' % spec)
        name, rest = spec.split('=', 1)
        path, _, col = rest.partition('@')
        file_cases = load_emon(path)
        if col:
            hit = [c for k, c in file_cases.items() if norm(k) == norm(col)]
            if not hit:
                die('%s has no column %r (columns: %s)' % (path, col, ', '.join(file_cases)))
            c = hit[0]
        elif len(file_cases) == 1:
            c = list(file_cases.values())[0]
        else:
            die('%s has several columns (%s); use NAME=PATH@COLUMN' % (path, ', '.join(file_cases)))
        c.name = name.strip()
        cases[c.name] = c
    if not cases:
        die('no EMON data: give --emon PATH or --case NAME=PATH[@COLUMN]')
    return cases


def match_name(name, candidates, what, required=True):
    """Exact, then case-insensitive, then unique longest prefix match."""
    if name in candidates:
        return name
    n = norm(name)
    exact = [c for c in candidates if norm(c) == n]
    if len(exact) == 1:
        return exact[0]
    pref = [c for c in candidates if norm(c).startswith(n) or n.startswith(norm(c))]
    if len(pref) == 1:
        return pref[0]
    if len(pref) > 1:
        pref.sort(key=lambda c: -len(os.path.commonprefix([norm(c), n])))
        if len(os.path.commonprefix([norm(pref[0]), n])) > len(os.path.commonprefix([norm(pref[1]), n])):
            return pref[0]
    if not required:
        return None
    die('cannot match %s %r to one of: %s' % (what, name, ', '.join(candidates)))


# ------------------------------------------------------------------ scores / per-case values
def parse_scores(files, pairs):
    scores = {}
    for path in files or []:
        rows = read_csv(path)
        header = [h.strip() for h in rows[0]]
        wide = header[0].strip().lower() not in ('case', 'name', 'config', 'configuration') and (len(header) > 2 or (len(header) == 2 and num(header[1]) is None and
                                   all(num(r[0]) is None for r in rows[1:]) and len(rows) == 2))
        if wide:
            data = None
            for r in rows[1:]:
                if r[0].strip().lower() in ('score', 'scores', 'result', 'value'):
                    data = r
                    break
            if data is None:
                data = next((r for r in rows[1:] if any(num(x) is not None for x in r[1:])), None)
            if data is None:
                die('%s: no numeric score row' % path)
            for h, v in zip(header[1:], data[1:]):
                if h and num(v) is not None:
                    scores[h] = num(v)
        else:
            for r in rows:
                if len(r) >= 2 and num(r[1]) is not None:
                    scores[r[0].strip()] = num(r[1])
    for p in pairs or []:
        if '=' not in p:
            die('--score expects CASE=VALUE, got %r' % p)
        k, v = p.rsplit('=', 1)
        if num(v) is None:
            die('--score %r: value is not a number' % p)
        scores[k.strip()] = num(v)
    return scores


def parse_kv(pairs, what):
    out = {}
    for p in pairs or []:
        if '=' not in p:
            die('%s expects CASE=VALUE, got %r' % (what, p))
        k, v = p.rsplit('=', 1)
        v = v.strip()
        val = num(v[:-1]) / 100 if v.endswith('%') and num(v[:-1]) is not None else num(v)
        if val is None:
            die('%s %r: value is not a number' % (what, p))
        out[k.strip()] = val
    return out


# ------------------------------------------------------------------ TMA tree
class Tree:
    def __init__(self, base):
        self.nodes, self.depth, self.parent, self.key = [], {}, {}, {}
        stack = []
        for row in base.order:
            m = TMA_RE.match(row)
            if not m:
                continue
            d, name = len(m.group(1)) // 2, m.group(2)
            if name in self.depth:          # duplicated node name: keep the first one
                continue
            del stack[d:]
            self.parent[name] = stack[-1] if stack else None
            stack.append(name)
            self.nodes.append(name)
            self.depth[name] = d
            self.key[name] = row
        self.children = {n: [c for c in self.nodes if self.parent[c] == n] for n in self.nodes}

    def ratio(self, case, node):
        row = case.lower.get(self.key[node].lower())
        if row is None:     # tolerate a different number of dots in other files
            rx = re.compile(r'^metric_TMA_\.*%s\(%%\)$' % re.escape(node), re.I)
            row = next((k for k in case.order if rx.match(k)), None)
        return None if row is None else case.values.get(row)


# ------------------------------------------------------------------ computation
def breakdown(tree, base, case, r, beta, noise):
    k = r / beta
    res = {}
    W = {}

    def wr(n):
        if n in W:
            return W[n]
        p = tree.parent[n]
        rb, rc = tree.ratio(base, n), tree.ratio(case, n)
        if rb is None or rc is None:
            W[n] = None
        elif p is None:
            W[n] = (rb, rc)
        else:
            pw = wr(p)
            sib = tree.children[p]
            vals = [(tree.ratio(base, s), tree.ratio(case, s)) for s in sib]
            ok = (pw is not None and len(sib) >= 2 and all(b is not None and c is not None for b, c in vals)
                  and all((b or 0) != 0 or (c or 0) != 0 for b, c in vals))
            sb, sc = sum(b for b, _ in vals) if ok else 0, sum(c for _, c in vals) if ok else 0
            W[n] = (pw[0] * rb / sb, pw[1] * rc / sc) if ok and sb > 0 and sc > 0 else None
        return W[n]

    for n in tree.nodes:
        rb, rc = tree.ratio(base, n), tree.ratio(case, n)
        if rb is None or rc is None:
            res[n] = dict(bm=rb, vm=rc, unw=None, w=None, band=None)
            continue
        w = wr(n)
        res[n] = dict(bm=rb, vm=rc, unw=rc - k * rb, w=None if w is None else w[1] - k * w[0],
                      band=k * noise * rb)
    return res


def evidence_value(case, ev, inst_key='INST_RETIRED.ANY', clk_key='CPU_CLK_UNHALTED.THREAD'):
    kind = ev['kind']
    if kind == 'metric':
        return case.get(ev['metric'])
    if kind == 'event':
        return case.event(ev['event'])
    if kind == 'event_per_instr':
        a, b = case.event(ev['event']), case.event(inst_key)
    elif kind == 'event_per_cycle':
        a, b = case.event(ev['event']), case.event(clk_key)
    elif kind == 'event_ratio':
        a, b = case.event(ev['num']), case.event(ev['den'])
    else:
        die('unknown evidence kind %r' % kind)
    return a / b if a is not None and b not in (None, 0) else None


# ------------------------------------------------------------------ formatting
def md_table(header, rows, align=None):
    esc = lambda s: str(s).replace('|', '\\|').replace('\n', ' ')
    out = ['| ' + ' | '.join(esc(h) for h in header) + ' |',
           '|' + '|'.join((':---' if (align and align[i] == 'l') else '---:') for i in range(len(header))) + '|']
    out += ['| ' + ' | '.join(esc(c) for c in r) + ' |' for r in rows]
    return '\n'.join(out)


def fp(v, nd=2, pct=False, sign=False):
    if v is None:
        return 'n/a'
    s = ('%+.*f' if sign else '%.*f') % (nd, v)
    if s in ('-0.00', '+0.00', '-0.0', '+0.0', '-0', '+0'):
        s = s.replace('-', '').replace('+', '') if not sign else '+' + s[1:]
    return s + ('%' if pct else '')


def fsci(v):
    if v is None:
        return 'n/a'
    a = abs(v)
    if a == 0:
        return '0'
    if a >= 1000 or a < 0.01:
        return '%.3e' % v
    return '%.4g' % v


def slug(s):
    return re.sub(r'[^A-Za-z0-9._-]+', '-', s).strip('-') or 'workload'


# ------------------------------------------------------------------ inspect
def cmd_inspect(a):
    cases = parse_case_specs(a.emon, a.case)
    rows = []
    for name, c in cases.items():
        tree = Tree(c)
        l1 = [tree.ratio(c, n) if n in tree.depth else None for n in L1]
        rows.append([name, os.path.basename(c.path), fp(c.get(KEY['tma_version']), 1),
                     len(tree.nodes), fp(sum(x for x in l1 if x is not None), 2) if all(x is not None for x in l1) else 'missing',
                     fp(c.get(KEY['util']), 2), fp(c.get(KEY['freq']), 3), fp(c.get(KEY['cpi']), 3),
                     fp(c.get(KEY['mux']), 2), fp(c.get(KEY['util_kernel']), 2),
                     fp(c.get(KEY['window']), 1), fp(c.get(KEY['samples']), 0)])
    print(md_table(['case', 'file', 'TMA ver', 'TMA nodes', 'L1 sum %', 'CPU util %', 'freq GHz', 'CPI',
                    'mux rel %', 'kernel util %', 'window s', 'samples'], rows, 'llrrrrrrrrrr'))
    for path, nsamp in HEADER_RANGE.items():
        odd = [n for n, c in cases.items() if c.path == path and c.get(KEY['samples']) not in (None, nsamp)]
        print('\nheader of %s names %d samples; columns with a different sample count: %s' % (
            os.path.basename(path), nsamp, ', '.join(odd) if odd else 'none'))
    if a.json:
        with open(a.json, 'w') as f:
            json.dump({'cases': [dict(zip(['case', 'file', 'tma_version', 'tma_nodes', 'l1_sum', 'util', 'freq',
                                           'cpi', 'mux', 'util_kernel', 'window_s', 'samples'], r))
                                 for r in rows]}, f, indent=1)


# ------------------------------------------------------------------ report
def status_of(checks):
    st = [c['status'] for c in checks]
    if 'FAIL' in st:
        return 'NOT APPLICABLE'
    if 'WARN' in st or 'ASK' in st:
        return 'APPLICABLE WITH CAVEATS'
    return 'APPLICABLE'


def cmd_report(a):
    cases = parse_case_specs(a.emon, a.case)
    base_name = match_name(a.baseline, list(cases), 'baseline case')
    base = cases[base_name]
    targets = [match_name(t, list(cases), 'case') for t in a.compare] if a.compare else \
        [n for n in cases if n != base_name]
    if not targets:
        die('no case to compare with the baseline')
    raw_scores = parse_scores(a.scores, a.score)
    score, score_label = {}, {}
    for n in [base_name] + targets:
        k = match_name(n, list(raw_scores), 'score of case', required=False) if raw_scores else None
        score[n] = raw_scores.get(k) if k else None
        score_label[n] = k or ''
    beta_in = {match_name(k, list(cases), '--beta case'): v for k, v in parse_kv(a.beta, '--beta').items()}
    alpha_in = {match_name(k, list(cases), '--alpha case'): v for k, v in parse_kv(a.alpha, '--alpha').items()}
    confirm = {}
    for p in a.confirm or []:
        k, _, v = p.partition('=')
        if k not in CONFIRM or v not in ('yes', 'no', 'unknown'):
            die('--confirm expects one of %s = yes|no|unknown, got %r' % (', '.join(CONFIRM), p))
        confirm[k] = v
    rules = {'rules': [], 'context': []}
    if a.rules:
        with open(a.rules) as f:
            rules = json.load(f)
    tree = Tree(base)
    noise = a.score_noise / 100.0

    def descendants(nd):
        out, todo = [], list(tree.children.get(nd, []))
        while todo:
            x = todo.pop(0)
            out.append(x)
            todo += tree.children.get(x, [])
        return out

    def overlaps(nd):
        p = tree.parent.get(nd)
        if not p:
            return False
        for case in [base] + [C[t] for t in targets]:
            v, pv = tree.ratio(case, nd), tree.ratio(case, p)
            if v is not None and pv is not None and v > pv + 0.5:
                return True
        return False

    def l1_of(nd):
        while tree.parent.get(nd):
            nd = tree.parent[nd]
        return nd
    allc = [base_name] + targets
    C = {n: cases[n] for n in allc}
    get = lambda n, key: C[n].get(KEY[key])

    # ---- per-case score model
    model = {}
    for n in targets:
        sb, sc = score[base_name], score[n]
        r = None
        if sb and sc:
            r = sc / sb if a.direction == 'higher' else sb / sc
        fb, fc, ub, uc = get(base_name, 'freq'), get(n, 'freq'), get(base_name, 'util'), get(n, 'util')
        beta_emon = (fc * uc) / (fb * ub) if None not in (fb, fc, ub, uc) and fb * ub else None
        if n in beta_in:
            beta, beta_src = beta_in[n], 'given'
        elif a.beta_mode == 'emon' and beta_emon:
            beta, beta_src = beta_emon, 'EMON freq x util'
        else:
            beta, beta_src = 1.0, 'assumed 1 (simplified formula)'
        cb, cc = get(base_name, 'cpi'), get(n, 'cpi')
        k_meas = cb / cc if cb and cc else None
        alpha = alpha_in.get(n)
        implied_alpha = k_meas * beta / r - 1 if k_meas and r else None
        k_pred = r * (1 + (alpha or 0.0)) / beta if r else None
        model[n] = dict(r=r, beta=beta, beta_src=beta_src, beta_emon=beta_emon, k=(r / beta if r else None),
                        gap=(1 - r) * 100 if r else None, virt=(r * (1 / beta - 1) * 100 if r else None),
                        k_meas=k_meas, k_pred=k_pred, alpha=alpha, implied_alpha=implied_alpha)

    # ---- applicability checks
    checks = []

    def add(cid, title, values, status, note):
        checks.append(dict(id=cid, title=title, values=values, status=status, note=note))

    present = {n: all(n2 in tree.depth and tree.ratio(C[n], n2) is not None for n2 in L1) for n in allc}
    add('tma_present', 'Level-1 TMA nodes present', {n: 'yes' if present[n] else 'no' for n in allc},
        'PASS' if all(present.values()) else 'FAIL', 'Frontend_Bound, Bad_Speculation, Backend_Bound, Retiring')
    if not all(present.values()):
        pass
    sums = {n: sum(tree.ratio(C[n], x) for x in L1) if present[n] else None for n in allc}
    dev = max(abs(s - 100) for s in sums.values() if s is not None) if any(sums.values()) else 99
    add('tma_sum', 'Level-1 TMA ratios add up to 100%', {n: fp(v, 2) for n, v in sums.items()},
        'PASS' if dev <= 1 else 'WARN' if dev <= 3 else 'FAIL',
        'max deviation %.2f%%; the identity needs sum = 100%%' % dev)
    vers = {n: get(n, 'tma_version') for n in allc}
    add('tma_version', 'Same TMA metric version', {n: fp(v, 1) for n, v in vers.items()},
        'PASS' if len(set(v for v in vers.values() if v is not None)) <= 1 else 'WARN',
        'node definitions must match across cases')
    mux = {n: get(n, 'mux') for n in allc}
    mmin = min((v for v in mux.values() if v is not None), default=None)
    add('mux', 'EMON event multiplexing reliability', {n: fp(v, 2) for n, v in mux.items()},
        'INFO' if mmin is None else 'PASS' if mmin >= 95 else 'WARN' if mmin >= 90 else 'FAIL',
        'below 95% the multiplexed TMA events are unreliable')
    miss = [n for n in allc if not score.get(n)]
    add('scores', 'Scores available for every case', {n: fp(score.get(n), 3) for n in allc},
        'PASS' if not miss else 'FAIL', 'missing: %s' % ', '.join(miss) if miss else
        'direction: %s is better' % a.direction)
    fr = {n: get(n, 'freq') for n in allc}
    fdev = max((abs(fr[n] / fr[base_name] - 1) for n in targets if fr[n] and fr[base_name]), default=None)
    add('freq', 'Same core frequency', {n: fp(v, 3) for n, v in fr.items()},
        'INFO' if fdev is None else 'PASS' if fdev <= 0.01 else 'WARN',
        'n/a' if fdev is None else 'max deviation %.2f%%; otherwise beta must include the frequency ratio' % (fdev * 100))
    ut = {n: get(n, 'util') for n in allc}
    worst = None
    for n in targets:
        be = model[n]['beta_emon']
        if be is not None:
            worst = be if worst is None or abs(be - 1) > abs(worst - 1) else worst
    if worst is None:
        ust, unote = 'ASK', 'EMON has no utilization; confirm steady-state utilization (beta) with the user'
    elif abs(worst - 1) <= a.beta_tol:
        ust, unote = 'PASS', 'EMON beta within %.0f%% of 1 for every case' % (a.beta_tol * 100)
    elif all(n in beta_in for n in targets):
        ust, unote = 'WARN', ('EMON-window utilization differs (beta_emon furthest from 1: %.3f) but steady-state beta '
                              'was given; the EMON window likely includes idle time outside the workload' % worst)
    else:
        ust, unote = 'FAIL', ('utilization differs (beta_emon furthest from 1: %.3f): investigate the utilization gap first, or '
                              'give the steady-state beta (perf ref-cycles/TSC) with --beta' % worst)
    add('util', 'Same CPU utilization (beta = 1)', {n: fp(v, 2) for n, v in ut.items()}, ust, unote)
    cons = {}
    cst = 'PASS'
    notes = []

    def user_cpi(n):
        c, cs = C[n].event('CPU_CLK_UNHALTED.THREAD'), C[n].event('CPU_CLK_UNHALTED.THREAD:SUP')
        i, isup = C[n].event('INST_RETIRED.ANY'), C[n].event('INST_RETIRED.ANY:SUP')
        if None in (c, cs, i, isup) or i == isup:
            return None
        return (c - cs) / (i - isup)
    for n in targets:
        m = model[n]
        if m['k_meas'] is None or m['r'] is None:
            cons[n] = 'n/a'
            continue
        if m['alpha'] is not None:
            d = m['k_meas'] / m['k_pred'] - 1
            cons[n] = 'CPI ratio %.3f vs model %.3f (%+.1f%%)' % (m['k_meas'], m['k_pred'], d * 100)
            if abs(d) > 0.03:
                cst = 'WARN'
                notes.append('%s: EMON CPI ratio deviates %+.1f%% from r(1+alpha)/beta' % (n, d * 100))
        else:
            ia = m['implied_alpha']
            cons[n] = 'implied alpha %+.1f%%' % (ia * 100)
            if not (-0.02 <= ia <= 0.05):
                cst = 'WARN'
                notes.append('%s: EMON CPI implies %+.1f%% instructions per unit of work vs the baseline' % (n, ia * 100))
        ub, uc = user_cpi(base_name), user_cpi(n)
        if ub and uc:
            m['k_meas_user'] = ub / uc
            cons[n] += '; user-mode CPI ratio %.3f vs total %.3f' % (ub / uc, m['k_meas'])
    ias = [model[n]['implied_alpha'] for n in targets if model[n].get('implied_alpha') is not None]
    if cst == 'WARN' and len(ias) >= 2 and max(ias) - min(ias) <= 0.02:
        notes.append('the same implied alpha in every compared case points at the baseline window rather than '
                     'at the VMs (see the window check); a user-mode CPI ratio that deviates like the total one means the '
                     'workload code itself runs at a different speed in that window (another phase)')
    add('cpi_consistency', 'EMON CPI consistent with the score model', {**cons, base_name: '-'}, cst,
        '; '.join(notes) + ('. TMA ratios may include non-workload activity (misaligned window, idle polling, '
                            'extra kernel/hypervisor code); alpha cancels out of the breakdown itself'
                            if notes else 'alpha cancels out of the breakdown; this only validates the EMON window'))
    win = {n: get(n, 'window') for n in allc}
    busy = {n: win[n] * get(n, 'util') / 100 if win[n] and get(n, 'util') else None for n in allc}

    def user_inst(n):
        i, sup = C[n].event('INST_RETIRED.ANY'), C[n].event('INST_RETIRED.ANY:SUP')
        return (i - (sup or 0)) * win[n] if i and win[n] else None
    uinst = {n: user_inst(n) for n in allc}
    est = {n: busy[n] * model[n]['r'] for n in targets if busy[n] and model[n]['r']}   # BM run time implied
    wnotes, wst, cov = [], 'PASS', {}
    if busy[base_name] and est:
        med = sorted(est.values())[len(est) // 2]
        spread = max(est.values()) / min(est.values()) - 1
        cov['busy'] = busy[base_name] / med
        vu = [uinst[n] for n in targets if uinst[n]]
        if uinst[base_name] and vu:
            cov['instr'] = uinst[base_name] / sorted(vu)[len(vu) // 2]
        if spread > a.window_tol / 2:
            wst = 'WARN'
            wnotes.append('the compared windows disagree with each other (busy time x r spreads %.0f%%): they '
                          'cover different parts of their runs' % (spread * 100))
        if abs(cov['busy'] - 1) > a.window_tol:
            wst = 'WARN'
            wnotes.append('the baseline window covers about %.0f%% of its run by busy time%s, while the compared '
                          'windows agree with whole runs (busy time tracks 1/r within %.0f%%)' % (
                              cov['busy'] * 100, (' and %.0f%% by user instructions' % (cov['instr'] * 100))
                              if 'instr' in cov else '', spread * 100))
    elif not win[base_name]:
        wst = 'INFO'
    if wst == 'WARN' and confirm.get('same_phase') == 'yes':
        wnotes.append('this contradicts the same_phase answer')
    add('window', 'EMON windows cover comparable parts of the runs',
        {n: ('%s s, busy %s s' % (fp(win[n], 1), fp(busy[n], 1))) if win[n] else 'n/a' for n in allc}, wst,
        ('; '.join(wnotes) + '. TMA of a partial window may not represent the scored run')
        if wnotes else ('busy time (window x utilization) x r agrees across cases' if wst == 'PASS'
                        else 'no window length in the EMON summary'))
    window_cov = cov
    refuted = wst == 'WARN' and confirm.get('same_phase') == 'yes'
    MIX = ('BR_INST_RETIRED.ALL_BRANCHES', 'MEM_INST_RETIRED.ALL_LOADS', 'MEM_INST_RETIRED.ALL_STORES')
    mixdev = {}
    for n in targets:
        devs = []
        for ev in MIX:
            vb = evidence_value(base, {'kind': 'event_per_instr', 'event': ev})
            vc = evidence_value(C[n], {'kind': 'event_per_instr', 'event': ev})
            if vb and vc:
                devs.append(vc / vb - 1)
        mixdev[n] = max(devs, key=abs) if devs else None
    md = [abs(v) for v in mixdev.values() if v is not None]
    add('instruction_mix', 'Same instruction mix (branches, loads, stores per instr)',
        {**{n: fp(v * 100, 2, True, sign=True) if v is not None else 'n/a' for n, v in mixdev.items()},
         base_name: '-'},
        'INFO' if not md else 'PASS' if max(md) <= 0.03 else 'WARN',
        'same binary and input expected; a uniform shift means non-workload instructions of another mix '
        '(about the size of the shift) or a different binary. With a CPI mismatch and an unchanged mix, '
        'suspect windows covering different phases rather than extra instructions')
    for key, title in (('uncore', 'Same uncore frequency'), ('ddr', 'Same DDR data rate')):
        v = {n: get(n, key) for n in allc}
        d = max((abs(v[n] / v[base_name] - 1) for n in targets if v[n] and v[base_name]), default=None)
        add(key, title, {n: fp(x, 3) for n, x in v.items()}, 'INFO' if d is None else 'PASS' if d <= 0.01 else 'WARN',
            'shared resources outside the core model; differences limit the method')
    kshare = {n: (get(n, 'util_kernel') or 0) / get(n, 'util') * 100 if get(n, 'util') and
              get(n, 'util_kernel') is not None else None for n in allc}
    kd = max((kshare[n] - kshare[base_name] for n in targets if kshare[n] is not None and
              kshare[base_name] is not None), default=None)
    add('kernel_share', 'Kernel share of busy time', {n: fp(v, 2) for n, v in kshare.items()},
        'INFO' if kd is None or kd <= 5 else 'WARN',
        'increase %.2f points vs the baseline; kernel/hypervisor work is part of the VM cost' % kd if kd is not None else 'n/a')
    for key, title in CONFIRM.items():
        v = confirm.get(key, 'unknown')
        no = CONFIRM_NO.get(key, 'FAIL')
        if key == 'same_phase' and refuted:
            add('confirm_' + key, title, {'answer': v}, 'WARN', 'answered yes, but the window check refutes it')
            continue
        add('confirm_' + key, title, {'answer': v}, {'yes': 'PASS', 'no': no, 'unknown': 'ASK'}[v],
            {'yes': 'confirmed by the user', 'unknown': 'not confirmed yet: ask the user',
             'no': 'the user says no' + ('; TMA ratios tolerate extra halted time, not a different active phase'
                                         if no == 'WARN' else '')}[v])
    verdict = status_of(checks)
    computed = verdict != 'NOT APPLICABLE' or a.force

    # ---- breakdown
    B = {}
    if computed:
        for n in targets:
            if model[n]['r'] is None:
                continue
            B[n] = breakdown(tree, base, C[n], model[n]['r'], model[n]['beta'], noise)

    # ---- cross-check
    X = []          # evidence rows
    S = []          # node summaries
    if computed and rules.get('rules'):
        idx = {}
        for ri, rule in enumerate(rules['rules']):
            for nd in rule['nodes']:
                idx.setdefault(nd, []).append(ri)
        for n in targets:
            if n not in B:
                continue
            res = B[n]
            sel = [nd for nd in tree.nodes if res[nd]['unw'] is not None and nd in idx and
                   (tree.depth[nd] == 0 or abs(res[nd]['unw']) >= max(a.min_gap, res[nd]['band'] or 0))]
            cand = [nd for nd in sel if tree.depth[nd] > 0]
            cset = set(cand)
            # a child that repeats its parent's gap (e.g. DTLB_Load -> Load_STLB_Miss -> _4K) adds nothing
            cand = [nd for nd in cand if not (tree.parent[nd] in cset and abs(res[nd]['unw'] - res[tree.parent[nd]]['unw'])
                                                <= 0.15 * abs(res[tree.parent[nd]]['unw']))]
            rank = lambda nd: abs(res[nd]['w']) if overlaps(nd) and res[nd]['w'] is not None else abs(res[nd]['unw'])
            cand.sort(key=lambda nd: -rank(nd))
            room = max(a.max_nodes - 4, 0)
            keep = []
            for top in L1:                        # quota: the largest nodes of every level-1 branch first
                keep += [nd for nd in cand if l1_of(nd) == top][:a.per_branch]
            keep = sorted(set(keep), key=lambda nd: -rank(nd))[:room]
            keep += [nd for nd in cand if nd not in keep][:room - len(keep)]
            forced = set(x for spec in (a.nodes or []) for x in spec.split(',') if x)
            keep = set(keep) | set(nd for nd in sel if tree.depth[nd] == 0) | (forced & set(idx))
            sel = [nd for nd in tree.nodes if nd in keep and res[nd]['unw'] is not None]
            for nd in sel:
                g = res[nd]['unw']
                sign = 1 if g > 0 else -1
                cnt = dict(supports=0, contradicts=0, flat=0, missing=0)
                seen = set()
                for ri in idx[nd]:
                    for ev in rules['rules'][ri]['evidence']:
                        if ev['label'] in seen:
                            continue
                        seen.add(ev['label'])
                        vb, vc = evidence_value(base, ev), evidence_value(C[n], ev)
                        ratio = vc / vb if vb not in (None, 0) and vc is not None else None
                        if ratio is None:
                            verdict_ev = 'missing'
                        elif ev.get('worse', 'higher') == 'info':
                            verdict_ev = 'info'
                        else:
                            exp = sign * (1 if ev.get('worse', 'higher') == 'higher' else -1)
                            ch = ratio - 1
                            verdict_ev = 'flat' if abs(ch) < a.evidence_threshold else \
                                ('supports' if ch * exp > 0 else 'neutral' if ev.get('one_sided') else 'contradicts')
                        if verdict_ev in cnt:
                            cnt[verdict_ev] += 1
                        X.append(dict(case=n, node=nd, gap=g, label=ev['label'], kind=ev['kind'], bm=vb, vm=vc,
                                      ratio=ratio, worse=ev.get('worse', 'higher'), verdict=verdict_ev,
                                      why=ev.get('why', '')))
                st = ('corroborated' if cnt['supports'] >= 2 and not cnt['contradicts'] else
                      'weakly supported' if cnt['supports'] == 1 and not cnt['contradicts'] else
                      'mixed' if cnt['supports'] and cnt['contradicts'] else
                      'contradicted' if cnt['contradicts'] else
                      'no signal' if cnt['flat'] else 'no data')
                opp = [d for d in descendants(nd) if res[d]['unw'] is not None and
                       res[d]['unw'] * g < 0 and abs(res[d]['unw']) >= a.min_gap]
                note = ''
                if cnt['contradicts'] and opp:
                    st = 'children diverge'
                    note = 'opposite-sign children: ' + ', '.join('%s %s' % (d, fp(res[d]['unw'], 2, sign=True))
                                                                for d in opp[:4])
                km = model[n]['k_meas']
                S.append(dict(case=n, node=nd, depth=tree.depth[nd], gap=g, band=res[nd]['band'], status=st,
                              note=note, d=(g - (km - model[n]['k']) * res[nd]['bm']) if km else None, **cnt))
    CTX = []
    for ev in rules.get('context', []):
        vals = {n: evidence_value(C[n], ev) for n in allc}
        CTX.append(dict(label=ev['label'], vals=vals, why=ev.get('why', '')))

    # ---- write report
    now = datetime.datetime.now()
    out = a.out or 'tma-breakdown-%s.md' % slug(a.workload)
    L = []
    w = L.append
    w('# TMA breakdown report: %s' % a.workload)
    w('')
    w('Generated %s by `tma_breakdown.py` %s. Baseline: **%s**; compared: %s.' % (
        now.strftime('%Y-%m-%d %H:%M'), VERSION, base_name, ', '.join('**%s**' % t for t in targets)))
    w('')
    w('## 1. Verdict')
    w('')
    w('**%s**%s' % (verdict, ' (breakdown computed with --force)' if verdict == 'NOT APPLICABLE' and a.force else ''))
    w('')
    for c in checks:
        if c['status'] in ('FAIL', 'WARN', 'ASK'):
            w('- **%s** `%s`: %s' % (c['status'], c['id'], c['note']))
    w('')
    w('<!-- AGENT: summarize the verdict and the main findings here (3-6 sentences or up to 8 bullets). -->')
    w('')
    w('## 2. Inputs')
    w('')
    w(md_table(['case', 'EMON file', 'column', 'score', 'score label', 'EMON window s', 'role'],
               [[n, os.path.basename(C[n].path), C[n].column, fp(score.get(n), 3), score_label.get(n, ''),
                 fp(get(n, 'window'), 1), 'baseline' if n == base_name else 'compared'] for n in allc],
               'lllrlrl'))
    w('')
    w('Score direction: %s is better. Score noise used for the noise band: %.2f%%. Minimum gap for the '
      'cross-check: %.2f points. Evidence threshold: %.0f%% change.' % (
          a.direction, a.score_noise, a.min_gap, a.evidence_threshold * 100))
    w('')
    w('## 3. Applicability checks')
    w('')
    w(md_table(['check', 'status'] + allc + ['note'],
               [[c['title'], c['status']] + [c['values'].get(n, c['values'].get('answer', '')) if c['id'].startswith('confirm_')
                                             and n == base_name else c['values'].get(n, '') for n in allc] + [c['note']]
                for c in checks], 'll' + 'r' * len(allc) + 'l'))
    w('')
    w('## 4. Score model')
    w('')
    rows = []
    for key, title, f in (('gap', 'score gap (1 - r)', lambda v: fp(v, 2, True)),
                          ('r', 'r = score ratio', lambda v: fp(v * 100, 2, True) if v else 'n/a'),
                          ('beta', 'beta used', lambda v: fp(v * 100, 2, True)),
                          ('beta_src', 'beta source', str),
                          ('beta_emon', 'beta from EMON (freq x util)', lambda v: fp(v * 100, 2, True) if v else 'n/a'),
                          ('virt', 'gap_virt = r(1/beta - 1)', lambda v: fp(v, 2, True)),
                          ('k_meas', 'EMON CPI_BM / CPI_VM', lambda v: fp(v, 4)),
                          ('alpha', 'alpha (given)', lambda v: fp(v * 100, 2, True) if v is not None else 'not given'),
                          ('implied_alpha', 'alpha implied by EMON CPI', lambda v: fp(v * 100, 2, True) if v is not None else 'n/a')):
        rows.append([title] + [f(model[n][key]) for n in targets])
    w(md_table(['quantity'] + targets, rows, 'l' + 'r' * len(targets)))
    w('')
    if not computed:
        w('The breakdown was not computed because the verdict is NOT APPLICABLE. Resolve the FAIL checks '
          '(or rerun with --force and state why) first.')
        w('')
    else:
        w('## 5. Top-level breakdown (points of score gap)')
        w('')
        w('gap_i = Ratio_i,VM - (r/beta) x Ratio_i,BM. Values marked `~` are within the noise band '
          '(+/- k x noise x Ratio_i,BM).')
        w('')
        rows = []
        for nd in L1:
            row = ['%s gap' % nd]
            for n in targets:
                x = B.get(n, {}).get(nd)
                if not x or x['unw'] is None:
                    row.append('n/a')
                    continue
                row.append(fp(x['unw'], 2, sign=True) + (' ~' if abs(x['unw']) < x['band'] else ''))
            rows.append(row)
        tma_sum = {n: sum(B[n][nd]['unw'] for nd in L1) for n in B}
        rows.append(['TMA gap (sum)'] + [fp(tma_sum.get(n), 2, sign=True) for n in targets])
        rows.append(['gap_virt'] + [fp(model[n]['virt'], 2, sign=True) for n in targets])
        rows.append(['score gap'] + [fp(model[n]['gap'], 2, sign=True) for n in targets])
        rows.append(['residual (rounding / sum != 100%)'] + [
            fp(model[n]['gap'] - tma_sum[n] - model[n]['virt'], 2, sign=True) if n in tma_sum else 'n/a'
            for n in targets])
        w(md_table(['node (points of score gap)'] + targets, rows, 'l' + 'r' * len(targets)))
        w('')
        w('The `~` band covers score noise only. The next table shows how far the EMON windows themselves '
          'support each gap.')
        w('')
        if any(model[n]['k_meas'] for n in targets):
            w('### 5.1 Decomposition against the EMON windows')
            w('')
            w('Exactly, gap_i = d_i + k x alpha x Ratio_i,BM + (k_meas - k_pred) x Ratio_i,BM, where d_i = (change of '
              'node i\'s cycles per instruction between the two EMON windows) / CPI_VM compares the windows '
              'directly without the score, the alpha term is the cost of hypervisor instructions (alpha = 0 when '
              'not given), and the last term is the inconsistency between the scores and the EMON windows '
              '(k_meas = CPI_BM / CPI_VM from EMON, k_pred = r(1+alpha)/beta). When the windows match the scored '
              'runs the last term is about 0. When it is large (cpi_consistency or window WARN), the VM effect '
              'of a node is uncertain by about that term: read d_i and the score-based gap as two views, and '
              'trust conclusions that hold in both, or comparisons between cases whose windows match.')
            w('')
            rows = []
            for nd in L1:
                for label, f in (('score-based gap', lambda m, x: x['unw']),
                                 ('d (EMON per-instruction change)',
                                  lambda m, x: x['unw'] - (m['k_meas'] - m['k']) * x['bm']),
                                 ('alpha term', lambda m, x: m['k'] * (m['alpha'] or 0.0) * x['bm']),
                                 ('window term (unexplained)', lambda m, x: (m['k_meas'] - m['k_pred']) * x['bm'])):
                    row = ['%s: %s' % (nd, label)]
                    for n in targets:
                        m, x = model[n], B.get(n, {}).get(nd)
                        row.append(fp(f(m, x), 2, sign=True) if x and x['unw'] is not None and m['k_meas']
                                   and m['k_pred'] else 'n/a')
                    rows.append(row)
            rows.append(['k_meas - k_pred'] + [fp(model[n]['k_meas'] - model[n]['k_pred'], 4, sign=True)
                                               if model[n]['k_meas'] and model[n]['k_pred'] else 'n/a'
                                               for n in targets])
            w(md_table(['node (points)'] + targets, rows, 'l' + 'r' * len(targets)))
            w('')
        w('## 6. Sub-node breakdown')
        w('')
        w('Weighted gaps use the weight factors of each environment and add up to their parent; `-` means '
          'the children cannot be weighted (fewer than two, or one is 0 in both cases). Unweighted gaps '
          '(Ratio_VM - k x Ratio_BM) only rank siblings. Nodes with |gap| < %.2f in every case are hidden '
          'unless they are level 1 or 2. `‡` marks a cycle-based node larger than its parent: it overlaps other '
          'stalls, and its unweighted gap contains (1 - k) x Ratio_BM from the cycle normalization alone, '
          'so read its weighted value or its evidence instead.' % a.show_min)
        w('')
        rows = []
        for nd in tree.nodes:
            vis = tree.depth[nd] <= 1 or any(
                n in B and B[n][nd]['unw'] is not None and abs(B[n][nd]['unw']) >= a.show_min for n in targets)
            if not vis:
                continue
            row = ['&nbsp;' * 4 * tree.depth[nd] + nd + (' ‡' if overlaps(nd) else ''),
                   fp(B[targets[0]][nd]['bm'], 2) if targets[0] in B else '']
            for n in targets:
                x = B.get(n, {}).get(nd)
                if not x:
                    row += ['n/a'] * 3
                    continue
                row += [fp(x['vm'], 2), fp(x['w'], 2, sign=True) if x['w'] is not None else '-',
                        fp(x['unw'], 2, sign=True) if x['unw'] is not None else 'n/a']
            rows.append(row)
        hdr = ['node', 'Ratio %s %%' % base_name]
        for n in targets:
            hdr += ['Ratio %s %%' % n, 'weighted gap %s' % n, 'unweighted gap %s' % n]
        w(md_table(hdr, rows, 'l' + 'r' * (len(hdr) - 1)))
        w('')
        w('## 7. Cross-validation with other EMON data')
        w('')
        if not rules.get('rules'):
            w('No cross-check rules loaded.')
        else:
            w('For the level-1 nodes and the (at most %d per case) largest TMA nodes whose gap is at least %.2f '
              'points and above its noise band, the rules in `reference/crosscheck-rules.json` list independent EMON metrics. A positive '
              'gap expects the metric to be worse in the VM case. Raw events are normalized per instruction '
              '(INST_RETIRED.ANY) or per cycle (CPU_CLK_UNHALTED.THREAD), which removes the window length; '
              '`flat` means |change| < %.0f%%. One-sided evidence (e.g. walk counts) only supports: a change '
              'the other way is `neutral`, because the cost can grow through another path (e.g. longer walks). '
              '`children diverge` marks a parent whose children have gaps of opposite sign.'
              % (a.max_nodes, a.min_gap, a.evidence_threshold * 100))
            w('')
            w('### 7.1 Node summary')
            w('')
            w(md_table(['case', 'node', 'gap', 'd (window view)', 'supports', 'contradicts', 'flat', 'status', 'note'],
                       [[s['case'], '&nbsp;' * 4 * s['depth'] + s['node'], fp(s['gap'], 2, sign=True),
                         fp(s['d'], 2, sign=True) if s['d'] is not None else 'n/a',
                         s['supports'], s['contradicts'], s['flat'], s['status'], s['note']] for s in S],
                       'llrrrrrll'))
            w('')
            w('### 7.2 Evidence')
            w('')
            w(md_table(['case', 'node', 'gap', 'evidence', 'BM', 'VM', 'VM/BM', 'worse if', 'verdict'],
                       [[x['case'], x['node'], fp(x['gap'], 2, sign=True), x['label'], fsci(x['bm']), fsci(x['vm']),
                         'n/a' if x['ratio'] is None else 'x%.2f' % x['ratio'], x['worse'], x['verdict']]
                        for x in X], 'llrlrrrll'))
            w('')
        if CTX:
            w('### 7.3 Context metrics')
            w('')
            w(md_table(['metric'] + allc + ['why it matters'],
                       [[c['label']] + [fsci(c['vals'][n]) for n in allc] + [c['why']] for c in CTX],
                       'l' + 'r' * len(allc) + 'l'))
            w('')
        w('### 7.4 Automatic observations')
        w('')
        for n in targets:
            if n not in B:
                continue
            sub = [nd for nd in tree.nodes if tree.depth[nd] >= 1]
            topw = sorted([nd for nd in sub if B[n][nd]['w'] is not None], key=lambda nd: -abs(B[n][nd]['w']))[:6]
            topu = sorted([nd for nd in sub if B[n][nd]['unw'] is not None], key=lambda nd: -abs(B[n][nd]['unw']))[:6]
            l1s = ', '.join('%s %s' % (nd, fp(B[n][nd]['unw'], 2, sign=True)) for nd in L1)
            w('- **%s** (score gap %s): %s.' % (n, fp(model[n]['gap'], 2, True), l1s))
            w('  Largest weighted sub-node gaps (share of the score gap): %s.' % ', '.join(
                '%s %s' % (nd, fp(B[n][nd]['w'], 2, sign=True)) for nd in topw))
            w('  Largest unweighted sub-node gaps (ranking only; `‡` = overlapping cycle-based node): %s.' % ', '.join(
                '%s%s %s' % (nd, ' ‡' if overlaps(nd) else '', fp(B[n][nd]['unw'], 2, sign=True)) for nd in topu))
            for s in S:
                if s['case'] == n and s['status'] in ('corroborated', 'weakly supported', 'mixed', 'contradicted',
                                                      'children diverge'):
                    ev = [x for x in X if x['case'] == n and x['node'] == s['node'] and x['verdict'] in ('supports', 'contradicts')]
                    w('  - %s (%s): %s' % (s['node'], s['status'], '; '.join(
                        '%s x%.2f (%s)' % (x['label'], x['ratio'], x['verdict']) for x in ev[:4])))
        w('')
    w('## 8. Hypotheses')
    w('')
    w('<!-- AGENT: replace this comment with numbered hypotheses. Each one names the TMA nodes and the '
      'evidence rows (section 7) it rests on, the mechanism, its confidence, and the experiment that '
      'would confirm or refute it. Keep conjecture clearly separate from what the data shows. -->')
    w('')
    w('## 9. Derived evidence and open questions')
    w('')
    w('<!-- AGENT: list evidence you derived from the raw EMON rows (label it "derived", give the formula and the '
      'values), then the open questions for the user (data, configuration, missing measurements). -->')
    w('')
    w('## 10. Caveats')
    w('')
    w('- The breakdown is an accounting identity over slots, not a causal model: removing a gap does not '
      'necessarily recover the same score (TMA categories interact).')
    w('- gap_i is sensitive to r with the factor Ratio_i,BM: a %.2f%% score noise moves a node by about '
      'k x %.2f%% x Ratio_BM. Window mismatches add the uncertainty shown in section 5.1.' % (a.score_noise, a.score_noise))
    w('- Sub-nodes based on cycle counts may overlap; weighted values are a proportional allocation.')
    w('- EMON rates (per second) depend on the collection window; per-instruction and per-cycle values '
      'do not, but they are still diluted by any non-workload activity inside the window.')
    w('')
    w('## Appendix: method')
    w('')
    w('```')
    w('r        = Score_VM / Score_BM                 (or Time_BM / Time_VM)')
    w('beta     = (Freq_VM * Util_VM) / (Freq_BM * Util_BM)')
    w('gap      = 1 - r = sum_i gap_i + gap_virt')
    w('gap_i    = Ratio_i,VM - (r / beta) * Ratio_i,BM')
    w('gap_virt = r * (1 / beta - 1)')
    w('sub-node = w_i,VM * sub_Ratio_i,j,VM - (r / beta) * w_i,BM * sub_Ratio_i,j,BM,')
    w('           w_i,E = Ratio_i,E / sum_j sub_Ratio_i,j,E')
    w('```')
    w('')
    text = '\n'.join(L)
    for path in (out, a.json):
        if path and os.path.dirname(path):
            os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(out, 'w', encoding='utf-8') as f:
        f.write(text)
    if a.json:
        with open(a.json, 'w') as f:
            json.dump(dict(verdict=verdict, baseline=base_name, targets=targets, model=model, checks=checks,
                           breakdown=B, crosscheck=dict(nodes=S, evidence=X)), f, indent=1, default=str)
    print('verdict: %s' % verdict)
    for c in checks:
        if c['status'] != 'PASS':
            print('  %-5s %-18s %s' % (c['status'], c['id'], c['note']))
    print('report: %s' % os.path.abspath(out))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest='cmd', required=True)

    def inputs(p):
        p.add_argument('--emon', action='append', metavar='CSV', help='EMON summary CSV; every column is a case')
        p.add_argument('--case', action='append', metavar='NAME=CSV[@COLUMN]', help='one case from one column')
        p.add_argument('--json', metavar='FILE', help='also write machine-readable results')

    p = sub.add_parser('inspect', help='list cases and pre-check data')
    inputs(p)
    p.set_defaults(func=cmd_inspect)
    p = sub.add_parser('report', help='checks, breakdown, cross-check and Markdown report')
    inputs(p)
    p.add_argument('--workload', required=True, help='workload name, e.g. 520.omnetpp_r')
    p.add_argument('--baseline', required=True, help='baseline (bare-metal) case name')
    p.add_argument('--compare', action='append', metavar='CASE', help='compared case (default: all others)')
    p.add_argument('--scores', action='append', metavar='CSV', help='score CSV (wide: header + "score" row)')
    p.add_argument('--score', action='append', metavar='CASE=VALUE', help='one score')
    p.add_argument('--direction', choices=['higher', 'lower'], default='higher',
                   help='higher: score/throughput (default); lower: elapsed time')
    p.add_argument('--beta', action='append', metavar='CASE=VALUE', help='steady-state beta of a case (e.g. 1 or 99.5%%)')
    p.add_argument('--beta-mode', choices=['one', 'emon'], default='one',
                   help='beta when not given: 1 (default, simplified formula) or the EMON freq x util ratio')
    p.add_argument('--beta-tol', type=float, default=0.02, help='EMON beta tolerance around 1 (default 0.02)')
    p.add_argument('--alpha', action='append', metavar='CASE=VALUE',
                   help='alpha = IC_hypervisor / IC_BM, usually measured on the host during the VM run as '
                        'instructions:H / instructions:G (assumes IC_guest = IC_BM); only used by the CPI check')
    p.add_argument('--confirm', action='append', metavar='KEY=yes|no|unknown',
                   help='qualitative condition: %s' % ', '.join(CONFIRM))
    p.add_argument('--score-noise', type=float, default=0.5, help='relative score noise in %% (default 0.5)')
    p.add_argument('--min-gap', type=float, default=0.3, help='minimum |gap| (points) to cross-check a node')
    p.add_argument('--show-min', type=float, default=0.05, help='hide sub-nodes with |gap| below this')
    p.add_argument('--max-nodes', type=int, default=20, help='cross-check at most this many nodes per case (20)')
    p.add_argument('--per-branch', type=int, default=4,
                   help='nodes reserved for each level-1 branch before the global ranking (4)')
    p.add_argument('--nodes', action='append', metavar='NODE[,NODE]',
                   help='always cross-check these TMA nodes (in addition to the automatic selection)')
    p.add_argument('--window-tol', type=float, default=0.25,
                   help='tolerance of (T_VM/T_BM) * r around 1 for the window check (0.25)')
    p.add_argument('--evidence-threshold', type=float, default=0.10, help='relative change that counts (0.10)')
    p.add_argument('--rules', default=DEFAULT_RULES, help='cross-check rules JSON ("" to disable)')
    p.add_argument('--force', action='store_true', help='compute even when NOT APPLICABLE')
    p.add_argument('--out', help='report path (default: ./tma-breakdown-<workload>.md, overwritten on rerun)')
    p.set_defaults(func=cmd_report)
    a = ap.parse_args(argv)
    a.func(a)


if __name__ == '__main__':
    main()
