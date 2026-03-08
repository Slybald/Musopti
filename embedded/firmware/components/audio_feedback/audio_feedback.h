#pragma once

#include "esp_err.h"

typedef enum {
    TONE_MOVEMENT_START = 0,  /* short high-pitched beep */
    TONE_HOLD,                /* medium tone */
    TONE_REP_COMPLETE,        /* low-pitched beep */
    TONE_ERROR,               /* double short beep */
} audio_tone_t;

esp_err_t audio_feedback_init(void);

/**
 * Play a tone asynchronously. Non-blocking: queues the request
 * and returns immediately. The tone plays on a dedicated task.
 */
esp_err_t audio_feedback_play(audio_tone_t tone);

esp_err_t audio_feedback_set_volume(uint8_t percent);
