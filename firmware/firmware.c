// Gen Thang menu firmware (PicoRV32 iosys): pick a Mega Drive / Genesis ROM from the
// TF card and stream it into SDRAM. Drawn by the overlay in textdisp.v.
//
// Works with a DualShock or a Genesis 3/6-button pad (Genesis A/B/C = Square/Cross/
// Circle). Games page: D-pad move, Left/Right page, B/C load or enter, A parent
// directory, Start options. Options page: resume, save/load state, reset, video
// settings. While a game runs, Select+Start (Mode+Start) or Start+A+B+C opens the menu.
//
// Based on the iosys firmware of SNESTang / MDTang (nand2mario, GPL-3.0); modified for Gen Thang.

#include <stdbool.h>
#include "picorv32.h"
#include "fatfs/ff.h"
#include "ss_stub.h"
#include "version.h"

// joystick bits (R L X A RT LT DN UP START SELECT Y B)
#define J_B      0x001      // Cross
#define J_Y      0x002      // Square
#define J_SELECT 0x004
#define J_START  0x008
#define J_UP     0x010
#define J_DOWN   0x020
#define J_LEFT   0x040
#define J_RIGHT  0x080
#define J_A      0x100      // Circle
#define J_X      0x200      // Triangle
#define J_L      0x400      // L1
#define J_R      0x800      // R1
#define J_ALL    0xFFF
#define J_OK     (J_B | J_A)
#define J_BACK   J_Y
#define J_UPLOAD 0x1000

#define UPLOAD_ACK       0x06
#define UPLOAD_NAK       0x15
#define UPLOAD_VERSION   1
#define UPLOAD_CORE      1
#define UPLOAD_BLOCK     512
#define UPLOAD_TIMEOUT   5000

#define TITLE_ROW   0
#define SUB_ROW     3
#define LIST_ROW    5
#define PAGESIZE    18
#define STATUS_ROW  24
#define HELP_ROW    26

#define CFG_PATH    "/GENTHANG.CFG"
#define CORES_DIR   "/cores"

#define MAX_FILES   512
#define NAME_LEN    256
#define MAX_ROM     (4 * 1024 * 1024)
#define FLASH_SIZE  (8 * 1024 * 1024)

FATFS fs;
static char pwd[1024];
static char names[MAX_FILES][NAME_LEN];
static uint8_t is_dir[MAX_FILES];
static uint32_t sizes[MAX_FILES];
static int order[MAX_FILES];
static int nfiles;
static char load_buf[1024];
static bool game_loaded;
static char cur_rom[1024 + NAME_LEN + 2];
static int scanlines;               // 0 off, 1 25%, 2 50%
static int blend;                   // composite blend 0 off, 1 on, 2 adaptive

// ---- overlay helpers ---------------------------------------------------------------
static void put(int col, int row, int c) {
    reg_textdisp = ((uint32_t)col << 16) | ((uint32_t)row << 8) | (uint8_t)c;
}

static void td_reg(int idx, int val) {
    reg_textdisp = 0x03000000 | ((uint32_t)idx << 16) | (uint32_t)(val & 0xFFFF);
}

static void text(int col, int row, const char *s) {
    for (; *s && col < 32; s++, col++)
        put(col, row, *s);
}

static void fill(int col, int row, int n) {
    for (; n > 0 && col < 32; n--, col++)
        put(col, row, ' ');
}

static void centered(int row, int width, const char *s) {
    int n = strlen(s);
    fill(0, row, 32);
    text((width - n) / 2, row, s);
}

static void status(const char *s) {
    fill(0, STATUS_ROW, 32);
    text(1, STATUS_ROW, s);
}

static char *dec(unsigned v, char *end) {
    *--end = 0;
    do { *--end = '0' + v % 10; v /= 10; } while (v);
    return end;
}

static void draw_frame() {
    for (int r = 0; r < 28; r++)
        fill(0, r, 32);
    text(4, TITLE_ROW, "GEN THANG");
    centered(SUB_ROW, 32, "\x06 v" GENTHANG_VERSION " Outrageous \x06");
}

static void help(const char *s) {
    fill(0, HELP_ROW, 32);
    text(0, HELP_ROW, s);
}

// ---- video options ---------------------------------------------------------------
static void apply_options() {
    td_reg(1, scanlines | blend << 2);
}

