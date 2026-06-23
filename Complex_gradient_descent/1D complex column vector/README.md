# Complex Gradient Descent Hardware Accelerator

## 📝 Overview
A parameterizable, block-sequential hardware module implemented in Verilog to perform complex-valued **Gradient Descent (GD)** parameter estimation. It manages optimization updates using a synchronous Finite State Machine (FSM) to calculate parameter vectors matching real observations across multiple multi-cycle accumulation loops.

---

## Mathematical Formulation

Given a packed real observation vector $y$, real and imaginary data channel components $A_{re}$ and $A_{im}$, and a parameter state variable $x = (x_{re} + j \cdot x_{im})$, the FSM minimizes the Mean Squared Error (MSE) by processing streaming data sequences in fixed blocks.

The total composite channel energy ($\text{power}$) is accumulated across all samples:

$$\text{power} = \sum_{i=0}^{N-1} \left( A_{re}[i]^2 + A_{im}[i]^2 \right)$$

The dynamic learning rate ($\alpha$) is updated in the `COMPUTE_AX` state by scaling a fixed-point numerator by the computed channel energy to maintain a $Q2.14$ precision layer:

$$\alpha = \frac{1 \ll \left(2 \cdot \text{SHIFT\_PRODUCT} + 14\right)}{\text{power}}$$

The complex residual error vector calculation for each element is governed by:

$$r_{re}[i] = y[i] - (A_{re}[i] \cdot x_{re} - A_{im}[i] \cdot x_{im})$$

$$r_{im}[i] = 0 - (A_{re}[i] \cdot x_{im} + A_{im}[i] \cdot x_{re})$$

The accumulated complex-conjugate gradients ($\nabla$) over a total set of $N$ samples are tracked via:

$$\text{total\_grad\_re} = \sum_{i=0}^{N-1} \left( A_{re}[i] \cdot r_{re}[i] + A_{im}[i] \cdot r_{im}[i] \right)$$

$$\text{total\_grad\_im} = \sum_{i=0}^{N-1} \left( A_{re}[i] \cdot r_{im}[i] - A_{im}[i] \cdot r_{re}[i] \right)$$

The parameter update vector state rules for optimization follow:

$$x_{re}^{(k+1)} = x_{re}^{(k)} + \left( \alpha \cdot \text{total\_grad\_re} \right)$$

$$x_{im}^{(k+1)} = x_{im}^{(k)} + \left( \alpha \cdot \text{total\_grad\_im} \right)$$
---

## Key Features

* **Parameterizable Block Sizes:** Fully dynamic configuration via `sample` and `BLOCK_SIZE` parameters to adapt to varying matrix constraints and balance system throughput with logical area costs.
* **Dynamic Step Scaling:** Automatically scales the algorithmic learning step ($\alpha$) inversely with signal power $\sum \|A\|^2$ to safeguard against divergence during optimization.
* **Overflow Protection Guardrails:** Features integrated overflow detection mechanisms in the state update layer, locking weights to raw boundaries (`16'sh7FFF` or `16'sh8000`) to completely eliminate binary roll-over noise distortions.

---

## Architecture & FSM States

The module processes hardware calculations sequentially using a 7-state structural FSM:

