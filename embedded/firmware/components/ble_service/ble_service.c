#include "ble_service.h"
#include "ble_config_validation.h"
#include "esp_log.h"
#include "host/ble_hs.h"
#include "host/ble_gap.h"
#include "host/ble_gatt.h"
#include "host/util/util.h"
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"

#include <stdatomic.h>
#include <string.h>

static const char *TAG = "ble_svc";

#define DEVICE_NAME "Musopti"

/* ---- UUIDs ---- */

/* Service UUID: 4D55534F-5054-4900-0001-000000000000 */
static const ble_uuid128_t s_svc_uuid =
    /* NimBLE stores UUID128 in little-endian (see ble_uuid_to_str()). */
    BLE_UUID128_INIT(0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00,
                     0x00, 0x49, 0x54, 0x50, 0x4f, 0x53, 0x55, 0x4d);

/* Event characteristic: 4D55534F-5054-4900-0001-000000000001 */
static const ble_uuid128_t s_evt_chr_uuid =
    BLE_UUID128_INIT(0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00,
                     0x00, 0x49, 0x54, 0x50, 0x4f, 0x53, 0x55, 0x4d);

/* Config characteristic: 4D55534F-5054-4900-0001-000000000002 */
static const ble_uuid128_t s_cfg_chr_uuid =
    BLE_UUID128_INIT(0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00,
                     0x00, 0x49, 0x54, 0x50, 0x4f, 0x53, 0x55, 0x4d);

/* Raw data characteristic: 4D55534F-5054-4900-0001-000000000003 */
static const ble_uuid128_t s_raw_chr_uuid =
    BLE_UUID128_INIT(0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00,
                     0x00, 0x49, 0x54, 0x50, 0x4f, 0x53, 0x55, 0x4d);

/* Status characteristic: 4D55534F-5054-4900-0001-000000000004 */
static const ble_uuid128_t s_status_chr_uuid =
    BLE_UUID128_INIT(0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00,
                     0x00, 0x49, 0x54, 0x50, 0x4f, 0x53, 0x55, 0x4d);

/* ---- state ---- */

static uint16_t s_conn_handle;
static atomic_bool s_connected;
static uint16_t s_evt_chr_val_handle;
static uint16_t s_cfg_chr_val_handle;
static uint16_t s_raw_chr_val_handle;
static uint16_t s_status_chr_val_handle;
static uint16_t s_config_revision;
static bool s_evt_notify_enabled;
static bool s_raw_notify_enabled;
static bool s_status_notify_enabled;

static ble_config_change_cb_t s_config_cb;
static musopti_ble_config_payload_t s_current_config;
static musopti_ble_event_payload_t s_last_event;
static musopti_ble_status_payload_t s_status;

static esp_err_t notify_status_if_subscribed(void)
{
    if (!atomic_load(&s_connected) || !s_status_notify_enabled) {
        return ESP_OK;
    }

    struct os_mbuf *om = ble_hs_mbuf_from_flat(&s_status, sizeof(s_status));
    if (!om) {
        ESP_LOGW(TAG, "Failed to allocate mbuf for status notification");
        return ESP_ERR_NO_MEM;
    }

    int rc = ble_gatts_notify_custom(s_conn_handle, s_status_chr_val_handle, om);
    if (rc != 0) {
        ESP_LOGW(TAG, "Status notify failed: %d (non-blocking)", rc);
        return ESP_FAIL;
    }
    return ESP_OK;
}

/* ---- characteristic callbacks ---- */

static int evt_chr_access_cb(uint16_t conn_handle, uint16_t attr_handle,
                             struct ble_gatt_access_ctxt *ctxt, void *arg)
{
    (void)conn_handle; (void)attr_handle; (void)arg;

    if (ctxt->op == BLE_GATT_ACCESS_OP_READ_CHR) {
        os_mbuf_append(ctxt->om, &s_last_event, sizeof(s_last_event));
    }
    return 0;
}

static int status_chr_access_cb(uint16_t conn_handle, uint16_t attr_handle,
                                struct ble_gatt_access_ctxt *ctxt, void *arg)
{
    (void)conn_handle; (void)attr_handle; (void)arg;

    if (ctxt->op == BLE_GATT_ACCESS_OP_READ_CHR) {
        os_mbuf_append(ctxt->om, &s_status, sizeof(s_status));
    }
    return 0;
}

static int cfg_chr_access_cb(uint16_t conn_handle, uint16_t attr_handle,
                             struct ble_gatt_access_ctxt *ctxt, void *arg)
{
    (void)conn_handle; (void)attr_handle; (void)arg;

