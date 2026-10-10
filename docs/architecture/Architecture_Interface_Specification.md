# Step 9I-B — Architecture & Interface Specification

**Project:** 4×4 INT8 Systolic Array Accelerator with AXI Read DMA and On-Chip SRAM<br>
**Document revision:** 1.0 — 2026-10-10<br>
**RTL baseline:** `step9h_c_design.sv` (Step 9H-B DRAIN fix carried into Step 9H-C)<br>
**Simulation environment:** EDA Playground, Icarus Verilog, `-Wall -g2012`<br>
**Status:** As-implemented architecture documentation; not a full AXI compliance or synthesis signoff.

## 1. System overview

The top-level module is `matrix_dma_compute_top`. Each accepted job provides the external memory base addresses for one 4×4 INT8 matrix A and one 4×4 INT8 matrix B. The integrated AXI Read DMA transfers both operands, one after the other, through a 32-bit AXI-Stream path into staging memory. The data is mapped to banked SRAM, processed by a 4×4 systolic array, and written to a 16-entry C output SRAM.

```text
             a_base_addr / b_base_addr / start
                             |
                    matrix_dma_compute_top
                             |
                   matrix_dma_job_manager
                             |
                   matrix_dma_controller
                             |
        Descriptor (addr, len, tag, valid/ready)
                             v
               upstream axi_dma_rd (unchanged)
                  ^                      |
         AXI4 AR/R memory          AXI-Stream + status
                                         v
                               matrix_dma_staging_v2
                              [A[16], B[16], DRAIN]
                                         |
                                  pair_valid
                                         v
                               matrix_staging_to_sram
                                         |
                             A/B banked write ports
                                         v
                             matrix_accelerator_v4_top
                             |  banked_sram A/B       |
                             |  matrix_sram_reader    |
                             |  input_skew_4x4       |
                             |  matrix_compute_top   |
                             |  systolic_array_4x4   |
                             |  c_writeback_controller|
                             |  output_sram          |
                             +-----------------------+
                                         |
                                c_rd_addr / c_rd_data
```

**Important boundary:** The integrated module implements the **read/input DMA path**. The C result is exposed through a local C SRAM read port; there is no integrated AXI Write DMA for output in this RTL baseline.

## 2. Top-level interface (`matrix_dma_compute_top`)

| Group | Signal(s) | Direction | Width | Purpose |
|---|---|---|---|---|
| Clock/reset | `clk`, `rst_n` | input | 1 each | Rising-edge clock, active-low reset |
| Job command | `start` | input | 1 | Start a job while idle |
| Job command | `a_base_addr`, `b_base_addr` | input | 32 each | External operand base addresses |
| Job status | `busy`, `done`, `error` | output | 1 each | Active job and terminal pulses |
| Result read | `c_rd_addr` | input | 4 | Index 0–15 in output SRAM |
| Result read | `c_rd_data` | output | signed 32 | C element read data |
| Descriptor | `desc_addr`, `desc_len`, `desc_tag`, `desc_valid` | output | 32, 20, 8, 1 | DMA read descriptor request |
| Descriptor | `desc_ready` | input | 1 | DMA accepts descriptor |
| Stream | `tdata`, `tkeep`, `tvalid`, `tlast` | output | 32, 4, 1, 1 | DMA read data stream |
| Stream | `tready` | input | 1 | Staging backpressure into DMA |
| DMA status | `status_tag`, `status_error`, `status_valid` | input | 8, 4, 1 | Completion/error information |
| AXI AR | `araddr`, `arlen`, `arsize`, `arburst`, `arvalid` | output | 32, 8, 3, 2, 1 | AXI read address channel |
| AXI AR | `arready` | input | 1 | Memory address acceptance |
| AXI R | `rdata`, `rresp`, `rvalid`, `rlast` | input | 32, 2, 1, 1 | AXI read data/response |
| AXI R | `rready` | output | 1 | DMA read-data acceptance |

The AR/R, descriptor, stream, and status signals are **exposed at the top level for the testbench memory model and integration wiring**; they are not a general-purpose CPU register interface.

