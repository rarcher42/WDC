// vmem.c : Create, manage, and release blocks of memory with defineable permissions for 
// use by an external user of memory, in this case a simulated 4-32 bit CPU with addresses
// up to 32 bits in length.
// 
// Application can mask addresses to limit the range to below 32 bits.  This driver will not
// manage CPU-specific behavior like fewer address pins than address register bits causing mirroring,
// or enforcing smaller address space.  That's up to the simulator that uses these routines.
// 
// Note that blocks CANNOT overlap addresses.  If a block is created which overlaps a prior block,
// it will replace it.  
// 
// FIXME: this is super-minimal and oriented for functionality over efficiency.  A sorted list 
// and on-the-fly management of memory would be faster and more efficient, as is the plan, as 
// time permits.  Just trying to get skeletal functionality up and running as the first targeted
// system is orders of magnitude slower IRL than the most inefficient imaginable implementation
// of a simulator, and we're going to honor Mr. Donald Knuth's wisdom about premature optimization.
// That said, this implementation kind of sucks without some more work. :D


#include <stdio.h>
#include <stdlib.h>
#include <inttypes.h>
#include "vmem.h"
#include "vmem_api.h"


static mem_t mem[NUM_ASIDS];  // The memories :)

// Note: this is only to be called at program initialization.  Please use deallocate_mem_all() to clean up
// upon exit.
void init_mem(void)
{
    uint32_t i;

    for (i = 0; i < NUM_ASIDS; i++)
        mem[i].head = NULL;
}

// Create the block descriptor and allocate a memory region for it.  Return a pointer to link
// into the memory region list, or NULL if there's an error.  
static mem_block_descriptor_t* mem_create_block(uint32_t sa, uint32_t size, uint8_t permissions)
{
    void* mrp;
    mem_block_descriptor_t * bp;

    mrp = malloc((size_t)size); // The virtual memory block
    if (mrp != NULL) {
        bp = (mem_block_descriptor_t *) malloc(sizeof(mem_block_descriptor_t));
        if (bp != NULL) {
            bp->sa = sa;
            bp->ea = sa + size - 1;
            bp->permissions = permissions;
            bp->mem = mrp;  // Point to the memory region just allocated
            bp->valid = 1;   // Valid because we just finished creating it
        }
    }
    else {
        bp = NULL;
    }
    return bp;
}

// Just free the storage held by specified block.  Any linked list relink operations needed should be done
// prior to calling this function.
static uint8_t mem_free(mem_block_descriptor_t* p)
{
    // Note: we won't bother with changing any of the fields as that should have been done earlier 
    // if it mattered. Just free memory only.
    if (p != NULL) {
        if (p->mem != NULL) {
            free((void*)p->mem);    // Free the virtual memory
        }
        free(p);    // Free the memory descriptor block
        return 0;   // No error
    }
    return 1;    // Error handle path if(mem_free_block()) { <handle error> paradigm }
}

// Attempt to insert a newly-created block.
//  If it overlaps an existing block, we will deallocate
// the conflicting block before inserting the new replacement block
// Note: this operation is expensive, but as it's associated with a file I/O operation...
// it's probably OK that it grinds through memory twice in search of pre-existing duplicate memory
// blocks. FIXME: implement a sorted list once everything works.
// FIXME: Deallocate overlapping blocks as they're marked invalid instead of possibly leaving them around
static uint8_t mem_insert_block(uint32_t asid, mem_block_descriptor_t* p)
{
    uint32_t sa;
    uint32_t ea;
    mem_block_descriptor_t* overlap;

    if (p != NULL) {
        sa = p->sa;
        ea = p->ea;
        overlap = find_descriptor(asid, sa);
        if (overlap != NULL) {
            overlap->valid = 0;   // Exclude from valid block search
        } else {
            overlap = find_descriptor(asid, ea);
            if (overlap != NULL) {
                overlap->valid = 0;   // Exclude from valid block search
            }
        }
        // Insert the new node at the head of the list
        p->next = mem[asid].head; // Prior head of list 
        mem[asid].head = p;       // New head of list
        return 0;       // Success 
    }
    return 1;    // Error return
}

// Start higher-level functions (API-level)

// Return the memory descriptor corresponding with specified address, or return NULL if 
// it was not found.  Does not consider access permissions, just existence.
// FIXME: Implement sorted list for faster lookup.
// FIXME: Cull invalid entries instead of just marking them invalid
mem_block_descriptor_t* find_descriptor(uint8_t asid, uint32_t address)
{
    mem_block_descriptor_t* nb;

    nb = mem[asid].head;
    while (nb != NULL) {
        // In case we delete a block without deleting it immediately, check the Valid bit for stale handles
        if ((nb->valid) && (address >= nb->sa) && (address <= nb->ea)) {
            return nb;    // Found it!
        }
        nb = (mem_block_descriptor_t*)nb->next;   // Can't forward-ref *self apparently so must typecast here
    }
    return NULL;    // Not found 
}

uint8_t vm_create_block(uint32_t asid, uint32_t sa, uint32_t size, uint8_t permissions)
{
    mem_block_descriptor_t* p;
    uint8_t fail = 1;   // Pessimistic assumption

    p = mem_create_block(sa, size, permissions);
    if (p != NULL) {
        fail = mem_insert_block(asid, p);
    }
    return fail;
}

uint8_t vm_release_block(uint32_t asid, mem_block_descriptor_t* p)
{
    mem_block_descriptor_t* scan;
    uint8_t fail = 1;
    if (p != NULL) {
        scan = mem[asid].head;
        while (scan != NULL) {
            // iwashere
            scan = (mem_block_descriptor_t *) scan->next;
        }
    }
    return fail;
}

uint8_t vm_release_block_by_address(uint32_t asid, uint32_t address)
{
    mem_block_descriptor_t* p;
    uint8_t fail = 1;

    p = find_descriptor(asid, address);
    if (p != NULL) {

        fail = 0;
    }
    return fail;
}


int vmem_test(void)
{
    mem_block_descriptor_t* p;
    uint32_t i;
    uint8_t fail;


    init_mem();
    for (i = 0; i < NUM_ASIDS; i++) {
        fail = vm_create_block(i, 0x0000, 65536, MEM_RAM);
        printf("%d:%d\n", i, fail);
    }
    for (i = 0; i < NUM_ASIDS; i++) {
        p = find_descriptor(i, 0x6502);
        printf("%d->%p\n", i, p);
    }
    
    printf("Hebbo Wurld!\n");
    while (1)
        ;
    return 0;
}

int main(void)
{
    vmem_test();
}


