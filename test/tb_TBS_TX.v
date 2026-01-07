`timescale 1ns / 1ps // 定义仿真时间单位为1ns，精度为1ps
module tb_TBS_TX;
    // -- 参数定义 --
    localparam CLK_FREQ    = 50_000_000;
    localparam BAUD_RATE   = 115200;
    localparam CLK_PERIOD  = 1_000_000_000 / CLK_FREQ; // 20ns
    localparam BIT_PERIOD  = 1_000_000_000 / BAUD_RATE; // ~8680ns
    // -- 信号定义 --
    reg clk_50M;
    reg rst_n;
    reg rs232_in; // DUT 输入
    wire TBS_out;  // DUT 输出
    
    //----------------------------------------------------------------
    // 例化待测模块 (DUT)
    //----------------------------------------------------------------
    TBS_TX #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) u_tbs_tx (
        .clk_50M(clk_50M),
        .rst_n(rst_n),
        .rs232_in(rs232_in),
        .TBS_out(TBS_out)
    );
    //----------------------------------------------------------------
    // 1. 时钟和复位激励生成
    //----------------------------------------------------------------
    // 生成时钟
    initial begin
        clk_50M = 0;
        forever #(CLK_PERIOD / 2) clk_50M = ~clk_50M;
    end
    // 生成复位信号和测试主流程
    initial begin
        // 初始化和复位
        rst_n = 1'b0;
        rs232_in = 1'b1; // RS-232 空闲为高
        #200;
        rst_n = 1'b1;
        #200;
        $display("------------------- Simulation Start -------------------");
        
        // 调用任务，发送测试数据
        send_rs232_byte(8'h55); // 发送 01010101
        send_rs232_byte(8'hA3); // 发送 10100011
        send_rs232_byte(8'h01); // 发送 00000001
        send_rs232_byte(8'h06); // 发送 00000110
        send_rs232_byte(8'h0B); // 发送 00001100
        send_rs232_byte(8'h0F); // 发送 00001111
        send_rs232_byte(8'h6B); // 发送 01101100
        send_rs232_byte(8'hBB); // 发送 11001100
        send_rs232_byte(8'hFB); // 发送 11111100
        send_rs232_byte(8'h00); // 发送全 0
        send_rs232_byte(8'hFF); // 发送全 1
        
        #1_000_000;
        
        $display("------------------- Simulation Finish -------------------");
        $finish;
    end
    //----------------------------------------------------------------
    // 2. 激励生成任务 (Stimulus)
    //----------------------------------------------------------------
    // 定义一个任务，用于发送一个字节的标准 RS-232 格式数据
    task send_rs232_byte;
        input [7:0] data_to_send;
        integer i;
        begin
            $display("At time %0t ns, sending RS232 byte: 0x%h", $time, data_to_send);
            
            // -- 发送起始位 (低电平，持续一个比特周期) --
            rs232_in = 1'b0;
            #(BIT_PERIOD);
            // -- 发送8位数据位 (从低位到高位) --
            for (i = 0; i < 8; i = i + 1) begin
                rs232_in = data_to_send[i];
                #(BIT_PERIOD);
            end
            // -- 发送停止位 (高电平，持续一个比特周期) --
            rs232_in = 1'b1;
            #(BIT_PERIOD);
            
            // 两个字节之间增加一些空闲时间
            #(BIT_PERIOD * 20);
        end
    endtask
    //----------------------------------------------------------------
    // 3. 监控和比较 (Monitor)
    //----------------------------------------------------------------
    // 监控关键信号
    initial begin
        $monitor("At time %0t ns: rst_n=%b, rs232_in=%b ===> TBS_out=%b",
                 $time, rst_n, rs232_in, TBS_out);
    end
endmodule
    