// 系统启动后开始4秒计时
// 每10ms产生一次超声激励
// 激励后延迟1ms开始AD采样
// AD采样持续8ms（1ms-9ms期间）
// 4秒后系统自动停止
module Order (
    input            clk_50M,     // 50MHz时钟
    input            rst_n,       // 复位信号
    input      [2:0] command,     // 命令输入
    output reg       start,       // 系统启动
    output reg       start_test,  // 开始测试
    output reg       Exc_start,   //激发开始信号
    output reg       AD_start     //AD开始信号
    // ,output reg       AD_end       //AD停止信号，此时也代表系统停止
);
    //参数定义
    parameter CLK_FREQ = 50_000_000;  // 系统时钟频率
    parameter Time_4s = 200_000_000;  // 4S
    parameter Time_10ms = 500_000;  // 10mS
    parameter Time_9ms = 450_000;  // 9ms
    parameter Time_1ms = 50_000;  // 1ms
    parameter Time_1us = 50;  // 4S

    reg [27:0] cnt_4s;  //4s计数器
    reg [18:0] cnt_10ms;  //10ms计数器
    reg [ 5:0] cnt_1us;  //1us计数器
    reg        cnt_en;  //4s计数时，信号使能
    reg [ 1:0] sync_regs;  // 同步寄存器（用于亚稳态消除）
    reg [ 1:0] sync_regs_test;
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) begin
            start <= 0;
            start_test <= 0;
        end
        else begin
            case (command)
                3'h0: begin
                    start <= 0;
                    start_test <= 0;
                end
                3'h1: start <= 1;  //系统启动，开启定时器
                3'h2: start_test <= 1;  //测试启动，开启定时器
                default: begin
                    start <= 0;
                    start_test <= 0;
                end
            endcase
        end
    end

    //同步和下降沿检测
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) sync_regs <= 2'b11;
        else sync_regs <= {sync_regs[0], start};
    end
    wire nedge_detect = (sync_regs[1] & ~sync_regs[0]);  // 启动信号start下降沿检测

    //同步和下降沿检测
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) sync_regs_test <= 2'b11;
        else sync_regs_test <= {sync_regs_test[0], start_test};
    end
    wire nedge_detect_test = (sync_regs_test[1] & ~sync_regs_test[0]);  // 测试信号start_test下降沿检测

    //初步设定4S作为采集时间，多余部分为自相关运算做时间冗余

    //4s定时器
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) begin
            cnt_4s <= Time_4s + 1;
            cnt_en <= 0;
        end
        else if (cnt_4s == Time_4s) begin
            cnt_4s <= Time_4s + 1;
            cnt_en <= 0;
        end
        else if (nedge_detect) begin
            cnt_4s <= 0;
        end
        else begin
            cnt_4s <= cnt_4s + 1;
            cnt_en <= 1;
        end
    end
    //10ms定时器，用于激励脉冲信号
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) begin
            cnt_10ms <= Time_10ms + 1;
        end
        else if (!cnt_en) begin
            cnt_10ms <= Time_10ms + 1;
        end
        else if (cnt_10ms == Time_10ms) begin
            cnt_10ms <= 0;
        end
        else if (nedge_detect) begin
            cnt_10ms <= 0;
        end
        else begin
            cnt_10ms <= cnt_10ms + 1;
        end
    end

    //90KHZ的十倍采样率，故用大致1MHZ采样率
    //1us定时器
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) begin
            cnt_1us <= Time_1us + 1;
        end
        else if (!cnt_en) begin
            cnt_1us <= Time_1us + 1;
        end
        else if (cnt_1us == Time_1us) begin
            cnt_1us <= 0;
        end
        else if (cnt_10ms == Time_1ms) begin
            cnt_1us <= 0;  //激发完成1ms后，开启AD转换
        end
        else if (cnt_10ms == Time_9ms) begin
            cnt_1us <= Time_1us + 1;
        end
        else begin
            cnt_1us <= cnt_1us + 1;
        end
    end

    //4s结束后，发送停止信号
    // always @(posedge clk_50M or negedge rst_n) begin
    //     if (!rst_n) begin
    //         AD_end <= 0;
    //     end
    //     else if (cnt_4s == Time_4s) begin
    //         AD_end <= 1;
    //     end
    //     else begin
    //         AD_end <= 0;
    //     end
    // end

    //10ms触发一次超声激励
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) begin
            Exc_start <= 0;
        end
        else if (cnt_10ms == Time_10ms) begin
            Exc_start <= 1;
        end
        else begin
            Exc_start <= 0;
        end
    end
    //激发完成后1ms后开始AD采集
    //每隔1us，AD采样一次
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) begin
            AD_start <= 0;
        end
        else if (cnt_1us == Time_1us) begin
            AD_start <= 1;
        end
        else begin
            AD_start <= 0;
        end
    end

endmodule
