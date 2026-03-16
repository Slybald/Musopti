@preconcurrency import CoreBluetooth
import Foundation
import Observation
import os

enum BLEConnectionState: Equatable {
    case offline
    case searching
    case connecting
    case ready
    case recovering
    case error
}

struct DiscoveredPeripheral: Identifiable {
    let id: UUID
    let peripheral: CBPeripheral
    let name: String
    let rssi: Int
}

@MainActor
@Observable
final class BLEManager: NSObject, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {

    // MARK: - Observable State

    var connectionState: BLEConnectionState = .offline
    var bluetoothState: CBManagerState = .unknown
    var peripherals: [DiscoveredPeripheral] = []
    var lastEvent: MusoptiEvent?
    var lastRawSamples: [IMUSample] = []
    var signalStrength: Int?
    var deviceStatus: DeviceStatus = .placeholder
    var lastConfigSent: MusoptiConfig?
    var lastConfigReadBack: MusoptiConfig?
    var lastStatus: MusoptiStatus?
    var lastErrorMessage: String?
    var isConfigInSync: Bool = true

    // MARK: - Callbacks

    var onEventReceived: ((MusoptiEvent) -> Void)?
    var onRawDataReceived: (([IMUSample]) -> Void)?

    // MARK: - Private State

    private let logger = Logger(subsystem: "com.musopti", category: "BLE")
    @ObservationIgnored private var centralManager: CBCentralManager!

    @ObservationIgnored private var connectedPeripheral: CBPeripheral?
    @ObservationIgnored private var eventCharacteristic: CBCharacteristic?
    @ObservationIgnored private var configCharacteristic: CBCharacteristic?
    @ObservationIgnored private var rawDataCharacteristic: CBCharacteristic?
    @ObservationIgnored private var statusCharacteristic: CBCharacteristic?
    @ObservationIgnored private var readConfigCompletion: ((MusoptiConfig?) -> Void)?
    @ObservationIgnored private var readStatusCompletion: ((MusoptiStatus?) -> Void)?
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored private var rssiTimer: Timer?
    @ObservationIgnored private var allowAutoReconnect = true
    @ObservationIgnored private var userInitiatedDisconnect = false
    @ObservationIgnored private var lastEventAt: Date?
    @ObservationIgnored private var lastConfigSyncAt: Date?
    @ObservationIgnored private var lastStatusAt: Date?

