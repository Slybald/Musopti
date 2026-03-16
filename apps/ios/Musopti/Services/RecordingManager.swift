import CoreBluetooth
import Foundation
import Observation
import SwiftData
import os

enum RecordingState: Equatable {
    case idle
    case recording
    case finishing
    case error
}

enum RecordingQuality: String, Equatable {
    case ok
    case noIncomingSamples
    case unexpectedLowRate

    var title: String {
        switch self {
        case .ok: return "OK"
        case .noIncomingSamples: return "No incoming samples"
        case .unexpectedLowRate: return "Unexpected low rate"
        }
    }
}

enum RecordingPreflightIssue: Equatable {
    case bluetoothUnavailable
    case deviceNotReady
    case unsupportedSampleRate

    var title: String {
        switch self {
        case .bluetoothUnavailable:
            return "Bluetooth is unavailable."
        case .deviceNotReady:
            return "The Musopti device is not ready."
        case .unsupportedSampleRate:
            return "This sample rate is not supported."
        }
    }
}

enum RecordingExportFormat: String, CaseIterable, Identifiable {
    case csv
    case binary
    case datasetBundle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .csv: return "CSV"
        case .binary: return "Binary"
        case .datasetBundle: return "Dataset Bundle"
        }
    }
}

enum RecordingPreflightEvaluator {
    static func evaluate(
        sampleRateHz: Int,
        bluetoothState: CBManagerState,
        deviceStatus: DeviceStatus
    ) -> RecordingPreflightIssue? {
        let supportedSampleRates = [50, 100, 200]

        guard bluetoothState == .poweredOn else {
            return .bluetoothUnavailable
        }

        guard deviceStatus.isReady else {
            return .deviceNotReady
        }

        guard supportedSampleRates.contains(sampleRateHz) else {
            return .unsupportedSampleRate
        }

        return nil
    }
}

struct RecordingPreviewPoint: Identifiable, Equatable {
    let id = UUID()
    let magnitude: Double
}

struct RecordingSummary: Identifiable, Equatable {
    let id = UUID()
    let recordingID: UUID
    let duration: TimeInterval
    let sampleCount: Int
    let requestedSampleRateHz: Int
    let observedSampleRateHz: Double?
}

struct RecordingDatasetMetadata: Codable, Equatable {
    let recordingID: String
    let exercise: String
    let requestedSampleRateHz: Int
    let observedSampleRateHz: Double?
    let appliedSampleRateHz: Int?
    let appVersion: String
    let firmwareVersion: String?
    let configRevision: Int?
    let startedAt: Date
    let finishedAt: Date?
}

@MainActor
@Observable
final class RecordingManager {

    // MARK: - Observable State

    var isRecording: Bool = false
    var currentRecording: IMURecording?
    var sampleCount: Int = 0
    var elapsedSeconds: Double = 0
    var livePreviewSamples: [RecordingPreviewPoint] = []
    var preflightIssue: RecordingPreflightIssue?
    var recordingState: RecordingState = .idle
    var recordingQuality: RecordingQuality = .ok
    var lastCompletedSummary: RecordingSummary?
    var preferredSampleRateHz: Int = 100

    // MARK: - Private

    private var modelContext: ModelContext?
    private var fileHandle: FileHandle?
    private var timer: Timer?
    private var startTime: Date?
    private var lastSampleReceivedAt: Date?
    private var requestedSampleRateHz: Int?
    private let logger = Logger(subsystem: "com.musopti", category: "Recording")
    private static let sampleSize = 28
    private let maxPreviewSamples = 120

    // MARK: - Configuration

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func applyPreferences(_ preferences: AppPreferences) {
        preferredSampleRateHz = preferences.defaultSampleRateHz
    }

    func preparePreflight(exercise: Exercise?, sampleRateHz: Int, bleManager: BLEManager) {
        preflightIssue = evaluatePreflight(exercise: exercise, sampleRateHz: sampleRateHz, bleManager: bleManager)
    }

    // MARK: - Start Recording

    func startRecording(exercise: Exercise?, sampleRateHz: Int, bleManager: BLEManager) {
        guard !isRecording else { return }

        let issue = evaluatePreflight(exercise: exercise, sampleRateHz: sampleRateHz, bleManager: bleManager)
        preflightIssue = issue
        guard issue == nil else {
            recordingState = .error
            return
        }

        let recordingID = UUID()
        let fileName = "recording_\(recordingID.uuidString).bin"
        let fileURL = Self.recordingsDirectory.appendingPathComponent(fileName)

        Self.ensureRecordingsDirectory()
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)

