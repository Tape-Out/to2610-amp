# to2610-amp

An asymmetric two-core chip for the ECOS 2610 shuttle: [`to2610-kvc`](https://github.com/Tape-Out/to2610-kvc) with a second KianV core that runs an RTOS beside Linux, sharing the bus through an arbiter and talking through a page of doorbells.

![maturity](https://img.shields.io/badge/maturity-simulated-yellow) ![license](https://img.shields.io/badge/license-MIT%20OR%20Apache--2.0%20OR%20MulanPSL--2.0-blue)

The core is upstream's KianV, its submodule untouched, taken from [`gf180mcu-kianv-rv32ima-sv32`](https://github.com/Tape-Out/gf180mcu-kianv-rv32ima-sv32); the peripherals and the pads are those of `to2610-kvc`. What this repository adds:

| File | What |
|:--:|:--:|
| `patch/amp.patch` | a second core in `soc.v`, reset to `0x2000_0000`, with its own CLINT at `0x0300_0000` |
| `hwsrc/amp_arb.v` | the arbiter: one access at a time, turns taken when both cores ask, three idle cycles before the bus changes hands |
| `hwsrc/amp_ctl.v` | the inter-core page at `0x4004_0000`: `RUN`, a doorbell and a word in each direction |

The functions, the registers, the pad table, the tests and the limits are in [`docs/流片说明.md`](docs/流片说明.md); the tape-out report is generated from that file.

## The two cores

Only the first core runs after reset, and until `RUN` is written the chip behaves as `to2610-kvc` does. Writing 1 to `0x4004_0004` releases the second core. It starts in the flash at `0x2000_0000`, in the megabyte the boot loader leaves free; fetching from the flash is too slow for a tick interrupt, so its image begins by copying itself to the top megabyte of the SDRAM.

The second core has no UART. It writes a word to `MSG_A` and rings `BELL_A`, which reaches the first core as PLIC source 26; `MSG_B` and `BELL_B` go the other way, the bell arriving as the second core's machine external interrupt.

The cores share the memory and the peripherals but not the atomics: each core's `mhartid` reads 0 and a reservation lives inside one core. For two cores contending on locks see [`to2610-smp`](https://github.com/Tape-Out/to2610-smp).

## Testing and tape-out

```console
$ ran run to2610-amp src                  # assemble build/src
$ ran test to2610-amp                     # the chip tests, on the Verilog file that goes to the shuttle
$ ran asic to2610-amp                     # to2610_amp.v, ecc at 50 MHz, report.json
```

The chip tests run on Verilator with pin-level models of the SDRAM, the flash and the UART: the tests of `to2610-kvc` unchanged, then `htest/amp`, where FreeRTOS on the second core passes five numbers through a queue and reports each to the first core by doorbell. On its way up the second core posts where it has got to, and the first core prints it.

## License

任选其一：

- [MIT](LICENSE-MIT)
- [Apache 2.0](LICENSE-APACHE)
- [木兰宽松许可证 第2版](LICENSE-MULAN)

`SPDX-License-Identifier: MIT OR Apache-2.0 OR MulanPSL-2.0`

The upstream sources keep their own licence: Apache-2.0.

除非另行说明，你提交的贡献按上述三者同时授权，不附加其他条件。
