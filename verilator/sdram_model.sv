// Behavioural model of the Nano 20K embedded SDRAM (2M x 32, 4 banks, CL2, BL1)
// for the cycle-based Verilator testbench.
//
// The controller registers commands on edge e; the chip (clocked ~315 deg later)
// acts on them before edge e+1, so this model samples them at posedge e+1.
// READ data is visible only between controller edges r+2 and r+3, so a controller
// that samples at any other edge reads garbage. Timing violations are counted.
module sdram_model #(
    parameter real T_NS      = 18.52,
    parameter      ROM_HEX   = "rom32.hex",
    parameter      ROM_BYTES = 2097152,
    parameter      PRELOAD   = 1        // 0: ROM must be written by the design
) (
    input             clk,
    input       [3:0] cmd,          // {nCS, nRAS, nCAS, nWE}
    input      [10:0] a,
    input       [1:0] ba,
    input       [3:0] dqm,
    input      [31:0] dq_out,
    input             dq_oe,
    output     [31:0] dq_in,

    output reg [31:0] errors,
    output reg [31:0] rom_writes_checked,
    output reg [31:0] refreshes,
    output reg [31:0] max_refresh_gap_cycles
);

localparam CMD_NOP = 4'b0111, CMD_ACT = 4'b0011, CMD_READ = 4'b0101, CMD_WRITE = 4'b0100,
           CMD_PRE = 4'b0010, CMD_REFRESH = 4'b0001, CMD_MRS = 4'b0000;

localparam real T_RCD = 18.0, T_RP = 18.0, T_RAS = 42.0, T_RC = 60.0, T_RRD = 12.0, T_RFC = 63.0;
localparam real T_REFI_MAX = 15600.0;  // 4096 refreshes / 64ms

reg [31:0] mem [0:2097151];
reg [31:0] rom_shadow [0:ROM_BYTES/4-1];

reg        active   [0:3];
reg [10:0] row      [0:3];
real       act_ns   [0:3];
real       idle_ns  [0:3];
real       last_act_any, refresh_done, mrs_ns, last_refresh_ns;
reg        mode_ok;
reg        init_pre_seen;
longint    k;

reg        rd_sched, drive, drive_d;
reg [31:0] rd_sched_data, drive_data;

assign dq_in = drive ? drive_data : 32'hBAD0BAD0;

integer i;
initial begin
    for (i = 0; i < 2097152; i = i + 1)
        mem[i] = i * 32'h9E3779B1 ^ 32'h5A5AA5A5;      // pseudo-random power-up contents
    $readmemh(ROM_HEX, rom_shadow);
    if (PRELOAD)
        for (i = 0; i < ROM_BYTES / 4; i = i + 1)
            mem[i] = rom_shadow[i];                 // ROM preloaded (backdoor)
    for (i = 0; i < 4; i = i + 1) begin
        active[i] = 1'b0;
        idle_ns[i] = 0.0;
        act_ns[i] = -1000.0;
    end
    last_act_any = -1000.0;
    refresh_done = 0.0;
    mrs_ns = -1000.0;
    last_refresh_ns = -1.0;
    mode_ok = 1'b0;
    init_pre_seen = 1'b0;
    errors = 0;
    rom_writes_checked = 0;
    refreshes = 0;
    max_refresh_gap_cycles = 0;
    k = 0;
    rd_sched = 1'b0;
    drive = 1'b0;
    drive_d = 1'b0;
end

task automatic err(input string msg);
    errors = errors + 1;
    if (errors <= 30)
        $display("SDRAM ERROR @cycle %0d (%0.1f ns): %s", k, k * T_NS, msg);
endtask

