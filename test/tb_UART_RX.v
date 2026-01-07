`timescale 1ns / 1ps

module tb_UART_RX();
    // 输入信号
    reg clk_50M;
    reg rst_n;
    reg rs232_rx;
    
    // 输出信号
    wire rx_done;
    //wire [7:0] rx_data;
    wire [2:0] command;
    parameter BPS=8681;// 1/38400秒 ≈ 26041ns
    // 实例化UART_RX模块
    UART_RX uut (
        .clk_50M(clk_50M),
        .rst_n(rst_n),
        .rs232_rx(rs232_rx),
        .rx_done(rx_done),
        //.rx_data(rx_data),
        .command(command)
    );
    
    // 时钟生成：50MHz
    always #10 clk_50M = ~clk_50M;
    
    // 任务：发送一个字节
    task send_byte;
        input [7:0] data;
        integer i;
        begin
            // 起始位
            rs232_rx = 0;
            #BPS; 
            
            // 数据位
            for (i = 0; i < 8; i = i + 1) begin
                rs232_rx = data[i];
                #BPS;
            end
            
            // 停止位
            rs232_rx = 1;
            #BPS;
        end
    endtask
    
    // 测试序列
    initial begin
        // 初始化信号
        clk_50M = 0;
        rst_n = 0;
        rs232_rx = 1; // 空闲状态为高电平
        
        // 复位
        #100 rst_n = 1;
        
        // 等待一段时间
        #1000;
        
        // 测试1：发送数据0x01
        send_byte(8'h01);
        
        // 等待处理完成
        #100000;
        
        // 测试2：发送数据0x02
        send_byte(8'h02);
        
        // 等待处理完成
        #100000;
        
        // 测试3：发送数据0x04
        send_byte(8'h04);
        
        // 等待处理完成
        #100000;
        
        // 测试4：发送无效数据
        send_byte(8'hFF);
        
        // 等待处理完成
        #100000;
        
        // 结束仿真
        #100 $finish;
    end
    
endmodule
