import Foundation
import AudioToolbox
import PreviewContracts

public enum MIDIPlaybackFailure: Error, Equatable, Sendable {
    case invalidPresentation, soundBankUnavailable, audioUnavailable
}

@MainActor
public protocol MIDIPlaybackDevice: AnyObject {
    func send(status: UInt8, data1: UInt8, data2: UInt8) throws
    func silence()
    func close()
}

/// Audio and timing belong to the visible native control surface, never to parsing.
@MainActor
public final class NativeMIDIPlayback {
    public private(set) var position: Double = 0
    public private(set) var isPlaying = false
    public var onChange: ((Double, Bool) -> Void)?
    public var onFailure: ((MIDIPlaybackFailure) -> Void)?
    private var presentation: MIDIPresentation?
    private var device: (any MIDIPlaybackDevice)?
    private var timer: Task<Void, Never>?
    private var eventIndex = 0
    private var startedAt: Double = 0
    private var startedPosition: Double = 0
    private let clock: () -> Double
    private let makeDevice: () throws -> any MIDIPlaybackDevice

    public init(clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime },
                makeDevice: @escaping () throws -> any MIDIPlaybackDevice = { try SystemMIDIDevice() }) {
        self.clock = clock
        self.makeDevice = makeDevice
    }
    isolated deinit { timer?.cancel(); device?.silence(); device?.close() }

    public func load(_ value: MIDIPresentation) {
        clear()
        guard Self.isValid(value) else { onFailure?(.invalidPresentation); return }
        presentation = value
        onChange?(0, false)
    }
    public func play() {
        guard let presentation, !isPlaying else { return }
        if position >= presentation.durationSeconds { position = 0 }
        do {
            if device == nil { device = try makeDevice() }
            try restoreState(at: position, events: presentation.events)
            startedAt = clock()
            startedPosition = position
            isPlaying = true
            onChange?(position, true)
            update()
            timer = Task { @MainActor [weak self] in
                guard self?.isPlaying == true else { return }
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(8)) }
                    catch { return }
                    guard let self, self.isPlaying else { return }
                    self.update()
                }
            }
        } catch {
            suspend()
            onFailure?(error as? MIDIPlaybackFailure ?? .audioUnavailable)
        }
    }
    public func pause() {
        if isPlaying { position = currentPosition() }
        isPlaying = false
        timer?.cancel()
        timer = nil
        device?.silence()
        onChange?(position, false)
    }
    public func seek(to seconds: Double) {
        guard let presentation, seconds.isFinite else { return }
        let resume = isPlaying
        pause()
        position = min(max(0, seconds), presentation.durationSeconds)
        onChange?(position, false)
        if resume { play() }
    }
    /// Host disappearance closes audio resources while retaining only validated data.
    public func suspend() {
        pause()
        device?.close()
        device = nil
    }
    public func clear() {
        suspend()
        presentation = nil
        position = 0
        eventIndex = 0
    }

    /// Public to permit deterministic lifecycle/timing tests with an injected clock/device.
    public func update() {
        guard isPlaying, let presentation, let device else { return }
        position = currentPosition()
        do {
            while eventIndex < presentation.events.count && presentation.events[eventIndex].timeSeconds <= position {
                let event = presentation.events[eventIndex]
                try device.send(status: event.status, data1: event.data1, data2: event.data2)
                eventIndex += 1
            }
            if position >= presentation.durationSeconds { pause() }
            else { onChange?(position, true) }
        } catch {
            suspend()
            onFailure?(.audioUnavailable)
        }
    }
    private func currentPosition() -> Double {
        min(presentation?.durationSeconds ?? 0, startedPosition + max(0, clock() - startedAt))
    }
    private func restoreState(at seconds: Double, events: [MIDIChannelEvent]) throws {
        guard let device else { return }
        device.silence()
        for channel in UInt8(0)..<16 {
            try device.send(status: 0xb0 | channel, data1: 121, data2: 0) // Reset controllers.
            try device.send(status: 0xc0 | channel, data1: 0, data2: 0)
            try device.send(status: 0xe0 | channel, data1: 0, data2: 64)
        }
        eventIndex = 0
        while eventIndex < events.count && events[eventIndex].timeSeconds < seconds {
            let event = events[eventIndex]
            // Notes are not replayed on seek; controller/program/pitch state is restored.
            if event.status & 0xf0 >= 0xb0 {
                try device.send(status: event.status, data1: event.data1, data2: event.data2)
            }
            eventIndex += 1
        }
    }
    private static func isValid(_ value: MIDIPresentation) -> Bool {
        guard value.format <= 1, (1...128).contains(value.trackCount), value.format != 0 || value.trackCount == 1,
              value.ticksPerQuarter > 0, value.ticksPerQuarter < 0x8000,
              value.durationSeconds.isFinite, (0...3600).contains(value.durationSeconds), value.events.count <= 20_000 else { return false }
        var lastTime: Double = 0
        for event in value.events {
            guard event.timeSeconds.isFinite, event.timeSeconds >= lastTime, event.timeSeconds <= value.durationSeconds,
                  (0x80...0xef).contains(event.status), event.data1 < 128, event.data2 < 128 else { return false }
            lastTime = event.timeSeconds
        }
        return true
    }
}

