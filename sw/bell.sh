#!/bin/sh
# 在芯片上的 Linux 里用（to2610-kvc 的镜像，busybox 带 devmem）：经 /dev/mem 操作核间那一页。
# 用法：bell.sh run            放开第二个核
#       bell.sh stop           收回第二个核
#       bell.sh get            等第二个核拉门铃，读出它写的那个字，清门铃
#       bell.sh say <数>       写一个字给第二个核，拉它的门铃
set -eu
B=0x40040000
r() { devmem $((B + $1)) 32; }
w() { devmem $((B + $1)) 32 "$2"; }
case "${1:-}" in
  run) w 0x04 1 ;;
  stop) w 0x04 0 ;;
  get)
    while [ $(($(r 0x08) & 1)) -eq 0 ]; do sleep 1; done
    r 0x18
    w 0x0c 1
    ;;
  say)
    w 0x1c "$2"
    w 0x10 1
    ;;
  *)
    sed -n '2,6p' "$0"
    exit 1
    ;;
esac
