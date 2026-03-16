#include "display.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"

static const char *TAG = "display";

/*
 * When CONFIG_MUSOPTI_DISPLAY_SIMULATED is set, the display module logs state
 * changes instead of driving the real SH8601 panel.  This allows building and
 * testing the orchestrator without the physical board or LVGL dependencies.
 */

#if !defined(CONFIG_MUSOPTI_DISPLAY_SIMULATED)

#include "lvgl.h"
#include "driver/spi_master.h"
#include "driver/i2c.h"
#include "driver/gpio.h"
#include "esp_timer.h"
#include "esp_lcd_panel_io.h"
#include "esp_lcd_panel_ops.h"
#include "esp_lcd_sh8601.h"
#include "esp_io_expander_tca9554.h"

/* ---- pin definitions (match Waveshare BSP) ---- */
#define LCD_HOST         SPI2_HOST
#define TOUCH_HOST       I2C_NUM_0
#define LCD_BIT_PER_PIXEL 16

#define PIN_LCD_CS    GPIO_NUM_5
#define PIN_LCD_PCLK  GPIO_NUM_0
#define PIN_LCD_D0    GPIO_NUM_1
#define PIN_LCD_D1    GPIO_NUM_2
#define PIN_LCD_D2    GPIO_NUM_3
#define PIN_LCD_D3    GPIO_NUM_4
#define PIN_TOUCH_SCL GPIO_NUM_7
#define PIN_TOUCH_SDA GPIO_NUM_8
#define PIN_TOUCH_INT GPIO_NUM_15

#define LVGL_BUF_HEIGHT      (DISPLAY_V_RES / 4)
#define LVGL_TICK_PERIOD_MS  2
#define LVGL_TASK_STACK      (6 * 1024)
#define LVGL_TASK_PRIO       2

static SemaphoreHandle_t s_lvgl_mux;

/* LVGL widgets */
static lv_obj_t *s_lbl_reps;
static lv_obj_t *s_lbl_state;
static lv_obj_t *s_lbl_exercise;
static lv_obj_t *s_lbl_mode;
static lv_obj_t *s_lbl_hold;
static lv_obj_t *s_lbl_ble;
static lv_obj_t *s_lbl_battery;

static const sh8601_lcd_init_cmd_t s_lcd_init_cmds[] = {
    {0x11, (uint8_t[]){0x00}, 0, 120},
    {0x44, (uint8_t[]){0x01, 0xD1}, 2, 0},
    {0x35, (uint8_t[]){0x00}, 1, 0},
    {0x53, (uint8_t[]){0x20}, 1, 10},
    {0x2A, (uint8_t[]){0x00, 0x00, 0x01, 0x6F}, 4, 0},
    {0x2B, (uint8_t[]){0x00, 0x00, 0x01, 0xBF}, 4, 0},
    {0x51, (uint8_t[]){0x00}, 1, 10},
    {0x29, (uint8_t[]){0x00}, 0, 10},
    {0x51, (uint8_t[]){0xFF}, 1, 0},
};

/* ---- LVGL callbacks ---- */

static lv_disp_drv_t s_disp_drv;

static bool flush_ready_cb(esp_lcd_panel_io_handle_t panel_io,
                           esp_lcd_panel_io_event_data_t *edata, void *user_ctx)
{
    lv_disp_flush_ready(&s_disp_drv);
    return false;
}

static void flush_cb(lv_disp_drv_t *drv, const lv_area_t *area, lv_color_t *color_map)
{
    esp_lcd_panel_handle_t panel = (esp_lcd_panel_handle_t)drv->user_data;
    esp_lcd_panel_draw_bitmap(panel, area->x1, area->y1,
                              area->x2 + 1, area->y2 + 1, color_map);
}

static void rounder_cb(lv_disp_drv_t *drv, lv_area_t *area)
{
    area->x1 = (area->x1 >> 1) << 1;
    area->y1 = (area->y1 >> 1) << 1;
    area->x2 = ((area->x2 >> 1) << 1) + 1;
    area->y2 = ((area->y2 >> 1) << 1) + 1;
}

static void update_cb(lv_disp_drv_t *drv)
{
    esp_lcd_panel_handle_t panel = (esp_lcd_panel_handle_t)drv->user_data;
    switch (drv->rotated) {
    case LV_DISP_ROT_NONE:
        esp_lcd_panel_swap_xy(panel, false);
        esp_lcd_panel_mirror(panel, true, false);
        break;
    case LV_DISP_ROT_90:
        esp_lcd_panel_swap_xy(panel, true);
        esp_lcd_panel_mirror(panel, true, true);
        break;
    case LV_DISP_ROT_180:
        esp_lcd_panel_swap_xy(panel, false);
        esp_lcd_panel_mirror(panel, false, true);
        break;
    case LV_DISP_ROT_270:
        esp_lcd_panel_swap_xy(panel, true);
        esp_lcd_panel_mirror(panel, false, false);
        break;
    }
}

