#!/usr/bin/env python3
"""断言目录树下所有 Mach-O 的最低系统版本不超上限、且包含 x86_64 架构。

为什么需要：捆绑的 Python 若含高于 10.14.6 的部署目标，在老 Intel Mac 上
直接无法加载；若混入 arm64-only 二进制，Intel 机器同样跑不起来。
这两类问题在 CI 的现代 macOS 上毫无征兆，必须用 otool / lipo 逐个二进制自证。
"""
import os
import subprocess
import sys

MACHO_MAGICS = {
    b"\xcf\xfa\xed\xfe",  # MH_MAGIC_64 (LE)
    b"\xce\xfa\xed\xfe",  # MH_CIGAM_64 (BE)
    b"\xca\xfe\xba\xbe",  # FAT_MAGIC (BE)
    b"\xbe\xba\xfe\xca",  # FAT_CIGAM (LE)
    b"\xfe\xed\xfa\xcf",  # MH_MAGIC (LE)
    b"\xfe\xed\xfa\xce",  # MH_CIGAM (BE)
}


def parse_version(s):
    parts = []
    for x in s.strip().split("."):
        try:
            parts.append(int(x))
        except ValueError:
            parts.append(0)
    while len(parts) < 3:
        parts.append(0)
    return tuple(parts[:3])


def macho_min_version(path):
    try:
        out = subprocess.run(
            ["otool", "-l", path], capture_output=True, text=True, timeout=60
        ).stdout
    except Exception:
        return None
    lines = out.splitlines()
    ver = None
    for i, ln in enumerate(lines):
        t = ln.strip()
        if t.startswith("cmd LC_VERSION_MIN_MACOSX"):
            for j in range(i + 1, min(i + 5, len(lines))):
                if "version" in lines[j]:
                    ver = lines[j].split()[-1]
                    break
        elif t.startswith("cmd LC_BUILD_VERSION"):
            for j in range(i + 1, min(i + 5, len(lines))):
                if "minos" in lines[j]:
                    ver = lines[j].split()[-1]
                    break
    return ver


def macho_archs(path):
    try:
        out = subprocess.run(
            ["lipo", "-archs", path], capture_output=True, text=True, timeout=60
        )
    except Exception:
        return None
    if out.returncode != 0:
        return None
    return out.stdout.strip()


def main():
    if len(sys.argv) != 3:
        print("用法: check_deployment.py <目录> <版本上限，如 10.14.6>")
        sys.exit(2)
    root, limit_s = sys.argv[1], sys.argv[2]
    limit = parse_version(limit_s)
    bad, bad_arch, checked = [], [], 0
    for dirpath, _dirnames, filenames in os.walk(root):
        for fn in filenames:
            p = os.path.join(dirpath, fn)
            if os.path.islink(p):
                continue
            try:
                with open(p, "rb") as f:
                    magic = f.read(4)
            except OSError:
                continue
            if magic not in MACHO_MAGICS:
                continue
            checked += 1
            v = macho_min_version(p)
            if v is None:
                bad.append((p, "无法解析最低系统版本"))
            elif parse_version(v) > limit:
                bad.append((p, v))
            archs = macho_archs(p)
            if archs is None or "x86_64" not in archs:
                bad_arch.append((p, archs or "无法解析架构"))
    print("检查 %d 个 Mach-O，上限 ≤ %s，架构需含 x86_64" % (checked, limit_s))
    for p, v in bad:
        print("  部署目标超限: %s -> %s" % (p, v))
    for p, a in bad_arch:
        print("  架构不含 x86_64: %s -> %s" % (p, a))
    if bad or bad_arch:
        sys.exit(1)
    print("部署目标与架构断言通过")


if __name__ == "__main__":
    main()
