import Foundation
import Testing
import PreviewContracts
import PreviewCore
import PreviewFormats

@Suite("Q16 legacy privacy compatibility")
struct Q16PrivacyCompatibilityTests {
    @Test func boundedFieldWordsRetainPluralCredentialsAndOrdinaryStructuralNames() {
        for key in ["user_tokens", "userTokens", "TOKENS", "api_key", "cacheKey", "key_data", "requirepass", "masterauth", "proxy_pass_token", "NSStringLocalizedFormatKey_password", "NSStringFormatSpecTypeKey_token"] {
            #expect(SecretFieldPolicy.isSensitive(key), "Sensitive compatibility key \(key)")
        }
        for key in ["key", "key0", "key_42", "proxy_pass", "proxyPass", "public_key", "syntax_tokenizer", "NSStringLocalizedFormatKey", "NSStringFormatSpecTypeKey", "NSStringFormatValueTypeKey"] {
            #expect(!SecretFieldPolicy.isSensitive(key), "Ordinary compatibility key \(key)")
        }
    }

    @Test func pluralMetadataStaysReadableWithoutExemptingAdjacentCredentials() throws {
        let metadata = """
        <key>NSStringLocalizedFormatKey</key><string>%#@items@</string>
        <key>items</key><dict>
          <key>NSStringFormatSpecTypeKey</key><string>NSStringPluralRuleType</string>
          <key>NSStringFormatValueTypeKey</key><string>d</string>
          <key>one</key><string>one item</string><key>other</key><string>%d items</string>
        </dict>
        """
        func filter(extra: String) throws -> SafeText {
            let source = "<plist version=\"1.0\"><dict><key>item_count</key><dict>" + metadata + "</dict>" + extra + "</dict></plist>"
            let context = RequestContext(budget: .standard)
            let parsed = try PropertyListSourceAdapter().parse(.init(text: source, encoding: .utf8, byteCount: source.utf8.count), context: context)
            return try DefaultPrivacyFilter().filter(parsed, context: context)
        }
        let ordinary = try filter(extra: "")
        #expect(ordinary.redactionCount == 0)
        #expect(ordinary.text.contains("NSStringPluralRuleType"))
        #expect(ordinary.text.contains("%#@items@"))
        let concealed = try filter(extra: "<key>api_key</key><string>synthetic-plural-adjacent-credential</string>")
        let leaked = concealed.text.contains("synthetic-plural-adjacent-credential")
        #expect(!leaked)
        #expect(concealed.redactionCount == 1)
        #expect(concealed.text.contains("NSStringPluralRuleType"))
    }

    @Test func proxyRoutingDirectivesRetainHostsAndStillConcealActualCredentials() throws {
        func filter(_ source: String) throws -> SafeText {
            let context = RequestContext(budget: .standard)
            let parsed = try INIConfigurationAdapter().parse(.init(text: source, encoding: .utf8, byteCount: source.utf8.count), context: context)
            return try DefaultPrivacyFilter().filter(parsed, context: context)
        }
        let source = "proxy_pass http://upstream.example.test/path?q=ordinary;\n"
        let ordinary = try filter(source)
        #expect(ordinary.text == source)
        #expect(ordinary.redactionCount == 0)
        let assignment = "proxy_pass = http://upstream.example.test/path?q=ordinary;\n"
        let assigned = try filter(assignment)
        #expect(assigned.text == assignment)
        #expect(assigned.redactionCount == 0)
        let credential = try filter("proxy_pass https://app:synthetic-proxy-password@upstream.example.test;\nproxy_pass http://upstream.example.test?api_key=synthetic-proxy-query;\n")
        let leaked = credential.text.contains("synthetic-proxy-password") || credential.text.contains("synthetic-proxy-query")
        #expect(!leaked)
        #expect(credential.redactionCount == 2)
        #expect(credential.text.contains("@upstream.example.test"))
        let provider = "sk_test_" + String(repeating: "Aa1Bb2", count: 5)
        let shaped = try filter("proxy_pass http://upstream.example.test/" + provider + ";\n")
        let providerLeaked = shaped.text.contains(provider)
        #expect(!providerLeaked)
        #expect(shaped.redactionCount > 0)
        let nested = try filter("proxy_pass http://upstream.example.test password=synthetic-proxy-tail;\nproxy_pass_token=synthetic-proxy-field\n")
        let nestedLeaked = nested.text.contains("synthetic-proxy-tail") || nested.text.contains("synthetic-proxy-field")
        #expect(!nestedLeaked)
        #expect(nested.redactionCount == 2)
        let unknown = try filter("upstream_password http://synthetic-unknown-directive.example.test\n")
        let unknownLeaked = unknown.text.contains("synthetic-unknown-directive")
        #expect(!unknownLeaked)
    }

