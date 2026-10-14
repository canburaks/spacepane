import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

@Suite("Add-on registrations")
struct AddOnFormatAdaptersTests {
    private func summary(_ formatID: FormatID, _ data: Data, suffix: String? = nil) throws -> [String: Any] {
        let registration = try #require(AddOnFormatAdapters.registrations.first { $0.formatID == formatID })
        guard case .randomAccess(let make) = registration.inputPath else {
            Issue.record("\(formatID.rawValue) is not a random-access registration")
            return [:]
        }
        var context = RequestContext(budget: try #require(registration.defaultBudget))
        context.nameHint = suffix.map { PreviewNameHint(filename: "sample.\($0)", suffix: $0) }
        return PackageTestSupport.object(try make().parse(DataByteSource(data), context: context))
    }

    @Test func threeRandomAccessRegistrationsUseTheContainerScanBudget() {
        let registrations = AddOnFormatAdapters.registrations
        #expect(registrations.map(\.formatID) == [.mcpBundle, .editorExtension, .browserExtension])
        #expect(registrations.allSatisfy { $0.defaultBudget == .containerScan && $0.lenses.isEmpty })
        #expect(registrations.allSatisfy { if case .randomAccess = $0.inputPath { true } else { false } })
    }

    @Test func eachRegistrationReadsItsOwnPackage() throws {
        #expect(try summary(.mcpBundle, MCPBundleAdapterTests.bundle())["name"] as? String == "notes-server")
        #expect(try summary(.editorExtension, EditorExtensionAdapterTests.vsix())["name"] as? String == "notes-helper")
        #expect(try summary(.browserExtension, BrowserExtensionAdapterTests.zip(BrowserExtensionAdapterTests.firefox()))["browser"] as? String == "Firefox (XPI)")
    }

    @Test func xpiAndCRXFilesReachTheSameBrowserExtensionAdapter() throws {
        let archive = BrowserExtensionAdapterTests.zip(BrowserExtensionAdapterTests.chrome())
        let xpi = try summary(.browserExtension, archive, suffix: "xpi")
        let crx = try summary(.browserExtension, AddOnFixtures.crx3(archive: archive), suffix: "crx")
        #expect(xpi["browser"] as? String == "Firefox (XPI)" && crx["browser"] as? String == "Chrome (CRX3)")
        #expect(xpi["name"] as? String == "Tab Notes" && crx["name"] as? String == "Tab Notes")
    }

    @Test func aPackageWithTheWrongShapeIsRefusedNotMisread() throws {
        let vsix = EditorExtensionAdapterTests.vsix()
        #expect(throws: PreviewFailure.malformedDocument) { try summary(.mcpBundle, vsix) }
        #expect(throws: PreviewFailure.malformedDocument) { try summary(.browserExtension, vsix) }
        #expect(throws: PreviewFailure.malformedDocument) { try summary(.editorExtension, MCPBundleAdapterTests.bundle()) }
    }
}
