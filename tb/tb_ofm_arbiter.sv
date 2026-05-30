`timescale 1ns / 1ps

module tb_ofm_arbiter();

    // Thông số
    localparam ADDR_WIDTH = 11;
    localparam DATA_WIDTH = 128;

    // Tín hiệu
    logic                  bank_sel;
    logic [ADDR_WIDTH-1:0] pea_ofm_addr;
    logic                  pea_ofm_we;
    logic [DATA_WIDTH-1:0] pea_ofm_wdata;

    logic                  ping_en;
    logic                  ping_we;
    logic [ADDR_WIDTH-1:0] ping_addr;
    logic [DATA_WIDTH-1:0] ping_wdata;

    logic                  pong_en;
    logic                  pong_we;
    logic [ADDR_WIDTH-1:0] pong_addr;
    logic [DATA_WIDTH-1:0] pong_wdata;

    // DUT
    ofm_arbiter #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .bank_sel(bank_sel),
        .pea_ofm_addr(pea_ofm_addr),
        .pea_ofm_we(pea_ofm_we),
        .pea_ofm_wdata(pea_ofm_wdata),
        
        .ping_en(ping_en),
        .ping_we(ping_we),
        .ping_addr(ping_addr),
        .ping_wdata(ping_wdata),
        
        .pong_en(pong_en),
        .pong_we(pong_we),
        .pong_addr(pong_addr),
        .pong_wdata(pong_wdata)
    );

    initial begin
        $display("========================================");
        $display("   BẮT ĐẦU TEST: OFM ARBITER");
        $display("========================================");
        
        // Khởi tạo
        bank_sel = 0;
        pea_ofm_addr = '0;
        pea_ofm_we = 0;
        pea_ofm_wdata = 128'hDEAD_BEEF_CAFE_BABE_0123_4567_89AB_CDEF;
        
        #10;
        
        // Test Case 1: bank_sel = 0 (Ping là IFM -> Pong là OFM)
        $display("[TC1] bank_sel = 0 (Pong -> OFM)");
        bank_sel = 0;
        pea_ofm_we = 1;
        pea_ofm_addr = 11'hABC;
        #10;
        
        if (pong_en === 1 && pong_we === 1 && pong_addr === 11'hABC && pong_wdata === pea_ofm_wdata && ping_en === 0) begin
            $display("   [PASS] Tín hiệu Write điều hướng đúng tới Pong Bank!");
        end else begin
            $display("   [FAIL] Trạng thái không mong đợi! pong_en=%b, ping_en=%b", pong_en, ping_en);
        end
        
        // Test Case 2: bank_sel = 1 (Pong là IFM -> Ping là OFM)
        $display("[TC2] bank_sel = 1 (Ping -> OFM)");
        bank_sel = 1;
        pea_ofm_we = 1;
        pea_ofm_addr = 11'hDEF;
        pea_ofm_wdata = 128'h1111_2222_3333_4444_5555_6666_7777_8888;
        #10;
        
        if (ping_en === 1 && ping_we === 1 && ping_addr === 11'hDEF && ping_wdata === pea_ofm_wdata && pong_en === 0) begin
            $display("   [PASS] Tín hiệu Write điều hướng đúng tới Ping Bank!");
        end else begin
            $display("   [FAIL] Trạng thái không mong đợi! pong_en=%b, ping_en=%b", pong_en, ping_en);
        end
        
        // Test Case 3: Không có yêu cầu Write
        $display("[TC3] Không có yêu cầu ghi (pea_ofm_we = 0)");
        pea_ofm_we = 0;
        #10;
        
        if (ping_en === 0 && pong_en === 0 && ping_we === 0 && pong_we === 0) begin
            $display("   [PASS] Cả hai bank đều không Write Enable!");
        end else begin
            $display("   [FAIL] Một bank vẫn Enable khi không có yêu cầu ghi!");
        end
        
        $display("========================================");
        $display("   KẾT THÚC TEST");
        $display("========================================");
        $finish;
    end

endmodule
