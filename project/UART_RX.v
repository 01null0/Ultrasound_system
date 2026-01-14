module UART_RX (
    input             clk_50M,       // 50MHz时钟
    input             rst_n,         // 复位信号
    input             rs232_rx,      // 串行数据输入
    
    output reg [23:0] rx_frame_data, // 接收到的3字节完整数据
    output reg [ 2:0] command,       // 取最低3位作为命令
    output reg        frame_valid    // 帧有效标志
);

    //参数定义
    parameter CLK_FREQ = 50_000_000;  // 系统时钟频率
    parameter BAUD_RATE = 19200;      // 波特率
    localparam BAUD_CNT_MAX = CLK_FREQ / BAUD_RATE - 1;
    localparam HALF_BAUD = BAUD_CNT_MAX / 2;

    // 帧格式定义 (ASCII码)
    localparam FRAME_HEAD = 8'h5B; // '['
    localparam FRAME_TAIL = 8'h5D; // ']'

    //信号定义
    reg [1:0] sync_regs;   // 同步寄存器
    reg [15:0] baud_cnt;   // 波特率计数器
    reg [3:0] bit_cnt;     // 数据位计数器
    reg [7:0] rx_data;     // 当前接收到的单字节
    reg       rx_done;     // 单字节接收完成标志

    // 帧处理相关信号
    reg [2:0] byte_cnt;       // 接收字节计数器 (0-4)
    reg [7:0] data_buf [2:0]; // 缓存中间的3个数据字节

    //状态定义
    localparam IDLE = 2'b00;
    localparam START = 2'b01;
    localparam DATA = 2'b10;
    localparam STOP = 2'b11;
    reg [1:0] state;

    //同步和下降沿检测
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) sync_regs <= 2'b11;
        else sync_regs <= {sync_regs[0], rs232_rx};
    end
    wire nedge_detect = (sync_regs[1] & ~sync_regs[0]);

    // -----------------------------------------------------------------
    // Part 1: UART 底层接收逻辑
    // -----------------------------------------------------------------
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) begin
            state    <= IDLE;
            baud_cnt <= 0;
            bit_cnt  <= 0;
            rx_data  <= 8'h00;
            rx_done  <= 0;
        end
        else begin
            // 1. 处理 rx_done 脉冲复位，但绝对不要清零 rx_data
            if (rx_done) 
                rx_done <= 1'b0;

            case (state)
                IDLE: begin
                    if (nedge_detect) begin
                        state <= START;
                        baud_cnt <= 0;
                    end
                end

                START: begin
                    if (baud_cnt == HALF_BAUD) begin
                        if (!sync_regs[0]) begin // 确认起始位还是低电平
                            state <= DATA;
                            baud_cnt <= 0;
                            bit_cnt <= 0;
                        end
                        else state <= IDLE; // 误触发，回空闲
                    end
                    else baud_cnt <= baud_cnt + 1;
                end

                DATA: begin
                    // 修正后的采样逻辑：等待满一个波特率周期
                    if (baud_cnt == BAUD_CNT_MAX) begin
                        baud_cnt <= 0;
                        // 此时处于数据位的中间位置，进行采样
                        rx_data[bit_cnt] <= sync_regs[0];
                        
                        if (bit_cnt == 7)
                            state <= STOP;
                        else
                            bit_cnt <= bit_cnt + 1;
                    end
                    else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end

                STOP: begin
                    if (baud_cnt == BAUD_CNT_MAX) begin
                        state <= IDLE;
                        rx_done <= 1'b1; // 接收完成，产生脉冲
                    end
                    else baud_cnt <= baud_cnt + 1;
                end
                
                default: state <= IDLE;
            endcase
        end
    end

    // -----------------------------------------------------------------
    // Part 2: 帧解析状态机 (5字节协议: [ D1 D2 D3 ])
    // -----------------------------------------------------------------
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) begin
            byte_cnt <= 0;
            rx_frame_data <= 0;
            command <= 0;
            frame_valid <= 0;
            data_buf[0] <= 0;
            data_buf[1] <= 0;
            data_buf[2] <= 0;
        end
        else begin
            frame_valid <= 0; // 默认拉低

            if (rx_done) begin // 每收到一个字节触发一次
                case (byte_cnt)
                    0: begin // 等待帧头 '['
                        if (rx_data == FRAME_HEAD) 
                            byte_cnt <= 1;
                        else 
                            byte_cnt <= 0;
                    end

                    1: begin // Data Byte 1
                        data_buf[0] <= rx_data;
                        byte_cnt <= 2;
                    end

                    2: begin // Data Byte 2
                        data_buf[1] <= rx_data;
                        byte_cnt <= 3;
                    end

                    3: begin // Data Byte 3
                        data_buf[2] <= rx_data;
                        byte_cnt <= 4;
                    end

                    4: begin // 检查帧尾 ']'
                        if (rx_data == FRAME_TAIL) begin
                            // 1. 拼接完整数据
                            rx_frame_data <= {data_buf[0], data_buf[1], data_buf[2]};
                            
                            // 2. 提取命令：取最后一个字节(data_buf[2])的最低3位
                            command <= data_buf[2][2:0]; 
                            
                            // 3. 输出有效脉冲
                            frame_valid <= 1'b1;
                        end
                        byte_cnt <= 0; // 复位状态机，准备接收下一帧
                    end
                    
                    default: byte_cnt <= 0;
                endcase
            end
        end
    end

endmodule
