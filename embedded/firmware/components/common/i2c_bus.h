#pragma once

#include <stdint.h>

#include "driver/i2c_master.h"
#include "esp_err.h"

esp_err_t musopti_i2c_bus_get(i2c_port_num_t port,
                              int sda_io_num,
                              int scl_io_num,
                              uint32_t scl_speed_hz,
                              i2c_master_bus_handle_t *out_bus);
