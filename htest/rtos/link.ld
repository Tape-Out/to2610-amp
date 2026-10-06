OUTPUT_ARCH("riscv")
ENTRY(_start)
/* SDRAM 顶上的 1 MiB 归第二个核，Linux 的设备树里不把它算进内存 */
MEMORY { ram (rwx) : ORIGIN = 0x81F00000, LENGTH = 1M }
SECTIONS {
  .text : { *(.text.start) *(.text*) *(.rodata*) *(.srodata*) } > ram
  .data : { *(.data*) *(.sdata*) . = ALIGN(4); __image_end = .; } > ram
  .bss : ALIGN(4) { __bss_start = .; *(.bss*) *(.sbss*) *(COMMON) . = ALIGN(4); __bss_end = .; } > ram
  . = ALIGN(16);
  . += 4096;
  __stack_top = .;
  /DISCARD/ : { *(.comment) *(.riscv.attributes) *(.eh_frame) }
}
