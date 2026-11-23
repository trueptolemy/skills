# Method: breaking a score gap down into TMA nodes

Source: *Break Down Performance Gap into Topdown Metric* (Zhao Liu, Wangyang Guo,
Chao Peng, Dapeng Mi, Tianyou Li, Litrin Jiang), revised version.

## Why side-by-side TMA does not work

TMA reports every category as a fraction of the slots of *its own* run. When
the VM needs more cycles for the same work, a category whose absolute cost grew
can keep or even lower its percentage. In 520.omnetpp_r, for example, Backend_Bound
went from 68.28% to 66.05% in a 4K-page VM, yet Backend accounts for 8.8 of the
16.2 points of score gap. Counting absolute events (misses × penalty) is no
better: it needs aligned time windows and ignores the overlap of an out-of-order core.

## Score model

For a throughput benchmark (SPEC CPU rate) with the same number of copies:

```
score ∝ 1 / measured_time,   measured_time = cycles / (Freq * Util)

r = Score_VM / Score_BM = measured_time_BM / measured_time_VM
  = (cycles_BM / cycles_VM) * (Freq_VM * Util_VM) / (Freq_BM * Util_BM)
  = (cycles_BM / cycles_VM) * beta
```

Hence `cycles_BM / cycles_VM = r / beta`. With instruction counts written out,
`r = beta / (1 + alpha) * CPI_BM / CPI_VM`, where `alpha = IC_hypervisor / IC_BM`.
alpha is usually measured on the host during the VM run as perf
`instructions:H / instructions:G`. That assumes the guest retires as many
instructions as BM, and guest-kernel inflation is in neither count. alpha
matters only for the consistency check; it cancels out of the breakdown.

## Breakdown identity

Every slot of every cycle is in exactly one level-1 category:
`cycles = sum_i cycles * Ratio_i` with `sum_i Ratio_i = 100%`. Charging each category
with its cycles in the VM minus its cycles in BM, normalized by the VM cycles:

```
1 - r/beta = sum_i (Ratio_i,VM - (r/beta) * Ratio_i,BM)
gap = 1 - r = sum_i gap_i + gap_virt
gap_i    = Ratio_i,VM - (r/beta) * Ratio_i,BM
gap_virt = r * (1/beta - 1)            (0 when beta = 1)
```

`gap_i` is in points of the score gap: the share of the VM run time that
category i costs beyond bare metal. A negative value means that category is
cheaper in the VM, i.e. it contributes a gain.

**Requirement:** the VM-case TMA must cover all VM cycles: guest mode, host
mode (hypervisor) and the transitions between them. Collect EMON on the host
system-wide, without a guest/host filter. Then the hypervisor's cycles are
already inside Ratio_i,VM and are distributed by their own micro-architectural
behavior. If TMA is collected inside the guest, the host cycles (h = host
share of cycles) are missing. In that case use
`gap = h + sum_i ((1-h) * Ratio_i,G - (r/beta) * Ratio_i,BM) + gap_virt`
and state this in the report (the script does not do this variant).

## Sub-nodes

Children of a node need not add up to it: many level-3+ nodes are cycle-based
estimates that overlap. Per environment E, write
`Ratio_i,E = w_i,E * sum_j sub_Ratio_i,j,E`, with weight factors that differ between
VM and BM. Then

```
weighted   gap_i,j = w_i,VM * sub_Ratio_i,j,VM - (r/beta) * w_i,BM * sub_Ratio_i,j,BM
unweighted gap_i,j = sub_Ratio_i,j,VM - (r/beta) * sub_Ratio_i,j,BM
```

- Weighted gaps add up exactly to the parent's gap, so they are shares of the
  score gap. They assume the parent can be split in proportion to the children.
- Unweighted gaps keep each node's own magnitude. They only rank siblings, and
  can exceed the parent. For example, DTLB_Load (cycles with an active page walk)
  can exceed its parent L1_Bound, because walks overlap with other stalls.
- A parent's children are not weighted when there are fewer than two, or when
  one child is 0 in both cases (an unsupported metric, e.g. Code_L2_Hit or
  Code_STLB_Hit in some EMON versions).
- A weighted gap can exceed its unweighted gap. The weights use all children,
  including siblings hidden in the report table because their gaps are tiny.
- Cycle-based nodes larger than their parent (marked `‡`: DRAM_Bound >
  Memory_Bound, DTLB_Load > L1_Bound, MEM_Latency) overlap other stalls. Their
  unweighted gap contains `(1 - k) * Ratio_BM` from the cycle normalization
  alone. A node at 85% of cycles in both cases shows a large gap without any
  change, so rank and read them by the weighted gap and by their evidence.

## Noise band

`gap_i` depends on r with the factor Ratio_i,BM:
`d gap_i ≈ (r/beta) * (dr/r) * Ratio_i,BM`. A 0.5% score noise moves a node with
Ratio_BM = 68% by about 0.34 points. Gaps within the band are marked `~` and
should be read as "on par with bare metal".

## Consistency check

From EMON, `k_meas = CPI_BM / CPI_VM`; the model predicts `k_pred = r * (1+alpha) / beta`.
Without a measured alpha, the script reports the implied
`alpha' = k_meas * beta / r - 1`. Virtualization normally inflates instructions by
a few percent. A much larger alpha', or a mismatch with a measured alpha, means
the EMON window includes activity the score does not count. Typical causes:
- idle periods or halt/idle polling outside the steady state;
- a window that is not aligned with the run;
- a phase of the run that differs from the scored one.

The TMA ratios are diluted by the same activity. The breakdown can still be
indicative, but a clean steady-state window should be recommended.

**Decomposition against the EMON windows (report section 5.1).** With
`c_i = CPI * Ratio_i` (cycles per instruction of node i) in each window and
`k = r/beta`, the score-based gap splits exactly into three terms:

```
gap_i = d_i + k * alpha * Ratio_i,BM + (k_meas - k_pred) * Ratio_i,BM
d_i   = (c_i,VM - c_i,BM) / CPI_VM        compares the windows only, no score
```

- `d_i`: the per-instruction change between the two EMON windows.
- `k * alpha * Ratio_i,BM`: the expected cost of hypervisor instructions.
- `(k_meas - k_pred) * Ratio_i,BM`: the inconsistency between the scores
  and the EMON windows.

When the windows match the scored runs, the last term is about 0. A node
whose slots per instruction did not change shows only the last two terms.
For example, a Retiring gap equal to `Retiring_BM * (k_meas - k)` carries no
VM effect.

When the last term is large, the VM effect of each node is uncertain by about
that term. Read `d_i` and the score-based gap as two views. Trust conclusions
that hold in both, and comparisons between cases whose windows agree. For
example, the gap of one VM configuration against another, when every VM
window spans its whole run.

The `cpi_consistency` check also prints the **user-mode CPI ratio**
`(cycles - cycles:SUP) / (instructions - instructions:SUP)` of BM over VM, next
to the total ratio k_meas. If the user-mode ratio deviates from k_pred like the
total one, the workload's own code runs at a different speed in the windows
(another phase). If only the total ratio deviates, supervisor (kernel or
hypervisor) code explains the difference.

Before blaming extra instructions for a CPI mismatch, check the instruction
mix: branches, loads and stores per instruction. Then check the window check.
If the mix is unchanged (`instruction_mix` PASS) and the busy time shows one
window covering only part of its run (`window` WARN, e.g. a short BM window
against whole VM runs), that window samples a different phase. Its CPI and TMA
ratios differ from the run average, and extra code is not the cause.