static void load_options() {
    FIL f;
    char c[3];
    unsigned br;
    if (f_open(&f, CFG_PATH, FA_READ) == FR_OK) {
        if (f_read(&f, c, sizeof c, &br) == FR_OK && br >= 2) {
            if (c[0] >= '0' && c[0] <= '2') scanlines = c[0] - '0';
            if (c[1] >= '0' && c[1] <= '2') blend = c[1] - '0';
            if (br == sizeof c) {
                if (f_read(&f, cur_rom, sizeof cur_rom - 1, &br) == FR_OK) {
                    cur_rom[br] = 0;
                    char *end = strchr(cur_rom, '\n');
                    if (end) *end = 0;
                }
            }
        }
        f_close(&f);
    }
    apply_options();
}

static void save_options() {
    FIL f;
    char c[3] = {'0' + scanlines, '0' + blend, '\n'};
    unsigned bw;
    if (sd_init() != 0 || f_open(&f, CFG_PATH, FA_WRITE | FA_CREATE_ALWAYS) != FR_OK) {
        status("Cannot save settings");
        return;
    }
    if (f_write(&f, c, sizeof c, &bw) != FR_OK || bw != sizeof c)
        status("Cannot save settings");
    else if (cur_rom[0]) {
        unsigned len = strlen(cur_rom);
        if (f_write(&f, cur_rom, len, &bw) != FR_OK || bw != len ||
            f_write(&f, "\n", 1, &bw) != FR_OK || bw != 1)
            status("Cannot save settings");
    }
    f_close(&f);
}

// ---- input -------------------------------------------------------------------------
static int joy() {
    return reg_joystick & 0xFFF;
}

// Select+Start (6-button: Mode+Start) or Start+A+B+C; matches menu_key in md20k_core
static bool menu_combo(int j) {
    return (j & J_START) && ((j & J_SELECT) || (j & (J_Y | J_B | J_A)) == (J_Y | J_B | J_A));
}

static int uart_getchar_nowait() {
    uint32_t v = reg_uart_data;
    return v == UINT32_MAX ? -1 : v & 0xFF;
}

static int upload_request() {
    static const char magic[] = "GTHG";
    static int pos;
    int c = uart_getchar_nowait();
    if (c < 0) return 0;
    if (c == magic[pos]) {
        if (++pos == sizeof magic - 1) {
            pos = 0;
            return 1;
        }
    } else {
        pos = c == magic[0] ? 1 : 0;
    }
    return 0;
}

static void wait_release(int mask) {
    while (joy() & mask) ;
    delay(30);
}

// one press event, with auto-repeat on the D-pad
static int read_key() {
    static int last, t_next;
    for (;;) {
        if (upload_request()) return J_UPLOAD;
        int j = joy();
        int now = time_millis();
        if (j == 0) {
            last = 0;
            continue;
        }
        if (j != last) {
            delay(20);                          // debounce
            if (joy() != j) continue;
            last = j;
            t_next = now + 350;
            return j;
        }
        if ((j & (J_UP | J_DOWN | J_LEFT | J_RIGHT)) && (int)(now - t_next) >= 0) {
            t_next = now + 70;
            return j;
        }
    }
}

// ---- directory listing -------------------------------------------------------------
static bool is_rom(const char *n) {
    const char *dot = strrchr(n, '.');
    return dot && (!strcasecmp(dot, ".md") || !strcasecmp(dot, ".bin") || !strcasecmp(dot, ".gen"));
}

static bool is_core(const char *n) {
    const char *dot = strrchr(n, '.');
    return dot && !strcasecmp(dot, ".bin");
}

static bool before(int a, int b) {             // directories first, then by name
    if (is_dir[a] != is_dir[b]) return is_dir[a];
    return strcasecmp(names[a], names[b]) < 0;
}

static int load_dir() {
    DIR d;
    FILINFO fno;
    nfiles = 0;
    if (f_opendir(&d, pwd) != FR_OK)
        return -1;
    if (pwd[1]) {
        strcpy(names[0], "..");
        is_dir[0] = 1;
        sizes[0] = 0;
        nfiles = 1;
    }
    while (nfiles < MAX_FILES && f_readdir(&d, &fno) == FR_OK && fno.fname[0]) {
        if (fno.fattrib & (AM_HID | AM_SYS)) continue;
        bool dir = fno.fattrib & AM_DIR;
        if (!dir && !is_rom(fno.fname)) continue;
        strncpy(names[nfiles], fno.fname, NAME_LEN - 1);
        names[nfiles][NAME_LEN - 1] = 0;
        is_dir[nfiles] = dir;
        sizes[nfiles] = fno.fsize;
        nfiles++;
    }
    f_closedir(&d);

    for (int i = 0; i < nfiles; i++) {          // insertion sort, ".." stays first
        int v = i, j = i;
        if (pwd[1] && i == 0) { order[0] = 0; continue; }
        while (j > (pwd[1] ? 1 : 0) && before(v, order[j - 1])) {
            order[j] = order[j - 1];
            j--;
        }
        order[j] = v;
    }
    return 0;
}

