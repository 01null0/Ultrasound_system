module ortho_square
#(
    parameter FREQ_DIV = 250_000      // 半周期计数值，可外部例化时覆盖
)
(
    input  wire clk_50M,             // 系统时钟
    input  wire rst_n,           // 低电平异步复位
    output reg  sq_0deg,         // 0° 方波
    output reg  sq_90deg         // 90° 方波
);

// 计数器位宽自动计算
localparam CTR_WIDTH = $clog2(FREQ_DIV);
reg [CTR_WIDTH-1:0] cnt;

// 计数器逻辑
always @(posedge clk_50M or negedge rst_n) begin
    if (!rst_n) begin
        cnt <= 0;
    end
    else if (cnt == FREQ_DIV - 1) begin
        cnt <= 0;
    end
    else begin
        cnt <= cnt + 1'b1;
    end
end

// 0° 方波：半周期翻转
always @(posedge clk_50M or negedge rst_n) begin
    if (!rst_n)
        sq_0deg <= 1'b0;
    else if (cnt == FREQ_DIV - 1)
        sq_0deg <= ~sq_0deg;
end


always @(posedge clk_50M or negedge rst_n) begin
    if (!rst_n)
        sq_90deg <= 1'b0;
    else if (cnt == (FREQ_DIV >> 1) - 1)
        sq_90deg <= ~sq_90deg;
end

endmodule
