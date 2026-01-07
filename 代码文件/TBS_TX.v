module TBS_TX #(
    // -- 参数化配置 --
    parameter CLK_FREQ    = 50_000_000, // 系统时钟频率 (单位: Hz)
    parameter BAUD_RATE   = 115200      // 期望的波特率
) (
    input                       clk_50M,        // 系统时钟
    input                       rst_n,      // 异步复位，低电平有效

    // -- 标准 UART 接口 --
    input                       rs232_in,   // 来自标准 UART_TX 模块的输出信号

    // -- TBS 总线接口 --
    output                      TBS_out     // 输出到 TBS 总线
);

    // UART_TX/RX 中 BAUD_CNT_MAX = 434，表示 435 个时钟周期。
    localparam BIT_PERIOD_COUNT  = 434; // 修复：硬编码为 434，或使用 (CLK_FREQ / BAUD_RATE) + 1 但需确保整除逻辑

    localparam PULSE_WIDTH_COUNT = BIT_PERIOD_COUNT / 10; // 脉冲宽度定义为比特周期的 10%
    // 精确位宽计算，$clog2(N) - 1 是指 N 个值 (0到N-1) 所需的最高位索引
    localparam PULSE_CNT_WIDTH   = $clog2(PULSE_WIDTH_COUNT) - 1;
    localparam BAUD_CNT_WIDTH    = $clog2(BIT_PERIOD_COUNT) - 1;
    
    //----------------------------------------------------------------
    // 内部信号定义
    //----------------------------------------------------------------
    // -- 脉冲生成相关 --
    reg [PULSE_CNT_WIDTH:0] pulse_cnt;  

    // -- 输入同步与边沿检测 --
    reg                 rs232_in_sync_d1;
    reg                 rs232_in_sync_d2;
    wire                start_of_frame_detected; // 帧起始下降沿检测

    // -- 波特率时钟和状态控制 --
    reg [BAUD_CNT_WIDTH:0]  baud_cnt;         
    reg [3:0]               bit_cnt;         // 比特位计数器 (0-9, 对应起始位, 8*数据位, 停止位)
    reg                     tx_active;       // 帧传输激活状态标志
    wire                    baud_tick;       // 单周期脉冲，标志着一个比特周期的结束
    
    // 用于10周期延迟的移位寄存器
    reg [9:0]               baud_tick_delay_sr; 

    //----------------------------------------------------------------
    // 输入信号同步 与 边沿检测
    //----------------------------------------------------------------
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) begin
            rs232_in_sync_d1 <= 1'b1;
            rs232_in_sync_d2 <= 1'b1;
        end else begin
            rs232_in_sync_d1 <= rs232_in;
            rs232_in_sync_d2 <= rs232_in_sync_d1;
        end
    end

    // 仅在 tx 未激活时，下降沿才被认为是帧的开始
    assign start_of_frame_detected = rs232_in_sync_d2 & ~rs232_in_sync_d1 & ~tx_active;
    
    //----------------------------------------------------------------
    // 波特率节拍器与状态机
    //----------------------------------------------------------------
    // 波特率计数器
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) begin
            baud_cnt <= 0;
        end else if (tx_active) begin
            if (baud_cnt == BIT_PERIOD_COUNT - 1) begin
                baud_cnt <= 0;
            end else begin
                baud_cnt <= baud_cnt + 1;
            end
        end else begin
            baud_cnt <= 0;
        end
    end
    
    // 在每个比特周期的边界产生一个单周期的 tick 信号
    assign baud_tick = (tx_active && (baud_cnt == BIT_PERIOD_COUNT - 1));

    // 传输状态机
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) begin
            tx_active <= 1'b0;
            bit_cnt   <= 0;
        end else begin
            if (start_of_frame_detected) begin
                tx_active <= 1'b1;
                bit_cnt   <= 0; // 准备开始计数（起始位是第0个）
            end else if (baud_tick) begin
                if (bit_cnt == 9) begin // 假设1位停止位，共10个bit (0-9)
                    tx_active <= 1'b0;
                    bit_cnt   <= 0;
                end else begin
                    bit_cnt <= bit_cnt + 1;
                end
            end
        end
    end
    
    //----------------------------------------------------------------
    // 10周期延迟采样点以避免时序竞争
    // baud_tick 产生于前一个比特周期的结束。
    // baud_tick_d10 将在当前比特周期的开始后 10 个时钟周期内发生，
    // 提供一个稳定的采样点。
    //----------------------------------------------------------------
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) begin
            baud_tick_delay_sr <= 10'b0;
        end else begin
            // 将 baud_tick 移入移位寄存器的最低位，旧数据向高位移动
            baud_tick_delay_sr <= {baud_tick_delay_sr[8:0], baud_tick};
        end
    end

    // 定义延迟10拍后的信号，取移位寄存器的最高位
    wire baud_tick_d10 = baud_tick_delay_sr[9];

    //----------------------------------------------------------------
    // 脉冲生成触发逻辑
    //----------------------------------------------------------------
    // 脉冲触发条件：
    // 1. 帧的开始 (start_of_frame_detected) - 对起始位快速响应。
    // 2. 在比特周期边界后10拍 (baud_tick_d10)，并且此时采样的输入为低电平 - 确保数据位采样的稳定性。
    // 这种混合触发是合理的：起始位下降沿是最明确的帧开始信号，应立即响应；
    // 而后续数据位则需要更稳定的采样点。
    wire trigger_pulse = start_of_frame_detected ||
                         (tx_active && baud_tick_d10 && (rs232_in_sync_d1 == 1'b0)); // 修正：baud_tick_d10只在tx_active时才采样

    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) begin
            pulse_cnt <= PULSE_WIDTH_COUNT;
        end else if (trigger_pulse) begin
            pulse_cnt <= 0;
        end else if (pulse_cnt < PULSE_WIDTH_COUNT) begin
            pulse_cnt <= pulse_cnt + 1'b1;
        end else begin
            pulse_cnt <= PULSE_WIDTH_COUNT;
        end
    end
    
    //----------------------------------------------------------------
    // 输出信号生成 (此部分逻辑不变)
    //----------------------------------------------------------------
    assign TBS_out = (pulse_cnt < PULSE_WIDTH_COUNT) ? 1'b0 : 1'b1;

endmodule
