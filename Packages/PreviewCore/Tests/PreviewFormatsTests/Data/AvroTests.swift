import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

/// An Avro writer independent of the reader under test.
enum AvroWriter {
    static func long(_ value: Int64) -> [UInt8] {
        var rest = UInt64(bitPattern: (value << 1) ^ (value >> 63))
        var out: [UInt8] = []
        repeat {
            var byte = UInt8(rest & 0x7F)
            rest >>= 7
            if rest != 0 { byte |= 0x80 }
            out.append(byte)
        } while rest != 0
        return out
    }
    static func string(_ text: String) -> [UInt8] { long(Int64(text.utf8.count)) + Array(text.utf8) }
    static let sync = [UInt8](0..<16)

    static func container(schema: String, codec: String = "null", blocks: [(count: Int, payload: [UInt8])]) -> Data {
        var out: [UInt8] = [0x4F, 0x62, 0x6A, 0x01]
        let metadata = [("avro.schema", Array(schema.utf8)), ("avro.codec", Array(codec.utf8))]
        out += long(Int64(metadata.count))
        for (key, value) in metadata { out += string(key) + long(Int64(value.count)) + value }
        out += long(0) + sync
        for block in blocks { out += long(Int64(block.count)) + long(Int64(block.payload.count)) + block.payload + sync }
        return Data(out)
    }

    static func deflate(_ bytes: [UInt8]) -> [UInt8] { DataTest.rawDeflate(bytes) }
}

