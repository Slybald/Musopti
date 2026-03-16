idf_component_register(
    SRCS
        "ble_config_validation.c"
        "i2c_bus.c"
        "musopti_types.c"
    INCLUDE_DIRS "."
    REQUIRES esp_driver_i2c
)
