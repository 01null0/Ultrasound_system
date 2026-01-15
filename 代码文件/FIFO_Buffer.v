module FIFO_Buffer (
    input         clk,          // 50MHz
    input         rst_n,
    
    // 写接口 (连接 AD)
    input         wr_en,        // AD 完成信号 (ad_done)
    input  [11:0] wr_data,      // AD 数据 (ad_out)
    output        full,         // 缓存满了，通知 Order_4s 停止采样
    
    // 读接口 (连接 UART)
    input         rd_req,       // UART 空闲时请求读取
    output [11:0] rd_data,      // 发送给 UART 的数据
    output reg    rd_valid,     // 读出数据有效 (作为 UART 的 ad_done)
    output        empty         // 缓存空了
);

    // 定义缓存深度：4096 个点 (占用 EP4CE10 约 12% 的内存)
    parameter DEPTH = 4096;
    parameter ADDR_W = 12; // 2^12 = 4096

    reg [11:0] mem [0:DEPTH-1]; // 定义 RAM
    reg [ADDR_W-1:0] wr_ptr;
    reg [ADDR_W-1:0] rd_ptr;
    reg [ADDR_W:0]   cnt;       // 数据量计数器

    assign full  = (cnt >= DEPTH);
    assign empty = (cnt == 0);
    assign rd_data = mem[rd_ptr]; // 读出数据

    // 写逻辑
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 0;
        end else if (wr_en && !full) begin
            mem[wr_ptr] <= wr_data;
            wr_ptr <= wr_ptr + 1;
        end
    end

    // 读逻辑
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr <= 0;
            rd_valid <= 0;
        end else begin
            rd_valid <= 0; // 默认拉低
            if (rd_req && !empty) begin
                rd_ptr <= rd_ptr + 1;
                rd_valid <= 1; // 产生一个脉冲告诉 UART 数据好了
            end
        end
    end

    // 计数器逻辑
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt <= 0;
        end else begin
            case ({wr_en && !full, rd_req && !empty})
                2'b10: cnt <= cnt + 1; // 只写
                2'b01: cnt <= cnt - 1; // 只读
                default: cnt <= cnt;   // 同时读写或无操作
            endcase
        end
    end

endmodule