    if (ctxt->op == BLE_GATT_ACCESS_OP_READ_CHR) {
        os_mbuf_append(ctxt->om, &s_current_config, sizeof(s_current_config));
    } else if (ctxt->op == BLE_GATT_ACCESS_OP_WRITE_CHR) {
        uint16_t len = OS_MBUF_PKTLEN(ctxt->om);
        if (len != sizeof(musopti_ble_config_payload_t)) {
            ESP_LOGW(TAG, "Config write: bad length %d (expected %d)",
                     len, (int)sizeof(musopti_ble_config_payload_t));
            return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
        }

        musopti_ble_config_payload_t incoming;
        os_mbuf_copydata(ctxt->om, 0, sizeof(incoming), &incoming);
        esp_err_t validation_err = validate_ble_config(&incoming);
        if (validation_err != ESP_OK) {
            ESP_LOGW(TAG,
                     "Rejected config write: version=%u mode=%u exercise=%u sample_rate=%u err=%s",
                     incoming.version,
                     incoming.device_mode,
                     incoming.exercise_type,
                     incoming.sample_rate_hz,
                     esp_err_to_name(validation_err));
            return BLE_ATT_ERR_UNLIKELY;
        }

        musopti_ble_config_payload_t applied = incoming;
        esp_err_t apply_err = ESP_OK;
        if (s_config_cb) {
            apply_err = s_config_cb(&incoming, &applied);
        }

        if (apply_err != ESP_OK) {
            ESP_LOGW(TAG, "Config apply failed: %s", esp_err_to_name(apply_err));
            return BLE_ATT_ERR_UNLIKELY;
        }

        s_current_config = applied;
        s_config_revision++;
        s_status.config_revision = s_config_revision;
        s_status.device_mode = applied.device_mode;
        s_status.exercise_type = applied.exercise_type;
        s_status.sample_rate_hz = applied.sample_rate_hz;
        s_status.flags = (s_status.flags & ~MUSOPTI_STATUS_FLAG_RECORDING_ACTIVE) |
                         ((applied.device_mode == MUSOPTI_MODE_RECORDING)
                            ? MUSOPTI_STATUS_FLAG_RECORDING_ACTIVE
                            : 0);

        ESP_LOGI(TAG, "Config applied: mode=%d exercise=%d hold_target=%d sample_rate=%u rev=%u",
                 applied.device_mode, applied.exercise_type, applied.hold_target_ms,
                 applied.sample_rate_hz, s_config_revision);
        notify_status_if_subscribed();
    }
    return 0;
}

static int raw_chr_access_cb(uint16_t conn_handle, uint16_t attr_handle,
                             struct ble_gatt_access_ctxt *ctxt, void *arg)
{
    (void)conn_handle; (void)attr_handle; (void)arg;
    /* Raw data is notify-only, reads return empty */
    return 0;
}

/* ---- GATT service definition ---- */

static const struct ble_gatt_svc_def s_gatt_svcs[] = {
    {
        .type = BLE_GATT_SVC_TYPE_PRIMARY,
        .uuid = &s_svc_uuid.u,
        .characteristics = (struct ble_gatt_chr_def[]) {
            {
                .uuid = &s_evt_chr_uuid.u,
                .access_cb = evt_chr_access_cb,
                .val_handle = &s_evt_chr_val_handle,
                .flags = BLE_GATT_CHR_F_NOTIFY | BLE_GATT_CHR_F_READ,
            },
            {
                .uuid = &s_cfg_chr_uuid.u,
                .access_cb = cfg_chr_access_cb,
                .val_handle = &s_cfg_chr_val_handle,
                .flags = BLE_GATT_CHR_F_READ | BLE_GATT_CHR_F_WRITE,
            },
            {
                .uuid = &s_raw_chr_uuid.u,
                .access_cb = raw_chr_access_cb,
                .val_handle = &s_raw_chr_val_handle,
                .flags = BLE_GATT_CHR_F_NOTIFY,
            },
            {
                .uuid = &s_status_chr_uuid.u,
                .access_cb = status_chr_access_cb,
                .val_handle = &s_status_chr_val_handle,
                .flags = BLE_GATT_CHR_F_NOTIFY | BLE_GATT_CHR_F_READ,
            },
            { 0 },
        },
    },
    { 0 },
};

/* ---- GAP / advertising ---- */

static void start_advertising(void);

