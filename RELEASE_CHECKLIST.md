# v4.0.0 repository integration checklist

Target: https://github.com/adawu777/4-4-INT8-Matrix-Accelerator.git
Branch: `main`. Independent clone; parent history is the target repository's v3 history.
Source snapshot: `37e73024e443f72f432c7d673abbdb846b018db8` in AXI-Read-DMA; imported as files only.

- [x] Reviewed target main, README, source layout, history and existing v1.0/v2.0/v3.0 tags.
- [x] Imported all 29 release files; RTL lives in `rtl/v4/` to preserve legacy modules with incompatible interfaces.
- [x] Existing RTL, testbenches, vectors and documents preserved. Root README deliberately updated with v4 information and original v3 documentation retained.
- [x] All 15 v4 module definitions unique within the v4 compile set and exactly match the verified Step 9H-C combined baseline.
- [x] Upstream `axi_dma_rd` byte-identical; complete Alex Forencich copyright and MIT permission retained.
- [x] Staging DRAIN recovery fix retained.
- [x] All three Step 9H testbenches retained verbatim; corrected B includes registered R payload/stability checks, B-DECERR coverage and five scenarios.
- [x] Historical EDA Playground Step 9H-B: 5/5 PASS; Errors=2, RecoveryJobs=3.
- [x] Historical EDA Playground Step 9H-C: 6/6 PASS; Descriptors=12, AR=12, R=48, Stream=48, TLAST=12, Status=12; AR stalls=43, R idle cycles=188.
- [x] Icarus runner explicitly selects v4 sources, uses `-Wall -g2012` and top `tb_step9h_c`; script syntax checked.
- [ ] New local regression: not run; `iverilog` and `vvp` unavailable on PATH. No new simulation PASS claimed.
- [x] File completeness, static dependencies, whitespace, staged contents and intended-file scope checked before committing.

Known limitations: fixed 4×4 INT8, read DMA only, no write DMA, C SRAM output, no DMA/compute overlap, no DRAIN timeout, limited protocol/reset coverage, no synthesis or STA signoff. Full historical simulator logs are not bundled. Run local regressions when Icarus is available before stronger signoff.

Commit message: `Add v4.0.0 AXI DMA integration and verification`. Push only to target `origin/main` without force. No tag or GitHub Release in this task; wrong repository remains unchanged.
