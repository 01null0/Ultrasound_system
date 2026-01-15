`timescale 1ns / 1ns

module tb_Ultrasound_system;

    // ============================================================
    // 1. 信号定义
    // ============================================================
    reg         clk_50M;
    reg         rst_n;
    reg         TBS_in;          // 输入：TBS 协议脉冲信号
    reg         ad_in;           // 输入：模拟 AD7352 的串行数据输出 (SDATA)
    reg  [17:0] corr_threshold;  // 阈值设置

    // 输出信号
    wire        TBS_out;
    wire        ad_cs;
    wire        ad_clk;
    wire        relay;
    wire VIN_1, VIN_2, VIN_3, VIN_4;

    // ============================================================
    // 2. 参数定义 (修改为 19200 波特率)
    // ============================================================
    parameter CLK_FREQ   = 50_000_000;
    parameter BAUD_RATE  = 19200;                  // 【关键修改】波特率改为 19200
    parameter BIT_PERIOD = 1000000000 / BAUD_RATE; // ~52083ns
    parameter PULSE_WIDTH = BIT_PERIOD / 8;        // TBS 窄脉冲宽度 (约6.5us)

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

    // 【关键修改】强行覆盖子模块的波特率参数，确保仿真模型与 TB 一致
    // 必须覆盖 TBS_RX，否则它无法识别 TB 发送的脉冲宽度
    defparam u_dut.inst2_TBS_RX.BAUD_RATE   = 19200; 
    defparam u_dut.inst3_UART_RX.BAUD_RATE  = 19200;
    defparam u_dut.inst12_UART_TX.BAUD_RATE = 19200;
    defparam u_dut.inst2_TBS_TX.BAUD_RATE   = 19200;

    // ============================================================
    // 5. 信号探针 (Debug Signals)
    // ============================================================
    // 观测 UART_RX 解析出的命令 (应为 1)
    wire [ 2:0] debug_command = u_dut.inst3_UART_RX.command;
    // 观测 UART_RX 是否成功接收到一帧 (5字节)
    wire        debug_frame_valid = u_dut.inst3_UART_RX.frame_valid;
    
    // 观察 AD 采样相关
    wire [11:0] debug_ad_out_data = u_dut.inst9_AD.ad_out;
    wire        debug_ad_done = u_dut.inst9_AD.ad_done;

    // 自相关数据
    wire [19:0] debug_echo_tof = u_dut.inst_Echo_Correlation.echo_tof;
    
    // 串口发送完成标志
    wire debug_processing_done = u_dut.inst12_UART_TX.processing_done; 
    wire debug_rs232_tx = u_dut.inst12_UART_TX.rs232_tx; 

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
    // TBS协议: 发送 '0' 时拉低 TBS_in 一个脉冲宽度，发送 '1' 时保持高电平
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
                if (data[k] == 1'b0) begin
                    // Send Logic 0
                    TBS_in = 0;
                    #(PULSE_WIDTH);
                    TBS_in = 1;
                    #(BIT_PERIOD - PULSE_WIDTH);
                end
                else begin
                    // Send Logic 1
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
    // 【关键修改】任务：发送 5 字节数据帧
    // 帧结构: [0x5B] [Data1] [Data2] [Data3(Cmd)] [0x5D]
    // ============================================================
    task send_tbs_frame;
        input [7:0] cmd_byte; // 只需要传入命令字节，其他填充 0
        begin
            // 1. Frame Head '['
            send_tbs_byte(8'h5B); 
            // 2. Data 1 (Reserved/Zero)
            send_tbs_byte(8'h00);
            // 3. Data 2 (Reserved/Zero)
            send_tbs_byte(8'h00);
            // 4. Data 3 (Contains Command) - 这里放入命令 0x01
            send_tbs_byte(cmd_byte);
            // 5. Frame Tail ']'
            send_tbs_byte(8'h5D);
            
            // 帧间隙
            #(BIT_PERIOD * 5); 
        end
    endtask

    // ============================================================
    // 8. AD7352 行为模型 (读取 ad_data.hex 并发送)
    // ============================================================
    reg     [11:0] ad_memory     [0:32767];
    integer        ad_index = 0;
    reg     [15:0] spi_shift_reg;

    initial begin
        // 请确保路径正确，如果是 Modelsim 仿真，通常放在工程目录下
        // 或者使用绝对路径，例如: "E:/pythonProject1/ad_data.hex"
        $readmemh("ad_data.hex", ad_memory); 
        ad_in = 1'b0;
    end

    // 在系统产生启动脉冲（T0）时，复位读取索引，方便每轮观察
    always @(posedge u_dut.inst4_Order_4s.sys_start_pulse) begin
        ad_index = 0;
    end

    // 在 CS 下降沿加载数据
    always @(negedge ad_cs) begin
        if (ad_index < 32768) begin
            // 构造 16 位数据帧：2位前导0 + 12位数据 + 2位后缀0
            spi_shift_reg <= {2'b00, ad_memory[ad_index], 2'b00};
            ad_index <= ad_index + 1;
        end
        else begin
            spi_shift_reg <= 16'd0;
        end
    end

    // 串行移位输出 (SPI Slave)
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
        // 设置阈值 (示例值 3500)
        corr_threshold = 18'd3500;

        // --- 复位 & 等待 PLL 稳定 ---
        #200;
        rst_n = 0;
        #200;
        rst_n = 1;
        #1000;

        // ========================================================
        // 阶段 1: 发送启动命令帧 (命令 0x01)
        // ========================================================
        $display("Sending Start Command Frame (5 Bytes)...");
        
        // 【关键修改】调用新任务发送 5 字节帧
        send_tbs_frame(8'h01);

        // 等待帧解析完成 (检测 UART_RX 输出的 valid 信号和命令值)
        wait (debug_frame_valid == 1'b1);
        
        if (debug_command == 3'h1)
            $display("System Started Successfully! (Command 0x01 received)");
        else
            $display("Error: Incorrect command received: %h", debug_command);
        
        // ========================================================
        // 阶段 2: 运行 10ms 周期
        // ========================================================
        // 此时 Order_4s 应该进入 PULSE_GEN -> AD_SAMPLING
        // 观察 ad_cs 是否开始翻转，VIN_1 是否有激励波形
        
        // 运行足够长的时间 (15ms) 以覆盖整个 10ms 周期及后续串口上传
        #15_000_000;

        $display("Simulation Finished.");
        $stop;
    end

endmodule
