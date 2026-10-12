import Foundation
import Testing
import PreviewContracts

@Suite("Shared credential value policy")
struct RecognizableSecretPolicyTests {
    @Test(arguments: Q16CredentialCorpus.positives.filter(\.structured))
    func decodedValueFamiliesUseTheSamePolicy(sample: Q16CredentialCorpus.Positive) throws {
        let context = RequestContext(budget: .standard)
        #expect(try RecognizableSecretPolicy.containsCredential(in: sample.line, context: context))
        let result = try RecognizableSecretPolicy.recognizedRanges(in: sample.line, context: context, maximumMatches: 20)
        guard case .matches(let matches) = result else { Issue.record("Unexpected match overflow"); return }
        #expect(!matches.isEmpty)
        #expect(matches.allSatisfy { !$0.utf16Range.isEmpty && $0.utf16Range.lowerBound >= 0 && $0.utf16Range.upperBound <= sample.line.utf16.count })
        #expect(matches.allSatisfy { $0.kind == .secretSensitiveField })
    }

    @Test(arguments: Q16CredentialCorpus.ordinary)
    func ordinaryValuesDoNotMatch(sample: Q16CredentialCorpus.Ordinary) throws {
        #expect(try !RecognizableSecretPolicy.containsCredential(in: sample.line, context: RequestContext(budget: .standard)))
    }

    @Test func fieldClassificationIsSeparateFromValueRecognition() throws {
        #expect(SecretFieldPolicy.isSensitive("password"))
        #expect(try !RecognizableSecretPolicy.containsCredential(in: "password=synthetic-field-value", context: RequestContext(budget: .standard)))
    }

    @Test func rangesReferToExactUTF16CodeUnitsAndExistingKinds() throws {
        let token = "sk_test_" + String(repeating: "a1", count: 16)
        let leading = "😀 e\u{301} 日本語 "
        let source = leading + token + " tail"
        let result = try RecognizableSecretPolicy.recognizedRanges(in: source, context: RequestContext(budget: .standard), maximumMatches: 1)
        guard case .matches(let matches) = result else { Issue.record("Expected one credential"); return }
        #expect(matches.count == 1)
        #expect(matches.first?.utf16Range == leading.utf16.count..<(leading.utf16.count + token.utf16.count))
        #expect(matches.first?.kind == .secretSensitiveField)
    }

    @Test func overflowIsExplicitAndNeverReturnsAnIncompleteRangeList() throws {
        let text = "AKIAABCDEFGHIJKLMNOP ASIAABCDEFGHIJKLMNOP"
        #expect(try RecognizableSecretPolicy.recognizedRanges(in: text, context: RequestContext(budget: .standard), maximumMatches: 1) == .matchLimitExceeded)
        #expect(try RecognizableSecretPolicy.recognizedRanges(in: text, context: RequestContext(budget: .standard), maximumMatches: 0) == .matchLimitExceeded)
        #expect(try RecognizableSecretPolicy.recognizedRanges(in: "ordinary", context: RequestContext(budget: .standard), maximumMatches: 0) == .matches([]))
        #expect(throws: PreviewFailure.tooManyNodes) {
            try RecognizableSecretPolicy.recognizedRanges(in: text, context: RequestContext(budget: PreviewBudget(maxJSONNodes: 1)), maximumMatches: 2)
        }
    }

    @Test func booleanRecognitionStopsWithoutCollectingAllMatches() throws {
        let text = String(repeating: "AKIAABCDEFGHIJKLMNOP ", count: 2_000)
        #expect(try RecognizableSecretPolicy.containsCredential(in: text, context: RequestContext(budget: PreviewBudget(maxJSONNodes: 1))))
    }

    @Test func cancelledAndExpiredRequestsAreRejected() async {
        #expect(throws: PreviewFailure.deadlineExceeded) {
            try RecognizableSecretPolicy.containsCredential(in: "ordinary", context: RequestContext(budget: PreviewBudget(maxMilliseconds: 0)))
        }
        let cancelled = await Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try RecognizableSecretPolicy.containsCredential(in: "ordinary", context: RequestContext(budget: .standard))
                return false
            } catch is CancellationError { return true }
            catch { return false }
        }.value
        #expect(cancelled)
    }

    @Test func cachedPatternsAreSafeAcrossIndependentConcurrentRequests() async throws {
        let results = try await withThrowingTaskGroup(of: Bool.self) { group in
            for index in 0..<32 {
                group.addTask {
                    let text = index.isMultiple(of: 2) ? "payload sk_test_" + String(repeating: "a1", count: 16) : "basic programming"
                    return try RecognizableSecretPolicy.containsCredential(in: text, context: RequestContext(budget: .standard)) == index.isMultiple(of: 2)
                }
            }
            var results: [Bool] = []
            for try await result in group { results.append(result) }
            return results
        }
        #expect(results.count == 32 && results.allSatisfy { $0 })
    }
}
