// ----------------------------------------------------------------------------
// 模块名称: AD8137_7352_test (直接输出AD原始数据测试版)
// 功能: 用于 AD8137 和 AD7352 链路的零点测试，输出单点原始数据
// ----------------------------------------------------------------------------
module AD8137_7352_test (
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

    // 输出结果 (将AD原始数据通过 echo_tof 发送)
    output reg        hit_flag,
    output reg [19:0] echo_tof,       // 借用输出: 直接输出 AD 原始数值
    output reg [17:0] echo_peak,      
    output reg        processing_done 
);

    // ============================================================
    // 1. FIFO 读取控制逻辑
    // ============================================================
    // 只要 FIFO 不空就一直读，把数据抽空，防止上游 AD/FIFO 堵塞卡死
    assign fifo_rdreq = !fifo_empty;

    // 指示当前处理的数据是否有效
    reg fifo_data_valid;
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) 
            fifo_data_valid <= 0;
        else 
            fifo_data_valid <= fifo_rdreq;
    end

    // ============================================================
    // 2. 采样抓取逻辑
    // ============================================================
    reg [7:0] sample_cnt;

    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) begin
            sample_cnt      <= 8'd0;
            echo_tof        <= 20'd0;
            echo_peak       <= 18'd0;
            hit_flag        <= 1'b0;
            processing_done <= 1'b0;
        end
        else if (sys_start_pulse) begin
            // 每次系统重新触发，计数器清零，准备抓取新的点
            sample_cnt      <= 8'd0;
            processing_done <= 1'b0;
            hit_flag        <= 1'b0;
        end
        else if (fifo_data_valid) begin
            // 抓取第 10 个数据点（避开刚上电或刚触发时的任何抖动）
            if (sample_cnt < 8'd10) begin
                sample_cnt <= sample_cnt + 1'b1;
                processing_done <= 1'b0;
            end
            else if (sample_cnt == 8'd10) begin
                hit_flag <= 1'b1;
                
                // 【核心逻辑】：直接把 FIFO 出来的 12位原始 AD数据 赋给 TOF
                echo_tof <= {8'd0, fifo_q}; 
                
                // 拉高完成信号，通知顶层的 UART_TX_8bit 发送数据
                processing_done <= 1'b1; 
                
                // 计数器加 1，停留在 >10 的状态，直到下一次 sys_start_pulse
                sample_cnt <= sample_cnt + 1'b1; 
            end
            else begin
                // 恢复 processing_done，产生一个单周期脉冲即可
                processing_done <= 1'b0; 
            end
        end
        else begin
            processing_done <= 1'b0;
        end
    end

endmodule