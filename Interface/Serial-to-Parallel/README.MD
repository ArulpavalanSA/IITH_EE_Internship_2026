# Parallel-to-Serial DAC Packetizer Module

## 📝 Overview
The `dac_packetizer` module is a high-throughput, synchronous data restructuring interface designed to serialize massive parallel digital signal blocks for Digital-to-Analog Converters (DACs). It splits a wide $2047:0$ (2048-bit) composite data vector containing 128 distinct 16-bit signal samples into a sequence of eight narrower $255:0$ (256-bit) streaming bus windows, distributing transmission bandwidth over consecutive system clock cycles.

---


## Verification & Testbench Results

The functional performance and structural correctness of the `dac_packetizer` module were validated via post-synthesis behavioral timing simulation inside AMD Vivado. 

### 1. Timing Waveform Analysis

* **Input Dataset Initialization:** The 2048-bit wide input bus is stimulated with partitioned, deterministic hex sequences that scale incrementally across the channel fields:
  `samples[2047:0] = { ... ffffffff..., 22222222..., 11111111... , aaaaaaaa..., bbbbbbbb..., cccccccc..., dddddddd..., eeeeeeee... }`
* **Sequential Framing Loop:** As observed in the simulation waveform, with `valid` tied high (`1`), the output register `dac_data_out` tracks the rising edge of `clk` and steps through the sliced segments cycle-by-cycle without any data stalls:
  $$\text{cccccccc...} \rightarrow \text{dddddddd...} \rightarrow \text{eeeeeeee...} \rightarrow \text{ffffffff...} \rightarrow \text{11111111...} \rightarrow \text{22222222...} \rightarrow \text{aaaaaaaa...}$$
* **Termination Boundary:** Once the tracking pointer rolls past `3'd7`, it immediately wraps back to `3'd0` to continue streaming subsequent frames or drops to zero if the master validation line `valid` is de-asserted.

#### HDL Timing Simulation Waveform
![Vivado Packetizer Simulation Waveform](/Interface/Serial-to-Parallel/Result_image/92s.jpg)

---

### 2. Mapping & Serialization Cross-Check

The table below correlates the internal 3-bit counter index with the exact bit range and output hex signature captured during testbench execution:

| Pointer State (`count`) | Sample Target Slice Range | Waveform Hex Segment Output (`dac_data_out`) | Status |
| :--- | :--- | :--- | :--- |
| `3'b000` (`0`) | `samples[255:0]` | `256'hcccccccc...` | **PASSED** |
| `3'b001` (`1`) | `samples[511:256]` | `256'hdddddddd...` | **PASSED** |
| `3'b010` (`2`) | `samples[767:512]` | `256'heeeeeeee...` | **PASSED** |
| `3'b011` (`3`) | `samples[1023:768]` | `256'hffffffff...` | **PASSED** |
| `3'b100` (`4`) | `samples[1279:1024]` | `256'h11111111...` | **PASSED** |
| `3'b101` (`5`) | `samples[1535:1280]` | `256'h22222222...` | **PASSED** |
| `3'b110` (`6`) | `samples[1791:1536]` | `256'haaaaaaaa...` | **PASSED** |
| `3'b111` (`7`) | `samples[2047:1792]` | `256'hbbbbbbbb...` | **PASSED** |

> [!NOTE]
> The simulation confirms zero-latency word switching and strict boundary compliance. The module successfully satisfies its design constraint for cycle-accurate parallel-to-serial distribution.

---

## Architectural Mechanics

The module leverages a highly efficient, single-stage synchronous multiplexing architecture:

```mermaid
graph LR
    S[samples 2047:0] --> MUX{3-Bit Counter MUX}
    COUNT[count 2:0] --> MUX
    MUX -->|count=0| D0[samples 255:0]
    MUX -->|count=1| D1[samples 511:256]
    MUX -->|...| DX[...]
    MUX -->|count=7| D7[samples 2047:1792]
    
    style S fill:#2b6cb0,stroke:#3182ce,stroke-width:2px,color:#fff
    style MUX fill:#d69e2e,stroke:#ecc94b,stroke-width:2px,color:#fff
