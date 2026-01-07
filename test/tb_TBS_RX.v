`timescale 1ns / 1ps // 定义仿真时间单位为1ns，精度为1ps [1]
module tb_TBS_RX; // Testbench 模块没有输入输出端口 [1]
    // -- 参数定义 --
    localparam CLK_FREQ    = 50_000_000;   // 时钟频率 50MHz
    localparam BAUD_RATE   = 115200;       // 波特率 115200
    localparam CLK_PERIOD  = 1_000_000_000 / CLK_FREQ; // 时钟周期: 20ns
    localparam BIT_PERIOD  = 1_000_000_000 / BAUD_RATE; // 比特周期: ~8680ns
    localparam PULSE_WIDTH = BIT_PERIOD / 10;          // TBS '0' 脉冲宽度: ~868ns
    // -- 信号定义 --
    // DUT 输入信号类型为 reg
    reg clk_50M;
    reg rst_n;
    reg TBS_in;
    // DUT 输出信号类型为 wire
    wire rs232_out;
    
    //----------------------------------------------------------------
    // 例化待测模块 (DUT: Design Under Test)
    //----------------------------------------------------------------
    TBS_RX #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) u_tbs_rx (
        .clk_50M(clk_50M),
        .rst_n(rst_n),
        .TBS_in(TBS_in),
        .rs232_out(rs232_out)
    );
    //----------------------------------------------------------------
    // 1. 时钟和复位激励生成
    //----------------------------------------------------------------
    // 生成时钟信号
    initial begin
        clk_50M = 0;
        forever #(CLK_PERIOD / 2) clk_50M = ~clk_50M; // 产生周期为 CLK_PERIOD 的时钟
    end
    // 生成复位信号和测试主流程
    initial begin
        // 初始化和复位
        rst_n = 1'b0; // 进入复位状态
        TBS_in = 1'b1; // 总线空闲为高
        #200;          // 保持复位 200ns [3]
        rst_n = 1'b1; // 释放复位
        #200;          // 等待电路稳定
        $display("------------------- Simulation Start -------------------");
        
        // 调用任务，发送测试数据
        send_tbs_byte(8'h55); // 发送 01010101
        send_tbs_byte(8'hA3); // 发送 10100011
        send_tbs_byte(8'h00); // 发送全 0
        send_tbs_byte(8'hFF); // 发送全 1
        
        #50000; // 等待最后一个字节发送完成
        
        $display("------------------- Simulation_Finish -------------------");
        $finish; // 结束仿真
    end
    //----------------------------------------------------------------
    // 2. 激励生成任务 (Stimulus)
    //----------------------------------------------------------------
    // 定义一个任务，用于发送一个字节的 TBS 格式数据
    task send_tbs_byte;
        input [7:0] data_to_send;
        integer i;
        begin
            $display("At time %0t ns, sending TBS byte: 0x%h", $time, data_to_send);
            
            // -- 发送起始位 (值为'0') --
            TBS_in = 1'b0;
            #(PULSE_WIDTH);
            TBS_in = 1'b1;
            #(BIT_PERIOD - PULSE_WIDTH);
            // -- 发送8位数据位 (从低位到高位) --
            for (i = 0; i < 8; i = i + 1) begin
                if (data_to_send[i] == 1'b0) begin
                    // 如果是 '0', 发送一个短脉冲
                    TBS_in = 1'b0;
                    #(PULSE_WIDTH);
                    TBS_in = 1'b1;
                    #(BIT_PERIOD - PULSE_WIDTH);
                end else begin
                    // 如果是 '1', 保持高电平
                    TBS_in = 1'b1;
                    #(BIT_PERIOD);
                end
            end
            // -- 发送停止位 (值为'1') --
            TBS_in = 1'b1;
            #(BIT_PERIOD);
            
            // 两个字节之间增加一些空闲时间
            #(BIT_PERIOD * 2);
        end
    endtask
    //----------------------------------------------------------------
    // 3. 监控和比较 (Monitor)
    //----------------------------------------------------------------
    // 监控关键信号，当信号变化时打印其状态
    initial begin
        // $time 可用于获取当前仿真时间 [1]
        $monitor("At time %0t ns: rst_n=%b, TBS_in=%b ===> rs232_out=%b",
                 $time, rst_n, TBS_in, rs232_out);
    end
endmodule
