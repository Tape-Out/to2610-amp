/* 第二个核上的 FreeRTOS：两个任务经一条队列传数，一个按节拍发、一个收了报给第一个核；一个最低优先级的任务不让出。
 * 这个核没有自己的串口，话都经核间那一页说：数写进 MSG_A、拉 BELL_A，等对面清掉门铃再说下一句。
 * 走得通就说明这个核的计时器中断、ecall 让出、抢占，以及两个核共用总线，都对。
 */
#include <stdint.h>
#include <stddef.h>

#include "FreeRTOS.h"
#include "queue.h"
#include "task.h"

#define REG(a) (*(volatile uint32_t *)(a))
#define AMP 0x40040000u
#define BELL_A (AMP + 0x08)
#define MSG_A (AMP + 0x18)
#define MSG_B (AMP + 0x1c)
/* 起步的站：3 调度器起来之前，4 收的那个任务跑起来，5 发的那个任务等到了头三个节拍，6 收的那个任务拿到第一个数 */
#define AT(n) (REG(MSG_A) = 0xb0000000u | (n))

static QueueHandle_t box;
static volatile uint32_t spins;

static void tell(uint32_t v) {
  REG(MSG_A) = v;
  REG(BELL_A) = 1;
  while (REG(BELL_A) & 1) vTaskDelay(1);
}

/* FreeRTOS 不认的异常与中断：原因写成 0xb0f000cc、0xb0f100cc，停住 */
void freertos_risc_v_application_exception_handler(uint32_t cause) {
  REG(MSG_A) = 0xb0f00000u | (cause & 0xff);
  for (;;) {}
}

void freertos_risc_v_application_interrupt_handler(uint32_t cause) {
  REG(MSG_A) = 0xb0f10000u | (cause & 0xff);
  for (;;) {}
}

void rtos_assert(const char *file, int line_no) {
  (void)file;
  REG(MSG_A) = 0xa55e0000u | (line_no & 0xffff);
  REG(BELL_A) = 1;
  for (;;) {}
}

void *memset(void *d, int c, size_t n) {
  for (uint8_t *p = d; n--;) *p++ = c;
  return d;
}

void *memcpy(void *d, const void *s, size_t n) {
  const uint8_t *q = s;
  for (uint8_t *p = d; n--;) *p++ = *q++;
  return d;
}

static void sender(void *arg) {
  (void)arg;
  for (uint32_t i = 1; i <= 5; i++) {
    vTaskDelay(3);
    if (i == 1) AT(5);
    xQueueSend(box, &i, portMAX_DELAY);
  }
  for (;;) vTaskDelay(1000);
}

static void receiver(void *arg) {
  (void)arg;
  uint32_t v, sum = 0;
  AT(4);
  for (int k = 0; k < 5; k++) {
    xQueueReceive(box, &v, portMAX_DELAY);
    if (k == 0) AT(6);
    sum += v;
    tell(v);
  }
  /* 最后一句：第一个核写在 MSG_B 里的数加上五个数的和；低优先级的那个任务这期间被抢占着也转过 */
  tell(0xd0e50000u | (sum == 15 && spins > 0 ? (REG(MSG_B) + sum) & 0xffff : 0xffff));
  for (;;) vTaskDelay(1000);
}

/* 最低优先级，不让出：只有抢占起作用，上面两个才轮得到 */
static void spinner(void *arg) {
  (void)arg;
  for (;;) spins++;
}

int main(void) {
  box = xQueueCreate(4, sizeof(uint32_t));
  xTaskCreate(sender, "send", 256, NULL, 2, NULL);
  xTaskCreate(receiver, "recv", 256, NULL, 3, NULL);
  xTaskCreate(spinner, "spin", 256, NULL, 1, NULL);
  AT(3);
  extern void freertos_risc_v_trap_handler(void);
  __asm__ volatile("csrw mtvec, %0" : : "r"(freertos_risc_v_trap_handler));
  vTaskStartScheduler();
  rtos_assert(__FILE__, __LINE__);
  return 0;
}