static int gap_event_cb(struct ble_gap_event *event, void *arg)
{
    (void)arg;

    switch (event->type) {
    case BLE_GAP_EVENT_CONNECT:
        if (event->connect.status == 0) {
            s_conn_handle = event->connect.conn_handle;
            atomic_store(&s_connected, true);
            ESP_LOGI(TAG, "BLE connected (handle=%d)", s_conn_handle);
        } else {
            ESP_LOGW(TAG, "BLE connection failed: %d", event->connect.status);
            start_advertising();
        }
        break;

    case BLE_GAP_EVENT_DISCONNECT:
        atomic_store(&s_connected, false);
        s_evt_notify_enabled = false;
        s_raw_notify_enabled = false;
        s_status_notify_enabled = false;
        ESP_LOGI(TAG, "BLE disconnected (reason=%d)", event->disconnect.reason);
        start_advertising();
        break;

    case BLE_GAP_EVENT_SUBSCRIBE:
        if (event->subscribe.attr_handle == s_evt_chr_val_handle) {
            s_evt_notify_enabled = event->subscribe.cur_notify;
        } else if (event->subscribe.attr_handle == s_raw_chr_val_handle) {
            s_raw_notify_enabled = event->subscribe.cur_notify;
        } else if (event->subscribe.attr_handle == s_status_chr_val_handle) {
            s_status_notify_enabled = event->subscribe.cur_notify;
            if (s_status_notify_enabled) {
                notify_status_if_subscribed();
            }
        }
        ESP_LOGI(TAG, "Subscribe: attr=%d cur_notify=%d",
                 event->subscribe.attr_handle, event->subscribe.cur_notify);
        break;

    default:
        break;
    }
    return 0;
}

static void start_advertising(void)
{
    struct ble_gap_adv_params adv_params = {
        .conn_mode = BLE_GAP_CONN_MODE_UND,
        .disc_mode = BLE_GAP_DISC_MODE_GEN,
    };

    struct ble_hs_adv_fields fields = {
        .flags = BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP,
        .name = (uint8_t *)DEVICE_NAME,
        .name_len = strlen(DEVICE_NAME),
        .name_is_complete = 1,
        .uuids128 = (ble_uuid128_t[]) { s_svc_uuid },
        .num_uuids128 = 1,
        .uuids128_is_complete = 1,
    };

    ble_gap_adv_set_fields(&fields);
    int rc = ble_gap_adv_start(BLE_OWN_ADDR_PUBLIC, NULL, BLE_HS_FOREVER,
                               &adv_params, gap_event_cb, NULL);
    if (rc != 0 && rc != BLE_HS_EALREADY) {
        ESP_LOGE(TAG, "Advertising start failed: %d", rc);
    } else {
        ESP_LOGI(TAG, "Advertising as '%s'", DEVICE_NAME);
    }
}

static void on_sync(void)
{
    ble_hs_id_infer_auto(0, NULL);
    start_advertising();
}

static void on_reset(int reason)
{
    ESP_LOGW(TAG, "BLE host reset: %d", reason);
}

static void nimble_host_task(void *param)
{
    (void)param;
    nimble_port_run();
    nimble_port_freertos_deinit();
}

/* ---- public API ---- */

esp_err_t ble_service_init(const ble_service_config_t *config)
{
    if (config) {
        s_config_cb = config->on_config_change;
    }

    memset(&s_current_config, 0, sizeof(s_current_config));
    s_current_config.version = 1;
    s_current_config.device_mode = MUSOPTI_MODE_DETECTION;
    s_current_config.exercise_type = EXERCISE_GENERIC;
    s_current_config.sample_rate_hz = 100;
    s_current_config.min_rep_duration_ms = 600;

    memset(&s_last_event, 0, sizeof(s_last_event));
    memset(&s_status, 0, sizeof(s_status));
    s_status.version = 1;
    s_status.battery_pct = 0xFF;
    s_status.device_mode = s_current_config.device_mode;
    s_status.exercise_type = s_current_config.exercise_type;
    s_status.motion_state = MOTION_STATE_IDLE;
    s_status.sample_rate_hz = s_current_config.sample_rate_hz;
    s_status.config_revision = 0;
    s_config_revision = 0;
    s_evt_notify_enabled = false;
    s_raw_notify_enabled = false;
    s_status_notify_enabled = false;

    int rc = nimble_port_init();
    if (rc != ESP_OK) {
        ESP_LOGE(TAG, "NimBLE port init failed: %d", rc);
        return ESP_FAIL;
    }

    ble_hs_cfg.sync_cb  = on_sync;
    ble_hs_cfg.reset_cb = on_reset;

    ble_svc_gap_init();
    ble_svc_gatt_init();

    rc = ble_gatts_count_cfg(s_gatt_svcs);
    if (rc != 0) {
        ESP_LOGE(TAG, "GATT count cfg failed: %d", rc);
        return ESP_FAIL;
    }

    rc = ble_gatts_add_svcs(s_gatt_svcs);
    if (rc != 0) {
        ESP_LOGE(TAG, "GATT add svcs failed: %d", rc);
        return ESP_FAIL;
    }

    ble_svc_gap_device_name_set(DEVICE_NAME);
    nimble_port_freertos_init(nimble_host_task);

    ESP_LOGI(TAG, "BLE service initialized (4 characteristics)");
    return ESP_OK;
}

