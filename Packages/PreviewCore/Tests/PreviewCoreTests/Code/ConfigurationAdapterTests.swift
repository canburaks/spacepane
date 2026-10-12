import Foundation
import Synchronization
import Testing
import PreviewContracts
import PreviewCore
import PreviewFormats

private let secret = "synthetic-secret-value"

/// Parses with the adapter and applies the shared privacy stage, as the pipeline does.
private func concealed(_ adapter: some FormatAdapter, _ text: String, name: String? = nil,
                       budget: PreviewBudget = .standard) throws -> (parsed: ParsedTextDocument, safe: SafeText) {
    var context = RequestContext(budget: budget)
    if let name { context.nameHint = PreviewNameHint(url: URL(fileURLWithPath: "/tmp/" + name)) }
    let parsed = try adapter.parse(DecodedText(text: text, encoding: .utf8, byteCount: text.utf8.count), context: context)
    return (parsed, try DefaultPrivacyFilter().filter(parsed, context: context))
}

@Suite("INI configuration adapter")
struct INIConfigurationAdapterTests {
    private func safe(_ text: String, name: String = "settings.ini") throws -> SafeText {
        try concealed(INIConfigurationAdapter(), text, name: name).safe
    }

    @Test func normalFileKeepsItsExactSourceAndSyntax() throws {
        let source = "; comment\n[server]\nhost = localhost\nport: 8080\n\n[logging]\nlevel=info\n"
        let (parsed, safeText) = try concealed(INIConfigurationAdapter(), source)
        #expect(parsed.text == source)
        #expect(parsed.syntax == .ini)
        // Structural privacy: an empty placeholder value must not conceal the rest of the file.
        #expect(parsed.usesStructuredPrivacy)
        #expect(safeText.text == source)
        #expect(safeText.redactionCount == 0)
    }

    @Test(arguments: [
        "password = \(secret)",
        "db_password: \(secret)",
        "API_KEY=\(secret)",
        "secret_key = \(secret)",
        "  token = \(secret)  ",
        "[auth]\npassword=\(secret)\nuser=visible"
    ]) func secretAssignmentsAreConcealed(source: String) throws {
        let result = try safe(source)
        #expect(!result.text.contains(secret))
        #expect(result.redactionCount > 0)
    }

    @Test func npmrcTokenAndPasswordFormsAreConcealed() throws {
        let source = """
        //registry.npmjs.org/:_authToken=\(secret)
        //registry.example.test/:_auth=\(secret)
        //registry.example.test/:_password=\(secret)
        //registry.example.test/:username=visible-user
        registry=https://registry.npmjs.org/
        always-auth=true
        """
        let result = try safe(source, name: ".npmrc")
        #expect(!result.text.contains(secret))
        #expect(result.text.contains("visible-user"))
        #expect(result.text.contains("registry=https://registry.npmjs.org/"))
        #expect(result.text.contains("_authToken="))
    }

    @Test func pypircPasswordIsConcealedAndUsernameIsNot() throws {
        let source = "[distutils]\nindex-servers = pypi\n\n[pypi]\nusername = __token__\npassword = \(secret)\n"
        let result = try safe(source, name: ".pypirc")
        #expect(!result.text.contains(secret))
        #expect(result.text.contains("username = __token__"))
    }

    @Test func continuationLinesOfASecretAreConcealed() throws {
        let indented = try safe("password =\n    \(secret)-line-one\n    \(secret)-line-two\nvisible = yes\n")
        #expect(!indented.text.contains(secret))
        #expect(indented.text.contains("visible = yes"))
        let backslash = try safe("secret = first \\\n\(secret)-continued\nvisible = yes\n", name: "a.properties")
        #expect(!backslash.text.contains(secret))
        #expect(backslash.text.contains("visible = yes"))
        // CRLF line endings keep the continuation attached.
        let crlf = try safe("password =\r\n    \(secret)\r\nvisible = yes\r\n")
        #expect(!crlf.text.contains(secret))
        #expect(crlf.text.contains("visible = yes"))
    }

    @Test func credentialsEmbeddedInUrlsAreConcealedButHostsStay() throws {
        let result = try safe("[remote]\nurl = https://deploy:\(secret)@git.example.test/team/repo.git\nssh = ssh://git@git.example.test/repo\n",
                              name: ".gitconfig")
        #expect(!result.text.contains(secret))
        #expect(result.text.contains("@git.example.test/team/repo.git"))
        // A user name without a password is not a secret.
        #expect(result.text.contains("ssh://git@git.example.test/repo"))
        let header = try safe("[credential \"https://user:\(secret)@host.example.test\"]\nhelper = store\n", name: ".gitconfig")
        #expect(!header.text.contains(secret))
    }

