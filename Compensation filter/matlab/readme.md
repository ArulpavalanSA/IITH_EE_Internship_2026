# 📖 MWC Offline Calibration & Filter Coefficient Generator Script

This MATLAB script is an **offline calibration tool** for a **Modulated Wideband Converter (MWC)**. 

In plain terms, when you send high-frequency signals through a real-world electronic circuit board, the physical copper tracks, connectors, and chips act like a messy filter—they accidentally shrink the signal and delay it. This script **simulates those physical board mistakes, calculates exactly how to fix them, and outputs the exact hex code** you need to copy-paste directly into an FPGA (Verilog) hardware design to clean up the signal.

---

## 🛠️ Section-by-Section Breakdown

### 1. System Parameters Configuration
Before doing any math, the script sets up the boundaries and data formats of the physical hardware pipeline:
* **The Speed (`fs = 100e6`):** The master digital pipeline runs at **100 MHz**.
* **Fixed-Point Layout (`Q8.8 Format`):** FPGAs cannot process decimal numbers easily. The script configures a **Q8.8 format** inside 16-bit blocks (`DATA_WIDTH` and `COEFF_WIDTH`). This means 8 bits are reserved for whole numbers, and 8 bits are reserved for the fractional/decimal parts.
* **The Filters (`16 Taps`):** It prepares to design two filters (**`Hs`**, a sharp low-pass filter, and **`Hc`**, a board compensation filter) that are each exactly 16 steps (taps) long.

---

### 2. Generate Newman-Phase Training Signal & Ideal Spectrum
To find out how a circuit board distorts a signal, you have to feed it a known test signal. The script creates a **multi-tone** signal, which is a bundle of **7 pure sine waves (tones)** grouped together (`G = 7`).

* **The Problem:** If you combine 7 sine waves normally, their peaks align perfectly at certain points, creating a massive voltage spike that overloads and clips the Analog-to-Digital Converter (ADC).
* **The Solution:** The script uses a mathematical trick called **Newman Phases**. It intentionally shifts the starting angle (phase) of each individual sine wave so they never peak at the same time. This keeps the total signal flat and safe for the hardware, creating a perfect reference spectrum (`Z_ideal`).

---

### 3. Model Hardware Imperfections
Because you are running this in a simulation instead of a real lab, the script uses a transfer function formula (`H_eq_true`) to **simulate a real, imperfect circuit board trace**. 
* It takes the perfect 7-tone test signal and introduces a **20% overall power loss**, adds a **2-nanosecond time delay** (the time it takes electricity to travel down physical copper track), and forces **high frequencies to roll off and fade out**. 
* The resulting degraded signal is called `Y_corrupted`.

---

### 4. Execute Distortion Estimation
Now, the script plays detective. Since it knows exactly what the signal *should* look like (`Z_ideal`) and what it *actually* looks like after the board messed it up (`Y_corrupted`), it performs a pointwise division at the 7 active tone locations:

$$\hat{H}_{eq} = \frac{Y_{corrupted}}{Z_{ideal}}$$

Because it only knows the distortion at those 7 specific frequency points, it uses **linear interpolation** (`interp1`) to connect the dots and guess how the board distorts all the other frequencies in between, reconstructing a continuous error curve.

---

### 5. Construct Target Frequency Response Filters
Now that the script knows exactly what mistakes the board makes, it designs the **Compensation Filter (`Hc`)** to counteract them. 
* It first creates an ideal low-pass target curve (`Hs_target`) with a sharp brick-wall cutoff at $1/8\text{th}$ of the sampling frequency.
* To fix the board errors, it mathematically **inverts** the estimated distortion inside the passband area. If the board shrinks a frequency by half, the compensation filter is programmed to amplify it by two.
* **Safety Guard:** The code includes a check (`abs(H_eq_continuous) > 1e-4`) to ensure it never divides by zero in areas outside the passband, preventing infinite mathematical gains.

---

### 6. Convert Frequency Responses to Time-Domain Coefficients via IFFT
Up to this point, all the filter design happened in the frequency domain. Hardware logic cannot read frequency graphs; it needs a sequential list of time-domain numbers (coefficients) to multiply against incoming samples.
* The script uses an **Inverse Fast Fourier Transform (IFFT)** to convert the frequency responses back into time-domain waves.
* It truncates the resulting waves down to fit our target **16-tap register length**.
* It normalizes and scales the values down slightly (`* 0.9`) to guarantee they will never cause an arithmetic integer overflow inside the FPGA's multipliers.

---

### 7. Quantize to Fixed-Point Layout & Generate Verilog Hex Vectors
This is where the math converts into a hardware-ready payload. The script loops through the 16 floating-point coefficients, converts them into signed 16-bit binary integers based on the Q8.8 rules, and formats them into **2's complement hexadecimal strings**. 

It then prints out a flattened parameter vector formatted directly for your RTL copy-pasting:
```verilog
hs_coeff_vector = 256'h00A200B1... ;