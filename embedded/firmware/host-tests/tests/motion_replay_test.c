#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "motion_detection.h"

typedef struct {
    musopti_exercise_type_t exercise;
    uint16_t expected_rep_count;
    uint16_t expected_hold_valid_count;
    uint16_t expected_hold_invalid_count;
    bool expect_session_stop;
} replay_expectations_t;

static const motion_detector_config_t *profile_for_exercise(musopti_exercise_type_t exercise)
{
    return motion_detector_get_profile(exercise);
}

static bool parse_exercise(const char *raw, musopti_exercise_type_t *exercise)
{
    if (strcmp(raw, "generic") == 0) {
        *exercise = EXERCISE_GENERIC;
        return true;
    }
    if (strcmp(raw, "bench_press") == 0) {
        *exercise = EXERCISE_BENCH_PRESS;
        return true;
    }
    if (strcmp(raw, "squat") == 0) {
        *exercise = EXERCISE_SQUAT;
        return true;
    }
    if (strcmp(raw, "deadlift") == 0) {
        *exercise = EXERCISE_DEADLIFT;
        return true;
    }
    return false;
}

static bool parse_bool(const char *raw, bool *value)
{
    if (strcmp(raw, "0") == 0 || strcmp(raw, "false") == 0) {
        *value = false;
        return true;
    }
    if (strcmp(raw, "1") == 0 || strcmp(raw, "true") == 0) {
        *value = true;
        return true;
    }
    return false;
}

static int load_expectations(const char *path, replay_expectations_t *out)
{
    FILE *file = fopen(path, "r");
    if (!file) {
        fprintf(stderr, "Failed to open expectations file: %s\n", path);
        return 1;
    }

    char line[256];
    memset(out, 0, sizeof(*out));
    out->exercise = EXERCISE_GENERIC;

    while (fgets(line, sizeof(line), file)) {
        char *newline = strchr(line, '\n');
        if (newline) {
            *newline = '\0';
        }
        if (line[0] == '\0' || line[0] == '#') {
            continue;
        }

        char *equals = strchr(line, '=');
        if (!equals) {
            continue;
        }

        *equals = '\0';
        const char *key = line;
        const char *value = equals + 1;

        if (strcmp(key, "exercise") == 0) {
            if (!parse_exercise(value, &out->exercise)) {
                fprintf(stderr, "Unsupported exercise in expectations: %s\n", value);
                fclose(file);
                return 1;
            }
        } else if (strcmp(key, "rep_count") == 0) {
            out->expected_rep_count = (uint16_t)strtoul(value, NULL, 10);
        } else if (strcmp(key, "hold_valid_count") == 0) {
            out->expected_hold_valid_count = (uint16_t)strtoul(value, NULL, 10);
        } else if (strcmp(key, "hold_invalid_count") == 0) {
            out->expected_hold_invalid_count = (uint16_t)strtoul(value, NULL, 10);
        } else if (strcmp(key, "session_stop") == 0) {
            if (!parse_bool(value, &out->expect_session_stop)) {
                fprintf(stderr, "Invalid session_stop value: %s\n", value);
                fclose(file);
                return 1;
            }
        }
    }

    fclose(file);
    return 0;
}

static int replay_fixture(const char *csv_path, const replay_expectations_t *expectations)
{
    FILE *file = fopen(csv_path, "r");
    if (!file) {
        fprintf(stderr, "Failed to open fixture: %s\n", csv_path);
        return 1;
    }

    if (motion_detector_init(profile_for_exercise(expectations->exercise)) != ESP_OK) {
        fprintf(stderr, "motion_detector_init failed\n");
        fclose(file);
        return 1;
    }

    char line[256];
    bool session_stop_seen = false;
    uint16_t hold_valid_count = 0;
    uint16_t hold_invalid_count = 0;

    while (fgets(line, sizeof(line), file)) {
        if (strncmp(line, "timestamp_ms", 12) == 0 || line[0] == '#') {
            continue;
        }

        double timestamp_ms = 0.0;
        double accel_x = 0.0;
        double accel_y = 0.0;
        double accel_z = 0.0;
        double gyro_x = 0.0;
        double gyro_y = 0.0;
        double gyro_z = 0.0;

        if (sscanf(line, "%lf,%lf,%lf,%lf,%lf,%lf,%lf",
                   &timestamp_ms,
                   &accel_x,
                   &accel_y,
                   &accel_z,
                   &gyro_x,
                   &gyro_y,
                   &gyro_z) != 7) {
            continue;
        }

        imu_sample_t sample = {
            .accel_x = (float)accel_x,
            .accel_y = (float)accel_y,
            .accel_z = (float)accel_z,
            .gyro_x = (float)gyro_x,
            .gyro_y = (float)gyro_y,
            .gyro_z = (float)gyro_z,
            .timestamp_us = (int64_t)(timestamp_ms * 1000.0),
        };

        musopti_event_t event;
        bool has_event = false;
        if (motion_detector_process(&sample, &event, &has_event) != ESP_OK) {
            fprintf(stderr, "motion_detector_process failed\n");
            fclose(file);
            return 1;
        }

        if (!has_event) {
            continue;
        }

        if (event.type == MUSOPTI_EVENT_HOLD_RESULT) {
            if (event.hold_valid) {
                hold_valid_count++;
            } else {
                hold_invalid_count++;
            }
        } else if (event.type == MUSOPTI_EVENT_SESSION_STOP) {
            session_stop_seen = true;
        }
    }

    fclose(file);

    uint16_t rep_count = motion_detector_get_rep_count();
    if (rep_count != expectations->expected_rep_count) {
        fprintf(stderr, "rep_count mismatch: expected %u got %u\n",
                expectations->expected_rep_count, rep_count);
        return 1;
    }
    if (hold_valid_count != expectations->expected_hold_valid_count) {
        fprintf(stderr, "hold_valid_count mismatch: expected %u got %u\n",
                expectations->expected_hold_valid_count, hold_valid_count);
        return 1;
    }
    if (hold_invalid_count != expectations->expected_hold_invalid_count) {
        fprintf(stderr, "hold_invalid_count mismatch: expected %u got %u\n",
                expectations->expected_hold_invalid_count, hold_invalid_count);
        return 1;
    }
    if (session_stop_seen != expectations->expect_session_stop) {
        fprintf(stderr, "session_stop mismatch: expected %d got %d\n",
                expectations->expect_session_stop, session_stop_seen);
        return 1;
    }

    return 0;
}

int main(int argc, char **argv)
{
    if (argc != 3) {
        fprintf(stderr, "Usage: %s <fixture.csv> <expectations>\n", argv[0]);
        return 1;
    }

    replay_expectations_t expectations;
    if (load_expectations(argv[2], &expectations) != 0) {
        return 1;
    }

    return replay_fixture(argv[1], &expectations);
}
