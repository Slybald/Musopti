#include "recorder.h"
#include "esp_log.h"
#include <string.h>

static const char *TAG = "recorder";

static recorder_config_t s_cfg;
static bool s_active;
static imu_sample_t s_buffer[RECORDER_BUFFER_SIZE];
static size_t s_buf_pos;
static uint32_t s_total_samples;

esp_err_t recorder_init(const recorder_config_t *config)
{
    if (!config || !config->flush_cb) {
        return ESP_ERR_INVALID_ARG;
    }
    s_cfg = *config;
    s_active = false;
    s_buf_pos = 0;
    s_total_samples = 0;

    ESP_LOGI(TAG, "Recorder initialized (rate=%d Hz, buf=%d)",
             s_cfg.sample_rate_hz, RECORDER_BUFFER_SIZE);
    return ESP_OK;
}

esp_err_t recorder_reconfigure(uint16_t sample_rate_hz)
{
    if (sample_rate_hz == 0) {
        return ESP_ERR_INVALID_ARG;
    }

    s_cfg.sample_rate_hz = sample_rate_hz;
    ESP_LOGI(TAG, "Recorder sample rate set to %d Hz", s_cfg.sample_rate_hz);
    return ESP_OK;
}

esp_err_t recorder_start(void)
{
    s_active = true;
    s_buf_pos = 0;
    s_total_samples = 0;
    ESP_LOGI(TAG, "Recording started");
    return ESP_OK;
}

esp_err_t recorder_stop(void)
{
    if (s_active && s_buf_pos > 0 && s_cfg.flush_cb) {
        s_cfg.flush_cb(s_buffer, s_buf_pos);
    }
    s_active = false;
    ESP_LOGI(TAG, "Recording stopped (%lu samples total)",
             (unsigned long)s_total_samples);
    return ESP_OK;
}

esp_err_t recorder_push_sample(const imu_sample_t *sample)
{
    if (!sample) {
        return ESP_ERR_INVALID_ARG;
    }
    if (!s_active) {
        return ESP_ERR_INVALID_STATE;
    }

    s_buffer[s_buf_pos++] = *sample;
    s_total_samples++;

    if (s_buf_pos >= RECORDER_BUFFER_SIZE) {
        if (s_cfg.flush_cb) {
            s_cfg.flush_cb(s_buffer, s_buf_pos);
        }
        s_buf_pos = 0;
    }

    return ESP_OK;
}

bool recorder_is_active(void)
{
    return s_active;
}

uint32_t recorder_get_sample_count(void)
{
    return s_total_samples;
}
