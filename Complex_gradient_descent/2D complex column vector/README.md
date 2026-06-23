# Multi-Channel Complex Gradient Descent Hardware Accelerator (2D)

## 📝 Overview
An advanced, parameterizable, block-sequential hardware accelerator implemented in Verilog to perform 2-element complex-valued **Gradient Descent (GD)** parameter estimation ($[x_1, x_2]$). Designed for high-performance deployment on devices like the AMD Xilinx Zynq UltraScale+ RFSoC ZCU216, this module iteratively solves the overdetermined system $y = A_1 x_1 + A_2 x_2$ by minimizing the Mean Squared Error (MSE) across parallel complex data pipelines controlled by a synchronous Finite State Machine (FSM).

---

## Mathematical Formulation

Given a packed real observation vector $y$, dual multi-channel complex data streams $A_1 = (A_{1,re} + j \cdot A_{1,im})$ and $A_2 = (A_{2,re} + j \cdot A_{2,im})$, and two complex parameter weights $x_1$ and $x_2$, the engine minimizes system error across streaming data sequences in configurable block dimensions.

### 1. Combined Channel Energy Accumulation
The total global channel energy ($\text{power}$) is accumulated across all $N$ samples to establish algorithm stability scaling:

$$\text{power} = \sum_{i=0}^{N-1} \left( A_{1,re}[i]^2 + A_{1,im}[i]^2 + A_{2,re}[i]^2 + A_{2,im}[i]^2 \right)$$

### 2. Dynamic Learning Rate Calibration
The global dynamic step size ($\alpha$) is updated in the `COMPUTE_AX` state by scaling a fixed-point numerator inversely by the channel energy to maintain safe $Q2.14$ execution precision:

$$\alpha = \frac{1 \ll \left(2 \cdot \text{SHIFT\_PRODUCT} + 14\right)}{\text{power}}$$

### 3. Combined Complex Estimate & Error Residuals
For each individual sample element, the parallel complex multipliers generate a combined estimate to extract the real and imaginary coordinate variances:

$$\text{ax\_combined\_re}[i] = (A_{1,re}[i] \cdot x_{1,re} - A_{1,im}[i] \cdot x_{1,im}) + (A_{2,re}[i] \cdot x_{2,re} - A_{2,im}[i] \cdot x_{2,im})$$

$$\text{ax\_combined\_im}[i] = (A_{1,re}[i] \cdot x_{1,im} + A_{1,im}[i] \cdot x_{1,re}) + (A_{2,re}[i] \cdot x_{2,im} + A_{2,im}[i] \cdot x_{2,re})$$

$$r_{re}[i] = y[i] - \text{ax\_combined\_re}[i]$$

$$r_{im}[i] = 0 - \text{ax\_combined\_im}[i]$$

### 4. Dual Accumulated Cross-Product Gradients
The system computes matching trajectories independently for both coordinate channels across $N$ samples via conjugate transposition:

$$\text{total\_grad1\_re} = \sum_{i=0}^{N-1} \left( A_{1,re}[i] \cdot r_{re}[i] + A_{1,im}[i] \cdot r_{im}[i] \right)$$

$$\text{total\_grad1\_im} = \sum_{i=0}^{N-1} \left( A_{1,re}[i] \cdot r_{im}[i] - A_{1,im}[i] \cdot r_{re}[i] \right)$$

$$\text{total\_grad2\_re} = \sum_{i=0}^{N-1} \left( A_{2,re}[i] \cdot r_{re}[i] + A_{2,im}[i] \cdot r_{im}[i] \right)$$

$$\text{total\_grad2\_im} = \sum_{i=0}^{N-1} \left( A_{2,re}[i] \cdot r_{im}[i] - A_{2,im}[i] \cdot r_{re}[i] \right)$$

### 5. Parallel Optimization Step Rules
$$\begin{aligned}
x_{1,re}^{(k+1)} &= x_{1,re}^{(k)} + \left( \alpha \cdot \text{total\_grad1\_re} \right) \\
x_{1,im}^{(k+1)} &= x_{1,im}^{(k)} + \left( \alpha \cdot \text{total\_grad1\_im} \right) \\
x_{2,re}^{(k+1)} &= x_{2,re}^{(k)} + \left( \alpha \cdot \text{total\_grad2\_re} \right) \\
x_{2,im}^{(k+1)} &= x_{2,im}^{(k)} + \left( \alpha \cdot \text{total\_grad2\_im} \right)
\end{aligned}$$

---

## Key Features

