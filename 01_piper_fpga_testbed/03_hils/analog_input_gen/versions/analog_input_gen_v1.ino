/* ============================================================================
 *  analog_input_gen  ―  Arduino Due 시리얼→DAC 아날로그 입력 생성기
 *  v1  (2026-06-16)
 * ----------------------------------------------------------------------------
 *  목적
 *    시리얼로 "레벨(0~64)"을 받아 Due 내장 DAC0 로 아날로그 전압을 출력.
 *    이 출력을 Zybo Z7-20 의 XADC(Pmod JA, aux analog) 입력으로 넣어
 *    칩 반사코어의 "아날로그 트리거"를 실제 전압으로 구동한다.
 *
 *  레벨 정의
 *    레벨 0 ~ 64 (총 65단계). 1스텝 = XADC_MAX / 64.
 *    XADC_MAX = 1.000 V → 1스텝 = 15.625 mV.
 *      level → 목표전압(mV) = level * XADC_MAX_MV / 64
 *      level 0  = 0 mV (요청),  level 64 = XADC_MAX_MV
 *
 *  ★안전(이 펌웨어의 핵심 요구)★
 *    Zybo Z7 XADC aux 입력 최대 = 1.0 V (unipolar, 보드에 분압 없음 / RC 안티앨리어싱만).
 *    [출처: Digilent Zybo Z7 Reference Manual — XADC: "limited to 1V"]
 *    → DAC 출력이 XADC_MAX_MV 를 절대 넘지 않도록 3중 클램프:
 *        (1) 레벨 0..64 클램프
 *        (2) 목표전압 0..XADC_MAX_MV 클램프
 *        (3) DAC 카운트 0..DAC_COUNT_SAFE_MAX 클램프  (카운트 단에서 최종 차단)
 *
 *  ⚠️ Due DAC 한계 (반드시 인지)
 *    Due 내장 DAC 는 rail-to-rail 이 아니다. 실제 출력은 약 0.55V~2.75V
 *    (≈ 1/6 ~ 5/6 of 3.3V). 즉 0V 와 0.55V 미만은 물리적으로 못 낸다.
 *    → 상한(≤1.0V) 보호는 완벽하지만, 0~64 중 낮은 절반(약 level<36)은
 *      모두 바닥(~0.55V)으로 뭉개진다. 펌웨어는 "요청 vs 추정 실제출력"을
 *      시리얼로 같이 찍어주고, 도달 불가 레벨은 경고한다.
 *    0V 부터의 풀스윙이 필요하면 외부 옵앰프 버퍼(레일투레일, 0V 기준) 권장.
 *
 *  ★캘리브레이션(권장, 안전 직결)★
 *    개체마다 DAC 출력 전압-카운트 관계가 조금 다르다. 멀티미터로 측정해
 *    아래 DAC_OUT_MIN_MV / DAC_OUT_MAX_MV 를 실측값으로 바꾸면
 *    1.0V 상한과 레벨↔전압 매핑이 정확해진다. (절차: 파일 하단 주석)
 *
 *  배선
 *    Due DAC0  ──→  Zybo XADC Pmod JA 의 아날로그 채널 P 핀 (Vaux_P)
 *    Due GND   ──→  Zybo GND        (★공통 그라운드 필수★)
 *    (단극/싱글엔드) 해당 채널 Vaux_N 은 Zybo 쪽에서 GND 로.
 *    ※ JA 핀 ↔ Vaux 채널번호 매핑은 Zybo Z7 Reference Manual XADC 절 참조.
 *
 *  시리얼 (115200 8N1)
 *    숫자 0~64 + Enter   레벨 설정
 *    +  /  -             레벨 ±1
 *    s                   현재 상태 출력
 *    ? 또는 h            도움말
 * ============================================================================
 */

// ─────────────────────────── 설정 상수 ───────────────────────────
const int      DAC_PIN          = DAC0;     // 사용할 DAC 핀 (DAC0 / DAC1)
const uint32_t SERIAL_BAUD      = 115200;

const int      LEVEL_MAX        = 64;       // 레벨 0..64
const int      XADC_MAX_MV      = 1000;     // ★XADC 입력 상한(mV) = 1.0V★  (절대 넘지 않음)

const int      DAC_RES_BITS     = 12;       // Due DAC 분해능 (12bit → 0..4095)
const int      DAC_COUNT_MAX    = (1 << DAC_RES_BITS) - 1;   // 4095

// Due DAC 전달함수(카운트→실제 출력전압) — ★개체마다 실측 권장★
//   count 0    → DAC_OUT_MIN_MV
//   count 4095 → DAC_OUT_MAX_MV
const int      DAC_OUT_MIN_MV   = 550;      // 실측 후 교체
const int      DAC_OUT_MAX_MV   = 2750;     // 실측 후 교체

// ─────────────────────────── 내부 상태 ───────────────────────────
int  g_level = 0;                 // 현재 레벨
char g_buf[16];                   // 시리얼 입력 라인 버퍼
int  g_len = 0;

