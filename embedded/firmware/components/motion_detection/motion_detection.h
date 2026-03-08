#pragma once

#include "esp_err.h"
#include "musopti_types.h"

typedef struct {
    musopti_exercise_type_t exercise;
    float accel_threshold_low;     /* below this magnitude deviation (m/s²) = quasi-still */
    float gyro_threshold_low;      /* below this (rad/s) = quasi-still */
    float accel_threshold_move;    /* above this = movement detected */
    bool  require_hold;            /* if false, skip hold phase (phase_a -> phase_b) */
    uint32_t hold_target_ms;       /* target hold duration (0 = no target) */
    uint32_t hold_tolerance_ms;    /* acceptable deviation from target */
    uint32_t min_rep_duration_ms;  /* minimum time for a valid rep */
    uint32_t idle_timeout_ms;      /* auto-stop session after this much idle time */
} motion_detector_config_t;

/* Per-exercise default profiles */
extern const motion_detector_config_t MOTION_PROFILE_GENERIC;
extern const motion_detector_config_t MOTION_PROFILE_BENCH_PRESS;
extern const motion_detector_config_t MOTION_PROFILE_SQUAT;
extern const motion_detector_config_t MOTION_PROFILE_DEADLIFT;

const motion_detector_config_t *motion_detector_get_profile(musopti_exercise_type_t ex);

esp_err_t motion_detector_init(const motion_detector_config_t *config);
esp_err_t motion_detector_reconfigure(const motion_detector_config_t *config);

/**
 * Feed one IMU sample to the detector.
 * If an event is produced, *has_event is set to true and *event_out is filled.
 */
esp_err_t motion_detector_process(const imu_sample_t *sample,
                                  musopti_event_t *event_out,
                                  bool *has_event);

motion_state_t motion_detector_get_state(void);
uint16_t motion_detector_get_rep_count(void);
void motion_detector_reset(void);
