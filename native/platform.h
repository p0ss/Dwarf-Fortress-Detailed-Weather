// platform.h
// =====================================================================
// DETAILED WEATHER'S NATIVE HOOK: WHAT DIFFERS BETWEEN WINDOWS AND LINUX
// =====================================================================
// detailed_weather_hook.cpp (the plans, the drawing and the painting) is
// the same on both. Everything that isn't is behind the few functions
// declared here, with one file each side:
//   platform_windows.h   MSVC, as grungeisdead wrote and tested it
//   platform_linux.h     g++, DF's native Linux build
// A check that stands in for the game (the harness) defines
// DW_PLATFORM_PROVIDED and supplies these functions itself.
//
// All are static: the hook is one translation unit, as it always was.
#pragma once
#include <cstddef>
#include <cstdint>

// Marks a function or constant the dfhooks chain loader looks up by name.
#if defined(_WIN32) || defined(DW_PLATFORM_WINDOWS)
#define DW_EXPORT __declspec(dllexport)
#else
#define DW_EXPORT __attribute__((visibility("default")))
#endif

// The library's file name, for the log.
#if defined(_WIN32) || defined(DW_PLATFORM_WINDOWS)
#define DW_LIBRARY_NAME "dfhooks_detailed_weather.dll"
#else
#define DW_LIBRARY_NAME "libdfhooks_detailed_weather.so"
#endif

// ---- MEMORY CHECKS ----
// Every pointer from Lua is checked before it is followed, so a wrong
// address refuses instead of faulting.
// Is [p, p + n) readable memory? (On Windows: in one region, as the hook's
// checks before patching always asked.)
static bool plat_readable(const void* p, size_t n);
// Are n bytes from p all readable, however many regions they span?
static bool plat_readable_span(const void* p, size_t n);

// ---- THE RENDERER'S SLOT ----
// Is this the game's own renderer vtable, with tidy_tile_cache in
// tidy_slot and render in render_slot? Writes the renderer's class name
// into class_name for the record, and into why what failed.
//   Windows: the vtable and both functions must be inside DF's exe, the
//            functions in code; the class name is read from MSVC's RTTI.
//   Linux:   the game exports its functions' names, so tidy_slot must be
//            the function named ...tidy_tile_cache... and render_slot one
//            from the same library; the class name is the vtable's symbol.
static bool plat_check_renderer(void** vtable, size_t tidy_slot, size_t render_slot,
                                char* class_name, size_t class_name_size, char* why, size_t why_size);
// Writes value into a vtable slot (read-only memory, made writable for the
// write and put back as it was). False, with why, if it can't be.
static bool plat_patch_slot(void** slot, void* value, char* why, size_t why_size);
// Where the game's code is loaded (Windows: the exe's base; Linux: the
// base of the library holding the function), for the log's offsets.
static uintptr_t plat_code_base(const void* function);

// ---- TIME ----
// A fast clock in ticks, and how many microseconds one tick is.
static double plat_ticks_now();
static double plat_us_per_tick();

// ---- THE REST ----
// Sets an environment variable so DFHack's Lua reads it with os.getenv.
static bool plat_publish(const char* name, const char* value);
static bool plat_file_exists(const char* path);

#if !defined(DW_PLATFORM_PROVIDED)
#if defined(_WIN32) || defined(DW_PLATFORM_WINDOWS)
#include "platform_windows.h"
#else
#include "platform_linux.h"
#endif
#endif