        guard let handle = try? FileHandle(forWritingTo: fileURL) else {
            logger.error("Failed to open file handle for \(fileURL.path)")
            recordingState = .error
            return
        }

        let recording = IMURecording(
            id: recordingID,
            exerciseID: exercise?.id,
            exerciseName: exercise?.name ?? "Unspecified",
            sampleRateHz: sampleRateHz,
            startedAt: .now,
            sampleCount: 0,
            filePath: fileName
        )

        modelContext?.insert(recording)
        save()

        fileHandle = handle
        currentRecording = recording
        sampleCount = 0
        elapsedSeconds = 0
        livePreviewSamples = []
        startTime = .now
        lastSampleReceivedAt = nil
        requestedSampleRateHz = sampleRateHz
        isRecording = true
        recordingState = .recording
        recordingQuality = .noIncomingSamples
        lastCompletedSummary = nil
        persistMetadata(
            for: recording,
            requestedSampleRateHz: sampleRateHz,
            observedSampleRateHz: nil,
            bleManager: bleManager
        )

        let config = MusoptiConfig(
            deviceMode: .recording,
            exerciseType: exerciseTypeFrom(exercise),
            holdTargetMs: 0,
            holdToleranceMs: 0,
            minRepDurationMs: 0,
            sampleRateHz: UInt16(sampleRateHz)
        )
        bleManager.writeConfig(config, verifyReadBack: true)

