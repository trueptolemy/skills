# TMA breakdown report: 520.omnetpp_r

Generated 2026-11-23 09:21 by `tma_breakdown.py` 1.0. Baseline: **bm**; compared: **4k-nothp vm**, **2m vm**, **2m ept 2m text**.

## 1. Verdict

**APPLICABLE WITH CAVEATS**

- **WARN** `util`: EMON-window utilization differs (beta_emon furthest from 1: 0.878) but steady-state beta was given; the EMON window likely includes idle time outside the workload
- **WARN** `cpi_consistency`: 4k-nothp vm: EMON CPI implies +10.7% instructions per unit of work vs the baseline; 2m vm: EMON CPI ratio deviates +8.7% from r(1+alpha)/beta; 2m ept 2m text: EMON CPI implies +10.7% instructions per unit of work vs the baseline; the same implied alpha in every compared case points at the baseline window rather than at the VMs (see the window check); a user-mode CPI ratio that deviates like the total one means the workload code itself runs at a different speed in that window (another phase). TMA ratios may include non-workload activity (misaligned window, idle polling, extra kernel/hypervisor code); alpha cancels out of the breakdown itself
- **WARN** `window`: the baseline window covers about 28% of its run by busy time and 26% by user instructions, while the compared windows agree with whole runs (busy time tracks 1/r within 1%); this contradicts the same_phase answer. TMA of a partial window may not represent the scored run
- **WARN** `confirm_same_phase`: answered yes, but the window check refutes it

**Summary.** APPLICABLE WITH CAVEATS: TMA, multiplexing, frequency, instruction mix and the other user confirmations pass, and the utilization WARN (EMON 88-96% in the VM windows) is covered by the measured steady-state beta = 1. **The data contradicts the answer that every EMON window spans its whole run:** the BM window lasts 232.7 s at 100% utilization, about 27-28% of a BM run of roughly 865 s, while the VM windows match whole runs; this explains the identical implied alpha of +10.0% to +10.7% in every VM case (measured: 1.15% for 2m vm) and adds a window term of 0.08-0.10 x Ratio_BM to every gap against BM (Backend +5.7 to +7.0 points, section 5.1). Frontend_Bound is a VM cost in every case and holds in both views (+5.84 / +4.31 / +5.39 points score-based, +4.71 / +3.12 / +4.11 in d_i), driven by ICache_Misses, Unknown_Branches and ITLB_Misses with code-miss and resteer events up 5x to 40x per instruction; in the 2M-EPT VMs it carries essentially the whole gap (5.35 and 4.93 points), while their Backend sign is unresolved (-0.39 / -1.88 score-based, -6.84 / -8.84 in d_i). The 4K VM's extra cost is Backend: +8.81 points against BM, and +9.16 of the 11.43-point gap against 2m vm in a VM-vs-VM rerun with whole-run windows and consistent CPI, where cycles per DTLB load walk are x1.77 at an unchanged walk count (two-dimensional page walks with 4K EPT). Adding 2M text to 2M EPT scores within noise of 2m vm (-0.44 points; Frontend +1.06, Backend -1.49). The Retiring (+0.98 to +1.08) and Bad_Speculation (+0.34 to +0.53) gaps against BM come from the BM window, not from the VM (d_i about 0 or negative).

## 2. Inputs

| case | EMON file | column | score | score label | EMON window s | role |
|:---|:---|:---|---:|:---|---:|:---|
| bm | 520 debug test.csv | bm | 364.060 | bm | 232.7 | baseline |
| 4k-nothp vm | 520 debug test.csv | 4k-nothp vm | 305.220 | 4k-nothp vm | 1029.1 | compared |
| 2m vm | 520 debug test.csv | 2m vm | 344.600 | 2m vm | 991.5 | compared |
| 2m ept 2m text | 520 debug test.csv | 2m ept 2m text | 346.100 | 2m ept 2m text (2m test section ratio - 45%) | 913.7 | compared |

Score direction: higher is better. Score noise used for the noise band: 0.50%. Minimum gap for the cross-check: 0.30 points. Evidence threshold: 10% change.

## 3. Applicability checks

| check | status | bm | 4k-nothp vm | 2m vm | 2m ept 2m text | note |
|:---|:---|---:|---:|---:|---:|:---|
| Level-1 TMA nodes present | PASS | yes | yes | yes | yes | Frontend_Bound, Bad_Speculation, Backend_Bound, Retiring |
| Level-1 TMA ratios add up to 100% | PASS | 100.00 | 100.00 | 100.00 | 100.00 | max deviation 0.00%; the identity needs sum = 100% |
| Same TMA metric version | PASS | 5.1 | 5.1 | 5.1 | 5.1 | node definitions must match across cases |
| EMON event multiplexing reliability | PASS | 99.99 | 99.77 | 99.91 | 99.57 | below 95% the multiplexed TMA events are unreliable |
| Scores available for every case | PASS | 364.060 | 305.220 | 344.600 | 346.100 | direction: higher is better |
| Same core frequency | PASS | 3.393 | 3.392 | 3.392 | 3.392 | max deviation 0.03%; otherwise beta must include the frequency ratio |
| Same CPU utilization (beta = 1) | WARN | 100.02 | 95.16 | 87.88 | 95.87 | EMON-window utilization differs (beta_emon furthest from 1: 0.878) but steady-state beta was given; the EMON window likely includes idle time outside the workload |
| EMON CPI consistent with the score model | WARN | - | implied alpha +10.7%; user-mode CPI ratio 0.947 vs total 0.928 | CPI ratio 1.041 vs model 0.957 (+8.7%); user-mode CPI ratio 1.057 vs total 1.041 | implied alpha +10.7%; user-mode CPI ratio 1.070 vs total 1.053 | 4k-nothp vm: EMON CPI implies +10.7% instructions per unit of work vs the baseline; 2m vm: EMON CPI ratio deviates +8.7% from r(1+alpha)/beta; 2m ept 2m text: EMON CPI implies +10.7% instructions per unit of work vs the baseline; the same implied alpha in every compared case points at the baseline window rather than at the VMs (see the window check); a user-mode CPI ratio that deviates like the total one means the workload code itself runs at a different speed in that window (another phase). TMA ratios may include non-workload activity (misaligned window, idle polling, extra kernel/hypervisor code); alpha cancels out of the breakdown itself |
| EMON windows cover comparable parts of the runs | WARN | 232.7 s, busy 232.8 s | 1029.1 s, busy 979.3 s | 991.5 s, busy 871.3 s | 913.7 s, busy 876.0 s | the baseline window covers about 28% of its run by busy time and 26% by user instructions, while the compared windows agree with whole runs (busy time tracks 1/r within 1%); this contradicts the same_phase answer. TMA of a partial window may not represent the scored run |
| Same instruction mix (branches, loads, stores per instr) | PASS | - | -0.33% | +1.27% | -1.39% | same binary and input expected; a uniform shift means non-workload instructions of another mix (about the size of the shift) or a different binary. With a CPI mismatch and an unchanged mix, suspect windows covering different phases rather than extra instructions |
| Same uncore frequency | PASS | 2.197 | 2.191 | 2.190 | 2.190 | shared resources outside the core model; differences limit the method |
| Same DDR data rate | PASS | 6393.313 | 6392.941 | 6392.575 | 6392.871 | shared resources outside the core model; differences limit the method |
| Kernel share of busy time | INFO | 0.61 | 3.87 | 3.45 | 3.12 | increase 3.26 points vs the baseline; kernel/hypervisor work is part of the VM cost |
| Throughput workload: score is proportional to 1/elapsed time, same copies/threads and same score metric in every case | PASS | yes |  |  |  | confirmed by the user |
| VM-case EMON was collected on the host, system-wide, without a guest/host mode filter (TMA covers guest, hypervisor and transition cycles) | PASS | yes |  |  |  | confirmed by the user |
| EMON windows of all cases cover comparable parts of their runs (all whole runs, or all the same steady-state range) | WARN | yes |  |  |  | answered yes, but the window check refutes it |
| All CPUs are busy in steady state: no single-thread critical section, I/O, sleep or off-CPU wait dominates | PASS | yes |  |  |  | confirmed by the user |

## 4. Score model

| quantity | 4k-nothp vm | 2m vm | 2m ept 2m text |
|:---|---:|---:|---:|
| score gap (1 - r) | 16.16% | 5.35% | 4.93% |
| r = score ratio | 83.84% | 94.65% | 95.07% |
| beta used | 100.00% | 100.00% | 100.00% |
| beta source | given | given | given |
| beta from EMON (freq x util) | 95.12% | 87.84% | 95.82% |
| gap_virt = r(1/beta - 1) | 0.00% | 0.00% | 0.00% |
| EMON CPI_BM / CPI_VM | 0.9278 | 1.0409 | 1.0526 |
| alpha (given) | not given | 1.15% | not given |
| alpha implied by EMON CPI | 10.67% | 9.97% | 10.72% |

## 5. Top-level breakdown (points of score gap)

gap_i = Ratio_i,VM - (r/beta) x Ratio_i,BM. Values marked `~` are within the noise band (+/- k x noise x Ratio_i,BM).

| node (points of score gap) | 4k-nothp vm | 2m vm | 2m ept 2m text |
|:---|---:|---:|---:|
| Frontend_Bound gap | +5.84 | +4.31 | +5.39 |
| Bad_Speculation gap | +0.53 | +0.41 | +0.34 |
| Backend_Bound gap | +8.81 | -0.39 | -1.88 |
| Retiring gap | +0.98 | +1.02 | +1.08 |
| TMA gap (sum) | +16.16 | +5.35 | +4.93 |
| gap_virt | +0.00 | +0.00 | +0.00 |
| score gap | +16.16 | +5.35 | +4.93 |
| residual (rounding / sum != 100%) | +0.00 | +0.00 | +0.00 |

The `~` band covers score noise only. The next table shows how far the EMON windows themselves support each gap.

### 5.1 Decomposition against the EMON windows

