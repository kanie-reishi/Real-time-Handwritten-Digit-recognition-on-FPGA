`timescale 1ns / 1ps

module tb_ofm_post_processor();

    logic clk;
    logic rst_n;
    
    // Configuration
    logic        reg_relu_en;
    logic        reg_pool_en;
    logic [31:0] reg_out_width;
    logic [31:0] reg_channels_out;

    // Interface from PEA MAC
    logic        pea_we;
    logic [31:0] pea_x;
    logic [31:0] pea_y;
    logic [31:0] pea_cout;
    logic [15:0][7:0] pea_data;

    // Interface to SRAM (OFM Arbiter)
    logic        sram_we;
    logic [15:0] sram_addr;
    logic [15:0][7:0] sram_data;

    ofm_post_processor #(
        .DATA_WIDTH(8),
        .ADDR_WIDTH(16)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .reg_relu_en(reg_relu_en),
        .reg_pool_en(reg_pool_en),
        .reg_out_width(reg_out_width),
        .reg_channels_out(reg_channels_out),
        .pea_we(pea_we),
        .pea_x(pea_x),
        .pea_y(pea_y),
        .pea_cout(pea_cout),
        .pea_data(pea_data),
        .sram_we(sram_we),
        .sram_addr(sram_addr),
        .sram_data(sram_data)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst_n = 0;
        reg_relu_en = 0;
        reg_pool_en = 1; // Enable Max Pooling
        reg_out_width = 6; // Width = 6
        reg_channels_out = 16;
        pea_we = 0;
        pea_x = 0;
        pea_y = 0;
        pea_cout = 0;
        for(int i=0; i<16; i++) pea_data[i] = 0;
        
        #20;
        rst_n = 1;
        #10;
        
        $display("--- STRESS TEST 6x4 IMAGE ---");
        $display("Expected Outputs:");
        $display("Addr=0 (Block 0,0): max(1,2,4,5) = 5");
        $display("Addr=1 (Block 1,0): max(9,10,7,3) = 10");
        $display("Addr=2 (Block 2,0): max(15,12,13,11) = 15");
        $display("Addr=3 (Block 0,1): max(0,0,1,2) = 2");
        $display("Addr=4 (Block 1,1): max(20,21,19,22) = 22");
        $display("Addr=5 (Block 2,1): max(30,31,33,29) = 33");
        $display("-----------------------------");

        // Push Row 0
        @(posedge clk); #1; pea_y = 0; pea_we = 1;
        pea_x = 0; for(int i=0; i<16; i++) pea_data[i] = 1;  @(posedge clk); #1;
        pea_x = 1; for(int i=0; i<16; i++) pea_data[i] = 2;  @(posedge clk); #1;
        pea_x = 2; for(int i=0; i<16; i++) pea_data[i] = 9;  @(posedge clk); #1;
        pea_x = 3; for(int i=0; i<16; i++) pea_data[i] = 10; @(posedge clk); #1;
        pea_x = 4; for(int i=0; i<16; i++) pea_data[i] = 15; @(posedge clk); #1;
        pea_x = 5; for(int i=0; i<16; i++) pea_data[i] = 12; @(posedge clk); #1;
        pea_we = 0;
        
        #20;
        
        // Push Row 1 (This will trigger pooling for row 0 and 1)
        @(posedge clk); #1; pea_y = 1; pea_we = 1;
        pea_x = 0; for(int i=0; i<16; i++) pea_data[i] = 4;  @(posedge clk); #1;
        pea_x = 1; for(int i=0; i<16; i++) pea_data[i] = 5;  @(posedge clk); #1;
        pea_x = 2; for(int i=0; i<16; i++) pea_data[i] = 7;  @(posedge clk); #1;
        pea_x = 3; for(int i=0; i<16; i++) pea_data[i] = 3;  @(posedge clk); #1;
        pea_x = 4; for(int i=0; i<16; i++) pea_data[i] = 13; @(posedge clk); #1;
        pea_x = 5; for(int i=0; i<16; i++) pea_data[i] = 11; @(posedge clk); #1;
        pea_we = 0;
        
        #20;

        // Push Row 2
        @(posedge clk); #1; pea_y = 2; pea_we = 1;
        pea_x = 0; for(int i=0; i<16; i++) pea_data[i] = 0;  @(posedge clk); #1;
        pea_x = 1; for(int i=0; i<16; i++) pea_data[i] = 0;  @(posedge clk); #1;
        pea_x = 2; for(int i=0; i<16; i++) pea_data[i] = 20; @(posedge clk); #1;
        pea_x = 3; for(int i=0; i<16; i++) pea_data[i] = 21; @(posedge clk); #1;
        pea_x = 4; for(int i=0; i<16; i++) pea_data[i] = 30; @(posedge clk); #1;
        pea_x = 5; for(int i=0; i<16; i++) pea_data[i] = 31; @(posedge clk); #1;
        pea_we = 0;

        #20;

        // Push Row 3 (This will trigger pooling for row 2 and 3)
        @(posedge clk); #1; pea_y = 3; pea_we = 1;
        pea_x = 0; for(int i=0; i<16; i++) pea_data[i] = 1;  @(posedge clk); #1;
        pea_x = 1; for(int i=0; i<16; i++) pea_data[i] = 2;  @(posedge clk); #1;
        pea_x = 2; for(int i=0; i<16; i++) pea_data[i] = 19; @(posedge clk); #1;
        pea_x = 3; for(int i=0; i<16; i++) pea_data[i] = 22; @(posedge clk); #1;
        pea_x = 4; for(int i=0; i<16; i++) pea_data[i] = 33; @(posedge clk); #1;
        pea_x = 5; for(int i=0; i<16; i++) pea_data[i] = 29; @(posedge clk); #1;
        pea_we = 0;

        #50;
        $finish;
    end

    // Monitor
    always_ff @(posedge clk) begin
        if (sram_we) begin
            $display("SRAM Write: Addr=%0d, Data[0]=%0d", sram_addr, sram_data[0]);
        end
    end

endmodule
