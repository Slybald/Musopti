#include <stdio.h>
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_log.h"

#include "ble_config_validation.h"
#include "musopti_types.h"
#include "imu.h"
#include "motion_detection.h"
#include "ble_service.h"
#include "recorder.h"
#include "audio_feedback.h"
#include "display.h"
#include "power_mgmt.h"

static const char *TAG = "musopti";

#define LOOP_PERIOD_MS 10  /* ~100 Hz */

static musopti_device_mode_t s_device_mode = MUSOPTI_MODE_DETECTION;
static musopti_exercise_type_t s_exercise  = EXERCISE_GENERIC;
static display_state_t s_disp_state;
static imu_config_t s_imu_cfg = IMU_CONFIG_DEFAULT();
static motion_detector_config_t s_detector_cfg;
static uint16_t s_detection_sample_rate_hz = 100;
static uint16_t s_recording_sample_rate_hz = 100;
static volatile uint32_t s_loop_period_ms = LOOP_PERIOD_MS;

#ifndef MUSOPTI_FW_VERSION_MAJOR
#define MUSOPTI_FW_VERSION_MAJOR 1
#endif

#ifndef MUSOPTI_FW_VERSION_MINOR
#define MUSOPTI_FW_VERSION_MINOR 0
#endif

#ifndef MUSOPTI_FW_VERSION_PATCH
#define MUSOPTI_FW_VERSION_PATCH 0
#endif

static uint32_t loop_period_ms_for_rate(uint16_t sample_rate_hz)
{
    if (sample_rate_hz == 0) {
        return LOOP_PERIOD_MS;
    }

    uint32_t period_ms = (1000u + sample_rate_hz - 1u) / sample_rate_hz;
    return period_ms == 0 ? 1 : period_ms;
}

static esp_err_t apply_sampling_rate(uint16_t sample_rate_hz)
{
    if (sample_rate_hz == 0) {
        return ESP_ERR_INVALID_ARG;
    }

    imu_config_t next_cfg = s_imu_cfg;
    next_cfg.sample_rate_hz = sample_rate_hz;

    esp_err_t ret = imu_reconfigure(&next_cfg);
    if (ret != ESP_OK) {
        return ret;
    }

    ret = recorder_reconfigure(sample_rate_hz);
    if (ret != ESP_OK) {
        imu_reconfigure(&s_imu_cfg);
        return ret;
    }

    s_imu_cfg = next_cfg;
    s_loop_period_ms = loop_period_ms_for_rate(sample_rate_hz);
    ESP_LOGI(TAG, "Sampling rate applied: %u Hz (loop=%lu ms)",
             sample_rate_hz, (unsigned long)s_loop_period_ms);
    return ESP_OK;
}

static bool motion_detector_config_equals(const motion_detector_config_t *lhs,
                                          const motion_detector_config_t *rhs)
{
    return lhs->exercise == rhs->exercise &&
           lhs->accel_threshold_low == rhs->accel_threshold_low &&
           lhs->gyro_threshold_low == rhs->gyro_threshold_low &&
           lhs->accel_threshold_move == rhs->accel_threshold_move &&
           lhs->require_hold == rhs->require_hold &&
           lhs->hold_target_ms == rhs->hold_target_ms &&
           lhs->hold_tolerance_ms == rhs->hold_tolerance_ms &&
           lhs->min_rep_duration_ms == rhs->min_rep_duration_ms &&
           lhs->idle_timeout_ms == rhs->idle_timeout_ms;
}

static void build_motion_detector_config(musopti_exercise_type_t exercise,
                                         const musopti_ble_config_payload_t *cfg,
                                         motion_detector_config_t *out)
{
    const motion_detector_config_t *profile = motion_detector_get_profile(exercise);
    motion_detector_config_t custom = *profile;

    custom.exercise = exercise;
    if (cfg->hold_target_ms == 0) {
        custom.require_hold = false;
        custom.hold_target_ms = 0;
        custom.hold_tolerance_ms = 0;
    } else {
        custom.require_hold = true;
        custom.hold_target_ms = cfg->hold_target_ms;
        custom.hold_tolerance_ms = cfg->hold_tolerance_ms;
    }

    if (cfg->min_rep_duration_ms > 0) {
        custom.min_rep_duration_ms = cfg->min_rep_duration_ms;
    }

    *out = custom;
}

static esp_err_t apply_motion_detector_config(const motion_detector_config_t *cfg)
{
    if (!cfg) {
        return ESP_ERR_INVALID_ARG;
    }

    bool changed = !motion_detector_config_equals(cfg, &s_detector_cfg);
    if (!changed) {
        return ESP_OK;
    }

    if (motion_detector_get_state() != MOTION_STATE_IDLE) {
        motion_detector_reset();
    }

    esp_err_t ret = motion_detector_reconfigure(cfg);
    if (ret == ESP_OK) {
        s_detector_cfg = *cfg;
    }
    return ret;
}

