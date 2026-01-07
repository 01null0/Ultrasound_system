module UART_TX (
    input        clk_50M,         // 50MHz系统时钟
    input        rst_n,           // 低电平复位

    input [19:0] echo_tof,        // 回波飞行时间 (20bit)
    input [17:0] echo_peak,       // (已废弃) 峰值数据，模块内不使用
    input        processing_done, // 发送触发信号

    output reg   rs232_tx,        // 串口发送线
    output       tx_busy          // 忙标志
);

    // ==========================================
    // 参数定义
    // ==========================================
    parameter CLK_FREQ  = 50_000_000;
    parameter BAUD_RATE = 115200;
    localparam BAUD_CNT_MAX = CLK_FREQ / BAUD_RATE - 1; 

    localparam S_IDLE  = 3'd0;
    localparam S_START = 3'd1;
    localparam S_DATA  = 3'd2;
    localparam S_STOP  = 3'd3;

    // ==========================================
    // 内部信号
    // ==========================================
    reg [2:0] state;
    reg [8:0] baud_cnt;
    reg       bit_flag;
    reg [2:0] bit_cnt;
    
    // --- 修改点：Buffer 大小改为 40位 (5字节) ---
    // 结构: [Header(8)] + [TOF_H, TOF_M, TOF_L] + [Tail(8)]
    reg [39:0] tx_packet_buffer;
    
    reg [2:0]  byte_index;    // 当前字节索引 (0-4)
    reg [7:0]  current_byte;  // 当前发送字节
    
    reg processing_done_d0;
    reg processing_done_d1;
    wire send_trigger;

    // ==========================================
    // 逻辑实现
    // ==========================================

    // 1. 边沿检测
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) begin
            processing_done_d0 <= 1'b0;
            processing_done_d1 <= 1'b0;
        end else begin
            processing_done_d0 <= processing_done;
            processing_done_d1 <= processing_done_d0;
        end
    end
    assign send_trigger = processing_done_d0 && !processing_done_d1;

    // 2. 波特率生成
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) begin
            baud_cnt <= 9'd0;
            bit_flag <= 1'b0;
        end
        else if (state == S_IDLE) begin
            baud_cnt <= 9'd0;
            bit_flag <= 1'b0;
        end
        else begin
            if (baud_cnt == BAUD_CNT_MAX) begin
                baud_cnt <= 9'd0;
                bit_flag <= 1'b1;
            end
            else begin
                baud_cnt <= baud_cnt + 1'b1;
                bit_flag <= 1'b0;
            end
        end
    end

    // 3. 发送状态机
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            rs232_tx <= 1'b1;
            tx_packet_buffer <= 40'd0;
            byte_index <= 3'd0;
            current_byte <= 8'd0;
            bit_cnt <= 3'd0;
        end
        else begin
            case (state)
                S_IDLE: begin
                    rs232_tx <= 1'b1;
                    byte_index <= 3'd0;
                    
                    if (send_trigger) begin
                        // --- 修改点：组包 5 字节 ---
                        // Echo_peak 被忽略
                        tx_packet_buffer <= {
                            8'hFA,                  // Byte 0: Header
                            4'b0000, echo_tof,      // Byte 1-3: TOF (24bit)
                            8'hFB                   // Byte 4: Tail
                        };
                        current_byte <= 8'hFA; 
                        state <= S_START;
                    end
                end

                S_START: begin
                    rs232_tx <= 1'b0;
                    if (bit_flag) begin
                        state <= S_DATA;
                        bit_cnt <= 3'd0;
                    end
                end

                S_DATA: begin
                    rs232_tx <= current_byte[bit_cnt];
                    if (bit_flag) begin
                        if (bit_cnt == 3'd7) begin
                            state <= S_STOP;
                        end
                        else begin
                            bit_cnt <= bit_cnt + 1'b1;
                        end
                    end
                end

                S_STOP: begin
                    rs232_tx <= 1'b1;
                    if (bit_flag) begin
                        // --- 修改点：判断是否发完 5 字节 (索引 0-4) ---
                        if (byte_index == 3'd4) begin
                            state <= S_IDLE;
                        end
                        else begin
                            byte_index <= byte_index + 1'b1;
                            // --- 修改点：移位取数逻辑 ---
                            // Buffer: [39:0]
                            // Byte 1: [31:24], Byte 2: [23:16], Byte 3: [15:8], Byte 4: [7:0]
                            case (byte_index + 1'b1)
                                3'd1: current_byte <= tx_packet_buffer[31:24]; // TOF High
                                3'd2: current_byte <= tx_packet_buffer[23:16]; // TOF Mid
                                3'd3: current_byte <= tx_packet_buffer[15:8];  // TOF Low
                                3'd4: current_byte <= tx_packet_buffer[7:0];   // Tail (0xFB)
                                default: current_byte <= 8'h00;
                            endcase
                            state <= S_START;
                        end
                    end
                end
                
                default: state <= S_IDLE;
            endcase
        end
    end

    assign tx_busy = (state != S_IDLE);

endmodule
