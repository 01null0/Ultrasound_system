// -------------------------------------------------------------
//  tb_ortho_square.v
//  功能：对 ortho_square 进行简单功能仿真
//  观察：sq_0deg 与 sq_90deg 相位差 90°，占空比 50%
//  工具：ModelSim、VCS、XSim、Quartus Simulator 均可
// -------------------------------------------------------------
`timescale 1ns / 1ps

module tb_ortho_square;

// 参数
localparam FREQ_DIV = 5;       // 小数值方便看波形
localparam CLK_PER  = 10;      // 100 MHz 时钟

// 信号
reg  clk_50M;
reg  rst_n;
wire sq_0deg;
wire sq_90deg;

// 例化 DUT
ortho_square
#(
    .FREQ_DIV ( FREQ_DIV )
)
dut (
    .clk_50M      ( clk_50M      ),
    .rst_n    ( rst_n    ),
    .sq_0deg  ( sq_0deg  ),
    .sq_90deg ( sq_90deg )
);

// 时钟
always #(CLK_PER/2) clk_50M = ~clk_50M;

// 激励
initial begin
    clk_50M   = 0;
    rst_n = 0;
    repeat(5) @(posedge clk_50M);
    rst_n = 1;

    // 运行足够长时间，观察至少 4 个周期
    repeat(2_000) @(posedge clk_50M);
    $display("Simulation finished");
    $finish;
end

// 可选：打印变化时刻
always @(sq_0deg or sq_90deg) begin
    $timeformat(-9, 1, "ns", 6);
    $display("[%t] sq_0deg=%b sq_90deg=%b", $realtime, sq_0deg, sq_90deg);
end

// 生成 VCD/FSDB 供 GTKWave/ModelSim 查看
initial begin
    $dumpfile("ortho_square.vcd");
    $dumpvars(0, tb_ortho_square);
end

endmodule
