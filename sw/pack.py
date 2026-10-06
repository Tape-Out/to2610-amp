"""拼这一颗的 Flash 镜像：头 1 MiB 放第二个核的镜像，1 MiB 处是引导程序，其后 64 KiB 处是第一个核的载荷。

后两样的格式与 to2610-kvc 的 sw/pack.py 相同（载荷带 16 字节的头：标记、长度、按字求的和），引导程序也是它的那一份。
第二个核从 Flash 起始处就地执行，镜像要自己先搬进 SDRAM（htest/rtos/start.S 是现成的样子）。

用法：pack.py <boot.bin> <第一个核的载荷> <第二个核的镜像> <输出>
"""
import pathlib
import struct
import sys

BOOT, PAYLOAD, MAGIC = 0x100000, 0x110000, 0x4C50564B

boot, load, second = (pathlib.Path(a).read_bytes() for a in sys.argv[1:4])
if len(second) > BOOT:
    sys.exit(f"第二个核的镜像 {len(second)} 字节，放不进头 1 MiB")
if len(boot) > PAYLOAD - BOOT:
    sys.exit(f"引导程序 {len(boot)} 字节，放不进 64 KiB")
body = load + b"\0" * (-len(load) % 4)
total = sum(struct.unpack(f"<{len(body) // 4}I", body)) & 0xFFFFFFFF
img = bytearray(b"\xff" * (PAYLOAD + 16 + len(body)))
img[:len(second)] = second
img[BOOT:BOOT + len(boot)] = boot
img[PAYLOAD:PAYLOAD + 16] = struct.pack("<4I", MAGIC, len(load), total, 0)
img[PAYLOAD + 16:] = body
if len(img) > 16 << 20:
    sys.exit(f"镜像 {len(img)} 字节，超过 16 MiB 的 Flash 窗口")
pathlib.Path(sys.argv[4]).write_bytes(img)
print(f"{sys.argv[4]}：第二个核 {len(second)} 字节，引导程序 {len(boot)} 字节，载荷 {len(load)} 字节，共 {len(img)} 字节")
