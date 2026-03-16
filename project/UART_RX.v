module UART_RX (
    input             clk_50M,       // 50MHz时钟
    input             rst_n,         // 复位信号
    input             rs232_rx,      // 串行数据输入
    
    // 调试用：输出完整的24位数据包 [Flag(4) + Data(20)]
    output reg [23:0] rx_frame_data, 
  
    // 解析后的控制信号
    output reg [ 2:0] command,       // 标志位为0时更新，脉冲信号(默认0)
    output reg [17:0] corr_threshold,// 标志位为1时更新，保持信号(默认2000)
    
    output reg        frame_valid    // 帧接收成功脉冲
);
    //参数定义
    parameter CLK_FREQ = 50_000_000;
    parameter BAUD_RATE = 19200; // 默认19200，可由上层 parameter 覆盖
    
    localparam BAUD_CNT_MAX = CLK_FREQ / BAUD_RATE - 1;
    localparam HALF_BAUD = BAUD_CNT_MAX / 2;

    // 帧定义
    localparam FRAME_HEAD = 8'h5B; // '['
    localparam FRAME_TAIL = 8'h5D; // ']'

    // 信号定义
    reg [1:0] sync_regs;
    reg [15:0] baud_cnt;
    reg [3:0] bit_cnt;
    reg [7:0] rx_data;
    reg       rx_done;

    // 帧解析状态
    reg [2:0] byte_cnt;       // 0~4
    reg [7:0] data_buf [2:0]; // 缓存中间3个字节

    // 状态机
    localparam IDLE = 2'b00;
    localparam START = 2'b01;
    localparam DATA = 2'b10;
    localparam STOP = 2'b11;
    reg [1:0] state;

    // -----------------------------------------------------------
    // 同步处理
    // -----------------------------------------------------------
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) sync_regs <= 2'b11;
        else sync_regs <= {sync_regs[0], rs232_rx};
    end
    wire nedge_detect = (sync_regs[1] & ~sync_regs[0]);

    // -----------------------------------------------------------
    // Part 1: UART 底层字节接收 (保持不变)
    // -----------------------------------------------------------
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) begin
            state    <= IDLE;
            baud_cnt <= 0;
            bit_cnt  <= 0;
            rx_data  <= 0;
            rx_done  <= 0;
        end
        else begin
            if (rx_done) rx_done <= 1'b0; // 脉冲复位

            case (state)
                IDLE: begin
                    if (nedge_detect) begin
                        state <= START;
                        baud_cnt <= 0;
                    end
                end
                START: begin
                    if (baud_cnt == HALF_BAUD) begin
                        if (!sync_regs[0]) begin
                             state <= DATA;
                             baud_cnt <= 0;
                             bit_cnt <= 0;
                        end
                        else state <= IDLE;
                    end
                    else baud_cnt <= baud_cnt + 1;
                end
                DATA: begin
                    if (baud_cnt == BAUD_CNT_MAX) begin
                        baud_cnt <= 0;
                        rx_data[bit_cnt] <= sync_regs[0]; 
                        if (bit_cnt == 7) state <= STOP;
                        else bit_cnt <= bit_cnt + 1;
                    end
                    else baud_cnt <= baud_cnt + 1;
                end
                STOP: begin
                    if (baud_cnt == BAUD_CNT_MAX) begin
                        state <= IDLE;
                        rx_done <= 1'b1; // 字节完成
                    end
                    else baud_cnt <= baud_cnt + 1;
                end
                default: state <= IDLE;
            endcase
        end
    end

    // -----------------------------------------------------------
    // Part 2: 5字节帧解析逻辑 (核心修改部分)
    // -----------------------------------------------------------
    
    // 辅助信号：提取24位Payload中的字段
    // Payload结构: [Byte1(Data1)] [Byte2(Data2)] [Byte3(Data3)]
    // Flag: Data1的高4位
    // Data: Data1的低4位 + Data2 + Data3 (共20位)
    wire [3:0]  pkg_flag = data_buf[0][7:4];//
    wire [19:0] pkg_data = {data_buf[0][3:0], data_buf[1], data_buf[2]};

    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) begin
            byte_cnt <= 0;
            rx_frame_data <= 0;
            
            command <= 0;           // 命令默认 0
            corr_threshold <= 18'd500; // 【关键】阈值默认 2000
            
            frame_valid <= 0;
            data_buf[0] <= 0; data_buf[1] <= 0; data_buf[2] <= 0;
        end
        else begin
            frame_valid <= 0;
            command <= 0; // 命令是脉冲信号，自动清零
            // 注意：corr_threshold 不自动清零，保持上一次的值

            if (rx_done) begin
                case (byte_cnt)
                    0: begin // 找帧头
                        if (rx_data == FRAME_HEAD) byte_cnt <= 1;
                        else byte_cnt <= 0;
                    end
                    1: begin // Data 1 (高8位，含标志位)
                        data_buf[0] <= rx_data;
                        byte_cnt <= 2;
                    end
                    2: begin // Data 2 (中8位)
                        data_buf[1] <= rx_data;
                        byte_cnt <= 3;
                    end
                    3: begin // Data 3 (低8位)
                        data_buf[2] <= rx_data;
                        byte_cnt <= 4;
                    end
                    4: begin // 校验帧尾
                        if (rx_data == FRAME_TAIL) begin
                            // 1. 组合完整数据用于调试
                            rx_frame_data <= {data_buf[0], data_buf[1], data_buf[2]};
                            
                            // 2. 根据标志位分发数据
                            case (pkg_flag)
                                4'b0100: begin // 标志位 0：控制命令
                                    if (data_buf[2] == 8'h40)
                                        command <= 3'd2; // 强制映射给 Order_4s 的垂直度(断电)命令
                                    else if (data_buf[2] == 8'h41)
                                        command <= 3'd1; // 强制映射给 Order_4s 的井径命令
                                    else if (data_buf[2] == 8'h43)
                                        command <= 3'd3; // 强制映射给 Order_4s 的开始命令
                                    else
                                        command <= 3'd0;
                                end
                                4'b0101: begin // 标志位 1：设置阈值
                                    corr_threshold <= pkg_data[17:0]; // 取低18位作为阈值
                                end
                                default: begin
                                    // 未知标志位
                                end
                            endcase
                            
                            frame_valid <= 1'b1;
                        end
                        byte_cnt <= 0; // 复位状态机
                    end
                    default: byte_cnt <= 0;
                endcase
            end
        end
    end
endmodule
