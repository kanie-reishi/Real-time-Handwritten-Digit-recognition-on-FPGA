`timescale 1ns / 1ps

module lenet_accelerator #(
    parameter AXI_AWIDTH  = 40, 
    parameter AXI_DWIDTH  = 64, // AXI Bus width
    parameter SRAM_DWIDTH = 128, // Internal SRAM width
    parameter SRAM_AWIDTH = 11   // 16KB per bank (2048 words * 16 bytes)
)(
    input  logic clk,
    input  logic rst_n,

    // =========================================================
    // 1. GIAO DIỆN AXI-LITE SLAVE (CPU -> FPGA)
    // =========================================================
    input  logic                    s_axi_awvalid,
    output logic                    s_axi_awready,
    input  logic [31:0]             s_axi_awaddr,
    input  logic                    s_axi_wvalid,
    output logic                    s_axi_wready,
    input  logic [31:0]             s_axi_wdata,
    
    // Các tín hiệu Read (Giản lược cho ví dụ)
    // input  logic s_axi_arvalid,
    // output logic s_axi_arready, ...
    
    input  logic                    s_axi_bready,
    output logic                    s_axi_bvalid,
    output logic [1:0]              s_axi_bresp,

    // =========================================================
    // 2. GIAO DIỆN AXI-FULL MASTER (FPGA -> DDR)
    // =========================================================
    output logic [AXI_AWIDTH-1:0]   m_axi_araddr,
    output logic [7:0]              m_axi_arlen,
    output logic [2:0]              m_axi_arsize,
    output logic [1:0]              m_axi_arburst,
    output logic                    m_axi_arvalid,
    input  logic                    m_axi_arready,
    
    input  logic [AXI_DWIDTH-1:0]   m_axi_rdata,
    input  logic                    m_axi_rlast,
    input  logic                    m_axi_rvalid,
    output logic                    m_axi_rready,

    output logic [AXI_AWIDTH-1:0]   m_axi_awaddr,
    output logic [7:0]              m_axi_awlen,
    output logic [2:0]              m_axi_awsize,
    output logic [1:0]              m_axi_awburst,
    output logic                    m_axi_awvalid,
    input  logic                    m_axi_awready,

    output logic [AXI_DWIDTH-1:0]   m_axi_wdata,
    output logic                    m_axi_wlast,
    output logic                    m_axi_wvalid,
    input  logic                    m_axi_wready,

    input  logic [1:0]              m_axi_bresp,
    input  logic                    m_axi_bvalid,
    output logic                    m_axi_bready,

    // =========================================================
    // 3. NGẮT (INTERRUPT TỚI CPU)
    // =========================================================
    output logic                    finish_irq_o
);

    // =========================================================
    // TÍN HIỆU KẾT NỐI NỘI BỘ
    // =========================================================
    // Instruction FIFO
    logic [63:0] inst_data;
    logic        inst_empty;
    logic        inst_read;

    // DMA Control
    logic                  dma_req;
    logic                  dma_dir;
    logic [AXI_AWIDTH-1:0] dma_addr;
    logic [31:0]           dma_bytes;
    logic [1:0]            dma_bank_sel;
    logic                  dma_busy;

    // PEA Control & Parameters
    logic        mac_start;
    logic        mac_done;
    logic        pool_start;
    logic        pool_done;
    
    logic [1:0]  src_bank;
    logic [1:0]  dst_bank;

    // PEA <-> SRAM Interfaces
    logic [SRAM_AWIDTH-1:0] pea_ifm_addr, pea_ofm_addr, pea_wgt_addr;
    logic                   pea_ifm_re, pea_ofm_we, pea_wgt_re;
    logic [SRAM_DWIDTH-1:0] pea_ifm_rdata, pea_ofm_wdata, pea_wgt_rdata;

    // SRAM Port A (DMA Access)
    logic                   wgt_we_a, ping_we_a, pong_we_a;
    logic [SRAM_AWIDTH-1:0] wgt_addr_a, ping_addr_a, pong_addr_a;
    logic [SRAM_DWIDTH-1:0] wgt_wdata_a, ping_wdata_a, pong_wdata_a;
    logic [SRAM_DWIDTH-1:0] wgt_rdata_a, ping_rdata_a, pong_rdata_a;

    // SRAM Port B (PEA Access)
    logic                   wgt_en_b, ping_en_b, pong_en_b;
    logic                   wgt_we_b, ping_we_b, pong_we_b;
    logic [SRAM_AWIDTH-1:0] wgt_addr_b, ping_addr_b, pong_addr_b;
    logic [SRAM_DWIDTH-1:0] wgt_wdata_b, ping_wdata_b, pong_wdata_b;
    logic [SRAM_DWIDTH-1:0] wgt_rdata_b, ping_rdata_b, pong_rdata_b;

    // Arbiter Outputs
    logic                   ifm_ping_en, ifm_pong_en;
    logic [SRAM_AWIDTH-1:0] ifm_ping_addr, ifm_pong_addr;
    
    logic                   ofm_ping_en, ofm_ping_we;
    logic [SRAM_AWIDTH-1:0] ofm_ping_addr;
    logic [SRAM_DWIDTH-1:0] ofm_ping_wdata;

    logic                   ofm_pong_en, ofm_pong_we;
    logic [SRAM_AWIDTH-1:0] ofm_pong_addr;
    logic [SRAM_DWIDTH-1:0] ofm_pong_wdata;

    // PEA Config
    logic [15:0] ifm_w, ifm_h, ifm_c, ofm_c;
    logic [7:0]  knl_size;
    logic [3:0]  stride, shift_amt;
    logic        relu_en;
    logic [1:0]  pool_type;

    // =========================================================
    // 1. GLOBAL ARBITER (AXI, DMA)
    // =========================================================
    global_arbiter #(
        .AXI_AWIDTH(AXI_AWIDTH),
        .AXI_DWIDTH(AXI_DWIDTH),
        .SRAM_DWIDTH(SRAM_DWIDTH),
        .SRAM_AWIDTH(SRAM_AWIDTH)
    ) u_global_arbiter (
        .clk(clk), .rst_n(rst_n),
        // AXI-Lite
        .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
        .s_axi_awaddr(s_axi_awaddr),   .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),   .s_axi_wdata(s_axi_wdata),
        // AXI-Full
        .m_axi_araddr(m_axi_araddr),   .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize),   .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata),     .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(m_axi_rvalid),   .m_axi_rready(m_axi_rready),
        .m_axi_awaddr(m_axi_awaddr),   .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize),   .m_axi_awburst(m_axi_awburst),
        .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata),     .m_axi_wlast(m_axi_wlast),
        .m_axi_wvalid(m_axi_wvalid),   .m_axi_wready(m_axi_wready),
        .m_axi_bresp(m_axi_bresp),     .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready),
        // Instruction FIFO
        .ctrl_inst_data_o(inst_data), .ctrl_inst_empty_o(inst_empty), .ctrl_inst_read_i(inst_read),
        // DMA Control
        .ctrl_dma_req_i(dma_req), .ctrl_dma_dir_i(dma_dir), .ctrl_dma_addr_i(dma_addr),
        .ctrl_dma_bytes_i(dma_bytes), .ctrl_dma_bank_sel_i(dma_bank_sel), .ctrl_dma_busy_o(dma_busy),
        // SRAM Port A
        .wgt_we_o(wgt_we_a),   .wgt_addr_o(wgt_addr_a),   .wgt_wdata_o(wgt_wdata_a),
        .ping_we_o(ping_we_a), .ping_addr_o(ping_addr_a), .ping_wdata_o(ping_wdata_a), .ping_rdata_i(ping_rdata_a),
        .pong_we_o(pong_we_a), .pong_addr_o(pong_addr_a), .pong_wdata_o(pong_wdata_a), .pong_rdata_i(pong_rdata_a)
    );

    // Simple AXI-Lite Write Response (B channel)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_bvalid <= 1'b0;
        end else begin
            // When both address and data are accepted, assert bvalid
            if (s_axi_awvalid && s_axi_wvalid && s_axi_awready && s_axi_wready && !s_axi_bvalid) begin
                s_axi_bvalid <= 1'b1;
            end else if (s_axi_bready && s_axi_bvalid) begin
                // Deassert bvalid when master is ready
                s_axi_bvalid <= 1'b0;
            end
        end
    end
    assign s_axi_bresp  = 2'b00; // OKAY response

    // =========================================================
    // 2. CONTROLLER
    // =========================================================
    controller_v2 #(
        .AXI_AWIDTH(AXI_AWIDTH),
        .AXI_DWIDTH(AXI_DWIDTH)
    ) u_ctrl (
        .clk(clk), .rst_n(rst_n),
        .inst_data_i(inst_data), .inst_empty_i(inst_empty), .inst_read_o(inst_read),
        .dma_req_o(dma_req), .dma_dir_o(dma_dir), .dma_addr_o(dma_addr),
        .dma_bytes_o(dma_bytes), .dma_bank_sel_o(dma_bank_sel), .dma_busy_i(dma_busy),
        .mac_start_o(mac_start), .mac_done_i(mac_done),
        .pool_start_o(pool_start), .pool_done_i(pool_done),
        .src_bank_o(src_bank), .dst_bank_o(dst_bank),
        .ifm_w_o(ifm_w), .ifm_h_o(ifm_h), .ifm_c_o(ifm_c), .ofm_c_o(ofm_c),
        .knl_size_o(knl_size), .stride_o(stride), .shift_amt_o(shift_amt),
        .relu_en_o(relu_en), .pool_type_o(pool_type),
        .finish_irq_o(finish_irq_o)
    );

    // =========================================================
    // 3. IFM / OFM ARBITERS
    // =========================================================
    logic bank_sel_bit;
    assign bank_sel_bit = (src_bank == 2'b10) ? 1'b1 : 1'b0; // 0=Ping, 1=Pong

    ifm_arbiter #(
        .ADDR_WIDTH(SRAM_AWIDTH),
        .DATA_WIDTH(SRAM_DWIDTH)
    ) u_ifm_arbiter (
        .bank_sel(bank_sel_bit),
        .pea_ifm_addr(pea_ifm_addr[SRAM_AWIDTH-1:0]), .pea_ifm_re(pea_ifm_re), .pea_ifm_rdata(pea_ifm_rdata),
        .ping_en(ifm_ping_en), .ping_addr(ifm_ping_addr), .ping_rdata(ping_rdata_b),
        .pong_en(ifm_pong_en), .pong_addr(ifm_pong_addr), .pong_rdata(pong_rdata_b)
    );

    ofm_arbiter #(
        .ADDR_WIDTH(SRAM_AWIDTH),
        .DATA_WIDTH(SRAM_DWIDTH)
    ) u_ofm_arbiter (
        .bank_sel(bank_sel_bit),
        .pea_ofm_addr(pea_ofm_addr[SRAM_AWIDTH-1:0]), .pea_ofm_we(pea_ofm_we), .pea_ofm_wdata(pea_ofm_wdata),
        .ping_en(ofm_ping_en), .ping_we(ofm_ping_we), .ping_addr(ofm_ping_addr), .ping_wdata(ofm_ping_wdata),
        .pong_en(ofm_pong_en), .pong_we(ofm_pong_we), .pong_addr(ofm_pong_addr), .pong_wdata(ofm_pong_wdata)
    );

    // =========================================================
    // 4. MUXING TÍN HIỆU PORT B CHO PING / PONG BANK
    // =========================================================
    assign ping_en_b    = ifm_ping_en | ofm_ping_en;
    assign ping_we_b    = ofm_ping_we;
    assign ping_addr_b  = ifm_ping_en ? ifm_ping_addr : ofm_ping_addr;
    assign ping_wdata_b = ofm_ping_wdata;

    assign pong_en_b    = ifm_pong_en | ofm_pong_en;
    assign pong_we_b    = ofm_pong_we;
    assign pong_addr_b  = ifm_pong_en ? ifm_pong_addr : ofm_pong_addr;
    assign pong_wdata_b = ofm_pong_wdata;

    // =========================================================
    // 5. SRAM BANKS
    // =========================================================
    assign wgt_rdata_a = '0; // DMA không đọc từ Wgt Bank

    sram_tdp #(
        .DWIDTH(SRAM_DWIDTH), .AWIDTH(SRAM_AWIDTH)
    ) u_ping_bank (
        .clk(clk),
        .ena(1'b1), .wea(ping_we_a), .addra(ping_addr_a), .dina(ping_wdata_a), .douta(ping_rdata_a),
        .enb(ping_en_b), .web(ping_we_b), .addrb(ping_addr_b), .dinb(ping_wdata_b), .doutb(ping_rdata_b)
    );

    sram_tdp #(
        .DWIDTH(SRAM_DWIDTH), .AWIDTH(SRAM_AWIDTH)
    ) u_pong_bank (
        .clk(clk),
        .ena(1'b1), .wea(pong_we_a), .addra(pong_addr_a), .dina(pong_wdata_a), .douta(pong_rdata_a),
        .enb(pong_en_b), .web(pong_we_b), .addrb(pong_addr_b), .dinb(pong_wdata_b), .doutb(pong_rdata_b)
    );

    sram_tdp #(
        .DWIDTH(SRAM_DWIDTH), .AWIDTH(SRAM_AWIDTH)
    ) u_wgt_bank (
        .clk(clk),
        .ena(1'b1), .wea(wgt_we_a), .addra(wgt_addr_a), .dina(wgt_wdata_a), .douta(),
        .enb(pea_wgt_re), .web(1'b0), .addrb(pea_wgt_addr[SRAM_AWIDTH-1:0]), .dinb('0), .doutb(pea_wgt_rdata)
    );

    // =========================================================
    // 6. PROCESSING ELEMENT ARRAY (PEA)
    // =========================================================
    // Route AXI-Lite writes to PEA config if address is in 0x100 - 0x1FF
    logic pea_cfg_we;
    assign pea_cfg_we = s_axi_awvalid && s_axi_wvalid && (s_axi_awaddr >= 32'h0000_0100) && (s_axi_awaddr < 32'h0000_0200);

    pea_top #(
        .DATA_WIDTH(8),
        .PSUM_WIDTH(32),
        .ADDR_WIDTH(16) // Khớp với ADDR_WIDTH nội bộ của khối PEA
    ) u_pea (
        .clk(clk),
        .rst_n(rst_n),
        .start(mac_start),
        .done(mac_done),
        
        // Config interface mapped to AXI-Lite
        .cfg_addr(s_axi_awaddr[7:0]),
        .cfg_data(s_axi_wdata),
        .cfg_we(pea_cfg_we),
        
        // Memory interfaces
        .wb_read_addr(pea_wgt_addr),
        .wb_re(pea_wgt_re),
        .wb_read_data(pea_wgt_rdata),
        
        .ifm_read_addr(pea_ifm_addr),
        .ifm_re(pea_ifm_re),
        .ifm_read_data(pea_ifm_rdata),
        
        .ofm_write_addr(pea_ofm_addr),
        .ofm_we(pea_ofm_we),
        .ofm_write_data(pea_ofm_wdata)
    );

    // Pool done hardcoded to 1 for now (if Pool is not integrated)
    assign pool_done = 1'b1;

endmodule
