#include <assert.h>
#include <stdio.h>
#include <strings.h>
#include "../firmware/picorv32.h"

static uint32_t display_reg, applied_video;
static char screen[28][33];

static volatile uint32_t *display_write(void) {
    unsigned col = (display_reg >> 16) & 255;
    unsigned row = (display_reg >> 8) & 255;
    if (!(display_reg >> 24) && col < 32 && row < 28)
        screen[row][col] = display_reg & 255;
    if ((display_reg >> 16) == 0x0301)
        applied_video = display_reg & 0xFFFF;
    return &display_reg;
}

#undef reg_textdisp
#define reg_textdisp (*display_write())
#define main firmware_main
#include "../firmware/firmware.c"
#undef main

static char config[2048];
static unsigned config_size, config_pos;
static bool short_write;

int sd_init(void) { return 0; }

FRESULT f_open(FIL *fp, const TCHAR *path, BYTE mode) {
    (void)fp;
    assert(strcmp(path, CFG_PATH) == 0);
    config_pos = 0;
    if (mode & FA_CREATE_ALWAYS) config_size = 0;
    return FR_OK;
}

FRESULT f_close(FIL *fp) {
    (void)fp;
    return FR_OK;
}

FRESULT f_read(FIL *fp, void *buff, UINT count, UINT *read_count) {
    (void)fp;
    *read_count = count < config_size - config_pos ? count : config_size - config_pos;
    memcpy(buff, config + config_pos, *read_count);
    config_pos += *read_count;
    return FR_OK;
}

FRESULT f_write(FIL *fp, const void *buff, UINT count, UINT *write_count) {
    (void)fp;
    *write_count = short_write && count ? count - 1 : count;
    assert(config_pos + *write_count <= sizeof config);
    memcpy(config + config_pos, buff, *write_count);
    config_pos += *write_count;
    config_size = config_pos;
    return FR_OK;
}

FRESULT f_stat(const TCHAR *path, FILINFO *info) {
    (void)path;
    (void)info;
    return FR_NO_FILE;
}

static void reset_options(void) {
    scanlines = blend = dvi = lcd = color_mode = picture_dim = 0;
    cur_rom[0] = 0;
}

static void load_config(const char *value) {
    strcpy(config, value);
    config_size = strlen(value);
    reset_options();
    load_options();
}

int main(void) {
    const char *rom = "/games/Test game.md";
    has_picture = true;
    for (int scan = 0; scan < 3; scan++)
    for (int bl = 0; bl < 3; bl++)
    for (int output = 0; output < 2; output++)
    for (int display = 0; display < 2; display++)
    for (int mode = 0; mode < 4; mode++)
    for (int dimming = 0; dimming < 4; dimming++) {
        scanlines = scan;
        blend = bl;
        dvi = output;
        lcd = display;
        color_mode = mode;
        picture_dim = dimming;
        strcpy(cur_rom, rom);
        save_options();
        assert(config_size == 7 + strlen(rom) + 1);
        assert(config[4] == '0' + mode && config[5] == '0' + dimming && config[6] == '\n');
        reset_options();
        load_options();
        assert(scanlines == scan && blend == bl && dvi == output && lcd == display);
        assert(color_mode == mode && picture_dim == dimming);
        assert(strcmp(cur_rom, rom) == 0);
        assert(applied_video == (unsigned)(scan | bl << 2 | output << 4 |
                                          display << 5 | mode << 6 | dimming << 8));
    }

    load_config("21\n/a.md\n");
    assert(scanlines == 2 && blend == 1 && !dvi && !lcd && !color_mode && !picture_dim);
    assert(strcmp(cur_rom, "/a.md") == 0);
    load_config("121\n/a.md\n");
    assert(scanlines == 1 && blend == 2 && dvi && !lcd && !color_mode && !picture_dim);
    assert(strcmp(cur_rom, "/a.md") == 0);
    load_config("1211\n/a.md\n");
    assert(dvi && lcd && !color_mode && !picture_dim);
    assert(strcmp(cur_rom, "/a.md") == 0);
    load_config("000033\n/a.md\n");
    assert(color_mode == 3 && picture_dim == 3 && strcmp(cur_rom, "/a.md") == 0);
    load_config("0000x9\n");
    assert(!color_mode && !picture_dim);
    load_config("000000\n");
    assert(!cur_rom[0]);
    load_config("00\nx\n");
    assert(strcmp(cur_rom, "x") == 0);
    load_config("00\n");
    assert(!cur_rom[0]);

    game_loaded = true;
    for (int mode = 0; mode < 4; mode++)
    for (int dimming = 0; dimming < 4; dimming++) {
        color_mode = mode;
        picture_dim = dimming;
        draw_options(0);
        display_write();
        assert(nopt <= PAGESIZE && nopt <= OPT_COUNT);
        assert(opt_items[nopt - 2] == OPT_COLOR && opt_items[nopt - 1] == OPT_DIM);
        assert(strncmp(screen[LIST_ROW + nopt - 2] + 3, "Color mode: ", 12) == 0);
        assert(strncmp(screen[LIST_ROW + nopt - 1] + 3, "Brightness: ", 12) == 0);
    }
    game_loaded = false;
    draw_options(0);
    assert(nopt == 8);

    // Builds without GT_PICTURE (DB9): no menu entries and no colour/brightness bits,
    // but the saved values survive for a card moved between builds.
    has_picture = false;
    color_mode = 2;
    picture_dim = 3;
    apply_options();
    display_write();
    assert(applied_video == 0);
    draw_options(0);
    assert(nopt == 6);
    for (int i = 0; i < nopt; i++)
        assert(opt_items[i] != OPT_COLOR && opt_items[i] != OPT_DIM);
    game_loaded = true;
    draw_options(0);
    for (int i = 0; i < nopt; i++)
        assert(opt_items[i] != OPT_COLOR && opt_items[i] != OPT_DIM);
    game_loaded = false;
    strcpy(cur_rom, rom);
    save_options();
    reset_options();
    load_options();
    assert(color_mode == 2 && picture_dim == 3 && applied_video == 0);
    has_picture = true;

    short_write = true;
    save_options();
    display_write();
    assert(strncmp(screen[STATUS_ROW] + 1, "Cannot save settings", 20) == 0);
    puts("Picture settings: round trips, legacy files, register packing, menu and non-picture builds passed");
    return 0;
}
