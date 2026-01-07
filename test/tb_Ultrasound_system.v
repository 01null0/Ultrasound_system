`timescale 1ns / 1ps

module tb_Ultrasound_system;

    // ============================================================
    // 1. 信号定义
    // ============================================================
    reg         clk_50M;
    reg         rst_n;
    reg         TBS_in;  // 输入：TBS 协议命令
    reg         ad_in;  // 输入：模拟 AD7352 的串行数据输出 (SDATA)
    reg  [17:0] corr_threshold;
    // 输出信号
    wire        TBS_out;
    wire        ad_cs;
    wire        ad_clk;
    wire        relay;
    wire VIN_1, VIN_2, VIN_3, VIN_4;

    // ============================================================
    // 2. 参数定义
    // ============================================================
    parameter CLK_FREQ = 50_000_000;
    parameter BAUD_RATE = 115200;
    parameter BIT_PERIOD = 1000000000 / BAUD_RATE;  // ~8680ns
    parameter PULSE_WIDTH = BIT_PERIOD / 8;  // TBS 窄脉冲宽度

    // ============================================================
    // 3. 实例化顶层模块
    // ============================================================
    Ultrasound_system u_dut (
        .clk_50M       (clk_50M),
        .rst_n         (rst_n),
        .TBS_in        (TBS_in),
        .ad_in         (ad_in),
        .corr_threshold(corr_threshold),
        .TBS_out       (TBS_out),
        .ad_cs         (ad_cs),
        .ad_clk        (ad_clk),
        .relay         (relay),
        .VIN_1         (VIN_1),
        .VIN_2         (VIN_2),
        .VIN_3         (VIN_3),
        .VIN_4         (VIN_4)
    );

    // ============================================================
    // 4. 【关键修正】重定义 Order_4s 参数以加速仿真
    //    将秒级/毫秒级参数缩小，以便在短时间内观察到完整的 AD 采集过程
    // ============================================================
    // 4秒 -> 改为 1ms (足够长即可)
    // defparam u_dut.inst4_Order_4s.Time_4s = 32'd50_000;

    // // 10ms -> 改为 200us (10000个时钟)，缩短初始等待时间
    // defparam u_dut.inst4_Order_4s.Time_10ms = 19'd10_000;

    // // 6ms -> 改为 100us (5000个时钟)，AD 采样窗口长度
    // defparam u_dut.inst4_Order_4s.Time_6ms = 19'd5_000;

    // // 3ms -> 改为 50us (2500个时钟)，缩短盲区等待时间
    // defparam u_dut.inst4_Order_4s.Time_3ms = 19'd2_500;

    // // 1us -> 改为 50个时钟 (保持 1MHz 采样率不变，保证 SPI 时序正确)
    // defparam u_dut.inst4_Order_4s.Time_1us = 16'd50;

    // ============================================================
    // 5. 信号探针 (Debug Signals)
    // ============================================================
    wire [ 2:0] debug_command = u_dut.inst3_UART_RX.command;
    wire [ 2:0] debug_uart_state = u_dut.inst3_UART_RX.state;
    //Order_4S 状态
    wire        debug_Exc_start = u_dut.inst4_Order_4s.Exc_start;
    wire [ 2:0] debug_current_state = u_dut.inst4_Order_4s.current_state;
    // 观察 AD 采样到的数据
    wire [11:0] debug_ad_out_data = u_dut.inst9_AD.ad_out;
    wire        debug_ad_done = u_dut.inst9_AD.ad_done;
    //自相关数据
    wire [11:0] debug_fifo_q = u_dut.inst_Echo_Correlation.fifo_q;
    wire [19:0] debug_echo_tof = u_dut.inst_Echo_Correlation.echo_tof;
    wire [19:0] debug_global_cnt = u_dut.inst_Echo_Correlation.global_cnt;

    //wire debug_c0=u_dut.inst6_pll.c0;

    // ============================================================
    // 6. 时钟生成
    // ============================================================
    initial begin
        clk_50M = 0;
        forever #10 clk_50M = ~clk_50M;  // 20ns 周期 (50MHz)
    end

    // ============================================================
    // 7. 任务：发送 TBS 命令
    // ============================================================
    task send_tbs_byte;
        input [7:0] data;
        integer k;
        begin
            // Start Bit (Low Pulse)
            TBS_in = 0;
            #(PULSE_WIDTH);
            TBS_in = 1;
            #(BIT_PERIOD - PULSE_WIDTH);
            // Data Bits (LSB First)
            for (k = 0; k < 8; k = k + 1) begin
                if (data[k] == 1'b0) begin
                    TBS_in = 0;
                    #(PULSE_WIDTH);
                    TBS_in = 1;
                    #(BIT_PERIOD - PULSE_WIDTH);
                end
                else begin
                    TBS_in = 1;
                    #(BIT_PERIOD);
                end
            end
            // Stop Bit
            TBS_in = 1;
            #(BIT_PERIOD);
            // Inter-frame gap
            #(BIT_PERIOD * 2);
        end
    endtask

    // ============================================================
    // 8. AD7352 行为模型 (读取 ad_data.hex 并发送)
    // ============================================================

    // 定义足够大的内存来存储 hex 文件数据
    reg     [11:0] ad_memory     [0:32767];
    integer        ad_index = 0;

    // 移位寄存器：16位 (2 Leading Zeros + 12 Data + 2 Trailing Zeros)
    reg     [15:0] spi_shift_reg;

    // 初始化：读取 hex 文件
    initial begin
        // 注意：请确保 ad_data.hex 在仿真器的工作目录中
        // 如果仿真报错找不到文件，请尝试使用绝对路径，例如 "D:/FPGA_Project/ad_data.hex"
        $readmemh("E:/pythonProject1/ad_data.hex", ad_memory);
        ad_in = 1'b0;
    end

    // 状态机：在 CS 下降沿加载下一个数据x
    // 添加这段逻辑：在系统产生启动脉冲（T0）时，强制复位读取索引
    always @(posedge u_dut.inst4_Order_4s.sys_start_pulse) begin
        ad_index = 0;
        $display("[%0t] AD Simulation Model: Reset ad_index to 0 (New Cycle Start)", $time);
    end


    // 【新增逻辑】在 CS 下降沿（传输开始）加载当前索引的数据到移位寄存器
    always @(negedge ad_cs) begin
        // 构造 16 位数据帧：2位前导0 + 12位数据 + 2位后缀0
        // AD7352 需要 16 个时钟周期，数据位在中间
        if (ad_index < 32768) begin
            // 这里的格式 {2'b00, data, 2'b00} 对应 AD.v 中的接收逻辑
            spi_shift_reg <= {2'b00, ad_memory[ad_index], 2'b00};

            // 准备下一次读取的索引
            ad_index <= ad_index + 1;
        end
        else begin
            spi_shift_reg <= 16'd0;  // 数据读完后发送 0
        end

        $display("[%0t] AD Model: Loaded Data[%0d] = %h", $time, ad_index, ad_memory[ad_index]);
    end


    // 串行移位输出 (SPI Slave)
    // AD7352 在 SCLK 下降沿改变数据，FPGA (Master) 在 SCLK 上升沿采样
    // 这里的 ad_clk 由 FPGA 的 AD.v 产生
    always @(negedge ad_clk) begin
        if (!ad_cs) begin
            // 输出最高位
            ad_in <= spi_shift_reg[15];
            // 左移
            spi_shift_reg <= {spi_shift_reg[14:0], 1'b0};
        end
        else begin
            ad_in <= 1'b0;
        end
    end

    // ============================================================
    // 9. 主测试流程
    // ============================================================
    initial begin
        // --- 初始化 ---
        rst_n = 1;
        TBS_in = 1;
        ad_index = 0;
        //设置阈值为 3500
        corr_threshold = 18'd3500;

        // --- 复位 & 等待 PLL 稳定 ---
        #200;
        rst_n = 0;
        #200;
        rst_n = 1;
        #1000;

        $display("==================================================");
        $display("Simulation Start: Ultrasound System");
        $display("Data Source: ad_data.hex");
        $display("Simulating 10ms cycle...");
        $display("==================================================");

        // ========================================================
        // 阶段 1: 发送启动命令 0x01
        // ========================================================
        $display("[%0t] Sending Command 0x01 (System Start)...", $time);
        send_tbs_byte(8'h01);

        // 等待命令解析完成
        wait (debug_command == 3'h1);
        $display("[%0t] Command Received. System Starting...", $time);

        // ========================================================
        // 阶段 2: 运行 10ms 周期
        // ========================================================
        // 此时 Order_4s 进入 SYS_START -> WAIT_10MS
        // 随后进入 PULSE_GEN (发射超声波) -> WAIT_1MS -> AD_SAMPLING
        // 在 AD_SAMPLING 阶段，ad_cs 将会不断翻转，读取 ad_data.hex 中的数据

        // 我们运行足够长的时间 (12ms) 以覆盖整个 10ms 周期及后续处理
        #12_000_000;

        // $display("==================================================");
        // $display("[%0t] Simulation Finished.", $time);
        // $display("Please check waveform for 'ad_in', 'ad_cs' and 'debug_ad_out_data'.");
        // $display("==================================================");
        // $stop;
    end

endmodule