static int load_cores() {
    DIR d;
    FILINFO fno;
    FRESULT made = f_mkdir(CORES_DIR);
    if (made != FR_OK && made != FR_EXIST)
        return -1;
    nfiles = 0;
    if (f_opendir(&d, CORES_DIR) != FR_OK)
        return -1;
    while (nfiles < MAX_FILES && f_readdir(&d, &fno) == FR_OK && fno.fname[0]) {
        if ((fno.fattrib & (AM_DIR | AM_HID | AM_SYS)) || !is_core(fno.fname))
            continue;
        strncpy(names[nfiles], fno.fname, NAME_LEN - 1);
        names[nfiles][NAME_LEN - 1] = 0;
        is_dir[nfiles] = 0;
        sizes[nfiles] = fno.fsize;
        nfiles++;
    }
    f_closedir(&d);
    for (int i = 0; i < nfiles; i++) {
        int v = i, j = i;
        while (j > 0 && before(v, order[j - 1])) {
            order[j] = order[j - 1];
            j--;
        }
        order[j] = v;
    }
    return 0;
}

static void draw_list(int page, int active) {
    char num[12], buf[33];
    int pages = (nfiles + PAGESIZE - 1) / PAGESIZE;
    if (pages == 0) pages = 1;
    for (int i = 0; i < PAGESIZE; i++) {
        int row = LIST_ROW + i, idx = page * PAGESIZE + i;
        fill(0, row, 32);
        if (idx >= nfiles) continue;
        int f = order[idx];
        put(1, row, is_dir[f] ? 0x01 : 0x02);
        char *n = names[f];
        int len = strlen(n);
        if (!is_dir[f] && strrchr(n, '.'))
            len = strrchr(n, '.') - n;           // hide the extension
        if (len > 28) len = 28;
        for (int k = 0; k < len; k++) put(3 + k, row, n[k]);
    }
    if (nfiles == 0)
        text(3, LIST_ROW, "no ROMs here");

    strcpy(buf, "PAGE ");
    strcat(buf, dec(page + 1, num + sizeof num));
    strcat(buf, "/");
    strcat(buf, dec(pages, num + sizeof num));
    status(buf);
    help("B/C OPEN  A UP  START OPTIONS");
    td_reg(0, nfiles ? LIST_ROW + active - page * PAGESIZE : 31);
}

// ---- ROM loading -------------------------------------------------------------------
static int load_rom(const char *path, uint32_t size) {
    FIL f;
    char msg[40], num[12];
    unsigned br, total = 0;

    if (size > MAX_ROM) {
        status("ROM too big (max 4MB)");
        return -1;
    }
    if (sd_init() != 0 || f_open(&f, path, FA_READ) != FR_OK) {
        status("Cannot open file");
        return -1;
    }
    td_reg(0, 31);
    core_ctrl(1);                   // loading: holds the Genesis in reset
    do {
        if (f_read(&f, load_buf, sizeof load_buf, &br) != FR_OK)
            break;
        if (br & 3) {               // pad the last word
            memset(load_buf + br, 0xFF, 4 - (br & 3));
            br = (br + 3) & ~3u;
        }
        for (unsigned i = 0; i < br; i += 4)
            core_data(*(uint32_t *)(load_buf + i));
        total += br;
        if ((total & 0xFFFF) == 0) {
            strcpy(msg, "LOADING ");
            strcat(msg, dec(total >> 10, num + sizeof num));
            strcat(msg, "/");
            strcat(msg, dec(size >> 10, num + sizeof num));
            strcat(msg, "K");
            status(msg);
        }
    } while (br == sizeof load_buf);
    f_close(&f);
    core_ctrl(0);                   // done: starts the game
    uart_printf("loaded %s: %d bytes\n", path, total);
    return 0;
}

// ---- save states -------------------------------------------------------------------
// The 68K stub (m68k/savestate.s) runs from a window the hardware maps at 68K 0x400000
// (0x440000 here); work RAM, cartridge SRAM and VRAM are read and written in SDRAM.
// 68K words appear as halfwords at the same offset.
#define SS_WIN      0x440000
#define SS_EN       1
#define SS_NMI      2
#define SS_ZFREEZE  4
#define SS_RESET    8               // holds the game in reset
#define SS_MAGIC    0x53534754      // "GTSS"
#define SS_VERSION  1

