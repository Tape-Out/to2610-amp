#!/usr/bin/env bash
# 拼出这一颗的源码树 build/src：黑盒仓拼好的那一份（KianV SoC，即 to2610-kvc 的那一颗），
# 套上 patch/amp.patch（第二个核、它的 CLINT、仲裁、核间那一页），再放进本仓 hwsrc 里的模块。
# 用法：setup.sh <gf180mcu-kianv-rv32ima-sv32 仓>
set -euo pipefail
cd "$(dirname "$0")/.."
K=$(realpath "$1")
rm -rf build/src
mkdir -p build
bash "$K/htest/setup.sh" > /dev/null
cp -r "$K/build/src" build/src
patch -s -p1 -d build < patch/amp.patch
cp hwsrc/*.v build/src/
echo "build/src：$(find build/src -name '*.v' -o -name '*.sv' | wc -l) 个源文件"
