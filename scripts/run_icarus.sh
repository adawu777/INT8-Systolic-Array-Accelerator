#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mode="${1:-}"
if [[ $# -gt 1 || ( -n "$mode" && "$mode" != --combined ) ]]; then
  echo "Usage: $0 [--combined]" >&2
  exit 2
fi
for tool in iverilog vvp; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Unavailable: $tool; regression not run." >&2
    exit 127
  fi
done
build="$(mktemp -d "${TMPDIR:-/tmp}/matrix-v4.XXXXXX")"
trap 'rm -rf "$build"' EXIT
sources=()
if [[ "$mode" == --combined ]]; then
  sources=("$root/eda_playground/design.sv")
else
  for module in axi_dma_rd banked_sram c_writeback_controller input_skew_4x4 matrix_accelerator_v4_top matrix_compute_top matrix_dma_compute_top matrix_dma_controller matrix_dma_job_manager matrix_dma_staging_v2 matrix_sram_reader matrix_staging_to_sram output_sram systolic_array_4x4 systolic_pe; do
    sources+=("$root/rtl/v4/$module.sv")
  done
fi
iverilog -Wall -g2012 -s tb_step9h_c -o "$build/regression.vvp" "${sources[@]}" "$root/tb/step9h_c_testbench.sv"
cd "$build"
vvp "$build/regression.vvp" | tee "$build/regression.log"
if ! grep -Fq 'ALL STEP 9H-C RANDOMIZED STRESS TESTS PASSED' "$build/regression.log"; then
  echo "Regression did not report the expected PASS marker." >&2
  exit 1
fi
