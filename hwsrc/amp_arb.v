// 两个核共用 KianV 的片上总线。谁举手谁用，一次访问从举手到应答做完才换人；对面在等的时候，刚用完的那个核
// 不能接着再用，两边都在要就一人一次轮着来。
//
// 片上几个外设的应答是把请求打一拍送回来的，请求撤掉之后应答还要高一拍。单核时不要紧，核自己两次访问之间
// 隔着好几拍；两个核轮着用时，后一个一上来就会收到前一个那次访问留下的应答。所以换人之前空三拍等它落下去；
// 对面没在等时同一个核接着用，不必空。
//
// 收回第二个核要等它手上那一次访问做完：访问到一半撤掉请求，SDRAM 那头还会把它做完，应答就落到下一次访问头上。
//
// 没在访问的时候地址、写选通、指令标记都给 0，与单个核空闲时一样。SoC 里外设区的应答是照「上一拍的地址
// 在不在外设区」预先算的：排队的那个核要是把地址漏到总线上，轮到它时第一拍就被当成做完，读回来的是 0。
`default_nettype none
module amp_arb (
    input  wire        clk,
    input  wire        resetn,

    input  wire        a_valid,
    input  wire [ 3:0] a_wstrb,
    input  wire [33:0] a_addr,
    input  wire [31:0] a_wdata,
    input  wire        a_instr,
    output wire        a_ready,
    output wire        a_fault,

    input  wire        b_valid,
    input  wire [ 3:0] b_wstrb,
    input  wire [33:0] b_addr,
    input  wire [31:0] b_wdata,
    input  wire        b_instr,
    output wire        b_ready,
    output wire        b_fault,

    input  wire        b_run,
    output reg         b_go,

    output wire        valid,
    output wire [ 3:0] wstrb,
    output wire [33:0] addr,
    output wire [31:0] wdata,
    output wire        instr,
    input  wire        ready,
    input  wire        fault
);
  reg       busy, own_b, last_b;
  reg [1:0] cool;

  wire can_a = a_valid && (last_b ? cool == 2'd0 : !b_valid);
  wire can_b = b_valid && (last_b ? !a_valid : cool == 2'd0);
  wire sel_b = busy ? own_b : can_b;
  wire act = busy ? (own_b ? b_valid : a_valid) : (can_a || can_b);
  wire done = act && (ready || fault);

  always @(posedge clk) begin
    if (!resetn) begin
      busy   <= 1'b0;
      own_b  <= 1'b0;
      last_b <= 1'b0;
      cool   <= 2'd0;
      b_go   <= 1'b0;
    end else begin
      if (cool != 2'd0) cool <= cool - 2'd1;
      if (done || (busy && !act)) begin
        // 做完了，或者占着的那个核自己撤了请求
        busy   <= 1'b0;
        last_b <= sel_b;
        cool   <= 2'd3;
      end else if (act) begin
        busy  <= 1'b1;
        own_b <= sel_b;
      end

      if (b_run) b_go <= 1'b1;
      else if (!(act && sel_b)) b_go <= 1'b0;
    end
  end

  assign valid   = act;
  assign wstrb   = !act ? 4'h0 : sel_b ? b_wstrb : a_wstrb;
  assign addr    = !act ? 34'h0 : sel_b ? b_addr : a_addr;
  assign wdata   = sel_b ? b_wdata : a_wdata;
  assign instr   = act && (sel_b ? b_instr : a_instr);
  assign a_ready = ready && act && !sel_b;
  assign a_fault = fault && act && !sel_b;
  assign b_ready = ready && act && sel_b;
  assign b_fault = fault && act && sel_b;
endmodule
`default_nettype wire