real now;
reg [20:0] waddr;
reg [31:0] wdata, merged;
always @(posedge clk) begin
    k = k + 1;
    now = k * T_NS;

    // data bus: controller must not drive while the chip drives (incl. hold tail)
    if (dq_oe && (drive || drive_d))
        err("DQ bus contention (controller drives during read data)");
    drive_d <= drive;
    drive <= rd_sched;
    drive_data <= rd_sched_data;
    rd_sched <= 1'b0;

    if (cmd != CMD_NOP && cmd[3] == 1'b0 && now < mrs_ns + 2.0 * T_NS && cmd != CMD_MRS)
        err("command within tMRD of MRS");

    case (cmd)
    CMD_ACT: begin
        if (!mode_ok) err("ACT before mode register set");
        if (active[ba]) err($sformatf("ACT to active bank %0d", ba));
        if (now < idle_ns[ba]) err($sformatf("ACT bank %0d before precharge done (tRP/tRAS/tWR) by %0.1fns", ba, idle_ns[ba] - now));
        if (now - act_ns[ba] < T_RC) err($sformatf("tRC violation bank %0d (%0.1fns)", ba, now - act_ns[ba]));
        if (now - last_act_any < T_RRD) err("tRRD violation");
        if (now < refresh_done) err("ACT within tRFC");
        active[ba] = 1'b1;
        row[ba] = a;
        act_ns[ba] = now;
        last_act_any = now;
    end
    CMD_READ, CMD_WRITE: begin
        if (!active[ba]) err($sformatf("%s to idle bank %0d", cmd == CMD_READ ? "READ" : "WRITE", ba));
        if (now - act_ns[ba] < T_RCD) err("tRCD violation");
        waddr = {ba, row[ba], a[7:0]};
        if (cmd == CMD_READ) begin
            if (dqm != 4'b0000) err("READ with DQM masked (controller expects full word)");
            rd_sched <= 1'b1;
            rd_sched_data <= mem[waddr];
            if (a[10]) idle_ns[ba] = ((now + T_NS > act_ns[ba] + T_RAS) ? now + T_NS : act_ns[ba] + T_RAS) + T_RP;
        end else begin
            if (!dq_oe) err("WRITE without controller driving DQ");
            wdata = dq_out;
            merged = mem[waddr];
            for (int b = 0; b < 4; b++)
                if (!dqm[b]) merged[b*8 +: 8] = wdata[b*8 +: 8];
            if ({waddr, 2'b00} < ROM_BYTES) begin
                if (merged != rom_shadow[waddr]) begin
                    err($sformatf("ROM write mismatch at byte %06h: wrote %08h expected %08h (dqm %b)",
                                  {waddr, 2'b00}, merged, rom_shadow[waddr], dqm));
                end
                rom_writes_checked = rom_writes_checked + 1;
            end
            mem[waddr] = merged;
            if (a[10]) idle_ns[ba] = ((now + 2.0 * T_NS > act_ns[ba] + T_RAS) ? now + 2.0 * T_NS : act_ns[ba] + T_RAS) + T_RP;
        end
        if (a[10]) active[ba] = 1'b0;
    end
    CMD_PRE: begin
        if (!init_pre_seen && now < 100000.0) err("first PRECHARGE before 100us power-up wait");
        init_pre_seen = 1'b1;
        for (int b = 0; b < 4; b++)
            if (a[10] || b == ba) begin
                if (active[b] && now - act_ns[b] < T_RAS) err("tRAS violation on PRECHARGE");
                active[b] = 1'b0;
                idle_ns[b] = now + T_RP;
            end
    end
    CMD_REFRESH: begin
        for (int b = 0; b < 4; b++) begin
            if (active[b]) err("REFRESH with an active bank");
            if (now < idle_ns[b]) err("REFRESH before bank precharge done");
        end
        if (now < refresh_done) err("REFRESH within tRFC");
        refresh_done = now + T_RFC;
        if (mode_ok) begin
            if (last_refresh_ns >= 0.0 && now - last_refresh_ns > T_REFI_MAX)
                err($sformatf("refresh gap %0.1fus too long", (now - last_refresh_ns) / 1000.0));
            if (last_refresh_ns >= 0.0 && (now - last_refresh_ns) / T_NS > max_refresh_gap_cycles)
                max_refresh_gap_cycles = int'((now - last_refresh_ns) / T_NS);
            last_refresh_ns = now;
            refreshes = refreshes + 1;
        end
    end
    CMD_MRS: begin
        for (int b = 0; b < 4; b++)
            if (active[b] || now < idle_ns[b]) err("MRS with a non-idle bank");
        if (a[6:4] != 3'b010 || a[2:0] != 3'b000 || a[3] != 1'b0) err($sformatf("unexpected mode register %011b", a));
        mode_ok = 1'b1;
        mrs_ns = now;
    end
    default:
        if (cmd[3] == 1'b0 && cmd != CMD_NOP) err($sformatf("unsupported command %b", cmd));
    endcase
end

endmodule
