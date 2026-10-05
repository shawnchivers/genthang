// Based on the iosys firmware of SNESTang / MDTang (nand2mario, GPL-3.0); modified for Gen Thang.
#include "picorv32.h"

static uint8_t flash_send(uint8_t value) {
    reg_spiflash_byte = value;
    return reg_spiflash_byte;
}

static uint8_t flash_receive() {
    return flash_send(0xFF);
}

static void flash_readblock(uint8_t *dst, unsigned length) {
    while (length--)
        *dst++ = flash_receive();
}

void spiflash_read(uint32_t addr, uint8_t *buf, int length) {
    reg_spiflash_ctrl = 0;
    flash_send(0x03);
    flash_send(addr >> 16);
    flash_send(addr >> 8);
    flash_send(addr);
    flash_readblock(buf, length);
    reg_spiflash_ctrl = 1;
}

void spiflash_write_enable() {
    reg_spiflash_ctrl = 0;
    flash_send(0x06);
    reg_spiflash_ctrl = 1;
}

void spiflash_write_disable() {
    reg_spiflash_ctrl = 0;
    flash_send(0x04);
    reg_spiflash_ctrl = 1;
}

void spiflash_sector_erase(uint32_t addr) {
    spiflash_write_enable();
    reg_spiflash_ctrl = 0;
    flash_send(0x20);
    flash_send(addr >> 16);
    flash_send(addr >> 8);
    flash_send(addr);
    reg_spiflash_ctrl = 1;
}

void spiflash_page_program(uint32_t addr, uint8_t *buf) {
    spiflash_write_enable();
    reg_spiflash_ctrl = 0;
    flash_send(0x02);
    flash_send(addr >> 16);
    flash_send(addr >> 8);
    flash_send(addr);
    for (int offset = 0; offset < 256; offset++)
        flash_send(buf[offset]);
    reg_spiflash_ctrl = 1;
}

uint8_t spiflash_read_status1() {
    reg_spiflash_ctrl = 0;
    flash_send(0x05);
    uint8_t status = flash_receive();
    reg_spiflash_ctrl = 1;
    return status;
}

int spiflash_ready() {
    int deadline = time_millis() + 2000;
    while (spiflash_read_status1() & 1) {
        if ((int)(time_millis() - deadline) >= 0)
            return 0;
    }
    return 1;
}
