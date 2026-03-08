#pragma once

typedef int esp_err_t;

#define ESP_OK 0
#define ESP_FAIL -1
#define ESP_ERR_INVALID_ARG 0x102
#define ESP_ERR_INVALID_STATE 0x103
#define ESP_ERR_NOT_FINISHED 0x104
#define ESP_ERR_INVALID_VERSION 0x105

static inline const char *esp_err_to_name(esp_err_t err)
{
    switch (err) {
    case ESP_OK:
        return "ESP_OK";
    case ESP_FAIL:
        return "ESP_FAIL";
    case ESP_ERR_INVALID_ARG:
        return "ESP_ERR_INVALID_ARG";
    case ESP_ERR_INVALID_STATE:
        return "ESP_ERR_INVALID_STATE";
    case ESP_ERR_NOT_FINISHED:
        return "ESP_ERR_NOT_FINISHED";
    case ESP_ERR_INVALID_VERSION:
        return "ESP_ERR_INVALID_VERSION";
    default:
        return "ESP_ERR_UNKNOWN";
    }
}