    private var lastKnownPeripheralID: UUID? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: "musopti.lastPeripheralID") else { return nil }
            return UUID(uuidString: raw)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.uuidString, forKey: "musopti.lastPeripheralID")
            } else {
                UserDefaults.standard.removeObject(forKey: "musopti.lastPeripheralID")
            }
        }
    }

    private var lastKnownPeripheralName: String? {
        get {
            UserDefaults.standard.string(forKey: "musopti.lastPeripheralName")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "musopti.lastPeripheralName")
        }
    }

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        updateDeviceStatus()
    }

    // MARK: - Public Methods

    func setAutoReconnectEnabled(_ isEnabled: Bool) {
        allowAutoReconnect = isEnabled
        if !isEnabled {
            reconnectTask?.cancel()
        }
    }

    func startScanningIfNeeded() {
        guard bluetoothState == .poweredOn else {
            connectionState = .offline
            lastErrorMessage = bluetoothState == .poweredOff ? "Bluetooth is turned off." : nil
            updateDeviceStatus()
            return
        }

        guard connectionState != .searching,
              connectionState != .connecting,
              connectionState != .ready
        else {
            return
        }

        startScanning()
    }

    func startScanning() {
        guard bluetoothState == .poweredOn else {
            connectionState = .offline
            lastErrorMessage = "Bluetooth is turned off."
            updateDeviceStatus()
            return
        }

        reconnectTask?.cancel()
        peripherals = []
        connectionState = .searching
        lastErrorMessage = nil
        centralManager.stopScan()
        centralManager.scanForPeripherals(
            withServices: [BLEConstants.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        updateDeviceStatus()
        logger.info("Started scanning for Musopti devices")
    }

    func stopScanning() {
        centralManager.stopScan()
        if connectionState == .searching {
            connectionState = .offline
            updateDeviceStatus()
        }
        logger.info("Stopped scanning")
    }

    func connect(to discovered: DiscoveredPeripheral) {
        userInitiatedDisconnect = false
        reconnectTask?.cancel()
        stopScanning()
        lastErrorMessage = nil
        connectionState = .connecting
        connectedPeripheral = discovered.peripheral
        connectedPeripheral?.delegate = self
        lastKnownPeripheralID = discovered.id
        lastKnownPeripheralName = discovered.name
        centralManager.connect(discovered.peripheral, options: nil)
        updateDeviceStatus()
        logger.info("Connecting to \(discovered.name)")
    }

    func disconnect() {
        userInitiatedDisconnect = true
        reconnectTask?.cancel()
        stopRSSITimer()

        if let peripheral = connectedPeripheral {
            if let eventCharacteristic {
                peripheral.setNotifyValue(false, for: eventCharacteristic)
            }
            if let rawDataCharacteristic {
                peripheral.setNotifyValue(false, for: rawDataCharacteristic)
            }
            centralManager.cancelPeripheralConnection(peripheral)
        }

        cleanupConnection()
        connectionState = .offline
        lastErrorMessage = nil
        updateDeviceStatus()
        logger.info("Disconnected by user request")
    }

    func writeConfig(_ config: MusoptiConfig, verifyReadBack: Bool = true) {
        guard let peripheral = connectedPeripheral,
              let characteristic = configCharacteristic
        else {
            lastErrorMessage = "Cannot send config while the device is unavailable."
            isConfigInSync = false
            updateDeviceStatus()
            return
        }

        lastConfigSent = config
        isConfigInSync = false
        lastConfigSyncAt = nil
        updateDeviceStatus()
        peripheral.writeValue(config.toData(), for: characteristic, type: .withResponse)
        logger.info("Wrote config for mode \(config.deviceMode.rawValue) and exercise \(config.exerciseType.rawValue)")

        if verifyReadBack {
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                self?.refreshConfig()
                self?.refreshStatus()
            }
        }
    }

    func refreshConfig() {
        readConfig { [weak self] config in
            self?.handleConfigReadBack(config)
        }
    }

    func refreshStatus() {
        readStatus { [weak self] status in
            self?.handleStatusReadBack(status)
        }
    }

    func readConfig(completion: @escaping (MusoptiConfig?) -> Void) {
        guard let peripheral = connectedPeripheral,
              let characteristic = configCharacteristic
        else {
            logger.warning("Cannot read config: not connected or characteristic not found")
            completion(nil)
            return
        }

        readConfigCompletion = completion
        peripheral.readValue(for: characteristic)
    }

    func readStatus(completion: @escaping (MusoptiStatus?) -> Void) {
        guard let peripheral = connectedPeripheral,
              let characteristic = statusCharacteristic
        else {
            logger.warning("Cannot read status: not connected or characteristic not found")
            completion(nil)
            return
        }

        readStatusCompletion = completion
        peripheral.readValue(for: characteristic)
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state

        switch central.state {
        case .poweredOn:
            if allowAutoReconnect && !userInitiatedDisconnect {
                attemptAutoReconnect()
            } else {
                connectionState = .offline
            }
            lastErrorMessage = nil

        case .poweredOff:
            stopRSSITimer()
            cleanupConnection()
            connectionState = .offline
            lastErrorMessage = "Bluetooth is turned off."

        case .resetting:
            stopRSSITimer()
            cleanupConnection()
            connectionState = .recovering
            lastErrorMessage = "Bluetooth is resetting."

        case .unauthorized:
            stopRSSITimer()
            cleanupConnection()
            connectionState = .error
            lastErrorMessage = "Bluetooth permission is required."

        case .unsupported:
            stopRSSITimer()
            cleanupConnection()
            connectionState = .error
            lastErrorMessage = "Bluetooth is unsupported on this device."

        case .unknown:
            connectionState = .offline

        @unknown default:
            connectionState = .error
            lastErrorMessage = "Bluetooth is unavailable."
        }

        updateDeviceStatus()
        logger.info("Central manager state changed to \(central.state.rawValue)")
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let rssiValue = RSSI.intValue
        guard rssiValue != 127 else { return }

        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? "Unknown"

        guard name.contains(BLEConstants.deviceName) else { return }

        let discovered = DiscoveredPeripheral(
            id: peripheral.identifier,
            peripheral: peripheral,
            name: name,
            rssi: rssiValue
        )

        if let index = peripherals.firstIndex(where: { $0.id == discovered.id }) {
            peripherals[index] = discovered
        } else {
            peripherals.append(discovered)
        }

        sortPeripherals()
        logger.info("Discovered \(name) (RSSI: \(rssiValue))")
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionState = .connecting
        connectedPeripheral = peripheral
        lastKnownPeripheralID = peripheral.identifier
        lastKnownPeripheralName = peripheral.name ?? lastKnownPeripheralName
        peripheral.delegate = self
        peripheral.discoverServices([BLEConstants.serviceUUID])
        updateDeviceStatus()
        logger.info("Connected to \(peripheral.name ?? "unknown")")
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        logger.info("Disconnected from \(peripheral.name ?? "unknown"): \(error?.localizedDescription ?? "no error")")
        stopRSSITimer()
        cleanupConnection()

        if userInitiatedDisconnect {
            connectionState = .offline
            userInitiatedDisconnect = false
        } else if allowAutoReconnect {
            connectionState = .recovering
            scheduleReconnect()
        } else {
            connectionState = .offline
        }

        updateDeviceStatus()
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        logger.error("Failed to connect: \(error?.localizedDescription ?? "unknown error")")
        cleanupConnection()
        lastErrorMessage = error?.localizedDescription ?? "Failed to connect."

        if allowAutoReconnect {
            connectionState = .recovering
            scheduleReconnect()
        } else {
            connectionState = .error
        }

        updateDeviceStatus()
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            logger.error("Service discovery failed: \(error.localizedDescription)")
            lastErrorMessage = error.localizedDescription
            connectionState = .error
            updateDeviceStatus()
            return
        }

        guard let service = peripheral.services?.first(where: { $0.uuid == BLEConstants.serviceUUID }) else {
            lastErrorMessage = "Musopti service not found."
            connectionState = .error
            updateDeviceStatus()
            return
        }

        peripheral.discoverCharacteristics(
            [
                BLEConstants.eventCharUUID,
                BLEConstants.configCharUUID,
                BLEConstants.rawDataCharUUID,
                BLEConstants.statusCharUUID,
            ],
            for: service
        )
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error {
            logger.error("Characteristic discovery failed: \(error.localizedDescription)")
            lastErrorMessage = error.localizedDescription
            connectionState = .error
            updateDeviceStatus()
            return
        }

        guard let characteristics = service.characteristics else { return }

        for characteristic in characteristics {
            switch characteristic.uuid {
            case BLEConstants.eventCharUUID:
                eventCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)

            case BLEConstants.configCharUUID:
                configCharacteristic = characteristic

            case BLEConstants.rawDataCharUUID:
                rawDataCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)

            case BLEConstants.statusCharUUID:
                statusCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)

            default:
                break
            }
        }

        connectionState = .ready
        lastErrorMessage = nil
        startRSSITimer(for: peripheral)
        updateDeviceStatus()
        refreshConfig()
        refreshStatus()
        logger.info("BLE characteristics ready")
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            logger.error("Characteristic update error: \(error.localizedDescription)")
            lastErrorMessage = error.localizedDescription
            updateDeviceStatus()
            return
        }

        guard let data = characteristic.value else { return }

        switch characteristic.uuid {
        case BLEConstants.eventCharUUID:
            guard let event = MusoptiEvent.parse(from: data) else {
                logger.warning("Failed to parse event (\(data.count) bytes)")
                return
            }
            lastEvent = event
            lastEventAt = .now
            updateDeviceStatus()
            onEventReceived?(event)

        case BLEConstants.rawDataCharUUID:
            guard let samples = RawDataParser.parse(from: data) else {
                logger.warning("Failed to parse raw data (\(data.count) bytes)")
                return
            }
            lastRawSamples = samples
            onRawDataReceived?(samples)

        case BLEConstants.configCharUUID:
            let config = MusoptiConfig.parse(from: data)
            handleConfigReadBack(config)
            readConfigCompletion?(config)
            readConfigCompletion = nil

        case BLEConstants.statusCharUUID:
            let status = MusoptiStatus.parse(from: data)
            handleStatusReadBack(status)
            readStatusCompletion?(status)
            readStatusCompletion = nil

        default:
            break
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        if let error {
            logger.warning("RSSI read error: \(error.localizedDescription)")
            return
        }

        signalStrength = RSSI.intValue
        updateDeviceStatus()
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            logger.error("Write to \(characteristic.uuid) failed: \(error.localizedDescription)")
            lastErrorMessage = error.localizedDescription
            isConfigInSync = false
            updateDeviceStatus()
        }
    }

    // MARK: - Auto-Reconnect

    private func attemptAutoReconnect() {
        guard allowAutoReconnect,
              let savedID = lastKnownPeripheralID
        else {
            connectionState = .offline
            updateDeviceStatus()
            return
        }

        let peripherals = centralManager.retrievePeripherals(withIdentifiers: [savedID])
        if let peripheral = peripherals.first {
            connectionState = .recovering
            connectedPeripheral = peripheral
            peripheral.delegate = self
            centralManager.connect(peripheral, options: nil)
            updateDeviceStatus()
            logger.info("Attempting auto-reconnect to \(savedID.uuidString)")
        } else {
            connectionState = .offline
            updateDeviceStatus()
        }
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self,
                  !Task.isCancelled,
                  self.allowAutoReconnect,
                  self.bluetoothState == .poweredOn
            else {
                return
            }
            self.attemptAutoReconnect()
        }
    }

    // MARK: - RSSI Timer

    private func startRSSITimer(for peripheral: CBPeripheral) {
        stopRSSITimer()
        rssiTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak peripheral] _ in
            peripheral?.readRSSI()
        }
    }

    private func stopRSSITimer() {
        rssiTimer?.invalidate()
        rssiTimer = nil
    }

    // MARK: - Helpers

    private func handleConfigReadBack(_ config: MusoptiConfig?) {
        lastConfigReadBack = config
        evaluateConfigSync()
    }

    private func handleStatusReadBack(_ status: MusoptiStatus?) {
        lastStatus = status
        lastStatusAt = status == nil ? nil : .now
        evaluateConfigSync()
    }

    private func evaluateConfigSync() {
        isConfigInSync = BLESyncEvaluator.isInSync(
            sent: lastConfigSent,
            readBack: lastConfigReadBack,
            status: lastStatus
        )

        if isConfigInSync {
            if lastConfigReadBack != nil || lastStatus != nil {
                lastConfigSyncAt = .now
            }
            if BLESyncEvaluator.syncErrorMessage(
                sent: lastConfigSent,
                readBack: lastConfigReadBack,
                status: lastStatus
            ) == nil {
                lastErrorMessage = nil
            }
        } else if let syncError = BLESyncEvaluator.syncErrorMessage(
            sent: lastConfigSent,
            readBack: lastConfigReadBack,
            status: lastStatus
        ) {
            lastErrorMessage = syncError
            lastConfigSyncAt = nil
        }

        updateDeviceStatus()
    }

    private func sortPeripherals() {
        peripherals.sort { lhs, rhs in
            let lhsPriority = lhs.id == lastKnownPeripheralID ? 0 : 1
            let rhsPriority = rhs.id == lastKnownPeripheralID ? 0 : 1
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            if lhs.rssi != rhs.rssi {
                return lhs.rssi > rhs.rssi
            }
            return lhs.name < rhs.name
        }
    }

    private func updateDeviceStatus() {
        let exercise = lastStatus?.exerciseType ?? lastEvent?.exerciseType ?? lastConfigReadBack?.exerciseType ?? lastConfigSent?.exerciseType
        let mode = lastStatus?.deviceMode ?? lastEvent?.deviceMode ?? lastConfigReadBack?.deviceMode ?? lastConfigSent?.deviceMode
        let motionPhase = lastStatus?.motionPhase ?? lastEvent?.phase

        let mappedState: DeviceConnectionState
        switch connectionState {
        case .offline:
            mappedState = .offline
        case .searching:
            mappedState = .searching
        case .connecting:
            mappedState = .connecting
        case .ready:
            mappedState = .ready
        case .recovering:
            mappedState = .recovering
        case .error:
            mappedState = .error
        }

        deviceStatus = DeviceStatus(
            connectionState: mappedState,
            bluetoothState: bluetoothState,
            rssi: signalStrength,
            batteryPercent: lastStatus?.batteryPercent,
            deviceMode: mode,
            firmwareExercise: exercise,
            motionPhase: motionPhase,
            appliedSampleRateHz: lastStatus.map { Int($0.sampleRateHz) },
            configRevision: lastStatus.map { Int($0.configRevision) },
            firmwareVersion: lastStatus?.firmwareVersion,
            isIMUSimulated: lastStatus?.isIMUSimulated ?? false,
            isDisplaySimulated: lastStatus?.isDisplaySimulated ?? false,
            isAudioSimulated: lastStatus?.isAudioSimulated ?? false,
            lastEventAt: lastEventAt,
            lastStatusAt: lastStatusAt,
            isRecovering: connectionState == .recovering,
            lastKnownDeviceName: lastKnownPeripheralName,
            lastConfigSyncAt: lastConfigSyncAt
        )
    }

    private func cleanupConnection() {
        connectedPeripheral = nil
        eventCharacteristic = nil
        configCharacteristic = nil
        rawDataCharacteristic = nil
        statusCharacteristic = nil
        readConfigCompletion = nil
        readStatusCompletion = nil
        signalStrength = nil
        lastRawSamples = []
        updateDeviceStatus()
    }
}
