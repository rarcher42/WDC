#pragma once
// Here's where the API interface functions are listed for external use
const uint8_t MEM_PERM_RD = 0x01;
const uint8_t MEM_PERM_WR = 0x02;
const uint8_t MEM_PERM_X = 0x04;

const uint8_t MEM_RAM = MEM_PERM_RD | MEM_PERM_WR | MEM_PERM_X;
const uint8_t MEM_ROM = MEM_PERM_RD | MEM_PERM_X;
const uint8_t MEM_IO = MEM_PERM_RD | MEM_PERM_WR;
