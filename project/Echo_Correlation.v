// ----------------------------------------------------------------------------
// 模块名称: Echo_Correlation
// 功能: 从FIFO读取数据进行90kHz回波自相关检测
// 注意: 
// 1. 此模块现在全速运行于50MHz，处理FIFO中的缓冲数据。
// 2. echo_tof 输出的单位变成了 "样本点索引" (Sample Index)。
//    实际物理时间 = (Window_Start_Time) + echo_tof * (1/Sample_Rate)。
// 3. 请根据采样率重新计算 BLIND_WINDOW 参数。
// ----------------------------------------------------------------------------
module Echo_Correlation (
    input clk_50M,
    input rst_n,

    // 系统启动信号，用于复位内部状态（如峰值记录）
    // 注意：如果是每10ms一轮，确保在FIFO开始写入或开始处理前给一个脉冲
    input sys_start_pulse,  // 每次新测量开始时拉高一个时钟周期

    // --- FIFO 接口修改 ---
    input [11:0] fifo_q,       // 来自 FIFO 的数据 (q)
    input        fifo_empty,   // FIFO 空标志 (rdempty)
    output       fifo_rdreq,   // FIFO 读请求
    // -------------------

    input [17:0] corr_threshold,

    // 输出结果
    output reg        hit_flag,
    output reg [19:0] echo_tof,   // 代表回波在FIFO中的位置(样本索引)
    output reg [17:0] echo_peak, 
    output reg       processing_done // 可选：指示FIFO读空，处理完成
);

    // ============================================================
    // 1. FIFO 读取控制逻辑
    // ============================================================
    // 只要 FIFO 不空，就全速读取
    assign fifo_rdreq = !fifo_empty;
    
    // 指示当前处理的数据是否有效
    // 对于 standard FIFO (LPM_SHOWAHEAD="OFF")，数据在 rdreq 后一个周期有效
    reg fifo_data_valid;
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) 
            fifo_data_valid <= 0;
        else 
            fifo_data_valid <= fifo_rdreq;
    end
    
    //===================================================================
    

    // ============================================================
    // 2. 数据预处理 & 移位寄存器
    // ============================================================
    wire signed [12:0] data_signed;
    // 使用 fifo_q 替代原来的 ad_data
    assign data_signed = {1'b0, fifo_q} - 13'd2048; 

    reg signed [12:0] tap[0:32];
    integer i;
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 33; i = i + 1) tap[i] <= 0;
        end
        // 使用 fifo_data_valid 替代 ad_valid
        else if (fifo_data_valid) begin
            tap[0] <= data_signed;
            for (i = 1; i < 33; i = i + 1) tap[i] <= tap[i-1];
        end
    end

    // ============================================================
    // 3. 互相关计算 (保持不变)
    // ============================================================
    reg signed [17:0] sum;
    always @(*) begin
        sum = 0;
        // Cycle 1
        sum = sum + tap[32] + tap[31] + tap[30] + tap[29] + tap[28];
        sum = sum - tap[27] - tap[26] - tap[25] - tap[24] - tap[23] - tap[22];
        // Cycle 2
        sum = sum + tap[21] + tap[20] + tap[19] + tap[18] + tap[17];
        sum = sum - tap[16] - tap[15] - tap[14] - tap[13] - tap[12] - tap[11];
        // Cycle 3
        sum = sum + tap[10] + tap[9] + tap[8] + tap[7] + tap[6];
        sum = sum - tap[5] - tap[4] - tap[3] - tap[2] - tap[1] - tap[0];
    end

    wire signed [17:0] abs_sum;
    assign abs_sum = (sum >= 0) ? sum : -sum;

    // ============================================================
    // 4. 时间(样本)计数器 & 参数调整 (重要修改)
    // ============================================================
    
    // 【重要提示】：原本的 25000 是基于 50MHz 时钟的。
    // 现在 global_cnt 计数的是“样本数”。
    // 假设您的 ADC 采样率是 1.5MHz (AD7352最大速率)，
    // 那么 500us 的盲区对应的样本数为：500us * 1.5MHz = 750 个点。
    // 请根据实际采样率修改下面的参数！
    
    parameter BLIND_WINDOW_SAMPLES  = 20'd500; // 示例：需根据实际采样率修改
    parameter NEAR_ZONE_END_SAMPLES = BLIND_WINDOW_SAMPLES + 20'd50; // 示例

    reg [19:0] global_cnt; 
    
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n)       global_cnt <= 0;
        else if (sys_start_pulse) global_cnt <= 0;
        // 只有在数据有效时才计数，这样 echo_tof 代表的是第几个采样点
        else if (fifo_data_valid && global_cnt < 20'hFFFFF) 
            global_cnt <= global_cnt + 1;
    end

    // ============================================================
    // 5. 自动底噪计算 
    // ============================================================
    reg [17:0] max_noise_blind;
    reg [17:0] base_threshold;

    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) begin
            max_noise_blind <= 0;
            base_threshold  <= 18'd2000; 
        end
        else if (sys_start_pulse) begin
            max_noise_blind <= 0;
            // base_threshold 保持上一轮的值或重置，取决于需求，这里建议保持
        end
        else if (fifo_data_valid) begin // 仅在数据有效时更新逻辑
            // 采样窗口
            if (global_cnt > 20'd100 && global_cnt < BLIND_WINDOW_SAMPLES) begin
                if (abs_sum > max_noise_blind)
                    max_noise_blind <= abs_sum;
            end
            
            // 盲区结束瞬间
            if (global_cnt == BLIND_WINDOW_SAMPLES) begin
                base_threshold <= max_noise_blind + (max_noise_blind >> 1);
                if ((max_noise_blind + (max_noise_blind >> 1)) < 18'd600)
                    base_threshold <= 18'd600;
            end
        end
    end

    // ============================================================
    // 6. 动态分段阈值
    // ============================================================
    reg [17:0] dynamic_thresh;
    always @(*) begin
        if (corr_threshold == 0) begin
            if (global_cnt < NEAR_ZONE_END_SAMPLES) 
                dynamic_thresh = base_threshold << 1;
            else 
                dynamic_thresh = base_threshold;
        end 
        else begin
            dynamic_thresh = corr_threshold;
        end
    end

    // ============================================================
    // 7. 峰值捕捉
    // ============================================================
    reg [2:0]  width_cnt;
    reg [17:0] max_peak_r;
    
    localparam MIN_WIDTH = 3'd3;

    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) begin
            echo_tof   <= 0;
            echo_peak  <= 0;
            max_peak_r <= 0;
            hit_flag   <= 0;
            width_cnt  <= 0;
        end
        else if (sys_start_pulse) begin
            max_peak_r <= 0;
            hit_flag   <= 0;
            width_cnt  <= 0;
            echo_tof   <= 0;
        end
        else if (fifo_data_valid) begin // 仅在数据有效时逻辑生效
            if (global_cnt > BLIND_WINDOW_SAMPLES) begin
                
                if (abs_sum > dynamic_thresh) begin
                    if (width_cnt < 3'd7) width_cnt <= width_cnt + 1;
                end
                else begin
                    width_cnt <= 0;
                end

                if (abs_sum > max_peak_r && width_cnt >= MIN_WIDTH) begin
                    max_peak_r <= abs_sum;
                    echo_peak  <= abs_sum;
                    echo_tof   <= global_cnt; // 记录样本索引
                    hit_flag   <= 1'b1;
                end
            end
        end
    end
    // ============================================================
    // 8. 处理完成信号生成 (修正版)
    // ============================================================
    
    // 设定一个合理的停止计数，例如 2000 (需大于实际回波窗口长度)
    // 假设 AD 采样率为 3MHz，10ms 周期内最多有 30000 个点，
    // 但通常我们只需要处理前几千个点（取决于最大测量距离）。
    localparam PROCESS_END_COUNT = 16'd8000; // 采集点数阈值，需根据实际情况调整

    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) begin
            processing_done <= 1'b0;
        end
        else if (sys_start_pulse) begin
            processing_done <= 1'b0; // 新周期开始，清除完成标志
        end
        else begin
            // 只有当采样点计数器超过设定值，才认为本轮处理结束
            // 这样既避免了起步误触发，也避免了过程中的抖动触发
            if (global_cnt >= PROCESS_END_COUNT) begin
                processing_done <= 1'b1;
            end
            else begin
                processing_done <= 1'b0;
            end
        end
    end

endmodule
