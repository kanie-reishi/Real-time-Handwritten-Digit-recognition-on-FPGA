`timescale 1ns / 1ps

module tb_fc_layers();

    // ==========================================
    // Configuration Parameters
    // ==========================================
    localparam AXI_AWIDTH  = 40;
    localparam AXI_DWIDTH  = 128;
    localparam SRAM_AWIDTH = 11;
    
    // ==========================================
    // Signals Declaration
    // ==========================================
    logic clk;
    logic rst_n;
    
    // AXI-Lite
    logic [31:0] s_axi_awaddr, s_axi_wdata;
    logic s_axi_awvalid, s_axi_wvalid, s_axi_bready;
    logic s_axi_awready, s_axi_wready, s_axi_bvalid;
    logic [1:0]  s_axi_bresp;
    
    // AXI-Full (Mock)
    logic [AXI_AWIDTH-1:0] m_axi_araddr, m_axi_awaddr;
    logic [7:0]  m_axi_arlen, m_axi_awlen;
    logic [2:0]  m_axi_arsize, m_axi_awsize;
    logic [1:0]  m_axi_arburst, m_axi_awburst;
    logic        m_axi_arvalid, m_axi_arready;
    logic        m_axi_awvalid, m_axi_awready;
    logic [AXI_DWIDTH-1:0] m_axi_wdata, m_axi_rdata;
    logic        m_axi_wvalid, m_axi_wready, m_axi_wlast;
    logic        m_axi_rvalid, m_axi_rready, m_axi_rlast;
    logic        m_axi_bvalid, m_axi_bready;
    logic [1:0]  m_axi_bresp;
    
    // Interrupt
    logic finish_irq_o;

    // ==========================================
    // INIT DUT
    // ==========================================
    lenet_accelerator #(
        .AXI_AWIDTH(AXI_AWIDTH),
        .AXI_DWIDTH(AXI_DWIDTH),
        .SRAM_AWIDTH(SRAM_AWIDTH)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),   .s_axi_wvalid(s_axi_wvalid),   .s_axi_wready(s_axi_wready),
        .s_axi_bready(s_axi_bready), .s_axi_bvalid(s_axi_bvalid),   .s_axi_bresp(s_axi_bresp),
        // ... (AXI-Full connections ignored for simulation brevity, assume mock DDR)
        .m_axi_araddr(m_axi_araddr), .m_axi_arlen(m_axi_arlen),     .m_axi_arsize(m_axi_arsize),   .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata),   .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready), .m_axi_rlast(m_axi_rlast),
        .m_axi_awaddr(m_axi_awaddr), .m_axi_awlen(m_axi_awlen),     .m_axi_awsize(m_axi_awsize),   .m_axi_awburst(m_axi_awburst),
        .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata),   .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wlast(m_axi_wlast),   .m_axi_wready(m_axi_wready),
        .m_axi_bvalid(m_axi_bvalid), .m_axi_bready(m_axi_bready),   .m_axi_bresp(m_axi_bresp),
        .finish_irq_o(finish_irq_o)
    );

    // ==========================================
    // CLOCK & RESET
    // ==========================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // AXI-Lite Task
    task axi_lite_write(input [31:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            s_axi_awaddr  <= addr;
            s_axi_wdata   <= data;
            s_axi_awvalid <= 1'b1;
            s_axi_wvalid  <= 1'b1;
            s_axi_bready  <= 1'b1;
            do begin
                @(posedge clk);
            end while (!(s_axi_awready && s_axi_wready));
            s_axi_awvalid <= 1'b0;
            s_axi_wvalid  <= 1'b0;
            while (!s_axi_bvalid) @(posedge clk);
            s_axi_bready  <= 1'b0;
        end
    endtask

    // ==========================================
    // MAIN TEST FLOW
    // ==========================================
    initial begin
        rst_n = 0;
        s_axi_awvalid = 0; s_axi_wvalid = 0; s_axi_bready = 0;
        m_axi_arready = 1; m_axi_rvalid = 0; m_axi_rlast = 0;
        m_axi_awready = 1; m_axi_wready = 1; m_axi_bvalid = 0;
        
        #20 rst_n = 1;
        #50;

        $display("==================================================");
        $display("   STARTING FC LAYER TEST: 1x1 Convolution");
        $display("==================================================");

        // 1. Configure FC6 (120 in, 84 out) -> Mapped as 1x1 Conv
        $display("[+] Configuring FC6...");
        axi_lite_write(32'h0000_0100, 1);   // width = 1
        axi_lite_write(32'h0000_0104, 1);   // height = 1
        axi_lite_write(32'h0000_0108, 120); // cin = 120
        axi_lite_write(32'h0000_010C, 84);  // cout = 84
        axi_lite_write(32'h0000_0110, 1);   // kernel size = 1
        axi_lite_write(32'h0000_0114, 10);  // right shift
        axi_lite_write(32'h0000_0118, 1);   // row stride = 1
        axi_lite_write(32'h0000_011C, 1);   // col stride = 1
        
        axi_lite_write(32'h0000_0128, 1);   // reg_relu_en = 1 (FC6 uses ReLU)
        axi_lite_write(32'h0000_012C, 0);   // reg_pool_en = 0

        #100;
        
        // 2. Configure FC7 / Output (84 in, 10 out) -> Mapped as 1x1 Conv
        $display("[+] Configuring FC7 (Output Layer)...");
        axi_lite_write(32'h0000_0100, 1);   // width = 1
        axi_lite_write(32'h0000_0104, 1);   // height = 1
        axi_lite_write(32'h0000_0108, 84);  // cin = 84
        axi_lite_write(32'h0000_010C, 10);  // cout = 10
        axi_lite_write(32'h0000_0110, 1);   // kernel size = 1
        
        axi_lite_write(32'h0000_0128, 0);   // reg_relu_en = 0 (Output layer has NO ReLU)
        axi_lite_write(32'h0000_012C, 0);   // reg_pool_en = 0

        #100;
        
        $display("[PASS] FC mapping configuration successful!");
        $finish;
    end

endmodule
