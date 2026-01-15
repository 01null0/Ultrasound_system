`timescale 1ns / 1ns

module tb_Ultrasound_system;

    // ============================================================
    // 1. 信号定义
    // ============================================================
    reg  clk_50M;
    reg  rst_n;
    reg  TBS_in;  // 输入：TBS 协议命令
    reg  ad_in;  // 输入：模拟 AD7352 的串行数据输出 (SDATA)
    reg  corr_threshold;

    // 输出信号
    wire TBS_out;
    wire ad_cs;
    wire ad_clk;
    wire relay;
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
        .corr_threshold(corr_threshold),
        .TBS_in        (TBS_in),
        .ad_in         (ad_in),
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
    // 4. 参数配置 (已按要求恢复原速)
    // ============================================================
    // 注意：您要求保持原速度，因此注释掉加速代码。
    // 在真实硬件速度下，Order_4s 可能会等待 4秒 才开始或重复，
    // 仿真跑 4秒 对应的 CPU 时间可能非常长（数小时甚至更久）。

    // defparam u_dut.inst4_Order_4s.Time_4s   = 32'd50_000; 
    // defparam u_dut.inst4_Order_4s.Time_10ms = 19'd10_000; 
    // defparam u_dut.inst4_Order_4s.Time_6ms  = 19'd5_000;  
    // defparam u_dut.inst4_Order_4s.Time_3ms  = 19'd2_500;  
    // defparam u_dut.inst4_Order_4s.Time_1us  = 16'd50;     

    // ============================================================
    // 5. 信号探针 (Debug Signals)
    // ============================================================
    // UART RX 相关
    wire [ 2:0] debug_command = u_dut.inst3_UART_RX.command;
    wire [ 2:0] debug_uart_state = u_dut.inst3_UART_RX.state;
    wire [23:0] debug_rx_frame_data = u_dut.inst3_UART_RX.rx_frame_data;
    // Order_4S 状态
    wire        debug_Exc_start = u_dut.inst4_Order_4s.Exc_start;
    wire [ 2:0] debug_current_state = u_dut.inst4_Order_4s.current_state;
    // AD 数据
    wire [11:0] debug_ad_out_data = u_dut.inst9_AD.ad_out;
    wire        debug_ad_done = u_dut.inst9_AD.ad_done;
    // 结果数据
    wire [19:0] debug_echo_tof = u_dut.inst_Echo_Correlation.echo_tof;
    wire        debug_processing_done = u_dut.inst_Echo_Correlation.processing_done;

    // ============================================================
    // 6. 时钟生成
    // ============================================================
    initial begin
        clk_50M = 0;
        forever #10 clk_50M = ~clk_50M;  // 20ns 周期 (50MHz)
    end

    // ============================================================
    // 7. 任务：发送 TBS/UART 字节
    // ============================================================
    task send_tbs_byte;
        input [7:0] data;
        integer k;
        begin
            // 1. 发送 Start Bit (TBS协议: 窄低脉冲)
            TBS_in = 0;
            #(PULSE_WIDTH);
            TBS_in = 1;
            #(BIT_PERIOD - PULSE_WIDTH);

            // 2. 发送 8位数据 (LSB First)
            for (k = 0; k < 8; k = k + 1) begin
                if (data[k] == 1'b0) begin  // 发送 '0'
                    TBS_in = 0;
                    #(PULSE_WIDTH);
                    TBS_in = 1;
                    #(BIT_PERIOD - PULSE_WIDTH);
                end
                else begin  // 发送 '1'
                    TBS_in = 1;
                    #(BIT_PERIOD);
                end
            end

            // 3. Stop Bit (High)
            TBS_in = 1;
            #(BIT_PERIOD);

            // 4. 字节间隙
            #(BIT_PERIOD * 4);
        end
    endtask

    // ============================================================
    // 8. AD7352 行为模型
    // ============================================================
    reg     [11:0] ad_memory     [0:32767];
    integer        ad_index = 0;
    reg     [15:0] spi_shift_reg;

    // 【关键修改】将 integer i 移到这里，解决 "unnamed block" 报错
    integer        i;

    initial begin

        corr_threshold = 12'd5000;
        // 初始化测试数据：简单的斜坡数据
        // 如果您有真实的 ad_data.hex，可以取消下面的注释
        $readmemh("E:/pythonProject1/ad_data.hex", ad_memory);

        // for (i=0; i<32768; i=i+1) begin
        //     ad_memory[i] = i % 4096; 
        // end

        ad_in = 1'b0;
    end

    // 每次系统启动脉冲复位索引
    always @(posedge u_dut.inst4_Order_4s.sys_start_pulse) begin
        ad_index = 0;
        $display("[%0t] AD Simulation Model: Reset ad_index to 0", $time);
    end

    // CS 下降沿加载数据
    always @(negedge ad_cs) begin
        if (ad_index < 32768) begin
            spi_shift_reg <= {2'b00, ad_memory[ad_index], 2'b00};
            ad_index <= ad_index + 1;
        end
        else begin
            spi_shift_reg <= 16'd0;
        end
    end

    // SPI 输出逻辑
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
    // 9. 主测试流程 (5字节协议 + 真实速度)
    // ============================================================
    initial begin
        // --- 初始化 ---
        rst_n  = 1;
        TBS_in = 1;

        // --- 复位 ---
        #200;
        rst_n = 0;
        #200;
        rst_n = 1;
        #1000;

        // $display("==================================================");
        // $display("Simulation Start: Ultrasound System (Real-Time Mode)");
        // $display("Note: Simulation may take a LONG time due to 4s delay.");
        // $display("==================================================");

        // ========================================================
        // 阶段 1: 发送 5字节 启动帧
        // 协议: [ (0x5B) + D1(00) + D2(00) + D3(01) + ] (0x5D)
        // ========================================================
        $display("[%0t] Sending Frame Header '[' (0x5B)...", $time);
        send_tbs_byte(8'h5B);

        $display("[%0t] Sending Data Byte 1 (0x00)...", $time);
        send_tbs_byte(8'h00);

        $display("[%0t] Sending Data Byte 2 (0x00)...", $time);
        send_tbs_byte(8'h00);

        $display("[%0t] Sending Data Byte 3 (0x01) -> Command 1...", $time);
        send_tbs_byte(8'h01);

        $display("[%0t] Sending Frame Tail ']' (0x5D)...", $time);
        send_tbs_byte(8'h5D);

        // ========================================================
        // 阶段 2: 等待系统响应
        // ========================================================

        // 等待命令解析
        wait (debug_command == 3'h1);
        //$display("[%0t] Command 1 Received! Waiting for System Reaction...", $time);

        // 由于是真实速度，我们只需观察启动后的一段时间。
        // 如果 Order_4s 逻辑是 "先等待4s再发射"，这里可能要等很久。
        // 如果是 "先发射再等待"，您将很快看到 VIN 信号变化。

        // 这里设置一个较大的超时时间 (20ms)，足以覆盖发射和AD采样过程
        // 如果您确实想跑完 4秒 周期，请将此处改为 #4_000_000_000 (不推荐)
        #20_000_000;

        //$display("==================================================");
        //$display("[%0t] Simulation Finished (Timeout).", $time);
        $stop;
    end

endmodule
