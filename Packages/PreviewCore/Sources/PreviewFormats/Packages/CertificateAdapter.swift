import Foundation
import CryptoKit
import Security
import PreviewContracts

/// Summarizes X.509 certificates in DER or PEM form.
///
/// Certificates are public documents, so their fields are shown as stored. Trust is never evaluated and
/// revocation is never checked. PEM files that also carry private keys (or consist only of one) are
/// reported as "private key present (hidden)": a private-key block is located by its label and skipped,
/// never base64-decoded, parsed, summarized or copied into any representation.
public struct CertificateAdapter: BinaryFormatAdapter {
    static let maximumCertificates = 32
    static let maximumCertificateBytes = 98_304
    static let maximumBlocks = 64

    private let now: @Sendable () -> Date

    public init() { self.init(now: { Date() }) }
    init(now: @escaping @Sendable () -> Date) { self.now = now }

    public func parse(_ input: FileBytes, context: RequestContext) throws -> ParsedTextDocument {
        try context.checkpoint()
        let bytes = [UInt8](input.data)
        guard !bytes.isEmpty else { throw PreviewFailure.malformedDocument }
        let scan = try PEMScanner.scan(bytes, maximumBlocks: Self.maximumBlocks, context: context)
        // One reading of the clock decides every `expired` flag and every validity finding of this file.
        let current = now()
        var fields = SummaryFields()
        if scan.blocks.isEmpty {
            // No armor: the file must be exactly one DER certificate.
            guard bytes.count <= Self.maximumCertificateBytes, let details = CertificateInspector.details(der: input.data, now: current) else {
                throw PreviewFailure.malformedDocument
            }
            fields.text("encoding", "DER")
            fields.number("certificateCount", 1)
            fields.add("certificates", .array([details.summaryValue()]))
            return try ValidityFindings.document(fields.value, findings: ValidityFindings.certificates([details], now: current),
                                                 context: context)
        }

        var certificates: [SummaryValue] = []
        var inspected: [CertificateDetails] = []
        var unreadable = 0
        var privateKeyKinds: [String] = []
        var otherBlocks = 0
        var certificateBlocks = 0
        for block in scan.blocks {
            try context.checkpoint()
            if block.isPrivateKey {
                // Only the label is recorded. The body is not decoded, inspected or retained.
                privateKeyKinds.append(block.label)
            } else if block.isCertificate {
                certificateBlocks += 1
                guard certificates.count < Self.maximumCertificates else { continue }
                if block.isTerminated,
                   let der = PEMScanner.decodeBase64(bytes[block.body], maximumDecodedBytes: Self.maximumCertificateBytes),
                   let details = CertificateInspector.details(der: der, now: current) {
                    certificates.append(details.summaryValue())
                    inspected.append(details)
                } else {
                    unreadable += 1
                }
            } else {
                otherBlocks += 1
            }
        }
        guard certificateBlocks > 0 || !privateKeyKinds.isEmpty || otherBlocks > 0 else { throw PreviewFailure.malformedDocument }
        fields.text("encoding", "PEM")
        if certificateBlocks > 0 { fields.number("certificateCount", certificateBlocks) }
        if !certificates.isEmpty { fields.add("certificates", .array(certificates)) }
        if unreadable > 0 { fields.number("unreadableCertificates", unreadable) }
        if !privateKeyKinds.isEmpty {
            fields.number("privateKeys", privateKeyKinds.count)
            fields.list("privateKeyKinds", privateKeyKinds)
        }
        if otherBlocks > 0 { fields.number("otherBlocks", otherBlocks) }
        fields.flag("partial", scan.truncated || certificateBlocks > certificates.count + unreadable)
        return try ValidityFindings.document(fields.value, findings: ValidityFindings.certificates(inspected, now: current),
                                             context: context)
    }
}

/// Validity findings of certificates and provisioning profiles (decision 029), judged against the adapter's
/// injected clock. They are whole-file facts: no lines, no source values, only kinds, counts and whole days.
enum ValidityFindings {
    /// How close an end date that has not passed must be, in whole days, to be reported as ending soon. The
    /// one threshold of the certificate and profile adapters; the boundary day itself counts as soon.
    static let expiresSoonDays = 30
    /// RSA keys with a modulus shorter than this are weak. Security reports the modulus size in bits.
    static let minimumRSAKeyBits = 2_048

    private static let secondsPerDay: TimeInterval = 86_400

    /// Where a validity end stands against the clock.
    enum Standing: Equatable {
        case valid
        /// Not yet passed and within `expiresSoonDays`: whole days left, rounded up, at least one.
        case endsSoon(days: Int)
        case expired