## 3. DMA configuration and descriptor contract

The upstream `axi_dma_rd` is instantiated with:

| Parameter | Configured value |
|---|---|
| `AXI_DATA_WIDTH`, `AXIS_DATA_WIDTH` | 32 bits |
| `AXI_ADDR_WIDTH` | 32 bits |
| `AXI_ID_WIDTH` | 8 bits |
| `AXI_MAX_BURST_LEN` | 256 |
| `LEN_WIDTH` | 20 bits |
| `TAG_WIDTH` | 8 bits |
| `AXIS_KEEP_ENABLE`, `AXIS_LAST_ENABLE` | 1 |
| `ENABLE_SG`, `ENABLE_UNALIGNED` | 0 |

The integration controller issues **two sequential 16-byte descriptors per job**: A uses tag `8'hA1`, B uses tag `8'hB1`. Each 16-byte operand is four 32-bit beats. The demonstrated tests use aligned base addresses and an AXI INCR burst. The upstream DMA's broader parameter capability is **not** evidence that the current matrix adapter supports arbitrary transfer sizes.

Descriptor handshake: `desc_valid && desc_ready` on a rising clock edge. AXI read-address handshake: `arvalid && arready`. AXI read-data handshake: `rvalid && rready`. AXI-Stream handshake: `tvalid && tready`.

## 4. Data layout and banking

### 4.1 External memory and staging

For each 4×4 matrix, 16 signed INT8 elements occupy 16 consecutive bytes in **row-major** order. With 32-bit little-endian stream assembly, one beat contains four consecutive matrix elements:

```text
Beat 0: elements [0..3]     Beat 1: [4..7]
Beat 2: elements [8..11]    Beat 3: [12..15] (TLAST=1)
```

`matrix_dma_staging_v2` stores A and B in separate 16-byte staging arrays, checks full-byte `TKEEP=4'hF`, checks `TLAST` position, and correlates the DMA status tag/error with the selected operand. Only a successful A+B pair can assert `pair_valid`.

### 4.2 SRAM mapping

`matrix_staging_to_sram` writes 16 A elements, then 16 B elements. It uses these bank/address formulas, where `index = 4*i + k` for A and `index = 4*k + j` for B:

- **A:** `a_wr_bank = index[3:2] = i`; `a_wr_addr = index[1:0] = k`. A is banked by row.
- **B:** `b_wr_bank = index[1:0] = j`; `b_wr_addr = index[3:2] = k`. B is banked by column.

Thus, at a fixed reduction index `k`, the datapath can access the A operands for rows 0–3 and B operands for columns 0–3 through distinct banks. Logical external row-major layout is **not** the same thing as physical SRAM banking.

### 4.3 Compute and output

The 4×4 systolic datapath computes:

\[ C[i][j] = \sum_{k=0}^{3} A[i][k] B[k][j] \]

Inputs are signed 8-bit; the integrated accumulator and C SRAM data width are signed 32-bit. `matrix_accelerator_v4_top` sequences compute and writeback, then exposes 16 output elements through `c_rd_addr`/`c_rd_data`. The output port is a **local SRAM read interface**, not an AXI write channel.

## 5. Control hierarchy and FSMs

| Module | States | Function |
|---|---|---|
| `matrix_dma_compute_top` | `IDLE → LOAD → COMPUTE_START → COMPUTE_WAIT → FINISH` | Whole-job sequencing; pulse `done` or `error` |
| `matrix_dma_job_manager` | `IDLE → START_DMA → WAIT_DMA → WAIT_SRAM` | Start DMA and wait for staging-to-SRAM completion |
| `matrix_dma_controller` | `ST_IDLE`, `ST_START_A`, `ST_DESC_A`, `ST_WAIT_A`, `ST_START_B`, `ST_DESC_B`, `ST_WAIT_B` | Sequential A/B descriptors and per-operand completion |
| `matrix_dma_staging_v2` | `IDLE`, `ACTIVE`, `DRAIN` | Validate stream/status, buffer data, safely finish failed descriptors |
| `matrix_staging_to_sram` | `ST_IDLE`, `ST_A`, `ST_B` | Sequentially write A and B SRAM banks |
| `matrix_accelerator_v4_top` | `IDLE`, `COMPUTE`, `WRITEBACK`, `DONE` | Run compute then write C SRAM |

