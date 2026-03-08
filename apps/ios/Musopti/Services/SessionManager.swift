import Foundation
import Observation
import SwiftData
import os

struct AccelSample: Identifiable {
    let id = UUID()
    let timestamp: Date
    let magnitude: Float
    let phase: MotionPhase
}

enum HoldResult: Equatable {
    case valid(durationMs: UInt32)
    case tooShort(durationMs: UInt32)
    case tooLong(durationMs: UInt32)
}

struct SessionFeedback: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let detail: String
    let isPositive: Bool
}

struct CurrentSetSummary: Equatable {
    let setNumber: Int
    let reps: Int
    let weightKg: Double?
    let averageHoldMs: Double?
    let holdSuccessRate: Double?
}

@MainActor
@Observable
final class SessionManager {

    // MARK: - Observable State

    var activeSession: WorkoutSession?
    var currentExercise: Exercise?
    var currentSetReps: Int = 0
    var currentPhase: MotionPhase = .idle
    var holdResult: HoldResult?
    var restTimerSeconds: Int = 0
    var isResting: Bool = false
    var currentWeightKg: Double?
    var liveAccelHistory: [AccelSample] = []
    var currentSetSummary: CurrentSetSummary?
    var lastFeedback: SessionFeedback?
    var holdTargetDisplay: String = "No hold target"
    var holdPhaseStartedAt: Date?
    var lastCompletedSessionID: UUID?

    var isSessionActive: Bool { activeSession != nil }
    var repCount: Int { activeSession?.totalReps ?? 0 }
    var currentSetNumber: Int {
        guard let session = activeSession else { return 1 }
        guard let exerciseLogIndex = currentExerciseLogIndex(in: session) else { return 1 }
        return session.exercises[exerciseLogIndex].sets.count + 1
    }

    // MARK: - Config

    var restTimeoutSeconds: Int = 8

    // MARK: - Private

    private let logger = Logger(subsystem: "com.musopti", category: "Session")
    private let feedbackCoordinator = SessionFeedbackCoordinator()
    private var modelContext: ModelContext?
    private var currentSetStart: Date?
    private var currentSetHoldDurations: [UInt32] = []
    private var currentSetHoldValids: [Bool] = []
    private var currentSetRepTimestamps: [Date] = []
    private var restTimer: Timer?
    private var restStartDate: Date?
    private let maxAccelHistory = 500

    // MARK: - Configuration

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func applyPreferences(_ preferences: AppPreferences) {
        restTimeoutSeconds = preferences.restTimerThreshold
        feedbackCoordinator.applyPreferences(preferences)
    }

    func resetLiveState() {
        cancelRestTimer()
        currentPhase = .idle
        holdPhaseStartedAt = nil
        holdResult = nil
        currentSetSummary = nil
        lastFeedback = nil
        liveAccelHistory = []
        resetCurrentSetTracking()
    }

    // MARK: - Event Handling

    func handleEvent(_ event: MusoptiEvent) {
        let previousPhase = currentPhase
        currentPhase = event.phase
        updatePhaseTracking(from: previousPhase, to: event.phase)
        appendAccelSample(for: event)

        switch event.eventType {
        case .stateChange:
            handleStateChange()

        case .repComplete:
            handleRepComplete()

        case .holdResult:
            handleHoldResult(event)

        case .sessionStart:
            if activeSession == nil {
                startSession(template: nil)
            }

        case .sessionStop:
            finishSession()
        }
    }

    // MARK: - Exercise Selection

    func selectExercise(_ exercise: Exercise) {
        if currentSetReps > 0 {
            saveCurrentSet()
        }

        currentExercise = exercise
        resetCurrentSetTracking()
        holdTargetDisplay = formattedHoldTarget(for: exercise)
        lastFeedback = SessionFeedback(
            title: "Exercise ready",
            detail: exercise.name,
            isPositive: true
        )

        if activeSession != nil {
            addExerciseLogIfNeeded()
        }

        updateCurrentSetSummary()
    }

    // MARK: - Weight

    func setWeight(_ kg: Double) {
        currentWeightKg = kg
        updateCurrentSetSummary()
    }

    // MARK: - Session Lifecycle

    func startSession(template: WorkoutTemplate? = nil) {
        guard activeSession == nil else { return }

        let session = WorkoutSession(
            templateID: template?.id,
            templateName: template?.name ?? "Freeform Session",
            startedAt: .now
        )

        if let template {
            session.exercises = template.exercises.map { entry in
                ExerciseLog(
                    exerciseID: entry.exerciseID,
                    exerciseName: entry.exerciseName,
                    order: entry.order
                )
            }
        }

        activeSession = session
        modelContext?.insert(session)
        save()

        lastFeedback = SessionFeedback(
            title: "Session started",
            detail: template?.name ?? "Freeform mode",
            isPositive: true
        )
        updateCurrentSetSummary()
        logger.info("Session started: \(session.id)")
    }