struct ss_part { uint32_t save, load, len; };
static const struct ss_part ss_parts[] = {
    {0x400000, 0x400000, 0x10000},              // work RAM
    {SS_WIN + 0x1000, SS_WIN + 0x1000, 0x3000}, // CPU/VDP/Z80/YM state, Z80 RAM
    {0x600000, SS_WIN + 0x10000, 0x10000},      // VRAM (the stub writes it on load)
    {0x420000, 0x420000, 0x10000},              // cartridge SRAM
};
#define SS_FILE_SIZE (512 + 0x10000 + 0x3000 + 0x10000 + 0x10000)

static volatile uint16_t *ss_w(unsigned off) {
    return (volatile uint16_t *)(SS_WIN + off);
}

static bool ss_wait(unsigned stat) {
    int deadline = time_millis() + 1000;
    while (*ss_w(0x84) != stat)
        if ((int)(time_millis() - deadline) >= 0) return false;
    return true;
}

// park the game in the stub; cmd 1 = save, 2 = load
static bool ss_enter(int cmd) {
    for (unsigned i = 0; i < sizeof ss_stub / 2; i++)
        *ss_w(0x100 + 2 * i) = ss_stub[i];
    *ss_w(0x7C) = 0x0040;           // level 7 vector: 0x400100
    *ss_w(0x7E) = 0x0100;
    *ss_w(0x80) = cmd;
    *ss_w(0x84) = 0;
    *ss_w(0x86) = 0;
    td_reg(2, SS_ZFREEZE);
    delay(2);
    td_reg(2, SS_EN | SS_NMI | SS_ZFREEZE);
    bool ok = ss_wait(1);
    td_reg(2, ok ? SS_EN | SS_ZFREEZE : 0);
    return ok;
}

static bool ss_leave() {
    *ss_w(0x86) = 2;
    bool ok = ss_wait(3);
    delay(1);                       // let the rte leave the window
    td_reg(2, 0);
    return ok;
}

static void state_path(char *dst) {
    strcpy(dst, cur_rom);
    char *dot = strrchr(dst, '.');
    if (dot && dot > strrchr(dst, '/')) *dot = 0;
    strcat(dst, ".ss0");
}

static bool saved_state_available() {
    char path[sizeof cur_rom + 4];
    FILINFO rom, state;
    if (!cur_rom[0] || f_stat(cur_rom, &rom) != FR_OK || (rom.fattrib & AM_DIR))
        return false;
    state_path(path);
    return f_stat(path, &state) == FR_OK && !(state.fattrib & AM_DIR) && state.fsize == SS_FILE_SIZE;
}

static int save_state() {
    char path[sizeof cur_rom + 4];
    uint32_t hdr[128] = {SS_MAGIC, SS_VERSION};
    FIL f;
    unsigned bw;

    state_path(path);
    status("Saving state...");
    if (!ss_enter(1)) {
        status("Game did not stop");
        return -1;
    }
    bool err = sd_init() != 0 || f_open(&f, path, FA_WRITE | FA_CREATE_ALWAYS) != FR_OK;
    if (!err) {
        err = f_write(&f, hdr, sizeof hdr, &bw) != FR_OK || bw != sizeof hdr;
        for (unsigned i = 0; i < 4 && !err; i++)
            err = f_write(&f, (const void *)ss_parts[i].save, ss_parts[i].len, &bw) != FR_OK ||
                  bw != ss_parts[i].len;
        if (f_close(&f) != FR_OK) err = true;
    }
    if (!ss_leave()) err = true;
    status(err ? "Cannot save state" : "State saved");
    return err ? -1 : 0;
}

static int load_state() {
    char path[sizeof cur_rom + 4];
    uint32_t hdr[128];
    FIL f;
    unsigned br;

    state_path(path);
    if (sd_init() != 0 || f_open(&f, path, FA_READ) != FR_OK) {
        status("No saved state");
        return -1;
    }
    if (f_size(&f) != SS_FILE_SIZE || f_read(&f, hdr, sizeof hdr, &br) != FR_OK ||
        br != sizeof hdr || hdr[0] != SS_MAGIC || hdr[1] != SS_VERSION) {
        f_close(&f);
        status("Bad state file");
        return -1;
    }
    status("Loading state...");
    if (!ss_enter(2)) {
        f_close(&f);
        status("Game did not stop");
        return -1;
    }
    bool err = false;
    for (unsigned i = 0; i < 4 && !err; i++)
        err = f_read(&f, (void *)ss_parts[i].load, ss_parts[i].len, &br) != FR_OK ||
              br != ss_parts[i].len;
    f_close(&f);
    if (!ss_leave()) err = true;
    if (err) status("State load failed");
    return err ? -1 : 0;
}

