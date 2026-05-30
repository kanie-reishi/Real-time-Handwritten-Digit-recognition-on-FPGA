`timescale 1ns / 1ps

// ============================================================================
// Module: line_buffer
// Description: Local SRAM Circular Line Buffer for Processing Element Array.
//              Automatically handles modulo row mapping.
// ============================================================================
module line_buffer #(
    parameter MAX_WIDTH = 32,
    parameter MAX_ROWS = 5,
    parameter DATA_WIDTH = 128
)(
    input  logic clk,
    
    // Write Interface (From IFM SRAM)
    input  logic                  we,
    input  logic [31:0]           write_row,
    input  logic [31:0]           write_col,
    input  logic [DATA_WIDTH-1:0] write_data,
    
    // Read Interface (To PE Array)
    input  logic [31:0]           read_row,
    input  logic [31:0]           read_col,
    output logic [DATA_WIDTH-1:0] read_data
);

    // Modulo mapping to physical rows
    logic [2:0] w_phys_row;
    logic [2:0] r_phys_row;
    
    assign w_phys_row = write_row % MAX_ROWS;
    assign r_phys_row = read_row % MAX_ROWS;
    
    // Linear address calculation
    logic [7:0] w_addr;
    logic [7:0] r_addr;
    
    assign w_addr = w_phys_row * MAX_WIDTH + write_col;
    assign r_addr = r_phys_row * MAX_WIDTH + read_col;
    
    // Block RAM inference
    logic [DATA_WIDTH-1:0] mem [0:MAX_ROWS*MAX_WIDTH-1];
    
    always_ff @(posedge clk) begin
        if (we) begin
            mem[w_addr] <= write_data;
        end
        read_data <= mem[r_addr];
    end

endmodule
