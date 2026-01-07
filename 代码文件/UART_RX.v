module UART_RX (
    input             clk_50M,       // 50MHz时钟
    input             rst_n,         // 复位信号
    input             rs232_rx,      // 串行数据输入
    output reg        rx_done,       // 接收完成标志
    output     [11:0] test_rx_data,  // 接收到的数据
    output reg [ 2:0] command        // 命令输出
);
    //参数定义
    parameter CLK_FREQ = 50_000_000;  // 系统时钟频率
    parameter BAUD_RATE = 115200;  // 波特率
    //localparam BAUD_CNT_MAX = CLK_FREQ / BAUD_RATE - 1;  // 波特周期计数器最大值
    //localparam HALF_BAUD = BAUD_CNT_MAX/2;  // 半波特周期计算（651）
    localparam BAUD_CNT_MAX = 434;
    localparam HALF_BAUD = 217;

    //信号定义
    reg [ 1:0] sync_regs;  // 同步寄存器（用于亚稳态消除）
    reg [16:0] baud_cnt;  // 波特率计数器
    reg [ 3:0] bit_cnt;  // 数据位计数器
    reg        rx_en;  // 接收使能信号
    reg [ 7:0] rx_data;
    assign test_rx_data = {4'b1010, rx_data};  //测试输出

    //状态定义
    localparam IDLE = 2'b00;  // 空闲状态
    localparam START = 2'b01;  // 起始位检测
    localparam DATA = 2'b10;  // 数据位接收
    localparam STOP = 2'b11;  // 停止位接收
    reg [1:0] state;

    //同步和下降沿检测
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) sync_regs <= 2'b11;
        else sync_regs <= {sync_regs[0], rs232_rx};
    end
    wire nedge_detect = (sync_regs[1] & ~sync_regs[0]);  // 下降沿检测

    //主状态机
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) begin
            state    <= IDLE;
            baud_cnt <= 0;
            bit_cnt  <= 0;
            rx_data  <= 8'h00;
            rx_done  <= 0;
            rx_en    <= 0;
        end
        else begin
            if (rx_done) begin
                rx_done <= 1'b0;
                rx_data <= 0;
            end
            case (state)
                IDLE: begin
                    if (nedge_detect) begin  // 检测到起始位下降沿
                        state <= START;
                        baud_cnt <= 0;
                    end
                end

                START: begin  // 起始位验证
                    if (baud_cnt == HALF_BAUD) begin  // 修改为HALF_BAUD
                        if (!sync_regs[0]) begin  // 确认起始位为低
                            state <= DATA;
                            baud_cnt <= 0;
                            bit_cnt <= 0;
                        end
                        else state <= IDLE;  // 错误，返回空闲
                    end
                    else baud_cnt <= baud_cnt + 1;
                end

                DATA: begin  // 接收8位数据
                    if (baud_cnt == BAUD_CNT_MAX) begin
                        baud_cnt <= 0;
                        if (bit_cnt == 7) begin
                            state <= STOP;
                        end
                        else bit_cnt <= bit_cnt + 1;
                    end
                    else begin
                        if (baud_cnt == HALF_BAUD) begin  // 修改为HALF_BAUD
                            rx_data[bit_cnt] <= sync_regs[0];  // 在比特中间采样
                        end
                        baud_cnt <= baud_cnt + 1;
                    end
                end

                STOP: begin  // 停止位处理
                    if (baud_cnt == BAUD_CNT_MAX) begin
                        if (sync_regs[0] == 1'b1) begin  // 验证停止位为高
                            rx_done <= 1'b1;  // 数据接收完成
                        end
                        state <= IDLE;
                    end
                    else baud_cnt <= baud_cnt + 1;
                end
            endcase
        end
    end

    //命令解码
    wire [7:0] cmd = rx_data;
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) begin
            command <= 0;
        end
        else begin
            case (cmd)
                8'h00: command <= 0;
                8'h01: command <= 1;
                8'h02: command <= 2;
                8'h03: command <= 3;
                8'h04: command <= 4;
                8'h05: command <= 5;
                8'h06: command <= 6;
                8'h07: command <= 7;
                8'h08: command <= 8;

                default: command <= 0;
            endcase
        end
    end
endmodule