private func schemaNode(_ json: String) throws -> AvroSchema {
    var reader = DataJSONReader(bytes: Array(json.utf8), context: DataTest.context())
    var tree: DataJSONValue?
    try reader.document { reader in
        var nodes = 10_000
        tree = try reader.value(depth: 1, nodes: &nodes)
    }
    return try AvroSchema.parse(try #require(tree), nodeAllowance: 10_000)
}

private func decode(_ schema: AvroSchema, _ bytes: [UInt8]) throws -> AvroValue {
    var decoder = AvroValueDecoder(block: bytes, schema: schema, context: DataTest.context(), workAllowance: 100_000)
    return try decoder.value(schema.root)
}

@Suite("Avro schema and binary decoding")
struct AvroDecoderTests {
    @Test func longsAreZigzagVarintsWithABoundedLength() throws {
        var reader = AvroBinaryReader([0x00, 0x01, 0x02, 0x03, 0x80, 0x01, 0xFE, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01])
        #expect(try reader.long() == 0)
        #expect(try reader.long() == -1)
        #expect(try reader.long() == 1)
        #expect(try reader.long() == -2)
        #expect(try reader.long() == 64)
        #expect(try reader.long() == Int64.max)
        var overlong = AvroBinaryReader([UInt8](repeating: 0xFF, count: 10) + [0x01])
        #expect(throws: PreviewFailure.malformedDocument) { try overlong.long() }
        var cut = AvroBinaryReader([0x80])
        #expect(throws: AvroUnderflow.self) { try cut.long() }
    }

    @Test func everyKindDecodesToItsValue() throws {
        let schema = try schemaNode("""
        {"type":"record","name":"All","fields":[
          {"name":"b","type":"boolean"},{"name":"i","type":"int"},{"name":"l","type":"long"},
          {"name":"f","type":"float"},{"name":"d","type":"double"},{"name":"y","type":"bytes"},
          {"name":"s","type":"string"},{"name":"e","type":{"type":"enum","name":"Color","symbols":["RED","GREEN"]}},
          {"name":"x","type":{"type":"fixed","name":"Hash","size":3}},{"name":"u","type":["null","string"]},
          {"name":"a","type":{"type":"array","items":"int"}},{"name":"m","type":{"type":"map","values":"long"}},
          {"name":"r","type":{"type":"record","name":"Inner","fields":[{"name":"k","type":"int"}]}}]}
        """)
        var bytes: [UInt8] = [1] + AvroWriter.long(-7) + AvroWriter.long(1 << 40)
        bytes += [0x00, 0x00, 0xC0, 0x3F] + [UInt8](repeating: 0, count: 6) + [0xF8, 0x3F]
        bytes += AvroWriter.long(2) + [9, 9] + AvroWriter.string("héllo")
        bytes += AvroWriter.long(1) + [1, 2, 3] + AvroWriter.long(1) + AvroWriter.string("x")
        bytes += AvroWriter.long(3) + AvroWriter.long(1) + AvroWriter.long(2) + AvroWriter.long(3) + AvroWriter.long(0)
        bytes += AvroWriter.long(1) + AvroWriter.string("k") + AvroWriter.long(5) + AvroWriter.long(0)
        bytes += AvroWriter.long(11)
        guard case .record(let fields) = try decode(schema, bytes) else { Issue.record("Expected a record"); return }
        #expect(fields.map(\.name) == ["b", "i", "l", "f", "d", "y", "s", "e", "x", "u", "a", "m", "r"])
        func text(_ value: AvroValue) -> String { AvroAdapter.compactText(value) }
        #expect(fields.map { text($0.value) } == [
            "true", "-7", "\(1 << 40)", "1.5", "1.5", "bytes[2]", "\"héllo\"", "GREEN", "bytes[3]", "\"x\"",
            "[1, 2, 3]", "{\"k\": 5}", "{\"k\": 11}"])
    }

    @Test func malformedValuesAreRejected() throws {
        let color = try schemaNode(#"{"type":"enum","name":"C","symbols":["A","B"]}"#)
        #expect(throws: PreviewFailure.malformedDocument) { try decode(color, AvroWriter.long(2)) }
        #expect(throws: PreviewFailure.malformedDocument) { try decode(color, AvroWriter.long(-1)) }
        let union = try schemaNode(#"["null","string"]"#)
        #expect(throws: PreviewFailure.malformedDocument) { try decode(union, AvroWriter.long(2)) }
        #expect(throws: PreviewFailure.malformedDocument) { try decode(try schemaNode(#""boolean""#), [2]) }
        // An int that does not fit 32 bits.
        #expect(throws: PreviewFailure.malformedDocument) { try decode(try schemaNode(#""int""#), AvroWriter.long(1 << 33)) }
        // A string longer than the block, and a block that ends inside a value.
        #expect(throws: PreviewFailure.malformedDocument) { try decode(try schemaNode(#""string""#), AvroWriter.long(500) + [1, 2]) }
        #expect(throws: PreviewFailure.malformedDocument) { try decode(try schemaNode(#""double""#), [1, 2, 3]) }
    }

    @Test func arrayAndMapBlocksAcceptNegativeCountsAndStayBounded() throws {
        let array = try schemaNode(#"{"type":"array","items":"long"}"#)
        // Negative count: block of two items preceded by its byte size.
        let blocked = AvroWriter.long(-2) + AvroWriter.long(2) + AvroWriter.long(10) + AvroWriter.long(20) + AvroWriter.long(0)
        guard case .array(let items, let total) = try decode(array, blocked) else { Issue.record("array"); return }
        #expect(total == 2 && items.count == 2)
        // Only a bounded prefix is retained, but every item is consumed.
        let many = AvroWriter.long(100) + [UInt8](repeating: 2, count: 100) + AvroWriter.long(0)
        guard case .array(let kept, let all) = try decode(array, many) else { Issue.record("array"); return }
        #expect(all == 100 && kept.count == AvroValueDecoder.retainedItems)
        // A claimed count beyond the limit never loops.
        #expect(throws: PreviewFailure.tooManyNodes) { try decode(array, AvroWriter.long(5_000_000) + [0]) }
        // Zero-width items cannot spin: nulls cost no bytes, so the work allowance stops them.
        let nulls = try schemaNode(#"{"type":"array","items":"null"}"#)
        #expect(throws: PreviewFailure.tooManyNodes) { try decode(nulls, AvroWriter.long(900_000) + [0]) }
    }

    @Test func recursiveSchemasResolveAndDepthIsBounded() throws {
        let node = try schemaNode(#"{"type":"record","name":"Node","fields":[{"name":"n","type":"int"},{"name":"next","type":["null","Node"]}]}"#)
        var chain: [UInt8] = []
        for value in 0..<3 { chain += AvroWriter.long(Int64(value)) + AvroWriter.long(1) }
        chain += AvroWriter.long(3) + AvroWriter.long(0)
        #expect(AvroAdapter.compactText(try decode(node, chain)) == #"{"n": 0, "next": {"n": 1, "next": {"n": 2, "next": {"n": 3, "next": null}}}}"#)
        var deep: [UInt8] = []
        for _ in 0..<40 { deep += AvroWriter.long(0) + AvroWriter.long(1) }
        deep += AvroWriter.long(0) + AvroWriter.long(0)
        #expect(throws: PreviewFailure.structureTooDeep) { try decode(node, deep) }
    }

    @Test func schemaErrorsAreMalformedNotGuessed() throws {
        let invalid = [
            #"{"type":"record","name":"A","fields":[{"name":"x","type":"int"},{"name":"x","type":"long"}]}"#,
            #"{"type":"record","name":"A","fields":[{"name":"x","type":"Missing"}]}"#,
            #"["null",{"type":"enum","name":"E","symbols":["A","A"]}]"#,
            #"{"type":"fixed","name":"F","size":-1}"#,
            #"{"type":"array"}"#, #"{"type":"map"}"#, #"{"name":"x"}"#, "7", "null",
            #"{"type":"record","name":"A","fields":[{"name":"x","type":{"type":"fixed","name":"A","size":2}}]}"#
        ]
        for json in invalid {
            #expect(throws: PreviewFailure.malformedDocument, "\(json)") { try schemaNode(json) }
        }
    }

    @Test func namespacesResolveRelativeReferencesAndLogicalTypesAreKept() throws {
        let schema = try schemaNode("""
        {"type":"record","name":"Outer","namespace":"com.example","fields":[
          {"name":"inner","type":{"type":"record","name":"Inner","fields":[{"name":"at","type":{"type":"long","logicalType":"timestamp-millis"}}]}},
          {"name":"again","type":"Inner"}]}
        """)
        #expect(schema.registry.keys.sorted() == ["com.example.Inner", "com.example.Outer"])
        let inner = try #require(schema.root.fields.first?.node)
        #expect(inner.fields.first?.node.logicalType == "timestamp-millis")
        #expect(schema.root.fields.last?.node.kind == .reference)
        #expect(try schema.resolve(try #require(schema.root.fields.last?.node)).name == "com.example.Inner")
    }

    @Test func schemaNestingBeyondTheLimitIsRejected() throws {
        var json = #""long""#
        for _ in 0..<40 { json = #"{"type":"array","items":"# + json + "}" }
        #expect(throws: PreviewFailure.self) { try schemaNode(json) }
    }
}

@Suite("Avro adapter")
struct AvroAdapterTests {
    private let sampleColumns = ["id", "name", "password", "ratio", "active", "nick", "tags", "blob"]

    @Test func nullCodecFileBecomesSchemaSummaryAndRowTable() throws {
        let document = try DataTest.parse(AvroAdapter(), DataFixtures.avro)
        let object = try DataTest.object(document)
        #expect(object["dataFormat"] as? String == "Avro")
        #expect(object["codec"] as? String == "null")
        #expect(object["recordCount"] as? Int == 3)
        #expect(object["blockCount"] as? Int == 1)
        let schema = try #require(object["schema"] as? [String: Any])
        #expect(schema["kind"] as? String == "record" && schema["typeName"] as? String == "synthetic.Sample")
        let fields = try #require(schema["fields"] as? [[String: Any]])
        #expect(fields.map { $0["name"] as? String } == sampleColumns)
        #expect(fields[5]["kind"] as? String == "union")
        #expect((fields[5]["branches"] as? [[String: Any]])?.map { $0["kind"] as? String } == ["null", "string"])
        #expect((fields[6]["items"] as? [String: Any])?["kind"] as? String == "string")

        let table = try DataTest.table(object)
        #expect(table.columns == sampleColumns)
        let rows = table.rows.map { $0.map(DataTest.cell) }
        #expect(rows.count == 3 && !table.truncated)
        #expect(rows[0] == ["0", "item 0", DataFixtures.secret, "0.0", "false", "null", #"["a", "b"]"#, "bytes:4"])
        #expect(rows[1] == ["1", "item 1", DataFixtures.secret, "0.25", "true", "nick1", #"["a", "b"]"#, "bytes:4"])
        #expect(rows[2][3] == "0.5")
        let metadata = try #require(object["metadata"] as? [[String: Any]])
        #expect(metadata.first?["key"] as? String == "writer")
    }

    @Test func columnsNamedLikeSecretsAreMarkedInEveryRow() throws {
        let document = try DataTest.parse(AvroAdapter(), DataFixtures.avro)
        let secret = Array(DataFixtures.secret.utf8)
        let text = Array(document.text.utf8)
        let concealed = document.sensitiveRanges.map { Array(text[$0.utf8Range]) }
        #expect(concealed.filter { $0 == secret }.count == 3)
        // Nothing else is marked: other columns stay readable.
        #expect(concealed.filter { $0 != secret }.isEmpty)
    }

    @Test func deflateBlocksDecodeLikeNullBlocks() throws {
        let plain = try DataTest.rows(try DataTest.object(try DataTest.parse(AvroAdapter(), DataFixtures.avro)))
        let packed = try DataTest.object(try DataTest.parse(AvroAdapter(), DataFixtures.avroDeflate))
        #expect(packed["codec"] as? String == "deflate")
        #expect(try DataTest.rows(packed) == plain)
    }

    @Test func unsupportedCodecsKeepTheSchemaButShowNoRows() throws {
        var data = DataFixtures.avroDeflate
        let range = try #require(data.range(of: Data("deflate".utf8)))
        data.replaceSubrange(range, with: Data("zstdxyz".utf8))
        let object = try DataTest.object(try DataTest.parse(AvroAdapter(), data))
        #expect(object["codec"] as? String == "zstdxyz")
        #expect(object["recordCount"] as? Int == 3)
        #expect(object["table"] == nil)
        #expect(object["schema"] != nil)
    }

    @Test func recordsAreCountedAcrossBlocksAndOnlyTheFirstHundredAreShown() throws {
        let schema = #"{"type":"record","name":"R","fields":[{"name":"n","type":"long"}]}"#
        let blocks = (0..<3).map { block in
            (count: 50, payload: (0..<50).flatMap { AvroWriter.long(Int64(block * 50 + $0)) })
        }
        let object = try DataTest.object(try DataTest.parse(AvroAdapter(), AvroWriter.container(schema: schema, blocks: blocks)))
        #expect(object["recordCount"] as? Int == 150 && object["blockCount"] as? Int == 3)
        let table = try DataTest.table(object)
        #expect(table.rows.count == 100 && table.truncated)
        #expect(DataTest.cell(table.rows[99][0]) == "99")
    }

    @Test func manyBlocksAreHoppedWithinALimitAndFlaggedPartial() throws {
        let schema = #"{"type":"record","name":"R","fields":[{"name":"n","type":"long"}]}"#
        let blocks = (0..<1_100).map { (count: 1, payload: AvroWriter.long(Int64($0))) }
        let source = DataRecordingSource(AvroWriter.container(schema: schema, blocks: blocks))
        let object = try DataTest.object(try AvroAdapter().parse(source, context: DataTest.context()))
        #expect(object["blockCount"] as? Int == AvroAdapter.maximumBlockHops)
        #expect(object["partial"] as? Bool == true)
        // Hopping reads a few dozen bytes per block, never the payloads of blocks beyond the table.
        #expect(source.reads.map(\.count).reduce(0, +) < 80_000)
    }

    @Test func hostileFramingIsRejected() throws {
        let schema = #"{"type":"record","name":"R","fields":[{"name":"n","type":"long"}]}"#
        let good = AvroWriter.container(schema: schema, blocks: [(count: 2, payload: [2, 4])])
        // Wrong sync marker after the block.
        var badSync = good
        badSync[badSync.count - 1] ^= 0xFF
        #expect(throws: PreviewFailure.malformedDocument) { try DataTest.parse(AvroAdapter(), badSync) }
        // A block that claims more bytes than the file holds.
        var longBlock = Data(good.prefix(good.count - 16 - 2 - 2))
        longBlock += Data(AvroWriter.long(2) + AvroWriter.long(1_000_000) + [2, 4] + AvroWriter.sync)
        #expect(throws: PreviewFailure.malformedDocument) { try DataTest.parse(AvroAdapter(), longBlock) }
        // Negative counts or sizes.
        let negative = AvroWriter.container(schema: schema, blocks: [(count: -1, payload: [2])])
        #expect(throws: PreviewFailure.malformedDocument) { try DataTest.parse(AvroAdapter(), negative) }
        // Not Avro at all, or no schema.
        #expect(throws: PreviewFailure.malformedDocument) { try DataTest.parse(AvroAdapter(), Data("Obj\u{2}".utf8) + Data(count: 64)) }
        #expect(throws: PreviewFailure.malformedDocument) { try DataTest.parse(AvroAdapter(), Data()) }
        // Fewer records in the block than it declares.
        let short = AvroWriter.container(schema: schema, blocks: [(count: 5, payload: [2, 4])])
        #expect(throws: PreviewFailure.malformedDocument) { try DataTest.parse(AvroAdapter(), short) }
    }

    @Test func everyTruncationAndCorruptionEndsBoundedAndTyped() {
        for data in [DataFixtures.avro, DataFixtures.avroDeflate] {
            for length in 0..<data.count {
                DataTest.expectBounded("prefix \(length)") { _ = try DataTest.parse(AvroAdapter(), data.prefix(length)) }
            }
            for index in 0..<data.count {
                var changed = data
                changed[index] ^= 0x5A
                DataTest.expectBounded("flip \(index)") { _ = try DataTest.parse(AvroAdapter(), changed) }
            }
        }
    }

    @Test func aDeflateBlockThatExpandsBeyondTheLimitFailsClosed() throws {
        let schema = #"{"type":"record","name":"R","fields":[{"name":"n","type":"null"}]}"#
        let payload = AvroWriter.deflate([UInt8](repeating: 0, count: 20_000_000))
        #expect(payload.count < 50_000)
        let data = AvroWriter.container(schema: schema, codec: "deflate", blocks: [(count: 20_000_000, payload: payload)])
        #expect(throws: PreviewFailure.outputTooLarge) { try DataTest.parse(AvroAdapter(), data) }
    }

    @Test func longTextAndWideRecordsStayInsideTheOutlineLimits() throws {
        var fields = ""
        var payload: [UInt8] = []
        for column in 0..<60 {
            fields += (column == 0 ? "" : ",") + #"{"name":"column\#(column)","type":"string"}"#
        }
        let record = (0..<60).flatMap { _ in AvroWriter.string(String(repeating: "é", count: 1_000)) }
        for _ in 0..<20 { payload += record }
        let schema = #"{"type":"record","name":"Wide","fields":["# + fields + "]}"
        let document = try DataTest.parse(AvroAdapter(), AvroWriter.container(schema: schema, blocks: [(count: 20, payload: payload)]),
                                          budget: PreviewBudget(maxInputBytes: 8_388_608, maxOutputUTF8Bytes: 4_194_304, maxMilliseconds: 30_000))
        let object = try DataTest.object(document)
        let table = try DataTest.table(object)
        #expect(table.columns.count == AvroAdapter.maximumColumns && table.truncated)
        #expect(table.rows.count < 20)
        let first = DataTest.cell(table.rows[0][0])
        #expect(first.count == 200 && first.hasSuffix("…"))
        #expect(document.text.utf16.count < 250_000)
        #expect(DataTest.nodeCount(object) < 18_000)
    }

    @Test func nestedValuesWithSecretKeysAreMarkedWholeAndBinaryIsNeverShown() throws {
        let schema = #"{"type":"record","name":"R","fields":[{"name":"meta","type":{"type":"map","values":"string"}},{"name":"safe","type":{"type":"map","values":"string"}},{"name":"raw","type":"bytes"}]}"#
        var payload = AvroWriter.long(1) + AvroWriter.string("api_key") + AvroWriter.string(DataFixtures.secret) + AvroWriter.long(0)
        payload += AvroWriter.long(1) + AvroWriter.string("note") + AvroWriter.string("fine") + AvroWriter.long(0)
        payload += AvroWriter.long(4) + Array(DataFixtures.secret.utf8.prefix(4))
        let document = try DataTest.parse(AvroAdapter(), AvroWriter.container(schema: schema, blocks: [(count: 1, payload: payload)]))
        let rows = try DataTest.rows(try DataTest.object(document))
        #expect(rows[0][1] == #"{"note": "fine"}"#)
        #expect(rows[0][2] == "bytes:4")
        let text = Array(document.text.utf8)
        let concealed = document.sensitiveRanges.map { String(decoding: text[$0.utf8Range], as: UTF8.self) }
        #expect(concealed.count == 1 && concealed[0].contains("api_key"))
    }

    @Test func cancellationPrecedesAnyRead() async {
        let source = DataRecordingSource(DataFixtures.avro)
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            _ = try? AvroAdapter().parse(source, context: DataTest.context())
        }
        await task.value
        #expect(source.reads.isEmpty)
    }
}