esp_err_t ble_service_set_status(const musopti_ble_status_payload_t *status)
{
    if (!status) {
        return ESP_ERR_INVALID_ARG;
    }

    s_status = *status;
    s_status.version = 1;
    s_status.config_revision = s_config_revision;
    return notify_status_if_subscribed();
}

esp_err_t ble_service_notify_event(const musopti_event_t *event)
{
    if (!event) {
        return ESP_ERR_INVALID_ARG;
    }
    if (!atomic_load(&s_connected) || !s_evt_notify_enabled) {
        return ESP_ERR_INVALID_STATE;
    }

    musopti_ble_event_payload_t payload = {
        .version = 2,
        .event_type = (uint8_t)event->type,
        .state = (uint8_t)event->state,
        .flags = event->hold_valid ? 0x01 : 0x00,
        .rep_count = event->rep_count,
        .exercise_type = (uint8_t)event->exercise,
        .device_mode = s_current_config.device_mode,
        .hold_duration_ms = event->hold_duration_ms,
    };
    s_last_event = payload;

    struct os_mbuf *om = ble_hs_mbuf_from_flat(&payload, sizeof(payload));
    if (!om) {
        ESP_LOGW(TAG, "Failed to allocate mbuf for event notification");
        return ESP_ERR_NO_MEM;
    }

    int rc = ble_gatts_notify_custom(s_conn_handle, s_evt_chr_val_handle, om);
    if (rc != 0) {
        ESP_LOGW(TAG, "Event notify failed: %d (non-blocking)", rc);
        return ESP_FAIL;
    }
    return ESP_OK;
}

esp_err_t ble_service_notify_raw_data(const imu_sample_t *samples, size_t count)
{
    if (!samples || count == 0) {
        return ESP_ERR_INVALID_ARG;
    }
    if (!atomic_load(&s_connected) || !s_raw_notify_enabled) {
        return ESP_ERR_INVALID_STATE;
    }

    /*
     * Pack samples as: [uint8_t version=1][uint8_t count][packed samples...]
     * Each packed sample: 6x float (24 bytes) + uint32_t timestamp_ms (4 bytes) = 28 bytes
     * BLE MTU limits apply; the caller should keep count reasonable (e.g. <= 7 samples per packet).
     */
    size_t max_samples = (count > 7) ? 7 : count;
    size_t pkt_size = 2 + max_samples * 28;
    uint8_t pkt[2 + 7 * 28];

    pkt[0] = 1;
    pkt[1] = (uint8_t)max_samples;
    size_t off = 2;

    for (size_t i = 0; i < max_samples; i++) {
        float vals[6] = {
            samples[i].accel_x, samples[i].accel_y, samples[i].accel_z,
            samples[i].gyro_x, samples[i].gyro_y, samples[i].gyro_z,
        };
        memcpy(&pkt[off], vals, sizeof(vals));
        off += sizeof(vals);
        uint32_t ts_ms = (uint32_t)(samples[i].timestamp_us / 1000);
        memcpy(&pkt[off], &ts_ms, sizeof(ts_ms));
        off += sizeof(ts_ms);
    }

    struct os_mbuf *om = ble_hs_mbuf_from_flat(pkt, pkt_size);
    if (!om) {
        ESP_LOGW(TAG, "Failed to allocate mbuf for raw data");
        return ESP_ERR_NO_MEM;
    }

    int rc = ble_gatts_notify_custom(s_conn_handle, s_raw_chr_val_handle, om);
    if (rc != 0) {
        ESP_LOGW(TAG, "Raw data notify failed: %d (non-blocking)", rc);
        return ESP_FAIL;
    }
    return ESP_OK;
}

bool ble_service_is_connected(void)
{
    return atomic_load(&s_connected);
}
