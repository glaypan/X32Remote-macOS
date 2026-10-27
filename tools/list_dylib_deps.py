#!/usr/bin/env python3
"""列出 .app 内所有 Mach-O 的外部动态库依赖（LC_LOAD_DYLIB 等），纯标准库解析。

用于在 Windows 上排查"dyld: Library not loaded"类打包缺陷：
找出所有引用构建机私有路径（/usr/local/opt/...、/opt/homebrew/...）的 Mach-O。

用法:
  python tools/list_dylib_deps.py build/xapp/X32Remote.app [--all]
"""

import os
import struct
import sys

MH_MAGIC_64 = 0xFEEDFACF
LC_REQ_DYLD = 0x80000000
LC_LOAD_DYLIB = 0x0C
LC_LOAD_WEAK_DYLIB = 0x18 | LC_REQ_DYLD
LC_REEXPORT_DYLIB = 0x1F | LC_REQ_DYLD
LC_RPATH = 0x1C

SYSTEM_PREFIXES = ("/usr/lib/", "/System/")


def parse_load_cmds(path):
    """返回 (arch, [(cmd_name, dylib_path)])；不是 Mach-O 返回 None。"""
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

    arch = "x86_64" if cputype == (0x01000000 | 7) else "0x%x" % cputype
    deps = []
    off = 0
    for _ in range(ncmds):
        if off + 8 > len(body):
            break
        cmd, cmdsize = struct.unpack(endian + "II", body[off:off + 8])
        if cmdsize <= 0:
            break
        if cmd in (LC_LOAD_DYLIB, LC_LOAD_WEAK_DYLIB, LC_REEXPORT_DYLIB):
            name_off = struct.unpack(endian + "I", body[off + 8:off + 12])[0]
            start = off + name_off
            end = body.find(b"\x00", start)
            name = body[start:end].decode("utf-8", "replace")
            tag = {LC_LOAD_DYLIB: "LOAD", LC_LOAD_WEAK_DYLIB: "WEAK",
                   LC_REEXPORT_DYLIB: "REEXPORT"}[cmd]
            deps.append((tag, name))
        elif cmd == LC_RPATH:
            name_off = struct.unpack(endian + "I", body[off + 8:off + 12])[0]
            start = off + name_off
            end = body.find(b"\x00", start)
            deps.append(("RPATH", body[start:end].decode("utf-8", "replace")))
        off += cmdsize
    return arch, deps


def is_external(path):
    return not path.startswith(SYSTEM_PREFIXES) and not path.startswith("@")


def main():
    app = sys.argv[1]
    show_all = "--all" in sys.argv[2:]
    bad = 0
    machos = 0
    for root, _dirs, files in os.walk(app):
        for name in sorted(files):
            p = os.path.join(root, name)
            got = parse_load_cmds(p)
            if not got:
                continue
            machos += 1
            arch, deps = got
            rel = os.path.relpath(p, app)
            ext = [(t, d) for t, d in deps if is_external(d)]
            if ext:
                bad += 1
                print("!! %s [%s]" % (rel, arch))
                for t, d in ext:
                    print("     %-8s %s" % (t, d))
            elif show_all:
                print("ok %s [%s]" % (rel, arch))
                for t, d in deps:
                    print("     %-8s %s" % (t, d))
    print("\nMach-O 总数 %d，引用非系统路径的 %d 个" % (machos, bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
