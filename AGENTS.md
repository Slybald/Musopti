# AGENTS.md

## Cursor Cloud specific instructions

### Project overview

Musopti is an embedded/mobile IoT project — an ESP32-C6 wearable for strength training, paired with an iOS companion app. See `README.md` for full architecture and build commands.

### What can run on Linux (Cloud Agent VMs)

| Component | Runnable | Command |
|---|---|---|
| **Host C tests** (motion detection, config validation) | Yes | `cd embedded/firmware/host-tests && cmake -B build && cmake --build build && ctest --test-dir build --output-on-failure` |
| **Desktop device simulator** | Yes | `python3 -m http.server 8080 --directory apps/desktop` then open `http://localhost:8080/index.html` in Chrome |
| **Firmware full build** | No | Requires ESP-IDF SDK + RISC-V toolchain (not installed in Cloud Agent) |
| **iOS app** | No | Requires macOS + Xcode 16+ |

### Lint / static analysis

No project-level lint config exists (no `.clang-format`, `.clang-tidy`, or equivalent). Installed lint tools:

- `cppcheck` — run against C source: `cppcheck --enable=all --std=c11 --suppress=missingInclude --suppress=unusedFunction -I embedded/firmware/components/common -I embedded/firmware/components/motion_detection -I embedded/firmware/host-tests/include embedded/firmware/components/common/*.c embedded/firmware/components/motion_detection/*.c`
- `clang-tidy-18` — available for more targeted analysis if needed

### Non-obvious notes

- The host tests in `embedded/firmware/host-tests/` are standalone C code with shim headers (`include/esp_log.h`, `include/esp_err.h`) that stub out ESP-IDF dependencies. They do **not** require ESP-IDF or `IDF_PATH` to build.
- The `vendor/` directory is gitignored and expected to contain local clones of `esp-idf` and the Waveshare board SDK. These are only needed for full firmware builds.
- The desktop simulator (`apps/desktop/index.html`) is a zero-dependency HTML/JS page. Any static file server works.
