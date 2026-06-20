#!/usr/bin/env python3
"""Piper CAN ID 상수 + 방향(명령/피드백) 분류.

권위 소스: piper_sdk piper_msgs/msg_v2/can_id.py (v0.6.1 / 프로토콜 V2).
1차 통합 범위만 정의한다 (핸드오프 §2-6, 프로토콜 계약서 ⚠️ 박스).
"""

# --- 명령 (Master -> Arm): PC가 생성, 브리지가 FPGA로 송출 ---
MOTION_CTRL_1   = 0x150   # 비상정지 등 (1차 범위 밖이지만 estop inject용으로 식별만)
MOTION_CTRL_2   = 0x151   # 모드/속도% 제어
JOINT_CTRL_12   = 0x155   # joint 1,2
JOINT_CTRL_34   = 0x156   # joint 3,4
JOINT_CTRL_56   = 0x157   # joint 5,6
MOTOR_ENABLE    = 0x471   # enable/disable
GRIPPER_CTRL    = 0x159   # ★그리퍼 제어 (GripperCtrl). /joint_ctrl_single position[6] → 컨트롤러가 0x159 로

# --- 피드백 (Arm -> Master): 가상로봇이 생성, vcan0로 직접 ---
ARM_STATUS         = 0x2A1
JOINT_FEEDBACK_12  = 0x2A5
JOINT_FEEDBACK_34  = 0x2A6
JOINT_FEEDBACK_56  = 0x2A7

# 1차 범위 명령 집합 (브리지 기본 화이트리스트)
SCOPE_COMMAND_IDS = frozenset({MOTION_CTRL_2, JOINT_CTRL_12, JOINT_CTRL_34,
                               JOINT_CTRL_56, MOTOR_ENABLE, GRIPPER_CTRL})

# 비상정지를 포함한 확장 명령 집합 (reflex/estop 단계에서 사용)
COMMAND_IDS_WITH_ESTOP = SCOPE_COMMAND_IDS | {MOTION_CTRL_1}

# 1차 범위 피드백 집합
SCOPE_FEEDBACK_IDS = frozenset({ARM_STATUS, JOINT_FEEDBACK_12,
                                JOINT_FEEDBACK_34, JOINT_FEEDBACK_56})


# 피드백(Arm->Master) ID 범위 — 단순 임계값으로 명령과 못 가른다.
# (명령 0x47x 와 피드백 0x48x 가 인접하므로 명시적 범위로 분류)
#   0x2A1-0x2A8 상태/말단/관절/그리퍼, 0x251-0x256 고속, 0x261-0x266 저속, 0x481-0x486 vel/acc
_FEEDBACK_RANGES = ((0x2A1, 0x2A8), (0x251, 0x256), (0x261, 0x266), (0x481, 0x486))


def is_feedback_id(can_id: int) -> bool:
    """피드백(Arm->Master) ID인가. 브리지가 절대 FPGA로 되돌리면 안 되는 ID."""
    return any(lo <= can_id <= hi for lo, hi in _FEEDBACK_RANGES)


def is_command_id(can_id: int) -> bool:
    """명령(Master->Arm) ID인가 (피드백이 아닌 모든 ID)."""
    return not is_feedback_id(can_id)
