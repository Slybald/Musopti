idf_component_register(
    SRCS "display.c"
    INCLUDE_DIRS "."
    REQUIRES common
)

# Only pull in LVGL and display drivers when building for real hardware
if(NOT CONFIG_MUSOPTI_DISPLAY_SIMULATED)
    idf_component_get_property(req display REQUIRES)
    list(APPEND req driver esp_lcd esp_timer lvgl)
    idf_component_set_property(display REQUIRES "${req}")
endif()
