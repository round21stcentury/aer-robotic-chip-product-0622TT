#!/usr/bin/env python3
"""Piper CAN 프레임 코덱 + CAN-over-UDP 13바이트 패킷 (순수 함수, 외부 의존성 없음).

두 계약서의 단일 진실 공급원:
  - 프레임 바이트 레이아웃: CAN_프로토콜_계약서.md §2-3
  - 13바이트 UDP 패킷:      CAN-이더넷_브리지_계약서.md §2

권위 검증: piper_sdk v0.6.1 protocol_v2 (piper_protocol_v2.py / piper_protocol_base.py)
  - 멀티바이트 정수 = 빅엔디언 (struct ">i"/">I"/">h"/">H")
  - 관절각 = signed int32, 단위 0.001°
  - ConvertBytesToInt 기본 빅엔디언
test_frames.py 의 골든벡터(piper_sdk 실코드 출력)로 바이트 동일성 보증.
"""
import struct

from . import ids

# ── 단위 변환 (piper_ctrl_single_node_new.py 와 동일 계수, 루프 일관성 위해 그대로 미러) ──
# 명령:   rad -> 0.001°  (controller joint_callback: factor = 1000*180/3.14)
RAD_TO_MILLIDEG = 57324.840764
# 피드백: 0.001° -> rad  (controller PublishArmJointAndGripper: /1000 * 0.017444)
MILLIDEG_TO_RAD = 0.017444 / 1000.0


def rad_to_raw(rad: float) -> int:
    """라디안 관절각 -> 0.001° 정수 (명령 인코딩용)."""
    return int(round(rad * RAD_TO_MILLIDEG))


def raw_to_rad(raw: int) -> float:
    """0.001° 정수 -> 라디안 (피드백 디코딩용, 컨트롤러 read 계수와 일치)."""
    return raw * MILLIDEG_TO_RAD


def fb_rad_to_raw(rad: float) -> int:
    """라디안 -> 0.001° 정수 (피드백 인코딩용; 컨트롤러 read 계수의 역).

    컨트롤러가 raw/1000*0.017444 로 읽으므로, Gazebo 실제각이 그대로
    표시되도록 그 역수를 쓴다.
    """
    return int(round(rad / MILLIDEG_TO_RAD))


# ───────────────────────── 저수준 정수 ↔ 바이트 (빅엔디언) ─────────────────────────
def _i32(v: int) -> bytes:
    """signed int32 빅엔디언 4바이트."""
    return struct.pack(">i", v)


def _read_i32(b: bytes, off: int) -> int:
    return struct.unpack(">i", b[off:off + 4])[0]


def _u8(v: int) -> bytes:
    return struct.pack(">B", v & 0xFF)


# ───────────────────────── CAN-over-UDP 13바이트 패킷 ─────────────────────────
# 레이아웃: can_id(4B BE) + dlc(1B) + data[8] (브리지 계약서 §2)
UDP_PACKET_LEN = 13


def pack_udp(can_id: int, data: bytes) -> bytes:
    """CAN 프레임 1개 -> 정확히 13바이트 UDP 페이로드.

    payload 는 재해석 없이 그대로(빅엔디언 can_id + dlc + 8B 패딩). 안 쓰는 바이트 0.
    """
    if len(data) > 8:
        raise ValueError(f"CAN data >8 bytes: {len(data)}")
    dlc = len(data)
    pkt = struct.pack(">I", can_id) + bytes([dlc]) + data.ljust(8, b"\x00")
    assert len(pkt) == UDP_PACKET_LEN
    return pkt


def unpack_udp(pkt: bytes):
    """13바이트 UDP 페이로드 -> (can_id, dlc, data[:dlc]). (mock_fpga 용)"""
    if len(pkt) != UDP_PACKET_LEN:
        raise ValueError(f"UDP packet must be {UDP_PACKET_LEN} bytes, got {len(pkt)}")
    can_id = struct.unpack(">I", pkt[0:4])[0]
    dlc = pkt[4]
    data = pkt[5:5 + dlc]
    return can_id, dlc, data


# ════════════════════════════ 명령 인코더 (Master -> Arm) ════════════════════════════
def enc_motion_ctrl_2(ctrl_mode: int = 0x01, move_mode: int = 0x01,
                      spd_rate: int = 50, mit_mode: int = 0x00,
                      residence_time: int = 0, installation_pos: int = 0x00):
    """0x151 MotionCtrl_2. 반환 (can_id, data[8]).

    바이트: [ctrl_mode, move_mode, spd_rate(0~100), mit_mode, residence, install, 0, 0]
    """
    if not 0 <= spd_rate <= 100:
        raise ValueError(f"spd_rate out of range 0-100: {spd_rate}")
    data = bytes([ctrl_mode & 0xFF, move_mode & 0xFF, spd_rate & 0xFF,
                  mit_mode & 0xFF, residence_time & 0xFF, installation_pos & 0xFF,
                  0x00, 0x00])
    return ids.MOTION_CTRL_2, data


