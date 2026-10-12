import Foundation
import Testing
import PreviewContracts
import PreviewFormats

private func midiInteger(_ value: Int, bytes: Int) -> Data { Data((0..<bytes).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }) }
private func midiFile(format: Int = 0, tracks: [Data], division: Int = 480) -> Data {
    var data = Data("MThd".utf8) + midiInteger(6, bytes: 4) + midiInteger(format, bytes: 2)
        + midiInteger(tracks.count, bytes: 2) + midiInteger(division, bytes: 2)
    for track in tracks { data += Data("MTrk".utf8) + midiInteger(track.count, bytes: 4) + track }
    return data
}

@Test func MIDIFormatZeroPreservesProgramChannelAndTimingWhileDiscardingSecretsAndSysEx() throws {
    let secret = Data("password=synthetic-secret".utf8)
    var track = Data([0, 0xff, 0x51, 3, 7, 0xa1, 0x20, 0, 0xc9, 40, 0, 0xff, 3, UInt8(secret.count)]) + secret
    track += Data([0, 0xf0, 4, 0x7d, 1, 2, 0xf7, 0, 0x99, 60, 100, 0x83, 0x60, 0x89, 60, 0, 0, 0xff, 0x2f, 0])
    let parsed = try MIDIAdapter().parse(FileBytes(data: midiFile(tracks: [track])), context: RequestContext(budget: .standard))
    let midi = try #require(parsed.midi)
    #expect(midi.format == 0)
    #expect(midi.durationSeconds == 0.5)
    #expect(midi.events.map(\.status) == [0xc9, 0x99, 0x89])
    #expect(midi.events.last?.timeSeconds == 0.5)
    #expect(!parsed.text.contains("synthetic-secret"))
    #expect(!parsed.text.contains("password"))
}

@Test func MIDIFormatOneAppliesTempoChangesAcrossTracks() throws {
    let tempo = Data([0, 0xff, 0x51, 3, 7, 0xa1, 0x20, 0x83, 0x60, 0xff, 0x51, 3, 0x0f, 0x42, 0x40, 0x83, 0x60, 0xff, 0x2f, 0])
    let notes = Data([0, 0x90, 60, 100, 0x87, 0x40, 0x80, 60, 0, 0, 0xff, 0x2f, 0])
    let parsed = try MIDIAdapter().parse(FileBytes(data: midiFile(format: 1, tracks: [tempo, notes])), context: RequestContext(budget: .standard))
    #expect(parsed.midi?.durationSeconds == 1.5)
    #expect(parsed.midi?.events.last?.timeSeconds == 1.5)
}

@Test func MIDIRejectsFormatTwoSMPTEBadRunningStatusAndOversizedEvents() throws {
    let end = Data([0, 0xff, 0x2f, 0])
    #expect(throws: PreviewFailure.unsupportedFormat) { try MIDIAdapter().parse(FileBytes(data: midiFile(format: 2, tracks: [end])), context: RequestContext(budget: .standard)) }
    #expect(throws: PreviewFailure.unsupportedFormat) { try MIDIAdapter().parse(FileBytes(data: midiFile(tracks: [end], division: 0xe728)), context: RequestContext(budget: .standard)) }
    #expect(throws: PreviewFailure.malformedDocument) { try MIDIAdapter().parse(FileBytes(data: midiFile(tracks: [Data([0, 60, 100]) + end])), context: RequestContext(budget: .standard)) }
    #expect(throws: PreviewFailure.malformedDocument) { try MIDIAdapter().parse(FileBytes(data: midiFile(tracks: [Data([0, 0x90, 128, 100]) + end])), context: RequestContext(budget: .standard)) }
    let many = Data(repeating: 0, count: 0) + (0..<5).reduce(into: Data()) { data, _ in data.append(contentsOf: [0, 0xc0, 1]) } + end
    #expect(throws: PreviewFailure.tooManyNodes) { try MIDIAdapter().parse(FileBytes(data: midiFile(tracks: [many])), context: RequestContext(budget: PreviewBudget(maxJSONNodes: 4))) }
}

@Test func MIDIValidatesEndOfTrackAndRunningStatus() throws {
    let track = Data([0, 0x90, 60, 100, 0, 61, 80, 0x83, 0x60, 0x80, 60, 0, 0, 61, 0, 0, 0xff, 0x2f, 0])
    #expect(try MIDIAdapter().parse(FileBytes(data: midiFile(tracks: [track])), context: RequestContext(budget: .standard)).midi?.events.count == 4)
    #expect(throws: PreviewFailure.malformedDocument) { try MIDIAdapter().parse(FileBytes(data: midiFile(tracks: [track.dropLast(4)])), context: RequestContext(budget: .standard)) }
}
