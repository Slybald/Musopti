#include "motion_detection.h"
#include "esp_log.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>

static const char *TAG = "motion_det";

/* --------------- exercise profiles --------------- */

const motion_detector_config_t MOTION_PROFILE_GENERIC = {
    .exercise            = EXERCISE_GENERIC,
    .accel_threshold_low = 0.6f,
    .gyro_threshold_low  = 0.2f,
    .accel_threshold_move= 1.5f,
    .require_hold        = false,
    .hold_target_ms      = 0,
    .hold_tolerance_ms   = 0,
    .min_rep_duration_ms = 600,
    .idle_timeout_ms     = 10000,
};

const motion_detector_config_t MOTION_PROFILE_BENCH_PRESS = {
    .exercise            = EXERCISE_BENCH_PRESS,
    .accel_threshold_low = 0.5f,
    .gyro_threshold_low  = 0.15f,
    .accel_threshold_move= 2.0f,
    .require_hold        = true,
    .hold_target_ms      = 3000,
    .hold_tolerance_ms   = 200,
    .min_rep_duration_ms = 1000,
    .idle_timeout_ms     = 15000,
};

const motion_detector_config_t MOTION_PROFILE_SQUAT = {
    .exercise            = EXERCISE_SQUAT,
    .accel_threshold_low = 0.5f,
    .gyro_threshold_low  = 0.15f,
    .accel_threshold_move= 1.8f,
    .require_hold        = false,
    .hold_target_ms      = 0,
    .hold_tolerance_ms   = 0,
    .min_rep_duration_ms = 800,
    .idle_timeout_ms     = 12000,
};

const motion_detector_config_t MOTION_PROFILE_DEADLIFT = {
    .exercise            = EXERCISE_DEADLIFT,
    .accel_threshold_low = 0.6f,
    .gyro_threshold_low  = 0.2f,
    .accel_threshold_move= 2.5f,
    .require_hold        = false,
    .hold_target_ms      = 0,
    .hold_tolerance_ms   = 0,
    .min_rep_duration_ms = 1200,
    .idle_timeout_ms     = 15000,
};

const motion_detector_config_t *motion_detector_get_profile(musopti_exercise_type_t ex)
{
    switch (ex) {
    case EXERCISE_BENCH_PRESS: return &MOTION_PROFILE_BENCH_PRESS;
    case EXERCISE_SQUAT:       return &MOTION_PROFILE_SQUAT;
    case EXERCISE_DEADLIFT:    return &MOTION_PROFILE_DEADLIFT;
    default:                   return &MOTION_PROFILE_GENERIC;
    }
}

/* --------------- internal state --------------- */

static motion_detector_config_t s_cfg;
static motion_state_t s_state;
static uint16_t s_rep_count;

static int64_t s_rep_start_us;
static int64_t s_phase_start_us;
static int64_t s_hold_start_us;
static int64_t s_last_activity_us;

/* --------------- helpers --------------- */

static float compute_accel_deviation(const imu_sample_t *s)
{
    float mag = sqrtf(s->accel_x * s->accel_x +
                      s->accel_y * s->accel_y +
                      s->accel_z * s->accel_z);
    return fabsf(mag - MUSOPTI_GRAVITY_MPS2);
}

static float compute_gyro_magnitude(const imu_sample_t *s)
{
    return sqrtf(s->gyro_x * s->gyro_x +
                 s->gyro_y * s->gyro_y +
                 s->gyro_z * s->gyro_z);
}

static bool is_still(float accel_dev, float gyro_mag)
{
    return (accel_dev < s_cfg.accel_threshold_low) &&
           (gyro_mag < s_cfg.gyro_threshold_low);
}

static bool is_moving(float accel_dev)
{
    return accel_dev > s_cfg.accel_threshold_move;
}

static void emit_event(musopti_event_t *out, musopti_event_type_t type,
                       const imu_sample_t *sample)
{
    memset(out, 0, sizeof(*out));
    out->type = type;
    out->state = s_state;
    out->exercise = s_cfg.exercise;
    out->rep_count = s_rep_count;
    out->timestamp_us = sample->timestamp_us;
}

static uint32_t elapsed_ms(int64_t from_us, int64_t to_us)
{
    return (uint32_t)((to_us - from_us) / 1000);
}

/* --------------- public API --------------- */

esp_err_t motion_detector_init(const motion_detector_config_t *config)
{
    if (!config) {
        return ESP_ERR_INVALID_ARG;
    }
    s_cfg = *config;
    s_state = MOTION_STATE_IDLE;
    s_rep_count = 0;
    s_rep_start_us = 0;
    s_phase_start_us = 0;
    s_hold_start_us = 0;
    s_last_activity_us = 0;

    ESP_LOGI(TAG, "Motion detector initialized: exercise=%s hold=%s",
             musopti_exercise_type_to_str(s_cfg.exercise),
             s_cfg.require_hold ? "required" : "skip");
    return ESP_OK;
}

