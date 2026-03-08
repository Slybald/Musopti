#include <stdio.h>

#include "ble_config_validation.h"

static int expect_equal(esp_err_t expected, esp_err_t actual, const char *label)
{
    if (expected != actual) {
        fprintf(stderr, "%s: expected %s, got %s\n",
                label, esp_err_to_name(expected), esp_err_to_name(actual));
        return 1;
    }
    return 0;
}

int main(void)
{
    int failures = 0;

    musopti_ble_config_payload_t valid = {
        .version = 1,
        .device_mode = MUSOPTI_MODE_RECORDING,
        .exercise_type = EXERCISE_BENCH_PRESS,
        .hold_target_ms = 3000,
        .hold_tolerance_ms = 200,
        .min_rep_duration_ms = 1000,
        .sample_rate_hz = 200,
    };

    failures += expect_equal(ESP_OK, validate_ble_config(&valid), "valid config");

    musopti_ble_config_payload_t bad_version = valid;
    bad_version.version = 2;
    failures += expect_equal(
        ESP_ERR_INVALID_VERSION,
        validate_ble_config(&bad_version),
        "reject invalid version"
    );

    musopti_ble_config_payload_t bad_hold = valid;
    bad_hold.hold_target_ms = 1000;
    bad_hold.hold_tolerance_ms = 1500;
    failures += expect_equal(
        ESP_ERR_INVALID_ARG,
        validate_ble_config(&bad_hold),
        "reject hold tolerance larger than target"
    );

    musopti_ble_config_payload_t bad_rate = valid;
    bad_rate.sample_rate_hz = 125;
    failures += expect_equal(
        ESP_ERR_INVALID_ARG,
        validate_ble_config(&bad_rate),
        "reject unsupported sample rate"
    );

    musopti_ble_config_payload_t no_hold = valid;
    no_hold.hold_target_ms = 0;
    no_hold.hold_tolerance_ms = 0;
    failures += expect_equal(ESP_OK, validate_ble_config(&no_hold), "allow no-hold config");

    return failures == 0 ? 0 : 1;
}
