#include "power_mgmt.h"
#include "esp_log.h"

static const char *TAG = "power_mgmt";

esp_err_t power_mgmt_init(void)
{
    ESP_LOGI(TAG, "Power management initialized (stub)");
    return ESP_OK;
}
