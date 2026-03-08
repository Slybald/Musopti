#pragma once

#include "esp_err.h"
#include "musopti_types.h"

typedef esp_err_t (*ble_config_change_cb_t)(
    const musopti_ble_config_payload_t *requested,
    musopti_ble_config_payload_t *applied
);

typedef struct {
    ble_config_change_cb_t on_config_change;
} ble_service_config_t;

esp_err_t ble_service_init(const ble_service_config_t *config);
esp_err_t ble_service_set_status(const musopti_ble_status_payload_t *status);
esp_err_t ble_service_notify_event(const musopti_event_t *event);
esp_err_t ble_service_notify_raw_data(const imu_sample_t *samples, size_t count);
bool ble_service_is_connected(void);
