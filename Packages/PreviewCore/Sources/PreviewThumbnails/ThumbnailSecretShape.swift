import Foundation

/// A thumbnail-only, deliberately over-inclusive guess that a document may hold a secret the privacy
/// filter did not conceal (decision 027, D14). It runs on the already concealed text and on the file's
/// name before anything is drawn, and a hit withholds the whole thumbnail, pictures included. A false
/// positive costs only the glyph; a miss would put a secret into Finder's durable thumbnail cache, which
/// this product never clears.
///
/// What counts:
/// - URL user information: `://` followed by `user:password@`. The user may be empty, the password may
///   not; a user alone (`ssh://git@host`) is a name, not a credential.
/// - A private-key marker: `-----BEGIN`, or the same text in base64 (`LS0tLS1CRUdJTi`).
/// - A token-like run: 32 or more consecutive ASCII letters and digits that include an upper-case letter,
///   a lower-case letter and a digit. A hexadecimal digest (a git commit hash, a SHA-256) has a single
///   letter case, so it never counts; a UUID never reaches 32 because its hyphens break the run.
/// - The file name: `secret`, `credential`, `token`, `passw`, `kubeconfig`, `.netrc`, `id_rsa` or
///   `id_ed25519` anywhere in it, in any letter case, or `config.json` directly inside a `.docker` folder.
///
/// The name decides withholding only and is never drawn. The text scan examines at most the first 256 KiB
/// of UTF-8, in place when the storage is contiguous, so its cost does not grow with the file.
enum ThumbnailSecretShape {
    /// Bytes of text examined. The thumbnail budget already bounds the text; this keeps the work fixed.
    static let maximumScannedBytes = 262_144
    /// Shortest run of ASCII letters and digits that counts as token-like when it mixes both letter cases
    /// and at least one digit.
    static let minimumTokenRun = 32
    /// How far past `://` the scan looks for the `@` that ends user information.
    static let maximumUserInformationBytes = 256

    private static let nameFragments = ["secret", "credential", "token", "passw", "kubeconfig", ".netrc", "id_rsa", "id_ed25519"]
    private static let dockerFolderName = ".docker"
    private static let dockerConfigName = "config.json"
    private static let privateKeyMarker = Array("-----BEGIN".utf8)
    private static let base64PrivateKeyMarker = Array("LS0tLS1CRUdJTi".utf8)

    /// True when the concealed `text` or the names look credential-bearing. `fileName` is the request's last
    /// path component and `parentFolderName` the name of its folder; neither is ever drawn.
    static func mayHoldSecret(_ text: Substring, fileName: String, parentFolderName: String?) -> Bool {
        nameMayHoldSecret(fileName: fileName, parentFolderName: parentFolderName) || textMayHoldSecret(text)
    }

    // MARK: Names

    private static func nameMayHoldSecret(fileName: String, parentFolderName: String?) -> Bool {
        let name = fileName.lowercased()
        if nameFragments.contains(where: { name.contains($0) }) { return true }
        return name == dockerConfigName && parentFolderName?.lowercased() == dockerFolderName
    }

    // MARK: Text

    private static func textMayHoldSecret(_ text: Substring) -> Bool {
        let window = text.utf8.prefix(maximumScannedBytes)
        if let found = window.withContiguousStorageIfAvailable({ scan($0) }) { return found }
        return Array(window).withUnsafeBufferPointer { scan($0) }
    }

    /// One forward pass. Every rule matches ASCII bytes only, so a multi-byte sequence, including one the
    /// window cuts in half, can never produce a match; the lookahead of each rule is bounded.
    private static func scan(_ bytes: UnsafeBufferPointer<UInt8>) -> Bool {
        var runLength = 0
        var hasUpper = false
        var hasLower = false
        var hasDigit = false
        for index in bytes.indices {
            let byte = bytes[index]
            switch byte {
            case UInt8(ascii: "A")...UInt8(ascii: "Z"):
                runLength += 1
                hasUpper = true
            case UInt8(ascii: "a")...UInt8(ascii: "z"):
                runLength += 1
                hasLower = true
            case UInt8(ascii: "0")...UInt8(ascii: "9"):
                runLength += 1
                hasDigit = true
            default:
                runLength = 0
                hasUpper = false
                hasLower = false
                hasDigit = false
            }
            if runLength >= minimumTokenRun, hasUpper, hasLower, hasDigit { return true }
            // The marker's last byte decides: `-----BEGIN` ends in `N`, so look back from the `B` at index.
            if byte == UInt8(ascii: "B"), matches(privateKeyMarker, in: bytes, at: index - 5) { return true }
            if byte == UInt8(ascii: "L"), matches(base64PrivateKeyMarker, in: bytes, at: index) { return true }
            if byte == UInt8(ascii: ":"), hasUserInformation(in: bytes, colonAt: index) { return true }
        }
        return false
    }

    private static func matches(_ pattern: [UInt8], in bytes: UnsafeBufferPointer<UInt8>, at start: Int) -> Bool {
        guard start >= 0, start + pattern.count <= bytes.count else { return false }
        for offset in pattern.indices where bytes[start + offset] != pattern[offset] { return false }
        return true
    }

    /// `://` at the colon, then user information that holds a colon and a non-empty password before its
    /// closing `@`. The scan stops at the first byte that cannot be part of user information, so it never
    /// leaves the authority and each `://` costs at most `maximumUserInformationBytes`.
    private static func hasUserInformation(in bytes: UnsafeBufferPointer<UInt8>, colonAt colon: Int) -> Bool {
        let start = colon + 3
        guard start < bytes.count, bytes[colon + 1] == UInt8(ascii: "/"), bytes[colon + 2] == UInt8(ascii: "/") else {
            return false
        }
        var passwordStart: Int?
        let limit = min(bytes.count, start + maximumUserInformationBytes)
        var position = start
        while position < limit {
            let byte = bytes[position]
            if byte == UInt8(ascii: "@") {
                guard let firstPasswordByte = passwordStart else { return false }
                return position > firstPasswordByte
            }
            if byte == UInt8(ascii: ":") {
                if passwordStart == nil { passwordStart = position + 1 }
            } else if endsUserInformation(byte) {
                return false
            }
            position += 1
        }
        return false
    }

    /// Bytes that cannot appear in a URL's user information: controls and space, the delimiters that end
    /// an authority, quotes and brackets that end a URL in prose or code, and the characters a URL forbids.
    private static func endsUserInformation(_ byte: UInt8) -> Bool {
        switch byte {
        case 0x00...0x20, 0x7F:
            true
        case UInt8(ascii: "/"), UInt8(ascii: "?"), UInt8(ascii: "#"), UInt8(ascii: "\""), UInt8(ascii: "'"),
             UInt8(ascii: "<"), UInt8(ascii: ">"), UInt8(ascii: "\\"), UInt8(ascii: "`"), UInt8(ascii: "["),
             UInt8(ascii: "]"), UInt8(ascii: "{"), UInt8(ascii: "}"), UInt8(ascii: "|"), UInt8(ascii: "^"):
            true
        default:
            false
        }
    }
}
