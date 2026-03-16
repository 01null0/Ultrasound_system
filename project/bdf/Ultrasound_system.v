// ============================================================
// File Name: Ultrasound_system.v
// Description: Reconstructed from Ultrasound_system.bdf
//              Top-level module connecting all sub-modules.
// ============================================================
module Ultrasound_system (
    input  wire clk_50M,
    input  wire rst_n,
    input  wire TBS_in,
    input  wire ad_in,    // AD7352 MISO
    output wire TBS_out,
    output wire ad_cs,
    output wire ad_clk,
    output wire relay,
    output wire VIN_1,
    output wire VIN_2,
    output wire VIN_3,
    output wire VIN_4
);

    // ========================================================
    // Internal Wires / Connection Signals
    // ========================================================
    wire        rs232_rx_line;  // TBS_RX -> UART_RX
    wire [ 2:0] command_bus;  // UART_RX -> Order_4s

    wire        sys_start_pulse_w;  // Order_4s -> Echo_Correlation
    wire        launch_cmd_w;  // Order_4s -> Launch Module
    wire        AD_start_w;  // Order_4s -> AD Module

    wire        clk_45M_w;  // PLL -> AD
    wire        pll_areset_w;  // Reset_PLL -> PLL
    wire        pll_locked_w;  // PLL -> (unused)

    wire [17:0] rx_threshold_w;  // 用于连接 UART_RX 输出的新阈值

    wire [11:0] ad_data_w;  // AD -> FIFO
    wire        ad_done_w;  // AD -> FIFO (wrreq)

    wire [11:0] fifo_q_w;  // FIFO -> Echo
    wire        fifo_empty_w;  // FIFO -> Echo
    wire        fifo_rdreq_w;  // Echo -> FIFO

    wire [19:0] echo_tof_w;  // Echo -> UART_TX
    wire [17:0] echo_peak_w;  // Echo -> UART_TX
    wire        processing_done_w;  // Echo -> UART_TX

    wire        rs232_tx_line;  // UART_TX -> TBS_TX
    wire        batch_start_w;
    wire        batch_end_w;
    wire [ 2:0] cmd_from_rx;  // 从 UART_RX 出来的原始命令
    wire [ 2:0] cmd_to_order;  // 经过处理后给 Order_4s 的命令
    wire        tx_main_line;  // 原 UART_TX_8bit 的输出
    wire        tx_ack_line;  // 新模块的 ACK 输出

    // ========================================================
    // Module Instantiations
    // ========================================================

    // 1. TBS Receiver Interface
    TBS_RX inst2_TBS_RX (
        .clk_50M  (clk_50M),
        .rst_n    (rst_n),
        .TBS_in   (TBS_in),
        .rs232_out(rs232_rx_line)
    );

    UART_RX inst3_UART_RX (
        .clk_50M       (clk_50M),
        .rst_n         (rst_n),
        .rs232_rx      (rs232_rx_line),
        .corr_threshold(rx_threshold_w),
        .frame_valid   (rx_frame_valid_w),
        // .command      (command_bus)    <-- 原连接（删除或注释）
        .command       (cmd_from_rx)        // <-- 改为连接到新定义的中间信号
    );
    //应答
    Ack_Start_Controller inst_Ack_Ctl (
        .clk           (clk_50M),
        .rst_n         (rst_n),
        .rx_frame_valid(rx_frame_valid_w),  // 【新增连线】：接入帧有效脉冲
        .rx_cmd_in     (cmd_from_rx),
        .sys_cmd_out   (cmd_to_order),
        .ack_tx_line   (tx_ack_line)
    );

    // 3. Main Control Logic (State Machine)
    Order_4s inst4_Order_4s (
        .clk_50M        (clk_50M),
        .rst_n          (rst_n),
        //.command        (command_bus),
        .command        (cmd_to_order),
        .sys_start_pulse(sys_start_pulse_w),
        .start          (),
        .start_test     (),
        .Exc_start      (launch_cmd_w),
        .relay          (relay),
        .AD_start       (AD_start_w),
        // 【新增】
        .batch_start    (batch_start_w),
        .batch_end      (batch_end_w)
    );

    // 4. Ultrasound Launch Module
    ultrasound_launch_90KHz_10ms inst5_launch (
        .clk_50M   (clk_50M),
        .rst_n     (rst_n),
        .launch_cmd(launch_cmd_w),
        .VIN_1     (VIN_1),
        .VIN_2     (VIN_2),
        .VIN_3     (VIN_3),
        .VIN_4     (VIN_4)
    );

    // 5. PLL Reset Logic
    Reset_PLL inst15_Reset_PLL (
        .clk_50M(clk_50M),
        .reset_n(rst_n),
        .areset (pll_areset_w)
    );

    // 6. PLL IP Core (Generates 45MHz for AD)
    pll_ip inst6_pll (
        .inclk0(clk_50M),
        .areset(pll_areset_w),
        .c0    (clk_45M_w),
        .locked(pll_locked_w)
    );

    // 7. AD Controller (AD7352)
    AD inst9_AD (
        .clk_50M (clk_50M),
        .clk_45M (clk_45M_w),
        .rst_n   (rst_n),
        .ad_in   (ad_in),
        .AD_start(AD_start_w),
        .ad_cs   (ad_cs),
        .ad_clk  (ad_clk),
        .ad_out  (ad_data_w),
        .ad_done (ad_done_w)
    );

    // 8. FIFO Buffer
    // Note: rdclk is connected to clk_50M in BDF
    fifo inst_fifo (
        .wrclk  (clk_45M_w),
        .wrreq  (ad_done_w),
        .data   (ad_data_w),
        .rdclk  (clk_50M),
        .rdreq  (fifo_rdreq_w),
        .q      (fifo_q_w),
        .rdempty(fifo_empty_w)
    );

    // 9. Echo Correlation / Signal Processing
    Echo_Correlation inst_Echo_Correlation (
        .clk_50M        (clk_50M),
        .rst_n          (rst_n),
        .sys_start_pulse(sys_start_pulse_w),
        .fifo_q         (fifo_q_w),
        .fifo_empty     (fifo_empty_w),

        // 【修改】这里不再连接 18'd0，而是连接顶层输入的 corr_threshold
        .corr_threshold(rx_threshold_w),

        .fifo_rdreq     (fifo_rdreq_w),
        .hit_flag       (),                  // unused
        .echo_tof       (echo_tof_w),
        .echo_peak      (echo_peak_w),
        .processing_done(processing_done_w)
    );

    // 10. UART Transmitter (Result Upload)
    // UART_TX inst12_UART_TX (
    //     .clk_50M        (clk_50M),
    //     .rst_n          (rst_n),
    //     .echo_tof       (echo_tof_w),
    //     .echo_peak      (echo_peak_w),
    //     .processing_done(processing_done_w),
    //     .rs232_tx       (rs232_tx_line),
    //     .tx_busy        ()
    // );
    UART_TX_8bit inst12_UART_TX (
        .clk_50M        (clk_50M),
        .rst_n          (rst_n),
        // 【新增/修改接口】
        .batch_start    (batch_start_w),
        .batch_end      (batch_end_w),
        .echo_tof       (echo_tof_w),
        .processing_done(processing_done_w),
        .rs232_tx       (tx_main_line)
        //.rs232_tx(rs232_tx_line)
    );
    // 合并主数据 TX 和 应答 TX
    assign rs232_tx_line = tx_main_line & tx_ack_line;

    // 11. TBS Transmitter Interface
    TBS_TX inst2_TBS_TX (
        .clk_50M (clk_50M),
        .rst_n   (rst_n),
        .rs232_in(rs232_tx_line),
        .TBS_out (TBS_out)
    );

endmodule
