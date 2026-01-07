// `timescale 1ns / 1ps

// module tb_90khz;

//     // Parameters
//     parameter CLK_PERIOD = 20; // 50MHz clock period (20ns)
//     parameter SIM_TIME = 1_000_000_000; // 1 second simulation time

//     // Inputs
//     reg clk_50M;
//     reg rst_n;

//     // Outputs
//     wire VIN_1;
//     wire VIN_2;
//     wire VIN_3;
//     wire VIN_4;

//     // Instantiate the module
//     ultrasound_launch_90KHz_10ms uut (
//         .clk_50M(clk_50M),
//         .rst_n(rst_n),
//         .VIN_1(VIN_1),
//         .VIN_2(VIN_2),
//         .VIN_3(VIN_3),
//         .VIN_4(VIN_4)
//     );

//     // Clock generation
//     initial begin
//         clk_50M = 0;
//         forever #(CLK_PERIOD/2) clk_50M = ~clk_50M;
//     end

//     // Test sequence
//     initial begin
//         // Initialize signals
//         rst_n = 0;

//         // Reset the system
//         #(CLK_PERIOD*10) rst_n = 1; // Release reset after 10 clock cycles
//         #(CLK_PERIOD*10) rst_n = 0; // Assert reset again for a short duration
//         #(CLK_PERIOD*10) rst_n = 1; // Release reset

//         // Run the simulation for 1 second
//         #(SIM_TIME) $stop; // Stop simulation after 1 second
//     end

// endmodule
`timescale 1ns/1ps

module tb_90khz;

    // 时钟和复位信号
    reg clk_50M;
    reg rst_n;
    reg launch_cmd;
    
    // 输出信号
    wire VIN_1;
    wire VIN_2;
    wire VIN_3;
    wire VIN_4;
    
    // 时钟参数
    parameter CLK_PERIOD = 20; // 50MHz时钟，周期20ns
    
    // 实例化被测试模块
    ultrasound_launch_90KHz_10ms uut (
        .clk_50M(clk_50M),
        .rst_n(rst_n),
        .launch_cmd(launch_cmd),
        .VIN_1(VIN_1),
        .VIN_2(VIN_2),
        .VIN_3(VIN_3),
        .VIN_4(VIN_4)
    );
    
    // 时钟生成
    always #(CLK_PERIOD/2) clk_50M = ~clk_50M;
    
    // 初始化
    initial begin
        // 初始化信号
        clk_50M = 0;
        rst_n = 0;
        launch_cmd = 0;
        
        
        // 复位序列
        #100;
        rst_n = 1;
        #100;
        
        $display("=== 超声波发射模块仿真开始 ===");
        $display("时间: %t", $time);
        
        // 测试场景1：单次发射
        $display("\n--- 测试1：单次发射 ---");
        launch_cmd = 1;
        #20; // 等待20ns
        launch_cmd = 0;
        #10000000; // 等待10ms
        
        // 测试场景2：连续快速发射（模拟连续按键）
        $display("\n--- 测试2：连续发射 ---");
        repeat (3) begin
            launch_cmd = 1;
            #200000; // 200us
            launch_cmd = 0;
            #5000000; // 5ms间隔
        end
        
        // 测试场景3：长时间保持发射
        $display("\n--- 测试3：长时间发射 ---");
        launch_cmd = 1;
        #5000000; // 5ms
        launch_cmd = 0;
        #10000000; // 10ms
        
        // 测试场景4：复位测试
        $display("\n--- 测试4：复位测试 ---");
        rst_n = 0;
        #1000;
        rst_n = 1;
        #1000000;
        
        // 测试场景5：边界情况测试
        $display("\n--- 测试5：边界情况测试 ---");
        launch_cmd = 1;
        #100;
        launch_cmd = 0;
        #100000;
        launch_cmd = 1;
        #1000000;
        launch_cmd = 0;
        
        // 等待剩余时间完成100ms仿真
        #80000000; // 80ms
        
        $display("\n=== 仿真完成 ===");
        $display("总仿真时间: %t", $time);
        $finish;
    end
    
    // 监控输出信号
    integer vin1_count = 0;
    integer vin2_count = 0;
    integer vin3_count = 0;
    integer vin4_count = 0;
    reg vin1_last = 0;
    reg vin2_last = 0;
    reg vin3_last = 0;
    reg vin4_last = 0;
    
    always @(posedge clk_50M) begin
        // 统计VIN_1的上升沿
        if (VIN_1 && !vin1_last) begin
            vin1_count <= vin1_count + 1;
        end
        vin1_last <= VIN_1;
        
        // 统计VIN_2的上升沿
        if (VIN_2 && !vin2_last) begin
            vin2_count <= vin2_count + 1;
        end
        vin2_last <= VIN_2;
        
        // 统计VIN_3的上升沿
        if (VIN_3 && !vin3_last) begin
            vin3_count <= vin3_count + 1;
        end
        vin3_last <= VIN_3;
        
        // 统计VIN_4的上升沿
        if (VIN_4 && !vin4_last) begin
            vin4_count <= vin4_count + 1;
        end
        vin4_last <= VIN_4;
    end
    
    

endmodule
