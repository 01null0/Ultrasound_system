module Ack_Start_Controller #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 19200,
    parameter WAIT_TIME_MS = 10      // 启动命令应答后的等待时间 10ms
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [2:0] rx_cmd_in,     // 来自 UART_RX 的原始命令(脉冲信号)
    output reg  [2:0] sys_cmd_out,   // 发送给 Order_4s 的命令(脉冲信号)
    output reg        ack_tx_line    // 模块独占的 TX 输出线
);

    // ============================================================
    // 参数定义
    // ============================================================
    localparam CNT_1MS      = CLK_FREQ / 1000;
    localparam DELAY_CYCLES = CNT_1MS * WAIT_TIME_MS;
    localparam BAUD_CNT_MAX = CLK_FREQ / BAUD_RATE;

    // 状态定义
    localparam S_IDLE       = 3'd0; // 空闲
    localparam S_SEND_ACK   = 3'd1; // 发送应答
    localparam S_WAIT_DELAY = 3'd2; // 等待延时 (仅针对启动命令)
    localparam S_TRIGGER    = 3'd3; // 触发系统启动/命令

    reg [2:0]  state;
    reg [31:0] delay_cnt;
    reg [2:0]  latched_cmd;         // 新增：用于锁存上位机发来的命令脉冲

    // UART 发送相关寄存器
    reg [12:0] baud_cnt;
    reg [3:0]  bit_idx;
    reg [2:0]  byte_idx;
    reg [7:0]  tx_shift;
    
    wire baud_tick = (baud_cnt == BAUD_CNT_MAX - 1);

    // ============================================================
    // 逻辑实现
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state       <= S_IDLE;
            sys_cmd_out <= 3'd0;
            ack_tx_line <= 1'b1; // UART 空闲为高
            baud_cnt    <= 0;
            delay_cnt   <= 0;
            latched_cmd <= 3'd0;
        end
        else begin
            case(state)
                // ------------------------------------------------
                // 空闲状态：拦截所有有效命令
                // ------------------------------------------------
                S_IDLE: begin
                    ack_tx_line <= 1'b1;
                    baud_cnt    <= 0;
                    sys_cmd_out <= 3'd0; // 确保向 Order_4s 输出的平时为0
                    
                    if (rx_cmd_in != 3'd0) begin
                        // 拦截到任何有效命令，锁存并开始应答流程
                        latched_cmd <= rx_cmd_in;
                        state       <= S_SEND_ACK;
                        byte_idx    <= 0;
                        bit_idx     <= 0;
                        tx_shift    <= 8'h7B; // 加载首字节
                    end
                end

                // ------------------------------------------------
                // 发送应答状态：发送 7B AA AA AA 7D
                // ------------------------------------------------
                S_SEND_ACK: begin
                    // 波特率计数
                    if (baud_tick) baud_cnt <= 0;
                    else baud_cnt <= baud_cnt + 1;

                    if (baud_tick) begin
                        if (bit_idx == 9) begin
                            bit_idx <= 0;
                            if (byte_idx == 4) begin
                                // 5个字节发送完毕，进入延时判定阶段
                                state <= S_WAIT_DELAY;
                                delay_cnt <= 0;
                            end
                            else begin
                                byte_idx <= byte_idx + 1;
                                // 准备下一个字节
                                case(byte_idx + 1)
                                    1: tx_shift <= 8'hAA;
                                    2: tx_shift <= 8'hAA;
                                    3: tx_shift <= 8'hAA;
                                    4: tx_shift <= 8'h7D;
                                endcase
                            end
                        end
                        else begin
                            bit_idx <= bit_idx + 1;
                        end
                    end
                    
                    // 输出 TX 引脚
                    case(bit_idx)
                        0: ack_tx_line <= 1'b0;        // Start
                        1: ack_tx_line <= tx_shift[0];
                        2: ack_tx_line <= tx_shift[1];
                        3: ack_tx_line <= tx_shift[2];
                        4: ack_tx_line <= tx_shift[3];
                        5: ack_tx_line <= tx_shift[4];
                        6: ack_tx_line <= tx_shift[5];
                        7: ack_tx_line <= tx_shift[6];
                        8: ack_tx_line <= tx_shift[7];
                        9: ack_tx_line <= 1'b1;        // Stop
                    endcase
                end

                // ------------------------------------------------
                // 延时状态：启动命令延时10ms，其他命令直接触发
                // ------------------------------------------------
                S_WAIT_DELAY: begin
                    ack_tx_line <= 1'b1;
                    if (latched_cmd == 3'd3) begin
                        // 如果是启动测量命令，延时 10ms
                        if (delay_cnt >= DELAY_CYCLES) begin
                            state <= S_TRIGGER;
                        end
                        else begin
                            delay_cnt <= delay_cnt + 1;
                        end
                    end 
                    else begin
                        // 如果是其他模式切换命令，无需延时，直接触发执行
                        state <= S_TRIGGER;
                    end
                end

                // ------------------------------------------------
                // 触发状态：向 Order_4s 发送命令脉冲
                // ------------------------------------------------
                S_TRIGGER: begin
                    // 将锁存的命令输出给 Order_4s
                    sys_cmd_out <= latched_cmd;
                    // 下一个时钟周期即回到 S_IDLE，从而产生单周期脉冲
                    state <= S_IDLE; 
                end
                
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
