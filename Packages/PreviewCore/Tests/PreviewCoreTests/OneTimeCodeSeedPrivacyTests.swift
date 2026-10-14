import Foundation
import Testing
import PreviewContracts
import PreviewCore
import PreviewFormats

private struct BytesReader: PreviewFileReading {
    let data: Data
    func read(url: URL, context: RequestContext) throws -> FileBytes { FileBytes(data: data) }
}

/// One-time-code seeds are secrets: whoever holds one can make every future code (decision 029).
@Suite("One-time-code seeds are concealed")
struct OneTimeCodeSeedPrivacyTests {
    @Test(arguments: ["totp", "login_totp", "OTPAuth", "otp", "hotp_secret", "otpauth"])
    func seedFieldNamesAreSensitive(_ name: String) {
        #expect(SecretFieldPolicy.isSensitive(name))
    }

    @Test(arguments: ["option", "output", "hotel", "topology", "footprint"])
    func ordinaryNamesStayOrdinary(_ name: String) {
        #expect(!SecretFieldPolicy.isSensitive(name))
    }

    @Test func aBitwardenStyleCSVConcealsTheSeedColumn() async throws {
        let seed = "JBSWY3DPEHPK3PXPSYNTHETIC"
        let csv = "folder,favorite,type,name,notes,fields,reprompt,login_uri,login_username,login_password,login_totp\n"
            + ",,login,Example,,,0,https://example.com,user,synthetic-password-1,\(seed)\n"
        let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations, reader: BytesReader(data: Data(csv.utf8)))
        let outcome = await pipeline.preview(url: URL(fileURLWithPath: "/fixtures/bitwarden_export.csv"))
        guard case .ready(let presentation) = outcome else { Issue.record("\(outcome)"); return }
        #expect(!presentation.text.contains(seed))
        #expect(!presentation.text.contains("synthetic-password-1"))
        #expect(presentation.findings.contains { $0.kind == .exportReadableLogins })
    }
}
