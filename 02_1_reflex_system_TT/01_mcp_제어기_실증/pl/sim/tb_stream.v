`timescale 1ns / 1ps
//============================================================================
// tb_stream — ★연속 스트림 + GPIO 쓰기 스큐 재현으로 데이터 섞임 디버그
//   HILS 처럼 155/156/157 을 번갈아 연속 전송. 각 id 에 ★고유 데이터★(id 가 데이터에 박힘)
//   를 실어서, MCP 로 나간 프레임의 id 와 데이터가 ★일치하는지★ 검사.
//   ★GPIO 쓰기 스큐 모델: cmd_id(토글)를 cmd_lo/hi 보다 SKEW 클럭 ★먼저★ 바꿈(최악).
//   섞이면 [MIX] 출력 → settle 부족. 깨끗하면 RTL 무죄.
//============================================================================
module tb_stream;
    reg aclk=0, aresetn=0; always #5 aclk=~aclk;
    integer errors=0, frames=0;
    reg  [15:0] cfg_in = 16'h0104;
    reg  [31:0] cmd_lo=0, cmd_hi=0, cmd_id=0;
    wire [31:0] obs0, obs1;
    wire        configured;
    wire        mcp_sck, mcp_si, mcp_so, mcp_cs, mcp_int;

    reflex_top_s1 #(.SPI_HALF(8), .PROBE_DIV(3000), .SAMPLE_DIV(3000), .RESET_DELAY(200)) dut (
        .aclk(aclk), .aresetn(aresetn), .cfg_in(cfg_in),
        .cmd_lo(cmd_lo), .cmd_hi(cmd_hi), .cmd_id(cmd_id),
        .obs0(obs0), .obs1(obs1), .configured(configured),
        .mcp_sck(mcp_sck), .mcp_si(mcp_si), .mcp_so(mcp_so), .mcp_cs(mcp_cs), .mcp_int(mcp_int)
    );
    mcp2515_model_v2 u_mcp (.sclk(mcp_sck), .mosi(mcp_si), .csn(mcp_cs), .miso(mcp_so), .int_n(mcp_int));

    // 한 프레임을 ★스큐 있게★ 메일박스에 적재: id(토글) 먼저, 몇 클럭 뒤 lo/hi.
    reg tog=0;
    integer SKEW = 6;     // 토글이 데이터보다 SKEW 클럭 먼저 도착(최악 스큐)
    integer GAP  = 30;    // ★프레임 간격. 작음=연달아(페이싱 실패). 큼=페이싱 정상.
    task send_skewed(input [10:0] id, input [31:0] d_lo, input [31:0] d_hi);
        integer i;
        begin
            // ★토글+id 를 먼저 (데이터보다 SKEW 클럭 앞서)
            @(posedge aclk); tog=~tog; cmd_id <= {tog, 20'd0, id};
            for (i=0;i<SKEW;i=i+1) @(posedge aclk);
            // 그 다음 데이터
            cmd_lo <= d_lo; cmd_hi <= d_hi;
            // ★프레임 간격 = GAP. 작게 주면 연달아(페이싱 실패) 시나리오.
            repeat (GAP) @(posedge aclk);
        end
    endtask

    // MCP 로 나간 프레임 검사: 데이터에 id 가 박혀있으니 id 와 일치해야
    //   규약: lo = {id, 16'hAAAA}, hi = {id, 16'h5555} → 데이터 상위 11비트(D)가 id 와 같아야
    reg [10:0] sent_id; reg [31:0] sent_lo, sent_hi;
    integer last_txc;
    task check_last;
        reg [10:0] did_lo, did_hi;
        begin
            // last_tx_data[7:0]=D0 ... norm_data = {hi, lo}. lo=cmd_lo, hi=cmd_hi.
            // lo = {sent_id, 16'hAAAA} → cmd_lo[31:21]=id. check.
            did_lo = u_mcp.last_tx_data[26:16];   // cmd_lo 에 박은 id 위치
            did_hi = u_mcp.last_tx_data[58:48];   // cmd_hi 에 박은 id 위치
            frames = frames + 1;
            if (did_lo !== u_mcp.last_tx_id || did_hi !== u_mcp.last_tx_id) begin
                errors = errors + 1;
                $display("[MIX] id=0x%03h 인데 데이터내 id: lo=0x%03h hi=0x%03h  (data=0x%016h)",
                         u_mcp.last_tx_id, did_lo, did_hi, u_mcp.last_tx_data);
            end
        end
    endtask

    integer k;
    initial begin
        repeat (10) @(posedge aclk); aresetn=1;
        $display("== 스트림 섞임 디버그 (스큐=%0d, 연속 155/156/157) ==", SKEW);
        while (!configured) @(posedge aclk);
        repeat (20000) @(posedge aclk);

        last_txc = u_mcp.tx_count;
        // 155/156/157 을 번갈아 연속 전송 (각 데이터에 id 박음)
        for (k=0;k<30;k=k+1) begin
            case (k%3)
                0: send_skewed(11'h155, {11'h155,16'hAAAA}, {11'h155,16'h5555});
                1: send_skewed(11'h156, {11'h156,16'hAAAA}, {11'h156,16'h5555});
                default: send_skewed(11'h157, {11'h157,16'hAAAA}, {11'h157,16'h5555});
            endcase
            // 새 프레임이 MCP 로 나갔으면 검사
            if (u_mcp.tx_count > last_txc) begin last_txc=u_mcp.tx_count; check_last(); end
        end
        repeat (10000) @(posedge aclk);
        if (u_mcp.tx_count > last_txc) check_last();

        $display("검사 프레임 %0d 개, 섞임 %0d 개", frames, errors);
        if (errors==0) $display("==== PASS: 스트림 섞임 없음 (settle 유효, RTL 무죄) ====");
        else           $display("==== FAIL: 섞임 %0d 개 — settle 부족, RTL 버그 ====", errors);
        $finish;
    end
    initial begin #80_000_000; $display("==== FAIL: 타임아웃 ===="); $finish; end
endmodule
