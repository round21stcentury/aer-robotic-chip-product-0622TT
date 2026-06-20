# ──────────────────────────────────────────────────────────────
# 03_hils — HILS 통합 (Zybo FPGA ↔ pc_bridge ↔ 로봇/시뮬)
#   딱 두 가지: prep(셋업) + run(실행).  MODE(어디로) × APP(무엇을) 조합.
#   사용법:  make   (가이드)
# ──────────────────────────────────────────────────────────────
# ⚠️★설계 무관 경계 — 함부로 고치지 말 것★
#   • 이 폴더는 "통신 연결 + 모드별 시뮬레이션"만 담당. 반사 설계와 무관.
#   • 반사 설계(02_reflex_system_dev/<01|A|B|C>)를 바꿔도 여기는 안 건드린다.
#   • 보드에 비트스트림/앱 올리는 program 은 ★각 반사 설계 폴더★에서 한다
#       (예: cd 02_reflex_system_dev/02_rs_A_can_in_pl && make program).
#   • 여기 FPGA=05_zybo_can_eth 는 설계무관 통신 베이스(반사 디자인 아님). FPGA를 블랙박스로 본다.
#   ※ 2026-06-15: 반사 작업 중 이 Makefile을 사용자 동의 없이 수정한 실수 있었음 → 반복 금지.
# ──────────────────────────────────────────────────────────────
PCB      = piper_pc_handoff/pc_bridge
FPGA     = ../02_zybo_skeleton/05_zybo_can_eth
FPGA_IP ?= 192.168.1.10

DOCKER_IMG ?= piper-hil:humble
WS_DIR      = $(abspath ../01_piper_sdk/piper-hil-docker/ros2_ws)
PCB_ABS     = $(abspath $(PCB))

# ── 핵심 옵션 ──
MODE    ?= sim          # sim | hil | robot          (어디로)
APP     ?= slider       # slider | motions/wave_v2.py    (무엇을)
BACKEND ?= gazebo       # gazebo | kinematic
ZYBO_TTY ?=             # 보드 UART (비우면 자동탐지: 마지막 ttyUSB)
LIBGL   ?=              # LIBGL=1 → Gazebo 소프트웨어 렌더링(GPU 문제 회피)
DBG     ?=              # DBG=1   → 전체 출력 /tmp/hils.log 로 tee (디버그)

.PHONY: guide help sdk-build-ws _sdk-build-ws prep fpga-prep run _run down \
        serial can-mon program docker-fix gz-kill _gz-kill

# ── 기본: 가이드 ──
guide:
	@echo ""
	@echo "═══════════════ HILS — prep + run ═══════════════"
	@echo ""
	@echo " 딱 두 단계:"
	@echo "   1) make prep MODE=<어디로>            # 인터페이스 셋업 (sudo)"
	@echo "   2) make run  MODE=<어디로> APP=<무엇을>"
	@echo ""
	@echo " MODE = 어디로 보낼지"
	@echo "    sim    FPGA 없이 mock + 가상로봇        하드웨어 0 (개발/연습)"
	@echo "    hil    실제 FPGA + USB-CAN + Gazebo     보드 program + USB-CAN 필요"
	@echo "    robot  실제 FPGA + ★진짜 로봇★          보드 program + 로봇 필요"
	@echo ""
	@echo " APP = 무엇을 실행할지"
	@echo "    slider             슬라이더 GUI 로 직접 조종"
	@echo "    motions/wave_v2.py    동작 스크립트 (motions/ 폴더의 .py, 경로 그대로)"
	@echo "       ★ back_and_forth.py 좌우왕복 | mobius.py figure-8+트위스트 | wave_v4.py 손인사"
	@echo "       ★ reflex_pursue.py 반사인지 추적(/reflex_active 구독·움츠리면 멈춰 대기·그리퍼. ikpy 자동설치)"
	@echo ""
	@echo " ── 예시 ──"
	@echo "    make run MODE=sim   APP=slider             # 시뮬 슬라이더"
	@echo "    make run MODE=sim   APP=motions/wave_v2.py    # 시뮬 손인사"
	@echo "    make run MODE=hil   APP=slider             # 실FPGA+Gazebo 슬라이더"
	@echo "    make run MODE=hil   APP=motions/wave_v2.py    # 실FPGA+Gazebo 손인사"
	@echo "    make run MODE=robot APP=motions/wave_v2.py    # ★진짜 로봇★ 손인사"
	@echo "    make run MODE=hil   APP=motions/back_and_forth.py        # 좌우 왕복"
	@echo "    make run MODE=hil   APP='motions/mobius.py --period 5'   # 뫼비우스 (인자는 따옴표로)"
	@echo "    make run MODE=hil   APP=motions/reflex_pursue.py        # ★반사인지 추적 (↓ 반사토픽 필요)"
	@echo ""
	@echo " ── 반사 토픽 (/reflex_active) ── reflex_pursue 같은 '반사인지' 모션일 때만 ──"
	@echo "    · make run 하면 reflex_status_node 는 자동 실행됨 (localhost:5001 → /reflex_active)"
	@echo "    · ★호스트 다른 터미널★ 에서 시리얼 리더도 켜야 반사가 토픽으로 흐름:"
	@echo "        cd ../../02_1_reflex_system_TT/06_로봇실증용 && make latency-gui"
	@echo "      (FPGA 시리얼 [RFX] 읽어 지연GUI 표시 + localhost:5001 로 노드에 전달)"
	@echo ""
	@echo " (최초 1회) make sdk-build-ws     # 패치된 piper_ros 빌드 (Docker)"
	@echo " ⚠️ robot: 속도 낮게, E-STOP 준비, 개루프(피드백X)"
	@echo " 새 동작: motions/_template.py 복사 → POSES 채우고 → APP=motions/내이름.py"
	@echo ""
	@echo " ── 단축어 ──  serial / can-mon / program / docker-fix / gz-kill / down"
	@echo " 전체 명령: make help"
	@echo "═════════════════════════════════════════════════"

