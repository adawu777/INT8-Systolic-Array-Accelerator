# Step 9H-B — DMA Error Injection & Reset Recovery Debug Report

**项目：** 4×4 INT8 Systolic Array Accelerator v4.0<br>
**仿真环境：** EDA Playground / Icarus Verilog / `-Wall -g2012`<br>
**验证范围：** `axi_dma_rd` → `matrix_dma_staging_v2` → DMA Controller → Job Manager → SRAM → Compute<br>
**结论：** Step 9H-B 的 5 项测试最终全部 PASS；此结论基于用户提交的 EDA Playground Simulation Log，而非本地仿真。

## 1. 背景与测试目标

在 Step 9H-A Backpressure Regression PASS 后，Step 9H-B 新增错误注入与恢复验证。测试包括：

1. **Test 1 — A DMA SLVERR**：对 A Matrix 的 AXI Read 注入 `SLVERR`，确认禁止 Compute 并逐级上报 Error。
2. **Test 2 — B DMA DECERR**：A Matrix 成功后，对 B Matrix 注入 `DECERR`，确认正确定位 B 错误。
3. **Test 3 — Recovery without Reset**：经历两个失败 Job 后，不 Reset，启动正常 Job 并比对 C Matrix Golden Model。
4. **Test 4 — Reset during DMA**：DMA 传输中 Reset，随后正常完成新 Job。
5. **Test 5 — Reset during Compute**：Compute 期间 Reset，随后正常完成新 Job。

## 2. 第一次失败：Test 2 假 PASS、Test 3 报错

初版日志：

```text
TEST 1: A DMA SLVERR prevents compute
DMA STATUS tag=a1 error=4
TEST 1 PASSED
TEST 2: B DMA DECERR prevents compute
DMA STATUS tag=a1 error=0
TEST 2 PASSED
TEST 3: Recovery job after DMA errors without reset
DMA STATUS tag=a1 error=0
FATAL: Unexpected DMA/staging/job error
```

**观察：** Test 2 没有 B Descriptor，也没有 B `DECERR` Status，却报告 PASS。原来的 `wait_error(2)` 只检查 Error Pulse 数量，不检查错误发生在哪个 Operand。Test 3 的 A DMA Status 为零，但 Staging 报错，提示可能是数据帧或前一 Job 残留状态的问题。

**采取的措施：** 加入 Error Trace，记录 `operand_error`、`dma_error`、`load_error`、`top_error`、Staging State、`beat_count`、`frame_error` 等；强化 Test 2 的 Descriptor / AR / Status Coverage 条件。

## 3. Error Trace：定位到 Staging

```text
Test 1:
t=225000 operand_error=1
t=235000 dma_error=1
t=245000 load_error=1
t=255000 top_error=1

Test 2:
DMA STATUS tag=a1 error=0
t=425000 operand_error=1 beat_count=4 frame_error=1

Test 3:
DMA STATUS tag=a1 error=0
t=625000 operand_error=1 beat_count=4 frame_error=1
```

**分析：** Test 1 的 Error Propagation 正常：Staging → DMA Controller → Job Manager → Top，每一级相隔一个 Clock Cycle。Test 2/3 的首次异常在 `matrix_dma_staging_v2`，`frame_error=1`，不是 AXI DMA Status 的 `RRESP` Error。`beat_count=4` 表示接收数据帧数量/边界异常，需要进一步观察每一次 AXI-Stream Handshake。

## 4. 修复 Testbench：AXI R Channel 的 VALID Stability

原 Memory Model 使用组合逻辑：

```systemverilog
assign rvalid = mem_active && ((cycle_count % 4) != 0);
```

**问题：** 当 `RVALID=1 && RREADY=0` 时，`cycle_count` 继续变化可能使 `RVALID` 下降，违反 AXI 的 Stall Stability 要求。数据源一旦 Assert `RVALID`，必须保持 `RVALID`、`RDATA`、`RRESP`、`RLAST` 直到 Handshake。

