set(imu_priv_requires "")

if(NOT CONFIG_MUSOPTI_IMU_SIMULATED)
    list(APPEND imu_priv_requires esp_driver_i2c qmi8658)
endif()

idf_component_register(
    SRCS "imu.c"
    INCLUDE_DIRS "."
    REQUIRES common esp_timer
    PRIV_REQUIRES ${imu_priv_requires}
)
