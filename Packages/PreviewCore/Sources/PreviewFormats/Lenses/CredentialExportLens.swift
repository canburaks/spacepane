import Foundation
import PreviewContracts

/// Readable credential exports: password-manager and one-time-code exports saved without encryption
/// (decision 029). A file like this holds every login or code secret of an account in the clear, so
/// the finding says that it is there, how many, and where it starts; it never says what they are.
///
/// - **CSV and TSV.** The first record is a header; `CredentialExportHeaders` decides whether it is a
///   password manager's. Each later record with any non-empty field counts as one login. Records are
///   read with the shared `DelimitedRecords` grammar, so a quoted field that holds line breaks is one
///   record. The finding points at the header line.
/// - **JSON.** An unencrypted Bitwarden export (`"encrypted": false` and `items` whose `login` is an
///   object), an unencrypted Aegis export (`header.slots` null and `db.entries`), a 2FAS export with
///   `schemaVersion` and `services` that hold a `secret`, and an andOTP array of objects with a `secret`
///   and a TOTP, HOTP or STEAM type. Encrypted exports of all four are structurally different and say nothing.
///
/// The privacy stage has already replaced the secret values with its token, which the JSON reader accepts.
public struct CredentialExportLens: PreviewTextLens {
    public init() {}

    public func findings(in text: String, request: PreviewLensRequest, context: RequestContext) throws -> [PreviewFinding] {
        try context.checkpoint()
        switch request.formatID {
        case .csv: return try Self.delimited(text, dialect: .comma, context: context)
        case .tsv: return try Self.delimited(text, dialect: .tab, context: context)
        case .json:
            guard let root = try LensJSON.parse(text, context: context) else { return [] }
            return Self.json(root)
        default: return []
        }
    }

    // MARK: CSV and TSV

    private static func delimited(_ text: String, dialect: DelimitedRecords.Dialect, context: RequestContext) throws -> [PreviewFinding] {
        let bytes = Array(text.utf8)
        let limits = DelimitedRecords.Limits(maxRecords: context.budget.maxTextLines,
                                             maxFieldsPerRecord: context.budget.maxJSONNodes,
                                             maxFieldBytes: context.budget.maxLineUTF8Bytes)
        var isExport = false
        var logins = 0
        do {
            _ = try DelimitedRecords.scan(bytes, dialect: dialect, limits: limits, checkpoint: { try context.checkpoint() }) { record, fields in
                if record == 0 {
                    isExport = CredentialExportHeaders.isCredentialExport(
                        header: fields.map { DelimitedRecords.text(of: $0, in: bytes) })
                    return isExport ? .proceed : .stop
                }
                if fields.contains(where: { !$0.content.isEmpty }) { logins += 1 }
                return .proceed
            }
        } catch PreviewFailure.deadlineExceeded {
            throw PreviewFailure.deadlineExceeded
        } catch is PreviewFailure {
            return []
        }
        guard isExport, logins > 0 else { return [] }
        return [PreviewFinding(kind: .exportReadableLogins, count: logins, lines: [1])]
    }

    // MARK: JSON

    private static func json(_ root: LensJSONNode) -> [PreviewFinding] {
        if let logins = bitwardenLogins(root), !logins.isEmpty {
            return [PreviewFinding(kind: .exportReadableLogins, count: logins.count, lines: logins)]
        }
        guard let secrets = oneTimeCodeSecrets(root), !secrets.isEmpty else { return [] }
        return [PreviewFinding(kind: .exportReadableCodeSecrets, count: secrets.count, lines: secrets)]
    }

    /// The lines of the `login` keys of an unencrypted Bitwarden export.
    private static func bitwardenLogins(_ root: LensJSONNode) -> [Int]? {
        guard root.member("encrypted")?.value.bool == false, let items = root.member("items")?.value.elements else { return nil }
        return items.compactMap { item in
            guard let login = item.member("login"), login.value.members?.isEmpty == false else { return nil }
            return login.line
        }
    }

    /// The lines of the secrets of an unencrypted Aegis, 2FAS or andOTP export.
    private static func oneTimeCodeSecrets(_ root: LensJSONNode) -> [Int]? {
        if let entries = root.elements {
            // andOTP: a top-level array of entries.
            return entries.compactMap { entry in
                guard let kind = entry.member("type")?.value.string, isOneTimeCodeType(kind),
                      let secret = entry.member("secret"), secret.value.hasContent else { return nil }
                return secret.line
            }
        }
        if let database = root.member("db")?.value, let entries = database.member("entries")?.value.elements,
           let slots = root.member("header")?.value.member("slots"), slots.value.isNull {
            // Aegis: plain only when the header declares no key slots.
            return entries.compactMap { entry in
                guard let secret = entry.member("info")?.value.member("secret"), secret.value.hasContent else { return nil }
                return secret.line
            }
        }
        if root.member("schemaVersion")?.value.number != nil, root.member("servicesEncrypted") == nil,
           let services = root.member("services")?.value.elements {
            // 2FAS: an encrypted export keeps its services in `servicesEncrypted` and leaves this list empty.
            return services.compactMap { service in
                guard let secret = service.member("secret"), secret.value.hasContent else { return nil }
                return secret.line
            }
        }
        return nil
    }

    /// ASCII case folding only: `uppercased()` would turn the long s of "ſteam" into an S.
    private static func isOneTimeCodeType(_ type: String) -> Bool {
        let folded = String(decoding: type.utf8.map { (97...122).contains($0) ? $0 - 32 : $0 }, as: UTF8.self)
        return ["TOTP", "HOTP", "STEAM"].contains { folded.equalsExactly($0) }
    }
}
