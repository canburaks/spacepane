import Foundation
import Testing
@testable import PreviewRenderers

@Suite("Q53 value-free information copy", .serialized)
@MainActor
struct Q53InfoPanelCopyTests {
    private let english = Locale(identifier: "en_US")

    @Test func configuredProviderAndCountPrecedeCompleteCurrentCommandRows() {
        let lines = PreviewInfoPanelCopy.lines(providerName: "Acme Preview", concealedCount: 2,
            commands: [.find, .goToLine], locale: english, languagePreferences: ["en"])
        #expect(Array(lines.prefix(5)) == ["Read-only preview", "Processed on this Mac", "Preview by Acme Preview",
            "2 likely secrets concealed.", "Commands in this view"])
        #expect(lines.count == 7)
        #expect(lines.dropFirst(5).first == PreviewStrings.format(.previewInfoCommand, arguments: [PreviewCommand.find.localizedTitle(
            locale: english, languagePreferences: ["en"]), "⌘F"], locale: english, languagePreferences: ["en"]))
        #expect(lines.dropFirst(6).first?.hasSuffix("⌘L") == true)
    }

    @Test func missingProviderAndNoCommandsProduceNoEmptyCaptionOrCommandsHeading() {
        for provider in [nil, ""] as [String?] {
            #expect(PreviewInfoPanelCopy.lines(providerName: provider, concealedCount: 0, commands: [],
                locale: english, languagePreferences: ["en"]) == ["Read-only preview", "Processed on this Mac",
                    "0 likely secrets concealed."])
        }
    }

    @Test func malformedNegativeConcealmentCountIsUnknownInsteadOfInventedZero() {
        #expect(PreviewInfoPanelCopy.lines(providerName: nil, concealedCount: -1, commands: [],
            locale: english, languagePreferences: ["en"]) == ["Read-only preview", "Processed on this Mac"])
    }
}
