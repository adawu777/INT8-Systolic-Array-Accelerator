# Step 9I-C — Known Limitations & Design Review

**Project:** 4×4 INT8 Systolic Array Accelerator with AXI Read DMA and On-Chip SRAM<br>
**Date:** 2026-10-10<br>
**Baseline reviewed:** `step9h_c_design.sv`<br>
**Simulator used for reported regressions:** EDA Playground / Icarus Verilog (`-Wall -g2012`)<br>
**Review type:** RTL inspection + previously reported simulation results; **not** a new simulation or synthesis signoff.

## 1. Review decision

**Decision: suitable to proceed to Step 9I-D regression/release checklist, with documented scope and open risks.**

The reported Step 9H-B run passed five error/reset recovery tests (Errors=2, RecoveryJobs=3). The reported Step 9H-C run passed six randomized matrix jobs (12 descriptors, 12 AR, 48 AXI R beats, 48 stream beats, 12 TLAST, 12 statuses). These are **scenario-specific functional results**, not a proof of complete AXI4 compliance or arbitrary workload support.

## 2. As-implemented design boundaries

| Area | Implemented / exercised | Not implemented or not established |
|---|---|---|
| Workload | Fixed 4×4 INT8 A×B → 4×4 signed 32-bit C | Arbitrary M/N/K, tiling, larger matrices |
| External memory | AXI4 read through upstream `axi_dma_rd` | AXI Write DMA / writeback to external DRAM |
| DMA command | Two 16-byte descriptors per job; A then B; tags A1/B1 | General-purpose descriptor queue, software register interface |
| AXI data path | 32-bit AXI and AXI-Stream; aligned fixed-size operand reads | Unaligned mode (configured disabled); full width/configuration sweep |
| Compute scheduling | Load both operands, then compute, then expose C SRAM | Overlap of current job's DMA with compute; ping-pong buffering |
| Concurrency | Single top-level job in progress | Multiple simultaneous jobs; multi-context isolation |
| Result interface | `c_rd_addr` / `c_rd_data` local SRAM read | Output DMA, interrupts, host programming API |
| Verification | Directed error/reset, randomized backpressure, golden-result checks | Formal verification, full AXI protocol compliance, silicon timing/power |

**Important:** The upstream DMA's generic capabilities should not be confused with the much narrower functionality exercised by this integrated top-level design.

## 3. Confirmed implementation observations

### 3.1 Descriptor sequencing and job control

`matrix_dma_controller` uses states `ST_IDLE`, `ST_START_A`, `ST_DESC_A`, `ST_WAIT_A`, `ST_START_B`, `ST_DESC_B`, `ST_WAIT_B`. Descriptor `VALID` stays asserted in the corresponding `ST_DESC_*` state until `desc_ready`. `desc_len` is hard-coded to 16 bytes, and tags are `8'hA1` and `8'hB1`. This is appropriate for the fixed matrix workload but not a configurable DMA scheduler.

At the top level, the FSM progresses through `IDLE → LOAD → COMPUTE_START → COMPUTE_WAIT → FINISH`; DMA load and compute are serialized rather than overlapped.

### 3.2 Staging and error recovery

`matrix_dma_staging_v2` has `IDLE`, `ACTIVE`, and `DRAIN` states. If DMA status indicates an error before the stream has finished, it enters `DRAIN`; `s_axis_tready` remains asserted in that state, and the adapter waits for a `TVALID && TREADY && TLAST` handshake before raising `operand_error`. This directly addresses the previously observed stale-final-beat contamination between jobs.

**Residual risk:** The DRAIN state has no internal timeout. If a malformed source never produces `TLAST`, the adapter may wait indefinitely. A future robust design should define an abort/timeout policy and test it independently.

### 3.3 Frame validation

In `ACTIVE`, staging checks `TKEEP == 4'hF` and `TLAST` position against `beat_count == 3`. It is tailored to exactly four 32-bit stream beats. Its data arrays contain 16 bytes per matrix.

**Residual risk:** Unexpected extra beats, missing `TLAST`, repeated status, or malformed stream termination beyond tested cases require additional directed verification. The code's fixed-size assumptions must be documented, not generalized.

