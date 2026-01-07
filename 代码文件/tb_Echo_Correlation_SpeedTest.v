`timescale 1ns/1ns

module tb_Echo_Correlation_SpeedTest;

    // ==========================================
    // 1. 核心配置参数 (在此处修改以测试不同深度)
    // ==========================================
    parameter CLK_PERIOD      = 20;     // 50MHz (20ns)
    parameter TEST_DATA_DEPTH = 20000;  // 【修改这里】设置要测试的数据量 (例如 2000, 10000, 50000)
    
    // Hex文件路径 (请根据实际情况修改)
    parameter HEX_FILE_PATH   = "E:/pythonProject1/ad_data.hex"; 

    // ==========================================
    // 2. 信号定义
    // ==========================================
    reg clk_50M;
    reg rst_n;
    reg sys_start_pulse;

    // FIFO 接口
    reg  [11:0] fifo_data_in;
    reg         fifo_wrreq;
    wire        fifo_rdreq;
    wire [11:0] fifo_q;
    wire        fifo_empty;
    
    // DUT 输出
    reg  [17:0] corr_threshold;
    wire [19:0] echo_tof;
    wire [17:0] echo_peak;
    wire        hit_flag;
    wire        processing_done;

    // 存储器与变量
    reg [11:0] mem_data [0:100000]; // 确保这个数组够大，能装下您的Hex文件
    integer i;
    
    // 计时统计变量
    time start_time;
    time end_time;
    integer process_cycles;

    // ==========================================
    // 3. 模块实例化
    // ==========================================
    
    // 3.1 FIFO (使用您工程中的 FIFO)
    fifo u_fifo (
        .data    (fifo_data_in),
        .wrclk   (clk_50M),
        .wrreq   (fifo_wrreq),
        .rdclk   (clk_50M),
        .rdreq   (fifo_rdreq),
        .q       (fifo_q),
        .rdempty (fifo_empty)
    );

    // 3.2 被测模块 (DUT)
    Echo_Correlation uut (
        .clk_50M         (clk_50M), 
        .rst_n           (rst_n), 
        .sys_start_pulse (sys_start_pulse), 
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
    // 5. 性能监控逻辑 (独立进程)
    // ==========================================
    
    // 监控处理开始 (当 FIFO 第一次被读取时)
    reg measurement_started;
    initial measurement_started = 0;

    always @(posedge clk_50M) begin
        if (fifo_rdreq && !measurement_started) begin
            start_time = $time;
            measurement_started = 1;
            $display("[Time: %t] Processing STARTED.", $time);
        end
    end

    // ==========================================
    // 6. 主测试激励 (全速写入)
    // ==========================================
    initial begin
        // --- 初始化 ---
        rst_n = 0;
        sys_start_pulse = 0;
        fifo_wrreq = 0;
        fifo_data_in = 0;
        corr_threshold = 18'd4500; // 设置阈值
        
        // --- 加载数据 ---
        // 注意：请确保 Hex 文件中的数据量 >= TEST_DATA_DEPTH
        $readmemh(HEX_FILE_PATH, mem_data);
        $display("--------------------------------------------------");
        $display("Test Configuration:");
        $display("  Data Depth: %d samples", TEST_DATA_DEPTH);
        $display("  Clock Freq: 50 MHz");
        $display("--------------------------------------------------");

        // --- 复位释放 ---
        #100;
        rst_n = 1;
        #100;
        
        // --- 发送 Start Pulse (清零内部计数器) ---
        @(posedge clk_50M);
        sys_start_pulse = 1;
        @(posedge clk_50M);
        sys_start_pulse = 0;
        
        // 等待几个周期
        repeat(5) @(posedge clk_50M);

        // --- 【关键】全速写入循环 ---
        $display("[Time: %t] Starting FAST WRITE to FIFO...", $time);
        
        for (i = 0; i < TEST_DATA_DEPTH; i = i + 2) begin 
            // 准备数据
            fifo_data_in = mem_data[i]; // 假设hex文件是连续存储的
            fifo_wrreq = 1;
            
            // 每个时钟周期写入一个数据！不等待！
            @(posedge clk_50M); 
        end
        
        // 停止写入
        fifo_wrreq = 0;
        fifo_data_in = 0;
        $display("[Time: %t] Fast Write COMPLETED. Waiting for DUT to finish...", $time);

        // --- 等待 FIFO 被取空 ---
        // 只要 FIFO 非空，或者 DUT 还在输出有效标志（如果有延迟），就等待
        // 这里的 fifo_empty 是最直接的判据
        wait(fifo_empty == 1);
        
        // 再额外等待一小段时间，确保流水线走完（比如 100个周期）
        repeat(100) @(posedge clk_50M);
        
        end_time = $time;
        
        // --- 输出统计结果 ---
        $display("--------------------------------------------------");
        $display("PERFORMANCE REPORT");
        $display("--------------------------------------------------");
        $display("Samples Processed : %d", TEST_DATA_DEPTH);
        $display("Total Time Taken  : %t ns", end_time - start_time);
        
        process_cycles = (end_time - start_time) / CLK_PERIOD;
        $display("Total Clock Cycles: %d", process_cycles);
        
        // 计算平均速度
        // 理想情况下应该是 1 cycle/sample
        $display("Average Speed     : %0.2f cycles/sample", (process_cycles * 1.0) / TEST_DATA_DEPTH);
        $display("--------------------------------------------------");

        if (hit_flag)
            $display("RESULT: Hit DETECTED at Index %d, Peak %d", echo_tof, echo_peak);
        else
            $display("RESULT: No Hit Detected.");

        $stop;
    end

endmodule
