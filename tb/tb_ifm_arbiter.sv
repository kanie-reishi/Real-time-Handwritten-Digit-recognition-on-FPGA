`timescale 1ns / 1ps

module tb_ifm_arbiter();

    // Thông số
    localparam ADDR_WIDTH = 11;
    localparam DATA_WIDTH = 128;

    // Tín hiệu
    logic                  bank_sel;
    logic [ADDR_WIDTH-1:0] pea_ifm_addr;
    logic                  pea_ifm_re;
    logic [DATA_WIDTH-1:0] pea_ifm_rdata;

    logic                  ping_en;
    logic [ADDR_WIDTH-1:0] ping_addr;
    logic [DATA_WIDTH-1:0] ping_rdata;

    logic                  pong_en;
    logic [ADDR_WIDTH-1:0] pong_addr;
    logic [DATA_WIDTH-1:0] pong_rdata;

    // DUT
    ifm_arbiter #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .bank_sel(bank_sel),
        .pea_ifm_addr(pea_ifm_addr),
        .pea_ifm_re(pea_ifm_re),
        .pea_ifm_rdata(pea_ifm_rdata),
        
        .ping_en(ping_en),
        .ping_addr(ping_addr),
        .ping_rdata(ping_rdata),
        
        .pong_en(pong_en),
        .pong_addr(pong_addr),
        .pong_rdata(pong_rdata)
    );

    initial begin
        $display("========================================");
        $display("   BẮT ĐẦU TEST: IFM ARBITER");
        $display("========================================");
        
        // Khởi tạo
        bank_sel = 0;
        pea_ifm_addr = '0;
        pea_ifm_re = 0;
        ping_rdata = 128'hAAAA_AAAA_AAAA_AAAA_AAAA_AAAA_AAAA_AAAA;
        pong_rdata = 128'hBBBB_BBBB_BBBB_BBBB_BBBB_BBBB_BBBB_BBBB;
        
        #10;
        
        // Test Case 1: bank_sel = 0 (Ping là IFM)
        $display("[TC1] bank_sel = 0 (Ping -> IFM)");
        bank_sel = 0;
        pea_ifm_re = 1;
        pea_ifm_addr = 11'h123;
        #10;
        
        if (ping_en === 1 && ping_addr === 11'h123 && pong_en === 0 && pea_ifm_rdata === ping_rdata) begin
            $display("   [PASS] Tín hiệu điều hướng đúng tới Ping Bank và rdata lấy từ Ping!");
        end else begin
            $display("   [FAIL] Trạng thái không mong đợi! ping_en=%b, pong_en=%b", ping_en, pong_en);
        end
        
        // Test Case 2: bank_sel = 1 (Pong là IFM)
        $display("[TC2] bank_sel = 1 (Pong -> IFM)");
        bank_sel = 1;
        pea_ifm_re = 1;
        pea_ifm_addr = 11'h456;
        #10;
        
        if (pong_en === 1 && pong_addr === 11'h456 && ping_en === 0 && pea_ifm_rdata === pong_rdata) begin
            $display("   [PASS] Tín hiệu điều hướng đúng tới Pong Bank và rdata lấy từ Pong!");
        end else begin
            $display("   [FAIL] Trạng thái không mong đợi! ping_en=%b, pong_en=%b", ping_en, pong_en);
        end
        
        // Test Case 3: Không có yêu cầu đọc
        $display("[TC3] Không có yêu cầu đọc (pea_ifm_re = 0)");
        pea_ifm_re = 0;
        #10;
        
        if (ping_en === 0 && pong_en === 0) begin
            $display("   [PASS] Cả hai bank đều không Enable!");
        end else begin
            $display("   [FAIL] Một bank vẫn Enable khi không có yêu cầu đọc!");
        end
        
        $display("========================================");
        $display("   KẾT THÚC TEST");
        $display("========================================");
        $finish;
    end

endmodule
