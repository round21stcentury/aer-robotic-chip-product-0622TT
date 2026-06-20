`timescale 1ns / 1ps
//============================================================================
// tb_reflex_top_s3 — 스텝3 PL 통합 시뮬 (reflex_top_s3 ─ MCP 모델)
//   xadc_val 은 입력 포트(BD 의 xadc_reader 역할을 TB 가 직접 구동).
//   configured + obs 관측 + FSR(XADC) 트리거 → 홈 포즈 + 센서 해제.
//============================================================================
module tb_reflex_top_s3;
    reg aclk=0, aresetn=0; always #5 aclk=~aclk; integer errors=0;
    reg         dip=0;
    reg  [15:0] cfg_in = 16'h0104;       // enable + SPI_DIV 4
    reg  [15:0] thr_in = 16'h0800;       // FSR 임계 (1개)
    reg  [15:0] rule_in= 16'h005A;       // ★FSR 규칙(기능선택): 0x5A=덕포즈(act2) / 0x79=estop(act1), src=XADC
    reg  [15:0] xadc_in= 16'h0000;
    reg  [31:0] cmd_lo=0, cmd_hi=0, cmd_id=0;  // 정상명령 메일박스(이 sim 은 XADC만 검증 → idle)
    reg  [31:0] flinch_in = 32'd25000;         // ★움찔 1회성 지속(틱) — sim 용 (chip_feeder 전파+0x151 사이클 넉넉)
    reg  [15:0] rspeed_in = 16'd100;           // ★반사 0x151 속도율(1~100)
    wire [31:0] obs0, obs1;
    wire        reflex_active, configured;
    wire        mcp_sck, mcp_si, mcp_so, mcp_cs, mcp_int;

    reflex_top_s3 #(.SPI_HALF(8), .SEND_DIV(3000), .PROBE_DIV(1500), .SAMPLE_DIV(1500), .RESET_DELAY(200)) dut (
        .aclk(aclk), .aresetn(aresetn), .dip(dip), .cfg_in(cfg_in), .thr_in(thr_in),
        .rule_in(rule_in), .xadc_val(xadc_in), .flinch_in(flinch_in), .rspeed_in(rspeed_in),
        .cmd_lo(cmd_lo), .cmd_hi(cmd_hi), .cmd_id(cmd_id),
        .obs0(obs0), .obs1(obs1), .reflex_active(reflex_active), .configured(configured),
        .mcp_sck(mcp_sck), .mcp_si(mcp_si), .mcp_so(mcp_so), .mcp_cs(mcp_cs), .mcp_int(mcp_int)
    );
    mcp2515_model_v2 u_mcp (.sclk(mcp_sck), .mosi(mcp_si), .csn(mcp_cs), .miso(mcp_so), .int_n(mcp_int));

    task chk32(input [8*12:1] label, input [31:0] got, input [31:0] exp);
        begin if (got!==exp) begin errors=errors+1; $display("[FAIL] %0s=0x%08h (기대 0x%08h)",label,got,exp); end
              else $display("[ ok ] %0s=0x%08h",label,got); end
    endtask
    integer txc; reg saw151, sawpose; integer ws;
    initial begin
        repeat (10) @(posedge aclk); aresetn=1;
        $display("== 스텝3 PL 통합: reflex_top_s3 ─ MCP 모델 ==");
        while (!configured) @(posedge aclk);
        $display("configured=1");
        repeat (40000) @(posedge aclk);
        chk32("obs0(CANSTAT/CNF)", obs0, 32'h0000C080);

        // XADC<임계 → 무발사
        txc=u_mcp.tx_count; repeat (10000) @(posedge aclk);
        if (u_mcp.tx_count==txc && !reflex_active) $display("[ ok ] XADC<임계 무발사");
        else begin errors=errors+1; $display("[FAIL] 미발동인데 활성/송신"); end

        // XADC>=임계 → 홈 포즈
        xadc_in=16'h0900; txc=u_mcp.tx_count; repeat (16000) @(posedge aclk);
        if (reflex_active) $display("[ ok ] FSR → reflex_active=1");
        else begin errors=errors+1; $display("[FAIL] FSR 인데 비활성"); end
        saw151=0; sawpose=0;
        for (ws=0; ws<13000; ws=ws+1) begin @(posedge aclk);   // 한 포즈 사이클(0x151+155~7) 샘플
            if (u_mcp.last_tx_id==11'h151 && u_mcp.last_tx_data[23:16]==8'h64) saw151=1;   // 0x151 속도=100
            if (((u_mcp.last_tx_id==11'h155)||(u_mcp.last_tx_id==11'h156)||(u_mcp.last_tx_id==11'h157)) && u_mcp.last_tx_data===64'h0) sawpose=1;
        end
        if (saw151 && sawpose) $display("[ ok ] FSR 규칙=0x5A → ★0x151 속도=100 + 덕포즈(홈0)");
        else begin errors=errors+1; $display("[FAIL] 덕포즈 saw151=%b sawpose=%b",saw151,sawpose); end

        // ★FSR 규칙 전환(같은 임계 1개): rule_in 0x5A(덕포즈)→0x79(estop) → 반사가 estop(0x150)로
        rule_in=16'h0079; txc=u_mcp.tx_count; repeat (16000) @(posedge aclk);
        if (reflex_active) $display("[ ok ] FSR 규칙=0x79 → reflex_active=1");
        else begin errors=errors+1; $display("[FAIL] estop 규칙인데 비활성"); end
        if (u_mcp.tx_count>txc && u_mcp.last_tx_id==11'h150)
            $display("[ ok ] ★★FSR 규칙 0x5A→0x79 → estop(0x150) 전환 (같은 임계, 기능만 선택)");
        else begin errors=errors+1; $display("[FAIL] estop 전환 실패 id=0x%03h (0x150 기대)",u_mcp.last_tx_id); end
        rule_in=16'h005A;   // 덕포즈로 복귀

        // ★움찔(act3 1회성): xadc 내림(재무장) → rule=0x5B 전파 → xadc 엣지 → 홈포즈 잠깐 → flinch_ticks 후 자동해제
        //   ※ chip_feeder 가 rule2·xadc 를 주기(~6300클럭)마다 전파 → 변경 후 2주기 이상 대기 필요(아래 14000).
        xadc_in=16'h0000; repeat (14000) @(posedge aclk);    // xadc 내림 칩까지 전파 → estop 해제
        rule_in=16'h005B; repeat (14000) @(posedge aclk);    // rule2=0x5B 칩까지 전파
        xadc_in=16'h0900; txc=u_mcp.tx_count;                // ★엣지 → 움찔 시작(칩 전파 후 ~6300 내 발동, 15000틱)
        repeat (8000) @(posedge aclk);                       // 칩 전파 + 움찔 시작
        saw151=0; sawpose=0;
        for (ws=0; ws<10000; ws=ws+1) begin @(posedge aclk); // 움찔 중 샘플(< flinch 25000틱)
            if (u_mcp.last_tx_id==11'h151 && u_mcp.last_tx_data[23:16]==8'h64) saw151=1;
            if (((u_mcp.last_tx_id==11'h155)||(u_mcp.last_tx_id==11'h156)||(u_mcp.last_tx_id==11'h157)) && u_mcp.last_tx_data===64'h0) sawpose=1;
        end
        if (reflex_active && saw151 && sawpose)
            $display("[ ok ] ★움찔(0x5B) 발동 → ★0x151 속도=100 + 홈포즈(0), active=1");
        else begin errors=errors+1; $display("[FAIL] 움찔 active=%b saw151=%b sawpose=%b",reflex_active,saw151,sawpose); end
        repeat (28000) @(posedge aclk);                      // flinch_ticks(15000) 경과 → 자동해제
        if (!reflex_active) $display("[ ok ] ★움찔 1회성 자동해제 (xadc 계속 높음에도 active=0)");
        else begin errors=errors+1; $display("[FAIL] 움찔 자동해제 안됨"); end
        xadc_in=16'h0000; rule_in=16'h005A; repeat (8000) @(posedge aclk);

        // 센서 떼기 → 해제
        xadc_in=16'h0000; repeat (8000) @(posedge aclk); txc=u_mcp.tx_count; repeat (10000) @(posedge aclk);
        if (u_mcp.tx_count==txc) $display("[ ok ] 센서 떼면 해제");
        else begin errors=errors+1; $display("[FAIL] 해제 안 됨"); end

        if (u_mcp.tx_fail_cnt==0) $display("[ ok ] tx_fail_cnt=0"); else begin errors=errors+1; $display("[FAIL] tx_fail=%0d",u_mcp.tx_fail_cnt); end
        if (errors==0) $display("==== PASS: 스텝3 PL 통합 시뮬 통과 ====");
        else           $display("==== FAIL: 오류 %0d 개 ====", errors);
        $finish;
    end
    initial begin #45_000_000; $display("==== FAIL: 타임아웃 ===="); $finish; end
endmodule
