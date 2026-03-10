`timescale 1ns / 1ns

module tb_Ultrasound_system;

    // ============================================================
    // 1. 信号定义
    // ============================================================
    reg  clk_50M;
    reg  rst_n;
    reg  TBS_in;  // 输入：TBS 协议脉冲信号
    reg  ad_in;  // 输入：模拟 AD7352 的串行数据输出 (SDATA)

    // 输出信号
    wire TBS_out;
    wire ad_cs;
    wire ad_clk;
    wire relay;
    wire VIN_1, VIN_2, VIN_3, VIN_4;

    // ============================================================
    // 2. 参数定义 (保持 19200 波特率)
    // ============================================================
    parameter CLK_FREQ = 50_000_000;
    parameter BAUD_RATE = 19200;
    parameter BIT_PERIOD = 1000000000 / BAUD_RATE;  // ~52083ns
    parameter PULSE_WIDTH = BIT_PERIOD / 8;  // TBS 窄脉冲宽度

    // ============================================================
    // 3. 实例化顶层模块
    // ============================================================
    Ultrasound_system u_dut (
        .clk_50M(clk_50M),
        .rst_n  (rst_n),
        .TBS_in (TBS_in),
        .ad_in  (ad_in),
        .TBS_out(TBS_out),
        .ad_cs  (ad_cs),
        .ad_clk (ad_clk),
        .relay  (relay),
        .VIN_1  (VIN_1),
        .VIN_2  (VIN_2),
        .VIN_3  (VIN_3),
        .VIN_4  (VIN_4)
    );

    // ============================================================
    // 4. 【关键修改】加速仿真参数覆盖
    // ============================================================


    // 1. ACK 模块参数
    defparam u_dut.inst_Ack_Ctl.WAIT_TIME_MS = 1;

    // // 2. Order_4s 模块参数 (必须成套修改!)

    // // (A) 周期长度：从 500,000 -> 150,000 (约3ms)
    // defparam u_dut.inst4_Order_4s.Time_10ms = 19'd150_000;

    // // (B) 采样结束点：原 325,000 (6.5ms) -> 必须小于 150,000
    // //     设置为 100,000 (约2ms处结束采样)
    // defparam u_dut.inst4_Order_4s.Time_6_5ms = 19'd100_000;

    // // (C) 采样开始点：原 40,000 (800us) -> 稍微减小一点以保持比例
    // //     设置为 20,000 (约0.4ms处开始采样)
    // defparam u_dut.inst4_Order_4s.Time_800us = 19'd20_000;

    // // 3. 总工作时间
    // defparam u_dut.inst4_Order_4s.Time_4s = 32'd2_000_000;

    // ============================================================
    // 5. 信号探针 (Debug Signals)
    // ============================================================
    // 观测 UART_RX 解析出的命令
    // 注意：现在 UART_RX 的输出连接到了 cmd_from_rx，但这里依然可以观测模块内部
    wire [ 2:0] debug_command = u_dut.inst3_UART_RX.command;
    wire        debug_frame_valid = u_dut.inst3_UART_RX.frame_valid;

    // 【新增】观测实际汇总后的串口发送线 (包含 ACK 和 数据)
    wire        debug_tx_line = u_dut.rs232_tx_line;

    // 观测 AD 采样相关
    wire [11:0] debug_ad_out_data = u_dut.inst9_AD.ad_out;

    // ============================================================
    // 6. 时钟生成
    // ============================================================
    initial begin
        clk_50M = 0;
        forever #10 clk_50M = ~clk_50M;  // 20ns 周期 (50MHz)
    end

    // ============================================================
    // 7. 任务：发送 TBS 单字节 (底层物理层)
    // ============================================================
    task send_tbs_byte;
        input [7:0] data;
        integer k;
        begin
            // Start Bit (Low Pulse -> Logic 0)
            TBS_in = 0;
            #(PULSE_WIDTH);
            TBS_in = 1;
            #(BIT_PERIOD - PULSE_WIDTH);

            // Data Bits (LSB First)
            for (k = 0; k < 8; k = k + 1) begin
                if (data[k] == 1'b0) begin  // Logic 0
                    TBS_in = 0;
                    #(PULSE_WIDTH);
                    TBS_in = 1;
                    #(BIT_PERIOD - PULSE_WIDTH);
                end
                else begin  // Logic 1
                    TBS_in = 1;
                    #(BIT_PERIOD);
                end
            end

            // Stop Bit (Logic 1)
            TBS_in = 1;
            #(BIT_PERIOD);
        end
    endtask

    // ============================================================
    // 任务：发送 5 字节数据帧
    // ============================================================
    task send_tbs_frame;
        input [7:0] cmd_byte;
        begin
            send_tbs_byte(8'h5B);  // Head
            send_tbs_byte(8'h40);
            send_tbs_byte(8'h40);
            send_tbs_byte(cmd_byte);  // Command
            send_tbs_byte(8'h5D);  // Tail
            #(BIT_PERIOD * 5);
        end
    endtask

    // ============================================================
    // 8. AD7352 行为模型
    // ============================================================
    reg     [11:0] ad_memory     [0:32767];
    integer        ad_index = 0;
    reg     [15:0] spi_shift_reg;

    initial begin
        // 使用相对路径或绝对路径，请根据实际环境修改
        // $readmemh("ad_data.hex", ad_memory); 
        $readmemh("E:/pythonProject1/ad_data.hex", ad_memory);
        ad_in = 1'b0;
    end

    // T0 时刻复位索引
    always @(posedge u_dut.inst4_Order_4s.sys_start_pulse) begin
        ad_index = 0;
    end

    // AD 模拟逻辑
    always @(negedge ad_cs) begin
        if (ad_index < 32768) begin
            spi_shift_reg <= {2'b00, ad_memory[ad_index], 2'b00};
            ad_index <= ad_index + 1;
        end
        else begin
            spi_shift_reg <= 16'd0;
        end
    end

    always @(negedge ad_clk) begin
        if (!ad_cs) begin
            ad_in <= spi_shift_reg[15];
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

        #200;
        rst_n = 0;
        #200;
        rst_n = 1;
        #1000;

        // ========================================================
        // 阶段 1: 发送启动命令帧 (命令 0x03)
        // ========================================================
        // 注意：原代码发的是 0x43 (0100 0011)，低3位是 011 (3)
        // 这对应 "井径测量模式" 或 "启动" (取决于 Order_4s 定义)
        // 根据之前的沟通，0x03 是启动命令。
        $display("[%t] Sending Start Command (0x03)...", $time);
        send_tbs_frame(8'h43);

        // 等待 UART_RX 解析
        wait (debug_frame_valid == 1'b1);
        #1000;
        if (debug_command == 3'h3) $display("[%t] Command 0x03 Received by UART_RX.", $time);
        else $display("[%t] Error: Received %h", $time, debug_command);

        // ========================================================
        // 阶段 2: 观察 ACK 应答 (7B AA AA AA 7D)
        // ========================================================
        $display("[%t] Waiting for ACK (7B AA AA AA 7D)...", $time);

        // 简单观察：等待 TX 线拉低 (Start bit)
        wait (debug_tx_line == 0);
        $display("[%t] ACK Transmission Started.", $time);

        // 等待约 2.6ms (5字节 * 10位 * 52us) 发送完 ACK
        #(BIT_PERIOD * 50);
        $display("[%t] ACK Transmission Finished (Estimated).", $time);

        // ========================================================
        // 阶段 3: 观察 1ms 等待 + 大帧头
        // ========================================================
        // 此时系统处于 1ms 等待期 (由 defparam 加速)
        // 随后 Order_4s 进入 WAIT_10MS (由 defparam 加速为 3ms)
        // 随后 Batch Header (7B 00 00 AA 7D) 发送

        $display("[%t] Waiting for Batch Header...", $time);
        // 等待下一次 TX 拉低 (Batch Header 开始)
        wait (debug_tx_line == 0);
        $display("[%t] Batch Header Transmission Started.", $time);

        // ========================================================
        // 阶段 4: 观察数据回传
        // ========================================================
        // 再运行一段时间，观察 VIN 激励和 AD 数据
        // 由于我们加速了周期 (3ms)，这里运行 10ms 应该能看到 2-3 个数据包
        #10_000_000;

        $display("[%t] Simulation Finished.", $time);
        $stop;
    end

endmodule
