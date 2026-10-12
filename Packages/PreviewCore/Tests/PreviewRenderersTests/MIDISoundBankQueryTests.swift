import Foundation
import AudioToolbox
import Testing
@testable import PreviewRenderers

@MainActor @Test func unsupportedOrWrongSizeSoundBankMetadataSkipsTheValueQuery() {
    var queries = 0
    let read: (inout Unmanaged<CFURL>?, inout UInt32) -> OSStatus = { _, _ in
        queries += 1
        return noErr
    }
    #expect(MIDISoundBankQuery.loadedURL(getInfo: { _ in kAudioUnitErr_InvalidProperty }, getValue: read) == nil)
    #expect(MIDISoundBankQuery.loadedURL(getInfo: { $0 = 0; return noErr }, getValue: read) == nil)
    #expect(queries == 0)
}

@MainActor @Test func soundBankMetadataConsumesOwnedURLWithoutReadingTheFile() {
    let url = URL(fileURLWithPath: "/nonexistent-synthetic-bank.dls")
    let result = MIDISoundBankQuery.loadedURL(getInfo: {
        $0 = UInt32(MemoryLayout<Unmanaged<CFURL>?>.size)
        return noErr
    }, getValue: { value, _ in
        value = .passRetained(url as CFURL)
        return noErr
    })
    #expect(result == url)
}

@MainActor @Test func failedNullWrongSizeAndNonFileBankMetadataAreOptional() {
    let info: (inout UInt32) -> OSStatus = {
        $0 = UInt32(MemoryLayout<Unmanaged<CFURL>?>.size)
        return noErr
    }
    #expect(MIDISoundBankQuery.loadedURL(getInfo: info, getValue: { _, _ in kAudioUnitErr_InvalidProperty }) == nil)
    #expect(MIDISoundBankQuery.loadedURL(getInfo: info, getValue: { _, _ in noErr }) == nil)
    #expect(MIDISoundBankQuery.loadedURL(getInfo: info, getValue: { value, size in
        value = .passRetained(URL(fileURLWithPath: "/synthetic-bank.dls") as CFURL)
        size = 0
        return noErr
    }) == nil)
    #expect(MIDISoundBankQuery.loadedURL(getInfo: info, getValue: { value, _ in
        value = .passRetained(URL(string: "https://invalid.example/synthetic-bank.dls")! as CFURL)
        return noErr
    }) == nil)
}
