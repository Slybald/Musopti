#include "audio_feedback.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/task.h"

#include <math.h>
#include <string.h>

static const char *TAG = "audio_fb";

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#define AUDIO_SAMPLE_RATE  16000
#define AUDIO_TASK_STACK   4096

/*
 * Hardware audio init depends on the BSP (ES8311 + I2S).
 * When CONFIG_MUSOPTI_AUDIO_SIMULATED is set, tones are logged instead of played.
 */

#if !defined(CONFIG_MUSOPTI_AUDIO_SIMULATED)
#include "driver/i2s_std.h"

#define I2S_MCLK_IO  19
#define I2S_SCLK_IO  20
#define I2S_LCLK_IO  22
#define I2S_DOUT_IO  23
#define I2S_DSIN_IO  21

static i2s_chan_handle_t s_tx_chan;
#endif

typedef struct {
    uint16_t freq_hz;
    uint16_t duration_ms;
} tone_def_t;

static const tone_def_t s_tone_defs[] = {
    [TONE_MOVEMENT_START] = { .freq_hz = 1000, .duration_ms = 100 },
    [TONE_HOLD]           = { .freq_hz = 800,  .duration_ms = 150 },
    [TONE_REP_COMPLETE]   = { .freq_hz = 500,  .duration_ms = 200 },
    [TONE_ERROR]          = { .freq_hz = 1200, .duration_ms = 80  },
};

static QueueHandle_t s_tone_queue;
static uint8_t s_volume = 80;

static void generate_sine(int16_t *buf, size_t num_samples, uint16_t freq_hz)
{
    float amp = (32767.0f * s_volume) / 100.0f;
    for (size_t i = 0; i < num_samples; i++) {
        float t = (float)i / AUDIO_SAMPLE_RATE;
        buf[i] = (int16_t)(amp * sinf(2.0f * (float)M_PI * freq_hz * t));
    }
}

static void play_tone_hw(const tone_def_t *def)
{
#if !defined(CONFIG_MUSOPTI_AUDIO_SIMULATED)
    size_t num_samples = (AUDIO_SAMPLE_RATE * def->duration_ms) / 1000;
    size_t buf_bytes = num_samples * sizeof(int16_t);

    int16_t *buf = malloc(buf_bytes);
    if (!buf) {
        ESP_LOGW(TAG, "No memory for tone buffer");
        return;
    }

    generate_sine(buf, num_samples, def->freq_hz);

    size_t written = 0;
    i2s_channel_write(s_tx_chan, buf, buf_bytes, &written, pdMS_TO_TICKS(500));

    free(buf);
#else
    ESP_LOGI(TAG, "[SIM] tone %d Hz for %d ms (vol=%d%%)",
             def->freq_hz, def->duration_ms, s_volume);
    vTaskDelay(pdMS_TO_TICKS(def->duration_ms));
#endif
}

static void audio_task(void *arg)
{
    (void)arg;
    audio_tone_t tone;

    while (1) {
        if (xQueueReceive(s_tone_queue, &tone, portMAX_DELAY) == pdTRUE) {
            if (tone == TONE_ERROR) {
                play_tone_hw(&s_tone_defs[TONE_ERROR]);
                vTaskDelay(pdMS_TO_TICKS(60));
                play_tone_hw(&s_tone_defs[TONE_ERROR]);
            } else if (tone < sizeof(s_tone_defs) / sizeof(s_tone_defs[0])) {
                play_tone_hw(&s_tone_defs[tone]);
            }
        }
    }
}

esp_err_t audio_feedback_init(void)
{
#if !defined(CONFIG_MUSOPTI_AUDIO_SIMULATED)
    i2s_chan_config_t chan_cfg = I2S_CHANNEL_DEFAULT_CONFIG(I2S_NUM_0, I2S_ROLE_MASTER);
    ESP_ERROR_CHECK(i2s_new_channel(&chan_cfg, &s_tx_chan, NULL));

    i2s_std_config_t std_cfg = {
        .clk_cfg = I2S_STD_CLK_DEFAULT_CONFIG(AUDIO_SAMPLE_RATE),
        .slot_cfg = I2S_STD_PHILIPS_SLOT_DEFAULT_CONFIG(I2S_DATA_BIT_WIDTH_16BIT, I2S_SLOT_MODE_MONO),
        .gpio_cfg = {
            .mclk = I2S_MCLK_IO,
            .bclk = I2S_SCLK_IO,
            .ws   = I2S_LCLK_IO,
            .dout = I2S_DOUT_IO,
            .din  = I2S_DSIN_IO,
            .invert_flags = { .mclk_inv = false, .bclk_inv = false, .ws_inv = false },
        },
    };
    ESP_ERROR_CHECK(i2s_channel_init_std_mode(s_tx_chan, &std_cfg));
    ESP_ERROR_CHECK(i2s_channel_enable(s_tx_chan));

    ESP_LOGI(TAG, "I2S + ES8311 audio initialized");
#else
    ESP_LOGI(TAG, "Audio feedback initialized (simulated)");
#endif

    s_tone_queue = xQueueCreate(4, sizeof(audio_tone_t));
    if (!s_tone_queue) {
        return ESP_ERR_NO_MEM;
    }

    xTaskCreate(audio_task, "audio_fb", AUDIO_TASK_STACK, NULL, 3, NULL);
    return ESP_OK;
}

esp_err_t audio_feedback_play(audio_tone_t tone)
{
    if (!s_tone_queue) {
        return ESP_ERR_INVALID_STATE;
    }
    if (xQueueSend(s_tone_queue, &tone, 0) != pdTRUE) {
        ESP_LOGW(TAG, "Tone queue full, dropping");
        return ESP_ERR_NO_MEM;
    }
    return ESP_OK;
}

esp_err_t audio_feedback_set_volume(uint8_t percent)
{
    s_volume = (percent > 100) ? 100 : percent;
    return ESP_OK;
}
