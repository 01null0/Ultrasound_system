module TBS_RX #(
    // -- 参数化配置 --
    parameter CLK_FREQ    = 50_000_000, // 系统时钟频率 (单位: Hz)
    parameter BAUD_RATE   = 115200      // 期望的波特率
) (
    input                       clk_50M,        // 系统时钟
    input                       rst_n,      // 异步复位，低电平有效

    // -- TBS 总线接口 --
    input                       TBS_in,     // 来自 TBS 总线的输入信号

    // -- 标准 UART 接口 --
    output                      rs232_out   // 输出到标准 UART_RX 模块的输入端
);

    //----------------------------------------------------------------
    // 本地参数定义
    //----------------------------------------------------------------
    // 计算每个比特周期对应的时钟周期数。
    // localparam BIT_PERIOD_COUNT = CLK_FREQ / BAUD_RATE;
    localparam BIT_PERIOD_COUNT = 434;
    // 为计数器计算所需的位宽，使用 $clog2 以优化资源。45
    localparam CNT_WIDTH = $clog2(BIT_PERIOD_COUNT);

    //----------------------------------------------------------------
    // 内部信号定义
    //----------------------------------------------------------------
    reg  [CNT_WIDTH:0]  stretch_cnt;        // 用于拉伸脉冲的计数器
    reg                 tbs_in_sync_d1;     // 两级同步寄存器，第一级
    reg                 tbs_in_sync_d2;     // 两级同步寄存器，第二级
    wire                falling_edge_detected; // 下降沿检测标志

    //----------------------------------------------------------------
    // 输入信号同步 与 边沿检测
    //----------------------------------------------------------------
    // 将异步的 TBS_in 输入信号同步到系统时钟域，以防止亚稳态问题。
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) begin
            tbs_in_sync_d1 <= 1'b1;
            tbs_in_sync_d2 <= 1'b1;
        end else begin
            tbs_in_sync_d1 <= TBS_in;
            tbs_in_sync_d2 <= tbs_in_sync_d1;
        end
    end

    // 在同步后的信号上检测下降沿。下降沿标志着一个 '0' 比特的开始。
    assign falling_edge_detected = tbs_in_sync_d2 & ~tbs_in_sync_d1;

    //----------------------------------------------------------------
    // 脉冲拉伸核心逻辑
    //----------------------------------------------------------------
    // 当检测到下降沿时，此计数器被清零并开始为一个完整的比特周期计时。
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) begin
            stretch_cnt <= BIT_PERIOD_COUNT;
        end else if (falling_edge_detected) begin
            // 一个 '0' 比特到来，触发计时器，开始拉伸。
            stretch_cnt <= 0;
        end else if (stretch_cnt < BIT_PERIOD_COUNT) begin
            // 在一个比特周期内持续计数。
            stretch_cnt <= stretch_cnt + 1'b1;
        end else begin
            // 空闲状态或计时结束后，将计数器置于满值，等待下一次触发。
            stretch_cnt <= BIT_PERIOD_COUNT;
        end
    end

    //----------------------------------------------------------------
    // 输出信号生成
    //----------------------------------------------------------------
    // 只要拉伸计数器在工作 (计数值小于比特周期)，输出就保持为低电平。
    // 否则，输出为高电平 (空闲状态)。
    assign rs232_out = (stretch_cnt < BIT_PERIOD_COUNT) ? 1'b0 : 1'b1;

endmodule
