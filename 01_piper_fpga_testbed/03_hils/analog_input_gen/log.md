# analog_input_gen — 작업 로그

> Due DAC → Zybo Z7-20 XADC 아날로그 트리거 입력 생성기.
> 코드 수정은 in-place 금지 규칙: 다음 변경분은 `versions/analog_input_gen_v2.ino` 사본 + 여기 기록.
> (Arduino 컴파일은 폴더명과 같은 `analog_input_gen.ino` 가 메인. 히스토리는 이 log.md 가 진실.)

## v3 — 2026-06-16  (백업: versions/analog_input_gen_v2.ino)
- **입력 의미 변경**: '레벨번호'가 아니라 '전압값(0.55~1.00V)'을 시리얼로 입력.
  → mvToLevel() 로 가장 가까운 레벨(0~64)로 양자화해 적용.
  - 예: `0.78` → req=780mV → level 33 → out≈782mV. 범위밖은 0.55/1.00 클램프.
- 프롬프트 `전압 입력(0.55~1.00V)> `. `+`/`-` 는 레벨 ±1 미세조정으로 유지.
- 레벨 정의(0=0.55V, 64=1.0V, 0~64)는 그대로 — 0.55V도 유효출력이라 0 유지.
  (엄격히 1~64 만 원하면 한 줄 클램프로 변경 가능. 현재는 0.56V↑ 쓰면 사실상 1~64.)
- setLevel/reportSet 로 분리(상태출력이 DAC 재기록 안 하도록 g_count 도입).
- 입력 하드닝(이스케이프/제어문자 무시)·1.0V 3중 클램프 안전로직 v2 그대로 유지.
- ✅ 컴파일: 39012B(7%, atof/float 출력 포함). 업로드는 Due Programming 포트 연결 후 `make program`.

## v2 — 2026-06-16  (백업: versions/analog_input_gen_v1.ino)
- **레벨 매핑 변경**: level 0 = 0.55V(DAC 바닥), level 64 = 1.0V(XADC 상한).
  0.55~1.0V 를 64단계로 → 1스텝 ≈ 7.031mV. 전 구간 물리적 도달 가능.
- **"도달불가" 경고 제거** (이제 모든 레벨이 실제로 나옴). 출력은 `[set] level=L/64 out=mV dac=N`.
- **텍스트 인터페이스**: `레벨 입력(0~64)> ` 프롬프트(부팅/명령 후 표시).
- **★입력 하드닝(오입력 재발 방지)★**: handleByte() 상태머신으로
  - ANSI 이스케이프 시퀀스(방향키 `ESC [ A` 등) 통째로 삼켜 무시
  - 출력가능 ASCII(0x20~0x7E)만 수집, 그 외 제어문자 무시
  - Backspace(0x08/0x7F) 지원
  → 시리얼 모니터에서 방향키 눌러도 레벨 안 바뀌고 에러도 안 뜸(무반응).
  ※ 참고: 방향키는 USB 포트 분리/리눅스 프리즈의 원인이 아님(그건 재부팅/물리연결).
    펌웨어 파서 오염만이 실제 영향이었고 그걸 차단함.
- ✅ 컴파일 검증: 29664B(5%). 보드 재업로드는 Due Programming 포트 연결 후 `make program`.

## v1 — 2026-06-16
- 최초 작성. 시리얼(115200) 로 레벨 0~64 입력 → DAC0 출력.
- 1스텝 = XADC_MAX/64 = 15.625 mV (XADC_MAX = 1.0V).

### 확정한 사실
- **Zybo Z7 XADC aux 입력 최대 = 1.0 V** (unipolar, 보드 분압 없음 / RC 안티앨리어싱만).
  출처: Digilent Zybo Z7 Reference Manual — XADC 절 "limited to 1V".
  → 펌웨어 상수 `XADC_MAX_MV = 1000`.

### 안전 설계 (사용자 핵심 요구 = 상한 절대 초과 금지)
- 3중 클램프: 레벨(0..64) → 목표전압(0..1000mV) → DAC카운트(0..g_safeMaxCount).
- `g_safeMaxCount = mvToCount(1000)` 을 setup()에서 계산, 이 카운트 초과로는 절대 안 씀.
- 부팅 시 레벨 0 으로 시작.

### ⚠️ 알려진 한계 (Due 하드웨어)
- Due 내장 DAC 는 rail-to-rail 아님 → 실제 출력 ≈ 0.55V~2.75V.
  - 상한(≤1.0V) 보호는 정확. 단, 0~64 중 낮은 절반(약 level<36, 즉 <0.55V)은
    물리적으로 못 내고 ~0.55V 로 바닥남. 펌웨어가 "요청 vs 추정실제" 출력 + 도달불가 경고.
  - 0V 풀스윙 필요 시 외부 레일투레일 옵앰프 버퍼 권장.
- 개체 편차: DAC 전달함수 실측 권장 (`DAC_OUT_MIN_MV`/`DAC_OUT_MAX_MV`).
  절차는 .ino 하단 주석. 1.0V 상한 정확도가 안전과 직결되므로 실측 후 사용 권장.

### 툴체인 (2026-06-16)
- arduino-cli **1.5.1** 설치(`~/.local/bin`), `arduino:sam@1.6.12` 코어 설치(gcc-arm + bossac).
- Makefile 추가: `install/perms/compile/program(=upload)/serial(=monitor)/boards/clean`.
- ✅ 컴파일 검증: `arduino:sam:arduino_due_x_dbg`, 플래시 29608B(5%). 업로드는 보드 연결 후.
- 시리얼 권한: 현재 유저 `dialout` 미포함 → `make perms` 후 재로그인 필요.

### TODO / 다음
- [ ] `make perms` → 재로그인 → 보드 꽂고 `make program` 업로드.
- [ ] 실측 캘리브레이션 후 DAC_OUT_MIN/MAX 상수 갱신.
- [ ] Zybo XADC 데모(Digilent)로 들어온 전압이 레벨과 선형으로 읽히는지 교차검증.
- [ ] (선택) 외부 옵앰프 버퍼로 0~1V 풀스윙 확보 여부 결정.
