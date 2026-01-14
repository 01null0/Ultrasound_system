`timescale 1ns / 1ps

module tb_UART_RX();

    // ----------------------------------------------------------------
    // 1. 信号定义
    // ----------------------------------------------------------------
    reg         clk_50M;
    reg         rst_n;
    reg         rs232_rx;
    
    wire [23:0] rx_frame_data;
    wire [ 2:0] command;
    wire        frame_valid;

    // ----------------------------------------------------------------
    // 2. 参数定义 (必须与被测模块一致)
    // ----------------------------------------------------------------
    parameter CLK_FREQ   = 50_000_000;
    parameter BAUD_RATE  = 19200;
    
    // 计算每一位的持续时间 (单位: ns)，用于仿真发送
    // 1秒 / 19200 ≈ 52083 ns
    localparam BIT_PERIOD_NS = 1_000_000_000 / BAUD_RATE;

    // ----------------------------------------------------------------
    // 3. 实例化被测模块 (DUT)
    // ----------------------------------------------------------------
    UART_RX #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) u_UART_RX (
        .clk_50M      (clk_50M),
        .rst_n        (rst_n),
        .rs232_rx     (rs232_rx),
        .rx_frame_data(rx_frame_data),
        .command      (command),
        .frame_valid  (frame_valid)
    );
        wire [7:0] debug_byte_0=u_UART_RX.data_buf[0];
    wire [7:0] debug_byte_1= u_UART_RX.data_buf[1];
    wire [7:0] debug_byte_2= u_UART_RX.data_buf[2];

    // ----------------------------------------------------------------
    // 4. 时钟生成 (50MHz => 周期 20ns)
    // ----------------------------------------------------------------
    initial clk_50M = 0;
    always #10 clk_50M = ~clk_50M;

    // ----------------------------------------------------------------
    // 5. UART 发送任务 (模拟串口发送一个字节)
    // ----------------------------------------------------------------
    task uart_send_byte;
        input [7:0] send_data;
        integer i;
        begin
            // 1. 发送起始位 (拉低)
            rs232_rx = 1'b0;
            #(BIT_PERIOD_NS); 
            
            // 2. 发送8位数据 (低位先发)
            for (i = 0; i < 8; i = i + 1) begin
                rs232_rx = send_data[i];
                #(BIT_PERIOD_NS);
            end
            
            // 3. 发送停止位 (拉高)
            rs232_rx = 1'b1;
            #(BIT_PERIOD_NS);
        end
    endtask

    // ----------------------------------------------------------------
    // 6. 主测试流程
    // ----------------------------------------------------------------
    initial begin
        // --- 初始化 ---
        rst_n = 0;
        rs232_rx = 1; // 串口空闲状态为高电平
        #200;
        rst_n = 1;
        #200;

        // --- 测试用例 1: 发送完整的一帧 ---
        // 格式: [ 0x12 0x34 0x05 ]
        // 期望结果: rx_frame_data = 123405, command = 5, frame_valid 产生脉冲
        
        $display("Time: %t, Start sending Frame 1...", $time);
        
        uart_send_byte(8'h5B); // 发送 '[' (帧头)
        uart_send_byte(8'h12); // Data 1
        uart_send_byte(8'h34); // Data 2
        uart_send_byte(8'h05); // Data 3 (最后3位是 101 => command=5)
        uart_send_byte(8'h5D); // 发送 ']' (帧尾)

        // 等待一段时间，让接收模块处理完成
        #1000; 

        // --- 测试用例 2: 发送另一帧 ---
        // 格式: [ 0xAA 0xBB 0xF2 ] 
        // 0xF2 = 1111_0010, 最低3位是 010 => command = 2
        
        $display("Time: %t, Start sending Frame 2...", $time);
        
        uart_send_byte(8'h5B); // '['
        uart_send_byte(8'hAA); 
        uart_send_byte(8'hBB); 
        uart_send_byte(8'hF2); 
        uart_send_byte(8'h5D); // ']'

        #5000;
        
        // --- 测试结束 ---
        $display("Simulation Finished.");
        $stop;
    end

endmodule
