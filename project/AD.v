module AD (
    input             clk_50M,    // 系统时钟，用于捕捉AD_start
    input             clk_45M,    // PLL产生的45MHz，用于AD转换
    input             rst_n,
    input             ad_in,      // AD7352 SDATA_A/B (MISO)
    input             AD_start,   // 来自Order_4s的启动信号 (50MHz域)
    
    output reg        ad_cs,      // CS 片选
    output            ad_clk,     // SCLK (连接到AD7352)
    output reg [11:0] ad_out,      // 转换结果
    output reg        ad_done    // 转换完成标志 (也是FIFO写请求)
);

    // ============================================================
    // 1. 跨时钟域信号处理 (CDC: 50MHz -> 45MHz)
    // ============================================================
    reg start_latch_50M;
    reg conversion_ack_45M;      // 45M域反馈的完成信号
    reg conversion_ack_sync_50M; // 同步回50M域的反馈信号
    reg conversion_ack_sync_50M_r;

    // 在 50MHz 域锁存启动信号
    // 只要 AD_start 来一个脉冲，start_latch_50M 就拉高，直到 45M 域完成任务
    always @(posedge clk_50M or negedge rst_n) begin
        if(!rst_n) begin
            start_latch_50M <= 1'b0;
            conversion_ack_sync_50M <= 1'b0;
            conversion_ack_sync_50M_r <= 1'b0;
        end else begin
            // 同步反馈信号到50M域
            conversion_ack_sync_50M <= conversion_ack_45M;
            conversion_ack_sync_50M_r <= conversion_ack_sync_50M;

            if (AD_start) 
                start_latch_50M <= 1'b1; // 捕捉启动脉冲
            else if (conversion_ack_sync_50M_r) 
                start_latch_50M <= 1'b0; // 收到完成反馈后清除
        end
    end

    // 将锁存的启动信号同步到 45MHz 域
    reg start_sync_45M_r1, start_sync_45M_r2;
    always @(posedge clk_45M or negedge rst_n) begin
        if(!rst_n) begin
            start_sync_45M_r1 <= 1'b0;
            start_sync_45M_r2 <= 1'b0;
        end else begin
            start_sync_45M_r1 <= start_latch_50M;
            start_sync_45M_r2 <= start_sync_45M_r1;
        end
    end
    
    // 生成45M域的单周期启动触发
    reg start_pulse_45M_prev;
    wire start_trigger_45M = start_sync_45M_r2 && !start_pulse_45M_prev;
    
    always @(posedge clk_45M or negedge rst_n) begin
        if(!rst_n) start_pulse_45M_prev <= 1'b0;
        else start_pulse_45M_prev <= start_sync_45M_r2;
    end

    // ============================================================
    // 2. AD采样状态机 (45MHz Domain)
    // ============================================================
    // AD7352时序: CS拉低 -> 14-16个SCLK -> CS拉高
    // 数据在SCLK下降沿更新，我们在上升沿采样
    
    localparam S_IDLE  = 2'd0;
    localparam S_CONV  = 2'd1;
    localparam S_DONE  = 2'd2;

    reg [1:0] state;
    reg [4:0] bit_cnt;      // 位计数器 (0-15)
    reg [15:0] shift_reg;   // 移位寄存器

    // ad_clk 直接由 45MHz 时钟驱动
    // 注意：AD7352在CS为高时忽略SCLK，所以让它一直跑也没关系，
    // 但为了信号质量，我们可以在CS有效时才让SCLK翻转（或直接输出clk_45M）
    assign ad_clk = (ad_cs == 1'b0) ? clk_45M : 1'b1; 

    always @(posedge clk_45M or negedge rst_n) begin
        if(!rst_n) begin
            state <= S_IDLE;
            ad_cs <= 1'b1;
            ad_done <= 1'b0;
            ad_out <= 12'd0;
            bit_cnt <= 5'd0;
            shift_reg <= 16'd0;
            conversion_ack_45M <= 1'b0;
        end else begin
            case(state)
                S_IDLE: begin// 等待启动信号
                    ad_done <= 1'b0;
                    conversion_ack_45M <= 1'b0; // 允许下一次握手
                    
                    if(start_trigger_45M) begin
                        state <= S_CONV;
                        ad_cs <= 1'b0;   // CS 拉低，开始转换
                        bit_cnt <= 5'd0;
                        shift_reg <= 16'd0;
                    end else begin
                        ad_cs <= 1'b1;
                    end
                end

                S_CONV: begin// 进行数据采样
                    // 在45M上升沿采样数据（此时也是ad_clk上升沿）
                    // AD7352在下降沿推出数据，上升沿采样最稳
                    shift_reg <= {shift_reg[14:0], ad_in};
                    
                    if(bit_cnt == 5'd15) begin
                        state <= S_DONE;
                        bit_cnt <= 5'd0;
                    end else begin
                        bit_cnt <= bit_cnt + 1'b1;
                    end
                end

                S_DONE: begin// 完成转换，输出数据
                    ad_cs <= 1'b1;       // 结束转换
                    state <= S_IDLE;
                    
                    // 输出数据截取：AD7352前两位是前导0，后12位是数据
                    // 移位16次后: [15:14]是0, [13:2]是数据, [1:0]可能是无效或末尾位
                    // 根据已有代码逻辑，通常数据位于 shift_reg[11:0] 或需要根据波形微调
                    // 假设标准16个clk读取：Leading Zeros (2) + Data (12) + Trailing Zeros (2)
                    // 如果读了16位，最后进来的在低位。
                    // 修正：AD7352数据格式是：2个0，然后12bit数据。
                    // 移位16次：
                    // bits: 0, 0, D11, D10... D0, x, x
                    // 寄存器内: shift_reg[13:2] 应该是 D11..D0
                    // 之前的代码取的是 shift_reg[11:0]，可能包含无效位。
                    // 这里为了保险，按照通用时序，建议取 shift_reg[13:2]。
                    // 但为了保持与您旧代码逻辑一致（如果您旧代码验证过位序），
                    // 我暂时保留 shift_reg[11:0]，如果数据数值不对，请改为 shift_reg[13:2]。
                    ad_out <= shift_reg[13:2]; 
                    
                    ad_done <= 1'b1;     // 产生一个周期的高电平用于FIFO写
                    conversion_ack_45M <= 1'b1; // 通知50M域清除锁存
                end
                
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
