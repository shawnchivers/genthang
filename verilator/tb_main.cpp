// Headless Verilator driver shared by tb_ref (golden) and tb_dut (Nano build).
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <string>
#include <vector>
#include <set>
#include <map>
#include <algorithm>
#include "verilated.h"
#include TOP_HEADER

#ifdef IS_DUT
// TF card image for sd_card_model (DPI)
#include "svdpi.h"
static std::vector<uint8_t> sd_img;
extern "C" int sd_img_read(int addr) {
    return (addr >= 0 && (size_t)addr < sd_img.size()) ? sd_img[addr] : 0;
}
extern "C" void sd_img_write(int addr, int data) {
    if (addr >= 0 && (size_t)addr < sd_img.size()) sd_img[addr] = data;
}
#endif

struct Press { int start, len, mask; };

static void usage() {
    printf("usage: tb [-n frames] [-o outdir] [-d f1,f2,...] [-p frame:len:mask]...\n"
           "          [-t ms:len_ms:mask]... [-T max_ms] [-s sd.img] [-O ms,...]   (last four: tb_dut only)\n"
           "  -p frames count from md_on, -t is absolute simulated time, -P ms:len_ms:mask from md_on\n"
           "  -O dumps the menu overlay (overlay_<ms>.ppm) after each time\n"
           "  mask bits: 0 right 1 left 2 down 3 up 4 A 5 B 6 C 7 Start, dut: 8 Select 9 L1 10 R1 11 Triangle\n");
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    int nframes = 60;
    std::string out = ".";
    std::set<int> dumps;
    std::vector<Press> presses;
    std::vector<Press> tpresses;
    std::vector<Press> rpresses;                // -P: ms from md_on
    int max_ms = 0;
    std::string sd_path = "sd.img";
    std::vector<int> ovl_dumps;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "-n") && i + 1 < argc) nframes = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-o") && i + 1 < argc) out = argv[++i];
        else if (!strcmp(argv[i], "-d") && i + 1 < argc) {
            char *s = argv[++i];
            for (char *t = strtok(s, ","); t; t = strtok(nullptr, ",")) dumps.insert(atoi(t));
        } else if (!strcmp(argv[i], "-p") && i + 1 < argc) {
            Press p;
            if (sscanf(argv[++i], "%d:%d:%i", &p.start, &p.len, &p.mask) == 3) presses.push_back(p);
        } else if (!strcmp(argv[i], "-t") && i + 1 < argc) {
            Press p;
            if (sscanf(argv[++i], "%d:%d:%i", &p.start, &p.len, &p.mask) == 3) tpresses.push_back(p);
        } else if (!strcmp(argv[i], "-P") && i + 1 < argc) {
            Press p;
            if (sscanf(argv[++i], "%d:%d:%i", &p.start, &p.len, &p.mask) == 3) rpresses.push_back(p);
        } else if (!strcmp(argv[i], "-T") && i + 1 < argc) max_ms = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-s") && i + 1 < argc) sd_path = argv[++i];
        else if (!strcmp(argv[i], "-O") && i + 1 < argc) {
            char *s = argv[++i];
            for (char *t = strtok(s, ","); t; t = strtok(nullptr, ",")) ovl_dumps.push_back(atoi(t));
        }
        else if (argv[i][0] == '-' && argv[i][1] != '+') { usage(); return 1; }
    }

#ifdef IS_DUT
    if (FILE *f = fopen(sd_path.c_str(), "rb")) {
        fseek(f, 0, SEEK_END);
        sd_img.resize(ftell(f));
        fseek(f, 0, SEEK_SET);
        if (fread(sd_img.data(), 1, sd_img.size(), f) != sd_img.size()) sd_img.clear();
        fclose(f);
        printf("TF card image %s: %zu bytes\n", sd_path.c_str(), sd_img.size());
    } else
        printf("no TF card image %s\n", sd_path.c_str());
    // firmware UART: 115200 baud from the 27MHz iosys clock, divider 234
    const int UART_BIT = 234 * 2;
    int uart_cnt = 0, uart_bit = -1, uart_byte = 0;
    std::string uart_line;
    int overlay_r = -1, loading_r = -1;
    // overlay scan: 256 pixels x 4 cycles + 200 blank cycles per line, 224 lines
    static uint8_t ovl[224][256][3];
    const int OVL_LINE = 256 * 4 + 200, OVL_LAT = 3;
    int ovl_c = 0, ovl_y = 0, ovl_hx[OVL_LAT + 1] = {0}, ovl_hy[OVL_LAT + 1] = {0}, ovl_hv[OVL_LAT + 1] = {0};
    size_t ovl_next = 0;
    std::sort(ovl_dumps.begin(), ovl_dumps.end());