/// Apple's DLS Music Device owns its default bank. Playback availability follows
/// audio-unit return codes; querying its bank URL is optional diagnostic metadata.
/// No document-provided bank URL is accepted or system bank file opened by this app.
@MainActor
public final class SystemMIDIDevice: MIDIPlaybackDevice {
    private var graph: AUGraph?
    private var instrument: AudioUnit?
    public private(set) var soundBankURL: URL?

    public init() throws {
        var graph: AUGraph?
        guard NewAUGraph(&graph) == noErr, let graph else { throw MIDIPlaybackFailure.audioUnavailable }
        self.graph = graph
        do {
            var instrumentNode = AUNode()
            var outputNode = AUNode()
            var instrumentDescription = AudioComponentDescription(componentType: kAudioUnitType_MusicDevice,
                componentSubType: kAudioUnitSubType_DLSSynth, componentManufacturer: kAudioUnitManufacturer_Apple,
                componentFlags: 0, componentFlagsMask: 0)
            var outputDescription = AudioComponentDescription(componentType: kAudioUnitType_Output,
                componentSubType: kAudioUnitSubType_DefaultOutput, componentManufacturer: kAudioUnitManufacturer_Apple,
                componentFlags: 0, componentFlagsMask: 0)
            guard AUGraphAddNode(graph, &instrumentDescription, &instrumentNode) == noErr,
                  AUGraphAddNode(graph, &outputDescription, &outputNode) == noErr,
                  AUGraphConnectNodeInput(graph, instrumentNode, 0, outputNode, 0) == noErr,
                  AUGraphOpen(graph) == noErr,
                  AUGraphNodeInfo(graph, instrumentNode, nil, &instrument) == noErr,
                  instrument != nil, AUGraphInitialize(graph) == noErr else { throw MIDIPlaybackFailure.audioUnavailable }
            if let instrument { soundBankURL = MIDISoundBankQuery.loadedURL(in: instrument) }
            guard AUGraphStart(graph) == noErr else { throw MIDIPlaybackFailure.audioUnavailable }
        } catch { close(); throw error }
    }
    isolated deinit { close() }
    public func send(status: UInt8, data1: UInt8, data2: UInt8) throws {
        guard let instrument, MusicDeviceMIDIEvent(instrument, UInt32(status), UInt32(data1), UInt32(data2), 0) == noErr else {
            throw MIDIPlaybackFailure.audioUnavailable
        }
    }
    public func silence() {
        guard let instrument else { return }
        for channel in UInt32(0)..<16 {
            MusicDeviceMIDIEvent(instrument, 0xb0 | channel, 120, 0, 0)
            MusicDeviceMIDIEvent(instrument, 0xb0 | channel, 123, 0, 0)
        }
    }
    public func close() {
        guard let graph else { return }
        silence()
        AUGraphStop(graph)
        AUGraphUninitialize(graph)
        AUGraphClose(graph)
        DisposeAUGraph(graph)
        self.graph = nil
        instrument = nil
        soundBankURL = nil
    }
}

/// A supported read-only DLS property, without any sandbox file-access requirement.
@MainActor
enum MIDISoundBankQuery {
    static func loadedURL(in instrument: AudioUnit) -> URL? {
        loadedURL(getInfo: { size in
            AudioUnitGetPropertyInfo(instrument, kMusicDeviceProperty_SoundBankURL,
                                     kAudioUnitScope_Global, 0, &size, nil)
        }, getValue: { value, size in
            AudioUnitGetProperty(instrument, kMusicDeviceProperty_SoundBankURL,
                                 kAudioUnitScope_Global, 0, &value, &size)
        })
    }

    static func loadedURL(getInfo: (inout UInt32) -> OSStatus,
                          getValue: (inout Unmanaged<CFURL>?, inout UInt32) -> OSStatus) -> URL? {
        let expectedSize = UInt32(MemoryLayout<Unmanaged<CFURL>?>.size)
        var size: UInt32 = 0
        guard getInfo(&size) == noErr, size == expectedSize else { return nil }
        var value: Unmanaged<CFURL>?
        let status = getValue(&value, &size)
        guard let value else { return nil }
        // AudioUnitGetProperty duplicates CF objects despite its Get name. Consume
        // the +1 result even if its returned size/status cannot be used as metadata.
        let url = value.takeRetainedValue() as URL
        guard status == noErr, size == expectedSize, url.isFileURL else { return nil }
        return url
    }
}
