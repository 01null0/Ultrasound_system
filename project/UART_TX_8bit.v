module UART_TX_8bit #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 19200
) (
    input wire clk_50M,
    input wire rst_n,

    input wire [19:0] echo_tof,
    input wire        processing_done,

    output reg rs232_tx
);


    localparam BAUD_CNT_MAX = CLK_FREQ / BAUD_RATE;
    localparam CNT_WIDTH = $clog2(BAUD_CNT_MAX);

    reg [CNT_WIDTH-1:0] baud_cnt;

    reg [          7:0] frame_buf [0:4];

    reg [          1:0] sync_regs;

    //边沿检测
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) sync_regs <= 2'b00;
        else sync_regs <= {sync_regs[0], processing_done};
    end
    wire pi_flag = (sync_regs[0] & ~sync_regs[1]);  // 上升沿监测

    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) begin
            frame_buf[0] <= 8'h00;
            frame_buf[1] <= 8'h00;
            frame_buf[2] <= 8'h00;
            frame_buf[3] <= 8'h00;
            frame_buf[4] <= 8'h00;
        end
        else if (pi_flag) begin
            frame_buf[0] <= 8'h5B;
            frame_buf[1] <= {4'b0000, echo_tof[19:16]};
            frame_buf[2] <= echo_tof[15:8];
            frame_buf[3] <= echo_tof[7:0];
            frame_buf[4] <= 8'h5D;
        end
    end

    reg       sending;
    reg       load_first;
    reg [2:0] byte_idx;
    reg [3:0] bit_idx;
    reg [7:0] tx_shift;

    // 波特计数器
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) baud_cnt <= 0;
        else if (!sending) baud_cnt <= 0;
        else if (baud_cnt == BAUD_CNT_MAX - 1) baud_cnt <= 0;
        else baud_cnt <= baud_cnt + 1'b1;
    end

    // 主发送状态机
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) begin
            sending    <= 1'b0;
            load_first <= 1'b0;
            byte_idx   <= 3'd0;
            bit_idx    <= 4'd0;
            tx_shift   <= 8'd0;
            rs232_tx   <= 1'b1;
        end
        else begin
            if (pi_flag && !sending) begin
                sending    <= 1'b1;
                load_first <= 1'b1;
                byte_idx   <= 3'd0;
                bit_idx    <= 4'd0;
                tx_shift   <= 8'h5B;
            end

            if (load_first) begin
                load_first <= 1'b0;
            end
            else if (sending && baud_cnt == BAUD_CNT_MAX - 1) begin
                bit_idx <= bit_idx + 1'b1;

                case (bit_idx)
                    4'd0: rs232_tx <= 1'b0;
                    4'd1: rs232_tx <= tx_shift[0];
                    4'd2: rs232_tx <= tx_shift[1];
                    4'd3: rs232_tx <= tx_shift[2];
                    4'd4: rs232_tx <= tx_shift[3];
                    4'd5: rs232_tx <= tx_shift[4];
                    4'd6: rs232_tx <= tx_shift[5];
                    4'd7: rs232_tx <= tx_shift[6];
                    4'd8: rs232_tx <= tx_shift[7];
                    4'd9: rs232_tx <= 1'b1;
                endcase

                // 一个字节完成
                if (bit_idx == 4'd9) begin
                    bit_idx <= 4'd0;

                    if (byte_idx == 3'd4) begin
                        sending  <= 1'b0;
                        rs232_tx <= 1'b1;
                    end
                    else begin
                        byte_idx <= byte_idx + 1'b1;
                        tx_shift <= frame_buf[byte_idx+1'b1];
                    end
                end
            end

            if (!sending) rs232_tx <= 1'b1;
        end
    end

endmodule





//可用
/* module UART_TX_8bit 
#(
    parameter BAUD_RATE = 19200,      // 串口波特率
    parameter CLK_FREQ  = 50_000_000  // 系统时钟频率
)
(
    input  wire       clk_50M,     // 系统时钟
    input  wire       rst_n,       // 低电平复位
    input  wire [7:0] pi_data,     // 待发送字节
    input  wire       pi_flag,     // 数据有效脉冲

    output wire       rs_tx,       // 测试输出
    output reg        rs232_tx,          // 串口 TX
    output reg        tx_done      // 字节发送完成脉冲
);

    // 计算每个 bit 的周期
    localparam BAUD_CNT_MAX = CLK_FREQ / BAUD_RATE;
    localparam CNT_WIDTH = $clog2(BAUD_CNT_MAX);

    // 内部寄存器
    reg [CNT_WIDTH-1:0] baud_cnt;
    reg work_en;
    reg [3:0] bit_cnt;         // bit 计数 0-9
    reg [7:0] tx_data_latch;   // 锁存发送字节

	assign rs_tx = rs232_tx;

    // 发送使能
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n)
            work_en <= 1'b0;
        else if (pi_flag && !work_en)
            work_en <= 1'b1;   // 新数据到来开始发送
        else if (bit_cnt == 4'd9 && baud_cnt == BAUD_CNT_MAX-1)
            work_en <= 1'b0;   // 停止位发送完关闭
    end

    // 锁存发送字节
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n)
            tx_data_latch <= 8'd0;
        else if (pi_flag && !work_en)
            tx_data_latch <= pi_data;
    end

    // 波特率计数
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n)
            baud_cnt <= 0;
        else if (!work_en)
            baud_cnt <= 0;
        else if (baud_cnt == BAUD_CNT_MAX-1)
            baud_cnt <= 0;
        else
            baud_cnt <= baud_cnt + 1'b1;
    end

    // bit 计数器
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n)
            bit_cnt <= 4'd0;
        else if (!work_en)
            bit_cnt <= 4'd0;
        else if (baud_cnt == BAUD_CNT_MAX-1)
            bit_cnt <= bit_cnt + 1'b1;
    end

    // rs232_tx 输出逻辑
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n)
            rs232_tx <= 1'b1; // 空闲高电平
        else if (work_en) begin
            case (bit_cnt)
                0: rs232_tx <= 1'b0;               // 起始位
                1: rs232_tx <= tx_data_latch[0];
                2: rs232_tx <= tx_data_latch[1];
                3: rs232_tx <= tx_data_latch[2];
                4: rs232_tx <= tx_data_latch[3];
                5: rs232_tx <= tx_data_latch[4];
                6: rs232_tx <= tx_data_latch[5];
                7: rs232_tx <= tx_data_latch[6];
                8: rs232_tx <= tx_data_latch[7];
                9: rs232_tx <= 1'b1;               // 停止位
                default: rs232_tx <= 1'b1;
            endcase
        end else
			rs232_tx <= 1'b1;
    end

    // tx_done 单拍脉冲
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n)
            tx_done <= 1'b0;
        else if (work_en && bit_cnt == 4'd9 && baud_cnt == BAUD_CNT_MAX-1)
            tx_done <= 1'b1;
        else
            tx_done <= 1'b0;
    end

endmodule  */



/* module UART_TX_8bit 
#(
    parameter   BAUD_RATE = 19200,    // 串口波特率（单位：bps）
    parameter   CLK_FREQ = 50_000_000 // 系统时钟频率（单位：Hz）
)
(
    input   wire        clk_50M,     // 系统时钟
    input   wire        rst_n,   // 低电平复位信号
    input   wire [7:0]  pi_data, // 并行输入数据（8位）
    input   wire        pi_flag, // 数据输入有效标志
    
    output  reg         rs232_tx     ,  // 串行数据输出
	output  reg         tx_done
);

// 计算每个bit需要的时钟周期数
	localparam   BAUD_CNT_MAX = CLK_FREQ / BAUD_RATE;
    localparam CNT_WIDTH = $clog2(BAUD_CNT_MAX);

// 内部寄存器定义
reg         work_en;    // 发送使能信号
reg [CNT_WIDTH:0]  baud_cnt;   // 波特率计数器
reg         bit_flag;   // 比特发送标志
reg [3:0]   bit_cnt;    // 已发送bit计数器（0-9）

// 发送使能控制逻辑
always@(posedge clk_50M or negedge rst_n)begin
    if(!rst_n)
        work_en <= 1'b0;  // 复位时关闭发送
    else begin
        if(pi_flag == 1'b1)
            work_en <= 1'b1; // 当有数据要发送时使能
        else if((bit_cnt == 4'd9)&&(bit_flag == 1'b1))
            work_en <= 1'b0; // 发送完停止位后关闭
    end
end

// 波特率时钟计数器
always@(posedge clk_50M or negedge rst_n)begin
    if(!rst_n)
        baud_cnt <= 0; // 复位清零
    else if((baud_cnt == BAUD_CNT_MAX - 1)||(work_en == 1'b0))
        baud_cnt <= 0;  // 计数满或发送关闭时清零
    else if(work_en == 1'b1)
        baud_cnt <= baud_cnt + 1'b1; // 发送使能时计数
end

// 比特发送标志生成（每个bit周期开始时产生脉冲）
always@(posedge clk_50M or negedge rst_n)begin
    if(!rst_n)
        bit_flag <= 1'b0;
    else if (baud_cnt == 1)
        bit_flag <= 1'b1; // 每个bit开始时刻产生标志
    else 
        bit_flag <= 1'b0;
end

// 发送bit计数器（计数范围0-9）
always@(posedge clk_50M or negedge rst_n)begin
    if(!rst_n)
        bit_cnt <= 4'd0;  // 复位清零
    else if((bit_cnt == 4'd9)&&(bit_flag == 1'b1))
        bit_cnt <= 4'd0; // 发送完停止位后清零
    else if(bit_flag == 1'b1)
        bit_cnt <= bit_cnt + 1'b1; // 每个bit周期递增
    else
        bit_cnt <= bit_cnt;
end

// 单字节发送完成标志（1 clk 脉冲）
always @(posedge clk_50M or negedge rst_n) begin
    if (!rst_n)
        tx_done <= 1'b0;
    else if ((bit_cnt == 4'd9) && (bit_flag == 1'b1))
        tx_done <= 1'b1;   // 停止位结束，字节发送完成
    else
        tx_done <= 1'b0;
end


// 串行数据输出逻辑
always@(posedge clk_50M or negedge rst_n)begin
    if(!rst_n)
        rs232_tx <= 1'b1; // 复位时保持空闲状态（高电平）
    else begin // 每个bit周期开始时更新输出
        case(bit_cnt)
            0: rs232_tx <= 1'b0;         // 起始位（低电平）
            1: rs232_tx <= pi_data[0];   // 数据位0（LSB）
            2: rs232_tx <= pi_data[1];   // 数据位1
            3: rs232_tx <= pi_data[2];   // 数据位2
            4: rs232_tx <= pi_data[3];   // 数据位3
            5: rs232_tx <= pi_data[4];   // 数据位4
            6: rs232_tx <= pi_data[5];   // 数据位5
            7: rs232_tx <= pi_data[6];   // 数据位6
            8: rs232_tx <= pi_data[7];   // 数据位7（MSB）
            9: rs232_tx <= 1'b1;         // 停止位（高电平）
            default: rs232_tx <= 1'b1;   // 默认空闲状态
        endcase
	end
end

endmodule */
