# RTL Design & Verification Modules — IIT Hyderabad Internship (Summer 2026)

This repository contains production-grade RTL hardware designs and verification pipelines developed during my research internship under **Dr. Abhishek Kumar** at **IIT Hyderabad**. The modules span arithmetic accelerators, high-speed interfaces, and signal processing DSP cores optimized for FPGA/ASIC synthesis.

---

## 📂 Repository Structure

```text
├── Complex_divider/
│   ├── rtl/
│   │   └── complex_divider.v                 # Parameterized 4-state Complex Divider FSM
│   └── tb/
│       ├── complex_divider_fsm_output_overflow_tb.v
│       ├── complex_divider_fsm_q0_16_tb.v
│       └── complex_divider_fsm_tb.v
│
├── Complex_gradient_descent/
│   ├── matlab/                               # Golden evaluation & coefficient scripts
│   │   ├── hex_converter.m
│   │   ├── two_column.m
│   │   └── two_col_noise.m
│   ├── 1D complex column vector/
│   │   ├── Results img/ (1D_gradient.jpg, matlab.jpg)
│   │   ├── rtl/ (Gradient_descent.v)         # 1D Complex LMS Optimizer
│   │   └── tb/ (tb_gradient_descent.v)
│   └── 2D complex column vector/
│       ├── results images/ (2D_gradient.jpg, 2D_mat.jpg)
│       ├── rtl/ 
│       └── tb/
│
├── Interface/
│   ├── Parallel-to-Serial/
│   │   ├── Result image/ (p2s.jpg)
│   │   ├── rtl/ (adc_decimation.v)           # 2x Decimation & CDC Extraction Interface
│   │   └── tb/ (tb.v)
│   └── Serial-to-Parallel/
│       ├── Result_image/ (92s.jpg)
│       ├── rtl/ (dac_packetizer.v)           # 2048-bit to 256-bit MUX Streamer
│       └── tb/ (tb_dac.v)
│
└── Matlab data/                              # Imported golden dataset matrix frames
    ├── LMS_test (1).mat
    └── LMS_test_smaller (1).mat
