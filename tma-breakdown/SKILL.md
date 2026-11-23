---
name: tma-breakdown
description: Break a throughput score gap between two configurations (typically a virtual machine versus bare metal) down into Intel TMA / top-down nodes from EMON summary CSVs. First checks whether the method applies, then computes the top-level and sub-node breakdown, cross-validates the large TMA gaps against other EMON metrics and events, and delivers a Markdown report (breakdown tables, evidence tables, hypotheses) in the current directory. Use when the user wants to explain a VM-vs-BM (or platform, kernel, BIOS, page-size) performance gap with topdown/TMA data, asks for a "TMA breakdown" or "topdown gap breakdown", or hands over EMON summaries together with scores. Asks the user for the workload name and the score of every case before computing.
---

# TMA breakdown of a score gap

Method: comparing TMA percentages side by side cannot show where a score gap
comes from, because each case normalizes by its own cycle count. This skill
converts the score ratio into a cycle ratio and charges every TMA node with the
slots it costs in addition to bare metal:

```
gap = 1 - r = sum_i (Ratio_i,VM - (r/beta) * Ratio_i,BM) + r * (1/beta - 1)
r = Score_VM / Score_BM        beta = (Freq_VM * Util_VM) / (Freq_BM * Util_BM)
```

The derivation, the sub-node weights and the noise band are in
[reference/method.md](reference/method.md). The checks are explained in
[reference/applicability.md](reference/applicability.md), and the reading of
typical evidence patterns in [reference/interpretation.md](reference/interpretation.md).
Cross-check rules (TMA node to EMON evidence) live in
[reference/crosscheck-rules.json](reference/crosscheck-rules.json).

All computation is done by `scripts/tma_breakdown.py` (Python 3 standard
library only). Never type breakdown numbers by hand. If a parameter changes, rerun the script.
`S` below means the directory of this skill: `S=<skill dir>/scripts`.

## Workflow

### 1. Intake: find the data, then ask the user

1. Look for EMON summaries the user named or that sit in the current
   directory: CSV files whose first header cell looks like
   `(Metric post processor ...) name ...` or that contain rows such as
   `metric_TMA_Frontend_Bound(%)`. A single file may hold several cases as
   columns. Several files with one column each work as well.
2. Run `python3 $S/tma_breakdown.py inspect --emon <file> [--emon <file> ...]`.
   It lists the cases with TMA version, level-1 sum, utilization, frequency,
   CPI and multiplexing reliability.
3. Ask the user, in one batch (use AskUserQuestion when available; otherwise
   ask in plain text and wait). Do not ask for what the user already gave.
   - the **workload name** (e.g. `520.omnetpp_r`);
   - which case is the **baseline** (bare metal) and which cases to compare;
   - the **score of every case** (or a score CSV), and whether higher is better
     (SPEC rate score, throughput) or lower is better (elapsed time). Also ask
     the run-to-run score noise; the default of 0.5% applies otherwise
     (`--score-noise`);
   - how the VM-case EMON was collected: **on the host, system-wide, without a
     guest/host filter**? (required for the identity, see method.md);
   - whether steady-state utilization is equal (e.g. perf
     `ref-cycles` and `msr/tsc/` ratios). This gives `--beta CASE=VALUE`. Optional:
     alpha = IC_hypervisor / IC_BM, usually measured on the host during the VM
     run as perf `instructions:H` / `instructions:G` (it assumes guest
     instructions equal BM). This gives `--alpha CASE=VALUE`;
   - the qualitative conditions of applicability.md: a throughput workload with
     the same copies, EMON windows covering comparable parts of the runs (all
     whole runs, or all the same steady-state range), and saturated CPUs. Map
     "every window spans its whole run" to `same_phase=yes`; the `window` check
     then verifies it.
   A score file in the directory is input only after the user confirms it
   belongs to these EMON runs. Never invent or guess a score.

### 2. Applicability gate

Run the report once (it always writes the checks):

```bash
python3 $S/tma_breakdown.py report --emon <emon.csv> --scores <scores.csv> \
    --workload <name> --baseline <bm case> [--compare <case> ...] \
    [--beta '<case>=1' ...] [--alpha '<case>=1.15%' ...] \
    --confirm throughput=yes|no|unknown --confirm host_side_tma=yes|no|unknown \
    --confirm same_phase=yes|no|unknown --confirm cpu_saturated=yes|no|unknown \
    [--score-noise 0.5] [--out <report.md>] [--json <results.json>]
```

