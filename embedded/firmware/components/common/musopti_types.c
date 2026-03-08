#include "musopti_types.h"

const char *motion_state_to_str(motion_state_t state)
{
    switch (state) {
    case MOTION_STATE_IDLE:         return "idle";
    case MOTION_STATE_PHASE_A:      return "phase_a";
    case MOTION_STATE_HOLD:         return "hold";
    case MOTION_STATE_PHASE_B:      return "phase_b";
    case MOTION_STATE_REP_COMPLETE: return "rep_complete";
    case MOTION_STATE_REP_INVALID:  return "rep_invalid";
    default:                        return "unknown";
    }
}

const char *musopti_event_type_to_str(musopti_event_type_t type)
{
    switch (type) {
    case MUSOPTI_EVENT_STATE_CHANGE: return "state_change";
    case MUSOPTI_EVENT_REP_COMPLETE: return "rep_complete";
    case MUSOPTI_EVENT_HOLD_RESULT:  return "hold_result";
    case MUSOPTI_EVENT_SESSION_START:return "session_start";
    case MUSOPTI_EVENT_SESSION_STOP: return "session_stop";
    default:                         return "unknown";
    }
}

const char *musopti_device_mode_to_str(musopti_device_mode_t mode)
{
    switch (mode) {
    case MUSOPTI_MODE_IDLE:      return "idle";
    case MUSOPTI_MODE_DETECTION: return "detection";
    case MUSOPTI_MODE_RECORDING: return "recording";
    default:                     return "unknown";
    }
}

const char *musopti_exercise_type_to_str(musopti_exercise_type_t type)
{
    switch (type) {
    case EXERCISE_GENERIC:     return "generic";
    case EXERCISE_BENCH_PRESS: return "bench_press";
    case EXERCISE_SQUAT:       return "squat";
    case EXERCISE_DEADLIFT:    return "deadlift";
    case EXERCISE_CUSTOM:      return "custom";
    default:                   return "unknown";
    }
}
