// Unit test for the minimized two-port Genesis I/O block.
#include "Vgen_io_minimal.h"
#include <cstdio>

static void tick(Vgen_io_minimal &top) {
    top.CLK = 0; top.eval();
    top.CLK = 1; top.eval();
    top.CLK = 0; top.eval();
}

static void idle(Vgen_io_minimal &top, int cycles = 1) {
    top.SEL = 0;
    while (cycles--) tick(top);
}

static void write_reg(Vgen_io_minimal &top, int address, int value) {
    top.A = address;
    top.DI = value;
    top.RNW = 0;
    top.SEL = 1;
    tick(top);
    idle(top);
}

static int read_reg(Vgen_io_minimal &top, int address) {
    top.A = address;
    top.RNW = 1;
    top.SEL = 1;
    tick(top);
    int value = top.DO;
    idle(top);
    return value;
}

static int fails = 0;

static void check_read(Vgen_io_minimal &top, int port, int want, const char *phase) {
    int got = read_reg(top, port);
    if (got != want) {
        std::printf("P%d %s: got %02x want %02x\n", port, phase, got, want);
        fails++;
    }
}

static void reset(Vgen_io_minimal &top) {
    top.SEL = 0;
    top.RESET = 1; tick(top);
    top.RESET = 0; tick(top);
}

static void poll_pad(Vgen_io_minimal &top, int port, bool six) {
    int high = port == 1 ? 0x56 : 0x7F;
    int low = port == 1 ? 0x22 : 0x33;
    int extra = port == 1 ? 0x55 : 0x70;
    write_reg(top, port + 3, 0x40);
    write_reg(top, port, 0x40);
    idle(top, 12050);
    check_read(top, port, high, "initial high");
    for (int pulse = 0; pulse < 4; pulse++) {
        write_reg(top, port, 0x00);
        idle(top, 4);
        int want_low = six && pulse == 2 ? low & 0x30 :
                       six && pulse == 3 ? low | 0x0F : low;
        check_read(top, port, want_low, "TH low");
        write_reg(top, port, 0x40);
        idle(top, 4);
        check_read(top, port, six && pulse == 2 ? extra : high, "TH high");
    }
}

int main() {
    Vgen_io_minimal top;
    top.CE = 1;
    top.J3BUT = 0;
    top.PAL = 0;
    top.EXPORT = 1;

    // Asymmetric active-low inputs distinguish the normal and extended phases.
    top.P1_UP = top.P1_DOWN = top.P1_LEFT = top.P1_RIGHT = 1;
    top.P1_A = top.P1_B = top.P1_C = top.P1_START = 1;
    top.P1_MODE = top.P1_X = top.P1_Y = top.P1_Z = 1;
    top.P1_UP = top.P1_RIGHT = top.P1_A = top.P1_C = top.P1_MODE = top.P1_Y = 0;
    top.P2_UP = top.P2_DOWN = top.P2_LEFT = top.P2_RIGHT = 1;
    top.P2_A = top.P2_B = top.P2_C = top.P2_START = 1;
    top.P2_MODE = top.P2_X = top.P2_Y = top.P2_Z = 0;

    for (int types = 0; types < 4; types++) {
        top.PAD_SIX_BUTTON = types;
        reset(top);
        poll_pad(top, 1, types & 1);
        poll_pad(top, 2, types & 2);
    }
    top.PAD_SIX_BUTTON = 3;
    top.J3BUT = 1;
    reset(top);
    poll_pad(top, 1, false);
    poll_pad(top, 2, false);

    top.J3BUT = 0;
    reset(top);
    write_reg(top, 4, 0x40);
    idle(top, 12050);
    for (int pulse = 0; pulse < 3; pulse++) {
        write_reg(top, 1, 0x00);
        idle(top, 4);
        write_reg(top, 1, 0x40);
        idle(top, 4);
    }
    check_read(top, 1, 0x55, "six-button extended");
    idle(top, 11500);
    check_read(top, 1, 0x55, "extended before timeout");
    idle(top, 200);
    check_read(top, 1, 0x56, "normal after timeout");
    idle(top, 150000);
    check_read(top, 1, 0x56, "normal after prolonged idle");
    for (int pulse = 0; pulse < 3; pulse++) {
        write_reg(top, 1, 0x00);
        idle(top, 4);
        write_reg(top, 1, 0x40);
        idle(top, 4);
    }
    check_read(top, 1, 0x55, "six-button extended after timeout");
    top.PAD_SIX_BUTTON = 2;
    check_read(top, 1, 0x56, "changed to three-button while TH high");
    write_reg(top, 1, 0x00);
    idle(top, 4);
    check_read(top, 1, 0x22, "three-button low after type change");
    poll_pad(top, 2, true);
    top.PAD_SIX_BUTTON = 3;
    poll_pad(top, 1, true);

    write_reg(top, 1, 0x00);
    idle(top, 4);
    write_reg(top, 4, 0x00);
    idle(top, 100);
    check_read(top, 1, 0x22, "floating TH before filter expiry");
    idle(top, 200);
    check_read(top, 1, 0x56, "floating TH after filter expiry");
    idle(top, 512);
    check_read(top, 1, 0x56, "floating TH after filter timer wraps");
    write_reg(top, 4, 0x40);
    idle(top, 4);
    check_read(top, 1, 0x22, "driving TH after floating");
    write_reg(top, 4, 0x00);
    idle(top, 220);
    check_read(top, 1, 0x56, "floating TH filter restarted");

    std::puts(fails ? "FAILED" : "ALL OK: three/six-button pairs, timeout, overrides and live type changes");
    return fails != 0;
}
