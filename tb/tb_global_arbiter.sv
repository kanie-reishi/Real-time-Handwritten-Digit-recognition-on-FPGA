`timescale 1ns / 1ps

module tb_global_arbiter();

    // ==========================================
    // Tham số cấu hình (Parameters)
    // ==========================================
    localparam AXI_AWIDTH  = 40;
    localparam AXI_DWIDTH  = 64;
    localparam SRAM_AWIDTH = 16;
    
    // ==========================================
    // Khai báo tín hiệu
    // ==========================================
    logic clk;
    logic rst_n;
    
    // --- 1. AXI-Lite Slave Interface (Host CPU) ---
    logic                    s_axi_awvalid;
    logic                    s_axi_awready;
    logic [31:0]             s_axi_awaddr;
    logic                    s_axi_wvalid;
    logic                    s_axi_wready;
    logic [31:0]             s_axi_wdata;
    
    // --- 2. AXI4-Full Master Interface (DDR) ---
    // Kênh AR
    logic [AXI_AWIDTH-1:0]   m_axi_araddr;
    logic [7:0]              m_axi_arlen;
    logic [2:0]              m_axi_arsize;
    logic [1:0]              m_axi_arburst;
    logic                    m_axi_arvalid;
    logic                    m_axi_arready;
    // Kênh R
    logic [AXI_DWIDTH-1:0]   m_axi_rdata;
    logic                    m_axi_rlast;
    logic                    m_axi_rvalid;
    logic                    m_axi_rready;
    // Kênh AW
    logic [AXI_AWIDTH-1:0]   m_axi_awaddr;
    logic [7:0]              m_axi_awlen;
    logic [2:0]              m_axi_awsize;
    logic [1:0]              m_axi_awburst;
    logic                    m_axi_awvalid;
    logic                    m_axi_awready;
    // Kênh W
    logic [AXI_DWIDTH-1:0]   m_axi_wdata;
    logic                    m_axi_wlast;
    logic                    m_axi_wvalid;
    logic                    m_axi_wready;
    // Kênh B
    logic [1:0]              m_axi_bresp;
    logic                    m_axi_bvalid;
    logic                    m_axi_bready;
    
    // --- 3. Controller Interface ---
    logic [63:0]             ctrl_inst_data_o;
    logic                    ctrl_inst_empty_o;
    logic                    ctrl_inst_read_i;
    
    logic                    ctrl_dma_req_i;
    logic                    ctrl_dma_dir_i;
    logic [AXI_AWIDTH-1:0]   ctrl_dma_addr_i;
    logic [31:0]             ctrl_dma_bytes_i;
    logic [1:0]              ctrl_dma_bank_sel_i;
    logic                    ctrl_dma_busy_o;
    
    // --- 4. SRAM Interfaces (Chỉ quan sát dạng sóng) ---
    logic                    wgt_we_o;
    logic [SRAM_AWIDTH-1:0]  wgt_addr_o;
    logic [AXI_DWIDTH-1:0]   wgt_wdata_o;
    
    logic                    ping_we_o;
    logic [SRAM_AWIDTH-1:0]  ping_addr_o;
    logic [AXI_DWIDTH-1:0]   ping_wdata_o;
    logic [AXI_DWIDTH-1:0]   ping_rdata_i;
    
    logic                    pong_we_o;
    logic [SRAM_AWIDTH-1:0]  pong_addr_o;
    logic [AXI_DWIDTH-1:0]   pong_wdata_o;
    logic [AXI_DWIDTH-1:0]   pong_rdata_i;

    // ==========================================
    // Instantiate DUT (Device Under Test)
    // ==========================================
    global_arbiter #(
        .AXI_AWIDTH(AXI_AWIDTH),
        .AXI_DWIDTH(AXI_DWIDTH),
        .SRAM_AWIDTH(SRAM_AWIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_wdata(s_axi_wdata),
        
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready),
        
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wlast(m_axi_wlast),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        
        .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready),
        
        .ctrl_inst_data_o(ctrl_inst_data_o),
        .ctrl_inst_empty_o(ctrl_inst_empty_o),
        .ctrl_inst_read_i(ctrl_inst_read_i),
        
        .ctrl_dma_req_i(ctrl_dma_req_i),
        .ctrl_dma_dir_i(ctrl_dma_dir_i),
        .ctrl_dma_addr_i(ctrl_dma_addr_i),
        .ctrl_dma_bytes_i(ctrl_dma_bytes_i),
        .ctrl_dma_bank_sel_i(ctrl_dma_bank_sel_i),
        .ctrl_dma_busy_o(ctrl_dma_busy_o),
        
        .wgt_we_o(wgt_we_o),
        .wgt_addr_o(wgt_addr_o),
        .wgt_wdata_o(wgt_wdata_o),
        
        .ping_we_o(ping_we_o),
        .ping_addr_o(ping_addr_o),
        .ping_wdata_o(ping_wdata_o),
        .ping_rdata_i(ping_rdata_i),
        
        .pong_we_o(pong_we_o),
        .pong_addr_o(pong_addr_o),
        .pong_wdata_o(pong_wdata_o),
        .pong_rdata_i(pong_rdata_i)
    );

    // ==========================================
    // Tạo xung Clock (100MHz)
    // ==========================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // Chu kỳ 10ns
    end
    
    // ==========================================
    // TASKS: Giao tiếp AXI-Lite (Host CPU)
    // ==========================================
    task axi_lite_write(input [31:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            s_axi_awvalid <= 1'b1;
            s_axi_awaddr  <= addr;
            s_axi_wvalid  <= 1'b1;
            s_axi_wdata   <= data;
            
            // Chờ cho đến khi slave nhận (ready = 1)
            wait(s_axi_awready && s_axi_wready);
            @(posedge clk);
            s_axi_awvalid <= 1'b0;
            s_axi_wvalid  <= 1'b0;
        end
    endtask

    // ==========================================
    // MÔ PHỎNG AXI-FULL SLAVE (DDR Memory)
    // ==========================================
    // 1. Phản hồi luồng Đọc (AR -> R)
    always @(posedge clk) begin
        if (!rst_n) begin
            m_axi_arready <= 1'b0;
            m_axi_rvalid  <= 1'b0;
            m_axi_rlast   <= 1'b0;
            m_axi_rdata   <= '0;
        end else begin
            // Luôn sẵn sàng nhận địa chỉ đọc
            m_axi_arready <= 1'b1;
            
            if (m_axi_arvalid && m_axi_arready) begin
                integer len;
                len = m_axi_arlen + 1;
                m_axi_arready <= 1'b0; // Bận xử lý
                
                @(posedge clk);
                // Bơm dữ liệu Rdata trả về
                for (integer i = 0; i < len; i = i + 1) begin
                    m_axi_rvalid <= 1'b1;
                    m_axi_rdata  <= $random; // Trả về dữ liệu ngẫu nhiên
                    m_axi_rlast  <= (i == len - 1) ? 1'b1 : 1'b0;
                    wait(m_axi_rready);
                    @(posedge clk);
                end
                m_axi_rvalid <= 1'b0;
                m_axi_rlast  <= 1'b0;
            end
        end
    end
    
    // 2. Phản hồi luồng Ghi (AW -> W -> B)
    always @(posedge clk) begin
        if (!rst_n) begin
            m_axi_awready <= 1'b0;
            m_axi_wready  <= 1'b0;
            m_axi_bvalid  <= 1'b0;
        end else begin
            m_axi_awready <= 1'b1;
            
            if (m_axi_awvalid && m_axi_awready) begin
                m_axi_awready <= 1'b0;
                // Chờ và nhận Wdata
                m_axi_wready <= 1'b1;
                while (!m_axi_wlast || !m_axi_wvalid) begin
                    @(posedge clk);
                end
                m_axi_wready <= 1'b0;
                
                // Gửi phản hồi B (OKAY)
                @(posedge clk);
                m_axi_bvalid <= 1'b1;
                m_axi_bresp  <= 2'b00; 
                wait(m_axi_bready);
                @(posedge clk);
                m_axi_bvalid <= 1'b0;
            end
        end
    end

    // ==========================================
    // LUỒNG KIỂM THỬ CHÍNH (MAIN TEST SEQUENCE)
    // ==========================================
    initial begin
        // --- KHỞI TẠO TÍN HIỆU ---
        rst_n = 0;
        s_axi_awvalid = 0;
        s_axi_awaddr  = 0;
        s_axi_wvalid  = 0;
        s_axi_wdata   = 0;
        
        m_axi_rready  = 1; // Luôn sẵn sàng nhận Rdata
        m_axi_bready  = 1; // Luôn sẵn sàng nhận Bresp
        
        ctrl_inst_read_i = 0;
        ctrl_dma_req_i   = 0;
        ctrl_dma_dir_i   = 0;
        ctrl_dma_addr_i  = 0;
        ctrl_dma_bytes_i = 0;
        ctrl_dma_bank_sel_i = 0;
        
        // Cấp dữ liệu giả cho đường Đọc từ Ping/Pong Bank lên DDR
        ping_rdata_i = 64'hAAAA_BBBB_CCCC_DDDD;
        pong_rdata_i = 64'h1111_2222_3333_4444;

        // Giữ reset 100ns
        #100;
        rst_n = 1;
        #50;
        
        // ----------------------------------------------------
        $display("[%0t] === TC1: Trạng thái sau Reset ===", $time);
        // ----------------------------------------------------
        #20;
        
        // ----------------------------------------------------
        $display("[%0t] === TC2: CPU nạp lệnh qua AXI-Lite ===", $time);
        // ----------------------------------------------------
        // Lệnh 64-bit: Nửa cao = 0xABCD_EF01, Nửa thấp = 0x2345_6789
        axi_lite_write(32'h04, 32'hABCDEF01);
        axi_lite_write(32'h00, 32'h23456789);
        
        #50;
        // Controller xin lấy lệnh từ FIFO ra
        if (!ctrl_inst_empty_o) begin
            ctrl_inst_read_i = 1'b1;
            @(posedge clk);
            ctrl_inst_read_i = 1'b0;
            $display("[%0t] Controller đọc được lệnh: %h", $time, ctrl_inst_data_o);
        end else begin
            $display("[%0t] ERROR: FIFO báo rỗng!", $time);
        end
        
        // ----------------------------------------------------
        $display("[%0t] === TC3: DMA Demux (Đọc DDR -> Ghi SRAM Ping) ===", $time);
        // ----------------------------------------------------
        @(posedge clk);
        ctrl_dma_req_i      <= 1'b1;
        ctrl_dma_dir_i      <= 1'b0;          // READ (DDR -> SRAM)
        ctrl_dma_addr_i     <= 40'h1000;
        ctrl_dma_bytes_i    <= 32'h40;        // 64 bytes
        ctrl_dma_bank_sel_i <= 2'b01;         // Chọn PING BANK (01)
        
        @(posedge clk);
        ctrl_dma_req_i      <= 1'b0;
        
        // Chờ DMA hoàn thành
        wait(!ctrl_dma_busy_o); 
        $display("[%0t] Hoàn thành DMA chuyển DDR -> PING Bank.", $time);
        #50;
        
        // ----------------------------------------------------
        $display("[%0t] === TC4: DMA Mux (Đọc SRAM Pong -> Ghi DDR) ===", $time);
        // ----------------------------------------------------
        @(posedge clk);
        ctrl_dma_req_i      <= 1'b1;
        ctrl_dma_dir_i      <= 1'b1;          // WRITE (SRAM -> DDR)
        ctrl_dma_addr_i     <= 40'h2000;
        ctrl_dma_bytes_i    <= 32'h20;        // 32 bytes
        ctrl_dma_bank_sel_i <= 2'b10;         // Chọn PONG BANK (10)
        
        @(posedge clk);
        ctrl_dma_req_i      <= 1'b0;
        
        // Chờ DMA hoàn thành
        wait(!ctrl_dma_busy_o);
        $display("[%0t] Hoàn thành DMA chuyển PONG Bank -> DDR.", $time);
        #50;
        
        // ----------------------------------------------------
        $display("[%0t] === TC5: Hardware Backpressure (Bơm FIFO) ===", $time);
        // ----------------------------------------------------
        // Bơm 16 lệnh liên tục để quan sát tín hiệu awready/wready
        for (int i = 0; i < 16; i++) begin
            axi_lite_write(32'h04, i);
            axi_lite_write(32'h00, ~i);
        end
        $display("[%0t] Hoàn thành bơm 16 lệnh.", $time);
        
        #100;
        $display("[%0t] === TẤT CẢ TEST CASE KẾT THÚC ===", $time);
        $finish;
    end

endmodule
