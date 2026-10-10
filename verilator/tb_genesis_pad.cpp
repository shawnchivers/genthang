// Unit test for genesis_pad.v: models 6-button pads with different TH reset timeouts, a
// 3-button pad and an empty port, and checks that held buttons read steadily over many scans.
#include "Vgenesis_pad.h"
#include <cstdio>
#include <cstdlib>

static const int CLK_PER_US = 54;

// Genesis buttons, active high
enum { UP = 1, DOWN = 2, LEFT = 4, RIGHT = 8, B = 16, C = 32, A = 64, START = 128,
       Z = 256, Y = 512, X = 1024, MODE = 2048 };

struct Pad {
    int kind;                       // 0 none, 3, 6
    int timeout_us = 1500;          // TH idle time after which a 6-button pad resets its counter
    int jitter_us = 0;              // the timeout varies by up to this much per idle period
    bool wrap = false;              // counter wraps after four TH pulses instead of saturating
    int held = 0, phase = 0, idle = 0, th_r = 1, limit = 0;
    void new_limit() { limit = (timeout_us + (jitter_us ? rand() % (2 * jitter_us + 1) - jitter_us : 0)) * CLK_PER_US; }
    int out(int th) {               // active-low lines {TR, TL, D3, D2, D1, D0}
        if (!kind) return 0x3F;
        if (th != th_r) {
            phase = wrap ? (phase + 1) % 8 : phase + 1;
            idle = 0; th_r = th; new_limit();
        }
        if (++idle > limit) phase = 0;
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

// Run for ms milliseconds; the output must reach want within settle_ms and then never change.
static bool hold(Vgenesis_pad &top, Pad &pad, int ms, int settle_ms, int want, int &glitches) {
    long settled = -1;
    glitches = 0;
    int last = top.btns;
    for (long i = 0; i < (long)ms * 1000 * CLK_PER_US; i++) {
        top.d = pad.out(top.th);
        top.clk = 1; top.eval();
        top.clk = 0; top.eval();
        if (top.btns != last) {
            last = top.btns;
            if (settled >= 0) glitches++;
        }
        if (settled < 0 && top.btns == want) settled = i;
    }
    return settled >= 0 && settled <= (long)settle_ms * 1000 * CLK_PER_US && glitches == 0 && top.btns == want;
}

int main() {
    srand(1);
    int fails = 0;
    struct Case { int kind, timeout_us, jitter_us; bool wrap; };
    const Case pads[] = {{6, 1000, 0, false}, {6, 1500, 0, false}, {6, 2050, 150, false}, {6, 3000, 0, false},
                         {6, 6000, 500, false}, {6, 12000, 1000, false}, {6, 12000, 0, true},
                         {3, 0, 0, false}, {0, 0, 0, false}};
    const int helds[] = {0, UP | B | START, Z | X | MODE | C, Y | A | LEFT | RIGHT, X, Y, Z};
    for (auto &p : pads) {
        for (int h : helds) {
            Vgenesis_pad top;
            top.eval();                                 // th starts high
            Pad pad{p.kind};
            pad.timeout_us = p.timeout_us; pad.jitter_us = p.jitter_us; pad.wrap = p.wrap;
            pad.new_limit();
            int g1, g2, g3;
            pad.held = h;                               // hold from power-up
            bool ok = hold(top, pad, 150, 40, expect(p.kind, h), g1);
            pad.held = 0;                               // release
            ok &= hold(top, pad, 80, 40, 0, g2);
            pad.held = h;                               // press again while the pad is being polled
            ok &= hold(top, pad, 150, 40, expect(p.kind, h), g3);
            printf("%d-button timeout %5dus+-%4dus%s held %04x: btns %03x want %03x glitches %d/%d/%d %s\n",
                   p.kind, p.timeout_us, p.jitter_us, p.wrap ? " wrap" : "     ", h, top.btns,
                   expect(p.kind, h), g1, g2, g3, ok ? "ok" : "FAIL");
            fails += !ok;
        }
    }
    printf(fails ? "FAILED\n" : "ALL OK\n");
    return fails != 0;
}
