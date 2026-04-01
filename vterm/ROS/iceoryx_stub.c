// iceoryx_stub.c
// no-op stubs for iceoryx shared-memory symbols referenced by rmw_cyclonedds_cpp
// CycloneDDS was compiled with ENABLE_SHM=OFF, so these code paths are never
// reached at runtime. We provide weak stubs so the static linker is satisfied

#include <stddef.h>
#include <stdint.h>

// called by ddsc when freeing an iceoryx chunk
void free_iox_chunk(void* iox_sub, void* chunk) {
    (void)iox_sub;
    (void)chunk;
}

// returns the iceoryx header preceding a chunk
void* iceoryx_header_from_chunk(const void* chunk) {
    (void)chunk;
    return NULL;
}

// sets the data state on an iceoryx chunk
void shm_set_data_state(void* chunk, uint8_t data_state) {
    (void)chunk;
    (void)data_state;
}
