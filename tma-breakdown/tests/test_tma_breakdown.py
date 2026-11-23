"""Offline tests of tma_breakdown.py on synthetic EMON summaries (no real data needed)."""
import json
import os
import subprocess
import sys
import tempfile
import unittest


def load(path):
    with open(path) as f:
        return json.load(f)


def read(path):
    with open(path) as f:
        return f.read()

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, '..', 'scripts', 'tma_breakdown.py')
RULES = os.path.join(HERE, '..', 'reference', 'crosscheck-rules.json')

TMA = [  # (dots, name, bm, vm)
    (0, 'Frontend_Bound', 10.0, 14.0),
    (2, 'Fetch_Latency', 7.0, 10.0),
    (4, 'ICache_Misses', 1.0, 3.0),
    (6, 'Code_L2_Hit', 0.0, 0.0),
    (6, 'Code_L2_Miss', 0.4, 1.0),
    (4, 'Branch_Resteers', 2.0, 3.5),
    (2, 'Fetch_Bandwidth', 3.0, 4.0),
    (0, 'Bad_Speculation', 5.0, 5.0),
    (2, 'Branch_Mispredicts', 4.5, 4.5),
    (2, 'Machine_Clears', 0.5, 0.5),
    (0, 'Backend_Bound', 60.0, 58.0),
    (2, 'Memory_Bound', 55.0, 53.0),
    (4, 'L1_Bound', 2.0, 4.0),
    (6, 'DTLB_Load', 10.0, 20.0),
    (4, 'DRAM_Bound', 50.0, 48.0),
    (2, 'Core_Bound', 5.0, 5.0),
    (0, 'Retiring', 25.0, 23.0),
    (2, 'Light_Operations', 24.0, 22.0),
    (2, 'Heavy_Operations', 1.0, 1.0),
]


def emon_csv(path, util_vm=100.0, cpi_vm=2.2, win_vm=111.0, loads_vm=3e10, win_bm=100.0):
    rows = [['(Metric post processor 5.19.0) name (sample #1 - #10)', 'bm', 'vm test']]
    rows += [['metric_CPU operating frequency (in GHz)', '3.0', '3.0'],
             ['metric_CPU utilization %', '100.0', str(util_vm)],
             ['metric_CPU utilization% in kernel mode', '0.5', '2.0'],
             ['metric_CPI', '2.0', str(cpi_vm)],
             ['metric_EMON event mux reliability%', '99.9', '99.8'],
             ['metric_TMA_Metrics_Version', '5.1', '5.1']]
    rows += [['metric_TMA_%s%s(%%)' % ('.' * d, n), str(b), str(v)] for d, n, b, v in TMA]
    rows += [['metric_TMA_Info_Thread_IPC', '0.5', '0.45'],
             ['INST_RETIRED.ANY', '1e11', '0.95e11'],
             ['CPU_CLK_UNHALTED.THREAD', '2e11', '2.09e11'],
             ['BACLEARS.ANY', '1e7', '5e7'],
             ['DTLB_LOAD_MISSES.WALK_COMPLETED', '1e8', '0.8e8'],
             ['DTLB_LOAD_MISSES.WALK_ACTIVE', '6e9', '1.2e10'],
             ['BR_INST_RETIRED.ALL_BRANCHES', '2e10', '1.9e10'],
             ['MEM_INST_RETIRED.ALL_LOADS', '3e10', str(loads_vm * 0.95)],
             ['MEM_INST_RETIRED.ALL_STORES', '1e10', '0.95e10'],
             ['$samplingTime', str(win_bm), str(win_vm)]]
    with open(path, 'w', newline='') as f:
        f.write('\n'.join(','.join(r) for r in rows) + '\n')


def score_csv(path, bm=100.0, vm=90.0):
    with open(path, 'w', newline='') as f:   # CRLF and a longer column name, like real score files
        f.write(',bm,vm test (extra notes)\r\nscore,%s,%s\r\n' % (bm, vm))


