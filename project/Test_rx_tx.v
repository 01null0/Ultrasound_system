module Test_rx_tx (
    input       clk_50M,
    input       rst_n,
    input [7:0] command
);
    reg Start;
    always @(posedge clk_50M or negedge rst_n) begin
        if (!rst_n) begin
            Start<=0;
        end
        else begin
            case (command)
                16'h01:Start <= 1;
                default:Start <= 0; 
            endcase
        end
    end
endmodule
