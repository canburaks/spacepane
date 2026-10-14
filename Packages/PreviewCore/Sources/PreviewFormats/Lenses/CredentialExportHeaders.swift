/// The header rule for password-manager CSV exports (decision 029).
///
/// A first line is the header of a credential export when it names a password column, a user column
/// (username, login or email) and an address column (url, uri or website), each as a complete name.
/// Every export header listed in `CredentialExportLensTests` (Bitwarden, 1Password, Apple Passwords and
/// Safari, Chrome, Edge and Brave, Firefox, LastPass, Dashlane, Proton Pass, KeePassXC, NordPass) satisfies
/// it, so the rule is the only recognition there is: a table of exact headers could add no case.
///
/// Names are matched after folding case and turning every run of other characters into one underscore,
/// so `Website Address`, `web-site` and `WEBSITE_ADDRESS` agree. A name must match whole: `password_hint`
/// and `passwordless` are not password columns.
enum CredentialExportHeaders {
    private static let passwordColumns: Set<String> = ["password", "passwd", "pwd", "login_password", "loginpassword"]
    private static let userColumns: Set<String> = [
        "username", "user_name", "user", "userid", "user_id", "login", "login_name", "login_username", "login_email",
        "email", "e_mail", "email_address"
    ]
    private static let addressColumns: Set<String> = [
        "url", "urls", "uri", "website", "web_site", "site", "web_address", "website_address", "login_uri", "login_url"
    ]

    static func isCredentialExport(header columns: [String]) -> Bool {
        var hasPassword = false
        var hasUser = false
        var hasAddress = false
        for column in columns {
            let name = normalized(column)
            hasPassword = hasPassword || passwordColumns.contains(name)
            hasUser = hasUser || userColumns.contains(name)
            hasAddress = hasAddress || addressColumns.contains(name)
        }
        return hasPassword && hasUser && hasAddress
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
