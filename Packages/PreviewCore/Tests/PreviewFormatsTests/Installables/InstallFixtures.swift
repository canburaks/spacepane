import Foundation
import PreviewContracts
@testable import PreviewFormats

/// Synthetic fixtures for the install-time inspectors (decision 030): TAR bytes assembled here, wrapped
/// in gzip with the shared test compressor. Nothing is produced by a packaging tool, and no fixture is
/// ever installed, unpacked or run; the strings that look like shell commands are inert text.
enum InstallFixtures {
    /// Built per use: a `RequestContext` dates its deadline from construction.
    static var context: RequestContext { RequestContext(budget: PreviewBudget(maxMilliseconds: 30_000)) }

    struct Member {
        var path: String
        var payload = Data()
        var type: UInt8 = 48

        static func file(_ path: String, _ text: String) -> Member { Member(path: path, payload: Data(text.utf8)) }
        static func file(_ path: String, bytes: [UInt8]) -> Member { Member(path: path, payload: Data(bytes)) }
        static func directory(_ path: String) -> Member { Member(path: path, type: 53) }
    }

    /// A USTAR archive; names must fit the 100-byte header field.
    static func tar(_ members: [Member]) -> Data {
        var data = Data()
        for member in members {
            var header = [UInt8](repeating: 0, count: 512)
            func put(_ string: String, at offset: Int, count: Int) {
                for (index, byte) in string.utf8.prefix(count).enumerated() { header[offset + index] = byte }
            }
            put(member.path, at: 0, count: 100)
            put("0000644\0", at: 100, count: 8)
            put(String(format: "%011o", member.payload.count) + "\0", at: 124, count: 12)
            header[156] = member.type
            put("ustar\0", at: 257, count: 6)
            for index in 148..<156 { header[index] = 32 }
            put(String(format: "%06o", header.reduce(0) { $0 + Int($1) }) + "\0 ", at: 148, count: 8)
            data += Data(header) + member.payload + Data(repeating: 0, count: (512 - member.payload.count % 512) % 512)
        }
        return data + Data(repeating: 0, count: 1024)
    }

    static func gzip(_ members: [Member]) throws -> Data { try compressFixture(tar(members), gzip: true) }

    /// An npm tarball: everything under `package/`, and no directory entries, as `npm pack` writes it.
    static func npmTarball(packageJSON: String, extra: [Member] = []) -> [Member] {
        [Member.file("package/package.json", packageJSON)] + extra
    }

    /// The listing of a gzip-wrapped TAR, as Finder's `.tgz` preview builds it.
    static func listing(_ members: [Member]) throws -> ParsedTextDocument {
        try GZIPPreviewAdapter().parse(FileBytes(data: gzip(members)), context: context)
    }

    static func kinds(_ document: ParsedTextDocument) -> Set<PreviewFindingKind> { Set(document.findings.map(\.kind)) }

    static func finding(_ kind: PreviewFindingKind, in document: ParsedTextDocument) -> PreviewFinding? {
        document.findings.first { $0.kind == kind }
    }

    /// A ZIP archive of stored or deflated members with exact sizes and CRCs, from the shared data fixtures.
    static func zip(_ members: [(path: String, data: Data)], deflate: Bool = true) -> Data {
        DataTest.zip(members.map { (name: $0.path, data: [UInt8]($0.data), deflate: deflate) })
    }

    // MARK: Wheels

    static let defaultMetadata = """
    Metadata-Version: 2.1
    Name: example
    Version: 1.0
    Summary: A tiny example
    Requires-Python: >=3.8
    Requires-Dist: requests (>=2.0)
    License-Expression: MIT

    A long description that is not part of the headers.

    """
    static let defaultWheelFile = "Wheel-Version: 1.0\nGenerator: bdist_wheel (0.43.0)\nRoot-Is-Purelib: true\nTag: py3-none-any\n"
    static let defaultEntryPoints = "[console_scripts]\nexample = example.cli:main\n"

    /// The members of a benign pure-Python wheel; `extra` members follow them.
    static func wheelMembers(metadata: String? = defaultMetadata, wheel: String? = defaultWheelFile,
                             entryPoints: String? = defaultEntryPoints, folder: String = "example-1.0",
                             extra: [(path: String, data: Data)] = []) -> [(path: String, data: Data)] {
        var members: [(path: String, data: Data)] = [("example/__init__.py", Data("VALUE = 1\n".utf8))]
        if let metadata { members.append(("\(folder).dist-info/METADATA", Data(metadata.utf8))) }
        if let wheel { members.append(("\(folder).dist-info/WHEEL", Data(wheel.utf8))) }
        members.append(("\(folder).dist-info/RECORD", Data("example/__init__.py,,\n".utf8)))
        if let entryPoints { members.append(("\(folder).dist-info/entry_points.txt", Data(entryPoints.utf8))) }
        return members + extra
    }

    static func wheelFile(_ text: String, at path: String) -> (path: String, data: Data) { (path, Data(text.utf8)) }

    /// A package.json whose `scripts` and dependency tables are given as ready-made JSON text.
    static func manifest(scripts: String? = nil, dependencies: String? = nil, optionalDependencies: String? = nil,
                         extra: String? = nil) -> String {
        var members = ["\"name\": \"example\"", "\"version\": \"1.0.0\""]
        if let scripts { members.append("\"scripts\": {\(scripts)}") }
        if let dependencies { members.append("\"dependencies\": {\(dependencies)}") }
        if let optionalDependencies { members.append("\"optionalDependencies\": {\(optionalDependencies)}") }
        if let extra { members.append(extra) }
        return "{" + members.joined(separator: ", ") + "}"
    }
}