        /// An end date is still valid through that very second, so it is expired only once the clock is past it.
        init(end: Date, now: Date) {
            let remaining = end.timeIntervalSince(now)
            if remaining < 0 {
                self = .expired
            } else if remaining <= TimeInterval(ValidityFindings.expiresSoonDays) * ValidityFindings.secondsPerDay {
                self = .endsSoon(days: max(1, Int((remaining / ValidityFindings.secondsPerDay).rounded(.up))))
            } else {
                self = .valid
            }
        }
    }

    /// The findings for every inspected certificate, one per kind with the number of certificates it
    /// applies to, in the order of the kind declarations. Expiry is judged on the end date, not before
    /// the start: a certificate can be both not yet valid and ending soon. A certificate whose dates the
    /// system parser did not give, or whose RSA key it did not size, adds nothing.
    static func certificates(_ certificates: [CertificateDetails], now: Date) -> [PreviewFinding] {
        var expired = 0
        var notYetValid = 0
        var weakKeys = 0
        var endingSoon = 0
        var soonestDays: Int?
        for certificate in certificates {
            if let end = certificate.notAfter {
                switch Standing(end: end, now: now) {
                case .expired: expired += 1
                case .endsSoon(let days):
                    endingSoon += 1
                    soonestDays = min(soonestDays ?? days, days)
                case .valid: break
                }
            }
            if let start = certificate.notBefore, start > now { notYetValid += 1 }
            if certificate.hasWeakRSAKey { weakKeys += 1 }
        }
        var findings: [PreviewFinding] = []
        if expired > 0 { findings.append(PreviewFinding(kind: .certificateExpired, count: expired)) }
        if endingSoon > 0, let soonestDays {
            findings.append(PreviewFinding(kind: .certificateExpiresSoon, count: endingSoon, detail: .days(soonestDays)))
        }
        if notYetValid > 0 { findings.append(PreviewFinding(kind: .certificateNotYetValid, count: notYetValid)) }
        if weakKeys > 0 { findings.append(PreviewFinding(kind: .certificateWeakKey, count: weakKeys)) }
        return findings
    }

    /// The summary document with its findings. `PackageSummary.document` is shared and carries none, so this
    /// writes the same document (structured privacy, JSON syntax, app-made summary origin, no images) through
    /// `SummaryWriter`, which accepts them.
    static func document(_ root: SummaryValue, findings: [PreviewFinding], context: RequestContext) throws -> ParsedTextDocument {
        var writer = SummaryWriter(context: context)
        return try writer.document(root, findings: findings)
    }
}

/// Facts read from one parsed certificate. Each is optional because the system parser can decline any of them.
struct CertificateDetails: Equatable {
    var subject: String?
    var issuer: String?
    var serialNumber: String?
    var notBefore: Date?
    var notAfter: Date?
    var isExpired: Bool?
    var publicKeyAlgorithm: String?
    var publicKeyBits: Int?
    var alternativeNames: [String] = []
    var sha256: String
    var sha1: String

    /// RSA with a modulus shorter than `ValidityFindings.minimumRSAKeyBits`. Unknown is not weak: a key the
    /// system parser declined to size, and every other algorithm, never qualify.
    var hasWeakRSAKey: Bool {
        guard publicKeyAlgorithm == CertificateInspector.rsaAlgorithmName, let publicKeyBits else { return false }
        return publicKeyBits < ValidityFindings.minimumRSAKeyBits
    }

    func summaryValue() -> SummaryValue {
        var fields = SummaryFields()
        fields.text("subject", subject)
        fields.text("issuer", issuer)
        fields.text("serialNumber", serialNumber)
        fields.date("notBefore", notBefore)
        fields.date("notAfter", notAfter)
        fields.flag("expired", isExpired)
        fields.text("publicKeyAlgorithm", publicKeyAlgorithm)
        fields.number("publicKeyBits", publicKeyBits)
        fields.list("subjectAlternativeNames", alternativeNames)
        fields.text("sha256", sha256)
        fields.text("sha1", sha1)
        return fields.value
    }
}

enum CertificateInspector {
    private static let maximumAlternativeNames = 64

