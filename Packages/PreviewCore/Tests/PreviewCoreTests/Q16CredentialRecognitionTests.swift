import Foundation
import Testing
import PreviewContracts
import PreviewCore

@Suite("Q16 credential recognition corpus")
struct Q16CredentialRecognitionTests {
    private func conceal(_ line: String, structured: Bool = false,
                         budget: PreviewBudget = .standard) throws -> SafeText {
        try DefaultPrivacyFilter().filter(ParsedTextDocument(text: line, usesStructuredPrivacy: structured),
                                          context: RequestContext(budget: budget))
    }

    @Test(arguments: Q16CredentialCorpus.positives)
    func everySyntheticPositiveIsConcealed(sample: Q16CredentialCorpus.Positive) throws {
        let safe = try conceal(sample.line, structured: sample.structured)
        let leaked = safe.text.contains(sample.credential)
        #expect(!leaked, "Credential family \(sample.testDescription)")
        #expect(safe.redactionCount > 0, "Credential family \(sample.testDescription)")
        #expect(safe.findings.allSatisfy { $0.kind == .secretSensitiveField },
                "Newly recognized families reuse the existing sensitive-field kind")
        #expect(safe.findings.reduce(0) { $0 + $1.count } == safe.redactionCount)
    }

    @Test(arguments: Q16CredentialCorpus.ordinary)
    func everyOrdinaryLineStaysReadable(sample: Q16CredentialCorpus.Ordinary) throws {
        let safe = try conceal(sample.line)
        let unchanged = safe.text == sample.line
        #expect(unchanged, "Ordinary line \(sample.index)")
        #expect(safe.redactionCount == 0, "Ordinary line \(sample.index)")
    }

    @Test func corpusSizeAndRecallAreMeasuredForEveryFamily() throws {
        let positives = Q16CredentialCorpus.positives
        let ordinary = Q16CredentialCorpus.ordinary
        let families = Dictionary(grouping: positives, by: \.family)
        #expect(positives.count > 150)
        #expect(families.count >= 40)
        #expect(ordinary.count >= 100)
        #expect(positives.allSatisfy { !$0.line.contains("\n") && !$0.line.contains("\r") })
        #expect(ordinary.allSatisfy { !$0.line.contains("\n") && !$0.line.contains("\r") })
        var concealed = 0
        for family in families.keys.sorted() {
            let samples = try #require(families[family])
            var familyConcealed = 0
            for sample in samples {
                let safe = try conceal(sample.line, structured: sample.structured)
                if !safe.text.contains(sample.credential), safe.redactionCount > 0 { familyConcealed += 1 }
            }
            concealed += familyConcealed
            let recall = Double(familyConcealed) / Double(samples.count)
            #expect(recall >= 0.95, "Family \(family): \(familyConcealed)/\(samples.count) concealed")
        }
        let recall = Double(concealed) / Double(positives.count)
        #expect(recall >= 0.95, "Positive corpus: \(concealed)/\(positives.count) concealed")
        var falsePositiveLines = 0
        for sample in ordinary {
            let safe = try conceal(sample.line)
            if safe.text != sample.line || safe.redactionCount > 0 { falsePositiveLines += 1 }
        }
        let falsePositiveRate = Double(falsePositiveLines) / Double(ordinary.count)
        #expect(falsePositiveRate <= 0.02,
                "Ordinary corpus: \(falsePositiveLines)/\(ordinary.count) falsely concealed")
    }

    @Test func independentSlowOracleMatchesEveryCorpusCaseInExactCodeUnits() throws {
        for sample in Q16CredentialCorpus.positives {
            let document = ParsedTextDocument(text: sample.line, usesStructuredPrivacy: sample.structured)
            let actual = try conceal(sample.line, structured: sample.structured)
            let expected = try ReferencePrivacyFilter().filter(document, context: RequestContext(budget: .standard))
            let exact = actual.text.utf16.elementsEqual(expected.text.utf16)
            #expect(exact, "Oracle family \(sample.testDescription)")
            #expect(actual.redactionCount == expected.redactionCount, "Oracle family \(sample.testDescription)")
        }
        for sample in Q16CredentialCorpus.ordinary {
            let actual = try conceal(sample.line)
            let expected = try ReferencePrivacyFilter().filter(ParsedTextDocument(text: sample.line),
                                                               context: RequestContext(budget: .standard))
            let exact = actual.text.utf16.elementsEqual(expected.text.utf16)
            #expect(exact && actual.redactionCount == expected.redactionCount, "Oracle ordinary line \(sample.index)")
        }
    }

    @Test(arguments: [
        "ssh_public_key", "publicKey", "primary_key", "foreignKey", "sort_key", "partitionKey",
        "hot_key", "key_path", "keyId", "monkey", "compass", "bypass", "passwordless_mode",
        "tokenizer", "tokenization", "secretariat", "authorship", "cookiecutter", "sessional", "passwdic"
    ])
    func ordinaryKeyVocabularyIsNotASensitiveSubstring(name: String) {
        #expect(!SecretFieldPolicy.isSensitive(name))
    }

    @Test(arguments: ["api\u{200B}Key", "access\u{FE0F}Key", "private\u{034F}.key", "auth\u{2060}"])
    func invisibleScalarsDoNotHideCredentialFieldNames(name: String) {
        #expect(SecretFieldPolicy.isSensitive(name))
    }

    @Test func explicitAuthorizationFieldsDoNotDependOnTokenShape() throws {
        for prefix in ["Authorization: ", "authorization = ", "auth: "] {
            let safe = try conceal(prefix + "synthetic-short-value")
            let leaked = safe.text.contains("synthetic-short-value")
            #expect(!leaked)
            #expect(safe.redactionCount > 0)
        }
    }

    @Test func validBasicAndBearerShapesRemainConcealedInFreeText() throws {
        for credential in ["Basic dGVzdDp0ZXN0MTIz", "Bearer abcdefgh12345678", "Bearer abcdefghijklmnop"] {
            let safe = try conceal("send " + credential, structured: true)
            let leaked = safe.text.contains(credential)
            #expect(!leaked)
            #expect(safe.findings.contains { $0.kind == .secretAuthorizationHeader })
        }
    }

    @Test func encodedPublicMaterialIsNotMistakenForAPrivateHeader() throws {
        for header in ["PUBLIC KEY", "CERTIFICATE"] {
            let encoded = Data("-----BEGIN \(header)-----\nsynthetic-public-material\n-----END \(header)-----".utf8).base64EncodedString()
            let safe = try conceal("payload " + encoded, structured: true)
            let unchanged = safe.text == "payload " + encoded
            #expect(unchanged)
            #expect(safe.redactionCount == 0)
        }
    }

    @Test func pathologicalFieldNamesHaveABoundedConservativeClassification() throws {
        for name in [String(repeating: "a", count: 513), String(repeating: "a_", count: 65)] {
            #expect(SecretFieldPolicy.isSensitive(name))
            let safe = try conceal(name + "=synthetic-q16-overflow-value")
            let leaked = safe.text.contains("synthetic-q16-overflow-value")
            #expect(!leaked)
        }
        // Invisible scalars count toward examined work even though they create no visible tokens.
        #expect(!SecretFieldPolicy.isSensitive(String(repeating: "\u{200B}", count: 1_024)))
        #expect(SecretFieldPolicy.isSensitive(String(repeating: "\u{200B}", count: 1_025)))
        #expect(SecretFieldPolicy.isSensitive(String(repeating: "\u{200B}", count: 65_536)))
    }

    @Test(arguments: [
        ("pgp", "-----BEGIN PGP PRIVATE KEY BLOCK-----\nsynthetic-q16-private-body\n-----END PGP PRIVATE KEY BLOCK-----"),
        ("putty", "PuTTY-User-Key-File-3: ssh-ed25519\nEncryption: none\nComment: synthetic\nPublic-Lines: 1\npublic-fixture\nPrivate-Lines: 1\nsynthetic-q16-private-body\nPrivate-MAC: synthetic-mac")
    ])
    func privateBlocksConcealBodiesAndResumeAtTheEnd(label: String, block: String) throws {
        let safe = try conceal("before\n" + block + "\nafter", structured: true)
        let leaked = safe.text.contains("synthetic-q16-private-body")
        #expect(!leaked, "Block family \(label)")
        #expect(safe.text.hasPrefix("before\n") && safe.text.hasSuffix("\nafter"))
        #expect(safe.findings.contains { $0.kind == .secretSensitiveField })
        #expect(safe.findings.flatMap(\.lines) == [2])
    }

    @Test func newValueMatchersRetainBoundedFallbackAndOutputChecks() throws {
        let sample = "note sk_test_" + String(repeating: "a1", count: 16)
        let safe = try conceal(sample + "\n" + sample, structured: true, budget: PreviewBudget(maxJSONNodes: 1))
        #expect(safe.text == SecretFieldPolicy.concealmentToken)
        #expect(safe.redactionCount == 1)
        #expect(throws: PreviewFailure.outputTooLarge) {
            try conceal(sample, structured: true, budget: PreviewBudget(maxOutputUTF8Bytes: 8))
        }
        #expect(throws: PreviewFailure.deadlineExceeded) {
            try conceal(sample, budget: PreviewBudget(maxMilliseconds: 0))
        }
    }

    @Test func cancellationIsObservedBeforeCredentialMatching() async {
        let outcome = await Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try DefaultPrivacyFilter().filter(ParsedTextDocument(text: "note sk_test_" + String(repeating: "a1", count: 16)),
                                                      context: RequestContext(budget: .standard))
                return false
            } catch is CancellationError { return true }
            catch { return false }
        }.value
        #expect(outcome)
    }
}