改进后的 Testbench 采用 `rvalid_reg`、`rdata_reg`、`rresp_reg`、`rlast_reg`，仅在无待传 Beat 时装载数据；`RVALID && !RREADY` 时寄存器不更新；`RVALID && RREADY` 后才能释放当前 Beat。Fault Injection 调整为只在目标 Burst 最后一个 Beat 设置非零 `RRESP`。另外增加 Stream Handshake Log、Stability Check 和 Test 2 Coverage Check。

**重要说明：** 此修复保证了 Testbench 的 AXI 协议行为，但单独并未消除全部错误。之后的 Log 暴露出真正的跨 Job 残留 Beat。

## 5. 关键证据：上一笔 DMA 的最后一个 Beat 泄漏到下一 Job

更新 Testbench 后得到以下 Log：

```text
TEST 1: A DMA SLVERR prevents compute
STREAM t=195000 data=04030201 keep=f last=0
STREAM t=215000 data=08070605 keep=f last=0
STREAM t=235000 data=0c0b0a09 keep=f last=0
DMA STATUS tag=a1 error=4
ERROR TRACE t=285000 ... top=1 ...
TEST 1 PASSED

TEST 2: B DMA DECERR prevents compute
DMA DESC addr=00003000 len=16 tag=a1
STREAM t=355000 data=100f0e0d keep=f last=1
AXI AR addr=00003000 beats=4
STREAM t=455000 data=2c2b2a29 keep=f last=0
...
ERROR TRACE t=515000 operand=1 ... beat_count=4 frame_error=1
FATAL: TEST 2 coverage failure: B DECERR not reached
```

`data=100f0e0d` 对应 Test 1 的 A Matrix（地址 `0x100C`–`0x100F`）最后四个字节，**却在 Test 2 开始后才完成 AXI-Stream Handshake**。随后 Test 2 真正的 A Matrix（地址 `0x3000` 起）才开始输出。于是 Staging 将上一笔的 `TLAST` 错误地视为当前帧的一部分，触发 `frame_error`，导致 B Descriptor 根本没有被发出。

**根因：** Upstream `axi_dma_rd` 可以在最后一个 AXI-Stream Beat 被下游消费之前先产生 Error Status。旧版 Staging 一收到 Error Status 就报告 `operand_error` 并返回 `IDLE`，没有等待/丢弃尚未完成的 AXI-Stream 帧。下一个 Job 因此接收到上一笔的残留 Beat。这是 **Error Completion 与 Stream Completion 的时序解耦**问题，不是单纯的 R Channel Backpressure 问题。

## 6. RTL 修复：Staging 增加 DRAIN 状态

修改文件：`matrix_dma_staging_v2`（完整集成文件 `step9h_b_drain_design.sv`）；**保留原始 upstream `axi_dma_rd`，不修改其内部实现。**

状态由原来的 `IDLE / ACTIVE` 扩展为：

```systemverilog
localparam [1:0] IDLE = 2'd0,
                 ACTIVE = 2'd1,
                 DRAIN = 2'd2;
reg [1:0] state;
```

`TREADY` 在 DRAIN 期间保持为 1，以便消费并丢弃 DMA 残余数据：

```systemverilog
assign s_axis_tready =
    ((state == ACTIVE) && !stream_complete &&
     (beat_count < 4) && !status_failed) ||
    (state == DRAIN);
```

收到 Bad Status 时，如果 Stream 尚未完成，则进入 `DRAIN`，**暂不**报告 `operand_error`；当最后一个 Beat 完成 `TVALID && TREADY && TLAST` Handshake 后，才报告 Error 并返回 `IDLE`：

```systemverilog
if (status_bad) begin
    pair_valid <= 0;
    // Invalidate the selected matrix.
    if (stream_complete || (stream_fire && s_axis_tlast)) begin
        operand_error <= 1;
        state <= IDLE;
    end else begin
        state <= DRAIN;
    end
end

DRAIN: begin
    if (stream_fire && s_axis_tlast) begin
        operand_error <= 1;
        state <= IDLE;
    end
end
```

