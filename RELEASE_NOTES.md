# v4.0.0 — local release candidate

Prepared 2026-10-10 from the existing verified Step 9H-C design and testbench. Integrates AXI4 Read DMA, staging, banked operand SRAM, 4×4 INT8 systolic compute and signed 32-bit C SRAM. All 15 separate module bodies exactly match the combined design. The upstream DMA and its copyright/license notice are unchanged. Staging retains DRAIN error recovery.

Historical EDA Playground/Icarus results: Step 9H-B five functional tests including error/reset recovery passed (Errors=2, Recovery Jobs=3). Step 9H-C six stress jobs passed (Descriptors=12, AR=12, AXI R=48, AXI-Stream=48, TLAST=12, DMA Status=12, AR Stall Cycles=43, R Idle Cycles=188).

New local regression: not run; `iverilog` and `vvp` are unavailable. All three Step 9H testbenches are present. The corrected Step 9H-B candidate source uses registered RVALID and R payload, holds them during stalls, includes a procedural stability assertion, and checks B-DECERR descriptor, AR, status and B error coverage. All five error/reset recovery scenarios are present. These are source-inspection findings; historical EDA Playground PASS results remain distinct from local simulation. Testbench contents were not modified during final preparation.

Limitations: fixed 4×4 INT8; read DMA only; no write DMA; C SRAM output; serialized DMA/compute; no DRAIN timeout; limited protocol/reset coverage; no synthesis or STA signoff. No FPGA/ASIC or production-readiness claim. This candidate has not been published, tagged or pushed.

Imported into the independent Matrix Accelerator repository. Verified RTL is preserved verbatim in `rtl/v4/` because legacy systolic modules use incompatible interfaces. Existing v1–v3 sources are retained. The v4 runner selects only v4 sources. This import does not create a tag or GitHub Release.
