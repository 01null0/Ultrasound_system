`timescale 1ns/1ns

module tb_Echo;

    // ============================================================
    // 1. 参数定义
    // ============================================================
    parameter CLK_PERIOD = 20;      // 50MHz时钟周期 = 20ns
    parameter AD_SAMPLE_RATE = 50;  // 1MHz采样率 = 50个时钟周期
    parameter DATA_DEPTH = 5000;    // 仿真数据深度

    // ============================================================
    // 2. 信号定义
    // ============================================================
    reg clk_50M;
    reg rst_n;
    
    // 这里的输入对应 Echo.vhd 的顶层输入
    reg sys_start_pulse;    // 【注意】需要在 BDF/VHDL 中补上这个端口
    reg [17:0] corr_threshold; // 【注意】需要在 BDF/VHDL 中补上这个端口
    
    reg ad_valid_in;        // 对应 DSP 的输入 valid
    reg [11:0] ad_data_in;  // 对应 DSP 的输入 data (原始12位)

    // 输出信号
    wire [31:0] echo_tof;
    wire [17:0] echo_peak;
    wire hit_flag;
    wire signed [12:0] debug_clean_data; 
    wire signed [31:0] debug_dsp_sum;    // 查看 DSP 内部累加器的原始值
    
    assign debug_clean_data = uut.dsp_data_wire; 
    assign debug_dsp_sum    = uut.u_dsp.sum;     // 甚至可以直接看子模块的子信号！
    // 存储器数组，用于存放 Hex 数据
    reg [11:0] mem_data [0:DATA_DEPTH-1];
    integer i;

    // ============================================================
    // 3. 实例化被测模块 (Top Level: Echo)
    // ============================================================
    // 注意：如果你的 VHDL 还没有加 start_pulse 和 threshold，这里会报错。
    // 请务必更新你的 VHDL 文件。
    Echo uut (
        .clk_50M(clk_50M), 
        .rst_n(rst_n), 
        
        // 关键控制信号 (必须添加到顶层)
        .sys_start_pulse(sys_start_pulse), 
        .corr_threshold(corr_threshold), 
        // 数据流输入 (喂给 DSP)
        .ad_valid_in(ad_valid_in), 
        .ad_data_in(ad_data_in), 
        
        // 结果输出
        .hit_flag(hit_flag), 
        .echo_peak(echo_peak), 
        .echo_tof(echo_tof)
    );

    // ============================================================
    // 4. 时钟生成
    // ============================================================
    always #(CLK_PERIOD/2) clk_50M = ~clk_50M;

    // ============================================================
    // 5. 主测试过程
    // ============================================================
    initial begin
        // --- 初始化 ---
        clk_50M = 0;
        rst_n = 0;
        sys_start_pulse = 0;
        ad_valid_in = 0;
        ad_data_in = 0;
        
        // 设置阈值：由于经过 FIR 滤波，信号幅值可能变化，
        // 建议先设低一点观察，或者根据 DSP 内部截断后的波形调整
        corr_threshold = 18'd1000; 

        // --- 加载数据文件 ---
        // 路径请根据实际情况修改
        $readmemh("E:/pythonProject1/ad_data.hex", mem_data);
        $display("Data loaded from ad_data.hex");

        // --- 复位释放 ---
        #100;
        rst_n = 1;
        #100;

        // --- 发送系统启动脉冲 (T0时刻) ---
        @(posedge clk_50M);
        sys_start_pulse = 1;
        @(posedge clk_50M);
        sys_start_pulse = 0;

        // --- 开始模拟 AD 数据流 (1MHz) ---
        // 注意：现在我们把数据喂给 Echo 顶层 -> DSP -> Correlation
        for (i = 0; i < 4500; i = i + 1) begin
            // 模拟 AD 转换完成信号
            @(posedge clk_50M);
            ad_valid_in = 1;
            ad_data_in = mem_data[i]; // 送入原始 12位 数据
            
            @(posedge clk_50M);
            ad_valid_in = 0; 

            // 等待下一个采样点
            repeat(AD_SAMPLE_RATE - 2) @(posedge clk_50M);

            // --- 实时打印调试信息 ---
            // 注意：由于 uut 是 VHDL，uut.b2v_inst1 是内部实例
            // ModelSim 中通常支持跨语言层次引用，如果报错请注释掉下面的 display
            /* b2v_inst1 是 Echo.vhd 中实例化的 echo_correlation 的名字
               sum/abs_sum 是 echo_correlation 内部信号
               具体路径名称可能需要根据 ModelSim 的 Objects 窗口确认
            */
             if (hit_flag) begin
                 $display("HIT! Time: %t | Index: %d | Peak: %d | ToF: %d", 
                          $time, i, echo_peak, echo_tof);
             end
        end

        // --- 仿真结束 ---
        #1000;
        $display("Simulation Finished.");
        $display("Final ToF: %d (x20ns)", echo_tof);
        $display("Final Peak: %d", echo_peak);
        $stop;
    end

endmodule