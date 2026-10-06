# 第二个核从 Flash 的 0x2000_0000 起。镜像链接在 SDRAM 顶上那 1 MiB，这一段先在 Flash 里就地执行，
# 把整个镜像搬过去再跳：从 Flash 取一条指令要一百多拍，留在那里跑不动节拍中断。
# 搬之前只用相对当前位置的寻址；目的地址与跳转目标取链接时的绝对地址。
# 这个核没有串口：走到哪一站写进 MSG_A（0xb000 打头），第一个核替它报。
# 调度器起来之前 FreeRTOS 的陷入入口用不得（它要往当前任务的控制块里存栈指针，那时还没有任务），
# 这一段的陷入交给 early_trap：原因写成 0xb0e000cc，过一会儿再写返回地址的低 20 位 0xb1xxxxxx，然后停住
.section .text.start
.global _start
_start:
    li t5, 0x40040018
    li t6, 0xb0000001
    sw t6, 0(t5)
    lla t0, early_trap
    csrw mtvec, t0
    lla t0, _start
    lui t1, %hi(_start)
    addi t1, t1, %lo(_start)
    lui t2, %hi(__image_end)
    addi t2, t2, %lo(__image_end)
1:  bgeu t1, t2, 2f
    lw t3, 0(t0)
    sw t3, 0(t1)
    addi t0, t0, 4
    addi t1, t1, 4
    j 1b
2:  lui t0, %hi(in_ram)
    jalr zero, %lo(in_ram)(t0)
in_ram:
    li t6, 0xb0000002
    sw t6, 0(t5)
    la t0, early_trap
    csrw mtvec, t0
    la sp, __stack_top
    la t0, __bss_start
    la t1, __bss_end
1:  bgeu t0, t1, 2f
    sw zero, 0(t0)
    addi t0, t0, 4
    j 1b
2:  call main
3:  j 3b

.balign 4
early_trap:
    li t5, 0x40040018
    csrr t6, mcause
    andi t6, t6, 0xff
    li t4, 0xb0e00000
    or t6, t6, t4
    sw t6, 0(t5)
    li t4, 4000
1:  addi t4, t4, -1
    bnez t4, 1b
    csrr t6, mepc
    li t4, 0x000fffff
    and t6, t6, t4
    li t4, 0xb1000000
    or t6, t6, t4
    sw t6, 0(t5)
2:  j 2b
