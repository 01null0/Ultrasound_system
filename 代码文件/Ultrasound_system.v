// ============================================================
// File Name: Ultrasound_system.v
// Description: Reconstructed from Ultrasound_system.bdf
//              Top-level module connecting all sub-modules.
// ============================================================
module Ultrasound_system (
    input  wire        clk_50M,
    input  wire        rst_n,
    input  wire        TBS_in,
    input  wire        ad_in,    // AD7352 MISO

    output wire        TBS_out,
    output wire        ad_cs,
    output wire        ad_clk,
    output wire        relay,
    output wire        VIN_1,
    output wire        VIN_2,
    output wire        VIN_3,
    output wire        VIN_4
);

    // ========================================================
    // Internal Wires / Connection Signals
    // ========================================================
    wire        rs232_rx_line;      // TBS_RX -> UART_RX
    wire [2:0]  command_bus;        // UART_RX -> Order_4s
    
    wire        sys_start_pulse_w;  // Order_4s -> Echo_Correlation
    wire        launch_cmd_w;       // Order_4s -> Launch Module
    wire        AD_start_w;         // Order_4s -> AD Module
    
    wire        clk_45M_w;          // PLL -> AD
    wire        pll_areset_w;       // Reset_PLL -> PLL
    wire        pll_locked_w;       // PLL -> (unused)
    
    wire [11:0] ad_data_w;          // AD -> FIFO
    wire        ad_done_w;          // AD -> FIFO (wrreq)
    
    wire [11:0] fifo_q_w;           // FIFO -> Echo
    wire        fifo_empty_w;       // FIFO -> Echo
    wire        fifo_rdreq_w;       // Echo -> FIFO
    
    wire [19:0] echo_tof_w;         // Echo -> UART_TX
    wire [17:0] echo_peak_w;        // Echo -> UART_TX
    wire        processing_done_w;  // Echo -> UART_TX
    
    wire        rs232_tx_line;      // UART_TX -> TBS_TX

    // ========================================================
    // Module Instantiations
    // ========================================================

    // 1. TBS Receiver Interface
    TBS_RX inst2_TBS_RX (
        .clk_50M   (clk_50M),
        .rst_n     (rst_n),
        .TBS_in    (TBS_in),
        .rs232_out (rs232_rx_line)
    );

    // 2. UART Receiver (Command Parser)
    UART_RX inst3_UART_RX (
        .clk_50M      (clk_50M),
        .rst_n        (rst_n),
        .rs232_rx     (rs232_rx_line),
        .rx_done      (),              // unused
        .test_rx_data (),              // unused
        .command      (command_bus)
    );

    // 3. Main Control Logic (State Machine)
    Order_4s inst4_Order_4s (
        .clk_50M         (clk_50M),
        .rst_n           (rst_n),
        .command         (command_bus),
        .sys_start_pulse (sys_start_pulse_w),
        .start           (),           // unused
        .start_test      (),           // unused
        .Exc_start       (launch_cmd_w),
        .relay           (relay),
        .AD_start        (AD_start_w)
    );

    // 4. Ultrasound Launch Module
    ultrasound_launch_90KHz_10ms inst5_launch (
        .clk_50M    (clk_50M),
        .rst_n      (rst_n),
        .launch_cmd (launch_cmd_w),
        .VIN_1      (VIN_1),
        .VIN_2      (VIN_2),
        .VIN_3      (VIN_3),
        .VIN_4      (VIN_4)
    );

    // 5. PLL Reset Logic
    Reset_PLL inst15_Reset_PLL (
        .clk_50M (clk_50M),
        .reset_n (rst_n),
        .areset  (pll_areset_w)
    );

    // 6. PLL IP Core (Generates 45MHz for AD)
    pll_ip inst6_pll (
        .inclk0 (clk_50M),
        .areset (pll_areset_w),
        .c0     (clk_45M_w),
        .locked (pll_locked_w)
    );

    // 7. AD Controller (AD7352)
    AD inst9_AD (
        .clk_50M  (clk_50M),
        .clk_45M  (clk_45M_w),
        .rst_n    (rst_n),
        .ad_in    (ad_in),
        .AD_start (AD_start_w),
        .ad_cs    (ad_cs),
        .ad_clk   (ad_clk),
        .ad_out   (ad_data_w),
        .ad_done  (ad_done_w)
    );

    // 8. FIFO Buffer
    // Note: rdclk is connected to clk_50M in BDF
    fifo inst_fifo (
        .wrclk   (clk_50M),
        .wrreq   (ad_done_w),
        .data    (ad_data_w),
        .rdclk   (clk_50M),
        .rdreq   (fifo_rdreq_w),
        .q       (fifo_q_w),
        .rdempty (fifo_empty_w)
    );

    // 9. Echo Correlation / Signal Processing
    Echo_Correlation inst_Echo_Correlation (
        .clk_50M         (clk_50M),
        .rst_n           (rst_n),
        .sys_start_pulse (sys_start_pulse_w),
        .fifo_q          (fifo_q_w),
        .fifo_empty      (fifo_empty_w),
        .corr_threshold  (18'd0),        // Connected to default/GND in BDF
        .fifo_rdreq      (fifo_rdreq_w),
        .hit_flag        (),             // unused
        .echo_tof        (echo_tof_w),
        .echo_peak       (echo_peak_w),
        .processing_done (processing_done_w)
    );

    // 10. UART Transmitter (Result Upload)
    UART_TX inst12_UART_TX (
        .clk_50M         (clk_50M),
        .rst_n           (rst_n),
        .echo_tof        (echo_tof_w),
        .echo_peak       (echo_peak_w),
        .processing_done (processing_done_w),
        .rs232_tx        (rs232_tx_line),
        .tx_busy         ()
    );

    // 11. TBS Transmitter Interface
    TBS_TX inst2_TBS_TX (
        .clk_50M (clk_50M),
        .rst_n   (rst_n),
        .rs232_in(rs232_tx_line),
        .TBS_out (TBS_out)
    );

endmodule
