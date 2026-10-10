# Step 9I-A — Verification Plan & Coverage Matrix

**Project:** 4×4 INT8 Systolic Array Accelerator with AXI Read DMA and On-Chip SRAM<br>
**Revision:** 1.0 (2026-10-10)<br>
**Simulator:** EDA Playground / Icarus Verilog, `-Wall -g2012`<br>
**Scope:** Evidence-based review of completed Step 9F–9H tests; not a claim of full AXI4 compliance.

## 1. Verification objectives

Verify the end-to-end path: external AXI memory → upstream `axi_dma_rd` → AXI-Stream → staging adapter → banked A/B SRAM → 4×4 INT8 systolic compute → C SRAM. Verify correct error propagation, safe cleanup of a failed DMA transfer, recovery, reset, and representative stalls. Preserve the upstream DMA implementation; verify project-specific integration and adapters separately.

## 2. Verification environment

- DUT: `matrix_dma_compute_top`, integrating original `axi_dma_rd` and project-specific staging, DMA controller, SRAM mapper, job manager and compute datapath.
- Testbench: procedural SystemVerilog, memory model, deterministic pseudo-random backpressure, cycle-by-cycle protocol monitors, golden C-matrix comparison.
- Icarus compatibility: no UVM, `covergroup`, or advanced concurrent SVA required; use `always @(posedge clk)` checks and `$fatal`.
- Reference outputs: testbench integer matrix multiplication. Earlier project stages also used a Python golden model; the Step 9H-C testbench itself uses an in-testbench expected-value calculation.
- Source artifacts: `step9h_b_drain_design.sv`, `step9h_b_fixed_testbench.sv`, `step9h_c_design.sv`, `step9h_c_testbench.sv`.

## 3. Coverage matrix

| ID | Feature / test intent | Evidence | Status | Notes |
|---|---|---|---|---|
| INT-01 | DMA → staging → banked SRAM | Step 9F, reported 4 tests PASS | VERIFIED | 2 jobs, A/B writes observed |
| INT-02 | DMA → SRAM → compute → C SRAM | Step 9G, reported 2 tests PASS | VERIFIED | Two jobs without reset |
| BP-01 | Deterministic AR/R backpressure and busy start | Step 9H-A, 3 tests PASS | VERIFIED | AR stall 15; R idle/stall metric requires interpretation |
| ERR-01 | A-side injected SLVERR prevents compute | Step 9H-B Test 1 PASS | VERIFIED | Error propagated through staging/controller/job/top |
| ERR-02 | B-side injected DECERR prevents compute | Step 9H-B Test 2 PASS | VERIFIED | B descriptor and error status explicitly checked |
| ERR-03 | Next job succeeds after errors without reset | Step 9H-B Test 3 PASS | VERIFIED | Drain fix prevents stale stream beat crossing jobs |
| RST-01 | Reset during DMA, then recover | Step 9H-B Test 4 PASS | VERIFIED | Tested at one selected timing point |
| RST-02 | Reset during compute, then recover | Step 9H-B Test 5 PASS | VERIFIED | Tested at one selected timing point |
| STR-01 | Six jobs under pseudo-random backpressure | Step 9H-C, 6/6 PASS | VERIFIED | Fixed pseudo-random sequence, not exhaustive |
| DAT-01 | C SRAM equals matrix-multiplication golden result | Step 9H-B/C successful-job checks | VERIFIED | Tested 4×4 matrices and selected values |
| PRO-01 | R channel stall stability | Step 9H-C procedural monitor | CHECK PRESENT / NO FAILURE | Coverage of actual `RVALID && !RREADY` stalls not quantified |
| PRO-02 | AXI-Stream stall stability | Step 9H-C procedural monitor | CHECK PRESENT / NO FAILURE | No separate nonzero stall coverage counter shown |
| PRO-03 | DMA descriptor stall stability | Step 9H-C procedural monitor | CHECK PRESENT / NO FAILURE | No separate nonzero stall coverage counter shown |
| CNT-01 | Descriptor/AR/R/stream/TLAST/status counts | Step 9H-C final log | VERIFIED | 12 / 12 / 48 / 48 / 12 / 12 |
| PRO-04 | Full AXI4 protocol corner cases | No exhaustive protocol suite | NOT COVERED | Includes malformed and unusual timing sequences |
| DMA-01 | Multiple outstanding transactions | Not in demonstrated configuration | NOT COVERED | Do not infer support from upstream IP alone |
| DMA-02 | Unaligned and multi-burst transfers, 4KB splits | Not in 16-byte integration tests | NOT COVERED | Separate directed tests required |
| MAT-01 | General matrix dimensions / tiling | Fixed 4×4 implementation | OUT OF SCOPE | Current release fixed-size |
| PERF-01 | Throughput, latency and resource/timing closure | No synthesis or performance report | NOT COVERED | Icarus functional simulation only |

**Status definitions:** VERIFIED = corresponding scenario passed in user-provided logs; CHECK PRESENT / NO FAILURE = monitor exists and simulation passed, but triggering coverage not proven; NOT COVERED = no adequate evidence; OUT OF SCOPE = intentionally unsupported in this version.

## 4. Final observed regression results

### Step 9H-B — Error & reset recovery

- 5/5 directed tests PASS.
- `Errors=2`, `RecoveryJobs=3`.
- `Descriptors=12`, `AXI_AR=12`, `AXI_R=44`, `Stream=44`, `TLAST=11`, `Status=11`.
- Root cause of prior failure: a final AXI-Stream beat from the failed descriptor was accepted in the next job. The staging adapter's DRAIN handling was revised and the regression passed.

### Step 9H-C — Randomized stress

- 6/6 matrix jobs PASS.
- `Jobs=6 Descriptors=12 AR=12 R=48 Stream=48 TLAST=12 Status=12`.
- `AR_stall_cycles=43 R_idle_cycles=188`.
- `R_idle_cycles` measures cycles with active memory transaction but no `RVALID`; it **does not** prove cycles with `RVALID && !RREADY`. Likewise, count equality is a useful integrity check but not complete protocol proof.

## 5. Additional verification recommended before release signoff

1. Add explicit hit counters for `RVALID && !RREADY`, `TVALID && !TREADY`, and `DESC_VALID && !DESC_READY`; require nonzero counts for each intended stall test.
2. Add randomized seeds beyond the current fixed sequence and save each seed with its log.
3. Add directed `RLAST`/`TLAST` boundary and malformed-frame tests, and check no stale data reaches subsequent jobs.
4. Test reset at additional points: descriptor handshake, first/middle/last R beat, stream backpressure, SRAM writeback.
5. Check error status exact values, tags, and pulse counts; ensure no compute or C SRAM writes on failed jobs.
6. Add independent AXI burst-boundary/unaligned tests only if those features are in the released scope.
7. Archive source revision/hash, simulator options, complete passing logs and a known-limitations section.

## 6. Release gate

**Current decision:** Step 9I-A verification inventory completed; Step 9H-B and 9H-C functional regressions passed. **Not yet a full v4.0 release signoff.** Proceed with Step 9I-B architecture/interface documentation, Step 9I-C limitations, then final reproducible regression and release review.
