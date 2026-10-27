#!/usr/bin/env python3
"""离线校验 macOS .app：纯 Python 解析 Mach-O，不需要 macOS / otool / lipo。

用途：在没有 Mac 的机器上（例如 Windows 上等 CI）确认五件事：
  1. 每个 Mach-O 的 **minos ≤ 部署目标**（默认 10.14.6）—— 这是"能在老系统上跑"的硬证据；
  2. 架构包含 **x86_64**；
  3. Info.plist 的版本与最低系统版本符合预期；
  4. 内置内核与协议仓对应 tag 的 sha256 一致（防止"发布包里的内核不是那一版"）；
  5. **没有任何 Mach-O 引用系统库之外的动态库** —— /usr/lib、/System 之外
     的路径（/usr/local/opt/...、/opt/homebrew/... 等构建机私有路径）一律拒绝。
     v1.1.2 事故：内置 Python 链了 Homebrew 的 keg-only 库，用户机上
     dyld: Library not loaded，python3 起不来。前三项检查查不到这类问题，
     必须单独扫 LC_LOAD_DYLIB。

用法:
  python tools/check_app_offline.py build/dl/X32Remote.app --sim-sha256 <期望值> \
      --version 1.1.0 --min-macos 10.14.6
"""

import argparse
import hashlib
import os
import plistlib
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from list_dylib_deps import parse_load_cmds, is_external  # noqa: E402

MH_MAGIC_64 = 0xFEEDFACF
LC_VERSION_MIN_MACOSX = 0x24
LC_BUILD_VERSION = 0x32
CPU_ARCH_ABI64 = 0x01000000
CPU_TYPE_X86_64 = 7


def ver_tuple(v):
    return (v >> 16) & 0xFFFF, (v >> 8) & 0xFF, v & 0xFF


def parse_macho(path):
    """返回 (arch_name, minos_tuple|None)；不是 Mach-O 返回 None。"""
    try:
        with open(path, "rb") as f:
            head = f.read(32)
            if len(head) < 32:
                return None
            magic_le = struct.unpack("<I", head[:4])[0]
            magic_be = struct.unpack(">I", head[:4])[0]
            if magic_le == MH_MAGIC_64:
                endian = "<"
            elif magic_be == MH_MAGIC_64:
                endian = ">"
            else:
                return None
            cputype, _cpusub, _ft, ncmds, sizeofcmds, _flags, _res = struct.unpack(
                endian + "IIIIIII", head[4:32])
            body = f.read(sizeofcmds)
    except OSError:
        return None

    arch = "x86_64" if cputype == (CPU_TYPE_X86_64 | CPU_ARCH_ABI64) else "0x%x" % cputype
    minos = None
    off = 0
    for _ in range(ncmds):
        if off + 8 > len(body):
            break
        cmd, cmdsize = struct.unpack(endian + "II", body[off:off + 8])
        if cmdsize <= 0:
            break
        if cmd == LC_BUILD_VERSION and off + 16 <= len(body):
            minos = ver_tuple(struct.unpack(endian + "I", body[off + 12:off + 16])[0])
        elif cmd == LC_VERSION_MIN_MACOSX and off + 12 <= len(body):
            minos = ver_tuple(struct.unpack(endian + "I", body[off + 8:off + 12])[0])
        off += cmdsize
    return arch, minos


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("app")
    ap.add_argument("--min-macos", default="10.14.6")
    ap.add_argument("--version")
    ap.add_argument("--sim-sha256")
    ap.add_argument("--sim-rel", default="Contents/Resources/x32_simulator.py")
    args = ap.parse_args()

    limit = tuple(int(x) for x in args.min_macos.split("."))
    fails = []
    machos = 0
    worst = None
    ext_deps = 0
    for root, _dirs, files in os.walk(args.app):
        for name in files:
            p = os.path.join(root, name)
            got = parse_macho(p)
            if not got:
                continue
            machos += 1
            arch, minos = got
            rel = os.path.relpath(p, args.app)
            if minos is None:
                fails.append("无 minos: %s" % rel)
                continue
            if tuple(minos) > limit:
                fails.append("minos 超出 %s: %s -> %s" % (
                    args.min_macos, rel, ".".join(map(str, minos))))
            if arch != "x86_64":
                fails.append("架构不是 x86_64: %s -> %s" % (rel, arch))
            if worst is None or tuple(minos) > tuple(worst[1]):
                worst = (rel, minos)
            # 第 5 项：外部动态库依赖（v1.1.2 事故的回归防线）
            deps = parse_load_cmds(p)
            if deps:
                for tag, dep in deps[1]:
                    if is_external(dep):
                        ext_deps += 1
                        fails.append("引用构建机私有动态库: %s -> %s (%s)" % (rel, dep, tag))

    print("Mach-O 文件数: %d" % machos)
    if worst:
        print("最高 minos: %s (%s)" % (".".join(map(str, worst[1])), worst[0]))
    print("外部私有动态库引用: %d 处（必须为 0）" % ext_deps)

    info_path = os.path.join(args.app, "Contents", "Info.plist")
    with open(info_path, "rb") as f:
        info = plistlib.load(f)
    short = info.get("CFBundleShortVersionString")
    build = info.get("CFBundleVersion")
    lsm = info.get("LSMinimumSystemVersion")
    print("Info.plist: 版本 %s (%s) / LSMinimumSystemVersion %s" % (short, build, lsm))
    if args.version and short != args.version:
        fails.append("版本不符: %s != %s" % (short, args.version))
    if lsm and tuple(int(x) for x in lsm.split(".")) != limit:
        fails.append("LSMinimumSystemVersion 不符: %s" % lsm)

    sim = os.path.join(args.app, args.sim_rel)
    if not os.path.exists(sim):
        fails.append("缺少内核: %s" % args.sim_rel)
    else:
        h = hashlib.sha256(open(sim, "rb").read()).hexdigest()
        lines = sum(1 for _ in open(sim, "rb"))
        print("内置内核: %d 行 / sha256 %s" % (lines, h))
        if args.sim_sha256 and h != args.sim_sha256:
            fails.append("内核哈希不符: %s != %s" % (h[:16], args.sim_sha256[:16]))

    if fails:
        print("\n== 失败 %d 项 ==" % len(fails))
        for x in fails:
            print("  ! " + x)
        return 1
    print("\n== 全部通过 ==")
    return 0


if __name__ == "__main__":
    sys.exit(main())
