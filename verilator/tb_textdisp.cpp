// Renders the menu overlay (textdisp.v) to PPM files for visual checks.
// usage: tb_textdisp [frames] [outdir]   (writes overlay_NNN.ppm every 8 frames)
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include "Vtextdisp.h"
#include "verilated.h"

static Vtextdisp *t;

static void tick() {
    t->hclk = 1; t->clk = 1; t->eval();
    t->hclk = 0; t->clk = 0; t->eval();
}

static void reg_write(uint32_t v) {
    t->reg_char_di = v;
    t->reg_char_we = 0xF;
    tick();
    t->reg_char_we = 0;
}

static void text(int col, int row, const char *s) {
    for (; *s && col < 32; s++, col++)
        reg_write(((uint32_t)col << 16) | ((uint32_t)row << 8) | (uint8_t)*s);
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    int frames = argc > 1 ? atoi(argv[1]) : 1;
    std::string out = argc > 2 ? argv[2] : ".";
    t = new Vtextdisp;
    t->x = 0; t->y = 0;

    for (int r = 0; r < 32; r++) text(0, r, "                                ");
    text(4, 0, "GEN THANG");
    text(3, 3, "\x06 Truly Truly Outrageous \x06");
    const char *files[] = {
        "\x01 ..", "\x02 Columns (W) (REV01).md", "\x02 Ecco the Dolphin (USA).md",
        "\x02 Gunstar Heroes (USA).md", "\x02 Sonic the Hedgehog 2.md",
        "\x02 Streets of Rage 2 (USA).md", "\x02 Thunder Force IV (USA).md",
        "\x01 hacks", "\x01 homebrew",
    };
    for (int i = 0; i < 9; i++) text(1, 5 + i, files[i]);
    text(1, 24, "PAGE 1/1");
    text(0, 26, "\x03X/O LOAD  \x05\x03 PAGE  SEL+START");
    reg_write(0x03000000 | 10);                                   // select row 10

    // 256x224 active area, 4 hclk cycles per pixel, then a 200-cycle blank with x = 0
    static uint8_t fb[224][256][3];
    const int LAT = 3;
    int hx[LAT + 1] = {0}, hy[LAT + 1] = {0}, hv[LAT + 1] = {0};
    for (int f = 0; f < frames; f++) {
        for (int y = 0; y < 224; y++) {
            for (int c = 0; c < 256 * 4 + 200; c++) {
                bool act = c < 256 * 4;
                t->x = act ? c / 4 : 0;
                t->y = y;
                tick();
                for (int i = LAT; i > 0; i--) { hx[i] = hx[i - 1]; hy[i] = hy[i - 1]; hv[i] = hv[i - 1]; }
                hx[0] = t->x; hy[0] = y; hv[0] = act;
                if (hv[LAT]) {
                    uint16_t col = t->color;
                    fb[hy[LAT]][hx[LAT]][0] = (col & 31) << 3;
                    fb[hy[LAT]][hx[LAT]][1] = ((col >> 5) & 31) << 3;
                    fb[hy[LAT]][hx[LAT]][2] = ((col >> 10) & 31) << 3;
                }
            }
        }
        if (f % 8 == 7 || frames == 1) {
            char name[512];
            snprintf(name, sizeof name, "%s/overlay_%03d.ppm", out.c_str(), f);
            FILE *fp = fopen(name, "wb");
            fprintf(fp, "P6\n256 224\n255\n");
            fwrite(fb, 1, sizeof fb, fp);
            fclose(fp);
        }
    }
    t->final();
    delete t;
    return 0;
}
