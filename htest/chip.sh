#!/usr/bin/env bash
# 整片测试，全部跑在 ran asic 出的那份 .v 上。测试台、片外模型来自黑盒仓，引导程序来自 to2610-kvc，
# 复用焊盘上的回环与外设测试来自 to2610-soc。
#   hello、periph、isa、boot  to2610-kvc 的四段原样跑：第二个核没放开时，这一颗与单核的那一颗一样
#   xio    to2610-soc 的外设测试原样跑
#   amp    两个核一起：第一个核放开第二个核，第二个核上的 FreeRTOS 经核间那一页报数，门铃进第一个核的中断
# 用法：chip.sh <输出目录> <gf180mcu-kianv-rv32ima-sv32 仓> <to2610-kvc 仓> <to2610-soc 仓>。
# 已经跑过 ran asic 的，把输出目录给 CHIP_ASIC
set -euo pipefail
cd "$(dirname "$0")/.."
O=$(realpath -m "$1")
K=$(realpath "$2")
L=$(realpath "$3")
S=$(realpath "$4")
rm -rf "$O"
mkdir -p "$O"
A=${CHIP_ASIC:-$O/asic}
[ -s "$A/report.json" ] || $XIRANG asic to2610-amp --no-run -o "$A"
top=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['top'])" "$A/report.json")
python3 "$S/htest/shim.py" "$A/report.json" > "$O/tb.v"
bash "$K/htest/sim.sh" "$O/sim" "$O/tb.v" "$A/$top.v"

res=()
run() {
  local name=$1 what=$2 t0=$SECONDS rc=0
  shift 2
  "$O/sim/Vtb" "$@" > "$O/$name.log" 2> "$O/$name.err" || rc=$?
  tail -n 3 "$O/$name.err"
  res+=("$name=$rc:$((SECONDS - t0)):$what")
}

make -s -C "$K/htest/hello" O="$O/hello"
run hello "to2610-kvc 的裸机冒烟：从 Flash 就地执行，读写 SDRAM" \
  +flash="$O/hello/hello.bin@0x100000" +script="$K/htest/hello/script" +max=30000000

make -s -C "$K/htest/periph" O="$O/periph"
run periph "to2610-kvc 的外设测试：GPIO、两路 SPI 与回声从设备、计时器中断、PLIC、重启" \
  +flash="$O/periph/periph.bin@0x100000" +script="$K/htest/periph/script" +spiecho +max=30000000

t0=$SECONDS
rc=0
SIM="$O/sim" bash "$K/htest/isa.sh" "$O/isa" > "$O/isa.log" 2>&1 || rc=$?
tail -n 3 "$O/isa.log"
res+=("isa=$rc:$((SECONDS - t0)):riscv-tests 的 rv32ui、um、ua、mi、si 逐个在这份 .v 上跑（第一个核），程序放进 SDRAM、测试台盯 tohost；已知失败钉住，多过一个少过一个都算红")

make -s -C "$L/sw/boot" O="$O/boot"
make -s -C "$L/htest/echo" O="$O/echo"
python3 "$L/sw/pack.py" "$O/boot/boot.bin" "$O/echo/echo.bin" "$O/echo.flash"
run boot "引导程序搬载荷并核对校验和，载荷回显串口" \
  +flash="$O/echo.flash@0" +script="$L/htest/echo/script" +max=60000000

# 寄存器偏移不手抄：让息壤照各 IP 的 regmap.yaml 出头文件
mkdir -p "$O/xio/inc"
for ip in uart gpio timer wdt rtc i2c spi onew i2s can ps2 rng emac pwm crc; do
  $XIRANG gen "$ip" -o "$O/xio/gen/$ip" > /dev/null
  cp "$O/xio/gen/$ip/sw/$ip.h" "$O/xio/inc/"
done
make -s -C "$S/htest/xio" O="$O/xio" HELLO="$K/htest/hello"
run xio "to2610-soc 的外设测试：十五个外设的地址、七个经复用焊盘走通、三路中断" \
  +flash="$O/xio/xio.bin@0x100000" +script="$S/htest/xio/script" +max=60000000

make -s -C htest/rtos O="$O/rtosb" KVC="$L"
make -s -C htest/amp O="$O/amp" ECHO="$L/htest/echo"
# Flash 里：头 1 MiB 放第二个核的镜像，1 MiB 处是引导程序，其后是第一个核的载荷
python3 "$L/sw/pack.py" "$O/boot/boot.bin" "$O/amp/amp.bin" "$O/amp.flash"
run amp "两个核一起：第二个核没放开时门铃是安静的；放开后它把 FreeRTOS 搬进 SDRAM 顶上起调度器，五个数与最后一句经门铃中断逐句到第一个核，两个方向的字都对；收回去之后不再响" \
  +flash="$O/amp.flash@0" +flash="$O/rtosb/rtos.bin@0" +script=htest/amp/script +max=100000000

python3 "$L/htest/junit.py" "$O/results.xml" "${res[@]}"
printf '%s\n' "${res[@]}"
if grep -q '<failure' "$O/results.xml"; then echo "有用例没过"; exit 1; fi
echo "整片测试 ${#res[@]} 段全过"
