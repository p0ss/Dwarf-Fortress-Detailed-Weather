// platform_linux.h: the Linux side of platform.h (g++, DF's native Linux build).
#pragma once
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <dlfcn.h>
#include <errno.h>
#include <sys/mman.h>
#include <sys/uio.h>
#include <time.h>
#include <unistd.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>

// The mapping holding an address, from /proc/self/maps: its end and its
// protection as mprotect takes it. False if the address isn't mapped.
// (Reads the whole list, some hundreds of lines: only used when patching
// the slot, and for the memory checks where the quick way isn't allowed.)
static bool plat_mapping_of(uintptr_t address, uintptr_t* end, int* protection) {
    FILE* maps = fopen("/proc/self/maps", "r");
    if (!maps) return false;
    char line[512];
    bool found = false;
    while (fgets(line, sizeof line, maps)) {
        unsigned long long from = 0, to = 0;
        char perms[8] = "";
        if (sscanf(line, "%llx-%llx %7s", &from, &to, perms) != 3) continue;
        if (address >= from && address < to) {
            *end = (uintptr_t)to;
            *protection = (perms[0] == 'r' ? PROT_READ : 0) | (perms[1] == 'w' ? PROT_WRITE : 0)
                        | (perms[2] == 'x' ? PROT_EXEC : 0);
            found = true;
            break;
        }
    }
    fclose(maps);
    return found;
}

// Readable, by the list of mappings: every mapping the bytes cross must be readable.
static bool plat_readable_by_maps(const void* p, size_t n) {
    uintptr_t at = (uintptr_t)p;
    const uintptr_t end = at + n;
    while (at < end) {
        uintptr_t mapping_end = 0;
        int protection = 0;
        if (!plat_mapping_of(at, &mapping_end, &protection) || !(protection & PROT_READ)) return false;
        if (mapping_end <= at) return false;
        at = mapping_end;
    }
    return true;
}

// The quick way: the kernel is asked to copy the bytes out of this very
// process, which fails cleanly (no fault) if any of them can't be read.
// Where that call isn't allowed (some sandboxes), the list of mappings.
static bool plat_readable_span(const void* p, size_t n) {
    if (!p) return false;
    if (n == 0) return true;
    static thread_local char scratch[1 << 16];
    static bool by_maps = false;
    if (by_maps) return plat_readable_by_maps(p, n);
    uintptr_t at = (uintptr_t)p;
    const uintptr_t end = at + n;
    if (end < at) return false;
    while (at < end) {
        size_t length = end - at < sizeof scratch ? end - at : sizeof scratch;
        struct iovec ours = {scratch, length};
        struct iovec theirs = {(void*)at, length};
        ssize_t copied = process_vm_readv(getpid(), &ours, 1, &theirs, 1, 0);
        if (copied != (ssize_t)length) {
            if (copied < 0 && (errno == ENOSYS || errno == EPERM)) {
                by_maps = true;
                return plat_readable_by_maps(p, n);
            }
            return false;
        }
        at += length;
    }
    return true;
}

// (Linux has no "one region" to ask about as Windows' VirtualQuery does: readable is readable.)
static bool plat_readable(const void* p, size_t n) { return plat_readable_span(p, n); }

// The game's Linux build exports its functions' names (libg_src_lib.so:
// _ZN16renderer_2d_base15tidy_tile_cacheEv), so the slot is checked by
// name rather than by where its code is: a game update that moved
// tidy_tile_cache to another slot is refused, not hooked wrongly.
static bool plat_check_renderer(void** vtable, size_t tidy_slot, size_t render_slot,
                                char* class_name, size_t class_name_size, char* why, size_t why_size) {
    Dl_info table = {}, tidy = {}, render = {};
    snprintf(class_name, class_name_size, "(unread)");
    if (dladdr(vtable, &table) && table.dli_sname) snprintf(class_name, class_name_size, "%s", table.dli_sname);
    if (!dladdr(vtable[tidy_slot], &tidy) || !tidy.dli_sname || !strstr(tidy.dli_sname, "tidy_tile_cache")) {
        snprintf(why, why_size, "slot %zu of %s is not tidy_tile_cache (it is %s)", tidy_slot, class_name,
                 tidy.dli_sname ? tidy.dli_sname : "a function with no name");
        return false;
    }
    if (!dladdr(vtable[render_slot], &render) || render.dli_fbase != tidy.dli_fbase
            || vtable[render_slot] == vtable[tidy_slot]) {
        snprintf(why, why_size, "slot %zu of %s is not a function of the game's beside tidy_tile_cache",
                 render_slot, class_name);
        return false;
    }
    return true;
}

// A vtable is in memory the loader has made read-only: made writable for
// the one write, then given back the protection it had.
static bool plat_patch_slot(void** slot, void* value, char* why, size_t why_size) {
    const uintptr_t page_size = (uintptr_t)sysconf(_SC_PAGESIZE);
    void* page = (void*)((uintptr_t)slot & ~(page_size - 1));
    uintptr_t mapping_end = 0;
    int protection = 0;
    if (!plat_mapping_of((uintptr_t)slot, &mapping_end, &protection)) {
        snprintf(why, why_size, "the slot's memory is not in /proc/self/maps");
        return false;
    }
    const bool writable = (protection & PROT_WRITE) != 0;
    if (!writable && mprotect(page, page_size, protection | PROT_WRITE) != 0) {
        snprintf(why, why_size, "mprotect failed (%d)", errno);
        return false;
    }
    (void)__atomic_exchange_n(slot, value, __ATOMIC_SEQ_CST);
    if (!writable) mprotect(page, page_size, protection);
    return true;
}

static uintptr_t plat_code_base(const void* function) {
    Dl_info info = {};
    return dladdr(function, &info) ? (uintptr_t)info.dli_fbase : 0;
}

static double plat_ticks_now() {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (double)t.tv_sec * 1e9 + (double)t.tv_nsec;
}

static double plat_us_per_tick() { return 1e-3; }   // (a tick is a nanosecond)

// DFHack's Lua reads the process's own environment with os.getenv.
static bool plat_publish(const char* name, const char* value) { return setenv(name, value, 1) == 0; }

static bool plat_file_exists(const char* path) { return access(path, F_OK) == 0; }
