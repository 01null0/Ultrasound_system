`timescale 1ns / 1ps

module tb_UART_TX();
    // 输入信号
    reg clk_50M;
    reg rst_n;
    reg [11:0] ad_data;
    reg ad_done;
    
    // 输出信号
    wire rs232_tx;

    wire [5:0]test_bit_cnt;
    
    // 实例化UART_TX模块
    UART_TX uut (
        .clk_50M(clk_50M),
        .rst_n(rst_n),
        .ad_data(ad_data),
        .ad_done(ad_done),

        
        .test_bit_cnt(test_bit_cnt),

        .rs232_tx(rs232_tx)
    );
    
    // 时钟生成：50MHz
    always #10 clk_50M = ~clk_50M;
    
    // 测试序列
    initial begin
        // 初始化信号
        clk_50M = 0;
        rst_n = 0;
        ad_data = 12'h000;
        ad_done = 0;
        
        // 复位
        #100 rst_n = 1;
        
        // 测试1：发送数据
        #100 ad_data = 12'hABC;
        ad_done = 1;
        #20 ad_done = 0;
        
        // 等待传输完成
        #1_000_000; // 等待足够长时间以确保传输完成
        
        // 测试2：发送另一个数据
        #100 ad_data = 12'h123;
        ad_done = 1;
        #20 ad_done = 0;
        
        // 等待传输完成
        #1_000_000;

        // 测试3：发送另一个数据
        #100 ad_data = 12'h001;
        ad_done = 1;
        #20 ad_done = 0;
        
        // 等待传输完成
        #1_000_000;
        // 测试4：发送另一个数据
        #100 ad_data = 12'h017;
        ad_done = 1;
        #20 ad_done = 0;
        
        // 等待传输完成
        #1_000_000;
        
        // 结束仿真
        #100 $finish;
    end
    
    // 监控输出
    initial begin
        $monitor("Time = %t, TX = %b, ad_data = %h, ad_done = %b", 
                 $time, rs232_tx, ad_data, ad_done);
    end
endmodule