// ----------------------------------------------------------------------------
// 模块名称: TBS_test (通讯测试版)
// 功能: 用于替代原本的自相关模块，输出固定数值以验证 UART/TBS 通讯链路
// ----------------------------------------------------------------------------
module TBS_test (
    input clk_50M,
    input rst_n,

    // 系统启动信号
    input sys_start_pulse,  

    // --- FIFO 接口 ---
    input [11:0] fifo_q,       
    input        fifo_empty,   
    output       fifo_rdreq,   
    // -------------------

    input [17:0] corr_threshold,

    // 输出结果
    output reg        hit_flag,
    output reg [19:0] echo_tof,   
    output reg [17:0] echo_peak, 
    output reg        processing_done 
);

    // ============================================================
    // 1. 维持 FIFO 正常运转
    // ============================================================
    // 只要 FIFO 不空，就持续读取将其清空，防止系统上下游阻塞
    assign fifo_rdreq = !fifo_empty; 

    // ============================================================
    // 2. 测试数据及延时参数设定
    // ============================================================
    // 设定你想在串口助手上看到的固定测试数据
    localparam FIXED_TOF  = 20'd12345;  // 固定的时间点索引 (十六进制为 0x3039)
    localparam FIXED_PEAK = 18'd8888;   // 固定的峰值大小

    // 模拟处理延时，延时足够长以确保系统稳定后再触发发送
    localparam PROCESS_DELAY = 16'd5000; 
    reg [15:0] delay_cnt;

    // ============================================================
    // 3. 状态控制与固定数据输出
    // ============================================================
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) begin
            hit_flag        <= 1'b0;
            echo_tof        <= 20'd0;
            echo_peak       <= 18'd0;
            processing_done <= 1'b0;
            delay_cnt       <= 16'd0;
        end
        else if (sys_start_pulse) begin
            // 收到新一轮采集的启动信号，清零标志位并重新开始延时计数
            hit_flag        <= 1'b0;
            echo_tof        <= 20'd0;
            echo_peak       <= 18'd0;
            processing_done <= 1'b0;
            delay_cnt       <= 16'd0;
        end
        else begin
            // 模拟计算过程的耗时
            if (delay_cnt < PROCESS_DELAY) begin
                delay_cnt <= delay_cnt + 1'b1;
                processing_done <= 1'b0;
            end 
            // 延时到达，输出固定结果
            else if (delay_cnt == PROCESS_DELAY) begin
                hit_flag        <= 1'b1;
                echo_tof        <= FIXED_TOF;
                echo_peak       <= FIXED_PEAK;
                processing_done <= 1'b1;        // 拉高处理完成标志，触发UART发送
                delay_cnt       <= delay_cnt + 1'b1; // 停止计数，停留在该状态直到下一次 pulse
            end
        end
    end

endmodule