注意：上面是核心逻辑摘录，非完整可独立编译的 Module。实际 RTL 还保留了 A/B Valid 清理、Tag 校验和其他 Frame Validation 逻辑。

**时序效果：** `Bad DMA Status` → `DRAIN` → 接收并丢弃剩余 Beat → `TLAST Handshake` → `operand_error` → 上层 Error Propagation → 下一 Job。`DRAIN` 中不写入 Operand Memory，也不触发 Compute。

## 7. 最终 Regression 结果

采用 DRAIN 修复后的 Design 与修正后的 Testbench，用户提交了最终 Log：

```text
TEST 5 PASSED
ALL STEP 9H-B ERROR/RESET RECOVERY TESTS PASSED
Errors=2 RecoveryJobs=3
Descriptors=12 AXI_AR=12 AXI_R=44 Stream=44 TLAST=11 Status=11
testbench.sv:296: $finish called at 5596000 (1ps)
Done
```

| 测试 | 最终结论 |
|---|---|
| Test 1：A DMA SLVERR | PASS（由最终汇总和前序日志支持） |
| Test 2：B DMA DECERR | PASS（由最终汇总支持；未在所摘录的最终日志中逐行展开） |
| Test 3：Recovery without Reset | PASS（由最终汇总支持） |
| Test 4：Reset during DMA | PASS（由最终汇总支持） |
| Test 5：Reset during Compute | PASS（最终日志明确显示） |

**统计说明：** `AXI_R=44` 与 `Stream=44` 在本次 Regression 中一致；`TLAST=11`、`Status=11` 反映实际观测的传输次数。不要把这些总数直接等同于完整 AXI Protocol Signoff：仍需更广泛的随机化、Corner Cases 与 Assertions。

## 8. 经验总结与可复用 Verification Checklist

- **Error Status 不一定意味着 Stream 已经完全 Drain。** Control-plane Status 和 Data-plane Stream 可能先后到达。
- **Job 完成/失败边界必须清晰。** 报告 Error 前，应确保旧 Job 不会污染新 Job；对于支持 Abort 的 DMA，还需明确取消与 Flush 的语义。
- **VALID/READY 的 Hold Rule 适用于 Testbench。** Verification Environment 本身违反协议，会造成误判并干扰 Root Cause Analysis。
- **PASS 不能只依赖 Error Pulse。** 必须检查期望 Descriptor、Address、Tag、Error Code 和最终禁止 Compute 的条件。
- **观察每个 Handshake 比只看 Status 更有效。** `TDATA/TLAST` 日志揭示了跨 Job 残留 Beat 的精确来源。
- **修复应放在正确的 Ownership Boundary。** 本次问题属于自定义 Staging 的 Job 隔离逻辑，修复在 Adapter，而非替换 upstream DMA IP。
- **Reset Recovery 和 No-reset Recovery 都要测。** 后者更容易发现状态/数据残留。

## 9. 当前结论与下一步

**Step 9H-B：5/5 Functional Tests PASS（EDA Playground / Icarus Verilog）。** 这是特定测试集的通过结论，不代表整个 Accelerator v4.0 完成 Verification Signoff。

建议继续 **Step 9H-C — AXI Protocol Assertions & Randomized Stress Regression**：固定 Seed 的 Randomized Backpressure、R/Stream Stall Stability、Back-to-back Jobs、Error 后的 Stream Isolation、Descriptor/Status Accounting、Golden Model Matrix Comparison。Icarus 兼容策略：使用 Procedural Assertions 和 `$fatal`，避免依赖高级 UVM/不兼容的 SVA 特性。

---

**相关文件：** `step9h_b_design.sv`（初版）、`step9h_b_debug_testbench.sv`（Error Trace）、`step9h_b_fixed_testbench.sv`（协议正确的 AXI Memory Model + Coverage）、`step9h_b_drain_design.sv`（最终 RTL 修复）。
