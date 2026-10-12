import Foundation
import Darwin
import Testing
import PreviewContracts
@testable import PreviewFormats

@Suite("Q153 complete bundle owner scope")
struct Q153BundleOwnerTests {
    @Test(arguments: [DirectoryMetadataCheck.rootPreflight, .rootOpened])
    func rootFlagsRefuseBeforeSignature(check: DirectoryMetadataCheck) throws {
        let fixture = try Q153BundleFixture(); defer { fixture.remove() }
        let probe = Q153DirectoryProbe(); probe.configure(dataless: check)
        let signature = Q153BundleSignatureProbe()
        #expect(throws: PreviewFailure.unavailableContent) {
            try ApplicationBundleAdapter(signatureReader: signature, access: probe.access).parse(url: fixture.url, context: q153DirectoryContext())
        }
        #expect(signature.calls == 0 && probe.snapshot.entries == 1 && probe.snapshot.restores == 1)
        #expect(probe.snapshot.rootOpened.count == (check == .rootPreflight ? 0 : 1))
        probe.expectClean()
    }
    @Test(arguments: [true, false])
    func policyFailureDoesNotReturnADocument(entryFailure: Bool) throws {
        let fixture = try Q153BundleFixture(); defer { fixture.remove() }
        let probe = Q153DirectoryProbe(); probe.configure(entryFails: entryFailure, restoreFails: !entryFailure)
        let signature = Q153BundleSignatureProbe()
        #expect(throws: PreviewFailure.unavailableContent) {
            try ApplicationBundleAdapter(signatureReader: signature, access: probe.access).parse(url: fixture.url, context: q153DirectoryContext())
        }
        #expect(signature.calls == (entryFailure ? 0 : 1))
        #expect(probe.snapshot.entries == 1 && probe.snapshot.restores == (entryFailure ? 0 : 1))
        probe.expectClean()
    }
    @Test func successfulParseClosesOwnerBeforeRestoration() throws {
        let fixture = try Q153BundleFixture(); defer { fixture.remove() }
        let probe = Q153DirectoryProbe(); let signature = Q153BundleSignatureProbe()
        let document = try ApplicationBundleAdapter(signatureReader: signature, access: probe.access).parse(url: fixture.url, context: q153DirectoryContext())
        #expect(PackageTestSupport.object(document)["name"] as? String == "Owned")
        #expect(signature.calls == 1 && probe.snapshot.entries == 1 && probe.snapshot.restores == 1)
        probe.expectClean()
    }
    @Test func completeOwnerSurvivesSuccessfulRestorationThenClosesOnce() throws {
        let fixture = try Q153BundleFixture(); defer { fixture.remove() }
        let probe = Q153DirectoryProbe()
        weak var weakOwner: BundleDirectory?
        var owner: BundleDirectory? = try probe.withoutMaterializing {
            let result = try BundleDirectory(url: fixture.url, allowance: 1_000, access: probe.access)
            weakOwner = result
            return result
        }
        withExtendedLifetime(owner) {
            #expect(weakOwner != nil && probe.snapshot.liveAtRestore == 1 && probe.snapshot.closed.isEmpty)
        }
        owner = nil
        #expect(weakOwner == nil && probe.snapshot.opened.count == 1 && probe.snapshot.closed == probe.snapshot.opened)
        #expect(probe.snapshot.closeResults == [0] && probe.snapshot.depth == 0 && probe.snapshot.outside == 0)
    }
    @Test func successfulOwnerIsDestroyedWhenRestorationFails() throws {
        let fixture = try Q153BundleFixture(); defer { fixture.remove() }
        let probe = Q153DirectoryProbe(); probe.configure(restoreFails: true)
        weak var weakOwner: BundleDirectory?
        #expect(throws: PreviewFailure.unavailableContent) {
            try probe.withoutMaterializing {
                let owner = try BundleDirectory(url: fixture.url, allowance: 1_000, access: probe.access)
                weakOwner = owner
                return owner
            }
        }
        #expect(weakOwner == nil && probe.snapshot.liveAtRestore == 1)
        #expect(probe.snapshot.opened.count == 1 && probe.snapshot.closed == probe.snapshot.opened && probe.snapshot.closeResults == [0])
    }
    @Test func constructorFailureAfterOpenClosesLocalOwner() throws {
        let fixture = try Q153BundleFixture(); defer { fixture.remove() }
        let probe = Q153DirectoryProbe(); probe.configure(fault: .metadata(.rootOpened), error: EDEADLK)
        #expect(throws: PreviewFailure.unavailableContent) {
            try probe.withoutMaterializing { try BundleDirectory(url: fixture.url, allowance: 1_000, access: probe.access) }
        }
        #expect(probe.snapshot.opened.count == 1)
        probe.expectClean()
    }
    @Test func cancelledContextSkipsScopeAndRoot() async throws {
        let fixture = try Q153BundleFixture(); defer { fixture.remove() }
        let probe = Q153DirectoryProbe(), signature = Q153BundleSignatureProbe(), url = fixture.url
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            #expect(throws: CancellationError.self) {
                try ApplicationBundleAdapter(signatureReader: signature, access: probe.access).parse(url: url, context: q153DirectoryContext())
            }
        }
        await task.value
        #expect(signature.calls == 0 && probe.snapshot.entries == 0 && probe.snapshot.operations.isEmpty)
        probe.expectClean()
    }
    @Test func requestedDescendantsAreOpenedInsideTheCheckedScope() throws {
        let fixture = try Q153BundleFixture(); defer { fixture.remove() }
        try fixture.addDescendants()
        let probe = Q153DirectoryProbe()
        let signature = Q153BundleSignatureProbe()
        let document = try ApplicationBundleAdapter(signatureReader: signature, access: probe.access)
            .parse(url: fixture.url, context: q153DirectoryContext())
        #expect(PackageTestSupport.object(document)["name"] as? String == "Owned")
        let operations = probe.snapshot.operations
        #expect(operations.contains(.metadata(.childPreflight)))
        #expect(operations.contains(.metadata(.listedChild)))
        #expect(operations.contains(.openDirectory(root: false)))
        probe.expectClean()
    }
    @Test func offloadedRequestedFileIsNotRead() throws {
        let fixture = try Q153BundleFixture(); defer { fixture.remove() }
        let probe = Q153DirectoryProbe()
        probe.configure(dataless: .childPreflight)
        let bundle = try BundleDirectory(url: fixture.url, allowance: 1_000_000, access: probe.access)
        #expect(throws: PreviewFailure.unavailableContent) {
            try bundle.read(["Contents", "Info.plist"], limit: 1_000_000, wholeFile: true, context: q153DirectoryContext())
        }
    }
    @Test func offloadedWalkedDirectoryIsNotOpened() throws {
        let fixture = try Q153BundleFixture(); defer { fixture.remove() }
        try fixture.addDescendants()
        let probe = Q153DirectoryProbe()
        probe.configure(dataless: .listedChild)
        let bundle = try BundleDirectory(url: fixture.url, allowance: 1_000_000, access: probe.access)
        let measurement = try bundle.measure(maximumItems: 100, maximumDepth: 8,
                                             softDeadline: ContinuousClock.now.advanced(by: .seconds(5)),
                                             context: q153DirectoryContext())
        #expect(measurement.isPartial)
        #expect(!probe.snapshot.operations.contains(.openDirectory(root: false)))
    }
    @Test func descendantDirectoryDeadlockIsUnavailable() throws {
        let fixture = try Q153BundleFixture(); defer { fixture.remove() }
        try fixture.addDescendants()
        let probe = Q153DirectoryProbe()
        probe.configure(fault: .openDirectory(root: false), error: EDEADLK)
        let bundle = try BundleDirectory(url: fixture.url, allowance: 1_000_000, access: probe.access)
        #expect(throws: PreviewFailure.unavailableContent) {
            try bundle.measure(maximumItems: 100, maximumDepth: 8,
                               softDeadline: ContinuousClock.now.advanced(by: .seconds(5)),
                               context: q153DirectoryContext())
        }
    }
}
