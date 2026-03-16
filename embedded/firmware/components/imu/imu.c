#include "imu.h"
#include "esp_log.h"
#include "esp_timer.h"

#include <math.h>
#include <string.h>

static const char *TAG = "imu";

static imu_config_t s_config;

#if !defined(CONFIG_MUSOPTI_IMU_SIMULATED)

#include "driver/i2c_master.h"
#include "i2c_bus.h"
#include "qmi8658.h"

#define I2C_SCL_IO  7
#define I2C_SDA_IO  8
#define I2C_PORT    I2C_NUM_0
#define I2C_FREQ_HZ 400000

static qmi8658_dev_t s_qmi_dev;
static bool s_initialized;

static uint32_t imu_odr_from_sample_rate(uint16_t sample_rate_hz)
{
    if (sample_rate_hz <= 50) {
        return QMI8658_ACCEL_ODR_62_5HZ;
    }
    if (sample_rate_hz <= 100) {
        return QMI8658_ACCEL_ODR_125HZ;
    }
    return QMI8658_ACCEL_ODR_250HZ;
}

static esp_err_t hw_apply_config(void)
{
    uint32_t odr = imu_odr_from_sample_rate(s_config.sample_rate_hz);

    qmi8658_set_accel_odr(&s_qmi_dev, odr);
    qmi8658_set_gyro_odr(&s_qmi_dev, odr);

    ESP_LOGI(TAG, "IMU sample rate applied: ~%d Hz", s_config.sample_rate_hz);
    return ESP_OK;
}

static esp_err_t hw_init(void)
{
    i2c_master_bus_handle_t bus;
    esp_err_t ret = musopti_i2c_bus_get(I2C_PORT, I2C_SDA_IO, I2C_SCL_IO, I2C_FREQ_HZ, &bus);
    if (ret != ESP_OK) {
        return ret;
    }

    ret = qmi8658_init(&s_qmi_dev, bus, QMI8658_ADDRESS_HIGH);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "QMI8658 init failed: %d", ret);
        return ret;
    }

    qmi8658_set_accel_range(&s_qmi_dev, QMI8658_ACCEL_RANGE_8G);
    qmi8658_set_gyro_range(&s_qmi_dev, QMI8658_GYRO_RANGE_512DPS);
    qmi8658_set_accel_unit_mps2(&s_qmi_dev, true);
    qmi8658_set_gyro_unit_rads(&s_qmi_dev, true);
    s_initialized = true;

    ESP_LOGI(TAG, "QMI8658 hardware initialized");
    return hw_apply_config();
}

static esp_err_t hw_read(imu_sample_t *sample)
{
    bool ready = false;
    esp_err_t ret = qmi8658_is_data_ready(&s_qmi_dev, &ready);
    if (ret != ESP_OK || !ready) {
        return ESP_ERR_NOT_FINISHED;
    }

    qmi8658_data_t raw;
    ret = qmi8658_read_sensor_data(&s_qmi_dev, &raw);
    if (ret != ESP_OK) {
        return ret;
    }

    sample->accel_x = raw.accelX;
    sample->accel_y = raw.accelY;
    sample->accel_z = raw.accelZ;
    sample->gyro_x  = raw.gyroX;
    sample->gyro_y  = raw.gyroY;
    sample->gyro_z  = raw.gyroZ;
    sample->timestamp_us = esp_timer_get_time();
    return ESP_OK;
}

#else /* CONFIG_MUSOPTI_IMU_SIMULATED */

static int64_t s_sim_start_us;

static esp_err_t sim_init(void)
{
    s_sim_start_us = esp_timer_get_time();
    ESP_LOGI(TAG, "Simulated IMU initialized (rate %d Hz)", s_config.sample_rate_hz);
    return ESP_OK;
}

static esp_err_t sim_read(imu_sample_t *sample)
{
    int64_t now = esp_timer_get_time();
    float t = (float)(now - s_sim_start_us) / 1e6f;

    /* Simulate a slow up/down oscillation (~0.3 Hz) on Z axis */
    float phase = sinf(2.0f * M_PI * 0.3f * t);
    sample->accel_x = 0.0f;
    sample->accel_y = 0.0f;
    sample->accel_z = MUSOPTI_GRAVITY_MPS2 + phase * 4.0f;
    sample->gyro_x  = 0.0f;
    sample->gyro_y  = phase * 0.5f;
    sample->gyro_z  = 0.0f;
    sample->timestamp_us = now;
    return ESP_OK;
}

#endif /* CONFIG_MUSOPTI_IMU_SIMULATED */

esp_err_t imu_init(const imu_config_t *config)
{
    if (!config) {
        return ESP_ERR_INVALID_ARG;
    }
    s_config = *config;

#if defined(CONFIG_MUSOPTI_IMU_SIMULATED)
    return sim_init();
#else
    return hw_init();
#endif
}

esp_err_t imu_reconfigure(const imu_config_t *config)
{
    if (!config || config->sample_rate_hz == 0) {
        return ESP_ERR_INVALID_ARG;
    }

#if !defined(CONFIG_MUSOPTI_IMU_SIMULATED)
    if (!s_initialized) {
        return ESP_ERR_INVALID_STATE;
    }
#endif

    s_config = *config;

#if defined(CONFIG_MUSOPTI_IMU_SIMULATED)
    ESP_LOGI(TAG, "Simulated IMU reconfigured (rate %d Hz)", s_config.sample_rate_hz);
    return ESP_OK;
#else
    return hw_apply_config();
#endif
}

esp_err_t imu_read(imu_sample_t *sample)
{
    if (!sample) {
        return ESP_ERR_INVALID_ARG;
    }

#if defined(CONFIG_MUSOPTI_IMU_SIMULATED)
    return sim_read(sample);
#else
    return hw_read(sample);
#endif
}
