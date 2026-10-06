/* 两个核一起跑：这段程序在第一个核上，由引导程序搬进 SDRAM 再跑；第二个核的 FreeRTOS 镜像在 Flash 的 0x2000_0000。
 * 不留在 Flash 里就地执行：那样每取一条指令占总线一百多拍，两个核轮着用，第二个核就被饿住了。
 * 实际用法里第一个核跑的是 Linux，本来也在 SDRAM 里。
 * 放开第二个核之前，核间那一页认得出来、门铃是安静的；放开之后它把自己搬进 SDRAM 顶上、起调度器，
 * 每收到队列里的一个数就写进 MSG_A 并拉门铃。门铃经 PLIC 的 26 号进这个核的中断，这里读数、清门铃、从串口报。
 * 最后一句带着这边事先写进 MSG_B 的数，证明两个方向都通。
 * 第二个核没有串口：它起步时走到哪一站写在 MSG_A 里（0xb0、0xb1 打头），这里等的时候顺手报出来，等不到就看得出停在哪。
 */
#include <stdint.h>

#define REG(a) (*(volatile uint32_t *)(a))
#define LSR (*(volatile uint8_t *)0x10000005)
#define CSR_R(n) ({ uint32_t v_; __asm__ volatile("csrr %0, " #n : "=r"(v_)); v_; })
#define CSR_W(n, v) __asm__ volatile("csrw " #n ", %0" : : "r"((uint32_t)(v)))
#define CSR_S(n, v) __asm__ volatile("csrs " #n ", %0" : : "r"((uint32_t)(v)))

/* 链接脚本没有 .bss：中断里要记的几个数放在 SDRAM 里固定的地方，离程序与栈都远 */
#define STATE ((volatile uint32_t *)0x80080000)
/* COUNT 是收到了几句，LOG 起逐句记下：打印比对面说话慢，只记最后一句会被下一句盖掉 */
enum { COUNT, LOG, AT = 9, IRQS };

#define AMP 0x40040000u
#define RUN (AMP + 0x04)
#define BELL_A (AMP + 0x08)
#define ACK_A (AMP + 0x0c)
#define MSG_A (AMP + 0x18)
#define MSG_B (AMP + 0x1c)
#define PLIC 0x0c000000u
#define MTIME 0x0200bff8u
#define AMP_IRQ 26

static void putch(char c) {
  while (!(LSR & 0x60)) {}
  REG(0x10000000) = c;
}

static void say(const char *s) {
  while (*s) putch(*s++);
}

static void hex(uint32_t v) {
  for (int i = 28; i >= 0; i -= 4) putch("0123456789abcdef"[v >> i & 15]);
}

static void verdict(const char *what, uint32_t bad, uint32_t detail) {
  say(what);
  say(bad ? " BAD " : " ok ");
  hex(detail);
  putch('\n');
}

__attribute__((interrupt("machine"), aligned(4))) static void trap(void) {
  uint32_t c = CSR_R(mcause);
  if (c == 0x8000000b) {
    uint32_t id = REG(PLIC + 0x200004);
    /* 整段只该进来六次。认领到别的号，或者清不掉反复进，都停下来报 */
    if (id != AMP_IRQ || ++STATE[IRQS] > 32) {
      say("irq ");
      hex(id);
      putch(' ');
      hex(REG(BELL_A));
      putch('\n');
      for (;;) {}
    }
    if (id == AMP_IRQ) {
      STATE[LOG + (STATE[COUNT] & 7)] = REG(MSG_A);
      STATE[COUNT]++;
      REG(ACK_A) = 1;
    }
    REG(PLIC + 0x200004) = id;
  } else {
    say("trap ");
    hex(c);
    putch('\n');
    for (;;) {}
  }
}

/* 等第 k 句，最多 600 毫秒（mtime 每微秒走一格；第二个核从放开到说第一句要一百多毫秒）；回 1 是没等到 */
static uint32_t await(uint32_t k) {
  for (uint32_t t0 = REG(MTIME), dot = 0; REG(MTIME) - t0 < 600000;) {
    /* 每一百毫秒出一个点：看得出这个核还在转、时间还在走 */
    if ((REG(MTIME) - t0) / 100000 > dot) {
      dot++;
      putch('.');
    }
    if (STATE[COUNT] >= k) return 0;
    uint32_t m = REG(MSG_A);
    if ((m >> 24 == 0xb0 || m >> 24 == 0xb1) && m != STATE[AT]) {
      STATE[AT] = m;
      say("b at ");
      hex(m);
      putch('\n');
    }
  }
  say("stuck ");
  hex(REG(MSG_A));
  putch(' ');
  hex(REG(BELL_A));
  putch('\n');
  return 1;
}

int main(void) {
  /* 主频寄存器是 8.8 定点的兆赫 */
  uint32_t hz = (REG(0x10000014) & 0xffff) * 15625 / 4;
  REG(0x1000000c) = hz / 115200;
  say("to2610 amp\n");
  for (int i = 0; i < 11; i++) STATE[i] = 0;
  CSR_W(mtvec, (uint32_t)trap);
  REG(PLIC + 4 * AMP_IRQ) = 1;
  REG(PLIC + 0x200000) = 0;
  REG(PLIC + 0x2000) = 1u << AMP_IRQ;
  CSR_S(mie, 1 << 11);
  CSR_S(mstatus, 1 << 3);

  /* 第二个核还没放开：认得出这一页，门铃没人拉 */
  verdict("ident", REG(AMP) != 0x414d5031 || REG(RUN) != 0, REG(AMP));
  verdict("quiet", REG(BELL_A) != 0 || STATE[COUNT] != 0, REG(BELL_A));

  REG(MSG_B) = 0x1230;
  REG(RUN) = 1;
  uint32_t bad = 0;
  for (uint32_t k = 1; k <= 5; k++) {
    bad |= await(k);
    say("amp got ");
    hex(STATE[LOG + k - 1]);
    putch('\n');
    bad |= STATE[LOG + k - 1] != k;
  }
  /* 最后一句：0xd0e5 打头，低 16 位是这边写的 0x1230 加上五个数的和 15 */
  bad |= await(6);
  verdict("amp", bad || STATE[LOG + 5] != 0xd0e5123f, STATE[LOG + 5]);

  /* 收回去：第二个核回到复位，门铃不再响 */
  REG(RUN) = 0;
  uint32_t n = STATE[COUNT];
  for (volatile uint32_t i = 0; i < 2000; i++) {}
  verdict("stop", STATE[COUNT] != n || REG(BELL_A) != 0, REG(RUN));
  say("done\n");
  for (;;) {}
}
