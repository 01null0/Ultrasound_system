// //无延时
// module ultrasound_launch_90KHz_10ms 
// #(
// 	parameter CNT_MAX		= 11'd1_666,			// 3*11us / 20ns = 1_666       90KHz对应的时间周期约为11us
// 	parameter CNT_10M		= 19'd499_999			// 10_000_000ns / 20ns = 500_000
// )
// (
// 	input 	wire 	clk_50M	,      
// 	input 	wire 	rst_n	,        
// //	input 	wire 	launch_cmd,//激发命令：1激发；0不激发
// 	output 	reg 	VIN_1	,   // 通道 1 输出
// 	output 	reg 	VIN_2	,   // 通道 2 输出
// 	output 	reg 	VIN_3	,   // 通道 3 输出
// 	output 	reg 	VIN_4    	// 通道 4 输出
// );

// reg key_flag;
// reg [18:0] cnt_10ms;

// always@(posedge clk_50M or negedge rst_n)begin
// 	if(!rst_n)
// 		cnt_10ms <= 19'd0;
// 	else if(cnt_10ms == CNT_10M)
// 		cnt_10ms <= 19'd0;
// 	else 
// 		cnt_10ms <= cnt_10ms + 19'd1;
// end

// always@(posedge clk_50M or negedge rst_n)begin
// 	if(!rst_n)
// 		key_flag <= 1'b0;
// 	else if(cnt_10ms == CNT_10M)
// 		key_flag <= 1'b1;
// 	else 
// 		key_flag <= 1'b0;
// end

// reg work_en;
// reg [10:0] cnt_en;      // 33us 计数器

// // 使能控制信号
// always @(posedge clk_50M or negedge rst_n) begin
// 	if (!rst_n) begin
// 		work_en <= 1'b0;
// 	end else if (cnt_en == CNT_MAX) begin
// 		work_en <= 1'b0;
// 	end else if ((key_flag && cnt_en == CNT_MAX) || (rst_n && cnt_en == 0)) begin
// 		work_en <= 1'b1;
// 	end
// end

// // 33us 计数器
// always @(posedge clk_50M or negedge rst_n) begin
// 	if (!rst_n) begin
// 		cnt_en <= 11'd0;
// 	end else if (key_flag) begin
// 		cnt_en <= 11'd0;
// 	end else if (work_en && cnt_en <= CNT_MAX) begin
// 		cnt_en <= cnt_en + 11'd1;
// 	end
// end

// // VIN_1 control (翻转 at 262, 550, 812, 1100, 1362, 1650)
// always @(posedge clk_50M or negedge rst_n) begin
// 	if (!rst_n) begin
// 		VIN_1 <= 1'b0;
// 	end else if (rst_n && cnt_en == 0) begin  // Reset released
// 		VIN_1 <= 1'b1;
// 	end else if (!work_en) begin
// 		VIN_1 <= 1'b0;
// 	end else if ((cnt_en == 13'd262) || (cnt_en == 13'd550) || 
// 				(cnt_en == 13'd812) || (cnt_en == 13'd1100) || 
// 				(cnt_en == 13'd1362)) begin
// 		VIN_1 <= ~VIN_1;
// 	end
// end

// // VIN_2 control (翻转 at 275, 537, 825, 1087, 1375, 1637)
// always @(posedge clk_50M or negedge rst_n) begin
// 	if (!rst_n) begin
// 		VIN_2 <= 1'b0;
// 	end else if (!work_en) begin
// 		VIN_2 <= 1'b0;
// 	end else if ((cnt_en == 13'd275) || (cnt_en == 13'd537) || 
// 				(cnt_en == 13'd825) || (cnt_en == 13'd1087) || 
// 				(cnt_en == 13'd1375) || (cnt_en == 13'd1637)) begin
// 		VIN_2 <= ~VIN_2;
// 	end
// end

// // VIN_3 control (翻转 at 267, 545, 817, 1095, 1367, 1645)
// always @(posedge clk_50M or negedge rst_n) begin
// 	if (!rst_n) begin
// 		VIN_3 <= 1'b0;
// 	end else if (!work_en) begin
// 		VIN_3 <= 1'b0;
// 	end else if ((cnt_en == 13'd267) || (cnt_en == 13'd545) || 
// 				(cnt_en == 13'd817) || (cnt_en == 13'd1095) || 
// 				(cnt_en == 13'd1367) || (cnt_en == 13'd1645)) begin
// 		VIN_3 <= ~VIN_3;
// 	end
// end