* **Multi-Channel Matrix Expansion:** Extends the 1D parameter search space to a 2-element complex weight vector $[x_1, x_2]$ to accurately model cross-coupled communication nodes.
* **Block-Based Memory Scaling:** Hardware processing loop constraints are parameterized via `BLOCK_SIZE` and `sample`, allowing large vectors (e.g., 400 elements) to stream iteratively without saturating logic resources.
* **Dual-Track Symmetric Update:** Computes gradients for both channels simultaneously within individual processing iterations to guarantee uniform operational convergence.

---

## Architecture & FSM States

The multi-channel module orchestrates computing logic using a highly deterministic 8-state hardware controller:

1. **`IDLE` (3'd0):** Polls the `start` flag; wipes previous weight variables and clears accumulation records.
2. **`ACCUMULATE_Y_A` (3'd7):** Pools combined matrix energy metrics ($\|A_1\|^2 + \|A_2\|^2$) alongside vector observations to extract early-exit noise floors (`threshold`).
3. **`COMPUTE_AX` (3'd1):** Calibrates the fixed-point global learning step ($\alpha$) through an isolated division array; defends natively against division-by-zero.
4. **`RESIDUAL` (3'd2):** Evaluates combined tracking deviations by processing multi-channel error profiles against true scalar system observations.
5. **`CHECK_ERROR` (3'd3):** Tracks complete Mean Squared Error (MSE) trends; checks convergence criteria against `threshold`.
6. **`GRADIENT` (3'd4):** Coordinates independent cross-product tracking routines to compute vector trajectory points `Grad1` and `Grad2`.
7. **`UPDATE_X` (3'd5):** Executes weight additions across all components; flags fixed-point convergence if values freeze, or restarts tracking loops.
8. **`DONE` (3'd6):** Packs matching structural parameter results into a single `4*bits` bus (`x_out`) and pulses the single-cycle handshake indicator.

---

## Module Interface (I/O Signal List)

| Signal Name | Direction | Width | Type | Description |
| :--- | :--- | :--- | :--- | :--- |
| `clk` | Input | `1` | wire | High-speed processing system clock |
| `rst` | Input | `1` | wire | Synchronous reset layer (Active High) |
| `start` | Input | `1` | wire | Pulse validation entry point to launch iteration loops |
| `y_vector` | Input | `(sample*bits-1):0` | wire | Packed real-valued input observation vector |
| `A_col1_rel` | Input | `(sample*bits-1):0` | wire | Packed Real data array for the first matrix column ($A_{1,re}$) |
| `A_col1_iml` | Input | `(sample*bits-1):0` | wire | Packed Imaginary data array for the first matrix column ($A_{1,im}$) |
| `A_col2_rel` | Input | `(sample*bits-1):0` | wire | Packed Real data array for the second matrix column ($A_{2,re}$) |
| `A_col2_iml` | Input | `(sample*bits-1):0` | wire | Packed Imaginary data array for the second matrix column ($A_{2,im}$) |
| `x_out` | Output | `(4*bits-1):0` | reg | Consolidated output parameter register array: `| x1_re | x1_im | x2_re | x2_im |` |
| `done` | Output | `1` | reg | High-asserted logic loop handshake complete notification |

---
## Verification & Testbench Results

The correctness and arithmetic precision of the multi-channel 2D Gradient Descent hardware accelerator were rigorously verified using a data-driven cross-verification framework. The hardware's fixed-point calculations were audited against an algorithmic golden reference model executed in MATLAB.

### 1. Verification Methodology & Flow

The hardware design validation was carried out through a multi-step empirical verification pipeline:

1. **Golden Dataset Ingestion:** A golden verification matrix data structure containing real observation targets (`y_vec`) and multi-column complex data frames (`A`) was imported into the MATLAB test environment (`LMS_test (1).mat`).
2. **Fixed-Point Hex Conversion:** Using custom workspace serialization utilities, fractional matrix coefficients were quantified and formatted into standard signed hexadecimal vectors (`16'h%04X`).
3. **Testbench Injection & Simulation:** The converted hex sequences were fed directly into the structural Verilog testbench via packed configuration ports (`y_vector[6399:0]`, `A_col1_rel[6399:0]`, `A_col1_iml[6399:0]`, `A_col2_rel[6399:0]`, `A_col2_iml[6399:0]`) to stimulate the multi-channel module under test.
4. **Hardware vs. Software Correlation:** Final converged hardware values (`final_x1_re`, `final_x1_im`, `final_x2_re`, `final_x2_im`) captured from the simulator waveform traces were directly compared to the high-precision floating-point complex matrix division quotients extracted from the MATLAB command terminal.

---

### 2. Simulation Waveform & Workspace Verification

The multi-channel functional execution was validated by comparing the timing waveforms directly against the active 2D MATLAB workspace results:

* **MATLAB Command Window Verification:** Performing the double-precision complex matrix division using the specific multi-column slice `A(:,8:9)\y_vec` yields an analytical target solution vector of:
  * $x_1 = -0.0632 - 0.0204i$
  * $x_2 = -0.0646 - 0.0268i$
* **Hardware Waveform Convergence:** Upon pulsing `start`, the internal 2D FSM calculates the dynamic learning step (`alp = 0.05828857421875`) and sequentially minimizes all cross-product gradients (`total_grad1` and `total_grad2`) from high initial error trajectories down toward zero.
* **Final Solution Delivery:** When convergence is achieved, the module asserts the single-cycle `done` handshake flag and locks the final packed parameter array `x_out` to represent the steady-state complex values perfectly aligned with the tracking targets.

#### MATLAB Verification Workspace
![MATLAB Reference Result 2D](/Complex_gradient_descent/2D%20complex%20column%20vector/results%20images/2D_mat.jpg)

#### HDL Timing Simulation Waveform
![Vivado Simulation Waveform 2D](/Complex_gradient_descent/2D%20complex%20column%20vector/results%20images/2d_gradent.jpg)

---

### 3. Software vs. Hardware Numerical Cross-Check

The table below contrasts the computed hardware fixed-point metrics directly against the floating-point reference solution vector derived inside the MATLAB Command Window environment:

| Metric Reference Point | MATLAB Floating-Point Matrix Model | Hardware Fixed-Point Result (Q4.12) | Absolute Matching Delta | Status |
| :--- | :--- | :--- | :--- | :--- |
| **Channel 1 Real Parameter ($x_{1,re}$)** | `-0.0632` | `-0.063232421875` | `0.000032` | **PASSED** |
| **Channel 1 Imag Parameter ($x_{1,im}$)** | `-0.0204` | `-0.0205078125` | `0.000107` | **PASSED** |
| **Channel 2 Real Parameter ($x_{2,re}$)** | `-0.0646` | `-0.064697265625` | `0.000097` | **PASSED** |
| **Channel 2 Imag Parameter ($x_{2,im}$)** | `-0.0268` | `-0.02685546875` | `0.000055` | **PASSED** |

> [!NOTE]
> The minute variances (sub-$10^{-4}$) observed between the design environments represent minor mathematical quantization noise introduced by formatting coefficients into a 12-bit fractional layer (`FRAC=12`). Hardware execution paths track the multi-channel floating-point trajectory models accurately.

---

## Architectural Flowchart

The following diagram illustrates the block-processing data loops and conditional exit paths managed by the FSM controller:

```mermaid
graph TD
    IDLE([1. IDLE: 3'd0]) -->|start == 1| ACCUM[2. ACCUMULATE_Y_A: 3'd7]
    IDLE -->|start == 0| IDLE
    
    ACCUM --> COMPUTE[3. COMPUTE_AX: 3'd1]
    COMPUTE --> RESIDUAL[4. RESIDUAL: 3'd2]
    RESIDUAL --> CHECK_ERR[5. CHECK_ERROR: 3'd3]
    
    CHECK_ERR -->|MSE < threshold| DONE[8. DONE: 3'd6]
    CHECK_ERR -->|MSE >= threshold| GRAD[6. GRADIENT: 3'd4]
    
    GRAD --> UPDATE[7. UPDATE_X: 3'd5]
    
    UPDATE -->|x Unchanged / Saturated| DONE
    UPDATE -->|x Updated| COMPUTE
    
    DONE --> IDLE

    style IDLE fill:#2d3748,stroke:#4a5568,stroke-width:2px,color:#fff
    style DONE fill:#1a202c,stroke:#4a5568,stroke-width:2px,color:#fff
    style ACCUM fill:#2b6cb0,stroke:#3182ce,stroke-width:2px,color:#fff
    style COMPUTE fill:#2b6cb0,stroke:#3182ce,stroke-width:2px,color:#fff
    style RESIDUAL fill:#2b6cb0,stroke:#3182ce,stroke-width:2px,color:#fff
    style CHECK_ERR fill:#d69e2e,stroke:#ecc94b,stroke-width:2px,color:#fff
    style GRAD fill:#2b6cb0,stroke:#3182ce,stroke-width:2px,color:#fff
    style UPDATE fill:#e53e3e,stroke:#f56565,stroke-width:2px,color:#fff