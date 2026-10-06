O ?= build
CROSS ?= riscv64-unknown-elf-
# 启动代码与链接脚本取 to2610-kvc 的回显载荷那一份：链接在 SDRAM 起始处，由引导程序搬过去
ECHO ?= ../../../to2610-kvc/htest/echo

$(O)/amp.bin: $(ECHO)/start.S amp.c $(ECHO)/link.ld
	mkdir -p $(O)
	$(CROSS)gcc -march=rv32ima_zicsr -mabi=ilp32 -Os -ffreestanding -nostdlib -Wl,-T,$(ECHO)/link.ld -o $(O)/amp.elf $(ECHO)/start.S amp.c
	$(CROSS)objcopy -O binary $(O)/amp.elf $@