static void tick_cb(void *arg)
{
    (void)arg;
    lv_tick_inc(LVGL_TICK_PERIOD_MS);
}

static void lvgl_task(void *arg)
{
    (void)arg;
    while (1) {
        if (display_lock(-1)) {
            uint32_t delay = lv_timer_handler();
            display_unlock();
            if (delay > 500) delay = 500;
            if (delay < 1) delay = 1;
            vTaskDelay(pdMS_TO_TICKS(delay));
        }
    }
}

/* ---- build the Musopti UI ---- */

static void build_ui(void)
{
    lv_obj_t *scr = lv_scr_act();
    lv_obj_set_style_bg_color(scr, lv_color_hex(0x0a0a14), 0);

    /* Top status bar: BLE + battery */
    lv_obj_t *bar = lv_obj_create(scr);
    lv_obj_set_size(bar, DISPLAY_H_RES, 36);
    lv_obj_align(bar, LV_ALIGN_TOP_MID, 0, 0);
    lv_obj_set_style_bg_opa(bar, LV_OPA_TRANSP, 0);
    lv_obj_set_style_border_width(bar, 0, 0);
    lv_obj_set_style_pad_all(bar, 4, 0);
    lv_obj_set_flex_flow(bar, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(bar, LV_FLEX_ALIGN_SPACE_BETWEEN, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);

    s_lbl_ble = lv_label_create(bar);
    lv_label_set_text(s_lbl_ble, "BLE --");
    lv_obj_set_style_text_color(s_lbl_ble, lv_color_hex(0x888888), 0);

    s_lbl_battery = lv_label_create(bar);
    lv_label_set_text(s_lbl_battery, "-- %");
    lv_obj_set_style_text_color(s_lbl_battery, lv_color_hex(0x888888), 0);

    /* Mode + exercise */
    s_lbl_mode = lv_label_create(scr);
    lv_label_set_text(s_lbl_mode, "DETECTION");
    lv_obj_align(s_lbl_mode, LV_ALIGN_TOP_MID, 0, 44);
    lv_obj_set_style_text_color(s_lbl_mode, lv_color_hex(0x00aaff), 0);

    s_lbl_exercise = lv_label_create(scr);
    lv_label_set_text(s_lbl_exercise, "Generic");
    lv_obj_align(s_lbl_exercise, LV_ALIGN_TOP_MID, 0, 68);
    lv_obj_set_style_text_color(s_lbl_exercise, lv_color_hex(0x666688), 0);

    /* Big rep counter */
    s_lbl_reps = lv_label_create(scr);
    lv_label_set_text(s_lbl_reps, "0");
    lv_obj_set_style_text_font(s_lbl_reps, LV_FONT_DEFAULT, 0);
    lv_obj_set_style_text_color(s_lbl_reps, lv_color_hex(0xffffff), 0);
    lv_obj_align(s_lbl_reps, LV_ALIGN_CENTER, 0, -30);

    lv_obj_t *reps_label = lv_label_create(scr);
    lv_label_set_text(reps_label, "REPS");
    lv_obj_set_style_text_color(reps_label, lv_color_hex(0x555555), 0);
    lv_obj_align(reps_label, LV_ALIGN_CENTER, 0, 10);

    /* Phase indicator */
    s_lbl_state = lv_label_create(scr);
    lv_label_set_text(s_lbl_state, "IDLE");
    lv_obj_set_style_text_font(s_lbl_state, LV_FONT_DEFAULT, 0);
    lv_obj_set_style_text_color(s_lbl_state, lv_color_hex(0x44cc44), 0);
    lv_obj_align(s_lbl_state, LV_ALIGN_CENTER, 0, 60);

    /* Last hold result */
    s_lbl_hold = lv_label_create(scr);
    lv_label_set_text(s_lbl_hold, "");
    lv_obj_set_style_text_color(s_lbl_hold, lv_color_hex(0xaaaaaa), 0);
    lv_obj_align(s_lbl_hold, LV_ALIGN_BOTTOM_MID, 0, -30);
}

/* ---- hardware init ---- */

static esp_err_t hw_display_init(void)
{
    /* I2C for touch + IO expander */
    const i2c_config_t i2c_conf = {
        .mode = I2C_MODE_MASTER,
        .sda_io_num = PIN_TOUCH_SDA,
        .sda_pullup_en = GPIO_PULLUP_ENABLE,
        .scl_io_num = PIN_TOUCH_SCL,
        .scl_pullup_en = GPIO_PULLUP_ENABLE,
        .master.clk_speed = 200000,
    };
    ESP_ERROR_CHECK(i2c_param_config(TOUCH_HOST, &i2c_conf));
    ESP_ERROR_CHECK(i2c_driver_install(TOUCH_HOST, i2c_conf.mode, 0, 0, 0));

    esp_io_expander_handle_t io_exp = NULL;
    ESP_ERROR_CHECK(esp_io_expander_new_i2c_tca9554(TOUCH_HOST,
                    ESP_IO_EXPANDER_I2C_TCA9554_ADDRESS_000, &io_exp));
    esp_io_expander_set_dir(io_exp, IO_EXPANDER_PIN_NUM_4 | IO_EXPANDER_PIN_NUM_5,
                            IO_EXPANDER_OUTPUT);
    esp_io_expander_set_level(io_exp, IO_EXPANDER_PIN_NUM_4, 0);
    esp_io_expander_set_level(io_exp, IO_EXPANDER_PIN_NUM_5, 0);
    vTaskDelay(pdMS_TO_TICKS(200));
    esp_io_expander_set_level(io_exp, IO_EXPANDER_PIN_NUM_4, 1);
    esp_io_expander_set_level(io_exp, IO_EXPANDER_PIN_NUM_5, 1);

    /* SPI bus for QSPI display */
    const spi_bus_config_t bus_cfg = SH8601_PANEL_BUS_QSPI_CONFIG(
        PIN_LCD_PCLK, PIN_LCD_D0, PIN_LCD_D1, PIN_LCD_D2, PIN_LCD_D3,
        DISPLAY_H_RES * DISPLAY_V_RES * LCD_BIT_PER_PIXEL / 8);
    ESP_ERROR_CHECK(spi_bus_initialize(LCD_HOST, &bus_cfg, SPI_DMA_CH_AUTO));

    /* Panel IO */
    esp_lcd_panel_io_handle_t io_handle = NULL;
    const esp_lcd_panel_io_spi_config_t io_cfg =
        SH8601_PANEL_IO_QSPI_CONFIG(PIN_LCD_CS, flush_ready_cb, &s_disp_drv);
    ESP_ERROR_CHECK(esp_lcd_new_panel_io_spi((esp_lcd_spi_bus_handle_t)LCD_HOST,
                                             &io_cfg, &io_handle));

    /* SH8601 panel */
    sh8601_vendor_config_t vendor_cfg = {
        .init_cmds = s_lcd_init_cmds,
        .init_cmds_size = sizeof(s_lcd_init_cmds) / sizeof(s_lcd_init_cmds[0]),
        .flags = { .use_qspi_interface = 1 },
    };
    esp_lcd_panel_handle_t panel = NULL;
    const esp_lcd_panel_dev_config_t panel_cfg = {
        .reset_gpio_num = -1,
        .rgb_ele_order = LCD_RGB_ELEMENT_ORDER_RGB,
        .bits_per_pixel = LCD_BIT_PER_PIXEL,
        .vendor_config = &vendor_cfg,
    };
    ESP_ERROR_CHECK(esp_lcd_new_panel_sh8601(io_handle, &panel_cfg, &panel));
    ESP_ERROR_CHECK(esp_lcd_panel_reset(panel));
    ESP_ERROR_CHECK(esp_lcd_panel_init(panel));
    ESP_ERROR_CHECK(esp_lcd_panel_disp_on_off(panel, true));

    /* LVGL init */
    lv_init();

    static lv_disp_draw_buf_t disp_buf;
    lv_color_t *buf1 = heap_caps_malloc(DISPLAY_H_RES * LVGL_BUF_HEIGHT * sizeof(lv_color_t),
                                        MALLOC_CAP_DMA);
    lv_color_t *buf2 = heap_caps_malloc(DISPLAY_H_RES * LVGL_BUF_HEIGHT * sizeof(lv_color_t),
                                        MALLOC_CAP_DMA);
    assert(buf1 && buf2);
    lv_disp_draw_buf_init(&disp_buf, buf1, buf2, DISPLAY_H_RES * LVGL_BUF_HEIGHT);

    lv_disp_drv_init(&s_disp_drv);
    s_disp_drv.hor_res = DISPLAY_H_RES;
    s_disp_drv.ver_res = DISPLAY_V_RES;
    s_disp_drv.flush_cb = flush_cb;
    s_disp_drv.rounder_cb = rounder_cb;
    s_disp_drv.drv_update_cb = update_cb;
    s_disp_drv.draw_buf = &disp_buf;
    s_disp_drv.user_data = panel;
    lv_disp_t *disp = lv_disp_drv_register(&s_disp_drv);

    /* Tick timer */
    const esp_timer_create_args_t tick_args = {
        .callback = tick_cb,
        .name = "lvgl_tick",
    };
    esp_timer_handle_t tick_timer;
    ESP_ERROR_CHECK(esp_timer_create(&tick_args, &tick_timer));
    ESP_ERROR_CHECK(esp_timer_start_periodic(tick_timer, LVGL_TICK_PERIOD_MS * 1000));

    s_lvgl_mux = xSemaphoreCreateMutex();
    assert(s_lvgl_mux);

    /* Build the UI */
    build_ui();

    /* Start LVGL task */
    xTaskCreate(lvgl_task, "lvgl", LVGL_TASK_STACK, NULL, LVGL_TASK_PRIO, NULL);

    ESP_LOGI(TAG, "Display initialized (%dx%d)", DISPLAY_H_RES, DISPLAY_V_RES);
    return ESP_OK;
}

bool display_lock(int timeout_ms)
{
    const TickType_t ticks = (timeout_ms < 0) ? portMAX_DELAY : pdMS_TO_TICKS(timeout_ms);
    return xSemaphoreTake(s_lvgl_mux, ticks) == pdTRUE;
}

void display_unlock(void)
{
    xSemaphoreGive(s_lvgl_mux);
}

esp_err_t display_update(const display_state_t *st)
{
    if (!st) return ESP_ERR_INVALID_ARG;
    if (!display_lock(100)) return ESP_ERR_TIMEOUT;

    char buf[32];

    snprintf(buf, sizeof(buf), "%d", st->rep_count);
    lv_label_set_text(s_lbl_reps, buf);

    const char *state_str = motion_state_to_str(st->state);
    lv_label_set_text(s_lbl_state, state_str);

    uint32_t color = 0x888888;
    switch (st->state) {
    case MOTION_STATE_IDLE:         color = 0x555555; break;
    case MOTION_STATE_PHASE_A:      color = 0xffaa00; break;
    case MOTION_STATE_HOLD:         color = 0x00ccff; break;
    case MOTION_STATE_PHASE_B:      color = 0xffaa00; break;
    case MOTION_STATE_REP_COMPLETE: color = 0x44cc44; break;
    case MOTION_STATE_REP_INVALID:  color = 0xff4444; break;
    }
    lv_obj_set_style_text_color(s_lbl_state, lv_color_hex(color), 0);

    lv_label_set_text(s_lbl_exercise, musopti_exercise_type_to_str(st->exercise));

    const char *mode_str = musopti_device_mode_to_str(st->mode);
    lv_label_set_text(s_lbl_mode, mode_str);

    if (st->last_hold_ms > 0) {
        snprintf(buf, sizeof(buf), "Hold: %lu ms %s",
                 (unsigned long)st->last_hold_ms,
                 st->last_hold_valid ? "OK" : "X");
        lv_label_set_text(s_lbl_hold, buf);
        lv_obj_set_style_text_color(s_lbl_hold,
            lv_color_hex(st->last_hold_valid ? 0x44cc44 : 0xff4444), 0);
    } else {
        lv_label_set_text(s_lbl_hold, "");
    }

    lv_label_set_text(s_lbl_ble, st->ble_connected ? "BLE OK" : "BLE --");
    lv_obj_set_style_text_color(s_lbl_ble,
        lv_color_hex(st->ble_connected ? 0x44cc44 : 0x888888), 0);

    snprintf(buf, sizeof(buf), "%d %%", st->battery_pct);
    lv_label_set_text(s_lbl_battery, buf);

    display_unlock();
    return ESP_OK;
}

esp_err_t display_init(void)
{
    return hw_display_init();
}

#else /* CONFIG_MUSOPTI_DISPLAY_SIMULATED */

static display_state_t s_sim_state;

esp_err_t display_init(void)
{
    ESP_LOGI(TAG, "Display initialized (simulated %dx%d)", DISPLAY_H_RES, DISPLAY_V_RES);
    return ESP_OK;
}

esp_err_t display_update(const display_state_t *st)
{
    if (!st) return ESP_ERR_INVALID_ARG;
    s_sim_state = *st;
    ESP_LOGI(TAG, "[SIM] reps=%d state=%s mode=%s exercise=%s ble=%s bat=%d%%",
             st->rep_count,
             motion_state_to_str(st->state),
             musopti_device_mode_to_str(st->mode),
             musopti_exercise_type_to_str(st->exercise),
             st->ble_connected ? "on" : "off",
             st->battery_pct);
    return ESP_OK;
}

bool display_lock(int timeout_ms)
{
    (void)timeout_ms;
    return true;
}

void display_unlock(void)
{
}

#endif /* CONFIG_MUSOPTI_DISPLAY_SIMULATED */