### 3.4 SRAM banking and compute

The write mapper maps A by row and B by column, feeding the existing 4×4 systolic compute path. `banked_sram` uses registered reads (`always_ff @(posedge clk)`), so latency assumptions in `matrix_sram_reader` and input skew are part of the interface contract.

**Residual risk:** The storage is inferred from RTL; FPGA synthesis may choose registers, distributed RAM, or block RAM depending on tool and target. Icarus functional simulation does not establish FPGA BRAM inference, ASIC SRAM macro mapping, timing closure, or power.

## 4. Risk register and recommended dispositions

| ID | Priority | Observation / risk | Disposition before release |
|---|---|---|---|
| R1 | High | No timeout if error DRAIN never sees `TLAST` | Document limitation; optionally add a dedicated missing-TLAST test before a stronger reliability claim |
| R2 | High | No AXI Write DMA for C output | Explicitly state read-DMA-only scope in README and release notes |
| R3 | Medium | Fixed 4×4, 16-byte operands, 32-bit interface | Document supported configuration; do not advertise arbitrary GEMM |
| R4 | Medium | Only reported stress scenarios, not full AXI protocol coverage | Preserve coverage gaps and report test counts precisely |
| R5 | Medium | No DMA/compute overlap or ping-pong buffering | State performance/throughput limitation; future enhancement |
| R6 | Medium | No synthesis/STA/FPGA hardware evidence | Mark implementation as simulation-verified, not silicon/FPGA-proven |
| R7 | Medium | No external job queue; top-level `start` only accepted in IDLE | Document busy-start semantics and add directed check if needed |
| R8 | Low | Fixed tags A1/B1 reused between sequential jobs | Fine for serialized operation; revisit if adding concurrency |
| R9 | Medium | Reset during transactions tested in selected phases only | Do not claim exhaustive asynchronous reset coverage |
| R10 | Medium | DMA status and stream completion ordering is nontrivial | Keep regression checking status-before-last-beat and stale-beat isolation |

Priority is a review judgment, not a measured failure frequency.

## 5. Suggested targeted verification before final release

1. **Missing-TLAST/abort behavior:** inject a stream that never terminates and record the current limitation; only add timeout RTL if it is an explicit requirement.
2. **Malformed stream:** wrong `TKEEP`, early `TLAST`, missing `TLAST`, unexpected extra beat; check exact error outcome and job isolation.
3. **Reset edges:** reset while ARVALID stalled, while RVALID stalled, during DRAIN, and during C writeback.
4. **Job interface:** issue `start` while `busy`, hold `start` high across cycles, and document accepted-command semantics.
5. **Protocol stability:** separately count and assert `RVALID && !RREADY` and `TVALID && !TREADY` stalls; `R_idle_cycles` is not equivalent to a stalled valid beat.
6. **Regression reproducibility:** retain exact `design.sv`, `testbench.sv`, simulator settings, random seed, and full passing logs with release artifacts.

These are **recommendations / gaps**, not tests claimed to have already passed.

## 6. Release wording and signoff boundaries

**Acceptable wording:** “The fixed 4×4 INT8 accelerator integrating upstream AXI Read DMA, staging, banked SRAM, systolic compute, and C SRAM passed the documented Icarus Verilog functional regressions, including directed DMA error/reset recovery and six randomized backpressure jobs.”

**Avoid wording:** “AXI4 fully compliant,” “all corner cases covered,” “production-ready DMA,” “full DMA read/write accelerator,” or “timing-closed FPGA/ASIC implementation” without separate evidence.

## 7. Step 9I-C outcome

- **Design review documentation:** COMPLETE.
- **New RTL changes:** NONE.
- **New simulation executed in this review:** NONE.
- **Blocking issue for documentation-focused Step 9I-D:** NONE, provided limitations remain explicit.
- **Open technical risks:** listed in Section 4; should be tracked as future work or additional verification before any stronger signoff.

**Next:** Step 9I-D — Final Regression & Release Checklist. Preserve the passing Step 9H-C RTL as the release candidate and avoid changing upstream `axi_dma_rd` merely to improve documentation.
