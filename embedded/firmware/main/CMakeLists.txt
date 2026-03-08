idf_component_register(
    SRCS "main.c"
    INCLUDE_DIRS ""
    REQUIRES imu motion_detection ble_service recorder audio_feedback display power_mgmt common
)

target_compile_definitions(${COMPONENT_LIB} PRIVATE
    MUSOPTI_FW_VERSION_MAJOR=1
    MUSOPTI_FW_VERSION_MINOR=0
    MUSOPTI_FW_VERSION_PATCH=0
)
