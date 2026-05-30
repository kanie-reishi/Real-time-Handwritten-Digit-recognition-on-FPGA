`timescale 1ns / 1ps

module tb_pea_top;

    // =========================================================================
    // Parameters & Signals
    // =========================================================================
    localparam DATA_WIDTH = 8;
    localparam ADDR_WIDTH = 16;
    
    logic clk;
    logic rst_n;
    logic start;
    logic done;
    
    // Configuration Bus
    logic [7:0]  cfg_addr;
    logic [31:0] cfg_data;
    logic        cfg_we;
    
    // Memory Interface
    logic [ADDR_WIDTH-1:0] wb_read_addr;
    logic                  wb_re;
    logic [15:0][7:0]      wb_read_data;
    
    logic [ADDR_WIDTH-1:0] ifm_read_addr;
    logic                  ifm_re;
    logic [15:0][7:0]      ifm_read_data;
    
    logic [ADDR_WIDTH-1:0] ofm_write_addr;
    logic                  ofm_we;
    logic [15:0][7:0]      ofm_write_data;

    // =========================================================================
    // Mock SRAM Arrays
    // =========================================================================
    logic [127:0] ifm_mem        [0:1023];
    logic [127:0] weight_mem     [0:4095];
    logic [31:0]  bias_mem       [0:127];
    logic [127:0] golden_ofm_mem [0:1023];

    // =========================================================================
    // Device Under Test (DUT)
    // =========================================================================
    pea_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .PSUM_WIDTH(32),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .done(done),
        .cfg_addr(cfg_addr),
        .cfg_data(cfg_data),
        .cfg_we(cfg_we),
        .wb_read_addr(wb_read_addr),
        .wb_re(wb_re),
        .wb_read_data(wb_read_data),
        .ifm_read_addr(ifm_read_addr),
        .ifm_re(ifm_re),
        .ifm_read_data(ifm_read_data),
        .ofm_write_addr(ofm_write_addr),
        .ofm_we(ofm_we),
        .ofm_write_data(ofm_write_data)
    );

    // =========================================================================
    // Memory Read Logic
    // =========================================================================
    always_comb begin
        if (wb_re && ^wb_read_addr !== 1'bx) begin
            if (wb_read_addr < 4096)
                wb_read_data = weight_mem[wb_read_addr[11:0]];
            else if (wb_read_addr >= 4096 && wb_read_addr < 4224)
                wb_read_data = {96'd0, bias_mem[wb_read_addr - 4096]};
            else
                wb_read_data = '0;
        end else begin
            wb_read_data = '0;
        end
    end

    // IFM Read
    always_comb begin
        if (ifm_re && ^ifm_read_addr !== 1'bx && ifm_read_addr < 1024)
            ifm_read_data = ifm_mem[ifm_read_addr];
        else
            ifm_read_data = '0;
    end

    // =========================================================================
    // Clock Generation
    // =========================================================================
    initial clk = 0;
    always #5 clk = ~clk; // 100MHz

    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    initial begin
        // Initialize signals
        rst_n = 0;
        start = 0;
        cfg_we = 0;
        cfg_addr = 0;
        cfg_data = 0;
        
        $readmemh("ifm.hex", ifm_mem);
        $readmemh("weight.hex", weight_mem);
        $readmemh("bias.hex", bias_mem);
        $readmemh("expected_ofm.hex", golden_ofm_mem);
        
        $display("---------------------------------------------------------");
        $display("[TB] Mock SRAMs initialized with Hex Data.");
        
        #20 rst_n = 1;
        #10;
        
        // Write Configurations for Conv5 (5x5 IFM, 5x5 Kernel, 120 Cout, 16 Cin)
        write_cfg(8'h00, 5);  // reg_ifm_width
        write_cfg(8'h04, 5);  // reg_ifm_height
        write_cfg(8'h08, 1);  // reg_channels_in = 1 (Because the 16 channels are processed in parallel by the 16 rows)
        write_cfg(8'h0C, 16); // reg_channels_out (per pass)
        write_cfg(8'h10, 5);  // reg_kernel_size
        write_cfg(8'h14, 10); // reg_right_shift = 10 (matching c5_right_shift)
        write_cfg(8'h18, 5);  // reg_row_stride = 5 (since width is 5)
        write_cfg(8'h1C, 1);  // reg_col_stride = 1
        
        $display("[TB] Static Configuration Written.");
        
        // We need 120 output channels, so we run 8 passes (8 * 16 = 128)
        for (int pass = 0; pass < 8; pass++) begin
            $display("[TB] Starting Pass %0d (Output Channels %0d - %0d)", pass, pass*16, pass*16+15);
            
            // Set Base Addresses for this pass
            write_cfg(8'h20, pass * 400); // 25 tiles * 16 rows = 400 rows per pass
            write_cfg(8'h24, 4096 + (pass * 16)); // 16 bias values per pass
            
            @(posedge clk);
            start = 1;
            @(posedge clk);
            start = 0;
            
            wait(done == 1);
            @(posedge clk);
            $display("[TB] Pass %0d Finished!", pass);
        end
        
        $display("---------------------------------------------------------");
        $display("[TB] All 8 Passes Finished! Total 120 Output Channels computed.");
        $finish;
    end
    
    task write_cfg(input [7:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            cfg_we <= 1;
            cfg_addr <= addr;
            cfg_data <= data;
            @(posedge clk);
            cfg_we <= 0;
        end
    endtask

    // =========================================================================
    // Scoreboard: Check OFM against Golden Data
    // =========================================================================
    integer error_count = 0;
    logic [ADDR_WIDTH-1:0] total_ofm_writes = 0;
    
    always_ff @(posedge clk) begin
        if (ofm_we) begin
            // The OFM address from PEA starts at 0 for each pass.
            // We need to offset it by the pass number to check the global golden memory.
            // But since each pass only produces 1 output pixel (16 channels),
            // ofm_write_addr is always 0.
            // We just use total_ofm_writes to index the golden memory.
            logic [ADDR_WIDTH-1:0] global_addr;
            global_addr = total_ofm_writes;
            
            if (ofm_write_data !== golden_ofm_mem[global_addr]) begin
                $display("[ERROR] Mismatch at pass %0d!", total_ofm_writes);
                $display("        Hardware : %H", ofm_write_data);
                $display("        Golden   : %H", golden_ofm_mem[global_addr]);
                error_count = error_count + 1;
            end else begin
                $display("[PASS]  Match at pass %0d: %H", total_ofm_writes, ofm_write_data);
            end
            total_ofm_writes <= total_ofm_writes + 1;
        end
    end

endmodule