        bleManager.onRawDataReceived = { [weak self] samples in
            self?.handleSamples(samples)
        }

        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if let start = self.startTime {
                    self.elapsedSeconds = Date.now.timeIntervalSince(start)
                }
                self.updateRecordingQuality()
            }
        }

        logger.info("Recording started: \(recordingID)")
    }

    // MARK: - Stop Recording

    func stopRecording(bleManager: BLEManager) {
        guard isRecording else { return }

        recordingState = .finishing
        timer?.invalidate()
        timer = nil
        bleManager.onRawDataReceived = nil
        bleManager.writeConfig(.defaultDetection, verifyReadBack: true)

        fileHandle?.closeFile()
        fileHandle = nil

        let duration = elapsedSeconds
        let observedRate = duration > 0 ? Double(sampleCount) / duration : nil
        let recordingID = currentRecording?.id ?? UUID()

        if let recording = currentRecording {
            recording.finishedAt = .now
            recording.sampleCount = sampleCount
            persistMetadata(
                for: recording,
                requestedSampleRateHz: requestedSampleRateHz ?? preferredSampleRateHz,
                observedSampleRateHz: observedRate,
                bleManager: bleManager
            )
            save()
            logger.info("Recording stopped: \(recording.id), \(self.sampleCount) samples")
        }

        lastCompletedSummary = RecordingSummary(
            recordingID: recordingID,
            duration: duration,
            sampleCount: sampleCount,
            requestedSampleRateHz: requestedSampleRateHz ?? preferredSampleRateHz,
            observedSampleRateHz: observedRate
        )

        isRecording = false
        currentRecording = nil
        startTime = nil
        lastSampleReceivedAt = nil
        requestedSampleRateHz = nil
        recordingState = .idle
        recordingQuality = .ok
    }

    // MARK: - Export

    func exportToCSV(recording: IMURecording) -> URL? {
        let binURL = Self.recordingsDirectory.appendingPathComponent(recording.filePath)
        guard let binData = try? Data(contentsOf: binURL) else {
            logger.error("Cannot read binary file: \(recording.filePath)")
            return nil
        }

        let csvName = recording.filePath.replacingOccurrences(of: ".bin", with: ".csv")
        let csvURL = Self.recordingsDirectory.appendingPathComponent(csvName)

        var csv = "timestamp_ms,accel_x,accel_y,accel_z,gyro_x,gyro_y,gyro_z\n"

        let count = binData.count / Self.sampleSize
        for i in 0..<count {
            let offset = i * Self.sampleSize
            guard let accelX = binData.readFloat32LE(at: offset),
                  let accelY = binData.readFloat32LE(at: offset + 4),
                  let accelZ = binData.readFloat32LE(at: offset + 8),
                  let gyroX = binData.readFloat32LE(at: offset + 12),
                  let gyroY = binData.readFloat32LE(at: offset + 16),
                  let gyroZ = binData.readFloat32LE(at: offset + 20),
                  let timestampMs = binData.readUInt32LE(at: offset + 24)
            else { continue }

            csv += "\(timestampMs),\(accelX),\(accelY),\(accelZ),\(gyroX),\(gyroY),\(gyroZ)\n"
        }

        do {
            try csv.write(to: csvURL, atomically: true, encoding: .utf8)
            return csvURL
        } catch {
            logger.error("Failed to write CSV: \(error.localizedDescription)")
            return nil
        }
    }

    func exportSelected(_ recordings: [IMURecording], format: RecordingExportFormat) -> [URL] {
        recordings.compactMap { recording in
            switch format {
            case .csv:
                return exportToCSV(recording: recording)
            case .binary:
                let url = Self.recordingsDirectory.appendingPathComponent(recording.filePath)
                return FileManager.default.fileExists(atPath: url.path) ? url : nil
            case .datasetBundle:
                return exportDatasetBundle(recording: recording)
            }
        }
    }

    func exportDatasetBundle(recording: IMURecording) -> URL? {
        let sourceURL = Self.recordingsDirectory.appendingPathComponent(recording.filePath)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            logger.error("Cannot export dataset bundle: missing binary file \(recording.filePath)")
            return nil
        }

        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("musopti_dataset_\(recording.id.uuidString)", isDirectory: true)
        let samplesURL = bundleURL.appendingPathComponent("samples.bin")
        let metadataURL = bundleURL.appendingPathComponent("metadata.json")

        try? FileManager.default.removeItem(at: bundleURL)

        do {
            try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: sourceURL, to: samplesURL)

            let metadata = loadMetadata(for: recording) ?? fallbackMetadata(for: recording)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(metadata)
            try data.write(to: metadataURL, options: .atomic)
            return bundleURL
        } catch {
            logger.error("Failed to export dataset bundle: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Delete Recording

    func deleteRecording(_ recording: IMURecording) {
        let binURL = Self.recordingsDirectory.appendingPathComponent(recording.filePath)
        let csvName = recording.filePath.replacingOccurrences(of: ".bin", with: ".csv")
        let csvURL = Self.recordingsDirectory.appendingPathComponent(csvName)
        let metadataURL = Self.metadataURL(for: recording.filePath)

        try? FileManager.default.removeItem(at: binURL)
        try? FileManager.default.removeItem(at: csvURL)
        try? FileManager.default.removeItem(at: metadataURL)

        modelContext?.delete(recording)
        save()

        logger.info("Deleted recording: \(recording.id)")
    }

    // MARK: - Read Samples from Binary

    static func readSamples(from recording: IMURecording) -> [IMUSample] {
        let url = recordingsDirectory.appendingPathComponent(recording.filePath)
        guard let data = try? Data(contentsOf: url) else { return [] }

        let count = data.count / sampleSize
        var samples: [IMUSample] = []
        samples.reserveCapacity(count)

        for i in 0..<count {
            let offset = i * sampleSize
            guard let accelX = data.readFloat32LE(at: offset),
                  let accelY = data.readFloat32LE(at: offset + 4),
                  let accelZ = data.readFloat32LE(at: offset + 8),
                  let gyroX = data.readFloat32LE(at: offset + 12),
                  let gyroY = data.readFloat32LE(at: offset + 16),
                  let gyroZ = data.readFloat32LE(at: offset + 20),
                  let timestampMs = data.readUInt32LE(at: offset + 24)
            else { continue }

            samples.append(IMUSample(
                accelX: accelX,
                accelY: accelY,
                accelZ: accelZ,
                gyroX: gyroX,
                gyroY: gyroY,
                gyroZ: gyroZ,
                timestampMs: timestampMs
            ))
        }

        return samples
    }

    // MARK: - Private

    private func handleSamples(_ samples: [IMUSample]) {
        guard let handle = fileHandle else { return }

        var buffer = Data(capacity: samples.count * Self.sampleSize)

        for sample in samples {
            var ax = sample.accelX
            var ay = sample.accelY
            var az = sample.accelZ
            var gx = sample.gyroX
            var gy = sample.gyroY
            var gz = sample.gyroZ
            var ts = sample.timestampMs.littleEndian

            buffer.append(Data(bytes: &ax, count: 4))
            buffer.append(Data(bytes: &ay, count: 4))
            buffer.append(Data(bytes: &az, count: 4))
            buffer.append(Data(bytes: &gx, count: 4))
            buffer.append(Data(bytes: &gy, count: 4))
            buffer.append(Data(bytes: &gz, count: 4))
            buffer.append(Data(bytes: &ts, count: 4))

            let magnitude = sqrt(
                Double(sample.accelX * sample.accelX)
                + Double(sample.accelY * sample.accelY)
                + Double(sample.accelZ * sample.accelZ)
            )
            livePreviewSamples.append(RecordingPreviewPoint(magnitude: magnitude))
        }

        if livePreviewSamples.count > maxPreviewSamples {
            livePreviewSamples.removeFirst(livePreviewSamples.count - maxPreviewSamples)
        }

        handle.write(buffer)
        sampleCount += samples.count
        lastSampleReceivedAt = .now
        updateRecordingQuality()
    }

    private func updateRecordingQuality() {
        guard isRecording else { return }

        let noIncomingData = lastSampleReceivedAt == nil
            || Date.now.timeIntervalSince(lastSampleReceivedAt!) > 1.2

        if noIncomingData && elapsedSeconds > 1 {
            recordingQuality = .noIncomingSamples
            return
        }

        if let requestedSampleRateHz,
           elapsedSeconds > 2 {
            let observedRate = Double(sampleCount) / max(elapsedSeconds, 0.001)
            if observedRate < Double(requestedSampleRateHz) * 0.75 {
                recordingQuality = .unexpectedLowRate
                return
            }
        }

        recordingQuality = sampleCount > 0 ? .ok : .noIncomingSamples
    }

    private func evaluatePreflight(exercise: Exercise?, sampleRateHz: Int, bleManager: BLEManager) -> RecordingPreflightIssue? {
        _ = exercise
        return RecordingPreflightEvaluator.evaluate(
            sampleRateHz: sampleRateHz,
            bluetoothState: bleManager.bluetoothState,
            deviceStatus: bleManager.deviceStatus
        )
    }

    private func exerciseTypeFrom(_ exercise: Exercise?) -> MusoptiExerciseType {
        guard let exercise else { return .generic }
        return MusoptiExerciseType(rawValue: exercise.detectionProfile.firmwareExerciseType) ?? .generic
    }

    private func save() {
        do {
            try modelContext?.save()
        } catch {
            logger.error("Failed to save context: \(error.localizedDescription)")
        }
    }

    // MARK: - File System

    static var recordingsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Recordings", isDirectory: true)
    }

    private static func metadataURL(for filePath: String) -> URL {
        let metadataFileName = filePath.replacingOccurrences(of: ".bin", with: ".metadata.json")
        return recordingsDirectory.appendingPathComponent(metadataFileName)
    }

    private static func ensureRecordingsDirectory() {
        let url = recordingsDirectory
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private func persistMetadata(
        for recording: IMURecording,
        requestedSampleRateHz: Int,
        observedSampleRateHz: Double?,
        bleManager: BLEManager
    ) {
        let metadata = RecordingDatasetMetadata(
            recordingID: recording.id.uuidString,
            exercise: recording.exerciseName,
            requestedSampleRateHz: requestedSampleRateHz,
            observedSampleRateHz: observedSampleRateHz,
            appliedSampleRateHz: bleManager.deviceStatus.appliedSampleRateHz,
            appVersion: appVersion,
            firmwareVersion: bleManager.deviceStatus.firmwareVersion?.title,
            configRevision: bleManager.deviceStatus.configRevision,
            startedAt: recording.startedAt,
            finishedAt: recording.finishedAt
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(metadata)
            try data.write(to: Self.metadataURL(for: recording.filePath), options: .atomic)
        } catch {
            logger.error("Failed to persist recording metadata: \(error.localizedDescription)")
        }
    }

    private func loadMetadata(for recording: IMURecording) -> RecordingDatasetMetadata? {
        let url = Self.metadataURL(for: recording.filePath)
        guard let data = try? Data(contentsOf: url) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(RecordingDatasetMetadata.self, from: data)
    }

    private func fallbackMetadata(for recording: IMURecording) -> RecordingDatasetMetadata {
        RecordingDatasetMetadata(
            recordingID: recording.id.uuidString,
            exercise: recording.exerciseName,
            requestedSampleRateHz: recording.sampleRateHz,
            observedSampleRateHz: recording.observedSampleRate,
            appliedSampleRateHz: nil,
            appVersion: appVersion,
            firmwareVersion: nil,
            configRevision: nil,
            startedAt: recording.startedAt,
            finishedAt: recording.finishedAt
        )
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