- **NOT APPLICABLE** (any FAIL): the breakdown is not computed. Explain each
  FAIL in one line, say what would fix it (see applicability.md) and ask the
  user how to proceed. Use `--force` only when the user accepts the risk, and
  state that in the report.
- **APPLICABLE WITH CAVEATS** (WARN or ASK): continue, but carry every caveat
  into the verdict summary. Turn ASK items into questions for the user, or keep
  them listed as open questions when the user is unavailable.
- **APPLICABLE**: continue.

Verify the user's answers against the data instead of taking them on trust:
- The `window` check compares the EMON window lengths with the run-time
  ratio 1/r. "Every window spans its whole run" implies T_VM/T_BM ≈ 1/r.
- The `instruction_mix` check compares branches, loads and stores per
  instruction, which are equal for the same binary and input.
- With a CPI mismatch and an unchanged mix, suspect windows that cover
  different phases rather than extra instructions.

Report any contradiction in the verdict summary.

### 3. Breakdown and cross-check

The report already contains:
- section 4: the score model, including the CPI consistency check;
- section 5: the top-level breakdown, like the table in the method document,
  and in 5.1 its decomposition against the EMON windows;
- section 6: the sub-node tree with weighted and unweighted gaps;
- section 7: the cross-validation, with a node summary, an evidence table and
  context metrics.

Read sections 4 to 7 completely before writing anything. The cross-check
covers the four level-1 nodes plus up to `--max-nodes` (default 20) larger
nodes. Each level-1 branch first gets `--per-branch` (default 4) of them.
Children that repeat their parent's gap are skipped. If a node you need is
missing, rerun with `--nodes NODE[,NODE]` or a larger `--max-nodes`; the
report is overwritten.

When the baseline window is unreliable but the compared windows agree with
each other (section 5.1, `window` check), also compare the VM cases with each
other. Rerun with `--baseline <vm case> --out tma-breakdown-<workload>-vs-<case>.md`,
which writes a second report in the current directory. Name it in the
main report's section 9 and fill only its verdict placeholder.

If alpha is known for only some cases, the window term of the others also
contains the cost of hypervisor instructions (about k x alpha x Ratio_BM).
Say so when comparing their window terms.

Extra evidence from the raw EMON rows is allowed (e.g. a `:SUP` split or an
event without a rule). Compute it with a small script that reads the CSV
(under /tmp), and label it "derived" in the report. Never alter the tables
the script generated.

### 4. Interpret and complete the report

Edit only the three `<!-- AGENT: ... -->` placeholders of the generated
report. When section 5.1 shows a large window term, base every conclusion on
what holds both in the score-based gap and in d_i (see method.md):

1. **Verdict summary** (3 to 6 sentences). Cover the applicability verdict and
   its caveats, which top-level node carries the gap in each case, and how the
   cases differ (e.g. the 4K→2M gain that comes from Backend).
2. **Hypotheses**: a numbered list. Each item names:
   - the TMA node(s) and their gap;
   - the evidence rows (section 7) that support or contradict it, with their
     VM/BM ratios;
   - the mechanism;
   - a confidence level. High: status `corroborated` (at least two independent
     events) and the gap holds in both views of section 5.1. Medium: `weakly
     supported` or `mixed`, or only one view. Low: TMA only;
   - the experiment that would confirm or refute it.

   Use the patterns of interpretation.md, but say when the data does not fit
   them. Keep data and conjecture apart. The breakdown is an accounting
   identity, not causality.
3. **Derived evidence and open questions**: list evidence you derived from the
   raw rows, labeled "derived" with its formula and values. Then list the open
   questions for the user. If a matched score label carries extra text (shown
   in the inputs table, e.g. a configuration note), ask what it means.

Do not change the numbers or tables of the generated report. If you exclude a
case or change a parameter, rerun the script.

### 5. Deliver

The report is written to the current directory as
`tma-breakdown-<workload>.md`, unless `--out` is given. A rerun overwrites it,
so fill the placeholders after the last run. Use `--out` to keep a variant.
Reply to the user with:
- the report path;
- the verdict;
- the top-level table of the main cases;
- the two or three strongest hypotheses with their evidence;
- the open questions or caveats.

## Boundaries

- Read-only on the input data. Never edit the EMON or score files.
- The method needs a throughput workload whose score is proportional to
  1/elapsed time, with CPUs saturated, the same frequency and utilization (or a
  measured beta), and TMA collected over all cycles of each case. When it does
  not apply, say so instead of producing numbers.
- The cross-check rules use Intel SPR/EMR/GNR EMON names. Evidence that is
  missing on another platform shows as `missing`. Extend the rules file rather
  than guessing.