static int restore_saved_game() {
    FILINFO rom;
    if (!saved_state_available() || f_stat(cur_rom, &rom) != FR_OK) {
        status("No saved game");
        return -1;
    }
    if (load_rom(cur_rom, rom.fsize) != 0)
        return -1;
    int deadline = time_millis() + 1000;
    while (!(reg_romload_ctrl & 1))
        if ((int)(time_millis() - deadline) >= 0) {
            status("Game did not start");
            return -1;
        }
    delay(20);
    game_loaded = true;
    return load_state();
}

static int flash_core(const char *path, uint32_t size) {
    static uint8_t page[256] __attribute__((aligned(4)));
    static uint8_t check[256] __attribute__((aligned(4)));
    FIL f;
    unsigned br;
    char msg[33], num[12];

    if (!size || size > FLASH_SIZE || f_open(&f, path, FA_READ) != FR_OK) {
        status("Cannot open core image");
        return -1;
    }
    help("DO NOT POWER OFF");
    for (uint32_t addr = 0; addr < size; addr += sizeof page) {
        memset(page, 0xFF, sizeof page);
        if (f_read(&f, page, min(sizeof page, size - addr), &br) != FR_OK || !br) {
            f_close(&f);
            status("Core image read failed");
            return -1;
        }
        if (!(addr & 0xFFF)) {
            if (!spiflash_ready()) goto flash_error;
            spiflash_sector_erase(addr);
        }
        if (!spiflash_ready()) goto flash_error;
        spiflash_page_program(addr, page);
        if (!spiflash_ready()) goto flash_error;
        spiflash_read(addr, check, sizeof check);
        if (memcmp(page, check, sizeof page)) {
            f_close(&f);
            status("Core verify failed");
            return -1;
        }
        if (!(addr & 0xFFFF)) {
            strcpy(msg, "FLASHING ");
            strcat(msg, dec(addr >> 10, num + sizeof num));
            strcat(msg, "K/");
            strcat(msg, dec((size + 1023) >> 10, num + sizeof num));
            strcat(msg, "K");
            status(msg);
        }
    }
    f_close(&f);
    spiflash_write_disable();
    status("Core ready - power cycle");
    help("SAFE TO POWER OFF");
    for (;;) ;

flash_error:
    f_close(&f);
    spiflash_write_disable();
    status("Flash timeout - recover USB");
    return -1;
}

static void select_core() {
    int active = 0, page = -1;
    char path[NAME_LEN + 16];
    if (load_cores() != 0) {
        status("Cannot create /cores");
        return;
    }
    for (;;) {
        int next_page = active / PAGESIZE;
        if (next_page != page) {
            page = next_page;
            draw_list(page, active);
            status(nfiles ? "CORE IMAGES" : "No .bin files in /cores");
            help("B/C SELECT  A CANCEL");
        } else
            td_reg(0, nfiles ? LIST_ROW + active - page * PAGESIZE : 31);

        int key = read_key();
        if (key & J_BACK) return;
        if ((key & J_UP) && nfiles) active = active > 0 ? active - 1 : nfiles - 1;
        else if ((key & J_DOWN) && nfiles) active = active < nfiles - 1 ? active + 1 : 0;
        else if ((key & J_LEFT) && nfiles) active = active >= PAGESIZE ? active - PAGESIZE : 0;
        else if ((key & J_RIGHT) && nfiles) active = active + PAGESIZE < nfiles ? active + PAGESIZE : nfiles - 1;
        else if ((key & J_OK) && nfiles) {
            int selected = order[active];
            for (int row = LIST_ROW; row < LIST_ROW + PAGESIZE; row++) fill(0, row, 32);
            text(3, LIST_ROW + 2, "REPLACE CURRENT CORE?");
            text(3, LIST_ROW + 4, names[selected]);
            text(3, LIST_ROW + 7, "POWER LOSS NEEDS USB RECOVERY");
            help("B/C CONFIRM  A CANCEL");
            wait_release(J_ALL);
            key = read_key();
            if (key & J_BACK) { page = -1; continue; }
            if (!(key & J_OK)) { page = -1; continue; }
            strcpy(path, CORES_DIR "/");
            strcat(path, names[selected]);
            flash_core(path, sizes[selected]);
            page = -1;
        }
    }
}

