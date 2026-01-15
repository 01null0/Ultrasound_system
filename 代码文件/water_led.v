module water_led 
#(
	parameter CNT_MAX_500MS = 25'd24_999_999
)
(
	input 	wire 	clk_50M,
	input 	wire 	rst_n,

	output	reg [3:0]led_out
);

reg [24:0]cnt;
reg cnt_flag;

always@(posedge clk_50M or negedge rst_n)begin
	if(!rst_n)
		cnt <= 25'd0;
	else if(cnt == CNT_MAX_500MS)
		cnt <= 25'd0;
	else 
		cnt <= cnt +25'd1;
end

always@(posedge clk_50M or negedge rst_n)begin
	if(!rst_n)
		cnt_flag <= 1'b0;
	else if(cnt == CNT_MAX_500MS)
		cnt_flag <= 1'b1;
	else 
		cnt_flag <= 1'b0;
end

always@(posedge clk_50M or negedge rst_n)begin
	if(!rst_n)
		led_out <= 4'b1110;
	else if(cnt_flag == 1'b1)
		led_out <= {led_out[2:0],led_out[3]};
	else if((led_out <= 4'b0111)&&(cnt_flag == 1'b1))
		led_out <= 4'b1110;
	else 
		led_out <= led_out;
end

/* always@(posedge clk_50M or negedge rst_n)begin
	if(!rst_n)
		led_out <= 4'b1000;
	else if(cnt_flag == 1'b1)
		led_out <= {led_out[0],led_out[3:1]};
	else if((led_out <= 4'b0001)&&(cnt_flag == 1'b1))
		led_out <= 4'b1000;
	else 
		led_out <= led_out;
end */

/* always@(posedge clk_50M or negedge rst_n)begin
	if(!rst_n)
		led_out <= 4'b1000;
	else if(cnt_flag == 1'b1)
		led_out <= led_out >> 1;
	else if((led_out <= 4'b0001)&&(cnt_flag == 1'b1))
		led_out <= 4'b1000;
	else 
		led_out <= led_out;
end
 */

endmodule
