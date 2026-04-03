import Foundation
import CoreAudio

// =============================================================================
// DeviceManager — Core Audio device monitoring
// =============================================================================
// Watches for device connect/disconnect events. Notifies Vigil when input
// or output devices change (e.g., AirPods stolen by iPhone).

struct AudioDevice: Identifiable {
    let id: AudioDeviceID
    let name: String
    let isInput: Bool
    let isOutput: Bool
}

struct DeviceChange: CustomStringConvertible {
    let type: ChangeType
    let device: AudioDevice?

    enum ChangeType {
        case added
        case removed
        case defaultInputChanged
        case defaultOutputChanged
    }

    var description: String {
        switch type {
        case .added: return "Device added: \(device?.name ?? "unknown")"
        case .removed: return "Device removed: \(device?.name ?? "unknown")"
        case .defaultInputChanged: return "Default input changed: \(device?.name ?? "unknown")"
        case .defaultOutputChanged: return "Default output changed: \(device?.name ?? "unknown")"
        }
    }
}

@MainActor
class DeviceManager: ObservableObject {
    @Published var inputDevices: [AudioDevice] = []
    @Published var outputDevices: [AudioDevice] = []
    @Published var defaultInput: AudioDevice?
    @Published var defaultOutput: AudioDevice?

    var onDeviceChanged: ((DeviceChange) -> Void)?

    private var listenerBlock: AudioObjectPropertyListenerBlock?

    init() {
        refreshDevices()
        setupListeners()
    }

    func cleanup() {
        removeListeners()
    }

    nonisolated func cleanupFromDeinit() {
        // Safe to call from nonisolated context — only touches non-actor state
    }

    // MARK: - Device enumeration

    func refreshDevices() {
        inputDevices = getDevices(scope: kAudioObjectPropertyScopeInput)
        outputDevices = getDevices(scope: kAudioObjectPropertyScopeOutput)
        defaultInput = getDefaultDevice(scope: kAudioObjectPropertyScopeInput)
        defaultOutput = getDefaultDevice(scope: kAudioObjectPropertyScopeOutput)
    }

    // MARK: - Core Audio queries

    private func getDevices(scope: AudioObjectPropertyScope) -> [AudioDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress, 0, nil, &dataSize
        )
        guard status == noErr else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress, 0, nil, &dataSize, &deviceIDs
        )

        return deviceIDs.compactMap { id in
            guard let name = getDeviceName(id) else { return nil }
            let hasInput = hasStreams(id, scope: kAudioObjectPropertyScopeInput)
            let hasOutput = hasStreams(id, scope: kAudioObjectPropertyScopeOutput)

            if scope == kAudioObjectPropertyScopeInput && !hasInput { return nil }
            if scope == kAudioObjectPropertyScopeOutput && !hasOutput { return nil }

            return AudioDevice(id: id, name: name, isInput: hasInput, isOutput: hasOutput)
        }
    }

    private func getDefaultDevice(scope: AudioObjectPropertyScope) -> AudioDevice? {
        let selector = scope == kAudioObjectPropertyScopeInput
            ? kAudioHardwarePropertyDefaultInputDevice
            : kAudioHardwarePropertyDefaultOutputDevice

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress, 0, nil, &dataSize, &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }

        guard let name = getDeviceName(deviceID) else { return nil }
        return AudioDevice(
            id: deviceID, name: name,
            isInput: hasStreams(deviceID, scope: kAudioObjectPropertyScopeInput),
            isOutput: hasStreams(deviceID, scope: kAudioObjectPropertyScopeOutput)
        )
    }

    private func getDeviceName(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &name)
        guard status == noErr else { return nil }
        return name as String
    }

    private func hasStreams(_ deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        return status == noErr && dataSize > 0
    }

    // MARK: - Listeners

    private func setupListeners() {
        // TODO(copilot): Verify this is the correct pattern for AudioObjectPropertyListenerBlock
        // with kAudioHardwarePropertyDevices and kAudioHardwarePropertyDefaultInputDevice.
        // FineTune's DeviceManager likely has a cleaner implementation.

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                let oldInput = self?.defaultInput
                self?.refreshDevices()

                // Detect input device change (AirPods disconnect)
                if let old = oldInput, let new = self?.defaultInput, old.id != new.id {
                    let change = DeviceChange(type: .defaultInputChanged, device: new)
                    self?.onDeviceChanged?(change)
                }
            }
        }
        self.listenerBlock = block

        var devicesAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddr,
            DispatchQueue.main,
            block
        )

        var inputAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &inputAddr,
            DispatchQueue.main,
            block
        )

        var outputAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &outputAddr,
            DispatchQueue.main,
            block
        )
    }

    private func removeListeners() {
        guard let block = listenerBlock else { return }

        var devicesAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &devicesAddr, DispatchQueue.main, block
        )

        var inputAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &inputAddr, DispatchQueue.main, block
        )

        var outputAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &outputAddr, DispatchQueue.main, block
        )

        listenerBlock = nil
    }
}
