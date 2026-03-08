#pragma once

#include <stdint.h>
#include <stdbool.h>

#define MUSOPTI_GRAVITY_MPS2 9.81f

typedef enum {
    MUSOPTI_MODE_IDLE = 0,
    MUSOPTI_MODE_DETECTION,
    MUSOPTI_MODE_RECORDING,
} musopti_device_mode_t;

typedef enum {
    EXERCISE_GENERIC = 0,
    EXERCISE_BENCH_PRESS,
    EXERCISE_SQUAT,
    EXERCISE_DEADLIFT,
    EXERCISE_CUSTOM,
    EXERCISE_TYPE_COUNT,
} musopti_exercise_type_t;

typedef enum {
    MOTION_STATE_IDLE = 0,
    MOTION_STATE_PHASE_A,
    MOTION_STATE_HOLD,
    MOTION_STATE_PHASE_B,
    MOTION_STATE_REP_COMPLETE,
    MOTION_STATE_REP_INVALID,
} motion_state_t;

typedef struct {
    float accel_x;
    float accel_y;
    float accel_z;
    float gyro_x;
    float gyro_y;
    float gyro_z;
    int64_t timestamp_us;
} imu_sample_t;

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

/* Compact on-air BLE payload for musopti_event_t (v2).
 * Little-endian, versioned for forward compatibility.
 */
typedef struct __attribute__((packed)) {
    uint8_t  version;           /* payload format version, currently 2 */
    uint8_t  event_type;        /* musopti_event_type_t */
    uint8_t  state;             /* motion_state_t */
    uint8_t  flags;             /* bit0: hold_valid */
    uint16_t rep_count;
    uint8_t  exercise_type;     /* musopti_exercise_type_t */
    uint8_t  device_mode;       /* musopti_device_mode_t */
    uint32_t hold_duration_ms;
} musopti_ble_event_payload_t;

/* BLE config payload written by the iOS app to configure the device. */
typedef struct __attribute__((packed)) {
    uint8_t  version;           /* currently 1 */
    uint8_t  device_mode;       /* musopti_device_mode_t */
    uint8_t  exercise_type;     /* musopti_exercise_type_t */
    uint8_t  reserved;
    uint16_t hold_target_ms;    /* 0 = no hold phase */
    uint16_t hold_tolerance_ms;
    uint16_t min_rep_duration_ms;
    uint16_t sample_rate_hz;    /* for recording mode */
} musopti_ble_config_payload_t;

typedef enum {
    MUSOPTI_STATUS_FLAG_BATTERY_VALID   = 1 << 0,
    MUSOPTI_STATUS_FLAG_RECORDING_ACTIVE = 1 << 1,
    MUSOPTI_STATUS_FLAG_IMU_SIMULATED   = 1 << 2,
} musopti_ble_status_flags_t;

typedef struct __attribute__((packed)) {
    uint8_t  version;           /* payload format version, currently 1 */
    uint8_t  flags;             /* musopti_ble_status_flags_t bitfield */
    uint8_t  battery_pct;       /* 0xFF if unavailable */
    uint8_t  device_mode;       /* musopti_device_mode_t */
    uint8_t  exercise_type;     /* musopti_exercise_type_t */
    uint8_t  motion_state;      /* motion_state_t */
    uint16_t sample_rate_hz;    /* currently applied sample rate */
    uint16_t config_revision;   /* increments on successful config apply */
    uint8_t  fw_major;
    uint8_t  fw_minor;
    uint8_t  fw_patch;
    uint8_t  reserved;
} musopti_ble_status_payload_t;

const char *motion_state_to_str(motion_state_t state);
const char *musopti_event_type_to_str(musopti_event_type_t type);
const char *musopti_device_mode_to_str(musopti_device_mode_t mode);
const char *musopti_exercise_type_to_str(musopti_exercise_type_t type);
