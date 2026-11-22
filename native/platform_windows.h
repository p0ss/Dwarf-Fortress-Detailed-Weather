// platform_windows.h: the Windows side of platform.h (MSVC x64).
// grungeisdead's own code, moved here unchanged in what it does.
#pragma once
#include <algorithm>   // (before windows.h, whose min and max macros would otherwise break its declarations)
#include <windows.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>

// DF's exe, as loaded.
static uintptr_t plat_exe_base() {
    static uintptr_t base = (uintptr_t)GetModuleHandleW(nullptr);
    return base;
}

static bool plat_readable(const void* p, size_t n) {
    MEMORY_BASIC_INFORMATION m;
    if (!p || VirtualQuery(p, &m, sizeof m) != sizeof m) return false;
    if (m.State != MEM_COMMIT) return false;
    if (m.Protect & (PAGE_NOACCESS | PAGE_GUARD)) return false;
    uintptr_t end = (uintptr_t)m.BaseAddress + m.RegionSize;
    return (uintptr_t)p + n <= end;
}

// readable() asks about one region (pages with the same allocation and
// protection), and a block of pixels can sit across two good ones: test 7
// refused 229 of 2571 copies that way, and they stayed blank on screen.
static bool plat_readable_span(const void* p, size_t n) {
    uintptr_t at = (uintptr_t)p;
    const uintptr_t end = at + n;
    while (at < end) {
        MEMORY_BASIC_INFORMATION m;
        if (!at || VirtualQuery((const void*)at, &m, sizeof m) != sizeof m) return false;
        if (m.State != MEM_COMMIT || (m.Protect & (PAGE_NOACCESS | PAGE_GUARD))) return false;
        const uintptr_t region_end = (uintptr_t)m.BaseAddress + m.RegionSize;
        if (region_end <= at) return false;
        at = region_end;
    }
    return true;
}

// Is p inside DF's exe as loaded (code or data)?
static bool plat_in_exe(const void* p) {
    MEMORY_BASIC_INFORMATION m;
    if (!p || VirtualQuery(p, &m, sizeof m) != sizeof m) return false;
    return m.State == MEM_COMMIT && (uintptr_t)m.AllocationBase == plat_exe_base();
}

// Is p code inside DF's exe?
static bool plat_is_code(const void* p) {
    MEMORY_BASIC_INFORMATION m;
    if (!p || VirtualQuery(p, &m, sizeof m) != sizeof m) return false;
    if (m.State != MEM_COMMIT || (uintptr_t)m.AllocationBase != plat_exe_base()) return false;
    return (m.Protect & (PAGE_EXECUTE | PAGE_EXECUTE_READ | PAGE_EXECUTE_READWRITE |
                         PAGE_EXECUTE_WRITECOPY)) != 0;
}

// The renderer's class name (MSVC x64 RTTI), for the record: the slot
// before a vtable holds its CompleteObjectLocator (signature 1, two
// offsets, then the TypeDescriptor as an RVA); the decorated name sits 16
// bytes into the TypeDescriptor (".?AVrenderer_2d@@" in test 1).
static void plat_read_class_name(void** vt, char* class_name, size_t class_name_size) {
    snprintf(class_name, class_name_size, "(unread)");
    if (!plat_readable(vt - 1, 8)) return;
    const uint32_t* col = (const uint32_t*)vt[-1];
    if (!plat_readable(col, 24) || col[0] != 1) return;
    const char* name = (const char*)(plat_exe_base() + col[3] + 16);
    if (!plat_readable(name, class_name_size)) return;
    size_t i = 0;
    for (; i + 1 < class_name_size && name[i]; i++) class_name[i] = name[i];
    class_name[i] = 0;
}

static bool plat_check_renderer(void** vtable, size_t tidy_slot, size_t render_slot,
                                char* class_name, size_t class_name_size, char* why, size_t why_size) {
    if (!plat_in_exe(vtable)) {
        snprintf(why, why_size, "the renderer's vtable is not inside DF's exe");
        return false;
    }
    plat_read_class_name(vtable, class_name, class_name_size);
    void* tidy = vtable[tidy_slot];
    void* render = vtable[render_slot];
    if (!plat_is_code(tidy) || !plat_is_code(render) || tidy == render) {
        snprintf(why, why_size, "slots %zu and %zu of %s are not both DF code", tidy_slot, render_slot, class_name);
        return false;
    }
    return true;
}

static bool plat_patch_slot(void** slot, void* value, char* why, size_t why_size) {
    DWORD old;
    if (!VirtualProtect(slot, sizeof(void*), PAGE_READWRITE, &old)) {
        snprintf(why, why_size, "VirtualProtect failed (%lu)", (unsigned long)GetLastError());
        return false;
    }
    InterlockedExchangePointer(slot, value);
    VirtualProtect(slot, sizeof(void*), old, &old);
    return true;
}

static uintptr_t plat_code_base(const void*) { return plat_exe_base(); }

static double plat_ticks_now() {
    LARGE_INTEGER t;
    QueryPerformanceCounter(&t);
    return (double)t.QuadPart;
}

static double plat_us_per_tick() {
    LARGE_INTEGER f;
    QueryPerformanceFrequency(&f);
    return 1e6 / (double)f.QuadPart;
}

// _putenv_s updates the C runtime's environment, which DFHack's Lua
// reads through os.getenv (both use the shared UCRT, as Stockhook found).
static bool plat_publish(const char* name, const char* value) { return _putenv_s(name, value) == 0; }

static bool plat_file_exists(const char* path) { return GetFileAttributesA(path) != INVALID_FILE_ATTRIBUTES; }
