import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Q52 bounded localized scalar facts", .serialized)
struct Q52FactsFormatterTests {
    private let english = Locale(identifier: "en_US")

    @Test func groupedFactsFlattenBeforeTheRegularAndCompactCaps() {
        let facts = PresentationFacts([
            .grid(rows: 12, columns: 7, rowsAreLowerBound: false),
            .records(3, .records), .lines(20), .size(1024)
        ])
        #expect(lines(facts) == ["Rows: 12", "Columns: 7", "Records: 3", "20 lines"])
        #expect(lines(facts, compact: true) == ["Rows: 12", "Columns: 7"])
        #expect(lines(.none).isEmpty)
    }

    @Test func lowerBoundsRemainExplicitForEveryListedCountAndSize() {
        let size = SafeListingFormatting.sizeText(1024, locale: english)
        let listing = PresentationFacts([.listing(files: 2, folders: 1, isLowerBound: true, listedBytes: 1024)])
        #expect(lines(listing) == ["Listed files: 2+", "Listed folders: 1+", "Listed size: " + size + "+"])
        #expect(lines(listing, compact: true) == ["Listed files: 2+", "Listed folders: 1+"])
        let grid = PresentationFacts([.grid(rows: 12, columns: 7, rowsAreLowerBound: true)])
        #expect(lines(grid) == ["Rows: 12+", "Columns: 7"])
    }

    @Test func recordKindsHaveTheirOwnMeaningAndNeverBorrowOneAnothersLabel() {
        let cases: [(PresentationFacts.RecordKind, String)] = [
            (.records, "Records: 2"), (.cues, "Cues: 2"), (.pages, "Pages: 2"),
            (.cells, "Cells: 2"), (.events, "Events: 2"), (.images, "Embedded images: 2")
        ]
        for (kind, expected) in cases {
            #expect(lines(.init([.records(2, kind)])) == [expected])
        }
        #expect(lines(.init([.nodes(4)])) == ["Nodes: 4"])
    }

    @Test func playbackTracksAndDurationAreSeparateFactsAtEitherDensity() {
        let facts = PresentationFacts([.playback(tracks: 2, seconds: 125), .size(1024)])
        #expect(Array(lines(facts).prefix(2)) == ["Tracks: 2", "Duration: 02:05"])
        #expect(lines(facts, compact: true) == ["Tracks: 2", "Duration: 02:05"])
    }

    @Test func durationRejectsValuesBeyondTheExistingMIDIHourLimitBeforeFormatting() {
        #expect(lines(.init([.playback(tracks: 2, seconds: 3600)])) == ["Tracks: 2", "Duration: 60:00"])
        for seconds in [3601.0, Double.greatestFiniteMagnitude] {
            #expect(lines(.init([.playback(tracks: 2, seconds: seconds)])) == ["Tracks: 2"])
        }
    }

    @Test func malformedNumbersAreOmittedWithoutInventedZeroOrNonfiniteText() {
        let invalid = PresentationFacts([
            .lines(-1), .size(-1), .shownSize(shown: -1, total: 2), .shownSize(shown: 2, total: 1),
            .grid(rows: -1, columns: -1, rowsAreLowerBound: false), .records(-1, .records), .nodes(-1),
            .listing(files: -1, folders: -1, isLowerBound: false, listedBytes: -1),
            .playback(tracks: -1, seconds: .infinity), .pixels(width: 0, height: -1),
            .geometry(faces: -1, bodies: -1, extentMillimetres: SIMD3<Double>(.nan, -1, .infinity), unit: .undeclared)
        ])
        #expect(lines(invalid).isEmpty)
        #expect(lines(invalid, compact: true).isEmpty)
    }

    @Test func geometryCapsDimensionsAndBodiesAreScalarFactsInPriorityOrder() {
        let facts = PresentationFacts([.geometry(faces: 100_000, bodies: 2,
            extentMillimetres: SIMD3<Double>(25.4, 50.8, 76.2), unit: .declared(.inch), facesAreLowerBound: true)])
        let symbol = GeometrySummaryUnits(.declared(.inch))?.lengthSymbol(locale: english) ?? ""
        #expect(!symbol.isEmpty)
        #expect(lines(facts) == ["Faces: 100,000+", "1 × 2 × 3 " + symbol, "Bodies: 2"])
        #expect(lines(facts, compact: true) == ["Faces: 100,000+", "1 × 2 × 3 " + symbol])
    }

    @Test func assumedAndUndeclaredUnitsNeverBecomeFileDeclaredMillimetres() {
        let extent = SIMD3<Double>(1, 2, 3)
        let unknown = PresentationFacts([.geometry(faces: 1, bodies: nil, extentMillimetres: extent, unit: .undeclared)])
        #expect(lines(unknown) == ["Faces: 1", "1 × 2 × 3 (unit not declared)"])
        let assumed = PresentationFacts([.geometry(faces: 1, bodies: nil, extentMillimetres: extent, unit: .assumedMillimetres)])
        let symbol = GeometrySummaryUnits(.assumedMillimetres)?.lengthSymbol(locale: english) ?? ""
        #expect(lines(assumed) == ["Faces: 1", "1 × 2 × 3 " + symbol + " (unit assumed)"])
    }

    @Test func extremeAndMalformedGeometryNeverEmitNonfiniteDimensions() {
        for extent in [SIMD3<Double>(.greatestFiniteMagnitude, 1, 2), SIMD3<Double>(.infinity, 1, 2)] {
            let result = lines(.init([.geometry(faces: 1, bodies: nil, extentMillimetres: extent,
                unit: .declared(.micrometre))]))
            #expect(result.first == "Faces: 1")
            #expect(!result.contains { $0.contains("∞") || $0.localizedCaseInsensitiveContains("inf") || $0.localizedCaseInsensitiveContains("nan") })
        }
    }

    @Test func pixelsAndCountsFollowThePresentationLocaleWhileEnglishLabelsStayEnglish() {
        for locale in [english, Locale(identifier: "de_DE"), Locale(identifier: "tr_TR")] {
            let width = 12_345.formatted(.number.locale(locale))
            let height = 23_456.formatted(.number.locale(locale))
            let facts = PresentationFacts([.pixels(width: 12_345, height: 23_456), .nodes(12_345)])
            #expect(lines(facts, locale: locale) == [width + " × " + height + " px", "Nodes: " + width])
        }
    }

    @Test func technicalEncodingNamesAreStableAndByteCountsFollowLocale() {
        let cases: [(TextEncoding, String)] = [
            (.utf8, "UTF-8"), (.utf16LittleEndian, "UTF-16 LE"),
            (.utf16BigEndian, "UTF-16 BE"), (.codePage437, "CP437")
        ]
        for (encoding, expected) in cases {
            #expect(lines(.init([.encoding(encoding)])) == [expected])
        }
        let size = SafeListingFormatting.sizeText(1024, locale: english)
        let total = SafeListingFormatting.sizeText(4096, locale: english)
        #expect(lines(.init([.size(1024), .shownSize(shown: 1024, total: 4096)]))
            == ["Size: " + size, "Read: " + size + " of " + total])
    }

    private func lines(_ facts: PresentationFacts, compact: Bool = false, locale: Locale? = nil) -> [String] {
        PresentationFactsFormatter.lines(for: facts, compact: compact, locale: locale ?? english, languagePreferences: ["en"])
    }
}
