// 两个核之间的那点东西，挂在 KianV 的片上总线上，地址 0x4004_0000 起一页，两个核都看得见。
//   0x00 ID      只读，0x414D5031（"AMP1"）
//   0x04 RUN     第 0 位：放开第二个核的复位。复位为 0，第二个核不动，整颗与单核的那一颗一样
//   0x08 BELL_A  给第一个核的门铃：写 1 的位置起，读回挂着的；挂着就向 PLIC 报中断
//   0x0C ACK_A   写 1 的位把 BELL_A 清掉
//   0x10 BELL_B  给第二个核的门铃，接它的机器态外部中断
//   0x14 ACK_B   写 1 的位把 BELL_B 清掉
//   0x18 MSG_A   第二个核写给第一个核的一个字
//   0x1C MSG_B   第一个核写给第二个核的一个字
`default_nettype none
module amp_ctl (
    input  wire        clk,
    input  wire        resetn,
    input  wire        bus_valid_i,
    input  wire [31:0] bus_addr_i,
    input  wire [ 3:0] bus_wstrb_i,
    input  wire [31:0] bus_wdata_i,
    output reg  [31:0] bus_rdata_o,
    output reg         bus_ready_o,
    output reg         run,
    output wire        irq_a,
    output wire        irq_b
);
  reg  [ 7:0] bell_a, bell_b;
  reg  [31:0] msg_a, msg_b;
  wire [ 2:0] sel = bus_addr_i[4:2];
  // 应答的那一拍请求还顶着，不能当成下一次
  wire        go = bus_valid_i && !bus_ready_o;
  wire [31:0] wd = bus_wdata_i;

  always @(posedge clk) begin
    if (!resetn) begin
      run         <= 1'b0;
      bell_a      <= 8'h00;
      bell_b      <= 8'h00;
      msg_a       <= 32'h0;
      msg_b       <= 32'h0;
      bus_ready_o <= 1'b0;
      bus_rdata_o <= 32'h0;
    end else begin
      bus_ready_o <= go;
      if (go) begin
        bus_rdata_o <= sel == 3'd0 ? 32'h414D_5031 :
                       sel == 3'd1 ? {31'h0, run} :
                       sel == 3'd2 || sel == 3'd3 ? {24'h0, bell_a} :
                       sel == 3'd4 || sel == 3'd5 ? {24'h0, bell_b} :
                       sel == 3'd6 ? msg_a : msg_b;
        if (|bus_wstrb_i)
          case (sel)
            3'd1: run <= wd[0];
            3'd2: bell_a <= bell_a | wd[7:0];
            3'd3: bell_a <= bell_a & ~wd[7:0];
            3'd4: bell_b <= bell_b | wd[7:0];
            3'd5: bell_b <= bell_b & ~wd[7:0];
            3'd6: msg_a <= wd;
            3'd7: msg_b <= wd;
            default: ;
          endcase
      end
    end
  end

  assign irq_a = |bell_a;
  assign irq_b = |bell_b;
endmodule
`default_nettype wire
