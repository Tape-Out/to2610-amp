#!/usr/bin/env bash
# 拼出这一颗的源码树 build/src：先让 to2610-soc 拼好它的那一份（KianV SoC 加地址窗与外设块），
# 套上 patch/amp.patch（第二个核、它的 CLINT、接进仲裁），再放进本仓 hwsrc 里的模块。
# 用法：setup.sh <gf180mcu-kianv-rv32ima-sv32 仓> <to2610-soc 仓>。息壤的调用方式由任务环境里的 $XIRANG 给
set -euo pipefail
cd "$(dirname "$0")/.."
K=$(realpath "$1")
S=$(realpath "$2")
rm -rf build/src
mkdir -p build
bash "$S/htest/setup.sh" "$K" > /dev/null
cp -r "$S/build/src" build/src
patch -s -p1 -d build < patch/amp.patch
cp hwsrc/*.v build/src/
echo "build/src：$(find build/src -name '*.v' -o -name '*.sv' | wc -l) 个源文件"
