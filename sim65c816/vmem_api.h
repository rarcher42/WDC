
// Here's where the API interface functions are listed for external use
const uint8_t MEM_PERM_RD = 0x01;
const uint8_t MEM_PERM_WR = 0x02;
const uint8_t MEM_PERM_X = 0x04;

const uint8_t MEM_RAM = MEM_PERM_RD | MEM_PERM_WR | MEM_PERM_X;
const uint8_t MEM_ROM = MEM_PERM_RD | MEM_PERM_X;
const uint8_t MEM_IO = MEM_PERM_RD | MEM_PERM_WR;

const uint32_t  NUM_ASIDS = 256;   // How many address spaces?

// Each memory block will an associated block descriptor that manages that block of memory
typedef struct {
    uint32_t sa;    // Starting linear address (if segmented, this is post-translation address)
    uint32_t ea;    // Ending linear address.  ea >= sa.  len = ea - sa + 1
    void* mem;      // The allocated memory space.  Initially malloc; may be mmap'ed later
    void* next;     // This is so dumb.  I can't create a pointer to selftype even though pointer's size known.
    uint8_t permissions;            // RD, WR, X
    uint8_t valid;                 // Must be non-zero or this block is slated for removal & should be ignored
} mem_block_descriptor_t;

typedef struct {
    mem_block_descriptor_t* head;
} mem_t;

// API functions for external use
mem_block_descriptor_t* find_descriptor(uint8_t asid, uint32_t address);
uint8_t vm_create_block(uint32_t asid, uint32_t sa, uint32_t size, uint8_t permissions);
uint8_t vm_release_block(uint32_t asid, mem_block_descriptor_t* p);
uint8_t vm_release_block_by_address(uint32_t asid, uint32_t address);