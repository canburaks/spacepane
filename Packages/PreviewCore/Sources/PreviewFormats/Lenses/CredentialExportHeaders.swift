/// The header rule for password-manager CSV exports (decision 029).
///
/// A first line is the header of a credential export when it names a password column, a user column
/// (username, login or email) and an address column (url, uri or website), each as a complete name.
/// The lens counts the records whose password cell is not empty, so a secure note or a card that a
/// manager writes into the same file is not counted as a login.
/// Every export header listed in `CredentialExportLensTests` (Bitwarden, 1Password, Apple Passwords and
/// Safari, Chrome, Edge and Brave, Firefox, LastPass, Dashlane, Proton Pass, KeePassXC, NordPass) satisfies
/// it, so the rule is the only recognition there is: a table of exact headers could add no case.
///
/// Names are matched after folding case and turning every run of other characters into one underscore,
/// so `Website Address`, `web-site` and `WEBSITE_ADDRESS` agree. A name must match whole: `password_hint`
/// and `passwordless` are not password columns.
enum CredentialExportHeaders {
    private static let passwordNames: Set<String> = ["password", "passwd", "pwd", "login_password", "loginpassword"]
    private static let userNames: Set<String> = [
        "username", "user_name", "user", "userid", "user_id", "login", "login_name", "login_username", "login_email",
        "email", "e_mail", "email_address"
    ]
    private static let addressNames: Set<String> = [
        "url", "urls", "uri", "website", "web_site", "site", "web_address", "website_address", "login_uri", "login_url"
    ]

    /// The positions of the password columns when the header is a credential export's, otherwise `nil`.
    static func passwordColumns(inHeader columns: [String]) -> [Int]? {
        var passwords: [Int] = []
        var hasUser = false
        var hasAddress = false
        for (index, column) in columns.enumerated() {
            let name = normalized(column)
            if passwordNames.contains(name) { passwords.append(index) }
            hasUser = hasUser || userNames.contains(name)
            hasAddress = hasAddress || addressNames.contains(name)
        }
        return !passwords.isEmpty && hasUser && hasAddress ? passwords : nil
    }

    /// ASCII letters and digits lowercased, every other run of characters one underscore, ends trimmed.
    static func normalized(_ column: String) -> String {
        var name = ""
        var pendingSeparator = false
        for byte in column.utf8 {
            let folded: UInt8? = switch byte {
            case 65...90: byte + 32
            case 97...122, 48...57: byte
            default: nil
            }
            guard let folded else { pendingSeparator = !name.isEmpty; continue }
            if pendingSeparator { name.append("_"); pendingSeparator = false }
            name.unicodeScalars.append(Unicode.Scalar(folded))
        }
        return name
    }
}
