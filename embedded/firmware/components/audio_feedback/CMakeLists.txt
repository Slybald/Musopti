set(audio_feedback_priv_requires "")

if(NOT CONFIG_MUSOPTI_AUDIO_SIMULATED)
    list(APPEND audio_feedback_priv_requires esp_driver_i2s)
endif()

idf_component_register(
    SRCS "audio_feedback.c"
    INCLUDE_DIRS "."
    REQUIRES common
    PRIV_REQUIRES ${audio_feedback_priv_requires}
)