The top-level `start` is consumed in `IDLE`; the current design does not provide a command queue for overlapping matrix jobs. During a job, the controller loads A and B **sequentially**, not simultaneously.

## 6. Error handling, DRAIN and reset

### 6.1 Error propagation

```text
DMA status error / tag mismatch / malformed stream
                     |
          staging.operand_error
                     |
           controller.dma_error
                     |
            manager.load_error
                     |
               top.error
```

`done` denotes successful completion; `error` denotes failed load. An unsuccessful DMA load must not start the compute phase.

### 6.2 Why DRAIN is necessary

During Step 9H-B, the DMA could report a descriptor error **before its final AXI-Stream beat had handshaken**. An earlier staging implementation returned to `IDLE` immediately, leaving the last beat pending. The following job then consumed that stale beat and failed its frame check.

The corrected staging implementation enters `DRAIN` on an error if the stream has not completed. While in `DRAIN`, it asserts `TREADY` and discards the remaining stream until the terminating `TLAST` handshake, **then** signals `operand_error`. This prevents an old descriptor's final beat from entering the next job in the verified test cases. `DRAIN` is an error-cleanup mechanism, not a data writeback operation.

### 6.3 Reset

`rst_n` is active low at the integration boundary. The upstream DMA receives active-high `rst = ~rst_n`. The Step 9H-B directed tests covered reset during an active DMA transfer and during compute, followed by successful jobs; not every possible reset cycle was tested.

## 7. Verification evidence

| Regression | Evidence provided by EDA Playground/Icarus | Result |
|---|---|---|
| Step 9F | DMA-to-SRAM integration | PASS |
| Step 9G | DMA-to-compute and C SRAM | PASS |
| Step 9H-A | Backpressure, three jobs | PASS |
| Step 9H-B | A SLVERR, B DECERR, recovery without reset, reset during DMA, reset during compute | 5/5 PASS |
| Step 9H-C | Randomized-backpressure jobs with C golden comparison | 6/6 PASS |

Step 9H-C counters: `Jobs=6 Descriptors=12 AR=12 R=48 Stream=48 TLAST=12 Status=12`, `AR_stall_cycles=43`, `R_idle_cycles=188`. `R_idle_cycles` is **not** a count of `RVALID && !RREADY` stalls. The regression passing does not prove complete AXI4 protocol coverage.

## 8. Scope, limitations and assumptions

**Implemented/demonstrated:** fixed 4×4 signed INT8 A×B, two sequential aligned 16-byte DMA reads per job, staging and banked SRAM mapping, systolic compute, 32-bit C accumulation/output, selected error/recovery/reset/backpressure cases.

**Not demonstrated or not part of this top-level:** AXI Write DMA of C, general GEMM tiling, variable matrix dimensions, multiple queued jobs, descriptor chaining/scatter-gather, unaligned reads (`ENABLE_UNALIGNED=0`), broad multi-burst/4KB-boundary stress, quantified throughput, FPGA synthesis/timing closure, complete AXI protocol compliance, or independent evidence of multiple outstanding transactions in this configuration.

**Engineering note:** This is an architecture record of the RTL actually tested, not a proposal that silently adds features. For future extensions, maintain a separate specification revision and add directed verification before marking any feature supported.

## 9. Source and documentation traceability

- Integrated source: `step9h_c_design.sv` (contains `matrix_dma_compute_top`, upstream `axi_dma_rd`, staging, controller, SRAM, and compute modules).
- Stress testbench: `step9h_c_testbench.sv`.
- Error/recovery testbench: `step9h_b_fixed_testbench.sv`.
- Coverage inventory: `Step9I-A_Verification_Plan.md`.
- Debug case study: `Step9H-B_DMA_Debug_Report.md`.

**Next:** Step 9I-C — Known Limitations & Design Review, then final reproducible regression and release checklist.
