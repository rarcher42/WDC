
// Here's where the API interface functions are listed for external use
#define MEM_PERM_RD     0x01
#define MEM_PERM_WR     0x02
#define MEM_PERM_X      0x04
#define MEM_PERM_VALID  0x80


// Note: The creation and deletion operations will manipulate the MEM_PERM_VALID bit transparently
// and the API should not manipulate it.  It may well go away with improvements.
#define MEM_RAM MEM_PERM_RD | MEM_PERM_WR | MEM_PERM_X
#define MEM_ROM MEM_PERM_RD | MEM_PERM_X
#define MEM_IO  MEM_PERM_RD | MEM_PERM_WR

const uint32_t  NUM_ASIDS = 256;   // How many address spaces?

// Each memory block will an associated block descriptor that manages that block of memory
typedef struct {
    uint32_t sa;    // Starting linear address (if segmented, this is post-translation address)
    uint32_t ea;    // Ending linear address.  ea >= sa.  len = ea - sa + 1
    void* mem;      // The allocated memory space.  Initially malloc; may be mmap'ed later
    void* next;     // This is so dumb.  I can't create a pointer to selftype even though pointer's size known.
    uint8_t permissions;            // Valid x x x RD, WR, X
} mem_block_descriptor_t;

typedef struct {
    mem_block_descriptor_t* head;
} mem_t;

// API functions for external use
void vm_init(void);
mem_block_descriptor_t* vm_find(uint8_t asid, uint32_t address);
uint8_t vm_create_block(uint32_t asid, uint32_t sa, uint32_t size, uint8_t permissions);
uint8_t vm_release_block_by_ptr(uint32_t asid, mem_block_descriptor_t* p);
uint8_t vm_release_block(uint32_t asid, uint32_t address);
uint8_t vm_read_bytes(uint32_t asid, uint32_t address, uint32_t count, uint8_t *buffer);
uint8_t vm_write_bytes(uint32_t asid, uint32_t address, uint32_t count, uint8_t* buffer);

