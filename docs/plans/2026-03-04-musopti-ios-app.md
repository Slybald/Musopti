# Musopti — iOS App Development Plan

**Date**: 2026-03-04
**Status**: Draft — awaiting approval
**Scope**: Complete iOS application for Musopti module configuration, real-time feedback, session tracking, recording, and statistics

---

## 1. Overview

The Musopti iOS app connects to the ESP32-C6 module over BLE. It lets the user choose an exercise, monitor reps in real-time with live accelerometer graphs, track workout history, analyze performance, and record raw IMU data for ML training or post-analysis.

### Target
- **Platform**: iOS 18+, iPhone only (Apple Watch architecture-ready, not implemented yet)
- **Framework**: SwiftUI, Swift 6, strict concurrency
- **BLE**: CoreBluetooth
- **Persistence**: SwiftData
- **Charts**: Swift Charts
- **Architecture**: MVVM with a service layer
- **Auth**: None now; data model supports a future user ID field

---

## 2. App Flow & Navigation

```
LaunchScreen
    │
    ▼
ConnectionScreen ── scan / auto-reconnect
    │ connected
    ▼
TabView ─────────────────────────────────
│  Tab 1: LiveSession                    │
│  Tab 2: Workouts (plan / freeform)     │
│  Tab 3: History                        │
│  Tab 4: Recordings                     │
│  Tab 5: Settings                       │
──────────────────────────────────────────
```

If the device disconnects at any point, an overlay banner appears (not a full-screen block) — the user can still browse history/stats while disconnected.

---

## 3. Screen Descriptions

### 3.1 Connection Screen

**Purpose**: Scan for and connect to the Musopti device.

- Large "Musopti" logo + animated scanning indicator
- List of discovered Musopti peripherals (by device name "Musopti" or service UUID)
- Tap to connect; spinner while connecting
- Auto-reconnect to last known device on launch
- "Searching..." empty state with troubleshooting tips
- Transition to TabView once connected + services discovered

### 3.2 Tab 1 — Live Session

**Purpose**: Real-time view of the current exercise.

**Top section — Exercise picker**:
- Horizontal scrollable category chips (Chest, Back, Legs, Shoulders, Arms, Core, Cardio, Custom)
- Tapping a chip reveals a grid/list of exercises in that category
- Selected exercise is highlighted; tapping sends the BLE config to the device

**Middle section — Live feedback**:
- Large rep counter (centered, prominent)
- Phase indicator pill (Idle / Phase A / Hold / Phase B) with color coding
- Hold timer when in hold phase (animated ring or countdown)
- Hold result badge (✓ valid / ✗ too short / ✗ too long)

**Bottom section — Real-time graph**:
- Rolling acceleration magnitude chart (last 5–10 seconds)
- Overlay markers for detected phase transitions
- Toggle button to show/hide the graph (default: visible)

**Footer**:
- Rest timer (auto-detected: starts counting when module goes idle after a rep)
- Set summary when rest starts: "Set 2: 8 reps @ 80kg"
- Weight input: tap the weight badge to enter/change kg for the current set

**Behavior**:
- Subscribes to the Event characteristic notifications
- Each `MUSOPTI_EVENT_REP_COMPLETE` increments the counter
- Each `MUSOPTI_EVENT_HOLD_RESULT` updates the hold badge
- `MUSOPTI_EVENT_STATE_CHANGE` updates the phase pill and graph markers
- Rest detection: if phase stays `IDLE` for > N seconds after at least 1 rep, auto-save the set and start the rest timer

### 3.3 Tab 2 — Workouts

**Purpose**: Plan workouts or start a freeform session.

**Freeform mode** (default):
- Just go to Live Session, pick an exercise, and start moving
- Each completed set (auto-detected rest) is logged under a freeform workout

**Planned workout mode**:
- Create a workout template: name + ordered list of exercises with target sets/reps
- Browse saved templates
- Start a planned workout → the app guides through exercises in order
- After each exercise's sets are done, prompt to move to the next exercise
- Deviation allowed (skip, reorder, add exercises)