static musopti_ble_config_payload_t current_ble_config(void)
{
    musopti_ble_config_payload_t applied = {
        .version = 1,
        .device_mode = (uint8_t)s_device_mode,
        .exercise_type = (uint8_t)s_exercise,
        .reserved = 0,
        .hold_target_ms = s_detector_cfg.require_hold ? (uint16_t)s_detector_cfg.hold_target_ms : 0,
        .hold_tolerance_ms = s_detector_cfg.require_hold ? (uint16_t)s_detector_cfg.hold_tolerance_ms : 0,
        .min_rep_duration_ms = (uint16_t)s_detector_cfg.min_rep_duration_ms,
        .sample_rate_hz = s_imu_cfg.sample_rate_hz,
    };
    return applied;
}

static void publish_ble_status(void)
{
    musopti_ble_status_payload_t status = {
        .version = 1,
        .flags = recorder_is_active() ? MUSOPTI_STATUS_FLAG_RECORDING_ACTIVE : 0,
        .battery_pct = 0xFF,
        .device_mode = (uint8_t)s_device_mode,
        .exercise_type = (uint8_t)s_exercise,
        .motion_state = (uint8_t)motion_detector_get_state(),
        .sample_rate_hz = s_imu_cfg.sample_rate_hz,
        .config_revision = 0,
        .fw_major = MUSOPTI_FW_VERSION_MAJOR,
        .fw_minor = MUSOPTI_FW_VERSION_MINOR,
        .fw_patch = MUSOPTI_FW_VERSION_PATCH,
        .reserved = 0,
    };

#if defined(CONFIG_MUSOPTI_IMU_SIMULATED)
    status.flags |= MUSOPTI_STATUS_FLAG_IMU_SIMULATED;
#endif
#if defined(CONFIG_MUSOPTI_DISPLAY_SIMULATED)
    status.flags |= MUSOPTI_STATUS_FLAG_DISPLAY_SIMULATED;
#endif
#if defined(CONFIG_MUSOPTI_AUDIO_SIMULATED)
    status.flags |= MUSOPTI_STATUS_FLAG_AUDIO_SIMULATED;
#endif

    ble_service_set_status(&status);
}

/* ---- recorder flush callback: forward raw samples over BLE ---- */

static void recorder_flush_over_ble(const imu_sample_t *samples, size_t count)
{
    if (ble_service_is_connected()) {
        size_t sent = 0;
        while (sent < count) {
            size_t chunk = (count - sent > 7) ? 7 : (count - sent);
            ble_service_notify_raw_data(&samples[sent], chunk);
            sent += chunk;
        }
    }
}

/* ---- BLE config change callback ---- */

static esp_err_t on_ble_config_change(const musopti_ble_config_payload_t *cfg,
                                      musopti_ble_config_payload_t *applied)
{
    if (!cfg || !applied) {
        return ESP_ERR_INVALID_ARG;
    }

    esp_err_t validation_err = validate_ble_config(cfg);
    if (validation_err != ESP_OK) {
        return validation_err;
    }

    ESP_LOGI(TAG, "BLE config received: mode=%d exercise=%d",
             cfg->device_mode, cfg->exercise_type);

    musopti_device_mode_t new_mode = (musopti_device_mode_t)cfg->device_mode;
    musopti_exercise_type_t new_ex = (musopti_exercise_type_t)cfg->exercise_type;
    motion_detector_config_t next_detector_cfg;
    build_motion_detector_config(new_ex, cfg, &next_detector_cfg);

    musopti_device_mode_t prev_mode = s_device_mode;
    uint16_t target_recording_rate_hz = cfg->sample_rate_hz;
    uint16_t target_active_rate_hz = (new_mode == MUSOPTI_MODE_RECORDING)
                                   ? target_recording_rate_hz
                                   : s_detection_sample_rate_hz;
    bool leaving_recording = prev_mode == MUSOPTI_MODE_RECORDING &&
                             new_mode != MUSOPTI_MODE_RECORDING;
    bool entering_recording = prev_mode != MUSOPTI_MODE_RECORDING &&
                              new_mode == MUSOPTI_MODE_RECORDING;

    if (leaving_recording) {
        ESP_ERROR_CHECK(recorder_stop());
    }

    if (target_active_rate_hz != s_imu_cfg.sample_rate_hz) {
        esp_err_t ret = apply_sampling_rate(target_active_rate_hz);
        if (ret != ESP_OK) {
            if (leaving_recording) {
                recorder_start();
            }
            return ret;
        }
    }

    if (entering_recording) {
        esp_err_t ret = recorder_start();
        if (ret != ESP_OK) {
            return ret;
        }
    }

    esp_err_t ret = apply_motion_detector_config(&next_detector_cfg);
    if (ret != ESP_OK) {
        if (entering_recording) {
            recorder_stop();
        } else if (leaving_recording) {
            recorder_start();
        }
        return ret;
    }

    s_exercise = new_ex;
    s_recording_sample_rate_hz = target_recording_rate_hz;
    s_device_mode = new_mode;
    *applied = current_ble_config();

    publish_ble_status();
    ESP_LOGI(TAG, "Applied config: mode=%s exercise=%s sample_rate=%u",
             musopti_device_mode_to_str(s_device_mode),
             musopti_exercise_type_to_str(s_exercise),
             applied->sample_rate_hz);
    return ESP_OK;
}

