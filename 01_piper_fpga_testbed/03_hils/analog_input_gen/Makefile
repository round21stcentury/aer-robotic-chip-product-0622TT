# ──────────────────────────────────────────────────────────────
# analog_input_gen — Arduino Due DAC → Zybo XADC 입력 생성기
#   arduino-cli 기반 빌드/업로드/시리얼.  사용법: make (가이드)
#   ※ 프로젝트 컨벤션 단축어 중 이 폴더에 해당되는 것만: program / serial.
#     (can-mon/docker-fix/gz-kill 은 HILS 전용이라 여기선 무의미 → 제외)
# ──────────────────────────────────────────────────────────────
CLI    ?= $(HOME)/.local/bin/arduino-cli
# Programming 포트 FQBN (펌웨어가 Serial=Programming 포트 사용)
FQBN   ?= arduino:sam:arduino_due_x_dbg
BAUD   ?= 115200
SKETCH  = .
# 포트 자동탐지: 가장 최근 ttyACM (Due Programming 포트). 없으면 비어있음.
PORT   ?= $(shell ls -t /dev/ttyACM* 2>/dev/null | head -1)
# 시리얼 권한: dialout 그룹이 현재 세션에 안 잡혀 있으면(=그룹추가 후 재로그인 전)
#   sg 로 감싸 실행한다. 재로그인하면 INGRP 가 채워져 직접 실행됨.
INGRP  := $(filter dialout,$(shell id -nG))

.PHONY: guide help install perms compile program upload serial monitor boards clean

# ── 기본: 가이드 ──
guide:
	@echo ""
	@echo "═════════ analog_input_gen (Due DAC → Zybo XADC) ═════════"
	@echo "  make install   arduino-cli + Due 코어(arduino:sam) 설치 (1회)"
	@echo "  make perms     현재 유저를 dialout 그룹에 추가 (sudo, 재로그인 필요)"
	@echo "  make compile   빌드만"
	@echo "  make program   빌드 후 보드에 업로드   (= upload)"
	@echo "  make serial    시리얼 모니터 $(BAUD)   (= monitor)"
	@echo "  make boards    연결된 보드/포트 목록"
	@echo "  make clean     빌드 산출물 정리"
	@echo ""
	@echo "  FQBN=$(FQBN)"
	@echo "  PORT=$(PORT)   (override: make program PORT=/dev/ttyACM0)"
	@echo ""
	@echo "  ※ Native USB 포트면: make program FQBN=arduino:sam:arduino_due_x"
	@echo "     (단 펌웨어는 Serial=Programming 포트 기준 → Programming 권장)"
	@echo ""

help: guide

# ── 설치 (1회) ──
install:
	@command -v $(CLI) >/dev/null 2>&1 || { \
	  echo "▶ arduino-cli 설치..."; mkdir -p $(HOME)/.local/bin; \
	  curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh \
	    | BINDIR=$(HOME)/.local/bin sh; }
	$(CLI) config init --overwrite
	$(CLI) core update-index
	$(CLI) core install arduino:sam
	@echo "✅ 설치 완료. (시리얼 권한은 'make perms' 후 재로그인)"

perms:
	sudo usermod -aG dialout $(USER)
	@echo "✅ dialout 추가됨 — ★로그아웃→로그인(또는 재부팅) 후 적용★"

# ── 빌드 / 업로드 / 시리얼 ──
compile:
	$(CLI) compile -b $(FQBN) $(SKETCH)

program upload: compile
	@test -n "$(PORT)" || { echo "✗ 포트 없음. 보드 꽂고 'make boards' 확인 → PORT=/dev/ttyACMx 지정"; exit 1; }
ifeq ($(INGRP),)
	sg dialout -c "$(CLI) upload -b $(FQBN) -p $(PORT) $(SKETCH)"
else
	$(CLI) upload -b $(FQBN) -p $(PORT) $(SKETCH)
endif
	@echo "✅ 업로드: $(PORT)"

serial monitor:
	@test -n "$(PORT)" || { echo "✗ 포트 없음. PORT=/dev/ttyACMx 지정"; exit 1; }
	@echo "▶ $(PORT) @ $(BAUD)  (종료: Ctrl-C).  레벨 0~64 입력 / +,- / s / ?"
ifeq ($(INGRP),)
	sg dialout -c "$(CLI) monitor -p $(PORT) -c baudrate=$(BAUD)"
else
	$(CLI) monitor -p $(PORT) -c baudrate=$(BAUD)
endif

boards:
	$(CLI) board list

clean:
	rm -rf build
	@echo "✅ 정리"
