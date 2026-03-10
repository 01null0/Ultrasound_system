`timescale 1ns/1ns

module tb_ultrasound_launch_90KHz_10ms;

    // ============================================================
    // 1. 信号定义
    // ============================================================
    reg     clk_50M;
    reg     rst_n;
    reg     launch_cmd;

    wire    VIN_1; // 左上
    wire    VIN_2; // 右上
    wire    VIN_3; // 左下
    wire    VIN_4; // 右下

    // 参数定义（与DUT保持一致，方便仿真观测）
    parameter CNT_MAX = 11'd1686;
    parameter START_DEAD_TIME = 11'd20; // 400ns 死区

    // ============================================================
    // 2. 待测模块实例化 (DUT)
    // ============================================================
    ultrasound_launch_90KHz_10ms #(
        .CNT_MAX(CNT_MAX),
        .START_DEAD_TIME(START_DEAD_TIME)
    ) uut (
        .clk_50M    (clk_50M),
        .rst_n      (rst_n),
        .launch_cmd (launch_cmd),
        .VIN_1      (VIN_1),
        .VIN_2      (VIN_2),
        .VIN_3      (VIN_3),
        .VIN_4      (VIN_4)
    );

    // ============================================================
    // 3. 时钟生成 (50MHz, 周期20ns)
    // ============================================================
    initial begin
        clk_50M = 0;
        forever #10 clk_50M = ~clk_50M;
    end

    // ============================================================
    // 4. 安全监控器 (Safety Monitor) - 关键部分！
    // ============================================================
    // 实时检测是否发生直通 (Shoot-through)
    // 如果左桥臂上下同高，或右桥臂上下同高，立即报错停止
    always @(posedge clk_50M) begin
        if ((VIN_1 && VIN_3) == 1'b1) begin
            $display("\n[FATAL ERROR] Shoot-through detected on LEFT Bridge (VIN1 & VIN3) at time %t ns!", $time);
            $stop; // 暂停仿真
        end
        if ((VIN_2 && VIN_4) == 1'b1) begin
            $display("\n[FATAL ERROR] Shoot-through detected on RIGHT Bridge (VIN2 & VIN4) at time %t ns!", $time);
            $stop; // 暂停仿真
        end
    end

    // ============================================================
    // 5. 暴力测试激励
    // ============================================================
    initial begin
        // --- 初始化 ---
        rst_n = 0;
        launch_cmd = 0;
        $display("=== Simulation Start ===");
        
        #100;
        rst_n = 1;
        #100;

        // --------------------------------------------------------
        // Case 1: 正常单次发射测试
        // --------------------------------------------------------
        $display("[%t] Test Case 1: Normal Single Launch", $time);
        @(posedge clk_50M);
        launch_cmd = 1; 
        @(posedge clk_50M);
        launch_cmd = 0; // 产生一个脉冲
        
        // 等待一次传输完成 (约34us)
        wait(uut.work_en == 0); 
        #2000; // 额外冷却时间

        // --------------------------------------------------------
        // Case 2: 暴力重触发 (Violent Re-triggering)
        // 模拟在发射过程中，意外又来了启动信号
        // --------------------------------------------------------
        $display("[%t] Test Case 2: Interrupting Launch (Re-trigger)", $time);
        
        // 第一次触发
        launch_cmd = 1;
        #20 launch_cmd = 0;
        
        #5000; // 此时正如火如荼地发射中 (5us时刻)
        
        $display("[%t] -> Injecting Interrupt Trigger! (Should reset and enter Dead Time)", $time);
        launch_cmd = 1; // 【暴力点】强制打断！
        #20 launch_cmd = 0;
        
        // 观察波形：此时计数器应立刻归零，且所有输出应强制拉低至少 START_DEAD_TIME (400ns)
        
        #5000; // 再跑一会
        $display("[%t] -> Injecting Another Interrupt!", $time);
        launch_cmd = 1; // 【暴力点】再次打断！
        #20 launch_cmd = 0;

        wait(uut.work_en == 0);
        #1000;

        // --------------------------------------------------------
        // Case 3: 狂暴连发 (Rapid Fire)
        // 模拟按键抖动或噪声，极高频率的触发
        // --------------------------------------------------------
        $display("[%t] Test Case 3: Rapid Fire Noise (High Frequency Triggers)", $time);
        
        repeat(50) begin
            @(posedge clk_50M);
            launch_cmd = 1; 
            #20;            // 只有20ns脉冲
            launch_cmd = 0;
            #200;           // 间隔200ns就来一次 (远小于周期)
        end

        // 停止狂暴，让它完成最后一次
        #1000;
        wait(uut.work_en == 0);
        
        $display("=== Simulation Finished Successfully (No Shoot-through detected) ===");
        $stop;
    end

endmodule