// ───────────────────────── 변환 헬퍼 ─────────────────────────────
// 목표전압(mV) → DAC 카운트 (Due 바닥 클램프 포함)
int mvToCount(int mv) {
  if (mv <= DAC_OUT_MIN_MV) return 0;                 // 바닥 아래는 카운트 0 (못 내려감)
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

// ★안전 상한 카운트★ : 절대 이 값을 넘겨 쓰지 않는다 (= XADC_MAX_MV 에 해당, setup()에서 계산)
int g_safeMaxCount = 0;

// ───────────────────────── 레벨 적용 ─────────────────────────────
void applyLevel(int level) {
  // (1) 레벨 클램프
  if (level < 0)         level = 0;
  if (level > LEVEL_MAX) level = LEVEL_MAX;
  g_level = level;

  // (2) 목표전압 클램프
  long targetMv = (long)level * XADC_MAX_MV / LEVEL_MAX;
  if (targetMv > XADC_MAX_MV) targetMv = XADC_MAX_MV;   // 이론상 불필요하지만 방어
  if (targetMv < 0)           targetMv = 0;

  // (3) 카운트 클램프 — 최종 안전 차단
  int count = mvToCount((int)targetMv);
  if (count > g_safeMaxCount) count = g_safeMaxCount;   // ★XADC 상한 초과 절대 금지★

  analogWrite(DAC_PIN, count);

  int estMv = countToMv(count);
  bool unreachable = (targetMv > 0 && targetMv < DAC_OUT_MIN_MV);

  Serial.print("[set] level=");  Serial.print(level);
  Serial.print("/");             Serial.print(LEVEL_MAX);
  Serial.print("  req=");        Serial.print((int)targetMv); Serial.print("mV");
  Serial.print("  dac=");        Serial.print(count);
  Serial.print("  est_out=");    Serial.print(estMv);         Serial.print("mV");
  if (unreachable) Serial.print("  ⚠️도달불가(Due바닥~550mV, 실제출력바닥)");
  Serial.println();
}

// ───────────────────────── 상태 / 도움말 ─────────────────────────
void printStatus() {
  Serial.print("[status] level=");  Serial.print(g_level);
  Serial.print("/");                Serial.print(LEVEL_MAX);
  Serial.print("  step=");          Serial.print((float)XADC_MAX_MV / LEVEL_MAX, 3); Serial.print("mV");
  Serial.print("  XADC_MAX=");      Serial.print(XADC_MAX_MV);  Serial.print("mV");
  Serial.print("  safeMaxCount=");  Serial.println(g_safeMaxCount);
}

void printHelp() {
  Serial.println(F("──── analog_input_gen (Due DAC → Zybo XADC) ────"));
  Serial.println(F("  0..64 + Enter : 레벨 설정 (1스텝=XADC_MAX/64=15.625mV)"));
  Serial.println(F("  + / -         : 레벨 ±1"));
  Serial.println(F("  s             : 상태"));
  Serial.println(F("  ? / h         : 도움말"));
  Serial.println(F("  ※ 상한 1.0V 절대 초과 안 함. Due DAC 바닥~0.55V는 물리한계."));
}

// ───────────────────────── 라인 처리 ─────────────────────────────
void processLine(char *s) {
  // 앞쪽 공백 스킵
  while (*s == ' ' || *s == '\t') s++;
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

// ───────────────────────── setup / loop ──────────────────────────
void setup() {
  Serial.begin(SERIAL_BAUD);
  analogWriteResolution(DAC_RES_BITS);

  // 안전 상한 카운트 계산 (XADC_MAX_MV 에 해당하는 카운트)
  g_safeMaxCount = mvToCount(XADC_MAX_MV);
  if (g_safeMaxCount > DAC_COUNT_MAX) g_safeMaxCount = DAC_COUNT_MAX;

  // 부팅 시 가장 낮은 출력(레벨 0)으로 안전하게 시작
  applyLevel(0);

  Serial.println();
  printHelp();
  printStatus();
}

void loop() {
  while (Serial.available() > 0) {
    char c = (char)Serial.read();
    if (c == '\n' || c == '\r') {
      if (g_len > 0) {
        g_buf[g_len] = '\0';
        processLine(g_buf);
        g_len = 0;
      }
    } else if (g_len < (int)sizeof(g_buf) - 1) {
      g_buf[g_len++] = c;
    } else {
      // 버퍼 넘침 → 리셋(라인 끝까지 버림)
      g_len = 0;
      Serial.println(F("[err] 입력 너무 김 — 무시"));
    }
  }
}

/* ============================================================================
 *  캘리브레이션 절차 (1.0V 상한 정확도 = 안전 직결)
 *  ----------------------------------------------------------------------------
 *  1) DAC0 ↔ GND 사이에 멀티미터(DC V) 연결.
 *  2) 코드 임시로 analogWrite(DAC_PIN, 0)    → 전압 측정 = DAC_OUT_MIN_MV.
 *  3) 코드 임시로 analogWrite(DAC_PIN, 4095) → 전압 측정 = DAC_OUT_MAX_MV.
 *  4) 위 두 상수에 실측 mV 기입 후 재업로드.
 *  5) 검증: 시리얼로 64 입력 → DAC0 전압이 1.000V 근처인지 멀티미터로 확인.
 *           (1.0V 를 넘으면 절대 안 됨. 넘으면 DAC_OUT_MAX_MV 를 낮춰 재조정)
 *  ※ 실측 전이라도 g_safeMaxCount 가 기본값(550/2750)에서 1.0V 로 막아주지만,
 *    개체 편차로 +수십 mV 오차 가능 → XADC 여유(1V) 고려해도 실측 권장.
 *
 *  업로드 (arduino-cli 예)
 *    arduino-cli compile -b arduino:sam:arduino_due_x_dbg .
 *    arduino-cli upload  -b arduino:sam:arduino_due_x_dbg -p /dev/ttyACM0 .
 *    ※ 업로드는 Native USB(Programming 포트 아님) 사용 시 보드/포트 확인.
 * ========================================================================== */
