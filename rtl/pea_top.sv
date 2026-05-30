`timescale 1ns / 1ps

module pea_top #(
    parameter DATA_WIDTH = 8,
    parameter PSUM_WIDTH = 32,
    parameter ADDR_WIDTH = 16
)(
    input  logic clk,
    input  logic rst_n,

    // Controller Interface
    input  logic start,
    output logic done,

    // Configuration Interface
    input  logic [7:0]  cfg_addr,
    input  logic [31:0] cfg_data,
    input  logic        cfg_we,

    // Memory Interface: Weight & Bias Bank (Read)
    output logic [ADDR_WIDTH-1:0] wb_read_addr,
    output logic                  wb_re,
    input  logic [15:0][7:0]      wb_read_data,
    
    // Memory Interface: IFM Buffer (Read)
    output logic [ADDR_WIDTH-1:0] ifm_read_addr,
    output logic                  ifm_re,
    input  logic [15:0][7:0]      ifm_read_data,

    // Memory Interface: OFM Buffer (Write)
    output logic [ADDR_WIDTH-1:0] ofm_write_addr,
    output logic                  ofm_we,
    output logic [15:0][7:0]      ofm_write_data
);

    // =========================================================================
    // 1. Configuration Register File
    // =========================================================================
    logic [31:0] reg_ifm_width;     
    logic [31:0] reg_ifm_height;    
    logic [31:0] reg_channels_in;   
    logic [31:0] reg_channels_out;  
    logic [31:0] reg_kernel_size;   
    logic [4:0]  reg_right_shift;   
    logic [31:0] reg_row_stride;    
    logic [31:0] reg_col_stride;    
    logic [31:0] reg_weight_base;   
    logic [31:0] reg_bias_base;     
    logic        reg_relu_en;
    logic        reg_pool_en;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_ifm_width    <= '0;
            reg_ifm_height   <= '0;
            reg_channels_in  <= '0;
            reg_channels_out <= '0;
            reg_kernel_size  <= '0;
            reg_right_shift  <= '0;
            reg_row_stride   <= '0;
            reg_col_stride   <= '0;
            reg_weight_base  <= '0;
            reg_bias_base    <= '0;
            reg_relu_en      <= 1'b0;
            reg_pool_en      <= 1'b0;
        end else if (cfg_we) begin
            case (cfg_addr)
                8'h00: reg_ifm_width    <= cfg_data;
                8'h04: reg_ifm_height   <= cfg_data;
                8'h08: reg_channels_in  <= cfg_data;
                8'h0C: reg_channels_out <= cfg_data;
                8'h10: reg_kernel_size  <= cfg_data;
                8'h14: reg_right_shift  <= cfg_data[4:0];
                8'h18: reg_row_stride   <= cfg_data;
                8'h1C: reg_col_stride   <= cfg_data;
                8'h20: reg_weight_base  <= cfg_data;
                8'h24: reg_bias_base    <= cfg_data;
                8'h28: reg_relu_en      <= cfg_data[0];
                8'h2C: reg_pool_en      <= cfg_data[0];
            endcase
        end
    end

    logic [31:0] out_width;
    assign out_width = reg_ifm_width - reg_kernel_size + 1;

    logic [31:0] tiles_per_cout;
    assign tiles_per_cout = reg_channels_in * reg_kernel_size * reg_kernel_size;

    // =========================================================================
    // 2. FSM & Control
    // =========================================================================
    typedef enum logic [2:0] {
        IDLE            = 3'd0,
        LOAD_BIAS       = 3'd1,
        LOAD_LINE_BUFFER= 3'd2,
        LOAD_WEIGHT     = 3'd3,
        STREAM_ROW      = 3'd4,
        WAIT_FLUSH      = 3'd5,
        WAIT_BRAM       = 3'd6,
        POST_PROC       = 3'd7
    } state_t;

    state_t state, next_state;

    logic [31:0] loop_cout; 
    logic [31:0] loop_y;    
    logic [31:0] loop_cin;  
    logic [31:0] loop_ky;   
    logic [31:0] loop_kx;   

    logic [7:0]  load_counter;
    logic [31:0] stream_cnt;
    logic [31:0] psum_flush_cnt;
    
    logic [31:0] lb_load_row_cnt;
    logic [31:0] lb_load_col_cnt;
    logic        load_full_lb;
    logic [31:0] rows_to_load;
    
    assign rows_to_load = load_full_lb ? reg_kernel_size : 32'd1;

    logic [31:0] tile_index;
    assign tile_index = loop_cout * tiles_per_cout + 
                        loop_cin * (reg_kernel_size * reg_kernel_size) + 
                        loop_ky * reg_kernel_size + 
                        loop_kx;

    logic is_first_acc;
    assign is_first_acc = (loop_cin == 0 && loop_ky == 0 && loop_kx == 0);

    logic [15:0]       load_weight_en;
    logic              swap_weight_in_global;
    logic [15:0]       data_en_left;
    logic [15:0]       psum_en_top;
    logic [15:0][31:0] psum_in_top;

    logic [15:0][31:0] psum_out_bottom;
    logic [15:0]       psum_en_bottom;

    logic [31:0] bias_array [0:15]; 

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            loop_cout <= '0; loop_y <= '0; loop_cin <= '0; 
            loop_ky <= '0; loop_kx <= '0;
            load_counter <= '0; stream_cnt <= '0; psum_flush_cnt <= '0;
            lb_load_row_cnt <= '0; lb_load_col_cnt <= '0;
            load_full_lb <= 1'b1;
        end else begin
            state <= next_state;
            
            if (state == IDLE && start) begin
                loop_cout <= '0; loop_y <= '0; loop_cin <= '0; 
                loop_ky <= '0; loop_kx <= '0;
                load_full_lb <= 1'b1;
            end
            
            if (state != LOAD_LINE_BUFFER && next_state == LOAD_LINE_BUFFER) begin
                lb_load_row_cnt <= '0;
                lb_load_col_cnt <= '0;
            end
            
            case (state)
                LOAD_BIAS: begin
                    // 1-cycle latency SRAM handling moved to a separate always_ff block
                    load_counter <= load_counter + 1;
                    if (load_counter == 15) load_counter <= '0;
                end
                
                LOAD_LINE_BUFFER: begin
                    lb_load_col_cnt <= lb_load_col_cnt + 1;
                    if (lb_load_col_cnt == reg_ifm_width - 1) begin
                        lb_load_col_cnt <= '0;
                        lb_load_row_cnt <= lb_load_row_cnt + 1;
                    end
                end
                
                LOAD_WEIGHT: begin
                    load_counter <= load_counter + 1;
                    if (load_counter == 15) load_counter <= '0;
                end
                
                STREAM_ROW: begin
                    stream_cnt <= stream_cnt + 1;
                    if (stream_cnt == out_width - 1) stream_cnt <= '0;
                end
                
                WAIT_FLUSH: begin
                    if (psum_en_bottom[0]) begin
                        psum_flush_cnt <= psum_flush_cnt + 1;
                        if (psum_flush_cnt == out_width - 1) begin
                            psum_flush_cnt <= '0;
                            if (loop_kx < reg_kernel_size - 1) begin
                                loop_kx <= loop_kx + 1;
                            end else begin
                                loop_kx <= '0;
                                if (loop_ky < reg_kernel_size - 1) begin
                                    loop_ky <= loop_ky + 1;
                                end else begin
                                    loop_ky <= '0;
                                    if (loop_cin + 1 < reg_channels_in) begin
                                        loop_cin <= loop_cin + 1;
                                        load_full_lb <= 1'b1;
                                    end else begin
                                        loop_cin <= '0;
                                    end
                                end
                            end
                        end
                    end
                end
                
                POST_PROC: begin
                    stream_cnt <= stream_cnt + 1;
                    if (stream_cnt == out_width - 1) begin
                        stream_cnt <= '0;
                        if (loop_y < reg_ifm_height - reg_kernel_size) begin
                            loop_y <= loop_y + 1;
                            load_full_lb <= 1'b0;
                        end else begin
                            loop_y <= '0;
                            if (loop_cout + 1 < (reg_channels_out >> 4)) begin
                                loop_cout <= loop_cout + 1;
                                load_full_lb <= 1'b1;
                            end
                        end
                    end
                end
            endcase
        end
    end

    logic done_comb;
    logic done_d1;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done_d1 <= 1'b0;
            done <= 1'b0;
        end else begin
            done_d1 <= done_comb;
            done <= done_d1;
        end
    end

    always_comb begin
        next_state = state;
        done_comb = 1'b0;
        
        case (state)
            IDLE: if (start) next_state = LOAD_BIAS;
            LOAD_BIAS: if (load_counter == 15) next_state = LOAD_LINE_BUFFER;
            LOAD_LINE_BUFFER: begin
                if (lb_load_col_cnt == reg_ifm_width - 1 && lb_load_row_cnt == rows_to_load - 1)
                    next_state = LOAD_WEIGHT;
            end
            LOAD_WEIGHT: if (load_counter == 15) next_state = STREAM_ROW;
            STREAM_ROW: if (stream_cnt == out_width - 1) next_state = WAIT_FLUSH;
            WAIT_FLUSH: begin
                if (psum_en_bottom[0] && psum_flush_cnt == out_width - 1) begin
                    if (loop_kx == reg_kernel_size - 1 && loop_ky == reg_kernel_size - 1) begin
                        if (loop_cin + 1 == reg_channels_in)
                            next_state = WAIT_BRAM;
                        else
                            next_state = LOAD_LINE_BUFFER;
                    end else begin
                        next_state = LOAD_WEIGHT;
                    end
                end
            end
            WAIT_BRAM: begin
                next_state = POST_PROC;
            end
            POST_PROC: begin
                if (stream_cnt == out_width - 1) begin
                    if (loop_y == reg_ifm_height - reg_kernel_size && loop_cout + 1 == (reg_channels_out >> 4)) begin
                        next_state = IDLE;
                        done_comb = 1'b1;
                    end else if (loop_y == reg_ifm_height - reg_kernel_size)
                        next_state = LOAD_BIAS;
                    else
                        next_state = LOAD_LINE_BUFFER;
                end
            end
        endcase
    end

    // =========================================================================
    // 3. Line Buffer & IFM SRAM Interface
    // =========================================================================
    logic [31:0] current_load_abs_row;
    assign current_load_abs_row = load_full_lb ? (loop_y + lb_load_row_cnt) : (loop_y + reg_kernel_size - 1);
    
    assign ifm_re = (state == LOAD_LINE_BUFFER);
    assign ifm_read_addr = current_load_abs_row * reg_row_stride + lb_load_col_cnt * reg_col_stride + loop_cin;
    
    // 1-cycle latency for IFM SRAM
    logic lb_we;
    logic [31:0] lb_write_row, lb_write_col;
    logic [31:0] lb_read_row, lb_read_col;
    logic [127:0] lb_read_data;
    
    always_ff @(posedge clk) begin
        lb_we <= ifm_re;
        lb_write_row <= current_load_abs_row;
        lb_write_col <= lb_load_col_cnt;
    end

    assign lb_read_row = loop_y + loop_ky;
    assign lb_read_col = stream_cnt + loop_kx;
    
    line_buffer #(
        .MAX_WIDTH(32),
        .MAX_ROWS(5),
        .DATA_WIDTH(128)
    ) u_line_buffer (
        .clk(clk),
        .we(lb_we),
        .write_row(lb_write_row),
        .write_col(lb_write_col),
        .write_data(ifm_read_data),
        .read_row(lb_read_row),
        .read_col(lb_read_col),
        .read_data(lb_read_data)
    );

    // =========================================================================
    // 4. Memory Interfaces & Systolic Signals
    // =========================================================================
    assign wb_re = (state == LOAD_BIAS) || (state == LOAD_WEIGHT);
    assign wb_read_addr = (state == LOAD_BIAS) ? (reg_bias_base + loop_cout * 16 + load_counter) :
                                                 (reg_weight_base + (tile_index * 16) + (15 - load_counter));

    // 1-cycle latency for WB SRAM
    always_ff @(posedge clk) begin
        load_weight_en <= (state == LOAD_WEIGHT) ? 16'hFFFF : 16'd0;
    end
    
    // Delayed states for bias load
    logic [3:0] state_delayed;
    logic [31:0] load_counter_delayed;
    always_ff @(posedge clk) begin
        state_delayed <= state;
        load_counter_delayed <= load_counter;
    end
    
    always_ff @(posedge clk) begin
        if (state_delayed == LOAD_BIAS) begin
            bias_array[load_counter_delayed] <= {wb_read_data[3], wb_read_data[2], wb_read_data[1], wb_read_data[0]};
        end
    end
    
    // Line buffer has 1-cycle latency internally, so delay data_en_left
    logic data_en_delayed;
    logic psum_en_top_delayed;
    logic swap_weight_delayed;
    
    always_ff @(posedge clk) begin
        data_en_delayed <= (state == STREAM_ROW);
        psum_en_top_delayed <= (state == STREAM_ROW);
        swap_weight_delayed <= (state == STREAM_ROW && stream_cnt == 0);
    end

    assign data_en_left = data_en_delayed ? 16'hFFFF : 16'd0;
    assign psum_en_top = psum_en_top_delayed ? 16'hFFFF : 16'd0;
    assign swap_weight_in_global = swap_weight_delayed;
    assign psum_in_top = '0; 

    // =========================================================================
    // 5. Systolic Array Core Instantiation
    // =========================================================================
    pea_systolic_16x16 u_systolic_core (
        .clk                   (clk),
        .rst_n                 (rst_n),
        .load_weight_en        (load_weight_en),
        .weight_in_top         (wb_read_data),
        .swap_weight_in_global (swap_weight_in_global),
        .data_en_left          (data_en_left),
        .data_in_left          (lb_read_data),
        .psum_en_top           (psum_en_top),
        .psum_in_top           (psum_in_top),
        .psum_out_bottom       (psum_out_bottom),
        .psum_en_bottom        (psum_en_bottom)
    );

    // =========================================================================
    // 6. Psum Buffer (Block RAM)
    // =========================================================================
    logic [511:0] psum_bram [0:63]; 
    logic [511:0] psum_bram_dout;
    logic [5:0]   psum_read_addr;
    logic [5:0]   psum_write_addr;
    logic         psum_we;
    logic [511:0] psum_din;
    
    always_comb begin
        if (state == WAIT_FLUSH && psum_en_bottom[0])
            psum_read_addr = psum_flush_cnt;
        else if (state == POST_PROC)
            psum_read_addr = stream_cnt;
        else
            psum_read_addr = '0;
    end

    always_ff @(posedge clk) begin
        if (psum_we) psum_bram[psum_write_addr] <= psum_din;
        
        if (psum_we && psum_write_addr == psum_read_addr)
            psum_bram_dout <= psum_din;
        else
            psum_bram_dout <= psum_bram[psum_read_addr];
    end

    logic [15:0][31:0] psum_out_delayed;
    logic              psum_en_delayed;
    logic [5:0]        psum_write_addr_reg;
    logic              is_first_acc_delayed;

    always_ff @(posedge clk) begin
        psum_out_delayed <= psum_out_bottom;
        psum_en_delayed  <= psum_en_bottom[0] && (state == WAIT_FLUSH);
        psum_write_addr_reg <= psum_flush_cnt; 
        is_first_acc_delayed <= is_first_acc; // FIX: Delay is_first_acc to match BRAM write cycle
    end

    always_comb begin
        psum_we = psum_en_delayed;
        psum_write_addr = psum_write_addr_reg;
        for (int i=0; i<16; i++) begin
            if (is_first_acc_delayed) 
                psum_din[i*32 +: 32] = psum_out_delayed[i];
            else 
                psum_din[i*32 +: 32] = psum_out_delayed[i] + psum_bram_dout[i*32 +: 32];
        end
    end

    // BRAM write logic moved to the combined block above

    // =========================================================================
    // 7. Post-Processing Unit (Apply Bias, Right Shift, ReLU)
    // =========================================================================
    logic               post_proc_en;
    logic [31:0]        post_proc_x;
    logic [15:0][7:0]   final_ofm;
    logic               ofm_we_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            post_proc_en <= 1'b0;
            post_proc_x <= '0;
        end else begin
            post_proc_en <= (state == POST_PROC);
            post_proc_x <= stream_cnt; 
        end
    end
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ofm_we_reg <= 1'b0;
        end else begin
            ofm_we_reg <= post_proc_en;
            if (post_proc_en) begin
                for (int i=0; i<16; i++) begin
                    logic signed [31:0] val;
                    logic signed [31:0] s_val;
                    val = $signed(psum_bram_dout[i*32 +: 32]) + $signed(bias_array[i]);
                    s_val = (val + (32'sd1 <<< (reg_right_shift - 1))) >>> reg_right_shift;
                    
                    if (s_val > 127) final_ofm[i] <= 8'd127;
                    else if (s_val < -128) final_ofm[i] <= -8'sd128;
                    else final_ofm[i] <= s_val[7:0];
                end
            end
        end
    end
    
    logic [31:0] post_proc_x_delayed;
    logic [31:0] loop_y_delayed;
    logic [31:0] loop_cout_delayed;
    
    always_ff @(posedge clk) begin
        post_proc_x_delayed <= post_proc_x;
        loop_y_delayed <= loop_y;
        loop_cout_delayed <= loop_cout;
    end
    
    ofm_post_processor #(
        .DATA_WIDTH(8),
        .ADDR_WIDTH(16)
    ) u_post_processor (
        .clk(clk),
        .rst_n(rst_n),
        .reg_relu_en(reg_relu_en),
        .reg_pool_en(reg_pool_en),
        .reg_out_width(out_width),
        .reg_channels_out(reg_channels_out),
        .pea_we(ofm_we_reg),
        .pea_x(post_proc_x_delayed),
        .pea_y(loop_y_delayed),
        .pea_cout(loop_cout_delayed),
        .pea_data(final_ofm),
        .sram_we(ofm_we),
        .sram_addr(ofm_write_addr),
        .sram_data(ofm_write_data)
    );

endmodule
