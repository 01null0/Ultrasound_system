module ultrasound_10ms 
(
	input 	wire 		clk_50M		,
	input 	wire 		rst_n	,

	output 	wire 	[3:0]led_out,   // 流水灯输出
	output  wire 	VIN_1		,   // 通道 1 输出
	output  wire 	VIN_2		,   // 通道 2 输出
	output  wire 	VIN_3		,   // 通道 3 输出
	output  wire 	VIN_4		    // 通道 4 输出
);

ultrasound_launch_90KHz_10ms 
#(
	.CNT_MAX 	 (   1666    ),
	.CNT_10M 	 (  499_999  )
)
ultrasound_launch_90KHz_10ms_inst
(
	.clk_50M	(clk_50M) ,
	.rst_n		(rst_n)	  ,

	.VIN_1		(VIN_1)	  ,
    .VIN_2		(VIN_2)   ,
	.VIN_3		(VIN_3)   ,
	.VIN_4		(VIN_4)  
);

water_led 
#(
	.CNT_MAX_500MS 	(24_999_999)
	
)
water_led_inst
(
	.clk_50M	(clk_50M),
	.rst_n		(rst_n)	 ,

	.led_out	(led_out)
);

endmodule 