    @Test func whitespaceDirectivesWithSecretNamesAreConcealed() throws {
        let result = try safe("port 6379\nrequirepass \(secret)\nmasterauth \(secret)\nbind 127.0.0.1\nproxy_pass http://upstream.test\n",
                              name: "redis.conf")
        #expect(!result.text.contains(secret))
        #expect(result.text.contains("bind 127.0.0.1"))
        // Names that merely contain "pass" stay readable.
        #expect(result.text.contains("proxy_pass http://upstream.test"))
    }

    @Test func bearerTokensAndRecognizableKeysAreConcealedWithoutAKey() throws {
        let result = try safe("header = Authorization: Bearer abcdefghijklmnop\nnote = ghp_abcdefghijklmnopqrstuvwxyz0123456789\n")
        #expect(!result.text.contains("abcdefghijklmnop"))
        #expect(!result.text.contains("ghp_abcdefghijklmnopqrstuvwxyz"))
    }

    @Test func anEmptyPlaceholderValueDoesNotConcealTheRestOfTheFile() throws {
        let source = "[pypi]\nusername = __token__\npassword =\n\n[other]\nhost = visible.example.test\n"
        let result = try safe(source)
        #expect(result.text.contains("host = visible.example.test"))
        #expect(result.text.contains("password ="))
    }

    @Test func ordinaryConfigurationIsNeverOverConcealed() throws {
        let source = "[core]\neditor = vim\nbypass = true\ncompass = north\nkeyboard = us\n"
        let result = try safe(source)
        #expect(result.text == source)
        #expect(result.redactionCount == 0)
    }

    @Test func budgetsCancellationAndRangesAreEnforced() async throws {
        let adapter = INIConfigurationAdapter()
        let big = DecodedText(text: String(repeating: "a", count: 65), encoding: .utf8, byteCount: 65)
        #expect(throws: PreviewFailure.inputTooLarge) { try adapter.parse(big, context: .init(budget: .init(maxInputBytes: 64))) }
        #expect(throws: PreviewFailure.lineTooLong) { try adapter.parse(big, context: .init(budget: .init(maxLineUTF8Bytes: 64))) }
        // More concealed ranges than the shared stage accepts conceal the whole text instead of failing.
        let many = (0..<30).map { "password = v\($0)" }.joined(separator: "\n")
        let tight = PreviewBudget(maxJSONNodes: 10)
        let result = try concealed(adapter, many, budget: tight)
        #expect(!result.safe.text.contains("v29"))
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try adapter.parse(.init(text: "", encoding: .utf8, byteCount: 0), context: .init(budget: .standard)); return false }
            catch is CancellationError { return true } catch { return false }
        }
        #expect(await task.value)
    }

    @Test func partialReadPolicyIsLineBased() {
        #expect(INIConfigurationAdapter().textInputPolicy == .leadingRecords(.line))
    }
}

@Suite("Embedded secret ranges through the source adapter")
struct EmbeddedSecretTests {
    private func safe(_ text: String, name: String) throws -> SafeText {
        try concealed(SourceCodeAdapter(), text, name: name).safe
    }

    @Test func connectionStringsInCodeAreConcealed() throws {
        let result = try safe("let url = \"postgres://app:\(secret)@db.example.test:5432/main\"\nlet host = \"db.example.test\"\n", name: "a.swift")
        #expect(!result.text.contains(secret))
        #expect(result.text.contains("@db.example.test:5432/main"))
        #expect(result.text.contains("let host"))
    }

    @Test(arguments: [
        "curl --password \(secret) https://example.test",
        "curl --token=\(secret) https://example.test",
        "deploy --api-key \"\(secret)\" --verbose",
        "run.sh --client-secret='\(secret)'"
    ]) func secretCommandLineFlagsAreConcealedInShellFiles(line: String) throws {
        let result = try safe(line + "\n", name: "deploy.sh")
        #expect(!result.text.contains(secret))
        #expect(result.redactionCount > 0)
    }

    @Test func flagsThatAreNotSecretsStayReadable() throws {
        let source = "tool --verbose --output build --retries 3 -v\n"
        let result = try safe(source, name: "build.sh")
        #expect(result.text == source)
    }

    @Test func dockerEnvironmentWithoutAnEqualsSignIsConcealed() throws {
        let result = try safe("FROM scratch\nENV API_TOKEN \(secret)\nENV PORT 8080\nARG DB_PASSWORD \(secret)\n", name: "Dockerfile")
        #expect(!result.text.contains(secret))
        #expect(result.text.contains("ENV PORT 8080"))
    }

    @Test func sourceLanguageComesFromTheNameHintOnly() throws {
        let (swift, _) = try concealed(SourceCodeAdapter(), "let x = 1\n", name: "a.swift")
        #expect(swift.sourceLanguage == .swift)
        let (named, _) = try concealed(SourceCodeAdapter(), "all:\n", name: "Makefile")
        #expect(named.sourceLanguage == .makefile)
        let (none, _) = try concealed(SourceCodeAdapter(), "x\n")
        #expect(none.sourceLanguage == nil)
    }
}
