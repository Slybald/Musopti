idf_component_register(
    SRCS "imu.c"
    INCLUDE_DIRS "."
    REQUIRES common driver esp_timer
)
