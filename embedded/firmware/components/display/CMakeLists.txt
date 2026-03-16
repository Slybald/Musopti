set(display_priv_requires "")

if(NOT CONFIG_MUSOPTI_DISPLAY_SIMULATED)
    list(APPEND display_priv_requires
        esp_driver_gpio
        esp_driver_i2c
        esp_driver_spi
        esp_io_expander_tca9554
        esp_lcd
        esp_lcd_sh8601
        esp_lcd_touch_ft5x06
        esp_timer
        lvgl
    )
endif()

idf_component_register(
    SRCS "display.c"
    INCLUDE_DIRS "."
    REQUIRES common
    PRIV_REQUIRES ${display_priv_requires}
)
