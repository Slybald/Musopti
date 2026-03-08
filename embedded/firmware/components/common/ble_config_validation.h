#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"
#include "musopti_types.h"

bool musopti_sample_rate_is_supported(uint16_t sample_rate_hz);
esp_err_t validate_ble_config(const musopti_ble_config_payload_t *config);