1. **`IDLE` (3'd0):** Awaits activation from the `start` input toggle; clears vector coefficients and updates tracking components.
2. **`ACCUMULATE_Y_A` (3'd7):** Aggregates power metrics over data elements to dynamically calibrate baseline error tracking limits.
3. **`COMPUTE_AX` (3'd1):** Formulates step coefficient weights via fixed-point division logic while checking against division-by-zero errors.
4. **`RESIDUAL` (3'd2):** Collects ongoing tracking variance profiles by computing scalar operational errors against complex elements.
5. **`CHECK_ERROR` (3'd3):** Tracks complete Mean Squared Error (MSE) trends; evaluates early termination requirements.
6. **`GRADIENT` (3'd4):** Accumulates cross-product evaluations over vector blocks to extract precise coordinate trajectories.
7. **`UPDATE_X` (3'd5):** Appends optimization corrections while checking step constraints and verifying overflow parameters.
8. **`DONE` (3'd6):** Packs matching structural parameters into `x_out` and asserts the single-cycle `done` notification flag.

---

## Module Interface (I/O Signal List)

| Signal Name | Direction | Width | Type | Description |
| :--- | :--- | :--- | :--- | :--- |
| `clk` | Input | `1` | wire | System Clock |
| `rst` | Input | `1` | wire | Synchronous Reset Layer (Active High) |
| `start` | Input | `1` | wire | Pulse activation signal to start processing loops |
| `y_vector` | Input | `(sample*bits-1):0` | wire | Packed array representation of Real baseline observations |
| `A_column_rel` | Input | `(sample*bits-1):0` | wire | Packed Real vector data values ($A_{re}$) |
| `A_column_iml` | Input | `(sample*bits-1):0` | wire | Packed Imaginary vector data values ($A_{im}$) |
| `x_out` | Output | `(2*bits-1):0` | reg | Packed Complex parameter output vector structure |
| `done` | Output | `1` | reg | Complete handshake indicator; signals algorithm convergence |

---

## Verification & Testbench Results

The correctness and arithmetic precision of the Gradient Descent hardware accelerator were rigorously verified using an data-driven cross-verification framework. The hardware's fixed-point calculations were audited against an algorithmic golden reference model executed in MATLAB.

### 1. Verification Methodology & Flow

The hardware design validation was carried out through a multi-step empirical verification pipeline:

1. **Golden Dataset Ingestion:** A golden verification matrix data structure containing real observation targets (`y_vec`) and multi-column data frames (`A`) was imported into the MATLAB test environment (`LMS_test (1).mat`).
2. **Fixed-Point Hex Conversion:** Using custom workspace serialization utilities, fractional matrix coefficients were quantified and formatted into standard signed hexadecimal vectors (`16'h%04X`).
3. **Testbench Injection & Simulation:** The converted hex sequences were fed directly into the structural Verilog testbench via packed configuration ports (`y_vector[6399:0]`, `A_column_rel[6399:0]`, `A_column_iml[6399:0]`) to stimulate the module under test.
4. **Hardware vs. Software Correlation:** Final converged hardware values (`final_x_re`, `final_x_im`) captured from the simulator waveform traces were directly compared to the high-precision floating-point matrix division quotients extracted from the MATLAB command terminal.

---

### 2. Simulation Waveform & Workspace Verification

The functional execution was validated by comparing the timing waveforms directly against the active MATLAB workspace results:

* **MATLAB Command Window Verification:** The double-precision matrix division `A(:,1)\y_vec` yields an analytical target solution of `-0.0730 + 0.0000i`.
* **Hardware Waveform Convergence:** Upon pulsing `start`, the internal FSM computes the dynamic learning step (`alp = 0.117614`) and sequentially minimizes the real gradient vector (`total_grad_re`) from `-0.621364` down toward zero.
* **Final Solution Delivery:** When convergence is achieved, the module asserts `done` and locks the final output vector parameters exactly to `x_out = 32'hfed30000` (representing $x_{re} = -0.073486$ and $x_{im} = 0.0$).

#### MATLAB Verification Workspace
![MATLAB Reference Result](/Complex_gradient_descent/1D%20complex%20column%20vector/Results%20img/matlab.jpg)

#### HDL Timing Simulation Waveform
![Vivado Simulation Waveform](/Complex_gradient_descent/1D%20complex%20column%20vector/Results%20img/1D_gradent.jpg)

---

### 3. Software vs. Hardware Numerical Cross-Check

The table below contrasts the computed hardware fixed-point metrics directly against the floating-point reference solution derived inside the MATLAB Command Window environment:

| Metric Reference Point | MATLAB Floating-Point Matrix Model | Hardware Fixed-Point Result (Q4.12) | Absolute Matching Delta | Status |
| :--- | :--- | :--- | :--- | :--- |
| **Optimized Parameter ($x_{re}$)** | `-0.0730` | `-0.073486` (`16'hFED3`) | `0.000486` | **PASSED** |
| **Optimized Parameter ($x_{im}$)** | `0.0000` | `0.0` (`16'h0000`) | `0.000000` | **PASSED** |

> [!NOTE]
> The tiny delta variance observed between the design environments represents the expected mathematical quantization noise introduced by formatting coefficients into a 12-bit fractional layer (`FRAC=12`). Hardware execution paths track floating-point trajectory models perfectly.

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