#include "ble_config_validation.h"

static bool is_valid_device_mode(uint8_t raw_mode)
{
    switch ((musopti_device_mode_t)raw_mode) {
    case MUSOPTI_MODE_IDLE:
    case MUSOPTI_MODE_DETECTION:
    case MUSOPTI_MODE_RECORDING:
        return true;
    default:
        return false;
    }
}

static bool is_valid_exercise_type(uint8_t raw_exercise)
{
    return raw_exercise < EXERCISE_TYPE_COUNT;
}

bool musopti_sample_rate_is_supported(uint16_t sample_rate_hz)
{
    return sample_rate_hz == 50 || sample_rate_hz == 100 || sample_rate_hz == 200;
}

esp_err_t validate_ble_config(const musopti_ble_config_payload_t *config)
{
    if (!config) {
        return ESP_ERR_INVALID_ARG;
    }

    if (config->version != 1) {
        return ESP_ERR_INVALID_VERSION;
    }

    if (!is_valid_device_mode(config->device_mode) ||
        !is_valid_exercise_type(config->exercise_type) ||
        !musopti_sample_rate_is_supported(config->sample_rate_hz)) {
        return ESP_ERR_INVALID_ARG;
    }

    if (config->hold_target_ms == 0) {
        if (config->hold_tolerance_ms != 0) {
            return ESP_ERR_INVALID_ARG;
        }
    } else if (config->hold_tolerance_ms > config->hold_target_ms) {
        return ESP_ERR_INVALID_ARG;
    }

    return ESP_OK;
}