// ---- serial upload -----------------------------------------------------------------
static int uart_read(void *dst, unsigned len) {
    uint8_t *p = dst;
    int deadline = time_millis() + UPLOAD_TIMEOUT;
    while (len) {
        int c = uart_getchar_nowait();
        if (c >= 0) {
            *p++ = c;
            len--;
            deadline = time_millis() + UPLOAD_TIMEOUT;
        } else if ((int)(time_millis() - deadline) >= 0) {
            return -1;
        }
    }
    return 0;
}

static uint32_t get_le32(const uint8_t *p) {
    return (uint32_t)p[0] | (uint32_t)p[1] << 8 |
           (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}

static uint32_t crc32_update(uint32_t crc, const uint8_t *p, unsigned len) {
    while (len--) {
        crc ^= *p++;
        for (int bit = 0; bit < 8; bit++)
            crc = (crc >> 1) ^ (0xEDB88320u & -(crc & 1));
    }
    return crc;
}

static void upload_error(int code, const char *message) {
    uart_putchar(UPLOAD_NAK);
    uart_putchar(code);
    status(message);
}

static int receive_upload() {
    uint8_t header[12];
    char target[NAME_LEN + 16], temp_path[32];
    FIL f;
    unsigned bw;
    bool opened = false;
    int error = 0;

    uart_putchar(UPLOAD_ACK);
    status("Gen Thang upload waiting...");
    if (uart_read(header, sizeof header) != 0) {
        upload_error(1, "Upload timed out");
        return -1;
    }

    unsigned name_len = header[2] | (unsigned)header[3] << 8;
    uint32_t size = get_le32(header + 4);
    uint32_t expected_crc = get_le32(header + 8);
    bool core_image = header[1] & UPLOAD_CORE;
    uint32_t max_size = core_image ? FLASH_SIZE : MAX_ROM;
    if (header[0] != UPLOAD_VERSION || header[1] & ~UPLOAD_CORE ||
        name_len == 0 || name_len >= NAME_LEN || size > max_size) {
        upload_error(2, "Invalid upload header");
        return -1;
    }

    strcpy(target, core_image ? CORES_DIR "/" : "/");
    unsigned prefix_len = strlen(target);
    if (uart_read(target + prefix_len, name_len) != 0) {
        upload_error(1, "Upload timed out");
        return -1;
    }
    target[prefix_len + name_len] = 0;
    for (unsigned i = prefix_len; i < prefix_len + name_len; i++) {
        unsigned char c = target[i];
        if (c < 0x20 || c > 0x7E || strchr("/\\:*?\"<>|", c)) {
            upload_error(3, "Invalid filename");
            return -1;
        }
    }
    if (core_image && !is_core(target)) {
        upload_error(3, "Core image must end in .bin");
        return -1;
    }

    if (core_image) {
        FRESULT made = f_mkdir(CORES_DIR);
        if (made != FR_OK && made != FR_EXIST) {
            upload_error(4, "Cannot create /cores");
            return -1;
        }
    }
    strcpy(temp_path, core_image ? CORES_DIR "/GENTHANG.UPL" : "/GENTHANG.UPL");

    f_unlink(temp_path);
    if (f_open(&f, temp_path, FA_WRITE | FA_CREATE_ALWAYS) != FR_OK) {
        upload_error(4, "Cannot create upload file");
        return -1;
    }
    opened = true;
    uart_putchar(UPLOAD_ACK);

    uint32_t crc = UINT32_MAX;
    uint32_t total = 0;
    while (total < size) {
        unsigned chunk = size - total > UPLOAD_BLOCK ? UPLOAD_BLOCK : size - total;
        if (uart_read(load_buf, chunk) != 0) {
            error = 1;
            break;
        }
        crc = crc32_update(crc, (uint8_t *)load_buf, chunk);
        if (f_write(&f, load_buf, chunk, &bw) != FR_OK || bw != chunk) {
            error = 5;
            break;
        }
        total += chunk;
        uart_putchar(UPLOAD_ACK);
    }

    if (!error && (crc ^ UINT32_MAX) != expected_crc) error = 6;
    if (opened && f_close(&f) != FR_OK && !error) error = 5;
    if (!error) {
        f_unlink(target);
        if (f_rename(temp_path, target) != FR_OK) error = 7;
    }
    if (error) {
        f_unlink(temp_path);
        upload_error(error, error == 6 ? "Upload CRC mismatch" : "Upload failed");
        return -1;
    }

    uart_putchar(UPLOAD_ACK);
    status("Upload complete");
    return 0;
}

// ---- menu --------------------------------------------------------------------------
enum { OPT_RESTORE, OPT_RESUME, OPT_SAVE, OPT_LOAD, OPT_RESET, OPT_GAMES, OPT_CORES, OPT_SCAN, OPT_BLEND };
static int opt_items[9], nopt;

static void draw_options(int active) {
    static const char *const sl[] = {"OFF", "25%", "50%"};
    static const char *const bl[] = {"OFF", "ON", "ADAPTIVE"};
    char buf[33];
    nopt = 0;
    if (!game_loaded && saved_state_available())
        opt_items[nopt++] = OPT_RESTORE;
    if (game_loaded) {
        opt_items[nopt++] = OPT_RESUME;
        opt_items[nopt++] = OPT_SAVE;
        opt_items[nopt++] = OPT_LOAD;
        opt_items[nopt++] = OPT_RESET;
    }
    opt_items[nopt++] = OPT_GAMES;
    opt_items[nopt++] = OPT_CORES;
    opt_items[nopt++] = OPT_SCAN;
    opt_items[nopt++] = OPT_BLEND;
    for (int i = 0; i < PAGESIZE; i++) {
        int row = LIST_ROW + i;
        fill(0, row, 32);
        if (i >= nopt) continue;
        switch (opt_items[i]) {
        case OPT_RESTORE: strcpy(buf, "Resume saved game"); break;
        case OPT_RESUME: strcpy(buf, "Resume game"); break;
        case OPT_SAVE:   strcpy(buf, "Save state"); break;
        case OPT_LOAD:   strcpy(buf, "Load state"); break;
        case OPT_RESET:  strcpy(buf, "Reset game"); break;
        case OPT_GAMES:  strcpy(buf, game_loaded ? "Load another game" : "Back to games"); break;
        case OPT_CORES:  strcpy(buf, "Switch core"); break;
        case OPT_SCAN:   strcpy(buf, "Scanlines: "); strcat(buf, sl[scanlines]); break;
        case OPT_BLEND:  strcpy(buf, "Composite blend: "); strcat(buf, bl[blend]); break;
        }
        text(3, row, buf);
    }
    if (game_loaded) {
        const char *n = strrchr(cur_rom, '/');
        strncpy(buf, n ? n + 1 : cur_rom, 30);
        buf[30] = 0;
        status(buf);
    } else
        status("OPTIONS");
    help(game_loaded ? "B/C SELECT  START RESUME" : "B/C SELECT  A/START GAMES");
    td_reg(0, LIST_ROW + active);
}

// returns when a game was started or the user resumed the running game
static void menu() {
    static int active, opt;
    char path[1024 + NAME_LEN + 2];
    bool reload = true, options = game_loaded || saved_state_available(), redraw = true;
    int page = -1;

    opt = 0;
    for (;;) {
        if (options) {
            if (opt >= nopt && !redraw) opt = 0;
            if (redraw) {
                draw_options(opt);
                redraw = false;
            }
            int k = read_key();
            if (k == J_UPLOAD) {
                receive_upload();
                active = 0;
                reload = true;
                options = false;
            } else if (menu_combo(k) || (k & J_START)) {
                if (game_loaded) {
                    wait_release(J_ALL);
                    return;
                }
                options = false;
                page = -1;
            } else if (k & J_UP) {
                opt = opt > 0 ? opt - 1 : nopt - 1;
                td_reg(0, LIST_ROW + opt);
            } else if (k & J_DOWN) {
                opt = opt < nopt - 1 ? opt + 1 : 0;
                td_reg(0, LIST_ROW + opt);
            } else if ((k & J_BACK) && !game_loaded) {
                options = false;
                page = -1;
            } else if (k & (J_OK | J_LEFT | J_RIGHT)) {
                switch (opt_items[opt]) {
                case OPT_RESTORE:
                    if (!(k & J_OK)) break;
                    if (restore_saved_game() == 0) {
                        wait_release(J_ALL);
                        return;
                    }
                    redraw = true;
                    break;
                case OPT_RESUME:
                    if (!(k & J_OK)) break;
                    wait_release(J_ALL);
                    return;
                case OPT_SAVE:
                case OPT_LOAD:
                    if (!(k & J_OK)) break;
                    if ((opt_items[opt] == OPT_SAVE ? save_state() : load_state()) == 0) {
                        wait_release(J_ALL);
                        return;
                    }
                    break;
                case OPT_RESET:
                    if (!(k & J_OK)) break;
                    td_reg(2, SS_RESET);                // short console reset; SDRAM stays intact
                    delay(100);
                    wait_release(J_ALL);
                    td_reg(2, 0);
                    return;
                case OPT_GAMES:
                    if (!(k & J_OK)) break;
                    options = false;
                    page = -1;
                    break;
                case OPT_CORES:
                    if (!(k & J_OK)) break;
                    select_core();
                    redraw = true;
                    break;
                case OPT_SCAN:
                    scanlines = (scanlines + ((k & J_LEFT) ? 2 : 1)) % 3;
                    apply_options();
                    save_options();
                    redraw = true;
                    break;
                case OPT_BLEND:
                    blend = (blend + ((k & J_LEFT) ? 2 : 1)) % 3;
                    apply_options();
                    save_options();
                    redraw = true;
                    break;
                }
            }
            continue;
        }

        if (reload) {
            if (load_dir() != 0) {
                status("Cannot read directory");
                strcpy(pwd, "/");
                delay(1000);
                continue;
            }
            reload = false;
            page = -1;
            if (active >= nfiles) active = 0;
        }
        if (active / PAGESIZE != page) {
            page = active / PAGESIZE;
            draw_list(page, active);
        } else
            td_reg(0, LIST_ROW + active - page * PAGESIZE);

        int k = read_key();
        if (k == J_UPLOAD) {
            receive_upload();
            active = 0;
            reload = true;
        } else if (menu_combo(k)) {
            if (game_loaded) {
                wait_release(J_ALL);
                return;
            }
        } else if (k & J_START) {
            options = true;
            redraw = true;
            opt = 0;
        } else if (k & J_UP) {
            active = active > 0 ? active - 1 : nfiles - 1;
        } else if (k & J_DOWN) {
            active = active < nfiles - 1 ? active + 1 : 0;
        } else if (k & J_LEFT) {
            active = active >= PAGESIZE ? active - PAGESIZE : 0;
        } else if (k & J_RIGHT) {
            active = active + PAGESIZE < nfiles ? active + PAGESIZE : nfiles - 1;
        } else if ((k & J_BACK) && pwd[1]) {
            *strrchr(pwd, '/') = 0;
            if (!pwd[0]) strcpy(pwd, "/");
            active = 0;
            reload = true;
        } else if ((k & J_OK) && nfiles) {
            int f = order[active];
            if (is_dir[f]) {
                if (!strcmp(names[f], "..")) {
                    *strrchr(pwd, '/') = 0;
                    if (!pwd[0]) strcpy(pwd, "/");
                } else {
                    if (pwd[1]) strcat(pwd, "/");
                    strcat(pwd, names[f]);
                }
                active = 0;
                reload = true;
            } else {
                strcpy(path, pwd);
                if (pwd[1]) strcat(path, "/");
                strcat(path, names[f]);
                if (load_rom(path, sizes[f]) == 0) {
                    game_loaded = true;
                    strcpy(cur_rom, path);
                    save_options();
                    wait_release(J_ALL);
                    return;
                }
            }
        }
    }
}

int main() {
    overlay(1);
    cursor(0, 31);                  // print() from FatFs glue lands off screen
    reg_uart_clkdiv = 234;          // 115200 baud from the 27MHz iosys clock
    td_reg(0, 31);
    draw_frame();
    uart_printf("Gen Thang menu\n");

    for (;;) {
        char msg[32], num[12];
        status("Reading SD card...");
        int sr = sd_init();
        if (sr == -1) {
            status("SD: no card / no reply");
        } else if (sr != 0) {
            status("SD: card did not initialise");
        } else {
            FRESULT fr = f_mount(&fs, "", 1);
            if (fr == FR_OK)
                break;
            strcpy(msg, fr == FR_NO_FILESYSTEM ? "SD: not FAT32/exFAT" : "SD: mount error ");
            if (fr != FR_NO_FILESYSTEM)
                strcat(msg, dec(fr, num + sizeof num));
            status(msg);
        }
        delay(1000);
    }
    strcpy(pwd, "/");
    load_options();

    for (;;) {
        overlay(1);
        menu();
        overlay(0);
        // game running: the bridge stalls this CPU until the menu combo is held, so
        // the overlay must come on before the keys are released (menu() already
        // waited for the keys that closed it while the overlay was still on)
        while (!menu_combo(joy())) ;
        overlay(1);
        wait_release(J_ALL);
    }
}
