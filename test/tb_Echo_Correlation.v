`timescale 1ns/1ns

module tb_Echo_Correlation;

    // ==========================================
    // 1. 参数定义
    // ==========================================
    parameter CLK_PERIOD = 20;      // 50MHz系统时钟 (20ns)
    // 模拟 ADC 采样率：假设为 1MHz (每50个系统时钟写一次FIFO)
    // 您可以根据实际情况调整写入速度，这不会影响处理结果，因为处理是基于样本计数的
    parameter ADC_WRITE_DELAY = 50; 
    
    parameter DATA_DEPTH = 20000;   // 仿真数据深度

    // ==========================================
    // 2. 信号定义
    // ==========================================
    reg clk_50M;
    reg rst_n;
    reg sys_start_pulse;
    
    // --- FIFO 相关信号 ---
    reg  [11:0] fifo_data_in;   // 写入FIFO的数据 (模拟ADC输出)
    reg         fifo_wrreq;     // FIFO写请求
    wire        fifo_rdreq;     // FIFO读请求 (来自DUT)
    wire [11:0] fifo_q;         // FIFO读出数据 (送给DUT)
    wire        fifo_empty;     // FIFO空标志
    // -------------------

    // --- DUT 配置与输出 ---
    reg  [17:0] corr_threshold;
    wire [19:0] echo_tof;       // 输出：样本索引
    wire [17:0] echo_peak;
    wire        hit_flag;
    wire        processing_done; // 指示FIFO处理完毕

    // 存储器数组 (Hex文件容器)
    reg [11:0] mem_data [0:DATA_DEPTH-1];
    integer i;

    // ==========================================
    // 3. 模块实例化
    // ==========================================

    // (1) 实例化 FIFO (使用您工程中的 project/FIFO/fifo.v)
    // 注意：仿真时需要编译 fifo.v 及其依赖的 Altera 库
    fifo u_fifo (
        .data    (fifo_data_in),
        .wrclk   (clk_50M),      // 模拟写时钟
        .wrreq   (fifo_wrreq),
        
        .rdclk   (clk_50M),      // 系统读时钟
        .rdreq   (fifo_rdreq),
        .q       (fifo_q),
        .rdempty (fifo_empty)
    );

    // (2) 实例化被测模块 (Echo_Correlation_FIFO)
    Echo_Correlation uut (
        .clk_50M         (clk_50M), 
        .rst_n           (rst_n), 
        .sys_start_pulse (sys_start_pulse), 
        
        // FIFO 接口连接
        .fifo_q          (fifo_q),
        .fifo_empty      (fifo_empty),
        .fifo_rdreq      (fifo_rdreq),
        
        .corr_threshold  (corr_threshold), 
        .echo_tof        (echo_tof), 
        .echo_peak       (echo_peak), 
        .hit_flag        (hit_flag),
        .processing_done (processing_done)
    );

    // ==========================================
    // 4. 时钟生成
    // ==========================================
    initial clk_50M = 0;
    always #(CLK_PERIOD/2) clk_50M = ~clk_50M;

    // ==========================================
    // 5. 主测试激励
    // ==========================================
    initial begin
        // --- 初始化 ---
        rst_n = 0;
        sys_start_pulse = 0;
        fifo_wrreq = 0;
        fifo_data_in = 0;
        
        // 建议阈值 (根据您的Hex数据调整)
        corr_threshold = 18'd4500; 

        // --- 加载数据 ---
        // 保持您原来的 hex 文件路径不变
        $readmemh("E:/pythonProject1/ad_data.hex", mem_data);
        $display("Data loaded from ad_data.hex");

        // --- 复位释放 ---
        #100;
        rst_n = 1;
        #100;

        // --- 发送系统启动脉冲 ---
        // 这会清零模块内的峰值记录和计数器
        @(posedge clk_50M);
        sys_start_pulse = 1;
        @(posedge clk_50M);
        sys_start_pulse = 0;

        $display("Starting to fill FIFO...");

        // --- 模拟 ADC 数据写入 FIFO ---
        // 循环读取 mem_data 并写入 FIFO
        for (i = 0; i < DATA_DEPTH; i = i + 1) begin // 注意：这里可以是 +1 或 +2，取决于您的数据存储方式
            
            // 1. 准备数据
            fifo_data_in = mem_data[i];
            
            // 2. 产生写请求脉冲
            @(posedge clk_50M);
            fifo_wrreq = 1;
            
            @(posedge clk_50M);
            fifo_wrreq = 0; // 写使能拉低
            
            // 3. 模拟采样间隔
            // 比如 1MHz 采样率，就需要等待约 50 个时钟周期再写下一个
            // 如果您想模拟“先存储后处理”，可以让这个延时非常小，快速把FIFO填满
            repeat(ADC_WRITE_DELAY - 1) @(posedge clk_50M);
            
            // (可选) 打印进度
            if (i % 1000 == 0) $display("Written sample %d to FIFO", i);
        end

        $display("All data written to FIFO.");
        
        // 等待 FIFO 被处理完
        wait(fifo_empty == 1);
        #1000; // 再多等一会儿确保最后的处理完成
        
        $stop;
    end

    // ==========================================
    // 6. 监控输出 (可选)
    // ==========================================
    // always @(posedge clk_50M) begin
    //     if (hit_flag) begin
    //         $display("Hit Detected! Sample Index: %d, Peak: %d", echo_tof, echo_peak);
    //     end
    // end

endmodule
