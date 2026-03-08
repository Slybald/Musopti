#pragma once

#include "esp_err.h"
#include "musopti_types.h"

#define DISPLAY_H_RES 368
#define DISPLAY_V_RES 448

typedef struct {
    motion_state_t state;
    musopti_device_mode_t mode;
    musopti_exercise_type_t exercise;
    uint16_t rep_count;
    uint32_t last_hold_ms;
    bool last_hold_valid;
    bool ble_connected;
    uint8_t battery_pct;
} display_state_t;

esp_err_t display_init(void);

/**
 * Update the on-screen state. Thread-safe: acquires LVGL mutex internally.
 */
esp_err_t display_update(const display_state_t *state);

/**
 * Acquire/release the LVGL mutex for direct LVGL calls.
 */
bool display_lock(int timeout_ms);
void display_unlock(void);