// // VIN_4 control (翻转 at 270, 542, 820, 1092, 1370, 1642)
// always @(posedge clk_50M or negedge rst_n) begin
// 	if (!rst_n) begin
// 		VIN_4 <= 1'b0;
// 	end else if (rst_n && cnt_en == 0) begin  
// 		VIN_4 <= 1'b1;
// 	end else if (!work_en) begin
// 		VIN_4 <= 1'b0;
// 	end else if ((cnt_en == 13'd270) || (cnt_en == 13'd542) || 
// 				(cnt_en == 13'd820) || (cnt_en == 13'd1092) || 
// 				(cnt_en == 13'd1370) || (cnt_en == 13'd1642)) begin
// 		VIN_4 <= ~VIN_4;
// 	end
// end

// endmodule
 //启动信号沿检测 —— 按一次键执行一次激励
module ultrasound_launch_90KHz_10ms 
#(
    parameter CNT_90K  = 11'd1_666   // 3*11.1us / 20ns = 1_666
)
(
    input  wire clk_50M,      
    input  wire rst_n,        
    input  wire launch_cmd,   // 按键命令：1启动；0停止
    output reg  VIN_1,        // 通道1
    output reg  VIN_2,        
    output reg  VIN_3,        
    output reg  VIN_4
);

//==================================================
// 1. 启动信号沿检测 —— 按一次键执行一次激励
//==================================================
reg launch_cmd_dly;
wire launch_cmd_posedge;

always @(posedge clk_50M or negedge rst_n) begin
    if (!rst_n)
        launch_cmd_dly <= 1'b0;
    else
        launch_cmd_dly <= launch_cmd;
end

assign launch_cmd_posedge = (launch_cmd && !launch_cmd_dly);

//==================================================
// 2. 单次激励计数控制
//==================================================
reg [10:0] cnt_pulse;
reg pulse_en;

always @(posedge clk_50M or negedge rst_n) begin
    if (!rst_n) begin
        cnt_pulse <= 11'd0;
        pulse_en  <= 1'b0;
    end 
    else if (launch_cmd_posedge) begin
        pulse_en  <= 1'b1;       // 检测到上升沿启动一次激励
        cnt_pulse <= 11'd0;
    end 
    else if (pulse_en && cnt_pulse < CNT_90K) begin
        cnt_pulse <= cnt_pulse + 11'd1;
    end 
    else begin
        pulse_en  <= 1'b0;       // 激励结束
    end
end

//==================================================
// 3. 四路输出控制（相位微调）
//==================================================
always @(posedge clk_50M or negedge rst_n) begin
    if (!rst_n)
        VIN_1 <= 1'b0;
    else if(!pulse_en)
        VIN_1 <= 1'b0;
    else if (cnt_pulse==11'd262 || cnt_pulse==11'd550 || 
             cnt_pulse==11'd812 || cnt_pulse==11'd1100 || 
             cnt_pulse==11'd1362)
        VIN_1 <= ~VIN_1;
end

always @(posedge clk_50M or negedge rst_n) begin
    if (!rst_n)
        VIN_2 <= 1'b0;
    else if(!pulse_en)
        VIN_2 <= 1'b0;
    else if (cnt_pulse==11'd275 || cnt_pulse==11'd537 || 
             cnt_pulse==11'd825 || cnt_pulse==11'd1087 || 
             cnt_pulse==11'd1375)
        VIN_2 <= ~VIN_2;
end

always @(posedge clk_50M or negedge rst_n) begin
    if (!rst_n)
        VIN_3 <= 1'b0;
    else if(!pulse_en)
        VIN_3 <= 1'b0;
    else if (cnt_pulse==11'd267 || cnt_pulse==11'd545 || 
             cnt_pulse==11'd817 || cnt_pulse==11'd1095 || 
             cnt_pulse==11'd1367)
        VIN_3 <= ~VIN_3;
end

always @(posedge clk_50M or negedge rst_n) begin
    if (!rst_n)
        VIN_4 <= 1'b0;
    else if(!pulse_en)
        VIN_4 <= 1'b0;
    else if (cnt_pulse==11'd270 || cnt_pulse==11'd542 || 
             cnt_pulse==11'd820 || cnt_pulse==11'd1092 || 
             cnt_pulse==11'd1370)
        VIN_4 <= ~VIN_4;
end

endmodule 
