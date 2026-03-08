# Musopti — Foundations Design

**Date**: 2026-03-03
**Status**: Approved
**Scope**: Repository structure, firmware architecture, module APIs, app skeleton

## Overview

Musopti is an intelligent wearable device for real-time strength training analysis.
It uses an ESP32-C6 (Waveshare Touch-AMOLED-1.8 board) with a QMI8658 IMU to detect
movement phases during exercises like bench press, validate isometric pauses, and send
events to an iPhone over BLE.

## Repository Structure

```
esp/
├── embedded/
│   └── firmware/              # ESP-IDF project targeting ESP32-C6
├── apps/
│   ├── ios/                   # Xcode project (Swift/SwiftUI)
│   └── desktop/               # UI experiments
├── data/
│   └── datasets/              # IMU recordings for Edge Impulse / testing
├── docs/
│   ├── plans/                 # Design documents
│   ├── validation/            # Validation checklists
│   └── spec/                  # Source specifications
├── vendor/                    # Local SDK / board reference clones
└── README.md
```

## Firmware Architecture

### Target
- Board: Waveshare ESP32-C6-Touch-AMOLED-1.8
- MCU: ESP32-C6 (RISC-V single-core 160 MHz)
- IMU: QMI8658 on I2C (SCL=7, SDA=8)
- Framework: ESP-IDF >= 5.3.0

### Data Flow

```
[QMI8658 / Simulated] → imu_source → imu_sample_t
        ↓
  motion_detection (state machine)
        ↓
  musopti_event_t (REP_COMPLETE, PAUSE_RESULT, STATE_CHANGE)
        ↓
  main (orchestrator) → ble_service → iPhone
```

### Module: common

Shared types used across all components.

```c
// Motion states
typedef enum {
    MOTION_STATE_IDLE,
    MOTION_STATE_LOWERING,
    MOTION_STATE_BOTTOM_PAUSE,
    MOTION_STATE_RISING,
    MOTION_STATE_REP_VALID,
    MOTION_STATE_REP_INVALID,
} motion_state_t;

// IMU sample
typedef struct {
    float accel_x, accel_y, accel_z;  // m/s²
    float gyro_x, gyro_y, gyro_z;    // rad/s
    int64_t timestamp_us;
} imu_sample_t;

// Application events
typedef enum {
    MUSOPTI_EVENT_STATE_CHANGE = 0,
    MUSOPTI_EVENT_REP_COMPLETE,
    MUSOPTI_EVENT_HOLD_RESULT,
    MUSOPTI_EVENT_SESSION_START,
    MUSOPTI_EVENT_SESSION_STOP,
} musopti_event_type_t;

typedef struct {
    musopti_event_type_t type;
    motion_state_t state;
    musopti_exercise_type_t exercise;
    uint16_t rep_count;
    uint32_t hold_duration_ms;
    bool hold_valid;
    int64_t timestamp_us;
} musopti_event_t;
```

### Module: imu

Abstraction over IMU data source. Two implementations:
1. **Hardware**: wraps `waveshare/qmi8658` component via I2C.
2. **Simulated**: generates synthetic samples for testing without hardware.

```c
// Public API
esp_err_t imu_init(const imu_config_t *config);
esp_err_t imu_read(imu_sample_t *sample);
```

The caller does not know whether data comes from real hardware or simulation.

### Module: motion_detection

Deterministic state machine consuming `imu_sample_t` and producing `musopti_event_t`.

- Rule-based detection: thresholds on acceleration magnitude + gyro magnitude.
- Configurable parameters: pause target duration, tolerance, thresholds.
- No dependency on BLE or hardware drivers.

```c
esp_err_t motion_detector_init(const motion_detector_config_t *config);
esp_err_t motion_detector_process(const imu_sample_t *sample, musopti_event_t *event_out, bool *has_event);
motion_state_t motion_detector_get_state(void);
```

### Module: ble_service

Minimal custom GATT service using NimBLE.

| Characteristic | UUID | Properties | Content |
|---|---|---|---|
| Event | `4D55534F-5054-4900-0001-000000000001` | Read + Notify | `musopti_ble_event_payload_t` (v2, 12 bytes) |
| Config | `4D55534F-5054-4900-0001-000000000002` | Read + Write | `musopti_ble_config_payload_t` (v1, 12 bytes) |
| Raw Data | `4D55534F-5054-4900-0001-000000000003` | Notify | Raw IMU packets (v1 header + packed samples) |

```c
esp_err_t ble_service_init(void);
esp_err_t ble_service_notify_event(const musopti_event_t *event);
bool ble_service_is_connected(void);
```

BLE failures never block the motion loop.

### Module: main (orchestrator)

`app_main()` initializes all modules, then runs a loop:
1. Read IMU sample.
2. Feed to motion detector.
3. If event produced, send via BLE.
4. Yield (target ~100 Hz loop = 10 ms period).

### Module: power_mgmt

Stub for now. Will handle deep sleep, battery monitoring, and wake-up later.

## iOS App (future)

- Swift + SwiftUI
- CoreBluetooth for BLE scanning/connection
- Subscribe to Events characteristic (0x2A1B)
- Write exercise config to Config characteristic (0x2A19)
- Send commands via Command characteristic (0x2A1A)
- Later: watchOS extension for haptic feedback

## Key Design Decisions

1. **ESP32-C6** (not S3): the Waveshare board in the workspace is a C6 board.
   The PDF recommended S3, but we use the hardware we have.
2. **Rule-based first**: no TinyML until rule-based detection is validated.
3. **Simulated IMU path**: allows all motion logic to be tested without hardware.
4. **NimBLE over Bluedroid**: lighter footprint, better suited for C6.
5. **Minimal GATT surface**: 3 characteristics, simple binary payloads.

## What Cannot Be Validated Without Hardware

- Actual QMI8658 I2C communication and data quality.
- BLE advertising range and connection stability.
- Real-time latency end-to-end (IMU → iPhone notification).
- Battery consumption and power management.
- Physical mounting and vibration robustness.
