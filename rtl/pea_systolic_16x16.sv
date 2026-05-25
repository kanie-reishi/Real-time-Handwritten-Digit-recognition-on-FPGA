`timescale 1ns / 1ps

// ============================================================================
// Module: mac_pe (Processing Element)
// Description: A single node in the Weight Stationary Systolic Array.
//              Performs 8x8 signed multiplication and 32-bit accumulation.
// ============================================================================
module mac_pe (
    input  logic        clk,
    input  logic        rst_n,

    // Weight Pre-load Interface (flows vertically, Top to Bottom)
    input  logic        load_weight_en,
    input  logic [7:0]  weight_in,
    output logic [7:0]  weight_out,

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
    // Stationary Weight Register
    logic [7:0] weight_reg;

    // Pipeline registers for Data and Partial Sum to pass to neighbors
    logic [7:0]  data_reg;
    logic        data_en_reg;
    
    logic [31:0] psum_reg;
    logic        psum_en_reg;

    // Direct assignment to output ports (pipelined to next PE)
    assign weight_out  = weight_reg;
    assign data_out    = data_reg;
    assign data_en_out = data_en_reg;
    assign psum_out    = psum_reg;
    assign psum_en_out = psum_en_reg;

    // Multiplier Logic (Uses registered data to cut critical path from routing)
    logic signed [15:0] mult_res;
    assign mult_res = $signed(weight_reg) * $signed(data_reg);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            weight_reg  <= 8'd0;
            data_reg    <= 8'd0;
            data_en_reg <= 1'b0;
            psum_reg    <= 32'd0;
            psum_en_reg <= 1'b0;
        end else begin
            // 1. Weight Pre-load phase
            if (load_weight_en) begin
                weight_reg <= weight_in;
            end

            // 2. Data propagation (shift horizontally)
            data_reg    <= data_in;
            data_en_reg <= data_en;

            // 3. Compute phase & Partial Sum accumulation (shift vertically)
            psum_en_reg <= psum_en;
            if (psum_en && data_en_reg) begin
                // Accumulate incoming partial sum with the registered MAC result
                psum_reg <= $signed(psum_in) + $signed(mult_res);
            end else if (psum_en) begin
                // Pass through the incoming partial sum if no valid data
                psum_reg <= psum_in;
            end else begin
                psum_reg <= 32'd0; 
            end
        end
    end
endmodule


// ============================================================================
// Module: pea_systolic_16x16
// Description: A 16x16 grid of mac_pe units.
//              - Weights stream down columns during pre-load.
//              - IFM data streams across rows during compute.
//              - Partial Sums stream down columns during compute.
// ============================================================================
module pea_systolic_16x16 (
    input  logic clk,
    input  logic rst_n,

    // Weight Pre-load Interface (Input at top row)
    input  logic [15:0]       load_weight_en, // Enable shifting weights down columns
    input  logic [15:0][7:0]  weight_in_top,

    // IFM Data Input Interface (Input at left column)
    input  logic [15:0]       data_en_left,
    input  logic [15:0][7:0]  data_in_left,

    // Partial Sum Input (Input at top row, usually initialized to 0 or bias)
    input  logic [15:0]       psum_en_top,
    input  logic [15:0][31:0] psum_in_top,

    // Output Feature Map Result (Output from bottom row)
    output logic [15:0][31:0] psum_out_bottom,
    output logic [15:0]       psum_en_bottom
);

    // Internal wires connecting the 16x16 grid
    // w_data[row][col] and p_data[row][col] flow Top to Bottom (17 rows to include outputs)
    logic [7:0]  w_data [0:16][0:15];
    logic [31:0] p_data [0:16][0:15];
    logic        p_en   [0:16][0:15];

    // d_data[row][col] flows Left to Right (17 columns to include outputs)
    logic [7:0]  d_data [0:15][0:16];
    logic        d_en   [0:15][0:16];

    // Generate boundary connections
    genvar i, j;
    generate
        // Top boundary (Inputs to row 0) and Bottom boundary (Outputs from row 16)
        for (j = 0; j < 16; j++) begin : assign_top_bottom
            assign w_data[0][j] = weight_in_top[j];
            assign p_data[0][j] = psum_in_top[j];
            assign p_en[0][j]   = psum_en_top[j];
            
            assign psum_out_bottom[j] = p_data[16][j];
            assign psum_en_bottom[j]  = p_en[16][j];
        end

        // Left boundary (Inputs to col 0)
        for (i = 0; i < 16; i++) begin : assign_left
            assign d_data[i][0] = data_in_left[i];
            assign d_en[i][0]   = data_en_left[i];
        end
    endgenerate

    // Generate 16x16 PE grid
    generate
        for (i = 0; i < 16; i++) begin : row
            for (j = 0; j < 16; j++) begin : col
                mac_pe u_pe (
                    .clk            (clk),
                    .rst_n          (rst_n),

                    // Vertical connection (Weights)
                    .load_weight_en (load_weight_en[j]), // Columns share load enable
                    .weight_in      (w_data[i][j]),
                    .weight_out     (w_data[i+1][j]),

                    // Horizontal connection (Data)
                    .data_en        (d_en[i][j]),
                    .data_in        (d_data[i][j]),
                    .data_out       (d_data[i][j+1]),
                    .data_en_out    (d_en[i][j+1]),

                    // Vertical connection (Partial Sums)
                    .psum_en        (p_en[i][j]),
                    .psum_in        (p_data[i][j]),
                    .psum_out       (p_data[i+1][j]),
                    .psum_en_out    (p_en[i+1][j])
                );
            end
        end
    endgenerate

endmodule
