import Foundation
import PreviewContracts

typealias GeoPosition = DataPlotCoding.Position

/// Running geographic statistics of the valid positions of one document: count, bounding box and
/// the positions rejected for lying outside longitude ±180 / latitude ±90. Out-of-range values
/// are counted and excluded, never clamped, so a projected-coordinate file cannot be mistaken for
/// a geographic one.
struct GeoBounds {
    private(set) var west = Double.infinity
    private(set) var south = Double.infinity
    private(set) var east = -Double.infinity
    private(set) var north = -Double.infinity
    private(set) var positionCount = 0
    private(set) var invalidCount = 0

    var isEmpty: Bool { positionCount == 0 }

    /// Records a position; returns whether it was valid.
    @discardableResult
    mutating func add(longitude: Double, latitude: Double) -> Bool {
        guard longitude.isFinite, latitude.isFinite, (-180.0...180.0).contains(longitude),
              (-90.0...90.0).contains(latitude) else {
            invalidCount += 1
            return false
        }
        positionCount += 1
        west = min(west, longitude)
        east = max(east, longitude)
        south = min(south, latitude)
        north = max(north, latitude)
        return true
    }

    var summary: SummaryValue? {
        guard !isEmpty else { return nil }
        func text(_ value: Double) -> SummaryValue { .string(String(format: "%.6f", value)) }
        return .object([("west", text(west)), ("south", text(south)), ("east", text(east)), ("north", text(north))])
    }
}

/// The geometry drawn by the Plot view: open or closed paths and isolated points, kept in memory
/// within a hard limit and decimated to `DataPlotCoding.maximumPositions` when written.
struct GeoPlot {
    /// Positions retained while scanning; further ones still count in the statistics.
    static let retainedLimit = 250_000
    static let maximumPaths = 500

    private(set) var paths: [[GeoPosition]] = []
    private(set) var points: [GeoPosition] = []
    private var retained = 0

    var isEmpty: Bool { paths.isEmpty && points.isEmpty }

    mutating func addPath(_ path: [GeoPosition]) {
        guard path.count >= 2, paths.count < Self.maximumPaths, retained + path.count <= Self.retainedLimit else { return }
        retained += path.count
        paths.append(path)
    }

    mutating func addPoint(_ point: GeoPosition) {
        guard retained < Self.retainedLimit else { return }
        retained += 1
        points.append(point)
    }

    /// The `plot` member: positions coded in chunks, uniformly thinned (keeping every path's
    /// endpoints) when the document holds more than the drawing limit.
    var summary: SummaryValue? {
        guard !isEmpty else { return nil }
        let total = paths.reduce(points.count) { $0 + $1.count }
        let limit = DataPlotCoding.maximumPositions
        let ratio = total > limit ? Double(limit) / Double(total) : 1
        let keptPoints = Self.thinned(points, keeping: max(points.isEmpty ? 0 : 1, Int((Double(points.count) * ratio).rounded(.up))))
        let keptPaths = paths.map { Self.thinned($0, keeping: max(2, Int((Double($0.count) * ratio).rounded(.up)))) }
        var members: [(String, SummaryValue)] = []
        if !keptPaths.isEmpty {
            members.append((DataSummaryKeys.paths, .array(keptPaths.map { path in
                .array(Self.chunks(path).map { .string($0) })
            })))
        }
        if !keptPoints.isEmpty {
            members.append((DataSummaryKeys.points, .array(Self.chunks(keptPoints).map { .string($0) })))
        }
        if ratio < 1 || paths.count >= Self.maximumPaths { members.append((DataSummaryKeys.simplified, .boolean(true))) }
        return .object(members)
    }

    private static func chunks(_ positions: [GeoPosition]) -> [String] {
        stride(from: 0, to: positions.count, by: DataPlotCoding.maximumPositionsPerChunk).map {
            DataPlotCoding.encode(positions[$0..<min(positions.count, $0 + DataPlotCoding.maximumPositionsPerChunk)])
        }
    }

    /// `count` positions at even spacing through `positions`, including the first and the last.
    static func thinned(_ positions: [GeoPosition], keeping count: Int) -> [GeoPosition] {
        guard count < positions.count else { return positions }
        guard count > 1 else { return count == 1 ? [positions[0]] : [] }
        return (0..<count).map { positions[Int((Double($0) * Double(positions.count - 1) / Double(count - 1)).rounded())] }
    }
}

/// Great-circle distance on a sphere of the IUGG mean Earth radius.
enum GeoDistance {
    static let earthRadiusMeters = 6_371_008.8

    static func haversine(_ first: GeoPosition, _ second: GeoPosition) -> Double {
        let toRadians = Double.pi / 180
        let latitudeA = first.latitude * toRadians
        let latitudeB = second.latitude * toRadians
        let deltaLatitude = latitudeB - latitudeA
        let deltaLongitude = (second.longitude - first.longitude) * toRadians
        let a = sin(deltaLatitude / 2) * sin(deltaLatitude / 2)
            + cos(latitudeA) * cos(latitudeB) * sin(deltaLongitude / 2) * sin(deltaLongitude / 2)
        return 2 * earthRadiusMeters * asin(min(1, a.squareRoot()))
    }
}

/// Elevation and time ranges gathered while scanning.
struct GeoRanges {
    private(set) var minimumElevation = Double.infinity
    private(set) var maximumElevation = -Double.infinity
    private(set) var earliest = Double.infinity
    private(set) var latest = -Double.infinity

