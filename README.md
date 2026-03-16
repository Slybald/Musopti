# Musopti

Intelligent wearable device for real-time strength training analysis.

Detects movement phases (lowering, pause, rising), validates isometric pause duration,
counts reps, and sends feedback to an iPhone over BLE.

## Hardware

- **Board**: Waveshare ESP32-C6-Touch-AMOLED-1.8
- **MCU**: ESP32-C6 (RISC-V, 160 MHz)
- **IMU**: QMI8658 (6-axis accelerometer + gyroscope)
- **Communication**: Bluetooth Low Energy (NimBLE)

## Repository Structure

```
apps/
  ios/              iPhone companion app (SwiftUI, XcodeGen, SwiftPM tests)
  desktop/          Desktop/UI experiments
embedded/
  firmware/         ESP-IDF project targeting the ESP32-C6 module
data/
  datasets/         IMU recordings and exported datasets
docs/
  plans/            Design and product plans
  validation/       System validation procedures
  spec/             Technical source documents
vendor/             Local-only SDK / board reference clones (ignored by Git)
```

## Building the Firmware

```bash
cd embedded/firmware
idf.py set-target esp32c6
idf.py build
idf.py flash monitor
```

The committed firmware config is hardware-first: the real IMU, display, and audio
paths are enabled by default so a board flash does not silently run in simulation mode.

### Simulated Peripheral Mode (no hardware needed)

```bash
idf.py menuconfig
# -> Musopti IMU -> Enable "Use simulated IMU data instead of hardware"
# -> Musopti Display -> Enable "Use simulated display (log only, no LVGL)"
# -> Musopti Audio -> Enable "Use simulated audio (log only, no I2S)"
idf.py build
```

## Building the iOS App

```bash
cd apps/ios
xcodegen generate
swift test
xcodebuild -project Musopti.xcodeproj -scheme Musopti -destination 'generic/platform=iOS' build
```

## Local Vendor Dependencies

This repository does not version heavy external dependencies. The expected local layout is:

```bash
git clone https://github.com/espressif/esp-idf.git vendor/esp-idf
git clone https://github.com/waveshareteam/ESP32-C6-Touch-AMOLED-1.8.git vendor/waveshare-esp32-c6-touch-amoled-1.8
```

If you use the shell helper installed locally on this machine, run `idfenv` before building firmware.

## Architecture

```
QMI8658 / Simulated  →  imu_read()  →  imu_sample_t
                                             ↓
                                    motion_detector_process()
                                             ↓
                                      musopti_event_t
                                             ↓
                              main loop  →  ble_service_notify_event()
                                             ↓
                                          iPhone
```

## BLE Event Payload (for iOS client)

Events are sent over a single custom GATT characteristic as a compact, little-endian
binary struct:

```c
typedef struct {
    uint8_t  version;           // currently 2
    uint8_t  event_type;        // musopti_event_type_t
    uint8_t  state;             // motion_state_t
    uint8_t  flags;             // bit0: hold_valid
    uint16_t rep_count;
    uint8_t  exercise_type;     // musopti_exercise_type_t
    uint8_t  device_mode;       // musopti_device_mode_t
    uint32_t hold_duration_ms;  // hold duration when relevant (0 otherwise)
} musopti_ble_event_payload_t;
```

On iOS, you can parse this as 12 bytes, using little-endian decoding for the
16-bit and 32-bit integers.

## License

To be determined.