help:
	@echo "make sdk-build-ws             (Docker,최초1회) 패치된 piper_ros colcon build"
	@echo "make prep MODE=sim|hil|robot  인터페이스 셋업 (sudo)"
	@echo "make run  MODE=.. APP=slider|motions/x.py    실행 (Docker)"
	@echo "make down                     vcan 인터페이스 정리"
	@echo "── 단축어 ──"
	@echo "make serial                   보드 시리얼 모니터 (UART 자동탐지)"
	@echo "make can-mon                  CAN 상태 지속 모니터"
	@echo "make program                  FPGA 프로그래밍 (보드에 앱 올리기)"
	@echo "make docker-fix               도커 권한 적용 셸로 진입 (끝나면 exit)"
	@echo "make gz-kill                  Gazebo/컨테이너 정리 + DDS shm 청소"
	@echo ""
	@echo "변수: BACKEND=gazebo|kinematic, FPGA_IP=$(FPGA_IP), ZYBO_TTY=<UART>, LIBGL=1, DBG=1"

# ── (최초 1회) 패치된 워크스페이스 빌드 ──
sdk-build-ws:
	@if docker ps >/dev/null 2>&1; then exec $(MAKE) --no-print-directory _sdk-build-ws; \
	 else echo "[docker 그룹으로 자동 재실행]"; exec sg docker -c "$(MAKE) --no-print-directory _sdk-build-ws"; fi
_sdk-build-ws:
	docker run -it --rm -v $(WS_DIR):/root/ros2_ws:rw $(DOCKER_IMG) \
	  bash -lc 'source /opt/ros/humble/setup.bash && cd /root/ros2_ws && \
	    rm -rf build install log; \
	    apt-get update && rosdep install --from-paths src --ignore-src -r -y --rosdistro humble || true; \
	    find src -path "*/scripts/*.py" -exec chmod +x {} \; ; \
	    colcon build --symlink-install'

# ── HOST 인터페이스 셋업 (MODE 별, sudo) ──
fpga-prep:
	$(MAKE) -C $(FPGA) pc-ip
	$(MAKE) -C $(FPGA) arp-static

prep:
ifeq ($(MODE),sim)
	sudo bash $(PCB)/setup/setup_can.sh sim          # vcan0 + vcan1
endif
ifeq ($(MODE),hil)
	$(MAKE) fpga-prep
	sudo bash $(PCB)/setup/setup_can.sh hw           # vcan0 + 실제 can0(1M)
endif
ifeq ($(MODE),robot)
	$(MAKE) fpga-prep
	-sudo modprobe vcan
	-sudo ip link add dev vcan0 type vcan 2>/dev/null
	sudo ip link set up vcan0
	@echo "robot 준비 완료 (vcan0). USB-CAN 불필요. 보드 program + 로봇 켜둘 것."
endif

# ── 통합 실행 (Docker): MODE 파이프라인 + APP 프론트엔드 ──
#  docker 권한 없으면 sg docker 로 자동 재실행 (터미널마다 docker-fix 안 해도 됨)
run:
	@if docker ps >/dev/null 2>&1; then \
	   exec $(MAKE) --no-print-directory _run MODE='$(MODE)' APP='$(APP)' BACKEND='$(BACKEND)' FPGA_IP='$(FPGA_IP)' LIBGL='$(LIBGL)' DBG='$(DBG)'; \
	 else echo "[docker 권한 없음 → docker 그룹으로 자동 재실행]"; \
	   exec sg docker -c "$(MAKE) --no-print-directory _run MODE='$(MODE)' APP='$(APP)' BACKEND='$(BACKEND)' FPGA_IP='$(FPGA_IP)' LIBGL='$(LIBGL)' DBG='$(DBG)'"; fi

