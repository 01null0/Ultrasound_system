`timescale 1ns / 1ps

module tb_Order_4s();

    // 输入信号
    reg        clk_50M;
    reg        rst_n;
    reg [2:0]  command;

    // 输出信号
    wire       start;
    wire       start_test;
    wire       Exc_start;
    wire       AD_start;

    // 实例化被测模块
    Order_4s uut (
        .clk_50M(clk_50M),
        .rst_n(rst_n),
        .command(command),
        .start(start),
        .start_test(start_test),
        .Exc_start(Exc_start),
        .AD_start(AD_start)
    );

    // 生成 50MHz 时钟
    always #10 clk_50M = ~clk_50M;  // 周期 20ns → 50MHz

    // 初始化
    initial begin
        // 初始化信号
        clk_50M = 0;
        rst_n = 0;
        command = 3'h0;

        // 释放复位
        #100;
        rst_n = 1;

        // 发送启动命令
        #50;
        command = 3'h1;  // 系统启动
        #50;
        command = 3'h0;  // 启动信号结束

        // 运行 1 秒
        #1000000000;  // 1 秒 = 1,000,000,000 ns

        // 结束仿真
        $display("Simulation finished at 1 second.");
        $finish;
    end

    // // 监控信号变化
    // initial begin
    //     $monitor("Time = %t ns | State = %d | Command = %h | Start = %b | Exc_start = %b | AD_start = %b",
    //              $time, uut.current_state, command, start, Exc_start, AD_start);
    // end

    // 生成 VCD 文件用于波形分析
    initial begin
        $dumpfile("Order_4s.vcd");
        $dumpvars(0, tb_Order_4s);
    end

endmodule