**Template editor**:
- Search/browse exercise catalog
- Drag-to-reorder exercises
- Set target sets × reps per exercise
- Save/edit/delete templates

### 3.4 Tab 3 — History & Statistics

**Purpose**: Review past sessions and track progress.

**Session list**:
- Grouped by date (today, this week, earlier)
- Each card: date, workout name (or "Freeform"), exercise count, total sets, total reps, duration
- Tap to expand → session detail

**Session detail**:
- Timeline of exercises performed
- Per exercise: sets table (set #, reps, weight, hold avg, hold consistency)
- Expandable per-set details (rep-by-rep hold times if available)

**Statistics dashboard** (separate sub-tab or scroll section):
- **Volume chart** (weekly): total kg × reps over time (Swift Charts bar)
- **Frequency chart**: workouts per week
- **Per-exercise progression**: line chart of estimated 1RM or total volume per exercise
- **Tempo analysis**: average hold duration over time, rep consistency (std deviation of rep timing)
- **Comparison**: side-by-side two sessions for the same exercise
- Date range filter (1W, 1M, 3M, 6M, 1Y, All)

### 3.5 Tab 4 — Recordings

**Purpose**: Capture and manage raw IMU data.

**Start recording**:
- Select exercise, tap "Record"
- App sends BLE config with `MUSOPTI_MODE_RECORDING` + sample rate
- Shows live sample count, elapsed time, rolling signal preview
- Tap "Stop" → saves locally

**Recording list**:
- Each recording: exercise name, date, duration, sample count, file size
- Swipe to delete
- Tap to preview (mini 3-axis graph of the full recording)

**Export**:
- Select one or more recordings
- Export as CSV (columns: timestamp_ms, accel_x, accel_y, accel_z, gyro_x, gyro_y, gyro_z)
- iOS share sheet (AirDrop, Files, Mail, etc.)

**CSV format**:
```
timestamp_ms,accel_x,accel_y,accel_z,gyro_x,gyro_y,gyro_z
0,0.12,-0.03,9.81,0.01,-0.02,0.00
10,0.14,-0.01,9.79,0.02,-0.01,0.01
...
```

### 3.6 Tab 5 — Settings

- **Device info**: firmware version (future), battery %, signal strength
- **Default rest timer threshold**: seconds of idle before auto-saving set (default: 8s)
- **Default sample rate**: for recording mode (50, 100, 200 Hz)
- **Units**: kg / lbs toggle
- **Exercise catalog management**: add/edit custom exercises
- **Data management**: export all history as JSON, delete all data
- **About**: version, credits, links

---

## 4. Data Model (SwiftData)

### 4.1 Exercise

```swift
@Model
final class Exercise {
    @Attribute(.unique) var id: UUID
    var name: String
    var category: ExerciseCategory  // enum: chest, back, legs, shoulders, arms, core, cardio, custom
    var muscleGroup: String         // "pectorals", "quadriceps", etc.
    var equipmentType: String       // "barbell", "dumbbell", "cable", "machine", "bodyweight"
    var isBuiltIn: Bool             // true for predefined, false for user-created
    var iconName: String            // SF Symbol name
    var detectionProfile: DetectionProfile  // maps to firmware exercise type + params

    // future
    var userID: String?
}
```

### 4.2 DetectionProfile

```swift
struct DetectionProfile: Codable {
    var firmwareExerciseType: UInt8  // maps to musopti_exercise_type_t
    var requireHold: Bool
    var holdTargetMs: UInt16
    var holdToleranceMs: UInt16
    var minRepDurationMs: UInt16
}
```

### 4.3 Workout Template

```swift
@Model
final class WorkoutTemplate {
    @Attribute(.unique) var id: UUID
    var name: String
    var exercises: [WorkoutTemplateEntry]  // ordered
    var createdAt: Date
    var updatedAt: Date
}

struct WorkoutTemplateEntry: Codable, Identifiable {
    var id: UUID
    var exerciseID: UUID
    var targetSets: Int
    var targetReps: Int
    var order: Int
}
```

### 4.4 Workout Session

```swift
@Model
final class WorkoutSession {
    @Attribute(.unique) var id: UUID
    var templateID: UUID?       // nil for freeform
    var startedAt: Date
    var finishedAt: Date?
    var exercises: [ExerciseLog]
    var notes: String?
}
```

### 4.5 Exercise Log (within a session)

```swift
struct ExerciseLog: Codable, Identifiable {
    var id: UUID
    var exerciseID: UUID
    var order: Int
    var sets: [SetLog]
}
```

### 4.6 Set Log

```swift
struct SetLog: Codable, Identifiable {
    var id: UUID
    var setNumber: Int
    var reps: Int
    var weightKg: Double?
    var holdDurations: [UInt32]     // per-rep hold duration in ms (empty if no hold)
    var holdValids: [Bool]          // per-rep hold validity
    var repTimestamps: [Date]       // time of each rep completion
    var startedAt: Date
    var finishedAt: Date
    var restDurationSec: Double?    // rest after this set (nil for last set)
}
```

### 4.7 IMU Recording

```swift
@Model
final class IMURecording {
    @Attribute(.unique) var id: UUID
    var exerciseID: UUID?
    var exerciseName: String
    var sampleRateHz: Int
    var startedAt: Date
    var finishedAt: Date?
    var sampleCount: Int
    var filePath: String            // relative path in app documents
    var notes: String?
}
```

The raw IMU data is stored as a binary file (not in SwiftData) for performance. The binary format mirrors the BLE raw packet layout for simplicity.

---

## 5. Architecture

```
┌──────────────────────────────────────────────────┐
│                    SwiftUI Views                  │
│  ConnectionView  LiveSessionView  HistoryView ... │
└──────────┬───────────────────────────┬───────────┘
           │                           │
     ┌─────▼─────┐             ┌──────▼──────┐
     │ ViewModels │             │  ViewModels  │
     │ (Observable│             │              │
     │  @Observable)            │              │
     └─────┬─────┘             └──────┬──────┘
           │                           │
     ┌─────▼───────────────────────────▼───────┐
     │              Service Layer                │
     │  BLEManager    SessionManager             │
     │  RecordingManager   StatsEngine           │
     │  ExerciseCatalog                          │
     └─────┬──────────┬─────────┬──────────────┘
           │          │         │
    ┌──────▼──┐  ┌───▼────┐ ┌──▼──────┐
    │ CoreBT  │  │SwiftData│ │FileManager│
    └─────────┘  └────────┘ └──────────┘
```

### 5.1 BLEManager (`@Observable`, singleton)

Responsibilities:
- Scan for devices with service UUID `4D55534F-5054-4900-0001-000000000000`
- Connect / disconnect / auto-reconnect
- Discover services and characteristics
- Subscribe to Event + Raw Data notifications
- Write config payloads
- Parse incoming payloads (event 12 bytes, raw data variable)
- Expose connection state, last event, signal strength
- Debounce / queue writes to avoid BLE congestion

Published state:
- `connectionState`: `.disconnected`, `.scanning`, `.connecting`, `.connected`, `.ready`
- `peripherals: [DiscoveredPeripheral]`
- `lastEvent: MusoptiEvent?`
- `signalStrength: Int?` (RSSI)
- `batteryPercent: Int?` (future)

### 5.2 SessionManager (`@Observable`)

Responsibilities:
- Manage active workout session lifecycle (start, finish, discard)
- Track current exercise, current set, rep count
- Receive events from BLEManager and update live state
- Auto-detect rest periods (idle timeout → save set)
- Persist completed sets/sessions to SwiftData
- Weight input management

Published state:
- `activeSession: WorkoutSession?`
- `currentExercise: Exercise?`
- `currentSetReps: Int`
- `currentPhase: MotionPhase`
- `holdResult: HoldResult?`
- `restTimerSeconds: Int`
- `isResting: Bool`
- `liveAccelHistory: [AccelSample]` (ring buffer for chart)

### 5.3 RecordingManager (`@Observable`)

Responsibilities:
- Start/stop recording mode via BLE config write
- Buffer incoming raw IMU samples
- Write to binary file incrementally
- Track recording state and sample count
- Export to CSV

### 5.4 StatsEngine

Responsibilities:
- Query SwiftData for sessions in a date range
- Compute aggregates: volume, frequency, progression, tempo stats
- Return chart-ready data structures

### 5.5 ExerciseCatalog

Responsibilities:
- Load built-in exercises from a bundled JSON file
- CRUD for user-created custom exercises via SwiftData
- Category filtering and search
- Map exercise → firmware detection profile

---

## 6. Exercise Catalog (built-in, 50+ exercises)

The exercises are loaded from a bundled `exercises.json` at first launch and inserted into SwiftData. `isBuiltIn = true` prevents user deletion.

### Categories and exercises (non-exhaustive):

**Chest** (icon: `figure.strengthtraining.traditional`)
- Bench Press (Barbell), Incline Bench Press, Decline Bench Press
- Dumbbell Press, Incline Dumbbell Press
- Cable Fly, Pec Deck Machine
- Push-Up, Dips (Chest)

**Back** (icon: `figure.rowing`)
- Barbell Row, Pendlay Row
- Dumbbell Row, Cable Row (Seated)
- Lat Pulldown (Wide/Close/Neutral)
- Pull-Up, Chin-Up
- T-Bar Row, Machine Row

**Legs** (icon: `figure.walk`)
- Squat (Barbell), Front Squat, Goblet Squat
- Leg Press, Hack Squat
- Romanian Deadlift, Leg Curl (Lying/Seated)
- Leg Extension, Calf Raise (Standing/Seated)
- Bulgarian Split Squat, Lunges

**Shoulders** (icon: `figure.arms.open`)
- Overhead Press (Barbell), Dumbbell Shoulder Press
- Lateral Raise, Front Raise
- Face Pull, Reverse Fly
- Arnold Press, Upright Row
- Cable Lateral Raise

**Arms** (icon: `figure.boxing`)
- Barbell Curl, Dumbbell Curl, Hammer Curl
- Preacher Curl, Cable Curl, Concentration Curl
- Tricep Pushdown (Rope/Bar), Overhead Tricep Extension
- Skull Crusher, Close Grip Bench Press, Dips (Tricep)

**Core** (icon: `figure.core.training`)
- Cable Crunch, Ab Wheel Rollout
- Hanging Leg Raise, Plank (timed, no reps)
- Russian Twist, Woodchop

**Cardio / Other** (icon: `figure.run`)
- Rowing Machine, Kettlebell Swing

### Detection Profile Mapping

Most exercises use `EXERCISE_GENERIC` with `requireHold = false`. The detection is purely motion start/stop. Specific profiles:

| Firmware Type | Exercises |
|---|---|
| `EXERCISE_BENCH_PRESS` (1) | Bench Press (all variants), Dumbbell Press (all variants) |
| `EXERCISE_SQUAT` (2) | Squat (all variants), Leg Press, Hack Squat, Goblet Squat |
| `EXERCISE_DEADLIFT` (3) | Deadlift, Romanian Deadlift |
| `EXERCISE_GENERIC` (0) | Everything else |
| `EXERCISE_CUSTOM` (4) | User-created exercises with custom hold/timing params |

---

## 7. BLE Protocol Reference

### Service UUID
`4D55534F-5054-4900-0001-000000000000`

### Characteristics

| Name | UUID suffix | Properties | Payload |
|---|---|---|---|
| Event | ...0001 | Read, Notify | `musopti_ble_event_payload_t` (12 bytes) |
| Config | ...0002 | Read, Write | `musopti_ble_config_payload_t` (12 bytes) |
| Raw Data | ...0003 | Notify | `[version:u8][count:u8][samples...]` |

### Event Payload (12 bytes, little-endian)

| Offset | Field | Type |
|---|---|---|
| 0 | version | UInt8 (= 2) |
| 1 | event_type | UInt8 |
| 2 | state | UInt8 |
| 3 | flags | UInt8 (bit0 = hold_valid) |
| 4 | rep_count | UInt16 |
| 6 | exercise_type | UInt8 |
| 7 | device_mode | UInt8 |
| 8 | hold_duration_ms | UInt32 |

### Config Payload (12 bytes, little-endian)

| Offset | Field | Type |
|---|---|---|
| 0 | version | UInt8 (= 1) |
| 1 | device_mode | UInt8 |
| 2 | exercise_type | UInt8 |
| 3 | reserved | UInt8 (= 0) |
| 4 | hold_target_ms | UInt16 |
| 6 | hold_tolerance_ms | UInt16 |
| 8 | min_rep_duration_ms | UInt16 |
| 10 | sample_rate_hz | UInt16 |

### Raw Data Packet

Header: 2 bytes (`version=1`, `count=N`, N ≤ 7)
Per sample: 28 bytes (6 × Float32 + UInt32 timestamp_ms)
Max packet: 198 bytes

---

## 8. UI Design Direction

**Style**: Dark mode first, high contrast. Inspired by Apple Fitness and Whoop.

- **Color palette**: Deep black background (#000000 for OLED), electric accent (vibrant teal/cyan #00E5CC as primary accent), warm orange (#FF6B35) for warnings/invalid, green (#34D399) for valid/success, muted grays for secondary text
- **Typography**: SF Pro Display (bold, large) for numbers/counters, SF Pro Text for body. Rep counter: 72pt+, phase pill: 17pt semibold
- **Cards**: Rounded corners (16pt), subtle dark-gray (#1C1C1E) card backgrounds with thin border accents
- **Animations**: Spring animations for rep counter increment, smooth phase pill color transitions, pulse animation on hold timer
- **Graph**: Teal line on dark background, phase markers as vertical dashed lines with colored dots
- **Icons**: SF Symbols throughout, exercise categories with filled SF Symbols

---

## 9. Implementation Phases

### Phase 1 — Foundation & Connection (Week 1)

**Goal**: Xcode project setup, BLE connection working, connection screen.

| # | Task | Details |
|---|---|---|
| 1.1 | Create Xcode project | SwiftUI App, iOS 18 deployment target, Swift 6, bundle ID `com.musopti.app` |
| 1.2 | Project structure | Create folder structure (see §10) |
| 1.3 | BLE protocol types | Swift structs mirroring firmware types (MusoptiEvent, MusoptiConfig, etc.) with Data parsing |
| 1.4 | BLEManager | CoreBluetooth wrapper: scan, connect, discover, subscribe, write, auto-reconnect |
| 1.5 | ConnectionView | Scanning animation, peripheral list, connect button, transition to main app |
| 1.6 | App entry point | Root view with connection state routing |
| 1.7 | Test with firmware | Verify BLE handshake, event notifications, config write |

### Phase 2 — Live Session & Exercise Catalog (Week 2)

**Goal**: Working live session with exercise selection and rep counting.

| # | Task | Details |
|---|---|---|
| 2.1 | SwiftData models | Exercise, WorkoutSession, ExerciseLog, SetLog, DetectionProfile |
| 2.2 | ExerciseCatalog service | Load exercises.json, seed SwiftData, category filter, search |
| 2.3 | exercises.json | Author the 50+ exercise catalog with categories and profiles |
| 2.4 | Exercise picker UI | Category chips + exercise grid, sends BLE config on selection |
| 2.5 | SessionManager | Event processing, rep counting, set auto-detection, rest timer |
| 2.6 | LiveSessionView | Rep counter, phase pill, hold result badge, weight input |
| 2.7 | Live acceleration chart | Swift Charts rolling graph with phase markers |
| 2.8 | Rest timer | Auto-start on idle detection, display countdown, auto-save set |
| 2.9 | Integration test | Full flow: select exercise → reps counted → set auto-saved |

### Phase 3 — Workout Planning (Week 3)

**Goal**: Create workout templates and guided workout flow.

| # | Task | Details |
|---|---|---|
| 3.1 | WorkoutTemplate model | SwiftData model + template entry |
| 3.2 | Template editor | Create/edit templates, add exercises, set targets, reorder |
| 3.3 | Workout list view | Browse saved templates, start workout |
| 3.4 | Guided workout flow | Step through exercises, show progress, allow deviation |
| 3.5 | Freeform vs planned | Auto-create freeform session when no template selected |

### Phase 4 — History & Statistics (Week 4)

**Goal**: Browse past sessions, view detailed stats and progression charts.

| # | Task | Details |
|---|---|---|
| 4.1 | HistoryView | Session list grouped by date, session detail view |
| 4.2 | Session detail | Exercise timeline, sets table, per-rep details |
| 4.3 | StatsEngine | Query aggregations: volume, frequency, per-exercise progression, tempo |
| 4.4 | Statistics dashboard | Volume chart, frequency chart, exercise progression, tempo analysis |
| 4.5 | Comparison view | Side-by-side two sessions for same exercise |
| 4.6 | Date range filters | 1W, 1M, 3M, 6M, 1Y, All |

### Phase 5 — Recording & Export (Week 5)

**Goal**: Raw IMU recording, preview, CSV export.

| # | Task | Details |
|---|---|---|
| 5.1 | IMURecording model | SwiftData model + binary file storage |
| 5.2 | RecordingManager | Start/stop via BLE, buffer samples, write binary file |
| 5.3 | RecordingsView | List recordings, preview mini graph, delete |
| 5.4 | Recording live view | Sample count, elapsed time, signal preview |
| 5.5 | CSV export | Generate CSV from binary file, iOS share sheet |
| 5.6 | Multi-select export | Select multiple recordings for batch export |

### Phase 6 — Settings & Polish (Week 6)

**Goal**: Settings screen, polish, edge cases, performance.

| # | Task | Details |
|---|---|---|
| 6.1 | SettingsView | All settings from §3.6 |
| 6.2 | Custom exercise editor | Create/edit/delete custom exercises with custom detection params |
| 6.3 | Disconnect handling | Banner overlay, graceful reconnect, no data loss |
| 6.4 | Empty states | First-launch onboarding tips, empty history, no device found |
| 6.5 | Haptic feedback | Subtle haptics on rep count, set complete, hold valid/invalid |
| 6.6 | Performance | Profile chart rendering, BLE throughput, SwiftData queries |
| 6.7 | Data export/import | Full history JSON export, delete all data confirmation |
| 6.8 | App icon & launch screen | Design and implement |

---

## 10. Xcode Project Structure

```
apps/ios/
├── Musopti.xcodeproj
├── Musopti/
│   ├── App/
│   │   ├── MusoptiApp.swift           # @main entry, SwiftData container
│   │   └── ContentView.swift          # Root routing (connection vs main)
│   ├── Models/
│   │   ├── Exercise.swift
│   │   ├── WorkoutTemplate.swift
│   │   ├── WorkoutSession.swift
│   │   ├── ExerciseLog.swift
│   │   ├── SetLog.swift
│   │   ├── IMURecording.swift
│   │   └── DetectionProfile.swift
│   ├── BLE/
│   │   ├── BLEManager.swift
│   │   ├── BLEConstants.swift         # UUIDs, payload sizes
│   │   ├── MusoptiEvent.swift         # Event payload parser
│   │   ├── MusoptiConfig.swift        # Config payload builder
│   │   └── RawDataParser.swift        # IMU sample parser
│   ├── Services/
│   │   ├── SessionManager.swift
│   │   ├── RecordingManager.swift
│   │   ├── ExerciseCatalog.swift
│   │   └── StatsEngine.swift
│   ├── Views/
│   │   ├── Connection/
│   │   │   └── ConnectionView.swift
│   │   ├── LiveSession/
│   │   │   ├── LiveSessionView.swift
│   │   │   ├── ExercisePickerView.swift
│   │   │   ├── RepCounterView.swift
│   │   │   ├── PhaseIndicatorView.swift
│   │   │   ├── HoldResultBadge.swift
│   │   │   ├── LiveAccelChart.swift
│   │   │   ├── RestTimerView.swift
│   │   │   └── WeightInputView.swift
│   │   ├── Workouts/
│   │   │   ├── WorkoutsView.swift
│   │   │   ├── TemplateEditorView.swift
│   │   │   └── GuidedWorkoutView.swift
│   │   ├── History/
│   │   │   ├── HistoryView.swift
│   │   │   ├── SessionDetailView.swift
│   │   │   ├── StatsDashboardView.swift
│   │   │   └── ComparisonView.swift
│   │   ├── Recordings/
│   │   │   ├── RecordingsView.swift
│   │   │   ├── RecordingLiveView.swift
│   │   │   └── RecordingPreviewView.swift
│   │   ├── Settings/
│   │   │   ├── SettingsView.swift
│   │   │   └── CustomExerciseEditor.swift
│   │   └── Shared/
│   │       ├── DeviceBanner.swift     # Disconnect/reconnect banner
│   │       ├── ExerciseIcon.swift
│   │       └── Theme.swift            # Colors, fonts, spacing constants
│   ├── Resources/
│   │   ├── exercises.json             # Built-in exercise catalog
│   │   └── Assets.xcassets
│   └── Utilities/
│       ├── DataParsing.swift          # Little-endian byte helpers
│       └── Extensions.swift
└── MusoptiTests/
    ├── BLEParsingTests.swift
    ├── SessionManagerTests.swift
    └── StatsEngineTests.swift
```

---

## 11. Key Design Decisions

1. **iOS 18+ only**: Enables `@Observable` macro, latest SwiftUI APIs, SwiftData without workarounds, and Swift Charts improvements. The user base for a gym tracking device skews toward recent iPhones.

2. **SwiftData over Core Data**: Native Swift integration, simpler API, automatic CloudKit sync path for future. iOS 18 has resolved most early SwiftData issues.

3. **Binary file for IMU recordings**: SwiftData is not suited for high-frequency time-series data. Raw recordings go to binary files; only metadata lives in SwiftData.

4. **Auto-detect rest periods**: Rather than manual set tracking, the app listens for the module's idle state after reps. A configurable timeout (default 8s) triggers set completion, matching how lifters actually train.

5. **Exercise → Firmware profile mapping**: Most exercises use `EXERCISE_GENERIC`. Only compound lifts with specific movement signatures get dedicated profiles. This keeps the firmware simple while the app provides a rich catalog.

6. **Disconnect tolerance**: BLE drops happen in a gym. The app shows a banner but remains functional for history/stats browsing. Reconnect is automatic.

7. **No auth, future-ready**: A `userID` field exists in the model but is unused. Adding Firebase/Supabase auth later only requires implementing the auth flow and populating this field.

---

## 12. What Cannot Be Validated Without Hardware

- Real BLE connection latency and throughput (MTU negotiation, notification rate)
- IMU raw data stream reliability at 100+ Hz over BLE
- Auto-rest detection timing calibration (depends on real movement patterns)
- Exercise detection accuracy per profile
- Battery % reporting (not yet implemented in firmware)
- Real-world disconnect/reconnect behavior in a gym environment

---

## 13. Dependencies

- **No external dependencies** for v1. Everything uses Apple frameworks:
  - CoreBluetooth (BLE)
  - SwiftData (persistence)
  - Swift Charts (graphs)
  - SwiftUI (UI)
- Future consideration: if ML training is needed on-device, Core ML could be added.

---

## 14. Testing Strategy

| Layer | Approach |
|---|---|
| BLE parsing | Unit tests: feed known byte arrays, verify parsed structs |
| SessionManager | Unit tests: simulate event sequences, verify rep counting, set detection, rest timer |
| StatsEngine | Unit tests: seed SwiftData with known sessions, verify computed stats |
| BLE integration | Manual test with firmware in simulated mode |
| UI | Manual test + Xcode previews with mock data |
| Recording export | Unit test: verify CSV output format from known binary data |
