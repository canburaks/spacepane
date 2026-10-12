import Foundation

public extension FormatID {
    static let sqlite = FormatID(rawValue: "database.sqlite")
    static let zip = FormatID(rawValue: "archive.zip")
    static let tar = FormatID(rawValue: "archive.tar")
    static let gzip = FormatID(rawValue: "archive.gzip")
    static let xip = FormatID(rawValue: "archive.xip")
    static let folder = FormatID(rawValue: "container.folder")
    static let midi = FormatID(rawValue: "audio.midi")
}

/// Binary formats receive the same bounded, read-only bytes as source formats.
public protocol BinaryFormatAdapter: Sendable {
    func parse(_ input: FileBytes, context: RequestContext) throws -> ParsedTextDocument
}

/// The folder adapter enumerates metadata only; other adapters consume bounded bytes.
public protocol URLFormatAdapter: Sendable {
    func parse(url: URL, context: RequestContext) throws -> ParsedTextDocument
}

/// Each source owns its read-only handle and accounts cumulative reads per request.
public protocol PreviewByteSource: Sendable {
    var byteCount: Int64 { get }
    func read(offset: Int64, count: Int, context: RequestContext) throws -> Data
}

public protocol RandomAccessFormatAdapter: Sendable {
    func parse(_ source: any PreviewByteSource, context: RequestContext) throws -> ParsedTextDocument
}

/// Only validated channel messages survive parsing. Text, SysEx and file bytes do not.
public struct MIDIChannelEvent: Equatable, Sendable {
    public let timeSeconds: Double
    public let status: UInt8
    public let data1: UInt8
    public let data2: UInt8
    public init(timeSeconds: Double, status: UInt8, data1: UInt8, data2: UInt8) {
        self.timeSeconds = timeSeconds
        self.status = status
        self.data1 = data1
        self.data2 = data2
    }
}

public struct MIDIPresentation: Equatable, Sendable {
    public let format: UInt16
    public let trackCount: Int
    public let ticksPerQuarter: UInt16
    public let durationSeconds: Double
    public let events: [MIDIChannelEvent]
    public init(format: UInt16, trackCount: Int, ticksPerQuarter: UInt16,
                durationSeconds: Double, events: [MIDIChannelEvent]) {
        self.format = format
        self.trackCount = trackCount
        self.ticksPerQuarter = ticksPerQuarter
        self.durationSeconds = durationSeconds
        self.events = events
    }
}