_run:
	@ids=$$(docker ps -q --filter ancestor=$(DOCKER_IMG) 2>/dev/null); \
	  [ -n "$$ids" ] && { echo "기존 piper-hil 컨테이너 정리(중복 방지): $$ids"; docker rm -f $$ids >/dev/null; } || true
	-xhost +local:root
	docker run -i $(if $(filter 1,$(DBG)),,-t) --rm --network host --ipc host \
	  --env DISPLAY=$$DISPLAY --env QT_X11_NO_MITSHM=1 \
	  $(if $(filter 1,$(LIBGL)),--env LIBGL_ALWAYS_SOFTWARE=1,) \
	  --env MODE=$(MODE) --env APP=$(APP) --env BACKEND=$(BACKEND) --env FPGA_IP=$(FPGA_IP) \
	  -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
	  $$([ -e /dev/dri ] && echo --device=/dev/dri) \
	  -v $(WS_DIR):/root/ros2_ws:rw \
	  -v $(PCB_ABS):/pc_bridge:rw \
	  $(DOCKER_IMG) bash /pc_bridge/tests/hils_run.sh $(if $(filter 1,$(DBG)),2>&1 | tee /tmp/hils.log,)

down:
	-sudo bash $(PCB)/setup/setup_can.sh down

# ══ 단축어 ══
# 보드 시리얼 모니터 (UART). ZYBO_TTY 비우면 마지막 ttyUSB 자동선택.
serial:
	@TTY=$${ZYBO_TTY:-$$(ls /dev/ttyUSB* 2>/dev/null | tail -1)}; \
	  [ -n "$$TTY" ] && { echo "serial → $$TTY (Ctrl-A Ctrl-X 종료)"; sudo picocom -b 115200 $$TTY; } \
	  || echo "ttyUSB 없음 — 보드 USB 연결/드라이버 확인"

# CAN(can0) 상태 지속 갱신 모니터 (state/bitrate/RX/TX/에러)
can-mon:
	$(MAKE) -C $(FPGA) monitor

# FPGA 프로그래밍 (보드에 앱 elf 올리기, JTAG)
program:
	$(MAKE) -C $(FPGA) program

# 도커 권한 오류 해결 — docker 그룹 적용된 셸로 바로 진입 (여기서 make run 등 실행, exit로 종료)
docker-fix:
	@if docker ps >/dev/null 2>&1; then \
	   echo "✅ docker 이미 정상 — 그대로 make run 등 실행하세요"; \
	 else \
	   id -nG | tr ' ' '\n' | grep -qx docker || { echo "docker 그룹 등록(sudo, 1회)..."; sudo usermod -aG docker $$USER; }; \
	   echo "→ docker 그룹 셸로 진입합니다. 여기서 'make run MODE=..' 등 실행, 끝나면 exit."; \
	   exec newgrp docker; \
	 fi

# 백그라운드 Gazebo/컨테이너 정리 + 이전 run 의 DDS 공유메모리 찌꺼기 청소
#  (--ipc host 라 /dev/shm/fastrtps_* 가 root소유로 남아 다음 gazebo 컨트롤러를 죽임 → 컨테이너 root 로 청소)
gz-kill:
	@if docker ps >/dev/null 2>&1; then exec $(MAKE) --no-print-directory _gz-kill; \
	 else echo "[docker 그룹으로 자동 재실행]"; exec sg docker -c "$(MAKE) --no-print-directory _gz-kill"; fi
_gz-kill:
	@ids=$$(docker ps -aq --filter ancestor=$(DOCKER_IMG)); \
	  if [ -z "$$ids" ]; then echo "정리할 piper-hil 컨테이너 없음"; \
	  else echo "제거할 컨테이너: $$ids"; docker rm -f $$ids; echo "✅ Gazebo 포트(11345) 해제됨"; fi
	@docker run --rm --ipc host $(DOCKER_IMG) bash -lc 'rm -f /dev/shm/fastrtps_* /dev/shm/sem.fastrtps_* /dev/shm/fast_datasharing_* 2>/dev/null; true' >/dev/null 2>&1 || true
	@echo "✅ DDS 공유메모리(/dev/shm/fastrtps_*) 청소됨 — 다음 run 깨끗이 시작"
