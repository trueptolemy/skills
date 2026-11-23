# Example: 520.omnetpp_r, VM vs bare metal

A complete run of the skill on real data: SPEC CPU 2017 520.omnetpp_r rate,
240 copies, on bare metal and in three VM configurations.

| file | content |
|---|---|
| `520 debug test.csv` | EMON summary, one column per case: `bm`, `4k-nothp vm`, `2m vm`, `2m ept 2m text` (TMA 5.1, GNR) |
| `520 debug score.csv` | SPECrate score of each case (the header carries a configuration note for `2m ept 2m text`) |
| `tma-breakdown-520.omnetpp_r.md` | the delivered report |
| `tma-breakdown-520.omnetpp_r.json` | the machine-readable results of the same run (`--json`) |

## How it was produced

An independent agent was asked to "explain the VM vs bare-metal gap of my 520
run" and followed `SKILL.md`. It ran `inspect`, then `report`, read sections
4 to 7, and filled in the three AGENT parts of the report:
- the verdict summary in section 1;
- the hypotheses in section 8;
- the derived evidence and open questions in section 9.

The user's answers to the intake questions were:
- workload 520.omnetpp_r, with higher scores better;
- baseline `bm`, compared with all three VM cases;
- the scores are in `520 debug score.csv`;
- the VM EMON was collected on the host, system-wide and unfiltered;
- steady-state utilization is 100% everywhere, so beta = 1;
- alpha = 1.15%, measured only for `2m vm`;
- a throughput workload with saturated CPUs;
- "EMON was started before and stopped after the workload in every case".

The script-generated tables were then regenerated with the current script, and
the agent's text was carried over unchanged except for two phrases that follow
the current output format. All derived numbers in section 9 (D1–D4, D9, D10)
were recomputed independently and match.

Commands, run inside this directory:

```bash
S=../scripts
python3 $S/tma_breakdown.py inspect --emon '520 debug test.csv'
python3 $S/tma_breakdown.py report --emon '520 debug test.csv' --scores '520 debug score.csv' \
    --workload 520.omnetpp_r --baseline bm \
    --compare '4k-nothp vm' --compare '2m vm' --compare '2m ept 2m text' \
    --beta '4k-nothp vm=1' --beta '2m vm=1' --beta '2m ept 2m text=1' --alpha '2m vm=1.15%' \
    --confirm throughput=yes --confirm host_side_tma=yes --confirm same_phase=yes --confirm cpu_saturated=yes \
    --out /tmp/520-check.md --json /tmp/520-check.json
# VM-vs-VM rerun (derived item D10 of the report): both windows are whole runs
python3 $S/tma_breakdown.py report --emon '520 debug test.csv' --scores '520 debug score.csv' \
    --workload 520.omnetpp_r --baseline '2m vm' --compare '4k-nothp vm' --compare '2m ept 2m text' \
    --beta '4k-nothp vm=1' --beta '2m ept 2m text=1' \
    --confirm throughput=yes --confirm host_side_tma=yes --confirm same_phase=yes --confirm cpu_saturated=yes \
    --out /tmp/520-vs-2m-vm.md
```

`tests/test_tma_breakdown.py` reruns the first report command. It checks that
the computed sections (score model, breakdown, decomposition) still equal those
in `tma-breakdown-520.omnetpp_r.md`.

## What the example shows

- **The applicability gate working on real data.** Three findings:
  - The user's answer about the windows is refuted by the data. The BM EMON
    window covers only about 28% of its run, while the VM windows cover
    whole runs (`window` WARN).
  - Every VM case therefore implies the same ~10% "alpha"
    (`cpi_consistency` WARN), against a measured 1.15%.
  - The instruction mix is unchanged (`instruction_mix` PASS), so this is a
    phase mismatch, not extra code.
- **Two views of every gap (section 5.1).** These conclusions hold in both
  the score-based view and d_i:
  - Frontend is a VM cost in every case.
  - The 4K-EPT Backend cost is about 9 points. The VM-vs-VM rerun confirms it
    with consistent windows.

  The Retiring and Bad_Speculation gaps against BM come from the partial BM
  window. The sign of the 2M-EPT Backend gap stays open.
- **Cross-validation (section 7).** Each claim is backed by independent events:
  - ICache misses: L1-I misses per instruction ×24–39.
  - Unknown branches: BACLEARS ×5.5–6.
  - Two-dimensional page walks: cycles per DTLB walk ×2.37 at a lower walk count.
- **Hypotheses with confidence and tests (section 8).** Examples are exit-induced
  front-end pollution, predictor state loss, nested page walks, the 2M-text
  side effects and SNC cross-cluster reads. Each one names its evidence rows
  and the experiment that would confirm it.
