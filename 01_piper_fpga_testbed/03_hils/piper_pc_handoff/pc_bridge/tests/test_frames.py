#!/usr/bin/env python3
"""코덱 정합성 테스트.

골든벡터 = piper_sdk v0.6.1 protocol_v2 실코드(ConvertToList_*) 출력.
  docker run --rm piper-hil:humble python3 -c '<gen>'  로 생성해 박아둠.
순수 의존성 없음 — `python3 tests/test_frames.py` 로 실행.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from piper import frames, ids  # noqa: E402


def hx(b: bytes) -> str:
    return "".join("%02X" % x for x in b)


_fail = 0


def check(name, got, expected):
    global _fail
    ok = got == expected
    if not ok:
        _fail += 1
    print(f"[{'PASS' if ok else 'FAIL'}] {name}: got={got} expected={expected}")


# ───── 골든벡터 (piper_sdk 실코드 출력) ─────
def test_golden():
    # 0x155: joint_1=1000, joint_2=-2000
    cid, data = frames.enc_joint_ctrl(1000, -2000, 0, 0, 0, 0)[0]
    check("0x155 joint(1000,-2000)", (hex(cid), hx(data)), ("0x155", "000003E8FFFFF830"))

    # int32 경계값
    cid, data = frames.enc_joint_ctrl(2147483647, -2147483648, 0, 0, 0, 0)[0]
    check("0x155 joint(max,min)", hx(data), "7FFFFFFF80000000")

    # 0x151: ctrl=1, move=1, spd=50
    cid, data = frames.enc_motion_ctrl_2(0x01, 0x01, 50)
    check("0x151 motion(1,1,50)", (hex(cid), hx(data)), ("0x151", "0101320000000000"))

    # 0x471: motor 7 enable(2) / 전체 disable(1)
    cid, data = frames.enc_motor_enable(7, 0x02)
    check("0x471 enable(7,2)", (hex(cid), hx(data)), ("0x471", "0702000000000000"))
    cid, data = frames.enc_motor_enable(0xFF, 0x01)
    check("0x471 disable(FF,1)", hx(data), "FF01000000000000")

    # 0x2A1 err_code 16비트 BE
    cid, data = frames.enc_arm_status(err_code=0xFFFF)
    check("0x2A1 err_code FFFF", hx(data[6:8]), "FFFF")
    cid, data = frames.enc_arm_status(err_code=513)
    check("0x2A1 err_code 513", hx(data[6:8]), "0201")


# ───── UDP 13바이트 패킷 (브리지 계약서 §2) ─────
def test_udp():
    cid, data = frames.enc_joint_ctrl(1000, -2000, 0, 0, 0, 0)[0]
    pkt = frames.pack_udp(cid, data)
    check("udp len == 13", len(pkt), 13)
    # can_id 빅엔디언 0x155 -> 00 00 01 55, dlc=08
    check("udp 0x155 bytes", hx(pkt), "00000155" + "08" + "000003E8FFFFF830")
    # round-trip
    rid, dlc, rdata = frames.unpack_udp(pkt)
    check("udp unpack id", hex(rid), "0x155")
    check("udp unpack data", hx(rdata), "000003E8FFFFF830")

    # 엔디언 함정 검증: 0x123 -> 00 00 01 23
    check("udp endian 0x123", hx(frames.pack_udp(0x123, b"")[:4]), "00000123")


# ───── 인코드/디코드 round-trip ─────
def test_roundtrip():
    for vals in [(1, 2, 3, 4, 5, 6), (-1000, 90000, -90000, 0, 12345, -67890)]:
        framelist = frames.enc_joint_ctrl(*vals)
        decoded = []
        for cid, data in framelist:
            a, b = frames.dec_joint_ctrl(cid, data)
            decoded.extend([a, b])
        check(f"joint round-trip {vals}", tuple(decoded), vals)

    cid, data = frames.enc_arm_status(ctrl_mode=3, arm_status=1, motion_status=1,
                                      err_code=0x1234)
    d = frames.dec_arm_status(data)
    check("arm_status round-trip", (d["ctrl_mode"], d["arm_status"],
          d["motion_status"], d["err_code"]), (3, 1, 1, 0x1234))


# ───── 단위 변환 ─────
def test_units():
    # rad -> 0.001° -> rad (계수가 비대칭이라 근사 일치)
    import math
    raw = frames.rad_to_raw(math.pi / 2)   # 90도
    check("rad_to_raw(pi/2)~90000", abs(raw - 90000) < 50, True)
    back = frames.raw_to_rad(90000)
    check("raw_to_rad(90000)~pi/2", abs(back - math.pi / 2) < 1e-3, True)


# ───── 방향 분류 (브리지 필터 근거) ─────
def test_direction():
    check("0x155 is command", ids.is_command_id(0x155), True)
    check("0x2A5 is feedback", ids.is_feedback_id(0x2A5), True)
    check("0x471 is command", ids.is_command_id(0x471), True)
    check("0x481 is feedback (not cmd)", ids.is_feedback_id(0x481), True)
    check("scope cmds none are feedback",
          any(ids.is_feedback_id(c) for c in ids.SCOPE_COMMAND_IDS), False)


if __name__ == "__main__":
    test_golden()
    test_udp()
    test_roundtrip()
    test_units()
    test_direction()
    print("-" * 40)
    if _fail:
        print(f"❌ {_fail} check(s) FAILED")
        sys.exit(1)
    print("✅ all checks passed")