    func finishSession() {
        guard let session = activeSession else { return }

        if currentSetReps > 0 {
            saveCurrentSet()
        }

        session.finishedAt = .now
        save()

        lastCompletedSessionID = session.id
        logger.info("Session finished: \(session.id), \(session.totalReps) total reps")
        resetAllState()
    }

    func discardSession() {
        guard let session = activeSession else { return }

        modelContext?.delete(session)
        save()

        logger.info("Session discarded: \(session.id)")
        resetAllState()
    }

    // MARK: - Live Accel Data

    func addAccelSample(magnitude: Float) {
        let sample = AccelSample(
            timestamp: .now,
            magnitude: magnitude,
            phase: currentPhase
        )

        liveAccelHistory.append(sample)
        if liveAccelHistory.count > maxAccelHistory {
            liveAccelHistory.removeFirst(liveAccelHistory.count - maxAccelHistory)
        }
    }

    // MARK: - Private: Event Handlers

    private func handleStateChange() {
        if currentPhase == .idle && currentSetReps > 0 {
            startRestTimer()
        } else if currentPhase != .idle {
            cancelRestTimer()
        }
    }

    private func handleRepComplete() {
        let now = Date.now

        cancelRestTimer()
        currentSetReps += 1
        currentSetRepTimestamps.append(now)

        if currentSetStart == nil {
            currentSetStart = now
        }

        if activeSession == nil {
            startSession(template: nil)
        }

        addExerciseLogIfNeeded()
        updateCurrentSetSummary()

        lastFeedback = SessionFeedback(
            title: "Rep counted",
            detail: "Set \(currentSetNumber) now at \(currentSetReps) reps",
            isPositive: true
        )
        feedbackCoordinator.playRepComplete()
        logger.debug("Rep \(self.currentSetReps) recorded")
    }

    private func handleHoldResult(_ event: MusoptiEvent) {
        let duration = event.holdDurationMs

        if event.holdValid {
            holdResult = .valid(durationMs: duration)
        } else if let profile = currentExercise?.detectionProfile,
                  profile.holdTargetMs > 0 {
            let minDuration = max(Int(profile.holdTargetMs) - Int(profile.holdToleranceMs), 0)
            holdResult = duration < UInt32(minDuration)
                ? .tooShort(durationMs: duration)
                : .tooLong(durationMs: duration)
        } else {
            holdResult = .tooShort(durationMs: duration)
        }

        currentSetHoldDurations.append(duration)
        currentSetHoldValids.append(event.holdValid)
        updateCurrentSetSummary()

        switch holdResult {
        case .valid:
            lastFeedback = SessionFeedback(
                title: "Hold validated",
                detail: "\(duration) ms",
                isPositive: true
            )
        case .tooShort:
            lastFeedback = SessionFeedback(
                title: "Hold too short",
                detail: "\(duration) ms",
                isPositive: false
            )
        case .tooLong:
            lastFeedback = SessionFeedback(
                title: "Hold too long",
                detail: "\(duration) ms",
                isPositive: false
            )
        case .none:
            break
        }

        feedbackCoordinator.playHold(valid: event.holdValid)
    }

    // MARK: - Private: Rest Timer

