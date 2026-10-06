O ?= build
CROSS ?= riscv64-unknown-elf-
# FreeRTOS 的内核与那几个 libc 的垫片取 to2610-kvc 仓里的
KVC ?= ../../../to2610-kvc
F = $(KVC)/third_party/FreeRTOS-Kernel
P = $(F)/portable/GCC/RISC-V

SRC = start.S main.c $(F)/tasks.c $(F)/queue.c $(F)/list.c $(F)/portable/MemMang/heap_4.c $(P)/port.c $(P)/portASM.S
INC = -I. -I$(KVC)/htest/rtos/libc -I$(F)/include -I$(P) -I$(P)/chip_specific_extensions/RV32I_CLINT_no_extensions

# -mno-relax：不设 gp，链接器就别把取地址松弛成相对 gp 的
$(O)/rtos.bin: $(SRC) FreeRTOSConfig.h link.ld
	mkdir -p $(O)
	$(CROSS)gcc -march=rv32ima_zicsr -mabi=ilp32 -Os -ffreestanding -nostdlib -mno-relax $(INC) \
	  -Wl,-T,link.ld -o $(O)/rtos.elf $(SRC)
	$(CROSS)objcopy -O binary $(O)/rtos.elf $@
