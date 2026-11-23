# Reading the breakdown and the evidence

Use these patterns as starting points for hypotheses. Each one lists the data
that supports it and the experiment that would confirm it. If the data does
not fit a pattern, say so.

Evidence verdicts in the report:
- `supports` / `contradicts` compare the direction of change with the sign of
  the node's gap.
- `neutral` marks one-sided evidence that moved the other way. Walk counts are
  an example: fewer walks do not refute a walk cost that grew through longer
  walks.
- `info` rows have no expected direction.
- `children diverge` marks a parent whose children have gaps of opposite sign;
  read the children, not the parent.

## Memory and translation (Backend_Bound)

| pattern | likely mechanism | confirm with |
|---|---|---|
| Load_STLB_Miss / DTLB_Load gap large; DTLB walks per instr flat or lower; cycles per walk and walk-active cycles up (often x2) | two-dimensional page walks: each guest walk step needs an EPT walk, so walks are longer, not more frequent | guest huge pages (THP or hugetlbfs in the guest) together with 2M/1G EPT backing; `DTLB_LOAD_MISSES.WALK_ACTIVE / WALK_COMPLETED` before and after |
| DTLB gap drops from 4K to 2M EPT but stays above BM | guest page tables still use 4K pages, or the walk caches thrash | guest THP status, `/proc/<pid>/smaps` AnonHugePages in the guest |
| Load_STLB_Miss_4K dominates in the VM, `Load_STLB_Miss_2M` small | guest mappings are 4K | as above |
| LLC page walk MPI up | page-walk references miss the LLC; nested page tables enlarge the walk footprint | 1G EPT pages; fewer guest page-table levels |
| Backend gap ≈ 0 or negative, DRAM_Bound negative | within the noise band, or reallocation: more front-end stalls leave fewer slots to back-end stalls | compare against the noise band; check MEM latency and bandwidth metrics |
| unweighted DTLB_Load larger than Backend_Bound | cycle-based node that overlaps other memory stalls | read the weighted value as a lower bound and walk-active cycles as an upper bound |

## Front end (Frontend_Bound)

| pattern | likely mechanism | confirm with |
|---|---|---|
| ICache_Misses, ITLB_Misses and Unknown_Branches up 5-30x per instruction, similar across guest page sizes | code-side pollution by VM exits and interrupts: host and hypervisor code evicts L1I/L2/ITLB/BTB, and the guest refetches after each exit | exit rate (`perf kvm stat`); timer and interrupt configuration (tickless guest, posted interrupts, APICv); collect ICACHE/BACLEARS with :G and :H on the host to split by mode |
| Unknown_Branches and BACLEARS up; Ind_Call and Ret mispredicts up | branch predictor flushed or overwritten on VM exit/entry by speculative-execution mitigations (IBPB, RSB stuffing, BHI clearing) | A/B test with the mitigation settings of host and guest; count exits |
| Code_L2_Miss and LLC code hits per instr up | instruction working set no longer fits L2 because of the extra code | same as the first row |
| ITLB walks per instr up, cycles per walk down | many short walks that hit the caches: an ITLB capacity loss, not walk cost | guest text on huge pages (e.g. 2M text) and its effect on ITLB_Misses |
| Code_L2_Hit, Code_STLB_Hit = 0 in all cases | metric unsupported in this EMON version | do not interpret; use the raw events |

## Bad speculation and retiring

| pattern | likely mechanism | confirm with |
|---|---|---|
| Bad_Speculation gap small but Ind_Call / Ret mispredicts per instr up | predictor state lost on transitions | as for Unknown_Branches |
| Retiring gap positive; supervisor share of instructions up; far branches per instr up | extra instructions per unit of work: exits, interrupt handling, guest kernel activity, idle polling | perf `instructions:G` and `instructions:H` (alpha); exit reasons |
| CPI consistency WARN with implied alpha ≫ measured alpha | the EMON window includes activity outside the scored work (idle polling, misaligned window) | collect EMON within the steady state; compare `metric_CPU utilization %` |
| CPI WARN with the same implied alpha in every case + `window` WARN naming the baseline as partial + `instruction_mix` PASS | the baseline window samples one phase of its run (e.g. 233 s of a run of about 820 s), while the VM windows cover whole runs; per-phase CPI and TMA differ from the run average | re-process all EMON over whole runs or matching sample ranges. Until then use section 5.1: keep conclusions that hold in both views (score-based gap and d_i) and comparisons between the VM cases; call gaps that are mostly window term not a VM effect |
| workload-intrinsic per-instr events (LLC MPI, walks per instr) uniformly lower in every VM case while the mix is unchanged | window or phase mismatch, not a VM effect: a VM does not change the workload's miss rates downward | as above |
| one-thread-active cycles or SMT 2T utilization differ | SMT siblings idle in the window (tail of the run, imbalance) | trim the windows; check per-copy run times |
| Serializing_Operation / PAUSE up | spin loops (halt polling, lock spinning) or serializing instructions on the exit path | PAUSE per instr; halt-polling settings |

## Writing a hypothesis

```
H1 (high): Backend +8.8 points in the 4K VM come from two-dimensional page walks.
Evidence: Load_STLB_Miss unweighted +15.8; cycles per DTLB load walk x2.37 and
walk-active cycles x1.95 (supports); walks per instr x0.89 (fewer, not more walks).
Mechanism: guest 4K page walks need an EPT walk per step.
Test: back the guest with 2M EPT pages and enable guest THP; expect cycles per walk
-> BM level and Backend gap -> noise band.
```