def enc_joint_ctrl(j1: int, j2: int, j3: int, j4: int, j5: int, j6: int):
    """0x155/0x156/0x157 JointCtrl. 각 관절 signed int32 0.001°.

    반환: [(0x155,data), (0x156,data), (0x157,data)] — 3프레임.
    """
    return [
        (ids.JOINT_CTRL_12, _i32(j1) + _i32(j2)),
        (ids.JOINT_CTRL_34, _i32(j3) + _i32(j4)),
        (ids.JOINT_CTRL_56, _i32(j5) + _i32(j6)),
    ]


def enc_motor_enable(motor_num: int = 0xFF, enable_flag: int = 0x02):
    """0x471 Enable/Disable. 반환 (can_id, data[8]).

    motor_num: 1-6 관절 / 7 그리퍼 / 0xFF 전체.  enable_flag: 0x01 disable / 0x02 enable.
    """
    data = bytes([motor_num & 0xFF, enable_flag & 0xFF, 0, 0, 0, 0, 0, 0])
    return ids.MOTOR_ENABLE, data


# ════════════════════════════ 명령 디코더 (가상로봇이 사용) ════════════════════════════
def dec_motion_ctrl_2(data: bytes) -> dict:
    return {
        "ctrl_mode": data[0], "move_mode": data[1], "spd_rate": data[2],
        "mit_mode": data[3], "residence_time": data[4], "installation_pos": data[5],
    }


def dec_joint_ctrl(can_id: int, data: bytes):
    """0x155/156/157 -> (joint_a, joint_b) signed int32 0.001°."""
    return _read_i32(data, 0), _read_i32(data, 4)


def dec_motor_enable(data: bytes):
    """0x471 -> (motor_num, enable_flag)."""
    return data[0], data[1]


# ════════════════════════════ 피드백 인코더 (가상로봇 -> 컨트롤러) ════════════════════════════
def enc_arm_status(ctrl_mode: int = 0x01, arm_status: int = 0x00,
                   mode_feed: int = 0x01, teach_status: int = 0x00,
                   motion_status: int = 0x00, trajectory_num: int = 0x00,
                   err_code: int = 0x0000):
    """0x2A1 ArmStatus. 반환 (can_id, data[8]).

    바이트: [ctrl_mode, arm_status, mode_feed, teach, motion, traj_num, err_code(16b BE)]
    (계약서의 err_low/err_high = SDK의 16비트 err_code 한 필드)
    motion_status: 0x00 도달 / 0x01 미도달
    """
    data = bytes([ctrl_mode & 0xFF, arm_status & 0xFF, mode_feed & 0xFF,
                  teach_status & 0xFF, motion_status & 0xFF, trajectory_num & 0xFF]) \
        + struct.pack(">H", err_code & 0xFFFF)
    return ids.ARM_STATUS, data


def enc_joint_feedback(j1: int, j2: int, j3: int, j4: int, j5: int, j6: int):
    """0x2A5/0x2A6/0x2A7 JointFeedback. 각 관절 signed int32 0.001°.

    반환: [(0x2A5,data), (0x2A6,data), (0x2A7,data)] — 3프레임.
    """
    return [
        (ids.JOINT_FEEDBACK_12, _i32(j1) + _i32(j2)),
        (ids.JOINT_FEEDBACK_34, _i32(j3) + _i32(j4)),
        (ids.JOINT_FEEDBACK_56, _i32(j5) + _i32(j6)),
    ]


# ════════════════════════════ 피드백 디코더 (검증/테스트용) ════════════════════════════
def dec_arm_status(data: bytes) -> dict:
    return {
        "ctrl_mode": data[0], "arm_status": data[1], "mode_feed": data[2],
        "teach_status": data[3], "motion_status": data[4], "trajectory_num": data[5],
        "err_code": struct.unpack(">H", data[6:8])[0],
    }


def dec_joint_feedback(can_id: int, data: bytes):
    """0x2A5/2A6/2A7 -> (joint_a, joint_b) signed int32 0.001°."""
    return _read_i32(data, 0), _read_i32(data, 4)
