/* ============================================================================
 *  analog_input_gen  ―  Arduino Due 시리얼→DAC 아날로그 입력 생성기
 *  v2  (2026-06-16)
 * ----------------------------------------------------------------------------
 *  목적
 *    시리얼로 "레벨(0~64)"을 받아 Due 내장 DAC0 로 아날로그 전압을 출력.
 *    이 출력을 Zybo Z7-20 의 XADC(Pmod JA, aux analog) 입력으로 넣어
 *    칩 반사코어의 "아날로그 트리거"를 실제 전압으로 구동한다.
 *
 *  레벨 정의 (v2: Due DAC 가 실제로 낼 수 있는 0.55~1.0V 구간만 사용)
 *    레벨 0 ~ 64 (총 65단계).
 *      level 0  = 0.55 V (Due DAC 바닥)          ← 기준점
 *      level 64 = 1.00 V (XADC 입력 상한)
 *      1스텝 = (1.00-0.55)/64 = 0.45/64 ≈ 7.031 mV
 *      level → 목표전압(mV) = V_LO_MV + level*(V_HI_MV - V_LO_MV)/64
 *    ※ 전 구간이 물리적으로 도달 가능 → "도달불가" 같은 경고 없음.
 *
 *  ★안전(이 펌웨어의 핵심 요구)★
 *    Zybo Z7 XADC aux 입력 최대 = 1.0 V (unipolar, 보드 분압 없음 / RC 안티앨리어싱만).
 *    [출처: Digilent Zybo Z7 Reference Manual — XADC: "limited to 1V"]
 *    → DAC 출력이 V_HI_MV(=XADC_MAX_MV) 를 절대 넘지 않도록 3중 클램프:
 *        (1) 레벨 0..64 클램프
 *        (2) 목표전압 V_LO_MV..V_HI_MV 클램프
 *        (3) DAC 카운트 0..g_safeMaxCount 클램프  (카운트 단에서 최종 차단)
 *
 *  ★입력 하드닝 (v2) — 오입력 재발 방지★
 *    시리얼 모니터에서 방향키/기능키 등을 눌러도 안전하도록:
 *      - ANSI 이스케이프 시퀀스(ESC '[' … 최종바이트)를 통째로 삼켜 무시.
 *      - 출력 가능 ASCII(0x20~0x7E)만 라인 버퍼에 수집, 그 외 제어문자 무시.
 *      - Backspace(0x08/0x7F) 한 글자 지우기 지원.
 *    → 방향키를 눌러도 레벨이 바뀌거나 에러가 뜨지 않는다(완전 무반응).
 *
 *  ⚠️ Due DAC 특성
 *    Due 내장 DAC 는 rail-to-rail 아님(≈0.55~2.75V). 그래서 v2 는 0V 가 아니라
 *    0.55V 를 기준점으로 삼는다. 0V 부터의 풀스윙이 필요하면 외부 레일투레일
 *    옵앰프 버퍼를 쓰고 V_LO_MV 를 0 으로 바꾸면 된다.
 *
 *  ★캘리브레이션(권장, 안전 직결)★
 *    개체마다 DAC 출력 전압-카운트 관계가 다르다. 멀티미터로 측정해
 *    DAC_OUT_MIN_MV / DAC_OUT_MAX_MV 를 실측값으로 바꾸면
 *    0.55V 기준·1.0V 상한·레벨 매핑이 정확해진다. (절차: 파일 하단 주석)
 *
 *  배선
 *    Due DAC0  ──→  Zybo XADC Pmod JA 의 아날로그 채널 P 핀 (Vaux_P)
 *    Due GND   ──→  Zybo GND        (★공통 그라운드 필수★)
 *    (단극/싱글엔드) 해당 채널 Vaux_N 은 Zybo 쪽에서 GND 로.
 *    ※ JA 핀 ↔ Vaux 채널번호 매핑은 Zybo Z7 Reference Manual XADC 절 참조.
 *
 *  시리얼 (115200 8N1)  ─ 텍스트 인터페이스
 *    "레벨 입력(0~64)> " 프롬프트에:
 *      숫자 0~64 + Enter   레벨 설정
 *      +  /  -             레벨 ±1
 *      s                   현재 상태 출력
 *      ? 또는 h            도움말
 * ============================================================================
 */

// ─────────────────────────── 설정 상수 ───────────────────────────
const int      DAC_PIN          = DAC0;     // 사용할 DAC 핀 (DAC0 / DAC1)
const uint32_t SERIAL_BAUD      = 115200;

const int      LEVEL_MAX        = 64;       // 레벨 0..64
const int      XADC_MAX_MV      = 1000;     // ★XADC 입력 상한(mV) = 1.0V★ (절대 초과 금지)

