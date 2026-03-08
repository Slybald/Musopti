cmake_minimum_required(VERSION 3.20)
project(musopti_host_tests C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

enable_testing()

set(HOST_TEST_INCLUDE_DIRS
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/common
    ${CMAKE_CURRENT_SOURCE_DIR}/../components/motion_detection
)

add_executable(
    config_validation_test
    tests/config_validation_test.c
    ../components/common/ble_config_validation.c
    ../components/common/musopti_types.c
)
target_include_directories(config_validation_test PRIVATE ${HOST_TEST_INCLUDE_DIRS})
add_test(NAME config_validation COMMAND config_validation_test)

add_executable(
    motion_replay_test
    tests/motion_replay_test.c
    ../components/common/musopti_types.c
    ../components/motion_detection/motion_detection.c
)
target_include_directories(motion_replay_test PRIVATE ${HOST_TEST_INCLUDE_DIRS})
target_link_libraries(motion_replay_test PRIVATE m)

add_test(
    NAME replay_generic_single_rep
    COMMAND motion_replay_test
        ${CMAKE_CURRENT_SOURCE_DIR}/fixtures/generic_single_rep.csv
        ${CMAKE_CURRENT_SOURCE_DIR}/fixtures/generic_single_rep.expected
)

add_test(
    NAME replay_bench_valid_hold
    COMMAND motion_replay_test
        ${CMAKE_CURRENT_SOURCE_DIR}/fixtures/bench_valid_hold.csv
        ${CMAKE_CURRENT_SOURCE_DIR}/fixtures/bench_valid_hold.expected
)
