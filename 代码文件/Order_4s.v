module Order_4s (
    input            clk_50M,          // 系统时钟 50MHz
    input            rst_n,            // 低电平复位
    input      [2:0] command,          // 命令信号
    output reg       sys_start_pulse,  // 输出：系统同步脉冲 (T0时刻)
    output reg       start,            // 输出：系统启动状态指示
    output reg       start_test,       // 输出：测试模式指示
    output reg       Exc_start,        // 输出：激励启动信号 (发射超声波)
    output reg       relay,            // 输出：继电器切换信号
    output reg       AD_start          // 输出：AD启动信号
);

    // ============================================================
    // 参数定义 (基于 50MHz 时钟)
    // ============================================================
    parameter CLK_FREQ = 50_000_000;

    // 时间参数
    parameter Time_4s = 32'd200_000_000;
    parameter Time_10ms = 19'd500_000;  // 10ms (单次测量周期)
    parameter Time_6ms = 19'd300_000;  // 6ms (AD采样结束时刻)
    parameter Time_3ms = 19'd150_000;  // 3ms (盲区/等待时刻)

    // AD采样率控制: 1us = 50个时钟周期 (即 1MSPS 采样率)
    parameter Time_1us = 16'd34;

    // 状态机定义
    localparam [2:0] 
        IDLE        = 3'b000,
        SYS_START   = 3'b001,
        WAIT_10MS   = 3'b010, // 这里的命名保留原意，实际作为周期末尾的等待或初始等待
    PULSE_GEN = 3'b011,  // 产生激励脉冲 (T0)
    WAIT_1MS = 3'b100,  // 激励后的盲区等待
    AD_SAMPLING = 3'b101,  // AD 采样窗口
    SYS_STOP = 3'b110;  // 系统停止

    // ============================================================
    // 内部信号
    // ============================================================
    reg [31:0] cnt_4s;  // 4秒总计时
    reg [18:0] cnt_10ms;  // 10ms 周期计时
    reg [15:0] cnt_1us;  // AD 采样间隔计时
    reg [ 2:0] current_state;
    reg [ 2:0] next_state;

    // ============================================================
    // 1. 命令解析 (Command Processing)
    // ============================================================
    reg [ 2:0] command_prev;

    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) begin
            start        <= 0;  //
            start_test   <= 0;
            relay        <= 0;
            command_prev <= 0;
        end
        else begin
            command_prev <= command;  // 记录上一拍命令，用于边沿检测

            // 命令 0x01: 系统启动
            if (command == 3'h1 && command_prev != 3'h1) start <= 1;
            // (注意: start 信号在原逻辑中是脉冲还是电平取决于需求，这里保持置1，由状态机控制结束)

            // 命令 0x02: 测试模式
            if (command == 3'h2 && command_prev != 3'h2) start_test <= 1;

            // 命令 0x03: 继电器切换 (保留原文件逻辑，替代 sig_ctl)
            if (command == 3'h3 && command_prev != 3'h3) relay <= ~relay;
        end
    end

    // ============================================================
    // 2. 状态机逻辑 (FSM)
    // ============================================================
    // 状态跳转
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) current_state <= IDLE;
        else current_state <= next_state;
    end

    // 状态转移判断
    always @(*) begin
        case (current_state)
            IDLE: begin
                if (start) next_state = SYS_START;
                else next_state = IDLE;
            end

            SYS_START: begin
                next_state = PULSE_GEN;  // 启动后先进入等待，确保时序对齐
            end

            // 循环周期的起始/结束等待状态
            WAIT_10MS: begin
                if (cnt_4s >= Time_4s) next_state = SYS_STOP;  // 4秒结束
                else if (cnt_10ms >= Time_10ms)
                    next_state = PULSE_GEN;  // 10ms 周期结束，开始新一轮激励
                else next_state = WAIT_10MS;
            end

            // T0 时刻：产生激励
            PULSE_GEN: begin
                next_state = WAIT_1MS;
            end

            // 等待盲区 (0 ~ 1ms)
            WAIT_1MS: begin
                if (cnt_10ms >= Time_3ms) next_state = AD_SAMPLING;
                else next_state = WAIT_1MS;
            end

            // 采样窗口 (1ms ~ 9ms)
            AD_SAMPLING: begin
                if (cnt_4s >= Time_4s) next_state = SYS_STOP;
                else if (cnt_10ms >= Time_6ms)
                    next_state = WAIT_10MS;  // 采样结束，等待本周期剩余时间
                else next_state = AD_SAMPLING;
            end

            SYS_STOP: begin
                next_state = IDLE;
            end

            default: next_state = IDLE;
        endcase
    end

    // ============================================================
    // 3. 计数器逻辑
    // ============================================================

    // [计数器1] 4秒总计时
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) cnt_4s <= 0;
        else if (current_state == SYS_START) cnt_4s <= 0;
        else if (current_state != IDLE && current_state != SYS_STOP) begin
            // 在所有工作状态下都计数
            if (cnt_4s < Time_4s) cnt_4s <= cnt_4s + 1;
        end
        else cnt_4s <= 0;
    end

    // [计数器2] 10ms 周期计时
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) cnt_10ms <= 0;
        else if (current_state == SYS_START) cnt_10ms <= 0;
        else if (current_state != IDLE && current_state != SYS_STOP) begin
            // 循环计数 0 ~ Time_10ms
            if (cnt_10ms >= Time_10ms) cnt_10ms <= 0;
            else cnt_10ms <= cnt_10ms + 1;
        end
        else cnt_10ms <= 0;
    end

    // [计数器3] 1us 采样分频计时
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) cnt_1us <= 0;
        else if (current_state == AD_SAMPLING) begin
            if (cnt_1us >= Time_1us - 1) cnt_1us <= 0;
            else cnt_1us <= cnt_1us + 1;
        end
        else cnt_1us <= 0;
    end

    // ============================================================
    // 4. 输出信号逻辑
    // ============================================================

    // 生成激励启动信号 (Exc_start)
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) Exc_start <= 0;
        else if (current_state == PULSE_GEN) Exc_start <= 1;  // 产生一个周期的高电平
        else Exc_start <= 0;
    end

    // 生成 AD 启动信号 (AD_start)
    // 在 AD_SAMPLING 状态下，每隔 1us 产生一个脉冲
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) AD_start <= 0;
        else if (current_state == AD_SAMPLING && cnt_1us == 0) AD_start <= 1;
        else AD_start <= 0;
    end

    // 生成系统同步脉冲 (sys_start_pulse) - 用于指示 T0 时刻
    // 检测状态进入 PULSE_GEN 的瞬间
    reg [2:0] state_dly;
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) state_dly <= IDLE;
        else state_dly <= current_state;
    end

    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) sys_start_pulse <= 0;
        else if (current_state == PULSE_GEN && state_dly != PULSE_GEN) sys_start_pulse <= 1;
        else sys_start_pulse <= 0;
    end

endmodule
