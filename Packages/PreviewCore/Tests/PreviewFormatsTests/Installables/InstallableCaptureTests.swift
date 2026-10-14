import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

@Suite("Install-time capture")
struct InstallableCaptureTests {
    private func file(_ path: String, size: Int = 0) -> ContainerEntry { ContainerEntry(path: path, kind: .file, size: size) }

    private func observe(_ capture: inout InstallableCapture, _ path: String, _ bytes: [UInt8]) {
        capture.observe(file(path, size: bytes.count), payload: bytes[...])
    }

    // MARK: Requested payloads

    @Test func keepsOnlyTheRequestedFilesDirectlyInsideAFolder() {
        var capture = InstallableCapture()
        observe(&capture, "package/package.json", Array("{}".utf8))
        observe(&capture, "package/pyproject.toml", Array("[x]".utf8))
        observe(&capture, "package/node_modules/dep/package.json", Array("{}".utf8))
        observe(&capture, "package.json", Array("{}".utf8))
        observe(&capture, "package/readme.md", Array("text".utf8))
        observe(&capture, "package/not-package.json", Array("{}".utf8))
        #expect(Set(capture.payloads.keys) == ["package/package.json", "package/pyproject.toml"])
    }

    @Test func normalizesLeadingDotComponentsAndIgnoresLinks() {
        var capture = InstallableCapture()
        observe(&capture, "./package/package.json", Array("{}".utf8))
        capture.observe(ContainerEntry(path: "package/pyproject.toml", kind: .symlink, size: 0), payload: [UInt8]()[...])
        #expect(Set(capture.payloads.keys) == ["package/package.json"])
    }

    @Test func aFileOverTheSizeCapIsNotKept() {
        var capture = InstallableCapture()
        observe(&capture, "package/package.json", [UInt8](repeating: 0x20, count: InstallableCapture.maximumPayloadBytes))
        observe(&capture, "package/pyproject.toml", [UInt8](repeating: 0x20, count: InstallableCapture.maximumPayloadBytes + 1))
        #expect(capture.payloads.keys.sorted() == ["package/package.json"])
        #expect(capture.payloads["package/package.json"]?.count == InstallableCapture.maximumPayloadBytes)
    }

    @Test func aLaterMemberOfTheSameNameReplacesTheEarlierOne() {
        var capture = InstallableCapture()
        observe(&capture, "package/package.json", Array("{\"a\":1}".utf8))
        observe(&capture, "package/package.json", Array("{\"b\":2}".utf8))
        #expect(capture.payloads["package/package.json"] == Data("{\"b\":2}".utf8))
        // When the replacement is too large to keep, the stale earlier file is dropped rather than read.
        observe(&capture, "package/package.json", [UInt8](repeating: 0x20, count: InstallableCapture.maximumPayloadBytes + 1))
        #expect(capture.payloads.isEmpty)
    }

    @Test func keepsAtMostSixtyFourPayloads() {
        var capture = InstallableCapture()
        for index in 0..<100 { observe(&capture, "folder\(index)/package.json", Array("{}".utf8)) }
        #expect(capture.payloads.count == InstallableCapture.maximumPayloads)
    }

    @Test func keepsAtMostFourMebibytesInTotal() {
        var capture = InstallableCapture()
        for index in 0..<8 { observe(&capture, "folder\(index)/package.json", [UInt8](repeating: 0x20, count: 700_000)) }
        #expect(capture.payloads.count == 5)
        #expect(capture.payloads.values.reduce(0) { $0 + $1.count } <= InstallableCapture.maximumTotalBytes)
    }

    // MARK: Native code

    @Test func countsNativeMembersByNameAndByLeadingBytes() {
        var capture = InstallableCapture()
        observe(&capture, "package/build/Release/addon.node", Array("not a binary".utf8))
        observe(&capture, "package/bin/tool", [0xCF, 0xFA, 0xED, 0xFE, 7, 0, 0, 1])
        observe(&capture, "package/lib/helper", [0x7F, 0x45, 0x4C, 0x46, 2, 1, 1, 0])
        observe(&capture, "package/index.js", Array("module.exports = 1".utf8))
        observe(&capture, "package/readme.md", [])
        #expect(capture.native.count == 3)
        #expect(capture.native.finding?.severity == .info)
    }

    @Test func nonRegularMembersAreNeverCounted() {
        var capture = InstallableCapture()
        capture.observe(ContainerEntry(path: "package/link.node", kind: .symlink, size: 0), payload: [UInt8]()[...])
        capture.observe(ContainerEntry(path: "package/lib.so", kind: .directory, size: 0), payload: [UInt8]()[...])
        #expect(capture.native.count == 0)
        #expect(capture.native.finding == nil)
    }

    @Test func leadingBytesAreCheckedForAtMostTheFirstFourThousandNinetySixMembers() {
        var capture = InstallableCapture()
        let elf: [UInt8] = [0x7F, 0x45, 0x4C, 0x46, 2, 1, 1, 0]
        for index in 0..<(NativeCodeTally.maximumMagicChecks + 10) { observe(&capture, "package/f\(index)", elf) }
        #expect(capture.native.count == NativeCodeTally.maximumMagicChecks)
        // A name settles a member without using up the budget.
        observe(&capture, "package/late.so", [])
        #expect(capture.native.count == NativeCodeTally.maximumMagicChecks + 1)
    }

    // MARK: The TAR listing

    @Test func aPlainTarballHasNoInstallFindingsAndTheSameListing() throws {
        let members: [InstallFixtures.Member] = [.file("pkg/readme.txt", "hello"), .file("pkg/data/values.json", "{}")]
        let document = try InstallFixtures.listing(members)
        #expect(document.findings.isEmpty)
        let direct = try TARListingAdapter().parse(FileBytes(data: InstallFixtures.tar(members)), context: InstallFixtures.context)
        #expect(direct.text == document.text)
    }

    @Test func archiveRisksAreStillReportedBesideTheInstallFindings() throws {
        let document = try InstallFixtures.listing([.file("../escape.txt", "x")])
        #expect(InstallFixtures.kinds(document) == [.archiveUnsafePath])
    }
}
