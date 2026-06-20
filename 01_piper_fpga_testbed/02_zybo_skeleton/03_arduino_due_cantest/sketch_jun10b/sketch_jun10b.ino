/*
 * Arduino Due ×2 — CAN 2노드 상호통신 테스트
 * ─────────────────────────────────────────────────────────────
 *  목적: USB-CAN/PC 완전히 빼고, Due↔Due 순수 CAN 통신 검증.
 *        되면 → Due코드+트랜시버+버스배선+종단 전부 정상 → 원래 문제는 USB-CAN쪽.
 *        안 되면 → 트랜시버/배선/종단이 아직 문제 → USB-CAN 무죄.
 *
 *  ★보드마다 MY_ID 다르게 설정하고 각각 업로드★
 *     1번 보드: #define MY_ID 0x111
 *     2번 보드: #define MY_ID 0x222
 *
 *  판정은 TX가 아니라 RX로! :
 *     1번 시리얼에 "RX ID=0x222" 뜨고, 2번 시리얼에 "RX ID=0x111" 뜨면 → 상호통신 성공.
 *     (TX "보냄"은 큐에 넣은 것뿐, ACK 증거 아님)
 *
 *  배선 (각 Due마다 트랜시버 1개씩, 총 2개 필요!):
 *     Due CANTX → 트랜시버 TXD,  Due CANRX ← 트랜시버 RXD
 *     Due 3.3V → 트랜시버 VCC,   Due GND → 트랜시버 GND
 *     트랜시버A CANH ─ 트랜시버B CANH
 *     트랜시버A CANL ─ 트랜시버B CANL
 *     ★양 끝 120Ω (둘 다), 두 Due GND 공통★
 *
 *  라이브러리: due_can + can_common (collin80)
 */
#include <due_can.h>

#define MY_ID  0x111      // ★2번 보드는 0x222로 바꿔서 업로드★

uint32_t lastTx = 0;
uint32_t txCount = 0, rxCount = 0;

void setup() {
  Serial.begin(115200);
  while (!Serial && millis() < 3000) { }
  Serial.print("=== Due CAN 2노드 테스트 (MY_ID=0x");
  Serial.print(MY_ID, HEX);
  Serial.println(") ===");

  if (Can0.begin(CAN_BPS_1000K)) Serial.println("Can0.begin OK (1Mbps)");
  else                           Serial.println("Can0.begin 실패!");

  Can0.watchFor();   // 모든 프레임 수신 허용
  Serial.println("송신+수신 시작. 상대 ID가 RX로 뜨면 성공.");
}

void loop() {
  // --- 송신: 0.5초마다 MY_ID ---
  if (millis() - lastTx >= 500) {
    lastTx = millis();
    CAN_FRAME tx;
    tx.id       = MY_ID;
    tx.extended = false;
    tx.rtr      = 0;
    tx.length   = 8;
    for (int i = 0; i < 8; i++) tx.data.byte[i] = 0x10 + i;

    if (Can0.sendFrame(tx)) {
      Serial.print("TX #"); Serial.print(++txCount);
      Serial.print(" ID=0x"); Serial.println(MY_ID, HEX);
    } else {
      Serial.println("TX 실패 (메일박스 full)");
    }
  }

  // --- 수신: 들어온 프레임 출력 (이게 진짜 성공 증거) ---
  if (Can0.available() > 0) {
    CAN_FRAME rx;
    Can0.read(rx);
    Serial.print(">>> RX #"); Serial.print(++rxCount);
    Serial.print(" ID=0x"); Serial.print(rx.id, HEX);
    Serial.print(" DATA=");
    for (int i = 0; i < rx.length; i++) {
      if (rx.data.byte[i] < 0x10) Serial.print("0");
      Serial.print(rx.data.byte[i], HEX);
      Serial.print(" ");
    }
    Serial.println();
  }
}