const int      DAC_RES_BITS     = 12;       // Due DAC 분해능 (12bit → 0..4095)
const int      DAC_COUNT_MAX    = (1 << DAC_RES_BITS) - 1;   // 4095

// Due DAC 전달함수(카운트→실제 출력전압) — ★개체마다 실측 권장★
//   count 0    → DAC_OUT_MIN_MV
//   count 4095 → DAC_OUT_MAX_MV
const int      DAC_OUT_MIN_MV   = 550;      // 실측 후 교체
const int      DAC_OUT_MAX_MV   = 2750;     // 실측 후 교체

// 레벨 매핑 구간 (v2): level 0 = V_LO_MV, level 64 = V_HI_MV
const int      V_LO_MV          = DAC_OUT_MIN_MV;   // 0.55V (DAC 바닥)
const int      V_HI_MV          = XADC_MAX_MV;      // 1.00V (XADC 상한)

// ─────────────────────────── 내부 상태 ───────────────────────────
int  g_level = 0;                 // 현재 레벨
char g_buf[16];                   // 시리얼 입력 라인 버퍼
int  g_len = 0;
int  g_esc = 0;                   // 이스케이프 시퀀스 스킵 상태머신 (0/1/2)
int  g_safeMaxCount = 0;          // ★안전 상한 카운트★ (= V_HI_MV, setup()에서 계산)

// ───────────────────────── 변환 헬퍼 ─────────────────────────────
// 목표전압(mV) → DAC 카운트 (Due 바닥 클램프 포함)
int mvToCount(int mv) {
  if (mv <= DAC_OUT_MIN_MV) return 0;                 // 바닥 아래는 카운트 0
  long span = (long)DAC_OUT_MAX_MV - DAC_OUT_MIN_MV;  // 2200
  long c = ((long)(mv - DAC_OUT_MIN_MV) * DAC_COUNT_MAX + span / 2) / span;  // 반올림
  if (c < 0) c = 0;
  if (c > DAC_COUNT_MAX) c = DAC_COUNT_MAX;
  return (int)c;
}

// DAC 카운트 → 추정 실제 출력전압(mV)
int countToMv(int count) {
  long span = (long)DAC_OUT_MAX_MV - DAC_OUT_MIN_MV;
  return (int)(DAC_OUT_MIN_MV + ((long)count * span + DAC_COUNT_MAX / 2) / DAC_COUNT_MAX);
}

// ───────────────────────── 텍스트 UI ─────────────────────────────
void printPrompt() {
  Serial.print(F("레벨 입력(0~64)> "));
}

// ───────────────────────── 레벨 적용 ─────────────────────────────
void applyLevel(int level) {
  // (1) 레벨 클램프
  if (level < 0)         level = 0;
  if (level > LEVEL_MAX) level = LEVEL_MAX;
  g_level = level;

  // (2) 목표전압 (V_LO_MV ~ V_HI_MV 선형) + 클램프
  long targetMv = (long)V_LO_MV + (long)level * (V_HI_MV - V_LO_MV) / LEVEL_MAX;
  if (targetMv > V_HI_MV) targetMv = V_HI_MV;   // 상한 방어
  if (targetMv < V_LO_MV) targetMv = V_LO_MV;

  // (3) 카운트 클램프 — 최종 안전 차단 (1.0V 초과 절대 금지)
  int count = mvToCount((int)targetMv);
  if (count > g_safeMaxCount) count = g_safeMaxCount;

  analogWrite(DAC_PIN, count);

  int estMv = countToMv(count);
  Serial.print(F("[set] level="));  Serial.print(level);
  Serial.print(F("/"));             Serial.print(LEVEL_MAX);
  Serial.print(F("  out="));        Serial.print(estMv);  Serial.print(F("mV"));
  Serial.print(F("  dac="));        Serial.println(count);
}

// ───────────────────────── 상태 / 도움말 ─────────────────────────
void printStatus() {
  Serial.print(F("[status] level="));  Serial.print(g_level);
  Serial.print(F("/"));                Serial.print(LEVEL_MAX);
  Serial.print(F("  range="));         Serial.print(V_LO_MV); Serial.print(F("~"));
  Serial.print(V_HI_MV);               Serial.print(F("mV"));
  Serial.print(F("  step="));          Serial.print((float)(V_HI_MV - V_LO_MV) / LEVEL_MAX, 3);
  Serial.println(F("mV"));
}

void printHelp() {
  Serial.println(F("──── analog_input_gen v2 (Due DAC → Zybo XADC) ────"));
  Serial.println(F("  level 0 = 0.55V(바닥), level 64 = 1.00V(XADC상한), 1스텝≈7.03mV"));
  Serial.println(F("  0..64 + Enter : 레벨 설정"));
  Serial.println(F("  + / -         : 레벨 ±1"));
  Serial.println(F("  s             : 상태"));
  Serial.println(F("  ? / h         : 도움말"));
  Serial.println(F("  ※ 상한 1.0V 절대 초과 안 함. 방향키 등 특수키는 무시됨."));
}

