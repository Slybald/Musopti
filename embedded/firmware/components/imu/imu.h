#pragma once

#include "esp_err.h"
#include "musopti_types.h"

typedef enum {
    IMU_SOURCE_HARDWARE = 0,
    IMU_SOURCE_SIMULATED,
} imu_source_type_t;

typedef struct {
    imu_source_type_t source;
    uint16_t sample_rate_hz;
} imu_config_t;

#define IMU_CONFIG_DEFAULT() { \
    .source = IMU_SOURCE_HARDWARE, \
    .sample_rate_hz = 100, \
}

esp_err_t imu_init(const imu_config_t *config);
esp_err_t imu_reconfigure(const imu_config_t *config);
esp_err_t imu_read(imu_sample_t *sample);
