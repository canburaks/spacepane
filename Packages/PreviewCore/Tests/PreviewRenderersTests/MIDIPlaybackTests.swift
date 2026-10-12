import Foundation
import Testing
import PreviewContracts
import PreviewRenderers

@MainActor private final class TestMIDIDevice: MIDIPlaybackDevice {
    var sent: [(UInt8, UInt8, UInt8)] = []
    var silenceCount = 0
    var closeCount = 0
    func send(status: UInt8, data1: UInt8, data2: UInt8) throws { sent.append((status, data1, data2)) }
    func silence() { silenceCount += 1 }
    func close() { closeCount += 1 }
}

@MainActor private final class WeakMIDIPlayerReference {
    weak var value: NativeMIDIPlayback?
    init(_ value: NativeMIDIPlayback?) { self.value = value }
}

@MainActor @Test func MIDIPlaybackRequiresPlayAndRestoresStateWithoutReplayingNotesOnScrub() throws {
    var now: Double = 10
    var creations = 0
    let device = TestMIDIDevice()
    let player = NativeMIDIPlayback(clock: { now }, makeDevice: { creations += 1; return device })
    let presentation = MIDIPresentation(format: 0, trackCount: 1, ticksPerQuarter: 480, durationSeconds: 2, events: [
        MIDIChannelEvent(timeSeconds: 0, status: 0xc0, data1: 40, data2: 0),
        MIDIChannelEvent(timeSeconds: 0.25, status: 0x90, data1: 60, data2: 100),
        MIDIChannelEvent(timeSeconds: 1, status: 0x80, data1: 60, data2: 0)
    ])
    player.load(presentation)
    #expect(creations == 0)
    #expect(!player.isPlaying)
    player.play()
    #expect(creations == 1)
    #expect(player.isPlaying)
    now = 10.5; player.update()
    #expect(player.position == 0.5)
    #expect(device.sent.contains { $0.0 == 0x90 && $0.1 == 60 })
    player.pause()
    #expect(!player.isPlaying)
    #expect(device.silenceCount >= 2)
    device.sent = []
    player.seek(to: 0.75)
    player.play()
    #expect(device.sent.contains { $0.0 == 0xc0 && $0.1 == 40 })
    #expect(!device.sent.contains { $0.0 & 0xf0 == 0x90 })
    player.clear()
    #expect(device.closeCount == 1)
    #expect(!player.isPlaying)
}

@MainActor @Test func MIDIReplacementAndDeallocationCloseDevicesAndStopTimers() {
    let device = TestMIDIDevice()
    var player: NativeMIDIPlayback? = NativeMIDIPlayback(makeDevice: { device })
    let value = MIDIPresentation(format: 0, trackCount: 1, ticksPerQuarter: 96, durationSeconds: 10, events: [])
    player?.load(value); player?.play()
    player?.load(value)
    #expect(device.closeCount == 1)
    #expect(player?.isPlaying == false)
    player?.play()
    let weakPlayer = WeakMIDIPlayerReference(player)
    player = nil
    #expect(weakPlayer.value == nil)
    #expect(device.closeCount == 2)
}

@MainActor @Test func MIDIPlaybackRejectsUnsafeDirectlyConstructedEvents() {
    var creations = 0
    var failure: MIDIPlaybackFailure?
    let player = NativeMIDIPlayback(makeDevice: { creations += 1; return TestMIDIDevice() })
    player.onFailure = { failure = $0 }
    player.load(MIDIPresentation(format: 0, trackCount: 1, ticksPerQuarter: 96, durationSeconds: 1, events: [
        MIDIChannelEvent(timeSeconds: .nan, status: 0xf0, data1: 255, data2: 0)
    ]))
    player.play()
    #expect(failure == .invalidPresentation)
    #expect(creations == 0)
}

@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["PREV_VALIDATE_AUDIO"] == "1"))
func MIDISystemSoundBankAndAudioGraphLifecycleSmoke() throws {
    let device = try SystemMIDIDevice()
    // DLS may not expose optional bank metadata; actual initialization/start must succeed.
    if let bank = device.soundBankURL { #expect(bank.isFileURL) }
    device.silence()
    device.close()
    #expect(device.soundBankURL == nil)
    device.close() // Teardown is idempotent.
}
