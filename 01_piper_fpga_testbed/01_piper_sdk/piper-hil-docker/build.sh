#!/usr/bin/env bash
# 이미지 빌드: piper-hil:humble
set -euo pipefail
cd "$(dirname "$0")"
docker build -t piper-hil:humble .
echo "✅ 이미지 빌드 완료: piper-hil:humble"
echo "   다음: ./run.sh"
