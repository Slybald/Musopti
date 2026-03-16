#include "i2c_bus.h"

#include "esp_log.h"

static const char *TAG = "i2c_bus";

static i2c_master_bus_handle_t s_bus_handle;
static bool s_bus_initialized;
static i2c_port_num_t s_bus_port;
static int s_bus_sda_io_num;
static int s_bus_scl_io_num;
static uint32_t s_bus_scl_speed_hz;

esp_err_t musopti_i2c_bus_get(i2c_port_num_t port,
                              int sda_io_num,
                              int scl_io_num,
                              uint32_t scl_speed_hz,
                              i2c_master_bus_handle_t *out_bus)
{
    if (!out_bus) {
        return ESP_ERR_INVALID_ARG;
    }

    if (s_bus_initialized) {
        bool same_config = s_bus_port == port &&
                           s_bus_sda_io_num == sda_io_num &&
                           s_bus_scl_io_num == scl_io_num &&
                           s_bus_scl_speed_hz == scl_speed_hz;
        if (!same_config) {
            ESP_LOGW(TAG,
                     "Reusing I2C bus with existing config port=%d sda=%d scl=%d hz=%lu",
                     s_bus_port, s_bus_sda_io_num, s_bus_scl_io_num,
                     (unsigned long)s_bus_scl_speed_hz);
        }
        *out_bus = s_bus_handle;
        return ESP_OK;
    }

    i2c_master_bus_config_t bus_cfg = {
        .i2c_port = port,
        .sda_io_num = sda_io_num,
        .scl_io_num = scl_io_num,
        .clk_source = I2C_CLK_SRC_DEFAULT,
        .glitch_ignore_cnt = 7,
        .intr_priority = 0,
        .trans_queue_depth = 0,
        .flags.enable_internal_pullup = true,
    };

    esp_err_t ret = i2c_new_master_bus(&bus_cfg, &s_bus_handle);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "I2C bus init failed: %s", esp_err_to_name(ret));
        return ret;
    }

    s_bus_initialized = true;
    s_bus_port = port;
    s_bus_sda_io_num = sda_io_num;
    s_bus_scl_io_num = scl_io_num;
    s_bus_scl_speed_hz = scl_speed_hz;

    *out_bus = s_bus_handle;
    ESP_LOGI(TAG, "I2C bus ready on port=%d sda=%d scl=%d hz=%lu",
             port, sda_io_num, scl_io_num, (unsigned long)scl_speed_hz);
    return ESP_OK;
}
