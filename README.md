# RTL Design & Verification Modules — IIT Hyderabad Internship (Summer 2026)

This repository contains production-grade RTL hardware designs and verification pipelines developed during my research internship under **Dr. Abhishek Kumar** at **IIT Hyderabad**. The modules span arithmetic accelerators, high-speed interfaces, and signal processing DSP cores optimized for FPGA/ASIC synthesis.

---

## 📂 Repository Structure

```text
├── Compensation filter/
│   ├── matlab/
│   │   ├── adc_din.txt
│   │   ├── MWC Calibration & Compensation Filter.m
│   │   └── readme.md
│   ├── rtl/
│   │   ├── downsampler.v
│   │   ├── fir_filter.v
│   │   ├── mwc_pre_processing_top.v
│   │   └── upsampler.v
│   ├── tb/
│   │   ├── tb_fir_filter.v
│   │   ├── tb_mwc_downsampler.v
│   │   ├── tb_mwc_pre_processing_top.v
│   │   └── tb_mwc_upsampler.v
│   |── xsim/
│   |   └── clean_dout.txt
│   └── README
|
├── Complex_divider/
│   ├── rtl/
│   │   └── complex_divider.v                 
│   └── tb/
│       ├── complex_divider_fsm_output_overflow_tb.v
│       ├── complex_divider_fsm_q0_16_tb.v
│       └── complex_divider_fsm_tb.v
│
├── Complex_gradient_descent/
│   ├── matlab/                               
│   │   ├── hex_converter.m
│   │   ├── two_column.m
│   │   └── two_col_noise.m
│   ├── 1D complex column vector/
│   │   ├── Results img/ (1D_gradient.jpg, matlab.jpg)
│   │   ├── rtl/ (Gradient_descent.v)         
│   │   └── tb/ (tb_gradient_descent.v)
│   └── 2D complex column vector/
│       ├── results images/ (2D_gradient.jpg, 2D_mat.jpg)
│       ├── rtl/ 
│       └── tb/
│
└── Interface/
    ├── Parallel-to-Serial/
    │   ├── Result image/ (p2s.jpg)
    |   │   ├── rtl/ (adc_decimation.v)           
    │   └── tb/ (tb.v)
    └── Serial-to-Parallel/
        ├── Result_image/ (92s.jpg)
        ├── rtl/ (dac_packetizer.v)          
        └── tb/ (tb_dac.v)