// ───────────────────────── 라인 처리 ─────────────────────────────
void processLine(char *s) {
  while (*s == ' ' || *s == '\t') s++;     // 앞쪽 공백 스킵
  if (*s == '\0') return;                  // 빈 줄 무시

  if (*s == '?' || *s == 'h' || *s == 'H') { printHelp();   return; }
  if (*s == 's' || *s == 'S')              { printStatus(); return; }
  if (*s == '+')                           { applyLevel(g_level + 1); return; }
  if (*s == '-')                           { applyLevel(g_level - 1); return; }

  if (*s >= '0' && *s <= '9') {             // 숫자 → 레벨
    applyLevel(atoi(s));
    return;
  }
  Serial.print(F("[err] 알 수 없는 입력: ")); Serial.println(s);
}

// ───────────────── 한 바이트 입력 처리 (하드닝 포함) ───────────────
// ESC 이스케이프 시퀀스(방향키/기능키)와 제어문자를 안전하게 무시한다.
void handleByte(char c) {
  // ── 이스케이프 시퀀스 스킵 상태머신 ──
  if (g_esc == 1) {                         // ESC 직후
    g_esc = (c == '[' || c == 'O') ? 2 : 0; // CSI/SS3 진입, 아니면 단독 ESC → 종료
    return;
  }
  if (g_esc == 2) {                         // CSI 본문: 최종바이트(0x40~0x7E) 만나면 끝
    if (c >= 0x40 && c <= 0x7E) g_esc = 0;
    return;                                 // 본문/최종 모두 버림 (방향키 무반응)
  }
  if (c == 0x1B) { g_esc = 1; return; }     // ESC 시작

  // ── 라인 종료 ──
  if (c == '\n' || c == '\r') {
    if (g_len > 0) { g_buf[g_len] = '\0'; processLine(g_buf); g_len = 0; }
    printPrompt();
    return;
  }

  // ── Backspace / Delete ──
  if (c == 0x08 || c == 0x7F) {
    if (g_len > 0) g_len--;
    return;
  }

  // ── 출력 가능 ASCII 만 수집, 나머지 제어문자 무시 ──
  if (c >= 0x20 && c <= 0x7E) {
    if (g_len < (int)sizeof(g_buf) - 1) {
      g_buf[g_len++] = c;
    } else {
      g_len = 0;                            // 버퍼 넘침 → 라인 폐기
      Serial.println();
      Serial.println(F("[err] 입력 너무 김 — 무시"));
      printPrompt();
    }
  }
  // 그 외(제어문자 등) 전부 무시
}

// ───────────────────────── setup / loop ──────────────────────────
void setup() {
  Serial.begin(SERIAL_BAUD);
  analogWriteResolution(DAC_RES_BITS);

  // 안전 상한 카운트 계산 (V_HI_MV 에 해당하는 카운트)
  g_safeMaxCount = mvToCount(V_HI_MV);
  if (g_safeMaxCount > DAC_COUNT_MAX) g_safeMaxCount = DAC_COUNT_MAX;

  // 부팅 시 가장 낮은 출력(레벨 0 = 0.55V)으로 안전하게 시작
  applyLevel(0);

  Serial.println();
  printHelp();
  printStatus();
  printPrompt();
}

void loop() {
  while (Serial.available() > 0) {
    handleByte((char)Serial.read());
  }
}

/* ============================================================================
 *  캘리브레이션 절차 (1.0V 상한 정확도 = 안전 직결)
 *  ----------------------------------------------------------------------------
 *  1) DAC0 ↔ GND 사이에 멀티미터(DC V) 연결.
 *  2) 코드 임시로 analogWrite(DAC_PIN, 0)    → 전압 측정 = DAC_OUT_MIN_MV.
 *  3) 코드 임시로 analogWrite(DAC_PIN, 4095) → 전압 측정 = DAC_OUT_MAX_MV.
 *  4) 위 두 상수에 실측 mV 기입 후 재업로드. (V_LO_MV 는 DAC_OUT_MIN_MV 추종)
 *  5) 검증: 시리얼로 64 입력 → DAC0 전압이 1.000V 근처인지 멀티미터로 확인.
 *           (1.0V 를 넘으면 절대 안 됨. 넘으면 DAC_OUT_MAX_MV 를 낮춰 재조정)
 *
 *  업로드 (arduino-cli 예 / 또는 `make program`)
 *    arduino-cli compile -b arduino:sam:arduino_due_x_dbg .
 *    arduino-cli upload  -b arduino:sam:arduino_due_x_dbg -p /dev/ttyACM0 .
 *    ※ 펌웨어가 Serial 사용 → USB 는 Due "Programming" 포트에 연결.
 * ========================================================================== */
