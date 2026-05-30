`timescale 1ns / 1ps

// ============================================================================
// Module: mac_pe (Processing Element)
// Description: A single node in the Double-Buffered Weight Stationary Systolic Array.
// ============================================================================
module mac_pe (
    input  logic        clk,
    input  logic        rst_n,

    // Weight Pre-load Interface (flows vertically, Top to Bottom)
    // Uses a shadow register to allow loading while computing
    input  logic        load_weight_en,
    input  logic [7:0]  weight_in,
    output logic [7:0]  weight_out,

    // Wavefront Swapping Interface (flows horizontally with data)
    input  logic        swap_weight_in,
    output logic        swap_weight_out,

    // Data Flow Interface (flows horizontally, Left to Right)
    input  logic        data_en,
    input  logic [7:0]  data_in,
    output logic [7:0]  data_out,
    output logic        data_en_out,

    // Partial Sum Flow Interface (flows vertically, Top to Bottom)
    input  logic        psum_en,
    input  logic [31:0] psum_in,
    output logic [31:0] psum_out,
    output logic        psum_en_out
);
    // Stage 1 Registers (Latched at T+1)
    logic [7:0]  weight_reg;
    logic [7:0]  weight_shadow_reg;
    logic [7:0]  data_reg;
    logic        data_en_reg;
    logic        swap_reg;

    // Stage 2 Registers (Latched at T+2, representing MREG & propagation)
    logic signed [15:0] mult_res_reg;
    logic [7:0]  data_out_reg;
    logic        data_en_out_reg;
    logic        swap_out_reg;
    logic [31:0] psum_in_reg;
    logic        psum_en_in_reg;

    // Stage 3 Registers (Latched at T+3, representing PREG)
    logic [31:0] psum_reg;
    logic        psum_en_reg;

    // Output assignments
    assign weight_out      = weight_shadow_reg; // Weight shadow flows without pipeline stages
    assign data_out        = data_out_reg;
    assign data_en_out     = data_en_out_reg;
    assign swap_weight_out = swap_out_reg;
    assign psum_out        = psum_reg;
    assign psum_en_out     = psum_en_reg;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            weight_reg        <= 8'd0;
            weight_shadow_reg <= 8'd0;
            data_reg          <= 8'd0;
            data_en_reg       <= 1'b0;
            swap_reg          <= 1'b0;
            
            mult_res_reg      <= 16'd0;
            data_out_reg      <= 8'd0;
            data_en_out_reg   <= 1'b0;
            swap_out_reg      <= 1'b0;
            psum_in_reg       <= 32'd0;
            psum_en_in_reg    <= 1'b0;
            
            psum_reg          <= 32'd0;
            psum_en_reg       <= 1'b0;
        end else begin
            // -------------------------------------------------------------
            // STAGE 1: Input Latching (AREG/BREG equivalents)
            // -------------------------------------------------------------
            if (load_weight_en) begin
                weight_shadow_reg <= weight_in;
            end
            
            swap_reg <= swap_weight_in;
            if (swap_weight_in) begin
                weight_reg <= weight_shadow_reg;
            end
            
            data_reg    <= data_in;
            data_en_reg <= data_en;

            // -------------------------------------------------------------
            // STAGE 2: Multiplier (MREG) & Horizontal Propagation
            // -------------------------------------------------------------
            mult_res_reg    <= $signed(weight_reg) * $signed(data_reg);
            
            data_out_reg    <= data_reg;
            data_en_out_reg <= data_en_reg;
            swap_out_reg    <= swap_reg;

            // Align Psum input with the multiplier result
            psum_in_reg     <= psum_in;
            psum_en_in_reg  <= psum_en;

            // -------------------------------------------------------------
            // STAGE 3: Accumulator (PREG)
            // -------------------------------------------------------------
            psum_en_reg <= psum_en_in_reg;
            
            // data_en_out_reg is aligned with psum_en_in_reg
            if (psum_en_in_reg && data_en_out_reg) begin
                psum_reg <= $signed(psum_in_reg) + $signed(mult_res_reg);
            end else if (psum_en_in_reg) begin
                psum_reg <= psum_in_reg;
            end else begin
                psum_reg <= 32'd0; 
            end
        end
    end
endmodule


// ============================================================================
// Module: pea_systolic_16x16
// Description: A 16x16 grid of mac_pe units. Includes Input Skewing and Output De-Skewing.
// ============================================================================
module pea_systolic_16x16 (
    input  logic clk,
    input  logic rst_n,

    // Weight Pre-load Interface (Input at top row)
    input  logic [15:0]       load_weight_en,
    input  logic [15:0][7:0]  weight_in_top,

    // IFM Data Input Interface (Simultaneous Input)
    input  logic [15:0]       data_en_left,
    input  logic [15:0][7:0]  data_in_left,
    
    // Wavefront Swapping Trigger (Simultaneous Input, will be skewed with data)
    input  logic              swap_weight_in_global,

    // Partial Sum Input (Input at top row)
    input  logic [15:0]       psum_en_top,
    input  logic [15:0][31:0] psum_in_top,

    // Output Feature Map Result (Aligned Simultaneous Output)
    output logic [15:0][31:0] psum_out_bottom,
    output logic [15:0]       psum_en_bottom
);

    // ------------------------------------------------------------------------
    // 1. INPUT SKEW BUFFERS (Stagger data horizontally by row index)
    // ------------------------------------------------------------------------
    logic [15:0][7:0] skewed_data_in;
    logic [15:0]      skewed_data_en;
    logic [15:0]      skewed_swap_in;

    genvar r, c;
    generate
        for (r = 0; r < 16; r++) begin : skew_row
            if (r == 0) begin
                assign skewed_data_in[r] = data_in_left[r];
                assign skewed_data_en[r] = data_en_left[r];
                assign skewed_swap_in[r] = swap_weight_in_global;
            end else begin
                // Shift register of length '2*r'
                localparam delay = 2 * r;
                logic [7:0] sr_data [0:delay-1];
                logic       sr_en   [0:delay-1];
                logic       sr_swap [0:delay-1];
                
                always_ff @(posedge clk) begin
                    if (!rst_n) begin
                        for (int k=0; k<delay; k++) begin
                            sr_data[k] <= 8'd0;
                            sr_en[k]   <= 1'b0;
                            sr_swap[k] <= 1'b0;
                        end
                    end else begin
                        sr_data[0] <= data_in_left[r];
                        sr_en[0]   <= data_en_left[r];
                        sr_swap[0] <= swap_weight_in_global;
                        for (int k=1; k<delay; k++) begin
                            sr_data[k] <= sr_data[k-1];
                            sr_en[k]   <= sr_en[k-1];
                            sr_swap[k] <= sr_swap[k-1];
                        end
                    end
                end
                assign skewed_data_in[r] = sr_data[delay-1];
                assign skewed_data_en[r] = sr_en[delay-1];
                assign skewed_swap_in[r] = sr_swap[delay-1];
            end
        end
    endgenerate

    // ------------------------------------------------------------------------
    // 1.5 PSUM SKEW BUFFERS (Stagger psum vertically by col index)
    // ------------------------------------------------------------------------
    logic [15:0][31:0] skewed_psum_in;
    logic [15:0]       skewed_psum_en;

    generate
        for (c = 0; c < 16; c++) begin : skew_col
            localparam delay = 2 * c + 1;
            logic [31:0] sr_p_data [0:delay-1];
            logic        sr_p_en   [0:delay-1];
            
            always_ff @(posedge clk) begin
                if (!rst_n) begin
                    for (int k=0; k<delay; k++) begin
                        sr_p_data[k] <= 32'd0;
                        sr_p_en[k]   <= 1'b0;
                    end
                end else begin
                    sr_p_data[0] <= psum_in_top[c];
                    sr_p_en[0]   <= psum_en_top[c];
                    for (int k=1; k<delay; k++) begin
                        sr_p_data[k] <= sr_p_data[k-1];
                        sr_p_en[k]   <= sr_p_en[k-1];
                    end
                end
            end
            assign skewed_psum_in[c] = sr_p_data[delay-1];
            assign skewed_psum_en[c] = sr_p_en[delay-1];
        end
    endgenerate

    // ------------------------------------------------------------------------
    // 2. 16x16 PE GRID
    // ------------------------------------------------------------------------
    logic [7:0]  w_data [0:16][0:15];
    logic [31:0] p_data [0:16][0:15];
    logic        p_en   [0:16][0:15];
    logic [7:0]  d_data [0:15][0:16];
    logic        d_en   [0:15][0:16];
    logic        s_swap [0:15][0:16];

    generate
        // Boundary connections
        for (c = 0; c < 16; c++) begin : top_boundary
            assign w_data[0][c] = weight_in_top[c];
            assign p_data[0][c] = skewed_psum_in[c];
            assign p_en[0][c]   = skewed_psum_en[c];
        end
        for (r = 0; r < 16; r++) begin : left_boundary
            assign d_data[r][0] = skewed_data_in[r];
            assign d_en[r][0]   = skewed_data_en[r];
            assign s_swap[r][0] = skewed_swap_in[r];
        end

        for (r = 0; r < 16; r++) begin : grid_row
            for (c = 0; c < 16; c++) begin : grid_col
                mac_pe u_pe (
                    .clk            (clk),
                    .rst_n          (rst_n),
                    .load_weight_en (load_weight_en[c]),
                    .weight_in      (w_data[r][c]),
                    .weight_out     (w_data[r+1][c]),
                    .swap_weight_in (s_swap[r][c]),
                    .swap_weight_out(s_swap[r][c+1]),
                    .data_en        (d_en[r][c]),
                    .data_in        (d_data[r][c]),
                    .data_out       (d_data[r][c+1]),
                    .data_en_out    (d_en[r][c+1]),
                    .psum_en        (p_en[r][c]),
                    .psum_in        (p_data[r][c]),
                    .psum_out       (p_data[r+1][c]),
                    .psum_en_out    (p_en[r+1][c])
                );
            end
        end
    endgenerate

    // ------------------------------------------------------------------------
    // 3. OUTPUT DE-SKEW BUFFERS (Re-align columns)
    // Column c outputs earlier than Column c+1, so Col c needs more delay.
    // Delay for Col c is (15 - c) cycles.
    // ------------------------------------------------------------------------
    generate
        for (c = 0; c < 16; c++) begin : deskew_col
            localparam delay = 30 - 2 * c;
            
            if (delay == 0) begin
                assign psum_out_bottom[c] = p_data[16][c];
                assign psum_en_bottom[c]  = p_en[16][c];
            end else begin
                logic [31:0] ds_data [0:delay-1];
                logic        ds_en   [0:delay-1];
                
                always_ff @(posedge clk) begin
                    if (!rst_n) begin
                        for (int k=0; k<delay; k++) begin
                            ds_data[k] <= 32'd0;
                            ds_en[k]   <= 1'b0;
                        end
                    end else begin
                        ds_data[0] <= p_data[16][c];
                        ds_en[0]   <= p_en[16][c];
                        for (int k=1; k<delay; k++) begin
                            ds_data[k] <= ds_data[k-1];
                            ds_en[k]   <= ds_en[k-1];
                        end
                    end
                end
                assign psum_out_bottom[c] = ds_data[delay-1];
                assign psum_en_bottom[c]  = ds_en[delay-1];
            end
        end
    endgenerate

endmodule