    mutating func addElevation(_ meters: Double) {
        guard meters.isFinite, abs(meters) < 100_000 else { return }
        minimumElevation = min(minimumElevation, meters)
        maximumElevation = max(maximumElevation, meters)
    }

    mutating func addTime(_ text: String) {
        guard let seconds = GeoTime.epochSeconds(text) else { return }
        earliest = min(earliest, seconds)
        latest = max(latest, seconds)
    }

    /// Members shared by GPX and KML summaries; absent facts are omitted.
    func members(distanceMeters: Double?) -> [(String, SummaryValue)] {
        var members: [(String, SummaryValue)] = []
        if let distanceMeters, distanceMeters > 0 { members.append(("totalDistanceMeters", .integer(Int(distanceMeters.rounded())))) }
        if minimumElevation <= maximumElevation {
            members.append(("elevationMinMeters", .integer(Int(minimumElevation.rounded()))))
            members.append(("elevationMaxMeters", .integer(Int(maximumElevation.rounded()))))
        }
        if earliest <= latest {
            members.append(("timeStart", .string(GeoTime.format(earliest))))
            members.append(("timeEnd", .string(GeoTime.format(latest))))
            members.append(("durationSeconds", .integer(Int((latest - earliest).rounded()))))
        }
        return members
    }
}

/// ISO 8601 instants without Foundation formatters, which are slow for tens of thousands of track
/// points. Supports `YYYY-MM-DD` and `YYYY-MM-DDThh:mm:ss[.fraction]` with `Z` or a numeric offset.
enum GeoTime {
    static func epochSeconds(_ text: String) -> Double? {
        let bytes = Array(text.utf8)
        func number(_ start: Int, _ count: Int) -> Int? {
            guard start + count <= bytes.count else { return nil }
            var value = 0
            for byte in bytes[start..<(start + count)] {
                guard (0x30...0x39).contains(byte) else { return nil }
                value = value * 10 + Int(byte - 0x30)
            }
            return value
        }
        guard bytes.count >= 10, bytes[4] == 0x2D, bytes[7] == 0x2D,
              let year = number(0, 4), let month = number(5, 2), let day = number(8, 2),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        var seconds = Double(daysFromCivil(year: year, month: month, day: day)) * 86_400
        guard bytes.count > 10 else { return seconds }
        guard bytes[10] == 0x54 || bytes[10] == 0x20, bytes.count >= 19, bytes[13] == 0x3A, bytes[16] == 0x3A,
              let hour = number(11, 2), let minute = number(14, 2), let second = number(17, 2),
              hour < 24, minute < 60, second < 61 else { return nil }
        seconds += Double(hour * 3_600 + minute * 60 + second)
        var index = 19
        if index < bytes.count, bytes[index] == 0x2E {
            index += 1
            var scale = 0.1
            while index < bytes.count, (0x30...0x39).contains(bytes[index]) {
                seconds += Double(bytes[index] - 0x30) * scale
                scale /= 10
                index += 1
            }
        }
        guard index < bytes.count else { return seconds }
        switch bytes[index] {
        case 0x5A where index == bytes.count - 1:
            return seconds
        case 0x2B, 0x2D:
            let sign: Double = bytes[index] == 0x2D ? -1 : 1
            guard let offsetHour = number(index + 1, 2) else { return nil }
            var offsetMinute = 0
            var end = index + 3
            if end < bytes.count, bytes[end] == 0x3A { end += 1 }
            if end < bytes.count {
                guard let minutes = number(end, 2) else { return nil }
                offsetMinute = minutes
                end += 2
            }
            guard end == bytes.count, offsetHour < 24, offsetMinute < 60 else { return nil }
            return seconds - sign * Double(offsetHour * 3_600 + offsetMinute * 60)
        default:
            return nil
        }
    }

    /// `YYYY-MM-DDThh:mm:ssZ` in UTC.
    static func format(_ epochSeconds: Double) -> String {
        let whole = Int(epochSeconds.rounded(.down))
        let days = Int((Double(whole) / 86_400).rounded(.down))
        let remainder = whole - days * 86_400
        let (year, month, day) = civilFromDays(days)
        return String(format: "%04d-%02d-%02dT%02d:%02d:%02dZ", year, month, day,
                      remainder / 3_600, remainder % 3_600 / 60, remainder % 60)
    }

    /// Days since 1970-01-01 of a proleptic Gregorian date (Hinnant's algorithm).
    static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    static func civilFromDays(_ days: Int) -> (year: Int, month: Int, day: Int) {
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let shifted = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * shifted + 2) / 5 + 1
        let month = shifted < 10 ? shifted + 3 : shifted - 9
        return (yearOfEra + era * 400 + (month <= 2 ? 1 : 0), month, day)
    }
}

/// Counts of a closed set of geometry names, written in a fixed order with zero counts omitted.
struct GeoTypeCounts {
    private let order: [String]
    private var counts: [String: Int] = [:]

    init(order: [String]) { self.order = order }

    mutating func add(_ name: String) { counts[name, default: 0] += 1 }

    var isEmpty: Bool { counts.isEmpty }

    var summary: SummaryValue {
        .object(order.compactMap { name in counts[name].map { (name, SummaryValue.integer($0)) } })
    }
}
