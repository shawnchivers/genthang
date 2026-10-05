// Unit test for genesis_pad.v: models a 6-button pad, a 3-button pad and an empty port.
#include "Vgenesis_pad.h"
#include <cstdio>

// Genesis buttons, active high
enum { UP = 1, DOWN = 2, LEFT = 4, RIGHT = 8, B = 16, C = 32, A = 64, START = 128,
       Z = 256, Y = 512, X = 1024, MODE = 2048 };

struct Pad {
    int kind;                       // 0 none, 3, 6
    int held = 0, phase = 0, idle = 0, th_r = 1;
    int out(int th) {               // active-low lines {TR, TL, D3, D2, D1, D0}
        if (!kind) return 0x3F;
        if (th != th_r) { phase++; idle = 0; th_r = th; }
        if (++idle > 54 * 1500) phase = 0;          // 1.5ms without TH edges: reset
        auto b = [&](int m) { return (held & m) ? 0 : 1; };
        int v;
        if (kind == 6 && phase == 5)                // 3rd TH low
            v = b(A) << 4 | b(START) << 5;
        else if (kind == 6 && phase == 6)           // following TH high
            v = b(Z) | b(Y) << 1 | b(X) << 2 | b(MODE) << 3 | 3 << 4;
        else if (th)
            v = b(UP) | b(DOWN) << 1 | b(LEFT) << 2 | b(RIGHT) << 3 | b(B) << 4 | b(C) << 5;
        else
            v = b(UP) | b(DOWN) << 1 | b(A) << 4 | b(START) << 5;
        return v;
    }
};

// expected: {Z, X, Y, C, Right, Left, Down, Up, Start, Mode, A, B}
static int expect(int kind, int h) {
    if (!kind) return 0;
    int six = kind == 6;
    auto f = [&](int m) { return (h & m) ? 1 : 0; };
    return (six & f(Z)) << 11 | (six & f(X)) << 10 | (six & f(Y)) << 9 | f(C) << 8 |
           f(RIGHT) << 7 | f(LEFT) << 6 | f(DOWN) << 5 | f(UP) << 4 | f(START) << 3 |
           (six & f(MODE)) << 2 | f(A) << 1 | f(B);
}

int main() {
    Vgenesis_pad top;
    int fails = 0;
    const int cases[][2] = {{6, 0}, {6, UP | B | START}, {6, Z | X | MODE | C}, {6, Y | A | LEFT | RIGHT},
                            {3, 0}, {3, DOWN | A | C | START}, {3, Z | MODE | B}, {0, 0}};
    for (auto &c : cases) {
        Pad pad{c[0]};
        pad.held = c[1];
        for (int i = 0; i < 54 * 7000; i++) {      // 7ms: a couple of scans
            top.d = pad.out(top.th);
            top.clk = 1; top.eval();
            top.clk = 0; top.eval();
        }
        int want = expect(c[0], c[1]);
        printf("%d-button held %04x: btns %03x want %03x %s\n", c[0], c[1], top.btns, want,
               top.btns == want ? "ok" : "FAIL");
        fails += top.btns != want;
    }
    printf(fails ? "FAILED\n" : "ALL OK\n");
    return fails != 0;
}