    private func startRestTimer() {
        cancelRestTimer()
        restStartDate = .now
        restTimerSeconds = 0
        isResting = true

        restTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.restTimerSeconds += 1

                if self.restTimerSeconds >= self.restTimeoutSeconds {
                    self.saveCurrentSet()
                    self.cancelRestTimer()
                }
            }
        }
    }

    private func cancelRestTimer() {
        restTimer?.invalidate()
        restTimer = nil

        if isResting {
            isResting = false
            restTimerSeconds = 0
            restStartDate = nil
        }
    }

    // MARK: - Private: Set Persistence

    private func saveCurrentSet() {
        guard currentSetReps > 0, let session = activeSession else { return }

        addExerciseLogIfNeeded()

        guard let exerciseLogIndex = currentExerciseLogIndex(in: session) else {
            logger.warning("No exercise log to save set into")
            return
        }

        let now = Date.now
        let setNumber = session.exercises[exerciseLogIndex].sets.count + 1

        var restDuration: Double?
        if let previousSet = session.exercises[exerciseLogIndex].sets.last {
            restDuration = (currentSetStart ?? now).timeIntervalSince(previousSet.finishedAt)
        }

        let setLog = SetLog(
            setNumber: setNumber,
            reps: currentSetReps,
            weightKg: currentWeightKg,
            holdDurations: currentSetHoldDurations,
            holdValids: currentSetHoldValids,
            repTimestamps: currentSetRepTimestamps,
            startedAt: currentSetStart ?? now,
            finishedAt: now,
            restDurationSec: restDuration
        )

        session.exercises[exerciseLogIndex].sets.append(setLog)
        save()

        lastFeedback = SessionFeedback(
            title: "Set saved",
            detail: "\(currentSetReps) reps recorded",
            isPositive: true
        )
        logger.info("Set \(setNumber) saved: \(self.currentSetReps) reps")
        resetCurrentSetTracking()
        updateCurrentSetSummary()
    }

    // MARK: - Private: Exercise Log Management

    private func addExerciseLogIfNeeded() {
        guard let session = activeSession else { return }

        let exerciseID = currentExercise?.id ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        let exerciseName = currentExercise?.name ?? "Unknown Exercise"

        if session.exercises.contains(where: { $0.exerciseID == exerciseID }) {
            return
        }

        let log = ExerciseLog(
            exerciseID: exerciseID,
            exerciseName: exerciseName,
            order: session.exercises.count
        )
        session.exercises.append(log)
        save()
    }

    private func currentExerciseLogIndex(in session: WorkoutSession) -> Int? {
        let exerciseID = currentExercise?.id ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        return session.exercises.lastIndex(where: { $0.exerciseID == exerciseID })
    }

    // MARK: - Private: Accel Samples

    private func appendAccelSample(for event: MusoptiEvent) {
        let magnitude: Float
        switch event.phase {
        case .idle:
            magnitude = 0
        case .phaseA:
            magnitude = 0.4
        case .hold:
            magnitude = 0.15
        case .phaseB:
            magnitude = 0.65
        case .repComplete:
            magnitude = 0.85
        case .repInvalid:
            magnitude = 0.25
        }

        let sample = AccelSample(
            timestamp: .now,
            magnitude: magnitude,
            phase: event.phase
        )

        liveAccelHistory.append(sample)
        if liveAccelHistory.count > maxAccelHistory {
            liveAccelHistory.removeFirst(liveAccelHistory.count - maxAccelHistory)
        }
    }

    // MARK: - Private: Derived State

    private func updatePhaseTracking(from previousPhase: MotionPhase, to newPhase: MotionPhase) {
        if newPhase == .hold && previousPhase != .hold {
            holdPhaseStartedAt = .now
        } else if newPhase != .hold {
            holdPhaseStartedAt = nil
        }
    }

    private func updateCurrentSetSummary() {
        currentSetSummary = CurrentSetSummary(
            setNumber: currentSetNumber,
            reps: currentSetReps,
            weightKg: currentWeightKg,
            averageHoldMs: currentSetHoldDurations.isEmpty
                ? nil
                : Double(currentSetHoldDurations.reduce(0, +)) / Double(currentSetHoldDurations.count),
            holdSuccessRate: currentSetHoldValids.isEmpty
                ? nil
                : Double(currentSetHoldValids.filter(\.self).count) / Double(currentSetHoldValids.count)
        )
    }

    private func formattedHoldTarget(for exercise: Exercise?) -> String {
        guard let profile = exercise?.detectionProfile else {
            return "No hold target"
        }
        guard profile.requireHold, profile.holdTargetMs > 0 else {
            return "No hold target"
        }

        let seconds = Double(profile.holdTargetMs) / 1000
        let tolerance = Double(profile.holdToleranceMs) / 1000
        return String(format: "%.1fs target ± %.1fs", seconds, tolerance)
    }

    // MARK: - Private: State Reset

    private func resetCurrentSetTracking() {
        currentSetReps = 0
        currentSetStart = nil
        currentSetHoldDurations = []
        currentSetHoldValids = []
        currentSetRepTimestamps = []
        holdResult = nil
        holdPhaseStartedAt = nil
    }

    private func resetAllState() {
        activeSession = nil
        currentExercise = nil
        currentWeightKg = nil
        holdTargetDisplay = "No hold target"
        cancelRestTimer()
        resetLiveState()
    }

    // MARK: - Private: Persistence

    private func save() {
        do {
            try modelContext?.save()
        } catch {
            logger.error("Failed to save context: \(error.localizedDescription)")
        }
    }
}