    /// Distinguished-name attribute types by dotted OID; others print as the OID itself.
    private static let nameAttributes: [String: String] = [
        "2.5.4.3": "CN", "2.5.4.5": "serialNumber", "2.5.4.6": "C", "2.5.4.7": "L", "2.5.4.8": "ST",
        "2.5.4.9": "street", "2.5.4.10": "O", "2.5.4.11": "OU", "2.5.4.12": "title", "2.5.4.17": "postalCode",
        "1.2.840.113549.1.9.1": "emailAddress", "0.9.2342.19200300.100.1.25": "DC", "0.9.2342.19200300.100.1.1": "UID"
    ]
    /// The name reported for `rsaEncryption` keys, which the weak-key finding matches. RSA-PSS keys are named
    /// apart because Security does not size them.
    static let rsaAlgorithmName = "RSA"
    private static let publicKeyAlgorithms: [String: (name: String, bits: Int?)] = [
        "1.2.840.113549.1.1.1": (rsaAlgorithmName, nil), "1.2.840.113549.1.1.10": ("RSA-PSS", nil),
        "1.2.840.10045.2.1": ("EC", nil), "1.2.840.10040.4.1": ("DSA", nil),
        "1.3.101.112": ("Ed25519", 256), "1.3.101.113": ("Ed448", 456),
        "1.3.101.110": ("X25519", 255), "1.3.101.111": ("X448", 448)
    ]
    private static let alternativeNameKinds: [String: String] = [
        "DNS Name": "DNS", "IP Address": "IP", "Email Address": "email", "URI": "URI",
        "Uniform Resource Identifier": "URI", "Registered ID": "RID", "Directory Name": "DirName"
    ]

    /// Parses one DER certificate through Security. Returns `nil` when the system rejects the encoding.
    static func details(der: Data, now: Date) -> CertificateDetails? {
        guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else { return nil }
        var details = CertificateDetails(sha256: fingerprint(SHA256.hash(data: der)), sha1: fingerprint(Insecure.SHA1.hash(data: der)))
        details.serialNumber = (SecCertificateCopySerialNumberData(certificate, nil) as Data?)?.hexadecimal(separator: ":")
        let keys = [kSecOIDX509V1SubjectName, kSecOIDX509V1IssuerName, kSecOIDX509V1ValidityNotBefore,
                    kSecOIDX509V1ValidityNotAfter, kSecOIDSubjectAltName, kSecOIDX509V1SubjectPublicKeyAlgorithm] as CFArray
        let values = SecCertificateCopyValues(certificate, keys, nil) as? [String: [String: Any]] ?? [:]
        details.subject = distinguishedName(values[kSecOIDX509V1SubjectName as String]) ?? SecCertificateCopySubjectSummary(certificate) as String?
        details.issuer = distinguishedName(values[kSecOIDX509V1IssuerName as String])
        details.notBefore = absoluteDate(values[kSecOIDX509V1ValidityNotBefore as String])
        details.notAfter = absoluteDate(values[kSecOIDX509V1ValidityNotAfter as String])
        details.isExpired = details.notAfter.map { $0 < now }
        details.alternativeNames = alternativeNames(values[kSecOIDSubjectAltName as String])
        let oid = properties(values[kSecOIDX509V1SubjectPublicKeyAlgorithm as String])
            .first { ($0[kSecPropertyKeyLabel as String] as? String) == "Algorithm" }
            .flatMap { $0[kSecPropertyKeyValue as String] as? String }
        if let oid {
            let known = publicKeyAlgorithms[oid]
            details.publicKeyAlgorithm = known?.name ?? oid
            details.publicKeyBits = known?.bits
        }
        if let key = SecCertificateCopyKey(certificate), let attributes = SecKeyCopyAttributes(key) as? [String: Any],
           let bits = (attributes[kSecAttrKeySizeInBits as String] as? NSNumber)?.intValue, bits > 0 {
            details.publicKeyBits = bits
        }
        return details
    }

    private static func fingerprint<D: Digest>(_ digest: D) -> String {
        Data(digest).hexadecimal(separator: ":")
    }

    private static func properties(_ entry: [String: Any]?) -> [[String: Any]] {
        entry?[kSecPropertyKeyValue as String] as? [[String: Any]] ?? []
    }

    private static func distinguishedName(_ entry: [String: Any]?) -> String? {
        let parts = properties(entry).compactMap { attribute -> String? in
            guard let oid = attribute[kSecPropertyKeyLabel as String] as? String,
                  let value = attribute[kSecPropertyKeyValue as String] as? String, !value.isEmpty else { return nil }
            return "\(nameAttributes[oid] ?? oid)=\(PackageSummary.clipped(value, limit: 256))"
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private static func absoluteDate(_ entry: [String: Any]?) -> Date? {
        guard let seconds = (entry?[kSecPropertyKeyValue as String] as? NSNumber)?.doubleValue else { return nil }
        return Date(timeIntervalSinceReferenceDate: seconds)
    }

    private static func alternativeNames(_ entry: [String: Any]?) -> [String] {
        var names: [String] = []
        for property in properties(entry) {
            guard let label = property[kSecPropertyKeyLabel as String] as? String, label != "Critical",
                  let value = property[kSecPropertyKeyValue as String] as? String, !value.isEmpty else { continue }
            names.append("\(alternativeNameKinds[label] ?? label): \(PackageSummary.clipped(value, limit: 256))")
            if names.count == maximumAlternativeNames { break }
        }
        return names
    }
}