Exactly, gap_i = d_i + k x alpha x Ratio_i,BM + (k_meas - k_pred) x Ratio_i,BM, where d_i = (change of node i's cycles per instruction between the two EMON windows) / CPI_VM compares the windows directly without the score, the alpha term is the cost of hypervisor instructions (alpha = 0 when not given), and the last term is the inconsistency between the scores and the EMON windows (k_meas = CPI_BM / CPI_VM from EMON, k_pred = r(1+alpha)/beta). When the windows match the scored runs the last term is about 0. When it is large (cpi_consistency or window WARN), the VM effect of a node is uncertain by about that term: read d_i and the score-based gap as two views, and trust conclusions that hold in both, or comparisons between cases whose windows match.

| node (points) | 4k-nothp vm | 2m vm | 2m ept 2m text |
|:---|---:|---:|---:|
| Frontend_Bound: score-based gap | +5.84 | +4.31 | +5.39 |
| Frontend_Bound: d (EMON per-instruction change) | +4.71 | +3.12 | +4.11 |
| Frontend_Bound: alpha term | +0.00 | +0.14 | +0.00 |
| Frontend_Bound: window term (unexplained) | +1.13 | +1.05 | +1.28 |
| Bad_Speculation: score-based gap | +0.53 | +0.41 | +0.34 |
| Bad_Speculation: d (EMON per-instruction change) | -0.21 | -0.37 | -0.50 |
| Bad_Speculation: alpha term | +0.00 | +0.09 | +0.00 |
| Bad_Speculation: window term (unexplained) | +0.74 | +0.69 | +0.84 |
| Backend_Bound: score-based gap | +8.81 | -0.39 | -1.88 |
| Backend_Bound: d (EMON per-instruction change) | +2.71 | -6.84 | -8.84 |
| Backend_Bound: alpha term | +0.00 | +0.74 | +0.00 |
| Backend_Bound: window term (unexplained) | +6.11 | +5.70 | +6.96 |
| Retiring: score-based gap | +0.98 | +1.02 | +1.08 |
| Retiring: d (EMON per-instruction change) | +0.01 | +0.00 | -0.02 |
| Retiring: alpha term | +0.00 | +0.12 | +0.00 |
| Retiring: window term (unexplained) | +0.97 | +0.91 | +1.11 |
| k_meas - k_pred | +0.0895 | +0.0835 | +0.1019 |

## 6. Sub-node breakdown

Weighted gaps use the weight factors of each environment and add up to their parent; `-` means the children cannot be weighted (fewer than two, or one is 0 in both cases). Unweighted gaps (Ratio_VM - k x Ratio_BM) only rank siblings. Nodes with |gap| < 0.05 in every case are hidden unless they are level 1 or 2. `‡` marks a cycle-based node larger than its parent: it overlaps other stalls, and its unweighted gap contains (1 - k) x Ratio_BM from the cycle normalization alone, so read its weighted value or its evidence instead.

| node | Ratio bm % | Ratio 4k-nothp vm % | weighted gap 4k-nothp vm | unweighted gap 4k-nothp vm | Ratio 2m vm % | weighted gap 2m vm | unweighted gap 2m vm | Ratio 2m ept 2m text % | weighted gap 2m ept 2m text | unweighted gap 2m ept 2m text |
|:---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Frontend_Bound | 12.59 | 16.39 | +5.84 | +5.84 | 16.22 | +4.31 | +4.31 | 17.35 | +5.39 | +5.39 |
| &nbsp;&nbsp;&nbsp;&nbsp;Fetch_Latency | 8.24 | 12.32 | +5.41 | +5.41 | 11.71 | +3.91 | +3.91 | 12.63 | +4.80 | +4.80 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;ICache_Misses | 0.25 | 2.40 | +1.88 | +2.19 | 2.36 | +1.88 | +2.13 | 2.68 | +2.28 | +2.44 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Code_L2_Miss | 0.07 | 0.80 | - | +0.75 | 0.68 | - | +0.62 | 0.85 | - | +0.78 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;ITLB_Misses | 0.28 | 1.92 | +1.44 | +1.69 | 1.12 | +0.74 | +0.85 | 0.99 | +0.67 | +0.73 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Code_STLB_Miss | 0.01 | 0.30 | - | +0.30 | 0.02 | - | +0.01 | 0.00 | - | +0.00 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Code_STLB_Miss_4K | 0.03 | 0.51 | - | +0.48 | 0.13 | - | +0.10 | 0.10 | - | +0.07 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Branch_Resteers | 2.44 | 4.71 | +2.11 | +2.67 | 4.35 | +1.64 | +2.04 | 4.35 | +1.82 | +2.03 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Mispredicts_Resteers | 1.93 | 2.24 | +0.38 | +0.62 | 2.24 | +0.23 | +0.42 | 2.23 | +0.31 | +0.40 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Unknown_Branches | 0.42 | 2.38 | +1.72 | +2.02 | 2.01 | +1.40 | +1.61 | 2.02 | +1.50 | +1.61 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;MS_Switches | 0.11 | 0.23 | +0.11 | +0.14 | 0.23 | +0.10 | +0.12 | 0.26 | +0.15 | +0.16 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;DSB_Switches | 5.38 | 4.87 | -0.14 | +0.36 | 5.04 | -0.45 | -0.05 | 5.20 | -0.09 | +0.09 |
| &nbsp;&nbsp;&nbsp;&nbsp;Fetch_Bandwidth | 4.35 | 4.08 | +0.43 | +0.43 | 4.52 | +0.40 | +0.40 | 4.72 | +0.59 | +0.59 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;MITE | 3.04 | 2.71 | +0.12 | +0.16 | 3.00 | +0.09 | +0.12 | 3.07 | +0.17 | +0.18 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;DSB | 4.57 | 4.21 | +0.26 | +0.38 | 4.68 | +0.25 | +0.36 | 4.79 | +0.36 | +0.45 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;MS | 0.06 | 0.15 | +0.06 | +0.10 | 0.15 | +0.05 | +0.09 | 0.16 | +0.07 | +0.11 |
| Bad_Speculation | 8.28 | 7.47 | +0.53 | +0.53 | 8.25 | +0.41 | +0.41 | 8.22 | +0.34 | +0.34 |
| &nbsp;&nbsp;&nbsp;&nbsp;Branch_Mispredicts | 7.93 | 7.17 | +0.53 | +0.53 | 7.91 | +0.41 | +0.41 | 7.86 | +0.33 | +0.33 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Cond_NT_Mispredicts | 0.48 | 0.42 | -0.03 | +0.02 | 0.47 | +0.00 | +0.02 | 0.36 | -0.32 | -0.10 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Cond_TK_Mispredicts | 0.38 | 0.33 | -0.03 | +0.01 | 0.37 | +0.00 | +0.01 | 0.42 | +0.07 | +0.06 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Ind_Call_Mispredicts | 0.03 | 0.08 | +0.12 | +0.05 | 0.08 | +0.12 | +0.05 | 0.08 | +0.12 | +0.06 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Ind_Jump_Mispredicts | 0.06 | 0.05 | -0.01 | +0.00 | 0.05 | -0.01 | +0.00 | 0.11 | +0.12 | +0.05 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Other_Mispredicts | 2.15 | 2.11 | +0.42 | +0.31 | 2.21 | +0.23 | +0.18 | 2.35 | +0.29 | +0.31 |
| &nbsp;&nbsp;&nbsp;&nbsp;Machine_Clears | 0.35 | 0.30 | +0.00 | +0.00 | 0.34 | +0.00 | +0.00 | 0.35 | +0.02 | +0.02 |
| Backend_Bound | 68.28 | 66.05 | +8.81 | +8.81 | 64.23 | -0.39 | -0.39 | 63.02 | -1.88 | -1.88 |
| &nbsp;&nbsp;&nbsp;&nbsp;Memory_Bound | 62.99 | 61.09 | +8.28 | +8.28 | 58.96 | -0.66 | -0.66 | 57.94 | -1.94 | -1.94 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;L1_Bound | 1.63 | 2.76 | +1.03 | +1.39 | 2.59 | +0.74 | +1.05 | 2.15 | +0.38 | +0.59 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;DTLB_Load ‡ | 15.30 | 28.64 | +1.00 | +15.81 | 18.68 | +0.61 | +4.20 | 18.84 | +0.35 | +4.30 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Load_STLB_Hit | 1.09 | 0.92 | +0.00 | +0.00 | 1.07 | +0.02 | +0.04 | 0.78 | -0.01 | -0.26 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Load_STLB_Miss | 14.20 | 27.72 | +1.00 | +15.82 | 17.61 | +0.59 | +4.17 | 18.05 | +0.36 | +4.55 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Load_STLB_Miss_4K | 14.20 | 27.59 | +0.99 | +15.69 | 17.51 | +0.58 | +4.07 | 17.95 | +0.35 | +4.46 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Load_STLB_Miss_2M | 0.01 | 0.12 | +0.01 | +0.12 | 0.09 | +0.01 | +0.08 | 0.10 | +0.01 | +0.09 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;L1_Latency_Dependency ‡ | 3.79 | 3.51 | +0.02 | +0.33 | 4.01 | +0.10 | +0.42 | 3.98 | +0.04 | +0.37 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Lock_Latency | 0.01 | 0.06 | +0.00 | +0.05 | 0.06 | +0.00 | +0.05 | 0.05 | +0.00 | +0.05 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Split_Loads | 0.44 | 0.39 | +0.00 | +0.02 | 0.44 | +0.01 | +0.02 | 0.25 | -0.01 | -0.17 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;FB_Full | 1.05 | 0.83 | +0.00 | -0.05 | 0.91 | +0.01 | -0.08 | 0.95 | +0.00 | -0.05 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;L2_Bound | 1.02 | 1.56 | +0.51 | +0.70 | 1.27 | +0.20 | +0.31 | 1.43 | +0.30 | +0.45 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;L2_Hit_Latency ‡ | 2.70 | 2.64 | - | +0.38 | 2.83 | - | +0.27 | 3.09 | - | +0.52 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;L3_Bound | 8.63 | 12.17 | +3.61 | +4.94 | 9.63 | +0.85 | +1.46 | 9.66 | +0.77 | +1.45 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;L3_Hit_Latency | 3.97 | 3.98 | +3.59 | +0.66 | 4.18 | +0.85 | +0.43 | 4.19 | +0.78 | +0.41 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;DRAM_Bound ‡ | 68.84 | 63.20 | +3.06 | +5.49 | 64.44 | -2.48 | -0.73 | 64.20 | -3.37 | -1.25 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;MEM_Bandwidth | 22.35 | 19.73 | -0.57 | +0.99 | 21.24 | -1.10 | +0.08 | 20.49 | -1.65 | -0.76 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;MEM_Latency ‡ | 77.52 | 80.09 | +3.63 | +15.10 | 78.68 | -1.38 | +5.30 | 79.51 | -1.72 | +5.82 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Local_MEM | 35.41 | 30.53 | +3.21 | +0.84 | 33.55 | -1.73 | +0.03 | 33.22 | -2.06 | -0.45 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Remote_Cache | 0.17 | 0.47 | +0.42 | +0.33 | 0.48 | +0.35 | +0.32 | 0.47 | +0.34 | +0.31 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Store_Bound | 0.77 | 0.76 | +0.07 | +0.11 | 0.81 | +0.03 | +0.08 | 0.74 | -0.02 | +0.01 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Store_Latency ‡ | 17.79 | 15.42 | +0.00 | +0.51 | 16.43 | +0.00 | -0.41 | 16.59 | -0.04 | -0.32 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;False_Sharing | 0.05 | 0.17 | +0.00 | +0.13 | 0.20 | +0.00 | +0.16 | 0.18 | +0.00 | +0.13 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;DTLB_Store ‡ | 8.90 | 11.03 | +0.07 | +3.56 | 9.76 | +0.03 | +1.33 | 9.82 | +0.01 | +1.35 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Store_STLB_Hit | 4.84 | 4.34 | +0.00 | +0.28 | 4.88 | +0.01 | +0.30 | 4.78 | +0.00 | +0.18 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Store_STLB_Miss | 4.06 | 6.69 | +0.07 | +3.28 | 4.88 | +0.03 | +1.04 | 5.04 | +0.02 | +1.17 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Store_STLB_Miss_4K | 4.05 | 6.68 | +0.07 | +3.28 | 4.87 | +0.03 | +1.04 | 5.02 | +0.02 | +1.18 |
| &nbsp;&nbsp;&nbsp;&nbsp;Core_Bound | 5.29 | 4.97 | +0.53 | +0.53 | 5.27 | +0.26 | +0.26 | 5.09 | +0.06 | +0.06 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Serializing_Operation | 0.51 | 0.78 | - | +0.35 | 0.73 | - | +0.25 | 0.73 | - | +0.24 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Ports_Utilization ‡ | 8.08 | 8.93 | - | +2.16 | 9.49 | - | +1.84 | 9.60 | - | +1.92 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Ports_Utilized_0 | 1.83 | 3.14 | - | +1.60 | 2.97 | - | +1.23 | 3.04 | - | +1.30 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Ports_Utilized_1 | 5.56 | 5.20 | - | +0.54 | 5.77 | - | +0.51 | 5.78 | - | +0.50 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Ports_Utilized_2 | 3.61 | 3.37 | - | +0.34 | 3.78 | - | +0.36 | 3.86 | - | +0.43 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Ports_Utilized_3m | 8.11 | 7.51 | - | +0.71 | 8.42 | - | +0.75 | 8.60 | - | +0.89 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;ALU_Op_Utilization | 8.16 | 7.71 | - | +0.87 | 8.48 | - | +0.76 | 8.57 | - | +0.81 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Port_0 | 6.43 | 6.10 | - | +0.71 | 6.80 | - | +0.72 | 7.11 | - | +1.00 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Port_1 | 4.47 | 4.28 | - | +0.53 | 4.73 | - | +0.50 | 4.82 | - | +0.57 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Port_6 ‡ | 18.79 | 17.75 | - | +2.00 | 19.29 | - | +1.51 | 19.40 | - | +1.54 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Load_Op_Utilization ‡ | 10.84 | 10.02 | - | +0.94 | 11.11 | - | +0.85 | 11.21 | - | +0.90 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Store_Op_Utilization ‡ | 9.32 | 8.65 | - | +0.84 | 9.56 | - | +0.74 | 9.52 | - | +0.66 |
| Retiring | 10.86 | 10.08 | +0.98 | +0.98 | 11.30 | +1.02 | +1.02 | 11.40 | +1.08 | +1.08 |
| &nbsp;&nbsp;&nbsp;&nbsp;Light_Operations | 10.07 | 9.28 | +0.83 | +0.83 | 10.49 | +0.96 | +0.96 | 10.60 | +1.03 | +1.03 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Memory_Operations | 5.12 | 4.69 | +0.40 | +0.40 | 5.31 | +0.46 | +0.46 | 5.37 | +0.50 | +0.50 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Fused_Instructions | 1.01 | 0.93 | +0.08 | +0.08 | 1.05 | +0.09 | +0.09 | 1.11 | +0.14 | +0.14 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Non_Fused_Branches | 1.23 | 1.12 | +0.09 | +0.09 | 1.30 | +0.14 | +0.14 | 1.28 | +0.10 | +0.10 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Other_Light_Ops | 2.67 | 2.50 | +0.26 | +0.26 | 2.80 | +0.27 | +0.27 | 2.82 | +0.28 | +0.28 |
| &nbsp;&nbsp;&nbsp;&nbsp;Heavy_Operations | 0.78 | 0.80 | +0.14 | +0.14 | 0.81 | +0.06 | +0.06 | 0.80 | +0.06 | +0.06 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Few_Uops_Instructions | 0.76 | 0.70 | +0.06 | +0.06 | 0.70 | -0.01 | -0.01 | 0.70 | -0.02 | -0.02 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Microcode_Sequencer | 0.03 | 0.10 | +0.08 | +0.08 | 0.10 | +0.08 | +0.08 | 0.10 | +0.08 | +0.08 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;CISC | 0.03 | 0.10 | +0.08 | +0.08 | 0.10 | +0.08 | +0.08 | 0.10 | +0.08 | +0.08 |

## 7. Cross-validation with other EMON data

For the level-1 nodes and the (at most 20 per case) largest TMA nodes whose gap is at least 0.30 points and above its noise band, the rules in `reference/crosscheck-rules.json` list independent EMON metrics. A positive gap expects the metric to be worse in the VM case. Raw events are normalized per instruction (INST_RETIRED.ANY) or per cycle (CPU_CLK_UNHALTED.THREAD), which removes the window length; `flat` means |change| < 10%. One-sided evidence (e.g. walk counts) only supports: a change the other way is `neutral`, because the cost can grow through another path (e.g. longer walks). `children diverge` marks a parent whose children have gaps of opposite sign.

### 7.1 Node summary

| case | node | gap | d (window view) | supports | contradicts | flat | status | note |
|:---|:---|---:|---:|---:|---:|---:|:---|:---|
| 4k-nothp vm | Frontend_Bound | +5.84 | +4.71 | 4 | 0 | 0 | corroborated |  |
| 4k-nothp vm | &nbsp;&nbsp;&nbsp;&nbsp;Fetch_Latency | +5.41 | +4.67 | 4 | 0 | 0 | corroborated |  |
| 4k-nothp vm | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;ICache_Misses | +2.19 | +2.17 | 8 | 0 | 0 | corroborated |  |
| 4k-nothp vm | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;ITLB_Misses | +1.69 | +1.66 | 5 | 0 | 0 | corroborated |  |
| 4k-nothp vm | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Branch_Resteers | +2.67 | +2.45 | 2 | 0 | 0 | corroborated |  |
| 4k-nothp vm | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Unknown_Branches | +2.02 | +1.99 | 2 | 0 | 0 | corroborated |  |
| 4k-nothp vm | Bad_Speculation | +0.53 | -0.21 | 0 | 0 | 2 | no signal |  |
| 4k-nothp vm | &nbsp;&nbsp;&nbsp;&nbsp;Branch_Mispredicts | +0.53 | -0.18 | 0 | 0 | 2 | no signal |  |
| 4k-nothp vm | Backend_Bound | +8.81 | +2.71 | 1 | 0 | 2 | weakly supported |  |
| 4k-nothp vm | &nbsp;&nbsp;&nbsp;&nbsp;Memory_Bound | +8.28 | +2.65 | 1 | 0 | 2 | weakly supported |  |
| 4k-nothp vm | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;L1_Bound | +1.39 | +1.24 | 4 | 0 | 0 | corroborated |  |
| 4k-nothp vm | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;DTLB_Load | +15.81 | +14.45 | 4 | 0 | 0 | corroborated |  |
| 4k-nothp vm | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;L3_Bound | +4.94 | +4.16 | 1 | 0 | 2 | weakly supported |  |
| 4k-nothp vm | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;DRAM_Bound | +5.49 | -0.67 | 0 | 0 | 4 | no signal |  |
| 4k-nothp vm | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;MEM_Bandwidth | +0.99 | -1.01 | 0 | 0 | 0 | no data |  |
| 4k-nothp vm | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;MEM_Latency | +15.10 | +8.17 | 0 | 0 | 4 | no signal |  |
| 4k-nothp vm | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Ports_Utilization | +2.16 | +1.43 | 1 | 0 | 1 | weakly supported |  |
| 4k-nothp vm | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Ports_Utilized_0 | +1.60 | +1.43 | 1 | 0 | 1 | weakly supported |  |
| 4k-nothp vm | Retiring | +0.98 | +0.01 | 2 | 0 | 2 | corroborated |  |
| 4k-nothp vm | &nbsp;&nbsp;&nbsp;&nbsp;Light_Operations | +0.83 | -0.07 | 2 | 0 | 2 | corroborated |  |
| 2m vm | Frontend_Bound | +4.31 | +3.12 | 4 | 0 | 0 | corroborated |  |
| 2m vm | &nbsp;&nbsp;&nbsp;&nbsp;Fetch_Latency | +3.91 | +3.13 | 4 | 0 | 0 | corroborated |  |
| 2m vm | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;ICache_Misses | +2.13 | +2.10 | 8 | 0 | 0 | corroborated |  |
| 2m vm | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Code_L2_Miss | +0.62 | +0.61 | 8 | 0 | 0 | corroborated |  |
| 2m vm | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;ITLB_Misses | +0.85 | +0.83 | 5 | 0 | 0 | corroborated |  |
| 2m vm | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Branch_Resteers | +2.04 | +1.81 | 2 | 0 | 0 | corroborated |  |
| 2m vm | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Unknown_Branches | +1.61 | +1.57 | 2 | 0 | 0 | corroborated |  |
| 2m vm | Bad_Speculation | +0.41 | -0.37 | 0 | 0 | 2 | no signal |  |
| 2m vm | &nbsp;&nbsp;&nbsp;&nbsp;Branch_Mispredicts | +0.41 | -0.34 | 0 | 0 | 2 | no signal |  |
| 2m vm | Backend_Bound | -0.39 | -6.84 | 0 | 1 | 2 | children diverge | opposite-sign children: L1_Bound +1.05, L2_Bound +0.31, L3_Bound +1.46, Ports_Utilization +1.84 |
| 2m vm | &nbsp;&nbsp;&nbsp;&nbsp;Memory_Bound | -0.66 | -6.60 | 0 | 1 | 2 | children diverge | opposite-sign children: L1_Bound +1.05, L2_Bound +0.31, L3_Bound +1.46, DTLB_Load +4.20 |
| 2m vm | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;L1_Bound | +1.05 | +0.89 | 3 | 0 | 1 | corroborated |  |
| 2m vm | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;DTLB_Load | +4.20 | +2.76 | 3 | 0 | 1 | corroborated |  |
| 2m vm | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;L3_Bound | +1.46 | +0.64 | 0 | 0 | 3 | no signal |  |
| 2m vm | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;MEM_Latency | +5.30 | -2.01 | 0 | 0 | 4 | no signal |  |
| 2m vm | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Store_STLB_Miss | +1.04 | +0.65 | 3 | 0 | 0 | corroborated |  |
| 2m vm | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Ports_Utilization | +1.84 | +1.07 | 1 | 0 | 1 | weakly supported |  |
| 2m vm | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Ports_Utilized_0 | +1.23 | +1.06 | 1 | 0 | 1 | weakly supported |  |
| 2m vm | Retiring | +1.02 | +0.00 | 2 | 0 | 2 | corroborated |  |
| 2m vm | &nbsp;&nbsp;&nbsp;&nbsp;Light_Operations | +0.96 | +0.01 | 2 | 0 | 2 | corroborated |  |
| 2m ept 2m text | Frontend_Bound | +5.39 | +4.11 | 4 | 0 | 0 | corroborated |  |
| 2m ept 2m text | &nbsp;&nbsp;&nbsp;&nbsp;Fetch_Latency | +4.80 | +3.96 | 4 | 0 | 0 | corroborated |  |
| 2m ept 2m text | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;ICache_Misses | +2.44 | +2.42 | 8 | 0 | 0 | corroborated |  |
| 2m ept 2m text | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Code_L2_Miss | +0.78 | +0.77 | 8 | 0 | 0 | corroborated |  |
| 2m ept 2m text | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;ITLB_Misses | +0.73 | +0.70 | 2 | 2 | 1 | mixed |  |
| 2m ept 2m text | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Branch_Resteers | +2.03 | +1.79 | 2 | 0 | 0 | corroborated |  |
| 2m ept 2m text | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Unknown_Branches | +1.61 | +1.57 | 2 | 0 | 0 | corroborated |  |
| 2m ept 2m text | Bad_Speculation | +0.34 | -0.50 | 0 | 0 | 2 | no signal |  |
| 2m ept 2m text | &nbsp;&nbsp;&nbsp;&nbsp;Branch_Mispredicts | +0.33 | -0.48 | 0 | 0 | 2 | no signal |  |
| 2m ept 2m text | Backend_Bound | -1.88 | -8.84 | 0 | 1 | 2 | children diverge | opposite-sign children: L1_Bound +0.59, L2_Bound +0.45, L3_Bound +1.45, Ports_Utilization +1.92 |
| 2m ept 2m text | &nbsp;&nbsp;&nbsp;&nbsp;Memory_Bound | -1.94 | -8.36 | 0 | 1 | 2 | children diverge | opposite-sign children: L1_Bound +0.59, L2_Bound +0.45, L3_Bound +1.45, DTLB_Load +4.30 |
| 2m ept 2m text | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;L1_Bound | +0.59 | +0.43 | 3 | 0 | 1 | corroborated |  |
| 2m ept 2m text | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;L3_Bound | +1.45 | +0.57 | 0 | 0 | 3 | no signal |  |
| 2m ept 2m text | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;DRAM_Bound | -1.25 | -8.26 | 2 | 0 | 2 | corroborated |  |
| 2m ept 2m text | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;MEM_Bandwidth | -0.76 | -3.04 | 0 | 0 | 0 | no data |  |
| 2m ept 2m text | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;MEM_Latency | +5.82 | -2.08 | 0 | 2 | 2 | children diverge | opposite-sign children: Local_MEM -0.45 |
| 2m ept 2m text | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Ports_Utilization | +1.92 | +1.09 | 1 | 0 | 1 | weakly supported |  |
| 2m ept 2m text | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Ports_Utilized_0 | +1.30 | +1.11 | 1 | 0 | 1 | weakly supported |  |
| 2m ept 2m text | Retiring | +1.08 | -0.02 | 1 | 0 | 3 | weakly supported |  |
| 2m ept 2m text | &nbsp;&nbsp;&nbsp;&nbsp;Light_Operations | +1.03 | +0.00 | 1 | 0 | 3 | weakly supported |  |

### 7.2 Evidence

| case | node | gap | evidence | BM | VM | VM/BM | worse if | verdict |
|:---|:---|---:|:---|---:|---:|---:|:---|:---|
| 4k-nothp vm | Frontend_Bound | +5.84 | cycles with 0 uops delivered (per cycle) | 0.04256 | 0.06304 | x1.48 | higher | supports |
| 4k-nothp vm | Frontend_Bound | +5.84 | ICACHE_DATA.STALLS per cycle | 2.506e-03 | 0.02398 | x9.57 | higher | supports |
| 4k-nothp vm | Frontend_Bound | +5.84 | BACLEARS.ANY per instr | 2.182e-04 | 1.336e-03 | x6.12 | higher | supports |
| 4k-nothp vm | Frontend_Bound | +5.84 | ITLB walks per instr | 5.277e-06 | 1.268e-04 | x24.03 | higher | supports |
| 4k-nothp vm | Fetch_Latency | +5.41 | cycles with 0 uops delivered (per cycle) | 0.04256 | 0.06304 | x1.48 | higher | supports |
| 4k-nothp vm | Fetch_Latency | +5.41 | ICACHE_DATA.STALLS per cycle | 2.506e-03 | 0.02398 | x9.57 | higher | supports |
| 4k-nothp vm | Fetch_Latency | +5.41 | BACLEARS.ANY per instr | 2.182e-04 | 1.336e-03 | x6.12 | higher | supports |
| 4k-nothp vm | Fetch_Latency | +5.41 | ITLB walks per instr | 5.277e-06 | 1.268e-04 | x24.03 | higher | supports |
| 4k-nothp vm | ICache_Misses | +2.19 | L1-I code read misses per instr | 8.080e-05 | 2.246e-03 | x27.80 | higher | supports |
| 4k-nothp vm | ICache_Misses | +2.19 | ICACHE_DATA.STALLS per cycle | 2.506e-03 | 0.02398 | x9.57 | higher | supports |
| 4k-nothp vm | ICache_Misses | +2.19 | ICACHE_TAG.MISS per instr | 8.270e-05 | 2.520e-03 | x30.48 | higher | supports |
| 4k-nothp vm | ICache_Misses | +2.19 | L2 code read misses per instr | 7.626e-05 | 1.414e-03 | x18.54 | higher | supports |
| 4k-nothp vm | ICache_Misses | +2.19 | L2 demand code MPI | 7.620e-05 | 1.414e-03 | x18.55 | higher | supports |
| 4k-nothp vm | ICache_Misses | +2.19 | LLC code hits per instr | 7.490e-05 | 1.412e-03 | x18.86 | higher | supports |
| 4k-nothp vm | ICache_Misses | +2.19 | LLC code read MPI | 8.910e-07 | 1.410e-06 | x1.58 | higher | supports |
| 4k-nothp vm | ICache_Misses | +2.19 | retired instrs after an L1I miss, per instr | 2.295e-05 | 5.568e-04 | x24.26 | higher | supports |
| 4k-nothp vm | ITLB_Misses | +1.69 | ITLB (2nd level) MPI | 5.270e-06 | 1.268e-04 | x24.06 | higher | supports |
| 4k-nothp vm | ITLB_Misses | +1.69 | ITLB walks per instr | 5.277e-06 | 1.268e-04 | x24.03 | higher | supports |
| 4k-nothp vm | ITLB_Misses | +1.69 | ITLB STLB hits per instr | 9.449e-06 | 2.194e-05 | x2.32 | higher | supports |
| 4k-nothp vm | ITLB_Misses | +1.69 | cycles per ITLB walk | 190.5 | 126.9 | x0.67 | higher | neutral |
| 4k-nothp vm | ITLB_Misses | +1.69 | ITLB miss latency (core clks) | 190.5 | 126.9 | x0.67 | higher | neutral |
| 4k-nothp vm | ITLB_Misses | +1.69 | retired instrs after an ITLB miss, per instr | 1.105e-06 | 5.401e-05 | x48.86 | higher | supports |
| 4k-nothp vm | ITLB_Misses | +1.69 | retired instrs after an STLB miss (code), per instr | 9.041e-07 | 4.623e-05 | x51.14 | higher | supports |
| 4k-nothp vm | Branch_Resteers | +2.67 | BACLEARS.ANY per instr | 2.182e-04 | 1.336e-03 | x6.12 | higher | supports |
| 4k-nothp vm | Branch_Resteers | +2.67 | unknown-branch cycles per cycle | 4.233e-03 | 0.02378 | x5.62 | higher | supports |
| 4k-nothp vm | Unknown_Branches | +2.02 | BACLEARS.ANY per instr | 2.182e-04 | 1.336e-03 | x6.12 | higher | supports |
| 4k-nothp vm | Unknown_Branches | +2.02 | unknown-branch cycles per cycle | 4.233e-03 | 0.02378 | x5.62 | higher | supports |
| 4k-nothp vm | Bad_Speculation | +0.53 | branch mispredict ratio | 0.02212 | 0.02142 | x0.97 | higher | flat |
| 4k-nothp vm | Bad_Speculation | +0.53 | mispredicted branches per instr | 4.723e-03 | 4.572e-03 | x0.97 | higher | flat |
| 4k-nothp vm | Branch_Mispredicts | +0.53 | branch mispredict ratio | 0.02212 | 0.02142 | x0.97 | higher | flat |
| 4k-nothp vm | Branch_Mispredicts | +0.53 | mispredicted branches per instr | 4.723e-03 | 4.572e-03 | x0.97 | higher | flat |
| 4k-nothp vm | Backend_Bound | +8.81 | memory stall cycles per cycle | 0.8019 | 0.7962 | x0.99 | higher | flat |
| 4k-nothp vm | Backend_Bound | +8.81 | L3-miss stall cycles per cycle | 0.6884 | 0.632 | x0.92 | higher | flat |
| 4k-nothp vm | Backend_Bound | +8.81 | cycles with an active DTLB load walk | 0.142 | 0.2772 | x1.95 | higher | supports |
| 4k-nothp vm | Memory_Bound | +8.28 | memory stall cycles per cycle | 0.8019 | 0.7962 | x0.99 | higher | flat |
| 4k-nothp vm | Memory_Bound | +8.28 | L3-miss stall cycles per cycle | 0.6884 | 0.632 | x0.92 | higher | flat |
| 4k-nothp vm | Memory_Bound | +8.28 | cycles with an active DTLB load walk | 0.142 | 0.2772 | x1.95 | higher | supports |
| 4k-nothp vm | L1_Bound | +1.39 | DTLB (2nd level) load MPI | 6.327e-03 | 5.617e-03 | x0.89 | higher | neutral |
| 4k-nothp vm | L1_Bound | +1.39 | DTLB load walks per instr | 6.332e-03 | 5.617e-03 | x0.89 | higher | neutral |
| 4k-nothp vm | L1_Bound | +1.39 | cycles per DTLB load walk | 65.95 | 156.3 | x2.37 | higher | supports |
| 4k-nothp vm | L1_Bound | +1.39 | cycles with an active DTLB load walk | 0.142 | 0.2772 | x1.95 | higher | supports |
| 4k-nothp vm | L1_Bound | +1.39 | DTLB load miss latency (core clks) | 65.95 | 156.3 | x2.37 | higher | supports |
| 4k-nothp vm | L1_Bound | +1.39 | LLC page walk MPI | 2.189e-04 | 6.193e-04 | x2.83 | higher | supports |
| 4k-nothp vm | DTLB_Load | +15.81 | DTLB (2nd level) load MPI | 6.327e-03 | 5.617e-03 | x0.89 | higher | neutral |
| 4k-nothp vm | DTLB_Load | +15.81 | DTLB load walks per instr | 6.332e-03 | 5.617e-03 | x0.89 | higher | neutral |
| 4k-nothp vm | DTLB_Load | +15.81 | cycles per DTLB load walk | 65.95 | 156.3 | x2.37 | higher | supports |
| 4k-nothp vm | DTLB_Load | +15.81 | cycles with an active DTLB load walk | 0.142 | 0.2772 | x1.95 | higher | supports |
| 4k-nothp vm | DTLB_Load | +15.81 | DTLB load miss latency (core clks) | 65.95 | 156.3 | x2.37 | higher | supports |
| 4k-nothp vm | DTLB_Load | +15.81 | LLC page walk MPI | 2.189e-04 | 6.193e-04 | x2.83 | higher | supports |
| 4k-nothp vm | L3_Bound | +4.94 | L2 MPI | 0.01894 | 0.02219 | x1.17 | higher | supports |
| 4k-nothp vm | L3_Bound | +4.94 | L2 demand data read MPI | 8.260e-03 | 7.950e-03 | x0.96 | higher | flat |
| 4k-nothp vm | L3_Bound | +4.94 | L3-hit loads per instr | 1.493e-03 | 1.633e-03 | x1.09 | higher | flat |
| 4k-nothp vm | DRAM_Bound | +5.49 | LLC MPI | 0.01345 | 0.0131 | x0.97 | higher | flat |
| 4k-nothp vm | DRAM_Bound | +5.49 | L3-miss loads per instr | 6.770e-03 | 6.305e-03 | x0.93 | higher | flat |
| 4k-nothp vm | DRAM_Bound | +5.49 | LLC demand read miss latency (ns) | 157.7 | 151.3 | x0.96 | higher | flat |
| 4k-nothp vm | DRAM_Bound | +5.49 | L3-miss stall cycles per cycle | 0.6884 | 0.632 | x0.92 | higher | flat |
| 4k-nothp vm | MEM_Bandwidth | +0.99 | memory bandwidth total (MB/s, window-dependent) | 3.234e+05 | 2.771e+05 | x0.86 | info | info |
| 4k-nothp vm | MEM_Bandwidth | +0.99 | TOR DRD miss avg entries | 4.203 | 3.355 | x0.80 | info | info |
| 4k-nothp vm | MEM_Latency | +15.10 | LLC MPI | 0.01345 | 0.0131 | x0.97 | higher | flat |
| 4k-nothp vm | MEM_Latency | +15.10 | L3-miss loads per instr | 6.770e-03 | 6.305e-03 | x0.93 | higher | flat |
| 4k-nothp vm | MEM_Latency | +15.10 | LLC demand read miss latency (ns) | 157.7 | 151.3 | x0.96 | higher | flat |
| 4k-nothp vm | MEM_Latency | +15.10 | L3-miss stall cycles per cycle | 0.6884 | 0.632 | x0.92 | higher | flat |
| 4k-nothp vm | Ports_Utilization | +2.16 | cycles with 0 ports used per cycle | 0.02347 | 0.03912 | x1.67 | higher | supports |
| 4k-nothp vm | Ports_Utilization | +2.16 | cycles with 1 port used per cycle | 0.05557 | 0.05201 | x0.94 | higher | flat |
| 4k-nothp vm | Ports_Utilized_0 | +1.60 | cycles with 0 ports used per cycle | 0.02347 | 0.03912 | x1.67 | higher | supports |
| 4k-nothp vm | Ports_Utilized_0 | +1.60 | cycles with 1 port used per cycle | 0.05557 | 0.05201 | x0.94 | higher | flat |
| 4k-nothp vm | Retiring | +0.98 | supervisor share of instructions | 5.363e-03 | 0.01929 | x3.60 | higher | supports |
| 4k-nothp vm | Retiring | +0.98 | far branches per instr | 1.772e-06 | 2.036e-06 | x1.15 | higher | supports |
| 4k-nothp vm | Retiring | +0.98 | uops per instr | 0.9568 | 0.9641 | x1.01 | higher | flat |
| 4k-nothp vm | Retiring | +0.98 | NOPs per instr | 0.01403 | 0.0142 | x1.01 | higher | flat |
| 4k-nothp vm | Light_Operations | +0.83 | supervisor share of instructions | 5.363e-03 | 0.01929 | x3.60 | higher | supports |
| 4k-nothp vm | Light_Operations | +0.83 | far branches per instr | 1.772e-06 | 2.036e-06 | x1.15 | higher | supports |
| 4k-nothp vm | Light_Operations | +0.83 | uops per instr | 0.9568 | 0.9641 | x1.01 | higher | flat |
| 4k-nothp vm | Light_Operations | +0.83 | NOPs per instr | 0.01403 | 0.0142 | x1.01 | higher | flat |
| 2m vm | Frontend_Bound | +4.31 | cycles with 0 uops delivered (per cycle) | 0.04256 | 0.06018 | x1.41 | higher | supports |
| 2m vm | Frontend_Bound | +4.31 | ICACHE_DATA.STALLS per cycle | 2.506e-03 | 0.02364 | x9.43 | higher | supports |
| 2m vm | Frontend_Bound | +4.31 | BACLEARS.ANY per instr | 2.182e-04 | 1.192e-03 | x5.46 | higher | supports |
| 2m vm | Frontend_Bound | +4.31 | ITLB walks per instr | 5.277e-06 | 6.189e-05 | x11.73 | higher | supports |
| 2m vm | Fetch_Latency | +3.91 | cycles with 0 uops delivered (per cycle) | 0.04256 | 0.06018 | x1.41 | higher | supports |
| 2m vm | Fetch_Latency | +3.91 | ICACHE_DATA.STALLS per cycle | 2.506e-03 | 0.02364 | x9.43 | higher | supports |
| 2m vm | Fetch_Latency | +3.91 | BACLEARS.ANY per instr | 2.182e-04 | 1.192e-03 | x5.46 | higher | supports |
| 2m vm | Fetch_Latency | +3.91 | ITLB walks per instr | 5.277e-06 | 6.189e-05 | x11.73 | higher | supports |
| 2m vm | ICache_Misses | +2.13 | L1-I code read misses per instr | 8.080e-05 | 1.922e-03 | x23.79 | higher | supports |
| 2m vm | ICache_Misses | +2.13 | ICACHE_DATA.STALLS per cycle | 2.506e-03 | 0.02364 | x9.43 | higher | supports |
| 2m vm | ICache_Misses | +2.13 | ICACHE_TAG.MISS per instr | 8.270e-05 | 2.153e-03 | x26.04 | higher | supports |
| 2m vm | ICache_Misses | +2.13 | L2 code read misses per instr | 7.626e-05 | 1.180e-03 | x15.47 | higher | supports |
| 2m vm | ICache_Misses | +2.13 | L2 demand code MPI | 7.620e-05 | 1.180e-03 | x15.48 | higher | supports |
| 2m vm | ICache_Misses | +2.13 | LLC code hits per instr | 7.490e-05 | 1.178e-03 | x15.72 | higher | supports |
| 2m vm | ICache_Misses | +2.13 | LLC code read MPI | 8.910e-07 | 1.440e-06 | x1.62 | higher | supports |
| 2m vm | ICache_Misses | +2.13 | retired instrs after an L1I miss, per instr | 2.295e-05 | 4.552e-04 | x19.83 | higher | supports |
| 2m vm | Code_L2_Miss | +0.62 | L1-I code read misses per instr | 8.080e-05 | 1.922e-03 | x23.79 | higher | supports |
| 2m vm | Code_L2_Miss | +0.62 | ICACHE_DATA.STALLS per cycle | 2.506e-03 | 0.02364 | x9.43 | higher | supports |
| 2m vm | Code_L2_Miss | +0.62 | ICACHE_TAG.MISS per instr | 8.270e-05 | 2.153e-03 | x26.04 | higher | supports |
| 2m vm | Code_L2_Miss | +0.62 | L2 code read misses per instr | 7.626e-05 | 1.180e-03 | x15.47 | higher | supports |
| 2m vm | Code_L2_Miss | +0.62 | L2 demand code MPI | 7.620e-05 | 1.180e-03 | x15.48 | higher | supports |
| 2m vm | Code_L2_Miss | +0.62 | LLC code hits per instr | 7.490e-05 | 1.178e-03 | x15.72 | higher | supports |
| 2m vm | Code_L2_Miss | +0.62 | LLC code read MPI | 8.910e-07 | 1.440e-06 | x1.62 | higher | supports |
| 2m vm | Code_L2_Miss | +0.62 | retired instrs after an L1I miss, per instr | 2.295e-05 | 4.552e-04 | x19.83 | higher | supports |
| 2m vm | ITLB_Misses | +0.85 | ITLB (2nd level) MPI | 5.270e-06 | 6.190e-05 | x11.75 | higher | supports |
| 2m vm | ITLB_Misses | +0.85 | ITLB walks per instr | 5.277e-06 | 6.189e-05 | x11.73 | higher | supports |
| 2m vm | ITLB_Misses | +0.85 | ITLB STLB hits per instr | 9.449e-06 | 1.224e-05 | x1.30 | higher | supports |
| 2m vm | ITLB_Misses | +0.85 | cycles per ITLB walk | 190.5 | 60.6 | x0.32 | higher | neutral |
| 2m vm | ITLB_Misses | +0.85 | ITLB miss latency (core clks) | 190.5 | 60.6 | x0.32 | higher | neutral |
| 2m vm | ITLB_Misses | +0.85 | retired instrs after an ITLB miss, per instr | 1.105e-06 | 6.764e-06 | x6.12 | higher | supports |
| 2m vm | ITLB_Misses | +0.85 | retired instrs after an STLB miss (code), per instr | 9.041e-07 | 2.370e-06 | x2.62 | higher | supports |
| 2m vm | Branch_Resteers | +2.04 | BACLEARS.ANY per instr | 2.182e-04 | 1.192e-03 | x5.46 | higher | supports |
| 2m vm | Branch_Resteers | +2.04 | unknown-branch cycles per cycle | 4.233e-03 | 0.0201 | x4.75 | higher | supports |
| 2m vm | Unknown_Branches | +1.61 | BACLEARS.ANY per instr | 2.182e-04 | 1.192e-03 | x5.46 | higher | supports |
| 2m vm | Unknown_Branches | +1.61 | unknown-branch cycles per cycle | 4.233e-03 | 0.0201 | x4.75 | higher | supports |
| 2m vm | Bad_Speculation | +0.41 | branch mispredict ratio | 0.02212 | 0.02121 | x0.96 | higher | flat |
| 2m vm | Bad_Speculation | +0.41 | mispredicted branches per instr | 4.723e-03 | 4.586e-03 | x0.97 | higher | flat |
| 2m vm | Branch_Mispredicts | +0.41 | branch mispredict ratio | 0.02212 | 0.02121 | x0.96 | higher | flat |
| 2m vm | Branch_Mispredicts | +0.41 | mispredicted branches per instr | 4.723e-03 | 4.586e-03 | x0.97 | higher | flat |
| 2m vm | Backend_Bound | -0.39 | memory stall cycles per cycle | 0.8019 | 0.7796 | x0.97 | higher | flat |
| 2m vm | Backend_Bound | -0.39 | L3-miss stall cycles per cycle | 0.6884 | 0.6444 | x0.94 | higher | flat |
| 2m vm | Backend_Bound | -0.39 | cycles with an active DTLB load walk | 0.142 | 0.1761 | x1.24 | higher | contradicts |
| 2m vm | Memory_Bound | -0.66 | memory stall cycles per cycle | 0.8019 | 0.7796 | x0.97 | higher | flat |
| 2m vm | Memory_Bound | -0.66 | L3-miss stall cycles per cycle | 0.6884 | 0.6444 | x0.94 | higher | flat |
| 2m vm | Memory_Bound | -0.66 | cycles with an active DTLB load walk | 0.142 | 0.1761 | x1.24 | higher | contradicts |
| 2m vm | L1_Bound | +1.05 | DTLB (2nd level) load MPI | 6.327e-03 | 5.622e-03 | x0.89 | higher | neutral |
| 2m vm | L1_Bound | +1.05 | DTLB load walks per instr | 6.332e-03 | 5.622e-03 | x0.89 | higher | neutral |
| 2m vm | L1_Bound | +1.05 | cycles per DTLB load walk | 65.95 | 88.41 | x1.34 | higher | supports |
| 2m vm | L1_Bound | +1.05 | cycles with an active DTLB load walk | 0.142 | 0.1761 | x1.24 | higher | supports |
| 2m vm | L1_Bound | +1.05 | DTLB load miss latency (core clks) | 65.95 | 88.41 | x1.34 | higher | supports |
| 2m vm | L1_Bound | +1.05 | LLC page walk MPI | 2.189e-04 | 2.259e-04 | x1.03 | higher | flat |
| 2m vm | DTLB_Load | +4.20 | DTLB (2nd level) load MPI | 6.327e-03 | 5.622e-03 | x0.89 | higher | neutral |
| 2m vm | DTLB_Load | +4.20 | DTLB load walks per instr | 6.332e-03 | 5.622e-03 | x0.89 | higher | neutral |
| 2m vm | DTLB_Load | +4.20 | cycles per DTLB load walk | 65.95 | 88.41 | x1.34 | higher | supports |
| 2m vm | DTLB_Load | +4.20 | cycles with an active DTLB load walk | 0.142 | 0.1761 | x1.24 | higher | supports |
| 2m vm | DTLB_Load | +4.20 | DTLB load miss latency (core clks) | 65.95 | 88.41 | x1.34 | higher | supports |
| 2m vm | DTLB_Load | +4.20 | LLC page walk MPI | 2.189e-04 | 2.259e-04 | x1.03 | higher | flat |
| 2m vm | L3_Bound | +1.46 | L2 MPI | 0.01894 | 0.01885 | x1.00 | higher | flat |
| 2m vm | L3_Bound | +1.46 | L2 demand data read MPI | 8.260e-03 | 7.619e-03 | x0.92 | higher | flat |
| 2m vm | L3_Bound | +1.46 | L3-hit loads per instr | 1.493e-03 | 1.516e-03 | x1.02 | higher | flat |
| 2m vm | MEM_Latency | +5.30 | LLC MPI | 0.01345 | 0.01227 | x0.91 | higher | flat |
| 2m vm | MEM_Latency | +5.30 | L3-miss loads per instr | 6.770e-03 | 6.105e-03 | x0.90 | higher | flat |
| 2m vm | MEM_Latency | +5.30 | LLC demand read miss latency (ns) | 157.7 | 155.6 | x0.99 | higher | flat |
| 2m vm | MEM_Latency | +5.30 | L3-miss stall cycles per cycle | 0.6884 | 0.6444 | x0.94 | higher | flat |
| 2m vm | Store_STLB_Miss | +1.04 | DTLB (2nd level) store MPI | 8.542e-04 | 7.298e-04 | x0.85 | higher | neutral |
| 2m vm | Store_STLB_Miss | +1.04 | cycles per DTLB store walk | 69.87 | 95.01 | x1.36 | higher | supports |
| 2m vm | Store_STLB_Miss | +1.04 | cycles with an active DTLB store walk | 0.02032 | 0.02457 | x1.21 | higher | supports |
| 2m vm | Store_STLB_Miss | +1.04 | DTLB store miss latency (core clks) | 69.87 | 95.01 | x1.36 | higher | supports |
| 2m vm | Ports_Utilization | +1.84 | cycles with 0 ports used per cycle | 0.02347 | 0.03705 | x1.58 | higher | supports |
| 2m vm | Ports_Utilization | +1.84 | cycles with 1 port used per cycle | 0.05557 | 0.05767 | x1.04 | higher | flat |
| 2m vm | Ports_Utilized_0 | +1.23 | cycles with 0 ports used per cycle | 0.02347 | 0.03705 | x1.58 | higher | supports |
| 2m vm | Ports_Utilized_0 | +1.23 | cycles with 1 port used per cycle | 0.05557 | 0.05767 | x1.04 | higher | flat |
| 2m vm | Retiring | +1.02 | supervisor share of instructions | 5.363e-03 | 0.01922 | x3.58 | higher | supports |
| 2m vm | Retiring | +1.02 | far branches per instr | 1.772e-06 | 2.060e-06 | x1.16 | higher | supports |
| 2m vm | Retiring | +1.02 | uops per instr | 0.9568 | 0.9634 | x1.01 | higher | flat |
| 2m vm | Retiring | +1.02 | NOPs per instr | 0.01403 | 0.01414 | x1.01 | higher | flat |
| 2m vm | Light_Operations | +0.96 | supervisor share of instructions | 5.363e-03 | 0.01922 | x3.58 | higher | supports |
| 2m vm | Light_Operations | +0.96 | far branches per instr | 1.772e-06 | 2.060e-06 | x1.16 | higher | supports |
| 2m vm | Light_Operations | +0.96 | uops per instr | 0.9568 | 0.9634 | x1.01 | higher | flat |
| 2m vm | Light_Operations | +0.96 | NOPs per instr | 0.01403 | 0.01414 | x1.01 | higher | flat |
| 2m ept 2m text | Frontend_Bound | +5.39 | cycles with 0 uops delivered (per cycle) | 0.04256 | 0.06506 | x1.53 | higher | supports |
| 2m ept 2m text | Frontend_Bound | +5.39 | ICACHE_DATA.STALLS per cycle | 2.506e-03 | 0.02681 | x10.70 | higher | supports |
| 2m ept 2m text | Frontend_Bound | +5.39 | BACLEARS.ANY per instr | 2.182e-04 | 1.207e-03 | x5.53 | higher | supports |
| 2m ept 2m text | Frontend_Bound | +5.39 | ITLB walks per instr | 5.277e-06 | 6.093e-05 | x11.55 | higher | supports |
| 2m ept 2m text | Fetch_Latency | +4.80 | cycles with 0 uops delivered (per cycle) | 0.04256 | 0.06506 | x1.53 | higher | supports |
| 2m ept 2m text | Fetch_Latency | +4.80 | ICACHE_DATA.STALLS per cycle | 2.506e-03 | 0.02681 | x10.70 | higher | supports |
| 2m ept 2m text | Fetch_Latency | +4.80 | BACLEARS.ANY per instr | 2.182e-04 | 1.207e-03 | x5.53 | higher | supports |
| 2m ept 2m text | Fetch_Latency | +4.80 | ITLB walks per instr | 5.277e-06 | 6.093e-05 | x11.55 | higher | supports |
| 2m ept 2m text | ICache_Misses | +2.44 | L1-I code read misses per instr | 8.080e-05 | 3.118e-03 | x38.59 | higher | supports |
| 2m ept 2m text | ICache_Misses | +2.44 | ICACHE_DATA.STALLS per cycle | 2.506e-03 | 0.02681 | x10.70 | higher | supports |
| 2m ept 2m text | ICache_Misses | +2.44 | ICACHE_TAG.MISS per instr | 8.270e-05 | 3.437e-03 | x41.56 | higher | supports |
| 2m ept 2m text | ICache_Misses | +2.44 | L2 code read misses per instr | 7.626e-05 | 1.328e-03 | x17.41 | higher | supports |
| 2m ept 2m text | ICache_Misses | +2.44 | L2 demand code MPI | 7.620e-05 | 1.328e-03 | x17.42 | higher | supports |
| 2m ept 2m text | ICache_Misses | +2.44 | LLC code hits per instr | 7.490e-05 | 1.313e-03 | x17.52 | higher | supports |
| 2m ept 2m text | ICache_Misses | +2.44 | LLC code read MPI | 8.910e-07 | 1.470e-05 | x16.50 | higher | supports |
| 2m ept 2m text | ICache_Misses | +2.44 | retired instrs after an L1I miss, per instr | 2.295e-05 | 7.117e-04 | x31.01 | higher | supports |
| 2m ept 2m text | Code_L2_Miss | +0.78 | L1-I code read misses per instr | 8.080e-05 | 3.118e-03 | x38.59 | higher | supports |
| 2m ept 2m text | Code_L2_Miss | +0.78 | ICACHE_DATA.STALLS per cycle | 2.506e-03 | 0.02681 | x10.70 | higher | supports |
| 2m ept 2m text | Code_L2_Miss | +0.78 | ICACHE_TAG.MISS per instr | 8.270e-05 | 3.437e-03 | x41.56 | higher | supports |
| 2m ept 2m text | Code_L2_Miss | +0.78 | L2 code read misses per instr | 7.626e-05 | 1.328e-03 | x17.41 | higher | supports |
| 2m ept 2m text | Code_L2_Miss | +0.78 | L2 demand code MPI | 7.620e-05 | 1.328e-03 | x17.42 | higher | supports |
| 2m ept 2m text | Code_L2_Miss | +0.78 | LLC code hits per instr | 7.490e-05 | 1.313e-03 | x17.52 | higher | supports |
| 2m ept 2m text | Code_L2_Miss | +0.78 | LLC code read MPI | 8.910e-07 | 1.470e-05 | x16.50 | higher | supports |
| 2m ept 2m text | Code_L2_Miss | +0.78 | retired instrs after an L1I miss, per instr | 2.295e-05 | 7.117e-04 | x31.01 | higher | supports |
| 2m ept 2m text | ITLB_Misses | +0.73 | ITLB (2nd level) MPI | 5.270e-06 | 6.090e-05 | x11.56 | higher | supports |
| 2m ept 2m text | ITLB_Misses | +0.73 | ITLB walks per instr | 5.277e-06 | 6.093e-05 | x11.55 | higher | supports |
| 2m ept 2m text | ITLB_Misses | +0.73 | ITLB STLB hits per instr | 9.449e-06 | 9.385e-06 | x0.99 | higher | flat |
| 2m ept 2m text | ITLB_Misses | +0.73 | cycles per ITLB walk | 190.5 | 46.37 | x0.24 | higher | neutral |
| 2m ept 2m text | ITLB_Misses | +0.73 | ITLB miss latency (core clks) | 190.5 | 46.37 | x0.24 | higher | neutral |
| 2m ept 2m text | ITLB_Misses | +0.73 | retired instrs after an ITLB miss, per instr | 1.105e-06 | 9.526e-07 | x0.86 | higher | contradicts |
| 2m ept 2m text | ITLB_Misses | +0.73 | retired instrs after an STLB miss (code), per instr | 9.041e-07 | 3.286e-07 | x0.36 | higher | contradicts |
| 2m ept 2m text | Branch_Resteers | +2.03 | BACLEARS.ANY per instr | 2.182e-04 | 1.207e-03 | x5.53 | higher | supports |
| 2m ept 2m text | Branch_Resteers | +2.03 | unknown-branch cycles per cycle | 4.233e-03 | 0.02017 | x4.76 | higher | supports |
| 2m ept 2m text | Unknown_Branches | +1.61 | BACLEARS.ANY per instr | 2.182e-04 | 1.207e-03 | x5.53 | higher | supports |
| 2m ept 2m text | Unknown_Branches | +1.61 | unknown-branch cycles per cycle | 4.233e-03 | 0.02017 | x4.76 | higher | supports |
| 2m ept 2m text | Bad_Speculation | +0.34 | branch mispredict ratio | 0.02212 | 0.02051 | x0.93 | higher | flat |
| 2m ept 2m text | Bad_Speculation | +0.34 | mispredicted branches per instr | 4.723e-03 | 4.430e-03 | x0.94 | higher | flat |
| 2m ept 2m text | Branch_Mispredicts | +0.33 | branch mispredict ratio | 0.02212 | 0.02051 | x0.93 | higher | flat |
| 2m ept 2m text | Branch_Mispredicts | +0.33 | mispredicted branches per instr | 4.723e-03 | 4.430e-03 | x0.94 | higher | flat |
| 2m ept 2m text | Backend_Bound | -1.88 | memory stall cycles per cycle | 0.8019 | 0.7791 | x0.97 | higher | flat |
| 2m ept 2m text | Backend_Bound | -1.88 | L3-miss stall cycles per cycle | 0.6884 | 0.642 | x0.93 | higher | flat |
| 2m ept 2m text | Backend_Bound | -1.88 | cycles with an active DTLB load walk | 0.142 | 0.1805 | x1.27 | higher | contradicts |
| 2m ept 2m text | Memory_Bound | -1.94 | memory stall cycles per cycle | 0.8019 | 0.7791 | x0.97 | higher | flat |
| 2m ept 2m text | Memory_Bound | -1.94 | L3-miss stall cycles per cycle | 0.6884 | 0.642 | x0.93 | higher | flat |
| 2m ept 2m text | Memory_Bound | -1.94 | cycles with an active DTLB load walk | 0.142 | 0.1805 | x1.27 | higher | contradicts |
| 2m ept 2m text | L1_Bound | +0.59 | DTLB (2nd level) load MPI | 6.327e-03 | 5.438e-03 | x0.86 | higher | neutral |
| 2m ept 2m text | L1_Bound | +0.59 | DTLB load walks per instr | 6.332e-03 | 5.438e-03 | x0.86 | higher | neutral |
| 2m ept 2m text | L1_Bound | +0.59 | cycles per DTLB load walk | 65.95 | 92.67 | x1.41 | higher | supports |
| 2m ept 2m text | L1_Bound | +0.59 | cycles with an active DTLB load walk | 0.142 | 0.1805 | x1.27 | higher | supports |
| 2m ept 2m text | L1_Bound | +0.59 | DTLB load miss latency (core clks) | 65.95 | 92.67 | x1.41 | higher | supports |
| 2m ept 2m text | L1_Bound | +0.59 | LLC page walk MPI | 2.189e-04 | 2.288e-04 | x1.05 | higher | flat |
| 2m ept 2m text | L3_Bound | +1.45 | L2 MPI | 0.01894 | 0.01864 | x0.98 | higher | flat |
| 2m ept 2m text | L3_Bound | +1.45 | L2 demand data read MPI | 8.260e-03 | 7.509e-03 | x0.91 | higher | flat |
| 2m ept 2m text | L3_Bound | +1.45 | L3-hit loads per instr | 1.493e-03 | 1.512e-03 | x1.01 | higher | flat |
| 2m ept 2m text | DRAM_Bound | -1.25 | LLC MPI | 0.01345 | 0.01194 | x0.89 | higher | supports |
| 2m ept 2m text | DRAM_Bound | -1.25 | L3-miss loads per instr | 6.770e-03 | 6.034e-03 | x0.89 | higher | supports |
| 2m ept 2m text | DRAM_Bound | -1.25 | LLC demand read miss latency (ns) | 157.7 | 153.8 | x0.98 | higher | flat |
| 2m ept 2m text | DRAM_Bound | -1.25 | L3-miss stall cycles per cycle | 0.6884 | 0.642 | x0.93 | higher | flat |
| 2m ept 2m text | MEM_Bandwidth | -0.76 | memory bandwidth total (MB/s, window-dependent) | 3.234e+05 | 2.942e+05 | x0.91 | info | info |
| 2m ept 2m text | MEM_Bandwidth | -0.76 | TOR DRD miss avg entries | 4.203 | 3.66 | x0.87 | info | info |
| 2m ept 2m text | MEM_Latency | +5.82 | LLC MPI | 0.01345 | 0.01194 | x0.89 | higher | contradicts |
| 2m ept 2m text | MEM_Latency | +5.82 | L3-miss loads per instr | 6.770e-03 | 6.034e-03 | x0.89 | higher | contradicts |
| 2m ept 2m text | MEM_Latency | +5.82 | LLC demand read miss latency (ns) | 157.7 | 153.8 | x0.98 | higher | flat |
| 2m ept 2m text | MEM_Latency | +5.82 | L3-miss stall cycles per cycle | 0.6884 | 0.642 | x0.93 | higher | flat |
| 2m ept 2m text | Ports_Utilization | +1.92 | cycles with 0 ports used per cycle | 0.02347 | 0.03769 | x1.61 | higher | supports |
| 2m ept 2m text | Ports_Utilization | +1.92 | cycles with 1 port used per cycle | 0.05557 | 0.0578 | x1.04 | higher | flat |
| 2m ept 2m text | Ports_Utilized_0 | +1.30 | cycles with 0 ports used per cycle | 0.02347 | 0.03769 | x1.61 | higher | supports |
| 2m ept 2m text | Ports_Utilized_0 | +1.30 | cycles with 1 port used per cycle | 0.05557 | 0.0578 | x1.04 | higher | flat |
| 2m ept 2m text | Retiring | +1.08 | supervisor share of instructions | 5.363e-03 | 0.01562 | x2.91 | higher | supports |
| 2m ept 2m text | Retiring | +1.08 | far branches per instr | 1.772e-06 | 1.852e-06 | x1.05 | higher | flat |
| 2m ept 2m text | Retiring | +1.08 | uops per instr | 0.9568 | 0.9611 | x1.00 | higher | flat |
| 2m ept 2m text | Retiring | +1.08 | NOPs per instr | 0.01403 | 0.01444 | x1.03 | higher | flat |
| 2m ept 2m text | Light_Operations | +1.03 | supervisor share of instructions | 5.363e-03 | 0.01562 | x2.91 | higher | supports |
| 2m ept 2m text | Light_Operations | +1.03 | far branches per instr | 1.772e-06 | 1.852e-06 | x1.05 | higher | flat |
| 2m ept 2m text | Light_Operations | +1.03 | uops per instr | 0.9568 | 0.9611 | x1.00 | higher | flat |
| 2m ept 2m text | Light_Operations | +1.03 | NOPs per instr | 0.01403 | 0.01444 | x1.03 | higher | flat |

### 7.3 Context metrics

| metric | bm | 4k-nothp vm | 2m vm | 2m ept 2m text | why it matters |
|:---|---:|---:|---:|---:|:---|
| CPI | 2.938 | 3.166 | 2.823 | 2.791 | with the score ratio it implies the instruction inflation (score-model check) |
| kernel CPI | 3.344 | 6.355 | 5.059 | 5.569 | supervisor-mode efficiency |
| CPU utilization % (window) | 100 | 95.16 | 87.88 | 95.87 | below 100% in a saturated run usually means the window includes idle time |
| kernel-mode utilization % | 0.61 | 3.684 | 3.031 | 2.988 | kernel and hypervisor work |
| supervisor share of instructions | 5.363e-03 | 0.01929 | 0.01922 | 0.01562 |  |
| supervisor share of cycles | 6.099e-03 | 0.03871 | 0.03445 | 0.03117 |  |
| far branches per instr | 1.772e-06 | 2.036e-06 | 2.060e-06 | 1.852e-06 | interrupts, system calls, VM transitions |
| PAUSE executions per instr | 2.330e-05 | 2.190e-05 | 2.870e-05 | 1.310e-05 | spin/idle polling |
| instructions per second (window-dependent) | 2.770e+11 | 2.447e+11 | 2.535e+11 | 2.796e+11 | absolute rate; compare with the score ratio only if the windows match |
| core frequency GHz | 3.393 | 3.392 | 3.392 | 3.392 |  |
| EMON window (s) | 232.7 | 1.029e+03 | 991.5 | 913.7 | about 1/r times the BM window when every window spans its whole run |
| one-thread-active cycles per cycle | 4.457e-08 | 5.301e-05 | 5.428e-05 | 5.009e-05 | SMT sibling idle: tail or idle phases inside the window |
| SMT 2T utilization | 1 | 0.9857 | 0.9854 | 0.9865 | below 1 when SMT siblings idle |
| return mispredicts per instr | 2.212e-07 | 2.373e-05 | 2.089e-05 | 2.007e-05 | predictor state lost on transitions |
| branches per instr | 0.2135 | 0.2134 | 0.2162 | 0.216 | workload-intrinsic: equal for the same binary and input |
| loads per instr | 0.3106 | 0.3096 | 0.3138 | 0.3093 | workload-intrinsic |

### 7.4 Automatic observations

- **4k-nothp vm** (score gap 16.16%): Frontend_Bound +5.84, Bad_Speculation +0.53, Backend_Bound +8.81, Retiring +0.98.
  Largest weighted sub-node gaps (share of the score gap): Memory_Bound +8.28, Fetch_Latency +5.41, MEM_Latency +3.63, L3_Bound +3.61, L3_Hit_Latency +3.59, Local_MEM +3.21.
  Largest unweighted sub-node gaps (ranking only; `‡` = overlapping cycle-based node): Load_STLB_Miss +15.82, DTLB_Load ‡ +15.81, Load_STLB_Miss_4K +15.69, MEM_Latency ‡ +15.10, Memory_Bound +8.28, DRAM_Bound ‡ +5.49.
  - Frontend_Bound (corroborated): cycles with 0 uops delivered (per cycle) x1.48 (supports); ICACHE_DATA.STALLS per cycle x9.57 (supports); BACLEARS.ANY per instr x6.12 (supports); ITLB walks per instr x24.03 (supports)
  - Fetch_Latency (corroborated): cycles with 0 uops delivered (per cycle) x1.48 (supports); ICACHE_DATA.STALLS per cycle x9.57 (supports); BACLEARS.ANY per instr x6.12 (supports); ITLB walks per instr x24.03 (supports)
  - ICache_Misses (corroborated): L1-I code read misses per instr x27.80 (supports); ICACHE_DATA.STALLS per cycle x9.57 (supports); ICACHE_TAG.MISS per instr x30.48 (supports); L2 code read misses per instr x18.54 (supports)
  - ITLB_Misses (corroborated): ITLB (2nd level) MPI x24.06 (supports); ITLB walks per instr x24.03 (supports); ITLB STLB hits per instr x2.32 (supports); retired instrs after an ITLB miss, per instr x48.86 (supports)
  - Branch_Resteers (corroborated): BACLEARS.ANY per instr x6.12 (supports); unknown-branch cycles per cycle x5.62 (supports)
  - Unknown_Branches (corroborated): BACLEARS.ANY per instr x6.12 (supports); unknown-branch cycles per cycle x5.62 (supports)
  - Backend_Bound (weakly supported): cycles with an active DTLB load walk x1.95 (supports)
  - Memory_Bound (weakly supported): cycles with an active DTLB load walk x1.95 (supports)
  - L1_Bound (corroborated): cycles per DTLB load walk x2.37 (supports); cycles with an active DTLB load walk x1.95 (supports); DTLB load miss latency (core clks) x2.37 (supports); LLC page walk MPI x2.83 (supports)
  - DTLB_Load (corroborated): cycles per DTLB load walk x2.37 (supports); cycles with an active DTLB load walk x1.95 (supports); DTLB load miss latency (core clks) x2.37 (supports); LLC page walk MPI x2.83 (supports)
  - L3_Bound (weakly supported): L2 MPI x1.17 (supports)
  - Ports_Utilization (weakly supported): cycles with 0 ports used per cycle x1.67 (supports)
  - Ports_Utilized_0 (weakly supported): cycles with 0 ports used per cycle x1.67 (supports)
  - Retiring (corroborated): supervisor share of instructions x3.60 (supports); far branches per instr x1.15 (supports)
  - Light_Operations (corroborated): supervisor share of instructions x3.60 (supports); far branches per instr x1.15 (supports)
- **2m vm** (score gap 5.35%): Frontend_Bound +4.31, Bad_Speculation +0.41, Backend_Bound -0.39, Retiring +1.02.
  Largest weighted sub-node gaps (share of the score gap): Fetch_Latency +3.91, DRAM_Bound -2.48, ICache_Misses +1.88, Local_MEM -1.73, Branch_Resteers +1.64, Unknown_Branches +1.40.
  Largest unweighted sub-node gaps (ranking only; `‡` = overlapping cycle-based node): MEM_Latency ‡ +5.30, DTLB_Load ‡ +4.20, Load_STLB_Miss +4.17, Load_STLB_Miss_4K +4.07, Fetch_Latency +3.91, ICache_Misses +2.13.
  - Frontend_Bound (corroborated): cycles with 0 uops delivered (per cycle) x1.41 (supports); ICACHE_DATA.STALLS per cycle x9.43 (supports); BACLEARS.ANY per instr x5.46 (supports); ITLB walks per instr x11.73 (supports)
  - Fetch_Latency (corroborated): cycles with 0 uops delivered (per cycle) x1.41 (supports); ICACHE_DATA.STALLS per cycle x9.43 (supports); BACLEARS.ANY per instr x5.46 (supports); ITLB walks per instr x11.73 (supports)
  - ICache_Misses (corroborated): L1-I code read misses per instr x23.79 (supports); ICACHE_DATA.STALLS per cycle x9.43 (supports); ICACHE_TAG.MISS per instr x26.04 (supports); L2 code read misses per instr x15.47 (supports)
  - Code_L2_Miss (corroborated): L1-I code read misses per instr x23.79 (supports); ICACHE_DATA.STALLS per cycle x9.43 (supports); ICACHE_TAG.MISS per instr x26.04 (supports); L2 code read misses per instr x15.47 (supports)
  - ITLB_Misses (corroborated): ITLB (2nd level) MPI x11.75 (supports); ITLB walks per instr x11.73 (supports); ITLB STLB hits per instr x1.30 (supports); retired instrs after an ITLB miss, per instr x6.12 (supports)
  - Branch_Resteers (corroborated): BACLEARS.ANY per instr x5.46 (supports); unknown-branch cycles per cycle x4.75 (supports)
  - Unknown_Branches (corroborated): BACLEARS.ANY per instr x5.46 (supports); unknown-branch cycles per cycle x4.75 (supports)
  - Backend_Bound (children diverge): cycles with an active DTLB load walk x1.24 (contradicts)
  - Memory_Bound (children diverge): cycles with an active DTLB load walk x1.24 (contradicts)
  - L1_Bound (corroborated): cycles per DTLB load walk x1.34 (supports); cycles with an active DTLB load walk x1.24 (supports); DTLB load miss latency (core clks) x1.34 (supports)
  - DTLB_Load (corroborated): cycles per DTLB load walk x1.34 (supports); cycles with an active DTLB load walk x1.24 (supports); DTLB load miss latency (core clks) x1.34 (supports)
  - Store_STLB_Miss (corroborated): cycles per DTLB store walk x1.36 (supports); cycles with an active DTLB store walk x1.21 (supports); DTLB store miss latency (core clks) x1.36 (supports)
  - Ports_Utilization (weakly supported): cycles with 0 ports used per cycle x1.58 (supports)
  - Ports_Utilized_0 (weakly supported): cycles with 0 ports used per cycle x1.58 (supports)
  - Retiring (corroborated): supervisor share of instructions x3.58 (supports); far branches per instr x1.16 (supports)
  - Light_Operations (corroborated): supervisor share of instructions x3.58 (supports); far branches per instr x1.16 (supports)
- **2m ept 2m text** (score gap 4.93%): Frontend_Bound +5.39, Bad_Speculation +0.34, Backend_Bound -1.88, Retiring +1.08.
  Largest weighted sub-node gaps (share of the score gap): Fetch_Latency +4.80, DRAM_Bound -3.37, ICache_Misses +2.28, Local_MEM -2.06, Memory_Bound -1.94, Branch_Resteers +1.82.
  Largest unweighted sub-node gaps (ranking only; `‡` = overlapping cycle-based node): MEM_Latency ‡ +5.82, Fetch_Latency +4.80, Load_STLB_Miss +4.55, Load_STLB_Miss_4K +4.46, DTLB_Load ‡ +4.30, ICache_Misses +2.44.
  - Frontend_Bound (corroborated): cycles with 0 uops delivered (per cycle) x1.53 (supports); ICACHE_DATA.STALLS per cycle x10.70 (supports); BACLEARS.ANY per instr x5.53 (supports); ITLB walks per instr x11.55 (supports)
  - Fetch_Latency (corroborated): cycles with 0 uops delivered (per cycle) x1.53 (supports); ICACHE_DATA.STALLS per cycle x10.70 (supports); BACLEARS.ANY per instr x5.53 (supports); ITLB walks per instr x11.55 (supports)
  - ICache_Misses (corroborated): L1-I code read misses per instr x38.59 (supports); ICACHE_DATA.STALLS per cycle x10.70 (supports); ICACHE_TAG.MISS per instr x41.56 (supports); L2 code read misses per instr x17.41 (supports)
  - Code_L2_Miss (corroborated): L1-I code read misses per instr x38.59 (supports); ICACHE_DATA.STALLS per cycle x10.70 (supports); ICACHE_TAG.MISS per instr x41.56 (supports); L2 code read misses per instr x17.41 (supports)
  - ITLB_Misses (mixed): ITLB (2nd level) MPI x11.56 (supports); ITLB walks per instr x11.55 (supports); retired instrs after an ITLB miss, per instr x0.86 (contradicts); retired instrs after an STLB miss (code), per instr x0.36 (contradicts)
  - Branch_Resteers (corroborated): BACLEARS.ANY per instr x5.53 (supports); unknown-branch cycles per cycle x4.76 (supports)
  - Unknown_Branches (corroborated): BACLEARS.ANY per instr x5.53 (supports); unknown-branch cycles per cycle x4.76 (supports)
  - Backend_Bound (children diverge): cycles with an active DTLB load walk x1.27 (contradicts)
  - Memory_Bound (children diverge): cycles with an active DTLB load walk x1.27 (contradicts)
  - L1_Bound (corroborated): cycles per DTLB load walk x1.41 (supports); cycles with an active DTLB load walk x1.27 (supports); DTLB load miss latency (core clks) x1.41 (supports)
  - DRAM_Bound (corroborated): LLC MPI x0.89 (supports); L3-miss loads per instr x0.89 (supports)
  - MEM_Latency (children diverge): LLC MPI x0.89 (contradicts); L3-miss loads per instr x0.89 (contradicts)
  - Ports_Utilization (weakly supported): cycles with 0 ports used per cycle x1.61 (supports)
  - Ports_Utilized_0 (weakly supported): cycles with 0 ports used per cycle x1.61 (supports)
  - Retiring (weakly supported): supervisor share of instructions x2.91 (supports)
  - Light_Operations (weakly supported): supervisor share of instructions x2.91 (supports)

## 8. Hypotheses

Ratios below are VM/BM in the order 4k-nothp vm / 2m vm / 2m ept 2m text unless stated otherwise. "Data" is what the EMON tables show. "Mechanism" is conjecture. "Derived" items are defined in section 9. The breakdown is an accounting identity, not a causal model.

1. **Front-end code-side pollution: VM transitions and kernel/hypervisor code evict the workload's instruction-side state (confidence: high).**
   - Nodes: Frontend_Bound +5.84 / +4.31 / +5.39 (d_i +4.71 / +3.12 / +4.11). Fetch_Latency +5.41 / +3.91 / +4.80. Unweighted gaps: ICache_Misses +2.19 / +2.13 / +2.44, Unknown_Branches +2.02 / +1.61 / +1.61, ITLB_Misses +1.69 / +0.85 / +0.73. These sub-nodes have tiny BM ratios (0.25-0.42%), so their window term is at most 0.04 points (derived D5): they hold in both views.
   - Data (7.2, all `supports`):
     - L1-I code read misses per instr x27.80 / x23.79 / x38.59; ICACHE_TAG.MISS per instr x30.48 / x26.04 / x41.56.
     - L2 code read misses per instr x18.54 / x15.47 / x17.41; LLC code hits per instr x18.86 / x15.72 / x17.52.
     - ICACHE_DATA.STALLS per cycle x9.57 / x9.43 / x10.70.
     - BACLEARS.ANY per instr x6.12 / x5.46 / x5.53; unknown-branch cycles per cycle x5.62 / x4.75 / x4.76.
     - ITLB walks per instr x24.03 / x11.73 / x11.55, while cycles per ITLB walk are x0.67 / x0.32 / x0.24 (`neutral`).
     - Context (7.3): supervisor share of cycles goes from 0.61% to 3.87 / 3.45 / 3.12%, and kernel CPI from 3.34 to 6.36 / 5.06 / 5.57.
     - These ratios are 10x to 40x, far beyond the roughly 10% shift the BM window can cause (hypothesis 6).
   - Mechanism (conjecture): this matches the interpretation pattern "ICache_Misses, ITLB_Misses and Unknown_Branches up 5-30x, similar across guest page sizes". Every VM exit or interrupt runs host (KVM, host kernel) and guest-kernel code. That code evicts the workload's L1I/L2 lines, ITLB entries and BTB entries, and the workload refetches them from L2/LLC afterwards. The many short ITLB walks point to a capacity loss, not to longer walks. Part of the extra misses belongs to the supervisor code itself (hypothesis 2). EMON has no `:USER`/`:SUP` split for these events, so the two parts cannot be separated.
   - Test: run `perf kvm stat record/report` during each VM run (exit rate and reasons). On the host, collect ICACHE_TAG.MISS, FRONTEND_RETIRED.L1I_MISS, BACLEARS.ANY and ITLB_MISSES.WALK_COMPLETED with `:USER`/`:SUP` (and `:G`/`:H` where possible). Then reduce exits and interrupts (tickless guest, posted interrupts/APICv, timer and halt-polling settings). The hypothesis predicts that L1I misses per instr and the Frontend gap shrink with the exit rate. An unchanged Frontend gap at a much lower exit rate would refute it.

2. **Kernel and hypervisor execution accounts for about half of the 2M-EPT gaps (confidence: medium; it overlaps hypothesis 1).**
   - Data (derived D1): extra supervisor cycles, S_VM - r x S_BM, are 3.36 / 2.87 / 2.54 points of the 16.16 / 5.35 / 4.93-point gaps. That leaves 12.80 / 2.48 / 2.40 points for user mode.
   - Extra supervisor instructions are only +1.43 / +1.42 / +1.05% of user instructions, in line with alpha = 1.15% (2m vm). The supervisor code runs at a CPI of 5.1 to 6.4.
   - These supervisor cycles are spread over all TMA nodes (host-side, unfiltered collection), most likely over the Frontend ones.
   - Mechanism (conjecture): exit handling, timer and IPI interrupts, and guest-kernel work (e.g. page faults with 4K pages) run cold code with poor locality.
   - Caveat: the 2m vm window extends about 78 s beyond its run (derived D4). Halt polling in idle periods could add some unhalted supervisor cycles there.
   - Test: `perf kvm stat`, plus `perf record -a -e cycles:k` on the host and in the guest during the steady state. Collect `instructions:H`/`instructions:G` (alpha) for 4k-nothp vm and 2m ept 2m text as well.

3. **Branch-predictor state is lost on transitions (confidence: medium; the measurable cost is small).**
   - Nodes: Unknown_Branches +2.02 / +1.61 / +1.61 (unweighted). Ind_Call_Mispredicts weighted +0.12 in every case. Bad_Speculation (+0.53 / +0.41 / +0.34) does not hold in d_i (-0.21 / -0.37 / -0.50) and is on par with BM.
   - Data:
     - Return mispredicts per instr rise from 2.212e-07 to 2.373e-05 / 2.089e-05 / 2.007e-05 (7.3).
     - Derived D2: user-mode return mispredicts per user instr are x40.96 / x35.96 / x35.45, and user-mode indirect-call mispredicts x2.58 / x2.34 / x2.39.
     - Total mispredicts per instr stay flat (x0.97 / x0.97 / x0.94, 7.2 `flat`). The predictor-state rows are a clear fingerprint, but they are a small share of all mispredicts.
   - Mechanism (conjecture): matches the pattern "Unknown_Branches and BACLEARS up; Ind_Call and Ret mispredicts up". The workload's RSB, indirect predictor and BTB are cleared or overwritten when the CPU enters and leaves the guest or host kernel. Candidate causes are RSB filling on VM exit, IBPB, BHI clearing, or simply host code evicting entries. The user-mode RET increase is the strongest single sign of this.
   - Test: compare `/sys/devices/system/cpu/vulnerabilities/*` and the mitigation boot options of host and guest. As a test only, A/B the mitigations (e.g. `mitigations=off`, `spectre_v2=`, `spectre_bhi=`) together with exit counts. The hypothesis predicts that user-mode RET mispredicts and Unknown_Branches drop.

4. **With 4K EPT, two-dimensional page walks make up the Backend gap of 4k-nothp vm (confidence: high).**
   - Nodes: Backend_Bound +8.81 against BM (d_i +2.71, window term +6.11). In the VM-vs-VM rerun (derived D10), Backend is +9.16 against 2m vm, with a window term of only +0.36, so the 4K-specific Backend cost is robust at about 9 points.
   - DTLB_Load ‡ unweighted +15.81 against BM and +12.09 against 2m vm; its weighted value (+1.00 / +0.46) is only a lower bound. Load_STLB_Miss_4K +15.69; Store_STLB_Miss +3.28.
   - The weighted cost lands in L3_Bound (+3.61 against BM, +2.86 against 2m vm) and in DRAM_Bound / MEM_Latency (+3.06 / +3.63 against BM; +5.25 / +4.85 against 2m vm).
   - Data:
     - Cycles per DTLB load walk 65.95 -> 156.3 (x2.37; x1.77 against 2m vm).
     - Cycles with an active DTLB load walk x1.95 (x1.57 against 2m vm).
     - DTLB load walks per instr x0.89 (`neutral`; x1.00 against 2m vm): walks got longer, not more frequent.
     - LLC page walk MPI x2.83 (x2.74 against 2m vm).
     - L2 MPI x1.17 while L2 demand data read MPI is flat (x0.96).
     - DTLB store miss latency 69.9 -> 152.9 clks (raw metric row).
     - Walk-active cycles per instr 0.418 -> 0.878 (derived D7).
   - Mechanism (conjecture): guest 4K pages on 4K EPT. Every guest page-table level needs its own EPT walk, and the nested tables enlarge the walk footprint, so walker references miss the LLC. The stalls are counted under L3_Bound/DRAM_Bound rather than under the small L1_Bound parent.
   - Test: 2M EPT already recovers 11.43 points (score +12.9%). 1G EPT backing, and guest THP on top of it, should lower cycles per walk toward the BM level. Track `DTLB_LOAD_MISSES.WALK_ACTIVE / WALK_COMPLETED`.

5. **The 2M-EPT VMs keep a residual 2D walk cost because guest data pages are still 4K (confidence: medium). The Backend sign against BM is open.**
   - Nodes: Backend -0.39 / -1.88 score-based, but -6.84 / -8.84 in d_i with window terms of +5.70 / +6.96, so the views disagree only in size and the result is unresolved.
   - DTLB_Load ‡ unweighted +4.20 / +4.30 (d_i +2.76 / +2.74, derived D5; positive in both views).
   - Load_STLB_Miss_4K +4.07 / +4.46, while Load_STLB_Miss_2M is only 0.09 / 0.10.
   - Data:
     - Cycles per DTLB load walk x1.34 / x1.41 and walk-active cycles x1.24 / x1.27. In 7.2 they `support` L1_Bound and DTLB_Load and `contradict` only the negative Backend/Memory_Bound parents, which are marked `children diverge`.
     - LLC page walk MPI is flat (x1.03 / x1.05). The 2nd-level DTLB 4KB-page load MPI is 5.59e-3, against 2.8e-5 for 2MB pages (raw metric rows).
     - Derived D6: if the BM window had the run-average per-instruction cost for Frontend, Bad_Speculation and Retiring, Backend would be +2.25 / +1.35 points. That brackets Backend in [-0.39, +2.25] and [-1.88, +1.35].
     - Part of the negative score-based value may be slot reallocation: more front-end stalls leave fewer slots to the back end.
   - Mechanism (conjecture): matches the pattern "DTLB gap drops from 4K to 2M EPT but stays above BM" and "Load_STLB_Miss_4K dominates". The guest maps the heap with 4K pages, so each walk still needs EPT translations; 2M leaves only make them shorter than with 4K EPT.
   - Test: enable THP in the guest and check AnonHugePages of a copy in the guest `/proc/<pid>/smaps`. Use the same THP policy on BM, which shows 4K walks too. Collect a whole-run BM EMON to settle the sign.

6. **The BM EMON window is a partial, unrepresentative phase. It, not the VM, produces the Retiring and Bad_Speculation gaps and part of every gap against BM (confidence: high).**
   - Nodes: Retiring +0.98 / +1.02 / +1.08 with d_i +0.01 / -0.00 / -0.02 and window terms +0.97 / +0.91 / +1.11. Only the alpha term (+0.12 for 2m vm) is a real cost of hypervisor instructions. Bad_Speculation d_i is -0.21 / -0.37 / -0.50.
   - Data (checks):
     - `cpi_consistency` WARN: implied alpha 10.67 / 9.97 / 10.72% against a measured 1.15% (2m vm). The user-mode CPI ratio deviates like the total one (0.947 / 1.057 / 1.070 against 0.928 / 1.041 / 1.053; read as an implied alpha, +12.9 / +11.7 / +12.5%).
     - `window` WARN: the BM window covers about 28% of its run. `instruction_mix` PASS (-0.33 / +1.27 / -1.39%).
   - Data (workload-intrinsic rates are uniformly lower in every VM case):
     - LLC MPI x0.97 / x0.91 / x0.89; L3-miss loads per instr x0.93 / x0.90 / x0.89.
     - DTLB load walks per instr x0.89 / x0.89 / x0.86; L2 demand data read MPI x0.96 / x0.92 / x0.91.
   - Derived:
     - D1: extra supervisor instructions are only about 1.0-1.4%, so they cannot explain a 10% inflation.
     - D3: the three VM cases independently imply a BM run-average CPI of 2.685 / 2.702 / 2.684 (agreeing within 0.7%), against 2.938 in the BM window.
     - D4: the implied BM elapsed time is about 865 s, against the 232.7 s window.
   - Mechanism: the pattern "CPI WARN with the same implied alpha in every case + window WARN naming the baseline as partial + instruction_mix PASS". The BM window samples a phase whose CPI is about 9% above the run average and which is more memory-bound.
   - Test: re-process the BM EMON over the whole run (or re-collect it) and rerun this skill. The hypothesis predicts that k_meas - k_pred falls to about 0, that the Retiring gap shrinks to the alpha term, and that the 2M-case Backend gaps move up by several points.

7. **2M text (on 2M EPT) trades an ITLB gain on the workload's own code for more instruction-cache misses; the net effect is zero (confidence: low to medium).**
   - Nodes (VM-vs-VM rerun against 2m vm, derived D10): gap -0.44 points, within the score noise. Frontend +1.06 (d_i +0.95): ICache_Misses weighted +0.39 and DSB_Switches +0.36, while ITLB_Misses is -0.07. Backend -1.49: Memory_Bound -1.28, L1_Bound -0.36.
   - Data (VM/VM ratios against 2m vm, from the rerun):
     - L1-I code read misses per instr x1.62; ICACHE_TAG.MISS x1.60.
     - LLC code read MPI x10.21; L2 code read misses x1.13. L2 code read hits per instr 7.43e-4 -> 1.80e-3 (derived D8).
     - Retired instrs after an STLB miss (code), per instr: 2.370e-06 -> 3.286e-07; after an ITLB miss: 6.764e-06 -> 9.526e-07. Yet ITLB walks per instr are unchanged (6.189e-05 vs 6.093e-05). In the main report, ITLB_Misses of this case is `mixed`.
     - The DTLB rows hardly move (cycles per load walk 88.4 -> 92.7).
   - Reading: the workload's own code now sits on large ITLB pages. The remaining ITLB walks come from code outside the workload text, or from fetches that do not retire. The Backend decrease without a change in the memory evidence (LLC MPI x0.97) looks like reallocation of slots to the front end rather than a memory gain.
   - Mechanism (conjecture): if the 2M text is a private copy per process (e.g. remapped into anonymous huge pages), the copies no longer share physical code. SMT siblings then duplicate the L1I/L2 contents and the LLC holds one copy per process. That fits the L1I x1.6 and LLC code-miss x10 increases. It depends on what "(2m test section ratio - 45%)" means.
   - Test: in the guest, check the text VMA of a copy in `/proc/<pid>/smaps` (AnonHugePages vs FilePmdMapped, Private_Clean vs Shared_Clean). Then try a shared, file-backed 2M text.

8. **Shared lines served from another SNC cluster's cache add latency to the VM's extra code and data reads (confidence: low).**
   - Nodes: Remote_Cache unweighted +0.33 / +0.32 / +0.31 (0.17% -> 0.47%).
   - Data (raw metric rows and derived D9):
     - NUMA % all reads to remote cluster cache goes from 0.66% to 6.60 / 5.61 / 5.54%, while remote cluster memory and remote socket stay at about 0.
     - OCR.READS_TO_CORE.SNC_CACHE.HIT_WITH_FWD per instr x13.35 / x9.35 / x9.60. Its magnitude (1.37e-3 / 9.56e-4 / 9.82e-4) is close to that of L2 code read misses per instr (1.41e-3 / 1.18e-3 / 1.33e-3).
   - Mechanism (conjecture): code and kernel/hypervisor data shared by all vCPUs (guest kernel text, host/KVM text, EPT entries) are held by cores in other SNC clusters. The extra L2 misses of hypotheses 1 and 4 are then served cross-cluster, at a higher latency than a local LLC hit. Only the magnitudes match; no event splits these reads into code and data.
   - Test: collect the code-read OCR events (e.g. OCR.DEMAND_CODE_RD.* with SNC response types). Pin vCPUs and guest memory per SNC cluster and expose a matching vNUMA topology. Look for the remote-cluster-cache share and the Frontend gap to drop.

## 9. Derived evidence and open questions

### 9.1 Derived evidence

Everything below was computed from the raw rows of `520 debug test.csv`, the scores and the script's JSON output by a small read-only script. None of it was typed by hand. Values are in the order bm / 4k-nothp vm / 2m vm / 2m ept 2m text. EMON raw events in this summary are per-second averages, so ratios of two events are window-independent.

- **D1 (derived) Supervisor share.**
  - S = CPU_CLK_UNHALTED.THREAD:SUP / CPU_CLK_UNHALTED.THREAD = 0.610 / 3.871 / 3.445 / 3.117%.
  - Extra supervisor cycles in points of score gap, S_VM - r x S_BM, are 3.36 / 2.87 / 2.54 for the three VM cases. The user-mode remainder of the gap is 12.80 / 2.48 / 2.40.
  - Supervisor instructions per user instruction, INST_RETIRED.ANY:SUP / (INST_RETIRED.ANY - INST_RETIRED.ANY:SUP) = 0.539 / 1.967 / 1.960 / 1.587%.
  - Supervisor CPI = 3.34 / 6.36 / 5.06 / 5.57; user-mode CPI = 2.938 / 3.104 / 2.779 / 2.747.
  - The supervisor cycles include guest kernel and host (KVM), because the counting is host-side and unfiltered.
- **D2 (derived) User-mode predictor events**, (EVENT - EVENT:SUP) / (INST_RETIRED.ANY - INST_RETIRED.ANY:SUP):
  - BR_MISP_RETIRED.RET: 2.09e-07 / 8.56e-06 / 7.52e-06 / 7.41e-06 (x40.96 / x35.96 / x35.45).
  - BR_MISP_RETIRED.INDIRECT_CALL: 5.56e-05 / 1.43e-04 / 1.30e-04 / 1.33e-04 (x2.58 / x2.34 / x2.39).
  - BR_MISP_RETIRED.INDIRECT: x1.47 / x1.39 / x2.00.
  - BR_MISP_RETIRED.ALL_BRANCHES: x0.97 / x0.97 / x0.94.
  - The supervisor share of RET mispredicts is 6.0 / 64.6 / 64.7 / 63.7%.
- **D3 (derived) BM run-average CPI implied by each VM case**, r x (1 + alpha) / beta x CPI_VM, with alpha = 1.15% assumed for all VM cases (measured only for 2m vm): 2.685 / 2.702 / 2.684. The BM window CPI is 2.938, about 9% higher.
- **D4 (derived) Elapsed time implied by the SPECrate score**, T = copies x 1312 s / score. This assumes 240 copies (logical CPUs = CPU_CLK_UNHALTED.THREAD per s / freq / util = 240.0) and the 520.omnetpp_r reference time of 1312 s.
  - T = 864.9 / 1031.6 / 913.8 / 909.8 s, against EMON windows of 232.7 / 1029.1 / 991.5 / 913.7 s.
  - Window / T = 0.27 / 1.00 / 1.09 / 1.00. The BM window covers about a quarter of its run, and the 2m vm window runs about 78 s beyond its run.
- **D5 (derived) Two views for sub-nodes.**
  - d_i (unweighted) = Ratio_VM - k_meas x Ratio_BM. Window term = (k_meas - k_pred) x Ratio_BM.
  - Values are shown as "score-based unweighted gap / d_i / window term" for the three VM cases:

  | node | 4k-nothp vm | 2m vm | 2m ept 2m text |
  |:---|:---|:---|:---|
  | ICache_Misses | +2.19 / +2.17 / +0.02 | +2.13 / +2.10 / +0.02 | +2.44 / +2.42 / +0.03 |
  | ITLB_Misses | +1.69 / +1.66 / +0.02 | +0.85 / +0.83 / +0.02 | +0.73 / +0.70 / +0.03 |
  | Unknown_Branches | +2.02 / +1.99 / +0.04 | +1.61 / +1.57 / +0.04 | +1.61 / +1.57 / +0.04 |
  | DTLB_Load ‡ | +15.81 / +14.45 / +1.37 | +4.20 / +2.76 / +1.28 | +4.30 / +2.74 / +1.56 |
  | L3_Bound | +4.94 / +4.16 / +0.77 | +1.46 / +0.64 / +0.72 | +1.45 / +0.57 / +0.88 |
  | DRAM_Bound ‡ | +5.49 / -0.67 / +6.16 | -0.73 / -7.22 / +5.75 | -1.25 / -8.26 / +7.01 |
- **D6 (derived) Backend bracket.** This scenario assumes the BM window's per-instruction cost of Frontend, Bad_Speculation and Retiring equals the BM run average, so the whole window term moves into Backend: Backend = gap - sum over {FE, BS, RET} of (d_i + alpha term).
  - Result: +11.65 / +2.25 / +1.35, against the score-based +8.81 / -0.39 / -1.88.
  - This is a scenario, not a measurement.
- **D7 (derived) DTLB walk cycles.**
  - DTLB_LOAD_MISSES.WALK_ACTIVE / INST_RETIRED.ANY = 0.418 / 0.878 / 0.497 / 0.504 cycles per instruction.
  - DTLB_LOAD_MISSES.WALK_COMPLETED / INST_RETIRED.ANY = 6.33e-03 / 5.62e-03 / 5.62e-03 / 5.44e-03.
  - ITLB_MISSES.WALK_ACTIVE / CPU_CLK_UNHALTED.THREAD = 3.4e-04 / 5.08e-03 / 1.33e-03 / 1.01e-03.
- **D8 (derived) Code side.** L2_RQSTS.CODE_RD_HIT / INST_RETIRED.ANY = 4.0e-06 / 8.51e-04 / 7.43e-04 / 1.80e-03. L2_RQSTS.CODE_RD_MISS / INST_RETIRED.ANY = 7.63e-05 / 1.41e-03 / 1.18e-03 / 1.33e-03.
- **D9 (derived) SNC.**
  - OCR.READS_TO_CORE.SNC_CACHE.HIT_WITH_FWD / INST_RETIRED.ANY = 1.02e-04 / 1.37e-03 / 9.56e-04 / 9.82e-04 (x13.35 / x9.35 / x9.60).
  - Raw metric "NUMA % all reads to remote cluster cache" = 0.66 / 6.60 / 5.61 / 5.54%; "remote cluster memory" is about 0 in every case.
- **D10 (derived, script rerun) VM-vs-VM breakdown against 2m vm.**
  - Both windows are whole runs; `window` and `cpi_consistency` PASS, implied alpha +0.64% / +0.68%. The rerun was written to a scratch file, not to this directory.
  - Command: `tma_breakdown.py report --emon '520 debug test.csv' --scores '520 debug score.csv' --workload 520.omnetpp_r --baseline '2m vm' --compare '4k-nothp vm' --compare '2m ept 2m text' --beta '4k-nothp vm=1' --beta '2m ept 2m text=1' --confirm throughput=yes --confirm host_side_tma=yes --confirm same_phase=yes --confirm cpu_saturated=yes --out <scratch>`.
  - 4k-nothp vm against 2m vm: gap 11.43. Frontend +2.02 (d_i +1.93), Bad_Speculation +0.17, Backend +9.16 (d_i +8.80, window term +0.36), Retiring +0.07. Backend weighted: L3_Bound +2.86, DRAM_Bound +5.25. DTLB_Load ‡ unweighted +12.09; cycles per DTLB load walk x1.77, walks per instr x1.00, LLC page walk MPI x2.74. ITLB_Misses +0.93 (unweighted).
  - 2m ept 2m text against 2m vm: gap -0.44. Frontend +1.06 (d_i +0.95), Bad_Speculation -0.07, Backend -1.49 (d_i -1.93), Retiring +0.06. ICache_Misses weighted +0.39 (unweighted +0.31), ITLB_Misses -0.07 (unweighted -0.13). L1-I code read misses per instr x1.62, LLC code read MPI x10.21.

### 9.2 Open questions

1. **BM EMON window.** The BM summary has 2307 samples (232.7 s) at 100.0% utilization, so it starts and ends inside the run. That conflicts with "EMON was started before the workload and stopped after it ended". Was the BM collection time- or sample-limited, taken from another run, or post-processed over samples #1-#2307 only? Please re-process or re-collect it over the whole BM run, so that the score-based gap and d_i agree.
2. **Score label "2m ept 2m text (2m test section ratio - 45%)".** What does "2m test section ratio - 45%" mean? Is it 45% of the text section on 2M pages? How was 2M text implemented: a shared file-backed THP or hugetlbfs mapping, or a private anonymous remap per process? Hypothesis 7 depends on this.
3. **Case definitions.** Is "4k-nothp vm" 4K EPT with THP off in the guest? Is "2m vm" 2M EPT backing with or without guest THP? What is the THP setting on BM? The data shows 4K data walks in every case, including BM.
4. **Run setup.** Number of copies (240 is assumed in D4), vCPU count and pinning, SNC mode, and the guest vNUMA topology relative to the host SNC clusters.
5. **Alpha and exits.** Alpha (`instructions:H` / `instructions:G`) for 4k-nothp vm and 2m ept 2m text, and the VM-exit rate and reasons (`perf kvm stat`) for each VM case.
6. **Kernels and mitigations.** Host and guest kernel versions, speculative-execution mitigation settings, timer mode (nohz), APICv/posted interrupts, and halt-polling settings.
7. **Score noise.** Is 0.5% the right run-to-run score noise for this setup? How many iterations stand behind each score? The 2m ept 2m text vs 2m vm difference (-0.44 points) depends on it.
8. **Mode splits.** Can you collect `:USER`/`:SUP` (or `:G`/`:H`) splits of ICACHE_TAG.MISS, FRONTEND_RETIRED.L1I_MISS, BACLEARS.ANY and ITLB_MISSES.WALK_COMPLETED? They would separate the workload's own refetches from kernel/hypervisor code (hypotheses 1 and 2).

## 10. Caveats

- The breakdown is an accounting identity over slots, not a causal model: removing a gap does not necessarily recover the same score (TMA categories interact).
- gap_i is sensitive to r with the factor Ratio_i,BM: a 0.50% score noise moves a node by about k x 0.50% x Ratio_BM. Window mismatches add the uncertainty shown in section 5.1.
- Sub-nodes based on cycle counts may overlap; weighted values are a proportional allocation.
- EMON rates (per second) depend on the collection window; per-instruction and per-cycle values do not, but they are still diluted by any non-workload activity inside the window.

## Appendix: method

```
r        = Score_VM / Score_BM                 (or Time_BM / Time_VM)
beta     = (Freq_VM * Util_VM) / (Freq_BM * Util_BM)
gap      = 1 - r = sum_i gap_i + gap_virt
gap_i    = Ratio_i,VM - (r / beta) * Ratio_i,BM
gap_virt = r * (1 / beta - 1)
sub-node = w_i,VM * sub_Ratio_i,j,VM - (r / beta) * w_i,BM * sub_Ratio_i,j,BM,
           w_i,E = Ratio_i,E / sum_j sub_Ratio_i,j,E
```
