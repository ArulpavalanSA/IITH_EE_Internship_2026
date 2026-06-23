# Parallel-to-Serial ADC Decimation & Extraction Interface

## 📝 Overview
The `adc_decimation` module is a hardware deserialization and downsampling interface designed to ingest wide, multi-sample parallel digital data packets from a high-speed Analog-to-Digital Converter (ADC) pipeline and stream them as isolated sequential words. Operating across an asynchronous Clock Domain Crossing (CDC), the module captures a 192-bit parallel bus on a high-speed clock domain (`clk`) and extracts decimated 16-bit sample components over a divided processing clock domain (`clk_1`).

---

## Architectural Mechanics & Clock Domain Crossing (CDC)

The module coordinates data transfer and rate reduction between two separate clock systems using a handshake-free toggle synchronizer mechanism:

### 1. High-Speed Capture and Toggle Assertion (`clk`)
* When the input flag `valid` is asserted on the rising edge of `clk`, the wide 192-bit observation vector `packet_in` is securely latched into the `packet_captured` storage register.
* Concurrently, a internal `toggle` flip-flop is inverted (`~toggle`), signaling to the downstream clock domain that a new data payload is ready for serial disassembly.

### 2. Dual-Stage Metastability Defenses (`clk_1`)
* Because `clk` and `clk_1` operate asynchronously, the control flag `toggle` passes through a 2-bit shift-register pipeline (`toggle_sync`) clocked by the slower destination domain `clk_1`.
* This dual-stage structure isolates metastability, and an edge detection circuit determines when a fresh transfer arrives by evaluating the inequality:
$$\text{new packet} = (\text{toggle sync}[0] \neq \text{toggle sync}[1])$$

### 3. Decimation Logic & Serialization Loop
* Upon detecting `new_packet`, an internal control flag `update` is raised. 
* The module sequentially unrolls the packed vector over 6 successive `clk_1` clock periods, pulling every alternate 16-bit sample word. This downsampling filter implements a **decimation-by-2** structure, filtering out padding/interleaved channels and lowering the high-bandwidth output stream down to the target baseband layer.

---

## Key Features

* **Asynchronous Clock Boundary Crossing:** Employs a robust, low-overhead dual-stage toggle-synchronizer network to securely bridge data vectors between un-phased clock domains.
* **Integrated 2× Decimation Filter:** Natively downsamples data sequences during extraction by parsing out alternating 16-bit segments (capturing 6 unique channels out of 12 packed streams).
* **Deterministic Word Extraction:** Leverages an interior state-tracking pointer (`shift_count`) to execute strict, jitter-free timing bounds during word shifting.
* **Autonomous Handshaking Ports:** Automatically drives a single-cycle high output flag (`valid_out`) during window extraction, allowing drop-in compatibility with downstream DSP IPs or AXI-Stream FIFOs.

---

## Module Interface (I/O Signal List)

| Signal Name | Direction | Width | Type | Description |
| :--- | :--- | :--- | :--- | :--- |
| `clk` | Input | `1` | wire | High-speed master interface source clock |
| `rst` | Input | `1` | wire | Synchronous global master reset layer (Active High) |
| `packet_in` | Input | `192` | wire | 192-bit packed parallel data packet array from the ADC front-end |
| `valid` | Input | `1` | wire | Input data qualification handshake flag |
| `clk_1` | Input | `1` | wire | Divided downsampled processing/destination clock |
| `sample_out` | Output | `16` | reg | Extracted, decimated 16-bit signed ADC sample output |
| `valid_out` | Output | `1` | reg | High-asserted downstream data validity handshake signal |

---

## Verification & Testbench Results

The functional integrity, data layout preservation, and Clock Domain Crossing behavior of the `adc_decimation` block were verified via behavioral timing simulation within AMD Vivado.

### 1. Functional Waveform Execution Analysis

The hardware module was stimulated using a patterned 192-bit hex sequence to evaluate the shifting order and decimation boundaries across the clock domains:

* **Input Data Stream:** A test packet vector is injected on the `clk` interface:
  `packet_in = 192'haaaabbbbccccddddeeeeffff999988887777555511112222`
* **CDC Synchronization Transition:** As seen in the timing waveform, the assertion of `valid` registers the packet on `clk`. Following a brief latency dictated by the 2-stage synchronizer on the `clk_1` domain, the interior internal signal `new_packet` pulses high to notify the processing state machine.
* **Decimated Serial Extraction:** Once `update` is asserted, the serialization logic begins parsing out data on every rising edge of `clk_1`. It extracts and routes every alternate 16-bit word, isolating individual components sequentially while safely skipping the interleaved channels:
  $$\text{aaaa} \rightarrow \text{cccc} \rightarrow \text{eeee} \rightarrow \text{9999} \rightarrow \text{7777} \rightarrow \text{1111}$$
* **Handshake Termination:** Upon routing the final decimated sample block (`16'h1111`), the internal counter reaches its boundary limit (`shift_count == 7`), forcing `valid_out` to drop low to prevent duplicate data reads.

#### HDL Timing Simulation Waveform
![Vivado Decimation Simulation Waveform](/Interface/Parallel-to-Serial/Result%20image/p2s.jpg)

---

### 2. Software vs. Hardware Structural Mapping

The validation table below matches the packed parallel elements within the high-speed input stream against the serialized hardware outputs observed on the tracking ports:

| Processing Stage / Step Pointer | Input Word Segment (16-bit) | Extracted Output Parameter (`sample_out`) | Operation Mode | Status |
| :--- | :--- | :--- | :--- | :--- |
| **Initial Latch Event** | `16'haaaa` | `16'haaaa` | **Capture & Route** | **PASSED** |
| **Shift Sequence 1** | `16'hbbbb` | *Skipped* | **Decimation Filter Block** | **PASSED** |
| **Shift Sequence 2** | `16'hcccc` | `16'hcccc` | **Capture & Route** | **PASSED** |
| **Shift Sequence 3** | `16'hdddd` | *Skipped* | **Decimation Filter Block** | **PASSED** |
| **Shift Sequence 4** | `16'heeee` | `16'heeee` | **Capture & Route** | **PASSED** |
| **Shift Sequence 5** | `16'hffff` | *Skipped* | **Decimation Filter Block** | **PASSED** |
| **Shift Sequence 6** | `16'h9999` | `16'h9999` | **Capture & Route** | **PASSED** |
| **Shift Sequence 7** | `16'h8888` | *Skipped* | **Decimation Filter Block** | **PASSED** |
| **Shift Sequence 8** | `16'h7777` | `16'h7777` | **Capture & Route** | **PASSED** |
| **Shift Sequence 9** | `16'h5555` | *Skipped* | **Decimation Filter Block** | **PASSED** |
| **Shift Sequence 10** | `16'h1111` | `16'h1111` | **Capture & Route** | **PASSED** |
| **Shift Sequence 11** | `16'h2222` | *Skipped* | **Decimation Filter Block** | **PASSED** |

> [!NOTE]
> The simulation confirms that the module executes exactly six extraction cycles per parallel packet arrival. The data interface functions reliably across the clock boundaries without dropping elements or corrupting channel sequence alignment.