/* ---- display state helper ---- */

static void update_display(void)
{
    s_disp_state.mode = s_device_mode;
    s_disp_state.exercise = s_exercise;
    s_disp_state.state = motion_detector_get_state();
    s_disp_state.rep_count = motion_detector_get_rep_count();
    s_disp_state.ble_connected = ble_service_is_connected();
    s_disp_state.battery_pct = 100; /* TODO: read from AXP2101 */
    display_update(&s_disp_state);
}

/* ---- main processing loop ---- */

static void motion_loop(void *arg)
{
    (void)arg;

    imu_sample_t sample;
    musopti_event_t event;
    bool has_event;

    while (1) {
        esp_err_t ret = imu_read(&sample);
        if (ret != ESP_OK) {
            vTaskDelay(pdMS_TO_TICKS(LOOP_PERIOD_MS));
            continue;
        }

        switch (s_device_mode) {
        case MUSOPTI_MODE_DETECTION:
            ret = motion_detector_process(&sample, &event, &has_event);
            if (ret == ESP_OK && has_event) {
                ESP_LOGI(TAG, "[%s] state=%s rep=%d",
                         musopti_event_type_to_str(event.type),
                         motion_state_to_str(event.state),
                         event.rep_count);

                /* Audio feedback */
                if (event.type == MUSOPTI_EVENT_STATE_CHANGE) {
                    if (event.state == MOTION_STATE_PHASE_A) {
                        audio_feedback_play(TONE_MOVEMENT_START);
                    } else if (event.state == MOTION_STATE_HOLD) {
                        audio_feedback_play(TONE_HOLD);
                    }
                } else if (event.type == MUSOPTI_EVENT_REP_COMPLETE) {
                    audio_feedback_play(TONE_REP_COMPLETE);
                }

                /* Display */
                if (event.type == MUSOPTI_EVENT_HOLD_RESULT) {
                    s_disp_state.last_hold_ms = event.hold_duration_ms;
                    s_disp_state.last_hold_valid = event.hold_valid;
                }
                update_display();

                /* BLE notify */
                if (ble_service_is_connected()) {
                    ble_service_notify_event(&event);
                }
                publish_ble_status();
            }
            break;

        case MUSOPTI_MODE_RECORDING:
            recorder_push_sample(&sample);
            break;

        case MUSOPTI_MODE_IDLE:
        default:
            break;
        }

        vTaskDelay(pdMS_TO_TICKS(s_loop_period_ms));
    }
}

/* ---- entry point ---- */

void app_main(void)
{
    ESP_LOGI(TAG, "=== Musopti starting ===");

    /* Power management */
    ESP_ERROR_CHECK(power_mgmt_init());

    /* Display */
    ESP_ERROR_CHECK(display_init());

    /* Audio feedback */
    ESP_ERROR_CHECK(audio_feedback_init());

    /* IMU */
    ESP_ERROR_CHECK(imu_init(&s_imu_cfg));
    s_detection_sample_rate_hz = s_imu_cfg.sample_rate_hz;
    s_recording_sample_rate_hz = s_imu_cfg.sample_rate_hz;
    s_loop_period_ms = loop_period_ms_for_rate(s_detection_sample_rate_hz);

    /* Motion detector — default profile */
    const motion_detector_config_t *profile = motion_detector_get_profile(s_exercise);
    ESP_ERROR_CHECK(motion_detector_init(profile));
    s_detector_cfg = *profile;

    /* Recorder */
    recorder_config_t rec_cfg = {
        .sample_rate_hz = s_imu_cfg.sample_rate_hz,
        .flush_cb = recorder_flush_over_ble,
    };
    ESP_ERROR_CHECK(recorder_init(&rec_cfg));

    /* BLE */
    ble_service_config_t ble_cfg = {
        .on_config_change = on_ble_config_change,
    };
    ESP_ERROR_CHECK(ble_service_init(&ble_cfg));
    publish_ble_status();

    /* Initial display state */
    memset(&s_disp_state, 0, sizeof(s_disp_state));
    update_display();

    /* Main processing loop */
    xTaskCreate(motion_loop, "motion_loop", 8192, NULL, 5, NULL);

    ESP_LOGI(TAG, "=== Musopti ready ===");
}
