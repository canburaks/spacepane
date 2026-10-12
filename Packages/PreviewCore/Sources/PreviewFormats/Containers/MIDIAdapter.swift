import Foundation
import PreviewContracts

/// Standard MIDI File formats 0/1 with PPQN timing. No bytes are delegated to a native file decoder.
public struct MIDIAdapter: BinaryFormatAdapter {
    public init() {}
    public func parse(_ input: FileBytes, context: RequestContext) throws -> ParsedTextDocument {
        try ContainerLimits(context: context).validateInput(input.data)
        var cursor = BinaryCursor(input.data)
        guard try cursor.integer(4) == 0x4d546864, try cursor.integer(4) == 6 else { throw PreviewFailure.malformedDocument }
        let format = UInt16(try cursor.integer(2))
        let tracks = try boundedInt(cursor.integer(2))
        let division = UInt16(try cursor.integer(2))
        guard format <= 1, division & 0x8000 == 0 else { throw PreviewFailure.unsupportedFormat }
        guard division > 0, (1...128).contains(tracks), format != 0 || tracks == 1 else { throw PreviewFailure.malformedDocument }
        var events: [TickEvent] = []
        var tempos: [TempoEvent] = [TempoEvent(tick: 0, microseconds: 500_000, order: -1)]
        var totalEvents = 0
        var finalTick: UInt64 = 0
        for trackIndex in 0..<tracks {
            try context.checkpoint()
            guard try cursor.integer(4) == 0x4d54726b else { throw PreviewFailure.malformedDocument }
            let length = try boundedInt(cursor.integer(4))
            var track = BinaryCursor(Data(try cursor.read(length)))
            var runningStatus: UInt8?
            var tick: UInt64 = 0
            var ended = false
            while track.remaining > 0 {
                try context.checkpoint()
                totalEvents += 1
                guard totalEvents <= min(20_000, context.budget.maxJSONNodes) else { throw PreviewFailure.tooManyNodes }
                let delta = try variableLength(&track)
                let sum = tick.addingReportingOverflow(delta)
                guard !sum.overflow else { throw PreviewFailure.malformedDocument }
                tick = sum.partialValue
                let first = UInt8(try track.integer(1))
                let status: UInt8
                if first < 0x80 {
                    guard let runningStatus else { throw PreviewFailure.malformedDocument }
                    status = runningStatus
                    track.offset -= 1
                } else { status = first }
                if (0x80...0xef).contains(status) {
                    runningStatus = status
                    let firstData = UInt8(try track.integer(1))
                    let oneByte = status & 0xf0 == 0xc0 || status & 0xf0 == 0xd0
                    let secondData = oneByte ? 0 : UInt8(try track.integer(1))
                    guard firstData < 128, secondData < 128 else { throw PreviewFailure.malformedDocument }
                    events.append(TickEvent(tick: tick, status: status, data1: firstData, data2: secondData, order: totalEvents))
                } else if status == 0xff {
                    runningStatus = nil
                    let kind = try track.integer(1)
                    let size = try boundedInt(variableLength(&track))
                    let payload = try track.read(size)
                    if kind == 0x2f {
                        guard size == 0, track.remaining == 0 else { throw PreviewFailure.malformedDocument }
                        ended = true
                        break
                    }
                    if kind == 0x51 {
                        guard size == 3, format == 0 || trackIndex == 0 else { throw PreviewFailure.malformedDocument }
                        let microseconds = payload.reduce(0) { ($0 << 8) | Int($1) }
                        guard microseconds > 0 else { throw PreviewFailure.malformedDocument }
                        tempos.append(TempoEvent(tick: tick, microseconds: microseconds, order: totalEvents))
                    }
                    // All text, names, copyright messages, sequencer-specific and other metadata are discarded.
                } else if status == 0xf0 || status == 0xf7 {
                    runningStatus = nil
                    _ = try track.read(try boundedInt(variableLength(&track)))
                    // SysEx is never delivered to an instrument or retained in presentation.
                } else { throw PreviewFailure.malformedDocument }
            }
            guard ended else { throw PreviewFailure.malformedDocument }
            finalTick = max(finalTick, tick)
        }
        guard cursor.remaining == 0 else { throw PreviewFailure.malformedDocument }
        events.sort { $0.tick == $1.tick ? $0.order < $1.order : $0.tick < $1.tick }
        tempos.sort { $0.tick == $1.tick ? $0.order < $1.order : $0.tick < $1.tick }
        var tempoIndex = 0
        var tempo = 500_000
        var tempoTick: UInt64 = 0
        var tempoSeconds: Double = 0
        func seconds(at tick: UInt64) throws -> Double {
            while tempoIndex < tempos.count && tempos[tempoIndex].tick <= tick {
                let next = tempos[tempoIndex]
                tempoSeconds += Double(next.tick - tempoTick) * Double(tempo) / Double(division) / 1_000_000
                tempoTick = next.tick
                tempo = next.microseconds
                tempoIndex += 1
            }
            let time = tempoSeconds + Double(tick - tempoTick) * Double(tempo) / Double(division) / 1_000_000
            guard time.isFinite, time <= 3600 else { throw PreviewFailure.inputTooLarge }
            return time
        }
        var channelEvents: [MIDIChannelEvent] = []
        for event in events {
            try context.checkpoint()
            channelEvents.append(MIDIChannelEvent(timeSeconds: try seconds(at: event.tick), status: event.status,
                                                  data1: event.data1, data2: event.data2))
        }
        let duration = try seconds(at: finalTick)
        let midi = MIDIPresentation(format: format, trackCount: tracks, ticksPerQuarter: division,
                                    durationSeconds: duration, events: channelEvents)
        var writer = SummaryWriter(context: context)
        let document = try writer.document(.object([
            ("MIDIFormat", .integer(Int(format))), ("tracks", .integer(tracks)),
            ("ticksPerQuarter", .integer(Int(division))), ("channelEvents", .integer(channelEvents.count)),
            ("textMetadataRetained", .boolean(false)), ("systemExclusiveRetained", .boolean(false)),
            ("autoplay", .boolean(false))
        ]))
        return ParsedTextDocument(text: document.text, usesStructuredPrivacy: true, syntax: .json, midi: midi,
                                  origin: document.origin)
    }

    private func variableLength(_ cursor: inout BinaryCursor) throws -> UInt64 {
        var value: UInt64 = 0
        for _ in 0..<4 {
            let byte = try cursor.integer(1)
            value = (value << 7) | (byte & 0x7f)
            if byte & 0x80 == 0 { return value }
        }
        throw PreviewFailure.malformedDocument
    }
}

private struct TickEvent {
    let tick: UInt64
    let status: UInt8
    let data1: UInt8
    let data2: UInt8
    let order: Int
}
private struct TempoEvent {
    let tick: UInt64
    let microseconds: Int
    let order: Int
}
