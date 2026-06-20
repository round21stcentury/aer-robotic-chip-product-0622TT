#!/usr/bin/env bash
# CAN 디버깅 워크벤치 — tmux 5분할 자동 구성
# 사용: ./can_workbench.sh    (장치명 다르면: ZYBO_TTY=/dev/ttyUSB1 DUE_TTY=/dev/ttyACM0 ./can_workbench.sh)
# 구성: ①candump ②버스모니터 ③cansend(입력만) ④Zybo시리얼(입력만) ⑤Due시리얼(입력만)
set -e

SESSION=can
ZYBO_TTY=${ZYBO_TTY:-/dev/ttyUSB1}
DUE_TTY=${DUE_TTY:-/dev/ttyACM0}

command -v tmux >/dev/null || { echo "tmux가 없습니다: sudo apt install tmux"; exit 1; }

tmux kill-session -t "$SESSION" 2>/dev/null || true
tmux new-session -d -s "$SESSION" -n bus

# ① candump (즉시 실행)
tmux send-keys -t "$SESSION" "candump -ta -c can0" C-m

# ② 버스 모니터링 (즉시 실행)
tmux split-window -t "$SESSION"
tmux send-keys -t "$SESSION" "watch -n1 \"ip -details -statistics link show can0 | grep -E 'can state|bitrate|RX:|TX:' -A1\"" C-m

# ③ cansend — 명령 입력만 (Enter치면 송신)
tmux split-window -t "$SESSION"
tmux send-keys -t "$SESSION" "cansend can0 456#DEADBEEF"

# ④ 시리얼1 Zybo — 입력만 (보드 연결 후 Enter)
tmux split-window -t "$SESSION"
tmux send-keys -t "$SESSION" "picocom -b 115200 $ZYBO_TTY"

# ⑤ 시리얼2 Due / 기타 — 입력만
tmux split-window -t "$SESSION"
tmux send-keys -t "$SESSION" "picocom -b 115200 $DUE_TTY"

tmux select-layout -t "$SESSION" tiled
tmux attach -t "$SESSION"
