import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

@Suite("Source grid facts")
struct PresentationGridFactsTests {
    @Test func delimitedCountsExcludeTheHeaderAndDoNotCountQuotedNewlinesAsRows() throws {
        let text = "a,b\n1,\"first\nsecond\"\n2,x,y\n"
        let document = try DelimitedTextAdapter(dialect: .comma).parse(
            DecodedText(text: text, encoding: .utf8, byteCount: text.utf8.count), context: DataTest.context())
        #expect(document.facts == PresentationFacts([.grid(rows: 2, columns: 3, rowsAreLowerBound: false)]))
        #expect(document.text.utf8.elementsEqual(text.utf8))
        let empty = try DelimitedTextAdapter(dialect: .comma).parse(
            DecodedText(text: "a,b\n", encoding: .utf8, byteCount: 4), context: DataTest.context())
        #expect(empty.facts == PresentationFacts([.grid(rows: 0, columns: 2, rowsAreLowerBound: false)]))
    }

    @Test func arrowCountsUseBatchRowsAndSourceColumnsRatherThanSchemaTableRows() throws {
        for bytes in [DataFixtures.arrowFile, DataFixtures.arrowStream] {
            let document = try DataTest.parse(ArrowAdapter(), bytes)
            #expect(document.facts == PresentationFacts([.grid(rows: 7, columns: 5, rowsAreLowerBound: false)]))
        }
        let source = DataRecordingSource(DataFixtures.arrowManyBatches)
        let document = try ArrowAdapter().parse(source, context: DataTest.context())
        #expect(document.facts == PresentationFacts([.grid(rows: 64, columns: 5, rowsAreLowerBound: true)]))
        #expect(source.reads.count == 67, "Facts must not add source reads or scan column buffers")
    }

    @Test func arrowNegativeAndOverflowingBatchLengthsAreTypedFailures() throws {
        let stream = DataFixtures.arrowStream
        func length(at offset: Int) -> Int {
            stream[(offset + 4)..<(offset + 8)].enumerated().reduce(0) { $0 | Int($1.element) << ($1.offset * 8) }
        }
        let batchStart = 8 + length(at: 0)
        let metadataStart = batchStart + 8
        let metadataEnd = metadataStart + length(at: batchStart)
        let message = try FlatBuffer(Array(stream[metadataStart..<metadataEnd])).rootTable()
        let header = try #require(try message.table(2))
        let rowOffset = try #require(try header.field(0))
        for count in [Int64(-1), Int64.max] {
            var bytes = stream
            bytes.replaceSubrange((metadataStart + rowOffset)..<(metadataStart + rowOffset + 8),
                                  with: DataTest.little(UInt64(bitPattern: count), width: 8))
            #expect(throws: PreviewFailure.malformedDocument) { try DataTest.parse(ArrowAdapter(), bytes) }
        }
    }

    @Test func parquetFactsUseFooterTotalsRatherThanTheFlattenedSchemaTable() throws {
        let document = try DataTest.parse(ParquetAdapter(), DataFixtures.parquet)
        #expect(document.facts == PresentationFacts([.grid(rows: 3, columns: 4, rowsAreLowerBound: false)]))
    }

    @Test func avroAndNumpyFactsAreIndependentOfSampleAndTechnicalIndexColumns() throws {
        let avro = try DataTest.parse(AvroAdapter(), DataFixtures.avro)
        #expect(avro.facts == PresentationFacts([.grid(rows: 3, columns: 8, rowsAreLowerBound: false)]))
        let numpy = try DataTest.parse(NumPyAdapter(), DataFixtures.numpy)
        #expect(numpy.facts == PresentationFacts([.grid(rows: 3, columns: 4, rowsAreLowerBound: false)]))
    }
}