#endif

    TOP_CLASS *top = new TOP_CLASS;
    static uint8_t fb[240][320][3];
    FILE *aud = fopen((out + "/audio.raw").c_str(), "wb");
    FILE *hashes = fopen((out + "/hashes.txt").c_str(), "w");

    top->clk_sys = 0; top->clk_z80 = 0; top->btn_n = 0xFF;
    uint64_t cycles = 0, frame_start = 0, on_cycle = 0;
    int px = 0, py = 0, frame = 0, hblank_r = 0, cepix_r = 0, vblank_r = 0;
    bool hs_seen = false, on = false;
    long long aud_n = 0, aud_nz = 0;
    long long menu_aud_n = 0, menu_aud_nz = 0;
    int aud_min = 0, aud_max = 0;
    const uint64_t AUD_DIV = 54000000 / 48000;   // samples at 48kHz of clk_sys
#ifdef HAS_DBG
    std::map<uint32_t, uint32_t> pc_hist;
    uint32_t last_a = 0;
#endif

    while (frame < nframes && !Verilated::gotFinish()) {
        // one clk_sys period; clk_z80 toggles on clk_sys falling edges
        top->clk_sys = 1; top->eval();
        top->clk_z80 = !top->clk_z80; top->clk_sys = 0; top->eval();
        cycles++;
        double ms = cycles / 54e3;

        int btn = 0;
        for (auto &p : tpresses) if (ms >= p.start && ms < p.start + p.len) btn |= p.mask;
        if (on)
            for (auto &p : presses) if (frame >= p.start && frame < p.start + p.len) btn |= p.mask;
        if (on) {
            double rms = (cycles - on_cycle) / 54e3;
            for (auto &p : rpresses) if (rms >= p.start && rms < p.start + p.len) btn |= p.mask;
        }
        top->btn_n = ~btn & 0xFF;
#ifdef IS_DUT
        top->btn_x_n = ~(btn >> 8) & 15;
#endif
        if (max_ms && ms > max_ms) { printf("time limit %d ms reached\n", max_ms); break; }

#ifdef IS_DUT
        if (uart_bit < 0) {
            if (!top->uart_tx) { uart_bit = 0; uart_cnt = UART_BIT * 3 / 2; uart_byte = 0; }
        } else if (--uart_cnt == 0) {
            if (uart_bit < 8) {
                uart_byte |= top->uart_tx << uart_bit;
                uart_bit++;
                uart_cnt = UART_BIT;
            } else {
                uart_bit = -1;
                if (uart_byte == '\n') {
                    printf("[%8.1f ms] uart: %s\n", ms, uart_line.c_str());
                    fflush(stdout);
                    uart_line.clear();
                } else if (uart_byte != '\r')
                    uart_line += (char)uart_byte;
            }
        }
        if (top->overlay != overlay_r || top->loading != loading_r) {
            printf("[%8.1f ms] overlay %d loading %d md_on %d\n", ms, top->overlay, top->loading, top->md_on);
            fflush(stdout);
            overlay_r = top->overlay;
            loading_r = top->loading;
        }

        // the scan for this cycle was applied before the clock edge above
        for (int k = OVL_LAT; k > 0; k--) {
            ovl_hx[k] = ovl_hx[k - 1]; ovl_hy[k] = ovl_hy[k - 1]; ovl_hv[k] = ovl_hv[k - 1];
        }
        ovl_hx[0] = top->overlay_x; ovl_hy[0] = top->overlay_y; ovl_hv[0] = ovl_c < 1024;
        if (ovl_hv[OVL_LAT]) {
            uint16_t c = top->overlay_color;
            uint8_t *p = ovl[ovl_hy[OVL_LAT]][ovl_hx[OVL_LAT]];
            p[0] = (c & 31) << 3; p[1] = ((c >> 5) & 31) << 3; p[2] = ((c >> 10) & 31) << 3;
        }
        if (++ovl_c == OVL_LINE) {
            ovl_c = 0;
            if (++ovl_y == 224) {
                ovl_y = 0;
                if (ovl_next < ovl_dumps.size() && ms >= ovl_dumps[ovl_next]) {
                    char name[512];
                    snprintf(name, sizeof name, "%s/overlay_%d.ppm", out.c_str(), ovl_dumps[ovl_next]);
                    FILE *f = fopen(name, "wb");
                    fprintf(f, "P6\n256 224\n255\n");
                    fwrite(ovl, 1, sizeof ovl, f);
                    fclose(f);
                    printf("[%8.1f ms] wrote %s\n", ms, name);
                    ovl_next++;
                }
            }
        }
        top->overlay_x = ovl_c < 1024 ? ovl_c / 4 : 0;
        top->overlay_y = ovl_y;
#endif

        if (!on && top->md_on) {
            on = true; on_cycle = cycles; frame_start = cycles;
            printf("md_on at cycle %llu (%.3f s)\n", (unsigned long long)cycles, cycles / 54e6);
            fflush(stdout);
        }
        static int md_on_r = 0;
        if (on && top->md_on && !md_on_r)
            printf("game started at frame %d (%.3f s)\n", frame, cycles / 54e6);
        md_on_r = top->md_on;
        if (!on) {
            if (cycles % 20000000 == 0) { printf("  loading... cycle %llu\n", (unsigned long long)cycles); fflush(stdout); }
            continue;
        }

        if ((cycles - on_cycle) % AUD_DIV == 0) {
            int16_t l = (int16_t)top->audio_left, r = (int16_t)top->audio_right;
            fwrite(&l, 2, 1, aud); fwrite(&r, 2, 1, aud);
            aud_n++;
            if (l || r) aud_nz++;
#ifdef IS_DUT
            if (top->md_on && top->overlay) {
                menu_aud_n++;
                if (l || r) menu_aud_nz++;
            }
#endif
            if (l < aud_min) aud_min = l;
            if (l > aud_max) aud_max = l;
        }

        if (top->vblank) { py = 0; hs_seen = false; }
        if (top->hsync) hs_seen = true;
        if (hs_seen && top->hblank) {
            px = 0;
            if (!hblank_r) py++;
        }
        hblank_r = top->hblank;
        if (hs_seen && top->ce_pix && !cepix_r && !top->hblank && !top->vblank && px < 320 && py < 240 && py > 0) {
            fb[py - 1][px][0] = top->red << 4;
            fb[py - 1][px][1] = top->green << 4;
            fb[py - 1][px][2] = top->blue << 4;
            px++;
        }
        cepix_r = top->ce_pix;
#ifdef HAS_DBG
        if (top->dbg_m68k_a != last_a) { last_a = top->dbg_m68k_a; pc_hist[last_a]++; }
#endif

        if (top->vblank && !vblank_r) {
#ifdef HAS_DBG
            if (frame % 10 == 0) {
                std::vector<std::pair<uint32_t,uint32_t>> v;
                for (auto &kv : pc_hist) v.push_back({kv.second, kv.first});
                std::sort(v.rbegin(), v.rend());
                printf("  68K hot addrs:");
                for (size_t i = 0; i < v.size() && i < 8; i++) printf(" %06x(%u)", v[i].second, v[i].first);
                printf("\n");
            }
            pc_hist.clear();
#endif
            int w = (top->resolution & 1) ? 320 : 256, h = (top->resolution & 2) ? 240 : 224;
            uint64_t hsh = 1469598103934665603ULL;
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                    for (int c = 0; c < 3; c++) { hsh ^= fb[y][x][c]; hsh *= 1099511628211ULL; }
            fprintf(hashes, "%d %016llx %llu\n", frame, (unsigned long long)hsh,
                    (unsigned long long)(cycles - frame_start));
            if (dumps.count(frame)) {
                char name[256];
                snprintf(name, sizeof name, "%s/frame%04d.ppm", out.c_str(), frame);
                FILE *f = fopen(name, "wb");
                fprintf(f, "P6\n%d %d\n255\n", w, h);
                for (int y = 0; y < h; y++) fwrite(fb[y], 3, w, f);
                fclose(f);
            }
            if (frame % 10 == 0) {
                printf("frame %4d  %7llu cyc  hash %016llx  audio nz %lld/%lld [%d..%d]  sdram_err %u flash_err %u\n",
                       frame, (unsigned long long)(cycles - frame_start), (unsigned long long)hsh,
                       aud_nz, aud_n, aud_min, aud_max, top->sdram_errors, top->flash_errors);
                fflush(stdout);
            }
            frame++;
            frame_start = cycles;
            memset(fb, 0, sizeof fb);
        }
        vblank_r = top->vblank;
    }

    printf("DONE frames=%d cycles=%llu sdram_errors=%u flash_errors=%u rom_words_checked=%u refreshes=%u max_refresh_gap=%u cyc audio_nonzero=%lld/%lld\n",
           frame, (unsigned long long)cycles, top->sdram_errors, top->flash_errors,
           top->rom_writes_checked, top->refreshes, top->max_refresh_gap, aud_nz, aud_n);
#ifdef IS_DUT
    printf("TF card: blocks_read=%u errors=%u\n", top->sd_blocks_read, top->sd_errors);
    printf("menu audio: nonzero=%lld/%lld\n", menu_aud_nz, menu_aud_n);
    if (FILE *f = fopen((out + "/sd_out.img").c_str(), "wb")) {    // card after the firmware's writes
        fwrite(sd_img.data(), 1, sd_img.size(), f);
        fclose(f);
    }
#endif
    fclose(aud); fclose(hashes);
    top->final();
    delete top;
#ifdef IS_DUT
    if (menu_aud_nz) return 2;
#endif
    return 0;
}