esp_err_t motion_detector_reconfigure(const motion_detector_config_t *config)
{
    if (!config) {
        return ESP_ERR_INVALID_ARG;
    }
    s_cfg = *config;
    ESP_LOGI(TAG, "Motion detector reconfigured: exercise=%s",
             musopti_exercise_type_to_str(s_cfg.exercise));
    return ESP_OK;
}

esp_err_t motion_detector_process(const imu_sample_t *sample,
                                  musopti_event_t *event_out,
                                  bool *has_event)
{
    if (!sample || !event_out || !has_event) {
        return ESP_ERR_INVALID_ARG;
    }

    *has_event = false;

    if (s_state == MOTION_STATE_IDLE &&
        s_cfg.idle_timeout_ms > 0 &&
        s_last_activity_us != 0 &&
        elapsed_ms(s_last_activity_us, sample->timestamp_us) >= s_cfg.idle_timeout_ms) {
        emit_event(event_out, MUSOPTI_EVENT_SESSION_STOP, sample);
        *has_event = true;
        motion_detector_reset();
        return ESP_OK;
    }

    float accel_dev = compute_accel_deviation(sample);
    float gyro_mag  = compute_gyro_magnitude(sample);
    bool still = is_still(accel_dev, gyro_mag);
    bool moving = is_moving(accel_dev);

    motion_state_t prev = s_state;

    switch (s_state) {
    case MOTION_STATE_IDLE:
        if (moving) {
            s_state = MOTION_STATE_PHASE_A;
            s_rep_start_us = sample->timestamp_us;
            s_phase_start_us = sample->timestamp_us;
            s_last_activity_us = sample->timestamp_us;
        }
        break;

    case MOTION_STATE_PHASE_A:
        s_last_activity_us = sample->timestamp_us;
        if (still) {
            if (s_cfg.require_hold) {
                s_state = MOTION_STATE_HOLD;
                s_hold_start_us = sample->timestamp_us;
            } else {
                s_state = MOTION_STATE_PHASE_B;
                s_phase_start_us = sample->timestamp_us;
            }
        }
        break;

    case MOTION_STATE_HOLD:
        if (moving) {
            uint32_t hold_ms = elapsed_ms(s_hold_start_us, sample->timestamp_us);
            s_state = MOTION_STATE_PHASE_B;
            s_phase_start_us = sample->timestamp_us;
            s_last_activity_us = sample->timestamp_us;

            emit_event(event_out, MUSOPTI_EVENT_HOLD_RESULT, sample);
            event_out->hold_duration_ms = hold_ms;

            if (s_cfg.hold_target_ms > 0) {
                int32_t diff = (int32_t)hold_ms - (int32_t)s_cfg.hold_target_ms;
                event_out->hold_valid = (abs(diff) <= (int32_t)s_cfg.hold_tolerance_ms);
            } else {
                event_out->hold_valid = true;
            }

            *has_event = true;
            ESP_LOGI(TAG, "Hold ended: %lu ms (target %lu, %s)",
                     (unsigned long)hold_ms,
                     (unsigned long)s_cfg.hold_target_ms,
                     event_out->hold_valid ? "VALID" : "INVALID");
        }
        break;

    case MOTION_STATE_PHASE_B:
        s_last_activity_us = sample->timestamp_us;
        if (still) {
            int64_t rep_start_us = (s_rep_start_us != 0) ? s_rep_start_us : s_phase_start_us;
            uint32_t total_rep_ms = elapsed_ms(rep_start_us, sample->timestamp_us);
            bool valid = (total_rep_ms >= s_cfg.min_rep_duration_ms);

            if (valid) {
                s_rep_count++;
                s_state = MOTION_STATE_REP_COMPLETE;
            } else {
                s_state = MOTION_STATE_REP_INVALID;
            }

            emit_event(event_out, MUSOPTI_EVENT_REP_COMPLETE, sample);
            *has_event = true;
            ESP_LOGI(TAG, "Rep #%d %s (dur=%lu ms)", s_rep_count,
                     valid ? "valid" : "invalid",
                     (unsigned long)total_rep_ms);

            /* Transient states -- return to idle next cycle */
            s_state = MOTION_STATE_IDLE;
            s_rep_start_us = 0;
        }
        break;

    case MOTION_STATE_REP_COMPLETE:
    case MOTION_STATE_REP_INVALID:
        s_state = MOTION_STATE_IDLE;
        break;
    }

    if (prev != s_state && !(*has_event)) {
        emit_event(event_out, MUSOPTI_EVENT_STATE_CHANGE, sample);
        *has_event = true;
    }

    return ESP_OK;
}

motion_state_t motion_detector_get_state(void)
{
    return s_state;
}

uint16_t motion_detector_get_rep_count(void)
{
    return s_rep_count;
}

void motion_detector_reset(void)
{
    s_state = MOTION_STATE_IDLE;
    s_rep_count = 0;
    s_rep_start_us = 0;
    s_phase_start_us = 0;
    s_hold_start_us = 0;
    s_last_activity_us = 0;
}