    @Test func escapedNewlinesDoNotExpandConcealmentOfAlreadyVisibleURLCredentials() throws {
        let source = #"{"note":"connect postgres://app:synthetic-url-compatible@db.example.test/main\n"}"#
        let context = RequestContext(budget: .standard)
        let parsed = try JSONSourceAdapter().parse(.init(text: source, encoding: .utf8, byteCount: source.utf8.count), context: context)
        let result = try DefaultPrivacyFilter().filter(parsed, context: context)
        #expect(result.text.contains("postgres://••••@db.example.test/main"))
        let leaked = result.text.contains("synthetic-url-compatible")
        #expect(!leaked)
        #expect(result.redactionCount == 1)
    }

    @Test(arguments: ["synthetic-visible-url", "synthetic-extra-url"])
    func oneVisibleURLCannotExemptAnEscapedDuplicateOrExtraCredential(password: String) throws {
        let source = #"{"note":"visible postgres://app:synthetic-visible-url@db.example.test/main encoded postgres:\u002f\u002fapp:"# + password + #"@other.example.test/main\n"}"#
        let context = RequestContext(budget: .standard)
        let parsed = try JSONSourceAdapter().parse(.init(text: source, encoding: .utf8, byteCount: source.utf8.count), context: context)
        let result = try DefaultPrivacyFilter().filter(parsed, context: context)
        let leaked = result.text.contains("synthetic-")
        #expect(!leaked)
        #expect(result.redactionCount > 0)
    }

    @Test func aVisibleURLCannotExemptADifferentEscapedCredentialGrammar() throws {
        let source = #"{"note":"visible postgres://app:synthetic-visible-url@db.example.test/main encoded \u0073k_test_SyntheticExtraQ16TokenAa1Bb2Cc3Dd4Ee5Ff6"}"#
        let context = RequestContext(budget: .standard)
        let parsed = try JSONSourceAdapter().parse(.init(text: source, encoding: .utf8, byteCount: source.utf8.count), context: context)
        let result = try DefaultPrivacyFilter().filter(parsed, context: context)
        let leaked = result.text.contains("SyntheticExtraQ16Token") || result.text.contains("synthetic-visible-url")
        #expect(!leaked)
        #expect(result.redactionCount > 0)
    }

    @Test func decodedURLAllowanceUsesExactCodeUnitsRatherThanCanonicalStringEquality() throws {
        let original = "postgres://app:caf\u{E9}@db.example.test/main"
        let decoded = "postgres://app:cafe\u{301}@db.example.test/main"
        #expect(original == decoded)
        #expect(Array(original.utf16) != Array(decoded.utf16))
        let context = RequestContext(budget: .standard)
        #expect(try !RecognizableSecretPolicy.requiresDecodedConcealment(in: original, originalText: original, context: context))
        #expect(try RecognizableSecretPolicy.requiresDecodedConcealment(in: decoded, originalText: original, context: context))
    }

    @Test func decodedURLAllowanceIsCountedAndFallsBackOnStorageOverflow() throws {
        let url = "postgres://app:synthetic-counted-url@db.example.test/main"
        let one = RequestContext(budget: PreviewBudget(maxJSONNodes: 1))
        #expect(try !RecognizableSecretPolicy.requiresDecodedConcealment(in: url, originalText: url, context: one))
        #expect(try RecognizableSecretPolicy.requiresDecodedConcealment(in: url + " " + url, originalText: url, context: one))
        #expect(try RecognizableSecretPolicy.requiresDecodedConcealment(in: url, originalText: url + " " + url, context: one))
        let zero = RequestContext(budget: PreviewBudget(maxJSONNodes: 0))
        #expect(try RecognizableSecretPolicy.requiresDecodedConcealment(in: url, originalText: url, context: zero))
        #expect(try !RecognizableSecretPolicy.requiresDecodedConcealment(in: "ordinary", originalText: "ordinary", context: zero))
    }

    @Test func existingFindingKindCannotExemptADifferentGrammar() throws {
        let url = "postgres://app:synthetic-kind-url@db.example.test/main"
        let provider = "sk_test_" + String(repeating: "Aa1Bb2", count: 5)
        let context = RequestContext(budget: .standard)
        #expect(try RecognizableSecretPolicy.requiresDecodedConcealment(in: url + " " + provider, originalText: url + " " + provider, context: context))
    }

    @Test func decodedURLAllowanceRetainsDeadlineAndCancellationChecks() async {
        #expect(throws: PreviewFailure.deadlineExceeded) {
            try RecognizableSecretPolicy.requiresDecodedConcealment(in: "ordinary", originalText: "ordinary", context: RequestContext(budget: PreviewBudget(maxMilliseconds: 0)))
        }
        let cancelled = await Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try RecognizableSecretPolicy.requiresDecodedConcealment(in: "ordinary", originalText: "ordinary", context: RequestContext(budget: .standard))
                return false
            } catch is CancellationError { return true }
            catch { return false }
        }.value
        #expect(cancelled)
    }
}
