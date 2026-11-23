# Applicability checks

`tma_breakdown.py report` evaluates every check and derives the verdict:
- any FAIL gives NOT APPLICABLE;
- any WARN or ASK gives APPLICABLE WITH CAVEATS;
- otherwise the verdict is APPLICABLE.

| id | condition | PASS | WARN / ASK | FAIL | if it fails |
|---|---|---|---|---|---|
| tma_present | level-1 TMA nodes exist in every case | all four present | - | missing | collect EMON with the TMA metric file |
| tma_sum | level-1 ratios add up to 100% | within 1 point | 1-3 points | > 3 points | the identity needs 100%; check multiplexing or the metric file |
| tma_version | same TMA metric version | equal | differs | - | node definitions may differ; compare only common nodes |
| mux | EMON multiplexing reliability | >= 95% | 90-95% | < 90% | longer runs, fewer events, or a non-multiplexed TMA (perf-metrics) group |
| scores | a score for every case | all present | - | missing | ask the user; never guess |
| freq | same core frequency | within 1% | larger | - | pin the frequency, or give beta including the frequency ratio |
| util | same utilization (beta = 1) | EMON beta within 2% of 1 | steady-state beta given but EMON differs | EMON beta off and no beta given | investigate the utilization gap first (off-CPU, I/O, imbalance); measure steady-state beta (perf `ref-cycles`/`msr/tsc/`) and pass `--beta` |
| cpi_consistency | EMON CPI matches the score model | within 3% (alpha given) or implied alpha in [-2%, +5%] | otherwise | - | see method.md, consistency check; prefer a steady-state window |
| window | windows cover comparable parts of the runs: busy time (window x util) x r agrees across cases | within the tolerance | the compared windows disagree, or the baseline busy time differs from them (the note gives its coverage by busy time and by user instructions) | - | re-process EMON over whole runs or matching ranges; meanwhile read section 5.1 |
| instruction_mix | branches, loads, stores per instruction equal | within 3% | differs | - | different binary or input, or non-workload instructions of another mix |
| uncore, ddr | same uncore frequency and DDR rate | within 1% | differs | - | shared resources are outside the model: say so |
| kernel_share | kernel share of busy time | INFO | VM +5 points or more | - | kernel/hypervisor work is part of the cost; read it with Retiring and the frontend |
| confirm_throughput | score ∝ 1/time, same copies and score metric | yes | unknown | no | the method needs a throughput score |
| confirm_host_side_tma | VM EMON on the host, system-wide, no :G/:H filter | yes | unknown | no | in-guest TMA misses the host cycles (method.md gives the h variant) |
| confirm_same_phase | windows cover comparable parts of the runs (all whole runs, or all the same steady-state range) | yes | unknown or no (WARN) | - | ratios tolerate extra halted time, not a different active phase; the window check verifies the answer |
| confirm_cpu_saturated | CPUs busy; no serial section, I/O or sleep dominating | yes | unknown | no | TMA cannot explain off-CPU time; analyze utilization instead |

## Notes

- A low EMON utilization in a CPU-saturated benchmark usually means the window
  includes time before, after or between copies. TMA ratios count only
  unhalted cycles, so they are hurt less than event rates, but idle-polling code
  still retires instructions inside the window.
- The method compares the same workload binary and input in every case. For
  different platforms or microarchitectures it still holds per case: ratios are
  fractions of each case's own slots, and only the score is shared. Node
  definitions must match, though, and the result explains slots, not ISA or
  compiler differences.
- Uncore, memory-bandwidth and cross-socket effects show up inside Backend
  nodes. When they differ between cases, mention it next to the Backend gap.
