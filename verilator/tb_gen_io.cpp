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

int main() {
    Vgen_io_minimal top;
    top.CE = 1;
    top.J3BUT = 0;
    top.PAL = 0;
    top.EXPORT = 1;

    // Inputs are active low. Player 1 is idle; player 2 holds Mode+X+Y+Z.
    top.P1_UP = top.P1_DOWN = top.P1_LEFT = top.P1_RIGHT = 1;
    top.P1_A = top.P1_B = top.P1_C = top.P1_START = 1;
    top.P1_MODE = top.P1_X = top.P1_Y = top.P1_Z = 1;
    top.P2_UP = top.P2_DOWN = top.P2_LEFT = top.P2_RIGHT = 1;
    top.P2_A = top.P2_B = top.P2_C = top.P2_START = 1;
    top.P2_MODE = top.P2_X = top.P2_Y = top.P2_Z = 0;

    top.RESET = 0; tick(top);
    top.RESET = 1; tick(top);
    top.RESET = 0; tick(top);

    // Configure P2 TH as an output, then let the six-button counter idle-reset.
    write_reg(top, 5, 0x40);
    idle(top, 12050);

    int player2 = 0;
    bool saw_extended = false;
    for (int pulse = 0; pulse < 5; pulse++) {
        write_reg(top, 2, 0x00);
        write_reg(top, 2, 0x40);
        player2 = read_reg(top, 2);
        saw_extended |= player2 == 0x70;
    }

    int player1 = read_reg(top, 1);
    std::printf("P1 idle=%02x want=7f\n", player1);
    std::printf("P2 extended phase %s\n", saw_extended ? "seen" : "missing");
    if (player1 != 0x7F || !saw_extended) {
        std::puts("FAILED");
        return 1;
    }
    std::puts("ALL OK");
    return 0;
}
