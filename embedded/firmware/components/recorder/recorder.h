#pragma once

#include "esp_err.h"
#include "musopti_types.h"

#define RECORDER_BUFFER_SIZE 128

typedef void (*recorder_flush_cb_t)(const imu_sample_t *samples, size_t count);

typedef struct {
    uint16_t sample_rate_hz;
    recorder_flush_cb_t flush_cb;
} recorder_config_t;

esp_err_t recorder_init(const recorder_config_t *config);
esp_err_t recorder_reconfigure(uint16_t sample_rate_hz);
esp_err_t recorder_start(void);
esp_err_t recorder_stop(void);
esp_err_t recorder_push_sample(const imu_sample_t *sample);
bool recorder_is_active(void);
uint32_t recorder_get_sample_count(void);
