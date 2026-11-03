// Read-only QPC access from the existing UE4SS Lua state. No engine or rendering hooks.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <string.h>

extern "C" __declspec(dllexport) int pb0_qpc_ms(void* lua) {
    struct State { void* lua; } state{lua};
    using Push = void (*)(const State*, double);
    static Push push = []() -> Push {
        auto module = GetModuleHandleW(L"UE4SS.dll");
        if (!module) return nullptr;
        auto getter = GetProcAddress(module, "?get_lua_state@Lua@LuaMadeSimple@RC@@QEBAPEAUlua_State@@XZ");
        if (!getter || memcmp(reinterpret_cast<const void*>(getter), "\x48\x8B\x01\xC3", 4)) return nullptr;
        return reinterpret_cast<Push>(GetProcAddress(module, "?set_number@Lua@LuaMadeSimple@RC@@QEBAXN@Z"));
    }();
    if (!push) return 0;
    static double frequency = [] { LARGE_INTEGER f{}; QueryPerformanceFrequency(&f); return double(f.QuadPart); }();
    LARGE_INTEGER counter{};
    if (!frequency || !QueryPerformanceCounter(&counter)) return 0;
    push(&state, double(counter.QuadPart) * 1000.0 / frequency);
    return 1;
}
