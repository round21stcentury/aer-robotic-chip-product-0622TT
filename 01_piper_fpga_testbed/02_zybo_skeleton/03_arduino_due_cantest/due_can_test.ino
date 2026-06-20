/*
 * Arduino Due — CAN 실버스 송수신 테스트 (트랜시버 검증용)
 * ─────────────────────────────────────────────────────────────
 *  목적: FPGA 자리에 Due를 넣고 동일 트랜시버+USB-CAN+PC로 통신.
 *        되면 → 트랜시버/USB-CAN/배선 정상 → 범인은 FPGA쪽.
 *        안 되면 → 트랜시버/배선/USB-CAN 쪽 문제.
 *  - CAN0 사용 (Due의 CANTX/CANRX 핀), 1 Mbps, 클래식 CAN
 *  - TX: ID=0x123, 8바이트(11 22 33 44 55 66 77 88)를 0.5초마다 송신
 *  - RX: 들어온 프레임 시리얼 출력
 *  - 프레임 포맷은 FPGA 테스트와 동일 → PC에서 바로 비교
 * ─────────────────────────────────────────────────────────────
 *  라이브러리 설치 (둘 다 collin80, Arduino 라이브러리매니저 또는 GitHub):
 *    - due_can     : https://github.com/collin80/due_can
 *    - can_common  : https://github.com/collin80/can_common   (due_can 의존성)
 *
 *  배선 (Due ↔ 트랜시버):
 *    Due CANTX  → 트랜시버 TXD(D)      (Due 보드의 "CANTX" 실크 핀)
 *    Due CANRX  ← 트랜시버 RXD(R)      (Due 보드의 "CANRX" 실크 핀)
 *    Due 3.3V   → 트랜시버 VCC
 *    Due GND    → 트랜시버 GND (USB-CAN과 GND 공통!)
 *    트랜시버 CANH/CANL → USB-CAN CANH/CANL, 양끝 120Ω
 *
 *  PC 쪽:
 *    sudo ip link set can0 up type can bitrate 1000000
 *    candump can0                          # Due가 보낸 0x123 뜨면 TX OK
 *    cansend can0 456#DEADBEEFCAFEBABE     # 시리얼에 RX 뜨면 RX OK
 */
#include <due_can.h>

const uint32_t TX_ID   = 0x123;   // 표준 11비트 ID
const uint32_t TX_PERIOD_MS = 500;

uint32_t lastTx = 0;
uint32_t txCount = 0, rxCount = 0;

void setup() {
  Serial.begin(115200);
  while (!Serial && millis() < 3000) { }   // USB 시리얼 대기(최대 3초)
  Serial.println("=== Arduino Due CAN 실버스 테스트 (1Mbps) ===");

  // CAN0 시작, 1 Mbps
  if (Can0.begin(CAN_BPS_1000K)) {
    Serial.println("Can0.begin OK (1Mbps)");
  } else {
    Serial.println("Can0.begin 실패!");
  }

  // 모든 프레임 수신 허용 (catch-all 메일박스)
  Can0.watchFor();

  Serial.println("송신(0x123) + 수신 대기. PC: candump / cansend");
}

void loop() {
  // --- 송신: 0.5초마다 ---
  if (millis() - lastTx >= TX_PERIOD_MS) {
    lastTx = millis();

    CAN_FRAME tx;
    tx.id       = TX_ID;
    tx.extended = false;     // 표준 ID
    tx.rtr      = 0;
    tx.length   = 8;
    tx.data.byte[0] = 0x11;
    tx.data.byte[1] = 0x22;
    tx.data.byte[2] = 0x33;
    tx.data.byte[3] = 0x44;
    tx.data.byte[4] = 0x55;
    tx.data.byte[5] = 0x66;
    tx.data.byte[6] = 0x77;
    tx.data.byte[7] = 0x88;

    if (Can0.sendFrame(tx)) {
      Serial.print("TX #"); Serial.print(++txCount);
      Serial.println(": ID=0x123 8B 보냄");
    } else {
      Serial.println("TX 실패 (메일박스 full / ACK 못받음?)");
    }
  }

  // --- 수신: 들어온 프레임 출력 ---
  if (Can0.available() > 0) {
    CAN_FRAME rx;
    Can0.read(rx);
    Serial.print(">>> RX #"); Serial.print(++rxCount);
    Serial.print(": ID=0x"); Serial.print(rx.id, HEX);
    Serial.print(rx.extended ? " (ext)" : " (std)");
    Serial.print(" DLC="); Serial.print(rx.length);
    Serial.print(" DATA=");
    for (int i = 0; i < rx.length; i++) {
      if (rx.data.byte[i] < 0x10) Serial.print("0");
      Serial.print(rx.data.byte[i], HEX);
      Serial.print(" ");
    }
    Serial.println();
  }
}
