# System Validation

## Objective

This document is the single validation checklist for firmware BLE/config correctness, iOS observability, recording fidelity, and hardware regression tracking.

## Required Artifacts Per Scenario

- Firmware logs (`idf.py monitor` capture or exported serial log)
- iOS logs (console export or captured screenshots)
- BLE config read-back payload
- BLE status snapshot (`config_revision`, `sample_rate_hz`, `firmware`, `battery`)
- Recording export when the scenario touches recording mode

## Pass Criteria

- Requested config and applied config match after `write -> read config -> refresh status`
- `config_revision` increments only on successful config application
- Observed sample rate stays within `+-10%` of the requested rate
- Auto-reconnect completes in under `5 s`
- No false `SESSION_STOP` while the module is actively moving

## Scenario Matrix

| Scenario | Procedure | Expected Result | Artifacts |
| --- | --- | --- | --- |
| Same exercise, new hold target | Keep the same exercise and change `hold_target_ms` over BLE | `config` read-back and `status` reflect the new hold target / revision without reconnect | Firmware log, iOS device sheet screenshot, status snapshot |
| Same exercise, new min rep duration | Change `min_rep_duration_ms` during a live session | Detector resets to `IDLE`, no mixed rep is completed, new config is applied | Firmware log, iOS device sheet screenshot |
| Invalid config rejected | Send an unsupported sample rate or invalid hold tolerance | BLE write fails, `config_revision` does not change, old config remains readable | iOS write error, config read-back, status snapshot |
| Recording 50 Hz | Record for `60 s` at `50 Hz` | `status.sample_rate_hz` shows `50`, observed rate is within tolerance | Recording bundle, status snapshot |
| Recording 100 Hz | Record for `60 s` at `100 Hz` | `status.sample_rate_hz` shows `100`, observed rate is within tolerance | Recording bundle, status snapshot |
| Recording 200 Hz | Record for `60 s` at `200 Hz` | `status.sample_rate_hz` shows `200`, observed rate is within tolerance | Recording bundle, status snapshot |
| BLE disconnect during set | Force a disconnect mid-set | App enters `recovering`, reconnects, and does not claim config is synced until config/status read-back succeeds again | iOS logs, reconnection timing |
| Firmware status fields | Connect and inspect device sheet | Firmware version, applied sample rate, config revision, and battery availability render correctly | Device status screenshot |

## Automation Gate

Every hardware issue found here must first produce one of these before a code fix lands:

- A new host replay fixture under [fixtures](/Users/nicolas/esp/embedded/firmware/host-tests/fixtures)
- A new Swift test in [MusoptiTests.swift](/Users/nicolas/esp/apps/ios/MusoptiTests/MusoptiTests.swift) or [MusoptiAppTests](/Users/nicolas/esp/apps/ios/MusoptiAppTests)