class T(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.d = self._tmp.name
        self.emon = os.path.join(self.d, 'emon.csv')
        self.scores = os.path.join(self.d, 'score.csv')
        emon_csv(self.emon)
        score_csv(self.scores)

    def tearDown(self):
        self._tmp.cleanup()

    def run_report(self, *extra, ok=True):
        out, js = os.path.join(self.d, 'r.md'), os.path.join(self.d, 'r.json')
        cmd = [sys.executable, '-I', SCRIPT, 'report', '--emon', self.emon, '--scores', self.scores,
               '--workload', 'synthetic', '--baseline', 'bm', '--out', out, '--json', js] + list(extra)
        p = subprocess.run(cmd, capture_output=True, text=True)
        if ok:
            self.assertEqual(p.returncode, 0, p.stderr)
        return p, (load(js) if p.returncode == 0 else None), out

    def confirms(self):
        return ['--confirm', 'throughput=yes', '--confirm', 'host_side_tma=yes',
                '--confirm', 'same_phase=yes', '--confirm', 'cpu_saturated=yes']

    def test_inspect(self):
        p = subprocess.run([sys.executable, '-I', SCRIPT, 'inspect', '--emon', self.emon],
                           capture_output=True, text=True)
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn('vm test', p.stdout)
        self.assertIn('100.00', p.stdout)

    def test_identity_and_verdict(self):
        _, j, out = self.run_report(*self.confirms())
        self.assertEqual(j['verdict'], 'APPLICABLE')
        b = j['breakdown']['vm test']
        l1 = sum(b[n]['unw'] for n in ('Frontend_Bound', 'Bad_Speculation', 'Backend_Bound', 'Retiring'))
        m = j['model']['vm test']
        self.assertAlmostEqual(m['r'], 0.9)
        self.assertAlmostEqual(l1 + m['virt'], m['gap'], places=6)
        self.assertAlmostEqual(b['Frontend_Bound']['unw'], 14.0 - 0.9 * 10.0, places=6)
        text = read(out)
        for sec in ('## 5. Top-level breakdown', '## 6. Sub-node breakdown', '## 7. Cross-validation',
                    '<!-- AGENT: replace this comment'):
            self.assertIn(sec, text)

    def test_weights(self):
        _, j, _ = self.run_report(*self.confirms())
        b = j['breakdown']['vm test']
        fe_children = b['Fetch_Latency']['w'] + b['Fetch_Bandwidth']['w']
        self.assertAlmostEqual(fe_children, b['Frontend_Bound']['unw'], places=6)
        self.assertAlmostEqual(b['ICache_Misses']['w'] + b['Branch_Resteers']['w'], b['Fetch_Latency']['w'], places=6)
        self.assertIsNone(b['Code_L2_Miss']['w'])           # sibling Code_L2_Hit is 0 in both cases
        self.assertIsNone(b['DTLB_Load']['w'])              # single child
        self.assertIsNotNone(b['DTLB_Load']['unw'])

    def test_util_gate(self):
        emon_csv(self.emon, util_vm=90.0)
        _, j, _ = self.run_report(*self.confirms())
        self.assertEqual(j['verdict'], 'NOT APPLICABLE')
        self.assertEqual(j['breakdown'], {})
        _, j, _ = self.run_report(*self.confirms(), '--beta', 'vm test=1')
        self.assertEqual(j['verdict'], 'APPLICABLE WITH CAVEATS')
        self.assertIn('vm test', j['breakdown'])
        _, j, _ = self.run_report(*self.confirms(), '--force')
        self.assertIn('vm test', j['breakdown'])

    def test_beta_term(self):
        _, j, _ = self.run_report(*self.confirms(), '--beta', 'vm test=95%')
        m, b = j['model']['vm test'], j['breakdown']['vm test']
        self.assertAlmostEqual(m['virt'], 0.9 * (1 / 0.95 - 1) * 100, places=6)
        l1 = sum(b[n]['unw'] for n in ('Frontend_Bound', 'Bad_Speculation', 'Backend_Bound', 'Retiring'))
        self.assertAlmostEqual(l1 + m['virt'], m['gap'], places=6)

    def test_unknown_confirm_is_caveat(self):
        _, j, _ = self.run_report()
        self.assertEqual(j['verdict'], 'APPLICABLE WITH CAVEATS')

    def test_same_phase_no_is_caveat(self):
        args = [x if x != 'same_phase=yes' else 'same_phase=no' for x in self.confirms()]
        _, j, _ = self.run_report(*args)
        self.assertEqual(j['verdict'], 'APPLICABLE WITH CAVEATS')
        args = [x if x != 'throughput=yes' else 'throughput=no' for x in self.confirms()]
        _, j, _ = self.run_report(*args)
        self.assertEqual(j['verdict'], 'NOT APPLICABLE')

    def status(self, j):
        return {c['id']: c['status'] for c in j['checks']}

    def test_window_and_mix_checks(self):
        _, j, _ = self.run_report(*self.confirms())
        st = self.status(j)
        self.assertEqual(st['window'], 'PASS')            # 111 s / 100 s ~ 1/r = 1.11
        self.assertEqual(st['instruction_mix'], 'PASS')
        emon_csv(self.emon, win_vm=400.0, loads_vm=3.3e10)
        _, j, _ = self.run_report(*self.confirms())
        st = self.status(j)
        self.assertEqual(st['window'], 'WARN')
        self.assertEqual(st['instruction_mix'], 'WARN')
        self.assertIn('contradicts the same_phase answer', [c for c in j['checks'] if c['id'] == 'window'][0]['note'])
        self.assertEqual(st['confirm_same_phase'], 'WARN')     # a refuted "yes" is not a PASS

    def test_one_sided_and_dedupe(self):
        _, j, _ = self.run_report(*self.confirms())
        walks = [x for x in j['crosscheck']['evidence'] if x['label'] == 'DTLB load walks per instr']
        self.assertTrue(walks and all(x['verdict'] == 'neutral' for x in walks))   # fewer walks, longer walks
        nodes = [s['node'] for s in j['crosscheck']['nodes']]
        self.assertIn('Frontend_Bound', nodes)

    def test_partial_baseline_window(self):
        emon_csv(self.emon, win_bm=30.0)       # VM busy x r = 99.9 s, BM busy 30 s
        _, j, _ = self.run_report(*self.confirms())
        c = [c for c in j['checks'] if c['id'] == 'window'][0]
        self.assertEqual(c['status'], 'WARN')
        self.assertIn('baseline window covers about 30% of its run', c['note'])

    def test_outputs_forced_nodes_and_markers(self):
        js = os.path.join(self.d, 'new', 'dir', 'r.json')
        out = os.path.join(self.d, 'other', 'r.md')
        p = subprocess.run([sys.executable, '-I', SCRIPT, 'report', '--emon', self.emon, '--scores', self.scores,
                            '--workload', 'synthetic', '--baseline', 'bm', '--out', out, '--json', js,
                            '--nodes', 'Machine_Clears'] + self.confirms(), capture_output=True, text=True)
        self.assertEqual(p.returncode, 0, p.stderr)
        j = load(js)
        self.assertIn('Machine_Clears', [s['node'] for s in j['crosscheck']['nodes']])
        text = read(out)
        self.assertIn('DTLB_Load ‡', text)                  # 20% > parent L1_Bound 4%
        self.assertIn('### 5.1 Decomposition against the EMON windows', text)
        # d_FE = (CPI_VM * R_VM - CPI_BM * R_BM) / CPI_VM = (2.2*14 - 2.0*10) / 2.2 = +4.91
        self.assertIn('| Frontend_Bound: d (EMON per-instruction change) | +4.91 |', text)
        self.assertIn('| Frontend_Bound: score-based gap | +5.00 |', text)
        self.assertIn('## 9. Derived evidence and open questions', text)

    def test_cpi_consistency_warns(self):
        emon_csv(self.emon, cpi_vm=1.9)        # implied alpha = (2.0/1.9)/0.9 - 1 = +17%
        _, j, _ = self.run_report(*self.confirms())
        st = {c['id']: c['status'] for c in j['checks']}
        self.assertEqual(st['cpi_consistency'], 'WARN')

    def test_lower_is_better(self):
        score_csv(self.scores, bm=100.0, vm=110.0)   # elapsed times
        _, j, _ = self.run_report(*self.confirms(), '--direction', 'lower')
        self.assertAlmostEqual(j['model']['vm test']['r'], 100 / 110)

    def test_crosscheck_rows(self):
        _, j, _ = self.run_report(*self.confirms())
        ev = [x for x in j['crosscheck']['evidence'] if x['label'] == 'BACLEARS.ANY per instr']
        self.assertTrue(ev and all(x['verdict'] == 'supports' for x in ev))
        walk = [x for x in j['crosscheck']['evidence'] if x['label'] == 'cycles per DTLB load walk']
        self.assertTrue(walk and walk[0]['ratio'] > 2)

    def test_rules_file(self):
        rules = load(RULES)
        kinds = {'metric', 'event', 'event_per_instr', 'event_per_cycle', 'event_ratio'}
        for r in rules['rules'] + [{'nodes': ['context'], 'evidence': rules['context']}]:
            self.assertTrue(r['nodes'])
            for e in r['evidence']:
                self.assertIn(e['kind'], kinds)
                self.assertIn(e.get('worse', 'higher'), ('higher', 'lower', 'info'))
                self.assertIn(e.get('one_sided', False), (True, False))
                self.assertFalse(set(e) - {'label', 'kind', 'metric', 'event', 'num', 'den', 'worse', 'one_sided', 'why'}, e)
                need = {'metric': ['metric'], 'event': ['event'], 'event_per_instr': ['event'],
                        'event_per_cycle': ['event'], 'event_ratio': ['num', 'den']}[e['kind']]
                for k in need:
                    self.assertTrue(e.get(k), e)

    def test_missing_score_fails(self):
        with open(self.scores, 'w') as f:
            f.write(',bm\nscore,100\n')
        _, j, _ = self.run_report(*self.confirms())
        self.assertEqual(j['verdict'], 'NOT APPLICABLE')


if __name__ == '__main__':
    unittest.main(verbosity=1)
