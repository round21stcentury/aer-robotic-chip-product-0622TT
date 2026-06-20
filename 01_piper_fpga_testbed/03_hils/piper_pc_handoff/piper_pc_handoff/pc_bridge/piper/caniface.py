#!/usr/bin/env python3
"""Raw SocketCAN(AF_CAN) 래퍼 — python-can 의존성 없이 클래식 CAN 2.0 송수신.

클래식 CAN 프레임 struct: can_id(u32) + can_dlc(u8) + pad(3) + data(8) = 16바이트.
표준 11비트 ID만 사용(플래그 비트 없음). 브리지 계약서 §3: 클래식 2.0 / 11비트 / 1Mbps.
"""
import socket
import struct

# Linux <linux/can.h> 와 동일 (네이티브 바이트오더)
CAN_FRAME_FMT = "=IB3x8s"
CAN_FRAME_SIZE = struct.calcsize(CAN_FRAME_FMT)  # 16

# socket 상수 폴백 (일부 환경에서 미정의일 수 있음)
SOL_CAN_RAW = getattr(socket, "SOL_CAN_RAW", 101)
CAN_RAW_FILTER = getattr(socket, "CAN_RAW_FILTER", 1)


def open_can(ifname: str, recv_ids=None, recv_timeout: float = None) -> socket.socket:
    """ifname(vcan0/can0...) raw CAN 소켓 오픈.

    recv_ids: 수신 화이트리스트(set/iterable of int). None이면 모두 수신.
    recv_timeout: recv 블로킹 타임아웃 초. None이면 블로킹.
    """
    s = socket.socket(socket.AF_CAN, socket.SOCK_RAW, socket.CAN_RAW)
    if recv_ids is not None:
        filters = b"".join(
            struct.pack("=II", cid, 0x7FF) for cid in recv_ids  # 표준 11비트 정확 매칭
        )
        if filters:
            s.setsockopt(SOL_CAN_RAW, CAN_RAW_FILTER, filters)
    s.bind((ifname,))
    if recv_timeout is not None:
        s.settimeout(recv_timeout)
    return s


def send(sock: socket.socket, can_id: int, data: bytes) -> None:
    """클래식 CAN 프레임 1개 송신 (data <= 8B, 8B로 패딩)."""
    dlc = len(data)
    frame = struct.pack(CAN_FRAME_FMT, can_id & 0x7FF, dlc, data.ljust(8, b"\x00"))
    sock.send(frame)


def recv(sock: socket.socket):
    """CAN 프레임 1개 수신 -> (can_id, data[:dlc]). 타임아웃 시 socket.timeout 발생."""
    frame = sock.recv(CAN_FRAME_SIZE)
    can_id, dlc, data = struct.unpack(CAN_FRAME_FMT, frame)
    return (can_id & 0x1FFFFFFF), data[:dlc]
