module UART_TX_8bit #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 19200
) (
    input wire clk_50M,
    input wire rst_n,

    // 控制接口
    input wire batch_start,  // 开始4s采集 (发送大帧头)
    input wire batch_end,    // 结束4s采集 (发送大帧尾)

    // 数据接口
    input wire [19:0] echo_tof,        // 回波数据
    input wire        processing_done, // 数据有效脉冲

    output reg rs232_tx
);
    localparam BAUD_CNT_MAX = CLK_FREQ / BAUD_RATE;

    // 状态定义
    localparam S_IDLE = 3'd0;
    localparam S_SEND_HEAD = 3'd1;  // 发送 7B 00 00 AA 7D
    localparam S_WAIT_DATA = 3'd2;  // 等待数据或结束信号
    localparam S_SEND_DATA = 3'd3;  // 发送 3字节 TOF
    localparam S_SEND_TAIL = 3'd4;  // 发送 7B 00 00 FF 7D

    reg [ 2:0] state;
    reg [ 2:0] byte_idx;  // 当前发送的字节索引
    reg [12:0] baud_cnt;
    reg [ 3:0] bit_idx;
    // reg [7:0] tx_data; // 未使用，注释掉
    reg [ 7:0] tx_shift;  // 当前发送字节的移位寄存器

    // 数据缓存
    reg [23:0] data_latch;  // 缓存20位数据 (填充为24位)
    reg        end_pending;  // 如果在发数据时来了结束信号，先记下来

    // 边沿检测 processing_done
    reg [ 1:0] pd_sync;
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) pd_sync <= 2'b00;
        else pd_sync <= {pd_sync[0], processing_done};
    end
    wire pd_rise = (pd_sync[0] & ~pd_sync[1]);

    // ============================================================
    // 【修改点1】集中控制 baud_cnt
    // 只在这里对 baud_cnt 进行赋值，不要在下面的状态机里赋值
    // ============================================================
    wire baud_tick = (baud_cnt == BAUD_CNT_MAX - 1);

    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) begin
            baud_cnt <= 0;
        end
        // 当处于空闲或等待状态时，强制复位计数器，
        // 这样一旦跳入发送状态，计数器就从0开始，Start位时序就是对的。
        else if (state == S_IDLE || state == S_WAIT_DATA) begin
            baud_cnt <= 0;
        end
        // 正常计数逻辑
        else if (baud_tick) begin
            baud_cnt <= 0;
        end
        else begin
            baud_cnt <= baud_cnt + 1'b1;
        end
    end

    // ============================================================
    // 主状态机
    // ============================================================
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            rs232_tx <= 1'b1;
            bit_idx <= 0;
            byte_idx <= 0;
            end_pending <= 0;
            tx_shift <= 0;
        end
        else begin
            // 记录结束请求
            if (batch_end) end_pending <= 1'b1;
            else if (state == S_IDLE) end_pending <= 1'b0;

            case (state)
                S_IDLE: begin
                    rs232_tx <= 1'b1;
                    if (batch_start) begin
                        state <= S_SEND_HEAD;
                        byte_idx <= 0;
                        bit_idx <= 0;
                        // baud_cnt <= 0; // 【修改点2】移除此处的赋值，由上面 always 块统一控制
                        // 加载帧头第一个字节
                        tx_shift <= 8'h7B;
                    end
                end

                S_SEND_HEAD: begin  // 发送 7B 00 00 AA 7D
                    if (baud_tick) begin
                        if (bit_idx == 9) begin
                            bit_idx <= 0;
                            if (byte_idx == 4) begin
                                state <= S_WAIT_DATA;  // 头发送完毕
                            end
                            else begin
                                byte_idx <= byte_idx + 1'b1;
                                // 准备下一个字节
                                case (byte_idx + 1)
                                    1: tx_shift <= 8'h00;
                                    2: tx_shift <= 8'h00;
                                    3: tx_shift <= 8'hAA;
                                    4: tx_shift <= 8'h7D;
                                endcase
                            end
                        end
                        else begin
                            bit_idx <= bit_idx + 1'b1;
                        end
                    end
                    update_tx_pin();
                end

                S_WAIT_DATA: begin
                    rs232_tx <= 1'b1;
                    bit_idx  <= 0;
                    byte_idx <= 0;
                    // baud_cnt <= 0; // 【修改点2】移除此处的赋值

                    if (pd_rise) begin
                        // 锁存数据，准备发送 (24位: 4位0 + 20位TOF)
                        data_latch <= {4'b0000, echo_tof};

                        // 【修改】先加载单包帧头 0x7B
                        tx_shift <= 8'h7B;

                        state <= S_SEND_DATA;
                    end
                    else if (end_pending || batch_end) begin
                        // 如果没有数据了且收到结束信号，发尾部
                        state <= S_SEND_TAIL;
                        byte_idx <= 0;
                        tx_shift <= 8'h7B;
                    end
                end

                // ---------------- 修改后 ----------------
                S_SEND_DATA: begin // 发送 5字节：7B + Data[23:16] + Data[15:8] + Data[7:0] + 7D
                    if (baud_tick) begin
                        if (bit_idx == 9) begin
                            bit_idx <= 0;

                            // 【修改】改为发送 5 个字节 (索引 0~4)
                            if (byte_idx == 4) begin
                                state <= S_WAIT_DATA;
                            end
                            else begin
                                byte_idx <= byte_idx + 1'b1;
                                // 【修改】状态机序列填充
                                case (byte_idx + 1)
                                    1: tx_shift <= data_latch[23:16];  // Data Byte 1 (高位)
                                    2: tx_shift <= data_latch[15:8];  // Data Byte 2 (中位)
                                    3: tx_shift <= data_latch[7:0];  // Data Byte 3 (低位)
                                    4: tx_shift <= 8'h7D;  // Tail Byte (帧尾)
                                endcase
                            end
                        end
                        else begin
                            bit_idx <= bit_idx + 1'b1;
                        end
                    end
                    update_tx_pin();
                end

                S_SEND_TAIL: begin  // 发送 7B 00 00 FF 7D
                    if (baud_tick) begin
                        if (bit_idx == 9) begin
                            bit_idx <= 0;
                            if (byte_idx == 4) begin
                                state <= S_IDLE;  // 全部结束
                                end_pending <= 0;
                            end
                            else begin
                                byte_idx <= byte_idx + 1'b1;
                                case (byte_idx + 1)
                                    1: tx_shift <= 8'h00;
                                    2: tx_shift <= 8'h00;
                                    3: tx_shift <= 8'hFF;
                                    4: tx_shift <= 8'h7D;
                                endcase
                            end
                        end
                        else begin
                            bit_idx <= bit_idx + 1'b1;
                        end
                    end
                    update_tx_pin();
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    // 辅助任务：更新TX引脚状态
    task update_tx_pin;
        begin
            case (bit_idx)
                0: rs232_tx <= 1'b0;  // Start bit
                1: rs232_tx <= tx_shift[0];
                2: rs232_tx <= tx_shift[1];
                3: rs232_tx <= tx_shift[2];
                4: rs232_tx <= tx_shift[3];
                5: rs232_tx <= tx_shift[4];
                6: rs232_tx <= tx_shift[5];
                7: rs232_tx <= tx_shift[6];
                8: rs232_tx <= tx_shift[7];
                9: rs232_tx <= 1'b1;  // Stop bit
                default: rs232_tx <= 1'b1;
            endcase
        end
    endtask

endmodule
