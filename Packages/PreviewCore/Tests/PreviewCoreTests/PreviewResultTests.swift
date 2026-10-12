import Foundation
import Synchronization
import Testing
import PreviewContracts
import PreviewCore

private final class ResultReadProbe: PreviewFileReading, Sendable {
    let budgets = Mutex<[PreviewBudget]>([])
    let data: Data
    init(_ text: String = "ordinary content") { data = Data(text.utf8) }
    func read(url: URL, context: RequestContext) throws -> FileBytes {
        budgets.withLock { $0.append(context.budget) }
        return FileBytes(data: data)
    }
    var recorded: [PreviewBudget] { budgets.withLock { $0 } }
}

private struct ResultTextAdapter: BinaryFormatAdapter {
    func parse(_ input: FileBytes, context: RequestContext) throws -> ParsedTextDocument {
        ParsedTextDocument(text: String(decoding: input.data, as: UTF8.self))
    }
}

@Suite("Effective preview result budgets")
struct PreviewResultTests {
    private let url = URL(fileURLWithPath: "/unused/result.txt")
    private let family = PreviewBudget(maxInputBytes: 512, maxOutputUTF8Bytes: 1_024, maxMilliseconds: 4_000)

    private func pipeline(_ reader: ResultReadProbe, budget: PreviewBudget?) -> PreviewPipeline {
        PreviewPipeline(registrations: [.init(formatID: .plainText, defaultBudget: budget,
                                              binaryAdapter: { ResultTextAdapter() })], reader: reader)
    }

    @Test func resultCarriesTheActualFamilyBudget() async throws {
        let reader = ResultReadProbe()
        let result = await pipeline(reader, budget: family).previewResult(url: url)
        guard case .ready(let text) = result.outcome else { Issue.record("Expected ready content"); return }
        #expect(text.text == "ordinary content")
        #expect(result.effectiveBudget == family)
        #expect(reader.recorded == [family])
    }

    @Test func explicitBudgetOverridesTheFamilyAndSurvivesFailure() async {
        let reader = ResultReadProbe()
        let requested = PreviewBudget(maxInputBytes: 8)
        let result = await pipeline(reader, budget: family).previewResult(url: url, budget: requested)
        #expect(result.outcome == .unavailable(.inputTooLarge))
        #expect(result.effectiveBudget == requested)
        #expect(reader.recorded == [requested])
    }

    @Test func standardIsReportedOnlyWhenItWasSelected() async {
        let reader = ResultReadProbe()
        let result = await pipeline(reader, budget: nil).previewResult(url: url)
        #expect(result.effectiveBudget == .standard)
        #expect(reader.recorded == [.standard])
    }

    @Test func disabledTypesDoNotReadOrInventAnEffectiveBudget() async {
        let reader = ResultReadProbe()
        var preferences = PreviewPreferencesSnapshot.defaults
        preferences.setEnabled(false, for: .plainText)
        let result = await pipeline(reader, budget: family).previewResult(url: url, preferences: preferences)
        #expect(result.outcome == .disabledByUser(.plainText))
        #expect(result.effectiveBudget == nil)
        #expect(reader.recorded.isEmpty)
    }

    @Test func invalidBudgetsFailBeforeReadingAndAreNotDisplayedAsLimits() async {
        let reader = ResultReadProbe()
        let service = pipeline(reader, budget: family)
        let result = await service.previewResult(url: url, budget: PreviewBudget(maxInputBytes: -1))
        #expect(result.outcome == .unavailable(.invalidBudget))
        #expect(result.effectiveBudget == nil)
        #expect(reader.recorded.isEmpty)
        let invalidFamily = await pipeline(reader, budget: PreviewBudget(maxMilliseconds: 0)).previewResult(url: url)
        #expect(invalidFamily.outcome == .unavailable(.invalidBudget))
        #expect(invalidFamily.effectiveBudget == nil)
        #expect(reader.recorded.isEmpty)
    }

    @Test func unsupportedRegistrationsHaveNoEffectiveBudget() async {
        let reader = ResultReadProbe()
        let result = await PreviewPipeline(registrations: [], reader: reader).previewResult(url: url)
        #expect(result.outcome == .unavailable(.unsupportedFormat))
        #expect(result.effectiveBudget == nil)
        #expect(reader.recorded.isEmpty)
    }

    @Test func oldOutcomeEntryPointPreservesTheSamePolicyAndContent() async {
        let reader = ResultReadProbe()
        let service = pipeline(reader, budget: family)
        let result = await service.previewResult(url: url)
        #expect(await service.preview(url: url) == result.outcome)
        #expect(reader.recorded == [family, family])
    }
}
